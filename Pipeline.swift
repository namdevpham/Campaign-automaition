import AppKit
import Foundation

struct IntegrationState: Codable {
    var recordID: UUID
    var stt: Int
    var updatedAt: Date
    var parsed: Bool
    var geminiGenerated: Bool
    var qaPassed: Bool
    var selectedSourcePositions: [Int]
    var contentCreated: Bool
    var groupID: String?
    var contentID: String?
    var contentLinkURL: String?
    var uploadedMediaID: String?
    var uploadedImageURL: String?
    var creativePayloadPrepared: Bool
    var creativeCreated: Bool
    var creativeID: String?
    var creativeBlocker: String?

    // V1.3 Campaign fields are optional so old integration_state.json files
    // continue decoding without migration failures.
    var campaignID: String?
    var adSetID: String?
    var adID: String?
    var campaignTemplateName: String?

    var campaignPageInternalID: Int?
    var campaignPageExternalID: String?
    var campaignPageName: String?

    var lastError: String?

    static func blank(for record: CampaignRecord) -> IntegrationState {
        IntegrationState(
            recordID: record.id,
            stt: record.stt ?? 0,
            updatedAt: Date(),
            parsed: false,
            geminiGenerated: false,
            qaPassed: false,
            selectedSourcePositions: [],
            contentCreated: false,
            groupID: nil,
            contentID: nil,
            contentLinkURL: nil,
            uploadedMediaID: nil,
            uploadedImageURL: nil,
            creativePayloadPrepared: false,
            creativeCreated: false,
            creativeID: nil,
            creativeBlocker: nil,
            campaignID: nil,
            adSetID: nil,
            adID: nil,
            campaignTemplateName: nil,
            campaignPageInternalID: nil,
            campaignPageExternalID: nil,
            campaignPageName: nil,
            lastError: nil
        )
    }
}

final class IntegrationStateStore {
    func url(folder: URL) -> URL {
        folder.appendingPathComponent("integration_state.json")
    }

    func load(folder: URL, record: CampaignRecord) -> IntegrationState {
        let stateURL = url(folder: folder)
        guard let data = try? Data(contentsOf: stateURL) else {
            return .blank(for: record)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(IntegrationState.self, from: data)) ?? .blank(for: record)
    }

    func save(_ state: IntegrationState, folder: URL) throws {
        var copy = state
        copy.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(copy).write(to: url(folder: folder), options: .atomic)
    }
}

enum PipelineError: Error, LocalizedError {
    case masterRulesMissing
    case badGeminiJSON(String)
    case missingGeneratedJSON
    case qaFailed(Int)
    case missingContentPayload
    case imageNeedsPublicURL

    var errorDescription: String? {
        switch self {
        case .masterRulesMissing:
            return "Không tìm thấy NAM_QUIZ_MASTER_RULES.md trong app."
        case .badGeminiJSON(let reason):
            return "Gemini JSON không hợp lệ: \(reason)"
        case .missingGeneratedJSON:
            return "Chưa có generated_content.json."
        case .qaFailed(let count):
            return "QA FAIL với \(count) issue(s)."
        case .missingContentPayload:
            return "Chưa có ethopex_content_payload.json. Hãy chạy TEST PIPELINE trước."
        case .imageNeedsPublicURL:
            return "Image trong Data Manager là file local; Creative API cần URL public http/https."
        }
    }
}

struct SourceFidelityRepairResult {
    let jsonText: String
    let selectedSourcePositions: [Int]
    let correctedFields: [String: Int]
    let details: [String]

    var totalCorrections: Int {
        correctedFields.values.reduce(0, +)
    }

    var reportText: String {
        var lines: [String] = []
        lines.append("SOURCE FIDELITY LOCK REPORT")
        lines.append("Selected source positions: " + selectedSourcePositions.map(String.init).joined(separator: ", "))
        lines.append("Total corrections: \(totalCorrections)")
        lines.append("")
        lines.append("Corrections:")
        for key in ["questionText", "options", "correctAnswer", "imageURL", "explanation"] {
            lines.append("- \(key): \(correctedFields[key] ?? 0)")
        }
        if !details.isEmpty {
            lines.append("")
            lines.append("Details:")
            details.forEach { lines.append("- \($0)") }
        }
        return lines.joined(separator: "\n")
    }
}

