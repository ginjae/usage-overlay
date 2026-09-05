import AppKit

enum Prefs {
    /// `swift run` 으로 띄운 바이너리와 .app 번들이 같은 설정을 보게 한다.
    private static let defaults = UserDefaults(suiteName: "io.github.ginjae.usage-overlay") ?? .standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.overlayVisible: true,
            Key.clickThrough: false,
            Key.refreshSeconds: 60,
            Key.opacity: 1.0,
            Key.overlayClaude: true,
            Key.overlayCodex: true,
            Key.menuBarClaude: true,
            Key.menuBarCodex: true,
            Key.menuBarWindow: MenuBarWindow.tightest.rawValue,
            Key.menuBarValue: MenuBarValue.remaining.rawValue,
            Key.menuBarLabel: true,
            Key.menuBarIcon: true,
            Key.menuBarReset: false,
        ])
    }

    private enum Key {
        static let overlayVisible = "overlayVisible"
        static let clickThrough = "clickThrough"
        static let refreshSeconds = "refreshSeconds"
        static let opacity = "opacity"
        static let topLeftX = "topLeftX"
        static let topLeftY = "topLeftY"
        static let overlayClaude = "overlayClaude"
        static let overlayCodex = "overlayCodex"
        static let menuBarClaude = "menuBarClaude"
        static let menuBarCodex = "menuBarCodex"
        static let menuBarWindow = "menuBarWindow"
        static let menuBarValue = "menuBarValue"
        static let menuBarLabel = "menuBarLabel"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarReset = "menuBarReset"
    }

    // MARK: - 공급자 표시

    /// 오버레이에 공급자 블록을 넣을지. 한쪽만 쓰는 사람은 반대쪽을 꺼서 창을 줄인다.
    static var overlayClaude: Bool {
        get { defaults.bool(forKey: Key.overlayClaude) }
        set { defaults.set(newValue, forKey: Key.overlayClaude) }
    }

    static var overlayCodex: Bool {
        get { defaults.bool(forKey: Key.overlayCodex) }
        set { defaults.set(newValue, forKey: Key.overlayCodex) }
    }

    /// 어느 화면에도 안 띄우는 공급자는 CLI 를 돌릴 이유가 없다.
    /// 갱신마다 프로세스 하나와 몇 초를 아끼고, 안 쓰는 CLI 의 오류도 따라 사라진다.
    static var readClaude: Bool { overlayClaude || menuBarClaude }
    static var readCodex: Bool { overlayCodex || menuBarCodex }

    /// 메뉴바에 공급자를 넣을지. 하나만 쓰는 사람은 반대쪽을 꺼서 폭을 줄인다.
    static var menuBarClaude: Bool {
        get { defaults.bool(forKey: Key.menuBarClaude) }
        set { defaults.set(newValue, forKey: Key.menuBarClaude) }
    }

    static var menuBarCodex: Bool {
        get { defaults.bool(forKey: Key.menuBarCodex) }
        set { defaults.set(newValue, forKey: Key.menuBarCodex) }
    }

    /// 어떤 한도 창의 숫자를 메뉴바에 띄울지.
    static var menuBarWindow: MenuBarWindow {
        get { defaults.string(forKey: Key.menuBarWindow).flatMap(MenuBarWindow.init(rawValue:)) ?? .tightest }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarWindow) }
    }

    /// 퍼센트를 남은 양으로 볼지 쓴 양으로 볼지.
    static var menuBarValue: MenuBarValue {
        get { defaults.string(forKey: Key.menuBarValue).flatMap(MenuBarValue.init(rawValue:)) ?? .remaining }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarValue) }
    }

    /// 숫자 앞에 창 이름을 붙일지. 예) `5h 39%`
    static var menuBarLabel: Bool {
        get { defaults.bool(forKey: Key.menuBarLabel) }
        set { defaults.set(newValue, forKey: Key.menuBarLabel) }
    }

    static var menuBarIcon: Bool {
        get { defaults.bool(forKey: Key.menuBarIcon) }
        set { defaults.set(newValue, forKey: Key.menuBarIcon) }
    }

    /// 남은 시간까지 붙일지. 예) `5h 39% · 2h 10m`
    static var menuBarReset: Bool {
        get { defaults.bool(forKey: Key.menuBarReset) }
        set { defaults.set(newValue, forKey: Key.menuBarReset) }
    }

    /// CLI를 흔치 않은 곳에 깔았을 때 직접 지정하는 자리. 재빌드 없이 고칠 수 있다.
    ///   defaults write io.github.ginjae.usage-overlay path.claude '/opt/homebrew/bin/claude'
    static func path(for name: String) -> String? {
        defaults.string(forKey: "path.\(name)")
    }

    static var overlayVisible: Bool {
        get { defaults.bool(forKey: Key.overlayVisible) }
        set { defaults.set(newValue, forKey: Key.overlayVisible) }
    }

    static var clickThrough: Bool {
        get { defaults.bool(forKey: Key.clickThrough) }
        set { defaults.set(newValue, forKey: Key.clickThrough) }
    }

    static var refreshSeconds: Int {
        // 갱신마다 CLI를 두 개 띄우고 서버에 물어본다. 너무 잦으면 얻는 것 없이 시끄럽다.
        get { max(30, defaults.integer(forKey: Key.refreshSeconds)) }
        set { defaults.set(newValue, forKey: Key.refreshSeconds) }
    }

    static var opacity: Double {
        get { defaults.double(forKey: Key.opacity) }
        set { defaults.set(newValue, forKey: Key.opacity) }
    }

    /// 창의 좌상단 위치. 창 높이가 바뀌어도 위쪽이 고정되도록 좌상단을 기준으로 저장한다.
    static var topLeft: NSPoint? {
        get {
            guard defaults.object(forKey: Key.topLeftX) != nil else { return nil }
            return NSPoint(x: defaults.double(forKey: Key.topLeftX),
                           y: defaults.double(forKey: Key.topLeftY))
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.topLeftX)
                defaults.removeObject(forKey: Key.topLeftY)
                return
            }
            defaults.set(newValue.x, forKey: Key.topLeftX)
            defaults.set(newValue.y, forKey: Key.topLeftY)
        }
    }
}
