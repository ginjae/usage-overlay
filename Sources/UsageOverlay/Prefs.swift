import AppKit

enum Prefs {
    /// `swift run` 으로 띄운 바이너리와 .app 번들이 같은 도메인을 보게 한다.
    /// 안 그러면 서로 상대의 탭을 못 찾아 창을 하나씩 더 만든다.
    private static let defaults = UserDefaults(suiteName: "io.github.ginjae.usage-overlay") ?? .standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.overlayVisible: true,
            Key.clickThrough: false,
            Key.refreshSeconds: 10,
            Key.opacity: 1.0,
            Key.browserEnabled: true,
            Key.hideWindow: true,
        ])
    }

    private enum Key {
        static let overlayVisible = "overlayVisible"
        static let clickThrough = "clickThrough"
        static let refreshSeconds = "refreshSeconds"
        static let opacity = "opacity"
        static let topLeftX = "topLeftX"
        static let topLeftY = "topLeftY"
        static let browserEnabled = "browserEnabled"
        static let hideWindow = "hideWindow"
    }

    /// 크롬에서 값을 가져올지. 끄면 로컬 캐시 파일만 읽는다.
    static var browserEnabled: Bool {
        get { defaults.bool(forKey: Key.browserEnabled) }
        set { defaults.set(newValue, forKey: Key.browserEnabled) }
    }

    /// 전용 크롬 창을 숨길지. 끄면 창이 보이므로 로그인이 필요할 때 쓴다.
    static var hideWindow: Bool {
        get { defaults.bool(forKey: Key.hideWindow) }
        set { defaults.set(newValue, forKey: Key.hideWindow) }
    }

    /// 사이트별로 열어 둘 URL. 웹앱 라우트가 바뀌어도 재빌드 없이 고칠 수 있게 저장한다.
    ///   defaults write io.github.ginjae.usage-overlay url.claude 'https://claude.ai/new#settings/usage'
    static func url(for key: String) -> String? {
        defaults.string(forKey: "url.\(key)")
    }

    /// 우리가 만든 탭. 사용자가 직접 열어 둔 탭을 건드리지 않도록 id로 추적한다.
    static func tab(for key: String) -> ChromeBridge.Tab? {
        guard defaults.object(forKey: "tab.\(key).tab") != nil else { return nil }
        return ChromeBridge.Tab(tabID: defaults.integer(forKey: "tab.\(key).tab"))
    }

    static func setTab(_ tab: ChromeBridge.Tab?, for key: String) {
        guard let tab else {
            defaults.removeObject(forKey: "tab.\(key).tab")
            return
        }
        defaults.set(tab.tabID, forKey: "tab.\(key).tab")
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
        get { max(2, defaults.integer(forKey: Key.refreshSeconds)) }
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
