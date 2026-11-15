import SwiftUI

/// 상태·예고·예측을 짧은 행으로 보여 주고, 원문은 링크와 툴팁에 둔다.
struct CodexResetsDetails: View {
    @ObservedObject var feed: CodexResetsStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Link("Codex Resets ↗", destination: CodexResetsStore.website)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            if let link = source.link {
                Link(destination: link) { valueLabel(value, detail: detail, linked: true) }
                    .buttonStyle(.plain)
            } else {
                valueLabel(value, detail: detail, linked: false)
            }
        }
        .help(text)
    }

    private func valueLabel(_ value: String, detail: String, linked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(value).font(.callout.weight(.medium))
                if linked {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            caption(detail).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()) + " · "
            + date.formatted(.dateTime.hour().minute())
    }
}
