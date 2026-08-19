import SwiftUI

final class PanelModel: ObservableObject {
    @Published var items: [MBItem] = []
    @Published var query: String = "" { didSet { clampSelection() } }
    @Published var selection: Int = 0

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
                if let glyph = glyphs[items[index].id] { items[index].icon = glyph }
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

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 360)
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
            .frame(width: 19, height: 19)

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
        return HStack(spacing: 10) {
            Text("\(model.items.count) 個圖示")
            if hidden > 0 {
                Text("· \(hidden) 個你原本看不到").foregroundStyle(.orange)
            }
            Spacer()
            Text("↑↓←→ 選擇   ⏎ 開啟   esc 關閉")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
}
