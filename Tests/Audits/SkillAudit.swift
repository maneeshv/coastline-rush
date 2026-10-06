import Foundation

/// Measures whether skill matters: a bot that only chases coins should fail, while the
/// hazard-reading RouteAudit bot clears everything. Compile with -D ROUTE_HELPER and RouteAudit.swift.
@main
struct SkillAudit {
    static let seeds = Int(ProcessInfo.processInfo.environment["QA_SEEDS"] ?? "30") ?? 30

    /// Lane choice comes from coins alone; vertical reflexes are perfect. Steers to the nearest coin ahead and never
    /// dodges sideways, but jumps or rolls whatever is directly in its current lane with the reader's timing.
    static func followCoins(_ run: inout RunnerSimulation, route: BranchRoute) {
        guard !run.isPortalTransitioning else { return }
        defer { if run.routeChoiceAvailable { run.chooseRoute(route) } }
        if run.isWaterTraversal { RouteAudit.driveWater(&run); return }
        if run.activePowerUps[.jetpack] != nil { RouteAudit.drive(&run, route: route); return }
        if let d = run.portalDistance, d < 5.5, run.height < 0.05 { run.act(.jump); return }
        if let coin = run.entities.filter({ $0.kind == .coin && $0.z > 0.5 }).min(by: { $0.z < $1.z }) {
            if coin.lane < run.lane { run.act(.left) } else if coin.lane > run.lane { run.act(.right) }
        }
        // Perfect reflexes for the nearest hazard in the occupied lane.
        let ahead = run.entities.filter { RouteAudit.hazards.contains($0.kind) && $0.z > 0 && abs(run.lateral - Double($0.lane)) < 0.55 }
        if let h = ahead.min(by: { $0.z < $1.z }) {
            switch h.kind {
            case .gap: if h.z < run.speed * 0.60, run.height < 0.05 { run.act(.jump) }
            case .iceCrack: if h.z < run.speed * 0.38, run.height < 0.05 { run.act(.jump) }
            case .barrier, .root: if h.z < run.speed * 0.32, run.height < 0.05 { run.act(.jump) }
            case .arch, .laserSweep: if h.z < run.speed * 0.30, !run.isRolling { run.act(.roll) }
            default: break
            }
        }
        // Fallback: coin height signal.
        guard let coin = run.entities.filter({ $0.kind == .coin && $0.z > 0.5 }).min(by: { $0.z < $1.z }),
              coin.lane == run.lane, coin.z < run.speed * 0.35 else { return }
        if coin.y >= 1.4, run.height < 0.05 { run.act(.jump) }
        if coin.y <= 0.6, !run.isRolling { run.act(.roll) }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // flush lines even if the precondition traps
        for expert in [false, true] {
            // Odyssey: share of coin-follower runs that crash before completing world 2.
            for route in [BranchRoute.safe, .risky] {
                var failedEarly = 0, worlds: [Double] = []
                for seed in 1...seeds {
                    var run = RunnerSimulation()
                    run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                    var tick = 0
                    while run.phase == .running && tick < 90_000 { followCoins(&run, route: route); run.update(dt: 1.0 / 60); tick += 1 }
                    if run.phase == .crashed && run.stageIndex < 2 { failedEarly += 1 }
                    worlds.append(Double(run.stageIndex) + run.stageProgress)
                }
                let share = Double(failedEarly) / Double(seeds)
                print(String(format: "COIN-FOLLOWER odyssey route=%@ expert=%@: failedBeforeWorld2=%d/%d (%.0f%%, target >=%d%%) meanWorlds=%.2f",
                             route.rawValue, String(expert), failedEarly, seeds, share * 100, expert ? 85 : 70, worlds.reduce(0, +) / Double(seeds)))
            }
            // Endless: coin-follower survival time, capped at 300 s.
            var survival: [Double] = []
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                while run.phase == .running && run.elapsed < 300 { followCoins(&run, route: .safe); run.update(dt: 1.0 / 60) }
                survival.append(run.elapsed)
            }
            print(String(format: "COIN-FOLLOWER endless expert=%@: median=%.1fs (target <%ds) mean=%.1fs",
                         String(expert), median(survival), expert ? 60 : 90, survival.reduce(0, +) / Double(seeds)))
            // Endless: the hazard reader must survive the full 300 s on every seed.
            var survived = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60) }
                if run.phase == .running { survived += 1 }
                else { print("READER-FAIL endless seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) lane=\(run.lane) reason=\(run.crashReason)") }
            }
            print("READER endless expert=\(expert): survived=\(survived)/\(seeds) (300s)")
            precondition(survived == seeds, "Hazard reader must survive every Endless seed")
        }
        print("SkillAudit passed")
    }
}
