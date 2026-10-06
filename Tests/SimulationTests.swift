import Foundation

/// Run: swiftc -swift-version 5 -module-cache-path work/SwiftModuleCache \
/// Sources/RunnerSimulation.swift Tests/SimulationTests.swift -o work/simulation-tests
@main
struct SimulationTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    static func entity(_ kind: EntityKind, id: Int = 1, lane: Int = 0,
                       z: Double = 5, y: Double = 0.9, length: Double = 0.8,
                       oncomingSpeed: Double = 0) -> TrackEntity {
        TrackEntity(id: id, kind: kind, lane: lane, z: z, y: y, length: length,
                    oncomingSpeed: oncomingSpeed)
    }

    static func fixture(_ track: [TrackEntity] = [], boards: Int = 3,
                        multiplier: Int = 1, durations: [PowerUp: Double] = [:]) -> RunnerSimulation {
        var simulation = RunnerSimulation()
        simulation.start(seed: 42, baseMultiplier: multiplier, durations: durations, boards: boards)
        simulation.replaceTrackForTesting(track)
        return simulation
    }

    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("lane controls clamp and interpolate", {
                var simulation = fixture()
                simulation.act(.left)
                simulation.act(.left)
                try expect(simulation.lane == -1 && simulation.lateral == 0, "Target lane should clamp and visual position should interpolate")
                simulation.update(dt: 0.2)
                try expect(simulation.lateral == -1, "Lane change did not finish")
                simulation.act(.right)
                simulation.act(.right)
                simulation.act(.right)
                simulation.update(dt: 0.3)
                try expect(simulation.lane == 1 && simulation.lateral == 1, "Right boundary failed")
            }),
            ("running into a barrier crashes with useful reason", {
                var simulation = fixture([entity(.barrier)])
                simulation.update(dt: 1)
                try expect(simulation.phase == .crashed, "A missed barrier must crash")
                try expect(simulation.crashReason.contains("Jump"), "Barrier reason should teach jumping")
                let distance = simulation.distance
                simulation.update(dt: 2)
                try expect(simulation.distance == distance, "A crashed run must freeze")
            }),
            ("jump clears barriers and lands", {
                var simulation = fixture([entity(.barrier)])
                simulation.act(.jump)
                simulation.act(.jump)
                simulation.update(dt: 1)
                try expect(simulation.phase == .running, "Jump should clear a correctly timed barrier")
                try expect(simulation.height == 0 && simulation.jumps == 1, "Jump should land and reject midair double jumps")
                try expect(simulation.dodges == 1, "Avoided obstacle should count exactly once")
            }),
            ("roll clears arches but jumping does not", {
                var rolling = fixture([entity(.arch)])
                rolling.act(.roll)
                rolling.update(dt: 0.65)
                try expect(rolling.phase == .running && rolling.rolls == 1, "Roll must pass under an arch")
                rolling.update(dt: 0.3)
                try expect(!rolling.isRolling, "Roll timer should expire")
                var jumping = fixture([entity(.arch)])
                jumping.act(.jump)
                jumping.update(dt: 0.6)
                try expect(jumping.phase == .crashed, "Jumping into the crossbar must crash")
            }),
            ("late jump swipes buffer across landing but early repeats do not", {
                var run = fixture()
                run.act(.jump); run.update(dt: 0.69)
                try expect(run.height > 0 && run.height < 0.9, "Buffer fixture must be just above landing")
                run.act(.jump); run.update(dt: 0.13)
                try expect(run.jumps == 2 && run.height > 0, "A swipe within 120 ms of landing should become the next jump")
                var early = fixture(); early.act(.jump); early.update(dt: 0.2); early.act(.jump); early.update(dt: 1)
                try expect(early.jumps == 1 && early.height == 0, "Early midair input should not create a queued double jump")
            }),
            ("roll forces an airborne runner down", {
                var simulation = fixture()
                simulation.act(.jump)
                simulation.update(dt: 0.2)
                let before = simulation.height
                simulation.act(.roll)
                simulation.update(dt: 0.08)
                try expect(simulation.height < before, "An airborne roll should fast-fall")
                simulation.update(dt: 0.2)
                try expect(simulation.height == 0, "Fast fall must return to the ground")
            }),
            ("lateral dodge avoids a tram", {
                var simulation = fixture([entity(.tram, length: 6)])
                simulation.act(.right)
                simulation.update(dt: 1)
                try expect(simulation.phase == .running, "Switching lanes in time should avoid the tram")
                try expect(simulation.dodges == 1, "Tram should count after its rear edge passes")
            }),
            ("ramps connect to collectible tram roofs", {
                var simulation = fixture([
                    entity(.ramp, id: 1, z: 6, y: 0, length: 7),
                    entity(.tram, id: 2, z: 16, y: 0, length: 12),
                    entity(.coin, id: 3, z: 16, y: 3.7, length: 0.3)
                ])
                simulation.update(dt: 1.3)
                try expect(simulation.phase == .running, "Ramp should safely carry the runner onto the tram")
                try expect(abs(simulation.height - RunnerSimulation.tramRoofHeight) < 0.01, "Runner should stand on roof")
                try expect(simulation.coins == 1, "Roof coins must be collectible")
                simulation.update(dt: 1.5)
                try expect(simulation.height == 0, "Runner must fall from the end of the roof")
            }),
            ("roof support follows a completed lane shift", {
                func carried(runnerLane: Int) -> RunnerSimulation {
                    var tram = entity(.tram, id: 2, lane: -1, z: 16, y: 0, length: 12)
                    tram.targetLane = 0; tram.motionStart = 40; tram.motionLength = 6 // finished long before it arrives
                    var run = fixture([entity(.ramp, id: 1, lane: runnerLane, z: 6, y: 0, length: 7), tram])
                    if runnerLane == -1 { run.act(.left) }
                    run.update(dt: 1.3)
                    return run
                }
                let arrival = carried(runnerLane: 0)
                try expect(arrival.phase == .running && abs(arrival.height - RunnerSimulation.tramRoofHeight) < 0.01,
                           "A runner in the arrival lane must stand on the shifted tram's roof")
                let spawn = carried(runnerLane: -1)
                try expect(spawn.phase == .running && spawn.height < 0.5, "The spawn lane has no roof once the tram has left it")
            }),
            ("board consumes inventory and absorbs exactly one hit", {
                var simulation = fixture([entity(.barrier)], boards: 2)
                simulation.act(.board)
                simulation.act(.board)
                try expect(simulation.availableBoards == 1 && simulation.boardsUsed == 1, "An active board must not consume more inventory")
                simulation.update(dt: 0.6)
                try expect(simulation.phase == .running && simulation.boardTime == 0, "A board should absorb one collision and break")
                try expect(simulation.invulnerableTime > 0, "Board break should grant collision grace")
                simulation.update(dt: 2.5)
                simulation.replaceTrackForTesting([entity(.barrier)])
                simulation.update(dt: 1)
                try expect(simulation.phase == .crashed, "A broken board must not absorb a second hit")
                var empty = fixture(boards: 0)
                empty.act(.board)
                try expect(empty.boardTime == 0 && empty.availableBoards == 0, "Empty board inventory must be respected")
            }),
            ("board naturally expires after thirty active seconds", {
                var simulation = fixture(boards: 1)
                simulation.act(.board)
                simulation.update(dt: 29)
                try expect(simulation.boardTime > 0.9, "Board expired early")
                simulation.update(dt: 1.1)
                try expect(simulation.boardTime == 0, "Board should expire after thirty seconds")
            }),
            ("pause freezes world, power timers and controls", {
                var simulation = fixture([entity(.magnet, z: 0)], durations: [.magnet: 5])
                simulation.update(dt: 0.01)
                simulation.act(.board)
                simulation.pause()
                let before = simulation
                simulation.act(.left)
                simulation.act(.jump)
                simulation.update(dt: 10)
                try expect(simulation.distance == before.distance && simulation.height == before.height, "Paused world must freeze")
                try expect(simulation.activePowerUps == before.activePowerUps && simulation.boardTime == before.boardTime, "Paused timers must freeze")
                try expect(simulation.lane == before.lane && simulation.jumps == 0, "Controls should be ignored during pause")
                simulation.resume()
                simulation.update(dt: 0.5)
                try expect(simulation.distance > before.distance && simulation.boardTime < before.boardTime, "Resume must continue simulation")
            }),
            ("revive clears crash and grants limited immunity", {
                var simulation = fixture([entity(.barrier)])
                simulation.update(dt: 1)
                simulation.revive()
                try expect(simulation.phase == .running && simulation.crashReason.isEmpty, "Revive should restore active state")
                simulation.replaceTrackForTesting([entity(.barrier, z: 0)])
                simulation.update(dt: 0.5)
                try expect(simulation.phase == .running, "Revive grace must prevent immediate collision")
                simulation.update(dt: 3)
                simulation.replaceTrackForTesting([entity(.barrier)])
                simulation.update(dt: 1)
                try expect(simulation.phase == .crashed, "Revive immunity must expire")
            }),
            ("magnet collects coins across lanes but not keys", {
                var simulation = fixture([
                    entity(.magnet, id: 1, z: 0),
                    entity(.coin, id: 2, lane: -1, z: 12),
                    entity(.coin, id: 3, lane: 1, z: 10),
                    entity(.key, id: 4, lane: 1, z: 10)
                ])
                simulation.update(dt: 0.1)
                try expect(simulation.coins == 2 && simulation.keys == 0, "Magnet should attract nearby coins across lanes")
                try expect(simulation.activePowerUps[.magnet] != nil, "Magnet pickup did not activate")
            }),
            ("low coins need a roll", {
                let low = entity(.coin, id: 1, lane: 0, z: 0.4, y: 0.35, length: 0.3)
                var standing = fixture([low])
                standing.update(dt: 1.0 / 60)
                try expect(standing.coins == 0, "A standing runner should pass over a low coin")
                var rolling = fixture([low])
                rolling.act(.roll)
                rolling.update(dt: 1.0 / 60)
                try expect(rolling.coins == 1, "A rolling runner should collect a low coin")
                var high = fixture([entity(.coin, id: 1, lane: 0, z: 0.4, y: 0.9, length: 0.3)])
                high.update(dt: 1.0 / 60)
                try expect(high.coins == 1, "A standing runner should still collect a chest-high coin")
            }),
            ("aligned keys are collected once", {
                var simulation = fixture([entity(.key, z: 0)])
                simulation.update(dt: 0.1)
                simulation.update(dt: 1)
                try expect(simulation.keys == 1, "Key should be collected exactly once")
            }),
            ("jetpack flies above collisions and collects airborne coins", {
                var simulation = fixture([
                    entity(.jetpack, id: 1, z: 0),
                    entity(.tram, id: 2, z: 10, y: 0, length: 12),
                    entity(.coin, id: 3, z: 12, y: 7.1, length: 0.3)
                ], durations: [.jetpack: 1.5])
                simulation.update(dt: 1)
                try expect(simulation.phase == .running && simulation.height > 6, "Jetpack should fly safely above a tram")
                try expect(simulation.coins >= 1, "Jetpack should collect airborne coins")
                simulation.update(dt: 2)
                try expect(simulation.activePowerUps[.jetpack] == nil && simulation.height == 0, "Jetpack should expire and land safely")
                try expect(simulation.phase == .running, "Landing grace should avoid unfair crashes")
            }),
            ("sneakers raise the jump arc", {
                var plain = fixture()
                var powered = fixture([entity(.sneakers, z: 0)])
                powered.update(dt: 0.01)
                plain.act(.jump)
                powered.act(.jump)
                plain.update(dt: 0.4)
                powered.update(dt: 0.4)
                try expect(powered.height > plain.height + 1, "Sneakers must noticeably raise jump height")
            }),
            ("score multipliers apply then expire", {
                var ordinary = fixture(multiplier: 3)
                var powered = fixture([entity(.multiplier, z: 0)], multiplier: 3, durations: [.multiplier: 1])
                ordinary.update(dt: 0.5)
                powered.update(dt: 0.5)
                try expect(powered.multiplier == 6, "Power pickup should double the base multiplier")
                try expect(powered.score > ordinary.score * 19 / 10, "Distance score should reflect the power multiplier")
                powered.update(dt: 0.7)
                try expect(powered.multiplier == 3, "Score multiplier must return to the base value")
            }),
            ("oncoming trams close faster and cannot tunnel through the runner", {
                var stationary = fixture([entity(.tram, z: 30, length: 12)])
                var oncoming = fixture([entity(.tram, z: 30, length: 12, oncomingSpeed: 10)])
                stationary.update(dt: 0.5)
                oncoming.update(dt: 0.5)
                try expect(abs(stationary.entities[0].z - oncoming.entities[0].z - 5) < 0.000_001,
                           "Oncoming tram should advance by its extra velocity")
                stationary.update(dt: 0.7)
                oncoming.update(dt: 0.7)
                try expect(stationary.phase == .running && oncoming.phase == .crashed,
                           "An oncoming tram should reach the runner before a stationary tram")
                try expect(oncoming.distance < 15, "Large delta should detect the approaching tram collision")
            }),
            ("entity saves preserve speed and accept older stationary entities", {
                let approaching = entity(.tram, oncomingSpeed: 11)
                let roundTrip = try JSONDecoder().decode(TrackEntity.self, from: JSONEncoder().encode(approaching))
                try expect(roundTrip == approaching, "Oncoming speed should survive a saved run")
                let legacy = Data(#"{"id":1,"kind":"tram","lane":0,"z":30,"y":0,"length":12}"#.utf8)
                let decoded = try JSONDecoder().decode(TrackEntity.self, from: legacy)
                try expect(decoded.oncomingSpeed == 0, "Older entity saves should decode as stationary")
            }),
            ("new entity fields decode with defaults and round-trip", {
                let legacy = Data(#"{"id":1,"kind":"meteor","lane":0,"z":30,"y":0,"length":2}"#.utf8)
                let old = try JSONDecoder().decode(TrackEntity.self, from: legacy)
                try expect(old.targetLane == nil && old.motionStart == 0 && old.motionLength == 0 && old.cyclePhase == -1 && old.activeFrom == .infinity,
                           "Old entities must decode with inert defaults")
                let plain = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
                try expect(!plain.contains("activeFrom") && !plain.contains("targetLane") && !plain.contains("cyclePhase") && !plain.contains("motion"),
                           "Default fields must not be written (JSON cannot hold an infinite activeFrom)")
                var moving = entity(.tram, lane: -1, z: 40, length: 7)
                moving.targetLane = 0; moving.motionStart = 30; moving.motionLength = 6; moving.cyclePhase = 0.4; moving.activeFrom = 12
                let restored = try JSONDecoder().decode(TrackEntity.self, from: JSONEncoder().encode(moving))
                try expect(restored == moving, "Set fields must survive a checkpoint")
            }),
            ("lane offset, laser cycle and activation are pure functions of z and time", {
                var shifting = entity(.tram, lane: -1, z: 31, length: 7)
                shifting.targetLane = 0; shifting.motionStart = 30; shifting.motionLength = 6
                try expect(shifting.laneOffset() == 0 && shifting.arrivalLane == 0, "No shift before motionStart; arrival lane is the target")
                shifting.z = 27
                try expect(abs(shifting.laneOffset() - 0.5) < 1e-9, "Halfway through the shift the offset is half a lane")
                shifting.z = 20
                try expect(shifting.laneOffset() == 1, "The shift completes at motionStart - motionLength")
                var laser = entity(.laserSweep)
                try expect(laser.isOn(at: 0.5) && laser.isOn(at: 1.5), "Untimed lasers are always on")
                laser.cyclePhase = 0
                try expect(laser.isOn(at: 0.1) && !laser.isOn(at: 1.0) && laser.isOn(at: 1.85), "Timed lasers are on 0.9 s, off 0.9 s")
                var meteor = entity(.meteor, z: 12, length: 2)
                meteor.activeFrom = 10
                try expect(!meteor.isActive, "Inactive before its activation z")
                meteor.z = 10
                try expect(meteor.isActive, "Active from its activation z")
            }),
            ("colliders follow lane shifts, laser cycles and activation", {
                func shifting() -> TrackEntity {
                    var tram = entity(.tram, lane: -1, z: 30, y: 0, length: 7)
                    tram.targetLane = 0; tram.motionStart = 26; tram.motionLength = 6
                    return tram
                }
                var hit = fixture([shifting()])
                hit.update(dt: 3)
                try expect(hit.phase == .crashed, "A tram shifting into the runner's lane must collide")
                var left = fixture([shifting()])
                left.act(.left)
                left.update(dt: 3)
                try expect(left.phase == .running, "The lane a shifting tram leaves must be safe")
                func laser(_ phase: Double) -> TrackEntity {
                    var beam = entity(.laserSweep, z: 6, y: 0, length: 1.1)
                    beam.cyclePhase = phase
                    return beam
                }
                var on = fixture([laser(0)])
                on.update(dt: 1)
                try expect(on.phase == .crashed, "A laser that is on while a standing runner passes collides")
                var off = fixture([laser(0.9)])
                off.update(dt: 1)
                try expect(off.phase == .running, "A laser that is off lets a standing runner through")
                var rolled = fixture([laser(0)])
                rolled.act(.roll)
                rolled.update(dt: 1)
                try expect(rolled.phase == .running, "Rolling is always safe under a timed laser")
                var meteor = entity(.meteor, z: 6, y: 0, length: 2)
                meteor.activeFrom = -50
                var dormant = fixture([meteor])
                dormant.update(dt: 1)
                try expect(dormant.phase == .running, "An inactive collider cannot hit")
                meteor.activeFrom = 20
                var impact = fixture([meteor])
                impact.update(dt: 1)
                try expect(impact.phase == .crashed, "An active collider hits")
            }),
            ("large frame deltas cannot tunnel through obstacles", {
                var simulation = fixture([entity(.barrier, z: 50)])
                simulation.update(dt: 10)
                try expect(simulation.phase == .crashed && simulation.distance < 51, "Large dt tunneled past a barrier")
            }),
            ("frame subdivision preserves motion and score", {
                var oneFrame = fixture()
                var manyFrames = fixture()
                oneFrame.update(dt: 1)
                for _ in 0..<90 { manyFrames.update(dt: 1.0 / 90.0) }
                try expect(abs(oneFrame.distance - manyFrames.distance) < 0.000_001, "Subdivided frames should match a single update")
                try expect(oneFrame.score == manyFrames.score, "Score changed with frame subdivision")
            }),
            ("seeded generation and replay reproduce exactly", {
                var first = RunnerSimulation()
                var second = RunnerSimulation()
                first.start(seed: 123)
                second.start(seed: 123)
                try expect(first.entities == second.entities, "Same seed must generate identical tracks")
                for _ in 0..<20 {
                    first.update(dt: 0.1)
                    second.update(dt: 0.1)
                }
                try expect(first.entities == second.entities && first.score == second.score, "Replay diverged")
                second.start(seed: 456)
                try expect(first.entities != second.entities, "Different seeds should vary the track")
            }),
            ("procedural rows retain an open lane and increase difficulty", {
                var sawAnyOncoming = false
                for seed in 1...10 {
                    var simulation = RunnerSimulation()
                    simulation.start(seed: UInt64(seed), durations: [.jetpack: 1_000])
                    let earlyObstacles = simulation.entities.filter { [.barrier, .arch, .tram].contains($0.kind) }
                    try expect(earlyObstacles.allSatisfy { $0.z >= 28 }, "First hazards must leave a visible opening approach")
                    simulation.replaceTrackForTesting([entity(.jetpack, z: 0)], generate: true)
                    var sawStationaryRoof = false
                    for _ in 0..<500 {
                        // This is a course-generation invariant test. Follow the new flight route
                        // so airborne hazards do not turn it into a passive invulnerability test.
                        if let upcoming = simulation.entities.filter({ $0.kind == .airRing && $0.z > 0 }).min(by: { $0.z < $1.z }), upcoming.z < 25 {
                            while simulation.lane < upcoming.lane { simulation.act(.right) }
                            while simulation.lane > upcoming.lane { simulation.act(.left) }
                        }
                        simulation.update(dt: 0.2)
                        let obstacles = simulation.entities.filter { [.barrier, .arch, .tram].contains($0.kind) }
                        var rows: [Int: Set<Int>] = [:]
                        for obstacle in obstacles {
                            rows[Int((obstacle.z * 1_000).rounded()), default: []].insert(obstacle.lane)
                        }
                        try expect(rows.values.allSatisfy { $0.count < 3 }, "Generated an impassable three-lane wall")
                        let oncoming = obstacles.filter { $0.oncomingSpeed > 0 }
                        if !oncoming.isEmpty {
                            sawAnyOncoming = true
                            try expect(simulation.distance > 500, "Moving trams must wait until the advanced section")
                        }
                        if simulation.entities.contains(where: { $0.kind == .ramp }) { sawStationaryRoof = true }
                        // Check interval overlap, not just matching row centers: moving trams cross rows.
                        for obstacle in obstacles {
                            for point in [obstacle.z - obstacle.length / 2 - 0.35,
                                          obstacle.z, obstacle.z + obstacle.length / 2 + 0.35] {
                                let blockedLanes = Set(obstacles.filter {
                                    abs($0.z - point) <= $0.length / 2 + 0.35 + 0.000_001
                                }.map(\.lane))
                                try expect(blockedLanes.count < 3, "A moving tram filled another row's only safe lane")
                            }
                        }
                    }
                    try expect(sawStationaryRoof, "Advanced tracks must retain stationary roof routes")
                    try expect(simulation.phase == .running && simulation.speed > 20, "Progression should accelerate and remain active")
                    try expect(simulation.entities.count < 200, "Entity pruning must bound memory")
                }
                try expect(sawAnyOncoming, "Advanced generation should include oncoming trams")
            }),
            ("finish is terminal and starting again resets counters", {
                var simulation = fixture()
                simulation.act(.jump)
                simulation.update(dt: 2)
                simulation.finish()
                let distance = simulation.distance
                simulation.update(dt: 2)
                try expect(simulation.phase == .finished && simulation.distance == distance, "Finished run must stop")
                simulation.start(seed: 42, boards: 4)
                try expect(simulation.distance == 0 && simulation.jumps == 0 && simulation.score == 0, "Start should reset the previous run")
                try expect(simulation.availableBoards == 4, "Start should restore the supplied inventory")
            }),
            ("headstart and invalid time inputs behave safely", {
                var simulation = RunnerSimulation()
                simulation.start(seed: 0, headstart: true)
                try expect(simulation.activePowerUps[.jetpack] != nil, "Headstart must activate flight")
                simulation.update(dt: .infinity)
                simulation.update(dt: .nan)
                simulation.update(dt: -1)
                try expect(simulation.distance == 0, "Invalid dt should be ignored")
                simulation.update(dt: 0.5)
                try expect(simulation.height > 0, "Valid time should advance headstart flight")
            })
        ]
        var failures: [String] = []
        for (name, body) in cases {
            do {
                try body()
                print("PASS \(name)")
            } catch {
                failures.append("\(name): \(error)")
                print("FAIL \(name): \(error)")
            }
        }
        print("\(cases.count - failures.count)/\(cases.count) simulation tests passed")
        if !failures.isEmpty { throw Failure(description: failures.joined(separator: "\n")) }
    }
}
