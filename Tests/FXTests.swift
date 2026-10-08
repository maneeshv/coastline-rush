import AppKit
import Metal
import SceneKit

/// Phase 4 camera and FX: runner screen size, hazard look-ahead, follow lag, lean, Reduced Motion, particles and quality tiers.
@main struct FXTests {
    static func field<T>(_ world: CoastalWorld, _ label: String) -> T {
        Mirror(reflecting: world).children.first { $0.label == label }!.value as! T
    }

    /// Normalised device coordinates (−1…1, y up) of a world point seen by the gameplay camera at `aspect` (width / height).
    static func project(_ world: CoastalWorld, _ p: SIMD3<Double>, aspect: Double) -> SIMD2<Double> {
        let projection = world.camera.camera!.projectionTransform(withViewportSize: CGSize(width: 1000 * aspect, height: 1000))
        let m = simd_double4x4(SCNMatrix4Mult(SCNMatrix4Invert(world.camera.worldTransform), projection))
        let c = m * SIMD4(p.x, p.y, p.z, 1)
        return SIMD2(c.x / c.w, c.y / c.w)
    }

    /// Lowest and highest screen y of the runner: its visible geometry's bounding-box corners, projected.
    static func runnerExtent(_ world: CoastalWorld, aspect: Double) -> (low: Double, high: Double) {
        var low = Double.infinity, high = -Double.infinity
        func visit(_ node: SCNNode) {
            guard !node.isHidden else { return }
            if let g = node.geometry {
                let (a, b) = g.boundingBox
                for k in 0..<8 {
                    let w = node.convertPosition(SCNVector3(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z), to: nil)
                    let y = project(world, SIMD3(Double(w.x), Double(w.y), Double(w.z)), aspect: aspect).y
                    low = min(low, y); high = max(high, y)
                }
            }
            node.childNodes.forEach(visit)
        }
        visit(field(world, "player"))
        return (low, high)
    }

    /// A fresh world after `frames` of running on an empty track.
    static func running(_ mode: RunMode, stage: Int, aspect: Double, frames: Int = 180, reducedMotion: Bool = false,
                        fps: Double = 60) -> (CoastalWorld, RunnerSimulation, Double) {
        let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
        world.resize(aspect: aspect)
        world.reducedMotion = reducedMotion
        var run = RunnerSimulation(); run.start(seed: 3, mode: mode, startStage: stage)
        var time = 0.0
        for _ in 0..<frames { step(world, &run, &time, fps: fps) }
        return (world, run, time)
    }

    static func step(_ world: CoastalWorld, _ run: inout RunnerSimulation, _ time: inout Double, fps: Double = 60) {
        run.replaceTrackForTesting([], generate: false)
        run.update(dt: 1 / fps); time += 1 / fps
        world.update(simulation: run, character: "milo", board: "tideline", time: time)
    }

    /// Ambient deaths seen by the real particle pass: how many, the nearest to the lens and to the route centre at that point of the track.
    final class Deaths { var count = 0, nearest = Float.infinity, lateral = Float.infinity, run = RunnerSimulation() }

    static func watchDeaths(_ world: CoastalWorld) -> Deaths {
        let seen = Deaths()
        world.ambientFX.handle(.death, forProperties: [.position]) { [unowned world] data, stride, _, count in
            for i in 0..<count {
                let p = (data[0] + i * stride[0]).assumingMemoryBound(to: Float.self)
                seen.count += 1
                seen.nearest = min(seen.nearest, simd_distance(SIMD3(p[0], p[1], p[2]), world.ambientEye))
                if p[2] < 0 {   // ahead of the runner: the track there bends the route to `routeTransform(atAheadDistance: -z)`
                    seen.lateral = min(seen.lateral, abs(p[0] - Float(seen.run.routeTransform(atAheadDistance: Double(-p[2])).lateralOffset)))
                }
            }
        }
        return seen
    }

    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        let portrait = 0.46, landscape = 16.0 / 9
        // 1. Runner screen size: the mean share over frames 151–180 (seed 3, empty track), so no single gait pose decides it.
        //    Phase 3 (3781698) values, measured with this exact setup: (mode, stage, portrait 0.46, landscape 16:9).
        //    The spec wants the runner larger on screen: at least 1.15× in every case, including Forge at 42 m/s where the
        //    speed-scaled field of view is widest.
        let phase3: [(RunMode, Int, Double, Double)] = [(.endless, 0, 0.1618, 0.2130), (.odyssey, 0, 0.1612, 0.2120), (.odyssey, 5, 0.1608, 0.2114)]
        for (mode, stage, p3Portrait, p3Landscape) in phase3 {
            for (aspect, before) in [(portrait, p3Portrait), (landscape, p3Landscape)] {
                var (world, run, time) = running(mode, stage: stage, aspect: aspect, frames: 150)
                var share = 0.0, lowest = 1.0
                for _ in 0..<30 {
                    step(world, &run, &time)
                    let e = runnerExtent(world, aspect: aspect)
                    share += (e.high - e.low) / 2 / 30; lowest = min(lowest, e.low)
                }
                print(String(format: "runner share %@ stage %d aspect %.2f speed %.1f: %.4f (phase 3 %.4f, ×%.3f)", "\(mode)", stage, aspect, run.speed, share, before, share / before))
                precondition(share >= before * 1.15, "runner must be ≥1.15× its phase-3 screen height (\(share) vs \(before))")
                precondition(lowest > -0.95, "runner's feet must stay on screen (\(lowest))")
            }
        }

