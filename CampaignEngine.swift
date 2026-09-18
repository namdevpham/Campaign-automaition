import Foundation

final class CampaignEngine {
    let dataSource: CampaignDataSource
    let api: EthopexAPIClient
    let gemini = GeminiAPIClient()
    let builder = PipelineFileBuilder()
    let qa = QuizQAValidator()
    let stateStore = IntegrationStateStore()

    init(dataSource: CampaignDataSource, api: EthopexAPIClient) {
        self.dataSource = dataSource
        self.api = api
    }


    private struct SelectedContentGroup {
        let key: String
        let owner: CampaignRecord
        let selectedMembers: [CampaignRecord]
        let allMembers: [CampaignRecord]
    }

    private func normalizedContentKey(
        _ record: CampaignRecord
    ) -> String {
        let sourceKey = BulkImportService.normalizedName(
            record.effectiveContentGroupName
        )
        return sourceKey + "||" + record.effectiveLanguageCode
    }

    private func selectedContentGroups(
        _ selected: [CampaignRecord]
    ) -> [SelectedContentGroup] {
        var result: [SelectedContentGroup] = []
        var seen = Set<String>()

        for selectedRecord in selected {
            let key =
                normalizedContentKey(
                    selectedRecord
                )

            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)

            let selectedMembers =
                selected.filter {
                    self.normalizedContentKey(
                        $0
                    ) == key
                }

            var allMembers =
                dataSource.records.filter {
                    self.normalizedContentKey(
                        $0
                    ) == key
                }

            if allMembers.isEmpty {
                allMembers =
                    selectedMembers
            }

            allMembers.sort {
                let lhs =
                    $0.stt ?? Int.max
                let rhs =
                    $1.stt ?? Int.max

                if lhs == rhs {
                    return $0.createdAt <
                        $1.createdAt
                }

                return lhs < rhs
            }

            guard let owner =
                    allMembers.first ??
                    selectedMembers.first else {
                continue
            }

            result.append(
                SelectedContentGroup(
                    key: key,
                    owner: owner,
                    selectedMembers:
                        selectedMembers,
                    allMembers:
                        allMembers
                )
            )
        }

