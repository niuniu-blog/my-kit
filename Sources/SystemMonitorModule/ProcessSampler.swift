import Darwin
import Foundation

/// 某一时刻全部可读进程的采样。
public struct ProcessSnapshot: Equatable, Sendable {
    public let samples: [ProcessSample]
    /// 单调时钟（纳秒），用来算两次采样之间隔了多久
    public let timestampNanoseconds: UInt64

    public init(samples: [ProcessSample], timestampNanoseconds: UInt64) {
        self.samples = samples
        self.timestampNanoseconds = timestampNanoseconds
    }
}

/// 采样全部进程。会在后台线程调用，所以要求 Sendable。
public protocol ProcessSampling: Sendable {
    func sampleAll() -> ProcessSnapshot
}

/// 直接读内核接口，无需授权。属于 root 的系统进程（WindowServer、kernel_task 等）读不到，会被跳过；
/// 用户自己打开的软件全部可读。采样一遍约 8 毫秒。
public struct ProcessSampler: ProcessSampling {
    /// proc_pid_rusage 给的 CPU 时间是 mach 时间单位，要用 timebase 换算成纳秒（Apple 芯片上是 125/3）
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        if info.denom == 0 { info = mach_timebase_info_data_t(numer: 1, denom: 1) }
        return info
    }()

    public init() {}

    public func sampleAll() -> ProcessSnapshot {
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return ProcessSnapshot(samples: [], timestampNanoseconds: timestamp) }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)      // 留点余量：列表期间可能有新进程
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return ProcessSnapshot(samples: [], timestampNanoseconds: timestamp) }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(filled))
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
                }
            }
            guard status == 0 else { continue }                          // 无权读取或进程已退出
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = length > 0 ? String(cString: pathBuffer) : ""
            let machTime = usage.ri_user_time + usage.ri_system_time
            let nanoseconds = machTime * UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)
            samples.append(ProcessSample(
                pid: pid,
                cpuNanoseconds: nanoseconds,
                footprintBytes: usage.ri_phys_footprint,
                path: path
            ))
        }
        return ProcessSnapshot(samples: samples, timestampNanoseconds: timestamp)
    }
}
