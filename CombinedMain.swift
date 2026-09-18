import AppKit
import Foundation
import UniformTypeIdentifiers


final class WorkspaceVerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(
        forBounds rect: NSRect
    ) -> NSRect {
        var drawingRect =
            super.drawingRect(
                forBounds: rect
            )

        let textSize =
            cellSize(
                forBounds: rect
            )

        let heightDelta =
            drawingRect.height -
            textSize.height

        if heightDelta > 0 {
            drawingRect.origin.y +=
                floor(heightDelta / 2.0)

            drawingRect.size.height =
                textSize.height
        }

        return drawingRect
    }
}


enum WorkspaceUI {
    static let cornerRadius: CGFloat = 12

    // Future-console palette. Keep the workflow logic untouched while giving
    // every module the same visual language: deep graphite surfaces, soft
    // borders and bright operational accents.
    static let canvas = NSColor(
        calibratedRed: 0.035,
        green: 0.047,
        blue: 0.075,
        alpha: 1
    )
    static let surface = NSColor(
        calibratedRed: 0.075,
        green: 0.090,
        blue: 0.135,
        alpha: 1
    )
    static let raisedSurface = NSColor(
        calibratedRed: 0.105,
        green: 0.125,
        blue: 0.180,
        alpha: 1
    )
    static let border = NSColor(
        calibratedWhite: 1,
        alpha: 0.10
    )
    static let cyan = NSColor(
        calibratedRed: 0.22,
        green: 0.86,
        blue: 0.96,
        alpha: 1
    )
    static let violet = NSColor(
        calibratedRed: 0.68,
        green: 0.45,
        blue: 1.0,
        alpha: 1
    )

    static func styleSurface(
        _ view: NSView,
        radius: CGFloat = cornerRadius
    ) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = surface.cgColor
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = border.cgColor
    }

    static func stylePrimaryButton(
        _ button: NSButton,
        symbol: String? = nil
    ) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .boldSystemFont(ofSize: 12)
        button.bezelColor = .controlAccentColor
        button.contentTintColor = .white

        if let symbol {
            button.image =
                NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: nil
                )
            button.imagePosition = .imageLeading
        }
    }

    static func styleSecondaryButton(
        _ button: NSButton,
        symbol: String? = nil
    ) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12, weight: .medium)

        if let symbol {
            button.image =
                NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: nil
                )
            button.imagePosition = .imageLeading
        }
    }

    static func styleAccentButton(
        _ button: NSButton,
        tint: NSColor,
        symbol: String? = nil,
        filled: Bool = false
    ) {
        styleSecondaryButton(
            button,
            symbol: symbol
        )

        if filled {
            button.font =
                .systemFont(
                    ofSize: 12,
                    weight: .semibold
                )
            button.bezelColor = tint
            button.contentTintColor = .white
        } else {
            button.contentTintColor = tint
        }
    }

    static func styleTintedSurface(
        _ view: NSView,
        tint: NSColor,
        radius: CGFloat = 11
    ) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor =
            NSColor(
                calibratedRed: 0.09,
                green: 0.105,
                blue: 0.155,
                alpha: 1
            ).cgColor
        view.layer?.borderWidth = 0.7
        view.layer?.borderColor =
            tint.withAlphaComponent(0.34).cgColor
    }

    static func styleDangerButton(
        _ button: NSButton,
        symbol: String? = nil
    ) {
        styleSecondaryButton(button, symbol: symbol)
        button.contentTintColor = .systemRed
    }

    static func styleScrollSurface(
        _ scroll: NSScrollView,
        radius: CGFloat = cornerRadius
    ) {
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = canvas
        styleSurface(scroll, radius: radius)
    }

    static func verticallyCenterText(
        in field: NSTextField
    ) {
        if field.cell is WorkspaceVerticallyCenteredTextFieldCell {
            return
        }

        let oldCell = field.cell

        let cell =
            WorkspaceVerticallyCenteredTextFieldCell(
                textCell: field.stringValue
            )

        cell.font =
            oldCell?.font ??
            field.font

        cell.alignment =
            oldCell?.alignment ??
            field.alignment

        cell.lineBreakMode =
            oldCell?.lineBreakMode ??
            .byTruncatingTail

        cell.usesSingleLineMode = true
        cell.isEditable = false
        cell.isSelectable = false
        cell.isBezeled = false
        cell.isBordered = false

        field.cell = cell
    }

    static func styleBadge(
        _ field: NSTextField,
        textColor: NSColor,
        backgroundColor: NSColor
    ) {
        verticallyCenterText(
            in: field
        )
        field.font = .boldSystemFont(ofSize: 11)
        field.alignment = .center
        field.textColor = textColor
        field.drawsBackground = true
        field.backgroundColor = backgroundColor
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.masksToBounds = true
    }
}