        return result
    }

    private func ownerStatusForwarder(
        groups: [SelectedContentGroup],
        downstream:
            @escaping (
                UUID,
                JobStatus
            ) -> Void
    ) -> (
        UUID,
        JobStatus
    ) -> Void {
        let map = Dictionary(
            uniqueKeysWithValues:
                groups.map {
                    (
                        $0.owner.id,
                        $0.selectedMembers.map(
                            \.id
                        )
                    )
                }
        )

        return {
            ownerID,
            status in

            let targets =
                map[ownerID] ??
                [ownerID]

            for id in targets {
                downstream(
                    id,
                    status
                )
            }
        }
    }

    private func copyFileIfPresent(
        named name: String,
        from sourceFolder: URL,
        to targetFolder: URL
    ) throws {
        let fm =
            FileManager.default

        let source =
            sourceFolder.appendingPathComponent(
                name
            )

        guard fm.fileExists(
            atPath: source.path
        ) else {
            return
        }

        try fm.createDirectory(
            at: targetFolder,
            withIntermediateDirectories: true
        )

        let target =
            targetFolder.appendingPathComponent(
                name
            )

        if fm.fileExists(
            atPath: target.path
        ) {
            try fm.removeItem(
                at: target
            )
        }

        try fm.copyItem(
            at: source,
            to: target
        )
    }

    private func syncPreparedContentFromOwner(
        group: SelectedContentGroup
    ) throws {
        let ownerFolder =
            dataSource.folder(
                for: group.owner
            )

        let ownerState =
            stateStore.load(
                folder: ownerFolder,
                record: group.owner
            )

        guard ownerState.qaPassed else {
            return
        }

        let sharedFiles = [
            "extracted_source.json",
            "generated_content.json",
            "source_fidelity_report.txt",
            "qa_report.txt",
            "ethopex_content_payload.json"
        ]

        for member in group.allMembers
        where member.id != group.owner.id {
            let folder =
                dataSource.folder(
                    for: member
                )

            for name in sharedFiles {
                try copyFileIfPresent(
                    named: name,
                    from: ownerFolder,
                    to: folder
                )
            }

            var state =
                stateStore.load(
                    folder: folder,
                    record: member
                )

            state.parsed =
                ownerState.parsed
            state.geminiGenerated =
                ownerState.geminiGenerated
            state.qaPassed =
                ownerState.qaPassed
            state.selectedSourcePositions =
                ownerState
                    .selectedSourcePositions

            if state.lastError?.hasPrefix(
                "QA FAIL"
            ) == true {
                state.lastError = nil
            }

            try stateStore.save(
                state,
                folder: folder
            )
        }
    }

    private func syncRemoteContentFromOwner(
        group: SelectedContentGroup
    ) throws {
        let ownerFolder =
            dataSource.folder(
                for: group.owner
            )

        let ownerState =
            stateStore.load(
                folder: ownerFolder,
                record: group.owner
            )

        guard ownerState.contentCreated,
              let sharedContentID =
                ownerState.contentID,
              !sharedContentID.isEmpty else {
            return
        }

        // Creative/Campaign needs generated_content.json in each creative folder.
        try syncPreparedContentFromOwner(
            group: group
        )

        let responseFiles = [
            "ethopex_cover_asset_response.json",
            "ethopex_content_response.json"
        ]

        for member in group.allMembers
        where member.id != group.owner.id {
            let folder =
                dataSource.folder(
                    for: member
                )

            for name in responseFiles {
                try copyFileIfPresent(
                    named: name,
                    from: ownerFolder,
                    to: folder
                )
            }

            var state =
                stateStore.load(
                    folder: folder,
                    record: member
                )

            let previousContentID =
                state.contentID

            let changed =
                previousContentID != nil &&
                previousContentID !=
                    sharedContentID

            state.contentCreated =
                true
            state.groupID =
                ownerState.groupID
            state.contentID =
                sharedContentID

            if changed {
                // This variant was built against an older duplicated Content.
                // Keep uploaded media cache, but recreate Creative + Campaign
                // against the one canonical shared content_id.
                state.creativePayloadPrepared =
                    false
                state.creativeCreated =
                    false
                state.creativeID =
                    nil
                state.creativeBlocker =
                    nil

                state.campaignID =
                    nil
                state.adSetID =
                    nil
                state.adID =
                    nil
                state.campaignTemplateName =
                    nil
                state.campaignPageInternalID =
                    nil
                state.campaignPageExternalID =
                    nil
                state.campaignPageName =
                    nil
            }

            state.lastError =
                nil

            try stateStore.save(
                state,
                folder: folder
            )
        }
    }

    // Public TEST PIPELINE:
    // One Gemini/QA/content-payload preparation per unique Source name.
    func testPipeline(
        records: [CampaignRecord],
        onStatus:
            @escaping (
                UUID,
                JobStatus
            ) -> Void,
        onLog:
            @escaping (String) -> Void,
        completion:
            @escaping () -> Void
    ) {
        let groups =
            selectedContentGroups(
                records
            )

        let owners =
            groups.map(
                \.owner
            )

        let forwardedStatus =
            ownerStatusForwarder(
                groups: groups,
                downstream: onStatus
            )

        testPipelinePerContentOwner(
            records: owners,
            onStatus:
                forwardedStatus,
            onLog: onLog
        ) { [weak self] in
            guard let self else {
                completion()
                return
            }

            for group in groups {
                do {
                    try self
                        .syncPreparedContentFromOwner(
                            group: group
                        )

                    if group.allMembers.count > 1 {
                        self.ui {
                            onLog(
                                "  ♻ SOURCE GROUP '\(group.owner.effectiveContentGroupName)': " +
                                "1 Landing Content preparation → " +
                                "\(group.allMembers.count) Creative variants"
                            )
                        }
                    }

                } catch {
                    self.ui {
                        onLog(
                            "  ⚠ Không sync được Content preparation: " +
                            error.localizedDescription
                        )
                    }
                }
            }

            completion()
        }
    }

    // Public CREATE CONTENT:
    // Only owners hit Ethopex Content API. The returned content_id is copied
    // to every Creative variant in that Source group.
    func createContentReal(
        records: [CampaignRecord],
        onStatus:
            @escaping (
                UUID,
                JobStatus
            ) -> Void,
        onLog:
            @escaping (String) -> Void,
        completion:
            @escaping () -> Void
    ) {
        let groups =
            selectedContentGroups(
                records
            )

        let owners =
            groups.map(
                \.owner
            )

        let forwardedStatus =
            ownerStatusForwarder(
                groups: groups,
                downstream: onStatus
            )

        createContentRealPerContentOwner(
            records: owners,
            onStatus:
                forwardedStatus,
            onLog: onLog
        ) { [weak self] in
            guard let self else {
                completion()
                return
            }

            for group in groups {
                do {
                    try self
                        .syncRemoteContentFromOwner(
                            group: group
                        )

                    let ownerFolder =
                        self.dataSource.folder(
                            for: group.owner
                        )

                    let ownerState =
                        self.stateStore.load(
                            folder: ownerFolder,
                            record: group.owner
                        )

                    if let contentID =
                            ownerState.contentID,
                       ownerState.contentCreated {
                        self.ui {
                            onLog(
                                "  ♻ SHARED CONTENT: " +
                                "\(group.owner.effectiveContentGroupName)"
                            )
                            onLog(
                                "    content_id: \(contentID)"
                            )
                            onLog(
                                "    Creative variants dùng chung: " +
                                "\(group.allMembers.count)"
                            )
                            onLog("")
                        }
                    }

                } catch {
                    self.ui {
                        onLog(
                            "  ⚠ Không sync được shared content_id: " +
                            error.localizedDescription
                        )
                    }
                }
            }

            completion()
        }
    }

    func persistedStatus(for record: CampaignRecord) -> JobStatus? {
        let folder = dataSource.folder(for: record)
        let state = stateStore.load(folder: folder, record: record)

        if state.creativeCreated {
            return .creativeDone
        }
        if state.uploadedImageURL != nil && state.contentCreated {
            return .mediaDone
        }
        if state.contentCreated {
            return .contentDone
        }
        if state.qaPassed {
            return .readyContent
        }
        if state.lastError != nil {
            return .failed
        }
        return nil
    }

    private func testPipelinePerContentOwner(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let queue = DispatchQueue(label: "local.ethopex.pipeline.test", qos: .userInitiated)

        queue.async {
            for (index, record) in records.enumerated() {
                let folder = self.dataSource.folder(for: record)
                var state = self.stateStore.load(folder: folder, record: record)
                state.lastError = nil

                self.ui {
                    onStatus(record.id, .queued)
                    onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                    onLog("  → QUEUED")
                }

                let validationErrors = self.dataSource.validate(record)
                if !validationErrors.isEmpty {
                    state.lastError = validationErrors.joined(separator: "; ")
                    try? self.stateStore.save(state, folder: folder)
                    self.ui {
                        onStatus(record.id, .failed)
                        onLog("  ✕ DATA VALIDATION FAILED")
                        validationErrors.forEach { onLog("    - \($0)") }
                        onLog("")
                    }
                    continue
                }

                do {
                    self.ui {
                        onStatus(record.id, .parsing)
                        onLog("  • Parse Source View...")
                    }

                    let parser = SourceViewParser()
                    let parsed = try parser.parse(fileURL: self.dataSource.sourceURL(for: record))
                    let targetLanguage = CampaignLanguage.from(code: record.effectiveLanguageCode)
                    let sourceLanguage = CampaignLanguage.matchingSourceLanguage(parsed.sourceLanguage)
                    let isCrossLanguage = sourceLanguage != Optional(targetLanguage)

                    _ = try parser.saveExtracted(parsed, to: folder)
                    state.parsed = true
                    try self.stateStore.save(state, folder: folder)

                    self.ui {
                        onLog("  ✓ Quiz ID: \(parsed.quizId)")
                        onLog("  ✓ Title: \(parsed.quizName)")
                        onLog("  ✓ Source language: \(parsed.sourceLanguage)")
                        onLog("  ✓ Target language: \(targetLanguage.shortLabel)")
                        if isCrossLanguage {
                            onLog("  ✓ Translation mode: FULL LANDING PAGE")
                        }
                        onLog("  ✓ Quiz type: \(parsed.quizType)")
                        onLog("  ✓ Source questions: \(parsed.sourceQuestionCount)")
                    }

                    let generatedURL = folder.appendingPathComponent("generated_content.json")
                    var generatedJSON: String
                    var fidelityResult: SourceFidelityRepairResult?

                    // V1.7.1 — old multilingual caches may have passed the weaker
                    // V1.7.0 QA while still containing source-language/English questions.
                    // Re-validate them with the strict Language Guard before reusing cache.
                    if isCrossLanguage,
                       state.qaPassed,
                       FileManager.default.fileExists(atPath: generatedURL.path),
                       let cached = try? String(contentsOf: generatedURL, encoding: .utf8) {
                        do {
                            let canonicalCache = try self.builder.canonicalizeGeminiJSON(cached)
                            let cacheLanguageQA = self.qa.validateLocalized(
                                jsonText: canonicalCache,
                                expectedLanguage: targetLanguage,
                                source: parsed
                            )

                            if !cacheLanguageQA.passed {
                                state.qaPassed = false
                                state.geminiGenerated = false
                                state.lastError = nil
                                try self.stateStore.save(state, folder: folder)

                                self.ui {
                                    onLog("  ⚠ LOCALIZED CACHE INVALIDATED [\(targetLanguage.shortLabel)]")
                                    onLog("    → phát hiện landing còn text sai ngôn ngữ / QA cũ chưa đủ chặt")
                                    cacheLanguageQA.issues.prefix(4).forEach { onLog("    - \($0)") }
                                    onLog("    → tự gọi Gemini lại trong cùng lượt chạy")
                                }
                            }
                        } catch {
                            state.qaPassed = false
                            state.geminiGenerated = false
                            state.lastError = nil
                            try? self.stateStore.save(state, folder: folder)
                            self.ui {
                                onLog("  ⚠ LOCALIZED CACHE INVALIDATED: \(error.localizedDescription)")
                                onLog("    → tự regenerate")
                            }
                        }
                    }

                    // Only trust cached generated JSON after it has already passed QA.
                    // If a previous run failed QA/JSON parsing, regenerate automatically.
                    if state.qaPassed,
                       FileManager.default.fileExists(atPath: generatedURL.path),
                       let cached = try? String(contentsOf: generatedURL, encoding: .utf8) {
                        // V0.11 migrates older cache locally without calling Gemini again.
                        let canonicalCache = try self.builder.canonicalizeGeminiJSON(cached)

                        if isCrossLanguage {
                            generatedJSON = canonicalCache
                            fidelityResult = nil
                            _ = try self.builder.saveGeneratedJSON(generatedJSON, folder: folder)
                            self.ui {
                                onLog("  ✓ Localized cache: \(targetLanguage.shortLabel)")
                                onLog("  ✓ Translation QA sẽ chạy lại")
                                onLog("  ✓ Không tốn thêm Gemini quota")
                            }
                        } else {
                            let lockedCache = try self.builder.enforceSourceFidelity(
                                jsonText: canonicalCache,
                                source: parsed
                            )
                            generatedJSON = lockedCache.jsonText
                            fidelityResult = lockedCache
                            _ = try self.builder.saveGeneratedJSON(generatedJSON, folder: folder)
                            _ = try self.builder.saveSourceFidelityReport(
                                lockedCache,
                                folder: folder
                            )
                            self.ui {
                                onLog("  ✓ Cache cũ đã chuẩn hóa Title = root title trên paths 1–5")
                                onLog("  ✓ Source Fidelity Lock đã chạy lại trên cache")
                                onLog("  ✓ Không tốn thêm Gemini quota")
                            }
                        }
                    } else {
                        self.ui {
                            onStatus(record.id, .gemini)
                            onLog("  • Gemini Structured Output...")
                            onLog("    Model: \(GeminiConfig.shared.model)")
                            onLog("    JSON Schema: ENABLED")
                            onLog("    Max output tokens: 65536")
                        }

                        let rules = try self.builder.masterRules()
                        let extracted = try self.builder.extractedSourceJSON(parsed)

                        var successfulJSON: String?
                        var finalGenerationError: Error?
                        let landingRepairer =
                            LandingBatchTranslationRepairer(
                                gemini: self.gemini
                            )

                        for attempt in 1...2 {
                            self.ui {
                                onLog("  • Gemini attempt \(attempt)/2...")
                            }

                            let semaphore = DispatchSemaphore(value: 0)
                            var aiResult: Result<GeminiGenerationResult, Error>?

                            self.gemini.generateNAMQuiz(
                                masterRules: rules,
                                extractedSourceJSON: extracted,
                                targetLanguage: targetLanguage,
                                sourceLanguage: parsed.sourceLanguage,
                                attempt: attempt
                            ) { result in
                                aiResult = result
                                semaphore.signal()
                            }

                            if semaphore.wait(timeout: .now() + 360) == .timedOut {
                                finalGenerationError = NSError(
                                    domain: "EthopexCampaignTool",
                                    code: 1001,
                                    userInfo: [NSLocalizedDescriptionKey:
                                        "Gemini timeout sau 360 giây ở attempt \(attempt)."
                                    ]
                                )
                                self.ui {
                                    onLog("    ✕ Timeout")
                                }
                                continue
                            }

                            switch aiResult {
                            case .success(let generation):
                                self.builder.saveRawResponse(
                                    generation.text,
                                    name: "raw_gemini_output_attempt_\(attempt).txt",
                                    folder: folder
                                )
                                self.builder.saveRawResponse(
                                    generation.rawAPIResponse,
                                    name: "raw_gemini_api_attempt_\(attempt).json",
                                    folder: folder
                                )

                                self.ui {
                                    onLog("    ✓ Response received")
                                    onLog("    finishReason: \(generation.finishReason)")
                                    if generation.promptTokenCount > 0 {
                                        onLog("    promptTokens: \(generation.promptTokenCount)")
                                    }
                                    if generation.outputTokenCount > 0 {
                                        onLog("    outputTokens: \(generation.outputTokenCount)")
                                    }
                                    if generation.totalTokenCount > 0 {
                                        onLog("    totalTokens: \(generation.totalTokenCount)")
                                    }
                                }

                                do {
                                    // A MAX_TOKENS response is treated as incomplete even if
                                    // a partial JSON fragment happens to be returned.
                                    if generation.finishReason.uppercased() == "MAX_TOKENS" {
                                        throw PipelineError.badGeminiJSON(
                                            "Gemini bị cắt vì MAX_TOKENS."
                                        )
                                    }

                                    let canonical = try self.builder.canonicalizeGeminiJSON(
                                        generation.text
                                    )

                                    if isCrossLanguage {
                                        var localizedJSON =
                                            canonical

                                        var localizedGuard =
                                            self.qa.validateLocalized(
                                                jsonText: localizedJSON,
                                                expectedLanguage: targetLanguage,
                                                source: parsed
                                            )

                                        if !localizedGuard.passed,
                                           landingRepairer
                                            .canRepairLanguageIssues(
                                                localizedGuard.issues
                                            ) {
                                            self.ui {
                                                onLog(
                                                    "    ⚠ LANGUAGE GUARD phát hiện question-card residue"
                                                )
                                                onLog(
                                                    "    → BATCH REPAIR 4 × 5 QUESTIONS"
                                                )
                                            }

                                            let repaired =
                                                try landingRepairer.repair(
                                                    jsonText: localizedJSON,
                                                    targetLanguage: targetLanguage,
                                                    sourceLanguage: parsed.sourceLanguage,
                                                    folder: folder,
                                                    onLog: { line in
                                                        self.ui {
                                                            onLog(line)
                                                        }
                                                    }
                                                )

                                            localizedJSON =
                                                try self.builder
                                                    .canonicalizeGeminiJSON(
                                                        repaired
                                                    )

                                            localizedGuard =
                                                self.qa.validateLocalized(
                                                    jsonText: localizedJSON,
                                                    expectedLanguage: targetLanguage,
                                                    source: parsed
                                                )
                                        }

                                        guard localizedGuard.passed else {
                                            let preview =
                                                localizedGuard.issues
                                                    .prefix(5)
                                                    .joined(
                                                        separator: " | "
                                                    )

                                            throw PipelineError.badGeminiJSON(
                                                "LANDING LANGUAGE GUARD [\(targetLanguage.shortLabel)] FAIL: \(preview)"
                                            )
                                        }

                                        successfulJSON =
                                            localizedJSON
                                        fidelityResult = nil

                                        self.builder.saveRawResponse(
                                            localizedJSON,
                                            name: "raw_gemini_response.txt",
                                            folder: folder
                                        )

                                        self.ui {
                                            onLog("    ✓ JSON parse: VALID")
                                            onLog("    ✓ LANDING TRANSLATED → \(targetLanguage.shortLabel)")
                                            onLog("    ✓ LANGUAGE GUARD: 20/20 question cards checked")
                                            onLog("    ✓ Batch cache: successful 5-question translations are reusable")
                                            onLog("    ✓ No verbatim source-language question residue detected")
                                        }
                                    } else {
                                        let locked = try self.builder.enforceSourceFidelity(
                                            jsonText: canonical,
                                            source: parsed
                                        )

                                        successfulJSON = locked.jsonText
                                        fidelityResult = locked

                                        self.builder.saveRawResponse(
                                            generation.text,
                                            name: "raw_gemini_response.txt",
                                            folder: folder
                                        )

                                        self.ui {
                                            onLog("    ✓ JSON parse: VALID")
                                            onLog("    ✓ Source Fidelity Lock: 20/20 cards mapped to Source View")
                                            if locked.totalCorrections > 0 {
                                                onLog("    ✓ Auto-repaired \(locked.totalCorrections) source field(s)")
                                            } else {
                                                onLog("    ✓ Source fields already exact")
                                            }
                                        }
                                    }

                                } catch {
                                    finalGenerationError = error
                                    self.ui {
                                        onLog("    ✕ JSON parse: INVALID")
                                        onLog("      \(error.localizedDescription)")
                                        if attempt < 2 {
                                            onLog("    → AUTO RETRY")
                                        }
                                    }
                                }

                            case .failure(let error):
                                finalGenerationError = error

                                let transient =
                                    isTransientGeminiError(
                                        error
                                    )

                                self.ui {
                                    onLog("    ✕ Gemini request failed")
                                    onLog("      \(error.localizedDescription)")

                                    if attempt < 2 {
                                        if transient {
                                            onLog(
                                                "    → TRANSIENT RETRY BACKOFF: 5s"
                                            )
                                        } else {
                                            onLog("    → AUTO RETRY")
                                        }
                                    }
                                }

                                if attempt < 2,
                                   transient {
                                    Thread.sleep(
                                        forTimeInterval: 5
                                    )
                                }

                            case .none:
                                finalGenerationError = GeminiAPIError.invalidResponse
                                self.ui {
                                    onLog("    ✕ Gemini response missing")
                                    if attempt < 2 {
                                        onLog("    → AUTO RETRY")
                                    }
                                }
                            }

                            if successfulJSON != nil {
                                break
                            }
                        }

                        guard let finalJSON = successfulJSON else {
                            throw finalGenerationError ?? GeminiAPIError.invalidResponse
                        }

                        generatedJSON = finalJSON
                        _ = try self.builder.saveGeneratedJSON(
                            generatedJSON,
                            folder: folder
                        )
                        if let fidelityResult {
                            _ = try self.builder.saveSourceFidelityReport(
                                fidelityResult,
                                folder: folder
                            )
                        }
                        state.geminiGenerated = true
                        state.lastError = nil
                        try self.stateStore.save(state, folder: folder)

                        self.ui {
                            onLog("  ✓ Gemini JSON generated successfully")
                        }
                    }

                    if let fidelityResult {
                        self.ui {
                            onLog("  • SOURCE FIDELITY LOCK...")
                            onLog("    ✓ Question text: Source View locked")
                            onLog("    ✓ Options/order: Source View locked")
                            onLog("    ✓ Correct answer/index: Source View locked")
                            onLog("    ✓ Image URL: Source View locked")
                            onLog("    ✓ Explanation: Source View locked")
                            if fidelityResult.totalCorrections > 0 {
                                for key in ["questionText", "options", "correctAnswer", "imageURL", "explanation"] {
                                    let count = fidelityResult.correctedFields[key] ?? 0
                                    if count > 0 {
                                        onLog("    ↳ repaired \(key): \(count)")
                                    }
                                }
                            }
                        }
                    }

                    self.ui {
                        onStatus(record.id, .qa)
                        if isCrossLanguage {
                            onLog("  • Localized QA [\(targetLanguage.shortLabel)]...")
                        } else {
                            onLog("  • Local QA...")
                        }
                    }

                    let qaResult: QuizQAResult
                    if isCrossLanguage {
                        qaResult = self.qa.validateLocalized(
                            jsonText: generatedJSON,
                            expectedLanguage: targetLanguage,
                            source: parsed
                        )
                    } else {
                        qaResult = self.qa.validate(
                            jsonText: generatedJSON,
                            source: parsed
                        )
                    }
                    _ = try self.builder.saveQA(qaResult, folder: folder)

                    state.qaPassed = qaResult.passed
                    state.selectedSourcePositions = qaResult.selectedSourcePositions

                    if !qaResult.passed {
                        state.lastError = "QA FAIL \(qaResult.issues.count) issue(s)"
                        try self.stateStore.save(state, folder: folder)
                        self.ui {
                            onStatus(record.id, .failed)
                            onLog("  ✕ QA FAIL: \(qaResult.issues.count) issue(s)")
                            qaResult.issues.prefix(12).forEach { onLog("    - \($0)") }
                            if qaResult.issues.count > 12 {
                                onLog("    - ... xem qa_report.txt")
                            }
                            onLog("")
                        }
                        continue
                    }

                    let contentPayloadURL = try self.builder.buildEthopexContentPayload(
                        jsonText: generatedJSON,
                        folder: folder
                    )

                    state.qaPassed = true
                    state.lastError = nil
                    try self.stateStore.save(state, folder: folder)

                    self.ui {
                        onStatus(record.id, .readyContent)
                        onLog("  ✓ QA PASS — 0 issues")
                        onLog("  ✓ Content payload: \(contentPayloadURL.lastPathComponent)")
                        onLog("  → READY FOR ETHOPEX CONTENT API")
                        onLog("")
                    }

                } catch {
                    state.lastError = error.localizedDescription
                    try? self.stateStore.save(state, folder: folder)
                    self.ui {
                        onStatus(record.id, .failed)
                        onLog("  ✕ FAILED")
                        onLog("    - \(error.localizedDescription)")
                        onLog("")
                    }
                }
            }

            DispatchQueue.main.async { completion() }
        }
    }

    private func createContentRealPerContentOwner(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let queue = DispatchQueue(label: "local.ethopex.content.real", qos: .userInitiated)

        queue.async {
            let coverName = "quiz 3"

            self.ui {
                onLog("• Tự tìm Cover trong Ethopex Library: '\(coverName)'...")
            }

            let coverSemaphore = DispatchSemaphore(value: 0)
            var coverResult: Result<EthopexCoverAsset, Error>?

            self.api.findImageAsset(named: coverName) {
                coverResult = $0
                coverSemaphore.signal()
            }

            if coverSemaphore.wait(timeout: .now() + 90) == .timedOut {
                let errorText = "Timeout khi tìm Cover '\(coverName)' trong Ethopex Library."
                self.ui {
                    for record in records {
                        onStatus(record.id, .failed)
                    }
                    onLog("✕ COVER LOOKUP FAILED")
                    onLog("  - \(errorText)")
                    onLog("")
                    completion()
                }
                return
            }

            let coverAsset: EthopexCoverAsset
            switch coverResult {
            case .success(let asset):
                coverAsset = asset
                self.ui {
                    onLog("✓ COVER FOUND")
                    onLog("  asset_id: \(asset.assetID)")
                    onLog("  name: \(asset.name)")
                    onLog("  file_path: \(asset.filePath)")
                    onLog("  public_url: \(asset.publicURL)")
                    onLog("  → Mọi Content mới trong batch này sẽ dùng Cover '\(coverName)'.")
                    onLog("")
                }

            case .failure(let error):
                self.ui {
                    for record in records {
                        onStatus(record.id, .failed)
                    }
                    onLog("✕ COVER LOOKUP FAILED")
                    onLog("  - \(error.localizedDescription)")
                    onLog("  → Không tạo Content để tránh Content bị thiếu Cover.")
                    onLog("")
                    completion()
                }
                return

            case .none:
                self.ui {
                    for record in records {
                        onStatus(record.id, .failed)
                    }
                    onLog("✕ COVER LOOKUP FAILED")
                    onLog("  - Ethopex không trả kết quả Cover.")
                    onLog("")
                    completion()
                }
                return
            }

            for (index, record) in records.enumerated() {
                let folder = self.dataSource.folder(for: record)
                var state = self.stateStore.load(folder: folder, record: record)

                do {
                    if state.contentCreated, let existingID = state.contentID {
                        self.ui {
                            onStatus(record.id, .checkingContent)
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            onLog("  • Local có content_id \(existingID)")
                            onLog("  • Kiểm tra content này còn tồn tại trên Ethopex...")
                        }

                        let checkSemaphore = DispatchSemaphore(value: 0)
                        var checkResult: Result<EthopexContentRemoteState, Error>?

                        self.api.checkContentExists(contentID: existingID) {
                            checkResult = $0
                            checkSemaphore.signal()
                        }

                        if checkSemaphore.wait(timeout: .now() + 90) == .timedOut {
                            throw NSError(
                                domain: "EthopexCampaignTool",
                                code: 1301,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Timeout khi kiểm tra content_id \(existingID) trên Ethopex."
                                ]
                            )
                        }

                        switch checkResult {
                        case .success(.exists):
                            self.ui {
                                onStatus(record.id, .contentDone)
                                onLog("  ✓ REMOTE CONTENT EXISTS")
                                onLog("    content_id: \(existingID)")
                                onLog("  → Content vẫn tồn tại trên Ethopex, không tạo trùng.")
                                onLog("")
                            }
                            continue

                        case .success(.missing):
                            self.ui {
                                onStatus(record.id, .readyContent)
                                onLog("  ⚠ REMOTE CONTENT MISSING")
                                onLog("    content_id cũ: \(existingID)")
                                onLog("  → Content đã bị xóa trên Ethopex.")
                                onLog("  → Xóa local stale state và TẠO LẠI CONTENT.")
                            }

                            // Keep parsed/Gemini/QA cache, but invalidate the deleted
                            // remote Content and all downstream Creative linkage.
                            state.contentCreated = false
                            state.groupID = nil
                            state.contentID = nil
                            state.contentLinkURL = nil

                            state.creativePayloadPrepared = false
                            state.creativeCreated = false
                            state.creativeID = nil
                            state.creativeBlocker = nil
                            state.campaignID = nil
                            state.adSetID = nil
                            state.adID = nil
                            state.campaignTemplateName = nil
                            state.campaignPageInternalID = nil
                            state.campaignPageExternalID = nil
                            state.campaignPageName = nil

                            // Uploaded media is an independent Ethopex asset and may
                            // still be reused for the new Creative.
                            state.lastError = nil
                            try self.stateStore.save(state, folder: folder)

                        case .failure(let error):
                            // Important: do NOT create another content when remote
                            // verification itself failed. This prevents accidental
                            // duplicates on 401/403/5xx/network failures.
                            throw NSError(
                                domain: "EthopexCampaignTool",
                                code: 1302,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "Không xác minh được content_id \(existingID) trên Ethopex: \(error.localizedDescription). " +
                                    "Tool dừng để tránh tạo trùng."
                                ]
                            )

                        case .none:
                            throw EthopexAPIError.invalidResponse
                        }
                    }

                    guard state.qaPassed else {
                        self.ui {
                            onLog(
                                "[\(index + 1)/\(records.count)] #" +
                                "\(record.stt ?? 0) \(record.name)"
                            )
                            onLog(
                                "  ↷ CASCADE SKIP CONTENT: Landing/QA chưa thành công."
                            )
                            onLog("")
                        }
                        continue
                    }

                    let payload = try self.builder.contentPayloadData(
                        folder: folder,
                        coverPublicURL: coverAsset.publicURL
                    )

                    self.builder.saveRawResponse(
                        coverAsset.rawResponse,
                        name: "ethopex_cover_asset_response.json",
                        folder: folder
                    )

                    self.ui {
                        onStatus(record.id, .creatingContent)
                        onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                        onLog("  ✓ Cover: \(coverAsset.name)")
                        onLog("    file_path: \(coverAsset.filePath)")
                        onLog("    sub_thumbnail URL: \(coverAsset.publicURL)")
                        onLog("  • POST Ethopex Content API...")
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    var result: Result<EthopexContentResult, Error>?

                    self.api.createContent(payloadData: payload) {
                        result = $0
                        semaphore.signal()
                    }

                    if semaphore.wait(timeout: .now() + 150) == .timedOut {
                        throw NSError(
                            domain: "EthopexCampaignTool",
                            code: 1002,
                            userInfo: [NSLocalizedDescriptionKey: "Ethopex Content API timeout."]
                        )
                    }

                    switch result {
                    case .success(let contentResult):
                        state.contentCreated = true
                        state.groupID = contentResult.groupID
                        state.contentID = contentResult.contentID
                        state.contentLinkURL = nil
                        state.lastError = nil
                        state.creativeBlocker = nil
                        try self.stateStore.save(state, folder: folder)

                        self.builder.saveRawResponse(
                            contentResult.rawResponse,
                            name: "ethopex_content_response.json",
                            folder: folder
                        )

                        self.ui {
                            onStatus(record.id, .contentDone)
                            onLog("  ✓ CONTENT CREATED + COVER")
                            onLog("    group_id: \(contentResult.groupID)")
                            onLog("    content_id: \(contentResult.contentID)")
                            onLog("    cover: \(coverAsset.name)")
                            onLog("  ✓ Local state đã cập nhật sang content_id mới.")
                            onLog("  → Tiếp theo: TẠO CREATIVE")
                            onLog("")
                        }

                    case .failure(let error):
                        throw error

                    case .none:
                        throw EthopexAPIError.invalidResponse
                    }

                    Thread.sleep(forTimeInterval: 1.6)

                } catch {
                    state.lastError = error.localizedDescription
                    try? self.stateStore.save(state, folder: folder)
                    self.ui {
                        onStatus(record.id, .failed)
                        onLog("  ✕ ETHOPEX CONTENT FAILED")
                        onLog("    - \(error.localizedDescription)")
                        onLog("")
                    }
                }
            }

            DispatchQueue.main.async { completion() }
        }
    }



    // V1.6.2 — One-click Campaign:
    // AUTO TEST (Source Parse → Gemini → Fidelity → QA)
    // → Content → Creative → Campaign.
    func createCampaignAutoPipeline(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        self.ui {
            onLog("")
            onLog("========== AUTO PRE-CHECK / TEST PIPELINE ==========")
            onLog("• Parse Source → Gemini → Source Fidelity → QA chạy tự động.")
            onLog("• Không cần bấm TEST PIPELINE trước.")
            onLog("")
        }

        testPipeline(
            records: records,
            onStatus: onStatus,
            onLog: onLog
        ) { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.ui {
                onLog("")
                onLog("========== AUTO TEST HOÀN TẤT ==========")
                onLog("→ Tiếp tục Content → Creative → Campaign...")
                onLog("")
            }

            self.createContentCreativeCampaign(
                records: records,
                onStatus: onStatus,
                onLog: onLog,
                completion: completion
            )
        }
    }


    func createContentCreativeCampaign(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        createContentReal(
            records: records,
            onStatus: onStatus,
            onLog: onLog
        ) { [weak self] in
            guard let self else {
                completion()
                return
            }

            self.ui {
                onLog("")
                onLog("========== AUTO RUN CREATIVE ==========")
                onLog("")
            }

            self.createCreativeReal(
                records: records,
                onStatus: onStatus,
                onLog: onLog
            ) { [weak self] in
                guard let self else {
                    completion()
                    return
                }

                self.ui {
                    onLog("")
                    onLog("========== AUTO RUN CAMPAIGN ==========")
                    onLog("Template routing: EN/RU/AR/RO/HR")
                    onLog("")
                }

                self.createCampaignReal(
                    records: records,
                    onStatus: onStatus,
                    onLog: onLog,
                    completion: completion
                )
            }
        }
    }

    func createCreativeReal(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let queue = DispatchQueue(label: "local.ethopex.creative.real", qos: .userInitiated)

        queue.async {
            for (index, record) in records.enumerated() {
                let folder = self.dataSource.folder(for: record)
                var state = self.stateStore.load(folder: folder, record: record)

                do {
                    let selectedDisplayLink = CreativeDisplayLinkConfig.shared.url

                    if state.creativeCreated, let existingID = state.creativeID {
                        if state.contentLinkURL == selectedDisplayLink {
                            self.ui {
                                onStatus(record.id, .creativeDone)
                                onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                                onLog("  ✓ Creative đã tồn tại: creative_id \(existingID)")
                                onLog("  ✓ Display link: \(selectedDisplayLink)")
                                onLog("  → Không tạo trùng.")
                                onLog("")
                            }
                            continue
                        } else {
                            self.ui {
                                onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                                onLog("  ⚠ Creative cũ dùng Display link khác.")
                                onLog("    creative_id cũ: \(existingID)")
                                onLog("    link cũ: \(state.contentLinkURL ?? "(unknown)")")
                                onLog("    link mới: \(selectedDisplayLink)")
                                if (state.contentLinkURL ?? "").contains("://") {
                                    onLog("    ↳ V0.16: bỏ http/https, Ethopex chỉ cần domain thuần.")
                                }
                                onLog("  → Reset local Creative state và tạo Creative mới.")
                            }

                            state.creativeCreated = false
                            state.creativeID = nil
                            state.creativePayloadPrepared = false
                            state.creativeBlocker = nil

                            // Campaign depends on Creative. If Creative changes,
                            // the previous campaign linkage is stale locally.
                            state.campaignID = nil
                            state.adSetID = nil
                            state.adID = nil
                            state.campaignTemplateName = nil
                            state.campaignPageInternalID = nil
                            state.campaignPageExternalID = nil
                            state.campaignPageName = nil

                            state.lastError = nil
                            try self.stateStore.save(state, folder: folder)
                        }
                    }

                    guard state.contentCreated,
                          let contentID = state.contentID,
                          !contentID.isEmpty else {
                        self.ui {
                            onLog(
                                "[\(index + 1)/\(records.count)] #" +
                                "\(record.stt ?? 0) \(record.name)"
                            )
                            onLog(
                                "  ↷ CASCADE SKIP CREATIVE: chưa có Content thành công."
                            )
                            onLog("")
                        }
                        continue
                    }

                    var publicImageURL = state.uploadedImageURL

                    if publicImageURL == nil || publicImageURL?.isEmpty == true {
                        self.ui {
                            onStatus(record.id, .uploadingMedia)
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            onLog("  • Upload Image → Ethopex R2...")
                        }

                        let semaphore = DispatchSemaphore(value: 0)
                        var mediaResult: Result<EthopexMediaResult, Error>?

                        self.api.uploadMedia(fileURL: self.dataSource.imageURL(for: record)) {
                            mediaResult = $0
                            semaphore.signal()
                        }

                        if semaphore.wait(timeout: .now() + 200) == .timedOut {
                            throw NSError(
                                domain: "EthopexCampaignTool",
                                code: 2101,
                                userInfo: [NSLocalizedDescriptionKey: "Upload Image timeout."]
                            )
                        }

                        switch mediaResult {
                        case .success(let media):
                            state.uploadedMediaID = media.mediaID
                            state.uploadedImageURL = media.fileURL
                            publicImageURL = media.fileURL
                            state.lastError = nil
                            try self.stateStore.save(state, folder: folder)

                            self.builder.saveRawResponse(
                                media.rawResponse,
                                name: "ethopex_media_response.json",
                                folder: folder
                            )

                            self.ui {
                                onStatus(record.id, .mediaDone)
                                onLog("  ✓ IMAGE UPLOADED")
                                onLog("    media_id: \(media.mediaID)")
                                onLog("    public_url: \(media.fileURL)")
                            }

                        case .failure(let error):
                            throw error

                        case .none:
                            throw EthopexAPIError.invalidResponse
                        }
                    } else {
                        self.ui {
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            onLog("  ✓ Dùng public image URL đã upload từ lần trước.")
                        }
                    }

                    guard let imageURL = publicImageURL, !imageURL.isEmpty else {
                        throw EthopexAPIError.noMediaURL
                    }

                    let linkURL = CreativeDisplayLinkConfig.shared.url

                    state.contentLinkURL = linkURL
                    state.lastError = nil
                    try self.stateStore.save(state, folder: folder)

                    self.ui {
                        onLog("  ✓ DISPLAY LINK PRESET")
                        onLog("    link_url: \(linkURL)")
                        onLog("    preset: \(CreativeDisplayLinkConfig.shared.selected.displayName)")
                    }

                    let generated = try self.builder.loadGeneratedJSON(folder: folder)
                    let payloadURL = try self.builder.buildCreativePayload(
                        record: record,
                        contentID: contentID,
                        linkURL: linkURL,
                        imageURL: imageURL,
                        generatedJSON: generated,
                        folder: folder
                    )
                    state.creativePayloadPrepared = true
                    try self.stateStore.save(state, folder: folder)

                    self.ui {
                        onStatus(record.id, .creatingCreative)
                        onLog("  ✓ Creative payload: \(payloadURL.lastPathComponent)")
                        onLog("    link_url: \(linkURL)")
                        onLog("  • POST /api/v1/creatives...")
                    }

                    let creativePayload = try self.builder.creativePayloadData(folder: folder)
                    let semaphore = DispatchSemaphore(value: 0)
                    var creativeResult: Result<EthopexCreativeResult, Error>?

                    self.api.createCreative(payloadData: creativePayload) {
                        creativeResult = $0
                        semaphore.signal()
                    }

                    if semaphore.wait(timeout: .now() + 150) == .timedOut {
                        throw NSError(
                            domain: "EthopexCampaignTool",
                            code: 2102,
                            userInfo: [NSLocalizedDescriptionKey: "Create Creative timeout."]
                        )
                    }

                    switch creativeResult {
                    case .success(let creative):
                        state.creativeCreated = true
                        state.creativeID = creative.creativeID
                        state.creativeBlocker = nil
                        state.lastError = nil
                        try self.stateStore.save(state, folder: folder)

                        self.builder.saveRawResponse(
                            creative.rawResponse,
                            name: "ethopex_creative_response.json",
                            folder: folder
                        )

                        self.ui {
                            onStatus(record.id, .creativeDone)
                            onLog("  ✓ CREATIVE CREATED")
                            onLog("    creative_id: \(creative.creativeID)")
                            onLog("  → Content + Image + Creative hoàn tất.")
                            onLog("")
                        }

                    case .failure(let error):
                        throw error

                    case .none:
                        throw EthopexAPIError.invalidResponse
                    }

                    Thread.sleep(forTimeInterval: 1.6)

                } catch {
                    state.lastError = error.localizedDescription
                    try? self.stateStore.save(state, folder: folder)
                    self.ui {
                        onStatus(record.id, .failed)
                        onLog("  ✕ CREATE CREATIVE FAILED")
                        onLog("    - \(error.localizedDescription)")
                        onLog("")
                    }
                }
            }

            DispatchQueue.main.async { completion() }
        }
    }


    func createCampaignReal(
        records: [CampaignRecord],
        onStatus: @escaping (UUID, JobStatus) -> Void,
        onLog: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let queue = DispatchQueue(
            label: "local.ethopex.campaign.real",
            qos: .userInitiated
        )

        queue.async {
            for (index, record) in records.enumerated() {
                let folder = self.dataSource.folder(for: record)
                var state = self.stateStore.load(
                    folder: folder,
                    record: record
                )

                do {
                    let selectedPage =
                        FacebookPageSelectionConfig.shared.selectedPage

                    let language = CampaignLanguage.from(
                        code: record.effectiveLanguageCode
                    )
                    let profile = LanguageCampaignTemplateRouter.profile(
                        for: language
                    )

                    if let existingID = state.campaignID,
                       !existingID.isEmpty {

                        let samePage =
                            state.campaignPageInternalID == selectedPage.id &&
                            state.campaignPageExternalID == selectedPage.externalID

                        // User rule: existing English campaigns are not recreated.
                        // Other languages must also match the language template.
                        let sameTemplate =
                            language == .english ||
                            state.campaignTemplateName == profile.templateName

                        if samePage && sameTemplate {
                            self.ui {
                                onStatus(record.id, .campaignDone)
                                onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                                onLog("  ✓ Campaign đã có trong local state")
                                onLog("    campaign_id: \(existingID)")
                                onLog("    fanpage: \(selectedPage.displayName)")
                                onLog("    page internal_id: \(selectedPage.id)")
                                onLog("    page external_id: \(selectedPage.externalID)")
                                if let adSetID = state.adSetID {
                                    onLog("    ad_set_id: \(adSetID)")
                                }
                                if let adID = state.adID {
                                    onLog("    ad_id: \(adID)")
                                }
                                onLog("    language: \(language.shortLabel)")
                                onLog("    template: \(state.campaignTemplateName ?? profile.templateName)")
                                onLog("  → Campaign đã tồn tại đúng routing, không tạo trùng.")
                                onLog("")
                            }
                            continue
                        }

                        self.ui {
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            if !samePage {
                                onLog("  ⚠ Fanpage batch đã thay đổi.")
                                onLog("    page cũ: \(state.campaignPageName ?? "(unknown)")")
                                onLog("    page mới: \(selectedPage.displayName)")
                            } else {
                                onLog("  ⚠ TEMPLATE MISMATCH — \(language.shortLabel)")
                                onLog("    template cũ: \(state.campaignTemplateName ?? "(unknown)")")
                                onLog("    template đúng: \(profile.templateName)")
                            }
                            onLog("    campaign_id cũ: \(existingID)")
                            onLog("  → Reset local Campaign state và tạo Campaign mới đúng routing.")
                        }

                        state.campaignID = nil
                        state.adSetID = nil
                        state.adID = nil
                        state.campaignTemplateName = nil
                        state.campaignPageInternalID = nil
                        state.campaignPageExternalID = nil
                        state.campaignPageName = nil
                        state.lastError = nil
                        try self.stateStore.save(state, folder: folder)
                    }

                    guard state.contentCreated,
                          let contentID = state.contentID,
                          !contentID.isEmpty else {
                        self.ui {
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            onLog("  ↷ CASCADE SKIP CAMPAIGN: chưa có Content thành công.")
                            onLog("")
                        }
                        continue
                    }

                    guard state.creativeCreated,
                          let creativeID = state.creativeID,
                          !creativeID.isEmpty else {
                        self.ui {
                            onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                            onLog("  ↷ CASCADE SKIP CAMPAIGN: chưa có Creative thành công.")
                            onLog("")
                        }
                        continue
                    }

                    let generated = try self.builder.loadGeneratedJSON(
                        folder: folder
                    )

                    let campaignName =
                        LanguageCampaignTemplateRouter.campaignName(
                            creativeRecordName: record.name,
                            generatedJSON: generated
                        )

                    let payload =
                        try LanguageCampaignTemplateRouter.buildPayload(
                            language: language,
                            campaignName: campaignName,
                            contentID: contentID,
                            creativeID: creativeID,
                            facebookPage: selectedPage
                        )

                    let payloadURL = try self.builder.saveCampaignPayload(
                        payload,
                        folder: folder
                    )

                    self.ui {
                        onStatus(record.id, .creatingCampaign)
                        onLog("[\(index + 1)/\(records.count)] #\(record.stt ?? 0) \(record.name)")
                        onLog("  • CREATE FACEBOOK CAMPAIGN [\(language.shortLabel)]")
                        onLog("    template: \(profile.templateName)")
                        onLog("    ad_account_id: \(profile.adAccountID)")
                        onLog("    external_account_id: \(profile.externalAccountID)")
                        if let locales = profile.targetingLocales {
                            onLog("    targeting.locales: \(locales)")
                        } else {
                            onLog("    targeting.locales: AUTO (EN template)")
                        }
                        onLog("    campaign name: \(campaignName)")
                        onLog("    source creative: \(record.name)")
                        onLog("    content_id: \(contentID)")
                        onLog("    creative_id: \(creativeID)")
                        onLog("    fanpage: \(selectedPage.displayName)")
                        onLog("    page internal_id: \(selectedPage.id)")
                        onLog("    page external_id: \(selectedPage.externalID)")
                        onLog("    campaign status: PAUSED")
                        onLog("    ad set status: PAUSED")
                        onLog("    payload: \(payloadURL.lastPathComponent)")
                        onLog("  • POST /api/v1/campaigns/facebook...")
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    var result: Result<EthopexCampaignResult, Error>?

                    self.api.createFacebookCampaign(
                        payloadData: payload
                    ) {
                        result = $0
                        semaphore.signal()
                    }

                    if semaphore.wait(
                        timeout: .now() + 180
                    ) == .timedOut {
                        throw NSError(
                            domain: "EthopexWorkspace",
                            code: 3101,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Create Campaign timeout."
                            ]
                        )
                    }

                    switch result {
                    case .success(let created):
                        state.campaignID = created.campaignID
                        state.adSetID = created.adSetID
                        state.adID = created.adID
                        state.campaignTemplateName =
                            profile.templateName
                        state.campaignPageInternalID = selectedPage.id
                        state.campaignPageExternalID = selectedPage.externalID
                        state.campaignPageName = selectedPage.displayName
                        state.lastError = nil

                        try self.stateStore.save(
                            state,
                            folder: folder
                        )

                        self.builder.saveRawResponse(
                            created.rawResponse,
                            name: "ethopex_campaign_response.json",
                            folder: folder
                        )

                        self.ui {
                            onStatus(record.id, .campaignDone)
                            onLog("  ✓ CAMPAIGN CREATED")
                            onLog("    campaign_id: \(created.campaignID)")
                            onLog("    ad_set_id: \(created.adSetID)")
                            onLog("    ad_id: \(created.adID)")
                            onLog("  ✓ FULL FLOW DONE")
                            onLog("    Content → Creative → Campaign")
                            onLog("")
                        }

                    case .failure(let error):
                        throw error

                    case .none:
                        throw EthopexAPIError.invalidResponse
                    }

                    Thread.sleep(forTimeInterval: 1.6)

                } catch {
                    state.lastError = error.localizedDescription
                    try? self.stateStore.save(
                        state,
                        folder: folder
                    )

                    self.ui {
                        onStatus(record.id, .failed)
                        onLog("  ✕ CREATE CAMPAIGN FAILED")
                        onLog("    - \(error.localizedDescription)")
                        onLog("")
                    }
                }
            }

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func ui(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
}
