import AppKit
import CoreGraphics

/// 一次截图会话内的马赛克缓存：同一个马赛克标注只像素化一次。遮罩结束即随视图一起释放。
final class MosaicCache {
    private struct Key: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, block: CGFloat
    }

    private var images: [Key: CGImage] = [:]

    func image(for rect: CGRect, block: CGFloat, make: () -> CGImage?) -> CGImage? {
        let key = Key(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, block: block)
        if let cached = images[key] { return cached }
        let created = make()
        images[key] = created
        return created
    }

    func removeAll() {
        images.removeAll()
    }
}

/// 把标注画出来：屏幕上实时绘制和导出图片用的是同一套代码。
enum AnnotationRenderer {
    /// 在 context 里画标注。调用前 context 必须已经是"选区内坐标"：
    /// 选区左上角为原点、y 向下、1 个单位 = 1pt（导出时由 flatten 按像素倍数放大）。
    /// 标注只画在选区范围内（超出部分被裁掉）。
    /// baseImage 是选区裁剪出来的原图，马赛克从它取像素。
    static func draw(
        _ items: [Annotation],
        in context: CGContext,
        selectionSize: CGSize,
        baseImage: CGImage?,
        cache: MosaicCache? = nil
    ) {
        guard !items.isEmpty else { return }
        let bounds = CGRect(origin: .zero, size: selectionSize)
        context.saveGState()
        context.clip(to: bounds)
        for item in items {
            context.saveGState()
            draw(item, in: context, bounds: bounds, baseImage: baseImage, cache: cache)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// 导出：把标注合成到选区裁剪图上，输出与 base 同样像素尺寸的新图。
    /// onlyMosaic = true 时只应用马赛克（给文字识别用：被遮住的内容不会被识别，其他标注不干扰识别）。
    /// 没有需要合成的标注时直接返回 base；位图上下文创建失败时返回 nil。
    static func flatten(base: CGImage, items: [Annotation], pointSize: CGSize, onlyMosaic: Bool = false) -> CGImage? {
        let applied = onlyMosaic ? items.filter(\.isMosaic) : items
        guard !applied.isEmpty else { return base }
        guard pointSize.width > 0, pointSize.height > 0,
              let context = CGContext(
                  data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let pixelSize = CGSize(width: base.width, height: base.height)
        context.draw(base, in: CGRect(origin: .zero, size: pixelSize))
        // CG 的原点在左下角：翻转成左上角原点，并按像素倍数放大，之后就可以直接用选区内坐标（pt）
        context.translateBy(x: 0, y: pixelSize.height)
        context.scaleBy(x: pixelSize.width / pointSize.width, y: -pixelSize.height / pointSize.height)
        draw(applied, in: context, selectionSize: pointSize, baseImage: base)
        return context.makeImage()
    }

    // MARK: 单个标注

    private static func draw(_ item: Annotation, in context: CGContext, bounds: CGRect, baseImage: CGImage?, cache: MosaicCache?) {
        let width = item.size.strokeWidth
        context.setStrokeColor(item.color.cgColor())
        context.setFillColor(item.color.cgColor())
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch item.kind {
        case .rectangle(let rect):
            context.setLineJoin(.miter)
            context.stroke(rect)

        case .ellipse(let rect):
            context.strokeEllipse(in: rect)

        case .line(let from, let to):
            strokePath([from, to], in: context)

        case .arrow(let from, let to):
            strokePath([from, AnnotationGeometry.arrowShaftEnd(from: from, to: to, lineWidth: width)], in: context)
            let head = AnnotationGeometry.arrowHead(from: from, to: to, lineWidth: width)
            context.beginPath()
            context.addLines(between: head)
            context.closePath()
            context.fillPath()

        case .pen(let points):
            strokePath(points, in: context)

        case .highlighter(let points):
            context.setStrokeColor(item.color.cgColor(alpha: annotationHighlighterAlpha))
            context.setLineWidth(item.size.highlighterWidth)
            context.setLineCap(.butt)
            strokePath(points, in: context)

        case .text(let string, let origin):
            drawText(string, at: origin, font: .systemFont(ofSize: item.size.fontSize, weight: .medium),
                     color: item.color.cgColor(), in: context)

        case .number(let number, let center):
            let diameter = item.size.numberDiameter
            context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
            let font = NSFont.systemFont(ofSize: (diameter * 0.55).rounded(), weight: .bold)
            let text = "\(number)" as NSString
            let textSize = text.size(withAttributes: [.font: font])
            let textColor: CGColor = item.color.numberTextIsBlack ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
            drawText(text as String, at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
                     font: font, color: textColor, in: context)

        case .mosaic(let rect):
            drawMosaic(rect.intersection(bounds), block: item.size.mosaicBlock, selectionSize: bounds.size,
                       baseImage: baseImage, cache: cache, in: context)
        }
    }

    private static func strokePath(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.beginPath()
        context.addLines(between: points)
        context.strokePath()
    }

    /// origin 是文字左上角。context 是 y 向下的，所以告诉 AppKit 这是一个 flipped 的上下文，文字才不会倒过来。
    private static func drawText(_ string: String, at origin: CGPoint, font: NSFont, color: CGColor, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .red,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (string as NSString).draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: 马赛克

    private static func drawMosaic(
        _ rect: CGRect, block: CGFloat, selectionSize: CGSize,
        baseImage: CGImage?, cache: MosaicCache?, in context: CGContext
    ) {
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return }
        let make = { pixelated(rect, block: block, selectionSize: selectionSize, baseImage: baseImage) }
        guard let image = cache?.image(for: rect, block: block, make: make) ?? make() else {
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))      // 取不到原图：退而求其次，盖一块灰色
            context.fill(rect)
            return
        }
        // 往 y 向下的上下文里画图片会上下颠倒，所以就地再翻一次
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none                        // 放大时保持方块的硬边
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// 把 rect 对应的原图缩小成"每个方块一个像素"的小图；再放大画回去就是马赛克。
    private static func pixelated(_ rect: CGRect, block: CGFloat, selectionSize: CGSize, baseImage: CGImage?) -> CGImage? {
        guard let baseImage, selectionSize.width > 0, selectionSize.height > 0 else { return nil }
        let scaleX = CGFloat(baseImage.width) / selectionSize.width
        let scaleY = CGFloat(baseImage.height) / selectionSize.height
        let pixelRect = CGRect(
            x: (rect.minX * scaleX).rounded(), y: (rect.minY * scaleY).rounded(),
            width: (rect.width * scaleX).rounded(), height: (rect.height * scaleY).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1,
              let source = baseImage.cropping(to: pixelRect)
        else { return nil }

        let columns = max(1, Int((rect.width / block).rounded()))
        let rows = max(1, Int((rect.height / block).rounded()))
        guard let small = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .medium                        // 缩小时取平均色
        small.draw(source, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        return small.makeImage()
    }
}
