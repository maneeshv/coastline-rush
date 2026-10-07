import SceneKit

/// A world's ambient particles. `count` is the live particles at ultra quality.
struct AmbientFX {
    var tint: String, opacity: Double
    var count: Double, life: Double, size: Double, sizeVariation: Double
    /// World-space drift (m/s) on top of the run: the air streams past at `flow` × run speed (1 = still air).
    var drift: SIMD3<Double>, flow: Double
    /// Birth heights above the route (m).
    var low: Double, high: Double
    var additive: Bool, stretch: Double
    /// Particles within this |x| (the road) fade out over 3 m beyond it; 0 = everywhere.
    var clear = 0.0
}

/// Ambient deaths so far: how many, the nearest to the lens and the nearest to the route line (tests read it).
struct AmbientSeen { var count = 0, nearest = Float.infinity, lateral = Float.infinity }

extension WorldStage {
    var ambient: AmbientFX {
        switch self {
        case .harbor:   // mist banks over the water only: sprites over the road cut far-hazard contrast, so `clear` keeps them off it
            return AmbientFX(tint: "C9D8E6", opacity: 0.35, count: 16, life: 6, size: 5.0, sizeVariation: 1.5,
                             drift: SIMD3(0.4, 0.05, 0), flow: 1, low: 0.2, high: 3, additive: false, stretch: 0, clear: 6)
        case .orbit:    // star streaks rushing past faster than the run
            return AmbientFX(tint: "DDEBFF", opacity: 0.8, count: 80, life: 1.2, size: 0.10, sizeVariation: 0.03,
                             drift: SIMD3(0, 0, 0), flow: 1.8, low: 1, high: 14, additive: true, stretch: 0.08)
        case .mars:     // dust on a crosswind
            return AmbientFX(tint: "E8B48A", opacity: 0.5, count: 120, life: 3, size: 0.25, sizeVariation: 0.10,
                             drift: SIMD3(2.2, 0.2, 0), flow: 1, low: 0.1, high: 6, additive: false, stretch: 0)
        case .verdant:  // rising bioluminescent spores
            return AmbientFX(tint: "B8FFE6", opacity: 0.8, count: 70, life: 5, size: 0.20, sizeVariation: 0.08,
                             drift: SIMD3(0, 0.35, 0), flow: 1, low: 0.3, high: 7, additive: true, stretch: 0)
        case .cryo:     // falling snow
            return AmbientFX(tint: "F2F8FF", opacity: 0.85, count: 160, life: 3, size: 0.18, sizeVariation: 0.06,
                             drift: SIMD3(0.4, -1.8, 0), flow: 1, low: 0.5, high: 9, additive: false, stretch: 0)
        case .forge:    // rising embers
            return AmbientFX(tint: "FFA050", opacity: 0.9, count: 90, life: 2.2, size: 0.18, sizeVariation: 0.05,
                             drift: SIMD3(0, 1.6, 0), flow: 1, low: 0, high: 6, additive: true, stretch: 0.02)
        }
    }
}

extension CoastalWorld {
    /// Particle budget per quality tier: performance half, balanced three quarters, ultra full.
    var fxScale: Double { [0.5, 0.75, 1.0][qualityLevel] }

    /// A 64 px soft round sprite shared by every particle system (generated and cached).
    func softDot() -> CGImage? {
        if let cached = textureCache["fx-dot"] { return cached }
        let dot = image(width: 64, height: 64) { ctx in
            let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color("FFFFFF").cgColor, color("FFFFFF", alpha: 0.35).cgColor, color("FFFFFF", alpha: 0).cgColor] as CFArray,
                                  locations: [0, 0.35, 1])!
            ctx.drawRadialGradient(fade, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        textureCache["fx-dot"] = dot
        return dot
    }

