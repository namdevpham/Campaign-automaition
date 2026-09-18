import AppKit
import Foundation

struct WorkspaceUpdateManifest: Codable {
    let app: String
    let version: String
    let minimumVersion: String?
    let files: [String]
    let deletePaths: [String]?

    enum CodingKeys: String, CodingKey {
        case app
        case version
        case minimumVersion = "minimum_version"
        case files
        case deletePaths = "delete_paths"
    }
}

struct PreparedWorkspaceUpdate {
    let manifest: WorkspaceUpdateManifest
    let tempDirectory: URL
    let packageRoot: URL
}

enum WorkspaceUpdaterError: Error, LocalizedError {
    case projectRootNotFound
    case invalidPackage(String)
    case invalidManifest(String)
    case wrongApp(String)
    case oldVersion(String)
    case unsafePath(String)
    case missingPayload(String)

    var errorDescription: String? {
        switch self {
        case .projectRootNotFound:
            return "Không tìm thấy source project cạnh thư mục build. Hãy chạy app từ project được build bằng build.command."
        case .invalidPackage(let message):
            return "Update package không hợp lệ: \(message)"
        case .invalidManifest(let message):
            return "update_manifest.json không hợp lệ: \(message)"
        case .wrongApp(let app):
            return "Package này dành cho app khác: \(app)"
        case .oldVersion(let message):
            return message
        case .unsafePath(let path):
            return "Package có path không an toàn: \(path)"
        case .missingPayload(let path):
            return "Thiếu file payload: \(path)"
        }
    }
}

final class WorkspaceUpdater {
    static let appID = "EthopexWorkspace"

    var currentVersion: String {
        (Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String) ?? "0"
    }

    func projectRoot() throws -> URL {
        let fm = FileManager.default

        // build/Ethopex Workspace.app → project root
        let candidate = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let buildScript = candidate
            .appendingPathComponent(
                "build.command"
            )

        guard fm.fileExists(
            atPath: buildScript.path
        ) else {
            throw WorkspaceUpdaterError
                .projectRootNotFound
        }

        return candidate
    }

