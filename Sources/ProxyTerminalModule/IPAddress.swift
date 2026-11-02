import Darwin
import Foundation

/// IP 地址的校验、规范化和从终端文字里提取。只用系统的 inet_pton / inet_ntop，不手写正则。
public enum IPAddress {
    /// 规范写法：IPv4 原样（去掉前后空白），IPv6 统一成小写压缩写法（如 `2001:db8::1`）。不是合法地址返回 nil。
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var v4 = in_addr()
        if inet_pton(AF_INET, trimmed, &v4) == 1 {
            return format(family: AF_INET, &v4, length: INET_ADDRSTRLEN)
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, trimmed, &v6) == 1 {
            return format(family: AF_INET6, &v6, length: INET6_ADDRSTRLEN)
        }
        return nil
    }

    public static func isValid(_ text: String) -> Bool {
        normalized(text) != nil
    }

    /// 两个地址是否相同（按规范写法比较）。任何一个不合法都算不同。
    public static func same(_ a: String, _ b: String) -> Bool {
        guard let a = normalized(a), let b = normalized(b) else { return false }
        return a == b
    }

    /// 从一段文字里找出第一个 IP 地址（按空白和常见标点切开后逐个校验）。
    public static func firstAddress(in text: String) -> String? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;\"'()[]<>"))
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            if let address = normalized(token) {
                return address
            }
        }
        return nil
    }

    private static func format<T>(family: Int32, _ address: inout T, length: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(length))
        guard inet_ntop(family, &address, &buffer, socklen_t(length)) != nil else { return nil }
        return String(cString: buffer)
    }
}
