import Foundation

/// 크롬 탭을 하나씩 맡아 사용량 API를 호출하는 리더.
final class BrowserReader {
    struct Site {
        let name: String
        let origin: String
        let defaultURL: String
        /// 웹앱 설정 모달을 사용량 화면에 유지시키는 해시 라우트. 값 자체는 API에서 온다.
        let hash: String
        let tabKey: String
        /// 사이트별로 엔드포인트를 풀어 사용량 JSON을 돌려주는 JS 함수.
        let resolver: String
    }

    static let claude = Site(name: "Claude",
                             origin: "https://claude.ai",
                             defaultURL: "https://claude.ai/new#settings/usage",
                             hash: "#settings/usage",
                             tabKey: "claude",
                             resolver: PageScript.claudeResolver)

    static let codex = Site(name: "Codex",
                            origin: "https://chatgpt.com",
                            defaultURL: "https://chatgpt.com/sites#settings/Usage",
                            hash: "#settings/Usage",
                            tabKey: "codex",
                            resolver: PageScript.codexResolver)

    private let site: Site
    private var tab: ChromeBridge.Tab?
    private var lastTabCreation: Date?
    /// 조회가 깨지면 폴링마다 창이 새로 열려 크롬이 난장판이 된다.
    /// 어떤 버그가 나더라도 창은 분당 하나를 넘지 않도록 막아 둔다.
    private let tabCreationCooldown: TimeInterval = 60
    /// 응답을 기다리는 한계와 확인 간격.
    private let responseTimeout: TimeInterval = 6
    private let pollStep: TimeInterval = 0.4

    init(site: Site) {
        self.site = site
        tab = Prefs.tab(for: site.tabKey)
    }

    private var url: String { Prefs.url(for: site.tabKey) ?? site.defaultURL }

    func read() -> ProviderUsage? {
        let mayCreate = lastTabCreation.map { Date().timeIntervalSince($0) >= tabCreationCooldown } ?? true
        guard let found = ChromeBridge.ensureTab(existing: tab, url: url,
                                                 origin: site.origin,
                                                 hidden: Prefs.hideWindow,
                                                 mayCreate: mayCreate) else { return nil }

        if self.tab?.tabID != found.tab.tabID {
            tab = found.tab
            Prefs.setTab(found.tab, for: site.tabKey)
        }
        if found.created {
            lastTabCreation = Date()
            return nil  // 방금 연 탭은 아직 로딩 중이다
        }

        return fetchUsage(in: found.tab)
    }

    /// 요청을 띄운 뒤 그 요청의 응답이 들어올 때까지 짧게 기다렸다가 읽는다.
    /// 기다리지 않으면 직전 주기의 값을 읽게 되어 화면이 한 주기 낡는다.
    private func fetchUsage(in tab: ChromeBridge.Tab) -> ProviderUsage? {
        let script = PageScript.request(resolver: site.resolver, hash: site.hash)
        guard let raw = ChromeBridge.evaluate(script, in: tab),
              let requestedAt = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }

        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollStep)
            guard let raw = ChromeBridge.evaluate(PageScript.readState, in: tab),
                  let data = raw.data(using: .utf8),
                  let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let errAt = Parse.double(state["errAt"]), errAt >= requestedAt { return nil }
            if let at = Parse.double(state["resultAt"]), at >= requestedAt {
                return interpret(state, at: at)
            }
        }
        return nil
    }

    private func interpret(_ state: [String: Any], at milliseconds: Double) -> ProviderUsage? {
        guard let result = state["result"] else { return nil }
        let gauges = UsageScan.normalize(UsageScan.scan(result))
        guard !gauges.isEmpty else { return nil }

        return ProviderUsage(name: site.name,
                             gauges: gauges,
                             plan: UsageScan.plan(in: result),
                             source: .browser,
                             updatedAt: Date(timeIntervalSince1970: milliseconds / 1000),
                             note: nil)
    }

    func closeTab() {
        if let tab { ChromeBridge.closeTab(tab) }
        tab = nil
        lastTabCreation = nil
        Prefs.setTab(nil, for: site.tabKey)
    }
}
