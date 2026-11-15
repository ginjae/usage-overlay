import Combine
import Foundation

/// 공개 status 응답. 예고와 예측은 API가 구분한 그대로 보관한다.
struct CodexResetStatus: Decodable, Equatable {
    struct Source: Decodable, Equatable {
        let url: URL?

        /// 링크는 표시용 원문으로만 쓴다. 응답의 URL로 다른 요청을 보내지는 않는다.
        var link: URL? { url.flatMap { $0.scheme == "https" ? $0 : nil } }
    }

    struct Reset: Decodable, Equatable {
        let resetType: String
        let announcedAt: Date
        let text: String
        let source: Source

        var title: String { resetType == "banked" ? "Banked reset" : "Usage reset" }
    }

    struct ScheduledReset: Decodable, Equatable {
        let resetType: String
        let announcedAt: Date
        let scheduledFor: Date?
        let text: String
        let source: Source

        var title: String { resetType == "banked" ? "Banked reset announced" : "Reset announced" }
    }

    struct Watch: Decodable, Equatable {
        let level: String
        let resetChancePercent: Int?
        let forecastWindow: String
        let observedAt: Date
        let expiresAt: Date
        let text: String
        let source: Source
    }

    let latestReset: Reset?
    let scheduledReset: ScheduledReset?
    let activeWatch: Watch?

    private enum CodingKeys: String, CodingKey { case latestReset, scheduledReset, activeWatch }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // 없는 키를 '예고 없음'으로 취급하지 않는다. null은 정상 응답이다.
        latestReset = try values.decode(Reset?.self, forKey: .latestReset)
        scheduledReset = try values.decode(ScheduledReset?.self, forKey: .scheduledReset)
        activeWatch = try values.decode(Watch?.self, forKey: .activeWatch)
    }

    static func parse(_ data: Data) throws -> Self {
        struct Response: Decodable { let data: CodexResetStatus }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = format.date(from: text) { return date }
            format.formatOptions = [.withInternetDateTime]
            if let date = format.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid reset date")
        }
        return try decoder.decode(Response.self, from: data).data
    }
}

/// 실험 기능을 켰을 때만 사용량 갱신과 함께 공개 API를 읽는다. 모든 상태 변경은 메인에서 한다.
final class CodexResetsStore: ObservableObject {
    static let website = URL(string: "https://codex-resets.com")!
    static let endpoint = URL(string: "https://codex-resets.com/api/v1/status")!

    @Published private(set) var status: CodexResetStatus?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    @Published private(set) var lastChecked: Date?

    private let session: URLSession
    private let currentDate: () -> Date
    private var enabled = false
    private var task: URLSessionDataTask?
    private var requestID: UUID?
    private var etag: String?
    private var retryAfter: Date?

    init(session: URLSession? = nil, currentDate: @escaping () -> Date = Date.init) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        self.session = session ?? URLSession(configuration: configuration)
        self.currentDate = currentDate
    }

    deinit { task?.cancel() }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        if !enabled {
            requestID = nil
            task?.cancel()
            task = nil
            isRefreshing = false
            status = nil
            error = nil
            lastChecked = nil
            etag = nil
            // 서버의 재시도 제한은 토글이나 잠자기로 우회하지 않는다.
        }
    }

    func refresh() {
        guard enabled, task == nil, retryAfter.map({ $0 <= currentDate() }) ?? true else { return }
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("usage-overlay", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let id = UUID()
        requestID = id
        isRefreshing = true
        task = session.dataTask(with: request) { [weak self] data, response, failure in
            DispatchQueue.main.async {
                guard let self, self.enabled, self.requestID == id else { return }
                self.task = nil
                self.requestID = nil
                self.isRefreshing = false
                self.lastChecked = self.currentDate()
                let http = response as? HTTPURLResponse
                if failure == nil, http?.statusCode == 304, self.status != nil {
                    self.error = nil
                    return
                }
                if failure == nil, http?.statusCode == 200, let data,
                   let status = try? CodexResetStatus.parse(data) {
                    self.status = status
                    self.error = nil
                    self.etag = http?.value(forHTTPHeaderField: "ETag")
                    self.retryAfter = nil
                } else {
                    // 조회 실패를 '예고 없음'으로 표시하거나 오래된 예측을 현재 값으로 남기지 않는다.
                    self.status = nil
                    self.etag = nil
                    self.error = "Couldn't load Codex reset status."
                    if http?.statusCode == 429 {
                        let seconds = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 300
                        self.retryAfter = self.currentDate().addingTimeInterval(max(30, seconds))
                    }
                }
            }
        }
        task?.resume()
    }
}
