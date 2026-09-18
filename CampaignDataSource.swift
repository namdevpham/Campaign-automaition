import Foundation

final class CampaignDataSource {
    private(set) var records: [CampaignRecord] = []

    let baseDirectory: URL
    let recordsDirectory: URL
    let indexURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("EthopexDataManager", isDirectory: true)
        recordsDirectory = baseDirectory.appendingPathComponent("records", isDirectory: true)
        indexURL = baseDirectory.appendingPathComponent("records.json")
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        guard let data = try? Data(contentsOf: indexURL) else {
            records = []
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let decoded = try? decoder.decode([CampaignRecord].self, from: data) else {
            records = []
            return false
        }

        records = decoded.sorted {
            let lhs = $0.stt ?? 0
            let rhs = $1.stt ?? 0
            if lhs == rhs { return $0.createdAt < $1.createdAt }
            return lhs < rhs
        }
        return true
    }

    func folder(for record: CampaignRecord) -> URL {
        recordsDirectory.appendingPathComponent(record.id.uuidString, isDirectory: true)
    }

    func sourceURL(for record: CampaignRecord) -> URL {
        folder(for: record).appendingPathComponent(record.sourceStoredName)
    }

    func imageURL(for record: CampaignRecord) -> URL {
        folder(for: record).appendingPathComponent(record.imageStoredName)
    }

    private func persistRecords() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    private func renumberSequentially() {
        records.sort {
            let lhs = $0.stt ?? Int.max
            let rhs = $1.stt ?? Int.max
            if lhs == rhs {
                return $0.createdAt < $1.createdAt
            }
            return lhs < rhs
        }

        for index in records.indices {
            records[index].stt = index + 1
        }
    }

    func rootRecord(for record: CampaignRecord) -> CampaignRecord {
        guard let sourceID = record.localizationSourceID else {
            return record
        }

        return records.first(where: { $0.id == sourceID }) ?? record
    }

    func languageVariant(
        rootID: UUID,
        language: CampaignLanguage
    ) -> CampaignRecord? {
        if let generated = records.first(where: { record in
            record.localizationSourceID == rootID &&
            record.effectiveLanguageCode == language.code
        }) {
            return generated
        }

        return records.first { record in
            record.id == rootID &&
            record.localizationSourceID == nil &&
            (record.languageCode ?? "").lowercased() == language.code
        }
    }

    @discardableResult
    func setDetectedLanguage(
        recordID: UUID,
        language: CampaignLanguage
    ) throws -> CampaignRecord? {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return nil
        }

        records[index].languageCode = language.code
        records[index].localizationSourceLanguage = language.code
        records[index].updatedAt = Date()
        try persistRecords()
        return records[index]
    }

    func createLanguageVariant(
        baseRecord: CampaignRecord,
        targetLanguage: CampaignLanguage,
        translatedPrimaryText: String,
        translatedHeadline: String,
        translatedDescription: String,
        sourceLanguageLabel: String,
        localizedImageData: Data,
        localizedImageExtension: String
    ) throws -> CampaignRecord {
        let root = rootRecord(for: baseRecord)

        if let existing = records.first(where: { record in
            record.localizationSourceID == root.id &&
            record.effectiveLanguageCode == targetLanguage.code
        }) {
            return existing
        }

        let fm = FileManager.default
        let id = UUID()
        let now = Date()
        let destination = recordsDirectory
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        let sourceFrom = sourceURL(for: root)
        let sourceStoredName = root.sourceStoredName.isEmpty
            ? "source.html"
            : root.sourceStoredName
        let sourceTo = destination.appendingPathComponent(sourceStoredName)
        try fm.copyItem(at: sourceFrom, to: sourceTo)

        let cleanExtension = localizedImageExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let imageExtension = cleanExtension.isEmpty ? "png" : cleanExtension
        let imageStoredName = "image_\(targetLanguage.shortLabel.lowercased()).\(imageExtension)"
        let imageTo = destination.appendingPathComponent(imageStoredName)
        try localizedImageData.write(to: imageTo, options: .atomic)

        let localizedName = MultilingualRecordNaming.localizedCreativeName(
            root.name,
            language: targetLanguage
        )

        let variant = CampaignRecord(
            id: id,
            stt: records.count + 1,
            name: localizedName,
            sourceOriginalName: root.sourceOriginalName,
            sourceStoredName: sourceStoredName,
            imageOriginalName: localizedName + "." + imageExtension,
            imageStoredName: imageStoredName,
            primaryText: translatedPrimaryText,
            headline: translatedHeadline,
            descriptionText: translatedDescription,
            contentGroupName: root.effectiveContentGroupName,
            creativeIndex: root.creativeIndex,
            creativeBaseName: root.creativeBaseName,
            creativeFingerprint: (root.creativeFingerprint ?? root.id.uuidString) + "||" + targetLanguage.code,
            sourceFingerprint: root.sourceFingerprint,
            importBatchID: root.importBatchID,
            importedAt: root.importedAt,
            languageCode: targetLanguage.code,
            localizationSourceID: root.id,
            localizationSourceLanguage: sourceLanguageLabel,
            localizationGenerated: true,
            createdAt: now,
            updatedAt: now
        )

        records.append(variant)
        renumberSequentially()
        try persistRecords()
        return records.first(where: { $0.id == id }) ?? variant
    }

    func replaceLanguageVariantImage(
        recordID: UUID,
        imageData: Data,
        fileExtension: String
    ) throws {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }

        let ext = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let finalExt = ext.isEmpty ? "png" : ext
        let filename = "image_\(records[index].effectiveLanguageCode).\(finalExt)"
        let folderURL = folder(for: records[index])
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        let target = folderURL.appendingPathComponent(filename)
        try imageData.write(to: target, options: .atomic)
        records[index].imageStoredName = filename
        records[index].imageOriginalName = filename
        records[index].updatedAt = Date()
        try persistRecords()
    }

    func validate(_ record: CampaignRecord) -> [String] {
        var errors: [String] = []

        if !record.isReady {
            errors.append("Record chưa ở trạng thái READY")
        }

        let fm = FileManager.default
        let source = sourceURL(for: record)
        let image = imageURL(for: record)

        if !fm.fileExists(atPath: source.path) {
            errors.append("Không tìm thấy Source View: \(source.lastPathComponent)")
        }

        if !fm.fileExists(atPath: image.path) {
            errors.append("Không tìm thấy Image: \(image.lastPathComponent)")
        }

        if record.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Thiếu Primary Text")
        }
        if record.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Thiếu Headline")
        }
        if record.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Thiếu Description")
        }

        return errors
    }
}
