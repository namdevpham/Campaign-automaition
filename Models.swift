import Foundation

struct CampaignRecord: Codable, Equatable {
    var id: UUID
    var stt: Int?
    var name: String
    var sourceOriginalName: String
    var sourceStoredName: String
    var imageOriginalName: String
    var imageStoredName: String
    var primaryText: String
    var headline: String
    var descriptionText: String

    // V1.6 — one Source/Content can own many Creative variants.
    // Optional fields keep old records.json files backward-compatible.
    var contentGroupName: String? = nil
    var creativeIndex: Int? = nil
    var creativeBaseName: String? = nil
    var creativeFingerprint: String? = nil
    var sourceFingerprint: String? = nil

    // V1.6.3 — bulk-import provenance.
    // Only genuinely NEW Creative records receive a new importBatchID.
    // Re-importing an exact existing Creative keeps its old batch metadata.
    var importBatchID: String? = nil
    var importedAt: Date? = nil

    // V1.6.4 — language layer. Existing records default to English.
    var languageCode: String? = nil

    // V1.7.0 — multilingual expansion metadata.
    // A generated language variant points back to the originally imported
    // Creative/Data record. Optional fields preserve old records.json files.
    var localizationSourceID: UUID? = nil
    var localizationSourceLanguage: String? = nil
    var localizationGenerated: Bool? = nil

    var createdAt: Date
    var updatedAt: Date

    var effectiveContentGroupName: String {
        let stored = (contentGroupName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !stored.isEmpty {
            return stored
        }

        // Migration fallback for an old/imported name like CT2_WORLD CAPITALS QUIZ.
        if let range = name.range(
            of: #"^CT[0-9]+_"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let stripped = String(name[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                return stripped
            }
        }

        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveLanguageCode: String {
        let raw = (languageCode ?? "en").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CampaignLanguage.from(code: raw).code
    }

    var localizationRootID: UUID {
        localizationSourceID ?? id
    }

    var isLocalizedVariant: Bool {
        localizationSourceID != nil || (localizationGenerated ?? false)
    }

    var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sourceStoredName.isEmpty &&
        !imageStoredName.isEmpty &&
        !primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum JobStatus: String {
    case idle = "CHƯA CHẠY"
    case queued = "QUEUED"
    case validating = "VALIDATING"
    case parsing = "PARSING SOURCE"
    case gemini = "GEMINI"
    case qa = "QA"
    case readyContent = "READY FOR CONTENT"
    case checkingContent = "CHECKING CONTENT"
    case creatingContent = "CREATING CONTENT"
    case contentDone = "CONTENT CREATED"
    case uploadingMedia = "UPLOADING IMAGE"
    case mediaDone = "IMAGE UPLOADED"
    case creatingCreative = "CREATING CREATIVE"
    case creativeDone = "CREATIVE CREATED"
    case creatingCampaign = "CREATING CAMPAIGN"
    case campaignDone = "CAMPAIGN CREATED"
    case failed = "FAILED"
    case done = "DONE"
}

struct APIResultIDs {
    var contentID: String?
    var creativeID: String?
    var campaignID: String?
    var adSetID: String?
    var adID: String?
}


enum ImportBatchHelper {
    static func latestBatchID(
        in records: [CampaignRecord]
    ) -> String? {
        records.compactMap { record -> (String, Date)? in
            guard let batchID = record.importBatchID,
                  !batchID.isEmpty,
                  let importedAt = record.importedAt else {
                return nil
            }

            return (batchID, importedAt)
        }
        .max { lhs, rhs in
            lhs.1 < rhs.1
        }?
        .0
    }

    static func isLatestImport(
        _ record: CampaignRecord,
        in records: [CampaignRecord]
    ) -> Bool {
        guard let latest = latestBatchID(in: records) else {
            return false
        }

        return record.importBatchID == latest
    }

    static func dataLabel(
        for record: CampaignRecord,
        in records: [CampaignRecord]
    ) -> String {
        let age =
            isLatestImport(record, in: records)
            ? "MỚI"
            : "CŨ"

        let readiness =
            record.isReady
            ? "READY"
            : "INCOMPLETE"

        return "\(age) • \(readiness)"
    }
}


enum CampaignLanguage: String, CaseIterable, Codable {
    case english = "en"
    case russian = "ru"
    case arabic = "ar"
    case romanian = "ro"
    case croatian = "hr"

    var code: String { rawValue }

    var shortLabel: String {
        switch self {
        case .english: return "EN"
        case .russian: return "RU"
        case .arabic: return "AR"
        case .romanian: return "RO"
        case .croatian: return "HR"
        }
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        case .arabic: return "Arabic"
        case .romanian: return "Romanian"
        case .croatian: return "Croatian"
        }
    }

    var localeInstruction: String {
        switch self {
        case .english: return "English (en)"
        case .russian: return "Russian (ru)"
        case .arabic: return "Arabic (ar), RTL"
        case .romanian: return "Romanian (ro)"
        case .croatian: return "Croatian (hr)"
        }
    }

    static func matchingSourceLanguage(_ raw: String) -> CampaignLanguage? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "en" || normalized.hasPrefix("en-") || normalized.contains("english") { return .english }
        if normalized == "ru" || normalized.hasPrefix("ru-") || normalized.contains("russian") || normalized.contains("рус") { return .russian }
        if normalized == "ar" || normalized.hasPrefix("ar-") || normalized.contains("arab") || normalized.contains("العرب") { return .arabic }
        if normalized == "ro" || normalized.hasPrefix("ro-") || normalized.contains("romanian") || normalized.contains("român") { return .romanian }
        if normalized == "hr" || normalized.hasPrefix("hr-") || normalized.contains("croatian") || normalized.contains("hrvat") { return .croatian }
        return nil
    }

