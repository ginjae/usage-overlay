import Combine
import Foundation

/// 주기적으로 두 CLI를 돌려 스냅샷을 갱신한다.
/// 한쪽이 실패하면 그쪽만 직전 값을 유지한다. 둘을 같이 비우면 화면이 통째로 깜빡인다.
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    /// 남은 시간과 갱신 시각은 분 단위로만 표시한다.
    @Published private(set) var now = Date()
    /// 조회 중임을 표시하고 중복 요청을 막는다.
    @Published private(set) var isRefreshing = false

    struct Configuration {
        var claude: Bool
        var codex: Bool
        var interval: TimeInterval

        static var preferences: Self {
            Self(claude: Prefs.readClaude, codex: Prefs.readCodex,
                 interval: TimeInterval(Prefs.refreshSeconds))
        }

        var hasProviders: Bool { claude || codex }
    }

    enum SuspensionReason { case systemSleep, displaySleep, inactiveSession }

    private let configuration: () -> Configuration
    private let currentDate: () -> Date
    private let readClaude: () -> ProviderUsage
    private let readCodex: () -> ProviderUsage
    private let queue = DispatchQueue(label: "usage-overlay.reader", qos: .utility)
    private var displayTimer: Timer?
    private var refreshTimer: Timer?
    private var lastRefresh: Date?
    private var isRunning = false
    private var suspensionReasons: Set<SuspensionReason> = []

    init(configuration: @escaping () -> Configuration = { .preferences },
         currentDate: @escaping () -> Date = Date.init,
         readClaude: @escaping () -> ProviderUsage = ClaudeReader.read,
         readCodex: @escaping () -> ProviderUsage = CodexReader.read) {
        self.configuration = configuration
        self.currentDate = currentDate
        self.readClaude = readClaude
        self.readCodex = readCodex
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        settingsChanged()
    }

    func stop() {
        isRunning = false
        invalidateTimers()
    }

    deinit {
        displayTimer?.invalidate()
        refreshTimer?.invalidate()
    }

    /// 화면과 시스템의 깨움 알림 순서가 달라도 모두 복귀한 뒤에만 재개한다.
    func setSuspended(_ suspended: Bool, for reason: SuspensionReason) {
        if suspended {
            guard suspensionReasons.insert(reason).inserted else { return }
        } else {
            guard suspensionReasons.remove(reason) != nil else { return }
        }
        settingsChanged()
    }

    func settingsChanged() {
        let config = configuration()
        var next = snapshot
        if !config.claude { next.claude = nil }
        if !config.codex { next.codex = nil }
        if next != snapshot { snapshot = next }

        guard isRunning, suspensionReasons.isEmpty, config.hasProviders else {
            invalidateTimers()
            return
        }

        now = currentDate()
        if displayTimer == nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.now = self.currentDate()
            }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            displayTimer = timer
        }

        let missingProvider = (config.claude && snapshot.claude == nil)
            || (config.codex && snapshot.codex == nil)
        let isDue = lastRefresh.map { currentDate().timeIntervalSince($0) >= config.interval } ?? true
        if !isRefreshing && (missingProvider || isDue) {
            refresh()
        } else {
            scheduleRefresh()
        }
    }

    private func invalidateTimers() {
        displayTimer?.invalidate()
        displayTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// 조회 시각으로 예약한다. 1초씩 세지 않으므로 잠자기 이후에도 주기가 밀리지 않는다.
    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let config = configuration()
        guard isRunning, suspensionReasons.isEmpty, config.hasProviders, !isRefreshing,
              let lastRefresh else { return }
        let delay = max(1, lastRefresh.addingTimeInterval(config.interval).timeIntervalSince(currentDate()))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.refresh() }
        timer.tolerance = min(5, config.interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        // CLI 응답을 기다리느라 한 번의 갱신이 몇 초 걸린다.
        // 그 사이 타이머가 또 부르면 프로세스가 쌓이므로 진행 중이면 건너뛴다.
        guard isRunning, suspensionReasons.isEmpty, !isRefreshing else { return }
        let config = configuration()
        guard config.hasProviders else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        lastRefresh = currentDate()
        now = currentDate()
        isRefreshing = true
        // 어느 화면에도 안 띄우는 공급자는 읽지 않는다. 설정은 메인에서 한 번만 본다.
        let wantClaude = config.claude
        let wantCodex = config.codex
        queue.async { [weak self] in
            guard let self else { return }
            // 둘 다 프로세스를 띄우고 기다리는 일이라 순서대로 하면 시간이 두 배가 된다.
            var claude: ProviderUsage?
            var codex: ProviderUsage?
            let group = DispatchGroup()
            if wantClaude {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    claude = self.readClaude()
                    group.leave()
                }
            }
            if wantCodex {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    codex = self.readCodex()
                    group.leave()
                }
            }
            group.wait()

            DispatchQueue.main.async {
                self.isRefreshing = false
                self.now = self.currentDate()
                var next = self.snapshot
                // 값을 못 받았으면(게이지가 빈 채로 돌아왔으면) 직전 숫자를 남기고 사유만 갈아 끼운다.
                // 끈 공급자는 비운다. 안 그러면 툴팁에 다시 켜기 전의 숫자가 계속 남는다.
                let current = self.configuration()
                next.claude = current.claude ? Self.merge(new: claude, old: next.claude) : nil
                next.codex = current.codex ? Self.merge(new: codex, old: next.codex) : nil
                if next != self.snapshot { self.snapshot = next }
                // 조회 도중 켠 공급자도 읽되, 일반 완료는 다음 주기까지 쉰다.
                if (current.claude && !wantClaude) || (current.codex && !wantCodex) {
                    self.settingsChanged()
                } else {
                    self.scheduleRefresh()
                }
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
        // 사용량이 0%이고 리셋 시각이 없으면 아직 시작하지 않은 창이므로 빈 값을 유지한다.
        // 사용 중인 창의 시각만 파싱에 실패했다면, 아직 지나지 않은 직전 시각으로만 메운다.
        var merged = new
        merged.gauges = new.gauges.map { gauge in
            guard gauge.resetsAt == nil, gauge.percent > 0,
                  let updatedAt = new.updatedAt,
                  let previous = old.gauges.first(where: { $0.label == gauge.label })?.resetsAt,
                  previous > updatedAt
            else { return gauge }
            var filled = gauge
            filled.resetsAt = previous
            return filled
        }
        return merged
    }
}