        // 2. Readability: hazards telegraphed at spawn distance (135 m; Odyssey shows up to 200 m) stay on screen, under the
        //    HUD band and clear of the runner's head, in both orientations, at cruise and top speed, through a lane change.
        //    MotionTests' recycling assumes the camera never sits behind world z 12, where sections leave.
        for aspect in [portrait, landscape] {
            for (mode, stage) in [(RunMode.endless, 0), (.odyssey, 5), (.jetSki, 0)] {
                var (world, run, time) = running(mode, stage: stage, aspect: aspect, frames: 120)
                for frame in 0..<60 {
                    if frame == 0 { run.act(.right) }
                    if frame == 30 { run.act(.left); run.act(.left) }
                    step(world, &run, &time)
                    precondition(world.camera.position.z < 12, "camera behind the recycle line (z \(world.camera.position.z))")
                    let head = runnerExtent(world, aspect: aspect).high
                    for z in [-100.0, -135, -200] {
                        let route = run.routeTransform(atAheadDistance: -z)
                        for lane in [-1.0, 0, 1] {
                            for y in [0.0, 2.8] {
                                let s = project(world, SIMD3(lane * 2.6 + route.lateralOffset, y + route.elevation, z), aspect: aspect)
                                precondition(abs(s.x) < 0.95 && s.y > -0.95 && s.y < 0.85, "hazard at z \(z) lane \(lane) y \(y) off screen or under the HUD: \(s) (aspect \(aspect), frame \(frame))")
                                precondition(s.y > head + 0.2, "hazard at z \(z) too close to the runner's head: \(s.y) vs \(head) (aspect \(aspect), frame \(frame))")
                            }
                        }
                    }
                }
            }
        }

