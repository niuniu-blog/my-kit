import AppKit
import Testing
@testable import Core

@MainActor
@Suite struct StatusItemImageTests {
    @Test func layoutPutsTheIconLeftAndCentersBothVertically() {
        let layout = StatusItemImage.layout(iconSize: CGSize(width: 18, height: 16), textSize: CGSize(width: 60.2, height: 20))

        #expect(layout.size == CGSize(width: 83, height: 22))          // 18 + 4 间距 + 61（向上取整）
        #expect(layout.iconRect == CGRect(x: 0, y: 3, width: 18, height: 16))
        #expect(layout.textRect == CGRect(x: 22, y: 1, width: 61, height: 20))
    }

    @Test func layoutWithoutTextIsJustTheIcon() {
        let layout = StatusItemImage.layout(iconSize: CGSize(width: 18, height: 16), textSize: .zero)
        #expect(layout.size == CGSize(width: 18, height: 22))
        #expect(layout.textRect.width == 0)
    }

    @Test func plainTextGivesATemplateImageSoTheSystemPicksTheRightColor() throws {
        let text = NSAttributedString(string: "CPU 12%\n内存 63%", attributes: [.font: NSFont.systemFont(ofSize: 9)])
        let image = try #require(StatusItemImage.compose(symbolName: "square.stack.3d.up", text: text))
        #expect(image.isTemplate)
        #expect(image.size.height == 22)
        #expect(image.size.width > 40)
    }

    @Test func coloredWarningTextGivesANonTemplateImage() throws {
        let text = NSMutableAttributedString(string: "CPU 91%", attributes: [.font: NSFont.systemFont(ofSize: 9)])
        text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 4, length: 3))
        let image = try #require(StatusItemImage.compose(symbolName: "square.stack.3d.up", text: text))
        #expect(!image.isTemplate)                                     // 模板图只有一种颜色，红色会丢
    }

    @Test func unknownSymbolGivesNil() {
        #expect(StatusItemImage.compose(symbolName: "this.symbol.does.not.exist", text: nil) == nil)
    }
}
