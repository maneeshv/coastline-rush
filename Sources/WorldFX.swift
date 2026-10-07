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
}

extension WorldStage {
    var ambient: AmbientFX {
        switch self {
        case .harbor:   // low sea mist: few, huge, faint
            return AmbientFX(tint: "C9D8E6", opacity: 0.08, count: 12, life: 6, size: 4.2, sizeVariation: 1.0,
                             drift: SIMD3(0.4, 0.05, 0), flow: 1, low: 0.2, high: 3, additive: false, stretch: 0)
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
    func makeFX() {
        ambientFX.birthLocation = .volume
        ambientNode.addParticleSystem(ambientFX)
        scene.rootNode.addChildNode(ambientNode)
    }

    /// Re-dresses the pooled ambient system for `stage` and restarts it pre-warmed, so the old world's particles vanish with it.
    func applyAmbient(_ stage: WorldStage) {
        let a = stage.ambient
        dress(ambientFX, life: a.life, size: a.size, tint: a.tint, opacity: a.opacity, additive: a.additive)
        ambientFX.particleSizeVariation = CGFloat(a.sizeVariation)
        ambientFX.stretchFactor = CGFloat(a.stretch)
        ambientFX.birthRate = CGFloat(a.count / a.life * fxScale)
        ambientFX.warmupDuration = CGFloat(a.life)   // offscreen snapshots and a new world start fully populated
        ambientFX.emitterShape = SCNBox(width: 22, height: CGFloat(a.high - a.low), length: 56, chamferRadius: 0)
        ambientFX.reset()
    }

    /// Per frame: the ambient volume follows the camera and the air streams past at run speed.
    func updateAmbient(speed: Double) {
        let a = renderedStage.ambient
        // The volume spans 50 m ahead to 6 m behind the runner. At speed a particle lives only while it travels about 25 m,
        // so the budget stays in view instead of streaming past the camera; the birth rate keeps the live count fixed.
        ambientNode.position = vector(cameraEye.x, routeHeight + (a.low + a.high) / 2, -22)
        let flow = a.drift + SIMD3(0, 0, a.flow * speed)
        let life = min(a.life, 25 / max(0.1, a.flow * speed))
        let heading = simd_normalize(flow)   // must be a unit vector: SceneKit scales particleVelocity by its length
        ambientFX.emittingDirection = vector(heading.x, heading.y, heading.z)
        ambientFX.particleVelocity = CGFloat(simd_length(flow))
        ambientFX.particleLifeSpan = CGFloat(life)
        ambientFX.birthRate = CGFloat(a.count * fxScale / life)
    }
}
