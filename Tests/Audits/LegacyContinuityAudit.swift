import Foundation

/// Legacy checkpoint continuity probe.
///   create <dir> <out.json>        writes v4/v5/v6 checkpoints for every world and difficulty, drives each to its portal
///                                   with a fixed input script under protection, and saves the snapshots.
///   verify <dir> <baseline.json>   drives the same checkpoints with this build. Revision-4 stages use the frozen legacy
///                                   generator and must match the baseline exactly. v5/v6 stages adopt the current
///                                   generator (spec: a resumed run builds new rows with new rules), so they must only
///                                   decode and reach their portal.
/// Scripts/audit.sh compiles `create` against the pre-overhaul sources (e3049e5) and `verify` against HEAD.
/// This is a generator and physics continuity probe, not a survival test: protection keeps the fixed input script alive.
@main struct LegacyContinuityAudit {
    static func main() throws {
        guard CommandLine.arguments.count == 4, ["create", "verify"].contains(CommandLine.arguments[1]) else {
            fatalError("Usage: legacy-probe create|verify checkpoint-directory json")
        }
        let create = CommandLine.arguments[1] == "create"
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        var samples: [String: [RunnerSimulation]] = [:]
        for revision in [4, 5, 6] {
            for expert in [false, true] {
                for stage in 0..<6 {
                    let key = "r\(revision)-e\(expert)-s\(stage)"
                    let path = directory.appendingPathComponent(key + ".json")
                    if create {
                        var run = RunnerSimulation()
                        run.start(seed: UInt64(93 + stage), boards: 0, mode: .odyssey, expert: expert, startStage: stage)
                        var object = try JSONSerialization.jsonObject(with: encoder.encode(run)) as! [String: Any]
                        var journey = object["journey"] as! [String: Any]
                        journey["routeRevision"] = revision
                        object["journey"] = journey
                        object["invulnerableTime"] = 10_000.0
                        object["entities"] = []
                        object["nextPatternDistance"] = revision == 4 ? 65.0 : run.stageOpeningLength
                        var enhancement = object["enhancements"] as! [String: Any]
                        enhancement["generatedRows"] = 0
                        object["enhancements"] = enhancement
                        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: path)
                    }
                    var run = try decoder.decode(RunnerSimulation.self, from: Data(contentsOf: path))
                    samples[key] = [run]
                    var tick = 0
                    while run.phase == .running && !run.isPortalTransitioning && tick < 12_000 {
                        if tick % 77 == 0 { run.act(.jump) }
                        if tick % 137 == 0 { run.act(.roll) }
                        if tick % 179 == 0 { run.act(.right) }
                        if tick % 211 == 0 { run.act(.left) }
                        run.update(dt: 1.0 / 60)
                        tick += 1
                        if tick % 300 == 0 { samples[key]!.append(run) }
                        if tick == 400 {
                            run.act(.jump); run.update(dt: 0.08)
                            run = try decoder.decode(RunnerSimulation.self, from: encoder.encode(run))
                            samples[key]!.append(run)
                        }
                    }
                    guard run.isPortalTransitioning else { fatalError("Did not reach portal: \(key) \(run.phase)") }
                    samples[key]!.append(run)
                }
            }
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        if create {
            try encoder.encode(samples).write(to: output)
            print("Captured \(samples.count) legacy stages and \(samples.values.reduce(0) { $0 + $1.count }) state snapshots")
            return
        }
        let baseline = try decoder.decode([String: [RunnerSimulation]].self, from: Data(contentsOf: output))
        var compared = 0
        for (key, snapshots) in samples.sorted(by: { $0.key < $1.key }) where key.hasPrefix("r4-") {
            guard let old = baseline[key], old.count == snapshots.count else { fatalError("Legacy r4 snapshot count changed: \(key)") }
            for (index, (a, b)) in zip(old, snapshots).enumerated() {
                guard a.entities == b.entities, a.distance == b.distance, a.score == b.score, a.coins == b.coins,
                      a.stageIndex == b.stageIndex, a.phase == b.phase, a.lateral == b.lateral, a.height == b.height else {
                    fatalError("Legacy r4 stage diverged from the pre-overhaul build: \(key) snapshot \(index)")
                }
                compared += 1
            }
        }
        let regenerated = samples.keys.filter { !$0.hasPrefix("r4-") }.count
        print("PASS legacy continuity: \(compared) r4 snapshots match the pre-overhaul build; \(regenerated) v5/v6 stages decode and reach their portal under the current generator")
    }
}
