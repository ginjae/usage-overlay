import Combine
import Foundation

/// 주기적으로 두 리더를 돌려 스냅샷을 갱신한다.
/// 읽기에 실패하면(CLI가 파일을 쓰는 중 등) 직전 값을 그대로 유지한다.
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    /// 남은 시간 표시를 1초마다 다시 그리기 위한 시계.
    @Published private(set) var now = Date()
    /// 새로고침 버튼에 회전 피드백을 주기 위한 플래그.
    @Published private(set) var isRefreshing = false

    private let codexReader = CodexReader()
    let claudeBrowser = BrowserReader(site: BrowserReader.claude)
    let codexBrowser = BrowserReader(site: BrowserReader.codex)
    private let queue = DispatchQueue(label: "usage-overlay.reader", qos: .utility)
    private var timer: Timer?
    private var secondsSinceRefresh = 0

    func start() {
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)  // 창을 드래그하는 동안에도 계속 돌도록
        self.timer = timer
    }

    private func tick() {
        now = Date()
        secondsSinceRefresh += 1
        if secondsSinceRefresh >= Prefs.refreshSeconds {
            refresh()
        }
    }

    func refresh() {
        secondsSinceRefresh = 0
        isRefreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            // 웹이 1순위(CLI를 안 켜도 최신), 실패하면 로컬 캐시로 떨어진다.
            let useBrowser = Prefs.browserEnabled && ChromeBridge.isRunning && ChromeBridge.javaScriptEnabled()
            let localClaude = ClaudeReader.read()
            let localCodex = self.codexReader.read()
            var claude = (useBrowser ? self.claudeBrowser.read() : nil) ?? localClaude
            var codex = (useBrowser ? self.codexBrowser.read() : nil) ?? localCodex
            // claude.ai 사용량 응답에는 플랜 이름이 없어 로컬 캐시에서 채워 넣는다.
            if claude?.plan == nil { claude?.plan = localClaude?.plan }
            if codex?.plan == nil { codex?.plan = localCodex?.plan }
            DispatchQueue.main.async {
                self.isRefreshing = false
                var next = self.snapshot
                if let claude { next.claude = claude }
                if let codex { next.codex = codex }
                if next != self.snapshot { self.snapshot = next }
            }
        }
    }
}