    /// Soft sprites, unsorted, alpha or additive. Opacity rides on the colour's alpha.
    func dress(_ system: SCNParticleSystem, life: Double, size: Double, tint: String, opacity: Double, additive: Bool) {
        system.particleImage = softDot()
        system.particleLifeSpan = CGFloat(life)
        system.particleSize = CGFloat(size)
        system.particleColor = color(tint, alpha: opacity)
        system.blendMode = additive ? .additive : .alpha
        system.sortingMode = .none
    }

    /// Builds the pooled ambient emitter once. Nothing is created per frame. A looping system restarts with `reset()`
    /// and is never re-added: re-adding a looping system to the same node stops it rendering (probe at 3781698).
    /// `reset()` does not re-run the warm-up: only the first render starts populated, a later world or tier refills over one life.
    func makeFX() {
        ambientFX.birthLocation = .volume
        ambientFX.handle(.birth, forProperties: [.position, .life, .velocity]) { [unowned self] data, stride, _, count in
            shapeAmbientBirths(data, stride, count: count)
        }
        ambientFX.handle(.death, forProperties: [.position]) { [unowned self] data, stride, _, count in
            noteAmbientDeaths(data, stride, count: count)
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]; fade.keyTimes = [0, 0.7, 1]; fade.duration = 1
        ambientFX.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        ambientNode.addParticleSystem(ambientFX)
        scene.rootNode.addChildNode(ambientNode)
    }

    /// Re-dresses the pooled ambient system for `stage` and restarts it, so the old world's particles vanish with it.
    /// Birth rate, heading, speed and stretch are per-frame (`updateAmbient`).
    func applyAmbient(_ stage: WorldStage) {
        let a = stage.ambient
        dress(ambientFX, life: a.life, size: a.size, tint: a.tint, opacity: a.opacity, additive: a.additive)
        ambientFX.particleSizeVariation = CGFloat(a.sizeVariation)
        ambientFX.warmupDuration = CGFloat(a.life)   // the first render (offscreen snapshots) starts fully populated
        ambientFX.emitterShape = SCNBox(width: 22, height: CGFloat(a.high - a.low), length: 52, chamferRadius: 0)
        for puff in footDust.compactMap({ $0.particleSystems?.first }) { puff.particleColor = color(stage.deckDust, alpha: 0.5) }
        ambientFX.reset()
    }

    /// Births (properties position, life, velocity): a particle is shortened so it dies `ambientNear` in front of the lens
    /// (5 m, or three sprite sizes: a sprite beside the lens is a blob, not weather; it fades out over its last 30%), and in a world with a
    /// `clear` zone it is pushed out of the road onto the water. Positions are world space.
    func shapeAmbientBirths(_ data: UnsafeMutablePointer<UnsafeMutableRawPointer>, _ stride: UnsafeMutablePointer<Int>, count: Int) {
        for i in 0..<count {
            let p = (data[0] + i * stride[0]).assumingMemoryBound(to: Float.self)
            let life = (data[1] + i * stride[1]).assumingMemoryBound(to: Float.self)
            let vz = (data[2] + i * stride[2]).assumingMemoryBound(to: Float.self)[2]
            if ambientClear > 0 { p[0] = (p[0] < 0 ? -1 : 1) * (ambientClear + abs(p[0]) * (11 - ambientClear) / 11) }
            if vz > 0.01 { life.pointee = min(life.pointee, max(0, ambientEye.z - ambientNear - p[2]) / vz) }
        }
    }

    /// Deaths (property position): the nearest to the lens and to the route line, for the tests.
    func noteAmbientDeaths(_ data: UnsafeMutablePointer<UnsafeMutableRawPointer>, _ stride: UnsafeMutablePointer<Int>, count: Int) {
        for i in 0..<count {
            let p = (data[0] + i * stride[0]).assumingMemoryBound(to: Float.self)
            ambientSeen.count += 1
            ambientSeen.nearest = min(ambientSeen.nearest, simd_distance(SIMD3(p[0], p[1], p[2]), ambientEye))
            ambientSeen.lateral = min(ambientSeen.lateral, abs(p[0]))
        }
    }

