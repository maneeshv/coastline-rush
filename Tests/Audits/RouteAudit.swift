import Foundation

#if !ROUTE_HELPER
@main
#endif
struct RouteAudit {
    static let hazards: Set<EntityKind> = [.barrier, .arch, .tram, .gap, .meteor, .root, .iceCrack, .laserSweep, .buoy, .waterTraffic]
    static let pursueRelics = ProcessInfo.processInfo.environment["QA_RELICS"] == "1"
    static let requestedRoute = BranchRoute(rawValue: ProcessInfo.processInfo.environment["QA_ROUTE"] ?? "safe") ?? .safe
    static func drive(_ run: inout RunnerSimulation, allowVerticalActions: Bool = true, route: BranchRoute? = nil) {
        guard !run.isPortalTransitioning else { return }
        // Steering during the marked fork window is itself a choice. Reassert the
        // audited route after normal obstacle steering, before the simulation tick.
        defer { if run.routeChoiceAvailable { run.chooseRoute(route ?? requestedRoute) } }
        if run.isWaterTraversal { driveWater(&run); return }
        if allowVerticalActions, let d = run.portalDistance, d < 5.5, run.height < 0.05 { run.act(.jump); return }
        if allowVerticalActions, run.height >= 2.79,
           run.entities.contains(where: { [.barrier, .root, .iceCrack].contains($0.kind) && $0.lane == run.lane && $0.z > 0 && $0.z < run.speed * 1.1 }) {
            // A rover roof is a launch platform: waiting to fall before jumping
            // wastes the recovery space before a following cargo line.
            run.act(.jump)
        }
        // A jetpack pickup swaps the hazard set: ground hazards are ignored in flight, drones are not.
        let flying = run.activePowerUps[.jetpack] != nil
        let active = run.entities.filter { (flying ? $0.kind == .airHazard : hazards.contains($0.kind)) && $0.z + $0.length / 2 > -0.5 }.sorted { $0.z < $1.z }
        guard let first = active.first, first.z < run.speed * 2.1 else { return }
        let row = active.filter { abs($0.z - first.z) < 2 }
        // Plan before a ramp starts. Hold the route until its full collider has passed.
        var target = run.lane
        let free = (-1...1).filter { lane in !row.contains { $0.lane == lane } }
        // Look ahead: among free lanes, avoid one whose next hazard is a solid (tram/meteor) the reader cannot jump.
        func freeCost(_ lane: Int) -> Int {
            let solidAfter = active.contains { $0.lane == lane && $0.z > first.z + 2 && $0.z < first.z + run.speed * 1.1 && [.tram, .meteor].contains($0.kind) } ? 4 : 0
            return abs(lane - run.lane) + solidAfter
        }
        if let best = free.min(by: { freeCost($0) < freeCost($1) }) { target = best }
        else if let supported = row.first(where: { vehicle in
            vehicle.kind == .tram && run.entities.contains(where: {
                $0.kind == .ramp && $0.lane == vehicle.lane && abs(($0.z + 9) - vehicle.z) < 0.5
            })
        }) { target = supported.lane }
        else {
            // Full-width mixed rows expose a jump lane, a slide lane and a solid
            // lane. Read those shapes, and prefer a lane whose next hazard is not solid.
            let choices = row.filter { $0.kind != .tram && $0.kind != .meteor }
            func cost(_ e: TrackEntity) -> Int {
                let airborneSlide = run.height > 0.3 && [.arch, .laserSweep].contains(e.kind) ? 3 : 0
                let solidAfter = active.contains { $0.lane == e.lane && $0.z > e.z + 2 && $0.z < e.z + run.speed * 1.1 && [.tram, .meteor].contains($0.kind) } ? 4 : 0
                return abs(e.lane - run.lane) + airborneSlide + solidAfter
            }
            if let choice = choices.min(by: { cost($0) < cost($1) }) { target = choice.lane }
        }
        if Set(row.map(\.lane)).count == 3, row.allSatisfy({ [.gap, .barrier, .root, .iceCrack].contains($0.kind) }) {
            // A full-width leap: read the landing, not the coins. Commit before the
            // leap to the lane the next hazard row leaves open.
            let landing = active.filter { $0.z > first.z + 2 && $0.z < first.z + run.speed * 1.1 }
            if let next = landing.first {
                let landingRow = landing.filter { abs($0.z - next.z) < 2 }
                let open = (-1...1).filter { lane in !landingRow.contains { $0.lane == lane } }
                if let lane = open.min(by: { abs($0 - run.lane) < abs($1 - run.lane) }) { target = lane }
            }
        }
        if pursueRelics, let relic = run.entities.first(where: { $0.kind == .relic && abs($0.z - first.z) < 3 }) { target = relic.lane }
        // Do not abandon an elevated/skill route as soon as its relic disappears.
        // Hold it until the complete collider has passed.
        if first.z < 2 { target = run.lane }
        if target < run.lane { run.act(.left) }
        if target > run.lane { run.act(.right) }
        // A moving crate may pull ahead of its neighboring beam. Always read
        // the next hazard in the occupied/target lane, even when another lane's
        // earlier collider is still passing. This also protects a lane-change exit.
        guard allowVerticalActions, let obstacle = active.first(where: {
            $0.z > 0 && ($0.lane == target || abs(run.lateral - Double($0.lane)) < 0.55)
        }) else { return }
        switch obstacle.kind {
        case .gap:
            if obstacle.z < run.speed * 0.60, run.height < 0.05 { run.act(.jump) }
        case .iceCrack:
            if obstacle.z < run.speed * 0.38, run.height < 0.05 { run.act(.jump) }
        case .barrier, .root:
            if obstacle.z < run.speed * 0.32, run.height < 0.05 { run.act(.jump) }
        case .arch, .laserSweep:
            if obstacle.z < run.speed * 0.30, !run.isRolling { run.act(.roll) }
        default: break
        }
    }

