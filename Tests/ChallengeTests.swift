import Foundation

@main
struct ChallengeTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
    static func entity(_ kind: EntityKind, id: Int = 1, lane: Int = 0,
                       z: Double = 0, y: Double = 0.9, length: Double = 0.5) -> TrackEntity {
        TrackEntity(id: id, kind: kind, lane: lane, z: z, y: y, length: length)
    }
    static func fixture(_ mode: RunMode = .endless, track: [TrackEntity] = [], expert: Bool = false) -> RunnerSimulation {
        var run = RunnerSimulation()
        run.start(seed: 27, mode: mode, expert: expert)
        run.replaceTrackForTesting(track)
        return run
    }
    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("challenge defaults preserve pre-upgrade saved runs", {
                var original = fixture()
                original.act(.jump)
                original.update(dt: 0.3)
                let data = try JSONEncoder().encode(original)
                var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                legacy.removeValue(forKey: "challenge")
                let restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: legacy))
                try expect(restored.mode == .endless && !restored.expert && restored.combo == 0, "Old saves must get the new mode defaults")
                try expect(restored.distance == original.distance && restored.height == original.height && restored.jumps == 1, "Migration discarded the active run")
            }),
            ("challenge counters and timed mode survive checkpoint round trips", {
                var run = fixture(.jetSki, track: [entity(.gate)])
                run.update(dt: 0.01)
                run.act(.board)
                let restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                try expect(restored.mode == .jetSki && restored.gatesCleared == 1 && restored.combo == 1, "Challenge counters did not survive encode/decode")
                try expect(restored.isBoosting && restored.boostCharge == run.boostCharge && restored.timeRemaining == run.timeRemaining, "Active boost/timer did not survive save")
            }),
            ("sprint checkpoints add time and cannot be collected twice", {
                var run = fixture(.harborSprint, track: [entity(.checkpoint)])
                run.update(dt: 0.02)
                try expect(run.gatesCleared == 1 && run.timeRemaining > 63.9 && run.combo == 1, "Checkpoint should add four seconds and a combo")
                run.update(dt: 0.3)
                try expect(run.gatesCleared == 1, "Checkpoint was credited twice")
            }),
            ("timed modes expire and pause freezes their clock", {
                for mode in [RunMode.harborSprint, .jetSki] {
                    var run = fixture(mode)
                    run.pause()
                    run.update(dt: 20)
                    try expect(run.timeRemaining == 60, "Pause consumed time")
                    run.resume()
                    run.update(dt: 60)
                    run.update(dt: 0.1)
                    try expect(run.phase == .crashed && run.crashReason.contains("Time ran out"), "A timed course must fail if time expires before the goal")
                    run.revive()
                    try expect(run.phase == .running && run.timeRemaining >= 15, "Revive must restore a playable clock")
                }
            }),
            ("sprint finishes at its goal instead of running forever", {
                var run = fixture(.harborSprint)
                for index in 0..<30 where run.phase == .running {
                    run.replaceTrackForTesting([entity(.checkpoint, id: index)])
                    run.update(dt: 5)
                }
                try expect(run.phase == .finished && run.distance >= 1_500, "Sprint did not complete at 1500 m")
                let distance = run.distance
                run.update(dt: 10)
                try expect(run.distance == distance, "Finished sprint continued advancing")
            }),
            ("water course has its own finish and time economy", {
                var run = fixture(.jetSki)
                for index in 0..<45 where run.phase == .running {
                    run.replaceTrackForTesting([entity(.gate, id: index)])
                    run.update(dt: 2)
                }
                try expect(run.phase == .finished && run.distance >= 1_800, "Water course did not finish at 1800 m")
                try expect(run.gatesCleared > 20, "Water course completion fixture did not exercise gates")
            }),
            ("slalom gates reward accuracy and penalize misses", {
                var run = fixture(.jetSki, track: [entity(.gate)])
                run.update(dt: 0.02)
                try expect(run.combo == 1 && run.gatesCleared == 1 && run.boostCharge > 0.8, "Perfect gate must build combo, charge and time")
                let before = run.timeRemaining
                run.replaceTrackForTesting([entity(.gate, id: 2, lane: -1)])
                run.update(dt: 0.1)
                try expect(run.gatesMissed == 1 && run.combo == 0, "A missed gate must reset the chain")
                try expect(before - run.timeRemaining > 4 && before - run.timeRemaining < 4.2, "A missed gate must cost four seconds exactly once")
            }),
            ("water boost spends charge rather than board inventory and does not shield collisions", {
                var boosted = fixture(.jetSki)
                var normal = fixture(.jetSki)
                boosted.act(.board)
                try expect(boosted.isBoosting && boosted.boostCharge < 0.16, "Charged boost did not activate")
                try expect(boosted.availableBoards == 3 && boosted.boardsUsed == 0 && boosted.boardTime == 0, "Boost must not spend or activate a hoverboard")
                boosted.update(dt: 1)
                normal.update(dt: 1)
                try expect(boosted.distance > normal.distance + 9.9, "Boost should make a meaningful speed difference")
                boosted.replaceTrackForTesting([entity(.buoy, z: 5, y: 0, length: 1.2)])
                boosted.update(dt: 0.5)
                try expect(boosted.phase == .crashed, "Boost must remain a risky speed increase, not invulnerability")
            }),
            ("braking lowers water speed and cancels boost", {
                var run = fixture(.jetSki)
                run.act(.board)
                run.act(.roll)
                run.update(dt: 0.1)
                try expect(run.isBraking && !run.isBoosting && run.speed < 13, "Down should brake and cancel boost")
                run.update(dt: 1)
                try expect(!run.isBraking && run.speed > 19, "Brake must expire without permanent slowdown")
            }),
            ("water ramps launch and each airborne trick can score only once", {
                var run = fixture(.jetSki, track: [entity(.waveRamp, z: 5, y: 0, length: 5)])
                run.act(.jump)
                try expect(run.jumps == 0, "A jet ski cannot jump from flat water")
                run.update(dt: 0.45)
                try expect(run.height > 0.5, "Wave ramp did not launch the craft")
                run.act(.jump)
                let charged = run.boostCharge
                run.act(.jump)
                try expect(run.jumps == 1 && run.isTricking && run.boostCharge == charged, "Air tricks must not be farmable by repeated input")
                run.update(dt: 1)
                try expect(run.height == 0 && !run.isTricking, "Water jump must land cleanly")
            }),
            ("airborne hazards are real threats but harmless on the ground", {
                var airborne = fixture(track: [entity(.jetpack), entity(.airHazard, id: 2, z: 18, y: 6.2, length: 2)])
                airborne.update(dt: 2)
                try expect(airborne.phase == .crashed && airborne.crashReason.contains("airborne"), "Jetpack must collide with airborne drones")
                var ground = fixture(track: [entity(.airHazard, z: 5, y: 6.2, length: 2)])
                ground.update(dt: 1)
                try expect(ground.phase == .running, "Ground runner should pass beneath airborne drones")
            }),
            ("flight rings require flight and lateral precision", {
                var flight = fixture(track: [entity(.jetpack), entity(.airRing, id: 2, z: 14, y: 7.1)])
                flight.update(dt: 1.3)
                try expect(flight.gatesCleared == 1 && flight.combo > 0, "Aligned airborne ring should award its challenge bonus")
                var ground = fixture(track: [entity(.airRing, z: 5, y: 7.1)])
                ground.update(dt: 1)
                try expect(ground.gatesCleared == 0, "Grounded runner must not collect a floating ring")
            }),
            ("clean obstacles form a combo and idle time decays it", {
                var run = fixture(track: [entity(.barrier, z: 5, y: 0, length: 0.8), entity(.arch, id: 2, z: 18, y: 0, length: 1.1)])
                run.act(.jump)
                run.update(dt: 0.8)
                try expect(run.combo == 1, "Clean jump should begin a combo")
                run.act(.roll)
                run.update(dt: 0.8)
                try expect(run.phase == .running && run.combo == 2 && run.bestCombo == 2, "Jump-to-slide chain should build a combo")
                run.replaceTrackForTesting([])
                run.update(dt: 5.1)
                try expect(run.combo == 0 && run.bestCombo == 2, "Inactive combo should decay while best combo survives")
            }),
            ("a last-moment lateral dodge counts a near miss but cruising does not", {
                var daring = fixture(track: [entity(.barrier, z: 2.5, y: 0, length: 0.8)])
                daring.update(dt: 0.09)
                daring.act(.left)
                daring.update(dt: 0.3)
                try expect(daring.phase == .running && daring.nearMisses == 1 && daring.combo == 1, "A narrowly timed dodge should earn a close-call combo")
                var cruising = fixture(track: [entity(.barrier, lane: 1, z: 5, y: 0, length: 0.8)])
                cruising.update(dt: 1)
                try expect(cruising.nearMisses == 0 && cruising.combo == 0, "Passing safely in an adjacent lane must not farm risk bonuses")
            }),
            ("shield crashes break a combo without losing the run", {
                var run = fixture(track: [entity(.barrier, z: 5, y: 0, length: 0.8)])
                run.act(.jump)
                run.update(dt: 0.8)
                run.replaceTrackForTesting([entity(.barrier, id: 2, z: 5, y: 0, length: 0.8)])
                run.act(.board)
                run.update(dt: 0.6)
                try expect(run.phase == .running && run.combo == 0 && run.bestCombo == 1, "Shield impact must break the chain but preserve its record")
            }),
            ("expert starts faster and its opening asks for earlier decisions", {
                var standard = RunnerSimulation()
                var expert = RunnerSimulation()
                standard.start(seed: 10)
                expert.start(seed: 10, expert: true)
                standard.update(dt: 0.1)
                expert.update(dt: 0.1)
                try expect(expert.speed >= standard.speed + 3.9, "Expert should change the opening pace")
                let standardHazards = standard.entities.filter { [.barrier, .arch, .tram].contains($0.kind) }.count
                let expertHazards = expert.entities.filter { [.barrier, .arch, .tram].contains($0.kind) }.count
                try expect(expertHazards > standardHazards, "Expert should have denser hazards")
            }),
            ("boosted expert ramp flight can clear the following slalom gate", {
                var run = fixture(.jetSki, track: [entity(.waveRamp, z: 3, y: 0, length: 5), entity(.gate, id: 2, z: 30)], expert: true)
                run.act(.board)
                run.update(dt: 0.92)
                try expect(run.height > 3, "Regression fixture must cross above the old gate limit")
                try expect(run.gatesCleared == 1 && run.gatesMissed == 0, "An aligned boosted ramp jump must clear the next gate")
            }),
            ("expert courses tighten the clock and checkpoint bonuses", {
                var sprint = fixture(.harborSprint, track: [entity(.checkpoint)], expert: true)
                var water = fixture(.jetSki, track: [entity(.gate)], expert: true)
                try expect(sprint.timeRemaining == 45 && water.timeRemaining == 45, "Expert courses must start with a shorter clock")
                sprint.update(dt: 0.02)
                water.update(dt: 0.02)
                try expect(sprint.timeRemaining > 47.9 && sprint.timeRemaining < 48, "Expert checkpoint bonus should be three seconds")
                try expect(water.timeRemaining > 45.4 && water.timeRemaining < 45.5, "Expert gate bonus should be half a second")
            }),
            ("water routes retain one clear gate lane and adequate reaction distance", {
                for expert in [false, true] {
                    for seed in 1...80 {
                        var run = RunnerSimulation()
                        run.start(seed: UInt64(seed), mode: .jetSki, expert: expert)
                        let gates = run.entities.filter { $0.kind == .gate }.sorted { $0.z < $1.z }
                        try expect(!run.entities.contains { [.tram, .arch, .jetpack].contains($0.kind) }, "Water course must not inherit land hazards/power-ups")
                        for (index, gate) in gates.enumerated() {
                            let buoys = run.entities.filter { $0.kind == .buoy && abs($0.z - gate.z) < 0.1 }
                            try expect(buoys.count == 2 && buoys.allSatisfy { $0.lane != gate.lane }, "A slalom gate has no feasible path")
                            if index > 0 {
                                try expect(abs(gate.lane - gates[index - 1].lane) == 1, "Water gates must require only one lane change at a time")
                                // At the maximum expert + boost speed (44 m/s), a 37 m row gives .84 s.
                                try expect(gate.z - gates[index - 1].z >= 37, "Boosted gate approach has inadequate reaction time")
                            }
                        }
                    }
                }
            }),
            ("water steering has momentum, currents and continuous touch targets", {
                var run = fixture(.jetSki)
                run.steerWater(0.35)
                run.update(dt: 0.04)
                try expect(run.lateral > 0 && run.lateral < 0.1 && run.lateralVelocity > 0, "Craft should accelerate into a carve rather than snap")
                run.update(dt: 1)
                try expect(run.lateral > 0.25 && run.lateral < 0.5, "Continuous water steering lost its between-lane target")
                try expect(abs(run.waterCurrent) > 0.05, "Water current must affect the craft")
                run.steerWater(nil)
                run.update(dt: 1)
                try expect(abs(run.lateral) < 0.2, "Releasing a carve must stabilize toward the nearest lane")
                run.steerWater(.nan)
                run.update(dt: 0.1)
                try expect(run.lateral.isFinite, "Invalid touch input poisoned physics")
            }),
            ("air combinations bank only unique tricks after a stable landing", {
                var run = fixture(.jetSki, track: [entity(.waveRamp, z: 3, y: 0, length: 5)])
                run.update(dt: 0.25); run.act(.jump); run.act(.jump)
                try expect(run.trickChain == 1, "Repeated identical tricks must not be farmed")
                run.update(dt: 0.19); run.act(.left)
                run.update(dt: 0.19); run.act(.right)
                try expect(run.trickChain == 3 && run.jumps == 3, "Up-left-right combination should chain three distinct tricks")
                let before = run.score
                run.update(dt: 0.7)
                try expect(run.cleanLandings == 1 && run.trickChain == 0 && run.height == 0, "A stable air combination must bank on landing")
                try expect(run.score > before + 600 && run.boostCharge > 0.99, "Landing should award combo points and earned boost")
            }),
            ("late water tricks lose the landing reward and momentarily slow the craft", {
                var run = fixture(.jetSki, track: [entity(.waveRamp, z: 3, y: 0, length: 5)])
                run.update(dt: 0.9); run.act(.jump)
                try expect(run.trickChain == 1, "Late trick fixture did not execute")
                run.update(dt: 0.3)
                try expect(run.height == 0 && run.cleanLandings == 0 && run.combo == 0 && run.isBraking, "A trick unfinished at landing should lose its banked reward")
                try expect(run.boostCharge < 0.6, "Rough landing should consume a small amount of boost")
            }),
            ("moving boats collide and wake jumps clear their actual hulls", {
                var impact = fixture(.jetSki, track: [TrackEntity(id: 1, kind: .waterTraffic, lane: 0, z: 10, y: 0, length: 5, oncomingSpeed: 4)])
                impact.update(dt: 0.8)
                try expect(impact.phase == .crashed && impact.crashReason.contains("boats"), "Moving water traffic must be a real hazard")
                var jump = fixture(.jetSki, track: [entity(.waveRamp, z: 3, y: 0, length: 5), TrackEntity(id: 2, kind: .waterTraffic, lane: 0, z: 15, y: 0, length: 5, oncomingSpeed: 4)])
                jump.update(dt: 1.4)
                try expect(jump.phase == .running && jump.height == 0, "Well-timed wake jump must clear a boat and land")
            }),
            ("water momentum and pending tricks survive a checkpoint exactly", {
                var run = fixture(.jetSki, track: [entity(.waveRamp, z: 3, y: 0, length: 5)])
                run.update(dt: 0.3); run.act(.jump); run.steerWater(0.4)
                var restored = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(run))
                run.update(dt: 0.7); restored.update(dt: 0.7)
                try expect(run.lateral == restored.lateral && run.height == restored.height && run.score == restored.score && run.trickChain == restored.trickChain, "Checkpoint changed an in-progress water maneuver")
            }),
            ("flight course remains finite, reachable and lane-readable", {
                var run = RunnerSimulation()
                run.start(seed: 7, headstart: true, expert: true)
                run.update(dt: 0.1)
                let rings = run.entities.filter { $0.kind == .airRing }.sorted { $0.z < $1.z }
                try expect(!rings.isEmpty && rings[0].z > 30, "Flight route needs a readable opening")
                for ring in rings {
                    let hazards = run.entities.filter { $0.kind == .airHazard && abs($0.z - ring.z) < 0.1 }
                    try expect(hazards.count == 2 && hazards.allSatisfy { $0.lane != ring.lane }, "Expert flight must preserve its visible ring lane")
                }
            })
        ]
        var failures: [String] = []
        for (name, test) in cases {
            do { try test(); print("PASS \(name)") }
            catch { failures.append("\(name): \(error)"); print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failures.count)/\(cases.count) challenge tests passed")
        if !failures.isEmpty {
            for failure in failures { fputs("\(failure)\n", stderr) }
            throw Failure(description: failures.joined(separator: "; "))
        }
    }
}
