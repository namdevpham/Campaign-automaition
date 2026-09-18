import AppKit
import Foundation

struct ParsedQuestion: Codable {
    let sourcePosition: Int
    let question: String
    let options: [String]
    let correctAnswer: String?
    let answerParagraph: String
    let imageUrl: String
    let sourceHint: String?
    let type: String?
}

struct ParsedQuiz: Codable {
    let sourceFile: String
    let quizId: String
    let quizName: String
    let sourceLanguage: String
    let quizType: String
    let sourceQuestionCount: Int
    let quizTags: [String]
    let questions: [ParsedQuestion]
}

enum SourceParserError: Error, LocalizedError {
    case unreadable
    case nextPayloadNotFound
    case stateNotFound
    case invalidState
    case noQuestions

    var errorDescription: String? {
        switch self {
        case .unreadable: return "Không thể đọc Source View."
        case .nextPayloadNotFound: return "Không tìm thấy payload Next.js chứa quizName/questions."
        case .stateNotFound: return "Không tìm thấy state quiz trong Source View."
        case .invalidState: return "State quiz không phải JSON hợp lệ."
        case .noQuestions: return "Không trích xuất được câu hỏi nào."
        }
    }
}

final class SourceViewParser {
    func parse(fileURL: URL) throws -> ParsedQuiz {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw SourceParserError.unreadable
        }

        let source = reconstructViewSourceIfNeeded(raw)
        let payloads = extractNextPayloadStrings(source)

        guard let quizPayload = payloads.first(where: { $0.contains("\"quizName\"") && $0.contains("\"questions\"") }) else {
            throw SourceParserError.nextPayloadNotFound
        }

        guard let stateRange = quizPayload.range(of: "\"state\":") else {
            throw SourceParserError.stateNotFound
        }

        var objectStart = stateRange.upperBound
        while objectStart < quizPayload.endIndex && quizPayload[objectStart].isWhitespace {
            objectStart = quizPayload.index(after: objectStart)
        }
        guard objectStart < quizPayload.endIndex, quizPayload[objectStart] == "{" else {
            throw SourceParserError.stateNotFound
        }

        guard let stateText = balancedExtract(quizPayload, from: objectStart, open: "{", close: "}") else {
            throw SourceParserError.invalidState
        }

        guard let data = stateText.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceParserError.invalidState
        }

        let quizId = root["quizId"] as? String ?? ""
        let quizName = root["quizName"] as? String ?? ""
        let language = (root["language"] as? String) ?? detectLanguage(in: quizPayload)
        let quizType = root["quizType"] as? String ?? ""
        let tags = root["quizTags"] as? [String] ?? []
        let rawQuestions = root["questions"] as? [[String: Any]] ?? []

        var questions: [ParsedQuestion] = []
        for (idx, q) in rawQuestions.enumerated() {
            let options = normalizeOptions(q["options"])
            let parsed = ParsedQuestion(
                sourcePosition: idx + 1,
                question: q["question"] as? String ?? "",
                options: options,
                correctAnswer: q["correctAnswer"] as? String,
                answerParagraph: q["answerParagraph"] as? String ?? "",
                imageUrl: q["imageUrl"] as? String ?? "",
                sourceHint: q["hint"] as? String,
                type: q["type"] as? String
            )
            questions.append(parsed)
        }

        guard !questions.isEmpty else { throw SourceParserError.noQuestions }

        return ParsedQuiz(
            sourceFile: fileURL.lastPathComponent,
            quizId: quizId,
            quizName: quizName,
            sourceLanguage: language,
            quizType: quizType,
            sourceQuestionCount: questions.count,
            quizTags: tags,
            questions: questions
        )
    }

    func saveExtracted(_ quiz: ParsedQuiz, to folder: URL) throws -> URL {
        let output = folder.appendingPathComponent("extracted_source.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(quiz)
        try data.write(to: output, options: .atomic)
        return output
    }

    private func reconstructViewSourceIfNeeded(_ raw: String) -> String {
        guard raw.contains("td class=\"line-content\"") else { return raw }

        let pattern = #"<td class="line-content">([\s\S]*?)</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return raw }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return raw }

        var lines: [String] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let fragment = ns.substring(with: match.range(at: 1))
            lines.append(htmlFragmentToText(fragment))
        }
        return lines.joined(separator: "\n")
    }

    private func htmlFragmentToText(_ fragment: String) -> String {
        let wrapped = "<html><body>\(fragment)</body></html>"
        guard let data = wrapped.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return fragment
        }
        return attr.string
    }

    private func extractNextPayloadStrings(_ source: String) -> [String] {
        let needle = "self.__next_f.push("
        var results: [String] = []
        var cursor = source.startIndex

        while let range = source.range(of: needle, range: cursor..<source.endIndex) {
            var start = range.upperBound
            while start < source.endIndex && source[start].isWhitespace {
                start = source.index(after: start)
            }

            if start < source.endIndex, source[start] == "[",
               let arrayText = balancedExtract(source, from: start, open: "[", close: "]"),
               let data = arrayText.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
               array.count > 1,
               let payload = array[1] as? String {
                results.append(payload)
                cursor = source.index(after: range.lowerBound)
            } else {
                cursor = range.upperBound
            }
        }

        return results
    }

    private func balancedExtract(_ text: String, from start: String.Index, open: Character, close: Character) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let ch = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                if ch == "\"" {
                    inString = true
                } else if ch == open {
                    depth += 1
                } else if ch == close {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }

            index = text.index(after: index)
        }
        return nil
    }

    private func normalizeOptions(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let objects = value as? [[String: Any]] {
            return objects.compactMap { $0["option"] as? String }
        }
        return []
    }

    private func detectLanguage(in payload: String) -> String {
        if let range = payload.range(of: #""data-language":"#) {
            let rest = payload[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                return String(rest[..<end])
            }
        }
        return ""
    }
}
