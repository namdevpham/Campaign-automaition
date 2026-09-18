import AppKit
import Foundation

final class APISettingsWindowController: NSWindowController {
    let geminiKeyField = NSSecureTextField(frame: .zero)
    let geminiModelField = NSTextField(frame: .zero)
    let geminiStatusLabel = NSTextField(labelWithString: "")

    let ethopexTokenField = NSSecureTextField(frame: .zero)
    let ethopexStatusLabel = NSTextField(labelWithString: "")

    var onSettingsChanged: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 610),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cài đặt API"
        window.center()
        self.init(window: window)
        setupUI()
        loadCurrentSettings()
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Kết nối API")
        title.font = .boldSystemFont(ofSize: 24)

        let geminiTitle = NSTextField(labelWithString: "1. GEMINI API")
        geminiTitle.font = .boldSystemFont(ofSize: 15)

        let geminiKeyLabel = NSTextField(labelWithString: "API Key")
        let modelLabel = NSTextField(labelWithString: "Model")

        geminiKeyField.placeholderString = "Dán Gemini API key"
        geminiModelField.placeholderString = "gemini-3.5-flash-lite"

        let testGeminiButton = NSButton(
            title: "Test Gemini",
            target: self,
            action: #selector(testGemini)
        )

        geminiStatusLabel.font = .systemFont(ofSize: 12)
        geminiStatusLabel.maximumNumberOfLines = 3
        geminiStatusLabel.lineBreakMode = .byWordWrapping

        let geminiNote = NSTextField(wrappingLabelWithString:
            "Gemini chỉ nhận Master Rules + dữ liệu Source đã parse. " +
            "API key được lưu trong macOS Keychain."
        )
        geminiNote.textColor = .secondaryLabelColor
        geminiNote.font = .systemFont(ofSize: 11)

        let divider = NSBox()
        divider.boxType = .separator

        let ethopexTitle = NSTextField(labelWithString: "2. ETHOPEX API")
        ethopexTitle.font = .boldSystemFont(ofSize: 15)

        let tokenLabel = NSTextField(labelWithString: "Bearer Token")
        ethopexTokenField.placeholderString = "Token từ app.ethopex.dev/profile"

        let contentEndpoint = NSTextField(wrappingLabelWithString:
            "Content: POST https://api-multi-be.ethopex.dev/api/v2/blog/contents/bulk"
        )
        let creativeEndpoint = NSTextField(wrappingLabelWithString:
            "Creative: POST https://api.ethopex.dev/api/v1/creatives/bulk-jobs"
        )
        contentEndpoint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        creativeEndpoint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        ethopexStatusLabel.font = .systemFont(ofSize: 12)
        ethopexStatusLabel.maximumNumberOfLines = 2

        let testEthopexButton = NSButton(
            title: "Test Ethopex",
            target: self,
            action: #selector(testEthopex)
        )

        let pasteEthopexButton = NSButton(
            title: "Dán từ clipboard",
            target: self,
            action: #selector(pasteEthopexToken)
        )

        let ethopexNote = NSTextField(wrappingLabelWithString:
            "HAR cho thấy endpoint GET /api/v1/profile/permissions có thể kiểm tra token mà không tạo dữ liệu. " +
            "Tool cũng đã map Upload Media và Create Creative từ request thật của Ethopex."
        )
        ethopexNote.textColor = .secondaryLabelColor
        ethopexNote.font = .systemFont(ofSize: 11)

        let saveButton = NSButton(
            title: "Lưu cài đặt",
            target: self,
            action: #selector(saveSettings)
        )
        saveButton.keyEquivalent = "\r"

        let closeButton = NSButton(
            title: "Đóng",
            target: self,
            action: #selector(closeWindow)
        )

        let views: [NSView] = [
            title,
            geminiTitle, geminiKeyLabel, geminiKeyField, modelLabel, geminiModelField,
            testGeminiButton, geminiStatusLabel, geminiNote,
            divider,
            ethopexTitle, tokenLabel, ethopexTokenField, pasteEthopexButton, testEthopexButton,
            contentEndpoint, creativeEndpoint, ethopexStatusLabel, ethopexNote,
            saveButton, closeButton
        ]

        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),

            geminiTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            geminiTitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),

            geminiKeyLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            geminiKeyLabel.topAnchor.constraint(equalTo: geminiTitle.bottomAnchor, constant: 16),
            geminiKeyLabel.widthAnchor.constraint(equalToConstant: 100),

            geminiKeyField.leadingAnchor.constraint(equalTo: geminiKeyLabel.trailingAnchor, constant: 10),
            geminiKeyField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            geminiKeyField.centerYAnchor.constraint(equalTo: geminiKeyLabel.centerYAnchor),

            modelLabel.leadingAnchor.constraint(equalTo: geminiKeyLabel.leadingAnchor),
            modelLabel.topAnchor.constraint(equalTo: geminiKeyLabel.bottomAnchor, constant: 18),
            modelLabel.widthAnchor.constraint(equalTo: geminiKeyLabel.widthAnchor),

            geminiModelField.leadingAnchor.constraint(equalTo: geminiKeyField.leadingAnchor),
            geminiModelField.widthAnchor.constraint(equalToConstant: 260),
            geminiModelField.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),

            testGeminiButton.leadingAnchor.constraint(equalTo: geminiModelField.trailingAnchor, constant: 10),
            testGeminiButton.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),

            geminiStatusLabel.leadingAnchor.constraint(equalTo: geminiKeyField.leadingAnchor),
            geminiStatusLabel.trailingAnchor.constraint(equalTo: geminiKeyField.trailingAnchor),
            geminiStatusLabel.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 12),

            geminiNote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            geminiNote.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            geminiNote.topAnchor.constraint(equalTo: geminiStatusLabel.bottomAnchor, constant: 10),

            divider.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            divider.topAnchor.constraint(equalTo: geminiNote.bottomAnchor, constant: 18),

            ethopexTitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            ethopexTitle.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 18),

            tokenLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            tokenLabel.topAnchor.constraint(equalTo: ethopexTitle.bottomAnchor, constant: 16),
            tokenLabel.widthAnchor.constraint(equalToConstant: 100),

            ethopexTokenField.leadingAnchor.constraint(equalTo: tokenLabel.trailingAnchor, constant: 10),
            ethopexTokenField.trailingAnchor.constraint(equalTo: pasteEthopexButton.leadingAnchor, constant: -8),
            ethopexTokenField.centerYAnchor.constraint(equalTo: tokenLabel.centerYAnchor),

            pasteEthopexButton.trailingAnchor.constraint(equalTo: testEthopexButton.leadingAnchor, constant: -8),
            pasteEthopexButton.centerYAnchor.constraint(equalTo: tokenLabel.centerYAnchor),

            testEthopexButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            testEthopexButton.centerYAnchor.constraint(equalTo: tokenLabel.centerYAnchor),

            contentEndpoint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            contentEndpoint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            contentEndpoint.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 18),

            creativeEndpoint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            creativeEndpoint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            creativeEndpoint.topAnchor.constraint(equalTo: contentEndpoint.bottomAnchor, constant: 8),

            ethopexStatusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            ethopexStatusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            ethopexStatusLabel.topAnchor.constraint(equalTo: creativeEndpoint.bottomAnchor, constant: 12),

            ethopexNote.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            ethopexNote.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            ethopexNote.topAnchor.constraint(equalTo: ethopexStatusLabel.bottomAnchor, constant: 10),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),

            saveButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])
    }

    private func loadCurrentSettings() {
        geminiModelField.stringValue = GeminiConfig.shared.model

        if let key = GeminiConfig.shared.apiKey, !key.isEmpty {
            geminiKeyField.stringValue = key
            geminiStatusLabel.stringValue = "✓ Gemini API key đã lưu."
            geminiStatusLabel.textColor = .systemGreen
        } else {
            geminiStatusLabel.stringValue = "Chưa có Gemini API key."
            geminiStatusLabel.textColor = .secondaryLabelColor
        }

        if let token = EthopexConfig.shared.token, !token.isEmpty {
            ethopexTokenField.stringValue = token
            ethopexStatusLabel.stringValue = "✓ Ethopex Bearer Token đã lưu. Chưa gửi request tạo dữ liệu."
            ethopexStatusLabel.textColor = .systemGreen
        } else {
            ethopexStatusLabel.stringValue = "Chưa có Ethopex Bearer Token."
            ethopexStatusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func testGemini() {
        geminiStatusLabel.stringValue = "Đang kiểm tra Gemini..."
        geminiStatusLabel.textColor = .secondaryLabelColor

        GeminiAPIClient().testConnection(
            apiKey: geminiKeyField.stringValue,
            model: geminiModelField.stringValue
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.geminiStatusLabel.stringValue = "✓ \(message)"
                self.geminiStatusLabel.textColor = .systemGreen

            case .failure(let error):
                self.geminiStatusLabel.stringValue = "✕ \(error.localizedDescription)"
                self.geminiStatusLabel.textColor = .systemRed
            }
        }
    }


    @objc private func testEthopex() {
        do {
            try EthopexConfig.shared.save(token: ethopexTokenField.stringValue)
        } catch {
            ethopexStatusLabel.stringValue = "✕ \(error.localizedDescription)"
            ethopexStatusLabel.textColor = .systemRed
            return
        }

        ethopexStatusLabel.stringValue = "Đang kiểm tra Ethopex Token..."
        ethopexStatusLabel.textColor = .secondaryLabelColor

        EthopexAPIClient().testConnection { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                self.ethopexStatusLabel.stringValue = "✓ \(message)"
                self.ethopexStatusLabel.textColor = .systemGreen

            case .failure(let error):
                self.ethopexStatusLabel.stringValue = "✕ \(error.localizedDescription)"
                self.ethopexStatusLabel.textColor = .systemRed
            }
        }
    }

    @objc private func pasteEthopexToken() {
        guard let pasted = NSPasteboard.general.string(forType: .string),
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ethopexStatusLabel.stringValue = "✕ Clipboard chưa có Ethopex token."
            ethopexStatusLabel.textColor = .systemRed
            return
        }

        ethopexTokenField.stringValue = pasted
        testEthopex()
    }

    @objc private func saveSettings() {
        do {
            try GeminiConfig.shared.save(
                apiKey: geminiKeyField.stringValue,
                model: geminiModelField.stringValue
            )
            try EthopexConfig.shared.save(token: ethopexTokenField.stringValue)

            loadCurrentSettings()
            onSettingsChanged?()
        } catch {
            showAlert("Không lưu được API settings", error.localizedDescription)
        }
    }

    @objc private func closeWindow() {
        close()
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
