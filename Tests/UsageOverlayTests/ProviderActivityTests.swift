import Foundation
import XCTest
@testable import UsageOverlay

final class ProviderActivityTests: XCTestCase {
    private var previousDomain: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        // Volatile overrides are local to this test process; installed app preferences stay intact.
        previousDomain = Prefs.defaults.volatileDomain(forName: "NSArgumentDomain")
        configure()
    }

    override func tearDown() {
        Prefs.defaults.setVolatileDomain(previousDomain, forName: "NSArgumentDomain")
        super.tearDown()
    }

    private func configure(_ extra: [String: Any] = [:]) {
        let defaults: [String: Any] = [
            "providers.claude": true, "providers.codex": true,
            "menuBarClaude": false, "menuBarCodex": false,
            "menuBar.claude.window": "all", "menuBar.codex.window": "all",
            "details.claude": false, "details.codex": false,
            "details.codexResets": false,
            "overlayClaude": true, "overlayCodex": true, "overlayVisible": false,
            "refreshSeconds": 300,
        ]
        Prefs.defaults.setVolatileDomain(defaults.merging(extra) { _, new in new }, forName: "NSArgumentDomain")
    }

    func testHiddenOverlayDoesNotKeepUnusedProvidersActive() {
        XCTAssertFalse(Settings.shared.reads(.claude))
        XCTAssertFalse(Settings.shared.reads(.codex))
        configure(["overlayVisible": true, "overlayCodex": false])
        XCTAssertTrue(Settings.shared.reads(.claude))
        XCTAssertFalse(Settings.shared.reads(.codex))
        configure(["menuBarClaude": true, "details.codex": true])
        XCTAssertTrue(Settings.shared.reads(.claude))
        XCTAssertTrue(Settings.shared.reads(.codex))
    }

    func testGlobalSwitchesOverrideSurfaceVisibilityAndCodexStatus() {
        var preferences: [String: Any] = [
            "menuBarClaude": true, "menuBarCodex": true, "details.claude": true, "details.codex": true,
            "overlayVisible": true, "details.codexResets": true, "providers.codex": false,
        ]
        let snapshot = Snapshot(claude: ProviderUsage(name: "Claude", gauges: []),
                                codex: ProviderUsage(name: "Codex", gauges: []))
        let now = Date()

        configure(preferences)
        XCTAssertEqual(Settings.shared.enabledProviders, [.claude])
        XCTAssertTrue(UsageStore.Configuration.preferences.claude)
        XCTAssertFalse(UsageStore.Configuration.preferences.codex)
        XCTAssertFalse(UsageStore.Configuration.preferences.codexResets)
        XCTAssertEqual(MenuBarText.parts(for: snapshot, now: now).count, 1)
        XCTAssertFalse(MenuBarText.tooltip(for: snapshot, now: now)?.contains("Codex") == true)

        preferences["providers.claude"] = false
        configure(preferences)
        XCTAssertFalse(UsageStore.Configuration.preferences.hasSources)
        XCTAssertEqual(MenuBarText.parts(for: snapshot, now: now).map(\.text), ["Usage"])
        XCTAssertNil(MenuBarText.tooltip(for: snapshot, now: now))

        preferences["providers.codex"] = true
        configure(preferences)
        XCTAssertEqual(Settings.shared.enabledProviders, [.codex])
        XCTAssertFalse(UsageStore.Configuration.preferences.claude)
        XCTAssertTrue(UsageStore.Configuration.preferences.codex)
        XCTAssertTrue(UsageStore.Configuration.preferences.codexResets)
    }

    func testShowingOverlayStartsQueryAndHidingClearsIt() {
        let fetched = expectation(description: "Visible overlay queries Claude")
        fetched.assertForOverFulfill = true
        let store = UsageStore(readClaude: {
            fetched.fulfill()
            return ProviderUsage(name: "Claude", gauges: [], updatedAt: Date())
        }, readCodex: {
            XCTFail("Hidden Codex must not start a query")
            return ProviderUsage(name: "Codex", gauges: [])
        })
        defer { store.stop() }
        store.start()
        XCTAssertFalse(store.isRefreshing)

        configure(["overlayVisible": true, "overlayCodex": false])
        store.settingsChanged()
        XCTAssertTrue(store.isRefreshing)
        wait(for: [fetched], timeout: 2)
        let deadline = Date().addingTimeInterval(2)
        while store.isRefreshing && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(store.snapshot.claude)

        configure()
        store.settingsChanged()
        store.refresh()
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.snapshot.claude)
    }
}
