import AppKit

Prefs.registerDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // Dock에 뜨지 않는 메뉴바 앱
app.run()
