import AppKit
import SwiftUI

final class CampaignHeaderModel: ObservableObject {
    @Published var searchText = ""
    @Published var summary = "Đang tải dữ liệu..."
    @Published var displayLink = "search.com"
    @Published var languageTitle = "Tất cả 5 ngôn ngữ"
    @Published var fanpageTitle = "Chưa chọn fanpage"
    @Published var fanpageOptions: [String] = []
    @Published var readyCount = "0"
    @Published var runTotal = "0"
    @Published var selectedCount = "0"
    @Published var runningCount = "0"
    @Published var createdCount = "0"
    @Published var failedCount = "0"
    @Published var runTime = "TIME 00:00:00"
    @Published var isBusy = false
}

struct CampaignSwiftUIHeader: View {
    @ObservedObject var model: CampaignHeaderModel
    let displayLinkOptions: [String]
    let onSearchChanged: (String) -> Void
    let onRefresh: () -> Void
    let onSelectAll: () -> Void
    let onSelectNew: () -> Void
    let onClear: () -> Void
    let onDisplayLinkChanged: (String) -> Void
    let onLanguages: () -> Void
    let onLanguageAnchor: (NSView) -> Void
    let onFanpageChanged: (String) -> Void
    let onRefreshPages: () -> Void
    let onAPI: () -> Void
    let onCreateCampaign: () -> Void

    private let teal = Color(nsColor: .systemTeal)
    private let purple = Color(nsColor: .systemPurple)
    private let blue = Color(nsColor: .systemBlue)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                dataCard
                    .frame(width: 395)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                campaignCard
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
            }
            .frame(height: 148, alignment: .topLeading)
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: WorkspaceUI.surface))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
        .opacity(model.isBusy ? 0.72 : 1)
        .animation(.easeOut(duration: 0.18), value: model.isBusy)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Campaign Automation")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Chọn dữ liệu  •  Cấu hình  •  Tạo campaign")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Label("API CHECK ON ACTION", systemImage: "bolt.horizontal.circle.fill")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Color(nsColor: WorkspaceUI.cyan))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(nsColor: WorkspaceUI.cyan).opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private var dataCard: some View {
        controlCard(tint: teal) {
            cardTitle("DATA SELECTION", tint: teal, icon: "square.stack.3d.up.fill")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Tìm theo tên hoặc headline", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .onChange(of: model.searchText) { value in
                        onSearchChanged(value)
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.black.opacity(0.20))
            .clipShape(Capsule())

            HStack(spacing: 6) {
                compactButton("Tất cả", icon: "checkmark.circle", tint: teal, action: onSelectAll)
                compactButton("DATA mới", icon: "sparkles", tint: purple, action: onSelectNew)
                compactButton("Bỏ chọn", icon: "xmark.circle", tint: .secondary, action: onClear)
                compactButton("Làm mới", icon: "arrow.clockwise", tint: .secondary, action: onRefresh)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var campaignCard: some View {
        controlCard(tint: purple) {
            HStack {
                cardTitle("CAMPAIGN SETUP", tint: purple, icon: "slider.horizontal.3")
                statusPill("AUTO MODE • READY", tint: purple)
                actionIconButton("API", icon: "gearshape", action: onAPI)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                selectionMenu(
                    title: "Display link",
                    value: model.displayLink,
                    options: displayLinkOptions,
                    tint: blue,
                    action: onDisplayLinkChanged
                )
                fieldButton(
                    title: "Languages",
                    value: model.languageTitle,
                    tint: purple,
                    action: onLanguages
                )
            }

            HStack(spacing: 8) {
                selectionMenu(
                    title: "Fanpage",
                    value: model.fanpageTitle,
                    options: model.fanpageOptions,
                    tint: purple,
                    action: onFanpageChanged
                )
                .layoutPriority(1)
                actionIconButton("Pages", icon: "arrow.clockwise", action: onRefreshPages)
                    .frame(width: 76)
            }

            Button(action: onCreateCampaign) {
                Label("TẠO CAMPAIGN AUTO", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledCampaignButtonStyle(color: blue))
            .disabled(model.isBusy)
        }
    }

    private func statusPill(_ title: String, tint: Color) -> some View {
                Text(title)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    private func controlCard<Content: View>(
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5, content: content)
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: WorkspaceUI.raisedSurface).opacity(0.74))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(tint.opacity(0.42), lineWidth: 0.8)
            )
    }

    private func cardTitle(_ title: String, tint: Color, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(tint)
    }

    private func compactButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .buttonStyle(DataSelectionButtonStyle(tint: tint))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isBusy)
    }

    private func actionIconButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
        }
        .buttonStyle(CompactCampaignButtonStyle(tint: .secondary))
        .disabled(model.isBusy)
    }

    private func selectionMenu(
        title: String,
        value: String,
        options: [String],
        tint: Color,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { action(option) }
                }
            } label: {
                fieldSurface(value: value, tint: tint)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .tint(tint)
    }

    private func fieldButton(
        title: String,
        value: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Button(action: action) {
                fieldSurface(value: value, tint: tint)
                    .overlay(
                        LanguagePopoverAnchor(onReady: onLanguageAnchor)
                            .allowsHitTesting(false)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldSurface(value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(tint)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 0.6)
        )
    }
}

private struct LanguagePopoverAnchor: NSViewRepresentable {
    let onReady: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onReady(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onReady(nsView)
        }
    }
}

private struct CompactCampaignButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct DataSelectionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 0.6)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct FilledCampaignButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(color.opacity(configuration.isPressed ? 0.72 : 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}
