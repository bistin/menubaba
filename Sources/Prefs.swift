import Foundation
import ServiceManagement

enum PanelLayout: String, CaseIterable {
    case strip   // 水平一長條，像選單列本身
    case list    // 垂直清單，像 Spotlight

    var label: String {
        switch self {
        case .strip: return "水平列"
        case .list:  return "垂直清單"
        }
    }
}

enum Prefs {
    private static let layoutKey = "PanelLayout"

    /// 開機自動啟動。狀態由系統保管（SMAppService），不存在 UserDefaults。
    /// 第一次註冊時 macOS 會要求使用者在「一般 → 登入項目」批准。
    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                mpLog("開機自動啟動設定失敗: \(error)")
            }
        }
    }

    static var layout: PanelLayout {
        get { PanelLayout(rawValue: UserDefaults.standard.string(forKey: layoutKey) ?? "") ?? .strip }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: layoutKey) }
    }
}
