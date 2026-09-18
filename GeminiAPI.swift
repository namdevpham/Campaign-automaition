import Foundation
import Security

enum SecureStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error: \(status)"
        }
    }
}

final class SecureStore {
    static let shared = SecureStore()
    private let service = "local.ethopex.campaigntool"

    private init() {}

    func save(_ value: String, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = Data(value.utf8)

        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.keychain(status)
        }
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

final class GeminiConfig {
    static let shared = GeminiConfig()

    let apiKeyAccount = "gemini.api.key"
    private let modelKey = "gemini.model"
    private let imageModelKey = "gemini.image.model"

    private init() {}

    var model: String {
        get {
            let saved = UserDefaults.standard.string(forKey: modelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "gemini-3.5-flash-lite" : saved
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelKey)
        }
    }

    var imageModel: String {
        get {
            let saved = UserDefaults.standard.string(forKey: imageModelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "gemini-3.1-flash-image" : saved
        }
        set {
            UserDefaults.standard.set(newValue, forKey: imageModelKey)
        }
    }

    var apiKey: String? {
        SecureStore.shared.read(account: apiKeyAccount)
    }

    func save(apiKey: String, model: String, imageModel: String? = nil) throws {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanKey.isEmpty {
            try SecureStore.shared.save(cleanKey, account: apiKeyAccount)
        }
        if !cleanModel.isEmpty {
            self.model = cleanModel
        }
        if let imageModel {
            let cleanImageModel = imageModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanImageModel.isEmpty {
                self.imageModel = cleanImageModel
            }
        }
    }
}

struct GeminiLocalizedAdCopy: Codable {
    let primaryText: String
    let headline: String
    let descriptionText: String
}

struct GeminiLocalizedImageResult {
    let data: Data
    let mimeType: String
    let model: String
}

struct GeminiGenerationResult {
    let text: String
    let finishReason: String
    let promptTokenCount: Int
    let outputTokenCount: Int
    let totalTokenCount: Int
    let rawAPIResponse: String
}

enum GeminiAPIError: Error, LocalizedError {
    case invalidURL
    case missingAPIKey
    case badStatus(Int, String)
    case invalidResponse
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Gemini API URL không hợp lệ."
        case .missingAPIKey:
            return "Chưa có Gemini API key."
        case .badStatus(let code, let body):
            return "Gemini HTTP \(code): \(body)"
        case .invalidResponse:
            return "Gemini trả response không đọc được."
        case .emptyOutput:
            return "Gemini không trả JSON."
        }
    }
}


func isTransientGeminiError(
    _ error: Error
) -> Bool {
    if let geminiError =
            error as? GeminiAPIError {
        switch geminiError {
        case .badStatus(
            let code,
            _
        ):
            return [
                429,
                500,
                502,
                503,
                504
            ].contains(code)

        case .invalidURL,
             .missingAPIKey,
             .invalidResponse,
             .emptyOutput:
            return false
        }
    }

    let nsError =
        error as NSError

    if nsError.domain ==
        NSURLErrorDomain {
        return true
    }

    let description =
        error.localizedDescription
            .uppercased()

    return description.contains(
        "UNAVAILABLE"
    ) ||
    description.contains(
        "TIMED OUT"
    ) ||
    description.contains(
        "NETWORK"
    )
}

