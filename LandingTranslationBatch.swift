import Foundation

struct LandingQuestionTranslationInput: Codable {
    let index: Int
    let question: String
    let options: [String]
    let explanation: String
    let hint: String
}

struct GeminiLandingQuestionTranslation: Codable {
    let index: Int
    let question: String
    let options: [String]
    let explanation: String
    let hint: String
}

struct GeminiLandingQuestionBatchResponse: Codable {
    let translations: [GeminiLandingQuestionTranslation]
}

private struct LandingTranslationBatchCache: Codable {
    let digest: String
    let languageCode: String
    let translations: [GeminiLandingQuestionTranslation]
}

enum LandingBatchRepairError: Error, LocalizedError {
    case invalidGeneratedJSON
    case invalidQuestionStructure(Int)
    case invalidBatchResponse(String)
    case timeout(Int)
    case translationStillSource(Int)
    case noQuestionCards
    case cannotPatchQuestion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidGeneratedJSON:
            return "Không đọc được generated landing JSON để batch-translate."
        case .invalidQuestionStructure(let index):
            return "Question \(index) không có đủ qtext/options/explanation/hint để batch-translate."
        case .invalidBatchResponse(let message):
            return "Gemini batch translation không hợp lệ: \(message)"
        case .timeout(let batch):
            return "Timeout khi dịch Landing batch \(batch)."
        case .translationStillSource(let index):
            return "Landing batch vẫn giữ nguyên source-language text ở Question \(index)."
        case .noQuestionCards:
            return "Không tìm thấy 20 question card để batch-translate."
        case .cannotPatchQuestion(let index):
            return "Không thể merge bản dịch vào Question \(index)."
        }
    }
}

final class LandingBatchTranslationRepairer {
    private let gemini: GeminiAPIClient
    private let batchSize = 5

    init(gemini: GeminiAPIClient) {
        self.gemini = gemini
    }

    func canRepairLanguageIssues(_ issues: [String]) -> Bool {
        guard !issues.isEmpty else {
            return false
        }

        return issues.allSatisfy { issue in
            issue.hasPrefix("LANGUAGE MISMATCH Question ")
        }
    }

