import AppKit
import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct AnnotationToolTests {
    @Test func nineToolsInToolbarOrder() {
        #expect(AnnotationTool.allCases == [.rectangle, .ellipse, .arrow, .line, .pen, .highlighter, .text, .mosaic, .number])
    }

    @Test func everyToolHasAChineseNameAndAValidSymbol() {
        let names = AnnotationTool.allCases.map(\.displayName)
        #expect(names == ["方框", "椭圆", "箭头", "直线", "画笔", "荧光笔", "文字", "马赛克", "序号"])
        for tool in AnnotationTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: nil) != nil, "\(tool.symbolName)")
        }
    }

    @Test func onlyMosaicHasNoColor() {
        #expect(!AnnotationTool.mosaic.usesColor)
        #expect(AnnotationTool.allCases.filter { !$0.usesColor } == [.mosaic])
    }
}

@Suite struct AnnotationStyleTests {
    @Test func sixColorsWithChineseNames() {
        #expect(AnnotationColor.allCases.map(\.displayName) == ["红", "黄", "绿", "蓝", "黑", "白"])
    }

    @Test func numberTextIsBlackOnLightColorsOnly() {
        #expect(AnnotationColor.allCases.filter(\.numberTextIsBlack) == [.yellow, .white])
    }

    @Test func cgColorCarriesComponentsAndAlpha() {
        let color = AnnotationColor.blue.cgColor(alpha: 0.4)
        let parts = color.components ?? []
        #expect(parts.count == 4)
        #expect(parts[0] == 0)
        #expect(parts[2] == 1)
        #expect(abs(parts[3] - 0.4) < 0.0001)
    }

    @Test func sizeMetricsPerTool() {
        #expect(AnnotationSize.allCases.map(\.displayName) == ["细", "中", "粗"])
        #expect(AnnotationSize.allCases.map(\.strokeWidth) == [2, 4, 6])
        #expect(AnnotationSize.allCases.map(\.highlighterWidth) == [12, 18, 24])
        #expect(AnnotationSize.allCases.map(\.fontSize) == [14, 20, 28])
        #expect(AnnotationSize.allCases.map(\.mosaicBlock) == [8, 12, 18])
        #expect(AnnotationSize.allCases.map(\.numberDiameter) == [22, 28, 36])
    }

    @Test func annotationKnowsWhetherItIsMosaicOrNumber() {
        let mosaic = Annotation(kind: .mosaic(CGRect(x: 0, y: 0, width: 10, height: 10)), color: .red, size: .medium)
        let number = Annotation(kind: .number(1, center: .zero), color: .red, size: .medium)
        #expect(mosaic.isMosaic)
        #expect(!mosaic.isNumber)
        #expect(number.isNumber)
        #expect(!number.isMosaic)
    }
}

@Suite struct AnnotationGeometryTests {
    private func close(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func rectIsNormalizedWhateverTheDragDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(AnnotationGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60), square: false) == expected)
        #expect(AnnotationGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20), square: false) == expected)
    }

    @Test func shiftMakesASquareFollowingTheDragDirection() {
        let downRight = AnnotationGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), square: true)
        #expect(downRight == CGRect(x: 10, y: 10, width: 40, height: 40))
        let upLeft = AnnotationGeometry.rect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 90, y: 40), square: true)
        #expect(upLeft == CGRect(x: 40, y: 40, width: 60, height: 60))
    }

    @Test func snappingKeepsLengthAndRoundsAngleTo45Degrees() {
        let start = CGPoint(x: 100, y: 100)
        // 略微偏离水平 → 吸附到水平，长度不变
        let nearlyHorizontal = CGPoint(x: 200, y: 108)
        let horizontalLength = AnnotationGeometry.distance(start, nearlyHorizontal)
        let horizontal = AnnotationGeometry.snappedEndpoint(from: start, to: nearlyHorizontal)
        #expect(close(horizontal, CGPoint(x: start.x + horizontalLength, y: start.y)))
        // 略微偏离竖直向上 → 吸附到竖直
        let nearlyVertical = CGPoint(x: 95, y: 0)
        let verticalLength = AnnotationGeometry.distance(start, nearlyVertical)
        let vertical = AnnotationGeometry.snappedEndpoint(from: start, to: nearlyVertical)
        #expect(close(vertical, CGPoint(x: start.x, y: start.y - verticalLength)))
        // 接近 45°
        let diagonal = AnnotationGeometry.snappedEndpoint(from: start, to: CGPoint(x: 160, y: 170))
        #expect(abs((diagonal.x - 100) - (diagonal.y - 100)) < 0.001)
        // 起点终点重合：原样返回
        #expect(AnnotationGeometry.snappedEndpoint(from: start, to: start) == start)
    }

    @Test func arrowHeadSizeFollowsLineWidth() {
        #expect(AnnotationGeometry.arrowHeadLength(lineWidth: 2) == 14)
        #expect(AnnotationGeometry.arrowHeadLength(lineWidth: 6) == 30)
    }

    @Test func arrowHeadIsSymmetricAroundTheShaft() {
        let head = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 100, y: 50), lineWidth: 4)
        #expect(head.count == 3)
        #expect(head[0] == CGPoint(x: 100, y: 50))
        let length: CGFloat = 22
        #expect(abs(AnnotationGeometry.distance(head[0], head[1]) - length) < 0.001)
        #expect(abs(AnnotationGeometry.distance(head[0], head[2]) - length) < 0.001)
        #expect(abs(head[1].x - head[2].x) < 0.001)                   // 两翼左右对称
        #expect(abs((head[1].y - 50) + (head[2].y - 50)) < 0.001)
        #expect(head[1].x < 100)
    }

    @Test func arrowShaftStopsBeforeTheTip() {
        let end = AnnotationGeometry.arrowShaftEnd(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        #expect(end.x > 70)
        #expect(end.x < 100)
        #expect(end.y == 0)
        // 箭头比头部还短：箭身长度为 0
        let tiny = AnnotationGeometry.arrowShaftEnd(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 0), lineWidth: 4)
        #expect(tiny == CGPoint(x: 0, y: 0))
    }
}
