import AppKit
import SwiftUI

/// 두 공급자. 이름 · 로고 · 설정 자리처럼 공급자마다 달라지는 것을 한곳에서 찾는다.
enum Provider: CaseIterable {
    case claude, codex

    var name: String { self == .claude ? "Claude" : "Codex" }
    var icon: NSImage { self == .claude ? Icons.claude : Icons.codex }

    func usage(in snapshot: Snapshot) -> ProviderUsage? {
        self == .claude ? snapshot.claude : snapshot.codex
    }

    /// 고를 수 있는 창. Fable 전용 주간 창은 Claude 일부 요금제에만 있다.
    var windowChoices: [WindowChoice] {
        self == .claude ? WindowChoice.allCases : WindowChoice.allCases.filter { $0 != .fable }
    }

    var menuBarShown: ReferenceWritableKeyPath<Settings, Bool> {
        self == .claude ? \.menuBarClaude : \.menuBarCodex
    }

    var menuBarWindow: ReferenceWritableKeyPath<Settings, WindowChoice> {
        self == .claude ? \.menuBarClaudeWindow : \.menuBarCodexWindow
    }

    var menuBarClockWindow: ReferenceWritableKeyPath<Settings, ClockWindowChoice> {
        self == .claude ? \.menuBarClaudeClockWindow : \.menuBarCodexClockWindow
    }

    var clockWindowChoices: [ClockWindowChoice] {
        self == .claude ? ClockWindowChoice.allCases : ClockWindowChoice.allCases.filter { $0 != .fable }
    }

    var detailsShown: ReferenceWritableKeyPath<Settings, Bool> {
        self == .claude ? \.detailsClaude : \.detailsCodex
    }

    var detailsWindow: ReferenceWritableKeyPath<Settings, WindowSelection> {
        self == .claude ? \.detailsClaudeWindow : \.detailsCodexWindow
    }

    var overlayShown: ReferenceWritableKeyPath<Settings, Bool> {
        self == .claude ? \.overlayClaude : \.overlayCodex
    }

    var overlayWindow: ReferenceWritableKeyPath<Settings, WindowSelection> {
        self == .claude ? \.overlayClaudeWindow : \.overlayCodexWindow
    }

    /// 기본 창과 계정에서 받은 추가 창. 지금 응답에 없어도 이미 고른 창은 끌 수 있게 남긴다.
    func windowLabels(from gauges: [Gauge], selection: WindowSelection) -> [String] {
        let known = windowChoices.compactMap(\.label)
        let extra = Set(gauges.map(\.label)).union(selection.selectedLabels).subtracting(known)
        return known + extra.sorted()
    }

    var accent: ReferenceWritableKeyPath<Settings, Tint> {
        self == .claude ? \.claudeAccent : \.codexAccent
    }
}

/// 공급자를 어느 쪽부터 놓을지. 메뉴바 · 상세 창 · 오버레이가 모두 따른다.
enum ProviderOrder: String, CaseIterable, PrefValue {
    case claudeFirst, codexFirst

    var title: String { self == .claudeFirst ? "Claude, then Codex" : "Codex, then Claude" }
    var providers: [Provider] { self == .claudeFirst ? [.claude, .codex] : [.codex, .claude] }
}

/// 어떤 한도 창을 보여 줄지.
enum WindowChoice: String, CaseIterable, PrefValue {
    case tightest, fiveHour, weekly, fable, all

    var title: String {
        switch self {
        case .tightest: return "Tightest Window"
        case .fiveHour: return "5-hour Window"
        case .weekly: return "Weekly Window"
        case .fable: return "Fable Weekly Window"
        case .all: return "All Windows"
        }
    }

    /// 이 설정이 고르는 게이지들. 고른 창이 그 공급자에 없으면 가장 빡빡한 창으로 떨어진다.
    /// 빈칸보다 다른 창이라도 보여 주는 편이 낫다.
    func pick(from gauges: [Gauge]) -> [Gauge] {
        guard let label else {
            return self == .all ? gauges : [tightest(gauges)].compactMap { $0 }
        }
        return [gauges.first { $0.label == label } ?? tightest(gauges)].compactMap { $0 }
    }

    /// 이름으로 고르는 창. 가장 빡빡한 창과 모든 창은 이름으로 고르지 않는다.
    var label: String? {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .fable: return "Fable"
        case .tightest, .all: return nil
        }
    }

    /// 남은 양이 가장 적은 창 = 사용률이 가장 높은 창.
    private func tightest(_ gauges: [Gauge]) -> Gauge? {
        gauges.max { $0.percent < $1.percent }
    }
}

