import Combine
import Foundation

/// 사용자가 고칠 수 있는 값 전부. 설정 창이 여기에 묶이고, 메뉴바 · 상세 창 · 오버레이는 그릴 때마다 여기서 읽는다.
///
/// 값을 따로 들고 있지 않고 UserDefaults 를 바로 읽고 쓴다. 바뀌면 objectWillChange 가 울려 세 화면이 다시 그린다.
/// 예전 판에서 쓰던 키는 그대로 둔다. 업데이트해도 골라 둔 설정이 남는다.
final class Settings: ObservableObject {
    static let shared = Settings()

    /// 설정 창의 한 쪽. 기본값 되돌리기를 이 단위로 한다.
    enum Section { case general, menuBar, details, overlay, colors }

    let defaults = Prefs.defaults

    private init() {}

    // MARK: - 일반

    /// 갱신마다 CLI를 띄우고 서버에 물어본다. 너무 잦으면 얻는 것 없이 시끄러워서 30초 밑으로는 쓰지 않는다.
    @Pref("refreshSeconds", .general) var refreshSeconds = 300
    @Pref("providerOrder", .general) var providerOrder = ProviderOrder.claudeFirst
    /// CLI를 흔치 않은 곳에 깔았을 때 직접 지정하는 자리. 비어 있으면 알려진 설치 위치를 훑는다.
    @Pref("path.claude", .general) var claudePath = ""
    @Pref("path.codex", .general) var codexPath = ""
    /// 하루 한 번 새 버전이 나왔는지 본다. 앱이 스스로 네트워크를 쓰는 유일한 자리라 끌 수 있게 둔다.
    @Pref("autoUpdate", .general) var autoUpdate = true

    // MARK: - 메뉴바

    @Pref("menuBarClaude", .menuBar) var menuBarClaude = true
    @Pref("menuBarCodex", .menuBar) var menuBarCodex = true
    /// 예전에는 두 공급자가 창 고르기 하나를 같이 썼다. 따로 고르기 전까지는 그 값을 물려받는다.
    @Pref("menuBar.claude.window", .menuBar, legacy: "menuBarWindow") var menuBarClaudeWindow = WindowChoice.tightest
    @Pref("menuBar.codex.window", .menuBar, legacy: "menuBarWindow") var menuBarCodexWindow = WindowChoice.tightest
    @Pref("menuBarValue", .menuBar) var menuBarValue = PercentKind.remaining
    /// 숫자 앞 창 이름. 예) `5h 39%`
    @Pref("menuBarLabel", .menuBar) var menuBarLabel = LabelStyle.short
    @Pref("menuBar.percentSign", .menuBar) var menuBarPercentSign = true
    @Pref("menuBar.separator", .menuBar) var menuBarSeparator = WindowSeparator.dot
    @Pref("menuBarIcon", .menuBar) var menuBarIcon = true
    /// 남은 시간을 붙일지, 붙인다면 글자로 셀지 로고에 시계로 그릴지. 예) `5h 39% · 2h 10m`
    @Pref("menuBarReset", .menuBar) var menuBarReset = MenuBarReset.off
    /// 카운트다운을 몇 단위까지 쓸지. 1 이면 `2h`, 2 면 `2h 10m`.
    @Pref("menuBar.countdownUnits", .menuBar) var menuBarCountdownUnits = 2
    @Pref("menuBar.clockFill", .menuBar) var menuBarClockFill = ClockFill.matchPercent
    /// 시계에서 칠하지 않은 쪽의 진하기.
    @Pref("menuBar.clockDim", .menuBar) var menuBarClockDim = 0.3
    @Pref("menuBar.ringWidth", .menuBar) var menuBarRingWidth = 1.5
    @Pref("menuBar.color", .menuBar) var menuBarColor = MenuBarColor.monochrome
    @Pref("menuBar.fontSize", .menuBar) var menuBarFontSize = 11.5
    @Pref("menuBar.fontWeight", .menuBar) var menuBarFontWeight = FontWeight.regular
    /// 숫자 폭을 고정하면 값이 바뀌어도 옆 메뉴바 아이콘들이 들썩이지 않는다.
    @Pref("menuBar.monospacedDigits", .menuBar) var menuBarMonospacedDigits = true
    @Pref("menuBar.iconSize", .menuBar) var menuBarIconSize = 13.0
    @Pref("menuBar.iconGap", .menuBar) var menuBarIconGap = 3.0
    /// 같은 공급자의 창 사이, 구분 기호 양옆.
    @Pref("menuBar.windowGap", .menuBar) var menuBarWindowGap = 4.0
    /// 공급자 사이. 창 사이보다 넓어야 어디서 갈리는지 보인다.
    @Pref("menuBar.providerGap", .menuBar) var menuBarProviderGap = 9.0
    @Pref("menuBar.tooltip", .menuBar) var menuBarTooltip = true

