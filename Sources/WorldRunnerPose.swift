import Foundation

/// Pure run-cycle math for the runner rig: keyframed joint curves sampled by gait phase, blends and springs.
/// Angles are radians about x. A positive thigh or arm swings forward (the runner faces −z), a negative shin
/// bends the knee, a positive forearm bends the elbow, and a positive foot lifts the toe.
enum RunnerPose {
    struct Limbs: Equatable {
        var thigh = 0.0, shin = 0.0, foot = 0.0, arm = 0.0, forearm = 0.0
    }

    /// Left-side keys, eight per stride, spaced evenly over one gait period (2π): left contact, down, passing, up,
    /// then left toe-off, recoil, passing and reach. The right side samples the same curves at phase + π.
    static let thighKeys: [Double] = [0.45, 0.25, -0.05, -0.40, -0.55, -0.20, 0.45, 0.70]
    static let shinKeys: [Double] = [-0.15, -0.45, -0.35, -0.15, -0.60, -1.70, -1.50, -0.55]
    static let footKeys: [Double] = [0.20, 0.00, -0.05, -0.45, -0.60, -0.30, 0.10, 0.25]
    static let armKeys: [Double] = [-0.50, -0.35, 0.00, 0.40, 0.55, 0.35, -0.10, -0.45]
    static let forearmKeys: [Double] = [0.70, 0.80, 1.00, 1.30, 1.40, 1.25, 0.95, 0.75]
    /// Per stride: hip sway toward the stance foot (metres on body x; the left foot is at −x), torso twist
    /// (positive while the left leg leads, so the right shoulder counter-rotates forward) and side tilt over the stance foot.
    static let swayKeys: [Double] = [-0.020, -0.035, -0.030, -0.010, 0.020, 0.035, 0.030, 0.010]
    static let yawKeys: [Double] = [0.10, 0.07, 0.00, -0.07, -0.10, -0.07, 0.00, 0.07]
    static let rollKeys: [Double] = [0.02, 0.04, 0.03, 0.00, -0.02, -0.04, -0.03, 0.00]
    /// Per step (contact, down, passing, up), repeated for each foot (period π): body lift in metres and forward lean.
    static let bobKeys: [Double] = [-0.02, -0.07, 0.00, 0.05]
    static let leanKeys: [Double] = [0.06, 0.09, 0.07, 0.05]
    /// Standing pose the run cycle scales from: knees and elbows slightly soft.
    static let rest = Limbs(thigh: 0, shin: -0.10, foot: 0, arm: 0, forearm: 0.35)

    /// Head pivot height in body space, shared by the rig builder and the pose (head counter-bob).
    static let neckHeight = 2.10

    /// Airborne: the leading (left) knee drives up, the trailing leg folds, the arms counter for balance.
    static let airLeft = Limbs(thigh: 0.95, shin: -1.30, foot: 0.15, arm: -0.60, forearm: 0.90)
    static let airRight = Limbs(thigh: -0.25, shin: -0.95, foot: -0.30, arm: 0.70, forearm: 1.10)
    /// Roll tuck: knees to chest, hands on the shins.
    static let tuck = Limbs(thigh: 2.45, shin: -2.55, foot: 0.60, arm: 0.55, forearm: 0.90)
    /// Jet-ski rider: limbs, forward lean (rad), body drop and forward shift (m), knee splay (rad).
    static let ride = Limbs(thigh: 0.80, shin: -1.20, foot: 0.28, arm: 1.00, forearm: 0.22)
    static let rideLean = 0.38, rideDrop = -0.32, rideShift = 0.0, rideSplay = 0.02

    /// The body's vertical scale: landing squash (0.32 s, down to 0.84) and takeoff stretch (0.12 s, up to 1.10).
    static func squash(landingAge: Double, takeoffAge: Double) -> Double {
        var s = 1.0
        if landingAge < 0.32 { s -= 0.16 * sin(landingAge / 0.32 * .pi) }
        if takeoffAge < 0.12 { s += 0.10 * sin(takeoffAge / 0.12 * .pi) }
        return s
    }

