import Foundation

struct MultilingualPreparationFailure {
    let recordName: String
    let language: CampaignLanguage
    let message: String
}

struct MultilingualPreparationResult {
    let records: [CampaignRecord]
    let failures: [MultilingualPreparationFailure]
}

final class MultilingualPreparationService {
    private let dataSource: CampaignDataSource
    private let gemini: GeminiAPIClient
    private let parser = SourceViewParser()

    init(
        dataSource: CampaignDataSource,
        gemini: GeminiAPIClient = GeminiAPIClient()
    ) {
        self.dataSource = dataSource
        self.gemini = gemini
    }

    func prepare(
        baseRecords: [CampaignRecord],
        targetLanguages: Set<CampaignLanguage>,
        onLog: @escaping (String) -> Void,
        completion: @escaping (MultilingualPreparationResult) -> Void
    ) {
        let queue = DispatchQueue(
            label: "local.ethopex.multilingual.prepare",
            qos: .userInitiated
        )

        queue.async {
            var prepared: [CampaignRecord] = []
            var failures: [MultilingualPreparationFailure] = []
            var seenRoots = Set<UUID>()

            let targets = CampaignLanguage.allCases.filter {
                targetLanguages.contains($0)
            }

            for selected in baseRecords {
                let initialRoot = self.dataSource.rootRecord(for: selected)
                guard !seenRoots.contains(initialRoot.id) else {
                    continue
                }
                seenRoots.insert(initialRoot.id)

                do {
                    let parsed = try self.parser.parse(
                        fileURL: self.dataSource.sourceURL(for: initialRoot)
                    )
                    let detected = CampaignLanguage.matchingSourceLanguage(
                        parsed.sourceLanguage
                    )

                    let root: CampaignRecord
                    if let detected {
                        root = try self.dataSource.setDetectedLanguage(
                            recordID: initialRoot.id,
                            language: detected
                        ) ?? initialRoot
                    } else {
                        root = initialRoot
                    }

                    DispatchQueue.main.async {
                        let detectedLabel = detected?.shortLabel ?? parsed.sourceLanguage
                        onLog(
                            "• MULTILINGUAL SOURCE: \(root.name) " +
                            "[detected \(detectedLabel)]"
                        )
                    }

                    for target in targets {
                        do {
                            if let existing = self.dataSource.records.first(where: {
                                $0.localizationSourceID == root.id &&
                                $0.effectiveLanguageCode == target.code
                            }) {
                                if self.dataSource.validate(existing).isEmpty {
                                    prepared.append(existing)
                                    DispatchQueue.main.async {
                                        onLog(
                                            "  ✓ \(target.shortLabel): dùng variant đã có — \(existing.name)"
                                        )
                                    }
                                    continue
                                }
                            }

                            if detected == target {
                                prepared.append(root)
                                DispatchQueue.main.async {
                                    onLog(
                                        "  ✓ \(target.shortLabel): dùng dữ liệu gốc, không dịch lại Image/Ad Copy"
                                    )
                                }
                                continue
                            }

                            DispatchQueue.main.async {
                                onLog(
                                    "  • \(target.shortLabel): dịch Ad Copy..."
                                )
                            }

                            let translated = try self.translateAdCopySync(
                                record: root,
                                target: target,
                                onLog: onLog
                            )

                            DispatchQueue.main.async {
                                onLog(
                                    "  • \(target.shortLabel): tạo Image localized bằng \(GeminiConfig.shared.imageModel)..."
                                )
                            }

                            let imageResult = try self.localizeImageSync(
                                record: root,
                                sourceLanguage: parsed.sourceLanguage,
                                target: target,
                                onLog: onLog
                            )

                            let ext = Self.fileExtension(
                                for: imageResult.mimeType
                            )

                            let variant = try self.dataSource.createLanguageVariant(
                                baseRecord: root,
                                targetLanguage: target,
                                translatedPrimaryText: translated.primaryText,
                                translatedHeadline: translated.headline,
                                translatedDescription: translated.descriptionText,
                                sourceLanguageLabel: parsed.sourceLanguage,
                                localizedImageData: imageResult.data,
                                localizedImageExtension: ext
                            )

                            prepared.append(variant)

                            DispatchQueue.main.async {
                                onLog(
                                    "  ✓ \(target.shortLabel): \(variant.name) — Ad Copy + Image READY"
                                )
                            }

                        } catch {
                            failures.append(
                                MultilingualPreparationFailure(
                                    recordName: root.name,
                                    language: target,
                                    message: error.localizedDescription
                                )
                            )

                            DispatchQueue.main.async {
                                onLog(
                                    "  ✕ \(target.shortLabel) PREP FAILED — \(root.name): \(error.localizedDescription)"
                                )
                                onLog(
                                    "    → tiếp tục language kế tiếp, không hủy cả source group."
                                )
                            }
                        }
                    }

                } catch {
                    for target in targets {
                        failures.append(
                            MultilingualPreparationFailure(
                                recordName: initialRoot.name,
                                language: target,
                                message: error.localizedDescription
                            )
                        )
                    }

                    DispatchQueue.main.async {
                        onLog(
                            "  ✕ SOURCE PREP FAILED — \(initialRoot.name): \(error.localizedDescription)"
                        )
                    }
                }
            }

            let unique = Dictionary(
                prepared.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).values.sorted {
                let lhs = $0.stt ?? Int.max
                let rhs = $1.stt ?? Int.max
                if lhs == rhs {
                    return $0.createdAt < $1.createdAt
                }
                return lhs < rhs
            }

            let finalRecords = Array(unique)
            let finalFailures = failures

            DispatchQueue.main.async {
                completion(
                    MultilingualPreparationResult(
                        records: finalRecords,
                        failures: finalFailures
                    )
                )
            }
        }
    }

