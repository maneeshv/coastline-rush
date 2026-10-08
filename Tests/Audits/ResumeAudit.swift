import Foundation
// Audit: a run JSON round-tripped every 157 ticks must continue exactly like the uninterrupted run (same seed, same bot).
@main struct ResumeAudit {
    static func main() throws {
        var cases: [(String, RunnerSimulation)] = []
        for expert in [false, true] {
            for seed in [UInt64(1), 7, 23] {
                var r = RunnerSimulation(); r.start(seed: seed, boards: 0, mode: .odyssey, expert: expert); cases.append(("odyssey s\(seed) e\(expert)", r))
                var e = RunnerSimulation(); e.start(seed: seed, boards: 0, mode: .endless, expert: expert); cases.append(("endless s\(seed) e\(expert)", e))
                var s = RunnerSimulation(); s.start(seed: seed, boards: 0, mode: .harborSprint, expert: expert); cases.append(("sprint s\(seed) e\(expert)", s))
            }
            var d = RunnerSimulation(); d.start(seed: 99, boards: 0, mode: .odyssey, expert: expert, dailyID: "2026-10-06"); cases.append(("daily e\(expert)", d))
        }
        var failures = 0
        for (name, start) in cases {
            var a = start, b = start, tick = 0, trips = 0
            let route: BranchRoute = name.hasSuffix("etrue") ? .risky : .safe
            while a.phase == .running && tick < 90_000 && (a.mode == .odyssey || a.elapsed < 300) {
                RouteAudit.drive(&a, route: route); a.update(dt: 1.0 / 60)
                RouteAudit.drive(&b, route: route); b.update(dt: 1.0 / 60)
                tick += 1
                if tick % 157 == 0 {
                    b = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(b)); trips += 1
                }
                if a.entities != b.entities || a.distance != b.distance || a.phase != b.phase {
                    print("DIVERGED \(name) tick=\(tick) stage=\(a.stageIndex)"); failures += 1; break
                }
            }
            precondition(tick > 1_000, "\(name) must run long enough to cross several save points")
            print("\(name): ticks=\(tick) trips=\(trips) phase=\(a.phase) stage=\(a.stageIndex) entitiesEqual=\(a.entities == b.entities)")
        }
        // Daily: two launch seeds, whole journey, must be identical.
        var x = RunnerSimulation(); x.start(seed: 1, boards: 0, mode: .odyssey, dailyID: "2026-10-06")
        var y = RunnerSimulation(); y.start(seed: 2, boards: 0, mode: .odyssey, dailyID: "2026-10-06")
        var t = 0
        while x.phase == .running && t < 90_000 {
            RouteAudit.drive(&x, route: .risky); x.update(dt: 1.0 / 60); RouteAudit.drive(&y, route: .risky); y.update(dt: 1.0 / 60); t += 1
            if x.entities != y.entities { print("DAILY DIVERGED t=\(t)"); failures += 1; break }
        }
        print("daily full journey: ticks=\(t) phase=\(x.phase) equal=\(x.entities == y.entities)")
        print("RESUME divergences=\(failures) cases=\(cases.count)")
        precondition(failures == 0, "A resumed run must continue exactly like an uninterrupted one")
    }
}
