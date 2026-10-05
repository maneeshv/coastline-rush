import Foundation

/// Ephemeral copies of the last three seconds. Playback never touches the live run.
struct CrashReplayBuffer {
    struct Frame { var run: RunnerSimulation; var worldTime: Double }
    private(set) var frames: [Frame] = []
    private var lastSample = -Double.infinity
    var duration: Double { max(0, (frames.last?.run.elapsed ?? 0) - (frames.first?.run.elapsed ?? 0)) }
    mutating func append(_ run: RunnerSimulation, worldTime: Double, force: Bool = false) {
        guard force || run.elapsed - lastSample >= 1.0 / 15 else { return }
        guard frames.last?.run.elapsed != run.elapsed else { return }
        lastSample = run.elapsed
        frames.append(Frame(run: run, worldTime: worldTime))
        while frames.count > 48 || (frames.count > 1 && run.elapsed - frames[1].run.elapsed > 3) { frames.removeFirst() }
    }
    func frame(at fraction: Double) -> Frame? {
        guard let first = frames.first else { return nil }
        let target = first.run.elapsed + min(1, max(0, fraction.isFinite ? fraction : 0)) * duration
        return frames.min { abs($0.run.elapsed - target) < abs($1.run.elapsed - target) }
    }
}

/// Local, bounded measurements. Callback cadence is not GPU presentation timing.
struct RunDiagnostics {
    private var intervals: [Double] = []
    private var cpuTicks: [Double] = []
    private var inputDelays: [Double] = []
    private var pendingInput: Double?
    private(set) var measuredFrames = 0
    mutating func markInput(at time: Double) { if pendingInput == nil { pendingInput = time } }
    mutating func recordInterval(_ seconds: Double) {
        guard seconds > 0, seconds < 2, seconds.isFinite else { return }
        measuredFrames += 1
        intervals.append(seconds * 1_000)
        if intervals.count > 720 { intervals.removeFirst(intervals.count - 720) }
    }
    mutating func beginTick(at time: Double) {
        if let input = pendingInput { inputDelays.append(max(0, time - input) * 1_000); pendingInput = nil }
        if inputDelays.count > 120 { inputDelays.removeFirst(inputDelays.count - 120) }
    }
    mutating func endTick(milliseconds: Double) {
        cpuTicks.append(max(0, milliseconds))
        if cpuTicks.count > 720 { cpuTicks.removeFirst(cpuTicks.count - 720) }
    }
    func report(quality: String, thermal: String, replayFrames: Int) -> String {
        func percentile(_ samples: [Double], _ fraction: Double) -> String {
            guard !samples.isEmpty else { return "—" }
            let sorted = samples.sorted()
            return String(format: "%.1f ms", sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))])
        }
        let fps = intervals.isEmpty ? "—" : String(format: "%.1f", 1_000 / (intervals.reduce(0, +) / Double(intervals.count)))
        return "Render callbacks: \(fps)/s · \(measuredFrames) measured\nCallback interval p95 / p99: \(percentile(intervals, 0.95)) / \(percentile(intervals, 0.99))\nCallbacks over 33 ms: \(intervals.filter { $0 > 33.34 }.count) / \(intervals.count)\nMain simulation + scene update p95: \(percentile(cpuTicks, 0.95))\nInput received → next tick p95: \(percentile(inputDelays, 0.95))\nQuality: \(quality) · Thermal: \(thermal)\nReplay frames: \(replayFrames) / 48\nRolling 720-frame window. These are local CPU/callback measurements, not GPU presentation, touch-to-photon, or battery measurements."
    }
}
