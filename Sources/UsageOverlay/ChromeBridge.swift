import AppKit
import Foundation

/// AppleScript로 사용자의 크롬을 조작한다.
///
/// 크롬 136부터 기본 프로필에서는 `--remote-debugging-port` 가 무시되므로
/// (별도 user-data-dir을 쓰면 로그인 세션을 잃는다) DevTools 프로토콜 대신
/// AppleScript 경로를 쓴다. 대신 크롬의
/// `보기 > 개발자용 > Apple 이벤트의 JavaScript 허용` 이 켜져 있어야 한다.
///
/// 실패는 전부 nil로 돌려준다. 호출부가 할 수 있는 일이 "이번 폴링을 건너뛰고
/// 로컬 캐시를 쓴다" 하나뿐이라 원인을 구분할 이유가 없다. 정말 중요한 두 가지
/// 전제(크롬이 떠 있는지, JS 실행이 켜져 있는지)는 `isRunning` 과
/// `javaScriptEnabled()` 로 미리 확인한다.
enum ChromeBridge {
    /// 크롬의 탭 id는 정수 리터럴과 `is` 비교가 성립하지 않는다
    /// (`as text` 하면 같은 값인데도 `(id of t) is 1546029274` 는 false).
    /// 그래서 조회는 전부 문자열로 비교한다.
    struct Tab {
        let tabID: Int
    }

    private static var probe: (at: Date, ok: Bool)?

