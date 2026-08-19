import Cocoa
import ApplicationServices

/// 一個選單列圖示的可見狀態
enum Visibility {
    case visible      // 看得到
    case notch        // 被瀏海遮住
    case offscreen    // 被推到畫面外（第三方管理器造成）

    var badge: String {
        switch self {
        case .visible:   return ""
        case .notch:     return "🌑"
        case .offscreen: return "🚫"
        }
    }
    var isHidden: Bool { self != .visible }
}

struct MBItem: Identifiable {
    let id: Int
    let appName: String
    let itemName: String
    var icon: NSImage?
    let element: AXUIElement
    let frame: CGRect
    let visibility: Visibility
    /// 面板上顯示的主標題。單一項目的 app 用 app 名稱（好認），
    /// 一個 app 有多個項目時（控制中心）改用項目自己的名稱，否則會全部塌成同一個名字。
    var displayTitle: String = ""
    /// 兩個名稱都納入搜尋，打 app 名或圖示名都找得到
    var searchKey: String { (appName + " " + itemName).lowercased() }
}

enum Scanner {

    /// 用 NSScreen 的 auxiliary area 量出瀏海的實際範圍，沒有瀏海就回 nil
    static func notchRange(on screen: NSScreen) -> ClosedRange<CGFloat>? {
        guard let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea,
              r.minX > l.maxX else { return nil }
        return l.maxX ... r.minX
    }

    private static func axValue<T>(_ el: AXUIElement, _ attr: String, _ type: AXValueType, _ initial: T) -> T {
        var ref: CFTypeRef?
        var result = initial
        if AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let ref {
            AXValueGetValue(ref as! AXValue, type, &result)
        }
        return result
    }

    /// 控制中心那類系統項目全都共用同一個 app 圖示，在面板上完全分不出來。
    /// 用項目名稱對應到 SF Symbol；對不到的就退回 app 圖示，不會因為漏列而壞掉。
    private static let symbolMap: [String: String] = [
        "wi-fi": "wifi", "wi‑fi": "wifi", "wifi": "wifi",
        "battery": "battery.100",
        "clock": "clock",
        "control center": "switch.2",
        "sound": "speaker.wave.2", "volume": "speaker.wave.2",
        "focus": "moon", "display": "sun.max",
        "now playing": "play.circle",
        "screen mirroring": "rectangle.on.rectangle",
        "keyboard brightness": "keyboard",
        "accessibility shortcuts": "figure.wave",
        "fast user switching": "person.crop.circle",
    ]

