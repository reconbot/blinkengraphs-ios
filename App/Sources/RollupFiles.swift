import BlinkengraphsCore
import Foundation

/// Rollups on disk: one JSON Lines file per UTC day in Application Support, appended a minute
/// at a time; days older than `rollup_days` are deleted. Off the main actor.
actor RollupFiles {
    private let directory: URL
    private let keepDays: Int
    private let encoder = JSONEncoder()

    init(keepDays: Int) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("rollups", isDirectory: true)
        self.keepDays = keepDays
    }

    func append(_ minutes: [StoredMinute]) {
        guard !minutes.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (day, group) in Dictionary(grouping: minutes, by: { Self.day($0.minute) }) {
            var data = Data()
            for m in group {
                guard let line = try? encoder.encode(m) else { continue }
                data.append(line)
                data.append(0x0A)
            }
            let url = file(day)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Every stored minute still within `rollup_days`, after deleting older days.
    func load(now: Date = .now) -> [StoredMinute] {
        let today = Self.day(Int(now.timeIntervalSince1970 / 60))
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var out: [StoredMinute] = []
        for url in files where url.pathExtension == "jsonl" {
            guard let day = Int(url.deletingPathExtension().lastPathComponent) else { continue }
            if day <= today - keepDays {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // A line cut short by a crash is skipped, not fatal.
            out += text.split(separator: "\n").compactMap { try? decoder.decode(StoredMinute.self, from: Data($0.utf8)) }
        }
        return out
    }

    private func file(_ day: Int) -> URL { directory.appendingPathComponent("\(day).jsonl") }

    /// Days since 1970, UTC.
    private static func day(_ minute: Int) -> Int { minute / (24 * 60) }
}

/// The Rollups the Monitor records into and the graphs read, shared by reference so a
/// refresh doesn't copy a week of minutes.
@MainActor
final class RollupHistory {
    var rollups: Rollups
    init(keepDays: Int) { rollups = Rollups(keepDays: keepDays) }

    struct GraphKey: Hashable {
        var range: String, aggregate: Aggregate, link: Link, probe: Probe
    }
    struct Graph { var points: [GraphPoint]; var summary: Double?; var loss: Double }
    /// Long-range graphs change only as minutes pass, but a 7d one merges 10,080 Minutes per line:
    /// computed once per minute, not once per refresh.
    private var cache: [GraphKey: Graph] = [:]
    private var cachedMinute = Int.min

    func graph(_ key: GraphKey, minute: Int, compute: () -> Graph) -> Graph {
        if minute != cachedMinute {
            cache = [:]
            cachedMinute = minute
        }
        if let hit = cache[key] { return hit }
        let graph = compute()
        cache[key] = graph
        return graph
    }
}
