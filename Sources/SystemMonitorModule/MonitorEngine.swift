import Foundation
import os

/// 采样调度。轻量的关键都在这里：
/// - 菜单栏显示开着：一个定时器，每次只读两个内核计数器（微秒级）；
/// - 菜单栏显示关着、菜单也没打开：什么都不运行；
/// - 菜单打开期间：额外在后台线程采样全部进程（约 8 毫秒），关闭后立刻停止并丢弃样本。
@MainActor
public final class MonitorEngine {
    public struct Totals: Equatable, Sendable {
        /// nil = 还没有两份快照，或读取失败
        public let cpu: CPULoad?
        public let memory: MemoryUsage?

        public init(cpu: CPULoad?, memory: MemoryUsage?) {
            self.cpu = cpu
            self.memory = memory
        }
    }

    public struct TopLists: Equatable, Sendable {
        /// nil = 正在统计（CPU 榜需要两次采样的差值）
        public let cpu: [TopEntry]?
        public let memory: [TopEntry]

        public init(cpu: [TopEntry]?, memory: [TopEntry]) {
            self.cpu = cpu
            self.memory = memory
        }
    }

    public var onTotals: ((Totals) -> Void)?
    public var onTopLists: ((TopLists) -> Void)?

    public private(set) var isMenuOpen = false
    /// 按当前状态是否应该有定时器在跑（菜单栏显示开着，或菜单正开着）
    public private(set) var wantsTimer = false
    public private(set) var lastTotals = Totals(cpu: nil, memory: nil)

    private let host: HostStatsReading
    private let processes: ProcessSampling
    private let settings: MonitorSettings
    private let firstCPUListDelay: TimeInterval
    private let usesTimer: Bool
    private let log = Logger(subsystem: "com.imiros.mykit", category: "monitor")

    private var timer: Timer?
    private var timerInterval = 0
    private var isStarted = false
    private var previousTicks: CPUTicks?
    private var lastLoad: CPULoad?
    private var previousSnapshot: ProcessSnapshot?
    /// 每次菜单开 / 关加一：后台采样回来时如果对不上，说明结果已经过时
    private var menuGeneration = 0
    private var isSamplingProcesses = false
    private var loggedFailures: Set<String> = []

    /// firstCPUListDelay：菜单打开后隔多久补第二次进程采样（CPU 榜要两次采样）。
    /// usesTimer = false 只在测试里用：不创建定时器，由测试直接调 tick()。
    public init(
        host: HostStatsReading = HostStatsReader(),
        processes: ProcessSampling = ProcessSampler(),
        settings: MonitorSettings = MonitorSettings(),
        firstCPUListDelay: TimeInterval = 1.0,
        usesTimer: Bool = true
    ) {
        self.host = host
        self.processes = processes
        self.settings = settings
        self.firstCPUListDelay = firstCPUListDelay
        self.usesTimer = usesTimer
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        applySettings()
        refreshTotals()           // 内存立刻就有；CPU 要等下一次才有差值
    }

    public func stop() {
        isStarted = false
        isMenuOpen = false
        menuGeneration += 1
        previousSnapshot = nil
        updateTimer()
    }

    /// 设置（是否显示、刷新间隔）变了之后调用，立即生效。
    public func applySettings() {
        updateTimer()
    }

    /// 菜单打开：立刻采样一次（内存榜马上有），约 1 秒后补第二次（CPU 榜出现），之后跟随定时器。
    public func menuDidOpen() async {
        setMenuOpen(true)
        let generation = menuGeneration
        await tick()
        if firstCPUListDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(firstCPUListDelay * 1_000_000_000))
        }
        guard isMenuOpen, generation == menuGeneration else { return }
        await tick()
    }

    public func setMenuOpen(_ open: Bool) {
        guard open != isMenuOpen else { return }
        isMenuOpen = open
        menuGeneration += 1
        previousSnapshot = nil        // 关闭即丢弃样本；重新打开从头统计
        updateTimer()
    }

    /// 立刻读一次总数（刚启动、刚改完设置时用，不用等一个间隔）。不该采样时什么都不做。
    public func refreshTotals() {
        guard isStarted, wantsTimer else { return }
        readTotals()
    }

    /// 一次刷新：读总数；菜单开着时再采样全部进程。定时器每次触发都调它，测试里直接调。
    public func tick() async {
        guard isStarted, wantsTimer else { return }
        readTotals()
        guard isMenuOpen else { return }
        await sampleProcesses()
    }

    // MARK: 总数

    private func readTotals() {
        let memory = host.memoryUsage()
        if memory == nil { logOnce("memory", "读取内存统计失败") }

        if let ticks = host.cpuTicks() {
            if let previous = previousTicks, let load = CPULoad.between(previous, ticks) {
                lastLoad = load       // 两次采样太近（Δ = 0）时沿用上一次的结果
            }
            previousTicks = ticks
        } else {
            logOnce("cpu", "读取 CPU 统计失败")
            previousTicks = nil
            lastLoad = nil
        }

        let totals = Totals(cpu: lastLoad, memory: memory)
        lastTotals = totals
        onTotals?(totals)
    }

    // MARK: 进程排行

    private func sampleProcesses() async {
        guard !isSamplingProcesses else { return }
        isSamplingProcesses = true
        defer { isSamplingProcesses = false }

        let generation = menuGeneration
        let sampler = processes
        let snapshot = await Task.detached(priority: .utility) { sampler.sampleAll() }.value
        guard isMenuOpen, generation == menuGeneration else { return }      // 期间菜单已经关了

        var cpu: [TopEntry]?
        if let previous = previousSnapshot, snapshot.timestampNanoseconds > previous.timestampNanoseconds {
            cpu = TopProcesses.byCPU(
                earlier: previous.samples,
                later: snapshot.samples,
                intervalNanoseconds: snapshot.timestampNanoseconds - previous.timestampNanoseconds
            )
        }
        previousSnapshot = snapshot
        onTopLists?(TopLists(cpu: cpu, memory: TopProcesses.byMemory(snapshot.samples)))
    }

    // MARK: 定时器

    private func updateTimer() {
        let wanted = isStarted && (settings.showInMenuBar || isMenuOpen)
        let interval = settings.interval
        if wanted == wantsTimer, !wanted || interval == timerInterval { return }

        wantsTimer = wanted
        timerInterval = interval
        timer?.invalidate()
        timer = nil

        guard wanted else {
            // 停止采样后，旧快照和现在隔得太久，下次不能拿来算差值
            previousTicks = nil
            lastLoad = nil
            return
        }
        guard usesTimer else { return }
        let timer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
        timer.tolerance = TimeInterval(interval) * 0.2
        RunLoop.main.add(timer, forMode: .common)      // .common：菜单打开（事件跟踪模式）时也照常触发
        self.timer = timer
    }

    private func logOnce(_ key: String, _ message: String) {
        guard !loggedFailures.contains(key) else { return }
        loggedFailures.insert(key)
        log.error("\(message, privacy: .public)")
    }
}
