import Darwin
import Foundation

/// 一个网卡从开机到现在累计收 / 发的字节数
public struct InterfaceBytes: Equatable, Sendable {
    public let received: UInt64
    public let sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

/// 某一时刻所有网卡的累计字节数（键是接口名，如 en0）
public struct NetworkCounters: Equatable, Sendable {
    public let interfaces: [String: InterfaceBytes]

    public init(interfaces: [String: InterfaceBytes]) {
        self.interfaces = interfaces
    }
}

/// 网速（字节 / 秒）。由两份累计值的差除以间隔得到。纯计算。
public struct NetworkSpeed: Equatable, Sendable {
    public let downBytesPerSecond: Double
    public let upBytesPerSecond: Double

    public init(downBytesPerSecond: Double, upBytesPerSecond: Double) {
        self.downBytesPerSecond = downBytesPerSecond
        self.upBytesPerSecond = upBytesPerSecond
    }

    /// 只统计真正联网的接口（en*：以太网、Wi-Fi、USB / 雷雳网卡、手机热点）。
    /// 回环 lo0（本机代理的流量会在上面再出现一遍）、VPN 的 utun（最终也走 en*）、
    /// awdl / bridge 等都不算，否则同一份流量会被算两遍。
    public static func countsTowardsSpeed(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("en")
    }

    public static func between(_ earlier: NetworkCounters, _ later: NetworkCounters, seconds: TimeInterval) -> NetworkSpeed? {
        guard seconds > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, now) in later.interfaces where countsTowardsSpeed(name) {
            // 刚出现的网卡：累计值不是这一轮的流量；计数变小：网卡被重置。两种情况这一轮都跳过。
            guard let before = earlier.interfaces[name], now.received >= before.received, now.sent >= before.sent else { continue }
            received += now.received - before.received
            sent += now.sent - before.sent
        }
        return NetworkSpeed(downBytesPerSecond: Double(received) / seconds, upBytesPerSecond: Double(sent) / seconds)
    }
}

/// 从内核读各网卡的 64 位累计字节数（sysctl NET_RT_IFLIST2）。约 1 毫秒，无需授权。
enum NetworkCountersReader {
    static func read() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var interfaces: [String: InterfaceBytes] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(info.ifm_index), &nameBuffer) != nil {
                        interfaces[String(cString: nameBuffer)] = InterfaceBytes(
                            received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return interfaces.isEmpty ? nil : NetworkCounters(interfaces: interfaces)
    }
}
