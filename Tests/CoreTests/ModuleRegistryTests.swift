import AppKit
import Testing
@testable import Core

@MainActor
private final class FakeModule: AppModule {
    let id: String
    let name: String
    var shouldFail = false
    var log: [String]
    let items: [NSMenuItem]

    init(id: String, items: [NSMenuItem] = [], log: [String] = []) {
        self.id = id
        self.name = id
        self.items = items
        self.log = log
    }

    struct Boom: Error {}

    func start() throws {
        if shouldFail { throw Boom() }
        log.append("start")
    }

    func stop() { log.append("stop") }

    var menuItems: [NSMenuItem] { items }

    func menuWillOpen() { log.append("menuWillOpen") }

    func menuDidClose() { log.append("menuDidClose") }
}

@MainActor
@Suite struct ModuleRegistryTests {
    @Test func startsAndStopsRegisteredModules() {
        let registry = ModuleRegistry()
        let a = FakeModule(id: "a")
        let b = FakeModule(id: "b")
        registry.register(a)
        registry.register(b)

        registry.startAll()
        registry.stopAll()

        #expect(a.log == ["start", "stop"])
        #expect(b.log == ["start", "stop"])
        #expect(registry.failures.isEmpty)
    }

    @Test func failingModuleDoesNotBlockOthersAndIsNotStopped() {
        let registry = ModuleRegistry()
        let bad = FakeModule(id: "bad")
        bad.shouldFail = true
        let good = FakeModule(id: "good")
        registry.register(bad)
        registry.register(good)

        registry.startAll()
        registry.stopAll()

        #expect(registry.failures.map(\.id) == ["bad"])
        #expect(bad.log.isEmpty)
        #expect(good.log == ["start", "stop"])
    }

    @Test func collectsMenuItemsInRegistrationOrder() {
        let registry = ModuleRegistry()
        registry.register(FakeModule(id: "a", items: [NSMenuItem(title: "A1", action: nil, keyEquivalent: "")]))
        registry.register(FakeModule(id: "b", items: [NSMenuItem(title: "B1", action: nil, keyEquivalent: "")]))

        #expect(registry.menuItems.map(\.title) == ["A1", "B1"])
    }

    @Test func separatorFollowsEachModuleThatHasMenuItems() {
        let registry = ModuleRegistry()
        registry.register(FakeModule(id: "a", items: [NSMenuItem(title: "A1", action: nil, keyEquivalent: "")]))
        registry.register(FakeModule(id: "empty"))
        registry.register(FakeModule(id: "c", items: [
            NSMenuItem(title: "C1", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "C2", action: nil, keyEquivalent: ""),
        ]))

        let described = registry.menuItemsWithSeparators.map { $0.isSeparatorItem ? "---" : $0.title }

        #expect(described == ["A1", "---", "C1", "C2", "---"])
    }

    @Test func noModulesMeansNoSeparators() {
        #expect(ModuleRegistry().menuItemsWithSeparators.isEmpty)
    }

    @Test func menuOpenAndCloseAreForwardedToStartedModulesOnly() {
        let registry = ModuleRegistry()
        let bad = FakeModule(id: "bad")
        bad.shouldFail = true
        let good = FakeModule(id: "good")
        registry.register(bad)
        registry.register(good)
        registry.startAll()

        registry.menuWillOpen()
        registry.menuDidClose()

        #expect(good.log == ["start", "menuWillOpen", "menuDidClose"])
        #expect(bad.log.isEmpty)
    }

    @Test func menuCallbacksAreNotForwardedAfterStopAll() {
        let registry = ModuleRegistry()
        let module = FakeModule(id: "m")
        registry.register(module)
        registry.startAll()
        registry.stopAll()

        registry.menuWillOpen()

        #expect(module.log == ["start", "stop"])
    }

    @Test func menuCallbacksHaveDefaultNoOpImplementations() {
        @MainActor final class Bare: AppModule {
            let id = "bare"
            let name = "bare"
            func start() throws {}
            func stop() {}
        }
        let bare = Bare()
        bare.menuWillOpen()
        bare.menuDidClose()
        #expect(bare.menuItems.isEmpty)
    }

    @Test func defaultMenuItemsAndSettingsViewAreEmpty() {
        @MainActor final class Bare: AppModule {
            let id = "bare"
            let name = "bare"
            func start() throws {}
            func stop() {}
        }
        let bare = Bare()
        #expect(bare.menuItems.isEmpty)
        #expect(bare.settingsView == nil)
    }
}
