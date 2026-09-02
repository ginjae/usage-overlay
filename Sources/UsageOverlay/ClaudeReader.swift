import Foundation

/// `claude -p "/usage"` 의 출력을 읽는다.
///
/// `/usage` 는 API 요청이 아니라 CLI 안의 내장 명령이라 토큰도 할당량도 쓰지 않는다.
/// (`--output-format json` 으로 보면 `num_turns: 0`, `total_cost_usd: 0`)
/// 대신 결과가 사람이 읽으라고 만든 문장이라 그 형식을 여기서 파싱한다.
///
///     You are currently using your subscription to power your Claude Code usage
///
///     Current session: 46% used · resets Sep 2 at 1:09pm (Asia/Seoul)
///     Current week (all models): 5% used · resets Sep 3 at 4:59pm (Asia/Seoul)
enum ClaudeReader {
    /// 요금제는 사용량과 달리 거의 안 바뀐다. 한 번만 물어보고 들고 있는다.
    private static var cachedPlan: String?

    static func read() -> ProviderUsage {
        guard let claude = CommandRunner.executable("claude") else {
            return empty(note: "claude CLI not found")
        }
        // 세션 id를 직접 정해 두면 이 호출이 남긴 기록만 정확히 골라 지울 수 있다.
        let session = UUID().uuidString.lowercased()
        defer { removeTranscript(session) }
        guard let output = CommandRunner.run(claude, ["-p", "/usage", "--session-id", session],
                                             timeout: 30) else {
            return empty(note: "claude didn't answer")
        }
        let gauges = gauges(from: output)
        guard !gauges.isEmpty else { return empty(note: note(from: output)) }

        return ProviderUsage(name: "Claude",
                             gauges: gauges,
                             plan: plan(claude),
                             updatedAt: Date(),
                             note: nil)
    }

    private static func empty(note: String) -> ProviderUsage {
        ProviderUsage(name: "Claude", gauges: [], plan: cachedPlan, updatedAt: nil, note: note)
    }

    /// `claude -p` 는 부를 때마다 세션 기록을 하나 남긴다. 1분마다 갱신하면 하루 1400개다.
    /// 우리가 넘긴 uuid가 곧 파일 이름이라, 방금 만든 그 파일만 지운다. 남의 기록은 건드리지 않는다.
    private static func removeTranscript(_ session: String) {
        let manager = FileManager.default
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let file = "\(session).jsonl"
        // 홈에서 돌리므로 디렉터리 이름은 "-Users-이름" 이 된다.
        // 이 규칙은 CLI 쪽 사정이라 바뀔 수 있어, 못 찾으면 프로젝트 폴더를 한 겹 더 훑는다.
        let expected = projects
            .appendingPathComponent(NSHomeDirectory().replacingOccurrences(of: "/", with: "-"))
            .appendingPathComponent(file)
        var candidates = [expected]
        candidates += ((try? manager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent(file) }
        guard let found = candidates.first(where: { manager.fileExists(atPath: $0.path) }) else { return }
        try? manager.removeItem(at: found)
    }

    // MARK: - 파싱

    private static func gauges(from output: String) -> [Gauge] {
        let gauges = output.split(separator: "\n").compactMap { gauge(from: String($0)) }
        return gauges.sorted {
            ($0.windowMinutes ?? .greatestFiniteMagnitude) < ($1.windowMinutes ?? .greatestFiniteMagnitude)
        }
    }

    /// "Current session: 46% used · resets Sep 2 at 1:09pm (Asia/Seoul)" 한 줄에서 게이지 하나.
    private static func gauge(from line: String) -> Gauge? {
        let line = line.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("Current "), let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: "Current ".count)..<colon])
        let rest = String(line[line.index(after: colon)...])
        guard let percent = percent(in: rest) else { return nil }

        let window = window(for: name)
        return Gauge(id: name,
                     label: window.label,
                     percent: percent,
                     resetsAt: resetDate(in: rest),
                     windowMinutes: window.minutes)
    }

    /// 창 이름이 곧 창 길이다. "session" 은 5시간, "week …" 은 주간.
    private static func window(for name: String) -> (label: String, minutes: Double?) {
        let name = name.lowercased()
        if name.contains("session") { return ("5-hour", 300) }
        if name.contains("week") {
            // 요금제에 따라 "week (all models)" 외에 모델별 주간 창이 따로 나온다.
            if name.contains("opus") { return ("Opus", 10080) }
            if name.contains("sonnet") { return ("Sonnet", 10080) }
            return ("Weekly", 10080)
        }
        return (name.capitalized, nil)
    }

    /// "46% used" 의 숫자.
    private static func percent(in text: String) -> Double? {
        guard let percentSign = text.firstIndex(of: "%") else { return nil }
        let digits = text[..<percentSign].reversed().prefix { $0.isNumber || $0 == "." }
        guard let value = Double(String(digits.reversed())), (0...100).contains(value) else { return nil }
        return value
    }

    /// "resets Sep 2 at 1:09pm (Asia/Seoul)" → Date.
    ///
    /// 연도가 없어서 올해·내년·작년 중 지금과 가장 가까운 쪽을 고른다(연말에 해가 넘어가는 경우).
    /// 형식이 바뀌면 리셋 시각만 "—" 로 비고 퍼센트는 그대로 나온다.
    private static func resetDate(in text: String) -> Date? {
        guard let marker = text.range(of: "resets ") else { return nil }
        var stamp = String(text[marker.upperBound...]).trimmingCharacters(in: .whitespaces)

        // 표준 시간대가 괄호로 따라온다. 없으면 이 맥의 시간대로 읽는다.
        var zone = TimeZone.current
        if let open = stamp.lastIndex(of: "("), let close = stamp.lastIndex(of: ")"), open < close {
            zone = TimeZone(identifier: String(stamp[stamp.index(after: open)..<close])) ?? zone
            stamp = String(stamp[..<open]).trimmingCharacters(in: .whitespaces)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.amSymbol = "am"  // CLI는 소문자로 쓴다
        formatter.pmSymbol = "pm"
        formatter.dateFormat = "MMM d 'at' h:mma yyyy"

        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let year = calendar.component(.year, from: now)
        return [year, year + 1, year - 1]
            .compactMap { formatter.date(from: "\(stamp) \($0)") }
            .min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
    }

    /// 사용량 줄이 없을 때 무슨 일인지 알려 준다. 로그인이 안 됐거나 API 키를 쓰는 경우 등.
    private static func note(from output: String) -> String {
        let first = output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("Total ") && !$0.hasPrefix("Usage:") }
        guard let first, !first.isEmpty else { return "No limits in /usage output" }
        return first.count > 70 ? String(first.prefix(69)) + "…" : first
    }

    // MARK: - 요금제

    /// `claude auth status` 가 JSON으로 알려 준다. `/usage` 출력에는 요금제 이름이 없다.
    private static func plan(_ claude: URL) -> String? {
        if let cachedPlan { return cachedPlan }
        guard let output = CommandRunner.run(claude, ["auth", "status"], timeout: 15),
              let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["subscriptionType"] as? String, !type.isEmpty else { return nil }
        cachedPlan = type.capitalized
        return cachedPlan
    }
}
