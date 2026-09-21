import AppKit

@MainActor
public final class ModuleRegistry {
    public private(set) var modules: [AppModule] = []
    public private(set) var failures: [(id: String, error: Error)] = []
    private var started: [AppModule] = []

    public init() {}

    public func register(_ module: AppModule) {
        modules.append(module)
    }

    /// 逐个启动；某个模块启动失败只记录，不影响其他模块。
    public func startAll() {
        for module in modules {
            do {
                try module.start()
                started.append(module)
            } catch {
                failures.append((id: module.id, error: error))
            }
        }
    }

    /// 只停止成功启动过的模块，顺序与启动相反。
    public func stopAll() {
        for module in started.reversed() {
            module.stop()
        }
        started.removeAll()
    }

    public var menuItems: [NSMenuItem] {
        modules.flatMap(\.menuItems)
    }
}
