import SwiftUI

/// macOS 27 SDK 里 `@State` 是宏，宏插件只随 Xcode 提供（Command Line Tools 里没有）。
/// 直接引用底层的属性包装器类型可以绕开：在 View 里写 `@ViewState private var x = false`。
public typealias ViewState<Value> = SwiftUI.State<Value>
