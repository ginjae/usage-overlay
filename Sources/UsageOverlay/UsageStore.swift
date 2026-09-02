import Combine
import Foundation

/// 주기적으로 두 CLI를 돌려 스냅샷을 갱신한다.
/// 한쪽이 실패하면 그쪽만 직전 값을 유지한다. 둘을 같이 비우면 화면이 통째로 깜빡인다.
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    /// 남은 시간 표시를 1초마다 다시 그리기 위한 시계.
    @Published private(set) var now = Date()
    /// 새로고침 버튼에 회전 피드백을 주기 위한 플래그.
    @Published private(set) var isRefreshing = false

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
        // CLI 응답을 기다리느라 한 번의 갱신이 몇 초 걸린다.
        // 그 사이 타이머가 또 부르면 프로세스가 쌓이므로 진행 중이면 건너뛴다.
        guard !isRefreshing else { return }
        secondsSinceRefresh = 0
        isRefreshing = true
        queue.async { [weak self] in
            guard let self else { return }
            // 둘 다 프로세스를 띄우고 기다리는 일이라 순서대로 하면 시간이 두 배가 된다.
            var claude: ProviderUsage?
            var codex: ProviderUsage?
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                claude = ClaudeReader.read()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                codex = CodexReader.read()
                group.leave()
            }
            group.wait()

            DispatchQueue.main.async {
                self.isRefreshing = false
                var next = self.snapshot
                // 값을 못 받았으면(게이지가 빈 채로 돌아왔으면) 직전 숫자를 남기고 사유만 갈아 끼운다.
                next.claude = Self.merge(new: claude, old: next.claude)
                next.codex = Self.merge(new: codex, old: next.codex)
                if next != self.snapshot { self.snapshot = next }
            }
        }
    }

    /// 이번 읽기가 부실하면 직전 값으로 메운다. 화면에서 숫자가 사라지는 것보다 낡은 숫자가 낫다.
    private static func merge(new: ProviderUsage?, old: ProviderUsage?) -> ProviderUsage? {
        guard let new else { return old }
        guard let old, !old.gauges.isEmpty else { return new }
        // 하나도 못 받았으면 직전 숫자를 통째로 남기고 사유만 갈아 끼운다.
        guard !new.gauges.isEmpty else {
            var kept = old
            kept.note = new.note
            return kept
        }
        // 퍼센트는 받았는데 리셋 시각만 비어 있는 경우가 가끔 있다(문장 형식이 어긋날 때).
        // 같은 창의 리셋 시각은 분 단위로만 흔들리므로, 한 번씩 "—" 로 깜빡이는 것보다 직전 값이 낫다.
        var merged = new
        merged.gauges = new.gauges.map { gauge in
            guard gauge.resetsAt == nil,
                  let previous = old.gauges.first(where: { $0.label == gauge.label })?.resetsAt
            else { return gauge }
            var filled = gauge
            filled.resetsAt = previous
            return filled
        }
        return merged
    }
}
