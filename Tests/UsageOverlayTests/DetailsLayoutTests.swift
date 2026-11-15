import AppKit
import SwiftUI
import XCTest
@testable import UsageOverlay

final class DetailsLayoutTests: XCTestCase {
    private var previousDomain: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = Prefs.defaults
        previousDomain = defaults.volatileDomain(forName: "NSArgumentDomain")
        defaults.setVolatileDomain([
            "details.claude": true, "details.codex": false,
            "details.claude.window": "all", "details.updated": true,
            "details.width": 300.0, "details.pace": false,
            "details.codexResets": false,
        ], forName: "NSArgumentDomain")
    }

    override func tearDown() {
        Prefs.defaults.setVolatileDomain(previousDomain, forName: "NSArgumentDomain")
        super.tearDown()
    }

    func testRecoveryFromWrappedErrorShrinksDetailsAndMenuWithoutReopening() throws {
        let now = Date()
        var note: String? = String(repeating: "A temporary error occurred. ", count: 12)
        let store = UsageStore(configuration: { .init(claude: true, codex: false, interval: 300) },
                               currentDate: { now }, readClaude: {
            ProviderUsage(name: "Claude", gauges: [Gauge(id: "session", label: "5-hour", percent: 20)],
                          updatedAt: now, note: note)
        })
        defer { store.stop() }
        store.start()
        finishRefresh(store)
        let item = DetailsMenuItem(store: store)
        let hosting = try XCTUnwrap(item.view)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh Now", action: nil, keyEquivalent: ""))
        menu.addItem(item)
        menu.addItem(.separator())
        hosting.layoutSubtreeIfNeeded()
        let tall = hosting.frame.height
        let tallMenu = menu.size.height

        note = nil
        store.refresh()
        finishRefresh(store)
        // Drive a rendering pass, without invoking menuWillOpen or manually resizing the view.
        hosting.layoutSubtreeIfNeeded()
        let fresh = NSHostingView(rootView: DetailsView(store: store))
        XCTAssertLessThan(hosting.frame.height, tall)
        XCTAssertEqual(hosting.frame.height, fresh.fittingSize.height, accuracy: 1)
        XCTAssertEqual(tallMenu - menu.size.height, tall - hosting.frame.height, accuracy: 1)
    }

    func testRefreshedWindowCountGrowsAndShrinksDetailsWithoutClipping() throws {
        let gauge = Gauge(id: "session", label: "5-hour", percent: 20)
        var gauges = [gauge]
        let store = UsageStore(configuration: { .init(claude: true, codex: false, interval: 300) },
                               readClaude: { ProviderUsage(name: "Claude", gauges: gauges) })
        defer { store.stop() }
        store.start()
        finishRefresh(store)
        let item = DetailsMenuItem(store: store)
        let hosting = try XCTUnwrap(item.view)
        hosting.layoutSubtreeIfNeeded()
        let short = hosting.frame.height

        gauges.append(Gauge(id: "week", label: "Weekly", percent: 40))
        store.refresh()
        finishRefresh(store)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.frame.height, short)
        XCTAssertEqual(hosting.frame.height, ceil(hosting.fittingSize.height))

        gauges = [gauge]
        store.refresh()
        finishRefresh(store)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.frame.height, short)
    }

    private func finishRefresh(_ store: UsageStore) {
        let deadline = Date().addingTimeInterval(2)
        while store.isRefreshing && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(store.isRefreshing)
    }
}
