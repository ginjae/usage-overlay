import SwiftUI

/// 사용량 수치와 섞지 않고, 공개 API의 상태·예고·예측을 출처와 함께 보여 준다.
struct CodexResetsDetails: View {
    @ObservedObject var feed: CodexResetsStore
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Codex Resets").font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("Experimental").font(.caption2).foregroundStyle(.secondary)
            }
            if let status = feed.status {
                if let reset = status.latestReset {
                    entry(title: "Latest: \(reset.title)",
                          detail: date(reset.announcedAt), text: reset.text, source: reset.source)
                } else {
                    caption("No recorded reset.")
                }
                if let scheduled = status.scheduledReset {
                    Divider()
                    entry(title: scheduled.title,
                          detail: scheduled.scheduledFor.map { "Scheduled for \(date($0))" }
                            ?? "Time not specified",
                          text: scheduled.text, source: scheduled.source)
                }
                if let watch = status.activeWatch {
                    Divider()
                    let chance = watch.resetChancePercent.map { " · \($0)%" } ?? ""
                    entry(title: "AI forecast: \(watch.level.capitalized)\(chance)",
                          detail: watch.forecastWindow, text: watch.text, source: watch.source)
                    caption("\(watch.expiresAt <= now ? "Expired" : "Expires") \(date(watch.expiresAt))")
                }
                if status.scheduledReset == nil, status.activeWatch == nil {
                    caption("No scheduled reset or active forecast.")
                }
                if feed.isRefreshing { caption("Checking…") }
            } else {
                caption(feed.error ?? (feed.isRefreshing ? "Checking…" : "Not checked yet."))
            }
            Link("Data from Codex Resets", destination: CodexResetsStore.website)
                .font(.caption2)
        }
    }

    private func entry(title: String, detail: String, text: String, source: CodexResetStatus.Source) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold))
            caption(detail)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .help(text)
            if let link = source.link {
                Link("Source post ↗", destination: link).font(.caption2)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
