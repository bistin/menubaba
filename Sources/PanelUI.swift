import SwiftUI

final class PanelModel: ObservableObject {
    @Published var items: [MBItem] = []
    @Published var query: String = "" { didSet { clampSelection() } }
    @Published var selection: Int = 0
    @Published var layout: PanelLayout = Prefs.layout
    @Published var showNames: Bool = Prefs.showNames

    var filtered: [MBItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.searchKey.contains(q) }
    }

    func reload() {
        items = Scanner.scan()
        query = ""
        selection = 0
        refreshGlyphs()
    }

    /// 先用 app 圖示把面板顯示出來，再背景截取選單列上的真圖示換掉，
    /// 這樣開面板不會被截圖拖慢
    private func refreshGlyphs() {
        let snapshot = items
        Task { @MainActor in
            let glyphs = await Capture.glyphs(for: snapshot)
            guard !glyphs.isEmpty else { return }
            for index in items.indices {
                guard let glyph = glyphs[items[index].id] else { continue }
                items[index].icon = glyph
                Capture.remember(glyph, for: items[index])
            }
        }
    }

    private func clampSelection() {
        let n = filtered.count
        selection = n == 0 ? 0 : min(selection, n - 1)
    }

    func move(_ delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selection = (selection + delta + n) % n
    }

    var selected: MBItem? {
        let f = filtered
        guard f.indices.contains(selection) else { return nil }
        return f[selection]
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onActivate: (MBItem) -> Void
    /// 面板本身就是設定入口。MenuBaba 自己的選單列圖示也可能被擠到看不見，
    /// 那時右鍵選單就完全按不到了，所以面板上一定要有一個進得去的地方。
    var onSettings: () -> Void

    /// 標名稱的時候格子要放寬，字才不會全部被截成「Cont…」
    private var tileWidth: CGFloat { model.showNames ? 64 : 48 }
    private var tileHeight: CGFloat { model.showNames ? 60 : 46 }

    /// 水平列的寬度跟著項目數量走，盡量一排排得下
    private var stripWidth: CGFloat {
        min(1000, max(380, CGFloat(model.items.count) * (tileWidth + 4) + 26))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.filtered.isEmpty {
                emptyState
            } else if model.layout == .strip {
                strip
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: model.layout == .strip ? stripWidth : 360)
        .background(.ultraThinMaterial)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋選單列圖示…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        Text("沒有符合的圖示")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                        Button { onActivate(item) } label: {
                            row(item, selected: index == model.selection)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .frame(maxHeight: 380)
            .onChange(of: model.selection) { _, _ in
                if let s = model.selected { proxy.scrollTo(s.id) }
            }
        }
    }

    /// 水平列：像選單列本身那樣橫排一條
    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                        Button { onActivate(item) } label: {
                            tile(item, selected: index == model.selection)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 7)
            }
            .frame(height: tileHeight + 18)
            .onChange(of: model.selection) { _, _ in
                if let s = model.selected { proxy.scrollTo(s.id) }
            }
        }
    }

    private func tile(_ item: MBItem, selected: Bool) -> some View {
        VStack(spacing: 3) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            // 只用高度正規化。每個圖示視窗高度都是 33px 但寬度從 24 到 47 不等，
            // 塞進正方形會讓窄的靠高度撐滿、寬的靠寬度撐滿，光學大小就亂了。
            // 固定高度、寬度自然變化，才會跟選單列上看到的相對大小一致。
            .frame(maxWidth: 44, maxHeight: 26)

            // 被藏起來的在底下點一顆橘點
            Circle()
                .fill(item.visibility.isHidden ? Color.orange : Color.clear)
                .frame(width: 5, height: 5)

            if model.showNames {
                Text(item.displayTitle)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: tileWidth - 6)
            }
        }
        .frame(width: tileWidth, height: tileHeight)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.accentColor.opacity(0.85) : Color.clear)
        )
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .contentShape(Rectangle())
    }

    private func row(_ item: MBItem, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.dashed").resizable().scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 26, maxHeight: 17)

            Text(item.displayTitle)
                .font(.system(size: 12.5))
                .lineLimit(1)

            Spacer(minLength: 4)

            if item.visibility.isHidden {
                Text(item.visibility == .notch ? "瀏海後" : "畫面外")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.accentColor.opacity(0.85) : Color.clear)
        )
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .contentShape(Rectangle())
    }

    private var footer: some View {
        let hidden = model.items.filter { $0.visibility.isHidden }.count
        return HStack(spacing: 8) {
            if model.layout == .strip, let sel = model.selected {
                Text(sel.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if sel.visibility.isHidden {
                    Text(sel.visibility == .notch ? "瀏海後" : "畫面外")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            } else {
                Text("\(model.items.count) 個圖示").font(.system(size: 10))
                if hidden > 0 {
                    Text("· \(hidden) 個你原本看不到")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(model.layout == .strip ? "←→ 選擇  ⏎ 開啟  esc 關閉" : "↑↓ 選擇  ⏎ 開啟  esc 關閉")
                .font(.system(size: 10))
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("MenuBaba 設定")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
