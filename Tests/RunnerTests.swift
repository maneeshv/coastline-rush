import Foundation
import SceneKit

/// Runner rig: the contracts other code relies on, bind-pose proportions, node and draw budgets, the clothing tint,
/// and the pose-curve math (keys, continuity, symmetry, blends, follow-through springs).
@main struct RunnerTests {
    static func field<T>(_ world: CoastalWorld, _ label: String) -> T {
        Mirror(reflecting: world).children.first { $0.label == label }!.value as! T
    }

    static func near(_ a: RunnerPose.Limbs, _ b: RunnerPose.Limbs) -> Bool {
        [a.thigh - b.thigh, a.shin - b.shin, a.foot - b.foot, a.arm - b.arm, a.forearm - b.forearm].allSatisfy { abs($0) < 1e-9 }
    }

    /// Exact vertices of visible geometry under `root`, in `space` coordinates, skipping the `except` subtree.
    /// Parametric primitives (SCNBox, SCNCapsule…) fall back to their bounding-box corners.
    static func points(under root: SCNNode, in space: SCNNode, except: SCNNode? = nil) -> [SIMD3<Double>] {
        var out: [SIMD3<Double>] = []
        func visit(_ node: SCNNode) {
            guard !node.isHidden, node !== except else { return }
            if let g = node.geometry {
                var local: [SCNVector3] = []
                if type(of: g) == SCNGeometry.self, let s = g.sources(for: .vertex).first {
                    s.data.withUnsafeBytes { raw in
                        for i in 0..<s.vectorCount {
                            let base = s.dataOffset + i * s.dataStride
                            func c(_ k: Int) -> Double {
                                s.bytesPerComponent == 4 ? Double(raw.loadUnaligned(fromByteOffset: base + 4 * k, as: Float.self))
                                                         : raw.loadUnaligned(fromByteOffset: base + 8 * k, as: Double.self)
                            }
                            local.append(SCNVector3(c(0), c(1), c(2)))
                        }
                    }
                } else {
                    let (a, b) = g.boundingBox
                    for k in 0..<8 { local.append(SCNVector3(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z)) }
                }
                for p in local {
                    let w = space.convertPosition(p, from: node)
                    out.append(SIMD3(Double(w.x), Double(w.y), Double(w.z)))
                }
            }
            node.childNodes.forEach(visit)
        }
        visit(root)
        return out
    }

    /// Geometry elements that render (one draw each), skipping hidden subtrees.
    static func visibleElements(_ root: SCNNode) -> Int {
        guard !root.isHidden else { return 0 }
        return (root.geometry?.elements.count ?? 0) + root.childNodes.reduce(0) { $0 + visibleElements($1) }
    }