enum SourceFidelityLockError: Error, LocalizedError {
    case invalidGeneratedJSON
    case invalidPages
    case cardCount(Int)
    case cannotMatchQuestion(Int, String)
    case sourceOrder(Int, Int)
    case missingCorrectAnswer(Int)
    case cannotPatchField(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidGeneratedJSON:
            return "Source Fidelity Lock: generated JSON không hợp lệ."
        case .invalidPages:
            return "Source Fidelity Lock: cấu trúc main_content/sub_pages không hợp lệ."
        case .cardCount(let count):
            return "Source Fidelity Lock: tìm thấy \(count) question cards, cần đúng 20."
        case .cannotMatchQuestion(let display, let text):
            return "Source Fidelity Lock: không xác định được source question cho Question \(display): \(text)"
        case .sourceOrder(let previous, let current):
            return "Source Fidelity Lock: source order bị đảo (\(previous) → \(current))."
        case .missingCorrectAnswer(let display):
            return "Source Fidelity Lock: source Question \(display) không xác định được correctAnswer/index."
        case .cannotPatchField(let display, let field):
            return "Source Fidelity Lock: không sửa được \(field) của Question \(display)."
        }
    }
}

final class PipelineFileBuilder {
    let stateStore = IntegrationStateStore()

    func masterRules() throws -> String {
        guard let url = Bundle.main.url(forResource: "NAM_QUIZ_MASTER_RULES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw PipelineError.masterRulesMissing
        }
        return text
    }

    func extractedSourceJSON(_ parsed: ParsedQuiz) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return String(data: try encoder.encode(parsed), encoding: .utf8) ?? "{}"
    }

    func canonicalizeGeminiJSON(_ raw: String) throws -> String {
        let cleaned = stripMarkdownFence(raw)
        guard let data = cleaned.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineError.badGeminiJSON("Không parse được root object.")
        }

        let required = [
            "locale", "title", "name", "description",
            "main_content", "confirm", "sub_pages"
        ]
        for key in required where root[key] == nil {
            throw PipelineError.badGeminiJSON("Thiếu key \(key).")
        }

        guard let rootTitle = root["title"] as? String,
              !rootTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipelineError.badGeminiJSON("Root title bị trống hoặc không phải string.")
        }

        let locale = root["locale"] as? String ?? ""
        let rawTechnicalName = root["name"] as? String ?? ""

        // V1.6.6.2:
        // Technical landing name is deterministic by target language.
        // Greek_God_Testw1 → Greek_God_EN / Greek_God_RU / ...
        root["name"] = TechnicalNameRule.normalize(
            rawName: rawTechnicalName,
            locale: locale,
            fallbackTitle: rootTitle
        )

        guard let confirm = root["confirm"] as? [String: Any] else {
            throw PipelineError.badGeminiJSON("confirm không phải object.")
        }
        guard let subPages = root["sub_pages"] as? [[String: Any]] else {
            throw PipelineError.badGeminiJSON("sub_pages không phải array object.")
        }

        let rootPairs = [
            ("locale", root["locale"]!),
            ("title", root["title"]!),
            ("name", root["name"]!),
            ("description", root["description"]!),
            ("main_content", root["main_content"]!)
        ]

        var lines: [String] = ["{"]
        for (index, pair) in rootPairs.enumerated() {
            let comma = (index < rootPairs.count - 1 || true) ? "," : ""
            lines.append("  \(jsonString(pair.0)): \(try jsonFragment(pair.1))\(comma)")
        }

        lines.append("  \"confirm\": {")
        lines.append("    \"title\": \(try jsonFragment(confirm["title"] ?? "")),")
        lines.append("    \"question\": \(try jsonFragment(confirm["question"] ?? "")),")
        lines.append("    \"button_text\": \(try jsonFragment(confirm["button_text"] ?? ""))")
        lines.append("  },")

        lines.append("  \"sub_pages\": [")
        for (index, page) in subPages.enumerated() {
            lines.append("    {")
            // V0.11: every path 1-5 MUST repeat the exact root title.
            lines.append("      \"title\": \(try jsonFragment(rootTitle)),")
            lines.append("      \"path\": \(try jsonFragment(page["path"] ?? "")),")
            lines.append("      \"content\": \(try jsonFragment(page["content"] ?? ""))")
            lines.append(index == subPages.count - 1 ? "    }" : "    },")
        }
        lines.append("  ]")
        lines.append("}")

        let result = lines.joined(separator: "\n")

        guard let finalData = result.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: finalData)) != nil else {
            throw PipelineError.badGeminiJSON("Canonical JSON sau khi chuẩn hóa không parse được.")
        }

        return result
    }