    static func fromSourceLanguage(_ raw: String) -> CampaignLanguage {
        matchingSourceLanguage(raw) ?? .english
    }

    static func from(code: String) -> CampaignLanguage {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return CampaignLanguage(rawValue: normalized) ?? .english
    }
}

final class CampaignLanguageSelectionConfig {
    static let shared = CampaignLanguageSelectionConfig()
    private let defaultsKey = "campaign.selected.languages.v1"
    private init() {}

    var selected: Set<CampaignLanguage> {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
            let parsed = Set(saved.compactMap { CampaignLanguage(rawValue: $0) })
            return parsed.isEmpty ? Set(CampaignLanguage.allCases) : parsed
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: defaultsKey)
        }
    }
}


enum MultilingualRecordNaming {
    static func localizedCreativeName(
        _ rawName: String,
        language: CampaignLanguage
    ) -> String {
        var base = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        base = base.replacingOccurrences(
            of: #"(?i)_(EN|RU|AR|RO|HR)$"#,
            with: "",
            options: .regularExpression
        )
        if base.isEmpty {
            base = "Creative"
        }
        return base + "_" + language.shortLabel
    }
}


enum TechnicalNameRule {
    static func suffix(for locale: String) -> String {
        let normalized = locale
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "en", "english":
            return "EN"
        case "ru", "russian":
            return "RU"
        case "ar", "arabic":
            return "AR"
        case "ro", "romanian":
            return "RO"
        case "hr", "croatian":
            return "HR"
        default:
            let compact = normalized
                .replacingOccurrences(
                    of: #"[^a-z0-9]+"#,
                    with: "",
                    options: .regularExpression
                )

            if compact.count >= 2 {
                return String(compact.prefix(2)).uppercased()
            }

            return "EN"
        }
    }

    static func normalize(
        rawName: String,
        locale: String,
        fallbackTitle: String
    ) -> String {
        var base = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if base.isEmpty {
            base = fallbackTitle
        }

        // Remove legacy/current language suffixes before appending the
        // authoritative suffix for the JSON locale.
        base = base.replacingOccurrences(
            of: #"(?i)_(Testw1|EN|RU|AR|RO|HR|English|Russian|Arabic|Romanian|Croatian)$"#,
            with: "",
            options: .regularExpression
        )

        base = base.replacingOccurrences(
            of: #"[^A-Za-z0-9]+"#,
            with: "_",
            options: .regularExpression
        )

        base = base.replacingOccurrences(
            of: #"_+"#,
            with: "_",
            options: .regularExpression
        )

        base = base.trimmingCharacters(
            in: CharacterSet(charactersIn: "_")
        )

        if base.isEmpty {
            base = "Quiz"
        }

        return base + "_" + suffix(for: locale)
    }

    static func expectedSuffix(for locale: String) -> String {
        "_" + suffix(for: locale)
    }
}
