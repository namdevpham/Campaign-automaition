
import AppKit
import Foundation
import UniformTypeIdentifiers

final class WorkspaceDarkPanelView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        WorkspaceUI.surface.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

final class DataStore {
    var records: [CampaignRecord] = []
    let baseDirectory: URL
    let recordsDirectory: URL
    let indexURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("EthopexDataManager", isDirectory: true)
        recordsDirectory = baseDirectory.appendingPathComponent("records", isDirectory: true)
        indexURL = baseDirectory.appendingPathComponent("records.json")

        try? fm.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL) else {
            records = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([CampaignRecord].self, from: data)) ?? []

        // V1.5: normalize every existing record to a clean sequential STT:
        // 1, 2, 3 ... n. Existing STT order is respected first.
        let before = records.map { ($0.id, $0.stt) }

        records.sort {
            let lhsSTT = $0.stt ?? Int.max
            let rhsSTT = $1.stt ?? Int.max
            if lhsSTT == rhsSTT {
                return $0.createdAt < $1.createdAt
            }
            return lhsSTT < rhsSTT
        }

        renumberSequentially()

        let after = records.map { ($0.id, $0.stt) }
        let changed = before.count != after.count ||
            zip(before, after).contains { lhs, rhs in
                lhs.0 != rhs.0 || lhs.1 != rhs.1
            }

        if changed {
            try? persist()
        }
    }

    func renumberSequentially() {
        records.sort {
            let lhsSTT = $0.stt ?? Int.max
            let rhsSTT = $1.stt ?? Int.max
            if lhsSTT == rhsSTT {
                return $0.createdAt < $1.createdAt
            }
            return lhsSTT < rhsSTT
        }

        for index in records.indices {
            records[index].stt = index + 1
        }
    }

    func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: .atomic)
    }

    func folder(for id: UUID) -> URL {
        recordsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func sourceURL(for record: CampaignRecord) -> URL? {
        guard !record.sourceStoredName.isEmpty else { return nil }
        return folder(for: record.id).appendingPathComponent(record.sourceStoredName)
    }

    func imageURL(for record: CampaignRecord) -> URL? {
        guard !record.imageStoredName.isEmpty else { return nil }
        return folder(for: record.id).appendingPathComponent(record.imageStoredName)
    }

    private func copyReplacing(_ source: URL, _ destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    func save(
        existing: CampaignRecord?,
        name: String,
        sourceURL: URL?,
        imageURL: URL?,
        primaryText: String,
        headline: String,
        descriptionText: String
    ) throws -> CampaignRecord {
        let fm = FileManager.default
        let id = existing?.id ?? UUID()
        let now = Date()

        // Existing record keeps its current position.
        // A new record is always n + 1.
        let assignedSTT = existing?.stt ?? (records.count + 1)

        let dir = folder(for: id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var sourceOriginalName = existing?.sourceOriginalName ?? ""
        var sourceStoredName = existing?.sourceStoredName ?? ""
        var imageOriginalName = existing?.imageOriginalName ?? ""
        var imageStoredName = existing?.imageStoredName ?? ""

        if let sourceURL {
            if !sourceStoredName.isEmpty {
                try? fm.removeItem(at: dir.appendingPathComponent(sourceStoredName))
            }
            sourceOriginalName = sourceURL.lastPathComponent
            let ext = sourceURL.pathExtension.isEmpty ? "html" : sourceURL.pathExtension.lowercased()
            sourceStoredName = "source.\(ext)"
            try copyReplacing(sourceURL, dir.appendingPathComponent(sourceStoredName))
        }

        if let imageURL {
            if !imageStoredName.isEmpty {
                try? fm.removeItem(at: dir.appendingPathComponent(imageStoredName))
            }
            imageOriginalName = imageURL.lastPathComponent
            let ext = imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension.lowercased()
            imageStoredName = "image.\(ext)"
            try copyReplacing(imageURL, dir.appendingPathComponent(imageStoredName))
        }

        let record = CampaignRecord(
            id: id,
            stt: assignedSTT,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceOriginalName: sourceOriginalName,
            sourceStoredName: sourceStoredName,
            imageOriginalName: imageOriginalName,
            imageStoredName: imageStoredName,
            primaryText: primaryText,
            headline: headline,
            descriptionText: descriptionText,
            contentGroupName: existing?.contentGroupName,
            creativeIndex: existing?.creativeIndex,
            creativeBaseName: existing?.creativeBaseName,
            creativeFingerprint: existing?.creativeFingerprint,
            sourceFingerprint: existing?.sourceFingerprint,
            importBatchID: existing?.importBatchID,
            importedAt: existing?.importedAt,
            languageCode: existing?.languageCode ?? "en",
            localizationSourceID: existing?.localizationSourceID,
            localizationSourceLanguage: existing?.localizationSourceLanguage,
            localizationGenerated: existing?.localizationGenerated,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index] = record
        } else {
            records.append(record)
        }

        renumberSequentially()
        try persist()

        return records.first(where: { $0.id == id }) ?? record
    }

    func delete(_ record: CampaignRecord) throws {
        try delete(ids: [record.id])
    }

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }

        let fm = FileManager.default

        for id in ids {
            let dir = folder(for: id)
            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
            }
        }

        records.removeAll { ids.contains($0.id) }
        renumberSequentially()
        try persist()
    }

    func deleteAll() throws {
        let fm = FileManager.default

        if fm.fileExists(atPath: recordsDirectory.path) {
            try fm.removeItem(at: recordsDirectory)
        }

        try fm.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
        records = []
        try persist()
    }

    func duplicate(_ record: CampaignRecord) throws -> CampaignRecord {
        let newID = UUID()
        let src = folder(for: record.id)
        let dst = folder(for: newID)

        if FileManager.default.fileExists(atPath: src.path) {
            try FileManager.default.copyItem(at: src, to: dst)
        } else {
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        }

        let now = Date()
        let copy = CampaignRecord(
            id: newID,
            stt: records.count + 1,
            name: record.name + " Copy",
            sourceOriginalName: record.sourceOriginalName,
            sourceStoredName: record.sourceStoredName,
            imageOriginalName: record.imageOriginalName,
            imageStoredName: record.imageStoredName,
            primaryText: record.primaryText,
            headline: record.headline,
            descriptionText: record.descriptionText,
            contentGroupName: record.contentGroupName,
            creativeIndex: record.creativeIndex,
            creativeBaseName: record.creativeBaseName,
            creativeFingerprint: record.creativeFingerprint,
            sourceFingerprint: record.sourceFingerprint,
            importBatchID: record.importBatchID,
            importedAt: record.importedAt,
            languageCode: record.languageCode,
            localizationSourceID: record.localizationSourceID,
            localizationSourceLanguage: record.localizationSourceLanguage,
            localizationGenerated: record.localizationGenerated,
            createdAt: now,
            updatedAt: now
        )

        records.append(copy)
        renumberSequentially()
        try persist()

        return records.first(where: { $0.id == newID }) ?? copy
    }
}

