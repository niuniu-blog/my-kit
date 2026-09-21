import Foundation

/// 记住上次用的标注颜色和粗细。
public struct AnnotationSettings {
    public static let colorKey = "screenshot.annotation.color"
    public static let sizeKey = "screenshot.annotation.size"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 未设置或存了不认识的值时为红色
    public var color: AnnotationColor {
        get { defaults.string(forKey: Self.colorKey).flatMap(AnnotationColor.init(rawValue:)) ?? .red }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.colorKey) }
    }

    /// 未设置或存了不认识的值时为"中"
    public var size: AnnotationSize {
        get { defaults.string(forKey: Self.sizeKey).flatMap(AnnotationSize.init(rawValue:)) ?? .medium }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.sizeKey) }
    }
}
