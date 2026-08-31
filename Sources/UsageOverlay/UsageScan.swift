import Foundation

/// 임의의 JSON 안에서 "사용량 게이지처럼 생긴" 객체를 찾아낸다.
///
/// 네 군데에서 오는 응답의 필드 이름이 제각각이라 경로를 고정하지 않고 재귀로 훑는다.
///   claude.ai `/api/organizations/{uuid}/usage` : `five_hour.utilization`, `limits[].kind/percent`
///   `~/.claude.json`                            : 위와 같은 모양
///   chatgpt.com `/backend-api/codex/usage`      : `rate_limit.primary_window.used_percent` +
///                                                 `limit_window_seconds`, `reset_at`
///   Codex 롤아웃 JSONL                           : `rate_limits.primary.used_percent` +
///                                                 `window_minutes`, `resets_at`
enum UsageScan {
    /// 알려진 키 → (표시 이름, 정렬용 창 길이(분))
    private static let keyLabels: [String: (String, Double?)] = [
        "five_hour": ("5-hour", 300),
        "session": ("5-hour", 300),
        "seven_day": ("Weekly", 10080),
        "weekly_all": ("Weekly", 10080),
        "seven_day_opus": ("Opus", 10080),
        "weekly_opus": ("Opus", 10080),
        "seven_day_sonnet": ("Sonnet", 10080),
        "weekly_sonnet": ("Sonnet", 10080),
        "primary": ("Weekly", nil),
        "secondary": ("5-hour", nil),
        "primary_window": ("Weekly", nil),
        "secondary_window": ("5-hour", nil),
    ]

    /// 들어가지 않을 가지. 모델별 부가 한도나 크레딧까지 게이지로 잡히면 오버레이가 지저분해진다.
    private static let skipKeys: Set<String> = [
        "additional_rate_limits", "code_review_rate_limit",
        "credits", "extra_usage", "spend",
    ]

    static func scan(_ value: Any?, key: String? = nil, depth: Int = 0) -> [Gauge] {
        guard depth < 8 else { return [] }
        if let array = value as? [Any] {
            return array.flatMap { scan($0, key: key, depth: depth + 1) }
        }
        guard let dict = value as? [String: Any] else { return [] }

        var found: [Gauge] = []
        if let gauge = gauge(from: dict, key: key) { found.append(gauge) }
        for (childKey, child) in dict where !skipKeys.contains(childKey) {
            guard child is [String: Any] || child is [Any] else { continue }
            found.append(contentsOf: scan(child, key: childKey, depth: depth + 1))
        }
        return found
    }

    /// 라벨이 같은 게이지는 먼저 나온 것만 남기고, 창이 짧은 순(5시간 → 주간)으로 정렬.
    static func normalize(_ gauges: [Gauge]) -> [Gauge] {
        var seen = Set<String>()
        let unique = gauges.filter { seen.insert($0.label).inserted }
        return unique.sorted {
            ($0.windowMinutes ?? .greatestFiniteMagnitude) < ($1.windowMinutes ?? .greatestFiniteMagnitude)
        }
    }

    /// 응답 어딘가에 있는 `plan_type` (Codex 쪽에만 있다).
    static func plan(in value: Any?, depth: Int = 0) -> String? {
        guard depth < 6 else { return nil }
        if let array = value as? [Any] {
            return array.lazy.compactMap { plan(in: $0, depth: depth + 1) }.first
        }
        guard let dict = value as? [String: Any] else { return nil }
        if let raw = dict["plan_type"] as? String, !raw.isEmpty {
            return raw == "prolite" ? "Pro Lite" : raw.capitalized
        }
        for (_, child) in dict {
            if let found = plan(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func gauge(from dict: [String: Any], key: String?) -> Gauge? {
        let kind = dict["kind"] as? String
        let percent: Double
        if let value = Parse.double(dict["used_percent"]) {
            percent = value                                   // Codex (웹/CLI 공통)
        } else if kind != nil, let value = Parse.double(dict["percent"]) {
            percent = value                                   // Claude limits[]
        } else if let key, keyLabels[key] != nil, let value = Parse.double(dict["utilization"]) {
            percent = value                                   // Claude 이름 있는 창
        } else {
            return nil
        }
        guard percent.isFinite, (0...100).contains(percent) else { return nil }

        let minutes = Parse.double(dict["window_minutes"])
            ?? Parse.double(dict["limit_window_seconds"]).map { $0 / 60 }
        let resetsAt = Parse.date(dict["resets_at"])
            ?? Parse.date(dict["reset_at"])
            ?? (Parse.double(dict["resets_in_seconds"]) ?? Parse.double(dict["reset_after_seconds"]))
                .map { Date().addingTimeInterval($0) }
        let name = kind ?? key ?? "limit"

        return Gauge(id: name,
                     label: minutes.map(label(forMinutes:)) ?? keyLabels[name]?.0 ?? prettify(name),
                     percent: percent,
                     resetsAt: resetsAt,
                     windowMinutes: minutes ?? keyLabels[name]?.1)
    }

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

    private static func prettify(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