    /// Per frame: the ambient volume follows the camera and the air streams past at run speed.
    func updateAmbient(speed: Double) {
        let a = renderedStage.ambient
        // The volume spans 50 m ahead to 6 m behind the runner. At speed a particle lives only while it travels about 25 m,
        // so most of the budget stays in view (roughly 15% still passes behind the camera); the birth rate keeps the live count fixed.
        // Reduced Motion: no stretched or faster-than-run streaks, which would read as speed lines.
        let flowScale = reducedMotion ? min(a.flow, 1) : a.flow
        ambientNode.position = vector(cameraEye.x, routeHeight + (a.low + a.high) / 2, -24)
        ambientEye = SIMD3(Float(cameraEye.x), Float(cameraEye.y), Float(cameraEye.z))
        ambientClear = Float(a.clear)
        ambientNear = Float(max(5, 3 * (a.size + a.sizeVariation)))
        let flow = a.drift + SIMD3(0, 0, flowScale * speed)
        let life = min(a.life, 25 / max(0.1, flowScale * speed))
        let heading = simd_normalize(flow)   // must be a unit vector: SceneKit scales particleVelocity by its length
        ambientFX.emittingDirection = vector(heading.x, heading.y, heading.z)
        ambientFX.stretchFactor = CGFloat(reducedMotion ? 0 : a.stretch)
        ambientFX.particleVelocity = CGFloat(simd_length(flow))
        ambientFX.particleLifeSpan = CGFloat(life)
        ambientFX.birthRate = CGFloat(a.count * fxScale / life)
    }
}

extension WorldStage {
    /// Footstep and landing dust on this world's deck.
    var deckDust: String {
        switch self {
        case .harbor: return "7E8A94"
        case .orbit: return "9FB4CC"
        case .mars: return "E0A97E"
        case .verdant: return "7FC9A8"
        case .cryo: return "E8F2FF"
        case .forge: return "8A6A5A"
        }
    }
}

extension CoastalWorld {
    /// Speed lines, footstep dust, the landing burst and the pickup sparkle: all pooled, built once.
    /// One-shot bursts restart by re-adding them (`burst`); `reset()` does not restart a finished one-shot.
    func makeMotionFX() {
        // Speed lines: thin streaks born on a ring 12 m ahead in camera space, flying out past the screen edges.
        dress(speedLines, life: 0.35, size: 0.025, tint: "FFFFFF", opacity: 0.35, additive: true)
        speedLines.emitterShape = SCNTorus(ringRadius: 3.2, pipeRadius: 1.0)
        speedLines.birthLocation = .volume
        speedLines.emittingDirection = vector(0, 1, 0)   // the emitter is turned so its +y points at the camera
        speedLines.particleVelocity = 30
        speedLines.stretchFactor = 0.05
        speedLines.isLocal = true
        speedLines.warmupDuration = 0.35
        speedLines.birthRate = 0
        let lineNode = SCNNode()
        lineNode.position = vector(0, 0.6, -12)
        lineNode.eulerAngles.x = scalar(.pi / 2)
        lineNode.addParticleSystem(speedLines)
        camera.addChildNode(lineNode)
        // Footstep dust: one emitter per foot, open only while that foot is planted. The puffs drift up and are left behind.
        for _ in 0..<2 {
            let puff = SCNParticleSystem()
            dress(puff, life: 0.45, size: 0.4, tint: "7E8A94", opacity: 0.5, additive: false)
            puff.emittingDirection = vector(0, 0, 1)
            puff.spreadingAngle = 6
            puff.acceleration = vector(0, 1.2, 0)
            puff.particleSizeVariation = 0.15
            puff.birthRate = 0
            let node = SCNNode()
            node.addParticleSystem(puff)
            scene.rootNode.addChildNode(node)
            footDust.append(node)
        }
        // Landing: spark streaks and a dust ring burst from the ripple rings' centre (landingRoot).
        dress(landingSparkFX, life: 0.45, size: 0.04, tint: "FFD9B0", opacity: 1, additive: true)
        landingSparkFX.particleColorVariation = SCNVector4(0.15, 0.3, 0, 0)
        landingSparkFX.particleVelocity = 3.5
        landingSparkFX.particleVelocityVariation = 1.5
        landingSparkFX.stretchFactor = 0.04
        landingSparkFX.acceleration = vector(0, -6, 0)
        dress(landingDustFX, life: 0.6, size: 0.45, tint: "7E8A94", opacity: 0.45, additive: false)
        landingDustFX.particleVelocity = 2.2
        // Pickup sparkle: a quick gold burst at the runner's chest whenever the coin count rises.
        dress(sparkleFX, life: 0.4, size: 0.09, tint: "FFD66B", opacity: 1, additive: true)
        sparkleFX.emitterShape = SCNSphere(radius: 0.3)
        sparkleFX.particleVelocity = 2.4
        let ring = SCNTorus(ringRadius: 0.45, pipeRadius: 0.06)
        for system in [landingSparkFX, landingDustFX, sparkleFX] {
            if system !== sparkleFX { system.emitterShape = ring }
            system.birthLocation = .surface
            system.birthDirection = .surfaceNormal
            system.emissionDuration = 0.05
            system.loops = false
        }
        scene.rootNode.addChildNode(sparkleRoot)
        applyBurstQuality()
    }

