import AppKit
import SwiftUI

/// MyKit 的一个功能模块（剪切板、截图、系统监控……）。外壳只通过这个协议认识模块。
@MainActor
public protocol AppModule: AnyObject {
    var id: String { get }
    /// 显示在偏好设置里的中文名
    var name: String { get }
    func start() throws
    func stop()
    /// 放进右上角菜单的菜单项
    var menuItems: [NSMenuItem] { get }
    /// 放进偏好设置窗口的设置页
    var settingsView: AnyView? { get }
    /// 右上角菜单即将打开（只通知成功启动的模块）
    func menuWillOpen()
    /// 右上角菜单已经关闭
    func menuDidClose()
}

public extension AppModule {
    var menuItems: [NSMenuItem] { [] }
    var settingsView: AnyView? { nil }
    func menuWillOpen() {}
    func menuDidClose() {}
}
