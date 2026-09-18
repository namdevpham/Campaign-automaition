import AppKit
import Foundation
import SwiftUI

final class CampaignWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let dataSource = CampaignDataSource()
    let api = EthopexAPIClient()
    lazy var engine = CampaignEngine(dataSource: dataSource, api: api)

    let tableView = NSTableView()
    let searchField = NSSearchField()
    let summaryLabel = NSTextField(labelWithString: "")
    let apiStatusLabel = NSTextField(labelWithString: "")
    let logView = NSTextView()
    let progress = NSProgressIndicator()
    let headerModel = CampaignHeaderModel()

    // V1.6.6 — Operations Dashboard metrics.
    let metricTotalValue = NSTextField(labelWithString: "0")
    let metricNewValue = NSTextField(labelWithString: "0")
    let metricSelectedValue = NSTextField(labelWithString: "0")
    let metricRunningValue = NSTextField(labelWithString: "0")
    let metricCampaignValue = NSTextField(labelWithString: "0")
    let metricFailedValue = NSTextField(labelWithString: "0")
    let completionProgress = NSProgressIndicator()
    let completionLabel = NSTextField(labelWithString: "0 / 0 campaigns created")
    let runTimeLabel = NSTextField(labelWithString: "TIME 00:00:00")

    // V1.7.2 — Multilingual AUTO runtime tracking.
    var autoRunStartedAt: Date?
    var autoRunTimer: Timer?
    var autoRunSourceCount = 0
    var autoRunPreparedVariantCount = 0
    var autoRunTargetLanguageCount = 0

    // V1.7.3 — CURRENT RUN overview.
    // These counters are session-scoped. A new AUTO run clears the
    // previous run instead of mixing metrics from every historical record.
    var autoRunOverviewActive = false
    var autoRunExpectedVariantCount = 0
    var autoRunOverviewScopeIDs = Set<UUID>()
    var autoRunOverviewNewVariantIDs = Set<UUID>()
    var autoRunOverviewBaselineCampaignIDs: [UUID: String] = [:]
    var autoRunOverviewTerminalIDs = Set<UUID>()
    var autoRunOverviewCreatedCampaignIDs = Set<UUID>()
    var autoRunOverviewFailedIDs = Set<UUID>()
    var autoRunOverviewPreparationFailureCount = 0
    var autoRunOverviewPreparationActive = false
    var autoRunOverviewFinished = false
    var autoRunOverviewRecordIDsBeforePreparation = Set<UUID>()
    var autoRunOverviewInputSourceCount = 0

    let refreshButton = NSButton()
    let selectAllButton = NSButton()
    let selectNewButton = NSButton()
    let clearButton = NSButton()
    let testPipelineButton = NSButton()
    let createContentButton = NSButton()
    let createCreativeButton = NSButton()
    let createCampaignButton = NSButton()
    let selectFailedButton = NSButton()
    let refreshFailureReportButton = NSButton()
    let failureScopeLabel = NSTextField(labelWithString: "LATEST FAILED STATE")
    let failureCountValue = NSTextField(labelWithString: "0")
    let failureSummaryLabel = NSTextField(labelWithString: "Không có lỗi")
    let failureTextView = NSTextView()
    let realtimeFailureCountValue = NSTextField(labelWithString: "0")
    let realtimeFailureTextView = NSTextView()
    var failureReportIDs: [UUID] = []
    var realtimeFailureIDs = Set<UUID>()
    var realtimeFailureMessages: [String] = []
    let displayLinkLabel = NSTextField(labelWithString: "Display link:")
    let displayLinkPopup = NSPopUpButton()

    let fanpageLabel = NSTextField(labelWithString: "Fanpage:")
    let fanpagePopup = NSPopUpButton()
    let refreshPagesButton = NSButton()

    let languagePopupLabel = NSTextField(labelWithString: "Languages:")
    let languagePopupButton = NSButton()
    let languagePopover = NSPopover()
    var languageCheckButtons: [CampaignLanguage: NSButton] = [:]

    let settingsButton = NSButton()

    var apiSettingsController: APISettingsWindowController?
    var filtered: [CampaignRecord] = []
    var selectedIDs = Set<UUID>()
    var statuses: [UUID: JobStatus] = [:]
    var integrationStates: [UUID: IntegrationState] = [:]
    var facebookPages: [EthopexFacebookPageAsset] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1540, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ethopex Campaign Tool"
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1240, height: 760)
        window.center()
        self.init(window: window)
        setupUI()
        reloadRecords()
    }

    func setupUI() {
        guard let content = window?.contentView else { return }

        content.wantsLayer = true
        content.layer?.backgroundColor =
            WorkspaceUI.canvas.cgColor

        let sidebar = NSView()
        let rightColumn = NSView()
        let header = NSView()
        let overview = NSView()
        let tableScroll = NSScrollView()
        let bottom = NSView()

        [sidebar, rightColumn, header, overview, tableScroll, bottom].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        content.addSubview(sidebar)
        content.addSubview(rightColumn)
        [header, overview, tableScroll].forEach {
            rightColumn.addSubview($0)
        }
        sidebar.addSubview(bottom)

        WorkspaceUI.styleSurface(sidebar, radius: 16)
        WorkspaceUI.styleSurface(header)
        WorkspaceUI.styleSurface(overview)
        WorkspaceUI.styleScrollSurface(tableScroll)
        WorkspaceUI.styleSurface(bottom)

        let tableMinimum =
            tableScroll.heightAnchor.constraint(
                greaterThanOrEqualToConstant: 150
            )
        tableMinimum.priority = .defaultHigh

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            sidebar.widthAnchor.constraint(equalToConstant: 310),

            rightColumn.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 12),
            rightColumn.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            rightColumn.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            rightColumn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            header.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            header.topAnchor.constraint(equalTo: rightColumn.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 252),

            overview.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            overview.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            overview.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            overview.heightAnchor.constraint(equalToConstant: 100),

            tableScroll.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: overview.bottomAnchor, constant: 8),
            tableScroll.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor),
            tableMinimum
        ])

        setupSidebar(sidebar, activity: bottom)
        setupModernHeader(header)
        setupOverview(overview)
        setupTable(tableScroll)
        setupBottom(bottom)
    }

    private func setupLegacyFailureSidebar(_ sidebar: NSView) {
        let brandIcon = NSImageView()
        brandIcon.image = NSImage(
            systemSymbolName: "scope",
            accessibilityDescription: "Ethopex Operations"
        )
        brandIcon.contentTintColor = WorkspaceUI.cyan
        brandIcon.translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = NSTextField(labelWithString: "ETHOPEX / OPS")
        eyebrow.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        eyebrow.textColor = WorkspaceUI.cyan
        eyebrow.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Failure Report")
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let version = NSTextField(labelWithString: "CAMPAIGN AUTO  •  v1.11.2")
        version.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        version.textColor = .tertiaryLabelColor
        version.translatesAutoresizingMaskIntoConstraints = false

        failureScopeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        failureScopeLabel.textColor = .systemRed
        failureScopeLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusCard = NSView()
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 10
        statusCard.layer?.backgroundColor = WorkspaceUI.raisedSurface.cgColor
        statusCard.layer?.borderWidth = 0.5
        statusCard.layer?.borderColor = WorkspaceUI.border.cgColor

        let failureCaption = NSTextField(labelWithString: "TOTAL FAILED")
        failureCaption.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        failureCaption.textColor = .tertiaryLabelColor
        failureCaption.translatesAutoresizingMaskIntoConstraints = false

        failureCountValue.font = .systemFont(ofSize: 30, weight: .bold)
        failureCountValue.textColor = .systemRed
        failureCountValue.translatesAutoresizingMaskIntoConstraints = false

        failureSummaryLabel.font = .systemFont(ofSize: 10, weight: .medium)
        failureSummaryLabel.textColor = .secondaryLabelColor
        failureSummaryLabel.maximumNumberOfLines = 3
        failureSummaryLabel.lineBreakMode = .byWordWrapping
        failureSummaryLabel.translatesAutoresizingMaskIntoConstraints = false

        statusCard.addSubview(failureCaption)
        statusCard.addSubview(failureCountValue)
        statusCard.addSubview(failureSummaryLabel)

        failureTextView.isEditable = false
        failureTextView.isSelectable = true
        failureTextView.drawsBackground = true
        failureTextView.backgroundColor = WorkspaceUI.canvas
        failureTextView.textColor = .labelColor
        failureTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        failureTextView.textContainerInset = NSSize(width: 8, height: 8)

        let failureScroll = NSScrollView()
        failureScroll.translatesAutoresizingMaskIntoConstraints = false
        failureScroll.hasVerticalScroller = true
        failureScroll.hasHorizontalScroller = false
        failureScroll.borderType = .noBorder
        failureScroll.drawsBackground = true
        failureScroll.backgroundColor = WorkspaceUI.canvas
        failureScroll.documentView = failureTextView

        let realtimeScopeLabel = NSTextField(labelWithString: "REALTIME FAILED • CURRENT AUTO")
        realtimeScopeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        realtimeScopeLabel.textColor = .systemOrange
        realtimeScopeLabel.translatesAutoresizingMaskIntoConstraints = false

        let realtimeCard = NSView()
        realtimeCard.translatesAutoresizingMaskIntoConstraints = false
        realtimeCard.wantsLayer = true
        realtimeCard.layer?.cornerRadius = 10
        realtimeCard.layer?.backgroundColor = WorkspaceUI.raisedSurface.cgColor
        realtimeCard.layer?.borderWidth = 0.5
        realtimeCard.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor

        let realtimeCaption = NSTextField(labelWithString: "ERRORS DURING LAST AUTO")
        realtimeCaption.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        realtimeCaption.textColor = .tertiaryLabelColor
        realtimeCaption.translatesAutoresizingMaskIntoConstraints = false

        realtimeFailureCountValue.font = .systemFont(ofSize: 24, weight: .bold)
        realtimeFailureCountValue.textColor = .systemOrange
        realtimeFailureCountValue.translatesAutoresizingMaskIntoConstraints = false

        realtimeCard.addSubview(realtimeCaption)
        realtimeCard.addSubview(realtimeFailureCountValue)

        realtimeFailureTextView.isEditable = false
        realtimeFailureTextView.isSelectable = true
        realtimeFailureTextView.drawsBackground = true
        realtimeFailureTextView.backgroundColor = WorkspaceUI.canvas
        realtimeFailureTextView.textColor = .labelColor
        realtimeFailureTextView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        realtimeFailureTextView.textContainerInset = NSSize(width: 8, height: 8)

        let realtimeScroll = NSScrollView()
        realtimeScroll.translatesAutoresizingMaskIntoConstraints = false
        realtimeScroll.hasVerticalScroller = true
        realtimeScroll.hasHorizontalScroller = false
        realtimeScroll.borderType = .noBorder
        realtimeScroll.drawsBackground = true
        realtimeScroll.backgroundColor = WorkspaceUI.canvas
        realtimeScroll.documentView = realtimeFailureTextView

        selectFailedButton.title = "Chọn record FAILED để retry"
        selectFailedButton.target = self
        selectFailedButton.action = #selector(selectFailedRecords)
        selectFailedButton.translatesAutoresizingMaskIntoConstraints = false
        WorkspaceUI.styleAccentButton(
            selectFailedButton,
            tint: .systemRed,
            symbol: "arrow.clockwise"
        )

        refreshFailureReportButton.title = "Làm mới báo cáo"
        refreshFailureReportButton.target = self
        refreshFailureReportButton.action = #selector(refreshFailureReport)
        refreshFailureReportButton.translatesAutoresizingMaskIntoConstraints = false
        WorkspaceUI.styleSecondaryButton(
            refreshFailureReportButton,
            symbol: "arrow.clockwise"
        )

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.cornerRadius = 10
        footer.layer?.backgroundColor = WorkspaceUI.cyan.withAlphaComponent(0.07).cgColor
        footer.layer?.borderWidth = 0.5
        footer.layer?.borderColor = WorkspaceUI.cyan.withAlphaComponent(0.20).cgColor

        let footerTitle = NSTextField(labelWithString: "HOW TO USE")
        footerTitle.font = .systemFont(ofSize: 10, weight: .bold)
        footerTitle.textColor = WorkspaceUI.cyan
        footerTitle.translatesAutoresizingMaskIntoConstraints = false

        let footerText = NSTextField(wrappingLabelWithString: "Chọn lỗi để retry, kiểm tra log chi tiết, sau đó chạy lại TẠO CAMPAIGN AUTO.")
        footerText.font = .systemFont(ofSize: 10, weight: .medium)
        footerText.textColor = .secondaryLabelColor
        footerText.maximumNumberOfLines = 3
        footerText.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(footerTitle)
        footer.addSubview(footerText)
        sidebar.addSubview(brandIcon)
        sidebar.addSubview(eyebrow)
        sidebar.addSubview(title)
        sidebar.addSubview(version)
        sidebar.addSubview(failureScopeLabel)
        sidebar.addSubview(statusCard)
        sidebar.addSubview(failureScroll)
        sidebar.addSubview(realtimeScopeLabel)
        sidebar.addSubview(realtimeCard)
        sidebar.addSubview(realtimeScroll)
        sidebar.addSubview(selectFailedButton)
        sidebar.addSubview(refreshFailureReportButton)
        sidebar.addSubview(footer)

        NSLayoutConstraint.activate([
            brandIcon.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            brandIcon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18),
            brandIcon.widthAnchor.constraint(equalToConstant: 22),
            brandIcon.heightAnchor.constraint(equalToConstant: 22),
            eyebrow.leadingAnchor.constraint(equalTo: brandIcon.trailingAnchor, constant: 9),
            eyebrow.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor),
            eyebrow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            title.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: brandIcon.bottomAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            version.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            version.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            version.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            failureScopeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            failureScopeLabel.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 24),
            failureScopeLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            statusCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            statusCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            statusCard.topAnchor.constraint(equalTo: failureScopeLabel.bottomAnchor, constant: 9),
            statusCard.heightAnchor.constraint(equalToConstant: 82),
            failureCaption.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 12),
            failureCaption.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 10),
            failureCountValue.leadingAnchor.constraint(equalTo: failureCaption.leadingAnchor),
            failureCountValue.topAnchor.constraint(equalTo: failureCaption.bottomAnchor, constant: 1),
            failureSummaryLabel.leadingAnchor.constraint(equalTo: failureCountValue.trailingAnchor, constant: 12),
            failureSummaryLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -10),
            failureSummaryLabel.centerYAnchor.constraint(equalTo: statusCard.centerYAnchor),
            failureScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            failureScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            failureScroll.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: 10),
            failureScroll.heightAnchor.constraint(equalToConstant: 160),
            realtimeScopeLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            realtimeScopeLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            realtimeScopeLabel.topAnchor.constraint(equalTo: failureScroll.bottomAnchor, constant: 12),
            realtimeCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            realtimeCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            realtimeCard.topAnchor.constraint(equalTo: realtimeScopeLabel.bottomAnchor, constant: 8),
            realtimeCard.heightAnchor.constraint(equalToConstant: 58),
            realtimeCaption.leadingAnchor.constraint(equalTo: realtimeCard.leadingAnchor, constant: 12),
            realtimeCaption.topAnchor.constraint(equalTo: realtimeCard.topAnchor, constant: 9),
            realtimeFailureCountValue.leadingAnchor.constraint(equalTo: realtimeCaption.leadingAnchor),
            realtimeFailureCountValue.topAnchor.constraint(equalTo: realtimeCaption.bottomAnchor, constant: 1),
            realtimeScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            realtimeScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            realtimeScroll.topAnchor.constraint(equalTo: realtimeCard.bottomAnchor, constant: 7),
            realtimeScroll.heightAnchor.constraint(equalToConstant: 92),
            selectFailedButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            selectFailedButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            selectFailedButton.topAnchor.constraint(equalTo: realtimeScroll.bottomAnchor, constant: 8),
            selectFailedButton.heightAnchor.constraint(equalToConstant: 30),
            refreshFailureReportButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            refreshFailureReportButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            refreshFailureReportButton.topAnchor.constraint(equalTo: selectFailedButton.bottomAnchor, constant: 7),
            refreshFailureReportButton.heightAnchor.constraint(equalToConstant: 30),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 76),
            footerTitle.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            footerTitle.topAnchor.constraint(equalTo: footer.topAnchor, constant: 11),
            footerTitle.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
            footerText.leadingAnchor.constraint(equalTo: footerTitle.leadingAnchor),
            footerText.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
            footerText.topAnchor.constraint(equalTo: footerTitle.bottomAnchor, constant: 5),
            footerText.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor, constant: -9)
        ])
    }

    private func setupSidebar(_ sidebar: NSView, activity: NSView) {
        let brandIcon = NSImageView()
        brandIcon.image = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: "Live Activity"
        )
        brandIcon.contentTintColor = WorkspaceUI.cyan
        brandIcon.translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = NSTextField(labelWithString: "ETHOPEX / OPS")
        eyebrow.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        eyebrow.textColor = WorkspaceUI.cyan
        eyebrow.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Live Activity")
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let version = NSTextField(labelWithString: "CAMPAIGN AUTO  •  v1.11.2")
        version.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        version.textColor = .tertiaryLabelColor
        version.translatesAutoresizingMaskIntoConstraints = false

        let totalCard = makeActivityMetricCard(
            title: "TOTAL FAILED",
            value: failureCountValue,
            tint: .systemRed
        )
        let realtimeCard = makeActivityMetricCard(
            title: "REALTIME FAILED",
            value: realtimeFailureCountValue,
            tint: .systemOrange
        )

        selectFailedButton.title = "Chọn FAILED để retry"
        selectFailedButton.target = self
        selectFailedButton.action = #selector(selectFailedRecords)
        selectFailedButton.translatesAutoresizingMaskIntoConstraints = false
        WorkspaceUI.styleAccentButton(
            selectFailedButton,
            tint: .systemRed,
            symbol: "arrow.clockwise"
        )

        refreshFailureReportButton.title = "Làm mới trạng thái"
        refreshFailureReportButton.target = self
        refreshFailureReportButton.action = #selector(refreshFailureReport)
        refreshFailureReportButton.translatesAutoresizingMaskIntoConstraints = false
        WorkspaceUI.styleSecondaryButton(
            refreshFailureReportButton,
            symbol: "arrow.clockwise"
        )

        [brandIcon, eyebrow, title, version, totalCard, realtimeCard,
         selectFailedButton, refreshFailureReportButton].forEach {
            sidebar.addSubview($0)
        }

        NSLayoutConstraint.activate([
            brandIcon.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            brandIcon.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18),
            brandIcon.widthAnchor.constraint(equalToConstant: 22),
            brandIcon.heightAnchor.constraint(equalToConstant: 22),
            eyebrow.leadingAnchor.constraint(equalTo: brandIcon.trailingAnchor, constant: 9),
            eyebrow.centerYAnchor.constraint(equalTo: brandIcon.centerYAnchor),
            eyebrow.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            title.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: brandIcon.bottomAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            version.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            version.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            version.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            totalCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            totalCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            totalCard.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 18),
            totalCard.heightAnchor.constraint(equalToConstant: 55),
            realtimeCard.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            realtimeCard.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            realtimeCard.topAnchor.constraint(equalTo: totalCard.bottomAnchor, constant: 7),
            realtimeCard.heightAnchor.constraint(equalToConstant: 55),
            selectFailedButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            selectFailedButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            selectFailedButton.topAnchor.constraint(equalTo: realtimeCard.bottomAnchor, constant: 8),
            selectFailedButton.heightAnchor.constraint(equalToConstant: 28),
            refreshFailureReportButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            refreshFailureReportButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            refreshFailureReportButton.topAnchor.constraint(equalTo: selectFailedButton.bottomAnchor, constant: 6),
            refreshFailureReportButton.heightAnchor.constraint(equalToConstant: 28),
            activity.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            activity.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            activity.topAnchor.constraint(equalTo: refreshFailureReportButton.bottomAnchor, constant: 10),
            activity.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)
        ])
    }

    private func makeActivityMetricCard(
        title: String,
        value: NSTextField,
        tint: NSColor
    ) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 9
        card.layer?.backgroundColor = WorkspaceUI.raisedSurface.cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = tint.withAlphaComponent(0.22).cgColor

        let label = NSTextField(labelWithString: title)
        label.font = .monospacedSystemFont(ofSize: 9, weight: .bold)
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        value.font = .systemFont(ofSize: 21, weight: .bold)
        value.textColor = tint
        value.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(label)
        card.addSubview(value)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            value.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            value.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func setupModernHeader(_ header: NSView) {
        searchField.delegate = self
        searchField.stringValue = headerModel.searchText

        displayLinkPopup.removeAllItems()
        displayLinkPopup.addItems(
            withTitles: CreativeDisplayLinkPreset.allCases.map(\.displayName)
        )
        if let index = CreativeDisplayLinkPreset.allCases.firstIndex(
            of: CreativeDisplayLinkConfig.shared.selected
        ) {
            displayLinkPopup.selectItem(at: index)
        }
        displayLinkPopup.target = self
        displayLinkPopup.action = #selector(displayLinkChanged(_:))

        fanpagePopup.removeAllItems()
        fanpagePopup.addItem(
            withTitle: FacebookPageSelectionConfig.shared.selectedPage.menuTitle
        )
        fanpagePopup.target = self
        fanpagePopup.action = #selector(fanpageChanged(_:))

        refreshPagesButton.title = "Pages"
        refreshPagesButton.target = self
        refreshPagesButton.action = #selector(refreshFacebookPagesAction)

        languagePopupButton.target = self
        languagePopupButton.action = #selector(showLanguagePopover(_:))
        configureLanguagePopover()
        refreshLanguageSelector()

        settingsButton.target = self
        settingsButton.action = #selector(openAPISettings)

        headerModel.displayLink =
            CreativeDisplayLinkConfig.shared.selected.displayName
        headerModel.fanpageTitle =
            FacebookPageSelectionConfig.shared.selectedPage.menuTitle
        headerModel.summary = summaryLabel.stringValue

        let hosting = NSHostingView(
            rootView: CampaignSwiftUIHeader(
                model: headerModel,
                displayLinkOptions: CreativeDisplayLinkPreset.allCases.map(\.displayName),
                onSearchChanged: { [weak self] value in
                    guard let self else { return }
                    self.searchField.stringValue = value
                    self.applyFilter()
                },
                onRefresh: { [weak self] in self?.refreshAction() },
                onSelectAll: { [weak self] in self?.selectAllReady() },
                onSelectNew: { [weak self] in self?.selectLatestImportedData() },
                onClear: { [weak self] in self?.clearSelection() },
                onDisplayLinkChanged: { [weak self] value in
                    guard let self,
                          let index = CreativeDisplayLinkPreset.allCases.firstIndex(
                            where: { $0.displayName == value }
                          ) else { return }
                    self.displayLinkPopup.selectItem(at: index)
                    self.displayLinkChanged(self.displayLinkPopup)
                },
                onLanguages: { [weak self, weak header] in
                    guard let self, let header else { return }
                    self.languagePopover.show(
                        relativeTo: header.bounds,
                        of: header,
                        preferredEdge: .maxY
                    )
                },
                onFanpageChanged: { [weak self] value in
                    guard let self,
                          let index = self.facebookPages.firstIndex(
                            where: { $0.menuTitle == value }
                          ) else { return }
                    self.fanpagePopup.selectItem(at: index)
                    self.fanpageChanged(self.fanpagePopup)
                },
                onRefreshPages: { [weak self] in self?.refreshFacebookPagesAction() },
                onAPI: { [weak self] in self?.openAPISettings() },
                onCreateCampaign: { [weak self] in self?.createCampaignReal() }
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: header.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
    }

    // Legacy AppKit header retained temporarily as a rollback path while the
    // SwiftUI command surface is validated against the existing engine.
    private func setupHeader(_ header: NSView) {
        let title =
            NSTextField(
                labelWithString: "Campaign Automation"
            )
        title.font =
            .systemFont(
                ofSize: 25,
                weight: .bold
            )
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle =
            NSTextField(
                labelWithString:
                    "Chọn dữ liệu  •  Cấu hình  •  Tạo campaign"
            )
        subtitle.font =
            .systemFont(
                ofSize: 12,
                weight: .medium
            )
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        apiStatusLabel.font =
            .systemFont(
                ofSize: 11,
                weight: .semibold
            )
        apiStatusLabel.alignment = .center
        apiStatusLabel.lineBreakMode = .byTruncatingTail
        apiStatusLabel.maximumNumberOfLines = 1
        WorkspaceUI.verticallyCenterText(
            in: apiStatusLabel
        )
        apiStatusLabel.drawsBackground = true
        apiStatusLabel.wantsLayer = true
        apiStatusLabel.layer?.cornerRadius = 8
        apiStatusLabel.layer?.masksToBounds = true
        apiStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        apiStatusLabel.stringValue = "● API CHECK ON ACTION"
        apiStatusLabel.textColor = WorkspaceUI.cyan
        apiStatusLabel.backgroundColor = WorkspaceUI.cyan.withAlphaComponent(0.09)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // V1.6.7.3:
        // Use an equal-width horizontal stack instead of rigid width ratios.
        // The center panel is Campaign Setup as requested.
        let panelStack = NSStackView()
        panelStack.orientation = .horizontal
        panelStack.alignment = .top
        panelStack.distribution = .fillEqually
        panelStack.spacing = 10
        panelStack.translatesAutoresizingMaskIntoConstraints = false

        let dataPanel = NSView()
        let campaignPanel = NSView()


        [dataPanel, campaignPanel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.setContentHuggingPriority(
                .defaultLow,
                for: .horizontal
            )
            $0.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )
        }

        WorkspaceUI.styleTintedSurface(
            dataPanel,
            tint: .systemTeal
        )
        WorkspaceUI.styleTintedSurface(
            campaignPanel,
            tint: .systemPurple
        )
        panelStack.addArrangedSubview(dataPanel)
        panelStack.addArrangedSubview(campaignPanel)

        let dataTitle =
            NSTextField(
                labelWithString: "DATA SELECTION"
            )
        dataTitle.font =
            .systemFont(
                ofSize: 11,
                weight: .bold
            )
        dataTitle.textColor = .systemTeal
        dataTitle.translatesAutoresizingMaskIntoConstraints = false

        let campaignTitle =
            NSTextField(
                labelWithString: "CAMPAIGN SETUP"
            )
        campaignTitle.font =
            .systemFont(
                ofSize: 11,
                weight: .bold
            )
        campaignTitle.textColor = .systemPurple
        campaignTitle.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString =
            "Tìm theo tên hoặc headline"
        searchField.delegate = self
        searchField.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        searchField.translatesAutoresizingMaskIntoConstraints = false

        refreshButton.title = "Làm mới"
        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)

        selectAllButton.title = "Chọn tất cả"
        selectAllButton.target = self
        selectAllButton.action = #selector(selectAllReady)

        selectNewButton.title = "DATA mới"
        selectNewButton.target = self
        selectNewButton.action = #selector(selectLatestImportedData)

        clearButton.title = "Bỏ chọn"
        clearButton.target = self
        clearButton.action = #selector(clearSelection)

        createCampaignButton.title = "4  TẠO CAMPAIGN AUTO"
        createCampaignButton.target = self
        createCampaignButton.action = #selector(createCampaignReal)
        createCampaignButton.keyEquivalent = "\r"

        displayLinkLabel.font =
            .systemFont(
                ofSize: 10,
                weight: .semibold
            )
        displayLinkLabel.textColor = .secondaryLabelColor
        displayLinkLabel.translatesAutoresizingMaskIntoConstraints = false

        displayLinkPopup.addItems(
            withTitles:
                CreativeDisplayLinkPreset
                    .allCases
                    .map { $0.displayName }
        )

        if let selectedIndex =
                CreativeDisplayLinkPreset
                    .allCases
                    .firstIndex(
                        of:
                            CreativeDisplayLinkConfig
                                .shared
                                .selected
                    ) {
            displayLinkPopup.selectItem(
                at: selectedIndex
            )
        }

        displayLinkPopup.target = self
        displayLinkPopup.action = #selector(displayLinkChanged(_:))
        displayLinkPopup.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        displayLinkPopup.translatesAutoresizingMaskIntoConstraints = false

        fanpageLabel.font =
            .systemFont(
                ofSize: 10,
                weight: .semibold
            )
        fanpageLabel.textColor = .secondaryLabelColor
        fanpageLabel.translatesAutoresizingMaskIntoConstraints = false

        fanpagePopup.addItem(
            withTitle:
                FacebookPageSelectionConfig
                    .shared
                    .selectedPage
                    .menuTitle
        )
        fanpagePopup.target = self
        fanpagePopup.action = #selector(fanpageChanged(_:))
        fanpagePopup.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        fanpagePopup.translatesAutoresizingMaskIntoConstraints = false

        refreshPagesButton.title = "Pages"
        refreshPagesButton.target = self
        refreshPagesButton.action = #selector(refreshFacebookPagesAction)
        refreshPagesButton.translatesAutoresizingMaskIntoConstraints = false

        languagePopupLabel.font =
            .systemFont(
                ofSize: 10,
                weight: .semibold
            )
        languagePopupLabel.textColor = .secondaryLabelColor
        languagePopupLabel.translatesAutoresizingMaskIntoConstraints = false

        languagePopupButton.font =
            .systemFont(
                ofSize: 12,
                weight: .medium
            )
        languagePopupButton.bezelStyle = .rounded
        languagePopupButton.image =
            NSImage(
                systemSymbolName: "chevron.down",
                accessibilityDescription: nil
            )
        languagePopupButton.imagePosition = .imageTrailing
        languagePopupButton.target = self
        languagePopupButton.action = #selector(showLanguagePopover(_:))
        languagePopupButton.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        languagePopupButton.translatesAutoresizingMaskIntoConstraints = false

        configureLanguagePopover()
        refreshLanguageSelector()

        settingsButton.title = "API"
        settingsButton.target = self
        settingsButton.action = #selector(openAPISettings)

        WorkspaceUI.styleSecondaryButton(
            refreshButton,
            symbol: "arrow.clockwise"
        )
        WorkspaceUI.styleAccentButton(
            selectAllButton,
            tint: .systemTeal,
            symbol: "checkmark.circle"
        )
        WorkspaceUI.styleAccentButton(
            selectNewButton,
            tint: .systemPurple,
            symbol: "sparkles"
        )
        WorkspaceUI.styleSecondaryButton(
            clearButton,
            symbol: "xmark.circle"
        )

        WorkspaceUI.styleAccentButton(
            createCampaignButton,
            tint: .systemBlue,
            symbol: "paperplane.fill",
            filled: true
        )

        WorkspaceUI.styleSecondaryButton(
            refreshPagesButton,
            symbol: "arrow.clockwise"
        )
        WorkspaceUI.styleAccentButton(
            settingsButton,
            tint: .systemTeal,
            symbol: "gearshape"
        )

        summaryLabel.font =
            .systemFont(
                ofSize: 10,
                weight: .semibold
            )
        summaryLabel.alignment = .left
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        summaryLabel.textColor = .systemTeal
        summaryLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        [
            refreshButton,
            selectAllButton,
            selectNewButton,
            clearButton,
            createCampaignButton,
            refreshPagesButton,
            settingsButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        // V1.6.7.6 — compact Campaign Setup.
        // Display Link + Languages share one row so the primary CTA
        // always remains fully visible inside the center panel.
        let displayGroup = NSStackView()
        displayGroup.orientation = .vertical
        displayGroup.alignment = .leading
        displayGroup.spacing = 4
        displayGroup.translatesAutoresizingMaskIntoConstraints = false
        displayGroup.addArrangedSubview(displayLinkLabel)
        displayGroup.addArrangedSubview(displayLinkPopup)

        let languageGroup = NSStackView()
        languageGroup.orientation = .vertical
        languageGroup.alignment = .leading
        languageGroup.spacing = 4
        languageGroup.translatesAutoresizingMaskIntoConstraints = false
        languageGroup.addArrangedSubview(languagePopupLabel)
        languageGroup.addArrangedSubview(languagePopupButton)

        let campaignConfigRow = NSStackView()
        campaignConfigRow.orientation = .horizontal
        campaignConfigRow.alignment = .top
        campaignConfigRow.distribution = .fillEqually
        campaignConfigRow.spacing = 10
        campaignConfigRow.translatesAutoresizingMaskIntoConstraints = false
        campaignConfigRow.addArrangedSubview(displayGroup)
        campaignConfigRow.addArrangedSubview(languageGroup)

        header.addSubview(title)
        header.addSubview(subtitle)
        header.addSubview(apiStatusLabel)
        header.addSubview(divider)
        header.addSubview(panelStack)

        // DATA PANEL
        dataPanel.addSubview(dataTitle)
        dataPanel.addSubview(searchField)
        dataPanel.addSubview(selectAllButton)
        dataPanel.addSubview(selectNewButton)
        dataPanel.addSubview(clearButton)
        dataPanel.addSubview(refreshButton)
        dataPanel.addSubview(summaryLabel)

        // CAMPAIGN PANEL (CENTER)
        campaignPanel.addSubview(campaignTitle)
        campaignPanel.addSubview(settingsButton)
        campaignPanel.addSubview(campaignConfigRow)
        campaignPanel.addSubview(fanpageLabel)
        campaignPanel.addSubview(fanpagePopup)
        campaignPanel.addSubview(refreshPagesButton)
        campaignPanel.addSubview(createCampaignButton)

        NSLayoutConstraint.activate([
            // Header title row
            title.leadingAnchor.constraint(
                equalTo: header.leadingAnchor,
                constant: 18
            ),
            title.topAnchor.constraint(
                equalTo: header.topAnchor,
                constant: 14
            ),
            title.trailingAnchor.constraint(
                lessThanOrEqualTo: apiStatusLabel.leadingAnchor,
                constant: -14
            ),

            subtitle.leadingAnchor.constraint(
                equalTo: title.leadingAnchor
            ),
            subtitle.topAnchor.constraint(
                equalTo: title.bottomAnchor,
                constant: 3
            ),
            subtitle.trailingAnchor.constraint(
                lessThanOrEqualTo: apiStatusLabel.leadingAnchor,
                constant: -14
            ),

            apiStatusLabel.trailingAnchor.constraint(
                equalTo: header.trailingAnchor,
                constant: -18
            ),
            apiStatusLabel.centerYAnchor.constraint(
                equalTo: title.centerYAnchor
            ),
            apiStatusLabel.heightAnchor.constraint(
                equalToConstant: 25
            ),
            apiStatusLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: 210
            ),

            divider.leadingAnchor.constraint(
                equalTo: header.leadingAnchor,
                constant: 16
            ),
            divider.trailingAnchor.constraint(
                equalTo: header.trailingAnchor,
                constant: -16
            ),
            divider.topAnchor.constraint(
                equalTo: subtitle.bottomAnchor,
                constant: 11
            ),

            panelStack.leadingAnchor.constraint(
                equalTo: header.leadingAnchor,
                constant: 16
            ),
            panelStack.trailingAnchor.constraint(
                equalTo: header.trailingAnchor,
                constant: -16
            ),
            panelStack.topAnchor.constraint(
                equalTo: divider.bottomAnchor,
                constant: 12
            ),
            panelStack.bottomAnchor.constraint(
                equalTo: header.bottomAnchor,
                constant: -14
            ),

            // DATA PANEL
            dataTitle.leadingAnchor.constraint(
                equalTo: dataPanel.leadingAnchor,
                constant: 14
            ),
            dataTitle.topAnchor.constraint(
                equalTo: dataPanel.topAnchor,
                constant: 12
            ),
            dataTitle.trailingAnchor.constraint(
                lessThanOrEqualTo: dataPanel.trailingAnchor,
                constant: -14
            ),

            searchField.leadingAnchor.constraint(
                equalTo: dataPanel.leadingAnchor,
                constant: 14
            ),
            searchField.trailingAnchor.constraint(
                equalTo: dataPanel.trailingAnchor,
                constant: -14
            ),
            searchField.topAnchor.constraint(
                equalTo: dataTitle.bottomAnchor,
                constant: 10
            ),

            selectAllButton.leadingAnchor.constraint(
                equalTo: dataPanel.leadingAnchor,
                constant: 14
            ),
            selectAllButton.topAnchor.constraint(
                equalTo: searchField.bottomAnchor,
                constant: 10
            ),

            selectNewButton.leadingAnchor.constraint(
                equalTo: selectAllButton.trailingAnchor,
                constant: 7
            ),
            selectNewButton.centerYAnchor.constraint(
                equalTo: selectAllButton.centerYAnchor
            ),

            clearButton.leadingAnchor.constraint(
                equalTo: selectNewButton.trailingAnchor,
                constant: 7
            ),
            clearButton.centerYAnchor.constraint(
                equalTo: selectAllButton.centerYAnchor
            ),
            clearButton.trailingAnchor.constraint(
                lessThanOrEqualTo: dataPanel.trailingAnchor,
                constant: -14
            ),

            refreshButton.leadingAnchor.constraint(
                equalTo: dataPanel.leadingAnchor,
                constant: 14
            ),
            refreshButton.topAnchor.constraint(
                equalTo: selectAllButton.bottomAnchor,
                constant: 9
            ),

            summaryLabel.leadingAnchor.constraint(
                equalTo: refreshButton.trailingAnchor,
                constant: 10
            ),
            summaryLabel.trailingAnchor.constraint(
                equalTo: dataPanel.trailingAnchor,
                constant: -14
            ),
            summaryLabel.centerYAnchor.constraint(
                equalTo: refreshButton.centerYAnchor
            ),

            // CENTER CAMPAIGN PANEL
            campaignTitle.leadingAnchor.constraint(
                equalTo: campaignPanel.leadingAnchor,
                constant: 14
            ),
            campaignTitle.topAnchor.constraint(
                equalTo: campaignPanel.topAnchor,
                constant: 12
            ),

            settingsButton.trailingAnchor.constraint(
                equalTo: campaignPanel.trailingAnchor,
                constant: -12
            ),
            settingsButton.centerYAnchor.constraint(
                equalTo: campaignTitle.centerYAnchor
            ),

            campaignConfigRow.leadingAnchor.constraint(
                equalTo: campaignPanel.leadingAnchor,
                constant: 14
            ),
            campaignConfigRow.trailingAnchor.constraint(
                equalTo: campaignPanel.trailingAnchor,
                constant: -14
            ),
            campaignConfigRow.topAnchor.constraint(
                equalTo: campaignTitle.bottomAnchor,
                constant: 10
            ),

            displayLinkPopup.widthAnchor.constraint(
                equalTo: displayGroup.widthAnchor
            ),
            languagePopupButton.widthAnchor.constraint(
                equalTo: languageGroup.widthAnchor
            ),

            fanpageLabel.leadingAnchor.constraint(
                equalTo: campaignPanel.leadingAnchor,
                constant: 14
            ),
            fanpageLabel.topAnchor.constraint(
                equalTo: campaignConfigRow.bottomAnchor,
                constant: 9
            ),

            fanpagePopup.leadingAnchor.constraint(
                equalTo: campaignPanel.leadingAnchor,
                constant: 14
            ),
            fanpagePopup.topAnchor.constraint(
                equalTo: fanpageLabel.bottomAnchor,
                constant: 5
            ),

            refreshPagesButton.leadingAnchor.constraint(
                equalTo: fanpagePopup.trailingAnchor,
                constant: 7
            ),
            refreshPagesButton.trailingAnchor.constraint(
                equalTo: campaignPanel.trailingAnchor,
                constant: -14
            ),
            refreshPagesButton.centerYAnchor.constraint(
                equalTo: fanpagePopup.centerYAnchor
            ),

            createCampaignButton.leadingAnchor.constraint(
                equalTo: campaignPanel.leadingAnchor,
                constant: 14
            ),
            createCampaignButton.trailingAnchor.constraint(
                equalTo: campaignPanel.trailingAnchor,
                constant: -14
            ),
            createCampaignButton.topAnchor.constraint(
                equalTo: fanpagePopup.bottomAnchor,
                constant: 10
            ),
            createCampaignButton.heightAnchor.constraint(
                equalToConstant: 34
            ),
            createCampaignButton.bottomAnchor.constraint(
                lessThanOrEqualTo: campaignPanel.bottomAnchor,
                constant: -12
            ),

        ])

        DispatchQueue.main.async { [weak self, weak campaignPanel] in
            guard let self,
                  let campaignPanel else {
                return
            }

            let buttonFrame =
                self.createCampaignButton
                    .convert(
                        self.createCampaignButton.bounds,
                        to: campaignPanel
                    )

            if buttonFrame.minY < 0 ||
               buttonFrame.maxY > campaignPanel.bounds.height {
                self.appendLog(
                    "⚠ UI LAYOUT: Campaign button bị clip. " +
                    "panel=\(Int(campaignPanel.bounds.height)) " +
                    "buttonY=\(Int(buttonFrame.minY))...\(Int(buttonFrame.maxY))"
                )
            }
        }
    }

    private func makeMetricCard(
        title: String,
        valueLabel: NSTextField,
        symbol: String,
        tint: NSColor
    ) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor =
            NSColor(
                calibratedRed: 0.095,
                green: 0.115,
                blue: 0.170,
                alpha: 1
            ).cgColor
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor =
            tint.withAlphaComponent(0.30).cgColor

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .systemFont(ofSize: 21, weight: .bold)
        valueLabel.textColor = .labelColor
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(icon)
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            titleLabel.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -10),

            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9)
        ])

        return card
    }

    func setupOverview(_ overview: NSView) {
        let title = NSTextField(labelWithString: "CURRENT RUN OVERVIEW")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        completionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        completionLabel.textColor = .secondaryLabelColor
        completionLabel.alignment = .right
        completionLabel.translatesAutoresizingMaskIntoConstraints = false

        runTimeLabel.font = .monospacedDigitSystemFont(
            ofSize: 11,
            weight: .semibold
        )
        runTimeLabel.alignment = .center
        runTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        WorkspaceUI.styleBadge(
            runTimeLabel,
            textColor: .secondaryLabelColor,
            backgroundColor:
                NSColor.secondaryLabelColor.withAlphaComponent(0.08)
        )

        let previousDuration =
            UserDefaults.standard.double(
                forKey: "ethopex.lastMultilingualAutoDuration"
            )
        if previousDuration > 0 {
            runTimeLabel.stringValue =
                "LAST " + formatRunDuration(previousDuration)
            runTimeLabel.toolTip =
                "Thời gian lần chạy Multilingual AUTO gần nhất."
        }

        completionProgress.style = .bar
        completionProgress.isIndeterminate = false
        completionProgress.minValue = 0
        completionProgress.maxValue = 1
        completionProgress.doubleValue = 0
        completionProgress.controlSize = .small
        completionProgress.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let cards: [NSView] = [
            makeMetricCard(
                title: "Run Total",
                valueLabel: metricTotalValue,
                symbol: "square.stack.3d.up",
                tint: .systemBlue
            ),
            makeMetricCard(
                title: "New Variants",
                valueLabel: metricNewValue,
                symbol: "sparkles",
                tint: .systemPurple
            ),
            makeMetricCard(
                title: "Selected",
                valueLabel: metricSelectedValue,
                symbol: "checkmark.circle",
                tint: .systemTeal
            ),
            makeMetricCard(
                title: "Running",
                valueLabel: metricRunningValue,
                symbol: "bolt.circle",
                tint: .systemOrange
            ),
            makeMetricCard(
                title: "Created",
                valueLabel: metricCampaignValue,
                symbol: "paperplane.circle.fill",
                tint: .systemGreen
            ),
            makeMetricCard(
                title: "Root Failed",
                valueLabel: metricFailedValue,
                symbol: "exclamationmark.triangle",
                tint: .systemRed
            )
        ]

        for card in cards {
            stack.addArrangedSubview(card)
        }

        overview.addSubview(title)
        overview.addSubview(runTimeLabel)
        overview.addSubview(completionLabel)
        overview.addSubview(completionProgress)
        overview.addSubview(stack)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: overview.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: overview.topAnchor, constant: 10),

            completionLabel.trailingAnchor.constraint(equalTo: overview.trailingAnchor, constant: -14),
            completionLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            runTimeLabel.trailingAnchor.constraint(
                equalTo: completionLabel.leadingAnchor,
                constant: -12
            ),
            runTimeLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            runTimeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
            runTimeLabel.heightAnchor.constraint(equalToConstant: 24),

            completionProgress.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 14),
            completionProgress.trailingAnchor.constraint(equalTo: runTimeLabel.leadingAnchor, constant: -12),
            completionProgress.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            completionProgress.heightAnchor.constraint(equalToConstant: 6),

            stack.leadingAnchor.constraint(equalTo: overview.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: overview.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: overview.bottomAnchor, constant: -8)
        ])
    }

    private enum StageTone {
        case neutral
        case info
        case success
        case warning
        case danger
    }

    private func styleStageBadge(
        _ field: NSTextField,
        tone: StageTone
    ) {
        switch tone {
        case .neutral:
            WorkspaceUI.styleBadge(
                field,
                textColor: .secondaryLabelColor,
                backgroundColor:
                    NSColor.secondaryLabelColor.withAlphaComponent(0.08)
            )
        case .info:
            WorkspaceUI.styleBadge(
                field,
                textColor: .systemBlue,
                backgroundColor:
                    NSColor.systemBlue.withAlphaComponent(0.10)
            )
        case .success:
            WorkspaceUI.styleBadge(
                field,
                textColor: .systemGreen,
                backgroundColor:
                    NSColor.systemGreen.withAlphaComponent(0.10)
            )
        case .warning:
            WorkspaceUI.styleBadge(
                field,
                textColor: .systemOrange,
                backgroundColor:
                    NSColor.systemOrange.withAlphaComponent(0.11)
            )
        case .danger:
            WorkspaceUI.styleBadge(
                field,
                textColor: .systemRed,
                backgroundColor:
                    NSColor.systemRed.withAlphaComponent(0.10)
            )
        }
    }

    private func cachedState(
        for record: CampaignRecord
    ) -> IntegrationState {
        integrationStates[record.id] ??
            engine.stateStore.load(
                folder: dataSource.folder(for: record),
                record: record
            )
    }

    private func stageDescriptor(
        columnID: String,
        record: CampaignRecord
    ) -> (
        text: String,
        tone: StageTone,
        tooltip: String?
    ) {
        let state = cachedState(for: record)
        let live = statuses[record.id] ?? .idle

        switch columnID {
        case "sourceStage":
            if live == .parsing {
                return ("RUNNING", .info, "Đang parse Source View")
            }
            if state.parsed {
                return ("PARSED", .success, "Source View đã parse thành công")
            }
            if state.lastError != nil && !state.parsed {
                return ("ERROR", .danger, state.lastError)
            }
            return ("WAITING", .neutral, "Chưa parse Source View")

        case "geminiStage":
            if live == .gemini {
                return ("RUNNING", .info, "Gemini đang tạo landing content")
            }
            if state.geminiGenerated {
                return ("DONE", .success, "generated_content.json đã có")
            }
            if state.parsed {
                return ("WAITING", .neutral, "Đã parse, chưa có Gemini output")
            }
            return ("—", .neutral, nil)

        case "qaStage":
            if live == .qa {
                return ("CHECKING", .info, "Source Fidelity + QA đang chạy")
            }
            if state.qaPassed {
                return ("PASSED", .success, "Source Fidelity / QA PASS")
            }
            if state.geminiGenerated,
               let error = state.lastError,
               error.localizedCaseInsensitiveContains("QA") {
                return ("FAILED", .danger, error)
            }
            if state.geminiGenerated {
                return ("WAITING", .neutral, "Chờ Source Fidelity / QA")
            }
            return ("—", .neutral, nil)

        case "contentStage":
            if live == .checkingContent {
                return ("CHECKING", .info, "Đang kiểm tra Content remote")
            }
            if live == .creatingContent {
                return ("CREATING", .info, "Đang tạo Ethopex Content")
            }
            if state.contentCreated {
                let tooltip = state.contentID.map { "content_id: \($0)" }
                return ("CREATED", .success, tooltip)
            }
            if state.qaPassed {
                return ("READY", .warning, "QA PASS, sẵn sàng tạo Content")
            }
            return ("—", .neutral, nil)

        case "mediaStage":
            if live == .uploadingMedia {
                return ("UPLOADING", .info, "Đang upload Image")
            }
            if state.uploadedImageURL != nil {
                let tooltip =
                    state.uploadedMediaID.map { "media_id: \($0)" } ??
                    state.uploadedImageURL
                return ("UPLOADED", .success, tooltip)
            }
            if state.contentCreated {
                return ("READY", .warning, "Content đã có, chờ upload Image")
            }
            return ("—", .neutral, nil)

        case "creativeStage":
            if live == .creatingCreative {
                return ("CREATING", .info, "Đang tạo Creative")
            }
            if state.creativeCreated {
                let tooltip = state.creativeID.map { "creative_id: \($0)" }
                return ("CREATED", .success, tooltip)
            }
            if let blocker = state.creativeBlocker,
               !blocker.isEmpty {
                return ("BLOCKED", .danger, blocker)
            }
            if state.contentCreated {
                return ("READY", .warning, "Content đã có, sẵn sàng tạo Creative")
            }
            return ("—", .neutral, nil)

        case "campaignStage":
            if live == .creatingCampaign {
                return ("CREATING", .info, "Đang tạo Campaign")
            }
            if let campaignID = state.campaignID,
               !campaignID.isEmpty {
                var ids = ["campaign_id: \(campaignID)"]
                if let adSetID = state.adSetID {
                    ids.append("ad_set_id: \(adSetID)")
                }
                if let adID = state.adID {
                    ids.append("ad_id: \(adID)")
                }
                return ("CREATED", .success, ids.joined(separator: "\n"))
            }
            if state.creativeCreated {
                return ("READY", .warning, "Creative đã có, sẵn sàng tạo Campaign")
            }
            return ("—", .neutral, nil)

        default:
            return ("—", .neutral, nil)
        }
    }

    func setupTable(_ scroll: NSScrollView) {
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .small
        scroll.horizontalScroller?.controlSize = .small
        scroll.contentInsets =
            NSEdgeInsets(
                top: 0,
                left: 0,
                bottom: 5,
                right: 4
            )
        scroll.borderType = .noBorder

        let columns: [(String, String, CGFloat)] = [
            ("select", "", 44),
            ("stt", "STT", 48),
            ("name", "Creative / Data", 280),
            ("language", "Lang", 62),
            ("data", "Data", 105),
            ("sourceStage", "Source", 105),
            ("geminiStage", "Gemini", 105),
            ("qaStage", "QA", 90),
            ("contentStage", "Content", 112),
            ("mediaStage", "Image", 112),
            ("creativeStage", "Creative", 118),
            ("campaignStage", "Campaign", 122),
            ("job", "Overall", 150),
            ("source", "Source View", 230)
        ]

        let centeredColumnIDs: Set<String> = [
            "select",
            "stt",
            "language",
            "data",
            "sourceStage",
            "geminiStage",
            "qaStage",
            "contentStage",
            "mediaStage",
            "creativeStage",
            "campaignStage",
            "job"
        ]

        for item in columns {
            let column =
                NSTableColumn(
                    identifier:
                        NSUserInterfaceItemIdentifier(
                            item.0
                        )
                )

            column.title = item.1
            column.width = item.2
            column.minWidth = item.2

            if centeredColumnIDs.contains(item.0) {
                column.headerCell.alignment = .center
            } else {
                column.headerCell.alignment = .left
            }

            tableView.addTableColumn(column)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 46
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.intercellSpacing =
            NSSize(
                width: 0,
                height: 1
            )
        tableView.backgroundColor = WorkspaceUI.canvas

        if let headerView = tableView.headerView {
            headerView.wantsLayer = true
            headerView.layer?.backgroundColor =
                WorkspaceUI.raisedSurface.cgColor
        }
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = false
        scroll.documentView = tableView
    }

    func setupBottom(_ bottom: NSView) {
        let logTitle = NSTextField(labelWithString: "LIVE ACTIVITY")
        logTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        logTitle.textColor = .secondaryLabelColor
        logTitle.translatesAutoresizingMaskIntoConstraints = false

        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.hasHorizontalScroller = false
        logScroll.autohidesScrollers = true
        logScroll.scrollerStyle = .overlay
        logScroll.verticalScroller?.controlSize = .small
        WorkspaceUI.styleScrollSurface(logScroll, radius: 9)
        logScroll.translatesAutoresizingMaskIntoConstraints = false

        logView.isEditable = false
        logView.drawsBackground = true
        logView.backgroundColor = WorkspaceUI.canvas
        logView.textColor = .labelColor
        logView.textContainerInset = NSSize(width: 10, height: 6)
        logView.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        logView.string = "V1.4 sẵn sàng. Fanpage batch + Auto Cover quiz 3.\n"
        logScroll.documentView = logView

        progress.isIndeterminate = true
        progress.style = .spinning
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "Theo dõi từng stage ngay trên bảng: Source → Gemini → QA → Content → Image → Creative → Campaign. Hover status để xem ID hoặc lỗi chi tiết."
        )
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.translatesAutoresizingMaskIntoConstraints = false

        bottom.addSubview(logTitle)
        bottom.addSubview(progress)
        bottom.addSubview(logScroll)
        bottom.addSubview(hint)

        NSLayoutConstraint.activate([
            logTitle.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 16),
            logTitle.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 4),

            progress.leadingAnchor.constraint(equalTo: logTitle.trailingAnchor, constant: 10),
            progress.centerYAnchor.constraint(equalTo: logTitle.centerYAnchor),

            logScroll.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 14),
            logScroll.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -14),
            logScroll.topAnchor.constraint(equalTo: logTitle.bottomAnchor, constant: 6),
            logScroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -5),

            hint.leadingAnchor.constraint(equalTo: logScroll.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: logScroll.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: bottom.bottomAnchor, constant: -6),
            hint.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func refreshAPIStatus() {
        let hasGemini =
            !(GeminiConfig.shared.apiKey ?? "").isEmpty
        let hasEthopex =
            !(EthopexConfig.shared.token ?? "").isEmpty

        apiStatusLabel.stringValue =
            "● Gemini \(hasGemini ? "READY" : "MISSING")   •   ● Ethopex \(hasEthopex ? "READY" : "MISSING")"

        let allReady =
            hasGemini && hasEthopex

        apiStatusLabel.textColor =
            allReady
            ? .systemGreen
            : .systemOrange

        apiStatusLabel.backgroundColor =
            (allReady
             ? NSColor.systemGreen
             : NSColor.systemOrange)
                .withAlphaComponent(0.09)

        apiStatusLabel.layer?.borderWidth = 0.6
        apiStatusLabel.layer?.borderColor =
            (allReady
             ? NSColor.systemGreen
             : NSColor.systemOrange)
                .withAlphaComponent(0.25)
                .cgColor
    }

    @objc func openAPISettings() {
        let controller = APISettingsWindowController()
        controller.onSettingsChanged = { [weak self] in
            self?.refreshAPIStatus()
            self?.appendLog("API settings đã cập nhật.")
        }
        apiSettingsController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    func reloadRecords() {
        let ok = dataSource.reload()
        statuses.removeAll()

        integrationStates.removeAll()

        if ok {
            let validIDs = Set(dataSource.records.map(\.id))
            selectedIDs = selectedIDs.intersection(validIDs)

            for record in dataSource.records {
                if let persisted = engine.persistedStatus(for: record) {
                    statuses[record.id] = persisted
                }

                integrationStates[record.id] =
                    engine.stateStore.load(
                        folder: dataSource.folder(for: record),
                        record: record
                    )
            }
        }

        applyFilter()

        if !ok {
            appendLog("Không tìm thấy dữ liệu tại: \(dataSource.indexURL.path)")
        } else {
            appendLog("Đã tải \(dataSource.records.count) record từ Ethopex Data Manager.")
        }
    }

    func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = q.isEmpty ? dataSource.records : dataSource.records.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.headline.localizedCaseInsensitiveContains(q)
        }

        filtered = base.sorted {
            let lhs = $0.stt ?? 0
            let rhs = $1.stt ?? 0
            if lhs == rhs { return $0.createdAt < $1.createdAt }
            return lhs < rhs
        }

        tableView.reloadData()
        updateSummary()
    }

    func updateSummary() {
        let records = dataSource.records
        let ready = records.filter { $0.isReady }.count

        let activeStatuses: Set<JobStatus> = [
            .queued,
            .validating,
            .parsing,
            .gemini,
            .qa,
            .checkingContent,
            .creatingContent,
            .uploadingMedia,
            .creatingCreative,
            .creatingCampaign
        ]

        if autoRunOverviewActive {
            let total =
                max(
                    autoRunExpectedVariantCount,
                    autoRunOverviewScopeIDs.count +
                    autoRunOverviewPreparationFailureCount
                )

            let selected =
                autoRunOverviewScopeIDs.isEmpty
                ? autoRunOverviewInputSourceCount
                : autoRunOverviewScopeIDs.count

            let runningJobs =
                statuses.filter { pair in
                    autoRunOverviewScopeIDs.contains(pair.key) &&
                    activeStatuses.contains(pair.value)
                }.count

            let runningCount =
                autoRunOverviewFinished
                ? 0
                : (autoRunOverviewPreparationActive
                   ? max(1, runningJobs)
                   : runningJobs)

            let campaignCount =
                autoRunOverviewCreatedCampaignIDs.count

            let failedCount =
                autoRunOverviewFailedIDs.count +
                autoRunOverviewPreparationFailureCount

            let processedCount =
                min(
                    total,
                    autoRunOverviewTerminalIDs.count +
                    autoRunOverviewPreparationFailureCount
                )

            metricTotalValue.stringValue = "\(total)"
            metricNewValue.stringValue =
                "\(autoRunOverviewNewVariantIDs.count)"
            metricSelectedValue.stringValue = "\(selected)"
            metricRunningValue.stringValue = "\(runningCount)"
            metricCampaignValue.stringValue = "\(campaignCount)"
            metricFailedValue.stringValue = "\(failedCount)"

            completionProgress.maxValue =
                Double(max(total, 1))
            completionProgress.doubleValue =
                Double(processedCount)

            completionLabel.stringValue =
                "\(processedCount) / \(total) processed"

            let languageLabels =
                CampaignLanguage.allCases
                    .filter {
                        CampaignLanguageSelectionConfig
                            .shared
                            .selected
                            .contains($0)
                    }
                    .map(\.shortLabel)
                    .joined(separator: "/")

            summaryLabel.stringValue =
                "\(ready) READY  •  \(selected) in current run  •  \(languageLabels)"
            headerModel.summary = summaryLabel.stringValue

            updateFailureReport()

            return
        }

        let selected = selectedIDs.count

        metricTotalValue.stringValue = "0"
        metricNewValue.stringValue = "0"
        metricSelectedValue.stringValue = "\(selected)"
        metricRunningValue.stringValue = "0"
        metricCampaignValue.stringValue = "0"
        metricFailedValue.stringValue = "0"

        completionProgress.maxValue = 1
        completionProgress.doubleValue = 0
        completionLabel.stringValue = "No current run"

        let languageLabels =
            CampaignLanguage.allCases
                .filter {
                    CampaignLanguageSelectionConfig
                        .shared
                        .selected
                        .contains($0)
                }
                .map(\.shortLabel)
                .joined(separator: "/")

        summaryLabel.stringValue =
            "\(ready) READY  •  \(selected) selected  •  \(languageLabels)"
        headerModel.summary = summaryLabel.stringValue

        updateFailureReport()
    }

    private func resetAutoRunOverview(
        sourceCount: Int,
        targetLanguageCount: Int
    ) {
        autoRunOverviewActive = true
        autoRunOverviewInputSourceCount = sourceCount
        autoRunExpectedVariantCount =
            sourceCount * targetLanguageCount
        autoRunOverviewScopeIDs.removeAll()
        autoRunOverviewNewVariantIDs.removeAll()
        autoRunOverviewBaselineCampaignIDs.removeAll()
        autoRunOverviewTerminalIDs.removeAll()
        autoRunOverviewCreatedCampaignIDs.removeAll()
        autoRunOverviewFailedIDs.removeAll()
        autoRunOverviewPreparationFailureCount = 0
        autoRunOverviewPreparationActive = true
        autoRunOverviewFinished = false
        autoRunOverviewRecordIDsBeforePreparation =
            Set(dataSource.records.map(\.id))

        updateSummary()

        appendLog(
            "↻ CURRENT RUN OVERVIEW RESET"
        )
        appendLog(
            "  Run total: \(autoRunExpectedVariantCount) planned variant(s)"
        )
    }

    private func attachPreparedRecordsToAutoRunOverview(
        _ records: [CampaignRecord],
        preparationFailureCount: Int
    ) {
        autoRunOverviewScopeIDs =
            Set(records.map(\.id))

        autoRunOverviewNewVariantIDs =
            autoRunOverviewScopeIDs.subtracting(
                autoRunOverviewRecordIDsBeforePreparation
            )

        autoRunOverviewPreparationFailureCount =
            preparationFailureCount
        autoRunOverviewPreparationActive = false

        var baseline: [UUID: String] = [:]

        for record in records {
            let state =
                engine.stateStore.load(
                    folder: dataSource.folder(for: record),
                    record: record
                )

            baseline[record.id] =
                state.campaignID ?? ""
        }

        autoRunOverviewBaselineCampaignIDs =
            baseline

        updateSummary()
    }

    private func trackAutoRunOverviewStatus(
        id: UUID,
        status: JobStatus
    ) {
        guard autoRunOverviewActive,
              autoRunOverviewScopeIDs.contains(id) else {
            return
        }

        switch status {
        case .failed:
            autoRunOverviewFailedIDs.insert(id)
            autoRunOverviewTerminalIDs.insert(id)

        case .campaignDone, .done:
            autoRunOverviewTerminalIDs.insert(id)

            var state = integrationStates[id]

            if state == nil,
               let record =
                    dataSource.records.first(
                        where: { $0.id == id }
                    ) {
                state =
                    engine.stateStore.load(
                        folder: dataSource.folder(for: record),
                        record: record
                    )
            }

            let currentCampaignID =
                state?.campaignID ?? ""

            let baselineCampaignID =
                autoRunOverviewBaselineCampaignIDs[id] ?? ""

            if !currentCampaignID.isEmpty &&
               currentCampaignID != baselineCampaignID {
                autoRunOverviewCreatedCampaignIDs.insert(id)
            }

        default:
            break
        }
    }

    private func finalizeAutoRunOverview() {
        guard autoRunOverviewActive else {
            return
        }

        autoRunOverviewPreparationActive = false
        autoRunOverviewFinished = true

        for id in autoRunOverviewScopeIDs {
            if statuses[id] == .failed {
                autoRunOverviewFailedIDs.insert(id)
            }

            if let record =
                    dataSource.records.first(
                        where: { $0.id == id }
                    ) {
                let state =
                    engine.stateStore.load(
                        folder: dataSource.folder(for: record),
                        record: record
                    )

                let currentCampaignID =
                    state.campaignID ?? ""

                let baselineCampaignID =
                    autoRunOverviewBaselineCampaignIDs[id] ?? ""

                if !currentCampaignID.isEmpty &&
                   currentCampaignID != baselineCampaignID {
                    autoRunOverviewCreatedCampaignIDs.insert(id)
                }
            }
        }

        autoRunOverviewTerminalIDs.formUnion(
            autoRunOverviewScopeIDs
        )

        updateSummary()
    }


    private func refreshIntegrationState(
        for id: UUID
    ) {
        guard let record =
                dataSource.records.first(
                    where: { $0.id == id }
                ) else {
            return
        }

        integrationStates[id] =
            engine.stateStore.load(
                folder: dataSource.folder(for: record),
                record: record
            )
    }

    private func refreshAllIntegrationStates() {
        for record in dataSource.records {
            integrationStates[record.id] =
                engine.stateStore.load(
                    folder: dataSource.folder(for: record),
                    record: record
                )
        }
    }

    private func handleStatusChange(
        id: UUID,
        status: JobStatus
    ) {
        statuses[id] = status

        switch status {
        case .readyContent,
             .contentDone,
             .mediaDone,
             .creativeDone,
             .campaignDone,
             .done,
             .failed:
            refreshIntegrationState(for: id)
            if status == .failed && autoRunOverviewActive {
                realtimeFailureIDs.insert(id)
            }

        default:
            break
        }

        trackAutoRunOverviewStatus(
            id: id,
            status: status
        )

        tableView.reloadData()
        updateSummary()
    }


    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = filtered[row]
        guard let columnID = tableColumn?.identifier.rawValue else { return nil }

        if columnID == "select" {
            let container = NSTableCellView(frame: .zero)
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheck(_:)))
            button.state = selectedIDs.contains(record.id) ? .on : .off
            button.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
            button.isEnabled = record.isReady
            button.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(button)

            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])

            return container
        }

        let container = NSTableCellView(frame: .zero)
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true

        WorkspaceUI.verticallyCenterText(
            in: field
        )

        switch columnID {
        case "stt":
            field.stringValue = "\(record.stt ?? 0)"
            field.alignment = .center
            field.font = .boldSystemFont(ofSize: 12)

        case "name":
            field.stringValue = record.name
            field.font = .boldSystemFont(ofSize: 12)

        case "language":
            let language =
                CampaignLanguage.from(
                    code: record.effectiveLanguageCode
                )
            field.stringValue = language.shortLabel
            field.alignment = .center
            field.font = .boldSystemFont(ofSize: 12)
            field.textColor = .labelColor

        case "sourceStage",
             "geminiStage",
             "qaStage",
             "contentStage",
             "mediaStage",
             "creativeStage",
             "campaignStage":
            let descriptor =
                stageDescriptor(
                    columnID: columnID,
                    record: record
                )

            field.stringValue = descriptor.text
            field.toolTip = descriptor.tooltip
            styleStageBadge(
                field,
                tone: descriptor.tone
            )

        case "data":
            let isNew =
                ImportBatchHelper.isLatestImport(
                    record,
                    in: dataSource.records
                )

            field.stringValue =
                ImportBatchHelper.dataLabel(
                    for: record,
                    in: dataSource.records
                )

            if !record.isReady {
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .systemOrange,
                    backgroundColor:
                        NSColor.systemOrange.withAlphaComponent(0.10)
                )
            } else if isNew {
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .systemBlue,
                    backgroundColor:
                        NSColor.systemBlue.withAlphaComponent(0.10)
                )
            } else {
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .secondaryLabelColor,
                    backgroundColor:
                        NSColor.secondaryLabelColor.withAlphaComponent(0.08)
                )
            }

        case "job":
            let status = statuses[record.id] ?? .idle
            let state = cachedState(for: record)
            field.stringValue = status.rawValue
            field.toolTip = state.lastError

            switch status {
            case .failed:
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .systemRed,
                    backgroundColor:
                        NSColor.systemRed.withAlphaComponent(0.10)
                )
            case .readyContent, .contentDone, .mediaDone, .creativeDone, .campaignDone, .done:
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .systemGreen,
                    backgroundColor:
                        NSColor.systemGreen.withAlphaComponent(0.10)
                )
            case .checkingContent, .uploadingMedia, .creatingContent, .creatingCreative, .creatingCampaign, .gemini, .qa, .parsing:
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .systemBlue,
                    backgroundColor:
                        NSColor.systemBlue.withAlphaComponent(0.10)
                )
            default:
                WorkspaceUI.styleBadge(
                    field,
                    textColor: .secondaryLabelColor,
                    backgroundColor:
                        NSColor.secondaryLabelColor.withAlphaComponent(0.08)
                )
            }

        case "source":
            field.stringValue = record.sourceOriginalName
            field.textColor = .secondaryLabelColor

        default:
            field.stringValue = ""
        }

        container.textField = field
        container.addSubview(field)

        let centeredColumns: Set<String> = [
            "stt",
            "language",
            "data",
            "sourceStage",
            "geminiStage",
            "qaStage",
            "contentStage",
            "mediaStage",
            "creativeStage",
            "campaignStage",
            "job"
        ]

        let leading: CGFloat =
            centeredColumns.contains(columnID)
            ? 6
            : 10

        let trailing: CGFloat =
            centeredColumns.contains(columnID)
            ? -6
            : -10

        var cellConstraints = [
            field.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: leading
            ),
            field.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: trailing
            ),
            field.centerYAnchor.constraint(
                equalTo: container.centerYAnchor
            )
        ]

        let badgeColumns: Set<String> = [
            "data",
            "sourceStage",
            "geminiStage",
            "qaStage",
            "contentStage",
            "mediaStage",
            "creativeStage",
            "campaignStage",
            "job"
        ]

        if badgeColumns.contains(columnID) {
            cellConstraints.append(
                field.heightAnchor.constraint(equalToConstant: 26)
            )
        }

        NSLayoutConstraint.activate(cellConstraints)

        return container
    }

    @objc func toggleCheck(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let id = UUID(uuidString: raw) else { return }
        if sender.state == .on { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        updateSummary()
    }

    @objc func refreshAction() {
        reloadRecords()
        refreshAPIStatus()
        refreshFacebookPages(silent: true)
    }


    @objc func refreshFacebookPagesAction() {
        refreshFacebookPages(silent: false)
    }

    func refreshFacebookPages(silent: Bool) {
        guard !(EthopexConfig.shared.token ?? "").isEmpty else {
            if !silent {
                showAlert(
                    "Chưa có Ethopex Token",
                    "Mở Cài đặt API và lưu Bearer Token trước."
                )
            }
            return
        }

        refreshPagesButton.isEnabled = false
        fanpagePopup.isEnabled = false

        if !silent {
            appendLog("• Đang tải danh sách Facebook Pages từ Ethopex...")
        }

        api.fetchFacebookPages { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }

                self.refreshPagesButton.isEnabled = true
                self.fanpagePopup.isEnabled = true

                switch result {
                case .success(let pages):
                    self.facebookPages = pages

                    guard !pages.isEmpty else {
                        if !silent {
                            self.showAlert(
                                "Không có Facebook Page",
                                "EthoPex API trả danh sách page rỗng."
                            )
                        }
                        return
                    }

                    let stored =
                        FacebookPageSelectionConfig.shared.selectedPage

                    let selectedPage =
                        pages.first {
                            $0.id == stored.id &&
                            $0.externalID == stored.externalID
                        } ??
                        pages.first {
                            $0.id ==
                            FacebookPageSelectionConfig.shared.fallback.id
                        } ??
                        pages[0]

                    FacebookPageSelectionConfig.shared.selectedPage =
                        selectedPage

                    self.fanpagePopup.removeAllItems()
                    self.fanpagePopup.addItems(
                        withTitles: pages.map { $0.menuTitle }
                    )

                    if let index = pages.firstIndex(of: selectedPage) {
                        self.fanpagePopup.selectItem(at: index)
                    }

                    self.headerModel.fanpageOptions = pages.map(\.menuTitle)
                    self.headerModel.fanpageTitle = selectedPage.menuTitle

                    self.appendLog(
                        "✓ Facebook Pages: \(pages.count) page(s) loaded"
                    )
                    self.appendLog(
                        "✓ Batch Fanpage: \(selectedPage.displayName) " +
                        "[\(selectedPage.id) / \(selectedPage.externalID)]"
                    )

                case .failure(let error):
                    if !silent {
                        self.showAlert(
                            "Không tải được Facebook Pages",
                            error.localizedDescription
                        )
                    }
                    self.appendLog(
                        "✕ LOAD FACEBOOK PAGES FAILED: " +
                        error.localizedDescription
                    )
                }
            }
        }
    }

    @objc func fanpageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem

        guard index >= 0,
              index < facebookPages.count else {
            return
        }

        let page = facebookPages[index]
        FacebookPageSelectionConfig.shared.selectedPage = page
        headerModel.fanpageTitle = page.menuTitle

        appendLog(
            "Batch Fanpage: \(page.displayName) " +
            "[internal \(page.id) / external \(page.externalID)]"
        )
    }



    private func languageDisplayName(
        _ language: CampaignLanguage
    ) -> String {
        switch language {
        case .english:
            return "English"
        case .russian:
            return "Russian"
        case .arabic:
            return "Arabic"
        case .romanian:
            return "Romanian"
        case .croatian:
            return "Croatian"
        }
    }

    private func languagePopupTitle() -> String {
        let selected =
            CampaignLanguageSelectionConfig
                .shared
                .selected

        if selected.count ==
            CampaignLanguage.allCases.count {
            return "Tất cả 5 ngôn ngữ"
        }

        return CampaignLanguage.allCases
            .filter {
                selected.contains($0)
            }
            .map(\.shortLabel)
            .joined(separator: " / ")
    }

    private func configureLanguagePopover() {
        languagePopover.behavior = .transient
        languagePopover.animates = true
        languagePopover.contentSize =
            NSSize(width: 250, height: 258)

        let controller = NSViewController()
        let root = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 250,
                height: 258
            )
        )

        let title = NSTextField(
            labelWithString: "CHỌN NGÔN NGỮ"
        )
        title.font =
            .systemFont(
                ofSize: 11,
                weight: .semibold
            )
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let selectAllButton = NSButton(
            title: "Chọn tất cả 5 ngôn ngữ",
            target: self,
            action: #selector(selectAllLanguagesFromPopover(_:))
        )
        WorkspaceUI.styleSecondaryButton(
            selectAllButton,
            symbol: "checkmark.circle"
        )
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        languageCheckButtons.removeAll()

        for language in CampaignLanguage.allCases {
            let checkbox = NSButton(
                checkboxWithTitle:
                    language.shortLabel +
                    " — " +
                    languageDisplayName(language),
                target: self,
                action: #selector(toggleLanguageCheckbox(_:))
            )
            checkbox.identifier =
                NSUserInterfaceItemIdentifier(
                    language.rawValue
                )
            checkbox.font =
                .systemFont(
                    ofSize: 12,
                    weight: .medium
                )
            checkbox.translatesAutoresizingMaskIntoConstraints = false

            languageCheckButtons[language] = checkbox
            stack.addArrangedSubview(checkbox)
        }

        root.addSubview(title)
        root.addSubview(selectAllButton)
        root.addSubview(divider)
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 14
            ),
            title.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: 14
            ),

            selectAllButton.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 14
            ),
            selectAllButton.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -14
            ),
            selectAllButton.topAnchor.constraint(
                equalTo: title.bottomAnchor,
                constant: 10
            ),

            divider.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 14
            ),
            divider.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -14
            ),
            divider.topAnchor.constraint(
                equalTo: selectAllButton.bottomAnchor,
                constant: 10
            ),

            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 16
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: root.trailingAnchor,
                constant: -14
            ),
            stack.topAnchor.constraint(
                equalTo: divider.bottomAnchor,
                constant: 9
            ),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: root.bottomAnchor,
                constant: -12
            )
        ])

        controller.view = root
        languagePopover.contentViewController = controller
    }

    private func refreshLanguageSelector() {
        let selected =
            CampaignLanguageSelectionConfig
                .shared
                .selected

        languagePopupButton.title =
            languagePopupTitle()
        headerModel.languageTitle = languagePopupButton.title

        for language in CampaignLanguage.allCases {
            languageCheckButtons[language]?.state =
                selected.contains(language)
                ? .on
                : .off
        }
    }

    private func saveLanguageSelection(
        _ selected: Set<CampaignLanguage>
    ) {
        CampaignLanguageSelectionConfig
            .shared
            .selected = selected

        refreshLanguageSelector()
        updateSummary()

        let labels =
            CampaignLanguage.allCases
                .filter {
                    selected.contains($0)
                }
                .map(\.shortLabel)
                .joined(separator: ", ")

        appendLog(
            "Languages selected: \(labels)"
        )
    }

    @objc func showLanguagePopover(
        _ sender: NSButton
    ) {
        refreshLanguageSelector()

        if languagePopover.isShown {
            languagePopover.performClose(sender)
            return
        }

        languagePopover.show(
            relativeTo: sender.bounds,
            of: sender,
            preferredEdge: .maxY
        )
    }

    @objc func selectAllLanguagesFromPopover(
        _ sender: NSButton
    ) {
        saveLanguageSelection(
            Set(CampaignLanguage.allCases)
        )
        // Không đóng popover: user có thể tiếp tục bỏ tick
        // một vài language ngay trong cùng một lần mở.
    }

    @objc func toggleLanguageCheckbox(
        _ sender: NSButton
    ) {
        guard let code =
                sender.identifier?.rawValue,
              let language =
                CampaignLanguage(
                    rawValue: code
                ) else {
            return
        }

        var selected =
            CampaignLanguageSelectionConfig
                .shared
                .selected

        if sender.state == .on {
            selected.insert(language)
        } else {
            // Campaign Auto cần tối thiểu 1 language.
            guard selected.count > 1 else {
                sender.state = .on
                NSSound.beep()
                return
            }
            selected.remove(language)
        }

        saveLanguageSelection(selected)
        // Popover vẫn mở sau mỗi click để multi-select liên tục.
    }


    @objc func selectLatestImportedData() {
        guard let latestBatch =
                ImportBatchHelper.latestBatchID(
                    in: dataSource.records
                ) else {
            showAlert(
                "Chưa có DATA MỚI",
                "Các record hiện tại được tạo trước khi có tính năng đánh dấu batch import. " +
                "Sau lần Import Folder Hàng Loạt tiếp theo, tool sẽ tự đánh dấu MỚI/CŨ."
            )
            return
        }

        let newestReady =
            dataSource.records.filter {
                $0.importBatchID == latestBatch &&
                $0.isReady
            }

        guard !newestReady.isEmpty else {
            showAlert(
                "Không có DATA MỚI READY",
                "Batch import mới nhất không có record READY để chọn."
            )
            return
        }

        selectedIDs =
            Set(
                newestReady.map {
                    $0.id
                }
            )

        tableView.reloadData()
        updateSummary()

        appendLog(
            "✓ Đã chọn DATA MỚI: \(newestReady.count) record(s) từ batch import gần nhất."
        )
    }


    @objc func selectAllReady() {
        selectedIDs = Set(dataSource.records.filter { $0.isReady }.map { $0.id })
        tableView.reloadData()
        updateSummary()
    }

    @objc func clearSelection() {
        selectedIDs.removeAll()
        tableView.reloadData()
        updateSummary()
    }

    private func failureStage(
        for state: IntegrationState,
        error: String?
    ) -> String {
        let message = (error ?? "").uppercased()

        if message.contains("CAMPAIGN") || state.creativeCreated {
            return "CAMPAIGN"
        }
        if message.contains("CREATIVE") || state.uploadedImageURL != nil {
            return "CREATIVE"
        }
        if message.contains("CONTENT") || state.contentCreated {
            return "CONTENT"
        }
        if message.contains("QA") || state.geminiGenerated {
            return "QA"
        }
        if message.contains("GEMINI") || state.parsed {
            return "GEMINI"
        }
        return "SOURCE / VALIDATION"
    }

    private func updateFailureReport() {
        updateRealtimeFailureReport()

        let failedRecords = dataSource.records
            .compactMap { record -> (CampaignRecord, IntegrationState)? in
                let state = cachedState(for: record)
                guard statuses[record.id] == .failed || state.lastError != nil else {
                    return nil
                }
                return (record, state)
            }
            .sorted {
                ($0.0.stt ?? 0, $0.0.name) < ($1.0.stt ?? 0, $1.0.name)
            }

        failureReportIDs = failedRecords.map { $0.0.id }
        failureCountValue.stringValue = "\(failedRecords.count)"
        selectFailedButton.isEnabled = !failedRecords.isEmpty

        guard !failedRecords.isEmpty else {
            failureSummaryLabel.stringValue = "Không có FAILED trong lần chạy gần nhất"
            failureTextView.string =
                "CHƯA CÓ LỖI\n\n" +
                "Khi TẠO CAMPAIGN AUTO gặp lỗi, record sẽ xuất hiện ở đây cùng stage và nguyên nhân."
            return
        }

        var stageCounts: [String: Int] = [:]
        for (_, state) in failedRecords {
            let stage = failureStage(for: state, error: state.lastError)
            stageCounts[stage, default: 0] += 1
        }

        let stageOrder = ["SOURCE / VALIDATION", "GEMINI", "QA", "CONTENT", "CREATIVE", "CAMPAIGN"]
        failureSummaryLabel.stringValue = stageOrder
            .compactMap { stage in
                guard let count = stageCounts[stage] else { return nil }
                return "\(stage): \(count)"
            }
            .joined(separator: "\n")

        var lines = [String]()
        for (record, state) in failedRecords.prefix(12) {
            let stage = failureStage(for: state, error: state.lastError)
            let number = record.stt.map(String.init) ?? "-"
            let message = (state.lastError ?? "Không có error message")
                .replacingOccurrences(of: "\n", with: " ")

            lines.append("#\(number)  [\(stage)]")
            lines.append(record.name)
            lines.append("↳ \(message)")
            lines.append("")
        }

        if failedRecords.count > 12 {
            lines.append("+ \(failedRecords.count - 12) lỗi khác. Chọn FAILED để đưa toàn bộ vào batch retry.")
        }

        failureTextView.string = lines.joined(separator: "\n")
        failureTextView.scrollToBeginningOfDocument(nil)
    }

    private func updateRealtimeFailureReport() {
        let realtimeRecords = dataSource.records
            .compactMap { record -> (CampaignRecord, IntegrationState)? in
                guard realtimeFailureIDs.contains(record.id) else { return nil }
                return (record, cachedState(for: record))
            }
            .sorted {
                ($0.0.stt ?? 0, $0.0.name) < ($1.0.stt ?? 0, $1.0.name)
            }

        let totalRealtimeFailures = realtimeRecords.count + realtimeFailureMessages.count
        realtimeFailureCountValue.stringValue = "\(totalRealtimeFailures)"

        guard totalRealtimeFailures > 0 else {
            realtimeFailureTextView.string =
                "CHƯA CÓ LỖI REALTIME\n\n" +
                "Khu vực này chỉ ghi lỗi phát sinh từ lần TẠO CAMPAIGN AUTO gần nhất."
            return
        }

        var lines = realtimeFailureMessages.map { "⚠ \($0)" }
        for (record, state) in realtimeRecords {
            let stage = failureStage(for: state, error: state.lastError)
            let number = record.stt.map(String.init) ?? "-"
            let message = (state.lastError ?? "Không có error message")
                .replacingOccurrences(of: "\n", with: " ")
            lines.append("#\(number)  [\(stage)] \(record.name)")
            lines.append("↳ \(message)")
        }

        realtimeFailureTextView.string = lines.joined(separator: "\n")
        realtimeFailureTextView.scrollToEndOfDocument(nil)
    }

    @objc func selectFailedRecords() {
        guard !failureReportIDs.isEmpty else { return }
        selectedIDs = Set(failureReportIDs)
        tableView.reloadData()
        updateSummary()
        appendLog("✓ Đã chọn \(failureReportIDs.count) record FAILED để retry.")
    }

    @objc func refreshFailureReport() {
        refreshAllIntegrationStates()
        updateFailureReport()
    }

    private func selectedRecords() -> [CampaignRecord] {
        let selectedLanguages = CampaignLanguageSelectionConfig.shared.selected
        return dataSource.records
            .filter {
                selectedIDs.contains($0.id) &&
                selectedLanguages.contains(
                    CampaignLanguage.from(code: $0.effectiveLanguageCode)
                )
            }
            .sorted {
                let lhs = $0.stt ?? 0
                let rhs = $1.stt ?? 0
                if lhs == rhs { return $0.createdAt < $1.createdAt }
                return lhs < rhs
            }
    }

    private func selectedSourceRecordsForLanguageExpansion() -> [CampaignRecord] {
        let selected = dataSource.records
            .filter { selectedIDs.contains($0.id) }
            .map { dataSource.rootRecord(for: $0) }

        let unique = Dictionary(
            selected.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return unique.values.sorted {
            let lhs = $0.stt ?? 0
            let rhs = $1.stt ?? 0
            if lhs == rhs { return $0.createdAt < $1.createdAt }
            return lhs < rhs
        }
    }

    @objc func runTestPipeline() {
        let selected = selectedRecords()
        guard !selected.isEmpty else {
            showAlert("Chưa chọn dữ liệu", "Hãy tick ít nhất một record READY.")
            return
        }
        guard !(GeminiConfig.shared.apiKey ?? "").isEmpty else {
            showAlert("Chưa có Gemini API Key", "Mở Cài đặt API và lưu Gemini API key trước.")
            return
        }

        setBusy(true)
        appendLog("")
        appendLog("========== TEST PIPELINE ==========")

        engine.testPipeline(
            records: selected,
            onStatus: { [weak self] id, status in
                self?.handleStatusChange(
                    id: id,
                    status: status
                )
            },
            onLog: { [weak self] line in self?.appendLog(line) },
            completion: { [weak self] in
                guard let self else { return }
                self.refreshAllIntegrationStates()
                self.setBusy(false)
                self.tableView.reloadData()
                self.updateSummary()
                self.appendLog("========== TEST PIPELINE HOÀN TẤT ==========")
            }
        )
    }

    @objc func createContentReal() {
        let selected = selectedRecords()
        guard !selected.isEmpty else {
            showAlert("Chưa chọn dữ liệu", "Hãy tick ít nhất một record.")
            return
        }
        guard !(EthopexConfig.shared.token ?? "").isEmpty else {
            showAlert("Chưa có Ethopex Token", "Mở Cài đặt API và lưu Bearer Token trước.")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Chạy FULL Content → Creative → Campaign?"
        alert.informativeText =
            "Bạn đang chọn \(selected.count) record. Chỉ record đã QA PASS mới chạy.\n" +
            "Template Campaign: \(DefaultFacebookCampaignTemplateV1.name)\n" +
            "Fanpage batch: \(FacebookPageSelectionConfig.shared.selectedPage.displayName)\n" +
            "Campaign + Ad Set được tạo ở trạng thái PAUSED để test an toàn."
        alert.addButton(withTitle: "CHẠY FULL")
        alert.addButton(withTitle: "Hủy")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setBusy(true)
        appendLog("")
        appendLog("========== ETHOPEX FULL FLOW — REAL ==========")
        appendLog("Template: \(DefaultFacebookCampaignTemplateV1.name)")
        let batchPage = FacebookPageSelectionConfig.shared.selectedPage
        appendLog("Fanpage: \(batchPage.displayName)")
        appendLog("Page internal_id: \(batchPage.id)")
        appendLog("Page external_id: \(batchPage.externalID)")

        engine.createContentCreativeCampaign(
            records: selected,
            onStatus: { [weak self] id, status in
                self?.handleStatusChange(
                    id: id,
                    status: status
                )
            },
            onLog: { [weak self] line in self?.appendLog(line) },
            completion: { [weak self] in
                guard let self else { return }
                self.refreshAllIntegrationStates()
                self.setBusy(false)
                self.tableView.reloadData()
                self.updateSummary()
                self.appendLog("========== ETHOPEX FULL FLOW HOÀN TẤT ==========")
            }
        )
    }

    @objc func displayLinkChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        let presets = CreativeDisplayLinkPreset.allCases

        guard index >= 0, index < presets.count else { return }

        let preset = presets[index]
        CreativeDisplayLinkConfig.shared.selected = preset
        headerModel.displayLink = preset.displayName
        appendLog("Display link: \(preset.rawValue)")
    }

    @objc func createCreativeReal() {
        let selected = selectedRecords()
        guard !selected.isEmpty else {
            showAlert("Chưa chọn dữ liệu", "Hãy tick ít nhất một record.")
            return
        }
        guard !(EthopexConfig.shared.token ?? "").isEmpty else {
            showAlert("Chưa có Ethopex Token", "Mở Cài đặt API và lưu Bearer Token trước.")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Upload ảnh và tạo Creative thật trên Ethopex?"
        alert.informativeText =
            "Tool lấy Image/Name/Primary Text/Headline/Description trực tiếp từ EthopexDataManager.\n" +
            "Display link: \(CreativeDisplayLinkConfig.shared.selected.displayName)"
        alert.addButton(withTitle: "TẠO CREATIVE")
        alert.addButton(withTitle: "Hủy")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setBusy(true)
        appendLog("")
        appendLog("========== ETHOPEX MEDIA + CREATIVE — REAL ==========")

        engine.createCreativeReal(
            records: selected,
            onStatus: { [weak self] id, status in
                self?.handleStatusChange(
                    id: id,
                    status: status
                )
            },
            onLog: { [weak self] line in self?.appendLog(line) },
            completion: { [weak self] in
                guard let self else { return }
                self.refreshAllIntegrationStates()
                self.setBusy(false)
                self.tableView.reloadData()
                self.updateSummary()
                self.appendLog("========== ETHOPEX CREATIVE HOÀN TẤT ==========")
            }
        )
    }


    private func formatRunDuration(
        _ interval: TimeInterval
    ) -> String {
        let totalSeconds =
            max(
                0,
                Int(interval.rounded(.down))
            )

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            seconds
        )
    }

    private func formatRunClock(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func startMultilingualRunTimer(
        sourceCount: Int,
        targetLanguageCount: Int
    ) {
        autoRunTimer?.invalidate()
        autoRunTimer = nil

        let startedAt = Date()
        autoRunStartedAt = startedAt
        autoRunSourceCount = sourceCount
        autoRunTargetLanguageCount = targetLanguageCount
        autoRunPreparedVariantCount = 0

        runTimeLabel.stringValue = "RUN 00:00:00"
        WorkspaceUI.styleBadge(
            runTimeLabel,
            textColor: .systemOrange,
            backgroundColor:
                NSColor.systemOrange.withAlphaComponent(0.11)
        )

        let expectedMaximum =
            sourceCount * targetLanguageCount

        runTimeLabel.toolTip =
            "Started: \(formatRunClock(startedAt))\n" +
            "Source creatives: \(sourceCount)\n" +
            "Target languages: \(targetLanguageCount)\n" +
            "Up to \(expectedMaximum) language variant(s)."

        appendLog(
            "⏱ AUTO START: \(formatRunClock(startedAt))"
        )
        appendLog(
            "⏱ Batch scope: \(sourceCount) source × " +
            "\(targetLanguageCount) language = up to " +
            "\(expectedMaximum) variant(s)"
        )

        let timer = Timer(
            timeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshMultilingualRunTimer()
        }

        autoRunTimer = timer
        RunLoop.main.add(
            timer,
            forMode: .common
        )
    }

    private func refreshMultilingualRunTimer() {
        guard let startedAt = autoRunStartedAt else {
            return
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        runTimeLabel.stringValue =
            "RUN " + formatRunDuration(elapsed)
    }

    private func finishMultilingualRunTimer(
        outcome: String
    ) {
        guard let startedAt = autoRunStartedAt else {
            return
        }

        autoRunTimer?.invalidate()
        autoRunTimer = nil

        let completedAt = Date()
        let elapsed = completedAt.timeIntervalSince(startedAt)
        let formatted = formatRunDuration(elapsed)

        let successful = outcome == "DONE"

        runTimeLabel.stringValue =
            "\(outcome) \(formatted)"

        WorkspaceUI.styleBadge(
            runTimeLabel,
            textColor:
                successful
                ? .systemGreen
                : .systemRed,
            backgroundColor:
                (successful
                 ? NSColor.systemGreen
                 : NSColor.systemRed)
                    .withAlphaComponent(0.10)
        )

        var tooltip =
            "Started: \(formatRunClock(startedAt))\n" +
            "Finished: \(formatRunClock(completedAt))\n" +
            "Total: \(formatted)"

        if autoRunPreparedVariantCount > 0 {
            let average =
                elapsed /
                Double(autoRunPreparedVariantCount)

            tooltip +=
                "\nPrepared variants: \(autoRunPreparedVariantCount)" +
                "\nAverage / variant: \(formatRunDuration(average))"
        }

        runTimeLabel.toolTip = tooltip

        UserDefaults.standard.set(
            elapsed,
            forKey: "ethopex.lastMultilingualAutoDuration"
        )

        appendLog(
            "⏱ AUTO FINISH: \(formatRunClock(completedAt))"
        )
        appendLog(
            "⏱ TOTAL ELAPSED: \(formatted)"
        )

        if autoRunPreparedVariantCount > 0 {
            let average =
                elapsed /
                Double(autoRunPreparedVariantCount)

            appendLog(
                "⏱ AVERAGE / VARIANT: " +
                formatRunDuration(average) +
                " (\(autoRunPreparedVariantCount) prepared)"
            )
        }

        autoRunStartedAt = nil
    }

    @objc func createCampaignReal() {
        let sourceRecords = selectedSourceRecordsForLanguageExpansion()
        let targetLanguages = CampaignLanguageSelectionConfig.shared.selected

        guard !sourceRecords.isEmpty else {
            showAlert(
                "Chưa chọn dữ liệu",
                "Hãy tick ít nhất một record nguồn."
            )
            return
        }

        guard !targetLanguages.isEmpty else {
            showAlert(
                "Chưa chọn ngôn ngữ",
                "Hãy chọn ít nhất một language trong Campaign Setup."
            )
            return
        }

        guard !(GeminiConfig.shared.apiKey ?? "").isEmpty else {
            showAlert(
                "Chưa có Gemini API Key",
                "Multilingual AUTO cần Gemini cho Landing Page, Ad Copy và Image."
            )
            return
        }

        guard !(EthopexConfig.shared.token ?? "").isEmpty else {
            showAlert(
                "Chưa có Ethopex Token",
                "Mở Cài đặt API và lưu Bearer Token trước."
            )
            return
        }

        let page = FacebookPageSelectionConfig.shared.selectedPage
        let languageLabels = CampaignLanguage.allCases
            .filter { targetLanguages.contains($0) }
            .map(\.shortLabel)
            .joined(separator: ", ")

        let profileLines = CampaignLanguage.allCases
            .filter { targetLanguages.contains($0) }
            .map {
                let profile = LanguageCampaignTemplateRouter.profile(for: $0)
                return "\($0.shortLabel) → \(profile.templateName)"
            }
            .joined(separator: "\n")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText =
            "Multilingual AUTO cho \(sourceRecords.count) Creative nguồn?"

        alert.informativeText =
            "Tool sẽ tự tạo/chọn đúng variant cho: \(languageLabels).\n\n" +
            "Mỗi ngôn ngữ chạy đủ:\n" +
            "Ad Copy → Image localized → Landing Page → Content → Creative → Campaign\n\n" +
            "Template routing:\n\(profileLines)\n\n" +
            "Campaign đã tồn tại ở đúng language/template sẽ SKIP, không tạo lại.\n" +
            "Fanpage batch: \(page.displayName)\n" +
            "Campaign + Ad Set tạo PAUSED để test an toàn."

        alert.addButton(withTitle: "CHẠY MULTILINGUAL AUTO")
        alert.addButton(withTitle: "Hủy")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        setBusy(true)
        realtimeFailureIDs.removeAll()
        realtimeFailureMessages.removeAll()
        updateRealtimeFailureReport()

        resetAutoRunOverview(
            sourceCount: sourceRecords.count,
            targetLanguageCount: targetLanguages.count
        )

        startMultilingualRunTimer(
            sourceCount: sourceRecords.count,
            targetLanguageCount: targetLanguages.count
        )
        appendLog("")
        appendLog("========== MULTILINGUAL AUTO V1.7.4 ==========")
        appendLog("Source creatives: \(sourceRecords.count)")
        appendLog("Target languages: \(languageLabels)")
        appendLog("Image model: \(GeminiConfig.shared.imageModel)")
        appendLog("Fanpage: \(page.displayName)")
        appendLog("")
        appendLog("STEP 0 — EXPAND LANGUAGE VARIANTS")

        let preparation = MultilingualPreparationService(
            dataSource: dataSource,
            gemini: GeminiAPIClient()
        )

        preparation.prepare(
            baseRecords: sourceRecords,
            targetLanguages: targetLanguages,
            onLog: { [weak self] line in
                self?.appendLog(line)
            },
            completion: { [weak self] result in
                guard let self else { return }

                let prepared = result.records
                self.autoRunPreparedVariantCount = prepared.count

                self.attachPreparedRecordsToAutoRunOverview(
                    prepared,
                    preparationFailureCount: result.failures.count
                )

                if prepared.isEmpty {
                    self.realtimeFailureMessages.append(contentsOf: result.failures.map {
                        "\($0.recordName) [\($0.language.shortLabel)]: \($0.message)"
                    })
                    self.updateRealtimeFailureReport()
                    self.finalizeAutoRunOverview()
                    self.finishMultilingualRunTimer(
                        outcome: "FAILED"
                    )
                    self.setBusy(false)
                    self.showAlert(
                        "Không tạo được language variant",
                        result.failures
                            .map { "\($0.recordName) [\($0.language.shortLabel)]: \($0.message)" }
                            .joined(separator: "\n")
                    )
                    return
                }

                self.selectedIDs = Set(prepared.map(\.id))
                self.reloadRecords()
                self.selectedIDs = Set(prepared.map(\.id))
                self.tableView.reloadData()
                self.updateSummary()

                self.appendLog("")
                self.appendLog("STEP 1–4 — LANDING → CONTENT → CREATIVE → CAMPAIGN")
                self.appendLog("Prepared variants: \(prepared.count)")

                if !result.failures.isEmpty {
                    self.appendLog("⚠ Variant failures: \(result.failures.count)")
                    for failure in result.failures {
                        self.realtimeFailureMessages.append(
                            "\(failure.recordName) [\(failure.language.shortLabel)]: \(failure.message)"
                        )
                        self.appendLog(
                            "  - \(failure.recordName) [\(failure.language.shortLabel)]: \(failure.message)"
                        )
                    }
                    self.updateRealtimeFailureReport()
                }

                self.engine.createCampaignAutoPipeline(
                    records: prepared,
                    onStatus: { [weak self] id, status in
                        self?.handleStatusChange(
                            id: id,
                            status: status
                        )
                    },
                    onLog: { [weak self] line in
                        self?.appendLog(line)
                    },
                    completion: { [weak self] in
                        guard let self else { return }

                        self.refreshAllIntegrationStates()
                        self.finalizeAutoRunOverview()
                        self.finishMultilingualRunTimer(
                            outcome: "DONE"
                        )
                        self.setBusy(false)
                        self.tableView.reloadData()
                        self.updateSummary()

                        self.appendLog("")
                        self.appendLog(
                            "========== MULTILINGUAL AUTO HOÀN TẤT =========="
                        )
                    }
                )
            }
        )
    }

    func setBusy(_ busy: Bool) {
        headerModel.isBusy = busy
        [refreshButton, selectAllButton, selectNewButton, clearButton, testPipelineButton,
         createContentButton, createCreativeButton, createCampaignButton,
         settingsButton, selectFailedButton, refreshFailureReportButton].forEach {
            $0.isEnabled = !busy
        }
        displayLinkPopup.isEnabled = !busy
        fanpagePopup.isEnabled = !busy
        refreshPagesButton.isEnabled = !busy
        languagePopupButton.isEnabled = !busy

        if busy && languagePopover.isShown {
            languagePopover.performClose(nil)
        }

        if busy {
            progress.isHidden = false
            progress.startAnimation(nil)
        } else {
            progress.stopAnimation(nil)
            progress.isHidden = true
        }
    }

    deinit {
        autoRunTimer?.invalidate()
    }

    func appendLog(_ line: String) {
        guard let storage = logView.textStorage else { return }

        let needsLeadingNewline =
            storage.length > 0 && !storage.string.hasSuffix("\n")

        let text =
            (needsLeadingNewline ? "\n" : "") +
            line +
            "\n"

        let font =
            logView.font ??
            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        storage.append(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.textColor
                ]
            )
        )

        // Prevent huge accumulated logs from making NSTextView sluggish.
        let hardLimit = 300_000
        let keepTarget = 240_000

        if storage.length > hardLimit {
            let removeApprox = storage.length - keepTarget
            let fullText = storage.string as NSString
            let safeRange = fullText.lineRange(
                for: NSRange(location: 0, length: removeApprox)
            )
            storage.deleteCharacters(in: safeRange)
        }

        logView.scrollRangeToVisible(
            NSRange(location: storage.length, length: 0)
        )
    }

    func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
