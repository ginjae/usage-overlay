import SwiftUI

/// 메뉴바를 누르면 뜨는 상세 창. 메뉴바에 다 못 담는 값을 창마다 펼쳐 보여 준다.
/// 설정은 바닥의 톱니바퀴가 여는 설정 창에서 바꾼다. 오버레이 켜고 끄기와 위치 되돌리기만은 자주 쓰여 여기에도 둔다.
struct DetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings = Settings.shared
    var refresh: () -> Void
    var resetOverlayPosition: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void

    private var providers: [Provider] {
        settings.providerOrder.providers.filter { settings[keyPath: $0.detailsShown] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(providers, id: \.self) { provider in
                ProviderDetails(provider: provider, usage: provider.usage(in: store.snapshot), now: store.now)
                Divider()
            }
            if providers.isEmpty {
                Text("No providers shown. Turn one on in Settings → Details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
            }
            overlayControls
            Divider()
            footer
        }
        .padding(14)
        .frame(width: settings.detailsWidth)
    }

    private var overlayControls: some View {
        HStack {
            Toggle("Overlay", isOn: $settings.overlayVisible)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer(minLength: 0)
            Button("Reset Position", action: resetOverlayPosition)
                .controlSize(.small)
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if settings.detailsUpdated {
                Text(Format.freshness(of: providers.compactMap { $0.usage(in: store.snapshot) }, from: store.now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: refresh) {
                Image(systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help(store.isRefreshing ? "Refreshing…" : "Refresh now")
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help("Settings…")
            Button(action: quit) { Image(systemName: "power") }
                .help("Quit Usage Overlay")
        }
        .buttonStyle(.borderless)
    }
}

private struct ProviderDetails: View {
    @ObservedObject var settings = Settings.shared
    let provider: Provider
    let usage: ProviderUsage?
    let now: Date

    var body: some View {
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
            if let gauges = usage?.gauges, !gauges.isEmpty {
                ForEach(gauges) { gauge in
                    WindowDetails(gauge: gauge, now: now)
                }
            } else if usage?.note == nil {
                Text(usage == nil ? "Loading…" : "No data yet")
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

    /// "Resets in 2h 10m · 3:20 PM". 카운트다운과 시각 중 켠 것만 잇는다.
    private var resetLine: String? {
        guard let resetsAt = gauge.resetsAt else { return nil }
        let countdown = Format.remaining(until: resetsAt, from: now)
        if countdown == "soon" { return "Resetting now" }
        switch (settings.detailsCountdown, settings.detailsResetTime) {
        case (true, true): return "Resets in \(countdown) · \(Format.clock(resetsAt, from: now))"
        case (true, false): return "Resets in \(countdown)"
        case (false, true): return "Resets \(Format.clock(resetsAt, from: now))"
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
