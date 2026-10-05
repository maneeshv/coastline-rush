import Foundation

@main struct WaterAudit {
    static func main() throws {
        var successes = 0, failures = 0, gates = 0, missed = 0
        for expert in [false, true] {
            for seed in 1...30 {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .jetSki, expert: expert)
                var heldLane = 0, holdUntil = 0.0, tick = 0
                while run.phase == .running && tick < 20_000 {
                    if run.distance >= holdUntil,
                       let next = run.entities.filter({ $0.kind == .gate && $0.z > -0.9 }).min(by: { $0.z < $1.z }) {
                        // A boat may cross the intended turn just after a gate.
                        // Wait on the previous clear lane until its stern passes.
                        let turningBoat = run.entities.contains {
                            $0.kind == .waterTraffic && $0.lane == next.lane && $0.z > -3.5 && $0.z < run.speed * 0.55 + 3
                        }
                        if !turningBoat {
                            heldLane = next.lane
                            holdUntil = run.distance + next.z + 1.6
                        }
                    }
                    run.steerWater(Double(heldLane))
                    if run.boostCharge >= 0.5 && !run.isBoosting { run.act(.board) }
                    run.update(dt: 1.0 / 60.0)
                    tick += 1
                }
                gates += run.gatesCleared; missed += run.gatesMissed
                if run.phase == .finished { successes += 1 }
                else {
                    failures += 1
                    print("FAIL seed=\(seed) expert=\(expert) distance=\(run.distance) lane=\(run.lane) x=\(run.lateral) y=\(run.height) target=\(heldLane) holdUntil=\(holdUntil) speed=\(run.speed) time=\(run.timeRemaining) reason=\(run.crashReason)")
                    for e in run.entities where [.gate, .buoy, .waterTraffic, .waveRamp].contains(e.kind) && abs(e.z) < 30 { print("  \(e.kind) lane=\(e.lane) z=\(e.z) length=\(e.length)") }
                    if failures >= 8 { break }
                }
            }
        }
        print("RESULT water complete=\(successes), failed=\(failures), gates=\(gates), missed=\(missed); actual generated course, no fixtures, no revives, immediate charged boost")
        if failures > 0 { exit(1) }
    }
}
