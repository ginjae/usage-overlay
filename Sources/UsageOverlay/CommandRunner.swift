import Foundation
import Darwin

/// CLI를 찾아 실행하고 표준출력을 돌려준다. 사용량은 전부 여기를 거쳐 들어온다.
///
/// Finder나 로그인 항목으로 띄운 앱의 PATH에는 `/usr/bin:/bin:/usr/sbin:/sbin` 밖에 없다.
/// 터미널에서 되던 `claude` / `codex` 가 그대로는 안 잡히므로 설치 위치를 직접 훑는다.
enum CommandRunner {
    /// 한 번 찾은 실행 파일. 갱신할 때마다 디렉터리를 훑지 않도록 들고 있는다.
    private static var cache: [String: URL] = [:]
    private static let lock = NSLock()

    // MARK: - 찾기

    /// 이름으로 실행 파일을 찾는다. 없으면 nil.
    static func executable(_ name: String) -> URL? {
        // 직접 지정한 경로가 먼저다. 설정 창에서 바꾸면 캐시를 거치지 않고 다음 조회부터 바로 따른다.
        if let override = Settings.shared.path(for: name),
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        lock.lock()
        defer { lock.unlock() }
        // 지웠다 다시 깔면 경로가 바뀔 수 있어 캐시도 존재 여부를 확인한다.
        if let cached = cache[name], FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }
        guard let found = search(name) else { return nil }
        cache[name] = found
        return found
    }

    /// 여기 없는 곳에 깔았다면 설정 창 General 에서 경로를 직접 지정한다.
    private static func search(_ name: String) -> URL? {
        searchDirectories
            .map { $0.appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// 두 CLI가 실제로 깔리는 자리들. 앞에서부터 먼저 찾은 것을 쓴다.
    private static var searchDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var directories = [
            home.appendingPathComponent(".local/bin"),      // 두 CLI의 기본 설치 위치
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin"),
            home.appendingPathComponent(".claude/local"),   // claude 구버전 로컬 설치
            home.appendingPathComponent(".bun/bin"),
            home.appendingPathComponent(".volta/bin"),
            home.appendingPathComponent(".cargo/bin"),
            home.appendingPathComponent(".npm-global/bin"),
        ]
        // nvm은 노드 버전마다 bin이 따로라 경로가 고정되지 않는다.
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(at: nvm,
                                                                    includingPropertiesForKeys: nil)) ?? []
        directories += versions.map { $0.appendingPathComponent("bin") }
        return directories
    }

    // MARK: - 실행

    /// 실행해서 표준출력을 읽는다.
    ///
    /// - Parameters:
    ///   - stdin: 넘겨줄 입력 줄들. app-server처럼 응답을 기다려야 하는 경우가 있어 파이프를 바로 닫지 않는다.
    ///   - match: 한 줄씩 검사해 true면 거기서 멈추고 그 줄만 돌려준다.
    ///            nil이면 프로세스가 끝날 때까지 모아서 전부 돌려준다.
    /// - Returns: 출력. 시간 안에 원하는 걸 못 받으면 nil.
    static func run(_ executable: URL,
                    _ arguments: [String],
                    stdin: [String] = [],
                    timeout: TimeInterval,
                    until match: ((String) -> Bool)? = nil) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment(for: executable)
        // 홈에서 돌린다. 앱 번들 안이 작업 디렉터리면 CLI가 그걸 프로젝트로 오해한다.
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

        let output = Pipe()
        let input = Pipe()
        defer {
            for handle in [output.fileHandleForReading, output.fileHandleForWriting,
                           input.fileHandleForReading, input.fileHandleForWriting] {
                try? handle.close()
            }
        }
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice  // 안 읽을 파이프를 물리면 가득 차서 멈춘다

        let reader = output.fileHandleForReading.fileDescriptor
        let writer = input.fileHandleForWriting.fileDescriptor
        // poll이 준비됐다고 해도 큰 읽기/쓰기가 timeout을 넘겨 막히지 않게 한다.
        guard fcntl(reader, F_SETFL, O_NONBLOCK) != -1,
              fcntl(writer, F_SETFL, O_NONBLOCK) != -1,
              fcntl(writer, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        defer {
            try? input.fileHandleForWriting.close()
            // 응답을 받았어도 app-server는 살아 있다. 종료를 무시하는 CLI도 다음 조회에 남기지 않는다.
            if process.isRunning {
                process.terminate()
                if exited.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            process.waitUntilExit()
        }

        if stdin.isEmpty {
            try? input.fileHandleForWriting.close()
        }
        let payload = stdin.isEmpty ? Data() : Data((stdin.joined(separator: "\n") + "\n").utf8)
        return readOutput(reader: reader, writer: writer, payload: payload, timeout: timeout, match: match)
    }

    /// 호출한 조회 큐에서 I/O 준비를 기다린다. 별도 읽기 스레드나 timeout 뒤에 남는 콜백이 없다.
    private static func readOutput(reader: Int32, writer: Int32, payload: Data,
                                   timeout: TimeInterval, match: ((String) -> Bool)?) -> String? {
        let deadline = (DispatchTime.now() + timeout).uptimeNanoseconds
        // 사용량 응답은 몇 KB다. 잘못된 CLI가 출력을 쏟아도 메모리가 계속 늘지 않게 한다.
        let outputLimit = 1024 * 1024
        var received = 0
        var sent = 0
        var buffered = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            let milliseconds = Int32(min((deadline - now) / 1_000_000 + 1, UInt64(Int32.max)))
            var descriptors = [
                pollfd(fd: reader, events: Int16(POLLIN), revents: 0),
                pollfd(fd: sent < payload.count ? writer : -1, events: Int16(POLLOUT), revents: 0),
            ]
            let ready = poll(&descriptors, nfds_t(descriptors.count), milliseconds)
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { return nil }

            if descriptors[0].revents & Int16(POLLIN | POLLHUP) != 0 {
                let count = chunk.withUnsafeMutableBytes { Darwin.read(reader, $0.baseAddress!, $0.count) }
                if count == 0 {
                    let tail = String(decoding: buffered, as: UTF8.self)
                    if let match { return match(tail) ? tail : nil }
                    return tail
                }
                if count < 0 {
                    if errno != EINTR && errno != EAGAIN { return nil }
                } else {
                    received += count
                    guard received <= outputLimit else { return nil }
                    buffered.append(contentsOf: chunk.prefix(count))
                    if let match {
                        // 바이트 단위로 줄을 모아야 UTF-8 문자가 read 경계에서 잘려도 보존된다.
                        while let newline = buffered.firstIndex(of: 10) {
                            let line = String(decoding: buffered[..<newline], as: UTF8.self)
                            if match(line) { return line }
                            buffered.removeSubrange(...newline)
                        }
                    }
                }
            } else if descriptors[0].revents & Int16(POLLERR | POLLNVAL) != 0 {
                return nil
            }

            if descriptors[1].revents & Int16(POLLOUT) != 0 {
                let count = payload.withUnsafeBytes {
                    Darwin.write(writer, $0.baseAddress!.advanced(by: sent), $0.count - sent)
                }
                if count > 0 {
                    sent += count
                } else if count < 0, errno != EINTR && errno != EAGAIN {
                    return nil
                }
            } else if descriptors[1].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
                return nil
            }
        }
    }

    private static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // USER 가 비어 있으면 `claude -p "/usage"` 가 사용량을 한 줄도 안 찍는다.
        // launchd 로 뜬 앱에는 없을 수 있어 직접 채운다. 조용히 빈 화면이 되는 함정이라 여기 남긴다.
        environment["USER"] = NSUserName()
        environment["HOME"] = NSHomeDirectory()
        // CLI가 자기 형제 실행 파일을 다시 찾는 경우가 있어 자기 자리를 PATH 앞에 넣어 준다.
        let own = executable.deletingLastPathComponent().path
        environment["PATH"] = own + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return environment
    }
}