/// 같은 창 이름도 화면·공급자가 다르면 별도의 Form 행이다.
struct WindowToggleID: Hashable {
    let preference: ReferenceWritableKeyPath<Settings, WindowSelection>
    let label: String
}

/// 상세 창과 오버레이는 여러 창을 함께 고른다. 선택하지 않은 창으로 대신 표시하지 않는다.
enum WindowSelection: Equatable, PrefValue {
    case all, tightest, selected(Set<String>)

    enum Mode: CaseIterable {
        case all, selected, tightest

        var title: String {
            switch self {
            case .all: return "All Windows"
            case .selected: return "Selected Windows"
            case .tightest: return "Tightest Window"
            }
        }
    }

    var mode: Mode {
        switch self {
        case .all: return .all
        case .tightest: return .tightest
        case .selected: return .selected
        }
    }

    var selectedLabels: Set<String> {
        if case .selected(let labels) = self { return labels }
        return []
    }

    init?(stored: Any) {
        // 이전 오버레이의 단일 창 설정도 같은 키에서 그대로 읽는다.
        if let raw = stored as? String, let old = WindowChoice(rawValue: raw) {
            if let label = old.label { self = .selected([label]) }
            else { self = old == .all ? .all : .tightest }
        } else if let labels = stored as? [String] {
            self = .selected(Set(labels))
        } else {
            return nil
        }
    }

    var stored: Any {
        switch self {
        case .all: return "all"
        case .tightest: return "tightest"
        case .selected(let labels): return labels.sorted()
        }
    }

    func pick(from gauges: [Gauge]) -> [Gauge] {
        switch self {
        case .all: return gauges
        case .tightest: return WindowChoice.tightest.pick(from: gauges)
        case .selected(let labels): return gauges.filter { labels.contains($0.label) }
        }
    }

    func emptyMessage(for usage: ProviderUsage?) -> String {
        if case .selected(let labels) = self, labels.isEmpty { return "No windows selected" }
        guard let usage else { return "Loading…" }
        return usage.gauges.isEmpty ? "No data yet" : "Selected windows aren't available"
    }
}

/// 퍼센트를 남은 양으로 볼지 쓴 양으로 볼지.
enum PercentKind: String, CaseIterable, PrefValue {
    case remaining, used

    var title: String { self == .remaining ? "Percent Left" : "Percent Used" }
    /// 숫자 뒤에 붙여 뜻을 밝히는 말. 예) `39% left`
    var word: String { self == .remaining ? "left" : "used" }

    func percent(of gauge: Gauge) -> Double {
        self == .remaining ? max(0, 100 - gauge.percent) : gauge.percent
    }
}

/// 숫자 앞 창 이름. 예전에는 켜고 끄기만 있었다. 그때 저장한 참 · 거짓도 읽는다.
enum LabelStyle: String, CaseIterable, PrefValue {
    case off, short, full

    init?(stored: Any) {
        if let on = stored as? Bool {
            self = on ? .short : .off
            return
        }
        guard let raw = stored as? String, let style = Self(rawValue: raw) else { return nil }
        self = style
    }

    var title: String {
        switch self {
        case .off: return "None"
        case .short: return "Short (5h, 7d)"
        case .full: return "Full (5-hour, Weekly)"
        }
    }

    func text(for gauge: Gauge) -> String? {
        switch self {
        case .off: return nil
        case .short: return gauge.shortLabel
        case .full: return gauge.label
        }
    }
}

/// 리셋까지 남은 시간을 붙일지, 붙인다면 어떤 꼴로. 예전에는 켜고 끄기만 있었다.
enum MenuBarReset: String, CaseIterable, PrefValue {
    case off, countdown, logoClock, ringClock

    init?(stored: Any) {
        if let on = stored as? Bool {
            self = on ? .countdown : .off
            return
        }
        guard let raw = stored as? String, let reset = Self(rawValue: raw) else { return nil }
        self = reset
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .countdown: return "Countdown"
        case .logoClock: return "Logo Clock"
        case .ringClock: return "Ring Clock"
        }
    }

    /// 시계는 로고 위에 그린다. 고른 동안에는 로고를 꺼 두었어도 띄운다.
    var face: LogoClock.Face? {
        switch self {
        case .off, .countdown: return nil
        case .logoClock: return .sweep
        case .ringClock: return .ring
        }
    }
}

/// 공급자마다 하나인 리셋 시계의 기준 창. 퍼센트로 보이지 않는 창도 고를 수 있다.
enum ClockWindowChoice: String, CaseIterable, PrefValue {
    case firstShown, tightest, fiveHour, weekly, fable