final class GeminiAPIClient {
    func testConnection(
        apiKey: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanKey.isEmpty else {
            completion(.failure(GeminiAPIError.missingAPIKey))
            return
        }

        guard let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel)") else {
            completion(.failure(GeminiAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(GeminiAPIError.invalidResponse))
                }
                return
            }

            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            if (200...299).contains(http.statusCode) {
                DispatchQueue.main.async {
                    completion(.success("Đã kết nối Gemini • \(cleanModel)"))
                }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(
                        GeminiAPIError.badStatus(http.statusCode, String(body.prefix(800)))
                    ))
                }
            }
        }.resume()
    }

    func generateNAMQuiz(
        masterRules: String,
        extractedSourceJSON: String,
        targetLanguage: CampaignLanguage? = nil,
        sourceLanguage: String? = nil,
        attempt: Int,
        completion: @escaping (Result<GeminiGenerationResult, Error>) -> Void
    ) {
        guard let apiKey = GeminiConfig.shared.apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(GeminiAPIError.missingAPIKey))
            return
        }

        let model = GeminiConfig.shared.model
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            completion(.failure(GeminiAPIError.invalidURL))
            return
        }

        let retryInstruction: String
        if attempt > 1 {
            retryInstruction = """
            IMPORTANT RETRY:
            The previous generation could not be parsed as the required JSON object
            or was incomplete. Rebuild the answer FROM SCRATCH.
            Do not add commentary, markdown, code fences, prefixes, or suffixes.
            Do not omit any required field.
            """
        } else {
            retryInstruction = ""
        }

        let languageInstruction: String
        if let targetLanguage {
            let sourceLabel = sourceLanguage ?? "source language detected in EXTRACTED SOURCE"
            if CampaignLanguage.matchingSourceLanguage(sourceLabel) == targetLanguage {
                languageInstruction = """
                TARGET LANGUAGE: \(targetLanguage.localeInstruction)
                The source is already in the target language. Preserve source-fidelity fields exactly.
                Root `locale` MUST be `\(targetLanguage.code)`.
                """
            } else {
                languageInstruction = """
                TARGET LANGUAGE: \(targetLanguage.localeInstruction)
                SOURCE LANGUAGE: \(sourceLabel)
                MULTILINGUAL OVERRIDE: target-language output supersedes any Master Rule that says
                to keep the original/source language. All other Master Rules remain authoritative.
                Translate ALL user-facing quiz text into the TARGET LANGUAGE, including:
                title, description, EVERY question text, EVERY option text that is linguistic,
                hints, correct/wrong feedback, answer explanations, buttons/navigation,
                result cards and footer text.
                CRITICAL: A translated landing is INVALID if even one quiz question sentence
                remains verbatim in the SOURCE LANGUAGE. Proper nouns such as Paris/Tokyo may
                remain unchanged when naturally required, but full question sentences must be
                written in the TARGET LANGUAGE.
                Preserve the exact meaning, option ORDER, correct-answer INDEX, image URLs,
                20-question count, selected-source relative order and all HTML/CSS structure.
                Do not translate URLs, CSS classes, HTML attributes, shortcode names or path values.
                Root `locale` MUST be `\(targetLanguage.code)`.
                Arabic MUST use RTL wrapper exactly as required by the Master Rules.
                """
            }
        } else {
            languageInstruction = ""
        }

        let prompt = """
        You are generating ONE final NAM QUIZ JSON for an automated local tool.

        \(languageInstruction)

        The MASTER RULES below are authoritative for quiz selection, source fidelity,
        language, naming, CSS, question cards, hints, ads, navigation, footer,
        results, RTL/LTR and JSON structure.

        \(retryInstruction)

        IMPORTANT FOR THIS TOOL RUN:
        - Return ONLY the final NAM QUIZ JSON object.
        - The API already enforces a JSON schema. Follow it exactly.
        - Do NOT return markdown fences.
        - Do NOT return a ZIP, QA report, audit JSON, commentary, or explanations.
        - The local app will perform QA and API mapping after your response.
        - SOURCE-FIDELITY:
          For same-language runs, question text, all 4 option texts/order, correctAnswer/index,
          answerParagraph/explanation and imageUrl must remain exact from EXTRACTED SOURCE.
          For cross-language runs, translate ALL human-readable quiz text while preserving
          option order, correct-answer INDEX, imageUrl, question meaning and relative order.
          NEVER leave a full question sentence in the source language.
          Never invent or substitute facts/questions.
        - Review the COMPLETE question pool before selecting the final 20.
        - Preserve selected-source relative order.
        - CRITICAL TITLE CONSISTENCY:
          Every `sub_pages[].title` for paths "1", "2", "3", "4", and "5"
          MUST be EXACTLY IDENTICAL to the root `title`.
          Never create page-specific titles such as "Questions 5–8",
          "Questions 9–12", "Results", or topic + question range.
        - `confirm.title` is separate confirmation text and is NOT part of this rule.
        - Follow the latest/current rules in the MASTER RULES.

        ===== MASTER RULES =====
        \(masterRules)

        ===== EXTRACTED SOURCE =====
        \(extractedSourceJSON)

        Return the final JSON object now.
        """

        let pageSchema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "propertyOrdering": ["title", "path", "content"],
            "properties": [
                "title": [
                    "type": "string",
                    "description": "MUST exactly equal the root title for every path 1-5. Never add question ranges or page-specific wording."
                ],
                "path": ["type": "string"],
                "content": ["type": "string"]
            ],
            "required": ["title", "path", "content"]
        ]

        let responseSchema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "propertyOrdering": [
                "locale",
                "title",
                "name",
                "description",
                "main_content",
                "confirm",
                "sub_pages"
            ],
            "properties": [
                "locale": [
                    "type": "string",
                    "description": "Lowercase locale code required by the NAM QUIZ rules."
                ],
                "title": [
                    "type": "string",
                    "description": "Final display title."
                ],
                "name": [
                    "type": "string",
                    "description": "Internal technical name. End with the target-language code: _EN, _RU, _AR, _RO, or _HR according to locale."
                ],
                "description": [
                    "type": "string",
                    "description": "Final description text/HTML required by the rules."
                ],
                "main_content": [
                    "type": "string",
                    "description": "Complete main page HTML including approved CSS and questions 1-4."
                ],
                "confirm": [
                    "type": "object",
                    "additionalProperties": false,
                    "propertyOrdering": ["title", "question", "button_text"],
                    "properties": [
                        "title": ["type": "string"],
                        "question": ["type": "string"],
                        "button_text": ["type": "string"]
                    ],
                    "required": ["title", "question", "button_text"]
                ],
                "sub_pages": [
                    "type": "array",
                    "minItems": 5,
                    "maxItems": 5,
                    "items": pageSchema
                ]
            ],
            "required": [
                "locale",
                "title",
                "name",
                "description",
                "main_content",
                "confirm",
                "sub_pages"
            ]
        ]

        let generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "responseJsonSchema": responseSchema,
            "temperature": 0.1,
            "maxOutputTokens": 65536
        ]

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            request.timeoutInterval = 300

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }

                let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(
                        GeminiAPIError.badStatus(http.statusCode, String(rawBody.prefix(2500)))
                    ))
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let first = candidates.first else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }

                let finishReason = first["finishReason"] as? String ?? "UNKNOWN"

                guard let content = first["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }

                let output = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(GeminiAPIError.emptyOutput))
                    return
                }

                let usage = json["usageMetadata"] as? [String: Any] ?? [:]
                let promptTokens = Self.intValue(usage["promptTokenCount"])
                let outputTokens =
                    Self.intValue(usage["candidatesTokenCount"]) > 0
                    ? Self.intValue(usage["candidatesTokenCount"])
                    : Self.intValue(usage["outputTokenCount"])
                let totalTokens = Self.intValue(usage["totalTokenCount"])

                completion(.success(
                    GeminiGenerationResult(
                        text: output,
                        finishReason: finishReason,
                        promptTokenCount: promptTokens,
                        outputTokenCount: outputTokens,
                        totalTokenCount: totalTokens,
                        rawAPIResponse: rawBody
                    )
                ))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func translateLandingQuestionBatch(
        cards: [LandingQuestionTranslationInput],
        sourceLanguage: String,
        targetLanguage: CampaignLanguage,
        attempt: Int,
        completion: @escaping (
            Result<GeminiLandingQuestionBatchResponse, Error>
        ) -> Void
    ) {
        guard let apiKey =
                GeminiConfig.shared.apiKey,
              !apiKey
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty else {
            completion(
                .failure(
                    GeminiAPIError.missingAPIKey
                )
            )
            return
        }

        let model =
            GeminiConfig.shared.model

        guard let encodedModel =
                model.addingPercentEncoding(
                    withAllowedCharacters:
                        .urlPathAllowed
                ),
              let url =
                URL(
                    string:
                        "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent"
                ) else {
            completion(
                .failure(
                    GeminiAPIError.invalidURL
                )
            )
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]

        guard let cardData =
                try? encoder.encode(cards),
              let cardJSON =
                String(
                    data: cardData,
                    encoding: .utf8
                ) else {
            completion(
                .failure(
                    GeminiAPIError.invalidResponse
                )
            )
            return
        }

        let retryInstruction =
            attempt > 1
            ? """
              RETRY \(attempt):
              The previous batch translation was rejected.
              Translate EVERY question and explanation fully.
              Never copy a full source-language sentence unchanged.
              Keep exactly 4 options in exactly the same order.
              """
            : ""

        let prompt = """
        Translate this SMALL quiz batch from \(sourceLanguage) or mixed source text
        into \(targetLanguage.displayName).

        \(retryInstruction)

        RULES:
        - Return exactly one translation for every input `index`.
        - Keep the same indexes.
        - Keep exactly 4 options per question and preserve option ORDER.
        - Preserve factual meaning and the correct-answer position indirectly by
          preserving option order.
        - Translate question, explanation and hint completely.
        - Translate linguistic option text; proper nouns may naturally stay unchanged.
        - Do not add facts, do not remove details, do not reorder options.
        - For Arabic use natural Arabic RTL text.
        - Return ONLY the schema JSON.

        INPUT:
        \(cardJSON)
        """

        let translationSchema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "propertyOrdering": [
                "index",
                "question",
                "options",
                "explanation",
                "hint"
            ],
            "properties": [
                "index": [
                    "type": "integer"
                ],
                "question": [
                    "type": "string"
                ],
                "options": [
                    "type": "array",
                    "minItems": 4,
                    "maxItems": 4,
                    "items": [
                        "type": "string"
                    ]
                ],
                "explanation": [
                    "type": "string"
                ],
                "hint": [
                    "type": "string"
                ]
            ],
            "required": [
                "index",
                "question",
                "options",
                "explanation",
                "hint"
            ]
        ]

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "propertyOrdering": [
                "translations"
            ],
            "properties": [
                "translations": [
                    "type": "array",
                    "minItems": cards.count,
                    "maxItems": cards.count,
                    "items": translationSchema
                ]
            ],
            "required": [
                "translations"
            ]
        ]

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [[
                    "text": prompt
                ]]
            ]],
            "generationConfig": [
                "responseMimeType":
                    "application/json",
                "responseJsonSchema":
                    schema,
                "temperature": 0.05,
                "maxOutputTokens": 8192
            ]
        ]

        do {
            let bodyData =
                try JSONSerialization.data(
                    withJSONObject: body
                )

            var request =
                URLRequest(
                    url: url
                )

            request.httpMethod = "POST"
            request.setValue(
                apiKey,
                forHTTPHeaderField:
                    "x-goog-api-key"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField:
                    "Content-Type"
            )
            request.httpBody = bodyData
            request.timeoutInterval = 150

            URLSession.shared
                .dataTask(
                    with: request
                ) {
                    data,
                    response,
                    error in

                    if let error {
                        completion(
                            .failure(error)
                        )
                        return
                    }

                    guard let http =
                            response
                                as? HTTPURLResponse else {
                        completion(
                            .failure(
                                GeminiAPIError
                                    .invalidResponse
                            )
                        )
                        return
                    }

                    let raw =
                        data.flatMap {
                            String(
                                data: $0,
                                encoding: .utf8
                            )
                        } ?? ""

                    guard (200...299)
                        .contains(
                            http.statusCode
                        ) else {
                        completion(
                            .failure(
                                GeminiAPIError
                                    .badStatus(
                                        http.statusCode,
                                        String(
                                            raw.prefix(
                                                1800
                                            )
                                        )
                                    )
                            )
                        )
                        return
                    }

                    guard let data,
                          let json =
                            try? JSONSerialization
                                .jsonObject(
                                    with: data
                                )
                                as? [String: Any],
                          let candidates =
                            json["candidates"]
                                as? [[String: Any]],
                          let first =
                            candidates.first,
                          let content =
                            first["content"]
                                as? [String: Any],
                          let parts =
                            content["parts"]
                                as? [[String: Any]] else {
                        completion(
                            .failure(
                                GeminiAPIError
                                    .invalidResponse
                            )
                        )
                        return
                    }

                    let output =
                        parts.compactMap {
                            $0["text"] as? String
                        }
                        .joined()

                    guard let outputData =
                            output.data(
                                using: .utf8
                            ),
                          let decoded =
                            try? JSONDecoder()
                                .decode(
                                    GeminiLandingQuestionBatchResponse.self,
                                    from: outputData
                                ) else {
                        completion(
                            .failure(
                                GeminiAPIError
                                    .invalidResponse
                            )
                        )
                        return
                    }

                    completion(
                        .success(decoded)
                    )
                }
                .resume()

        } catch {
            completion(
                .failure(error)
            )
        }
    }

    func translateAdCopy(
        primaryText: String,
        headline: String,
        descriptionText: String,
        targetLanguage: CampaignLanguage,
        completion: @escaping (Result<GeminiLocalizedAdCopy, Error>) -> Void
    ) {
        guard let apiKey = GeminiConfig.shared.apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(GeminiAPIError.missingAPIKey))
            return
        }

        let model = GeminiConfig.shared.model
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            completion(.failure(GeminiAPIError.invalidURL))
            return
        }

        let prompt = """
        Translate this Facebook ad copy into \(targetLanguage.displayName).
        Preserve meaning, persuasion level and punctuation. Do not add claims.
        Return ONLY the structured JSON fields requested by the schema.

        Primary Text: \(primaryText)
        Headline: \(headline)
        Description: \(descriptionText)
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "propertyOrdering": ["primaryText", "headline", "descriptionText"],
            "properties": [
                "primaryText": ["type": "string"],
                "headline": ["type": "string"],
                "descriptionText": ["type": "string"]
            ],
            "required": ["primaryText", "headline", "descriptionText"]
        ]

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseJsonSchema": schema,
                "temperature": 0.1,
                "maxOutputTokens": 2048
            ]
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            request.timeoutInterval = 120

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(GeminiAPIError.badStatus(http.statusCode, String(raw.prefix(1800)))))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let first = candidates.first,
                      let content = first["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }
                let output = parts.compactMap { $0["text"] as? String }.joined()
                guard let outputData = output.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(GeminiLocalizedAdCopy.self, from: outputData) else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }
                completion(.success(decoded))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    func localizeCreativeImage(
        fileURL: URL,
        sourceLanguage: String,
        targetLanguage: CampaignLanguage,
        completion: @escaping (Result<GeminiLocalizedImageResult, Error>) -> Void
    ) {
        guard let apiKey = GeminiConfig.shared.apiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(GeminiAPIError.missingAPIKey))
            return
        }

        let model = GeminiConfig.shared.imageModel
        guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            completion(.failure(GeminiAPIError.invalidURL))
            return
        }

        do {
            let imageData = try Data(contentsOf: fileURL)
            let mime = Self.imageMimeType(fileURL.pathExtension)
            let base64 = imageData.base64EncodedString()

            let prompt = """
            Edit the supplied Facebook quiz creative into \(targetLanguage.displayName).
            SOURCE LANGUAGE: \(sourceLanguage).
            Translate ALL visible human-readable text in the image into \(targetLanguage.displayName).
            Preserve the original composition, crop, people/objects, colors, typography hierarchy,
            visual style, CTA placement and overall design as closely as possible.
            Do not invent new marketing claims. Do not add or remove visual objects unless necessary
            to fit the translated text. Keep the final image square (1:1).
            For Arabic, render Arabic text naturally right-to-left.
            Return the edited image only.
            """

            let body: [String: Any] = [
                "contents": [[
                    "role": "user",
                    "parts": [
                        [
                            "inlineData": [
                                "mimeType": mime,
                                "data": base64
                            ]
                        ],
                        ["text": prompt]
                    ]
                ]],
                "generationConfig": [
                    "responseModalities": ["TEXT", "IMAGE"],
                    "imageConfig": [
                        "aspectRatio": "1:1",
                        "imageSize": "2K"
                    ]
                ]
            ]

            let bodyData = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            request.timeoutInterval = 300

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                guard (200...299).contains(http.statusCode) else {
                    completion(.failure(GeminiAPIError.badStatus(http.statusCode, String(raw.prefix(2000)))))
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]] else {
                    completion(.failure(GeminiAPIError.invalidResponse))
                    return
                }

                for candidate in candidates {
                    guard let content = candidate["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]] else {
                        continue
                    }
                    for part in parts {
                        let inline = (part["inlineData"] as? [String: Any]) ??
                            (part["inline_data"] as? [String: Any])
                        guard let inline,
                              let encoded = inline["data"] as? String,
                              let decoded = Data(base64Encoded: encoded),
                              !decoded.isEmpty else {
                            continue
                        }
                        let outputMime = (inline["mimeType"] as? String) ??
                            (inline["mime_type"] as? String) ?? "image/png"
                        completion(.success(
                            GeminiLocalizedImageResult(
                                data: decoded,
                                mimeType: outputMime,
                                model: model
                            )
                        ))
                        return
                    }
                }

                completion(.failure(GeminiAPIError.emptyOutput))
            }.resume()
        } catch {
            completion(.failure(error))
        }
    }

    private static func imageMimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "image/png"
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }
}
