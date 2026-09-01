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
            Text(freshness)
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

    /// 값이 언제 것인지 늘 띄운다. 조용하면 멈춘 건지 최신인 건지 알 수 없다.
    /// 어디서 온 값인지(Web/Local)는 여기 두면 어느 공급자 것인지 알 수 없어 메뉴바 툴팁에만 둔다.
    private var freshness: String {
        let providers = [store.snapshot.claude, store.snapshot.codex].compactMap { $0 }
        guard !providers.isEmpty else { return "Loading…" }
        guard let oldest = providers.compactMap(\.updatedAt).min() else { return "Updated —" }
        return "Updated " + Format.since(oldest, from: store.now)
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

    /// API는 "쓴 양"을 주지만 화면에는 "남은 양"을 보여 준다.
    /// 모델은 원본 의미를 그대로 두고 표시 단계에서만 뒤집는다.
    private var remaining: Double { max(0, 100 - gauge.percent) }
    private var fraction: Double { min(max(remaining / 100, 0), 1) }

    private var color: Color {
        switch remaining {
        case ..<20: return Color(red: 0.94, green: 0.38, blue: 0.34)
        case ..<50: return Color(red: 0.95, green: 0.72, blue: 0.25)
        default: return Color(red: 0.30, green: 0.78, blue: 0.47)
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
                Capsule().fill(color).frame(width: 72 * fraction)
            }
            .frame(width: 72, height: 5)

            Text("\(Int(remaining.rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 32, alignment: .trailing)

            Text(Format.remaining(until: gauge.resetsAt, from: now))
                .font(.system(size: 9.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
