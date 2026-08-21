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
    private static let showNamesKey = "ShowNames"

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

    /// 水平列要不要在圖示底下標名稱。垂直清單本來就有名稱，這個開關只影響水平列。
    static var showNames: Bool {
        get { UserDefaults.standard.bool(forKey: showNamesKey) }
        set { UserDefaults.standard.set(newValue, forKey: showNamesKey) }
    }
}
