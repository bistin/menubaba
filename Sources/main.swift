import Cocoa
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let menuBabaHotKey = Notification.Name("menuBabaHotKey")
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
                                               name: .menuBabaHotKey, object: nil)
        if !AXIsProcessTrusted() { promptForAccessibility() }
        Capture.prewarm()
        // 開發用：啟動即開面板，方便截圖驗證
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePanel() }
        }
    }

    // MARK: - 選單列圖示

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.grid.2x2",
                                     accessibilityDescription: "MenuBaba")
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

        let login = NSMenuItem(title: "開機時自動啟動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = Prefs.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "結束 MenuBaba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        Prefs.launchAtLogin.toggle()
        mpLog("開機自動啟動 -> \(Prefs.launchAtLogin)")
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
            NotificationCenter.default.post(name: .menuBabaHotKey, object: nil)
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x4D504B31), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_M),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - 面板

    @objc private func togglePanel() {
        mpLog("togglePanel 被呼叫 (目前 visible=\(panel?.isVisible ?? false))")
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
        mpLog("closePanel")
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

    /// 先關面板再觸發，否則選單會開在面板後面。
    /// 而且一定要讓出焦點：開面板時呼叫過 NSApp.activate，關掉面板後 MenuBaba
    /// 仍是最前景的 app，對方的浮動面板（NSPopover 那類）一出現就會因為不是
    /// 焦點而立刻收掉，看起來就像「閃一下就不見」。
    private func activate(_ item: MBItem) {
        closePanel()
        NSApp.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