    /// Burst sizes follow the quality tier: about 20 sparks, 22 dust puffs and 17 sparkles at ultra.
    func applyBurstQuality() {
        landingSparkFX.birthRate = CGFloat(400 * fxScale)
        landingDustFX.birthRate = CGFloat(450 * fxScale)
        sparkleFX.birthRate = CGFloat(350 * fxScale)
    }

    /// Restarts pooled one-shot bursts at `node`.
    func burst(_ systems: [SCNParticleSystem], at node: SCNNode) {
        node.removeAllParticleSystems()
        systems.forEach(node.addParticleSystem)
    }

    /// Per frame: speed lines, footstep dust and the pickup sparkle. `footing` is the run cycle's strength while running
    /// on foot (0 otherwise) and `gait` its phase (left contact at 0, right at π).
    func updateMotionFX(simulation: RunnerSimulation, running: Bool, gait: Double, footing: Double, height: Double, boosting: Bool) {
        // Speed lines from 26 m/s (full at 40) or while boosting; never under Reduced Motion.
        let t = min(1, max(0, (simulation.speed - 26) / 14))
        let lines = running && !reducedMotion ? max(t * t * (3 - 2 * t), boosting ? 1 : 0) : 0
        speedLines.birthRate = CGFloat(lines * 90 * fxScale)
        // Each foot puffs for the first 0.6 rad of its stance; the dust is left behind at 0.9 × run speed.
        for (i, node) in footDust.enumerated() {
            var since = (gait - Double(i) * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if since < 0 { since += 2 * .pi }
            let planted = running && footing > 0.6 && height < 0.05 && since < 0.6
            let foot = feet[i].worldPosition
            node.position = vector(Double(foot.x), routeHeight + 0.25, Double(foot.z))
            node.particleSystems?.first?.birthRate = CGFloat(planted ? 70 * fxScale : 0)
            node.particleSystems?.first?.particleVelocity = CGFloat(simulation.speed * 0.9)
            node.particleSystems?.first?.particleLifeSpan = CGFloat(min(0.45, 2 / max(1, simulation.speed * 0.9)))   // a puff dies within 2 m of the heel: it must not fly at the camera
        }
        // Pickup sparkle: the simulation exposes `coins`, so a rise is a pickup (no simulation change).
        if running && simulation.coins > lastCoins {
            sparkleRoot.position = vector(Double(player.position.x), Double(player.position.y) + 1.25, Double(player.position.z) - 0.3)
            burst([sparkleFX], at: sparkleRoot)
        }
        lastCoins = simulation.coins
    }
}
