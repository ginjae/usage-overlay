import Foundation

/// 하나의 사용량 한도 창(5시간 / 주간 등).
struct Gauge: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Double
    var resetsAt: Date?
    /// 한도 창의 길이(분). 정렬에만 쓰며 모를 수 있다.
    var windowMinutes: Double?

    /// 창 길이(분)로 정하는 표시 이름. 응답마다 창 이름이 달라 길이만 믿는다.
    static func label(forMinutes minutes: Double) -> String {
        switch Int(minutes) {
        case 300: return "5-hour"
        case 1440: return "Daily"
        case 10080: return "Weekly"
        case 43200: return "Monthly"
        case let m where m >= 1440: return "\(m / 1440)d"
        case let m where m >= 60: return "\(m / 60)h"
        default: return "\(Int(minutes))m"
        }
    }

    /// 창 시간 가운데 지난 몫(0...1). 리셋 시각이나 창 길이를 모르면 낼 수 없다.
    func elapsedFraction(at now: Date) -> Double? {
        guard let resetsAt, let windowMinutes, windowMinutes > 0 else { return nil }
        let left = resetsAt.timeIntervalSince(now) / (windowMinutes * 60)
        return min(max(1 - left, 0), 1)
    }

    /// 지금 속도를 그대로 이어 가면 어떻게 되는지. 창 초반에는 표본이 적어 들쭉날쭉하므로 조금 지난 뒤부터 낸다.
    func pace(at now: Date) -> Pace? {
        guard let resetsAt, let windowMinutes, let elapsed = elapsedFraction(at: now),
              elapsed >= 0.05, elapsed < 1 else { return nil }
        guard percent < 100 else { return .runsOut(at: now) }
        guard percent > 0 else { return .lasts(usedAtReset: 0) }
        // 쓴 양을 지난 시간으로 나눈 속도로 남은 양을 다 쓰는 데 걸리는 시간.
        let secondsToEmpty = (100 - percent) / (percent / (elapsed * windowMinutes * 60))
        let empty = now.addingTimeInterval(secondsToEmpty)
        return empty < resetsAt ? .runsOut(at: empty) : .lasts(usedAtReset: min(100, percent / elapsed))
    }

    /// 메뉴바용 짧은 라벨. 폭이 곧 다른 앱의 자리라 창 길이만 남긴다. "5-hour" → "5h".
    var shortLabel: String {
        switch label {
        case "5-hour": return "5h"
        case "Daily": return "1d"
        case "Weekly": return "7d"
        case "Monthly": return "30d"
        default: return label
        }
    }
}

enum Pace: Equatable {
    /// 리셋 전에 한도를 다 쓴다.
    case runsOut(at: Date)
    /// 리셋까지 버틴다. 그때까지 쓸 양(%).
    case lasts(usedAtReset: Double)
}

/// 한 공급자(Claude / Codex)의 사용량 스냅샷.
struct ProviderUsage: Equatable {
    var name: String
    var gauges: [Gauge]
    var plan: String?
    /// 값을 받아 온 시각. CLI가 대답을 못 하면 직전 값이 남으므로 나이를 표시한다.
    var updatedAt: Date?
    var note: String?

    /// 가장 빡빡한 창의 남은 비율. 화면에는 사용량이 아니라 남은 양을 보여 준다.
    var lowestRemaining: Double? { gauges.map { 100 - $0.percent }.min() }
}

struct Snapshot: Equatable {
    var claude: ProviderUsage?
    var codex: ProviderUsage?

    /// 숫자가 하나라도 있는지. 첫 조회가 끝나기 전에는 없다.
    var hasGauges: Bool { [claude, codex].contains { $0?.gauges.isEmpty == false } }
}

enum Format {
    /// 남은 시간을 "3d 4h" / "1h 20m" / "45m" 형태로. `units` 가 1 이면 큰 단위 하나만 "3d" / "1h".
    static func remaining(until date: Date?, from now: Date, units: Int = 2) -> String {
        guard let date else { return "—" }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "soon" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return units > 1 && h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return units > 1 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// 리셋 시각은 남은 기간과 관계없이 항상 요일과 시간으로 표시한다.
    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// 보여 주는 값 가운데 가장 오래된 것의 나이. 늘 떠 있는 자리라 조용하면 멈춘 건지 최신인 건지 알 수 없다.
    static func freshness(of usages: [ProviderUsage], from now: Date) -> String {
        guard !usages.isEmpty else { return "Loading…" }
        guard let oldest = usages.compactMap(\.updatedAt).min() else { return "Updated —" }
        return "Updated " + since(oldest, from: now)
    }

    /// 마지막 갱신 시점을 "just now" / "3m ago" 형태로. 늘 떠 있는 자리라 초 단위로 떨지 않게 한다.
    static func since(_ date: Date, from now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }

    /// 갱신이 늦어졌을 때만 알리는 판. 툴팁처럼 평소엔 조용해야 하는 자리에 쓴다.
    static func age(_ date: Date?, from now: Date) -> String? {
        guard let date else { return nil }
        let s = Int(now.timeIntervalSince(date))
        if s < 90 { return nil }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
