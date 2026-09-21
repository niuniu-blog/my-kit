import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 系统设置里几个隐私页面的链接。
public enum PrivacyPane: CaseIterable {
    case fullDiskAccess
    case appManagement
    case automation

    public var url: URL {
        let anchor: String
        switch self {
        case .fullDiskAccess: anchor = "Privacy_AllFiles"
        case .appManagement: anchor = "Privacy_AppBundles"
        case .automation: anchor = "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    @MainActor
    public func open() {
        NSWorkspace.shared.open(url)
    }
}

/// 图标缓存。属于卸载窗口，窗口关闭就一起释放。
@MainActor
final class AppIconStore {
    private var cache: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

struct UninstallerView: View {
    @ObservedObject var model: UninstallerViewModel
    let icons: AppIconStore
    let home: URL

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            acceptDrop(providers)
        }
        .overlay {
            if model.phase == .running || model.phase == .quitting {
                busyOverlay
            }
        }
        .alert("软件正在运行", isPresented: binding(for: .needsQuit)) {
            Button("退出并继续") { model.quitTapped() }
            Button("取消", role: .cancel) { model.cancelPending() }
        } message: {
            Text("「\(model.selectedApp?.title ?? "")」正在运行。要卸载它，需要先退出。MyKit 只会请它正常退出，不会强制结束。")
        }
        .alert("移到废纸篓？", isPresented: binding(for: .confirming)) {
            Button("移到废纸篓", role: .destructive) { model.confirmTapped() }
            Button("取消", role: .cancel) { model.cancelPending() }
        } message: {
            Text(model.confirmationText)
        }
        .sheet(isPresented: isShowingResult) {
            if case .finished(let report) = model.phase {
                ResultView(report: report, home: home) {
                    Task { await model.dismissResult() }
                }
            }
        }
    }

    /// 提示框由状态驱动；关闭动作交给各个按钮自己处理，这里的 set 什么都不做。
    private func binding(for phase: UninstallerViewModel.Phase) -> Binding<Bool> {
        Binding(get: { model.phase == phase }, set: { _ in })
    }

    private var isShowingResult: Binding<Bool> {
        Binding(get: { if case .finished = model.phase { return true } else { return false } }, set: { _ in })
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
            VStack(spacing: 10) {
                ProgressView()
                Text(model.phase == .quitting ? "正在等待软件退出…" : "正在移到废纸篓…")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: 左侧：软件列表

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("搜索软件…", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                Picker("排序", selection: $model.sortOrder) {
                    ForEach(AppListing.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(10)
            Divider()
            if model.isLoadingApps {
                Spacer()
                ProgressView("正在列出已安装的软件…")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app, icon: icons.icon(forPath: app.identity.url.path),
                                   isSelected: app.id == model.selectedApp?.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await model.select(app) }
                                }
                        }
                    }
                    .padding(6)
                }
            }
            Divider()
            Text("也可以把 .app 从访达拖到这个窗口里")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    // MARK: 右侧：清单

    @ViewBuilder
    private var detail: some View {
        if let app = model.selectedApp {
            VStack(spacing: 0) {
                header(app)
                Divider()
                if model.phase == .scanning {
                    Spacer()
                    ProgressView("正在查找相关文件…")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(model.groups) { group in
                                Text(group.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 10)
                                    .padding(.horizontal, 6)
                                ForEach(group.items) { item in
                                    ItemRow(
                                        item: item,
                                        icon: icons.icon(forPath: item.url.path),
                                        location: PathDisplay.location(of: item.url, home: home),
                                        isChecked: Binding(
                                            get: { model.isChecked(item) },
                                            set: { model.setChecked(item, $0) }),
                                        isHighlighted: model.highlightedItemID == item.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.highlightedItemID = item.id }
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                Divider()
                footer
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "trash.square")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("从左边选一个软件，或者把 .app 拖到这里")
                    .foregroundStyle(.secondary)
                Text("所有内容只会移到废纸篓，可以随时放回原处")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                if let notice = model.notice {
                    Text(notice)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func header(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: icons.icon(forPath: app.identity.url.path))
                    .resizable()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.identity.version.map { "\(app.title)  \($0)" } ?? app.title)
                        .font(.headline)
                    Text(app.identity.bundleID ?? "（没有标识符，只能按名称查找）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.summaryText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("全选") { model.selectAll() }
                Button("只选确定相关") { model.selectOnlyCertain() }
                Spacer()
            }
            .disabled(model.phase != .ready)
        }
        .padding(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if !model.unreadableLocations.isEmpty {
                HStack {
                    Text("有 \(model.unreadableLocations.count) 个位置无权读取。授予 MyKit「完全磁盘访问权限」后可以找得更全（不授予也能用）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("打开系统设置") { PrivacyPane.fullDiskAccess.open() }
                        .controlSize(.small)
                }
            }
            HStack {
                Spacer()
                Button("在访达中显示") {
                    if let item = model.highlightedItem {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                }
                .disabled(model.highlightedItem == nil)
                Button("移到废纸篓") { model.requestUninstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canUninstall)
            }
        }
        .padding(12)
    }

    // MARK: 拖放

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else { return false }
        let model = self.model
        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            var dropped: URL?
            if let data = item as? Data {
                dropped = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                dropped = url
            }
            guard let dropped else { return }
            Task { @MainActor in
                await model.handleDrop(dropped)
            }
        }
        return true
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let icon: NSImage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(app.sizeBytes.map(SizeCalculator.format) ?? "计算中…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : Color.clear))
    }
}

private struct ItemRow: View {
    let item: LeftoverItem
    let icon: NSImage
    let location: String
    @Binding var isChecked: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isChecked)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Image(nsImage: icon)
                .resizable()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.category) · \(location)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(item.sizeBytes.map(SizeCalculator.format) ?? "…")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear))
        .help(item.url.path)
    }
}

private struct ResultView: View {
    let report: TrashReport
    let home: URL
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.summary)
                .font(.headline)
            if !report.succeeded.isEmpty {
                Text("它们现在在废纸篓里。想恢复：打开废纸篓，右键点那一项，选「放回原处」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if report.touchedBackgroundServices {
                Text("其中的后台服务在重启电脑后才会完全停止。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !report.failed.isEmpty {
                Text("没有移走的项：")
                    .font(.subheadline.weight(.semibold))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.failed) { failure in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(PathDisplay.abbreviated(failure.item.url, home: home))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(failure.reason)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            if report.appManagementBlocked {
                HStack {
                    Text("系统拦住了 MyKit 移动其他软件。请在「隐私与安全性 → App 管理」里打开 MyKit，然后再试一次。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开「App 管理」") { PrivacyPane.appManagement.open() }
                }
            }
            if report.automationDenied {
                HStack {
                    Text("需要管理员权限的项要请访达来移走。请在「隐私与安全性 → 自动化」里允许 MyKit 控制访达，然后再试一次。")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开「自动化」") { PrivacyPane.automation.open() }
                }
            }
            HStack {
                Spacer()
                Button("好", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
