import Foundation

/// 開發期的除錯記錄，寫到 ~/menupeek-debug.log
func mpLog(_ message: String) {
    let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
    let path = NSHomeDirectory() + "/menupeek-debug.log"
    guard let data = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
