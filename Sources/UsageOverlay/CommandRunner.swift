import Foundation

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

    private static func search(_ name: String) -> URL? {
        // 여기 없는 곳에 깔았을 때의 탈출구. 재빌드 없이 지정할 수 있다.
        //   defaults write io.github.ginjae.usage-overlay path.claude '/opt/homebrew/bin/claude'
        if let override = Prefs.path(for: name),
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        return searchDirectories
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
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice  // 안 읽을 파이프를 물리면 가득 차서 멈춘다

        do {
            try process.run()
        } catch {
            return nil
        }

        let reader = output.fileHandleForReading
        let done = DispatchSemaphore(value: 0)
        var collected = Data()
        var matched: String?

        // availableData 는 블로킹이라 별도 스레드에서 돌린다.
        // 여기서 쓴 값은 done 을 지나서만 읽으므로 그 순서가 곧 동기화다.
        Thread.detachNewThread {
            var pending = ""
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }  // EOF
                collected.append(chunk)
                guard let match else { continue }
                pending += String(decoding: chunk, as: UTF8.self)
                var lines = pending.components(separatedBy: "\n")
                pending = lines.removeLast()  // 마지막 조각은 아직 줄이 안 끝났을 수 있다
                if let hit = lines.first(where: match) {
                    matched = hit
                    break
                }
            }
            done.signal()
        }

        if stdin.isEmpty {
            try? input.fileHandleForWriting.close()
        } else {
            let payload = Data((stdin.joined(separator: "\n") + "\n").utf8)
            try? input.fileHandleForWriting.write(contentsOf: payload)
        }

        let finished = done.wait(timeout: .now() + timeout) == .success
        // 원하는 줄을 이미 받았어도 서버형 프로세스는 스스로 끝나지 않는다.
        if !finished || match != nil { process.terminate() }
        // 이미 신호가 왔으면(finished) 읽기 스레드는 끝난 뒤다. 여기서 또 기다리면 그대로 2초를 버린다.
        if !finished { _ = done.wait(timeout: .now() + 2) }
        try? input.fileHandleForWriting.close()

        if match != nil { return matched }
        return finished ? String(decoding: collected, as: UTF8.self) : nil
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
