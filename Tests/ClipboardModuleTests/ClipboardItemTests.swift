import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardItemTests {
    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(id: 1, text: text, appBundleID: nil, appName: nil, createdAt: Date(), lastUsedAt: Date())
    }

    @Test func summaryCollapsesWhitespaceAndNewlines() {
        #expect(item("  line one\n\n\tline   two  ").summary == "line one line two")
    }

    @Test func summaryTruncatesLongText() {
        let summary = item(String(repeating: "a", count: 500)).summary
        #expect(summary.count == 121)            // 120 个字符 + "…"
        #expect(summary.hasSuffix("…"))
    }

    @Test func shortTextIsNotTruncated() {
        #expect(item("短文本").summary == "短文本")
    }
}
