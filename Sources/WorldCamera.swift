import SceneKit

/// Gameplay camera rig: where the camera sits, how it follows, how wide it sees and how far it leans.
/// Pure math (Foundation + simd), so FXTests can check it without rendering.
enum CameraRig {
    /// Run framing: height above the route and distance behind the runner. The menu keeps the old framing
    /// (`menuOffset`) and leaving it glides into this one.
    static func offset(portrait: Bool, water: Bool) -> (height: Double, depth: Double) {
        ((portrait ? 5.3 : 4.8) - (water ? 0.6 : 0), portrait ? 10.0 : 8.9)
    }
    static func menuOffset(portrait: Bool, water: Bool) -> (height: Double, depth: Double) {
        (water ? 5.4 : 6.1, portrait ? 11.8 : 10.4)
    }
    /// The camera looks at a point this far ahead of the runner and this high above the route.
    static let lookAhead = 14.0, lookHeight = 0.9
    /// Exponential follow rates (1/s): each frame the camera closes 1 − e^(−rate·dt) of the gap.
    static let followRate = 7.0, fovRate = 3.0
    static func baseFieldOfView(portrait: Bool) -> Double { portrait ? 64 : 56 }
    /// Widens by up to 3° between 14 and 44 m/s, and by 5° more while boosting. Reduced Motion: fixed.
    static func fieldOfView(portrait: Bool, speed: Double, boosting: Bool, reducedMotion: Bool) -> Double {
        let base = baseFieldOfView(portrait: portrait)
        guard !reducedMotion else { return base }
        let t = min(1, max(0, (speed - 14) / 30))
        return base + 3 * t * t * (3 - 2 * t) + (boosting ? 5 : 0)
    }
    /// Frame-rate independent: two steps of dt land exactly where one step of 2·dt does (for a fixed target).
    static func follow(_ current: SIMD3<Double>, toward target: SIMD3<Double>, rate: Double, dt: Double) -> SIMD3<Double> {
        target + (current - target) * exp(-rate * dt)
    }
    /// Roll about the view axis (radians), the same way the runner banks. Reduced Motion: none.
    static func lean(bank: Double, reducedMotion: Bool) -> Double { reducedMotion ? 0 : bank * 0.06 }
}

extension CoastalWorld {
    /// Places the gameplay camera. `snap` skips the lag (the first frame, or rewound time such as a crash replay).
    /// The menu and Reduced Motion never lag.
    func updateCamera(menu: Bool, waterMode: Bool, lateral: Double, speed: Double, boosting: Bool, flightLift: Double,
                      ahead: (lateralOffset: Double, elevation: Double), time: Double, dt: Double, snap: Bool) {
        let portrait = aspect < 0.8
        let x = menu ? 0.35 : lateral * 0.3 + routeOffset
        let rig = menu ? CameraRig.menuOffset(portrait: portrait, water: waterMode) : CameraRig.offset(portrait: portrait, water: waterMode)
        let eye = SIMD3(x, rig.height + routeHeight + flightLift, rig.depth)
        let target = SIMD3((x - routeOffset) * 0.25 + ahead.lateralOffset, (menu ? 0.5 : CameraRig.lookHeight) + ahead.elevation + flightLift, -CameraRig.lookAhead)
        let fov = menu ? (portrait ? 66 : 58) : CameraRig.fieldOfView(portrait: portrait, speed: speed, boosting: boosting, reducedMotion: reducedMotion)
        if snap || menu || reducedMotion || simd_distance(eye, cameraEye) > 6 {
            cameraEye = eye; cameraTarget = target; cameraFOV = fov
        } else {
            cameraEye = CameraRig.follow(cameraEye, toward: eye, rate: CameraRig.followRate, dt: dt)
            cameraTarget = CameraRig.follow(cameraTarget, toward: target, rate: CameraRig.followRate, dt: dt)
            cameraFOV = fov + (cameraFOV - fov) * exp(-CameraRig.fovRate * dt)
        }
        let shake = boosting && !reducedMotion ? sin(time * 30) * 0.025 : 0
        camera.position = vector(cameraEye.x, cameraEye.y + shake, cameraEye.z)
        // An explicit world up: plain look(at:) keeps the node's current up, so last frame's lean would accumulate.
        camera.look(at: vector(cameraTarget.x, cameraTarget.y, cameraTarget.z), up: vector(0, 1, 0), localFront: vector(0, 0, -1))
        camera.simdLocalRotate(by: simd_quatf(angle: Float(menu ? 0 : CameraRig.lean(bank: bank, reducedMotion: reducedMotion)), axis: SIMD3<Float>(0, 0, 1)))
        camera.camera?.fieldOfView = CGFloat(cameraFOV)
    }
}
