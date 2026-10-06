import Foundation

/// Measures whether skill matters: a bot that only chases coins should fail, while the
/// hazard-reading RouteAudit bot clears everything. Compile with -D ROUTE_HELPER and RouteAudit.swift.
@main
struct SkillAudit {
    static let seeds = Int(ProcessInfo.processInfo.environment["QA_SEEDS"] ?? "30") ?? 30

    /// Lane choice comes from coins (taking ramps to roof coins); never sideswipes a vehicle; vertical reflexes are
    /// perfect; never dodges what is ahead. Jumps or rolls whatever is directly in its lane with the reader's timing.
    static func followCoins(_ run: inout RunnerSimulation, route: BranchRoute) {
        guard !run.isPortalTransitioning else { return }
        defer { if run.routeChoiceAvailable { run.chooseRoute(route) } }
        if run.isWaterTraversal { RouteAudit.driveWater(&run); return }
        if run.activePowerUps[.jetpack] != nil { RouteAudit.drive(&run, route: route); return }
        if let d = run.portalDistance, d < 5.5, run.height < 0.05 { run.act(.jump); return }
        if let coin = run.entities.filter({ $0.kind == .coin && $0.z > 0.5 }).min(by: { $0.z < $1.z }) {
            // A roof coin means take that lane's ramp, aligned before it starts.
            var target = coin.lane
            if coin.y >= 3.0, let ramp = run.entities.first(where: { $0.kind == .ramp && $0.lane == coin.lane && $0.z > 0 && $0.z < coin.z }) { target = ramp.lane }
            let step = target < run.lane ? -1 : (target > run.lane ? 1 : 0)
            // Never steer into the side of a vehicle or obstacle overlapping the runner.
            let blocked = run.entities.contains { RouteAudit.hazards.contains($0.kind) && $0.lane == run.lane + step && $0.z - $0.length / 2 < 1.5 && $0.z + $0.length / 2 > -1.5 }
            if step < 0 && !blocked { run.act(.left) } else if step > 0 && !blocked { run.act(.right) }
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

    /// A coin is fair if some non-colliding posture at its position can collect it.
    static func coinIsFair(_ coin: TrackEntity, among entities: [TrackEntity]) -> Bool {
        // Flight coins (jetpack trails) are only reachable in flight, where ground colliders are inert. They are fair unless a drone overlaps them.
        if coin.y >= 5 {
            return !entities.contains { $0.kind == .airHazard && $0.lane == coin.lane &&
                abs($0.z - coin.z) < $0.length / 2 + 0.65 && abs($0.y - coin.y) < 2.0 }
        }
        for o in entities where o.lane == coin.lane && RouteAudit.hazards.contains(o.kind) && o.oncomingSpeed == coin.oncomingSpeed {
            guard abs(coin.z - o.z) < o.length / 2 + 0.35 + 0.3 else { continue }
            switch o.kind {
            case .arch, .laserSweep:
                // Only a roll at height 0 passes; it reaches coins below 2.05 m.
                if coin.y >= 2.05 { return false }
            default:
                let minimumSafeHeight: Double
                switch o.kind {
                case .barrier, .root: minimumSafeHeight = 1.03
                case .gap, .iceCrack: minimumSafeHeight = 0.4
                case .meteor: minimumSafeHeight = 2.5
                case .tram: minimumSafeHeight = RunnerSimulation.tramRoofHeight - 0.35
                case .buoy: minimumSafeHeight = 1.4
                default: minimumSafeHeight = 1.8 // waterTraffic
                }
                // Reachable at a safe height h if |y - (h + 0.9)| < 1.15 for some h >= minimum, and not low.
                if coin.y <= 0.6 || coin.y <= minimumSafeHeight - 0.25 { return false }
            }
        }
        return true
    }

    /// Records each newly generated coin once; counts it in `unfair` if it cannot be collected safely.
    static func checkCoins(_ run: RunnerSimulation, seen: inout Set<Int>, unfair: inout Int) {
        for coin in run.entities where coin.kind == .coin && !seen.contains(coin.id) {
            seen.insert(coin.id)
            if !coinIsFair(coin, among: run.entities) {
                unfair += 1
                if unfair <= 5 { print("UNFAIR coin id=\(coin.id) lane=\(coin.lane) z=\(coin.z) y=\(coin.y) mode=\(run.mode) world=\(run.worldStage)") }
            }
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // flush lines even if the precondition traps
        var unfair = 0
        for expert in [false, true] {
            // Odyssey: share of coin-follower runs that crash before completing world 2.
            for route in [BranchRoute.safe, .risky] {
                var failedEarly = 0, worlds: [Double] = []
                for seed in 1...seeds {
                    var run = RunnerSimulation()
                    run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                    var tick = 0, seen = Set<Int>()
                    while run.phase == .running && tick < 90_000 { followCoins(&run, route: route); run.update(dt: 1.0 / 60); tick += 1; checkCoins(run, seen: &seen, unfair: &unfair) }
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
                var seen = Set<Int>()
                while run.phase == .running && run.elapsed < 300 { followCoins(&run, route: .safe); run.update(dt: 1.0 / 60); checkCoins(run, seen: &seen, unfair: &unfair) }
                survival.append(run.elapsed)
            }
            print(String(format: "COIN-FOLLOWER endless expert=%@: median=%.1fs (target <%ds) mean=%.1fs",
                         String(expert), median(survival), expert ? 60 : 90, survival.reduce(0, +) / Double(seeds)))
            // Endless: the hazard reader must survive the full 300 s on every seed.
            var survived = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                var seen = Set<Int>()
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60); checkCoins(run, seen: &seen, unfair: &unfair) }
                if run.phase == .running { survived += 1 }
                else { print("READER-FAIL endless seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) lane=\(run.lane) reason=\(run.crashReason)") }
            }
            print("READER endless expert=\(expert): survived=\(survived)/\(seeds) (300s)")
            precondition(survived == seeds, "Hazard reader must survive every Endless seed")
        }
        print("FAIRNESS unfairCoins=\(unfair)")
        precondition(unfair == 0, "Every coin must be collectible without a forced collision")
        print("SkillAudit passed")
    }
}
