import Foundation
import MetricKit

/// MetricKit's diagnostic reports (hangs, crashes), saved as JSON in Documents/diagnostics so the
/// Report menu can share them. iOS 15+ delivers diagnostics as soon as they're available
/// (https://developer.apple.com/documentation/metrickit/mxmetricmanager). Whether it does for a
/// sideloaded build isn't documented.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()

    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics", isDirectory: true)
    }

    /// Saved reports, newest first.
    static var saved: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func start() {
        MXMetricManager.shared.add(self)
        // Reports delivered before this launch subscribed.
        save(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) { save(payloads) }

    private func save(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter()
        for payload in payloads {
            let kinds = [payload.hangDiagnostics.map { _ in "hang" }, payload.crashDiagnostics.map { _ in "crash" },
                         payload.cpuExceptionDiagnostics.map { _ in "cpu" }, payload.diskWriteExceptionDiagnostics.map { _ in "disk" }]
                .compactMap { $0 }.joined(separator: "-")
            let name = "\(stamp.string(from: payload.timeStampEnd))-\(kinds.isEmpty ? "other" : kinds).json"
            let url = Self.directory.appendingPathComponent(name.replacingOccurrences(of: ":", with: ""))
            // The same payload comes back from pastDiagnosticPayloads on later launches.
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? payload.jsonRepresentation().write(to: url)
        }
    }
}
