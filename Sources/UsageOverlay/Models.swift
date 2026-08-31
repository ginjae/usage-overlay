import Foundation

/// 하나의 사용량 한도 창(5시간 / 주간 등).
struct Gauge: Identifiable, Equatable {
    let id: String
    let label: String
    let percent: Double
    let resetsAt: Date?
    /// 한도 창의 길이(분). 정렬에만 쓰며 모를 수 있다.
    var windowMinutes: Double?
}

/// 한 공급자(Claude / Codex)의 사용량 스냅샷.
/// 값을 어디서 가져왔는지. 신선도와 신뢰도가 달라 UI에 표시한다.
enum UsageSource: String, Equatable {
    case browser = "Web"
    case localCache = "Local"
}

struct ProviderUsage: Equatable {
    var name: String
    var gauges: [Gauge]
    var plan: String?
    var source: UsageSource = .localCache
    /// 원본 데이터가 마지막으로 갱신된 시각. CLI가 떠 있지 않으면 오래된 값일 수 있다.
    var updatedAt: Date?
    var note: String?

    /// 가장 빡빡한 창의 남은 비율. 화면에는 사용량이 아니라 남은 양을 보여 준다.
    var lowestRemaining: Double? { gauges.map { 100 - $0.percent }.min() }
}

struct Snapshot: Equatable {
    var claude: ProviderUsage?
    var codex: ProviderUsage?
}

enum Parse {
    /// ISO8601 문자열(소수점 6자리 포함) 또는 epoch 초를 Date로.
    static func date(_ any: Any?) -> Date? {
        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard var s = any as? String, !s.isEmpty else { return nil }
        // "…:00.208150+00:00" 의 소수부를 떼어낸다. ISO8601DateFormatter가 6자리를 못 읽는다.
        if let dot = s.firstIndex(of: "."),
           let end = s[s.index(after: dot)...].firstIndex(where: { !$0.isNumber }) {
            s.removeSubrange(dot..<end)
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func double(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
}

enum Format {
    /// 남은 시간을 "3d 4h" / "1h 20m" / "45m" 형태로.
    static func remaining(until date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "soon" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// 마지막 갱신 시점을 "3m ago" 형태로.
    static func age(_ date: Date?, from now: Date) -> String? {
        guard let date else { return nil }
        let s = Int(now.timeIntervalSince(date))
        if s < 90 { return nil }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
