import Foundation

public enum CaptureDecision: Equatable {
    /// 记录这段文本
    case record(String)
    /// 这是 MyKit 自己写入的（用户刚从面板粘贴）：只把已有记录移到最前
    case touchOwn(String)
    case skip
}

/// 决定一次剪切板变化要不要进历史。纯函数。
public enum CaptureFilter {
    public static let ownWriteType = "com.imiros.mykit.own-write"
    public static let maxBytes = 1_048_576
    /// 密码管理器等按 nspasteboard.org 约定打的标记
    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
    ]

    public static func decide(types: [String], string: String?) -> CaptureDecision {
        if types.contains(where: ignoredTypes.contains) { return .skip }
        guard let string else { return .skip }
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .skip }
        if string.utf8.count > maxBytes { return .skip }
        if types.contains(ownWriteType) { return .touchOwn(string) }
        return .record(string)
    }
}
