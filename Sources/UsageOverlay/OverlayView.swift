import SwiftUI

struct OverlayView: View {
    @ObservedObject var store: UsageStore

    /// Claude 브랜드 주황. Codex는 로고가 단색이라 본문 색을 그대로 쓴다.
    private let claudeAccent = Color(red: 0.85, green: 0.45, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ProviderBlock(usage: store.snapshot.claude,
                          fallbackName: "Claude",
                          icon: Icons.claude,
                          accent: claudeAccent)
            ProviderBlock(usage: store.snapshot.codex,
                          fallbackName: "Codex",
                          icon: Icons.codex,
                          accent: .primary)
            footer
        }
        .environment(\.now, store.now)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 244, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        )
        .opacity(Prefs.opacity)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(sourceSummary)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Button(action: { store.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing
                               ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                               : .default,
                               value: store.isRefreshing)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh now")
        }
        .padding(.top, -2)
    }

    /// 어디서 온 값인지와, 오래됐으면 얼마나 오래됐는지.
    private var sourceSummary: String {
        let providers = [store.snapshot.claude, store.snapshot.codex].compactMap { $0 }
        guard !providers.isEmpty else { return "Loading…" }
        var text = Set(providers.map(\.source.rawValue)).sorted().joined(separator: "·")
        if let oldest = providers.compactMap(\.updatedAt).min(),
           let age = Format.age(oldest, from: store.now) {
            text += " · \(age)"
        }
        return text
    }
}

/// 1초마다 갱신되는 시계를 하위 뷰에 흘려보낸다.
private struct NowKey: EnvironmentKey {
    static let defaultValue = Date()
}

extension EnvironmentValues {
    var now: Date {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }
}

private struct ProviderBlock: View {
    let usage: ProviderUsage?
    let fallbackName: String
    let icon: NSImage
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(accent)
                Text(usage?.name ?? fallbackName)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                if let plan = usage?.plan {
                    Text(plan)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let gauges = usage?.gauges, !gauges.isEmpty {
                ForEach(gauges) { gauge in
                    GaugeRow(gauge: gauge)
                }
            } else {
                Text(usage?.note ?? "Loading…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GaugeRow: View {
    @Environment(\.now) private var now
    let gauge: Gauge

    private var fraction: Double { min(max(gauge.percent / 100, 0), 1) }

    private var color: Color {
        switch gauge.percent {
        case ..<50: return Color(red: 0.30, green: 0.78, blue: 0.47)
        case ..<80: return Color(red: 0.95, green: 0.72, blue: 0.25)
        default: return Color(red: 0.94, green: 0.38, blue: 0.34)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(gauge.label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: max(2, 72 * fraction))
            }
            .frame(width: 72, height: 5)

            Text("\(Int(gauge.percent.rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 32, alignment: .trailing)

            Text(Format.remaining(until: gauge.resetsAt, from: now))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
