import Foundation

/// 翻译前对识别文字做的纯文本处理。
enum TranslationText {
    /// 是否含有英文：至少出现一段连续 2 个以上的英文字母（单个字母如"A 级"不算）。
    static func containsEnglish(_ text: String) -> Bool {
        var run = 0
        for scalar in text.unicodeScalars {
            let isLetter = (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
            run = isLetter ? run + 1 : 0
            if run >= 2 { return true }
        }
        return false
    }

    /// 截图里的英文段落会被换行切成很多行，逐行翻译质量很差，所以先把同一段的行合并。
    /// 合并条件（同时满足）：上一行没有以句末标点结尾；上一行足够长（≥ 最长行的 60% 且 ≥ 25 个字符）
    /// —— 被换行切断的行一定接近整行宽度，而菜单项、标题这类短行不会被并到一起。空行总是分段。
    static func paragraphs(from text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let longest = lines.map(\.count).max() ?? 0
        let wrapThreshold = max(Double(longest) * 0.6, 25)
        let sentenceEnders: Set<Character> = [".", "!", "?", ":", ";", "。", "！", "？", "：", "；"]

        var result: [String] = []
        var current = ""
        var previousLine = ""
        for line in lines {
            if line.isEmpty {
                if !current.isEmpty { result.append(current); current = "" }
                previousLine = ""
                continue
            }
            let previousWasWrapped = !previousLine.isEmpty
                && Double(previousLine.count) >= wrapThreshold
                && !(previousLine.last.map(sentenceEnders.contains) ?? false)
            if current.isEmpty {
                current = line
            } else if previousWasWrapped {
                current += " " + line
            } else {
                result.append(current)
                current = line
            }
            previousLine = line
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