    /// Volume-preserving scale for vertical factor `y`: x and z take 1/√y.
    static func volumeScale(_ y: Double) -> (x: Double, y: Double, z: Double) {
        let w = 1 / y.squareRoot()
        return (w, y, w)
    }

    /// Roll tuck ball: spin centre in body space (1.5–1.9), its height above the deck (0.55–0.70) and
    /// the ball's scale (0.65–0.85; the 2.5 m figure must fit under the 1.30 m roll ceiling).
    static let tuckCentre = 1.75, tuckRadius = 0.65, tuckScale = 0.74
    /// One forward revolution per 0.8 s roll.
    static let spinRate = 2 * Double.pi / 0.8

    /// Roll spin in 0..<2π. While rolling it keeps turning; afterwards it finishes the turn and rests at 0 (upright).
    static func advanceSpin(_ angle: Double, rolling: Bool, dt: Double) -> Double {
        guard rolling || angle > 0 else { return 0 }
        let next = angle + dt * spinRate
        if next < 2 * .pi { return next }
        return rolling ? next - 2 * .pi : 0
    }

    /// Vertical speed (m/s) feeding the follow-through springs. Clamped so a frame hitch (where `dt` is already capped)
    /// or a one-frame jump in the rise cannot overshoot the springs.
    static func riseVelocity(from last: Double, to rise: Double, dt: Double) -> Double {
        dt > 0 ? max(-8, min(8, (rise - last) / dt)) : 0
    }

    /// Periodic Catmull-Rom through `keys` spaced evenly over 2π: it passes through every key and is C1 (no velocity jump).
    static func sample(_ keys: [Double], phase: Double) -> Double {
        let n = keys.count
        var t = phase / (2 * .pi) * Double(n)
        t -= (t / Double(n)).rounded(.down) * Double(n)
        let i = Int(t), f = t - Double(i)
        func k(_ j: Int) -> Double { keys[((j % n) + n) % n] }
        let p0 = k(i - 1), p1 = k(i), p2 = k(i + 1), p3 = k(i + 2)
        return 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (3 * p1 - p0 - 3 * p2 + p3) * f * f * f)
    }

    /// Both sides at gait `phase` (radians): the right side runs half a stride behind the left.
    static func limbs(phase: Double) -> (left: Limbs, right: Limbs) {
        func side(_ p: Double) -> Limbs {
            Limbs(thigh: sample(thighKeys, phase: p), shin: sample(shinKeys, phase: p), foot: sample(footKeys, phase: p),
                  arm: sample(armKeys, phase: p), forearm: sample(forearmKeys, phase: p))
        }
        return (side(phase), side(phase + .pi))
    }

    /// Body channels at gait `phase`. Bob and lean repeat every step, so they sample at twice the phase.
    static func torso(phase: Double) -> (sway: Double, bob: Double, lean: Double, yaw: Double, roll: Double) {
        (sample(swayKeys, phase: phase), sample(bobKeys, phase: phase * 2), sample(leanKeys, phase: phase * 2),
         sample(yawKeys, phase: phase), sample(rollKeys, phase: phase))
    }

    static func mix(_ a: Limbs, _ b: Limbs, _ t: Double) -> Limbs {
        func m(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return Limbs(thigh: m(a.thigh, b.thigh), shin: m(a.shin, b.shin), foot: m(a.foot, b.foot), arm: m(a.arm, b.arm), forearm: m(a.forearm, b.forearm))
    }

    /// Damped spring for follow-through (semi-implicit Euler; stable for dt ≤ 0.05 at these stiffnesses).
    struct Spring: Equatable { var value = 0.0, velocity = 0.0 }

    static func step(_ s: Spring, target: Double, dt: Double, stiffness: Double, damping: Double) -> Spring {
        var s = s
        s.velocity += ((target - s.value) * stiffness - s.velocity * damping) * dt
        s.value += s.velocity * dt
        return s
    }
}
