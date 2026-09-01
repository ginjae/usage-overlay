import AppKit

/// 메뉴바에 그릴 한 덩어리. 아이콘은 공급자마다 한 번만 붙으므로 없을 수 있다.
struct MenuBarPart {
    let icon: NSImage?
    let text: String
}

/// 이미지를 다시 합성할지 판단하려고 비교한다.
/// NSImage 는 실체가 두 개뿐(Icons.claude / Icons.codex)이라 내용 비교 대신 동일성으로 충분하다.
extension MenuBarPart: Equatable {
    static func == (a: MenuBarPart, b: MenuBarPart) -> Bool { a.icon === b.icon && a.text == b.text }
}

/// 메뉴바에 어떤 한도 창을 보여 줄지.
enum MenuBarWindow: String, CaseIterable {
    case tightest, fiveHour, weekly, all

    var title: String {
        switch self {
        case .tightest: return "Tightest Window"
        case .fiveHour: return "5-hour Window"
        case .weekly: return "Weekly Window"
        case .all: return "All Windows"
        }
    }

    /// 이 설정이 고르는 게이지들. 고른 창이 그 공급자에 없으면 가장 빡빡한 창으로 떨어진다.
    /// 메뉴바가 비어 버리는 것보다 다른 창이라도 보여 주는 편이 낫다.
    func pick(from gauges: [Gauge]) -> [Gauge] {
        switch self {
        case .all:
            return gauges
        case .tightest:
            return [tightest(gauges)].compactMap { $0 }
        case .fiveHour, .weekly:
            let wanted = self == .fiveHour ? "5-hour" : "Weekly"
            return [gauges.first { $0.label == wanted } ?? tightest(gauges)].compactMap { $0 }
        }
    }

    /// 남은 양이 가장 적은 창 = 사용률이 가장 높은 창.
    private func tightest(_ gauges: [Gauge]) -> Gauge? {
        gauges.max { $0.percent < $1.percent }
    }
}

/// 퍼센트를 남은 양으로 볼지 쓴 양으로 볼지.
enum MenuBarValue: String, CaseIterable {
    case remaining, used

    var title: String { self == .remaining ? "Percent Left" : "Percent Used" }

    func percent(of gauge: Gauge) -> Double {
        self == .remaining ? max(0, 100 - gauge.percent) : gauge.percent
    }
}

/// 스냅샷을 메뉴바 글자와 툴팁으로 옮긴다. 설정을 읽는 곳을 여기 한 군데로 모아 둔다.
enum MenuBarText {
    static func parts(for snapshot: Snapshot, now: Date) -> [MenuBarPart] {
        var parts: [MenuBarPart] = []
        if Prefs.menuBarClaude { parts += provider(snapshot.claude, icon: Icons.claude, now: now) }
        if Prefs.menuBarCodex { parts += provider(snapshot.codex, icon: Icons.codex, now: now) }
        // 둘 다 끄면 아무것도 안 그려져 메뉴를 다시 열 수 없다. 최소한의 손잡이는 남긴다.
        return parts.isEmpty ? [MenuBarPart(icon: nil, text: "Usage")] : parts
    }

    /// 메뉴바에 다 못 담는 값은 툴팁에서 전부 보여 준다. 여기서는 설정과 무관하게 항상 전체를.
    static func tooltip(for snapshot: Snapshot, now: Date) -> String? {
        let blocks = [snapshot.claude, snapshot.codex].compactMap { $0 }.map { usage in
            ([header(usage, now: now)] + rows(usage, now: now)).joined(separator: "\n")
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n")
    }

    private static func provider(_ usage: ProviderUsage?, icon: NSImage, now: Date) -> [MenuBarPart] {
        let badge: NSImage? = Prefs.menuBarIcon ? icon : nil
        let gauges = usage.map { Prefs.menuBarWindow.pick(from: $0.gauges) } ?? []
        guard !gauges.isEmpty else { return [MenuBarPart(icon: badge, text: "–")] }
        return gauges.enumerated().map { index, gauge in
            // 창을 여러 개 보여 줄 때 같은 아이콘이 반복되면 지저분하다. 공급자당 한 번만 붙인다.
            MenuBarPart(icon: index == 0 ? badge : nil, text: text(for: gauge, now: now))
        }
    }

    private static func text(for gauge: Gauge, now: Date) -> String {
        var text = "\(Int(Prefs.menuBarValue.percent(of: gauge).rounded()))%"
        if Prefs.menuBarLabel { text = "\(gauge.shortLabel) " + text }
        if Prefs.menuBarReset, gauge.resetsAt != nil {
            text += " · " + Format.remaining(until: gauge.resetsAt, from: now)
        }
        return text
    }

    private static func header(_ usage: ProviderUsage, now: Date) -> String {
        var header = usage.name
        if let plan = usage.plan { header += " · \(plan)" }
        header += " · \(usage.source.rawValue)"
        if let age = Format.age(usage.updatedAt, from: now) { header += " · \(age)" }
        return header
    }

    private static func rows(_ usage: ProviderUsage, now: Date) -> [String] {
        guard !usage.gauges.isEmpty else { return ["  " + (usage.note ?? "No data yet")] }
        return usage.gauges.map { gauge in
            var row = "  \(gauge.label) · \(Int(max(0, 100 - gauge.percent).rounded()))% left"
            let reset = Format.remaining(until: gauge.resetsAt, from: now)
            if gauge.resetsAt != nil {
                row += reset == "soon" ? " · resetting now" : " · resets in \(reset)"
            }
            return row
        }
    }
}
