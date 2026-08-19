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

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.filtered.isEmpty {
                emptyState
            } else {
                grid
            }
            Divider()
            footer
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋選單列圖示…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        Text("沒有符合的圖示")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                        Button { onActivate(item) } label: {
                            cell(item, selected: index == model.selection)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 340)
            .onChange(of: model.selection) { _, _ in
                if let s = model.selected { proxy.scrollTo(s.id) }
            }
        }
    }

    private func cell(_ item: MBItem, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 38, height: 38)
                } else {
                    Image(systemName: "app.dashed").resizable().frame(width: 38, height: 38)
                        .foregroundStyle(.secondary)
                }
                if item.visibility.isHidden {
                    Text(item.visibility.badge)
                        .font(.system(size: 11))
                        .offset(x: 7, y: -5)
                }
            }
            .frame(height: 42)

            Text(item.displayTitle)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(item.visibility.isHidden ? .primary : .secondary)
        }
        .frame(width: 84, height: 76)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
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
