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

    /// A live world driven by a running simulation, one frame per `step`.
    final class Drive {
        let world: CoastalWorld
        var sim = RunnerSimulation()
        var clock = 0.0
        init(_ resources: URL, reduced: Bool) {
            world = CoastalWorld(assetsURL: resources)
            world.reducedMotion = reduced
            sim.start(seed: 3, boards: 0, mode: .odyssey, startStage: 0)
        }
        func step(_ dt: Double = 1.0 / 60) {
            sim.replaceTrackForTesting([], generate: false)
            sim.update(dt: dt); clock += dt
            world.update(simulation: sim, character: "milo", board: "tideline", time: clock)
        }
        var player: SCNNode { field(world, "player") }
        var body: SCNNode { field(world, "body") }
        var pack: SCNNode { field(world, "pack") }
        var scarf: SCNNode { field(world, "scarf") }
        var rollSpin: Double { field(world, "rollSpin") }
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
        packSwing = 0
        tick(120, measure: true)
        let runPackPeak = packSwing
        precondition(sway > 0.015, "no hip sway on body (\(sway) m)")
        precondition(twist > 0.05, "no torso twist (\(twist) rad)")
        precondition(headYaw < 0.03 && headPitch < 0.05, "head not stabilised (yaw \(headYaw), pitch \(headPitch))")
        precondition(thigh.low < -0.4 && thigh.high > 0.6, "stride too small (thigh \(thigh))")
        packSwing = 0
        sim.act(.jump)
        tick(60, measure: false)
        precondition(packSwing > max(0.02, 2 * runPackPeak), "pack follow-through on a jump (\(packSwing)) must clearly exceed the run bob alone (\(runPackPeak))")
        // Squash and stretch keep volume; landing squashes, takeoff stretches, and both start and end at 1.
        var sy = 0.7
        while sy <= 1.3 {
            let s = RunnerPose.volumeScale(sy)
            precondition(abs(s.x * s.y * s.z - 1) < 1e-9, "squash must keep volume at \(sy)")
            sy += 0.05
        }
        precondition(RunnerPose.squash(landingAge: 0.16, takeoffAge: 9) < 0.9, "landing must squash")
        precondition(RunnerPose.squash(landingAge: 9, takeoffAge: 0.06) > 1.05, "takeoff must stretch")
        for (landing, takeoff) in [(0.0, 9.0), (0.32, 9.0), (9.0, 0.0), (9.0, 0.12), (9.0, 9.0)] {
            precondition(abs(RunnerPose.squash(landingAge: landing, takeoffAge: takeoff) - 1) < 1e-9, "squash must start and end at 1 (\(landing), \(takeoff))")
        }
        // Spin: continuous while rolling; afterwards it finishes the turn and rests upright at 0.
        var spin = 0.0
        for _ in 0..<24 {
            let next = RunnerPose.advanceSpin(spin, rolling: true, dt: 1.0 / 60)
            let turned = (next - spin + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            precondition(turned <= RunnerPose.spinRate / 60 + 1e-9, "spin must advance continuously")
            spin = next
        }
        var settled = -1
        for frame in 0..<60 {
            let next = RunnerPose.advanceSpin(spin, rolling: false, dt: 1.0 / 60)
            precondition(next == 0 || next > spin, "after a roll the spin finishes its turn forward, never rewinds")
            spin = next
            if spin == 0 && settled < 0 { settled = frame }
        }
        precondition(settled >= 0 && settled <= 48 && spin == 0, "spin must come to rest upright within one roll time")
        // Live roll: a compact spinning ball resting on the deck, under the 1.30 m roll ceiling.
        let roller = CoastalWorld(assetsURL: resources)
        let rollPlayer: SCNNode = field(roller, "player")
        var rollRun = RunnerSimulation()
        rollRun.start(seed: 3, boards: 0, mode: .odyssey, startStage: 0)
        var rollClock = 0.0, checked = 0, low = Double.infinity, high = -Double.infinity, maxSpin = 0.0
        for frame in 0..<120 {
            if frame == 60 { rollRun.act(.roll) }
            rollRun.replaceTrackForTesting([], generate: false)
            rollRun.update(dt: 1.0 / 60); rollClock += 1.0 / 60
            roller.update(simulation: rollRun, character: "milo", board: "tideline", time: rollClock)
            let blend: Double = field(roller, "rollBlend"), spun: Double = field(roller, "rollSpin")
            maxSpin = max(maxSpin, spun)
            guard blend >= 0.95 else { continue }
            let ys = points(under: rollPlayer, in: rollPlayer).map(\.y)
            low = min(low, ys.min()!); high = max(high, ys.max()!); checked += 1
        }
        precondition(checked >= 20, "roll never reached full tuck (\(checked) frames)")
        precondition(low >= -0.05, "roll tuck sinks into the deck (lowest \(low))")
        precondition(high <= 1.30, "roll tuck too tall (highest \(high))")
        precondition(maxSpin > 2.5, "roll tuck does not spin (\(maxSpin))")
        print(String(format: "roll tuck: %d frames, y %.2f…%.2f, spin %.2f", checked, low, high, maxSpin))
        // Rise velocity feeding the springs is clamped: a hitch or a one-frame jump cannot overshoot them.
        precondition(RunnerPose.riseVelocity(from: 0, to: 1, dt: 0.05) == 8 && RunnerPose.riseVelocity(from: 1, to: 0, dt: 0.05) == -8, "rise velocity must clamp at ±8 m/s")
        precondition(RunnerPose.riseVelocity(from: 0, to: 0.05, dt: 0.05) == 1 && RunnerPose.riseVelocity(from: 0, to: 1, dt: 0) == 0, "rise velocity: plain ratio, and 0 at dt 0")
        // Springs at the worst frame step the world allows (dt 0.05, both gain sets) stay stable and bounded, in the pure math and live.
        for (stiffness, damping) in [(160.0, 14.0), (60.0, 7.0)] {
            var s = RunnerPose.Spring(), peak = 0.0
            for _ in 0..<80 { s = RunnerPose.step(s, target: 1, dt: 0.05, stiffness: stiffness, damping: damping); peak = max(peak, abs(s.value)) }
            precondition(abs(s.value - 1) < 0.02 && peak < 1.5, "spring \(stiffness)/\(damping) at dt 0.05 must settle (value \(s.value), peak \(peak))")
        }
        // A jump can cancel the roll at any moment, and land again: sweep the jump from 1 frame into the roll to 0.55 s and
        // assert nothing goes under the deck on any frame from the jump until well after the landing.
        var sweepLow = Double.infinity
        for offset in [1, 2, 3] + Array(12...33) {
            let d = Drive(resources, reduced: false)
            for frame in 0..<20 + offset + 150 {
                if frame == 20 { d.sim.act(.roll) }
                if frame == 20 + offset { d.sim.act(.jump) }
                d.step(1.0 / 60)
                guard frame > 20 + offset else { continue }
                sweepLow = min(sweepLow, points(under: d.player, in: d.world.scene.rootNode).map(\.y).min()!)
                precondition(sweepLow >= -0.07, "jump \(offset) frames into a roll sinks into the deck (\(sweepLow)) at frame \(frame)")
            }
        }
        print(String(format: "jump-cancel sweep: lowest vertex %.3f", sweepLow))
        // Foot plant: through a whole stride (48 phases) the stance boot never goes into the deck, and the plant stays modest.
        let planter = CoastalWorld(assetsURL: resources)
        let plantBoots: [SCNNode] = field(planter, "feet"), plantBody: SCNNode = field(planter, "body"), plantPlayer: SCNNode = field(planter, "player")
        var bootLow = Double.infinity, bobLow = Double.infinity, bobHigh = -Double.infinity
        for k in 0..<48 {
            planter.poseRunner(gait: Double(k) / 48 * 2 * .pi, amount: 1, waterMode: false, surfing: false, flying: false, landingAge: 9,
                               takeoffAge: 9, speed: 17, height: 0, time: 1, dt: 1.0 / 60)
            for boot in plantBoots { bootLow = min(bootLow, points(under: boot, in: plantPlayer).map(\.y).min()!) }
            bobLow = min(bobLow, Double(plantBody.position.y)); bobHigh = max(bobHigh, Double(plantBody.position.y))
        }
        precondition(bootLow >= -0.01, "stance boot sinks into the deck (\(bootLow) m)")
        precondition(bobHigh - bobLow > 0.03 && bobHigh < 0.2, "run bounce lost or too large (\(bobLow)…\(bobHigh))")
        print(String(format: "foot plant: lowest boot vertex %.3f over a stride, body y %.3f…%.3f", bootLow, bobLow, bobHigh))
        // Roll finishes cleanly at any frame step, and when a jump cancels it: nothing dips below the deck after the
        // roll ends, the pitch is back near upright within a few frames, and no spin is left over.
        var slowPeak = 0.0
        for (dt, cancel) in [(1.0 / 60, false), (1.0 / 30, false), (0.05, false), (1.0 / 60, true), (1.0 / 30, true), (0.05, true)] {
            let d = Drive(resources, reduced: false)
            var lastPitch = 0.0, maxStep = 0.0, rolled = false, ended = -1, low = Double.infinity, runLow = Double.infinity, pitchAfter = 0.0
            for frame in 0..<400 {
                if frame == 20 { d.sim.act(.roll) }
                if cancel && frame == 20 + Int(0.3 / dt) { d.sim.act(.jump) }
                d.step(dt)
                for node in [d.pack, d.scarf] {
                    let x = Double(node.eulerAngles.x)
                    precondition(x.isFinite && abs(x) < 1.2, "spring node unstable at dt \(dt) (\(x)) frame \(frame)")
                    slowPeak = max(slowPeak, abs(x))
                }
                var step = Double(d.body.eulerAngles.x) - lastPitch
                step -= (step / (2 * .pi)).rounded() * 2 * .pi
                lastPitch = Double(d.body.eulerAngles.x)
                if rolled { maxStep = max(maxStep, abs(step) / (dt * 60)) }
                if d.sim.isRolling { rolled = true }
                else if rolled && ended < 0 { ended = frame }
                guard ended >= 0 else { continue }
                let floor = points(under: d.player, in: d.world.scene.rootNode).map(\.y).min()!   // world space: the deck is y 0
                if Double(frame - ended) * dt < 0.5 { low = min(low, floor) } else { runLow = min(runLow, floor) }
                if frame - ended >= 10 { pitchAfter = max(pitchAfter, abs(Double(d.body.eulerAngles.x))) }
                precondition(frame - ended < 10 || d.rollSpin == 0, "spin left over \(frame - ended) frames after the roll (dt \(dt))")
            }
            precondition(maxStep < 0.55, "pitch pops \(maxStep) rad per 1/60 s after the roll (dt \(dt), cancel \(cancel))")
            precondition(rolled && ended >= 0, "roll never ran (dt \(dt), cancel \(cancel))")
            precondition(low >= -0.07 && runLow >= -0.07, "runner sinks into the deck after the roll (lowest \(low), running \(runLow), dt \(dt), cancel \(cancel))")
            precondition(pitchAfter < 0.25, "runner not upright after the roll (pitch \(pitchAfter), dt \(dt), cancel \(cancel))")
        }
        // Reduced Motion halves hip sway, twist and tilt, drops the bob, keeps the squash gentle and does not spin the roll.
        let calm = Drive(resources, reduced: true), full = Drive(resources, reduced: false)
        var calmSway = 0.0, calmTwist = 0.0, calmTilt = 0.0, calmLo = Double.infinity, calmHi = -Double.infinity, fullSway = 0.0, fullTwist = 0.0, fullTilt = 0.0
        for frame in 0..<240 {
            calm.step(); full.step()
            guard frame >= 60 else { continue }
            calmSway = max(calmSway, abs(Double(calm.body.position.x))); calmLo = min(calmLo, Double(calm.body.position.y)); calmHi = max(calmHi, Double(calm.body.position.y))
            calmTwist = max(calmTwist, abs(Double(calm.body.eulerAngles.y))); calmTilt = max(calmTilt, abs(Double(calm.body.eulerAngles.z)))
            fullSway = max(fullSway, abs(Double(full.body.position.x)))
            fullTwist = max(fullTwist, abs(Double(full.body.eulerAngles.y))); fullTilt = max(fullTilt, abs(Double(full.body.eulerAngles.z)))
        }
        precondition(calmHi - calmLo < 0.015, "Reduced Motion must not bounce (\(calmLo)…\(calmHi))")
        precondition(calmSway > 0.006 && abs(calmSway - fullSway / 2) < 0.002, "Reduced Motion sway must be half (\(calmSway) vs \(fullSway))")
        precondition(calmTwist > 0.025 && abs(calmTwist - fullTwist / 2) < 0.005, "Reduced Motion twist must be half (\(calmTwist) vs \(fullTwist))")
        precondition(calmTilt > 0.01 && calmTilt < fullTilt * 0.6, "Reduced Motion tilt must be half (\(calmTilt) vs \(fullTilt))")
        var calmSquash = 1.0, fullSquash = 1.0, fullStretch = 1.0, calmMaxSpin = 0.0, calmLow = Double.infinity, calmHigh = -Double.infinity
        for frame in 0..<160 {
            if frame == 0 { calm.sim.act(.jump); full.sim.act(.jump) }
            if frame == 90 { calm.sim.act(.roll); full.sim.act(.roll) }
            calm.step(); full.step()
            if frame < 80 {
                calmSquash = min(calmSquash, Double(calm.body.scale.y)); fullSquash = min(fullSquash, Double(full.body.scale.y))
                fullStretch = max(fullStretch, Double(full.body.scale.y))
            }
            calmMaxSpin = max(calmMaxSpin, calm.rollSpin)
            let blend: Double = field(calm.world, "rollBlend")
            if blend >= 0.95 {
                let ys = points(under: calm.player, in: calm.player).map(\.y)
                calmLow = min(calmLow, ys.min()!); calmHigh = max(calmHigh, ys.max()!)
            }
        }
        precondition(fullSquash < 0.9 && fullStretch > 1.05, "live landing must squash and takeoff stretch (\(fullSquash), \(fullStretch))")
        precondition(calmSquash > 0.915 && calmSquash < 0.99, "Reduced Motion squash must be half (\(calmSquash))")
        precondition(calmMaxSpin == 0, "Reduced Motion roll must not spin (\(calmMaxSpin))")
        precondition(calmLow >= -0.05 && calmHigh <= 1.30, "Reduced Motion roll leaves the roll bounds (\(calmLow)…\(calmHigh))")
        print(String(format: "reduced motion: sway %.3f/%.3f twist %.3f/%.3f squash %.2f/%.2f roll y %.2f…%.2f; roll finish at dt 60/30/20 fps, cancelled or not: ok, spring peak %.2f",
                     calmSway, fullSway, calmTwist, fullTwist, calmSquash, fullSquash, calmLow, calmHigh, slowPeak))
        // Jet ski: the rider crouches on the craft, feet on the footrests, hands at the bars.
        let rider = CoastalWorld(assetsURL: resources)
        let riderPlayer: SCNNode = field(rider, "player"), craft: SCNNode = field(rider, "ski")
        let riderForearms: [SCNNode] = field(rider, "forearms")
        var ride = RunnerSimulation()
        ride.start(seed: 3, boards: 0, mode: .jetSki)
        var rideClock = 0.0
        for _ in 0..<120 {
            ride.replaceTrackForTesting([], generate: false)
            ride.update(dt: 1.0 / 60); rideClock += 1.0 / 60
            rider.update(simulation: ride, character: "milo", board: "tideline", time: rideClock)
        }
        precondition(!craft.isHidden, "jet ski hidden in jet-ski mode")
        func onCraft(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> {
            let p = craft.convertPosition(SCNVector3(x, y, z), to: riderPlayer)
            return SIMD3(Double(p.x), Double(p.y), Double(p.z))
        }
        // Craft geometry (makeJetSki): footrest top y 0.285, seat top y 0.52 spanning z −0.10…1.25, handlebar at (y 1.07, z −0.58).
        let footrest = onCraft(0, 0.285, 0).y, seat = onCraft(0, 0.52, 0).y
        let lowest = points(under: riderPlayer, in: riderPlayer, except: craft).map(\.y).min()!
        precondition(lowest >= footrest - 0.06, "rider sinks through the hull (lowest \(lowest), footrest \(footrest))")
        let seatHip = riderPlayer.childNode(withName: "leftLeg", recursively: true)!.convertPosition(SCNVector3Zero, to: riderPlayer)
        precondition(Double(seatHip.y) >= seat + 0.05 && Double(seatHip.y) <= seat + 0.55, "hips must ride over the seat (hip \(seatHip.y), seat \(seat))")
        precondition(Double(seatHip.z) >= onCraft(0, 0.52, -0.10).z && Double(seatHip.z) <= onCraft(0, 0.52, 1.25).z, "hips must be over the seat (z \(seatHip.z))")
        let bar = onCraft(0, 1.07, -0.58)
        for forearm in riderForearms {
            let hand = forearm.convertPosition(SCNVector3(0, -0.38, 0), to: riderPlayer)
            let reach = hypot(Double(hand.y) - bar.y, Double(hand.z) - bar.z)
            precondition(reach <= 0.25, "hand \(reach) m from the handlebar")
        }
        // The craft pitches under brake (+0.12) and boost (−0.08): the rider pitches with it, so the hands stay on the bar and the boots on the footrests.
        var neutralHands: [SIMD3<Double>] = []
        func rideFits(_ label: String) {
            func local(_ p: SCNVector3, from node: SCNNode) -> SIMD3<Double> {
                let q = craft.convertPosition(p, from: node)
                return SIMD3(Double(q.x), Double(q.y), Double(q.z))
            }
            let boots = points(under: riderPlayer, in: craft, except: craft).map(\.y).min()!
            precondition(boots >= 0.285 - 0.06, "\(label): boots sink through the footrest (\(boots))")
            let hands = riderForearms.map { local(SCNVector3(0, -0.38, 0), from: $0) }
            for hand in hands { precondition(hypot(hand.y - 1.07, hand.z + 0.58) <= 0.25, "\(label): hand \(hand) too far from the handlebar") }
            // Rigid with the craft: in craft space the hands sit where they did at neutral pitch, whichever way it tilts.
            if neutralHands.isEmpty { neutralHands = hands }
            for (hand, rest) in zip(hands, neutralHands) { precondition(simd_distance(hand, rest) < 0.05, "\(label): hand slid \(simd_distance(hand, rest)) m on the bar") }
        }
        rideFits("neutral")
        for (label, action, pitchSign) in [("brake", RunnerAction.roll, 1.0), ("boost", RunnerAction.board, -1.0)] {
            ride.act(action)
            for _ in 0..<20 {
                ride.replaceTrackForTesting([], generate: false)
                ride.update(dt: 1.0 / 60); rideClock += 1.0 / 60
                rider.update(simulation: ride, character: "milo", board: "tideline", time: rideClock)
            }
            precondition(Double(craft.eulerAngles.x) * pitchSign > 0.05, "\(label) did not pitch the craft (\(craft.eulerAngles.x))")
            rideFits(label)
        }
        // Water ghost: cloned in jet-ski mode it crouches over its own jet ski instead of standing through the hull.
        rider.updateGhost(sample: GhostSample(time: rideClock, distance: ride.distance + 5, stageIndex: 0, stageDistance: 5, x: 0, y: 0, roll: false))
        let waterGhost = rider.scene.rootNode.childNode(withName: "personalGhost", recursively: false)!
        let ghostCraft = waterGhost.childNode(withName: "jetSki", recursively: true)!
        precondition(!ghostCraft.isHidden && ghostCraft.eulerAngles.x == 0, "water ghost must show an unpitched jet ski")
        let ghostBoots = points(under: waterGhost, in: ghostCraft, except: ghostCraft).map(\.y).min()!
        precondition(ghostBoots >= 0.285 - 0.06, "water ghost sinks through the hull (\(ghostBoots))")
        let ghostHip = ghostCraft.convertPosition(SCNVector3Zero, from: waterGhost.childNode(withName: "leftLeg", recursively: true)!)
        precondition(Double(ghostHip.y) >= 0.57 && Double(ghostHip.y) <= 1.07 && Double(ghostHip.z) >= -0.10 && Double(ghostHip.z) <= 1.25,
                     "water ghost hips must ride over the seat (\(ghostHip))")
        // Ghost: cloned mid-roll it still stands upright, and it draws no more than the runner.
        let haunted = CoastalWorld(assetsURL: resources)
        var chase = RunnerSimulation()
        chase.start(seed: 3, boards: 0, mode: .odyssey, startStage: 0)
        var chaseClock = 0.0
        for frame in 0..<80 {
            if frame == 60 { chase.act(.roll) }
            chase.replaceTrackForTesting([], generate: false)
            chase.update(dt: 1.0 / 60); chaseClock += 1.0 / 60
            haunted.update(simulation: chase, character: "milo", board: "tideline", time: chaseClock)
        }
        haunted.updateGhost(sample: GhostSample(time: chaseClock, distance: chase.distance + 5, stageIndex: 0, stageDistance: 5, x: 0, y: 0, roll: false))
        let ghost = haunted.scene.rootNode.childNode(withName: "personalGhost", recursively: false)!
        let ghostBody = ghost.childNode(withName: "runnerBody", recursively: false)!
        precondition(SCNMatrix4EqualToMatrix4(ghostBody.transform, SCNMatrix4Identity), "ghost must reset the cloned pose root to upright")
        let hauntedPlayer: SCNNode = field(haunted, "player")
        precondition(visibleElements(ghost) <= visibleElements(hauntedPlayer) && visibleElements(ghost) <= 119, "ghost draws more than the runner")
        // The clone also froze the knees, elbows, feet and head mid-roll: they return to the standing rest pose, and the ghost stays under the old ceiling.
        for name in ["runnerShin", "runnerForearm", "runnerFoot", "runnerHead"] {
            let found = ghost.childNodes(passingTest: { n, _ in n.name == name })
            precondition(!found.isEmpty, "ghost has no \(name)")
            for node in found {
                let e = [Double(node.eulerAngles.x), Double(node.eulerAngles.y), Double(node.eulerAngles.z)]
                precondition(abs(e[0]) < 0.4 && abs(e[1]) < 1e-3 && abs(e[2]) < 1e-3, "ghost \(name) keeps its mid-roll pose \(e)")
            }
        }
        let ghostY = points(under: ghost, in: ghost).map(\.y)
        precondition(ghostY.min()! >= -0.05 && ghostY.max()! <= 2.65, "ghost leaves the standing bounds (\(ghostY.min()!)…\(ghostY.max()!))")
        // The ability aura encloses the 2.56 m figure's torso: centred about mid-height, wider than the shoulders and hips.
        let aura: SCNNode = field(rider, "abilityAura")
        let auraMid = aura.childNodes.map { Double($0.position.y) }.reduce(0, +) / Double(aura.childNodes.count)
        let auraRadii = aura.childNodes.map { Double(($0.geometry as! SCNTorus).ringRadius) }
        let auraReach = auraRadii.max()!
        precondition(auraMid >= 1.29 && auraMid <= 1.55 && auraRadii.min()! >= 1.04 && auraReach <= 1.25 + 1e-6, "aura mis-sized for the figure (mid \(auraMid), radii \(auraRadii))")
        print(String(format: "jet ski rider lowest %.2f (footrest %.2f), ghost y %.2f…%.2f, aura mid %.2f reach %.2f",
                     lowest, footrest, ghostY.min()!, ghostY.max()!, auraMid, auraReach))
        print("RunnerTests passed")
    }
}
