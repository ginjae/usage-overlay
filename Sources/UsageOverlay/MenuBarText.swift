import AppKit

/// 앞 조각과 어떻게 이어지는지. 메뉴바는 폭이 좁아 구분을 여백과 구분 기호로만 준다.
enum MenuBarSeam {
    /// 다른 공급자 — 여백을 넓게 둔다.
    case provider
    /// 같은 공급자의 다음 창 — 구분 기호로 묶는다.
    case window
    /// 같은 공급자지만 기호를 못 쓰는 경우. 조각 안에 이미 가운뎃점이 있으면 두 겹이 되어 뜻이 흐려진다.
    case plain
}

/// 메뉴바에 그릴 한 덩어리. 아이콘은 공급자마다 한 번만 붙으므로 없을 수 있다.
struct MenuBarPart {
    let icon: NSImage?
    let text: String
    /// 첫 조각에서는 쓰이지 않는다.
    var seam: MenuBarSeam = .provider
    /// 아이콘에 겹쳐 그리는 리셋 시계. 아이콘이 없으면 쓰이지 않는다.
    var clock: LogoClock?
    /// 단계 색을 입힐 때만 있다. 없으면 메뉴바 글자색을 따른다.
    var level: Level?
}

/// 이미지를 다시 합성할지 판단하려고 비교한다.
/// NSImage 는 실체가 두 개뿐(Icons.claude / Icons.codex)이라 내용 비교 대신 동일성으로 충분하다.
extension MenuBarPart: Equatable {
    static func == (a: MenuBarPart, b: MenuBarPart) -> Bool {
        a.icon === b.icon && a.text == b.text && a.seam == b.seam && a.clock == b.clock && a.level == b.level
    }
}

/// 로고를 시계판 삼아 리셋까지의 시간을 그린다. 바늘은 창이 지나는 대로 12시에서 시계 방향으로 돈다.
struct LogoClock: Equatable {
    enum Face {
        /// 로고 자체가 시계판. 칠할 쪽의 부채꼴만 진하게 남긴다. 폭이 늘지 않는다.
        case sweep
        /// 로고를 줄이고 둘레에 고리를 두른다. 어느 로고든 몇 시인지 또렷하다.
        case ring
    }

    let face: Face
    /// 창 시간 가운데 지난 몫(0...1). 곧 바늘의 자리.
    let elapsed: Double
    /// 바늘 뒤(남은 시간)를 칠할지, 앞(지난 시간)을 칠할지.
    let litRemaining: Bool

    /// 칠할 구간. 한 바퀴를 0...1 로 잰다.
    var lit: (from: Double, to: Double) { litRemaining ? (elapsed, 1) : (0, elapsed) }
}

/// 스냅샷을 메뉴바 조각과 툴팁으로 옮긴다. 무엇을 어떻게 붙일지는 설정의 메뉴바 쪽이 정한다.
enum MenuBarText {
    private static var settings: Settings { .shared }

    static func parts(for snapshot: Snapshot, now: Date) -> [MenuBarPart] {
        let parts = settings.providerOrder.providers
            .filter { settings[keyPath: $0.menuBarShown] }
            .flatMap { provider($0, usage: $0.usage(in: snapshot), now: now) }
        // 둘 다 끄면 아무것도 안 그려져 상세 창을 열 수 없다. 최소한의 손잡이는 남긴다.
        return parts.isEmpty ? [MenuBarPart(icon: nil, text: "Usage")] : parts
    }

