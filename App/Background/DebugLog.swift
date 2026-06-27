import Foundation

/// TEMPORARY diagnostic logger. Appends timestamped lines to
/// Documents/keepalive.log so background behavior can be inspected via
/// `xcrun devicectl device copy from --domain-type appDataContainer
///  --domain-identifier com.nightaps.aapsclientios --source Documents/keepalive.log`.
/// Remove once the Live Activity freshness issue is confirmed fixed.
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.nightaps.debuglog")
    private static let iso = ISO8601DateFormatter()
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("keepalive.log")
    }()

    static func log(_ msg: String) {
        let line = "\(iso.string(from: Date())) \(msg)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
