// FX and camera shots: Scripts/fx.sh <label>  ->  work/shots/<label>/*.png, each with its live particle count.
// Every sim frame is also rendered (small, untimed) so particle systems simulate between events, as they do in the app.
import AppKit
import Metal
import SceneKit

@main struct FXPreview {
    static let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")

    /// Live particles the attached emitters sustain: looping systems rate × life, plus each attached burst's size.
    static func particles(_ scene: SCNScene) -> Double {
        var total = 0.0
        scene.rootNode.enumerateHierarchy { node, _ in
            for s in node.particleSystems ?? [] { total += Double(s.birthRate) * Double(s.loops ? s.particleLifeSpan : s.emissionDuration) }
        }
        return total
    }

    struct Shot {
        let world: CoastalWorld, renderer: SCNRenderer, size: CGSize
        var run = RunnerSimulation(), time = 0.0
        init(_ mode: RunMode, stage: Int, size: CGSize = CGSize(width: 900, height: 1500), reducedMotion: Bool = false) {
            world = CoastalWorld(assetsURL: FXPreview.resources)
            world.applyQuality(.ultra)
            world.resize(aspect: Double(size.width / size.height))
            world.reducedMotion = reducedMotion
            renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = world.scene
            renderer.pointOfView = world.camera
            self.size = size
            run.start(seed: 7, mode: mode, startStage: stage)
        }
        /// Steps the sim at 60 fps. `track` replaces the entities each frame (default: keep the 18 m ahead of the runner clear).
        mutating func step(_ frames: Int, track: ((RunnerSimulation) -> [TrackEntity])? = nil) {
            for _ in 0..<frames {
                run.replaceTrackForTesting(track?(run) ?? run.entities.filter { $0.z > 18 }, generate: track == nil)
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                world.update(simulation: run, character: "milo", board: "tideline", time: time)
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 90, height: 150), antialiasingMode: .none)
            }
        }
        func shoot(_ name: String, into out: URL) throws {
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed: \(name)") }
            try png.write(to: out.appendingPathComponent(name + ".png"))
            print(name, String(format: "particles=%.0f speed=%.1f fov=%.1f", FXPreview.particles(world.scene), run.speed, Double(world.camera.camera!.fieldOfView)))
        }
    }

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "work/shots/fx")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Top speed: Forge cruise (42 m/s), widest field of view (and speed lines from Task 4); then Reduced Motion.
        var fast = Shot(.odyssey, stage: 5)
        fast.step(240)
        try fast.shoot("top-speed", into: out)
        var calm = Shot(.odyssey, stage: 5, reducedMotion: true)
        calm.step(240)
        try calm.shoot("top-speed-reduced-motion", into: out)
        // Lane-change lean and lag, portrait and landscape, 6 frames into a move right on Mars.
        for (name, size) in [("lane-lean", CGSize(width: 900, height: 1500)), ("lane-lean-wide", CGSize(width: 1600, height: 900))] {
            var lean = Shot(.odyssey, stage: 2, size: size)
            lean.step(150)
            lean.run.act(.right)
            lean.step(6)
            try lean.shoot(name, into: out)
        }
        // Ambient particles per world, 3 s in.
        for (index, name) in ["harbor", "orbit", "mars", "verdant", "cryo", "forge"].enumerated() {
            var shot = Shot(.odyssey, stage: index)
            shot.step(180)
            try shot.shoot("ambient-" + name, into: out)
        }
        // Footsteps on Mars: 3 frames after a foot's dust opens.
        var steps = Shot(.odyssey, stage: 2)
        steps.step(150)
        while steps.world.footDust.allSatisfy({ ($0.particleSystems?.first?.birthRate ?? 0) == 0 }) { steps.step(1) }
        steps.step(3)
        try steps.shoot("footstep", into: out)
        // Landing burst, 6 frames after touchdown in the harbor.
        var land = Shot(.endless, stage: 0)
        land.step(120)
        land.run.act(.jump)
        land.step(5)
        while land.run.height > 0 { land.step(1) }
        land.step(6)
        try land.shoot("landing", into: out)
        // Pickup sparkle: a coin placed in the runner's lane, shot 4 frames after it is collected.
        var pickup = Shot(.endless, stage: 0)
        pickup.step(120)
        let coins = pickup.run.coins
        var placed = false
        while pickup.run.coins == coins {
            pickup.step(1) { run in
                defer { placed = true }
                return placed ? run.entities : [TrackEntity(id: 9_000, kind: .coin, lane: run.lane, z: 8, y: 0.9, length: 0.6)]
            }
        }
        pickup.step(4) { $0.entities }
        try pickup.shoot("sparkle", into: out)
        print("wrote", out.path)
    }
}
