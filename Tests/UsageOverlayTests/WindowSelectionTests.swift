import Foundation
import XCTest
@testable import UsageOverlay

final class WindowSelectionTests: XCTestCase {
    private let gauges = [
        Gauge(id: "session", label: "5-hour", percent: 30),
        Gauge(id: "week", label: "Weekly", percent: 50),
        Gauge(id: "fable", label: "Fable", percent: 95),
        Gauge(id: "future", label: "Daily", percent: 10),
    ]

    func testEveryCombinationKeepsOnlySelectedWindowsInSourceOrder() {
        for mask in 0..<(1 << gauges.count) {
            let expected = gauges.enumerated().compactMap { index, gauge in
                mask & (1 << index) == 0 ? nil : gauge
            }
            let selection = WindowSelection.selected(Set(expected.map(\.label)))
            XCTAssertEqual(selection.pick(from: gauges), expected)
        }
    }

    func testMissingSelectedWindowNeverFallsBackToHiddenWindow() {
        XCTAssertTrue(WindowSelection.selected(["Monthly"]).pick(from: gauges).isEmpty)
        XCTAssertTrue(WindowSelection.selected(["5-hour"]).pick(from: []).isEmpty)
    }

    func testAllIncludesNewWindowTypesAndTightestStaysAutomatic() {
        XCTAssertEqual(WindowSelection.all.pick(from: gauges), gauges)
        XCTAssertEqual(WindowSelection.tightest.pick(from: gauges), [gauges[2]])
        XCTAssertTrue(WindowSelection.tightest.pick(from: []).isEmpty)
    }

    func testLegacyOverlayChoicesArePreserved() {
        XCTAssertEqual(WindowSelection(stored: "all"), .all)
        XCTAssertEqual(WindowSelection(stored: "tightest"), .tightest)
        XCTAssertEqual(WindowSelection(stored: "fiveHour"), .selected(["5-hour"]))
        XCTAssertEqual(WindowSelection(stored: "weekly"), .selected(["Weekly"]))
        XCTAssertEqual(WindowSelection(stored: "fable"), .selected(["Fable"]))
        XCTAssertNil(WindowSelection(stored: "invalid"))
        XCTAssertNil(WindowSelection(stored: [1, 2]))
    }

    func testPreferencesSurvivePropertyListRoundTripIncludingEmptySelection() throws {
        let selections: [WindowSelection] = [.all, .tightest, .selected([]),
                                             .selected(["5-hour", "Weekly"]), .selected(["Daily"])]
        for selection in selections {
            let data = try PropertyListSerialization.data(fromPropertyList: ["window": selection.stored],
                                                          format: .binary, options: 0)
            let decoded = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any])
            XCTAssertEqual(WindowSelection(stored: try XCTUnwrap(decoded["window"])), selection)
        }
    }

    func testChoicesIncludeAccountSpecificAndPreviouslySelectedWindows() {
        XCTAssertEqual(Provider.claude.windowLabels(from: [], selection: .all), ["5-hour", "Weekly", "Fable"])
        XCTAssertEqual(Provider.codex.windowLabels(from: [], selection: .all), ["5-hour", "Weekly"])
        XCTAssertEqual(Provider.codex.windowLabels(from: [gauges[3]], selection: .selected(["Monthly"])),
                       ["5-hour", "Weekly", "Daily", "Monthly"])
    }

    func testEmptySelectionAndUnavailableSelectionAreNotShownAsLoading() {
        let usage = ProviderUsage(name: "Claude", gauges: gauges)
        XCTAssertEqual(WindowSelection.selected([]).emptyMessage(for: nil), "No windows selected")
        XCTAssertEqual(WindowSelection.selected(["Monthly"]).emptyMessage(for: usage),
                       "Selected windows aren't available")
        XCTAssertEqual(WindowSelection.all.emptyMessage(for: nil), "Loading…")
        XCTAssertEqual(WindowSelection.all.emptyMessage(for: ProviderUsage(name: "Claude", gauges: [])),
                       "No data yet")
    }

    func testProviderAndSurfacePreferencesStayIndependent() {
        let defaults = Prefs.defaults
        let previous = defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { defaults.setVolatileDomain(previous, forName: "NSArgumentDomain") }
        defaults.setVolatileDomain([
            "details.claude.window": ["5-hour", "Weekly"],
            "details.codex.window": ["Weekly"],
            "overlay.claude.window": "fable",
            "overlay.codex.window": "tightest",
            "menuBar.claude.window": "all",
        ], forName: "NSArgumentDomain")

        let settings = Settings.shared
        XCTAssertEqual(settings[keyPath: Provider.claude.detailsWindow], .selected(["5-hour", "Weekly"]))
        XCTAssertEqual(settings[keyPath: Provider.codex.detailsWindow], .selected(["Weekly"]))
        XCTAssertEqual(settings[keyPath: Provider.claude.overlayWindow], .selected(["Fable"]))
        XCTAssertEqual(settings[keyPath: Provider.codex.overlayWindow], .tightest)
        XCTAssertEqual(settings.menuBarClaudeWindow, .all)
    }

    func testSameLabelsHaveDistinctFormIdentitiesAcrossProvidersAndPanes() {
        // Grouped Forms flatten nested ForEach rows. Reused IDs can bind Codex switches to Claude.
        let preferences = Provider.allCases.flatMap { [$0.detailsWindow, $0.overlayWindow] }
        let rows = preferences.flatMap { preference in
            ["5-hour", "Weekly"].map { WindowToggleID(preference: preference, label: $0) }
        }
        XCTAssertEqual(Set(rows).count, 8)
    }

    func testUpdatedDefaultsApplyWhenPreferencesAreUnsetOrInvalid() {
        let defaults = Prefs.defaults
        let previous = defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { defaults.setVolatileDomain(previous, forName: "NSArgumentDomain") }
        // Invalid values exercise the default path without reading or removing installed preferences.
        let keys = ["menuBar.claude.window", "menuBar.codex.window", "menuBarLabel", "menuBarReset",
                    "overlayVisible", "overlay.claude.window", "overlay.codex.window",
                    "details.claude.window", "details.codex.window"]
        defaults.setVolatileDomain(Dictionary(uniqueKeysWithValues: keys.map { ($0, ["invalid": true]) }),
                                  forName: "NSArgumentDomain")
        let settings = Settings.shared
        XCTAssertEqual(settings.menuBarClaudeWindow, .all)
        XCTAssertEqual(settings.menuBarCodexWindow, .all)
        XCTAssertEqual(settings.menuBarLabel, .off)
        XCTAssertEqual(settings.menuBarReset, .logoClock)
        XCTAssertFalse(settings.overlayVisible)
        XCTAssertEqual(settings.overlayClaudeWindow, .selected(["5-hour", "Weekly"]))
        XCTAssertEqual(settings.overlayCodexWindow, .selected(["5-hour", "Weekly"]))
        XCTAssertEqual(settings.detailsClaudeWindow, .all)
        XCTAssertEqual(settings.detailsCodexWindow, .all)
    }
}
