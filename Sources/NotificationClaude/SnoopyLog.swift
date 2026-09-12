import Foundation

final class SnoopyLog {
    static let shared = SnoopyLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.chidiwilliams.snoopy.file-log")
    private let formatter = ISO8601DateFormatter()

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Snoopy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("snoopy.log")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    func info(_ message: String) { write(level: "INFO", message: message) }
    func warning(_ message: String) { write(level: "WARN", message: message) }
    func error(_ message: String) { write(level: "ERROR", message: message) }

    func contents() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "Unable to read the log file."
        }
    }

    private func write(level: String, message: String) {
        queue.async { [fileURL, formatter] in
            let cleaned = message.replacingOccurrences(of: "\0", with: "")
            let line = "\(formatter.string(from: Date())) [\(level)] \(cleaned)\n"
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Logging must never interrupt notification monitoring.
            }
        }
    }
}
