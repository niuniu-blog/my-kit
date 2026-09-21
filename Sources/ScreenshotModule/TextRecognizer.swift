import CoreGraphics
import Foundation
import Vision

/// 文字识别（OCR）。用系统自带的 Vision，离线，支持简体中文、繁体中文、英文。
public enum TextRecognizer {
    /// 识别出的一段文字及其位置。box 是 Vision 的归一化坐标：0…1，**左下角为原点**。
    public struct Fragment: Equatable {
        public let text: String
        public let box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// 识别图片里的文字。没有文字时返回空字符串。识别在后台线程执行。
    public static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> Fragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return Fragment(text: candidate.string, box: observation.boundingBox)
            }
            return orderedText(from: fragments)
        }.value
    }

    /// 按阅读顺序拼成文本：自上而下分行；垂直位置接近的片段算同一行，行内自左而右、用空格连接；行与行之间换行。
    public static func orderedText(from fragments: [Fragment]) -> String {
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }     // Vision 的 y 向上，midY 大的在上面
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let reference = rows.last?.first,
               abs(reference.box.midY - fragment.box.midY) < min(reference.box.height, fragment.box.height) / 2 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows
            .map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
