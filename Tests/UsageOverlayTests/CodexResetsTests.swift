import AppKit
import Foundation
import XCTest
@testable import UsageOverlay

final class CodexResetsTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetAPIStub.self]
        session = URLSession(configuration: configuration)
        ResetAPIStub.handler = nil
    }

    override func tearDown() {
        session.invalidateAndCancel()
        ResetAPIStub.handler = nil
        super.tearDown()
    }

    func testStatusDecodesLatestScheduledAndWatchWithoutInventingCompletion() throws {
        let status = try CodexResetStatus.parse(payload(announcements: true))
        XCTAssertEqual(status.latestReset?.resetType, "banked")
        XCTAssertEqual(status.scheduledReset?.resetType, "regular")
        XCTAssertNotNil(status.scheduledReset?.scheduledFor)
        // A passed scheduled time is still an announcement; only the API decides completion.
        XCTAssertLessThan(try XCTUnwrap(status.scheduledReset?.scheduledFor), Date())
        XCTAssertEqual(status.activeWatch?.level, "strong")
        XCTAssertEqual(status.activeWatch?.resetChancePercent, 80)
        XCTAssertEqual(status.activeWatch?.forecastWindow, "next 24 hours")
        XCTAssertEqual(status.activeWatch?.source.link?.host, "x.com")
    }

    func testNullsAreNormalButMissingKeysAndBadDatesAreNotEmptyStatus() throws {
        let empty = try CodexResetStatus.parse(payload())
        XCTAssertNil(empty.scheduledReset)
        XCTAssertNil(empty.activeWatch)
        XCTAssertThrowsError(try CodexResetStatus.parse(Data(#"{"data":{}}"#.utf8)))
        let malformed = String(decoding: payload(), as: UTF8.self)
            .replacingOccurrences(of: "2026-11-12T21:59:39.000Z", with: "not a date")
        XCTAssertThrowsError(try CodexResetStatus.parse(Data(malformed.utf8)))
    }

    func testDisabledFeatureDoesNotSendRequests() {
        ResetAPIStub.handler = { _ in
            XCTFail("Disabled experiments must not access the API")
            return (200, [:], self.payload())
        }
        let feed = CodexResetsStore(session: session)
        feed.refresh()
        XCTAssertFalse(feed.isRefreshing)
        XCTAssertNil(feed.status)
        XCTAssertNil(feed.lastChecked)
    }

    func testConditionalRefreshKeepsStatusAndDisablingClearsIt() {
        var calls = 0
        ResetAPIStub.handler = { request in
            calls += 1
            XCTAssertEqual(request.url, CodexResetsStore.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            if calls == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
                return (200, ["ETag": "\"reset-1\""], self.payload(announcements: true))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"reset-1\"")
            return (304, [:], Data())
        }
        let feed = CodexResetsStore(session: session)
        feed.setEnabled(true)
        refresh(feed)
        let previous = feed.status
        refresh(feed)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(feed.status, previous)
        XCTAssertNil(feed.error)
        feed.setEnabled(false)
        XCTAssertNil(feed.status)
        XCTAssertNil(feed.lastChecked)
        feed.refresh()
        XCTAssertEqual(calls, 2)
    }

    func testFailedRefreshClearsOldForecastAndHonorsRetryAfter() {
        var now = Date()
        var calls = 0
        ResetAPIStub.handler = { _ in
            calls += 1
            return calls == 1 ? (200, [:], self.payload(announcements: true))
                : (429, ["Retry-After": "600"], Data())
        }
        let feed = CodexResetsStore(session: session, currentDate: { now })
        feed.setEnabled(true)
        refresh(feed)
        XCTAssertNotNil(feed.status?.activeWatch)
        refresh(feed)
        XCTAssertNil(feed.status)
        XCTAssertNotNil(feed.error)
        feed.refresh()
        XCTAssertFalse(feed.isRefreshing)
        XCTAssertEqual(calls, 2)
        feed.setEnabled(false)
        feed.setEnabled(true)
        feed.refresh()
        XCTAssertEqual(calls, 2)
        now.addTimeInterval(601)
        refresh(feed)
        XCTAssertEqual(calls, 3)
    }

    func testAnnouncementsRefreshWithoutCLIProvidersAndResizeOpenDetails() throws {
        let defaults = Prefs.defaults
        let previous = defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { defaults.setVolatileDomain(previous, forName: "NSArgumentDomain") }
        defaults.setVolatileDomain([
            "details.codexResets": true, "details.claude": false, "details.codex": false,
            "details.width": 300.0,
        ], forName: "NSArgumentDomain")
        var announcements = true
        ResetAPIStub.handler = { _ in (200, [:], self.payload(announcements: announcements)) }
        let feed = CodexResetsStore(session: session)
        let store = UsageStore(configuration: {
            .init(claude: false, codex: false, interval: 300, codexResets: true)
        }, codexResets: feed, readClaude: {
            XCTFail("Reset status must not start Claude")
            return ProviderUsage(name: "Claude", gauges: [])
        }, readCodex: {
            XCTFail("Reset status must not start Codex")
            return ProviderUsage(name: "Codex", gauges: [])
        })
        defer { store.stop() }
        store.start()
        finish(feed)
        let item = DetailsMenuItem(store: store)
        let hosting = try XCTUnwrap(item.view)
        hosting.layoutSubtreeIfNeeded()
        let tall = hosting.frame.height
        announcements = false
        while store.isRefreshing { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        store.refresh()
        finish(feed)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThan(hosting.frame.height, tall)
        XCTAssertNil(feed.status?.scheduledReset)
        XCTAssertNil(feed.status?.activeWatch)
        store.setSuspended(true, for: .systemSleep)
        XCTAssertNil(feed.status)
        store.setSuspended(false, for: .systemSleep)
        finish(feed)
        XCTAssertNotNil(feed.status)
    }

    func testDisablingInFlightRequestIgnoresItsCompletion() {
        ResetAPIStub.handler = { _ in (200, [:], self.payload(announcements: true)) }
        let feed = CodexResetsStore(session: session)
        feed.setEnabled(true)
        feed.refresh()
        feed.setEnabled(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(feed.status)
        XCTAssertNil(feed.error)
        XCTAssertNil(feed.lastChecked)
        XCTAssertFalse(feed.isRefreshing)
    }

    private func refresh(_ feed: CodexResetsStore) {
        feed.refresh()
        finish(feed)
    }

    private func finish(_ feed: CodexResetsStore) {
        let deadline = Date().addingTimeInterval(2)
        while feed.isRefreshing && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(feed.isRefreshing)
    }

    private func payload(announcements: Bool = false) -> Data {
        let source = #"{"type":"x_post","author":"thsottiaux","url":"https://x.com/thsottiaux/status/123"}"#
        let scheduled = announcements ? """
        {"id":"scheduled-1","status":"scheduled","reset_type":"regular",
         "announced_at":"2026-11-12T20:00:00Z","scheduled_for":"2026-11-12T22:00:00.000Z",
         "text":"A reset is scheduled for later today.","source":\(source)}
        """ : "null"
        let watch = announcements ? """
        {"level":"strong","reset_chance_percent":80,"forecast_window":"next 24 hours",
         "observed_at":"2026-11-12T20:00:00Z","expires_at":"2026-11-13T20:00:00Z",
         "text":"An AI-classified forecast, not a confirmed reset.","source":\(source)}
        """ : "null"
        return Data("""
        {"data":{"latest_reset":{"id":"reset-1","reset_type":"banked",
         "announced_at":"2026-11-12T21:59:39.000Z","text":"A banked reset has been activated.",
         "source":\(source)},"scheduled_reset":\(scheduled),"active_watch":\(watch),"stats":{}},
         "meta":{"api_version":"v1","generated_at":"2026-11-15T02:49:02.043Z"}}
        """.utf8)
    }
}

private final class ResetAPIStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (code, headers, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
