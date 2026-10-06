import AppKit
import Metal
import SceneKit

/// Surface detail must bind on lit materials, add visible breakup, and stay fixed to moving geometry.
@main struct MaterialTests {
    static func luminanceStats(_ rep: NSBitmapImageRep) -> (mean: Double, stddev: Double) {
        var sum = 0.0, squares = 0.0, n = 0.0
        for y in stride(from: 16, to: rep.pixelsHigh - 16, by: 2) { for x in stride(from: 16, to: rep.pixelsWide - 16, by: 2) {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
            sum += l; squares += l * l; n += 1
        } }
        let mean = sum / n
        return (mean, sqrt(max(0, squares / n - mean * mean)))
    }

    /// A 6×6 m quad filling the view, lit only by ambient light; node and camera shift together by `offset`.
    static func render(_ material: SCNMaterial, offset: Double, roll: Double = 0, renderer: SCNRenderer) -> NSBitmapImageRep {
        let scene = SCNScene()
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 1000
        scene.rootNode.addChildNode(ambient)
        let plane = SCNPlane(width: 6, height: 6); plane.firstMaterial = material
        let node = SCNNode(geometry: plane); node.position = SCNVector3(CGFloat(offset), 0, 0)
        scene.rootNode.addChildNode(node)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(CGFloat(offset), 0, 4); camera.eulerAngles.z = CGFloat(roll)
        scene.rootNode.addChildNode(camera)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 128, height: 128), antialiasingMode: .none)
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
    }

    static func main() {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        let lit = world.material("8C5743", unique: true)
        let glow = world.material("FFB369", emissive: true, unique: true)
        precondition(lit.shaderModifiers?[.surface]?.contains("detailMap") == true, "lit materials must carry surface detail")
        precondition(lit.value(forKey: "detailMap") is SCNMaterialProperty, "detail map must be bound")
        precondition(glow.shaderModifiers?[.surface] == nil, "emissive materials must stay clean")

        // Every section starts a fresh model space: whole detail periods per section, at both scales, or the pattern seams.
        for length in [24.0, 26.0, 16.0] { for k in [1.0, CoastalWorld.fineDetailMultiplier] {
            let periods = length * CoastalWorld.defaultDetailScale * k
            precondition(abs(periods - periods.rounded()) < 1e-9, "detail pattern must tile whole periods per section (\(length) m x\(k) = \(periods))")
        } }
        // Runner, jet ski and pickups stay clean; the lit shared "D9E1E5" (also on the runner) keeps its detail.
        let player = Mirror(reflecting: world).children.first { $0.label == "player" }!.value as! SCNNode
        var playerMaterials = 0
        player.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] {
                playerMaterials += 1
                precondition(m.shaderModifiers?[.surface] == nil, "player hierarchy material carries surface detail (\(node.name ?? "?"))")
            }
        }
        precondition(playerMaterials > 10, "player hierarchy not found (\(playerMaterials) materials)")
        precondition(world.material("D9E1E5").shaderModifiers?[.surface]?.contains("detailMap") == true, "shared lit material must keep surface detail")
        world.withoutSurfaceDetail { precondition(world.material("D9E1E5").shaderModifiers?[.surface] == nil, "flat variant must be clean") }
        precondition(world.surfaceDetailEnabled, "withoutSurfaceDetail must restore the flag")

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        let plain = SCNMaterial(); plain.lightingModel = .physicallyBased; plain.diffuse.contents = lit.diffuse.contents
        let flat = luminanceStats(render(plain, offset: 0, renderer: renderer))
        let detailed = render(lit, offset: 0, renderer: renderer)
        let stats = luminanceStats(detailed)
        precondition(flat.stddev < 0.01, "control quad should be flat (\(flat.stddev))")
        precondition(stats.stddev > 0.02, "surface detail adds no visible breakup (\(stats.stddev))")
        precondition(abs(stats.mean - flat.mean) < 0.08, "surface detail shifts brightness too much (\(stats.mean) vs \(flat.mean))")

        // Node and camera moved together: a model-space pattern renders identically (no swimming).
        let moved = render(lit, offset: 3.7, renderer: renderer)
        var diff = 0.0, n = 0.0
        for y in stride(from: 16, to: 112, by: 2) { for x in stride(from: 16, to: 112, by: 2) {
            diff += abs(detailed.colorAt(x: x, y: y)!.brightnessComponent - moved.colorAt(x: x, y: y)!.brightnessComponent); n += 1
        } }
        precondition(diff / n < 0.004, "surface detail swims with world position (\(diff / n))")

        // Camera rolled +90° about its view axis turns the image clockwise, so rolled(x, y) == detailed(y, 127 - x).
        // A shader that used view-space position (instead of model space) would change under the roll.
        let rolled = render(lit, offset: 0, roll: .pi / 2, renderer: renderer)
        var rollDiff = 0.0, rollN = 0.0
        for y in stride(from: 16, to: 112, by: 2) { for x in stride(from: 16, to: 112, by: 2) {
            rollDiff += abs(rolled.colorAt(x: x, y: y)!.brightnessComponent - detailed.colorAt(x: y, y: 127 - x)!.brightnessComponent); rollN += 1
        } }
        precondition(rollDiff / rollN < 0.01, "surface detail depends on view orientation (\(rollDiff / rollN))")
        // Deck textures: 1024² off-world, 512² harbor asphalt/paving, found on the actual route decks.
        func deckWidths(_ world: CoastalWorld) -> Set<Int> {
            var widths = Set<Int>()
            // Flattened deck geometry only reports its materials once SceneKit has rendered it.
            renderer.scene = world.scene
            _ = renderer.snapshot(atTime: 0, with: CGSize(width: 32, height: 32), antialiasingMode: .none)
            world.scene.rootNode.enumerateHierarchy { node, _ in
                guard node.name == "routeDeck" else { return }
                node.enumerateHierarchy { child, _ in
                    for m in child.geometry?.materials ?? [] {
                        if let contents = m.diffuse.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
                            let image = contents as! CGImage
                            widths.insert(image.width)
                            if image.width == 1024 {
                                precondition(m.diffuse.mipFilter == .linear && m.diffuse.maxAnisotropy >= 4, "deck textures need trilinear + anisotropic filtering")
                            }
                        }
                    }
                }
            }
            return widths
        }
        precondition(deckWidths(world).contains(512), "harbor asphalt/paving must be 512² (found \(deckWidths(world)))")
        for index in 1..<WorldStage.allCases.count {
            var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: index)
            world.update(simulation: run, character: "milo", board: "tideline", time: 2)
            precondition(deckWidths(world).contains(1024), "\(WorldStage.allCases[index]) deck must be 1024² (found \(deckWidths(world)))")
        }
        print(String(format: "MaterialTests passed (breakup %.3f, swim %.4f, roll %.4f)", stats.stddev, diff / n, rollDiff / rollN))
    }
}
