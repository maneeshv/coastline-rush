// Runner close-ups: Scripts/runner.sh <label>  ->  work/shots/<label>/*.png, plus the runner's node, geometry and material counts.
import AppKit
import Metal
import SceneKit

@main struct RunnerPreview {
    static let size = CGSize(width: 900, height: 1200)
    static let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    /// A fresh world per scenario, with a 3/4-front close-up camera.
    static func makeWorld() -> (world: CoastalWorld, player: SCNNode, close: SCNNode) {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        world.applyQuality(.ultra)
        world.resize(aspect: Double(size.width / size.height))
        let player = Mirror(reflecting: world).children.first { $0.label == "player" }!.value as! SCNNode
        let close = SCNNode(); close.camera = SCNCamera(); close.camera!.fieldOfView = 30; close.camera!.wantsHDR = true
        world.scene.rootNode.addChildNode(close)
        return (world, player, close)
    }

    static func counts(_ player: SCNNode) -> String {
        var nodes = 0, geometry = 0, elements = 0
        var materials = Set<ObjectIdentifier>()
        player.enumerateHierarchy { node, _ in
            nodes += 1
            guard let g = node.geometry else { return }
            geometry += 1
            var shown = true, n: SCNNode? = node
            while let m = n { if m.isHidden { shown = false }; n = m.parent }
            if shown { elements += g.elements.count }
            g.materials.forEach { materials.insert(ObjectIdentifier($0)) }
        }
        return "runner nodes=\(nodes) geometry=\(geometry) visibleElements=\(elements) materials=\(materials.count)"
    }

    /// World-space box around the visible geometry under `node`; hidden subtrees (board, jet ski, jetpack, aura) are skipped.
    static func bounds(_ node: SCNNode) -> (low: SIMD3<Double>, high: SIMD3<Double>) {
        var low = SIMD3<Double>(repeating: .infinity), high = -low
        func visit(_ n: SCNNode) {
            guard !n.isHidden else { return }
            if let g = n.geometry {
                let (a, b) = g.boundingBox
                for k in 0..<8 {
                    let w = n.convertPosition(SCNVector3(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z), to: nil)
                    let p = SIMD3(Double(w.x), Double(w.y), Double(w.z))
                    low = simd_min(low, p); high = simd_max(high, p)
                }
            }
            n.childNodes.forEach(visit)
        }
        visit(node)
        return (low, high)
    }

    /// 3/4 close-up (front-right by default) pulled back until the runner's visible box fills about 85% of the frame
    /// (whatever the pose: standing, rolling, on the jet ski), or the live game camera.
    static func shoot(_ s: (world: CoastalWorld, player: SCNNode, close: SCNNode), _ name: String, time: Double, out: URL,
                      from side: SIMD3<Double> = SIMD3(3.2, 0.85, -3.6), gameplay: Bool = false) throws {
        let box = bounds(s.player)
        let centre = (box.low + box.high) / 2, half = (box.high - box.low) / 2
        let view = simd_normalize(side)
        let tanV = tan(Double.pi / 12), tanH = tanV * Double(size.width / size.height)   // 30° vertical field of view
        let distance = 1.15 * max(half.y / tanV, (half.x * 0.75 + half.z * 0.67) / tanH)
        let eye = centre + view * distance
        s.close.position = SCNVector3(eye.x, eye.y, eye.z)
        s.close.look(at: SCNVector3(centre.x, centre.y, centre.z))
        renderer.scene = s.world.scene
        renderer.pointOfView = gameplay ? s.world.camera : s.close
        let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed: \(name)") }
        try png.write(to: out.appendingPathComponent(name + ".png"))
    }

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "work/shots/runner")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // Land run: game camera, gait sweep, jump apex, landing, roll, each character, board, accessories.
        let land = makeWorld()
        print(counts(land.player))
        var run = RunnerSimulation()
        run.start(seed: 3, boards: 1, mode: .odyssey, startStage: 0)
        var time = 0.0
        func step(_ frames: Int, character: String = "milo") {
            for _ in 0..<frames {
                run.replaceTrackForTesting([], generate: false)
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                land.world.update(simulation: run, character: character, board: "tideline", time: time)
            }
        }
        step(180)
        try shoot(land, "gameplay", time: time, out: out, gameplay: true)
        for i in 0..<4 { step(4); try shoot(land, "run-\(i)", time: time, out: out) }   // gait sweep, 1/15 s apart
        run.act(.jump)
        var last = -1.0
        while run.height > last { last = run.height; step(1) }
        try shoot(land, "jump-apex", time: time, out: out)
        while run.height > 0 { step(1) }
        step(9); try shoot(land, "landing", time: time, out: out)                        // ~0.15 s into the squash
        step(40); run.act(.roll); step(14); try shoot(land, "roll", time: time, out: out)
        step(60); try shoot(land, "milo", time: time, out: out)
        step(60, character: "sana"); try shoot(land, "sana", time: time, out: out)
        step(60, character: "rio"); try shoot(land, "rio", time: time, out: out)
        run.act(.board); step(30); try shoot(land, "board", time: time, out: out)
        // Placement check only: jetpack and aura shown together on the current pose.
        for label in ["jetpackNode", "abilityAura"] {
            (Mirror(reflecting: land.world).children.first { $0.label == label }!.value as! SCNNode).isHidden = false
        }
        try shoot(land, "accessories", time: time, out: out)

        // Menu idle: the real menu camera, then a close-up of the idle pose.
        let menu = makeWorld()
        let idle = RunnerSimulation()
        for frame in 1...90 { menu.world.update(simulation: idle, character: "milo", board: "tideline", time: Double(frame) / 60) }
        try shoot(menu, "menu", time: 1.5, out: out, gameplay: true)
        try shoot(menu, "menu-pose", time: 1.5, out: out, from: SIMD3(-3.2, 0.85, -3.6))   // front-left: a bus parks on the right

        // Jet ski: the rider on the craft.
        let water = makeWorld()
        var ride = RunnerSimulation()
        ride.start(seed: 3, boards: 0, mode: .jetSki)
        var rideTime = 0.0
        for _ in 0..<120 {
            ride.replaceTrackForTesting([], generate: false)
            ride.update(dt: 1.0 / 60); rideTime += 1.0 / 60
            water.world.update(simulation: ride, character: "milo", board: "tideline", time: rideTime)
        }
        try shoot(water, "jetski", time: rideTime, out: out)
        print("wrote", out.path)
    }
}
