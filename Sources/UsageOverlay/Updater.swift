import AppKit
import CryptoKit
import Foundation

/// 세 자리 버전. 태그(`v0.2.0`)와 Info.plist(`0.2.0`)를 같은 자로 잰다.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let numbers: [Int]
    let description: String

    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            // 숫자만 받는다. `1.2.3-beta` 같은 꼬리표가 붙으면 비교할 자신이 없으니 아예 모른 척한다.
            guard part.allSatisfy(\.isNumber), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.numbers = numbers
        self.description = body
    }

    /// 자릿수가 다를 수 있어 짧은 쪽을 0으로 채워 비교한다. `1.2` 와 `1.2.0` 은 같은 버전이다.
    private static func compare(_ lhs: Self, _ rhs: Self) -> ComparisonResult {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func < (lhs: Self, rhs: Self) -> Bool { compare(lhs, rhs) == .orderedAscending }
    static func == (lhs: Self, rhs: Self) -> Bool { compare(lhs, rhs) == .orderedSame }
}

/// 실패는 화면에 그대로 띄울 한 줄로 다룬다. 종류별로 갈라 볼 일이 없다.
struct UpdateFailure: Error, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// GitHub 릴리스 하나에서 우리가 쓰는 것만.
struct Release: Sendable {
    let version: AppVersion
    let notes: String
    let archive: URL
    /// 릴리스 워크플로가 zip 옆에 같이 올리는 `.sha256`. 옛 릴리스에는 없을 수 있다.
    let checksum: URL?
    let page: URL

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let body: String?
        let htmlUrl: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    /// 릴리스 API 응답에서 설치할 수 있는 릴리스만 뽑는다. 아니면 nil.
    static func parse(_ data: Data) -> Release? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tagName),
              // 자산 이름은 릴리스 워크플로가 정한다. 앱은 zip 하나, 그 옆에 체크섬 한 줄.
              let archive = payload.assets.first(where: {
                  $0.name.hasSuffix(".zip") && isGitHub($0.browserDownloadUrl)
              })
        else { return nil }
        let checksum = payload.assets.first {
            $0.name == archive.name + ".sha256" && isGitHub($0.browserDownloadUrl)
        }
        return Release(version: version,
                       notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                       archive: archive.browserDownloadUrl,
                       checksum: checksum?.browserDownloadUrl,
                       page: payload.htmlUrl)
    }

    /// 실행 파일을 끌어올 주소는 GitHub 것만 받는다. 응답이 어떻게 생겼든 남의 서버는 안 본다.
    private static func isGitHub(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com"
            || host.hasSuffix(".github.com")
            || host.hasSuffix(".githubusercontent.com")
    }
}

/// 새 버전을 GitHub 릴리스에서 찾아 받아 깔고, 앱을 다시 띄운다.
///
/// 앱이 스스로 서버에 말을 거는 자리는 여기뿐이다. 사용량은 여전히 CLI가 자기 자격증명으로 가져오고,
/// 이 파일만 공개 릴리스 정보를 익명으로 읽는다. 보내는 값은 없다.
///
/// 설치는 앱이 살아 있는 동안 할 수 있는 일(내려받기 · 검증 · 풀기 · 목적지 옆에 놓기)을 먼저 끝내고,
/// 종료한 뒤에 남는 셸이 이름만 바꿔 끼운다. 권한이 없거나 파일이 깨졌으면 앱을 끄기 전에 알 수 있고,
/// 정작 바꿔치기하는 순간은 같은 볼륨 안의 mv 두 번이라 실패할 구석이 거의 없다.
///
/// 공개 함수는 모두 메인에서 부른다. 오래 걸리는 일만 조회용 큐로 넘겼다가 메인으로 돌아온다.
final class Updater {
    enum Status { case idle, checking, downloading }
    enum Outcome { case found(Release), upToDate, failed(String) }

