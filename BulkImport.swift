import Foundation

struct BulkImportItem {
    let contentGroupName: String
    let sourceURL: URL
    let imageURL: URL
    let primaryText: String
    let headline: String
    let descriptionText: String
    let sourceQuestionCount: Int
    let sourceLanguage: String
    let creativeFingerprint: String
    let sourceFingerprint: String
}

struct BulkImportIssue {
    let location: String
    let message: String
}

struct BulkImportScanResult {
    let items: [BulkImportItem]
    let issues: [BulkImportIssue]

    var uniqueContentGroupCount: Int {
        Set(items.map {
            BulkImportService.normalizedName($0.contentGroupName)
        }).count
    }
}

struct BulkImportPreparedResult {
    let records: [CampaignRecord]
    let createdCount: Int
    let updatedCount: Int
    let issues: [BulkImportIssue]
}

final class BulkImportService {
    private let fm = FileManager.default
    private let parser = SourceViewParser()

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp"
    ]

    // MARK: - Scan

    func scan(rootURL: URL) -> BulkImportScanResult {
        var fileGroups: [String: [String: URL]] = [:]
        var issues: [BulkImportIssue] = []

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey
        ]

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ]
        ) else {
            return BulkImportScanResult(
                items: [],
                issues: [
                    BulkImportIssue(
                        location: rootURL.path,
                        message: "Không thể đọc folder."
                    )
                ]
            )
        }

        for case let fileURL as URL in enumerator {
            let parts = fileURL.pathComponents

            if parts.contains("__MACOSX") {
                if (try? fileURL.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? fileURL.resourceValues(
                forKeys: Set(keys)
            )

            if values?.isDirectory == true {
                continue
            }

            guard values?.isRegularFile == true else {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()

            guard ext == "json" ||
                  ext == "html" ||
                  imageExtensions.contains(ext) else {
                continue
            }

            let base = fileURL
                .deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            guard !base.isEmpty else { continue }

            // Parent path is intentionally part of the key.
            // The same basename can therefore appear in many subfolders and
            // become CT1_, CT2_, CT3_... variants of ONE Content group.
            let parent = fileURL
                .deletingLastPathComponent()
                .standardizedFileURL.path

            let key =
                parent.lowercased() +
                "||" +
                base.lowercased()

            var entry = fileGroups[key] ?? [:]

            if ext == "json" || ext == "html" {
                entry[ext] = fileURL
            } else {
                // One candidate image per concrete folder+basename.
                // If several image formats exist, use a deterministic preference.
                let existing = entry["image"]
                if shouldPreferImage(
                    candidate: fileURL,
                    over: existing
                ) {
                    entry["image"] = fileURL
                }
            }

            fileGroups[key] = entry
        }

        var items: [BulkImportItem] = []

        for (_, entry) in fileGroups.sorted(
            by: { $0.key < $1.key }
        ) {
            guard let sourceURL = entry["html"],
                  let jsonURL = entry["json"],
                  let imageURL = entry["image"] else {

                let anyURL =
                    entry["html"] ??
                    entry["json"] ??
                    entry["image"]

                if let anyURL {
                    let base = anyURL
                        .deletingPathExtension()
                        .lastPathComponent

                    let missing = [
                        entry["html"] == nil ? "HTML" : nil,
                        entry["json"] == nil ? "JSON" : nil,
                        entry["image"] == nil ? "IMAGE" : nil
                    ]
                    .compactMap { $0 }
                    .joined(separator: " + ")

                    issues.append(
                        BulkImportIssue(
                            location: anyURL
                                .deletingLastPathComponent()
                                .path,
                            message:
                                "\(base): thiếu \(missing), bỏ qua."
                        )
                    )
                }

                continue
            }

            let groupName = sourceURL
                .deletingPathExtension()
                .lastPathComponent
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            do {
                let adContent = try parseAdContent(
                    jsonURL: jsonURL
                )

                // Important: Source is validated with the exact parser used by
                // Campaign Automation, not just copied blindly.
                let parsed = try parser.parse(
                    fileURL: sourceURL
                )

                guard !parsed.questions.isEmpty else {
                    throw NSError(
                        domain: "EthopexBulkImport",
                        code: 5001,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "HTML không có câu hỏi."
                        ]
                    )
                }

                let sourceFingerprint =
                    try fingerprint(
                        fileURL: sourceURL,
                        extra: groupName
                    )

                let creativeExtra = [
                    groupName,
                    adContent.primaryText,
                    adContent.headline,
                    adContent.descriptionText
                ].joined(separator: "\u{241F}")

                let creativeFingerprint =
                    try fingerprint(
                        fileURL: imageURL,
                        extra: creativeExtra
                    )

                items.append(
                    BulkImportItem(
                        contentGroupName: groupName,
                        sourceURL: sourceURL,
                        imageURL: imageURL,
                        primaryText:
                            adContent.primaryText,
                        headline:
                            adContent.headline,
                        descriptionText:
                            adContent.descriptionText,
                        sourceQuestionCount:
                            parsed.questions.count,
                        sourceLanguage:
                            parsed.sourceLanguage,
                        creativeFingerprint:
                            creativeFingerprint,
                        sourceFingerprint:
                            sourceFingerprint
                    )
                )

            } catch {
                issues.append(
                    BulkImportIssue(
                        location: sourceURL
                            .deletingLastPathComponent()
                            .path,
                        message:
                            "\(groupName): " +
                            error.localizedDescription
                    )
                )
            }
        }

        items.sort {
            let lhs = Self.normalizedName(
                $0.contentGroupName
            )
            let rhs = Self.normalizedName(
                $1.contentGroupName
            )

            if lhs == rhs {
                return $0.imageURL.path
                    .localizedCaseInsensitiveCompare(
                        $1.imageURL.path
                    ) == .orderedAscending
            }

            return lhs < rhs
        }

        return BulkImportScanResult(
            items: items,
            issues: issues
        )
    }

    // MARK: - Prepare / merge into records

    func prepare(
        scan: BulkImportScanResult,
        existingRecords: [CampaignRecord],
        recordsDirectory: URL
    ) -> BulkImportPreparedResult {
        var working = existingRecords

        working.sort {
            let lhs = $0.stt ?? Int.max
            let rhs = $1.stt ?? Int.max

            if lhs == rhs {
                return $0.createdAt < $1.createdAt
            }

            return lhs < rhs
        }

        var issues = scan.issues
        var created = 0
        var updated = 0

        // One ID/time for every genuinely NEW Creative created by this
        // successful import run. Existing exact duplicates keep their old ID.
        let currentImportBatchID = UUID().uuidString
        let currentImportedAt = Date()

        let incomingGroups = Dictionary(
            grouping: scan.items,
            by: {
                Self.normalizedName(
                    $0.contentGroupName
                )
            }
        )

        for groupKey in incomingGroups.keys.sorted() {
            guard let incoming = incomingGroups[groupKey],
                  let first = incoming.first else {
                continue
            }

            let canonicalGroupName =
                first.contentGroupName

            var claimedLegacyIDs = Set<UUID>()

            for item in incoming {
                let candidateIndex = working.firstIndex {
                    let sameGroup =
                        Self.normalizedName(
                            $0.effectiveContentGroupName
                        ) == groupKey

                    guard sameGroup else { return false }

                    if let fp = $0.creativeFingerprint,
                       !fp.isEmpty {
                        return fp ==
                            item.creativeFingerprint
                    }

                    // Migration path for an older record created before V1.6:
                    // reuse at most one fingerprint-less row in this group.
                    return !claimedLegacyIDs.contains(
                        $0.id
                    )
                }

                let existing = candidateIndex.map {
                    working[$0]
                }

                if let existing,
                   existing.creativeFingerprint == nil {
                    claimedLegacyIDs.insert(
                        existing.id
                    )
                }

                let id =
                    existing?.id ??
                    UUID()

                let dir = recordsDirectory
                    .appendingPathComponent(
                        id.uuidString,
                        isDirectory: true
                    )

                do {
                    try fm.createDirectory(
                        at: dir,
                        withIntermediateDirectories: true
                    )

                    let sourceExt =
                        item.sourceURL.pathExtension.isEmpty
                        ? "html"
                        : item.sourceURL
                            .pathExtension
                            .lowercased()

                    let imageExt =
                        item.imageURL.pathExtension.isEmpty
                        ? "jpg"
                        : item.imageURL
                            .pathExtension
                            .lowercased()

                    let sourceStoredName =
                        "source.\(sourceExt)"
                    let imageStoredName =
                        "image.\(imageExt)"

                    if let old = existing,
                       !old.sourceStoredName.isEmpty,
                       old.sourceStoredName !=
                            sourceStoredName {
                        try? fm.removeItem(
                            at: dir.appendingPathComponent(
                                old.sourceStoredName
                            )
                        )
                    }

                    if let old = existing,
                       !old.imageStoredName.isEmpty,
                       old.imageStoredName !=
                            imageStoredName {
                        try? fm.removeItem(
                            at: dir.appendingPathComponent(
                                old.imageStoredName
                            )
                        )
                    }

                    try copyReplacing(
                        item.sourceURL,
                        dir.appendingPathComponent(
                            sourceStoredName
                        )
                    )

                    try copyReplacing(
                        item.imageURL,
                        dir.appendingPathComponent(
                            imageStoredName
                        )
                    )

                    let now = Date()

                    // Temporary name; after all variants for this content group
                    // are known we assign deterministic CT1_/CT2_/... names.
                    let record = CampaignRecord(
                        id: id,
                        stt:
                            existing?.stt ??
                            (working.count + 1),
                        name:
                            existing?.name ??
                            canonicalGroupName,
                        sourceOriginalName:
                            item.sourceURL.lastPathComponent,
                        sourceStoredName:
                            sourceStoredName,
                        imageOriginalName:
                            item.imageURL.lastPathComponent,
                        imageStoredName:
                            imageStoredName,
                        primaryText:
                            item.primaryText,
                        headline:
                            item.headline,
                        descriptionText:
                            item.descriptionText,
                        contentGroupName:
                            canonicalGroupName,
                        creativeIndex:
                            existing?.creativeIndex,
                        creativeBaseName:
                            canonicalGroupName,
                        creativeFingerprint:
                            item.creativeFingerprint,
                        sourceFingerprint:
                            item.sourceFingerprint,
                        importBatchID:
                            existing?.importBatchID ??
                            currentImportBatchID,
                        importedAt:
                            existing?.importedAt ??
                            currentImportedAt,
                        languageCode:
                            existing?.languageCode ?? (CampaignLanguage.matchingSourceLanguage(item.sourceLanguage)?.code ?? "und"),
                        localizationSourceID:
                            existing?.localizationSourceID,
                        localizationSourceLanguage:
                            existing?.localizationSourceLanguage ?? item.sourceLanguage,
                        localizationGenerated:
                            existing?.localizationGenerated,
                        createdAt:
                            existing?.createdAt ?? now,
                        updatedAt:
                            now
                    )

                    if let index = candidateIndex {
                        working[index] = record
                        updated += 1
                    } else {
                        working.append(record)
                        created += 1
                    }

                } catch {
                    issues.append(
                        BulkImportIssue(
                            location:
                                item.sourceURL
                                    .deletingLastPathComponent()
                                    .path,
                            message:
                                "\(canonicalGroupName): " +
                                error.localizedDescription
                        )
                    )
                }
            }

            // Re-number ALL existing + new variants belonging to this Source.
            let groupIndices = working.indices
                .filter {
                    Self.normalizedName(
                        working[$0]
                            .effectiveContentGroupName
                    ) == groupKey
                }
                .sorted {
                    let lhs =
                        working[$0].stt ??
                        Int.max
                    let rhs =
                        working[$1].stt ??
                        Int.max

                    if lhs == rhs {
                        return working[$0].createdAt <
                            working[$1].createdAt
                    }

                    return lhs < rhs
                }

            let total = groupIndices.count

            for (
                offset,
                recordIndex
            ) in groupIndices.enumerated() {
                let creativeNumber =
                    offset + 1

                working[recordIndex]
                    .contentGroupName =
                    canonicalGroupName

                working[recordIndex]
                    .creativeBaseName =
                    canonicalGroupName

                working[recordIndex]
                    .creativeIndex =
                    creativeNumber

                // Only duplicate groups need the CT prefix.
                // A single-creative Source keeps its clean original name.
                if total > 1 {
                    working[recordIndex].name =
                        "CT\(creativeNumber)_" +
                        canonicalGroupName
                } else {
                    working[recordIndex].name =
                        canonicalGroupName
                }
            }
        }

        working.sort {
            let lhs = $0.stt ?? Int.max
            let rhs = $1.stt ?? Int.max

            if lhs == rhs {
                return $0.createdAt < $1.createdAt
            }

            return lhs < rhs
        }

        for index in working.indices {
            working[index].stt =
                index + 1
        }

        return BulkImportPreparedResult(
            records: working,
            createdCount: created,
            updatedCount: updated,
            issues: issues
        )
    }

    // MARK: - JSON / fingerprint helpers

    private func parseAdContent(
        jsonURL: URL
    ) throws -> (
        primaryText: String,
        headline: String,
        descriptionText: String
    ) {
        let data = try Data(
            contentsOf: jsonURL
        )

        guard let root =
                try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any] else {
            throw NSError(
                domain: "EthopexBulkImport",
                code: 5002,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "JSON Ads Content không hợp lệ."
                ]
            )
        }

        let primaryText =
            firstString(
                root["primaryTexts"]
            )

        let headline =
            firstString(
                root["headlines"]
            )

        let descriptionText =
            firstString(
                root["descriptions"]
            )

        guard !primaryText.isEmpty,
              !headline.isEmpty,
              !descriptionText.isEmpty else {
            throw NSError(
                domain: "EthopexBulkImport",
                code: 5003,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "JSON phải có primaryTexts, " +
                        "headlines và descriptions."
                ]
            )
        }

        return (
            primaryText,
            headline,
            descriptionText
        )
    }

    private func firstString(
        _ value: Any?
    ) -> String {
        if let array = value as? [String] {
            return array
                .first {
                    !$0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                }?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
        }

        if let text = value as? String {
            return text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        return ""
    }

    private func shouldPreferImage(
        candidate: URL,
        over existing: URL?
    ) -> Bool {
        guard let existing else {
            return true
        }

        func rank(_ url: URL) -> Int {
            switch url.pathExtension.lowercased() {
            case "jpg", "jpeg":
                return 0
            case "png":
                return 1
            case "webp":
                return 2
            default:
                return 99
            }
        }

        return rank(candidate) <
            rank(existing)
    }

    private func fingerprint(
        fileURL: URL,
        extra: String
    ) throws -> String {
        // Stable FNV-1a 64-bit fingerprint without extra frameworks.
        let data = try Data(
            contentsOf: fileURL
        )

        var hash:
            UInt64 =
            14695981039346656037

        func feed(
            _ bytes: some Sequence<UInt8>
        ) {
            for byte in bytes {
                hash ^= UInt64(byte)
                hash =
                    hash &*
                    1099511628211
            }
        }

        feed(data)

        if let extraData =
                extra.data(
                    using: .utf8
                ) {
            feed(extraData)
        }

        return String(
            format: "%016llx",
            hash
        )
    }

    private func copyReplacing(
        _ source: URL,
        _ destination: URL
    ) throws {
        if fm.fileExists(
            atPath: destination.path
        ) {
            try fm.removeItem(
                at: destination
            )
        }

        try fm.copyItem(
            at: source,
            to: destination
        )
    }

    static func normalizedName(
        _ value: String
    ) -> String {
        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ],
                locale:
                    Locale(
                        identifier:
                            "en_US_POSIX"
                    )
            )
            .lowercased()
    }
}
