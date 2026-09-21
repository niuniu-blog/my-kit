import AppKit
import Testing
@testable import ClipboardModule

@MainActor
@Suite struct AppIconProviderTests {
    @Test func returnsRealIconForInstalledApp() {
        let provider = AppIconProvider()
        let icon = provider.icon(forBundleID: "com.apple.finder")
        #expect(icon !== provider.fallback)
        #expect(icon.size.width > 0)
    }

    @Test func cachesIconPerBundleID() {
        let provider = AppIconProvider()
        let first = provider.icon(forBundleID: "com.apple.finder")
        let second = provider.icon(forBundleID: "com.apple.finder")
        #expect(first === second)
    }

    @Test func fallsBackWhenSourceIsUnknown() {
        let provider = AppIconProvider()
        #expect(provider.icon(forBundleID: nil) === provider.fallback)
        #expect(provider.icon(forBundleID: "") === provider.fallback)
    }

    @Test func fallsBackWhenAppIsNoLongerInstalled() {
        let provider = AppIconProvider()
        #expect(provider.icon(forBundleID: "com.example.mykit.does-not-exist") === provider.fallback)
    }
}
