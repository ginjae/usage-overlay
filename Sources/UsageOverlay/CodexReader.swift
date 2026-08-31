import Foundation

/// Codex CLI가 세션 롤아웃(`~/.codex/sessions/**/rollout-*.jsonl`)에 남기는
/// 마지막 `token_count` 이벤트의 `rate_limits` 를 읽는다.
final class CodexReader {
    private struct Record {
        let timestamp: Date
        let gauges: [Gauge]
        let plan: String?
    }

    private struct CacheEntry {
        let mtime: Date
        let record: Record?
    }

    private let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
    /// 파일별 스캔 결과 캐시. mtime이 그대로면 다시 읽지 않는다.
    private var cache: [String: CacheEntry] = [:]
    /// 최근 파일 몇 개까지 훑을지. 마지막 세션에 token_count가 없을 수 있어 여유를 둔다.
    private let candidateCount = 12
    /// 파일 끝에서 읽어 들일 크기.
    private let tailBytes: UInt64 = 512 * 1024

    func read() -> ProviderUsage? {
        let files = recentFiles()
        guard !files.isEmpty else {
            return ProviderUsage(name: "Codex", gauges: [], plan: nil, updatedAt: nil,
                                 note: "No session history")
        }

        var best: Record?
        var fresh: [String: CacheEntry] = [:]
        for (url, mtime) in files {
            let key = url.path
            let entry: CacheEntry
            if let cached = cache[key], cached.mtime == mtime {
                entry = cached
            } else {
                entry = CacheEntry(mtime: mtime, record: scan(url))
            }
            fresh[key] = entry
            if let record = entry.record, record.timestamp > (best?.timestamp ?? .distantPast) {
                best = record
            }
        }
        cache = fresh

        guard let best else {
            return ProviderUsage(name: "Codex", gauges: [], plan: nil, updatedAt: nil,
                                 note: "No limits found — run Codex once")
        }
        return ProviderUsage(name: "Codex", gauges: best.gauges, plan: best.plan,
                             updatedAt: best.timestamp, note: nil)
    }

    /// 수정 시각 기준 최신 롤아웃 파일들.
    private func recentFiles() -> [(URL, Date)] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: root,
                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            files.append((url, mtime))
        }
        files.sort { $0.1 > $1.1 }
        return Array(files.prefix(candidateCount))
    }

    /// 파일 끝부분에서 마지막 rate_limits 이벤트를 찾는다.
    private func scan(_ url: URL) -> Record? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        // 잘린 첫 줄은 JSON 파싱에서 자연히 걸러진다.
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"rate_limits\"") else { continue }
            if let record = parse(line: line) { return record }
        }
        return nil
    }

    private func parse(line: Substring) -> Record? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = event["payload"] as? [String: Any],
              let limits = payload["rate_limits"] else { return nil }

        // 웹 응답과 필드 이름만 다를 뿐 같은 모양이라 스캐너가 그대로 처리한다.
        let gauges = UsageScan.normalize(UsageScan.scan(limits))
        guard !gauges.isEmpty else { return nil }

        return Record(timestamp: Parse.date(event["timestamp"]) ?? .distantPast,
                      gauges: gauges,
                      plan: UsageScan.plan(in: limits))
    }
}
