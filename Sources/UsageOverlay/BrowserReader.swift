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

        let script = PageScript.poll(resolver: site.resolver, hash: site.hash)
        guard let raw = ChromeBridge.evaluate(script, in: found.tab),
              let data = raw.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return interpret(payload)
    }

    /// fetch가 비동기라 첫 폴링은 요청만 띄우고 끝난다. 값은 다음 폴링에서 잡힌다.
    private func interpret(_ payload: [String: Any]) -> ProviderUsage? {
        guard let result = payload["result"],
              let at = Parse.double(payload["resultAt"]), at > 0 else { return nil }

        let gauges = UsageScan.normalize(UsageScan.scan(result))
        guard !gauges.isEmpty else { return nil }

        return ProviderUsage(name: site.name,
                             gauges: gauges,
                             plan: UsageScan.plan(in: result),
                             source: .browser,
                             updatedAt: Date(timeIntervalSince1970: at / 1000),
                             note: nil)
    }

    func closeTab() {
        if let tab { ChromeBridge.closeTab(tab) }
        tab = nil
        lastTabCreation = nil
        Prefs.setTab(nil, for: site.tabKey)
    }
}
