import SwiftUI

struct OverlayView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings = Settings.shared

    private var providers: [Provider] {
        settings.providerOrder.providers.filter { settings[keyPath: $0.overlayShown] }
    }

    var body: some View {
        let scale = settings.overlayScale
        VStack(alignment: .leading, spacing: 11 * scale) {
            ForEach(providers, id: \.self) { provider in
                ProviderBlock(provider: provider, usage: provider.usage(in: store.snapshot))
            }
            // 둘 다 끄면 바닥글만 남아 빈 상자처럼 보인다. 고장이 아니라는 것만 알려 준다.
            if providers.isEmpty {
                Text("No providers shown")
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
            }
            if settings.overlayFooter { footer }
        }
        .environment(\.now, store.now)
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 11 * scale)
        .frame(width: settings.overlayWidth, alignment: .leading)
        .modifier(Backdrop(background: settings.overlayBackground, shape: shape))
        .overlay {
            if settings.overlayBorder {
                shape.strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            }
        }
        .opacity(settings.overlayOpacity)
        .modifier(WindowDrag(enabled: !settings.overlayLocked))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: settings.overlayCornerRadius, style: .continuous)
    }

    private var footer: some View {
        let scale = settings.overlayScale
        return HStack(spacing: 4) {
            Text(freshness)
                .font(.system(size: 9 * scale))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Button(action: { store.refresh() }) {
                Image(systemName: store.isRefreshing ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14 * scale, height: 14 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .help(store.isRefreshing ? "Refreshing…" : "Refresh now")
        }
        .padding(.top, -2)
    }

    /// 값이 언제 것인지 늘 띄운다. 조용하면 멈춘 건지 최신인 건지 알 수 없다.
    private var freshness: String {
        Format.freshness(of: providers.compactMap { $0.usage(in: store.snapshot) }, from: store.now)
    }
}

/// 배경을 잡고 끌면 패널이 따라온다. 새로고침 버튼은 자기 제스처가 먼저라 그대로 눌린다.
/// macOS 27 부터 NSHostingView 가 마우스 다운을 직접 받아 버려서
/// `isMovableByWindowBackground` 만으로는 창이 끌리지 않는다.
/// 다른 앱을 쓰다 돌아온 첫 클릭은 패널을 key 로 만드는 데만 쓰여 제스처가 무시되므로,
/// 그 클릭으로도 바로 끌리도록 활성화 이벤트를 받는다.
/// 26 까지는 패널의 배경 드래그가 잘 되므로 그쪽은 건드리지 않는다. 위치를 잠그면 어느 쪽도 끌지 않는다.
private struct WindowDrag: ViewModifier {
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            if enabled {
                content
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// 고른 바탕을 패널 모양대로 깐다.
private struct Backdrop: ViewModifier {
    let background: OverlayBackground
    let shape: RoundedRectangle

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *), background == .liquidGlass {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(background.style, in: shape)
        }
        #else
        content.background(background.style, in: shape)
        #endif
    }
}

/// 분 단위 시계를 하위 뷰에 흘려보낸다.
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
    @ObservedObject var settings = Settings.shared
    let provider: Provider
    let usage: ProviderUsage?

    var body: some View {
        let scale = settings.overlayScale
        let selection = settings[keyPath: provider.overlayWindow]
        let gauges = selection.pick(from: usage?.gauges ?? [])
        VStack(alignment: .leading, spacing: 5 * scale) {
            if settings.overlayHeader {
                HStack(spacing: 5 * scale) {
                    Image(nsImage: provider.icon)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 11 * scale, height: 11 * scale)
                        .foregroundStyle(settings[keyPath: provider.accent].color)
                    Text(usage?.name ?? provider.name)
                        .font(.system(size: 11 * scale, weight: .semibold))
                    Spacer(minLength: 4)
                    if settings.overlayPlan, let plan = usage?.plan {
                        Text(plan)
                            .font(.system(size: 9 * scale, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !gauges.isEmpty {
                ForEach(gauges) { gauge in
                    GaugeRow(gauge: gauge)
                }
            } else {
                Text(usage?.note ?? selection.emptyMessage(for: usage))
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GaugeRow: View {
    @Environment(\.now) private var now
    @ObservedObject var settings = Settings.shared
    let gauge: Gauge

    var body: some View {
        let scale = settings.overlayScale
        // API는 "쓴 양"을 준다. 모델은 원본 의미를 그대로 두고, 남은 양으로 볼지는 표시 단계에서만 고른다.
        let value = settings.overlayValue.percent(of: gauge)
        HStack(spacing: 6 * scale) {
            if settings.overlayLabels {
                Text(gauge.label)
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                    .frame(width: 46 * scale, alignment: .leading)
            }

            if settings.overlayBars {
                UsageBar(fraction: value / 100, color: settings.levelColor(of: gauge).color,
                         height: settings.overlayBarHeight)
            } else {
                Spacer(minLength: 0)
            }

            if settings.overlayPercent {
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 10 * scale, weight: .medium).monospacedDigit())
                    .frame(width: 32 * scale, alignment: .trailing)
            }

            if settings.overlayCountdown {
                Text(Format.remaining(until: gauge.resetsAt, from: now))
                    .font(.system(size: 9.5 * scale).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 46 * scale, alignment: .trailing)
            }
        }
    }
}

/// 한도 막대. 오버레이와 상세 창이 같이 쓴다. 남은 양을 띄우면 줄어들고, 쓴 양을 띄우면 차오른다.
struct UsageBar: View {
    let fraction: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}
