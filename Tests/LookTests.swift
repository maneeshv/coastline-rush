import AppKit
import Metal
import SceneKit

/// Verifies the grading LUT layout against SceneKit and that every world applies its look.
@main struct LookTests {
    static func meanAbsDifference(_ a: NSImage, _ b: NSImage) -> Double {
        let ra = NSBitmapImageRep(data: a.tiffRepresentation!)!, rb = NSBitmapImageRep(data: b.tiffRepresentation!)!
        var total = 0.0, n = 0
        for y in stride(from: 0, to: ra.pixelsHigh, by: 3) { for x in stride(from: 0, to: ra.pixelsWide, by: 3) {
            let ca = ra.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, cb = rb.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            total += abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent) + abs(ca.blueComponent - cb.blueComponent)
            n += 3
        } }
        return total / Double(n)
    }

    static func main() {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        world.applyQuality(.ultra)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = world.scene; renderer.pointOfView = world.camera
        var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: 0)
        world.update(simulation: run, character: "milo", board: "tideline", time: 1)
        let size = CGSize(width: 160, height: 260)

        // 1. An identity LUT must leave the frame unchanged; a wrong slice/row order would not.
        world.camera.camera?.colorGrading.contents = nil
        let plain = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .none)
        world.camera.camera?.colorGrading.contents = CoastalWorld.gradingLUT { $0 }
        let identity = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .none)
        let identityDiff = meanAbsDifference(plain, identity)
        precondition(identityDiff < 0.012, "Identity LUT changed the frame by \(identityDiff); slice or row order is wrong")
        // 2. An inverting LUT must change it a lot, proving the LUT is applied at all.
        world.camera.camera?.colorGrading.contents = CoastalWorld.gradingLUT { 1 - $0 }
        let inverted = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .none)
        precondition(meanAbsDifference(plain, inverted) > 0.2, "Inverting LUT had no effect")

        // 3. Every world applies its own table, and off-world skies are real assets.
        for (index, stage) in WorldStage.allCases.enumerated() {
            var stageRun = RunnerSimulation(); stageRun.start(seed: 3, mode: .odyssey, startStage: index)
            world.update(simulation: stageRun, character: "milo", board: "tideline", time: 2)
            let camera = world.camera.camera!, look = stage.look
            precondition(abs(Double(camera.contrast) - look.contrast) < 0.001, "\(stage): contrast not applied")
            precondition(abs(Double(camera.saturation) - look.saturation) < 0.001, "\(stage): saturation not applied")
            precondition(camera.colorGrading.contents != nil, "\(stage): no grading LUT")
            precondition(abs(Double(world.scene.fogEndDistance) - look.fogEnd) < 0.001, "\(stage): fog not applied")
            if stage != .harbor && stage != .orbit {
                let sky = resources.appendingPathComponent(stage.rawValue.capitalized + "Sky.png")
                precondition(FileManager.default.fileExists(atPath: sky.path), "\(stage): missing \(sky.lastPathComponent)")
            }
        }
        // 4. Performance tier drops grain; ultra keeps it.
        world.applyQuality(.performance)
        precondition(world.camera.camera!.grainIntensity == 0, "performance tier must not use grain")
        print("LookTests passed (identity LUT diff \(String(format: "%.4f", identityDiff)))")
    }
}