    static func main() {
        let resources = URL(fileURLWithPath: "Resources")
        // Contracts: stored properties that Mirror-based tests and audits read, and node names looked up by string.
        let world = CoastalWorld(assetsURL: resources)
        let labels = Set(Mirror(reflecting: world).children.compactMap(\.label))
        for label in ["player", "body", "headRig", "shins", "forearms", "feet", "clothing", "boardNode", "jetpackNode", "abilityAura", "ski", "scarf"] {
            precondition(labels.contains(label), "stored property `\(label)` was renamed or removed")
        }
        for label in ["shins", "forearms", "feet"] {
            let nodes: [SCNNode] = field(world, label)
            precondition(nodes.count == 2, "`\(label)` must hold one node per side (\(nodes.count))")
        }
        let player: SCNNode = field(world, "player")
        for name in ["leftLeg", "rightLeg", "leftArm", "rightArm", "jetSki", "artifactAura", "deck"] {
            precondition(player.childNode(withName: name, recursively: true) != nil, "node `\(name)` missing under player")
        }
        world.updateGhost(sample: GhostSample(time: 0, distance: 5, stageIndex: 0, stageDistance: 5, x: 0, y: 0, roll: false))
        precondition(world.scene.rootNode.childNode(withName: "personalGhost", recursively: false) != nil, "ghost node `personalGhost` missing")

        // Pose curves: through every key, no velocity jump at a key, periodic, no steps, left/right half a stride apart.
        let curves = [RunnerPose.thighKeys, RunnerPose.shinKeys, RunnerPose.footKeys, RunnerPose.armKeys, RunnerPose.forearmKeys,
                      RunnerPose.swayKeys, RunnerPose.yawKeys, RunnerPose.rollKeys, RunnerPose.bobKeys, RunnerPose.leanKeys]
        for (c, keys) in curves.enumerated() {
            precondition(keys.allSatisfy { abs($0) <= 2.0 }, "curve \(c) has a key outside ±2 (spiked key?)")
            let f = { (p: Double) in RunnerPose.sample(keys, phase: p) }
            let spacing = 2 * Double.pi / Double(keys.count)
            for k in keys.indices {
                let p = Double(k) * spacing
                precondition(abs(f(p) - keys[k]) < 1e-9, "curve \(c) misses key \(k)")
                let h = 1e-5, before = (f(p) - f(p - h)) / h, after = (f(p + h) - f(p)) / h
                precondition(abs(before - after) < 1e-3, "curve \(c) velocity jumps at key \(k) (\(before) vs \(after))")
            }
            var p = -2 * Double.pi
            while p < 4 * Double.pi {
                precondition(abs(f(p) - f(p + 2 * .pi)) < 1e-9, "curve \(c) is not periodic at \(p)")
                precondition(abs(f(p + 0.001) - f(p)) < 0.0025, "curve \(c) steps at \(p)")
                precondition(abs(f(p)) <= 2.0, "curve \(c) leaves ±2 at \(p)")
                p += 0.001
            }
        }
        for step in 0..<63 {
            let p = Double(step) * 0.1
            let now = RunnerPose.limbs(phase: p), half = RunnerPose.limbs(phase: p + .pi)
            precondition(near(now.left, half.right) && near(now.right, half.left), "left and right must be half a stride (π) apart at \(p)")
            let torso = RunnerPose.torso(phase: p), next = RunnerPose.torso(phase: p + .pi)
            precondition(abs(torso.bob - next.bob) < 1e-9 && abs(torso.lean - next.lean) < 1e-9, "bob and lean repeat every step (period π)")
        }
        for k in [0, 3, 4, 7] {
            precondition(RunnerPose.armKeys[k] * RunnerPose.thighKeys[k] < 0, "arm must counter-swing its leg at key \(k)")
        }
        let target = RunnerPose.Limbs(thigh: 1, shin: -1, foot: 1, arm: 1, forearm: 1)
        precondition(near(RunnerPose.mix(RunnerPose.rest, target, 0), RunnerPose.rest) && near(RunnerPose.mix(RunnerPose.rest, target, 1), target), "mix must hit its endpoints")
        // Follow-through springs (pack 160/14, scarf 60/7) settle within 1.5 s without wild overshoot.
        for (stiffness, damping) in [(160.0, 14.0), (60.0, 7.0)] {
            var s = RunnerPose.Spring(), peak = 0.0
            for _ in 0..<90 { s = RunnerPose.step(s, target: 1, dt: 1.0 / 60, stiffness: stiffness, damping: damping); peak = max(peak, s.value) }
            precondition(abs(s.value - 1) < 0.02 && peak < 1.3, "spring \(stiffness)/\(damping) must settle (value \(s.value), peak \(peak))")
        }
        // Proportions in the bind pose (a fresh world, before any update): about 7 heads, hip at half height.
        let rig = CoastalWorld(assetsURL: resources)
        let rigPlayer: SCNNode = field(rig, "player"), rigHead: SCNNode = field(rig, "headRig"), rigBody: SCNNode = field(rig, "body")
        let all = points(under: rigPlayer, in: rigPlayer)
        let floor = all.map(\.y).min()!, height = all.map(\.y).max()! - floor
        precondition((2.40...2.65).contains(height), "runner height \(height) m outside 2.40–2.65")
        let hip = Double(rigPlayer.childNode(withName: "leftLeg", recursively: true)!.convertPosition(SCNVector3Zero, to: rigPlayer).y) - floor
        precondition((0.46...0.54).contains(hip / height), "hip/height \(hip / height) outside 0.46–0.54")
        let headYs = points(under: rigHead, in: rigPlayer).map(\.y)
        let headRatio = (headYs.max()! - headYs.min()!) / height
        precondition((0.12...0.16).contains(headRatio), "head/height \(headRatio) outside 0.12–0.16")
        // Budget: at most 100 geometry nodes (old rig 151); visible draws, and so the ghost's, at most the old 119.
        var geometryNodes = 0
        rigPlayer.enumerateHierarchy { node, _ in if node.geometry != nil { geometryNodes += 1 } }
        precondition(geometryNodes <= 100, "runner has \(geometryNodes) geometry nodes (budget 100)")
        precondition(visibleElements(rigPlayer) <= 119, "runner draws \(visibleElements(rigPlayer)) elements (budget 119)")
        print(String(format: "runner height %.2f hip %.3f head %.3f geometry %d elements %d", height, hip / height, headRatio, geometryNodes, visibleElements(rigPlayer)))
        // The character tint recolours the shirt and sleeve shells.
        let clothing: [SCNMaterial] = field(rig, "clothing")
        var used = Set<ObjectIdentifier>()
        rigPlayer.enumerateHierarchy { node, _ in node.geometry?.materials.forEach { used.insert(ObjectIdentifier($0)) } }
        precondition(clothing.count >= 2 && clothing.allSatisfy { used.contains(ObjectIdentifier($0)) }, "every clothing material must be on a shell")
        for node in [rigBody, rigPlayer.childNode(withName: "leftArm", recursively: true)!, rigPlayer.childNode(withName: "rightArm", recursively: true)!] {
            precondition(node.geometry?.materials.contains { m in clothing.contains { $0 === m } } == true, "\(node.name ?? "torso") must wear a clothing material")
        }
        rig.update(simulation: RunnerSimulation(), character: "sana", board: "tideline", time: 0)
        for m in clothing {
            let c = (m.diffuse.contents as! CoastColor).usingColorSpace(.sRGB)!
            precondition(abs(c.redComponent - 0xEF / 255.0) < 0.01 && abs(c.greenComponent - 0xB8 / 255.0) < 0.01 && abs(c.blueComponent - 0x4D / 255.0) < 0.01,
                         "sana tint not applied to every clothing material")
        }
        // Run cycle on the live rig: sway on `body` only, torso twist, a level head, a full stride, and follow-through.
        let runner = CoastalWorld(assetsURL: resources)
        let runPlayer: SCNNode = field(runner, "player"), runBody: SCNNode = field(runner, "body")
        let runHead: SCNNode = field(runner, "headRig"), runPack: SCNNode = field(runner, "pack")
        let runLeg = runPlayer.childNode(withName: "leftLeg", recursively: true)!
        var sim = RunnerSimulation()
        sim.start(seed: 3, boards: 0, mode: .odyssey, startStage: 0)
        var clock = 0.0, sway = 0.0, twist = 0.0, headYaw = 0.0, headPitch = 0.0, packSwing = 0.0
        var thigh = (low: Double.infinity, high: -Double.infinity)
        func tick(_ frames: Int, measure: Bool) {
            for _ in 0..<frames {
                sim.replaceTrackForTesting([], generate: false)
                sim.update(dt: 1.0 / 60); clock += 1.0 / 60
                runner.update(simulation: sim, character: "milo", board: "tideline", time: clock)
                let route = sim.routeTransform(atAheadDistance: 0)
                precondition(abs(Double(runPlayer.position.x) - (sim.lateral * 2.6 + route.lateralOffset)) < 0.001,
                             "player.position.x must follow the simulation exactly; sway belongs on body")
                packSwing = max(packSwing, abs(Double(runPack.eulerAngles.x)))
                guard measure else { continue }
                sway = max(sway, abs(Double(runBody.position.x)))
                twist = max(twist, abs(Double(runBody.eulerAngles.y)))
                let forward = runHead.convertVector(SCNVector3(0, 0, -1), to: runPlayer)
                headYaw = max(headYaw, abs(atan2(Double(forward.x), -Double(forward.z))))
                headPitch = max(headPitch, abs(atan2(Double(forward.y), -Double(forward.z))))
                let x = Double(runLeg.eulerAngles.x)
                thigh = (min(thigh.low, x), max(thigh.high, x))
            }
        }
        tick(60, measure: false)
        tick(120, measure: true)
        precondition(sway > 0.015, "no hip sway on body (\(sway) m)")
        precondition(twist > 0.05, "no torso twist (\(twist) rad)")
        precondition(headYaw < 0.03 && headPitch < 0.05, "head not stabilised (yaw \(headYaw), pitch \(headPitch))")
        precondition(thigh.low < -0.4 && thigh.high > 0.6, "stride too small (thigh \(thigh))")
        packSwing = 0
        sim.act(.jump)
        tick(60, measure: false)
        precondition(packSwing > 0.02, "pack shows no follow-through on a jump (\(packSwing))")
        print("RunnerTests passed")
    }
}