final class DataManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let store = DataStore()

    let tableView = NSTableView()
    let searchField = NSSearchField()
    let detailView = NSView()

    // V1.6.7.2 — stable master/detail split.
    // Selecting another record must never resize the two panes.
    let dataSplitView = NSSplitView()
    weak var dataDetailScrollView: NSScrollView?

    let nameLabel = NSTextField(labelWithString: "Chọn một dữ liệu")
    let statusLabel = NSTextField(labelWithString: "")
    let sourceLabel = NSTextField(labelWithString: "—")
    let imageNameLabel = NSTextField(labelWithString: "—")
    let imageView = NSImageView()
    let primaryTextView = NSTextView()
    let headlineValue = NSTextField(labelWithString: "—")
    let descriptionTextView = NSTextView()

    var filtered: [CampaignRecord] = []
    var selectedRecord: CampaignRecord?
    var checkedForDeletion = Set<UUID>()

    // V1.2: keep one editor alive while it is presented as a sheet.
    // This avoids app-wide runModal sessions that can leave the UI locked.
    var activeEditor: EditorWindowController?

    let importFolderButton = NSButton()
    let deleteCheckedButton = NSButton()
    let deleteAllButton = NSButton()

    var bulkImportInProgress = false

    convenience init() {
        let visible =
            NSScreen.main?.visibleFrame ??
            NSRect(
                x: 0,
                y: 0,
                width: 1280,
                height: 760
            )

        let width =
            min(
                1280,
                max(
                    840,
                    visible.width * 0.90
                )
            )

        let height =
            min(
                800,
                max(
                    620,
                    visible.height * 0.84
                )
            )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Ethopex Data Manager"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize =
            NSSize(
                width: 780,
                height: 580
            )
        window.center()

        self.init(window: window)
        setupUI()
        reloadData()
    }

    func setupUI() {
        guard let content = window?.contentView else { return }

        content.wantsLayer = true
        content.layer?.backgroundColor =
            WorkspaceUI.canvas.cgColor

        let split = dataSplitView
        split.isVertical = true
        split.dividerStyle = .thin
        split.appearance = NSAppearance(named: .darkAqua)
        split.wantsLayer = true
        split.layer?.backgroundColor = WorkspaceUI.surface.cgColor
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            split.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])

        let left = WorkspaceDarkPanelView()
        left.appearance = NSAppearance(named: .darkAqua)
        left.translatesAutoresizingMaskIntoConstraints = false

        let rightScroll = NSScrollView()
        dataDetailScrollView = rightScroll
        rightScroll.hasVerticalScroller = true
        rightScroll.hasHorizontalScroller = false
        rightScroll.autohidesScrollers = true
        rightScroll.borderType = .noBorder
        rightScroll.drawsBackground = true
        rightScroll.backgroundColor = WorkspaceUI.canvas
        rightScroll.contentView.drawsBackground = true
        rightScroll.contentView.backgroundColor = WorkspaceUI.surface
        rightScroll.scrollerStyle = .overlay
        rightScroll.translatesAutoresizingMaskIntoConstraints = false

        let right = WorkspaceDarkPanelView()
        right.appearance = NSAppearance(named: .darkAqua)
        right.translatesAutoresizingMaskIntoConstraints = false
        rightScroll.documentView = right

        split.addArrangedSubview(left)
        split.addArrangedSubview(rightScroll)

        // Let both sides resize. If the left table becomes narrow, it gets a
        // horizontal scroller instead of forcing the whole app off-screen.
        let leftMin =
            left.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 340
            )
        leftMin.priority = .defaultHigh
        leftMin.isActive = true

        let rightMin =
            rightScroll.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 390
            )
        rightMin.priority = .defaultHigh
        rightMin.isActive = true

        right.widthAnchor.constraint(
            equalTo: rightScroll.contentView.widthAnchor
        ).isActive = true

        // Detail contents must compress/truncate inside the current pane.
        // They are not allowed to change the divider position.
        right.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        right.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        rightScroll.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        rightScroll.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        left.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )
        left.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        left.wantsLayer = true
        right.wantsLayer = true
        left.layer?.backgroundColor =
            WorkspaceUI.surface.cgColor
        right.layer?.backgroundColor =
            WorkspaceUI.surface.cgColor

        split.setHoldingPriority(
            .defaultLow,
            forSubviewAt: 0
        )

        DispatchQueue.main.async {
            let available = split.bounds.width
            if available > 0 {
                let proposed =
                    max(
                        420,
                        min(
                            available - 430,
                            available * 0.43
                        )
                    )

                split.setPosition(
                    proposed,
                    ofDividerAt: 0
                )
            }
        }

        // Left panel
        searchField.placeholderString = "Tìm theo tên hoặc headline"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(searchField)

        let addButton = NSButton(
            title: "+ Thêm dữ liệu",
            target: self,
            action: #selector(addRecord)
        )
        WorkspaceUI.stylePrimaryButton(
            addButton,
            symbol: "plus"
        )
        addButton.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(addButton)

        importFolderButton.title = "Import Folder Hàng Loạt"
        importFolderButton.target = self
        importFolderButton.action = #selector(importFolderBatch)
        WorkspaceUI.styleSecondaryButton(
            importFolderButton,
            symbol: "tray.and.arrow.down"
        )
        importFolderButton.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(importFolderButton)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        WorkspaceUI.styleScrollSurface(scroll, radius: 10)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(scroll)

        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkColumn.title = "Chọn"
        checkColumn.width = 52
        checkColumn.minWidth = 52
        checkColumn.maxWidth = 52
        tableView.addTableColumn(checkColumn)

        let sttColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("stt"))
        sttColumn.title = "STT"
        sttColumn.width = 54
        sttColumn.minWidth = 54
        sttColumn.maxWidth = 64
        tableView.addTableColumn(sttColumn)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 310
        nameColumn.minWidth = 220
        tableView.addTableColumn(nameColumn)

        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = "Data"
        statusColumn.width = 145
        statusColumn.minWidth = 135
        tableView.addTableColumn(statusColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 46
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = WorkspaceUI.canvas
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.target = self
        tableView.doubleAction = #selector(editSelected)
        scroll.documentView = tableView

        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        left.addSubview(bottomBar)

        let openFolder = NSButton(title: "Thư mục", target: self, action: #selector(openDataFolder))
        openFolder.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(openFolder)

        deleteCheckedButton.title = "Xóa chọn"
        deleteCheckedButton.target = self
        deleteCheckedButton.action = #selector(deleteCheckedRecords)
        deleteCheckedButton.translatesAutoresizingMaskIntoConstraints = false
        deleteCheckedButton.isEnabled = false
        bottomBar.addSubview(deleteCheckedButton)

        deleteAllButton.title = "Xóa tất cả"
        deleteAllButton.target = self
        deleteAllButton.action = #selector(deleteAllRecords)
        deleteAllButton.translatesAutoresizingMaskIntoConstraints = false
        deleteAllButton.isEnabled = false
        bottomBar.addSubview(deleteAllButton)

        WorkspaceUI.styleSecondaryButton(
            openFolder,
            symbol: "folder"
        )
        WorkspaceUI.styleDangerButton(
            deleteCheckedButton,
            symbol: "trash"
        )
        WorkspaceUI.styleDangerButton(
            deleteAllButton,
            symbol: "trash.slash"
        )

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            searchField.topAnchor.constraint(equalTo: left.topAnchor, constant: 12),
            addButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            addButton.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -12),
            addButton.topAnchor.constraint(equalTo: searchField.topAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 135),

            importFolderButton.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            importFolderButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),

            scroll.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: importFolderButton.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -8),

            bottomBar.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            bottomBar.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -12),
            bottomBar.bottomAnchor.constraint(equalTo: left.bottomAnchor, constant: -10),
            bottomBar.heightAnchor.constraint(equalToConstant: 34),

            openFolder.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            openFolder.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            deleteAllButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            deleteAllButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            deleteCheckedButton.trailingAnchor.constraint(equalTo: deleteAllButton.leadingAnchor, constant: -8),
            deleteCheckedButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
        ])

        // Right panel
        setupDetailUI(in: right)
    }

    func setupDetailUI(in right: NSView) {
        let editButton = NSButton(title: "Sửa", target: self, action: #selector(editSelected))
        let duplicateButton = NSButton(title: "Nhân bản", target: self, action: #selector(duplicateSelected))
        let deleteButton = NSButton(title: "Xóa", target: self, action: #selector(deleteSelected))

        [nameLabel, statusLabel, sourceLabel, imageNameLabel, headlineValue].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        [editButton, duplicateButton, deleteButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        WorkspaceUI.stylePrimaryButton(
            editButton,
            symbol: "pencil"
        )
        WorkspaceUI.styleSecondaryButton(
            duplicateButton,
            symbol: "doc.on.doc"
        )
        WorkspaceUI.styleDangerButton(
            deleteButton,
            symbol: "trash"
        )

        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        statusLabel.font = .boldSystemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let sourceTitle = makeSectionTitle("Source View")
        let imageTitle = makeSectionTitle("Image")
        let primaryTitle = makeSectionTitle("Primary Text")
        let headlineTitle = makeSectionTitle("Headline")
        let descriptionTitle = makeSectionTitle("Description")

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.backgroundColor =
            WorkspaceUI.raisedSurface.cgColor
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor =
            WorkspaceUI.border.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        primaryTextView.isEditable = false
        primaryTextView.drawsBackground = false
        primaryTextView.font = .systemFont(ofSize: 14)
        descriptionTextView.isEditable = false
        descriptionTextView.drawsBackground = false
        descriptionTextView.font = .systemFont(ofSize: 14)

        let primaryScroll = wrapTextView(primaryTextView)
        let descriptionScroll = wrapTextView(descriptionTextView)

        let sourceButton = NSButton(title: "Hiện trong Finder", target: self, action: #selector(revealSource))
        let imageButton = NSButton(title: "Hiện trong Finder", target: self, action: #selector(revealImage))
        WorkspaceUI.styleSecondaryButton(
            sourceButton,
            symbol: "folder"
        )
        WorkspaceUI.styleSecondaryButton(
            imageButton,
            symbol: "folder"
        )
        sourceButton.translatesAutoresizingMaskIntoConstraints = false
        imageButton.translatesAutoresizingMaskIntoConstraints = false

        let all: [NSView] = [
            nameLabel, statusLabel, editButton, duplicateButton, deleteButton,
            sourceTitle, sourceLabel, sourceButton,
            imageTitle, imageView, imageNameLabel, imageButton,
            primaryTitle, primaryScroll,
            headlineTitle, headlineValue,
            descriptionTitle, descriptionScroll
        ]
        all.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            right.addSubview($0)
        }

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.maximumNumberOfLines = 1
        imageNameLabel.lineBreakMode = .byTruncatingMiddle
        imageNameLabel.maximumNumberOfLines = 1
        headlineValue.lineBreakMode = .byTruncatingTail
        headlineValue.maximumNumberOfLines = 2

        [
            nameLabel,
            sourceLabel,
            imageNameLabel,
            headlineValue
        ].forEach {
            $0.setContentHuggingPriority(
                .defaultLow,
                for: .horizontal
            )
            $0.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )
        }

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 20),
            nameLabel.topAnchor.constraint(equalTo: right.topAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),

            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),

            editButton.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            editButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),

            duplicateButton.leadingAnchor.constraint(equalTo: editButton.trailingAnchor, constant: 8),
            duplicateButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),

            deleteButton.leadingAnchor.constraint(equalTo: duplicateButton.trailingAnchor, constant: 8),
            deleteButton.centerYAnchor.constraint(equalTo: editButton.centerYAnchor),
            deleteButton.trailingAnchor.constraint(lessThanOrEqualTo: right.trailingAnchor, constant: -20),

            sourceTitle.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sourceTitle.topAnchor.constraint(equalTo: editButton.bottomAnchor, constant: 22),

            sourceLabel.leadingAnchor.constraint(equalTo: sourceTitle.leadingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: sourceTitle.bottomAnchor, constant: 8),
            sourceLabel.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),

            sourceButton.leadingAnchor.constraint(equalTo: sourceTitle.leadingAnchor),
            sourceButton.topAnchor.constraint(equalTo: sourceLabel.bottomAnchor, constant: 8),

            imageTitle.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            imageTitle.topAnchor.constraint(equalTo: sourceButton.bottomAnchor, constant: 20),

            imageView.leadingAnchor.constraint(equalTo: imageTitle.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: imageTitle.bottomAnchor, constant: 8),
            imageView.widthAnchor.constraint(equalToConstant: 190),
            imageView.heightAnchor.constraint(equalToConstant: 143),

            imageNameLabel.leadingAnchor.constraint(equalTo: imageTitle.leadingAnchor),
            imageNameLabel.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),
            imageNameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),

            imageButton.leadingAnchor.constraint(equalTo: imageTitle.leadingAnchor),
            imageButton.topAnchor.constraint(equalTo: imageNameLabel.bottomAnchor, constant: 8),

            primaryTitle.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            primaryTitle.topAnchor.constraint(equalTo: imageButton.bottomAnchor, constant: 20),

            primaryScroll.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            primaryScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),
            primaryScroll.topAnchor.constraint(equalTo: primaryTitle.bottomAnchor, constant: 8),
            primaryScroll.heightAnchor.constraint(equalToConstant: 105),

            headlineTitle.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            headlineTitle.topAnchor.constraint(equalTo: primaryScroll.bottomAnchor, constant: 18),

            headlineValue.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            headlineValue.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),
            headlineValue.topAnchor.constraint(equalTo: headlineTitle.bottomAnchor, constant: 8),

            descriptionTitle.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descriptionTitle.topAnchor.constraint(equalTo: headlineValue.bottomAnchor, constant: 18),

            descriptionScroll.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descriptionScroll.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -20),
            descriptionScroll.topAnchor.constraint(equalTo: descriptionTitle.bottomAnchor, constant: 8),
            descriptionScroll.heightAnchor.constraint(equalToConstant: 110),
            descriptionScroll.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -20)
        ])
    }

    func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    func wrapTextView(_ textView: NSTextView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        WorkspaceUI.styleScrollSurface(scroll, radius: 9)
        scroll.documentView = textView
        return scroll
    }

    func reloadData() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let base: [CampaignRecord]
        if q.isEmpty {
            base = store.records
        } else {
            base = store.records.filter {
                $0.name.localizedCaseInsensitiveContains(q) ||
                $0.headline.localizedCaseInsensitiveContains(q)
            }
        }

        filtered = base.sorted {
            let lhs = $0.stt ?? Int.max
            let rhs = $1.stt ?? Int.max
            if lhs == rhs {
                return $0.createdAt < $1.createdAt
            }
            return lhs < rhs
        }

        // Remove checked IDs that no longer exist.
        let existingIDs = Set(store.records.map { $0.id })
        checkedForDeletion = checkedForDeletion.intersection(existingIDs)

        updateBulkDeleteButtons()
        tableView.reloadData()
    }

    func updateBulkDeleteButtons() {
        let count = checkedForDeletion.count
        deleteCheckedButton.title = count > 0 ? "Xóa chọn (\(count))" : "Xóa chọn"
        deleteCheckedButton.isEnabled = count > 0
        deleteAllButton.isEnabled = !store.records.isEmpty
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = filtered[row]
        guard let columnID = tableColumn?.identifier.rawValue else { return nil }

        if columnID == "check" {
            let cell = NSTableCellView(frame: .zero)
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleDeleteCheck(_:))
            )
            checkbox.state = checkedForDeletion.contains(record.id) ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(checkbox)

            NSLayoutConstraint.activate([
                checkbox.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])

            return cell
        }

        let cell = NSTableCellView(frame: .zero)
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true

        switch columnID {
        case "stt":
            label.stringValue = "\(record.stt ?? 0)"
            label.font = .boldSystemFont(ofSize: 13)
            label.alignment = .center

        case "name":
            label.stringValue = record.name.isEmpty ? "Chưa đặt tên" : record.name
            label.font = .boldSystemFont(ofSize: 13)

        case "status":
            let isNew =
                ImportBatchHelper.isLatestImport(
                    record,
                    in: store.records
                )

            label.stringValue =
                ImportBatchHelper.dataLabel(
                    for: record,
                    in: store.records
                )
            label.font = .boldSystemFont(ofSize: 12)
            label.alignment = .center

            if !record.isReady {
                label.textColor = .systemOrange
            } else if isNew {
                label.textColor = .systemBlue
            } else {
                label.textColor = .secondaryLabelColor
            }

        default:
            label.stringValue = ""
        }

        cell.textField = label
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: columnID == "stt" ? 2 : 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: columnID == "stt" ? -2 : -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    @objc func toggleDeleteCheck(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw) else { return }

        if sender.state == .on {
            checkedForDeletion.insert(id)
        } else {
            checkedForDeletion.remove(id)
        }

        updateBulkDeleteButtons()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow

        // Capture the geometry BEFORE changing detail content.
        let dividerPosition =
            dataSplitView.subviews.first?.frame.width

        let horizontalOrigin =
            tableView.enclosingScrollView?
                .contentView
                .bounds
                .origin

        if row >= 0 && row < filtered.count {
            selectedRecord = filtered[row]
            showDetail(selectedRecord)
        } else {
            selectedRecord = nil
            showDetail(nil)
        }

        restoreDataManagerViewport(
            dividerPosition: dividerPosition,
            horizontalOrigin: horizontalOrigin
        )
    }

    private func restoreDataManagerViewport(
        dividerPosition: CGFloat?,
        horizontalOrigin: NSPoint?
    ) {
        let restore: () -> Void = { [weak self] in
            guard let self else {
                return
            }

            if let dividerPosition,
               self.dataSplitView.subviews.count >= 2 {
                let available =
                    self.dataSplitView.bounds.width

                let minimumLeft: CGFloat = 340
                let minimumRight: CGFloat = 390

                let maximumLeft =
                    max(
                        minimumLeft,
                        available - minimumRight
                    )

                let safePosition =
                    min(
                        max(
                            dividerPosition,
                            minimumLeft
                        ),
                        maximumLeft
                    )

                self.dataSplitView.setPosition(
                    safePosition,
                    ofDividerAt: 0
                )
            }

            if let horizontalOrigin,
               let scrollView =
                    self.tableView.enclosingScrollView {
                scrollView.contentView.scroll(
                    to: horizontalOrigin
                )
                scrollView.reflectScrolledClipView(
                    scrollView.contentView
                )
            }
        }

        // AppKit may recalculate fitting sizes after the string/image changes.
        // Restore now and again on the next runloop.
        restore()
        DispatchQueue.main.async {
            restore()
        }
    }

    func showDetail(_ record: CampaignRecord?) {
        guard let record else {
            nameLabel.stringValue = "Chọn một dữ liệu"
            statusLabel.stringValue = ""
            sourceLabel.stringValue = "—"
            imageNameLabel.stringValue = "—"
            imageView.image = nil
            primaryTextView.string = ""
            headlineValue.stringValue = "—"
            descriptionTextView.string = ""
            return
        }

        nameLabel.stringValue = record.name.isEmpty ? "Chưa đặt tên" : record.name
        statusLabel.stringValue =
            ImportBatchHelper.dataLabel(
                for: record,
                in: store.records
            )

        if !record.isReady {
            statusLabel.textColor = .systemOrange
        } else if ImportBatchHelper.isLatestImport(
            record,
            in: store.records
        ) {
            statusLabel.textColor = .systemBlue
        } else {
            statusLabel.textColor = .secondaryLabelColor
        }

        sourceLabel.stringValue = record.sourceOriginalName.isEmpty ? "Chưa có Source View" : record.sourceOriginalName
        imageNameLabel.stringValue = record.imageOriginalName.isEmpty ? "Chưa có ảnh" : record.imageOriginalName
        if let url = store.imageURL(for: record) {
            imageView.image = NSImage(contentsOf: url)
        } else {
            imageView.image = nil
        }
        primaryTextView.string = record.primaryText
        headlineValue.stringValue = record.headline.isEmpty ? "—" : record.headline
        descriptionTextView.string = record.descriptionText

        // Show each newly selected detail from the top without touching
        // master pane width or table scroll position.
        if let scrollView = dataDetailScrollView {
            scrollView.contentView.scroll(
                to: NSPoint(
                    x: 0,
                    y: 0
                )
            )
            scrollView.reflectScrolledClipView(
                scrollView.contentView
            )
        }
    }


    @objc func importFolderBatch() {
        guard !bulkImportInProgress else { return }

        let panel = NSOpenPanel()
        panel.title = "Chọn NHIỀU folder Quiz cùng lúc"
        panel.message =
            "Giữ Command hoặc Shift để chọn nhiều folder. " +
            "Mỗi folder được quét đệ quy. " +
            "Source trùng name → 1 Content; nhiều Creative vẫn giữ CT1_/CT2_/..."
        panel.prompt = "Import Hàng Loạt"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        panel.begin { [weak self] response in
            guard let self,
                  response == .OK,
                  !panel.urls.isEmpty else {
                return
            }

            // De-duplicate the exact same selected folder path while
            // preserving Finder selection order.
            var seenRootPaths = Set<String>()
            let rootURLs = panel.urls.filter {
                let path =
                    $0.standardizedFileURL.path

                return seenRootPaths
                    .insert(path)
                    .inserted
            }

            guard !rootURLs.isEmpty else {
                return
            }

            self.bulkImportInProgress = true
            self.importFolderButton.isEnabled = false
            self.importFolderButton.title =
                "Đang quét \(rootURLs.count) folder..."

            let existing = self.store.records
            let recordsDirectory =
                self.store.recordsDirectory

            DispatchQueue.global(
                qos: .userInitiated
            ).async {
                let service =
                    BulkImportService()

                var allItems:
                    [BulkImportItem] = []
                var allIssues:
                    [BulkImportIssue] = []

                // This also protects against selecting both a parent folder
                // and one of its child folders in the same Finder dialog.
                var seenImportedItems =
                    Set<String>()

                for rootURL in rootURLs {
                    let partial =
                        service.scan(
                            rootURL: rootURL
                        )

                    allIssues.append(
                        contentsOf:
                            partial.issues
                    )

                    for item in partial.items {
                        let signature = [
                            BulkImportService
                                .normalizedName(
                                    item.contentGroupName
                                ),
                            item.sourceFingerprint,
                            item.creativeFingerprint
                        ].joined(
                            separator: "|"
                        )

                        if seenImportedItems
                            .insert(signature)
                            .inserted {
                            allItems.append(
                                item
                            )
                        }
                    }
                }

                let scan =
                    BulkImportScanResult(
                        items: allItems,
                        issues: allIssues
                    )

                let prepared =
                    service.prepare(
                        scan: scan,
                        existingRecords:
                            existing,
                        recordsDirectory:
                            recordsDirectory
                    )

                DispatchQueue.main.async {
                    defer {
                        self.bulkImportInProgress =
                            false
                        self.importFolderButton
                            .isEnabled = true
                        self.importFolderButton
                            .title =
                            "Import Folder Hàng Loạt"
                    }

                    do {
                        self.store.records =
                            prepared.records
                        try self.store.persist()

                        self.checkedForDeletion
                            .removeAll()
                        self.selectedRecord = nil
                        self.reloadData()
                        self.showDetail(nil)

                        self.showBulkImportSummary(
                            rootURLs: rootURLs,
                            scan: scan,
                            prepared: prepared
                        )

                    } catch {
                        self.showError(
                            "Import đã copy file nhưng không " +
                            "lưu được records.json: " +
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    private func showBulkImportSummary(
        rootURLs: [URL],
        scan: BulkImportScanResult,
        prepared: BulkImportPreparedResult
    ) {
        let alert = NSAlert()
        alert.messageText =
            "Import hàng loạt hoàn tất"

        let selectedNames =
            rootURLs.map {
                $0.lastPathComponent
            }

        var folderSummary =
            "Folder đã chọn: \(rootURLs.count)"

        if !selectedNames.isEmpty {
            let preview =
                selectedNames
                    .prefix(5)
                    .joined(
                        separator: ", "
                    )

            folderSummary +=
                "\n\(preview)"

            if selectedNames.count > 5 {
                folderSummary +=
                    "\n... +\(selectedNames.count - 5) folder khác"
            }
        }

        var lines: [String] = [
            folderSummary,
            "",
            "Source / Content group: \(scan.uniqueContentGroupCount)",
            "Creative hợp lệ: \(scan.items.count)",
            "DATA MỚI: \(prepared.createdCount)",
            "Tạo mới Creative record: \(prepared.createdCount)",
            "Cập nhật Creative đã import trước: \(prepared.updatedCount)",
            "Bỏ qua / lỗi: \(prepared.issues.count)"
        ]

        if !scan.items.isEmpty {
            // Count each unique Source only once, even when that Source has
            // CT1/CT2/CT3... Creative variants.
            var seenSources =
                Set<String>()

            let totalQuestions =
                scan.items.reduce(0) {
                    partial,
                    item in

                    guard seenSources
                        .insert(
                            item.sourceFingerprint
                        )
                        .inserted else {
                        return partial
                    }

                    return partial +
                        item.sourceQuestionCount
                }

            lines.append(
                "Tổng câu hỏi Source đã đọc: \(totalQuestions)"
            )
        }

        if !prepared.issues.isEmpty {
            lines.append("")
            lines.append("Chi tiết lỗi/bỏ qua:")

            for issue in prepared.issues.prefix(12) {
                lines.append("• \(issue.message)")
            }

            if prepared.issues.count > 12 {
                lines.append(
                    "• ... và " +
                    "\(prepared.issues.count - 12) lỗi khác."
                )
            }
        }

        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "OK")

        if let hostWindow =
                tableView.window ??
                detailView.window ??
                searchField.window {
            alert.beginSheetModal(
                for: hostWindow,
                completionHandler: nil
            )
        } else {
            alert.runModal()
        }
    }

    @objc func addRecord() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        guard activeEditor == nil else {
            activeEditor?.window?.makeKeyAndOrderFront(nil)
            return
        }

        let editor = EditorWindowController(
            store: store,
            record: nil
        ) { [weak self] in
            self?.reloadData()
        }

        presentEditorAsSheet(editor)
    }

    @objc func editSelected() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        guard let record = selectedRecord else { return }

        guard activeEditor == nil else {
            activeEditor?.window?.makeKeyAndOrderFront(nil)
            return
        }

        let editor = EditorWindowController(
            store: store,
            record: record
        ) { [weak self] in
            self?.reloadData()

            if let updated = self?.store.records.first(
                where: { $0.id == record.id }
            ) {
                self?.selectedRecord = updated
                self?.showDetail(updated)
            }
        }

        presentEditorAsSheet(editor)
    }

    private func presentEditorAsSheet(_ editor: EditorWindowController) {
        guard let editorWindow = editor.window else { return }

        // In the combined app, tableView.window is the real visible
        // Ethopex Workspace window. self.window is the hidden shell window
        // from the original standalone module, so do not attach the sheet to it.
        guard let hostWindow =
            tableView.window ??
            detailView.window ??
            searchField.window else {
            // Safe non-modal fallback: never enter an application-wide modal loop.
            activeEditor = editor
            editor.showWindow(nil)
            editor.window?.makeKeyAndOrderFront(nil)
            return
        }

        activeEditor = editor

        hostWindow.beginSheet(editorWindow) { [weak self, weak editor] _ in
            editor?.window?.orderOut(nil)
            self?.activeEditor = nil
        }
    }

    @objc func duplicateSelected() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        guard let record = selectedRecord else { return }
        do {
            _ = try store.duplicate(record)
            reloadData()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func deleteSelected() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        guard let record = selectedRecord else { return }

        let alert = NSAlert()
        alert.messageText = "Xóa dữ liệu này?"
        alert.informativeText = "Source View và ảnh đã copy vào app cũng sẽ bị xóa."
        alert.addButton(withTitle: "Xóa")
        alert.addButton(withTitle: "Hủy")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try store.delete(record)
                checkedForDeletion.remove(record.id)
                selectedRecord = nil
                reloadData()
                showDetail(nil)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }


    @objc func deleteCheckedRecords() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        let ids = checkedForDeletion
        guard !ids.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Xóa \(ids.count) dữ liệu đã chọn?"
        alert.informativeText = "Source View và Image đã lưu trong app của các dữ liệu này cũng sẽ bị xóa. STT còn lại sẽ tự đánh lại từ 1."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Xóa đã chọn")
        alert.addButton(withTitle: "Hủy")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.delete(ids: ids)

            if let selectedRecord, ids.contains(selectedRecord.id) {
                self.selectedRecord = nil
                showDetail(nil)
            }

            checkedForDeletion.removeAll()
            reloadData()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func deleteAllRecords() {
        guard !bulkImportInProgress else {
            showError("Đang import hàng loạt. Hãy đợi import hoàn tất.")
            return
        }
        guard !store.records.isEmpty else { return }

        let total = store.records.count
        let alert = NSAlert()
        alert.messageText = "Xóa tất cả \(total) dữ liệu?"
        alert.informativeText = "Thao tác này sẽ xóa toàn bộ record, Source View và Image đã copy vào Ethopex Data Manager. Không thể hoàn tác."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "XÓA TẤT CẢ")
        alert.addButton(withTitle: "Hủy")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.deleteAll()
            checkedForDeletion.removeAll()
            selectedRecord = nil
            reloadData()
            showDetail(nil)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openDataFolder() {
        NSWorkspace.shared.open(store.baseDirectory)
    }

    @objc func revealSource() {
        guard let record = selectedRecord, let url = store.sourceURL(for: record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func revealImage() {
        guard let record = selectedRecord, let url = store.imageURL(for: record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Có lỗi xảy ra"
        alert.informativeText = message
        alert.runModal()
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let store: DataStore
    let existing: CampaignRecord?
    let onSaved: () -> Void

    let nameField = NSTextField()
    let sourceLabel = NSTextField(labelWithString: "Chưa chọn file")
    let imageLabel = NSTextField(labelWithString: "Chưa chọn ảnh")
    let imageView = NSImageView()
    let primaryTextView = NSTextView()
    let headlineField = NSTextField()
    let descriptionTextView = NSTextView()

    var selectedSourceURL: URL?
    var selectedImageURL: URL?

    init(store: DataStore, record: CampaignRecord?, onSaved: @escaping () -> Void) {
        self.store = store
        self.existing = record
        self.onSaved = onSaved

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = record == nil ? "Thêm dữ liệu" : "Sửa dữ liệu"
        window.center()

        super.init(window: window)
        window.delegate = self
        setupUI()
        populate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setupUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        let canvas = NSView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = canvas

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            canvas.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        var yAnchor = canvas.topAnchor

        func addTitle(_ text: String, top: CGFloat = 18) -> NSTextField {
            let t = NSTextField(labelWithString: text)
            t.font = .boldSystemFont(ofSize: 14)
            t.translatesAutoresizingMaskIntoConstraints = false
            canvas.addSubview(t)
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 22),
                t.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -22),
                t.topAnchor.constraint(equalTo: yAnchor, constant: top)
            ])
            yAnchor = t.bottomAnchor
            return t
        }

        func addField(_ field: NSView, height: CGFloat = 28, top: CGFloat = 8) {
            field.translatesAutoresizingMaskIntoConstraints = false
            canvas.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: 22),
                field.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -22),
                field.topAnchor.constraint(equalTo: yAnchor, constant: top),
                field.heightAnchor.constraint(equalToConstant: height)
            ])
            yAnchor = field.bottomAnchor
        }

        addTitle("Name")
        nameField.placeholderString = "Ví dụ: Bible_Quiz_US_01"
        addField(nameField)

        addTitle("1. Source View")
        let sourceRow = NSView()
        let chooseSource = NSButton(title: "Chọn Source View…", target: self, action: #selector(chooseSourceFile))
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        chooseSource.translatesAutoresizingMaskIntoConstraints = false
        sourceRow.addSubview(sourceLabel)
        sourceRow.addSubview(chooseSource)
        NSLayoutConstraint.activate([
            sourceLabel.leadingAnchor.constraint(equalTo: sourceRow.leadingAnchor),
            sourceLabel.centerYAnchor.constraint(equalTo: sourceRow.centerYAnchor),
            chooseSource.trailingAnchor.constraint(equalTo: sourceRow.trailingAnchor),
            chooseSource.centerYAnchor.constraint(equalTo: sourceRow.centerYAnchor),
            sourceLabel.trailingAnchor.constraint(lessThanOrEqualTo: chooseSource.leadingAnchor, constant: -8)
        ])
        addField(sourceRow, height: 34)

        addTitle("2. Image")
        let imageRow = NSView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = WorkspaceUI.raisedSurface.cgColor
        imageView.layer?.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageLabel.translatesAutoresizingMaskIntoConstraints = false
        let chooseImage = NSButton(title: "Chọn ảnh…", target: self, action: #selector(chooseImageFile))
        chooseImage.translatesAutoresizingMaskIntoConstraints = false
        imageRow.addSubview(imageView)
        imageRow.addSubview(imageLabel)
        imageRow.addSubview(chooseImage)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageRow.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: imageRow.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageRow.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 210),
            imageLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 14),
            imageLabel.trailingAnchor.constraint(equalTo: imageRow.trailingAnchor),
            imageLabel.topAnchor.constraint(equalTo: imageRow.topAnchor, constant: 12),
            chooseImage.leadingAnchor.constraint(equalTo: imageLabel.leadingAnchor),
            chooseImage.topAnchor.constraint(equalTo: imageLabel.bottomAnchor, constant: 12)
        ])
        addField(imageRow, height: 160)

        addTitle("3. Primary Text")
        let primaryScroll = makeEditorScroll(primaryTextView)
        addField(primaryScroll, height: 110)

        addTitle("4. Headline")
        addField(headlineField)

        addTitle("5. Description")
        let descScroll = makeEditorScroll(descriptionTextView)
        addField(descScroll, height: 90)

        let status = NSTextField(labelWithString: "Bạn có thể lưu khi chưa đủ dữ liệu. Record sẽ ở trạng thái INCOMPLETE.")
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        addField(status, height: 24, top: 16)

        let buttons = NSView()
        let cancel = NSButton(title: "Hủy", target: self, action: #selector(cancelAction))
        let save = NSButton(title: "Lưu", target: self, action: #selector(saveAction))
        save.keyEquivalent = "\r"
        cancel.translatesAutoresizingMaskIntoConstraints = false
        save.translatesAutoresizingMaskIntoConstraints = false
        buttons.addSubview(cancel)
        buttons.addSubview(save)
        NSLayoutConstraint.activate([
            save.trailingAnchor.constraint(equalTo: buttons.trailingAnchor),
            save.centerYAnchor.constraint(equalTo: buttons.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: buttons.centerYAnchor)
        ])
        addField(buttons, height: 40, top: 16)

        canvas.bottomAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 20).isActive = true
    }

    func makeEditorScroll(_ textView: NSTextView) -> NSScrollView {
        textView.font = .systemFont(ofSize: 14)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        return scroll
    }

    func populate() {
        guard let r = existing else { return }
        nameField.stringValue = r.name
        sourceLabel.stringValue = r.sourceOriginalName.isEmpty ? "Chưa chọn file" : r.sourceOriginalName
        imageLabel.stringValue = r.imageOriginalName.isEmpty ? "Chưa chọn ảnh" : r.imageOriginalName
        primaryTextView.string = r.primaryText
        headlineField.stringValue = r.headline
        descriptionTextView.string = r.descriptionText
        if let url = store.imageURL(for: r) {
            imageView.image = NSImage(contentsOf: url)
        }
    }

    @objc func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.title = "Chọn Source View"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            self?.selectedSourceURL = url
            self?.sourceLabel.stringValue = url.lastPathComponent
        }
    }

    @objc func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.title = "Chọn ảnh Creative"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image]
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            self?.selectedImageURL = url
            self?.imageLabel.stringValue = url.lastPathComponent

            // Keep UI responsive when previewing a large local image.
            DispatchQueue.global(qos: .userInitiated).async {
                let image = NSImage(contentsOf: url)

                DispatchQueue.main.async { [weak self] in
                    guard self?.selectedImageURL == url else { return }
                    self?.imageView.image = image
                }
            }
        }
    }

    @objc func cancelAction() {
        finishEditor(with: .cancel)
    }

    private func finishEditor(
        with response: NSApplication.ModalResponse
    ) {
        guard let window else { return }

        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: response)
            return
        }

        // Standalone/non-modal fallback.
        // Never leave a global modal loop behind.
        if NSApp.modalWindow === window {
            NSApp.stopModal(withCode: response)
        }

        window.orderOut(nil)
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let parent = sender.sheetParent {
            parent.endSheet(sender, returnCode: .cancel)
            return false
        }

        if NSApp.modalWindow === sender {
            NSApp.stopModal(withCode: .cancel)
        }

        return true
    }

    @objc func saveAction() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Bạn cần nhập Name"
            alert.runModal()
            return
        }

        do {
            _ = try store.save(
                existing: existing,
                name: name,
                sourceURL: selectedSourceURL,
                imageURL: selectedImageURL,
                primaryText: primaryTextView.string,
                headline: headlineField.stringValue,
                descriptionText: descriptionTextView.string
            )
            onSaved()
            finishEditor(with: .OK)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Không thể lưu"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
