import Foundation

/// Measures whether skill matters: a bot that only chases coins should fail, while the
/// hazard-reading RouteAudit bot clears everything. Coin-follower and reader survival numbers are
/// informational until G3. Binding from G1: placed safe-line share <= 35% per mode, and 0 unfair
/// coins and pickups (first sight and collection time). Compile with -D ROUTE_HELPER and RouteAudit.swift.
@main
struct SkillAudit {
    static var patternsByWorld: [WorldStage: Set<Int>] = [:]
    static var bagRepeats = 0
    static var escalationSeen: [Bool: Set<Int>] = [:]
    static var earlyEscalation = 0
    static var teachingViolations = 0, invitationsAfterTeaching = 0
    /// Standard teaching rows (Odyssey rows 0-3 of each world; Endless/Sprint rows before 160 m) lay only safe or action
    /// lines, and the rows right after them sometimes lay risk or bait lines, so teaching really ends.
    static func checkTeaching(_ run: RunnerSimulation) {
        guard !run.expert else { return }
        let limit = run.mode == .odyssey ? 4 : 160
        for p in run.placedLineLog {
            if p.position < limit && p.line != .safe && p.line != .action { teachingViolations += 1 }
            if p.position >= limit && p.position < limit * 2 && (p.line == .risk || p.line == .bait) { invitationsAfterTeaching += 1 }
        }
    }
    /// Endless row types 0-6 (0/1 full-width jump/slide, 2 compound, 3 lane-changer, 4 gap wall, 5 stack, 6 timed laser)
    /// must all appear, each only after its gate: full-width at half the gate, the rest at the gate (60 s, Expert 30 s).
    static func checkEscalation(_ run: RunnerSimulation) {
        let gate = run.expert ? 30.0 : 60.0
        for (kind, first) in run.escalationFirstSeen {
            escalationSeen[run.expert, default: []].insert(kind)
            if first < (kind <= 1 ? gate / 2 : gate) { earlyEscalation += 1 }
        }
    }
    /// Every world must build 10+ effective patterns (14+ overall), and a bag row never repeats one of the
    /// previous three rows of its world.
    static func checkPatterns(_ log: [PatternRecord]) {
        var window: [Int] = [], world: WorldStage? = nil
        for record in log {
            if record.world != world { window = []; world = record.world }
            patternsByWorld[record.world, default: []].insert(record.pattern)
            if record.fromBag && window.contains(record.pattern) {
                bagRepeats += 1
                if bagRepeats <= 5 { print("BAG-REPEAT world=\(record.world) pattern=\(record.pattern) after \(window)") }
            }
            window = Array((window + [record.pattern]).suffix(3))
        }
    }

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
            let blocked = run.entities.contains { RouteAudit.hazards.contains($0.kind) && $0.arrivalLane == run.lane + step && $0.z - $0.length / 2 < 1.5 && $0.z + $0.length / 2 > -1.5 }
            if step < 0 && !blocked { run.act(.left) } else if step > 0 && !blocked { run.act(.right) }
        }
        // Perfect reflexes for the nearest hazard in the occupied lane.
        let ahead = run.entities.filter { RouteAudit.hazards.contains($0.kind) && $0.z > 0 && abs(run.lateral - (Double($0.lane) + $0.laneOffset())) < run.lateralTolerance }
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

    /// A coin or pickup is fair if some non-colliding posture at its position can collect it.
    /// First sight compares hazards moving with the item, with a small margin. At collection time every hazard in
    /// the lane counts at its live position, and the window is the true collect/collide overlap (0.85 + the difficulty's collision padding).
    static func coinIsFair(_ coin: TrackEntity, among entities: [TrackEntity], expert: Bool, atCollection: Bool = false) -> Bool {
        let margin = atCollection ? RunnerSimulation.coinOverlap(expert: expert) : 0.65
        // Flight coins (jetpack trails) are only reachable in flight, where ground colliders are inert. They are fair unless a drone overlaps them.
        if coin.y >= 5 {
            return !entities.contains { $0.kind == .airHazard && $0.lane == coin.lane &&
                abs($0.z - coin.z) < $0.length / 2 + margin && abs($0.y - coin.y) < 2.0 }
        }
        // First sight: a lane-changer is still in its origin lane (live lane); at collection its shift is complete.
        for o in entities where RouteAudit.hazards.contains(o.kind) && (atCollection || o.oncomingSpeed == coin.oncomingSpeed)
            && (atCollection ? o.arrivalLane : Int((Double(o.lane) + o.laneOffset()).rounded())) == coin.lane {
            guard abs(coin.z - o.z) < o.length / 2 + margin else { continue }
            switch o.kind {
            case .wall, .stack:
                return false // nothing reaches a coin inside a solid wall
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

    static func isPickup(_ e: TrackEntity) -> Bool { e.kind == .coin || e.kind == .key || PowerUp(rawValue: e.kind.rawValue) != nil }

    /// Checks each coin, key and power-up at first sight, and again every frame it is within reach (live hazard positions).
    /// Each item counts at most once per check in `unfair`.
    static func checkCoins(_ run: RunnerSimulation, seen: inout Set<Int>, flagged: inout Set<Int>, unfair: inout Int) {
        func report(_ item: TrackEntity, _ check: String) {
            unfair += 1
            guard unfair <= 8 else { return }
            let hazard = run.entities.filter { $0.lane == item.lane && RouteAudit.hazards.contains($0.kind) }.min { abs($0.z - item.z) < abs($1.z - item.z) }
            print("UNFAIR \(check) \(item.kind) id=\(item.id) lane=\(item.lane) z=\(item.z) y=\(item.y) mode=\(run.mode) world=\(run.worldStage) t=\(String(format: "%.1f", run.elapsed))"
                  + (hazard.map { " near \($0.kind) id=\($0.id) z=\($0.z) length=\($0.length) oncoming=\($0.oncomingSpeed)" } ?? ""))
        }
        for item in run.entities where isPickup(item) {
            if seen.insert(item.id).inserted && !coinIsFair(item, among: run.entities, expert: run.expert) { report(item, "first-sight") }
            // One frame of travel wider, so an item that enters reach and is collected in the same frame is still checked.
            if abs(item.z) < RunnerSimulation.coinOverlap(expert: run.expert) + run.speed / 60 && !flagged.contains(item.id) && !coinIsFair(item, among: run.entities, expert: run.expert, atCollection: true) {
                flagged.insert(item.id)
                report(item, "collection")
            }
        }
    }

    /// Per-run audit state. Violation counters and coverage are global across runs.
    struct Watch { var seen: Set<Int> = [], flagged: Set<Int> = [], bait: Set<Int> = [], telegraphs: Set<Int> = [], features: Set<Int> = [] }
    static var unfair = 0, baitViolations = 0, telegraphViolations = 0
    static var shiftChecks = 0, impactChecks = 0, collapseChecks = 0
    static var coverage: [String: Set<WorldStage>] = [:]

    static func check(_ run: RunnerSimulation, _ watch: inout Watch) {
        checkCoins(run, seen: &watch.seen, flagged: &watch.flagged, unfair: &unfair)
        checkBaitEscapes(run, checked: &watch.bait, violations: &baitViolations)
        checkTelegraphs(run, done: &watch.telegraphs, violations: &telegraphViolations)
        if run.mode == .odyssey {
            for e in run.entities where watch.features.insert(e.id).inserted {
                if let feature = hazardFeature(e) { coverage[feature, default: []].insert(run.worldStage) }
                // Pattern 12's rock has already landed at first sight (activeFrom beyond its z); ordinary strike rocks have not.
                if e.kind == .meteor && e.activeFrom.isFinite && e.activeFrom > e.z { coverage["meteor-landed", default: []].insert(run.worldStage) }
            }
        }
    }

    /// The G2 hazard an entity shows, read from its visible state.
    static func hazardFeature(_ e: TrackEntity) -> String? {
        if e.targetLane != nil { return "lane-changer" }
        if e.kind == .laserSweep && e.cyclePhase >= 0 { return "timed-laser" }
        if e.kind == .wall { return "gap-wall" }
        if e.kind == .stack { return "stacked" }
        if e.kind == .meteor && e.activeFrom.isFinite { return "real-meteor" }
        if (e.kind == .gap || e.kind == .iceCrack) && e.activeFrom.isFinite { return "collapsing-deck" }
        return nil
    }

    /// G2 hazards and the Odyssey worlds that must generate them. Each hazard task adds its entry.
    static let hazardWorlds: [String: Set<WorldStage>] = [
        "lane-changer": [.harbor, .mars, .cryo],
        "timed-laser": [.orbit, .verdant, .forge],
        "gap-wall": Set(WorldStage.allCases),
        "stacked": Set(WorldStage.allCases),
        "real-meteor": [.mars],
        "meteor-landed": [.mars],
        "collapsing-deck": [.orbit, .cryo],
    ]

    /// Live check of the G2 lead-time rules at the moment each change happens, against the runner's real speed:
    /// a lane shift completes >= 1.0 s (Expert 0.8 s) ahead, a meteor lands >= 1.0 s ahead, a deck opens >= 0.5 s ahead.
    static func checkTelegraphs(_ run: RunnerSimulation, done: inout Set<Int>, violations: inout Int) {
        for e in run.entities where !done.contains(e.id) {
            let closing = run.speed + e.oncomingSpeed // oncoming entities close faster
            let slack = closing / 60 + 0.01 // the change is seen up to one frame late
            let need: Double
            if e.targetLane != nil && e.motionLength > 0 && !e.isShifting { need = run.expert ? 0.8 : 1.0; shiftChecks += 1 }
            else if e.activeFrom.isFinite && e.isActive {
                need = e.kind == .meteor ? 1.0 : 0.5
                if e.kind == .meteor { impactChecks += 1 } else { collapseChecks += 1 }
            }
            else { continue }
            done.insert(e.id)
            let edge = e.z - e.length / 2 - run.collisionPadding
            if edge + slack < closing * need {
                violations += 1
                if violations <= 5 { print("TELEGRAPH late \(e.kind) id=\(e.id) edge=\(edge) needs=\(closing * need) world=\(run.worldStage) expert=\(run.expert)") }
            }
        }
    }

    /// A bait line's last coin must leave one adjacent lane clear of every hazard, from that coin until the runner
    /// has passed the solid and stepped back in behind it (far edge + resume switch), with collision padding.
    /// Checked once the coin is within 2 s, when every row that could block the escape has been generated.
    static func checkBaitEscapes(_ run: RunnerSimulation, checked: inout Set<Int>, violations: inout Int) {
        for (coinID, solidID) in run.baitEscapes where !checked.contains(coinID) {
            guard let coin = run.entities.first(where: { $0.id == coinID }), coin.z < run.speed * 2,
                  let solid = run.entities.first(where: { $0.id == solidID }) else { continue }
            checked.insert(coinID)
            let from = coin.z - run.collisionPadding, to = solid.z + solid.length / 2 + max(2, run.speed * 0.15) + run.collisionPadding
            // A jump in the bait lane before the solid (an arc bait's row) is leapt anyway; that leap also clears
            // a jump hazard in the same row of the escape lane.
            let jumps: Set<EntityKind> = [.gap, .barrier, .root, .iceCrack]
            let leaps = run.entities.filter { jumps.contains($0.kind) && $0.lane == coin.lane && $0.z + $0.length / 2 > coin.z - 1 && $0.z < solid.z }
            let escapes = [solid.arrivalLane - 1, solid.arrivalLane + 1].filter { lane in
                (-1...1).contains(lane) && !run.entities.contains { o in
                    RouteAudit.hazards.contains(o.kind) && o.arrivalLane == lane && o.z + o.length / 2 > from && o.z - o.length / 2 < to &&
                        !(jumps.contains(o.kind) && leaps.contains { abs($0.z - o.z) < 1 })
                }
            }
            if escapes.isEmpty {
                violations += 1
                if violations <= 5 {
                    print("BAIT-ESCAPE blocked coin=\(coinID) lane=\(coin.lane) z=\(coin.z) solid=\(solid.kind) lane=\(solid.lane) z=\(solid.z) length=\(solid.length) mode=\(run.mode) world=\(run.worldStage) expert=\(run.expert)")
                }
            }
        }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // flush lines even if the precondition traps
        var tally: [RunnerSimulation.CoinLine: Int] = [:]
        for roll in UInt64(0)..<100 { tally[RunnerSimulation.coinLine(roll: roll, actionable: true, solid: true), default: 0] += 1 }
        precondition(tally[.safe, default: 0] <= 35, "At most 35% of rows may mark the safe lane")
        precondition(tally[.action, default: 0] > 0 && tally[.risk, default: 0] > 0 && tally[.bait, default: 0] > 0, "Every coin line type must occur")
        precondition(RunnerSimulation.coinLine(roll: 70, actionable: false, solid: false) == .safe, "Rows without hazards fall back to the safe line")
        print("COIN-LINES safe=\(tally[.safe, default: 0]) action=\(tally[.action, default: 0]) risk=\(tally[.risk, default: 0]) bait=\(tally[.bait, default: 0]) per 100 rows")
        // Coin lines the generator actually laid in the reader's runs, after fallbacks.
        var placed: [RunMode: [RunnerSimulation.CoinLine: Int]] = [:]
        for expert in [false, true] {
            // Odyssey: share of coin-follower runs that crash before completing world 2.
            for route in [BranchRoute.safe, .risky] {
                var failedEarly = 0, worlds: [Double] = []
                for seed in 1...seeds {
                    var run = RunnerSimulation()
                    run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                    var tick = 0, watch = Watch()
                    while run.phase == .running && tick < 90_000 { followCoins(&run, route: route); run.update(dt: 1.0 / 60); tick += 1; check(run, &watch) }
                    if run.phase == .crashed && run.stageIndex < 2 { failedEarly += 1 }
                    worlds.append(Double(run.stageIndex) + run.stageProgress)
                }
                let share = Double(failedEarly) / Double(seeds)
                print(String(format: "COIN-FOLLOWER odyssey route=%@ expert=%@: failedBeforeWorld2=%d/%d (%.0f%%, informational; binds at G3) meanWorlds=%.2f",
                             route.rawValue, String(expert), failedEarly, seeds, share * 100, worlds.reduce(0, +) / Double(seeds)))
            }
            // Odyssey: the hazard reader runs every world, fork and finale; every coin and pickup it passes is audited.
            for route in [BranchRoute.safe, .risky] {
                var cleared = 0
                for seed in 1...seeds {
                    var run = RunnerSimulation()
                    run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                    var tick = 0, watch = Watch()
                    while run.phase == .running && tick < 90_000 { RouteAudit.drive(&run, route: route); run.update(dt: 1.0 / 60); tick += 1; check(run, &watch) }
                    placed[run.mode, default: [:]].merge(run.placedCoinLines, uniquingKeysWith: +)
                    checkPatterns(run.patternLog)
                    checkTeaching(run)
                    if run.phase == .finished { cleared += 1 }
                    else { print("READER-FAIL odyssey seed=\(seed) route=\(route.rawValue) expert=\(expert) world=\(run.worldStage) reason=\(run.crashReason)") }
                }
                print("READER odyssey route=\(route.rawValue) expert=\(expert): cleared=\(cleared)/\(seeds)")
                precondition(cleared == seeds, "Hazard reader must clear every Odyssey seed so fairness covers all worlds")
            }
            // Endless: coin-follower survival time, capped at 300 s.
            var survival: [Double] = []
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                var watch = Watch()
                while run.phase == .running && run.elapsed < 300 { followCoins(&run, route: .safe); run.update(dt: 1.0 / 60); check(run, &watch) }
                survival.append(run.elapsed)
            }
            print(String(format: "COIN-FOLLOWER endless expert=%@: median=%.1fs (informational; binds at G3) mean=%.1fs",
                         String(expert), median(survival), survival.reduce(0, +) / Double(seeds)))
            // Endless: the hazard reader must survive the full 300 s on every seed.
            var survived = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                var watch = Watch()
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60); check(run, &watch) }
                placed[run.mode, default: [:]].merge(run.placedCoinLines, uniquingKeysWith: +)
                checkEscalation(run)
                checkTeaching(run)
                if run.phase == .running { survived += 1 }
                else { print("READER-FAIL endless seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) lane=\(run.lane) reason=\(run.crashReason)") }
            }
            print("READER endless expert=\(expert): survived=\(survived)/\(seeds) (300s)")
            // Harbor Sprint shares the Endless generator. A hazard crash would silently shrink fairness coverage.
            var sprintCrashes = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .harborSprint, expert: expert)
                var watch = Watch()
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60); check(run, &watch) }
                if run.phase == .crashed && !run.crashReason.hasPrefix("Time ran out") {
                    sprintCrashes += 1
                    print("READER-FAIL sprint seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) reason=\(run.crashReason)")
                }
            }
            print("READER sprint expert=\(expert): hazardCrashes=\(sprintCrashes)/\(seeds)")
            precondition(sprintCrashes == 0, "Hazard reader must not crash into a hazard in Harbor Sprint")
            precondition(survived == seeds, "Hazard reader must survive every Endless seed")
        }
        for mode in [RunMode.odyssey, .endless] {
            let lines = placed[mode, default: [:]]
            let total = Double(max(1, lines.values.reduce(0, +)))
            func share(_ line: RunnerSimulation.CoinLine) -> Double { Double(lines[line, default: 0]) / total * 100 }
            print(String(format: "PLACED-LINES mode=%@ safe=%.1f%% action=%.1f%% risk=%.1f%% bait=%.1f%% rows=%d",
                         mode.rawValue, share(.safe), share(.action), share(.risk), share(.bait), Int(total)))
            precondition(share(.safe) <= 35, "At most 35% of placed coin lines may mark the safe lane")
        }
        let missing = hazardWorlds.filter { coverage[$0.key] != $0.value }
        let leaks = coverage.filter { hazardWorlds[$0.key] != $0.value }
        let distinct = Set(patternsByWorld.values.flatMap { $0 })
        print("ENDLESS-ESCALATION standard=\(escalationSeen[false, default: []].sorted()) expert=\(escalationSeen[true, default: []].sorted()) early=\(earlyEscalation)")
        precondition([false, true].allSatisfy { escalationSeen[$0, default: []] == Set(0...6) } && earlyEscalation == 0,
                     "Endless must escalate through every row type, each after its gate")
        print("PATTERNS total=\(distinct.count) " + WorldStage.allCases.map { "\($0.rawValue)=\(patternsByWorld[$0, default: []].count)" }.joined(separator: " ") + " bagRepeats=\(bagRepeats)")
        precondition(distinct.count >= 14 && WorldStage.allCases.allSatisfy { patternsByWorld[$0, default: []].count >= 10 },
                     "Odyssey needs 14+ patterns and 10+ effective patterns per world")
        precondition(bagRepeats == 0, "A bag row must not repeat a pattern from the last three rows")
        print("HAZARD-COVERAGE " + hazardWorlds.keys.sorted().map { key in
            "\(key)=\(coverage[key, default: []].map(\.rawValue).sorted().joined(separator: "+"))" }.joined(separator: " "))
        precondition(missing.isEmpty && leaks.isEmpty, "Each G2 hazard must appear in exactly its worlds: missing=\(missing.keys.sorted()) leaks=\(leaks.keys.sorted())")
        print("TELEGRAPHS lateChanges=\(telegraphViolations) checks: shift=\(shiftChecks) impact=\(impactChecks) collapse=\(collapseChecks) (shift >= 1.0/0.8 s, impact >= 1.0 s, collapse >= 0.5 s)")
        precondition(shiftChecks > 0 && impactChecks > 0 && collapseChecks > 0, "Every telegraph kind must be checked at least once")
        precondition(telegraphViolations == 0, "Lane shifts, impacts and collapses must keep their lead time")
        print("BAIT-ESCAPES violations=\(baitViolations) (last bait coin to resume switch; one adjacent lane clear)")
        precondition(baitViolations == 0, "Every bait escape must be a single adjacent lane switch")
        print("TEACHING violations=\(teachingViolations) invitationsJustAfter=\(invitationsAfterTeaching)")
        precondition(teachingViolations == 0 && invitationsAfterTeaching > 0, "Standard teaching rows hold only safe or action lines, and end on time")
        print("FAIRNESS unfairCoins=\(unfair) (coins, keys and power-ups; first sight and collection time)")
        precondition(unfair == 0, "Every coin and pickup must be collectible without a forced collision")
        // Same seed, same track: the coin lines must draw from the seeded generator only.
        func trackAfterReaderRun() -> [TrackEntity] {
            var run = RunnerSimulation()
            run.start(seed: 4, boards: 0, mode: .odyssey, expert: false)
            for _ in 0..<3_000 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60) }
            return run.entities
        }
        precondition(trackAfterReaderRun() == trackAfterReaderRun(), "Same seed must generate the same track")
        // Daily follows its date alone: any launch seed rebuilds the same course, forks and finales included.
        func dailyTrack(seed: UInt64) -> [TrackEntity] {
            var run = RunnerSimulation()
            run.start(seed: seed, boards: 0, mode: .odyssey, dailyID: "2026-10-06")
            for _ in 0..<3_000 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60) }
            return run.entities
        }
        precondition(dailyTrack(seed: 1) == dailyTrack(seed: 2), "Daily Odyssey must reproduce from its date alone")
        // The fork/finale order depends on the run seed (every bit of it), and Daily's seed comes from its date.
        let order = { (seed: UInt64) in RunnerSimulation.seededOrder(WorldStage.harbor.finalePatterns, salt: 4, seed: seed) }
        precondition(order(2) != order(3), "Seeds 2 and 3 must not share a fork/finale order")
        precondition(Set((1...8).map(order)).count > 1, "seededOrder must depend on the run seed")
        let day = RunnerSimulation.dailyOdysseySeed
        precondition(order(day("2026-10-06")) == order(day("2026-10-06")), "The same Daily date must give the same order")
        precondition(order(day("2026-10-06")) != order(day("2026-10-07")), "The next Daily date must give a different order")
        print("SEEDED-ORDER seeds1...8 distinct=\(Set((1...8).map(order)).count) seed2==seed3: \(order(2) == order(3))")
        print("SkillAudit passed")
    }
}