    var title: String { window?.title ?? "First Shown Window" }

    func pick(from gauges: [Gauge], shown: [Gauge]) -> Gauge? {
        if let window { return window.pick(from: gauges).first }
        return shown.first
    }

    private var window: WindowChoice? {
        switch self {
        case .firstShown: return nil
        case .tightest: return .tightest
        case .fiveHour: return .fiveHour
        case .weekly: return .weekly
        case .fable: return .fable
        }
    }
}

/// 시계에서 칠할 쪽.
enum ClockFill: String, CaseIterable, PrefValue {
    /// 퍼센트와 같은 쪽. 남은 양을 띄우면 남은 시간을, 쓴 양을 띄우면 지난 시간을 칠해 둘을 견줄 수 있다.
    case matchPercent, timeLeft, timeGone

    var title: String {
        switch self {
        case .matchPercent: return "Same as Percent"
        case .timeLeft: return "Time Left"
        case .timeGone: return "Time Gone"
        }
    }
}

/// 같은 공급자의 창 사이에 놓는 기호.
enum WindowSeparator: String, CaseIterable, PrefValue {
    case dot, slash, bar, space

    var mark: String? {
        switch self {
        case .dot: return "·"
        case .slash: return "/"
        case .bar: return "|"
        case .space: return nil
        }
    }

    var title: String {
        switch self {
        case .dot: return "Dot (·)"
        case .slash: return "Slash (/)"
        case .bar: return "Bar (|)"
        case .space: return "Space"
        }
    }
}

/// 메뉴바에 단계 색을 입힐지.
enum MenuBarColor: String, CaseIterable, PrefValue {
    case monochrome, whenLow, always

    var title: String {
        switch self {
        case .monochrome: return "Match Menu Bar"
        case .whenLow: return "Color When Running Low"
        case .always: return "Always Color by Level"
        }
    }
}

enum FontWeight: String, CaseIterable, PrefValue {
    case light, regular, medium, semibold, bold

    var title: String { rawValue.capitalized }

    var nsWeight: NSFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }
}

enum OverlayBackground: String, CaseIterable, PrefValue {
    case liquidGlass, ultraThin, thin, regular, thick, solid

    /// 이 Mac 에서 고를 수 있는 바탕. Liquid Glass 는 macOS 26 이상, 26 SDK 로 빌드한 앱에서만 그려진다.
    static var choices: [OverlayBackground] {
        drawsLiquidGlass ? allCases : allCases.filter { $0 != .liquidGlass }
    }

    var title: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .ultraThin: return "Clear Glass"
        case .thin: return "Light Glass"
        case .regular: return "Glass"
        case .thick: return "Frosted Glass"
        case .solid: return "Solid"
        }
    }

    /// 머티리얼로 칠하는 바탕. Liquid Glass 를 그릴 수 없는 Mac 에서는 가장 맑은 머티리얼로 대신한다.
    var style: AnyShapeStyle {
        switch self {
        case .liquidGlass, .ultraThin: return AnyShapeStyle(.ultraThinMaterial)
        case .thin: return AnyShapeStyle(.thinMaterial)
        case .regular: return AnyShapeStyle(.regularMaterial)
        case .thick: return AnyShapeStyle(.thickMaterial)
        case .solid: return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
    }
}

/// 남은 양으로 가르는 세 단계. 경계와 색은 설정에서 고른다.
enum Level { case high, mid, low }

/// 설정에 담는 색. sRGB 로 "#RRGGBBAA" 꼴로 저장한다.
struct RGBA: Equatable, PrefValue {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let color = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: color.redComponent, green: color.greenComponent,
                  blue: color.blueComponent, alpha: color.alphaComponent)
    }

    init?(stored: Any) {
        guard let hex = stored as? String, hex.hasPrefix("#"), hex.count == 9,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        func channel(_ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        self.init(red: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }

    var stored: Any {
        let channels = [red, green, blue, alpha].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

/// 공급자 로고 색. 글자색을 그대로 따를 수도 있다.
enum Tint: Equatable, PrefValue {
    case text
    case custom(RGBA)

    init?(stored: Any) {
        guard let value = stored as? String else { return nil }
        if value.isEmpty {
            self = .text
        } else if let color = RGBA(stored: value) {
            self = .custom(color)
        } else {
            return nil
        }
    }

    var stored: Any {
        if case .custom(let color) = self { return color.stored }
        return ""
    }

    var color: Color {
        if case .custom(let color) = self { return color.color }
        return .primary
    }
}
