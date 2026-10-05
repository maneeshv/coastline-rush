// Offscreen visual check: renders the real CoastalWorld from a live simulation.
// Scripts/render.sh <label>  ->  work/shots/<label>/{harbor,orbit,mars,verdant,cryo,forge,jetski}.png
import AppKit
import Metal
import SceneKit

@main struct RenderPreview {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "shots")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let size = CGSize(width: 900, height: 1500)
        // name, mode, stage, seconds of simulated running
        let shots: [(String, RunMode, Int, Double)] = [
            ("harbor", .odyssey, 0, 6), ("orbit", .odyssey, 1, 6), ("mars", .odyssey, 2, 6),
            ("verdant", .odyssey, 3, 6), ("cryo", .odyssey, 4, 6), ("forge", .odyssey, 5, 6), ("jetski", .jetSki, 0, 4),
        ]
        for (name, mode, stage, seconds) in shots {
            let world = CoastalWorld(assetsURL: resources)
            world.applyQuality(.ultra)
            world.resize(aspect: Double(size.width / size.height))
            var run = RunnerSimulation()
            run.start(seed: 7, mode: mode, startStage: stage)
            var time = 0.0
            while time < seconds {
                // Keep the camera on a clean, populated stretch rather than a crash screen.
                run.replaceTrackForTesting(run.entities.filter { $0.z > 18 }, generate: true)
                run.update(dt: 1.0 / 60.0); time += 1.0 / 60.0
                world.update(simulation: run, character: "milo", board: "tideline", time: time)
            }
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = world.scene
            renderer.pointOfView = world.camera
            renderer.isJitteringEnabled = true
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)  // warm-up: Metal pipeline, shader compilation
            let started = Date()
            var image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            for frame in 1...4 { image = renderer.snapshot(atTime: time + Double(frame) / 60, with: size, antialiasingMode: .multisampling4X) }
            let ms = Date().timeIntervalSince(started) * 1000 / 5  // mean warm offscreen 4x-MSAA snapshot including readback
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed: \(name)") }
            try png.write(to: out.appendingPathComponent("\(name).png"))
            // Exposure sanity: mean luminance (sRGB-encoded gamma-space) plus shares of
            // crushed (<0.02) and clipped (>0.98) pixels.
            var sum = 0.0, crushed = 0, clipped = 0, samples = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                    sum += l; samples += 1
                    if l < 0.02 { crushed += 1 }
                    if l > 0.98 { clipped += 1 }
                }
            }
            let pct = { (n: Int) in String(format: "%.1f%%", Double(n) * 100 / Double(max(1, samples))) }
            print(name, String(format: "mean=%.3f", sum / Double(max(1, samples))), "crushed=\(pct(crushed))", "clipped=\(pct(clipped))", String(format: "ms=%.1f", ms))
        }
    }
}
