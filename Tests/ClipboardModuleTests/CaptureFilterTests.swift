import Testing
@testable import ClipboardModule

@Suite struct CaptureFilterTests {
    private let plain = ["public.utf8-plain-text"]

    @Test func recordsPlainText() {
        #expect(CaptureFilter.decide(types: plain, string: "hello") == .record("hello"))
    }

    @Test func keepsOriginalTextIncludingSurroundingWhitespace() {
        #expect(CaptureFilter.decide(types: plain, string: "  indented\n") == .record("  indented\n"))
    }

    @Test func skipsWhenNoString() {
        #expect(CaptureFilter.decide(types: ["public.png"], string: nil) == .skip)
    }

    @Test func skipsBlankText() {
        #expect(CaptureFilter.decide(types: plain, string: " \n\t ") == .skip)
        #expect(CaptureFilter.decide(types: plain, string: "") == .skip)
    }

    @Test func skipsConcealedContentFromPasswordManagers() {
        let types = plain + ["org.nspasteboard.ConcealedType"]
        #expect(CaptureFilter.decide(types: types, string: "hunter2") == .skip)
    }

    @Test func skipsTransientContent() {
        let types = plain + ["org.nspasteboard.TransientType"]
        #expect(CaptureFilter.decide(types: types, string: "temp") == .skip)
    }

    @Test func skipsTextLargerThanOneMegabyte() {
        let big = String(repeating: "a", count: CaptureFilter.maxBytes + 1)
        #expect(CaptureFilter.decide(types: plain, string: big) == .skip)
    }

    @Test func acceptsTextExactlyAtLimit() {
        let atLimit = String(repeating: "a", count: CaptureFilter.maxBytes)
        #expect(CaptureFilter.decide(types: plain, string: atLimit) == .record(atLimit))
    }

    @Test func sizeLimitCountsUTF8BytesNotCharacters() {
        let chinese = String(repeating: "中", count: CaptureFilter.maxBytes / 3 + 1)   // 每个字 3 字节
        #expect(CaptureFilter.decide(types: plain, string: chinese) == .skip)
    }

    @Test func recognisesOwnWrites() {
        let types = plain + [CaptureFilter.ownWriteType]
        #expect(CaptureFilter.decide(types: types, string: "pasted by MyKit") == .touchOwn("pasted by MyKit"))
    }

    @Test func concealedWinsOverOwnWrite() {
        let types = plain + [CaptureFilter.ownWriteType, "org.nspasteboard.ConcealedType"]
        #expect(CaptureFilter.decide(types: types, string: "x") == .skip)
    }
}
