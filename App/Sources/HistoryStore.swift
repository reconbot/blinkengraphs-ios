import BlinkengraphsCore
import Foundation

/// History on disk (ADR 0016), in Application Support/history:
/// - `raw/<start>.bin`: results, marks and route changes, one file per 10 minutes, deleted once
///   Raw no longer keeps them.
/// - `archives.bin`: Pauses, Rows, Paused seconds and written steps, rewritten whole at launch.
/// Appends with no fsync: a killed process loses nothing the kernel already has (DTS,
/// https://developer.apple.com/forums/thread/763058). Off the main actor.
actor HistoryStore {
    static let segment = 600
    private let directory: URL
    private var raw = HistoryCodec.Writer(), segment: Int?
    private var archives = HistoryCodec.Writer()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("history", isDirectory: true)
    }

    private var rawDirectory: URL { directory.appendingPathComponent("raw", isDirectory: true) }
    private var archiveFile: URL { directory.appendingPathComponent("archives.bin") }

    /// Every record, Archives first, then Raw in the order it was written.
    func load() -> [HistoryRecord] {
        var out = (try? Data(contentsOf: archiveFile)).map(HistoryCodec.decode) ?? []
        for (_, url) in segments() {
            if let data = try? Data(contentsOf: url) { out += HistoryCodec.decode(data) }
        }
        return out
    }

    func append(_ records: [HistoryRecord], now: Int) {
        guard !records.isEmpty else { return }
        let archive = records.filter(\.isArchive), rawRecords = records.filter { !$0.isArchive }
        if !archive.isEmpty { write(archives.encode(archive), to: archiveFile) }
        if !rawRecords.isEmpty {
            let start = now / Self.segment * Self.segment
            if start != segment {
                // A new file defines its keys again.
                segment = start
                raw = HistoryCodec.Writer()
            }
            write(raw.encode(rawRecords), to: rawDirectory.appendingPathComponent("\(start).bin"))
        }
    }

    /// Deletes Raw files whose every record is older than `cutoff`.
    func prune(rawCutoff cutoff: Int) {
        for (start, url) in segments() where start + Self.segment <= cutoff && start != segment {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Replaces the Archive file with what the Archives now hold, dropping what retention removed.
    func compact(_ records: [HistoryRecord]) {
        archives = HistoryCodec.Writer()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? archives.encode(records).write(to: archiveFile, options: .atomic)
    }

    private func segments() -> [(Int, URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: rawDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in Int(url.deletingPathExtension().lastPathComponent).map { ($0, url) } }
            .sorted { $0.0 < $1.0 }
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