    // MARK: - 상세 창

    @Pref("details.claude", .details) var detailsClaude = true
    @Pref("details.codex", .details) var detailsCodex = true
    @Pref("details.value", .details) var detailsValue = PercentKind.remaining
    @Pref("details.plan", .details) var detailsPlan = true
    @Pref("details.bars", .details) var detailsBars = true
    @Pref("details.countdown", .details) var detailsCountdown = true
    /// 리셋되는 시각. 카운트다운만으로는 오늘인지 내일인지 따져 봐야 한다.
    @Pref("details.resetTime", .details) var detailsResetTime = true
    /// 지금 속도로 쓰면 리셋 전에 바닥나는지. 어림값이라 기본으로는 감춘다.
    @Pref("details.pace", .details) var detailsPace = false
    @Pref("details.updated", .details) var detailsUpdated = true
    @Pref("details.width", .details) var detailsWidth = 300.0

    // MARK: - 오버레이

    @Pref("overlayVisible", .overlay) var overlayVisible = true
    @Pref("clickThrough", .overlay) var overlayClickThrough = false
    @Pref("overlay.locked", .overlay) var overlayLocked = false
    @Pref("opacity", .overlay) var overlayOpacity = 1.0
    @Pref("overlayClaude", .overlay) var overlayClaude = true
    @Pref("overlayCodex", .overlay) var overlayCodex = true
    @Pref("overlay.claude.window", .overlay) var overlayClaudeWindow = WindowChoice.all
    @Pref("overlay.codex.window", .overlay) var overlayCodexWindow = WindowChoice.all
    @Pref("overlay.value", .overlay) var overlayValue = PercentKind.remaining
    @Pref("overlay.header", .overlay) var overlayHeader = true
    @Pref("overlay.plan", .overlay) var overlayPlan = true
    @Pref("overlay.labels", .overlay) var overlayLabels = true
    @Pref("overlay.bars", .overlay) var overlayBars = true
    @Pref("overlay.percent", .overlay) var overlayPercent = true
    @Pref("overlay.countdown", .overlay) var overlayCountdown = true
    @Pref("overlay.footer", .overlay) var overlayFooter = true
    @Pref("overlay.width", .overlay) var overlayWidth = 244.0
    /// 글자와 여백을 함께 키운다. 막대 굵기는 따로 고른다.
    @Pref("overlay.scale", .overlay) var overlayScale = 1.0
    @Pref("overlay.barHeight", .overlay) var overlayBarHeight = 5.0
    @Pref("overlay.background", .overlay) var overlayBackground = OverlayBackground.ultraThin
    @Pref("overlay.cornerRadius", .overlay) var overlayCornerRadius = 13.0
    @Pref("overlay.border", .overlay) var overlayBorder = true
    @Pref("overlay.allSpaces", .overlay) var overlayAllSpaces = true
    @Pref("overlay.alwaysOnTop", .overlay) var overlayAlwaysOnTop = true

    // MARK: - 색

    @Pref("colors.high", .colors) var colorHigh = RGBA(red: 0.30, green: 0.78, blue: 0.47)
    @Pref("colors.mid", .colors) var colorMid = RGBA(red: 0.95, green: 0.72, blue: 0.25)
    @Pref("colors.low", .colors) var colorLow = RGBA(red: 0.94, green: 0.38, blue: 0.34)
    /// 남은 양이 이 밑으로 내려가면 그 단계 색이 된다.
    @Pref("colors.midBelow", .colors) var midBelow = 50.0
    @Pref("colors.lowBelow", .colors) var lowBelow = 20.0
    /// Claude 는 브랜드 주황, Codex 는 로고가 단색이라 글자색을 그대로 쓴다.
    @Pref("colors.claude", .colors) var claudeAccent = Tint.custom(RGBA(red: 0.85, green: 0.45, blue: 0.28))
    @Pref("colors.codex", .colors) var codexAccent = Tint.text

    // MARK: - 읽기 도우미

    /// 어느 화면에도 안 띄우는 공급자는 CLI 를 돌릴 이유가 없다.
    /// 갱신마다 프로세스 하나와 몇 초를 아끼고, 안 쓰는 CLI 의 오류도 따라 사라진다.
    func reads(_ provider: Provider) -> Bool {
        self[keyPath: provider.menuBarShown] || self[keyPath: provider.overlayShown]
            || self[keyPath: provider.detailsShown]
    }

