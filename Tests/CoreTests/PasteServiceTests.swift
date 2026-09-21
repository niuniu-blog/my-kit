import AppKit
import Testing
@testable import Core

@Suite struct PasteServiceTests {
    @Test func writePutsTextAndOwnMarkerOnPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("你好 MyKit", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "你好 MyKit")
        #expect(pasteboard.types?.contains(PasteService.ownWriteType) == true)
    }

    @Test func writeReplacesPreviousContent() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("mykit-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        PasteService.write("first", to: pasteboard)
        let countAfterFirst = pasteboard.changeCount
        PasteService.write("second", to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "second")
        #expect(pasteboard.changeCount > countAfterFirst)
    }

    @Test func ownWriteTypeMatchesTheSpecIdentifier() {
        #expect(PasteService.ownWriteType.rawValue == "com.imiros.mykit.own-write")
    }
}
