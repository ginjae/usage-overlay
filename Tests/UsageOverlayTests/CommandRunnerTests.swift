import Darwin
import Foundation
import XCTest
@testable import UsageOverlay

final class CommandRunnerTests: XCTestCase {
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("usage-overlay-command-tests-\(UUID().uuidString)")
    private static var executable: URL?
    // Hosted macOS runners need time to launch the fixture and install its SIGTERM handler.
    // A 150 ms timeout can terminate it before main(), leaving the cleanup path untested.
    private let stubbornTimeout: TimeInterval = 2

    override class func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        executable = nil
        super.tearDown()
    }

    private func fixture() throws -> URL {
        if let executable = Self.executable { return executable }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let source = try XCTUnwrap(Bundle.module.url(forResource: "CommandFixture", withExtension: "c",
                                                   subdirectory: "Fixtures"))
        let executable = Self.directory.appendingPathComponent("command-fixture")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", source.path, "-o", executable.path]
        try compiler.run()
        compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        Self.executable = executable
        return executable
    }

    private func run(_ mode: String, stdin: [String] = [], timeout: TimeInterval = 1,
                     match: ((String) -> Bool)? = nil,
                     file: StaticString = #filePath, line: UInt = #line) throws -> String? {
        let executable = try fixture()
        let pidFile = Self.directory.appendingPathComponent(UUID().uuidString)
        let started = Date()
        let output = CommandRunner.run(executable, [mode, pidFile.path], stdin: stdin,
                                       timeout: timeout, until: match)
        XCTAssertLessThan(Date().timeIntervalSince(started), timeout + 3, file: file, line: line)
        let pid = try XCTUnwrap(pid_t(String(contentsOf: pidFile, encoding: .utf8)), file: file, line: line)
        let alive = kill(pid, 0) == 0
        if alive { kill(pid, SIGKILL) } // Clean up even if this regression returns.
        XCTAssertFalse(alive, "The CLI must be reaped before run returns", file: file, line: line)
        try FileManager.default.removeItem(at: pidFile)
        return output
    }

    func testCompleteOutputAndFinalLineWithoutNewline() throws {
        XCTAssertEqual(try run("normal"), "usage: 정상\n")
        XCTAssertEqual(try run("tail", match: { $0.contains("\"id\":1") }), "{\"id\":1}")
        XCTAssertNil(try run("tail", match: { $0.contains("\"id\":2") }))
    }

    func testMatchedServerIsKilledAndSplitUTF8Survives() throws {
        XCTAssertEqual(try run("match", match: { $0.contains("\"id\":1") }), "{\"id\":1,\"text\":\"가\"}")
    }

    func testRepeatedTimeoutsReapStubbornProcesses() throws {
        for _ in 0..<3 {
            XCTAssertNil(try run("stubborn", timeout: stubbornTimeout))
        }
    }

    func testClosingStdoutDoesNotLeaveProcessRunning() throws {
        XCTAssertEqual(try run("closed-output"), "")
    }

    func testOutputFloodIsBounded() throws {
        XCTAssertNil(try run("flood", timeout: 5))
        XCTAssertNil(try run("flood", timeout: 5, match: { _ in false }))
    }

    func testInputAndOutputCanProgressTogether() throws {
        let payload = String(repeating: "a", count: 256 * 1024)
        XCTAssertEqual(try run("echo", stdin: [payload]), payload + "\n")
        // More than a pipe can hold, with a child that never reads it.
        XCTAssertNil(try run("stubborn", stdin: [payload], timeout: stubbornTimeout))
    }

    func testMissingExecutableReturnsNil() {
        XCTAssertNil(CommandRunner.run(URL(fileURLWithPath: "/nonexistent/usage-overlay-cli"), [], timeout: 0.1))
    }
}