    /// 직접 지정한 CLI 경로. 비어 있으면 nil.
    func path(for name: String) -> String? {
        let path = name == "claude" ? claudePath : name == "codex" ? codexPath : ""
        return path.isEmpty ? nil : (path as NSString).expandingTildeInPath
    }

    func level(remaining: Double) -> Level {
        if remaining < lowBelow { return .low }
        if remaining < midBelow { return .mid }
        return .high
    }

    func color(for level: Level) -> RGBA {
        switch level {
        case .high: return colorHigh
        case .mid: return colorMid
        case .low: return colorLow
        }
    }

    /// 단계는 무엇을 띄우든 남은 양으로 가른다. 쓴 양을 보여 줘도 바닥이 가까우면 붉어진다.
    func levelColor(of gauge: Gauge) -> RGBA {
        color(for: level(remaining: max(0, 100 - gauge.percent)))
    }

    /// 한 쪽의 값을 모두 지워 기본값으로 돌린다. 물려받던 예전 키도 같이 지워야 되살아나지 않는다.
    func reset(_ section: Section) {
        objectWillChange.send()
        for case let pref as AnyPref in Mirror(reflecting: self).children.map(\.value) where pref.section == section {
            pref.keys.forEach(defaults.removeObject(forKey:))
        }
    }
}

/// 설정 값 하나를 UserDefaults 에 넣고 꺼내는 방법.
protocol PrefValue {
    init?(stored: Any)
    var stored: Any { get }
}

extension Bool: PrefValue {
    init?(stored: Any) {
        guard let value = stored as? Bool else { return nil }
        self = value
    }

    var stored: Any { self }
}

extension Int: PrefValue {
    init?(stored: Any) {
        guard let value = stored as? Int else { return nil }
        self = value
    }

    var stored: Any { self }
}

extension Double: PrefValue {
    init?(stored: Any) {
        guard let value = stored as? Double else { return nil }
        self = value
    }

    var stored: Any { self }
}

extension String: PrefValue {
    init?(stored: Any) {
        guard let value = stored as? String else { return nil }
        self = value
    }

    var stored: Any { self }
}

/// 고르는 값은 이름으로 저장한다. 순서를 바꾸거나 새 값을 끼워도 예전 설정이 그대로 읽힌다.
extension PrefValue where Self: RawRepresentable, RawValue == String {
    init?(stored: Any) {
        guard let raw = stored as? String else { return nil }
        self.init(rawValue: raw)
    }

    var stored: Any { rawValue }
}

/// Settings 의 한 칸. 들고 있는 건 키와 기본값뿐이고, 값은 늘 UserDefaults 에서 읽고 바로 쓴다.
/// 기본값을 여기 한자리에 두므로 따로 등록하지 않는다.
@propertyWrapper
struct Pref<Value: PrefValue> {
    let key: String
    let section: Settings.Section
    /// 예전 이름으로 저장된 값. 새 키가 비어 있을 때만 읽는다.
    let legacyKey: String?
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String, _ section: Settings.Section, legacy legacyKey: String? = nil) {
        self.key = key
        self.section = section
        self.legacyKey = legacyKey
        self.defaultValue = wrappedValue
    }

    @available(*, unavailable, message: "Settings 안에서만 쓴다.")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    /// 감싼 쪽(Settings)을 받아야 바뀔 때 objectWillChange 를 울릴 수 있다.
    /// 컴파일러는 이 꼴(제네릭, 매개변수 이름까지)이 맞아야만 찾아 쓴다.
    static subscript<Owner: Settings>(_enclosingInstance settings: Owner,
                                      wrapped wrappedKeyPath: ReferenceWritableKeyPath<Owner, Value>,
                                      storage storageKeyPath: ReferenceWritableKeyPath<Owner, Pref<Value>>) -> Value {
        get {
            let pref = settings[keyPath: storageKeyPath]
            let stored = settings.defaults.object(forKey: pref.key)
                ?? pref.legacyKey.flatMap(settings.defaults.object(forKey:))
            return stored.flatMap(Value.init(stored:)) ?? pref.defaultValue
        }
        set {
            settings.objectWillChange.send()
            settings.defaults.set(newValue.stored, forKey: settings[keyPath: storageKeyPath].key)
        }
    }
}

/// 값의 형을 몰라도 지울 수 있게 키만 꺼내 보는 모양.
private protocol AnyPref {
    var keys: [String] { get }
    var section: Settings.Section { get }
}

extension Pref: AnyPref {
    fileprivate var keys: [String] { [key] + (legacyKey.map { [$0] } ?? []) }
}
