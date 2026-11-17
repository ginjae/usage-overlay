import Foundation
import XCTest
@testable import UsageOverlay

final class OverlayMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "io.github.ginjae.usage-overlay.tests.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstSupportedLaunchSelectsLiquidGlassFromEveryPreviousBackground() {
        for previous in [nil, "regular", "solid", "ultraThin", "thin", "thick", "liquidGlass"] as [String?] {
            defaults.removePersistentDomain(forName: suiteName)
            if let previous { defaults.set(previous, forKey: "overlay.background") }
            defaults.set(0.65, forKey: "opacity")
            defaults.set(false, forKey: "overlayVisible")
            defaults.set(340.0, forKey: "overlay.width")
            defaults.set(true, forKey: "clickThrough")

            Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: true)

            XCTAssertEqual(defaults.string(forKey: "overlay.background"), "liquidGlass")
            XCTAssertEqual(defaults.double(forKey: "opacity"), 0.65)
            XCTAssertFalse(defaults.bool(forKey: "overlayVisible"))
            XCTAssertEqual(defaults.double(forKey: "overlay.width"), 340)
            XCTAssertTrue(defaults.bool(forKey: "clickThrough"))
        }
    }

    func testLaterLaunchesKeepTheUsersChoice() {
        Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: true)
        defaults.set("solid", forKey: "overlay.background")

        // A fresh defaults instance represents the next launch reading the same persisted settings.
        let nextLaunch = UserDefaults(suiteName: suiteName)!
        Prefs.migrateOverlayToLiquidGlass(in: nextLaunch, supported: true)
        XCTAssertEqual(nextLaunch.string(forKey: "overlay.background"), "solid")

        nextLaunch.set("regular", forKey: "overlay.background")
        Prefs.migrateOverlayToLiquidGlass(in: nextLaunch, supported: true)
        XCTAssertEqual(nextLaunch.string(forKey: "overlay.background"), "regular")
    }

    func testUnsupportedMacKeepsItsBackgroundAndCanMigrateAfterAnOSUpgrade() {
        defaults.set("solid", forKey: "overlay.background")
        Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: false)
        XCTAssertEqual(defaults.string(forKey: "overlay.background"), "solid")

        Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: true)
        XCTAssertEqual(defaults.string(forKey: "overlay.background"), "liquidGlass")
    }

    func testClearingOverlayPreferencesDoesNotRepeatTheMigration() {
        Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: true)
        defaults.removeObject(forKey: "overlay.background")
        Prefs.migrateOverlayToLiquidGlass(in: defaults, supported: true)
        XCTAssertNil(defaults.object(forKey: "overlay.background"))
    }
}