final class CombinedWindowController: NSWindowController {
    private let modeControl = NSSegmentedControl(
        labels: ["DỮ LIỆU", "CAMPAIGN AUTOMATION"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private let titleLabel = NSTextField(labelWithString: "Ethopex Workspace")
    private let subtitleLabel = NSTextField(labelWithString: "Operations Workspace  •  Data + Campaign Monitoring  •  v1.10.2")
    private let container = NSView()
    private let loadingLabel = NSTextField(labelWithString: "Đang tải...")
    private let updateVersionButton = NSButton()
    private let updater = WorkspaceUpdater()

    // V1.1: Lazy module loading. Do NOT create both large windows at startup.
    private var dataManagerController: DataManagerWindowController?
    private var campaignController: CampaignWindowController?

    private var dataManagerView: NSView?
    private var campaignView: NSView?

    private var currentIndex = -1

    convenience init() {
        let fallbackVisible =
            NSRect(
                x: 0,
                y: 0,
                width: 1440,
                height: 900
            )

        let visible =
            NSScreen.main?.visibleFrame ??
            fallbackVisible

        // V1.6.6.4 — never create a window larger than the user's screen.
        // Keep comfortable desktop dimensions on large displays, but fit
        // automatically on MacBook / smaller external displays.
        let targetWidth =
            min(
                1480,
                max(
                    920,
                    visible.width * 0.94
                )
            )

        let targetHeight =
            min(
                920,
                max(
                    660,
                    visible.height * 0.90
                )
            )

        let minWidth =
            max(
                780,
                min(
                    980,
                    visible.width * 0.72
                )
            )

        let minHeight =
            max(
                600,
                min(
                    680,
                    visible.height * 0.70
                )
            )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: targetHeight
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

        window.title = "Ethopex Workspace"
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize =
            NSSize(
                width: minWidth,
                height: minHeight
            )

        let frame = NSRect(
            x: visible.midX - targetWidth / 2,
            y: visible.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        window.setFrame(frame, display: false)

        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let root = window?.contentView else { return }

        root.wantsLayer = true
        root.layer?.backgroundColor =
            WorkspaceUI.canvas.cgColor

        container.wantsLayer = true

        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor =
            WorkspaceUI.surface.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(container)

        titleLabel.font = .systemFont(ofSize: 23, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        updateVersionButton.title = "Update"
        WorkspaceUI.styleSecondaryButton(
            updateVersionButton,
            symbol: "arrow.triangle.2.circlepath"
        )
        updateVersionButton.target = self
        updateVersionButton.action = #selector(updateVersionAction)
        updateVersionButton.translatesAutoresizingMaskIntoConstraints = false

        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.segmentStyle = .rounded
        modeControl.controlSize = .large
        modeControl.font = .systemFont(ofSize: 12, weight: .semibold)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.setWidth(105, forSegment: 0)
        modeControl.setWidth(195, forSegment: 1)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)
        header.addSubview(modeControl)
        header.addSubview(updateVersionButton)
        header.addSubview(separator)

        loadingLabel.font = .systemFont(ofSize: 13)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.alignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.isHidden = true
        container.addSubview(loadingLabel)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 86),

            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: header.bottomAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: updateVersionButton.leadingAnchor,
                constant: -12
            ),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: updateVersionButton.leadingAnchor,
                constant: -12
            ),

            modeControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            modeControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            updateVersionButton.trailingAnchor.constraint(equalTo: modeControl.leadingAnchor, constant: -10),
            updateVersionButton.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            updateVersionButton.widthAnchor.constraint(equalToConstant: 118),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            loadingLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        showMode(index: 0)
    }


