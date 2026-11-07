import XCTest
@testable import UsageOverlay

final class SettingsSearchTests: XCTestCase {
    private func panes(matching query: String) -> [SettingsView.Pane] {
        SettingsView.Pane.allCases.filter { $0.matches(query) }
    }

    func testEmptyQueryShowsEveryPane() {
        XCTAssertEqual(panes(matching: ""), SettingsView.Pane.allCases)
        XCTAssertEqual(panes(matching: "   "), SettingsView.Pane.allCases)
    }

    func testFindsPanesByTheirRowsNotOnlyTheirTitles() {
        XCTAssertEqual(panes(matching: "opacity"), [.overlay])
        XCTAssertEqual(panes(matching: "launch at login"), [.general])
        XCTAssertEqual(panes(matching: "release notes"), [.updates])
        XCTAssertEqual(panes(matching: "PACE"), [.details])
    }

    func testEveryWordMustMatchTheSamePane() {
        XCTAssertEqual(panes(matching: "logo clock"), [.menuBar])
        XCTAssertEqual(panes(matching: "opacity tooltip"), [])
    }

    func testMatchesTheStartOfWordsWhileTyping() {
        XCTAssertEqual(panes(matching: "opac"), [.overlay])
        XCTAssertEqual(panes(matching: "command-line"), [.general])
        // "space" 안의 "pace" 는 낱말 첫머리가 아니다.
        XCTAssertFalse(panes(matching: "pace").contains(.overlay))
    }
}

final class ReleaseNotesTests: XCTestCase {
    func testSplitsHeadingsBulletsAndParagraphsAndDropsTheDocumentTitle() {
        let markdown = """
        # Usage Overlay v1.2.1

        Correct the Codex plan labels:

        - **Pro 100** for the $100/month subscription.
        * **Pro 200** for the $200/month subscription.

        ## Interface fixes
        **Compatibility:** macOS 14 or later.
        """
        XCTAssertEqual(ReleaseNotes.blocks(of: markdown), [
            .paragraph("Correct the Codex plan labels:"),
            .bullet("**Pro 100** for the $100/month subscription."),
            .bullet("**Pro 200** for the $200/month subscription."),
            .heading("Interface fixes"),
            .paragraph("**Compatibility:** macOS 14 or later."),
        ])
    }

    func testEmptyNotesHaveNoBlocks() {
        XCTAssertEqual(ReleaseNotes.blocks(of: "# Usage Overlay v1.3.0\n\n"), [])
    }
}
