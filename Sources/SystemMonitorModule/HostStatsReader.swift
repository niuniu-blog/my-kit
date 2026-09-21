import Darwin
import Foundation

/// 读取整机的 CPU tick 和内存统计。抽成协议是为了在测试里换成假实现。
public protocol HostStatsReading {
    func cpuTicks() -> CPUTicks?
    func memoryUsage() -> MemoryUsage?
}

/// 直接读 macOS 内核接口（"活动监视器"用的也是这些）。无需任何授权，一次调用是微秒级。
public struct HostStatsReader: HostStatsReading {
    /// mach_host_self() 每调一次都会多占一个端口引用，所以整个进程只取一次
    private static let host = mach_host_self()

    public init() {}

    public func cpuTicks() -> CPUTicks? {
        var coreCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(Self.host, PROCESSOR_CPU_LOAD_INFO, &coreCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        var cores: [CoreTicks] = []
        cores.reserveCapacity(Int(coreCount))
        for core in 0..<Int(coreCount) {
            let base = core * Int(CPU_STATE_MAX)
            cores.append(CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ))
        }
        return cores.isEmpty ? nil : CPUTicks(cores: cores)
    }

    public func memoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(Self.host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(Self.host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        return MemoryUsage.from(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}
