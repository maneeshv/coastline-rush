import Foundation

/// Compile once against the archived release and once against the current sources.
/// Both executables consume identical serialized checkpoints. This is a generator
/// and physics continuity probe, not a survival test: protection keeps the fixed
/// input script alive so every old stage is compared through its portal approach.
@main struct LegacyContinuityAudit {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: legacy-probe create|compare checkpoint-directory output-json")
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
        try encoder.encode(samples).write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
        print("Captured \(samples.count) legacy stages and \(samples.values.reduce(0) { $0 + $1.count }) state snapshots")
    }
}