    /// SF Symbols 沒有藍牙符號（Apple 不收品牌標誌），所以直接把那個 rune 畫出來。
    /// 這比硬找一個「有點像」的符號精確，也不依賴會隨系統改版消失的資源路徑。
    private static func bluetoothIcon() -> NSImage {
        let size = NSSize(width: 20, height: 28)
        let image = NSImage(size: size, flipped: false) { _ in
            // 以 100x160 的座標描一筆到底的藍牙 rune，再等比縮到實際尺寸
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: 1 + x / 100 * 18, y: 1 + y / 160 * 26)
            }
            let path = NSBezierPath()
            path.move(to: point(20, 110))
            path.line(to: point(80, 50))
            path.line(to: point(50, 20))
            path.line(to: point(50, 140))
            path.line(to: point(80, 110))
            path.line(to: point(20, 50))
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true    // 讓它跟著淺色/深色模式變色
        return image
    }

    private static func symbolIcon(for name: String) -> NSImage? {
        if name.lowercased() == "bluetooth" { return bluetoothIcon() }
        guard let symbol = symbolMap[name.lowercased()] else { return nil }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
        let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        return image?.withSymbolConfiguration(config)
    }

    /// AX 的描述常把狀態接在逗號後面（例如 "Wi‑Fi, connected, 3 bars"），
    /// 標題只留逗號前那段，狀態不是用來辨識的資訊
    private static func cleanName(_ raw: String) -> String {
        (raw.split(separator: ",").first.map(String.init) ?? raw)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let ref else { return "" }
        return (ref as? String) ?? ""
    }

    /// 掃描所有 app 的選單列圖示
    static func scan() -> [MBItem] {
        let notch = NSScreen.main.flatMap { notchRange(on: $0) }
        var items: [MBItem] = []
        var nextID = 0

        let selfBundle = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0 else { continue }
            guard app.bundleIdentifier != selfBundle else { continue }   // 不要列出自己

            var extras: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid),
                                                "AXExtrasMenuBar" as CFString, &extras) == .success,
                  let extras else { continue }

            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(extras as! AXUIElement, kAXChildrenAttribute as CFString,
                                                &children) == .success,
                  let kids = children as? [AXUIElement] else { continue }

            for el in kids {
                let pos = axValue(el, kAXPositionAttribute, .cgPoint, CGPoint.zero)
                // x == 0 是尚未啟用／沒有排版的項目（例如關閉的控制中心模組），不是真的圖示
                guard pos.x != 0 else { continue }
                let size = axValue(el, kAXSizeAttribute, .cgSize, CGSize.zero)
                let frame = CGRect(origin: pos, size: size)

                let vis: Visibility
                if pos.x < -100 {
                    vis = .offscreen
                } else if let notch, frame.maxX > notch.lowerBound, frame.minX < notch.upperBound {
                    vis = .notch
                } else {
                    vis = .visible
                }

                let name = [axString(el, kAXTitleAttribute),
                            axString(el, kAXDescriptionAttribute),
                            axString(el, kAXHelpAttribute)].first { !$0.isEmpty } ?? ""

                items.append(MBItem(id: nextID,
                                    appName: app.localizedName ?? "?",
                                    itemName: name,
                                    icon: app.icon,
                                    element: el,
                                    frame: frame,
                                    visibility: vis))
                nextID += 1
            }
        }
        // 同一個 app 貢獻幾個項目？只有一個就用 app 名稱，多個才需要靠項目名稱區分
        var counts: [String: Int] = [:]
        for item in items { counts[item.appName, default: 0] += 1 }

        for i in items.indices {
            let item = items[i]
            let own = cleanName(item.itemName)
            let ambiguous = (counts[item.appName] ?? 0) > 1
            items[i].displayTitle = ambiguous && !own.isEmpty ? own : item.appName
            if let symbol = symbolIcon(for: own) {
                items[i].icon = symbol
            }
        }

        // 依照在選單列上的實際位置排序，被藏起來的自然排在前面
        return items.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 觸發一個圖示。
    ///
    /// AXPress 的回傳碼在這裡是假訊號，實測結果：
    ///   - 回 cannotComplete(-25204) → 選單其實「有」打開，只是 modal tracking loop 卡住了呼叫
    ///   - 回 success(0) → 反而可能什麼都沒發生（例如 ChatGPT 那種自繪面板）
    /// 所以只有回 success 時才需要確認是否真的長出 AXMenu，沒有就補一次實體點擊。
    static func activate(_ item: MBItem) {
        mpLog("activate: \(item.appName) frame=\(item.frame) vis=\(item.visibility)")
        let element = item.element
        let frame = item.frame

        // 一定要在背景執行緒。選單被按開之後會進入 modal tracking loop，
        // AXUIElementPerformAction 會一路卡到選單關閉才返回；跑在主執行緒上
        // 等於把整個 app 凍住，連熱鍵都沒反應。
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementSetMessagingTimeout(element, 2.0)
            let err = AXUIElementPerformAction(element, kAXPressAction as CFString)
            mpLog("  AXPress -> \(err.rawValue)")

            // 回傳碼在這裡是假訊號：cannotComplete 代表選單其實開了，
            // 反倒是 success 可能什麼都沒發生（例如 ChatGPT 那種自繪面板）。
            guard err == .success else { return }

            Thread.sleep(forTimeInterval: 0.25)
            var kids: CFTypeRef?
            var hasMenu = false
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kids) == .success,
               let arr = kids as? [AXUIElement] {
                hasMenu = arr.contains { axString($0, kAXRoleAttribute) == "AXMenu" }
            }
            mpLog("  hasMenu=\(hasMenu)")
            if !hasMenu {
                mpLog("  -> 改用模擬點擊")
                synthesizeClick(at: frame)
            }
        }
    }

    /// AXPress 無效時的退路：直接在圖示座標送一組滑鼠事件
    private static func synthesizeClick(at frame: CGRect) {
        let p = CGPoint(x: frame.midX, y: frame.midY)
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}