    private static let latestRelease =
        URL(string: "https://api.github.com/repos/ginjae/usage-overlay/releases/latest")!
    static let releasesPage =
        URL(string: "https://github.com/ginjae/usage-overlay/releases/latest")!
    /// 하루 한 번. 익명 API는 시간당 60번까지고, 릴리스는 그보다 훨씬 뜸하게 나온다.
    private static let checkInterval: TimeInterval = 86400
    /// 압축을 푸는 자리의 이름. 도중에 죽어 남은 폴더를 알아보고 지우려고 접두사를 고정한다.
    private static let stagePrefix = ".usage-overlay-update-"
    /// 내려받기는 사용량 조회보다 오래 걸린다. 회선이 느려도 끊기지 않게 넉넉히 준다.
    private static let downloadTimeout: TimeInterval = 300

    private(set) var status: Status = .idle
    /// 검사 결과를 넘기는 자리. 알림창을 띄우는 일은 AppDelegate가 한다.
    var onCheckFinished: ((Outcome, _ userInitiated: Bool) -> Void)?

    /// 실행 중인 버전. 번들이 아니면(=`swift run`) 알 수 없다.
    let currentVersion: AppVersion? =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)

    private var timer: Timer?
    private let queue = DispatchQueue(label: "usage-overlay.updater", qos: .utility)
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = downloadTimeout
        // GitHub API는 User-Agent 없는 요청을 거절한다. 앱 이름만 보내고 그 밖엔 아무것도 안 붙인다.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "usage-overlay",
            "Accept": "application/vnd.github+json",
        ]
        return URLSession(configuration: configuration)
    }()

    /// 스스로 갱신할 수 없는 상태면 그 이유. 갱신할 수 있으면 nil.
    var unavailableReason: String? {
        let bundle = Bundle.main.bundleURL
        guard currentVersion != nil, bundle.pathExtension == "app" else {
            return "This build can't update itself. Download the app from the releases page instead."
        }
        // 검역된 자리에서 열면 macOS가 읽기 전용 사본으로 돌린다. 거기서 바꿔 봐야 원본은 그대로다.
        guard !bundle.path.contains("/AppTranslocation/") else {
            return "macOS is running Usage Overlay from a read-only copy. "
                + "Move the app to /Applications, open it again, and check once more."
        }
        return nil
    }

    func start() {
        removeStaleStages()
        scheduleCheck()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 자동 검사를 껐다 켰을 때.
    func settingsChanged() { scheduleCheck() }

    /// 마지막 검사 시각을 기준으로 예약한다. 껐다 켜도 하루 한 번을 넘지 않는다.
    private func scheduleCheck() {
        timer?.invalidate()
        timer = nil
        guard Prefs.autoUpdate, unavailableReason == nil else { return }
        let due = (Prefs.lastUpdateCheck ?? .distantPast).addingTimeInterval(Self.checkInterval)
        // 뜨자마자 물으면 첫 사용량 조회와 겹친다. 메뉴바가 자리를 잡은 뒤로 조금 미룬다.
        let delay = max(15, due.timeIntervalSinceNow)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        // 여유는 간격에 맞춰 준다. 15초짜리에 60초를 주면 첫 검사가 하염없이 밀린다.
        timer.tolerance = min(60, delay * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 검사

    func check(userInitiated: Bool) {
        guard case .idle = status else { return }
        if let reason = unavailableReason {
            onCheckFinished?(.failed(reason), userInitiated)
            return
        }
        status = .checking
        var request = URLRequest(url: Self.latestRelease)
        // 릴리스가 났는데 캐시된 대답을 다시 읽으면 갱신을 통째로 놓친다.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let current = currentVersion
        session.dataTask(with: request) { [weak self] data, response, error in
            let outcome = Self.outcome(data: data, response: response, error: error, current: current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = .idle
                Prefs.lastUpdateCheck = Date()
                self.scheduleCheck()
                self.report(outcome, userInitiated: userInitiated)
            }
        }.resume()
    }

    private static func outcome(data: Data?, response: URLResponse?, error: Error?,
                                current: AppVersion?) -> Outcome {
        if let error { return .failed(error.localizedDescription) }
        guard let data, let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return .failed("GitHub answered \(code) instead of the latest release.")
        }
        guard let release = Release.parse(data) else {
            return .failed("Couldn't read the latest release.")
        }
        guard let current else { return .failed("This build doesn't say which version it is.") }
        return release.version > current ? .found(release) : .upToDate
    }

    /// 자동 검사에서는 건너뛰기로 접어 둔 버전을 다시 꺼내지 않는다. 직접 눌렀을 땐 보여 준다.
    private func report(_ outcome: Outcome, userInitiated: Bool) {
        if case .found(let release) = outcome,
           !userInitiated, Prefs.skippedVersion == release.version.description {
            onCheckFinished?(.upToDate, userInitiated)
            return
        }
        onCheckFinished?(outcome, userInitiated)
    }

    // MARK: - 설치

    /// 받아서 검증하고 목적지 옆에 놓은 뒤 앱을 끈다. 성공하면 completion은 불리지 않는다.
    /// - Parameter completion: 실패 사유 한 줄. 알림창은 부른 쪽에서 띄운다.
    func install(_ release: Release, completion: @escaping (String) -> Void) {
        guard case .idle = status else { return }
        if let reason = unavailableReason {
            completion(reason)
            return
        }
        let destination = Bundle.main.bundleURL
        status = .downloading
        let session = self.session
        queue.async { [weak self] in
            let staged = Result { try Self.stage(release, beside: destination, using: session) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = .idle
                // 받는 동안 자동 검사 시각이 지나갔을 수 있다. 여기서 끝났으면 다음 검사를 다시 잡는다.
                defer { self.scheduleCheck() }
                do {
                    try self.swap(try staged.get(), into: destination)
                    NSApp.terminate(nil)  // 여기서 끝. 남은 셸이 바꿔 끼우고 새 번들을 띄운다.
                } catch {
                    completion((error as? UpdateFailure)?.message ?? error.localizedDescription)
                }
            }
        }
    }

    /// 내려받아 검증하고 목적지 옆에 풀어 둔다. 여기까지는 쓰던 앱을 건드리지 않는다.
    private static func stage(_ release: Release, beside destination: URL,
                              using session: URLSession) throws -> URL {
        let archive = try download(release.archive, using: session)
        let checksum = release.checksum.flatMap { try? download($0, using: session) }
        defer {
            try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
            if let checksum {
                try? FileManager.default.removeItem(at: checksum.deletingLastPathComponent())
            }
        }
        try verify(archive, against: checksum)
        let app = try unpack(archive, beside: destination)
        do {
            try validate(app, expecting: release)
        } catch {
            try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
            throw error
        }
        return app
    }

    /// 파일 하나를 우리 임시 폴더로 받는다. 조회 큐에서만 부르므로 끝날 때까지 기다린다.
    private static func download(_ url: URL, using session: URLSession) throws -> URL {
        let done = DispatchSemaphore(value: 0)
        var located: URL?
        // 핸들러가 돌아가는 순간 URLSession이 준 자리는 사라진다. 그 안에서 옮겨 둔다.
        let task = session.downloadTask(with: url) { temporary, response, _ in
            defer { done.signal() }
            guard let temporary, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            located = try? move(temporary, named: url.lastPathComponent)
        }
        task.resume()
        guard done.wait(timeout: .now() + downloadTimeout) == .success, let located else {
            task.cancel()
            throw UpdateFailure("Couldn't download \(url.lastPathComponent).")
        }
        return located
    }

    private static func move(_ file: URL, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-overlay-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    /// 릴리스가 같이 올린 체크섬과 맞춰 본다. 오다 깨진 파일을 앱을 끄기 전에 잡는 자리다.
    /// 전송 자체는 TLS가 지키므로, 체크섬이 아예 없는 옛 릴리스는 그냥 넘어간다.
    private static func verify(_ archive: URL, against checksumFile: URL?) throws {
        guard let checksumFile,
              let text = try? String(contentsOf: checksumFile, encoding: .utf8),
              let expected = text.split(whereSeparator: \.isWhitespace).first?.lowercased(),
              expected.count == 64
        else { return }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw UpdateFailure("The download didn't match its published checksum. Nothing was changed.")
        }
    }

    /// 목적지와 같은 폴더에 푼다. 마지막에 남는 일이 같은 볼륨 안의 이름 바꾸기가 되도록.
    private static func unpack(_ archive: URL, beside destination: URL) throws -> URL {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard manager.isWritableFile(atPath: parent.path) else {
            throw UpdateFailure("Usage Overlay can't write to \(parent.path). "
                + "Move the app to /Applications, or download the update yourself.")
        }
        let stage = parent.appendingPathComponent(stagePrefix + UUID().uuidString)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true)
        // ditto는 서명이 걸려 있는 확장 속성까지 그대로 푼다. unzip은 그러지 못한다.
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, stage.path]
        ditto.standardOutput = FileHandle.nullDevice
        ditto.standardError = FileHandle.nullDevice
        do {
            try ditto.run()
        } catch {
            try? manager.removeItem(at: stage)
            throw UpdateFailure("Couldn't unpack the update.")
        }
        ditto.waitUntilExit()
        let unpacked = (try? manager.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)) ?? []
        guard ditto.terminationStatus == 0,
              let app = unpacked.first(where: { $0.pathExtension == "app" })
        else {
            try? manager.removeItem(at: stage)
            throw UpdateFailure("The downloaded archive didn't contain the app.")
        }
        return app
    }

    /// 푼 번들이 우리 앱이 맞고 광고한 버전이 맞는지. 자산이 뒤바뀐 릴리스를 여기서 거른다.
    private static func validate(_ app: URL, expecting release: Release) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let shortVersion = info?["CFBundleShortVersionString"] as? String,
              AppVersion(shortVersion) == release.version
        else {
            throw UpdateFailure("The downloaded app didn't look like Usage Overlay \(release.version).")
        }
    }

    /// 종료한 뒤에 남아 번들을 바꿔 끼우고 앱을 다시 띄우는 셸.
    /// 앱이 살아 있는 동안은 아무것도 건드리지 않고, 옮기다 실패하면 쓰던 번들을 되돌린다.
    private static let swapScript = """
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    pid=$1; app=$2; new=$3; stage=$(dirname "$new")
    waited=0
    while [ $waited -lt 300 ] && kill -0 "$pid" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
    done
    previous="$stage/previous"
    mv "$app" "$previous" || exit 1
    mv "$new" "$app" || { mv "$previous" "$app"; exit 1; }
    rm -rf "$stage"
    open "$app"
    """

    private func swap(_ staged: URL, into destination: URL) throws {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 경로에 공백이 있다("Usage Overlay.app"). 스크립트에 끼워 넣지 않고 인자로 넘긴다.
        shell.arguments = ["-c", Self.swapScript, "usage-overlay-update",
                           String(ProcessInfo.processInfo.processIdentifier),
                           destination.path, staged.path]
        shell.standardOutput = FileHandle.nullDevice
        shell.standardError = FileHandle.nullDevice
        do {
            try shell.run()
        } catch {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            throw UpdateFailure("Couldn't start the installer.")
        }
    }

    /// 설치 도중에 죽어 남은 폴더를 치운다. 우리 접두사를 가진 것만 본다.
    private func removeStaleStages() {
        guard unavailableReason == nil else { return }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(at: parent,
                                                                   includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix(Self.stagePrefix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }
}
