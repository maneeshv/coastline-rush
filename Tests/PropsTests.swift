import Foundation
import SceneKit

/// Prop builders: bounded, deterministic shapes that keep their old footprints.
@main struct PropsTests {
    static func box(_ geometry: SCNGeometry) -> (lo: SIMD3<Double>, hi: SIMD3<Double>) {
        let (lo, hi) = geometry.boundingBox
        return (SIMD3(Double(lo.x), Double(lo.y), Double(lo.z)), SIMD3(Double(hi.x), Double(hi.y), Double(hi.z)))
    }
    /// Bounds of every geometry box under `node`, in `node` space. Tilted parts are bounded by their box corners, so slightly generous.
    /// (`flattenedClone().boundingBox` is empty off-screen, and parametric shapes keep normalised vertex data.)
    static func box(_ node: SCNNode) -> (lo: SIMD3<Double>, hi: SIMD3<Double>) {
        var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
        func visit(_ n: SCNNode) {
            if let g = n.geometry {
                let (a, b) = g.boundingBox
                for corner in 0..<8 {
                    let x = corner & 1 == 0 ? a.x : b.x, y = corner & 2 == 0 ? a.y : b.y, z = corner & 4 == 0 ? a.z : b.z
                    let p = node.convertPosition(SCNVector3(x, y, z), from: n)
                    let v = SIMD3(Double(p.x), Double(p.y), Double(p.z))
                    lo = pointwiseMin(lo, v); hi = pointwiseMax(hi, v)
                }
            }
            n.childNodes.forEach(visit)
        }
        visit(node)
        return (lo, hi)
    }

    static func main() {
        let world = CoastalWorld(assetsURL: nil), twin = CoastalWorld(assetsURL: nil)
        // Rocks: four distinct, deterministic, cached variants with a settled base.
        var boxes: [(lo: SIMD3<Double>, hi: SIMD3<Double>)] = []
        for variant in 0..<4 {
            let rock = world.rockGeometry(variant: variant)
            precondition(rock.sources(for: .vertex).first?.vectorCount == 960, "rock \(variant): expected 960 flat-shaded vertices")
            precondition(rock === world.rockGeometry(variant: variant + 4), "rock variants must be cached modulo 4")
            let b = box(rock)
            for axis in [0, 2] {
                precondition(b.hi[axis] > 0.6 && b.hi[axis] < 1.4 && b.lo[axis] < -0.6 && b.lo[axis] > -1.4, "rock \(variant) axis \(axis) out of bounds: \(b)")
            }
            precondition(b.hi.y > 0.6 && b.hi.y < 1.4 && b.lo.y >= -0.6 && b.lo.y <= -0.3, "rock \(variant) height out of bounds: \(b)")
            let t = box(twin.rockGeometry(variant: variant))
            precondition(simd_length(t.lo - b.lo) + simd_length(t.hi - b.hi) < 1e-5, "rock \(variant) must be deterministic")
            boxes.append(b)
        }
        precondition(simd_length(boxes[0].hi - boxes[1].hi) > 0.01, "rock variants must differ")
        // Crystals: four shards, as tall as requested, no wider than the old cone footprint allowance.
        for height in [0.48, 2.0, 4.5] {
            let cluster = world.crystalCluster(height: height, material: SCNMaterial())
            precondition(cluster.childNodes.count == 4, "crystal cluster needs 4 shards")
            let b = box(cluster)
            precondition(b.hi.y > 0.95 * height && b.hi.y < 1.02 * height, "crystal \(height) top \(b.hi.y)")
            precondition(b.lo.y > -0.08 * height, "crystal \(height) sinks below its base: \(b.lo.y)")
            let reach = [abs(b.lo.x), b.hi.x, abs(b.lo.z), b.hi.z].max()!
            precondition(reach <= 0.45 * height, "crystal \(height) too wide: \(reach)")
        }
        print("PropsTests passed")
    }
}
