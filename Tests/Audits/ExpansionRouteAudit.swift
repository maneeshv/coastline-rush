import Foundation
@main struct ExpansionRouteAudit {
    static func main() {
        var passes = 0, failures = 0
        for expert in [false, true] {
            for world in 0..<6 {
                var run = RunnerSimulation()
                run.start(seed: UInt64(101 + world), boards: 0, mode: .odyssey, expert: expert, startStage: world, expeditionStyle: .practice)
                var frames = 0
                while run.phase == .running && frames < 5000 {
                    RouteAudit.drive(&run, route: .risky)
                    run.update(dt: 1.0/60)
                    frames += 1
                }
                if run.phase == .finished && run.stagesCleared == 1 && run.stageResults[0].hits == 0 { passes += 1 }
                else { failures += 1; print("PRACTICE FAIL expert=\(expert) world=\(world) distance=\(run.stageDistance) reason=\(run.crashReason)") }
            }
            for seed in 1...2 {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert, expeditionStyle: .endless)
                var frames = 0, maxEntities = 0
                while run.phase == .running && run.stagesCleared < 13 && frames < 100_000 {
                    let oldBase = run.stageTargetSpeed
                    RouteAudit.drive(&run, route: seed == 1 ? .safe : .risky)
                    run.update(dt: 1.0/60)
                    if run.stageTargetSpeed + 0.000001 < oldBase { fatalError("Base speed fell") }
                    frames += 1; maxEntities = max(maxEntities, run.entities.count)
                }
                if run.phase == .running && run.stagesCleared == 13 && run.stageResults.allSatisfy({ $0.hits == 0 }) {
                    passes += 1; print("ENDLESS PASS expert=\(expert) seed=\(seed) stages=\(run.stagesCleared) elapsed=\(run.elapsed) maxEntities=\(maxEntities) speed=\(run.speed)")
                } else {
                    failures += 1; print("ENDLESS FAIL expert=\(expert) seed=\(seed) cycle=\(run.expeditionCycle) world=\(run.worldStage) progress=\(run.stageProgress) x=\(run.lateral) y=\(run.height) speed=\(run.speed) reason=\(run.crashReason)")
                    for e in run.entities where abs(e.z) < 20 { print(e) }
                }
            }
        }
        print("EXPANSION GENERATED AUDIT passes=\(passes) failures=\(failures)")
        if failures > 0 { exit(1) }
    }
}
