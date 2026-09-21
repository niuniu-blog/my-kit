import CoreGraphics
import Foundation

/// "识别结果"窗口背后的状态。识别和复制都通过闭包注入，方便测试。
@MainActor
final class OCRResultModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var status = ""
    @Published private(set) var isRecognizing = false

    private let recognize: (CGImage) async throws -> String
    private let copy: (String) -> Void
    /// 每次识别加一；旧的识别结果回来时如果代数变了就丢弃
    private var generation = 0

    init(recognize: @escaping (CGImage) async throws -> String, copy: @escaping (String) -> Void) {
        self.recognize = recognize
        self.copy = copy
    }

    func run(on image: CGImage) async {
        generation += 1
        let expected = generation
        text = ""
        status = "正在识别…"
        isRecognizing = true
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await recognize(image))
        } catch {
            outcome = .failure(error)
        }
        guard expected == generation else { return }
        isRecognizing = false
        switch outcome {
        case .success(let recognized) where recognized.isEmpty:
            status = "没有识别到文字"
        case .success(let recognized):
            text = recognized
            copy(recognized)
            status = "✓ 已复制全文"
        case .failure(let error):
            status = "识别失败：\(error.localizedDescription)"
        }
    }

    /// "重新复制"：复制文本区当前的全部内容（含用户的修改）。
    func copyCurrentText() {
        guard !text.isEmpty else { return }
        copy(text)
        status = "✓ 已复制全文"
    }
}