        // 3. Follow lag is frame-rate independent: a step target lands in the same place at 30, 60 and 120 fps.
        var ends: [SIMD3<Double>] = []
        for fps in [30.0, 60, 120] {
            var p = SIMD3<Double>(0, 0, 0)
            for _ in 0..<Int(fps / 2) { p = CameraRig.follow(p, toward: SIMD3(1, 2, 3), rate: CameraRig.followRate, dt: 1 / fps) }
            ends.append(p)
        }
        precondition(simd_distance(ends[0], ends[1]) < 1e-9 && simd_distance(ends[1], ends[2]) < 1e-9, "follow depends on frame rate: \(ends)")
        //    In the world: the same lane change at 30 and 120 fps puts the camera within 3 cm after 0.5 s, and the camera
        //    visibly lags the runner during the change, settles within a second and leans subtly.
        var afterHalf: [Double] = []
        for fps in [30.0, 120] {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: Int(fps * 2), fps: fps)
            run.act(.right)
            for _ in 0..<Int(fps / 2) { step(world, &run, &time, fps: fps) }
            afterHalf.append(Double(world.camera.position.x))
        }
        precondition(abs(afterHalf[0] - afterHalf[1]) < 0.03, "camera x after 0.5 s differs between 30 and 120 fps: \(afterHalf)")
        do {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 120)
            run.act(.right)
            var lag = 0.0, lean = 0.0
            for _ in 0..<60 {
                step(world, &run, &time)
                lag = max(lag, abs(Double(world.camera.position.x) - run.lateral * 0.3))
                lean = max(lean, abs(Double(world.camera.simdWorldRight.y)))
            }
            print(String(format: "lane change: max camera lag %.3f m, max lean %.4f", lag, lean))
            precondition(lag > 0.05, "camera must lag the runner during a lane change (\(lag))")
            precondition(abs(Double(world.camera.position.x) - run.lateral * 0.3) < 0.01, "camera must settle within a second")
            precondition(lean > 0.004 && lean < 0.05, "camera must lean subtly into the lane change (\(lean))")
        }

        // 4. Reduced Motion: no lag, no lean, no speed-scaled or boost field of view. The menu keeps its old framing.
        do {
            var (world, run, time) = running(.odyssey, stage: 5, aspect: portrait, frames: 120, reducedMotion: true)
            run.act(.right)
            for _ in 0..<40 {
                step(world, &run, &time)
                precondition(abs(Double(world.camera.position.x) - run.lateral * 0.3) < 1e-4, "Reduced Motion: the camera must not lag")
                precondition(abs(Double(world.camera.simdWorldRight.y)) < 1e-3, "Reduced Motion: the camera must not lean (\(world.camera.simdWorldRight))")
                precondition(abs(Double(world.camera.camera!.fieldOfView) - CameraRig.baseFieldOfView(portrait: true)) < 1e-6, "Reduced Motion: fixed field of view")
            }
        }
        for (aspect, depth) in [(portrait, 11.8), (landscape, 10.4)] {
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            world.resize(aspect: aspect)
            world.update(simulation: RunnerSimulation(), character: "milo", board: "tideline", time: 1)
            let p = world.camera.position
            precondition(abs(Double(p.x) - 0.35) < 1e-4 && abs(Double(p.y) - 6.1) < 1e-4 && abs(Double(p.z) - depth) < 1e-4, "menu framing changed: \(p)")
        }
        // 5. Ambient particles: each world has its own; the live budget is count × tier scale; the flow heading is a unit
        //    vector (SceneKit multiplies particleVelocity by its length).
        do {
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            var time = 0.0
            for (quality, scale) in [(RenderQuality.performance, 0.5), (.balanced, 0.75), (.ultra, 1.0)] {
                world.applyQuality(quality)
                for (index, stage) in WorldStage.allCases.enumerated() {
                    var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: index)
                    for _ in 0..<3 { step(world, &run, &time) }
                    let a = stage.ambient, fx = world.ambientFX
                    let live = Double(fx.birthRate * fx.particleLifeSpan)
                    precondition(abs(live - a.count * scale) < 0.5, "\(stage) \(quality): \(live) live particles, expected \(a.count * scale)")
                    precondition(a.count <= 160 && a.size <= 6, "\(stage): ambient budget is ≤160 particles of ≤6 m")
                    let d = fx.emittingDirection
                    precondition(abs(Double(d.x * d.x + d.y * d.y + d.z * d.z) - 1) < 1e-3, "\(stage): ambient heading must be a unit vector")
                }
            }
            // Reduced Motion: Orbit's streaks lose their stretch and the faster-than-run flow.
            do {
                let calm = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources")); calm.reducedMotion = true
                var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: 1)
                for _ in 0..<3 { step(calm, &run, &time) }
                precondition(calm.ambientFX.stretchFactor == 0, "Reduced Motion: no stretched ambient streaks")
                precondition(Double(calm.ambientFX.particleVelocity) < run.speed * 1.2, "Reduced Motion: ambient flow must not outrun the run")
            }
            precondition(Set(WorldStage.allCases.map(\.ambient.tint)).count == WorldStage.allCases.count, "every world needs its own ambient particles")
        }
        // 5b. Near-camera fade: rendered through the real particle pass, every ambient particle dies ahead of the lens
        //     (never within 3 m, and faded out by then), and in a world with a clear zone none strays onto the route.
        //     The last two cases are the Odyssey harbor's branch (safe route at x = -8, risky at +8, stage progress about 0.41):
        //     the mist must leave the route there too, so deaths are measured from the route centre, not from world x = 0.
        do {
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            let cases: [(WorldStage, Int, Bool?)] = WorldStage.allCases.enumerated().map { ($1, $0, nil) } + [(.harbor, 0, false), (.harbor, 0, true)]
            for (stage, index, risky) in cases {
                let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
                world.applyQuality(.ultra); world.resize(aspect: portrait)
                renderer.scene = world.scene; renderer.pointOfView = world.camera
                var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: index)
                var time = 0.0
                var farthest = 0.0
                let seen = watchDeaths(world)
                if let risky {   // run up to the branch unrendered, then render (so the mist is alive) from 30% of the stage
                    while run.stageProgress < 0.36 {
                        if risky && run.routeChoiceAvailable { run.act(.right) }
                        run.replaceTrackForTesting([], generate: false)
                        run.update(dt: 1 / 60); time += 1 / 60
                        precondition(run.phase == .running, "branch case: the run ended before the branch")
                        if run.stageProgress > 0.3 {
                            world.update(simulation: run, character: "milo", board: "tideline", time: time)
                            seen.run = run
                            _ = renderer.snapshot(atTime: time, with: CGSize(width: 90, height: 150), antialiasingMode: .none)
                        }
                    }
                }
                for _ in 0..<(risky == nil ? 240 : 300) {
                    step(world, &run, &time)
                    seen.run = run
                    farthest = max(farthest, abs(world.routeOffset))
                    _ = renderer.snapshot(atTime: time, with: CGSize(width: 90, height: 150), antialiasingMode: .none)
                }
                let label = risky.map { "\(stage) \($0 ? "risky" : "safe") branch (progress \(String(format: "%.2f", run.stageProgress)))" } ?? "\(stage)"
                print(String(format: "ambient %@: %d deaths, nearest %.2f m from the lens, nearest %.2f m from the route centre", label, seen.count, seen.nearest, seen.lateral))
                precondition(risky == nil || farthest > 7, "\(label): the route never left the road centre (\(farthest) m): the case does not test the branch")
                precondition(stage.ambient.count == 0 || seen.count > 0, "\(label): no ambient particle ever died: the death pass never ran")
                precondition(seen.nearest >= 3, "\(label): an ambient particle lived to \(seen.nearest) m from the lens")
                precondition(seen.lateral >= Float(max(3, stage.ambient.clear - 1)) || stage.ambient.clear == 0, "\(label): ambient over the route (\(seen.lateral) m from its centre)")
            }
        }
        // 6. Speed lines: none below 26 m/s, in the menu or under Reduced Motion; on at Forge cruise; half on performance.
        do {
            func lines(_ mode: RunMode, _ stage: Int, _ quality: RenderQuality = .ultra, reducedMotion: Bool = false) -> Double {
                let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
                world.applyQuality(quality); world.reducedMotion = reducedMotion
                var run = RunnerSimulation(); run.start(seed: 3, mode: mode, startStage: stage)
                var time = 0.0
                for _ in 0..<30 { step(world, &run, &time) }
                return Double(world.speedLines.birthRate)
            }
            precondition(lines(.odyssey, 0) == 0, "no speed lines at harbor cruise (17 m/s)")
            precondition(lines(.odyssey, 5) > 0, "speed lines at Forge cruise (42 m/s)")
            precondition(abs(lines(.odyssey, 5, .performance) - lines(.odyssey, 5) * 0.5) < 1e-6, "performance halves the speed lines")
            precondition(lines(.odyssey, 5, reducedMotion: true) == 0, "Reduced Motion: no speed lines")
            let menu = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            menu.update(simulation: RunnerSimulation(), character: "milo", board: "tideline", time: 1)
            precondition(menu.speedLines.birthRate == 0, "no speed lines in the menu")
        }

        // 7. Footstep dust opens and closes with each stance, never in the air or on the jet ski.
        do {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 60)
            var open = [0, 0], shut = [0, 0]
            for _ in 0..<60 {
                step(world, &run, &time)
                for i in 0..<2 { if (world.footDust[i].particleSystems?.first?.birthRate ?? 0) > 0 { open[i] += 1 } else { shut[i] += 1 } }
            }
            precondition(open.allSatisfy { $0 > 0 } && shut.allSatisfy { $0 > 0 }, "each foot must puff on contact only (open \(open), shut \(shut))")
            run.act(.jump)
            for _ in 0..<12 {
                step(world, &run, &time)
                if run.height > 0.1 { precondition(world.footDust.allSatisfy { ($0.particleSystems?.first?.birthRate ?? 0) == 0 }, "no footstep dust in the air") }
            }
            var (water, ride, rideTime) = running(.jetSki, stage: 0, aspect: portrait, frames: 60)
            for _ in 0..<30 {
                step(water, &ride, &rideTime)
                precondition(water.footDust.allSatisfy { ($0.particleSystems?.first?.birthRate ?? 0) == 0 }, "no footstep dust on the jet ski")
            }
        }

        // 8. Bursts: a landing restarts the pooled sparks and dust (not under Reduced Motion); a collected coin restarts the
        //    sparkle. Across all of it the scene never holds more than the 7 pooled systems: nothing is created per frame or event.
        for reducedMotion in [false, true] {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 60, reducedMotion: reducedMotion)
            let landing: SCNNode = field(world, "landingRoot")
            var pooled = Set<ObjectIdentifier>()
            func census() {
                world.scene.rootNode.enumerateHierarchy { node, _ in (node.particleSystems ?? []).forEach { pooled.insert(ObjectIdentifier($0)) } }
                precondition(pooled.count <= 7, "particle systems must be pooled (\(pooled.count) distinct)")
            }
            run.act(.jump)
            for _ in 0..<5 { step(world, &run, &time); census() }
            while run.height > 0 { step(world, &run, &time); census() }
            step(world, &run, &time); census()
            let attached = landing.particleSystems ?? []
            if reducedMotion { precondition(attached.isEmpty, "Reduced Motion: no landing burst") }
            else { precondition(attached.contains(world.landingSparkFX) && attached.contains(world.landingDustFX), "a landing must restart the pooled burst") }
            precondition(world.sparkleRoot.particleSystems?.isEmpty ?? true, "no sparkle before a pickup")
            let coins = run.coins
            var placed = false
            for _ in 0..<60 where run.coins == coins {
                run.replaceTrackForTesting(placed ? run.entities : [TrackEntity(id: 9_000, kind: .coin, lane: run.lane, z: 6, y: 0.9, length: 0.6)])
                placed = true
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                world.update(simulation: run, character: "milo", board: "tideline", time: time); census()
            }
            precondition(run.coins > coins, "test setup: the coin must be collected")
            precondition(world.sparkleRoot.particleSystems?.contains(world.sparkleFX) ?? false, "a pickup must restart the pooled sparkle")
            for _ in 0..<120 { step(world, &run, &time); census() }
        }
        do {   // bursts scale with the tier too
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            world.applyQuality(.ultra)
            let full = [world.landingSparkFX, world.landingDustFX, world.sparkleFX].map { Double($0.birthRate) }
            world.applyQuality(.performance)
            let half = [world.landingSparkFX, world.landingDustFX, world.sparkleFX].map { Double($0.birthRate) }
            precondition(zip(full, half).allSatisfy { abs($0 * 0.5 - $1) < 1e-6 }, "performance halves every burst")
        }
        // 9. Footstep puffs die within about 2 m of the heel (they leave at 0.9 x run speed, toward the static camera), and every
        //    burst and footstep rate follows the tier: 0.5 / 0.75 / 1.
        do {
            let (fast, run, _) = running(.odyssey, stage: 5, aspect: portrait, frames: 60)
            for node in fast.footDust {
                let puff = node.particleSystems!.first!
                precondition(Double(puff.particleLifeSpan * puff.particleVelocity) <= 2.2, "a puff must travel <= 2.2 m (\(Double(puff.particleLifeSpan * puff.particleVelocity)) m at \(run.speed) m/s)")
            }
            for (quality, scale) in [(RenderQuality.performance, 0.5), (.balanced, 0.75), (.ultra, 1.0)] {
                var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 0)
                world.applyQuality(quality)
                var peak = 0.0
                for _ in 0..<60 { step(world, &run, &time); peak = max(peak, world.footDust.map { Double($0.particleSystems!.first!.birthRate) }.max()!) }
                precondition(abs(peak - 70 * scale) < 1e-6, "footstep rate at \(quality): \(peak)")
                let bursts = [world.landingSparkFX, world.landingDustFX, world.sparkleFX].map { Double($0.birthRate) }
                precondition(zip(bursts, [400, 450, 350]).allSatisfy { abs($0 - $1 * scale) < 1e-6 }, "burst rates at \(quality): \(bursts)")
            }
        }
        print("FXTests passed")
    }
}
