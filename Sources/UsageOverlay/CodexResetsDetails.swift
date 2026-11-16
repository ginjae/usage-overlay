import SwiftUI

/// 상태·예고·예측을 짧은 행으로 보여 주고, 원문은 링크와 툴팁에 둔다.
struct CodexResetsDetails: View {
    @ObservedObject var feed: CodexResetsStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Hovering { hovered in
                    Link("Codex Resets ↗", destination: CodexResetsStore.website)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hovered ? .primary : .secondary)
                }
                Spacer(minLength: 4)
                if feed.isRefreshing {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel("Checking reset status")
                }
            }
            if let status = feed.status {
                if let reset = status.latestReset {
                    summary("Latest", value: reset.title,
                          detail: date(reset.announcedAt), text: reset.text, source: reset.source)
                }
                if let scheduled = status.scheduledReset {
                    summary("Scheduled", value: scheduled.resetType == "banked" ? "Banked reset" : "Usage reset",
                          detail: scheduled.scheduledFor.map(date) ?? "Time TBD",
                          text: scheduled.text, source: scheduled.source)
                }
                if let watch = status.activeWatch {
                    let expired = watch.expiresAt <= now
                    summary("AI forecast",
                            value: expired ? "Expired" : watch.resetChancePercent.map { "\($0)% chance" } ?? watch.level.capitalized,
                            detail: expired ? date(watch.expiresAt) : watch.forecastWindow,
                            text: watch.text, source: watch.source)
                }
                if status.scheduledReset == nil, status.activeWatch == nil {
                    caption("No upcoming reset")
                }
            } else {
                caption(feed.error == nil ? (feed.isRefreshing ? "Checking…" : "Not checked yet") : "Status unavailable")
                    .help(feed.error ?? "")
            }
        }
    }

    private func summary(_ label: String, value: String, detail: String,
                         text: String, source: CodexResetStatus.Source) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.callout.weight(.medium))
                if let link = source.link {
                    sourceLink(detail, to: link)
                } else {
                    caption(detail).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(text)
    }

    /// 값은 늘 진해서 포인터를 올려도 달라질 게 없으므로, 회색인 보조 줄을 링크로 삼아 올리면 진해지게 한다.
    private func sourceLink(_ detail: String, to link: URL) -> some View {
        let arrow = Text(Image(systemName: "arrow.up.right")).font(.system(size: 8, weight: .medium))
        return Hovering { hovered in
            Link(destination: link) {
                // 줄이 넘어가도 화살표만 따로 떨어지지 않게 붙여 둔다.
                Text("\(detail)\u{00A0}\(arrow)")
                    .font(.caption)
                    .foregroundStyle(hovered ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // 글자 사이 빈틈에서도 눌리게 한다.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()) + " · "
            + date.formatted(.dateTime.hour().minute())
    }
}

/// 포인터가 올라와 있는지를 내용에 넘겨, 눌리는 글자만 진해지게 한다.
private struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovered = false

    var body: some View {
        content(hovered)
            .onHover { hovered = $0 }
            // 링크를 누르면 포인터가 올라온 채로 메뉴가 닫히므로, 다음에 열 때 진한 채로 남지 않게 푼다.
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                hovered = false
            }
    }
}
