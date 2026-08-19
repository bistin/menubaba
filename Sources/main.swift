import Cocoa
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let menuPeekHotKey = Notification.Name("menuPeekHotKey")
}

/// 無邊框面板預設不能成為 key window，搜尋框就收不到鍵盤輸入，所以要覆寫
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = PanelModel()
    private var panel: KeyPanel?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(togglePanel),
                                               name: .menuPeekHotKey, object: nil)
        if !AXIsProcessTrusted() { promptForAccessibility() }

        // 開發用：驗證能不能截到圖示本身的畫面
        if CommandLine.arguments.contains("--capturetest") {
            let granted = CGRequestScreenCaptureAccess()
            mpLog("capturetest: 螢幕錄製權限 = \(granted)")
            Task {
                do {
                    let windows = try await Capture.statusWindows()
                    mpLog("capturetest: layer 25 視窗 \(windows.count) 個")
                    let items = Scanner.scan()
                    let dir = NSHomeDirectory() + "/menupeek-icons"
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    for (item, win) in Capture.match(items: items, windows: windows) {
                        guard let win else { mpLog("  \(item.displayTitle): 配對不到視窗"); continue }
                        do {
                            let image = try await Capture.image(of: win)
                            let ok = image.size.width > 0
                            mpLog("  \(item.displayTitle) [\(item.visibility)]: 截到 \(Int(image.size.width))x\(Int(image.size.height)) \(ok ? "✅" : "❌")")
                            if let tiff = image.tiffRepresentation,
                               let rep = NSBitmapImageRep(data: tiff),
                               let png = rep.representation(using: .png, properties: [:]) {
                                let safe = item.displayTitle.replacingOccurrences(of: "/", with: "_")
                                try? png.write(to: URL(fileURLWithPath: dir + "/\(safe).png"))
                            }
                        } catch {
                            mpLog("  \(item.displayTitle): 截圖失敗 \(error)")
                        }
                    }
                    mpLog("capturetest: 完成，圖片在 ~/menupeek-icons")
                } catch {
                    mpLog("capturetest: 失敗 \(error)")
                }
            }
        }

        // 開發用：不經過 UI，直接觸發一個項目，用來隔離「點擊沒傳到」和「AXPress 失效」
        if CommandLine.arguments.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let items = Scanner.scan()
                mpLog("selftest: 掃到 \(items.count) 個")
                let target = items.first { $0.appName == "Docker Desktop" }
                    ?? items.first { $0.appName == "OpenVPN Connect" }
                    ?? items.first
                guard let target else { mpLog("selftest: 沒有目標"); return }
                mpLog("selftest: 目標 = \(target.appName)")
                Scanner.activate(target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let menus = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
                        .filter { ($0[kCGWindowLayer as String] as? Int ?? 0) == 101 }
                        .map { "\($0[kCGWindowOwnerName as String] as? String ?? "?")" }
                    mpLog("selftest: 畫面上 layer=101 的選單視窗 = \(menus)")
                    // 一定要把選單收掉，開著的選單會抓住輸入事件
                    if let src = CGEventSource(stateID: .hidSystemState) {
                        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                        CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
                    }
                    mpLog("selftest: 已送 Esc 關閉選單")
                }
            }
        }

        // 開發用：啟動即開面板，方便截圖驗證
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePanel() }
        }
    }

    // MARK: - 選單列圖示

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.grid.2x2",
                                     accessibilityDescription: "MenuPeek")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else { togglePanel(); return }

        let menu = NSMenu()

        let show = NSMenuItem(title: "顯示面板  ⌃⌥⌘M", action: #selector(togglePanel), keyEquivalent: "")
        show.target = self
        menu.addItem(show)

        let layoutItem = NSMenuItem(title: "版面", action: nil, keyEquivalent: "")
        let layoutMenu = NSMenu()
        for layout in PanelLayout.allCases {
            let item = NSMenuItem(title: layout.label, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            item.state = Prefs.layout == layout ? .on : .off
            layoutMenu.addItem(item)
        }
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束 MenuPeek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = PanelLayout(rawValue: raw) else { return }
        Prefs.layout = layout
        model.layout = layout
        closePanel()   // 兩種版面寬度不同，關掉重開才會套用
    }

    // MARK: - 全域熱鍵 ⌃⌥⌘M

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            NotificationCenter.default.post(name: .menuPeekHotKey, object: nil)
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4D504B31), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_M),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - 面板

    @objc private func togglePanel() {
        if let p = panel, p.isVisible { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        model.reload()

        let view = PanelView(model: model) { [weak self] item in
            mpLog("tap 收到: \(item.appName)")
            self?.activate(item)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.layout()

        let p = KeyPanel(contentRect: .zero,
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.contentView = hosting
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        // 沒有這行的話，面板在全螢幕 app 的 Space 上不會出現
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.setContentSize(hosting.fittingSize)

        if let screen = NSScreen.main {
            let size = p.frame.size
            let x = screen.frame.midX - size.width / 2
            let y = screen.visibleFrame.maxY - size.height - 8
            p.setFrameOrigin(CGPoint(x: x, y: y))
        }

        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        mpLog("panel frame=\(p.frame) visible=\(p.isVisible) items=\(model.items.count) menuBarVisible=\(NSMenu.menuBarVisible())")
    }

    private func closePanel() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:      self.closePanel();                    return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let s = self.model.selected { self.activate(s) };    return nil
            case kVK_LeftArrow, kVK_UpArrow:     self.model.move(-1);   return nil
            case kVK_RightArrow, kVK_DownArrow:  self.model.move(1);    return nil
            default:              return event
            }
        }
    }

    /// 先關面板再觸發，否則選單會開在面板後面
    private func activate(_ item: MBItem) {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Scanner.activate(item)
        }
    }

    // MARK: - 權限

    private func promptForAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