    static func driveWater(_ run: inout RunnerSimulation) {
        // Read the buoy row as well as its gate. Collected gates disappear before
        // their neighboring buoy colliders have passed, so changing lane at the
        // pickup instant is not a valid water steering policy.
        let buoys = run.entities.filter { $0.kind == .buoy && $0.z > -1.8 }.sorted { $0.z < $1.z }
        guard let first = buoys.first else { return }
        let row = buoys.filter { abs($0.z - first.z) < 1 }
        guard let target = (-1...1).first(where: { lane in !row.contains { $0.lane == lane } }) else { return }
        let turningBoat = run.entities.contains {
            $0.kind == .waterTraffic && $0.lane == target && $0.z > -3.5 && $0.z < run.speed * 0.55 + 3
        }
        if !turningBoat { run.steerWater(Double(target)) }
    }

    static func main() throws {
        var passed = 0, failures = 0, roundTrips = 0, maximumEntities = 0, totalJumps = 0, totalRolls = 0, gold = 0, relics = 0, retainedPortals = 0, totalGates = 0, totalFinales = 0
        var branchWorlds = Set<WorldStage>(), finaleWorlds = Set<WorldStage>()
        var maximumSpeed = 0.0
        let seedCount = Int(ProcessInfo.processInfo.environment["QA_SEEDS"] ?? "30") ?? 30
        for expert in [false, true] {
            for seed in 1...seedCount {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                var tick = 0
                while run.phase == .running && tick < 90_000 {
                    let previousStage = run.stageIndex, previousBase = run.stageTargetSpeed
                    drive(&run)
                    run.update(dt: 1.0 / 60.0)
                    if run.routeIsActive { branchWorlds.insert(run.worldStage) }
                    if run.finaleActive { finaleWorlds.insert(run.worldStage) }
                    guard run.stageTargetSpeed >= previousBase else { fatalError("Base speed fell seed=\(seed) expert=\(expert) stage=\(run.stageIndex): \(previousBase) to \(run.stageTargetSpeed)") }
                    if run.stageIndex != previousStage { retainedPortals += 1 }
                    maximumSpeed = max(maximumSpeed, run.speed)
                    tick += 1
                    maximumEntities = max(maximumEntities, run.entities.count)
                    if tick % 401 == 0 {
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                        let data = try encoder.encode(run)
                        let restored = try JSONDecoder().decode(RunnerSimulation.self, from: data)
                        // Codable Sets/dictionaries have no byte-order contract. Check
                        // observable state and a future branch instead of JSON bytes.
                        var originalFuture = run, restoredFuture = restored
                        for _ in 0..<60 {
                            drive(&originalFuture); drive(&restoredFuture)
                            originalFuture.update(dt: 1.0 / 60); restoredFuture.update(dt: 1.0 / 60)
                            guard originalFuture.phase == restoredFuture.phase,
                                  originalFuture.entities == restoredFuture.entities,
                                  originalFuture.score == restoredFuture.score,
                                  originalFuture.height == restoredFuture.height,
                                  originalFuture.lateral == restoredFuture.lateral,
                                  originalFuture.stageResults == restoredFuture.stageResults,
                                  originalFuture.artifactsCollected == restoredFuture.artifactsCollected,
                                  originalFuture.abilityCharges == restoredFuture.abilityCharges,
                                  originalFuture.speed == restoredFuture.speed,
                                  originalFuture.distance == restoredFuture.distance,
                                  originalFuture.stageTargetSpeed == restoredFuture.stageTargetSpeed,
                                  originalFuture.routeRevision == restoredFuture.routeRevision,
                                  originalFuture.branchRoute == restoredFuture.branchRoute,
                                  originalFuture.isWaterTraversal == restoredFuture.isWaterTraversal,
                                  originalFuture.decisionPlan == restoredFuture.decisionPlan,
                                  originalFuture.selectedPerks == restoredFuture.selectedPerks,
                                  originalFuture.finaleProgress == restoredFuture.finaleProgress
                            else { fatalError("Checkpoint future mismatch seed=\(seed) tick=\(tick)") }
                        }
                        run = restored; roundTrips += 1
                    }
                }
                let masteryPassed = !pursueRelics || (run.artifactsCollected == 18 && run.stageResults.allSatisfy { $0.medal == .gold })
                let routePassed = run.stageResults.allSatisfy { $0.branchRoute == requestedRoute && $0.finaleCleared }
                if run.journeyComplete && run.stageResults.count == 6 && run.stageResults.allSatisfy({ $0.hits == 0 }) && run.boardsUsed == 0 && masteryPassed && routePassed {
                    passed += 1; totalJumps += run.jumps; totalRolls += run.rolls
                    gold += run.stageResults.filter { $0.medal == .gold }.count; relics += run.artifactsCollected
                    totalGates += run.gatesCleared; totalFinales += run.totalFinalesCleared
                    if seed == 1 {
                        let times = run.stageResults.map { "\($0.stage)=\(String(format: "%.2f", $0.elapsed))s" }.joined(separator: ", ")
                        print("TIMING expert=\(expert) stages=[\(times)] total=\(String(format: "%.2f", run.elapsed))s")
                    }
                    if pursueRelics { print("MASTERY seed=\(seed) expert=\(expert): \(run.stageResults.map { "\($0.stage)=\($0.medal),relics=\($0.relics),precision=\($0.precisionPortal)" }.joined(separator: "; "))") }
                } else {
                    failures += 1
                    print("FAIL seed=\(seed) expert=\(expert) route=\(requestedRoute) world=\(run.worldStage) local=\(String(format: "%.3f", run.stageDistance)) lane=\(run.lane) x=\(run.lateral) y=\(run.height) reason=\(run.crashReason)")
                    if !masteryPassed { print("  mastery=\(run.stageResults.map { "\($0.stage):\($0.medal):\($0.relics)" })") }
                    if !routePassed { print("  routes=\(run.stageResults.map { "\($0.stage):\($0.branchRoute):finale=\($0.finaleCleared)" })") }
                    for e in run.entities where hazards.contains(e.kind) && abs(e.z) < 20 { print("  id=\(e.id) \(e.kind) lane=\(e.lane) z=\(e.z) length=\(e.length)") }
                    if failures > 5 { break }
                }
            }
        }
        guard branchWorlds.count == 6, finaleWorlds.count == 6 else { fatalError("Audit did not visit all six forks and finales") }
        if requestedRoute == .safe { guard totalGates > 0 else { fatalError("Safe route did not exercise water gates") } }
        print("RESULT route=\(requestedRoute) passes=\(passed) failures=\(failures) generated-six-world-routes; roundTrips=\(roundTrips); maximumEntities=\(maximumEntities); jumps=\(totalJumps); rolls=\(totalRolls); gold=\(gold); relics=\(relics); retainedPortals=\(retainedPortals); gates=\(totalGates); finales=\(totalFinales); maximumSpeed=\(String(format: "%.3f", maximumSpeed))m/s; no fixture track, boards, abilities or revives")
        if failures > 0 { exit(1) }
    }
}
