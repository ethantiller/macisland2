import SwiftUI

/// The newest notifications macOS showed: the latest two at 3 by 1, the latest four from 3 by 2. A click opens one (its banner is
/// pressed if it is still there, else its app opens) and takes it off the list; Clear is in the widget's menu. Offered only while
/// Notifications is on. It reads nothing: it draws the inbox.
struct NotificationsWidget: View {
    let mirror: NotificationMirror
    var size = GridSize(3, 1)

    /// How many notifications a size lists.
    static func rowCount(for size: GridSize) -> Int { size.rows >= 2 ? 4 : 2 }

    private var items: [MirroredNotification] { mirror.inbox.latest(Self.rowCount(for: size)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if items.isEmpty {
                Label(emptyTitle, systemImage: "bell")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(items) { row($0) }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size.rows >= 2 ? .topLeading : .leading)
        .padding(.top, size.rows >= 2 ? 6 : 0)
        .widgetBox()
    }

    private var emptyTitle: String {
        mirror.reader.status == .needsAccess ? "Needs Accessibility" : "No Notifications"
    }

    private func row(_ notification: MirroredNotification) -> some View {
        Button {
            mirror.open(notification)
        } label: {
            HStack(spacing: 6) {
                Text(notification.headline)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                    .lineLimit(1)
                if let detail = notification.detail {
                    Text(detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([notification.headline, notification.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens it")
    }
}
