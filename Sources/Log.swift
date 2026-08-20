import Foundation

/// 除錯記錄，寫到 ~/menubaba-debug.log。
/// 預設關閉，加上 --debug 參數啟動才會寫，否則這個檔案會無止境長大。
private let loggingEnabled = CommandLine.arguments.contains("--debug")

func mpLog(_ message: String) {
    guard loggingEnabled else { return }
    let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
    let path = NSHomeDirectory() + "/menubaba-debug.log"
    guard let data = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
