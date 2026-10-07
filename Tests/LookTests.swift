import AppKit
import SceneKit

/// Verifies that every world applies its look (grading, fog, white balance, rim) and that the grading LUT stays off.
@main struct LookTests {
    static func main() {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        world.applyQuality(.ultra)
        // 1. Every world applies its own look (contrast, saturation, fog), and off-world skies are real assets.
        for (index, stage) in WorldStage.allCases.enumerated() {
            var stageRun = RunnerSimulation(); stageRun.start(seed: 3, mode: .odyssey, startStage: index)
            world.update(simulation: stageRun, character: "milo", board: "tideline", time: 2)
            let camera = world.camera.camera!, look = stage.look
            precondition(abs(Double(camera.contrast) - look.contrast) < 0.001, "\(stage): contrast not applied")
            precondition(abs(Double(camera.saturation) - look.saturation) < 0.001, "\(stage): saturation not applied")
            precondition(camera.colorGrading.contents == nil, "\(stage): grading LUT must stay off (floors darks)")
            precondition(abs(Double(world.scene.fogEndDistance) - look.fogEnd) < 0.001, "\(stage): fog not applied")
            precondition(abs(Double(camera.whiteBalanceTemperature) - look.temperature) < 0.001 && abs(Double(camera.whiteBalanceTint) - look.tint) < 0.001, "\(stage): white balance not applied")
            precondition(abs(Double(world.worldRim!.intensity) - look.rimIntensity) < 0.001, "\(stage): rim light not applied")
            if stage != .harbor && stage != .orbit {
                let sky = resources.appendingPathComponent(stage.rawValue.capitalized + "Sky.png")
                precondition(FileManager.default.fileExists(atPath: sky.path), "\(stage): missing \(sky.lastPathComponent)")
            }
        }
        // Phase 4: each world has its own bounded white balance, and Orbit's rim light is at least twice any other world's.
        let looks = WorldStage.allCases.map(\.look)
        precondition(Set(looks.map { "\($0.temperature) \($0.tint)" }).count == looks.count, "every world needs its own white balance")
        precondition(looks.allSatisfy { abs($0.temperature) <= 0.6 && abs($0.tint) <= 0.25 }, "white balance outside ±0.6 temperature / ±0.25 tint")
        precondition(WorldStage.allCases.allSatisfy { $0 == .orbit || WorldStage.orbit.look.rimIntensity >= 2 * $0.look.rimIntensity }, "Orbit needs the strong rim")
        // 2. Performance tier drops grain; ultra keeps it.
        precondition(world.camera.camera!.grainIntensity > 0, "ultra tier must use grain")
        world.applyQuality(.performance)
        precondition(world.camera.camera!.grainIntensity == 0, "performance tier must not use grain")
        print("LookTests passed")
    }
}
