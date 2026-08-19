import Foundation

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

    static var layout: PanelLayout {
        get { PanelLayout(rawValue: UserDefaults.standard.string(forKey: layoutKey) ?? "") ?? .strip }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: layoutKey) }
    }
}
