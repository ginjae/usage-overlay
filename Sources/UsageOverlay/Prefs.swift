import AppKit

/// 사용자가 고르지 않는 앱 내부 기록. 고칠 수 있는 값은 Settings 에 있다.
/// 둘은 같은 저장소를 쓰지만, 여기 값은 바뀌어도 화면을 다시 그릴 일이 없어 따로 둔다.
enum Prefs {
    /// `swift run` 으로 띄운 바이너리와 .app 번들이 같은 설정을 보게 한다.
    static let defaults = UserDefaults(suiteName: "io.github.ginjae.usage-overlay") ?? .standard

    private enum Key {
        static let topLeftX = "topLeftX"
        static let topLeftY = "topLeftY"
        static let skippedVersion = "skippedVersion"
        static let lastUpdateCheck = "lastUpdateCheck"
    }

    /// "Skip This Version" 으로 접어 둔 버전. 자동 검사에서만 무시하고, 직접 물으면 다시 보여 준다.
    static var skippedVersion: String? {
        get { defaults.string(forKey: Key.skippedVersion) }
        set { defaults.set(newValue, forKey: Key.skippedVersion) }
    }

    /// 마지막으로 물어본 시각. 껐다 켜는 것만으로 하루 한 번을 넘기지 않도록 남긴다.
    static var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
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