func enforceSourceFidelity(
        jsonText: String,
        source: ParsedQuiz
    ) throws -> SourceFidelityRepairResult {
        guard let data = jsonText.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mainContent = root["main_content"] as? String,
              var subPages = root["sub_pages"] as? [[String: Any]],
              subPages.count >= 5 else {
            throw SourceFidelityLockError.invalidGeneratedJSON
        }

        var used = Set<Int>()
        var lastSourcePosition = 0
        var selectedPositions: [Int] = []
        var displayIndex = 0
        var corrections: [String: Int] = [
            "questionText": 0,
            "options": 0,
            "correctAnswer": 0,
            "imageURL": 0,
            "explanation": 0
        ]
        var details: [String] = []

        root["main_content"] = try rewriteQuestionPage(
            mainContent,
            source: source,
            used: &used,
            lastSourcePosition: &lastSourcePosition,
            selectedPositions: &selectedPositions,
            displayIndex: &displayIndex,
            corrections: &corrections,
            details: &details
        )

        for index in 0..<4 {
            guard let html = subPages[index]["content"] as? String else {
                throw SourceFidelityLockError.invalidPages
            }
            subPages[index]["content"] = try rewriteQuestionPage(
                html,
                source: source,
                used: &used,
                lastSourcePosition: &lastSourcePosition,
                selectedPositions: &selectedPositions,
                displayIndex: &displayIndex,
                corrections: &corrections,
                details: &details
            )
        }

        guard displayIndex == 20 else {
            throw SourceFidelityLockError.cardCount(displayIndex)
        }

        root["sub_pages"] = subPages

        let repairedData = try JSONSerialization.data(
            withJSONObject: root,
            options: [.withoutEscapingSlashes]
        )
        guard let repairedRaw = String(data: repairedData, encoding: .utf8) else {
            throw SourceFidelityLockError.invalidGeneratedJSON
        }

        // Re-canonicalize so root/sub-page key order and Title consistency remain locked.
        let finalJSON = try canonicalizeGeminiJSON(repairedRaw)

        return SourceFidelityRepairResult(
            jsonText: finalJSON,
            selectedSourcePositions: selectedPositions,
            correctedFields: corrections,
            details: details
        )
    }

    func saveSourceFidelityReport(
        _ result: SourceFidelityRepairResult,
        folder: URL
    ) throws -> URL {
        let url = folder.appendingPathComponent("source_fidelity_report.txt")
        try result.reportText.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        return url
    }

    private func rewriteQuestionPage(
        _ html: String,
        source: ParsedQuiz,
        used: inout Set<Int>,
        lastSourcePosition: inout Int,
        selectedPositions: inout [Int],
        displayIndex: inout Int,
        corrections: inout [String: Int],
        details: inout [String]
    ) throws -> String {
        let cardPattern = #"(?s)<div class="qc">[\s\S]*?<details class="hintbox">[\s\S]*?</details>\s*</div>"#
        guard let regex = try? NSRegularExpression(pattern: cardPattern, options: []) else {
            return html
        }

        let ns = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: ns.length)
        )

        if matches.isEmpty {
            return html
        }

        var output = ""
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                output += ns.substring(
                    with: NSRange(
                        location: cursor,
                        length: match.range.location - cursor
                    )
                )
            }

            displayIndex += 1
            let originalCard = ns.substring(with: match.range)

            let rewritten = try rewriteQuestionCard(
                originalCard,
                displayIndex: displayIndex,
                source: source,
                used: &used,
                lastSourcePosition: &lastSourcePosition,
                selectedPositions: &selectedPositions,
                corrections: &corrections,
                details: &details
            )

            output += rewritten
            cursor = NSMaxRange(match.range)
        }

        if cursor < ns.length {
            output += ns.substring(
                with: NSRange(location: cursor, length: ns.length - cursor)
            )
        }

        return output
    }

    private func rewriteQuestionCard(
        _ card: String,
        displayIndex: Int,
        source: ParsedQuiz,
        used: inout Set<Int>,
        lastSourcePosition: inout Int,
        selectedPositions: inout [Int],
        corrections: inout [String: Int],
        details: inout [String]
    ) throws -> String {
        guard let rawQuestion = firstCapture(
            pattern: #"<div class="qtext">([\s\S]*?)</div>"#,
            in: card
        ) else {
            throw SourceFidelityLockError.cannotMatchQuestion(
                displayIndex,
                "qtext missing"
            )
        }

        let generatedQuestion = htmlDecode(rawQuestion)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let generatedOptions = allCaptures(
            pattern: #"<label class="opt(?: correct)?"><input type="radio" name="q\d+" class="(?:ac|aw)"> ([\s\S]*?)</label>"#,
            in: card
        ).map {
            htmlDecode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sourceQuestion = try matchSourceQuestion(
            generatedQuestion: generatedQuestion,
            generatedOptions: generatedOptions,
            source: source,
            used: used,
            displayIndex: displayIndex
        )

        if sourceQuestion.sourcePosition <= lastSourcePosition {
            throw SourceFidelityLockError.sourceOrder(
                lastSourcePosition,
                sourceQuestion.sourcePosition
            )
        }

        lastSourcePosition = sourceQuestion.sourcePosition
        used.insert(sourceQuestion.sourcePosition)
        selectedPositions.append(sourceQuestion.sourcePosition)

        var rewritten = card
        var fixedFields: [String] = []

        // 1) Question text — exact Source View.
        if generatedQuestion != sourceQuestion.question {
            corrections["questionText", default: 0] += 1
            fixedFields.append("questionText")
        }
        rewritten = replacingFirst(
            pattern: #"<div class="qtext">[\s\S]*?</div>"#,
            in: rewritten,
            with: "<div class=\"qtext\">\(htmlEscape(sourceQuestion.question))</div>"
        )

        // 2) Image URL — exact Source View; add/remove image block as needed.
        let generatedImage = firstCapture(
            pattern: #"<img class="qimg" src="([^"]*)" alt="">"#,
            in: rewritten
        ).map(htmlDecode) ?? ""

        let exactImage = sourceQuestion.imageUrl
        if generatedImage != exactImage {
            corrections["imageURL", default: 0] += 1
            fixedFields.append("imageURL")
        }

        let imgBlockPattern = #"<div class="imgbox">[\s\S]*?</div>"#
        if exactImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rewritten = removingFirst(pattern: imgBlockPattern, in: rewritten)
        } else {
            let block = "<div class=\"imgbox\"><img class=\"qimg\" src=\"\(htmlAttributeEscape(exactImage))\" alt=\"\"></div>"
            if firstMatchRange(pattern: imgBlockPattern, in: rewritten) != nil {
                rewritten = replacingFirst(
                    pattern: imgBlockPattern,
                    in: rewritten,
                    with: block
                )
            } else if let optsRange = firstMatchRange(
                pattern: #"<div class="opts">"#,
                in: rewritten
            ) {
                let ns = rewritten as NSString
                rewritten =
                    ns.substring(to: optsRange.location) +
                    block + "\n" +
                    ns.substring(from: optsRange.location)
            } else {
                throw SourceFidelityLockError.cannotPatchField(
                    displayIndex,
                    "imageUrl"
                )
            }
        }

        // 3) Options and correct answer/index — exact Source View.
        if generatedOptions != sourceQuestion.options {
            corrections["options", default: 0] += 1
            fixedFields.append("options")
        }

        guard let correctAnswer = sourceQuestion.correctAnswer,
              let correctIndex = sourceQuestion.options.firstIndex(of: correctAnswer) else {
            throw SourceFidelityLockError.missingCorrectAnswer(displayIndex)
        }

        let generatedCorrect = firstCapture(
            pattern: #"<label class="opt correct"><input type="radio" name="q\d+" class="ac"> ([\s\S]*?)</label>"#,
            in: rewritten
        ).map {
            htmlDecode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""

        if generatedCorrect != correctAnswer {
            corrections["correctAnswer", default: 0] += 1
            fixedFields.append("correctAnswer")
        }

        let inputName = firstCapture(
            pattern: #"name="(q\d+)""#,
            in: rewritten
        ) ?? "q\(displayIndex)"

        let optionLabels = sourceQuestion.options.enumerated().map { index, option in
            let isCorrect = index == correctIndex
            let labelClass = isCorrect ? "opt correct" : "opt"
            let inputClass = isCorrect ? "ac" : "aw"
            return "<label class=\"\(labelClass)\"><input type=\"radio\" name=\"\(inputName)\" class=\"\(inputClass)\"> \(htmlEscape(option))</label>"
        }.joined()

        let optionsBlock = "<div class=\"opts\">\(optionLabels)</div>"
        if firstMatchRange(
            pattern: #"<div class="opts">[\s\S]*?</div>"#,
            in: rewritten
        ) != nil {
            rewritten = replacingFirst(
                pattern: #"<div class="opts">[\s\S]*?</div>"#,
                in: rewritten,
                with: optionsBlock
            )
        } else {
            throw SourceFidelityLockError.cannotPatchField(
                displayIndex,
                "options"
            )
        }

        // 4) Explanation — exact Source View for both Correct/Wrong feedback.
        let sourceExplanation = sourceQuestion.answerParagraph
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let generatedExplanation = firstCapture(
            pattern: #"<div class="feedback correct-feedback">[\s\S]*?<br>[\s\S]*?</strong>\s*([\s\S]*?)</div>"#,
            in: rewritten
        ).map {
            htmlDecode($0).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""

        if generatedExplanation != sourceExplanation {
            corrections["explanation", default: 0] += 1
            fixedFields.append("explanation")
        }

        rewritten = try replacingFeedbackExplanation(
            in: rewritten,
            className: "correct-feedback",
            explanation: sourceExplanation,
            displayIndex: displayIndex
        )
        rewritten = try replacingFeedbackExplanation(
            in: rewritten,
            className: "wrong-feedback",
            explanation: sourceExplanation,
            displayIndex: displayIndex
        )

        if !fixedFields.isEmpty {
            details.append(
                "Question \(displayIndex) ← source #\(sourceQuestion.sourcePosition): fixed " +
                fixedFields.joined(separator: ", ")
            )
        }

        return rewritten
    }

    private func matchSourceQuestion(
        generatedQuestion: String,
        generatedOptions: [String],
        source: ParsedQuiz,
        used: Set<Int>,
        displayIndex: Int
    ) throws -> ParsedQuestion {
        let qKey = normalizedForMatch(generatedQuestion)

        var candidates = source.questions.filter {
            !used.contains($0.sourcePosition) &&
            normalizedForMatch($0.question) == qKey
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        if candidates.count > 1 && !generatedOptions.isEmpty {
            let optionKey = generatedOptions.map(normalizedForMatch)
            let narrowed = candidates.filter {
                $0.options.map(normalizedForMatch) == optionKey
            }
            if narrowed.count == 1 {
                return narrowed[0]
            }
        }

        // Fallback: if Gemini slightly changed qtext but kept all four source
        // options exact, use the unique option fingerprint to identify source.
        if !generatedOptions.isEmpty {
            let optionKey = generatedOptions.map(normalizedForMatch)
            candidates = source.questions.filter {
                !used.contains($0.sourcePosition) &&
                $0.options.map(normalizedForMatch) == optionKey
            }
            if candidates.count == 1 {
                return candidates[0]
            }
        }

        throw SourceFidelityLockError.cannotMatchQuestion(
            displayIndex,
            generatedQuestion
        )
    }

    private func replacingFeedbackExplanation(
        in text: String,
        className: String,
        explanation: String,
        displayIndex: Int
    ) throws -> String {
        let pattern =
            #"(<div class="feedback "# +
            NSRegularExpression.escapedPattern(for: className) +
            #"">[\s\S]*?<br>[\s\S]*?</strong>\s*)([\s\S]*?)(</div>)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw SourceFidelityLockError.cannotPatchField(
                displayIndex,
                className
            )
        }

        let ns = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        ),
        match.numberOfRanges >= 4 else {
            throw SourceFidelityLockError.cannotPatchField(
                displayIndex,
                className
            )
        }

        let prefix = ns.substring(with: match.range(at: 1))
        let suffix = ns.substring(with: match.range(at: 3))
        let replacement = prefix + htmlEscape(explanation) + suffix

        return ns.replacingCharacters(in: match.range, with: replacement)
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        allCaptures(pattern: pattern, in: text).first
    }

    private func allCaptures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let ns = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        )

        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return ns.substring(with: range)
        }
    }

    private func firstMatchRange(pattern: String, in text: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let ns = text as NSString
        return regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        )?.range
    }

    private func replacingFirst(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let ns = text as NSString
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        ) else {
            return text
        }

        return ns.replacingCharacters(in: match.range, with: replacement)
    }

    private func removingFirst(pattern: String, in text: String) -> String {
        replacingFirst(pattern: pattern, in: text, with: "")
    }

    private func htmlDecode(_ text: String) -> String {
        let wrapped = "<html><body>\(text)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }
        return attr.string
    }

    private func normalizedForMatch(_ value: String) -> String {
        var text = htmlDecode(value)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "…", with: "...")

        if let regex = try? NSRegularExpression(pattern: #"\s+"#, options: []) {
            let ns = text as NSString
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: " "
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func htmlAttributeEscape(_ value: String) -> String {
        htmlEscape(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func saveGeneratedJSON(_ jsonText: String, folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("generated_content.json")
        try jsonText.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    func loadGeneratedJSON(folder: URL) throws -> String {
        let url = folder.appendingPathComponent("generated_content.json")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw PipelineError.missingGeneratedJSON
        }
        return text
    }

    func saveQA(_ result: QuizQAResult, folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("qa_report.txt")
        try result.reportText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func buildEthopexContentPayload(jsonText: String, folder: URL) throws -> URL {
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let confirm = root["confirm"] as? [String: Any],
              let subPages = root["sub_pages"] as? [[String: Any]] else {
            throw PipelineError.badGeminiJSON("Không map được JSON sang Content payload.")
        }

        let rootTitle = root["title"] as? String ?? ""

        let pages: [[String: Any]] = subPages.map {
            [
                // V0.11: Ethopex always receives the root title on every path.
                "title": rootTitle,
                "path": $0["path"] as? String ?? "",
                "content": $0["content"] as? String ?? ""
            ]
        }

        let item: [String: Any] = [
            "title": rootTitle,
            "locale": root["locale"] as? String ?? "",
            "name": root["name"] as? String ?? "",
            "sub_title": confirm["title"] as? String ?? "",
            "question": confirm["question"] as? String ?? "",
            "button_text": confirm["button_text"] as? String ?? "",
            "description": root["description"] as? String ?? "",
            "content": root["main_content"] as? String ?? "",
            "pages": pages
        ]

        let payload = [item]
        let payloadData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        let url = folder.appendingPathComponent("ethopex_content_payload.json")
        try payloadData.write(to: url, options: .atomic)
        return url
    }

    func buildCreativePayload(
        record: CampaignRecord,
        contentID: String,
        linkURL: String,
        imageURL: String,
        generatedJSON: String,
        folder: URL
    ) throws -> URL {
        let cleanDisplayLink = linkURL
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanDisplayLink.isEmpty,
              !cleanDisplayLink.contains("://"),
              cleanDisplayLink.contains(".") else {
            throw NSError(
                domain: "EthopexCampaignTool",
                code: 2200,
                userInfo: [NSLocalizedDescriptionKey:
                    "Creative Display link phải là domain thuần, ví dụ search.com. Giá trị hiện tại: \(linkURL)"
                ]
            )
        }

        var contentName = record.name
        if let data = generatedJSON.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rootTitle = root["title"] as? String,
           !rootTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentName = rootTitle
        }

        let creative: [String: Any] = [
            "name": record.name,
            "content_id": Int(contentID) ?? contentID,
            "content_name": contentName,
            "link_url": cleanDisplayLink,
            "creative_type": "single_image",
            "traffic_source": "facebook",
            "status": "active",
            "call_to_action": "LEARN_MORE",
            "image_url": [imageURL],
            "video_url": [],
            "thumbnail_url": [],
            "asset_spec": [
                "primaryTexts": [record.primaryText],
                "headlines": [record.headline],
                "descriptions": [record.descriptionText]
            ]
        ]

        let data = try JSONSerialization.data(
            withJSONObject: creative,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        let url = folder.appendingPathComponent("ethopex_creative_payload.json")
        try data.write(to: url, options: .atomic)
        return url
    }


    func saveCampaignPayload(
        _ data: Data,
        folder: URL
    ) throws -> URL {
        let url = folder.appendingPathComponent("ethopex_campaign_payload.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func creativePayloadData(folder: URL) throws -> Data {
        let url = folder.appendingPathComponent("ethopex_creative_payload.json")
        guard let data = try? Data(contentsOf: url) else {
            throw NSError(
                domain: "EthopexCampaignTool",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Chưa có ethopex_creative_payload.json."]
            )
        }
        return data
    }

    func contentPayloadData(folder: URL, coverPublicURL: String) throws -> Data {
        let url = folder.appendingPathComponent("ethopex_content_payload.json")
        guard let data = try? Data(contentsOf: url),
              var payload = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !payload.isEmpty else {
            throw PipelineError.missingContentPayload
        }

        guard let coverURL = URL(string: coverPublicURL),
              let scheme = coverURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              coverURL.host != nil else {
            throw NSError(
                domain: "EthopexCampaignTool",
                code: 3001,
                userInfo: [NSLocalizedDescriptionKey:
                    "Cover URL không phải public http(s): \(coverPublicURL)"
                ]
            )
        }

        for index in payload.indices {
            // Bulk Content API requires a PUBLIC http(s) URL here.
            payload[index]["sub_thumbnail"] = coverPublicURL
        }

        let finalData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )

        let snapshotURL = folder.appendingPathComponent("ethopex_content_payload_with_cover.json")
        try finalData.write(to: snapshotURL, options: .atomic)

        return finalData
    }

    func saveRawResponse(_ raw: String, name: String, folder: URL) {
        try? raw.write(
            to: folder.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }

    private func stripMarkdownFence(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let lastFence = text.range(of: "```", options: .backwards) {
                text = String(text[..<lastFence.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func jsonString(_ value: String) -> String {
        (try? jsonFragment(value)) ?? "\"\""
    }

    private func jsonFragment(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .withoutEscapingSlashes]
        )
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
