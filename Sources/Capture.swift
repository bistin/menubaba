import Cocoa
import ScreenCaptureKit

/// 截取選單列圖示自己畫的那塊畫面。需要「螢幕錄製」權限。
enum Capture {

    /// 截好的圖示快取。開面板時直接拿現成的，才不會先顯示 app 圖示再跳成截圖。
    /// 只在主執行緒讀寫。
    private static var cache: [String: NSImage] = [:]

    private static func key(_ item: MBItem) -> String { item.appName + "|" + item.itemName }

    static func cached(for item: MBItem) -> NSImage? { cache[key(item)] }

    static func remember(_ image: NSImage, for item: MBItem) { cache[key(item)] = image }

    /// 啟動時先在背景把圖示截好放進快取，這樣第一次開面板就不會跳
    static func prewarm() {
        // 只用 Preflight 檢查的話，這個 app 從來沒「請求」過螢幕錄製權限，
        // 就不會出現在系統設定的清單裡，使用者連手動打開都沒得打開。
        // 沒授權過就主動請求一次（已授權的話這個呼叫不會跳任何東西）。
        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            mpLog("請求螢幕錄製權限 -> \(granted)")
        }
        Task { @MainActor in
            let items = Scanner.scan()
            let glyphs = await glyphs(for: items)
            for item in items {
                if let glyph = glyphs[item.id] { remember(glyph, for: item) }
            }
        }
    }

    /// 選單列圖示的視窗都在 layer 25
    static func statusWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.windows.filter { $0.windowLayer == 25 }
    }

    static func image(of window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)
        config.height = Int(window.frame.height * 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cg, size: window.frame.size)
    }

    /// 取得每個項目在選單列上真正畫出來的圖示。
    /// 沒有螢幕錄製權限就回空的，呼叫端會繼續沿用 app 圖示，不會壞掉。
    static func glyphs(for items: [MBItem]) async -> [Int: NSImage] {
        guard CGPreflightScreenCaptureAccess() else { return [:] }
        guard let windows = try? await statusWindows() else { return [:] }
        var result: [Int: NSImage] = [:]
        for (item, window) in match(items: items, windows: windows) {
            guard let window, let image = try? await image(of: window) else { continue }
            // 時鐘那種是一長條文字（165x33），縮進方格會糊成一團看不懂。
            // 太扁的就不採用，讓呼叫端沿用原本的符號／app 圖示。
            guard image.size.height > 0, image.size.width / image.size.height <= 2.5 else { continue }
            // 選單列圖示幾乎都是單色 template，標成 template 才能跟著淺色/深色模式變色，
            // 否則白色圖示在淺色面板上會整個看不見
            let trimmed = trimTransparent(image)
            trimmed.isTemplate = true
            result[item.id] = trimmed
        }
        return result
    }

    /// 截到的是整個 33px 高的視窗，圖案只佔中間一小塊，上下都是透明留白。
    /// 不裁掉的話縮進面板會比 app 圖示小一大截，看起來像壞掉。
    private static func trimTransparent(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.bitmapData,
              rep.samplesPerPixel == 4 else { return image }

        let width = rep.pixelsWide, height = rep.pixelsHigh
        let rowBytes = rep.bytesPerRow, spp = rep.samplesPerPixel
        var minX = width, minY = height, maxX = -1, maxY = -1

        for y in 0..<height {
            let row = data + y * rowBytes
            for x in 0..<width where row[x * spp + 3] > 16 {   // alpha 門檻，濾掉抗鋸齒邊緣
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = rep.cgImage?.cropping(to: CGRect(x: minX, y: minY,
                                                             width: maxX - minX + 1,
                                                             height: maxY - minY + 1))
        else { return image }

        let scale = max(1, CGFloat(rep.pixelsWide) / max(image.size.width, 1))
        return NSImage(cgImage: cropped,
                       size: NSSize(width: CGFloat(cropped.width) / scale,
                                    height: CGFloat(cropped.height) / scale))
    }

    /// 把 AX 項目對應到它的視窗：靠水平中心點最接近來配對
    static func match(items: [MBItem], windows: [SCWindow]) -> [(MBItem, SCWindow?)] {
        items.map { item in
            let center = item.frame.midX
            let best = windows.min { a, b in
                abs(a.frame.midX - center) < abs(b.frame.midX - center)
            }
            guard let best, abs(best.frame.midX - center) < 12 else { return (item, nil) }
            return (item, best)
        }
    }
}
