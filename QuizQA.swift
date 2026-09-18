import AppKit
import Foundation

struct QuizQAResult {
    let passed: Bool
    let issues: [String]
    let selectedSourcePositions: [Int]

    var reportText: String {
        var lines: [String] = []
        lines.append(passed ? "PASS — 0 issues" : "FAIL — \(issues.count) issue(s)")
        if !selectedSourcePositions.isEmpty {
            lines.append("Selected source positions: \(selectedSourcePositions.map(String.init).joined(separator: ", "))")
        }
        if !issues.isEmpty {
            lines.append("")
            for (index, issue) in issues.enumerated() {
                lines.append("\(index + 1). \(issue)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

final class QuizQAValidator {
    func validate(jsonText: String, source: ParsedQuiz) -> QuizQAResult {
        var issues: [String] = []
        var selectedPositions: [Int] = []

        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return QuizQAResult(
                passed: false,
                issues: ["generated_content.json không phải JSON object hợp lệ."],
                selectedSourcePositions: []
            )
        }

        let expectedRootOrder = [
            "\"locale\"", "\"title\"", "\"name\"", "\"description\"",
            "\"main_content\"", "\"confirm\"", "\"sub_pages\""
        ]
        var lastLocation = -1
        for key in expectedRootOrder {
            if let range = jsonText.range(of: key) {
                let loc = jsonText.distance(from: jsonText.startIndex, to: range.lowerBound)
                if loc <= lastLocation {
                    issues.append("Root key order không đúng tại \(key).")
                }
                lastLocation = loc
            } else {
                issues.append("Thiếu root key \(key).")
            }
        }

        let locale = root["locale"] as? String ?? ""
        let name = root["name"] as? String ?? ""
        if locale.isEmpty {
            issues.append("locale bị trống.")
        }

        let expectedNameSuffix =
            TechnicalNameRule.expectedSuffix(
                for: locale
            )

        if !name.hasSuffix(expectedNameSuffix) {
            issues.append(
                "name phải kết thúc bằng \(expectedNameSuffix) " +
                "theo locale \(locale)."
            )
        }

        let forbiddenLegacySuffixes = [
            "_Testw1",
            "_English",
            "_Russian",
            "_Arabic",
            "_Romanian",
            "_Croatian"
        ]

        for suffix in forbiddenLegacySuffixes
        where name.lowercased().hasSuffix(
            suffix.lowercased()
        ) {
            issues.append(
                "name còn dùng suffix cũ: \(suffix)."
            )
        }

        guard let mainContent = root["main_content"] as? String else {
            issues.append("main_content không phải string.")
            return QuizQAResult(passed: false, issues: issues, selectedSourcePositions: [])
        }

        guard let subPages = root["sub_pages"] as? [[String: Any]] else {
            issues.append("sub_pages không phải array object.")
            return QuizQAResult(passed: false, issues: issues, selectedSourcePositions: [])
        }

        if subPages.count != 5 {
            issues.append("sub_pages phải có đúng 5 item, hiện có \(subPages.count).")
        }

        let actualPaths = subPages.compactMap { $0["path"] as? String }
        let expectedPaths = ["1", "2", "3", "4", "5"]
        if actualPaths != expectedPaths {
            issues.append("Paths phải đúng [1,2,3,4,5], hiện là \(actualPaths).")
        }

        // V0.11: exact title consistency across paths 1-5.
        let rootTitle = root["title"] as? String ?? ""
        if rootTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Root title bị trống.")
        }
        for (index, page) in subPages.enumerated() {
            let pageTitle = page["title"] as? String ?? ""
            if pageTitle != rootTitle {
                let path = page["path"] as? String ?? "\(index + 1)"
                issues.append(
                    "Path \(path) title không giống root title. " +
                    "Phải là exact: '\(rootTitle)'."
                )
            }
        }

        var pages: [String] = [mainContent]
        pages.append(contentsOf: subPages.compactMap { $0["content"] as? String })

        if pages.count == 6 {
            let cards = pages.map { countExact("<div class=\"qc\">", in: $0) }
            if cards != [4, 4, 4, 4, 4, 0] {
                issues.append("Question-card distribution sai: \(cards), cần [4,4,4,4,4,0].")
            }

            let ads = pages.map { countExact("<p>[ads/]</p>", in: $0) }
            if ads != [1, 1, 1, 1, 1, 0] {
                issues.append("Ads distribution sai: \(ads), cần [1,1,1,1,1,0].")
            }

            let footers = pages.map { countExact("<div class=\"footer-note\">", in: $0) }
            if footers != [1, 1, 1, 1, 1, 1] {
                issues.append("Footer distribution sai: \(footers), cần [1,1,1,1,1,1].")
            }
        }

        let allHTML = pages.joined(separator: "\n")
        let hintCount = countExact("<details class=\"hintbox\">", in: allHTML)
        if hintCount != 20 {
            issues.append("Hint count = \(hintCount), cần 20.")
        }

        let correctFeedback = countExact("<div class=\"feedback correct-feedback\">", in: allHTML)
        let wrongFeedback = countExact("<div class=\"feedback wrong-feedback\">", in: allHTML)
        if correctFeedback != 20 {
            issues.append("Correct feedback count = \(correctFeedback), cần 20.")
        }
        if wrongFeedback != 20 {
            issues.append("Wrong feedback count = \(wrongFeedback), cần 20.")
        }

        let lowerHTML = allHTML.lowercased()
        if lowerHTML.contains("<script") { issues.append("Không được có <script>.") }
        if lowerHTML.contains("onclick=") { issues.append("Không được có onclick=.") }
        if lowerHTML.contains("onchange=") { issues.append("Không được có onchange=.") }

        if !mainContent.contains("max-width:600px") {
            issues.append("Không tìm thấy approved CSS max-width:600px.")
        }

        let expectedNav = [
            "custom=\"1\"", "custom=\"2\"", "custom=\"3\"",
            "custom=\"4\"", "custom=\"5\"", "custom=\"Confirm\""
        ]
        if pages.count == 6 {
            for i in 0..<min(pages.count, expectedNav.count) {
                if !pages[i].contains(expectedNav[i]) {
                    issues.append("Navigation page \(i) thiếu \(expectedNav[i]).")
                }
            }
        }

        let resultHTML = pages.count > 5 ? pages[5] : ""
        let resultClasses = [
            "result-tier-purple",
            "result-tier-green",
            "result-tier-yellow",
            "result-tier-red"
        ]
        for resultClass in resultClasses {
            let needle = "<div class=\"result-card \(resultClass)\">"
            if countExact(needle, in: resultHTML) != 1 {
                issues.append("Results phải có đúng 1 card class \(resultClass).")
            }
        }
        for range in ["17–20", "13–16", "8–12", "0–7"] {
            if !resultHTML.contains("<strong>\(range)</strong>") {
                issues.append("Results thiếu range \(range).")
            }
        }

        let isRTL = locale.lowercased() == "ar" || source.sourceLanguage.lowercased().contains("arab")
        if isRTL {
            for (index, page) in pages.enumerated() {
                if !actualWrapper(page).contains("dir=\"rtl\"") {
                    issues.append("Page \(index) phải dùng RTL wrapper.")
                }
            }
        } else {
            for (index, page) in pages.enumerated() {
                let wrapper = actualWrapper(page)
                if wrapper.isEmpty {
                    issues.append("Page \(index) không tìm thấy wrapper .tq sau CSS.")
                } else if wrapper.contains("dir=\"rtl\"") {
                    issues.append("Page \(index) không nên dùng RTL wrapper.")
                }
            }
        }

        // Source-fidelity verification card-by-card.
        let questionPages = Array(pages.prefix(5))
        let cardBodies = questionPages.flatMap { extractCardBodies(from: $0) }

        if cardBodies.count != 20 {
            issues.append("Không extract được đúng 20 question card để source-fidelity QA.")
        } else {
            var lastPosition = 0
            var used = Set<Int>()

            for (displayIndex, card) in cardBodies.enumerated() {
                guard let qHTML = firstCapture(
                    pattern: #"<div class="qtext">([\s\S]*?)</div>"#,
                    in: card
                ) else {
                    issues.append("Question \(displayIndex + 1): không đọc được qtext.")
                    continue
                }

                let questionText = htmlDecode(qHTML).trimmingCharacters(in: .whitespacesAndNewlines)
                let candidates = source.questions.filter {
                    !used.contains($0.sourcePosition) &&
                    $0.question.trimmingCharacters(in: .whitespacesAndNewlines) == questionText
                }

                guard let src = candidates.first else {
                    issues.append("Question \(displayIndex + 1) không khớp exact source question.")
                    continue
                }

                used.insert(src.sourcePosition)
                selectedPositions.append(src.sourcePosition)

                if src.sourcePosition <= lastPosition {
                    issues.append("Selected source-relative order bị thay đổi tại display question \(displayIndex + 1).")
                }
                lastPosition = src.sourcePosition

                let generatedOptions = allCaptures(
                    pattern: #"<label class="opt(?: correct)?"><input type="radio" name="q\d+" class="(?:ac|aw)"> ([\s\S]*?)</label>"#,
                    in: card
                ).map { htmlDecode($0).trimmingCharacters(in: .whitespacesAndNewlines) }

                if generatedOptions != src.options {
                    issues.append("Question \(displayIndex + 1): option order/text không khớp source.")
                }

                if let correctHTML = firstCapture(
                    pattern: #"<label class="opt correct"><input type="radio" name="q\d+" class="ac"> ([\s\S]*?)</label>"#,
                    in: card
                ) {
                    let generatedCorrect = htmlDecode(correctHTML)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if generatedCorrect != (src.correctAnswer ?? "") {
                        issues.append("Question \(displayIndex + 1): correct answer không khớp source.")
                    }
                } else if let correctAnswer = src.correctAnswer, !correctAnswer.isEmpty {
                    issues.append("Question \(displayIndex + 1): thiếu correct option từ source.")
                }

                let sourceImage = src.imageUrl
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let generatedImage = firstCapture(
                    pattern: #"<img class="qimg" src="([^"]*)" alt="">"#,
                    in: card
                ).map {
                    htmlDecode($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if sourceImage.isEmpty {
                    if let generatedImage, !generatedImage.isEmpty {
                        issues.append("Question \(displayIndex + 1): source không có image nhưng output lại có image.")
                    }
                } else {
                    guard let generatedImage else {
                        issues.append("Question \(displayIndex + 1): thiếu image URL từ source.")
                        continue
                    }
                    if generatedImage != sourceImage {
                        issues.append("Question \(displayIndex + 1): image URL không khớp source.")
                    }
                }

                let sourceExplanation = src.answerParagraph
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let explanationHTML = firstCapture(
                    pattern: #"<div class="feedback correct-feedback">[\s\S]*?<br>[\s\S]*?</strong>\s*([\s\S]*?)</div>"#,
                    in: card
                ) {
                    let generatedExplanation = htmlDecode(explanationHTML)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if generatedExplanation != sourceExplanation {
                        issues.append("Question \(displayIndex + 1): explanation không khớp source.")
                    }
                } else if !sourceExplanation.isEmpty {
                    issues.append("Question \(displayIndex + 1): thiếu explanation từ source.")
                }
            }
        }

        return QuizQAResult(
            passed: issues.isEmpty,
            issues: issues,
            selectedSourcePositions: selectedPositions
        )
    }

    func validateLocalized(
        jsonText: String,
        expectedLanguage: CampaignLanguage,
        source: ParsedQuiz
    ) -> QuizQAResult {
        var issues: [String] = []

        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return QuizQAResult(
                passed: false,
                issues: ["Localized generated_content.json không phải JSON object hợp lệ."],
                selectedSourcePositions: []
            )
        }

        let locale = (root["locale"] as? String ?? "").lowercased()
        if locale != expectedLanguage.code {
            issues.append(
                "locale phải là \(expectedLanguage.code), hiện là \(locale)."
            )
        }

        let name = root["name"] as? String ?? ""
        let suffix = TechnicalNameRule.expectedSuffix(for: expectedLanguage.code)
        if !name.hasSuffix(suffix) {
            issues.append("Technical name phải kết thúc bằng \(suffix).")
        }

        let rootTitle = root["title"] as? String ?? ""
        if rootTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Root title bị trống.")
        }

        guard let mainContent = root["main_content"] as? String,
              let subPages = root["sub_pages"] as? [[String: Any]] else {
            issues.append("Thiếu main_content hoặc sub_pages.")
            return QuizQAResult(
                passed: false,
                issues: issues,
                selectedSourcePositions: []
            )
        }

        if subPages.count != 5 {
            issues.append("sub_pages phải có đúng 5 item.")
        }

        let actualPaths = subPages.compactMap { $0["path"] as? String }
        if actualPaths != ["1", "2", "3", "4", "5"] {
            issues.append("Paths phải đúng [1,2,3,4,5].")
        }

        for page in subPages {
            if (page["title"] as? String ?? "") != rootTitle {
                issues.append("Sub-page title không giống exact root title.")
                break
            }
        }

        var pages: [String] = [mainContent]
        pages.append(contentsOf: subPages.compactMap { $0["content"] as? String })

        if pages.count == 6 {
            let cards = pages.map { countExact("<div class=\"qc\">", in: $0) }
            if cards != [4, 4, 4, 4, 4, 0] {
                issues.append("Question-card distribution sai: \(cards).")
            }

            let ads = pages.map { countExact("<p>[ads/]</p>", in: $0) }
            if ads != [1, 1, 1, 1, 1, 0] {
                issues.append("Ads distribution sai: \(ads).")
            }

            let footers = pages.map { countExact("<div class=\"footer-note\">", in: $0) }
            if footers != [1, 1, 1, 1, 1, 1] {
                issues.append("Footer distribution sai: \(footers).")
            }
        }

        let html = pages.joined(separator: "\n")
        if countExact("<details class=\"hintbox\">", in: html) != 20 {
            issues.append("Localized output phải có đúng 20 hintbox.")
        }
        if countExact("<div class=\"feedback correct-feedback\">", in: html) != 20 {
            issues.append("Localized output phải có đúng 20 correct feedback.")
        }
        if countExact("<div class=\"feedback wrong-feedback\">", in: html) != 20 {
            issues.append("Localized output phải có đúng 20 wrong feedback.")
        }

        if html.lowercased().contains("<script") {
            issues.append("Không được có <script>.")
        }
        if html.lowercased().contains("onclick=") || html.lowercased().contains("onchange=") {
            issues.append("Không được có inline event handler.")
        }
        if !mainContent.contains("max-width:600px") {
            issues.append("Không tìm thấy approved CSS max-width:600px.")
        }

        let questionPages = Array(pages.prefix(5))
        let cardBodies = questionPages.flatMap { extractCardBodies(from: $0) }
        if cardBodies.count != 20 {
            issues.append("Không extract được đúng 20 localized question card.")
        } else {
            let sourceQuestionKeys = Set(
                source.questions.map { normalizedLanguageGuardText($0.question) }
            )

            let sourceExplanationKeys = Set(
                source.questions
                    .map { normalizedLanguageGuardText($0.answerParagraph) }
                    .filter { !$0.isEmpty }
            )

            for (index, card) in cardBodies.enumerated() {
                let questionText = firstCapture(
                    pattern: #"<div class="qtext">([\s\S]*?)</div>"#,
                    in: card
                )
                .map(htmlDecode)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

                if questionText.isEmpty {
                    issues.append("Question \(index + 1): thiếu qtext localized.")
                } else if CampaignLanguage.matchingSourceLanguage(source.sourceLanguage) != expectedLanguage {
                    let qKey = normalizedLanguageGuardText(questionText)
                    if !qKey.isEmpty && sourceQuestionKeys.contains(qKey) {
                        issues.append(
                            "LANGUAGE MISMATCH Question \(index + 1): qtext vẫn giống nguyên văn Source View (\(source.sourceLanguage)) thay vì \(expectedLanguage.shortLabel)."
                        )
                    } else if looksLikeEnglishResidue(
                        questionText,
                        expectedLanguage: expectedLanguage
                    ) {
                        issues.append(
                            "LANGUAGE MISMATCH Question \(index + 1): qtext có dấu hiệu vẫn là English thay vì \(expectedLanguage.shortLabel): \(questionText.prefix(90))"
                        )
                    }
                }

                let options = allCaptures(
                    pattern: #"<label class="opt(?: correct)?"><input type="radio" name="q\d+" class="(?:ac|aw)"> ([\s\S]*?)</label>"#,
                    in: card
                ).map(htmlDecode)

                if options.count != 4 {
                    issues.append("Question \(index + 1): phải có đúng 4 options.")
                }

                let correctCount = countExact("class=\"opt correct\"", in: card)
                if correctCount != 1 {
                    issues.append("Question \(index + 1): phải có đúng 1 correct option.")
                }

                if CampaignLanguage.matchingSourceLanguage(source.sourceLanguage) != expectedLanguage {
                    for (optionIndex, option) in options.enumerated() {
                        let words = languageGuardWords(option)
                        if words.count >= 4 &&
                           looksLikeEnglishResidue(option, expectedLanguage: expectedLanguage) {
                            issues.append(
                                "LANGUAGE MISMATCH Question \(index + 1) option \(optionIndex + 1): option dài vẫn có dấu hiệu English."
                            )
                        }
                    }

                    if let explanation = firstCapture(
                        pattern: #"<div class="feedback correct-feedback">[\s\S]*?<br>[\s\S]*?</strong>\s*([\s\S]*?)</div>"#,
                        in: card
                    ).map(htmlDecode) {
                        let explanationKey = normalizedLanguageGuardText(explanation)
                        if !explanationKey.isEmpty && sourceExplanationKeys.contains(explanationKey) {
                            issues.append(
                                "LANGUAGE MISMATCH Question \(index + 1): explanation vẫn là nguyên văn Source View."
                            )
                        } else if languageGuardWords(explanation).count >= 5 &&
                                  looksLikeEnglishResidue(explanation, expectedLanguage: expectedLanguage) {
                            issues.append(
                                "LANGUAGE MISMATCH Question \(index + 1): explanation có dấu hiệu vẫn là English."
                            )
                        }
                    }
                }
            }
        }

        if CampaignLanguage.matchingSourceLanguage(source.sourceLanguage) != expectedLanguage {
            let sourceTitleKey = normalizedLanguageGuardText(source.quizName)
            let outputTitleKey = normalizedLanguageGuardText(rootTitle)
            if !sourceTitleKey.isEmpty && sourceTitleKey == outputTitleKey {
                issues.append(
                    "LANGUAGE MISMATCH: root title vẫn giống Source View thay vì \(expectedLanguage.shortLabel)."
                )
            }

            if looksLikeEnglishResidue(rootTitle, expectedLanguage: expectedLanguage) {
                issues.append(
                    "LANGUAGE MISMATCH: root title có dấu hiệu vẫn là English thay vì \(expectedLanguage.shortLabel)."
                )
            }
        }

        if expectedLanguage == .arabic {
            for (index, page) in pages.enumerated() {
                if !actualWrapper(page).contains("dir=\"rtl\"") {
                    issues.append("Arabic page \(index) phải dùng RTL wrapper.")
                }
            }
        } else {
            for (index, page) in pages.enumerated() {
                let wrapper = actualWrapper(page)
                if wrapper.isEmpty {
                    issues.append("Page \(index) không tìm thấy wrapper .tq.")
                } else if wrapper.contains("dir=\"rtl\"") {
                    issues.append("Page \(index) không nên dùng RTL wrapper.")
                }
            }
        }

        return QuizQAResult(
            passed: issues.isEmpty,
            issues: issues,
            selectedSourcePositions: []
        )
    }

    private func normalizedLanguageGuardText(_ text: String) -> String {
        let decoded = htmlDecode(text)
            .lowercased()
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )

        let scalars = decoded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : " "
        }

        return String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func languageGuardWords(_ text: String) -> [String] {
        normalizedLanguageGuardText(text)
            .split(separator: " ")
            .map(String.init)
    }

    private func looksLikeEnglishResidue(
        _ text: String,
        expectedLanguage: CampaignLanguage
    ) -> Bool {
        guard expectedLanguage != .english else {
            return false
        }

        let words = languageGuardWords(text)
        guard words.count >= 4 else {
            return false
        }

        let englishMarkers: Set<String> = [
            "what", "which", "who", "where", "when", "why", "how",
            "is", "are", "was", "were", "does", "do", "did", "can",
            "could", "would", "should", "the", "this", "that", "these",
            "those", "of", "from", "with", "into", "about", "your", "you",
            "serves", "capital", "city", "country", "answer", "correct",
            "wrong", "question", "remember", "know", "name", "called"
        ]

        let targetMarkers: Set<String>
        switch expectedLanguage {
        case .romanian:
            targetMarkers = [
                "care", "este", "sunt", "din", "si", "sau", "pentru", "cu",
                "ce", "unde", "cand", "cum", "cat", "acest", "aceasta", "oras",
                "capitala", "tara", "raspuns", "corect"
            ]
        case .croatian:
            targetMarkers = [
                "koji", "koja", "koje", "je", "su", "u", "i", "ili", "za",
                "sto", "gdje", "kada", "kako", "grad", "glavni", "drzava",
                "odgovor", "tocan"
            ]
        case .russian:
            targetMarkers = [
                "какой", "какая", "какое", "кто", "где", "когда", "как",
                "это", "столица", "город", "страна", "ответ", "правильный"
            ]
        case .arabic:
            targetMarkers = [
                "ما", "ماذا", "من", "أين", "متى", "كيف", "هي", "هو",
                "العاصمة", "مدينة", "دولة", "الإجابة", "الصحيحة"
            ]
        case .english:
            targetMarkers = []
        }

        let englishCount = words.filter { englishMarkers.contains($0) }.count
        let targetCount = words.filter { targetMarkers.contains($0) }.count

        if expectedLanguage == .russian {
            let hasCyrillic = text.unicodeScalars.contains {
                (0x0400...0x04FF).contains(Int($0.value))
            }
            if !hasCyrillic && englishCount >= 2 {
                return true
            }
        }

        if expectedLanguage == .arabic {
            let hasArabic = text.unicodeScalars.contains {
                (0x0600...0x06FF).contains(Int($0.value)) ||
                (0x0750...0x077F).contains(Int($0.value)) ||
                (0x08A0...0x08FF).contains(Int($0.value))
            }
            if !hasArabic && englishCount >= 2 {
                return true
            }
        }

        return englishCount >= 2 && englishCount > targetCount
    }

    private func countExact(_ needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private func actualWrapper(_ page: String) -> String {
        let pattern = #"</style>\s*(<div class="tq"(?: dir="rtl")?>)"#
        return firstCapture(pattern: pattern, in: page) ?? ""
    }

    private func extractCardBodies(from html: String) -> [String] {
        return allCaptures(
            pattern: #"(?s)<div class="qc">([\s\S]*?</details>\s*</div>)"#,
            in: html
        )
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        allCaptures(pattern: pattern, in: text).first
    }

    private func allCaptures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let r = match.range(at: 1)
            guard r.location != NSNotFound else { return nil }
            return ns.substring(with: r)
        }
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
}