    /// TCC 프롬프트 없이 즉시 확인할 수 있고, 크롬이 꺼져 있을 때
    /// AppleScript가 크롬을 실행시켜 버리는 것도 막아 준다.
    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.google.Chrome" }
    }

    /// JS 실행이 막혀 있으면 탭을 만들어 봐야 읽을 수 없으므로, 탭을 열기 전에 먼저 확인한다.
    /// 사용자가 크롬 메뉴에서 토글을 켜면 다음 확인 때 자동으로 살아난다.
    static func javaScriptEnabled() -> Bool {
        if let probe, Date().timeIntervalSince(probe.at) < 60 { return probe.ok }
        let script = "tell application \"Google Chrome\"\n"
            + "  if (count of windows) is 0 then return \"nowindow\"\n"
            + "  return (execute active tab of front window javascript \"1\")\n"
            + "end tell"
        let ok = run(script) != nil
        probe = (Date(), ok)
        return ok
    }

    /// 쓸 탭을 확보한다. 이미 있으면 그대로 쓰고, 없을 때만 `mayCreate` 를 보고 만든다.
    /// 살아 있는지 확인하면서 창의 숨김 상태도 같이 맞춰 두므로 폴링당 osascript 호출이 하나로 끝난다.
    /// 반환값의 `created` 가 true면 이번에 새로 만든 것이다.
    static func ensureTab(existing: Tab?, url: String, origin: String,
                          hidden: Bool, mayCreate: Bool) -> (tab: Tab, created: Bool)? {
        if let existing, checkAndApply(existing, origin: origin, hidden: hidden) {
            return (existing, false)
        }
        // 저장해 둔 탭이 죽었을 때, 우리가 쓰는 URL과 **정확히** 같은 탭이 이미 있으면 넘겨받는다.
        // 사용자가 손으로 열어 둔 탭을 뺏지 않도록 오리진이 아니라 해시까지 포함해 비교한다.
        if let adopted = findTab(exactURL: url) {
            _ = checkAndApply(adopted, origin: origin, hidden: hidden)
            return (adopted, false)
        }
        guard mayCreate, let made = makeTab(url: url, hidden: hidden) else { return nil }
        return (made, true)
    }

    /// 탭이 살아 있고 같은 오리진이면 true. 겸사겸사 창의 숨김 상태를 요청한 값으로 맞춘다.
    private static func checkAndApply(_ tab: Tab, origin: String, hidden: Bool) -> Bool {
        let script = "tell application \"Google Chrome\"\n"
            + "  repeat with w in windows\n"
            + "    repeat with t in tabs of w\n"
            + "      if ((id of t) as text) is \"\(tab.tabID)\" then\n"
            + "        if (URL of t) starts with \"\(origin)\" then\n"
            + "          if \(hidden) then\n"
            // 최소화된 창은 visible 이 false로 읽히므로 먼저 최소화를 풀어야 진짜로 숨길 수 있다
            + "            if (minimized of w) is true then set minimized of w to false\n"
            // 최소화 해제는 애니메이션이라 같은 스크립트 안에서 visible 이 아직 false로 읽힌다.
            // 조건을 걸면 숨김이 한 번 걸러지므로 그냥 매번 설정한다 (이미 같은 값이면 무시된다).
            + "            set visible of w to false\n"
            + "          else\n"
            + "            set visible of w to true\n"
            + "          end if\n"
            + "          return \"yes\"\n"
            + "        end if\n"
            + "        return \"no\"\n"
            + "      end if\n"
            + "    end repeat\n"
            + "  end repeat\n"
            + "  return \"no\"\n"
            + "end tell"
        return run(script)?.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }

    private static func findTab(exactURL url: String) -> Tab? {
        let script = "tell application \"Google Chrome\"\n"
            + "  repeat with w in windows\n"
            + "    repeat with t in tabs of w\n"
            + "      if (URL of t) is \"\(url)\" then return (id of t) as text\n"
            + "    end repeat\n"
            + "  end repeat\n"
            + "  return \"none\"\n"
            + "end tell"
        return run(script).flatMap(parseTab)
    }

    /// 사용자의 작업 창을 어지르지 않도록 전용 창을 새로 만든다.
    ///
    /// `visible of w` 를 false로 두면 최소화와 달리 Dock에도 흔적이 남지 않고
    /// 화면에도 그려지지 않는다. 그 상태에서도 탭은 살아 있어 JS와 fetch가 정상 동작한다
    /// (`document.hidden` 이 true가 될 뿐이다).
    private static func makeTab(url: String, hidden: Bool) -> Tab? {
        let script = "tell application \"Google Chrome\"\n"
            + "  set w to make new window\n"
            + "  set URL of active tab of w to \"\(url)\"\n"
            + "  set tabID to (id of active tab of w) as text\n"
            + (hidden ? "  set visible of w to false\n" : "")
            + "  return tabID\n"
            + "end tell"
        return run(script).flatMap(parseTab)
    }

    /// 탭 안에서 JS를 실행하고 문자열 결과를 돌려받는다.
    static func evaluate(_ javaScript: String, in tab: Tab) -> String? {
        let script = "tell application \"Google Chrome\"\n"
            + "  repeat with w in windows\n"
            + "    repeat with t in tabs of w\n"
            + "      if ((id of t) as text) is \"\(tab.tabID)\" then\n"
            + "        return (execute t javascript \"\(escapeForAppleScript(javaScript))\")\n"
            + "      end if\n"
            + "    end repeat\n"
            + "  end repeat\n"
            + "  return \"__NO_TAB__\"\n"
            + "end tell"
        guard let output = run(script), !output.contains("__NO_TAB__") else { return nil }
        return output
    }

    static func closeTab(_ tab: Tab) {
        let script = "tell application \"Google Chrome\"\n"
            + "  repeat with w in windows\n"
            + "    repeat with t in tabs of w\n"
            + "      if ((id of t) as text) is \"\(tab.tabID)\" then\n"
            + "        close t\n"
            + "        return \"ok\"\n"
            + "      end if\n"
            + "    end repeat\n"
            + "  end repeat\n"
            + "  return \"gone\"\n"
            + "end tell"
        _ = run(script)
    }

    private static func parseTab(_ output: String) -> Tab? {
        guard let tabID = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Tab(tabID: tabID)
    }

    // MARK: - osascript 실행

    private static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        guard (try? process.run()) != nil else { return nil }
        if let data = script.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
        }
        try? inPipe.fileHandleForWriting.close()

        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()  // 파이프가 차서 막히지 않도록 비운다
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// AppleScript 문자열 리터럴 안에 JS를 넣기 위한 이스케이프.
    private static func escapeForAppleScript(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