    func repair(
        jsonText: String,
        targetLanguage: CampaignLanguage,
        sourceLanguage: String,
        folder: URL,
        onLog: @escaping (String) -> Void
    ) throws -> String {
        guard let data = jsonText.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let main = root["main_content"] as? String,
              var subPages = root["sub_pages"] as? [[String: Any]] else {
            throw LandingBatchRepairError.invalidGeneratedJSON
        }

        var pages = [main]
        pages.append(
            contentsOf: subPages.prefix(4).compactMap {
                $0["content"] as? String
            }
        )

        guard pages.count == 5 else {
            throw LandingBatchRepairError.noQuestionCards
        }

        var cardsByPage: [[String]] = []
        var inputs: [LandingQuestionTranslationInput] = []
        var globalIndex = 0

        for page in pages {
            let cards = extractCards(from: page)
            cardsByPage.append(cards)

            for card in cards {
                globalIndex += 1
                inputs.append(
                    try extractInput(
                        from: card,
                        index: globalIndex
                    )
                )
            }
        }

        guard inputs.count == 20,
              cardsByPage.map(\.count) == [4, 4, 4, 4, 4] else {
            throw LandingBatchRepairError.noQuestionCards
        }

        var translatedByIndex: [Int: GeminiLandingQuestionTranslation] = [:]
        let batches = stride(
            from: 0,
            to: inputs.count,
            by: batchSize
        ).map {
            Array(
                inputs[
                    $0..<min($0 + batchSize, inputs.count)
                ]
            )
        }

        for (batchOffset, batch) in batches.enumerated() {
            let batchNumber = batchOffset + 1
            let start = batch.first?.index ?? 0
            let end = batch.last?.index ?? 0

            onLog(
                "    ↳ Landing batch \(batchNumber)/\(batches.count): Q\(start)–Q\(end)"
            )

            let translations = try loadOrTranslateBatch(
                batch,
                batchNumber: batchNumber,
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage,
                folder: folder,
                onLog: onLog
            )

            for translated in translations {
                translatedByIndex[translated.index] = translated
            }
        }

        var patchedPages: [String] = []
        globalIndex = 0

        for (pageIndex, page) in pages.enumerated() {
            var replacements: [String] = []

            for card in cardsByPage[pageIndex] {
                globalIndex += 1

                guard let translation =
                        translatedByIndex[globalIndex] else {
                    throw LandingBatchRepairError.cannotPatchQuestion(
                        globalIndex
                    )
                }

                replacements.append(
                    try patchCard(
                        card,
                        translation: translation,
                        targetLanguage: targetLanguage
                    )
                )
            }

            patchedPages.append(
                replaceCards(
                    in: page,
                    with: replacements
                )
            )
        }

        root["main_content"] = patchedPages[0]

        for index in 0..<min(4, subPages.count) {
            subPages[index]["content"] =
                patchedPages[index + 1]
        }

        root["sub_pages"] = subPages

        guard let output = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted]
        ),
        let text = String(
            data: output,
            encoding: .utf8
        ) else {
            throw LandingBatchRepairError.invalidGeneratedJSON
        }

        return text
    }

    private func loadOrTranslateBatch(
        _ batch: [LandingQuestionTranslationInput],
        batchNumber: Int,
        targetLanguage: CampaignLanguage,
        sourceLanguage: String,
        folder: URL,
        onLog: @escaping (String) -> Void
    ) throws -> [GeminiLandingQuestionTranslation] {
        let digest = batchDigest(
            batch,
            targetLanguage: targetLanguage
        )

        let cacheURL = folder.appendingPathComponent(
            String(
                format:
                    "landing_translation_%@_batch_%02d.json",
                targetLanguage.code,
                batchNumber
            )
        )

        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(
                LandingTranslationBatchCache.self,
                from: data
           ),
           cache.digest == digest,
           cache.languageCode == targetLanguage.code,
           validate(
                cache.translations,
                against: batch,
                targetLanguage: targetLanguage
           ) {
            onLog("      ✓ CACHE HIT — batch \(batchNumber)")
            return cache.translations
        }

        var lastError: Error?

        for attempt in 1...3 {
            let semaphore = DispatchSemaphore(value: 0)
            var result:
                Result<GeminiLandingQuestionBatchResponse, Error>?

            gemini.translateLandingQuestionBatch(
                cards: batch,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                attempt: attempt
            ) {
                result = $0
                semaphore.signal()
            }

            if semaphore.wait(
                timeout: .now() + 180
            ) == .timedOut {
                lastError =
                    LandingBatchRepairError.timeout(
                        batchNumber
                    )
            } else {
                switch result {
                case .success(let response):
                    if validate(
                        response.translations,
                        against: batch,
                        targetLanguage: targetLanguage
                    ) {
                        let cache =
                            LandingTranslationBatchCache(
                                digest: digest,
                                languageCode:
                                    targetLanguage.code,
                                translations:
                                    response.translations
                            )

                        if let cacheData =
                                try? JSONEncoder().encode(
                                    cache
                                ) {
                            try? cacheData.write(
                                to: cacheURL,
                                options: .atomic
                            )
                        }

                        onLog(
                            "      ✓ batch \(batchNumber) PASS " +
                            "(attempt \(attempt)/3)"
                        )
                        return response.translations
                    }

                    lastError =
                        LandingBatchRepairError
                            .invalidBatchResponse(
                                "count/index/options hoặc language residue sai."
                            )

                case .failure(let error):
                    lastError = error

                case .none:
                    lastError =
                        GeminiAPIError.invalidResponse
                }
            }

            if attempt < 3 {
                let delay: TimeInterval

                if let error = lastError,
                   isTransientGeminiError(error) {
                    delay =
                        attempt == 1 ? 3 : 8
                    onLog(
                        "      ↻ transient Gemini error — " +
                        "retry batch \(batchNumber) sau \(Int(delay))s"
                    )
                } else {
                    delay =
                        attempt == 1 ? 1.5 : 3
                    onLog(
                        "      ↻ retry batch \(batchNumber) " +
                        "(attempt \(attempt + 1)/3)"
                    )
                }

                Thread.sleep(
                    forTimeInterval: delay
                )
            }
        }

        throw lastError ??
            GeminiAPIError.invalidResponse
    }

    private func validate(
        _ translations: [GeminiLandingQuestionTranslation],
        against batch: [LandingQuestionTranslationInput],
        targetLanguage: CampaignLanguage
    ) -> Bool {
        guard translations.count == batch.count else {
            return false
        }

        let expected = Dictionary(
            uniqueKeysWithValues:
                batch.map { ($0.index, $0) }
        )

        for translated in translations {
            guard let source =
                    expected[translated.index],
                  translated.options.count ==
                    source.options.count,
                  translated.options.count == 4,
                  !translated.question
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty else {
                return false
            }

            if translationStillLooksSource(
                source: source.question,
                translated: translated.question,
                targetLanguage: targetLanguage
            ) {
                return false
            }

            if !source.explanation
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty,
               translationStillLooksSource(
                    source: source.explanation,
                    translated:
                        translated.explanation,
                    targetLanguage: targetLanguage
               ) {
                return false
            }
        }

        return Set(translations.map(\.index)) ==
            Set(batch.map(\.index))
    }

    private func translationStillLooksSource(
        source: String,
        translated: String,
        targetLanguage: CampaignLanguage
    ) -> Bool {
        let sourceKey = normalized(source)
        let translatedKey = normalized(translated)

        if sourceKey.count >= 12 &&
           sourceKey == translatedKey {
            return true
        }

        let words = translatedKey
            .split(separator: " ")
            .map(String.init)

        if words.count < 4 {
            return false
        }

        if targetLanguage == .russian {
            let hasCyrillic =
                translated.unicodeScalars.contains {
                    (0x0400...0x04FF)
                        .contains(Int($0.value))
                }
            return !hasCyrillic
        }

        if targetLanguage == .arabic {
            let hasArabic =
                translated.unicodeScalars.contains {
                    (0x0600...0x06FF)
                        .contains(Int($0.value)) ||
                    (0x0750...0x077F)
                        .contains(Int($0.value)) ||
                    (0x08A0...0x08FF)
                        .contains(Int($0.value))
                }
            return !hasArabic
        }

        let englishMarkers: Set<String> = [
            "what", "which", "who", "where", "when",
            "why", "how", "is", "are", "was", "were",
            "does", "do", "did", "can", "the", "this",
            "that", "these", "those", "of", "from",
            "with", "about", "your", "you", "capital",
            "city", "country", "answer", "correct",
            "wrong", "question", "remember", "know"
        ]

        let englishCount =
            words.filter {
                englishMarkers.contains($0)
            }.count

        switch targetLanguage {
        case .romanian:
            let markers: Set<String> = [
                "care", "este", "sunt", "din", "și",
                "sau", "pentru", "cu", "ce", "unde",
                "când", "cum", "oraș", "capitala",
                "țara", "răspuns", "corect"
            ]
            let targetCount =
                words.filter {
                    markers.contains($0)
                }.count
            return englishCount >= 2 &&
                englishCount > targetCount

        case .croatian:
            let markers: Set<String> = [
                "koji", "koja", "koje", "je", "su",
                "u", "i", "ili", "za", "što", "gdje",
                "kada", "kako", "grad", "glavni",
                "država", "odgovor", "točan"
            ]
            let targetCount =
                words.filter {
                    markers.contains($0)
                }.count
            return englishCount >= 2 &&
                englishCount > targetCount

        case .english:
            return false

        case .russian, .arabic:
            return false
        }
    }

    private func extractInput(
        from card: String,
        index: Int
    ) throws -> LandingQuestionTranslationInput {
        guard let question =
                firstCapture(
                    pattern:
                        #"<div class="qtext">([\s\S]*?)</div>"#,
                    in: card
                )
                    .map(htmlDecode),
              let explanation =
                firstCapture(
                    pattern:
                        #"<div class="feedback correct-feedback">[\s\S]*?<br>[\s\S]*?</strong>\s*([\s\S]*?)</div>"#,
                    in: card
                )
                    .map(htmlDecode),
              let hint =
                firstCapture(
                    pattern:
                        #"<div class="hint-content"><p>([\s\S]*?)</p></div>"#,
                    in: card
                )
                    .map(htmlDecode) else {
            throw LandingBatchRepairError
                .invalidQuestionStructure(index)
        }

        let options =
            allCaptures(
                pattern:
                    #"<label class="opt(?: correct)?"><input type="radio" name="q\d+" class="(?:ac|aw)"> ([\s\S]*?)</label>"#,
                in: card
            )
            .map(htmlDecode)

        guard options.count == 4 else {
            throw LandingBatchRepairError
                .invalidQuestionStructure(index)
        }

        return LandingQuestionTranslationInput(
            index: index,
            question:
                question.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            options:
                options.map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                },
            explanation:
                explanation.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            hint:
                hint.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
    }

    private func patchCard(
        _ card: String,
        translation:
            GeminiLandingQuestionTranslation,
        targetLanguage: CampaignLanguage
    ) throws -> String {
        var output = card

        output = replacingFirst(
            pattern:
                #"<div class="qnum">[\s\S]*?</div>"#,
            in: output,
            with:
                "<div class=\"qnum\">" +
                "\(labels(for: targetLanguage).question) " +
                "\(translation.index) / 20</div>"
        )

        output = replacingFirst(
            pattern:
                #"<div class="qtext">[\s\S]*?</div>"#,
            in: output,
            with:
                "<div class=\"qtext\">" +
                htmlEscape(translation.question) +
                "</div>"
        )

        let labelPattern =
            #"<label class="(opt(?: correct)?)"><input type="radio" name="(q\d+)" class="(ac|aw)"> ([\s\S]*?)</label>"#

        guard let regex =
                try? NSRegularExpression(
                    pattern: labelPattern
                ) else {
            throw LandingBatchRepairError
                .cannotPatchQuestion(
                    translation.index
                )
        }

        let ns = output as NSString
        let matches = regex.matches(
            in: output,
            range:
                NSRange(
                    location: 0,
                    length: ns.length
                )
        )

        guard matches.count == 4,
              translation.options.count == 4 else {
            throw LandingBatchRepairError
                .cannotPatchQuestion(
                    translation.index
                )
        }

        var rebuiltOptions = ""
        for (index, match) in matches.enumerated() {
            let labelClass =
                ns.substring(
                    with: match.range(at: 1)
                )
            let name =
                ns.substring(
                    with: match.range(at: 2)
                )
            let inputClass =
                ns.substring(
                    with: match.range(at: 3)
                )

            rebuiltOptions +=
                "<label class=\"\(labelClass)\">" +
                "<input type=\"radio\" name=\"\(name)\" " +
                "class=\"\(inputClass)\"> " +
                htmlEscape(
                    translation.options[index]
                ) +
                "</label>"
        }

        output = replacingFirst(
            pattern:
                #"<div class="opts">[\s\S]*?</div>"#,
            in: output,
            with:
                "<div class=\"opts\">" +
                rebuiltOptions +
                "</div>"
        )

        let labelSet = labels(
            for: targetLanguage
        )

        output = replacingFirst(
            pattern:
                #"<div class="feedback correct-feedback">[\s\S]*?</div>"#,
            in: output,
            with:
                "<div class=\"feedback correct-feedback\">" +
                "<strong>\(htmlEscape(labelSet.correct))</strong>" +
                "<br><strong>\(htmlEscape(labelSet.explanation))</strong> " +
                htmlEscape(translation.explanation) +
                "</div>"
        )

        output = replacingFirst(
            pattern:
                #"<div class="feedback wrong-feedback">[\s\S]*?</div>"#,
            in: output,
            with:
                "<div class=\"feedback wrong-feedback\">" +
                "<strong>\(htmlEscape(labelSet.wrong))</strong>" +
                "<br><strong>\(htmlEscape(labelSet.explanation))</strong> " +
                htmlEscape(translation.explanation) +
                "</div>"
        )

        output = replacingFirst(
            pattern:
                #"<details class="hintbox"><summary>[\s\S]*?</summary><div class="hint-content"><p>[\s\S]*?</p></div></details>"#,
            in: output,
            with:
                "<details class=\"hintbox\"><summary>" +
                "<span class=\"bulb\" aria-hidden=\"true\">💡</span> " +
                "<span>\(htmlEscape(labelSet.hint))</span>" +
                "</summary><div class=\"hint-content\"><p>" +
                htmlEscape(translation.hint) +
                "</p></div></details>"
        )

        return output
    }

    private func labels(
        for language: CampaignLanguage
    ) -> (
        question: String,
        correct: String,
        wrong: String,
        explanation: String,
        hint: String
    ) {
        switch language {
        case .english:
            return (
                "Question",
                "Correct.",
                "Not quite.",
                "Explanation:",
                "Hint"
            )

        case .russian:
            return (
                "Вопрос",
                "Верно.",
                "Не совсем.",
                "Объяснение:",
                "Подсказка"
            )

        case .arabic:
            return (
                "السؤال",
                "صحيح.",
                "ليس تمامًا.",
                "الشرح:",
                "تلميح"
            )

        case .romanian:
            return (
                "Întrebarea",
                "Corect.",
                "Nu chiar.",
                "Explicație:",
                "Indiciu"
            )

        case .croatian:
            return (
                "Pitanje",
                "Točno.",
                "Ne baš.",
                "Objašnjenje:",
                "Savjet"
            )
        }
    }

    private func batchDigest(
        _ batch: [LandingQuestionTranslationInput],
        targetLanguage: CampaignLanguage
    ) -> String {
        var text =
            targetLanguage.code + "\n"

        for item in batch {
            text += "\(item.index)\n"
            text += item.question + "\n"
            text += item.options.joined(separator: "\u{1F}") + "\n"
            text += item.explanation + "\n"
            text += item.hint + "\n"
        }

        var hash: UInt64 =
            1469598103934665603

        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        return String(
            format: "%016llx",
            hash
        )
    }

    private func extractCards(
        from html: String
    ) -> [String] {
        guard let regex =
                try? NSRegularExpression(
                    pattern:
                        #"(?s)<div class="qc">[\s\S]*?<details class="hintbox">[\s\S]*?</details>\s*</div>"#
                ) else {
            return []
        }

        let ns = html as NSString
        return regex.matches(
            in: html,
            range:
                NSRange(
                    location: 0,
                    length: ns.length
                )
        ).map {
            ns.substring(
                with: $0.range
            )
        }
    }

    private func replaceCards(
        in html: String,
        with replacements: [String]
    ) -> String {
        guard let regex =
                try? NSRegularExpression(
                    pattern:
                        #"(?s)<div class="qc">[\s\S]*?<details class="hintbox">[\s\S]*?</details>\s*</div>"#
                ) else {
            return html
        }

        let ns = html as NSString
        let matches = regex.matches(
            in: html,
            range:
                NSRange(
                    location: 0,
                    length: ns.length
                )
        )

        guard matches.count ==
                replacements.count else {
            return html
        }

        var output = ""
        var cursor = 0

        for (index, match) in matches.enumerated() {
            if match.range.location > cursor {
                output += ns.substring(
                    with:
                        NSRange(
                            location: cursor,
                            length:
                                match.range.location -
                                cursor
                        )
                )
            }

            output += replacements[index]
            cursor = NSMaxRange(match.range)
        }

        if cursor < ns.length {
            output += ns.substring(
                from: cursor
            )
        }

        return output
    }

    private func firstCapture(
        pattern: String,
        in text: String
    ) -> String? {
        allCaptures(
            pattern: pattern,
            in: text
        ).first
    }

    private func allCaptures(
        pattern: String,
        in text: String
    ) -> [String] {
        guard let regex =
                try? NSRegularExpression(
                    pattern: pattern
                ) else {
            return []
        }

        let ns = text as NSString
        return regex.matches(
            in: text,
            range:
                NSRange(
                    location: 0,
                    length: ns.length
                )
        ).compactMap { match in
            guard match.numberOfRanges > 1 else {
                return nil
            }

            let range = match.range(at: 1)
            guard range.location != NSNotFound else {
                return nil
            }

            return ns.substring(
                with: range
            )
        }
    }

    private func replacingFirst(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let regex =
                try? NSRegularExpression(
                    pattern: pattern
                ) else {
            return text
        }

        let ns = text as NSString
        let range =
            NSRange(
                location: 0,
                length: ns.length
            )

        guard let match =
                regex.firstMatch(
                    in: text,
                    range: range
                ) else {
            return text
        }

        return ns.replacingCharacters(
            in: match.range,
            with: replacement
        )
    }

    private func htmlEscape(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
    }

    private func htmlDecode(
        _ text: String
    ) -> String {
        text
            .replacingOccurrences(
                of: "&quot;",
                with: "\""
            )
            .replacingOccurrences(
                of: "&#39;",
                with: "'"
            )
            .replacingOccurrences(
                of: "&lt;",
                with: "<"
            )
            .replacingOccurrences(
                of: "&gt;",
                with: ">"
            )
            .replacingOccurrences(
                of: "&amp;",
                with: "&"
            )
    }

    private func normalized(
        _ text: String
    ) -> String {
        let folded =
            htmlDecode(text)
                .lowercased()
                .folding(
                    options: [
                        .diacriticInsensitive,
                        .widthInsensitive
                    ],
                    locale:
                        Locale(
                            identifier:
                                "en_US_POSIX"
                        )
                )

        let scalars =
            folded.unicodeScalars.map {
                scalar -> Character in

                CharacterSet
                    .alphanumerics
                    .contains(scalar)
                ? Character(
                    String(scalar)
                )
                : " "
            }

        return String(scalars)
            .split(
                whereSeparator:
                    \.isWhitespace
            )
            .joined(separator: " ")
    }
}
