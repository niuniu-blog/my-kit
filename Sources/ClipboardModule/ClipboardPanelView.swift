import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: ClipboardPanelViewModel
    let onPaste: (ClipboardItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if viewModel.items.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list.frame(width: 320)
                    Divider()
                    preview
                }
            }
            if let message = viewModel.footerMessage {
                Divider()
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 760, height: 460)
        .background(.regularMaterial)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            TextField(
                "搜索剪切板历史…",
                text: Binding(get: { viewModel.query }, set: { viewModel.updateQuery($0) })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "还没有复制记录" : "没有匹配的记录")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        ClipboardRowView(
                            summary: item.summary,
                            shortcut: index < 9 ? index + 1 : nil,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onPaste(item) }
                        .onTapGesture { viewModel.select(index: index) }
                        .onAppear {
                            if index == viewModel.items.count - 1 {
                                Task { await viewModel.loadMore() }
                            }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: viewModel.selectedIndex) { _, newIndex in
                if viewModel.items.indices.contains(newIndex) {
                    proxy.scrollTo(viewModel.items[newIndex].id)
                }
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            if let item = viewModel.selectedItem {
                ScrollView {
                    // 超长文本只预览前 2 万个字符，避免界面卡顿；粘贴时仍是完整内容
                    Text(String(item.text.prefix(20_000)))
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                Divider()
                Text(Self.caption(for: item, now: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func caption(for item: ClipboardItem, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: item.lastUsedAt, relativeTo: now)
        return "来自 \(item.appName ?? "未知应用") · \(when) · \(item.text.count) 个字符"
    }
}

private struct ClipboardRowView: View {
    let summary: String
    let shortcut: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }
}