    private func translateAdCopySync(
        record: CampaignRecord,
        target: CampaignLanguage,
        onLog: @escaping (String) -> Void
    ) throws -> GeminiLocalizedAdCopy {
        var lastError: Error?

        for attempt in 1...3 {
            let semaphore =
                DispatchSemaphore(value: 0)

            var result:
                Result<GeminiLocalizedAdCopy, Error>?

            gemini.translateAdCopy(
                primaryText: record.primaryText,
                headline: record.headline,
                descriptionText: record.descriptionText,
                targetLanguage: target
            ) {
                result = $0
                semaphore.signal()
            }

            if semaphore.wait(
                timeout: .now() + 180
            ) == .timedOut {
                lastError = NSError(
                    domain: "EthopexMultilingual",
                    code: 7101,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Timeout khi dịch Ad Copy sang \(target.displayName)."
                    ]
                )
            } else {
                switch result {
                case .success(let copy):
                    return copy

                case .failure(let error):
                    lastError = error

                case .none:
                    lastError =
                        GeminiAPIError.invalidResponse
                }
            }

            if attempt < 3 {
                let delay: TimeInterval =
                    (lastError.map {
                        isTransientGeminiError($0)
                    } ?? false)
                    ? (attempt == 1 ? 3 : 8)
                    : (attempt == 1 ? 1.5 : 3)

                DispatchQueue.main.async {
                    onLog(
                        "    ↻ \(target.shortLabel) Ad Copy retry " +
                        "\(attempt + 1)/3 sau \(Int(delay))s"
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

    private func localizeImageSync(
        record: CampaignRecord,
        sourceLanguage: String,
        target: CampaignLanguage,
        onLog: @escaping (String) -> Void
    ) throws -> GeminiLocalizedImageResult {
        var lastError: Error?

        for attempt in 1...3 {
            let semaphore =
                DispatchSemaphore(value: 0)

            var result:
                Result<GeminiLocalizedImageResult, Error>?

            gemini.localizeCreativeImage(
                fileURL:
                    dataSource.imageURL(
                        for: record
                    ),
                sourceLanguage:
                    sourceLanguage,
                targetLanguage:
                    target
            ) {
                result = $0
                semaphore.signal()
            }

            if semaphore.wait(
                timeout: .now() + 360
            ) == .timedOut {
                lastError = NSError(
                    domain: "EthopexMultilingual",
                    code: 7102,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Timeout khi tạo Image \(target.displayName)."
                    ]
                )
            } else {
                switch result {
                case .success(let image):
                    return image

                case .failure(let error):
                    lastError = error

                case .none:
                    lastError =
                        GeminiAPIError.invalidResponse
                }
            }

            if attempt < 3 {
                let delay: TimeInterval =
                    (lastError.map {
                        isTransientGeminiError($0)
                    } ?? false)
                    ? (attempt == 1 ? 4 : 10)
                    : (attempt == 1 ? 2 : 4)

                DispatchQueue.main.async {
                    onLog(
                        "    ↻ \(target.shortLabel) Image retry " +
                        "\(attempt + 1)/3 sau \(Int(delay))s"
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

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/webp": return "webp"
        default: return "png"
        }
    }
}
