import Foundation

/// Claude Code가 `~/.claude.json` 에 캐싱해 두는 사용량(`/usage` 와 같은 값)을 읽는다.
/// 크롬 경로가 막혔을 때의 폴백이라 값이 낡아 있을 수 있다.
enum ClaudeReader {
    static let configURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")

    static func read() -> ProviderUsage? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }  // CLI가 쓰는 중이면 부분 읽기로 실패할 수 있다 → 직전 값 유지

        let plan = planName(root)
        guard let cached = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] else {
            return ProviderUsage(name: "Claude", gauges: [], plan: plan, updatedAt: nil,
                                 note: "No cached usage — run Claude Code once")
        }

        // 웹 응답과 같은 모양이라 스캐너가 그대로 처리한다.
        let gauges = UsageScan.normalize(UsageScan.scan(utilization))
        return ProviderUsage(name: "Claude",
                             gauges: gauges,
                             plan: plan,
                             updatedAt: Parse.double(cached["fetchedAtMs"]).map { Date(timeIntervalSince1970: $0 / 1000) },
                             note: gauges.isEmpty ? "No limits reported" : nil)
    }

    private static func planName(_ root: [String: Any]) -> String? {
        guard let account = root["oauthAccount"] as? [String: Any],
              let type = account["organizationType"] as? String else { return nil }
        switch type {
        case "claude_pro": return "Pro"
        case "claude_max": return "Max"
        case "claude_team": return "Team"
        case "claude_enterprise": return "Enterprise"
        default: return type.replacingOccurrences(of: "claude_", with: "").capitalized
        }
    }
}
