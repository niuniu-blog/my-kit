import AppKit

// 顶层代码运行在主线程，但 Swift 5 语言模式下编译器不把它视为 MainActor 隔离，需要显式声明。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()   // 不会返回，delegate 在整个运行期间保持存活
}