    /// 메뉴바에 다 못 담는 값을 마우스를 올렸을 때 전부 보여 준다. 여기서는 메뉴바 설정과 무관하게 항상 전체를.
    static func tooltip(for snapshot: Snapshot, now: Date) -> String? {
        let blocks = settings.providerOrder.providers.compactMap { $0.usage(in: snapshot) }.map { usage in
            ([header(usage, now: now)] + rows(usage, now: now)).joined(separator: "\n")
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }

    private static func provider(_ provider: Provider, usage: ProviderUsage?, now: Date) -> [MenuBarPart] {
        let face = settings.menuBarReset.face
        let badge: NSImage? = settings.menuBarIcon || face != nil ? provider.icon : nil
        let gauges = usage.map { settings[keyPath: provider.menuBarWindow].pick(from: $0.gauges) } ?? []
        guard !gauges.isEmpty else { return [MenuBarPart(icon: badge, text: "–")] }
        // 리셋 시각을 글자로 붙이면 조각 안이 이미 "39% · 2h 10m" 이라 가운뎃점을 또 찍지 않는다.
        let joint: MenuBarSeam = settings.menuBarReset == .countdown && settings.menuBarSeparator == .dot
            ? .plain : .window
        return gauges.enumerated().map { index, gauge in
            // 창을 여러 개 보여 줄 때 같은 아이콘이 반복되면 지저분하다. 공급자당 한 번만 붙인다.
            // 시계도 그 로고에 하나뿐이라 바로 옆 첫 창의 시간을 그린다.
            MenuBarPart(icon: index == 0 ? badge : nil,
                        text: text(for: gauge, now: now),
                        seam: index == 0 ? .provider : joint,
                        clock: index == 0 ? clock(face, for: gauge, now: now) : nil,
                        level: level(of: gauge))
        }
    }

    private static func text(for gauge: Gauge, now: Date) -> String {
        let percent = Int(settings.menuBarValue.percent(of: gauge).rounded())
        var text = settings.menuBarPercentSign ? "\(percent)%" : "\(percent)"
        if let label = settings.menuBarLabel.text(for: gauge) { text = "\(label) " + text }
        if settings.menuBarReset == .countdown, gauge.resetsAt != nil {
            text += " · " + Format.remaining(until: gauge.resetsAt, from: now, units: settings.menuBarCountdownUnits)
        }
        return text
    }

    /// 퍼센트와 같은 쪽을 칠해야 둘을 나란히 놓고 견줄 수 있다.
    /// 남은 양 39% 옆 로고가 절반 켜져 있으면 시간보다 한도가 빨리 줄고 있다는 뜻이다.
    private static func clock(_ face: LogoClock.Face?, for gauge: Gauge, now: Date) -> LogoClock? {
        guard let face, let elapsed = gauge.elapsedFraction(at: now) else { return nil }
        let litRemaining: Bool
        switch settings.menuBarClockFill {
        case .matchPercent: litRemaining = settings.menuBarValue == .remaining
        case .timeLeft: litRemaining = true
        case .timeGone: litRemaining = false
        }
        return LogoClock(face: face, elapsed: elapsed, litRemaining: litRemaining)
    }

    private static func level(of gauge: Gauge) -> Level? {
        let level = settings.level(remaining: max(0, 100 - gauge.percent))
        switch settings.menuBarColor {
        case .monochrome: return nil
        case .whenLow: return level == .high ? nil : level
        case .always: return level
        }
    }

    private static func header(_ usage: ProviderUsage, now: Date) -> String {
        var header = usage.name
        if let plan = usage.plan { header += " · \(plan)" }
        if let age = Format.age(usage.updatedAt, from: now) { header += " · \(age)" }
        return header
    }

    private static func rows(_ usage: ProviderUsage, now: Date) -> [String] {
        let note = usage.note.map { ["  " + $0] } ?? []
        guard !usage.gauges.isEmpty else { return note.isEmpty ? ["  No data yet"] : note }
        return note + usage.gauges.map { gauge in
            var row = "  \(gauge.label) · \(Int(max(0, 100 - gauge.percent).rounded()))% left"
            let reset = Format.remaining(until: gauge.resetsAt, from: now)
            if gauge.resetsAt != nil {
                row += reset == "soon" ? " · resetting now" : " · resets in \(reset)"
            }
            return row
        }
    }
}
