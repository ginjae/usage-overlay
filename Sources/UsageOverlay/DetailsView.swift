import SwiftUI

/// 새로고침 메뉴 바로 아래에 갱신 시각과 메뉴바에 다 못 담는 값을 창마다 펼쳐 보여 준다.
/// 오버레이 · 설정 · 종료는 그 아래에 보통 메뉴 항목으로 붙는다.
struct DetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings = Settings.shared

    private var providers: [Provider] {
        settings.providerOrder.providers.filter { settings[keyPath: $0.detailsShown] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.detailsUpdated {
                Text(store.isRefreshing ? "Refreshing…"
                     : Format.freshness(of: providers.compactMap { $0.usage(in: store.snapshot) }, from: store.now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
            }
            ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                if index > 0 { Divider() }
                ProviderDetails(provider: provider, usage: provider.usage(in: store.snapshot), now: store.now)
            }
            if providers.isEmpty {
                Text("No providers shown. Turn one on in Settings → Details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: settings.detailsWidth, alignment: .leading)
    }
}

private struct ProviderDetails: View {
    @ObservedObject var settings = Settings.shared
    let provider: Provider
    let usage: ProviderUsage?
    let now: Date

    var body: some View {
        let selection = settings[keyPath: provider.detailsWindow]
        let gauges = selection.pick(from: usage?.gauges ?? [])
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(nsImage: provider.icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(settings[keyPath: provider.accent].color)
                Text(usage?.name ?? provider.name)
                    .font(.headline)
                Spacer(minLength: 4)
                if settings.detailsPlan, let plan = usage?.plan {
                    Text(plan)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            // 숫자가 남아 있어도 이번 조회가 실패했다면 그 까닭을 같이 보여 준다.
            if let note = usage?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !gauges.isEmpty {
                ForEach(gauges) { gauge in
                    WindowDetails(gauge: gauge, now: now)
                }
            } else if usage?.note == nil {
                Text(selection.emptyMessage(for: usage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WindowDetails: View {
    @ObservedObject var settings = Settings.shared
    let gauge: Gauge
    let now: Date

    var body: some View {
        let kind = settings.detailsValue
        let value = kind.percent(of: gauge)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(gauge.label)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text("\(Int(value.rounded()))% \(kind.word)")
                    .font(.subheadline.monospacedDigit())
            }
            if settings.detailsBars {
                UsageBar(fraction: value / 100, color: settings.levelColor(of: gauge).color, height: 6)
            }
            ForEach([resetLine, paceLine].compactMap { $0 }, id: \.self) { line in
                Text(line)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Resets in 2h 10m · Sat 3:20 PM". 카운트다운과 시각 중 켠 것만 잇는다.
    private var resetLine: String? {
        guard let resetsAt = gauge.resetsAt else { return nil }
        let countdown = Format.remaining(until: resetsAt, from: now)
        if countdown == "soon" { return "Resetting now" }
        switch (settings.detailsCountdown, settings.detailsResetTime) {
        case (true, true): return "Resets in \(countdown) · \(Format.clock(resetsAt))"
        case (true, false): return "Resets in \(countdown)"
        case (false, true): return "Resets \(Format.clock(resetsAt))"
        case (false, false): return nil
        }
    }

    private var paceLine: String? {
        guard settings.detailsPace, let pace = gauge.pace(at: now) else { return nil }
        switch pace {
        case .runsOut(let date) where date <= now:
            return "Limit reached until reset"
        case .runsOut(let date):
            return "At this pace, runs out in \(Format.remaining(until: date, from: now))"
        case .lasts(let used):
            let kind = settings.detailsValue
            let shown = kind == .remaining ? 100 - used : used
            return "At this pace, about \(Int(shown.rounded()))% \(kind.word) at reset"
        }
    }
}
