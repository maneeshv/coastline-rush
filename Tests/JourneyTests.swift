import Foundation

@main
struct JourneyTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
    static func fixture(stage: Int = 0, expert: Bool = false) -> RunnerSimulation {
        var run = RunnerSimulation()
        run.start(seed: 7, mode: .odyssey, expert: expert, startStage: stage, portalAssist: false)
        run.replaceTrackForTesting([])
        return run
    }
    static func reachPortal(_ run: inout RunnerSimulation) {
        for _ in 0..<40 where !run.portalReady && run.phase == .running { run.update(dt: 10) }
    }
    static func json(_ run: RunnerSimulation) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
    }
    static func advance(_ run: inout RunnerSimulation, toFraction fraction: Double) {
        let target = run.stageLength * fraction
        for _ in 0..<20_000 where run.stageDistance < target && run.phase == .running && !run.isPortalTransitioning {
            run.update(dt: 1.0 / 60)
        }
    }
    static func steerSkillRoute(_ run: inout RunnerSimulation) { RouteAudit.drive(&run) }

    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("six ordered worlds expose distinctive physics and finite lengths", {
                try expect(WorldStage.ordered == [.harbor, .orbit, .mars, .verdant, .cryo, .forge], "Destination order changed")
                try expect(WorldStage.orbit.gravity < WorldStage.mars.gravity && WorldStage.mars.gravity < WorldStage.harbor.gravity, "Planet gravity must differ")
                try expect(Set(WorldStage.allCases.map(\.artifactName)).count == 6, "Each world needs its own relic")
                try expect(WorldStage.allCases.allSatisfy { $0.length >= 2_000 && $0.length <= 5_000 }, "Every destination must offer a substantial finite route")
            }),
            ("manual portal setting waits safely when precision entry is missed", {
                var run = fixture()
                try expect(run.portalDistance == nil, "Portal should not appear at the start")
                advance(&run, toFraction: 0.97)
                try expect(run.portalDistance != nil && run.portalDistance! <= 160, "Approaching portal was not exposed")
                reachPortal(&run)
                try expect(run.portalReady && run.stageIndex == 0 && run.stageProgress == 1, "Arrival must await jump")
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let frozen = try encoder.encode(run)
                run.update(dt: 60)
                run.act(.roll); run.act(.board); run.act(.left)
                let after = try encoder.encode(run)
                try expect(after == frozen, "Waiting must not drain counters or accept other actions")
            }),
            ("jump from every lane enters the gateway without an alignment trap", {
                for lane in -1...1 {
                    var run = fixture()
                    if lane == -1 { run.act(.left) }; if lane == 1 { run.act(.right) }
                    reachPortal(&run)
                    run.act(.jump)
                    try expect(run.isPortalTransitioning && run.jumps == 1, "All lanes must enter the portal")
                    run.update(dt: 0.8)
                    try expect(abs(run.portalTransitionProgress - 0.5) < 0.001 && run.worldStage == .harbor, "World should remain until transition completes")
                    run.update(dt: 0.8)
                    try expect(run.worldStage == .orbit && !run.isPortalTransitioning && run.stagesCleared == 1, "Transition did not arrive in orbit")
                    try expect(run.stageDistance < 0.01 && run.lane == 0 && run.height == 0, "Landing must reset local physics")
                }
            }),
            ("pause and persistence preserve gateway transition exactly", {
                var run = fixture(stage: 2)
                reachPortal(&run); run.act(.jump); run.update(dt: 0.55); run.pause()
                let original = run.portalTransitionProgress
                var restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                restored.update(dt: 30)
                try expect(restored.portalTransitionProgress == original && restored.worldStage == .mars, "Paused transition advanced after restoration")
                restored.resume(); restored.update(dt: 1.05)
                try expect(restored.worldStage == .verdant && restored.stagesCleared == 1, "Restored transition did not complete once")
            }),
            ("moving transition protects the player and freezes resource clocks", {
                var run = fixture()
                reachPortal(&run)
                // A saved gateway may still contain active powers from its approach.
                var state = try json(run)
                state["boardTime"] = 12.0
                state["activePowerUps"] = ["magnet", 8.0]
                run = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                run.act(.jump)
                run.replaceTrackForTesting([TrackEntity(id: 987, kind: .tram, lane: 0, z: 0, y: 0, length: 12)])
                let distance = run.distance, score = run.score, elapsed = run.elapsed
                run.update(dt: 1)
                run.act(.board); run.act(.right)
                try expect(run.phase == .running && run.distance > distance && run.score == score && run.elapsed > elapsed, "Transit must move forward without obstacle collisions or scoring")
                try expect(run.boardTime == 12 && run.activePowerUps[.magnet] == 8, "Transition consumed power timers")
                run.update(dt: 0.6)
                try expect(run.entities.isEmpty && run.activePowerUps.isEmpty && run.boardTime > 11.99, "Arrival must clear hazards/flight but preserve earned shield time")
            }),
            ("six portals complete a journey with no relic requirement", {
                var run = fixture()
                for index in 0..<6 {
                    try expect(run.stageIndex == index, "Incorrect destination in sequence")
                    reachPortal(&run); run.act(.jump); run.update(dt: 1.6)
                    try expect(run.stagesCleared == index + 1, "Portal completion count incorrect")
                }
                try expect(run.journeyComplete && run.phase == .finished && run.artifactsCollected == 0, "Final portal must complete without a collectible gate")
                let totalLength = WorldStage.allCases.reduce(0) { $0 + $1.length }
                try expect(run.distance > totalLength && run.distance < totalLength + 500, "Distance must include visible forward travel through portals")
                let score = run.score
                run.update(dt: 30); run.act(.jump)
                try expect(run.score == score && run.stagesCleared == 6, "Finished journey was rewarded twice")
            }),
            ("relics award score and persist a world catalog without double collection", {
                var run = fixture(stage: 1)
                let relic = TrackEntity(id: 123, kind: .relic, lane: 0, z: 0, y: 1, length: 0.6)
                run.replaceTrackForTesting([relic]); run.update(dt: 0.01)
                try expect(run.artifactsCollected == 1 && run.collectedArtifactWorlds == [.orbit] && run.score >= 250, "Relic was not rewarded/cataloged")
                run.replaceTrackForTesting([relic]); run.update(dt: 0.01)
                try expect(run.artifactsCollected == 1, "Identical relic was credited twice")
                let restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                try expect(restored.artifactsCollected == 1 && restored.collectedArtifactWorlds == [.orbit], "Artifact state did not persist")
            }),
            ("old snapshots decode and retain existing mode", {
                for mode in [RunMode.endless, .harborSprint, .jetSki] {
                    var run = RunnerSimulation(); run.start(mode: mode); run.replaceTrackForTesting([]); run.update(dt: 1)
                    var state = try json(run); state.removeValue(forKey: "journey")
                    let restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                    try expect(restored.mode == mode && restored.distance == run.distance && restored.worldStage == .harbor, "Legacy run was altered")
                }
            }),
            ("moving Mars rovers retain their ramp and collectible roof support", {
                var run = fixture(stage: 2)
                run.replaceTrackForTesting([
                    TrackEntity(id: 1, kind: .ramp, lane: 0, z: 6, y: 0, length: 7, oncomingSpeed: -1.5),
                    TrackEntity(id: 2, kind: .tram, lane: 0, z: 15, y: 0, length: 9, oncomingSpeed: -1.5),
                    TrackEntity(id: 3, kind: .relic, lane: 0, z: 15, y: 3.7, length: 0.6, oncomingSpeed: -1.5)
                ])
                run.update(dt: 15 / (run.speed - 1.5))
                try expect(run.phase == .running && run.height == RunnerSimulation.tramRoofHeight, "Moving rover detached from its ramp")
                try expect(run.artifactsCollected == 1, "Roof relic must move with its rover and remain collectible")
                run.update(dt: 1)
                try expect(run.height == 0 && run.phase == .running, "Rover exit should return safely to the ground")
            }),
            ("world gravity, ice steering and growing bounded stage speed are real", {
                var orbital = fixture(stage: 1), harbor = fixture(), ice = fixture(stage: 4)
                orbital.act(.jump); harbor.act(.jump); orbital.update(dt: 0.7); harbor.update(dt: 0.7)
                try expect(orbital.height > harbor.height + 1, "Low gravity did not change the jump")
                ice.act(.right); harbor.act(.right); ice.update(dt: 0.1); harbor.update(dt: 0.1)
                try expect(ice.lateral < harbor.lateral, "Ice should require earlier steering")
                for stage in 0..<6 {
                    var run = fixture(stage: stage); let speed = run.speed
                    run.update(dt: 10)
                    try expect(run.speed > speed && run.speed < 45, "Odyssey must accelerate through each stage within a readable maximum")
                }
            }),
            ("each world lasts ninety to one hundred twenty seconds while speed rises", {
                var standardTotal = 0.0
                for stage in 0..<6 {
                    var standardDuration = 0.0
                    for expert in [false, true] {
                        var run = RunnerSimulation()
                        run.start(mode: .odyssey, expert: expert, startStage: stage, portalAssist: false)
                        run.replaceTrackForTesting([])
                        let entrySpeed = run.speed
                        var previousSpeed = entrySpeed
                        for _ in 0..<600 where !run.portalReady {
                            run.update(dt: 0.25)
                            try expect(run.speed >= previousSpeed, "Speed fell within world \(stage), expert \(expert)")
                            try expect(run.speed <= (expert ? 51.01 : 45.01), "Speed exceeded the verified control envelope")
                            previousSpeed = run.speed
                        }
                        try expect(run.portalReady, "A finite stage did not reach its portal")
                        try expect(run.speed > entrySpeed + 2.5, "A stage must continue accelerating from its retained entry speed")
                        if expert {
                            try expect(run.elapsed < standardDuration * 0.95 && run.elapsed > 65, "Expert must increase challenge without collapsing stage duration")
                        } else {
                            try expect(run.elapsed >= 90 && run.elapsed <= 120, "Stage \(stage) duration was \(run.elapsed), expected 90–120 seconds")
                            standardDuration = run.elapsed
                            standardTotal += run.elapsed
                        }
                    }
                }
                try expect(standardTotal >= 540 && standardTotal <= 720, "Six-stage expedition length must be substantial")
            }),
            ("later worlds start and finish faster and Expert increases the curve", {
                var previousEntry = 0.0, previousFinish = 0.0
                for stage in 0..<6 {
                    var standard = fixture(stage: stage)
                    var expert = RunnerSimulation()
                    expert.start(mode: .odyssey, expert: true, startStage: stage, portalAssist: false)
                    expert.replaceTrackForTesting([])
                    try expect(standard.speed > previousEntry && expert.speed > standard.speed, "World entry speeds must escalate and Expert must start faster")
                    previousEntry = standard.speed
                    for fraction in [0.25, 0.5, 0.75, 0.99] {
                        advance(&standard, toFraction: fraction); advance(&expert, toFraction: fraction)
                        try expect(expert.speed > standard.speed, "Expert was not harder at \(fraction) in world \(stage)")
                    }
                    try expect(standard.speed > previousFinish, "Later worlds must have higher final speed")
                    previousFinish = standard.speed
                }
            }),
            ("normal and precision portals retain speed across every world boundary", {
                for expert in [false, true] {
                    for precision in [false, true] {
                        for stage in 0..<5 {
                            var run = fixture(stage: stage, expert: expert)
                            let expected = run.worldStage.speed(at: 1, expert: expert)
                            if precision {
                                while run.stageDistance < run.stageLength - 8 { run.update(dt: 1.0 / 60) }
                                run.act(.jump)
                                for _ in 0..<60 where !run.isPortalTransitioning { run.update(dt: 1.0 / 60) }
                            } else {
                                reachPortal(&run); run.act(.jump)
                            }
                            let departure = run.speed
                            try expect(run.isPortalTransitioning, "Portal did not start")
                            run.update(dt: 1.6)
                            try expect(run.stageIndex == stage + 1 && !run.isPortalTransitioning, "Portal failed to arrive")
                            try expect(run.speed >= departure && abs(run.speed - expected) < 0.02, "Portal reset base speed: stage \(stage), Expert \(expert), precision \(precision), \(departure) to \(run.speed)")
                            try expect(run.stageResults.last?.precisionPortal == precision, "Portal scoring disagreed with entry action")
                            let arrival = run.speed
                            run.update(dt: 1)
                            try expect(run.speed > arrival, "Next destination stopped accelerating")
                        }
                    }
                }
            }),
            ("later worlds retain encounter tiers and phase progress remains valid", {
                let entries: [JourneyDifficultyTier] = [.warmup, .pressure, .pressure, .intense, .intense, .overdrive]
                for stage in 0..<6 {
                    var run = fixture(stage: stage)
                    try expect(run.difficultyTier == entries[stage], "World \(stage) reset to tutorial pressure")
                    var previous = run.difficultyTier.rawValue
                    for fraction in [0.0, 0.1, 0.3, 0.5, 0.8, 0.99] {
                        advance(&run, toFraction: fraction)
                        try expect(run.difficultyTier.rawValue >= previous, "Encounter tier fell within the world")
                        try expect((0...1).contains(run.difficultyProgress), "Difficulty HUD progress escaped its range")
                        previous = run.difficultyTier.rawValue
                    }
                    try expect(run.difficultyTier == .overdrive, "World failed to reach its climax")
                }
            }),
            ("late-stage Air Dash always accelerates and its bonus expires", {
                for expert in [false, true] {
                    var run = fixture(stage: 5, expert: expert)
                    run.chooseAbility(.airDash)
                    run.replaceTrackForTesting([TrackEntity(id: 999, kind: .relic, lane: 0, z: 0, y: 1, length: 0.6)])
                    run.update(dt: 0.01); run.replaceTrackForTesting([])
                    advance(&run, toFraction: 0.90)
                    let base = run.stageTargetSpeed
                    run.act(.ability); run.update(dt: 0.1)
                    try expect(run.speed > base + 5.9, "High-speed Air Dash slowed or capped the player")
                    run.update(dt: 0.6)
                    try expect(!run.isAbilityActive && abs(run.speed - run.stageTargetSpeed) < 0.01, "Air Dash permanently raised the base curve")
                }
            }),
            ("a new expedition resets momentum to the selected starting world", {
                for expert in [false, true] {
                    var run = fixture(stage: 5, expert: expert)
                    advance(&run, toFraction: 0.9)
                    run.start(seed: 19, mode: .odyssey, expert: expert)
                    try expect(run.stageIndex == 0 && run.stageDistance == 0, "Restart kept old destination progress")
                    try expect(run.speed == (expert ? 20 : 17), "Restart retained a previous expedition's speed")
                    try expect(run.difficultyTier == .warmup && run.stageResults.isEmpty, "Restart retained previous encounter pressure or rewards")
                }
            }),
            ("later worlds retain demanding encounter pressure throughout their stages", {
                for stage in 0..<6 {
                    for expert in [false, true] {
                        var earlyCount = 0, lateCount = 0
                        var earlySeconds = 0.0, lateSeconds = 0.0
                        for seed in [5, 17, 23, 41, 79] {
                            var run = RunnerSimulation()
                            run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert, startStage: stage, portalAssist: false)
                            var early = Set<Int>(), late = Set<Int>()
                            for _ in 0..<600 where !run.portalReady {
                                for entity in run.entities where RouteAudit.hazards.contains(entity.kind) {
                                    let fraction = (run.stageDistance + entity.z) / run.stageLength
                                    if (0.15..<0.35).contains(fraction) { early.insert(entity.id) }
                                    if (0.65..<0.85).contains(fraction) { late.insert(entity.id) }
                                }
                                if (0.15..<0.35).contains(run.stageProgress) { earlySeconds += 0.25 }
                                if (0.65..<0.85).contains(run.stageProgress) { lateSeconds += 0.25 }
                                // This fixture audits generated pressure only; route
                                // survival is checked separately without replacement.
                                run.replaceTrackForTesting(run.entities.filter { $0.z > 35 }, generate: true)
                                run.update(dt: 0.25)
                            }
                            try expect(run.portalReady && !early.isEmpty && !late.isEmpty, "Density sampler did not cover the complete course")
                            earlyCount += early.count; lateCount += late.count
                        }
                        let earlyRate = Double(earlyCount) / earlySeconds
                        let lateRate = Double(lateCount) / lateSeconds
                        print("DENSITY world=\(stage) expert=\(expert) early=\(String(format: "%.3f", earlyRate))/s late=\(String(format: "%.3f", lateRate))/s")
                        // Worlds with an intense/overdrive entry already start near
                        // their physical action floor; speed and compound choices
                        // carry escalation rather than impossible shorter jumps.
                        let minimumGrowth = stage == 0 || stage == 2 ? 1.15 : 0.90
                        try expect(lateRate > earlyRate * minimumGrowth, "World \(stage), Expert \(expert): late pressure \(lateRate) fell behind entry pressure \(earlyRate)")
                    }
                }
            }),
            ("steering alone cannot bypass the required jump and slide encounters", {
                for expert in [false, true] {
                    for stage in 0..<6 {
                        var run = RunnerSimulation()
                        run.start(seed: 19, boards: 0, mode: .odyssey, expert: expert, startStage: stage)
                        for _ in 0..<20_000 where run.phase == .running && !run.isPortalTransitioning {
                            RouteAudit.drive(&run, allowVerticalActions: false)
                            run.update(dt: 1.0 / 60)
                        }
                        try expect(run.phase == .crashed && run.stageProgress < 0.5, "Lane-only steering bypassed the action vocabulary in \(run.worldStage)")
                        try expect(run.jumps == 0 && run.rolls == 0 && run.boardsUsed == 0, "Passive audit used an ability or action")
                    }
                }
            }),
            ("all generated worlds provide a clear landing and portal approach", {
                for seed in 1...12 {
                    for stage in 0..<6 {
                        for expert in [false, true] {
                            var run = RunnerSimulation(); run.start(seed: UInt64(seed), mode: .odyssey, expert: expert, startStage: stage, portalAssist: false)
                            let firstHazard = run.entities.filter { RouteAudit.hazards.contains($0.kind) }.map { $0.z - $0.length / 2 }.min() ?? .infinity
                            try expect(firstHazard >= run.speed * 3, "A destination did not leave three seconds to read its new setting")
                            var seenRelics = Set<Int>()
                            for _ in 0..<400 where !run.portalReady {
                                for entity in run.entities {
                                    let local = run.stageDistance + entity.z
                                    if RouteAudit.hazards.contains(entity.kind) {
                                        try expect(local + entity.length / 2 < run.stageLength - run.portalApproachLength, "Hazard in portal approach: seed \(seed), stage \(stage), expert \(expert), kind \(entity.kind), local \(local), length \(entity.length), limit \(run.stageLength - run.portalApproachLength), z \(entity.z)")
                                    }
                                    if entity.kind == .relic { seenRelics.insert(entity.id) }
                                }
                                run.replaceTrackForTesting(run.entities.filter { $0.z > 35 }, generate: true)
                                run.update(dt: 0.5)
                                try expect(run.phase == .running && run.entities.count < 200, "Generation collided with fixture or grew without bound")
                            }
                            try expect(run.portalReady && seenRelics.count == 3, "World must end at gateway and offer exactly three relics")
                            let state = try json(run)
                            try expect((state["processedObstacles"] as? [Any] ?? []).count < 10, "Obstacle bookkeeping retained old rows")
                        }
                    }
                }
            })
            ,("assisted portals keep moving and a precision jump earns an entry bonus", {
                var assisted = RunnerSimulation()
                assisted.start(mode: .odyssey); assisted.replaceTrackForTesting([])
                advance(&assisted, toFraction: 0.999)
                assisted.update(dt: 0.4)
                try expect(assisted.isPortalTransitioning && assisted.portalTransitionProgress > 0, "Default assist should enter while running")
                let before = assisted.distance
                assisted.update(dt: 0.4)
                try expect(assisted.distance > before && assisted.height > 0, "Portal leap must animate real simulation motion")
                var precise = fixture()
                while precise.stageDistance < precise.stageLength - 8 { precise.update(dt: 1.0 / 60) }
                precise.act(.jump); precise.update(dt: 2.3)
                try expect(precise.stageResults.first?.precisionPortal == true, "Timed airborne crossing did not earn precision")
                try expect(precise.combo > 0, "Portal should carry the combo into the next destination")
            }),
            ("relic charges power real abilities with caps and honest collision outcomes", {
                for ability in ArtifactAbility.allCases {
                    var run = fixture()
                    run.chooseAbility(ability)
                    for id in 100..<105 {
                        run.replaceTrackForTesting([TrackEntity(id: id, kind: .relic, lane: 0, z: 0, y: 1, length: 0.6)])
                        run.update(dt: 0.01)
                    }
                    try expect(run.abilityCharges == 3, "Relics must cap carried charges at three")
                    run.act(.ability)
                    try expect(run.abilityCharges == 2 && run.isAbilityActive, "Ability did not consume exactly one charge")
                    run.act(.ability)
                    try expect(run.abilityCharges == 2, "Active ability consumed a second charge")
                    if ability == .airDash {
                        try expect(run.height >= 1.4, "Air dash must lift the player")
                        run.update(dt: 0.1)
                        try expect(run.speed > WorldStage.harbor.cruiseSpeed, "Air dash must change forward movement")
                    } else {
                        run.replaceTrackForTesting([TrackEntity(id: 999, kind: .tram, lane: 0, z: 2, y: 0, length: 9)])
                        run.update(dt: 0.2)
                        try expect(run.phase == .running, "Defensive artifact failed to protect the player")
                        if ability == .shield { try expect(!run.isAbilityActive && run.stageHits == 1, "Shield must break and count an impact") }
                    }
                    let saved = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                    try expect(saved.abilityCharges == run.abilityCharges && saved.selectedAbility == ability, "Artifact loadout did not survive a save")
                }
                var empty = fixture(); empty.chooseAbility(.phaseStep); empty.act(.ability)
                try expect(!empty.isAbilityActive, "An empty artifact must not activate")
            }),
            ("medals require actual skill and risky relic collection", {
                var run = fixture()
                for id in 1...2 {
                    run.replaceTrackForTesting([TrackEntity(id: id, kind: .barrier, lane: 0, z: 5, y: 0, length: 1.1)])
                    run.act(.jump); run.update(dt: 0.85)
                    run.replaceTrackForTesting([TrackEntity(id: id + 100, kind: .relic, lane: 0, z: 0, y: 1, length: 0.6)])
                    run.update(dt: 0.02)
                }
                try expect(run.stageSkillActions == 2, "Clean jumps did not count as stage skills")
                run.replaceTrackForTesting([])
                while run.stageDistance < run.stageLength - 8 { run.update(dt: 1.0 / 60) }
                run.act(.jump); run.update(dt: 2.2)
                try expect(run.stageResults.first?.medal == .gold, "Clean two-relic precision stage should earn gold")
                var passive = fixture(); reachPortal(&passive); passive.act(.jump); passive.update(dt: 1.6)
                try expect(passive.stageResults.first?.medal == .bronze, "Skipping all skills must not grant a clean silver medal")
            }),
            ("v3 snapshots migrate new state without losing an active expedition", {
                var original = fixture(stage: 3)
                original.replaceTrackForTesting([TrackEntity(id: 888, kind: .relic, lane: 0, z: 0, y: 1, length: 0.6)])
                original.update(dt: 3)
                var state = try json(original); state.removeValue(forKey: "enhancements")
                let restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                try expect(restored.worldStage == .verdant && restored.distance == original.distance, "Migration reset active journey")
                try expect(restored.portalAssist && restored.abilityCharges == 0 && restored.stageResults.isEmpty, "Migration defaults are unsafe")
                try expect(restored.stageRelics == 0 && restored.artifactsCollected == 1, "Legacy collected relics must persist without granting new mastery progress")
            }),
            ("v4 active checkpoints finish their original stage then enter the longer route", {
                var original = fixture(stage: 2)
                original.update(dt: 3)
                var state = try json(original)
                var journey = state["journey"] as! [String: Any]
                journey.removeValue(forKey: "routeRevision")
                journey["stageDistance"] = 350.0
                state["journey"] = journey
                state["distance"] = 350.0
                state["speed"] = 17.0
                var restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                try expect(restored.routeRevision == 4 && restored.stageLength == 480 && restored.stageDistance == 350, "Old active-stage progress must not be stretched into a longer route")
                restored.update(dt: 0.5)
                try expect(restored.speed == 17 && abs(restored.stageDistance - 358.5) < 0.001, "Old stage physics must remain stable until its portal")
                reachPortal(&restored); restored.act(.jump); restored.update(dt: 1.6)
                try expect(restored.worldStage == .verdant && restored.routeRevision == PortalJourney.currentRevision, "The next world did not upgrade the route")
                try expect(restored.stageLength == WorldStage.verdant.length && restored.stageDistance == 0, "Arrival must begin the longer world safely")
                try expect(restored.stageResults.first?.routeRevision == 4, "Legacy medal timing must retain its course identity")
                let saved = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(restored))
                try expect(saved.routeRevision == restored.routeRevision && saved.stageLength == restored.stageLength, "New checkpoint lost its difficulty revision")
            }),
            ("v5 midair checkpoints keep original speed and length until the next portal", {
                for expert in [false, true] {
                    var state = try json(fixture(stage: 2, expert: expert))
                    var journey = state["journey"] as! [String: Any]
                    journey["routeRevision"] = 5
                    journey["stageDistance"] = 1_200.0
                    state["journey"] = journey
                    state["distance"] = 1_200.0
                    state["height"] = 1.2
                    state["verticalVelocity"] = 3.0
                    state["grounded"] = false
                    let entry = expert ? 23.0 : 20.0, peak = expert ? 40.0 : 34.0
                    state["speed"] = entry + (peak - entry) * 1_200 / 2_750
                    var restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                    try expect(restored.routeRevision == 5 && restored.stageLength == 2_750 && restored.height == 1.2, "Restoration altered a v5 airborne checkpoint")
                    try expect(abs(restored.stageTargetSpeed - (entry + (peak - entry) * 1_200 / 2_750)) < 0.001, "Restoration changed old speed")
                    restored.update(dt: 0.1)
                    try expect(restored.height > 1.2 && restored.stageLength == 2_750 && restored.speed < peak, "Old stage physics did not continue")
                    reachPortal(&restored); restored.act(.jump); restored.update(dt: 1.6)
                    try expect(restored.routeRevision == PortalJourney.currentRevision && restored.stageIndex == 3 && restored.stageLength == 3_800, "v5 did not upgrade at its next portal")
                    try expect(restored.stageResults.last?.routeRevision == 5, "Old mastery result lost course provenance")
                    try expect(restored.speed >= peak && restored.difficultyTier == .intense, "Migration regressed the next world's speed or pressure")
                }
            }),
            ("v6 checkpoints retain their stage until the next portal enables expansion", {
                for expert in [false, true] {
                    for stage in 0..<5 {
                        var state = try json(fixture(stage: stage, expert: expert))
                        var journey = state["journey"] as! [String: Any]
                        let world = WorldStage.ordered[stage]
                        let local = world.length(forRevision: 6) * 0.40
                        journey["routeRevision"] = 6
                        journey["stageDistance"] = local
                        state["journey"] = journey
                        state["distance"] = local
                        state["speed"] = world.speed(at: 0.40, expert: expert, revision: 6)
                        state.removeValue(forKey: "expansion")
                        var restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: state))
                        try expect(restored.routeRevision == 6 && restored.stageDistance == local, "Restoration changed a live v6 stage")
                        try expect(!restored.isExpansionActive && !restored.routeIsActive && !restored.isWaterTraversal && !restored.finaleActive, "An old route gained new mechanics before its portal")
                        let expectedSpeed = world.speed(at: 0.40, expert: expert, revision: 6)
                        restored.update(dt: 0.10)
                        // update(dt:) substeps acceleration, so its final speed is
                        // slightly above the input speed rather than one Euler step.
                        try expect(restored.speed >= expectedSpeed && restored.speed < expectedSpeed + 0.02 && abs(restored.stageDistance - local - expectedSpeed * 0.10) < 0.002, "v6 movement changed before migration")
                        reachPortal(&restored); restored.act(.jump); restored.update(dt: 1.6)
                        try expect(restored.routeRevision == PortalJourney.currentRevision && restored.stageIndex == stage + 1 && restored.isExpansionActive, "Expansion did not activate at the next safe arrival")
                        try expect(restored.stageResults.last?.routeRevision == 6 && restored.stageResults.last?.finaleCleared == false, "Legacy result acquired new finale credit")
                        try expect(restored.speed >= world.speed(at: 1, expert: expert, revision: 6), "Migration dropped inherited momentum")
                    }
                }
            }),
            ("daily Odyssey uses a stable date seed and reproduces encounters", {
                var first = RunnerSimulation(), second = RunnerSimulation(), nextDay = RunnerSimulation()
                first.start(seed: 1, mode: .odyssey, dailyID: "2026-10-04")
                second.start(seed: 999, mode: .odyssey, dailyID: "2026-10-04")
                nextDay.start(mode: .odyssey, dailyID: "2026-10-05")
                try expect(first.entities == second.entities && first.runSeed == second.runSeed, "Daily course depends on random launch seed")
                try expect(first.entities != nextDay.entities && first.runSeed != nextDay.runSeed, "Daily course did not rotate")
                try expect(first.dailyID == "2026-10-04", "Daily identity must survive the simulation")
            }),
            ("required world actions are feasible over eight full seeded routes", {
                for expert in [false, true] {
                    for seed in 1...4 {
                        var run = RunnerSimulation()
                        run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                        for tick in 0..<90_000 where run.phase == .running {
                            steerSkillRoute(&run)
                            run.update(dt: 1.0 / 60)
                            if tick % 601 == 0 {
                                run = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                            }
                        }
                        try expect(run.journeyComplete, "Unreachable route seed \(seed), expert \(expert), world \(run.worldStage): \(run.crashReason)")
                        try expect(run.jumps >= 12 && run.rolls >= 6 && run.boardsUsed == 0, "A completed route must use its required skills without shields")
                        try expect(run.stageResults.count == 6, "Each world must settle exactly one mastery result")
                    }
                }
            })
        ]
        for (name, test) in cases { try test(); print("PASS: \(name)") }
        print("\(cases.count) portal journey tests passed.")
    }
}
