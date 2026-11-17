import AppKit
import ObjectiveC.runtime
import XCTest
@testable import UsageOverlay

final class OverlayAppearanceTests: XCTestCase {
    func testLiquidGlassKeepsActiveAppearanceWithoutTakingFocus() throws {
        guard drawsLiquidGlass else { throw XCTSkip("Liquid Glass requires a macOS 26 SDK and runtime") }
        let selector = NSSelectorFromString("_hasActiveAppearance")
        let systemMethod = try XCTUnwrap(class_getInstanceMethod(NSPanel.self, selector))
        typealias ActiveAppearance = @convention(c) (NSWindow, Selector) -> Bool
        let systemAppearance = unsafeBitCast(method_getImplementation(systemMethod), to: ActiveAppearance.self)
        let previous = Prefs.defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { Prefs.defaults.setVolatileDomain(previous, forName: "NSArgumentDomain") }
        func configure(_ background: String) {
            Prefs.defaults.setVolatileDomain([
                "overlay.background": background, "overlayVisible": false,
                "overlay.locked": false, "clickThrough": false,
            ], forName: "NSArgumentDomain")
        }
        configure("liquidGlass")
        let previousKey = NSApp?.keyWindow
        let panel = OverlayPanel(store: UsageStore())
        defer { panel.close() }
        panel.apply(Settings.shared)
        let method = try XCTUnwrap(class_getInstanceMethod(OverlayPanel.self, selector))
        let appearance = unsafeBitCast(method_getImplementation(method), to: ActiveAppearance.self)

        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.isMainWindow)
        XCTAssertTrue(appearance(panel, selector), "Unfocused Liquid Glass must retain its native active appearance")
        XCTAssertTrue(NSApp?.keyWindow === previousKey)
        XCTAssertTrue(panel.canBecomeKey, "The refresh button must remain focusable")
        XCTAssertFalse(panel.ignoresMouseEvents)

        for background in ["regular", "solid"] {
            configure(background)
            panel.apply(Settings.shared)
            XCTAssertEqual(appearance(panel, selector), systemAppearance(panel, selector),
                           "Other backgrounds must retain AppKit's normal appearance behavior")
            XCTAssertFalse(panel.isKeyWindow)
        }
    }
}
