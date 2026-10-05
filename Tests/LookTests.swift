import AppKit
import Metal
import SceneKit

/// Verifies that every world applies its look and that the grading LUT stays off.
@main struct LookTests {
    static func main() {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        world.applyQuality(.ultra)
        // 1. Every world applies its own table, and off-world skies are real assets.
        for (index, stage) in WorldStage.allCases.enumerated() {
            var stageRun = RunnerSimulation(); stageRun.start(seed: 3, mode: .odyssey, startStage: index)
            world.update(simulation: stageRun, character: "milo", board: "tideline", time: 2)
            let camera = world.camera.camera!, look = stage.look
            precondition(abs(Double(camera.contrast) - look.contrast) < 0.001, "\(stage): contrast not applied")
            precondition(abs(Double(camera.saturation) - look.saturation) < 0.001, "\(stage): saturation not applied")
            precondition(camera.colorGrading.contents == nil, "\(stage): grading LUT must stay off (floors darks)")
            precondition(abs(Double(world.scene.fogEndDistance) - look.fogEnd) < 0.001, "\(stage): fog not applied")
            if stage != .harbor && stage != .orbit {
                let sky = resources.appendingPathComponent(stage.rawValue.capitalized + "Sky.png")
                precondition(FileManager.default.fileExists(atPath: sky.path), "\(stage): missing \(sky.lastPathComponent)")
            }
        }
        // 2. Performance tier drops grain; ultra keeps it.
        world.applyQuality(.performance)
        precondition(world.camera.camera!.grainIntensity == 0, "performance tier must not use grain")
        print("LookTests passed")
    }
}
