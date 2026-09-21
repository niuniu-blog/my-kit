import Foundation

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let text: String
    public let appBundleID: String?
    public let appName: String?
    /// 第一次复制的时间
    public let createdAt: Date
    /// 最近一次复制 / 粘贴的时间，列表按它倒序
    public let lastUsedAt: Date

    public init(id: Int64, text: String, appBundleID: String?, appName: String?, createdAt: Date, lastUsedAt: Date) {
        self.id = id
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// 列表里显示的单行摘要：压缩空白，最多 120 个字符。
    public var summary: String {
        let head = text.prefix(600)   // 先截一段，避免对 1MB 文本做整体处理
        let collapsed = head.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if collapsed.count > 120 {
            return String(collapsed.prefix(120)) + "…"
        }
        return collapsed
    }
}
