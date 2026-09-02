import Foundation

/// `codex app-server` 에 붙어 `account/rateLimits/read` 를 부른다.
///
/// Codex CLI에는 사용량만 찍는 서브커맨드가 없지만, TUI가 쓰는 stdio JSON-RPC 서버는
/// 직접 띄울 수 있다. 웹에서 받던 것과 같은 값을 구조화된 JSON으로 준다.
///
/// 프로토콜상 `initialize` → `initialized` 를 먼저 보내야 하고, 응답이 올 때까지
/// stdin을 열어 둬야 한다. 닫으면 서버가 대답하기 전에 먼저 끝난다.
enum CodexReader {
    /// 응답을 골라내는 표식. 알림이 섞여 들어오므로 id로 구분한다.
    private static let requestID = 1

    private struct Envelope: Decodable {
        struct Result: Decodable { let rateLimits: Limits? }
        struct Limits: Decodable {
            let primary: Window?
            let secondary: Window?
            let planType: String?
        }
        /// 한도 창 하나. `primary` / `secondary` 라는 이름은 창 길이를 뜻하지 않아서
        /// 라벨은 반드시 `windowDurationMins` 로만 정한다.
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Double?
            let resetsAt: Double?
        }
        struct Failure: Decodable { let message: String? }

        let result: Result?
        let error: Failure?
    }

    static func read() -> ProviderUsage {
        guard let codex = CommandRunner.executable("codex") else {
            return empty(note: "codex CLI not found")
        }
        let request = [
            #"{"id":0,"method":"initialize","params":{"clientInfo":{"name":"usage-overlay","version":"1.0.0"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":\#(requestID),"method":"account/rateLimits/read"}"#,
        ]
        guard let line = CommandRunner.run(codex, ["app-server"], stdin: request, timeout: 30,
                                           until: { $0.contains("\"id\":\(requestID)") }),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(line.utf8))
        else {
            return empty(note: "codex app-server didn't answer")
        }
        guard let limits = envelope.result?.rateLimits else {
            return empty(note: envelope.error?.message ?? "No limits reported — run codex login")
        }

        let gauges = [("primary", limits.primary), ("secondary", limits.secondary)]
            .compactMap { name, window in window.map { gauge(name: name, $0) } }
            .sorted { ($0.windowMinutes ?? .greatestFiniteMagnitude) < ($1.windowMinutes ?? .greatestFiniteMagnitude) }

        return ProviderUsage(name: "Codex",
                             gauges: gauges,
                             plan: plan(limits.planType),
                             updatedAt: Date(),
                             note: gauges.isEmpty ? "No limits reported" : nil)
    }

    private static func empty(note: String) -> ProviderUsage {
        ProviderUsage(name: "Codex", gauges: [], plan: nil, updatedAt: nil, note: note)
    }

    private static func gauge(name: String, _ window: Envelope.Window) -> Gauge {
        Gauge(id: name,
              label: window.windowDurationMins.map(Gauge.label(forMinutes:)) ?? name.capitalized,
              percent: min(max(window.usedPercent, 0), 100),
              resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0) },
              windowMinutes: window.windowDurationMins)
    }

    private static func plan(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw == "prolite" ? "Pro Lite" : raw.capitalized
    }
}