    @objc private func updateVersionAction() {
        let panel = NSOpenPanel()
        panel.title = "Chọn Ethopex Update Package"
        panel.message =
            "Chọn file ZIP update do ChatGPT tạo cho Ethopex Workspace."
        panel.prompt = "Kiểm tra Update"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]

        panel.begin { [weak self] response in
            guard let self,
                  response == .OK,
                  let packageURL =
                    panel.url else {
                return
            }

            self.updateVersionButton
                .isEnabled = false
            self.updateVersionButton
                .title = "ĐANG KIỂM TRA..."

            DispatchQueue.global(
                qos: .userInitiated
            ).async {
                do {
                    let prepared =
                        try self.updater.prepare(
                            packageURL:
                                packageURL
                        )

                    DispatchQueue.main.async {
                        self.updateVersionButton
                            .isEnabled = true
                        self.updateVersionButton
                            .title =
                            "Update"

                        self.confirmAndApply(
                            prepared
                        )
                    }

                } catch {
                    DispatchQueue.main.async {
                        self.updateVersionButton
                            .isEnabled = true
                        self.updateVersionButton
                            .title =
                            "Update"

                        let alert =
                            NSAlert()
                        alert.messageText =
                            "Không thể cập nhật"
                        alert.informativeText =
                            error.localizedDescription
                        alert.addButton(
                            withTitle: "OK"
                        )

                        if let window =
                                self.window {
                            alert.beginSheetModal(
                                for: window
                            )
                        } else {
                            alert.runModal()
                        }
                    }
                }
            }
        }
    }

    private func confirmAndApply(
        _ prepared:
            PreparedWorkspaceUpdate
    ) {
        let current =
            updater.currentVersion
        let target =
            prepared.manifest.version

        let alert = NSAlert()
        alert.messageText =
            "Update Ethopex Workspace"

        alert.informativeText =
            "Version hiện tại: \(current)\n" +
            "Version mới: \(target)\n\n" +
            "Tool sẽ backup source hiện tại, gắn update, đóng app và tự build lại version mới."

        alert.addButton(
            withTitle: "Cập nhật"
        )
        alert.addButton(
            withTitle: "Hủy"
        )

        guard let window else {
            updater.cleanup(
                prepared
            )
            return
        }

        alert.beginSheetModal(
            for: window
        ) { [weak self] response in
            guard let self else {
                return
            }

            guard response ==
                    .alertFirstButtonReturn else {
                self.updater.cleanup(
                    prepared
                )
                return
            }

            self.updateVersionButton
                .isEnabled = false
            self.updateVersionButton
                .title =
                "ĐANG UPDATE..."

            DispatchQueue.global(
                qos: .userInitiated
            ).async {
                do {
                    let backup =
                        try self.updater.apply(
                            prepared
                        )

                    self.updater.cleanup(
                        prepared
                    )

                    DispatchQueue.main.async {
                        let done =
                            NSAlert()
                        done.messageText =
                            "Update đã được gắn"
                        done.informativeText =
                            "Backup: \(backup.lastPathComponent)\n\n" +
                            "App sẽ đóng và tự build lại v\(target). Khi build xong version mới sẽ tự mở."

                        done.addButton(
                            withTitle:
                                "Build Version Mới"
                        )

                        done.beginSheetModal(
                            for: window
                        ) { _ in
                            do {
                                try self.updater
                                    .rebuildAndRestart()
                            } catch {
                                self.updateVersionButton
                                    .isEnabled = true
                                self.updateVersionButton
                                    .title =
                                    "Update"

                                let failed =
                                    NSAlert()
                                failed.messageText =
                                    "Không chạy được build tự động"
                                failed.informativeText =
                                    error.localizedDescription +
                                    "\n\nBạn vẫn có thể chạy build.command thủ công."
                                failed.addButton(
                                    withTitle:
                                        "OK"
                                )
                                failed.beginSheetModal(
                                    for: window
                                )
                            }
                        }
                    }

                } catch {
                    self.updater.cleanup(
                        prepared
                    )

                    DispatchQueue.main.async {
                        self.updateVersionButton
                            .isEnabled = true
                        self.updateVersionButton
                            .title =
                            "Update"

                        let failed =
                            NSAlert()
                        failed.messageText =
                            "Update thất bại"
                        failed.informativeText =
                            error.localizedDescription
                        failed.addButton(
                            withTitle: "OK"
                        )
                        failed.beginSheetModal(
                            for: window
                        )
                    }
                }
            }
        }
    }


    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        showMode(index: sender.selectedSegment)
    }

    private func showMode(index: Int) {
        guard index == 0 || index == 1 else { return }

        if currentIndex == index {
            // Only refresh the active module; do not rebuild the view.
            refreshModule(index: index)
            return
        }

        currentIndex = index
        loadingLabel.isHidden = false
        loadingLabel.stringValue = index == 0
            ? "Đang mở Data Manager..."
            : "Đang mở Campaign Automation..."

        // Let the segmented control visually update first.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if index == 0 {
                self.showDataManager()
            } else {
                self.showCampaign()
            }

            self.loadingLabel.isHidden = true
        }
    }

    private func showDataManager() {
        titleLabel.stringValue = "Ethopex Workspace — Data Manager"
        subtitleLabel.stringValue = "Nhập dữ liệu • STT • Source View • Image • Ad copy"

        let view = ensureDataManagerView()

        campaignView?.isHidden = true
        view.isHidden = false

        dataManagerController?.reloadData()
    }

    private func showCampaign() {
        titleLabel.stringValue = "Ethopex Workspace — Campaign Automation"
        subtitleLabel.stringValue = "Test Pipeline → Content → Creative → Campaign • Fanpage batch"

        let view = ensureCampaignView()

        dataManagerView?.isHidden = true
        view.isHidden = false

        campaignController?.reloadRecords()
    }

    private func refreshModule(index: Int) {
        if index == 0 {
            dataManagerController?.reloadData()
        } else {
            campaignController?.reloadRecords()
        }
    }

    private func ensureDataManagerView() -> NSView {
        if let existing = dataManagerView {
            return existing
        }

        let controller = DataManagerWindowController()
        let view = detachContentView(from: controller)

        attachOnce(view)
        dataManagerController = controller
        dataManagerView = view

        return view
    }

    private func ensureCampaignView() -> NSView {
        if let existing = campaignView {
            return existing
        }

        let controller = CampaignWindowController()
        let view = detachContentView(from: controller)

        attachOnce(view)
        campaignController = controller
        campaignView = view

        return view
    }

    private func detachContentView(from controller: NSWindowController) -> NSView {
        guard let childWindow = controller.window,
              let view = childWindow.contentView else {
            let fallback = NSView()
            fallback.translatesAutoresizingMaskIntoConstraints = false
            return fallback
        }

        childWindow.contentView = NSView(frame: .zero)
        childWindow.orderOut(nil)

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func attachOnce(_ view: NSView) {
        container.addSubview(view, positioned: .below, relativeTo: loadingLabel)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CombinedWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let controller = CombinedWindowController()
        self.controller = controller

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "Thoát Ethopex Workspace",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Sửa")
        editMenuItem.submenu = editMenu

        func add(
            _ title: String,
            _ selector: Selector,
            _ key: String,
            modifiers: NSEvent.ModifierFlags = [.command]
        ) {
            let item = NSMenuItem(
                title: title,
                action: selector,
                keyEquivalent: key
            )
            item.keyEquivalentModifierMask = modifiers
            item.target = nil
            editMenu.addItem(item)
        }

        add("Hoàn tác", Selector(("undo:")), "z")
        add("Làm lại", Selector(("redo:")), "z", modifiers: [.command, .shift])
        editMenu.addItem(.separator())
        add("Cắt", #selector(NSText.cut(_:)), "x")
        add("Sao chép", #selector(NSText.copy(_:)), "c")
        add("Dán", #selector(NSText.paste(_:)), "v")
        add("Chọn tất cả", #selector(NSText.selectAll(_:)), "a")

        NSApp.mainMenu = mainMenu
    }
}

@main
struct EthopexWorkspaceEntryPoint {
    static func main() {
        autoreleasepool {
            NSWindow.allowsAutomaticWindowTabbing = false

            let app = NSApplication.shared
            let delegate = AppDelegate()

            app.delegate = delegate
            app.setActivationPolicy(.regular)

            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
