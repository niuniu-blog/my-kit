import Foundation

public enum ScreenshotFileNamer {
    /// 形如 "MyKit 2026-09-21 14.32.05"（不含扩展名）。
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "MyKit " + formatter.string(from: date)
    }

    /// 形如 "MyKit 2026-09-21 14.32.05.png"；同名已存在则依次尝试 " (2)"、" (3)"……
    /// exists 由调用方提供（传入文件名，返回该文件是否已存在）。
    public static func fileName(for date: Date, timeZone: TimeZone = .current, exists: (String) -> Bool) -> String {
        let base = baseName(for: date, timeZone: timeZone)
        var candidate = base + ".png"
        var counter = 2
        while exists(candidate) {
            candidate = "\(base) (\(counter)).png"
            counter += 1
        }
        return candidate
    }
}