    func prepare(
        packageURL: URL
    ) throws -> PreparedWorkspaceUpdate {
        let fm = FileManager.default

        let temp = fm.temporaryDirectory
            .appendingPathComponent(
                "EthopexUpdate-" +
                UUID().uuidString,
                isDirectory: true
            )

        try fm.createDirectory(
            at: temp,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL =
            URL(fileURLWithPath:
                "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            packageURL.path,
            temp.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WorkspaceUpdaterError
                .invalidPackage(
                    "không giải nén được ZIP."
                )
        }

        guard let manifestURL =
                findManifest(
                    inside: temp
                ) else {
            throw WorkspaceUpdaterError
                .invalidPackage(
                    "không có update_manifest.json."
                )
        }

        let packageRoot =
            manifestURL
                .deletingLastPathComponent()

        let data = try Data(
            contentsOf: manifestURL
        )

        let decoder =
            JSONDecoder()

        let manifest:
            WorkspaceUpdateManifest

        do {
            manifest =
                try decoder.decode(
                    WorkspaceUpdateManifest.self,
                    from: data
                )
        } catch {
            throw WorkspaceUpdaterError
                .invalidManifest(
                    error.localizedDescription
                )
        }

        guard manifest.app ==
                Self.appID else {
            throw WorkspaceUpdaterError
                .wrongApp(
                    manifest.app
                )
        }

        guard compareVersions(
            manifest.version,
            currentVersion
        ) == .orderedDescending else {
            throw WorkspaceUpdaterError
                .oldVersion(
                    "Version package \(manifest.version) không mới hơn version hiện tại \(currentVersion)."
                )
        }

        if let minimum =
                manifest.minimumVersion,
           compareVersions(
                currentVersion,
                minimum
           ) == .orderedAscending {
            throw WorkspaceUpdaterError
                .oldVersion(
                    "Package yêu cầu tối thiểu v\(minimum), nhưng app hiện tại là v\(currentVersion)."
                )
        }

        guard !manifest.files.isEmpty else {
            throw WorkspaceUpdaterError
                .invalidManifest(
                    "files đang rỗng."
                )
        }

        for relative in manifest.files {
            try validateRelativePath(
                relative
            )

            let payload = packageRoot
                .appendingPathComponent(
                    "payload",
                    isDirectory: true
                )
                .appendingPathComponent(
                    relative
                )

            guard fm.fileExists(
                atPath: payload.path
            ) else {
                throw WorkspaceUpdaterError
                    .missingPayload(
                        relative
                    )
            }
        }

        for relative in
            manifest.deletePaths ?? [] {
            try validateRelativePath(
                relative
            )
        }

        return PreparedWorkspaceUpdate(
            manifest: manifest,
            tempDirectory: temp,
            packageRoot: packageRoot
        )
    }

    func apply(
        _ prepared: PreparedWorkspaceUpdate
    ) throws -> URL {
        let fm = FileManager.default
        let root = try projectRoot()

        let formatter =
            DateFormatter()
        formatter.dateFormat =
            "yyyyMMdd-HHmmss"

        let backup = root
            .appendingPathComponent(
                "update_backups",
                isDirectory: true
            )
            .appendingPathComponent(
                "before-v" +
                prepared.manifest.version +
                "-" +
                formatter.string(
                    from: Date()
                ),
                isDirectory: true
            )

        try fm.createDirectory(
            at: backup,
            withIntermediateDirectories: true
        )

        let payloadRoot =
            prepared.packageRoot
                .appendingPathComponent(
                    "payload",
                    isDirectory: true
                )

        var newlyCreated:
            [URL] = []

        do {
            // Backup every path that is about to change.
            let affected =
                prepared.manifest.files +
                (
                    prepared.manifest
                        .deletePaths ??
                    []
                )

            for relative in Set(affected) {
                let target =
                    root.appendingPathComponent(
                        relative
                    )

                guard fm.fileExists(
                    atPath: target.path
                ) else {
                    continue
                }

                let backupTarget =
                    backup.appendingPathComponent(
                        relative
                    )

                try fm.createDirectory(
                    at: backupTarget
                        .deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                try fm.copyItem(
                    at: target,
                    to: backupTarget
                )
            }

            // Apply replacements.
            for relative in
                prepared.manifest.files {
                let source =
                    payloadRoot
                        .appendingPathComponent(
                            relative
                        )

                let target =
                    root.appendingPathComponent(
                        relative
                    )

                if !fm.fileExists(
                    atPath: target.path
                ) {
                    newlyCreated.append(
                        target
                    )
                } else {
                    try fm.removeItem(
                        at: target
                    )
                }

                try fm.createDirectory(
                    at: target
                        .deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                try fm.copyItem(
                    at: source,
                    to: target
                )
            }

            // Apply deletions after replacements.
            for relative in
                prepared.manifest
                    .deletePaths ?? [] {
                let target =
                    root.appendingPathComponent(
                        relative
                    )

                if fm.fileExists(
                    atPath: target.path
                ) {
                    try fm.removeItem(
                        at: target
                    )
                }
            }

            let buildScript =
                root.appendingPathComponent(
                    "build.command"
                )

            try? fm.setAttributes(
                [
                    .posixPermissions:
                        0o755
                ],
                ofItemAtPath:
                    buildScript.path
            )

            return backup

        } catch {
            // Best-effort rollback.
            for created in newlyCreated {
                try? fm.removeItem(
                    at: created
                )
            }

            if let enumerator =
                    fm.enumerator(
                        at: backup,
                        includingPropertiesForKeys:
                            [.isRegularFileKey]
                    ) {
                for case let backupFile
                        as URL in enumerator {
                    let values =
                        try? backupFile
                            .resourceValues(
                                forKeys:
                                    [.isRegularFileKey]
                            )

                    guard values?
                        .isRegularFile ==
                        true else {
                        continue
                    }

                    let relative =
                        backupFile.path
                            .replacingOccurrences(
                                of:
                                    backup.path + "/",
                                with: ""
                            )

                    let target =
                        root.appendingPathComponent(
                            relative
                        )

                    try? fm.createDirectory(
                        at:
                            target
                                .deletingLastPathComponent(),
                        withIntermediateDirectories:
                            true
                    )

                    try? fm.removeItem(
                        at: target
                    )

                    try? fm.copyItem(
                        at: backupFile,
                        to: target
                    )
                }
            }

            throw error
        }
    }

    func rebuildAndRestart() throws {
        let root = try projectRoot()
        let fm = FileManager.default

        let runner =
            root.appendingPathComponent(
                ".ethopex_update_runner.command"
            )

        let log =
            root.appendingPathComponent(
                "update_build.log"
            )

        let quotedRoot =
            shellQuote(
                root.path
            )
        let quotedLog =
            shellQuote(
                log.path
            )
        let quotedRunner =
            shellQuote(
                runner.path
            )

        let script = """
        #!/bin/zsh
        sleep 1
        cd \(quotedRoot)
        export ETHOPEX_UPDATE_MODE=1
        ./build.command >> \(quotedLog) 2>&1
        STATUS=$?
        rm -f \(quotedRunner)
        exit $STATUS
        """

        try script.write(
            to: runner,
            atomically: true,
            encoding: .utf8
        )

        try fm.setAttributes(
            [
                .posixPermissions:
                    0o755
            ],
            ofItemAtPath:
                runner.path
        )

        let command =
            "nohup /bin/zsh " +
            shellQuote(
                runner.path
            ) +
            " >/dev/null 2>&1 &"

        let launcher =
            Process()
        launcher.executableURL =
            URL(fileURLWithPath:
                "/bin/zsh")
        launcher.arguments = [
            "-c",
            command
        ]

        try launcher.run()

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.25
        ) {
            NSApp.terminate(nil)
        }
    }

    func cleanup(
        _ prepared: PreparedWorkspaceUpdate
    ) {
        try? FileManager.default
            .removeItem(
                at:
                    prepared.tempDirectory
            )
    }

    private func findManifest(
        inside root: URL
    ) -> URL? {
        let fm = FileManager.default

        if fm.fileExists(
            atPath:
                root.appendingPathComponent(
                    "update_manifest.json"
                ).path
        ) {
            return root.appendingPathComponent(
                "update_manifest.json"
            )
        }

        guard let enumerator =
                fm.enumerator(
                    at: root,
                    includingPropertiesForKeys:
                        [.isRegularFileKey],
                    options:
                        [.skipsHiddenFiles]
                ) else {
            return nil
        }

        for case let url as URL
        in enumerator {
            if url.lastPathComponent ==
                "update_manifest.json" {
                return url
            }
        }

        return nil
    }

    private func validateRelativePath(
        _ path: String
    ) throws {
        let trimmed =
            path.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed
                .split(separator: "/")
                .contains("..") else {
            throw WorkspaceUpdaterError
                .unsafePath(
                    path
                )
        }
    }

    private func compareVersions(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
        let l = lhs
            .split(separator: ".")
            .map {
                Int($0) ?? 0
            }

        let r = rhs
            .split(separator: ".")
            .map {
                Int($0) ?? 0
            }

        let count =
            max(
                l.count,
                r.count
            )

        for index in 0..<count {
            let lv =
                index < l.count
                ? l[index]
                : 0

            let rv =
                index < r.count
                ? r[index]
                : 0

            if lv < rv {
                return .orderedAscending
            }

            if lv > rv {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private func shellQuote(
        _ value: String
    ) -> String {
        "'" +
        value.replacingOccurrences(
            of: "'",
            with: "'\\''"
        ) +
        "'"
    }
}
