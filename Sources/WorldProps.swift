import SceneKit

/// Shared prop geometry. Builders return detached nodes; the `make…` call sites place and merge them.
extension CoastalWorld {
    /// Smooth 3D value noise in 0...1, deterministic on every platform.
    static func valueNoise(_ x: Double, _ y: Double, _ z: Double, seed: Int = 0) -> Double {
        func hash(_ i: Int, _ j: Int, _ k: Int) -> Double {
            // Split into steps: one long mixed &*/^ expression times out the type checker.
            var mixed = i &* 73_856_093
            mixed ^= j &* 19_349_663
            mixed ^= k &* 83_492_791
            mixed ^= seed &* 2_654_435_761
            var h = UInt64(bitPattern: Int64(mixed))
            h ^= h >> 33; h = h &* 0xFF51_AFD7_ED55_8CCD; h ^= h >> 33
            return Double(h & 0xFFFF) / 65535
        }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let xi = Int(floor(x)), yi = Int(floor(y)), zi = Int(floor(z))
        let fx = x - floor(x), fy = y - floor(y), fz = z - floor(z)
        let u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy), w = fz * fz * (3 - 2 * fz)
        let x00 = lerp(hash(xi, yi, zi), hash(xi + 1, yi, zi), u)
        let x10 = lerp(hash(xi, yi + 1, zi), hash(xi + 1, yi + 1, zi), u)
        let x01 = lerp(hash(xi, yi, zi + 1), hash(xi + 1, yi, zi + 1), u)
        let x11 = lerp(hash(xi, yi + 1, zi + 1), hash(xi + 1, yi + 1, zi + 1), u)
        return lerp(lerp(x00, x10, v), lerp(x01, x11, v), w)
    }

    /// Flat-shaded triangles: three unique vertices per face, each carrying the face normal.
    /// Triangles must be counter-clockwise seen from outside.
    static func facetedGeometry(_ triangles: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)],
                                uv: (SIMD3<Double>) -> CGPoint) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], coordinates: [CGPoint] = []
        for (a, b, c) in triangles {
            let n = simd_normalize(simd_cross(b - a, c - a))
            for p in [a, b, c] {
                vertices.append(SCNVector3(CoastScalar(p.x), CoastScalar(p.y), CoastScalar(p.z)))
                normals.append(SCNVector3(CoastScalar(n.x), CoastScalar(n.y), CoastScalar(n.z)))
                coordinates.append(uv(p))
            }
        }
        let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: coordinates)], elements: [element])
    }

    /// Faceted boulder: icosahedron subdivided twice, noise-displaced, with a settled base. Unit radius.
    func rockGeometry(variant: Int) -> SCNGeometry {
        let slot = ((variant % 4) + 4) % 4
        let key = "rock-\(slot)"
        if let cached = geometryCache[key] { return cached }
        let t = (1 + 5.0.squareRoot()) / 2
        var points: [SIMD3<Double>] = [
            SIMD3(-1, t, 0), SIMD3(1, t, 0), SIMD3(-1, -t, 0), SIMD3(1, -t, 0),
            SIMD3(0, -1, t), SIMD3(0, 1, t), SIMD3(0, -1, -t), SIMD3(0, 1, -t),
            SIMD3(t, 0, -1), SIMD3(t, 0, 1), SIMD3(-t, 0, -1), SIMD3(-t, 0, 1),
        ].map { simd_normalize($0) }
        var faces: [(Int, Int, Int)] = [
            (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
            (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
        ]
        for _ in 0..<2 {
            var midpoints: [Int: Int] = [:]
            func midpoint(_ a: Int, _ b: Int) -> Int {
                let key = min(a, b) * 4096 + max(a, b)
                if let found = midpoints[key] { return found }
                points.append(simd_normalize((points[a] + points[b]) / 2))
                midpoints[key] = points.count - 1
                return points.count - 1
            }
            var next: [(Int, Int, Int)] = []
            for (a, b, c) in faces {
                let ab = midpoint(a, b), bc = midpoint(b, c), ca = midpoint(c, a)
                next += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
            }
            faces = next
        }
        let seed = Double(slot) * 17.3
        let rough = points.map { p -> SIMD3<Double> in
            let broad = Self.valueNoise(p.x * 1.6 + seed, p.y * 1.6, p.z * 1.6) - 0.5
            let fine = Self.valueNoise(p.x * 4.1, p.y * 4.1 + seed, p.z * 4.1) - 0.5
            var q = p * (1 + broad * 0.55 + fine * 0.16)
            if q.y < -0.35 { q.y = -0.35 + (q.y + 0.35) * 0.2 }   // settle onto the ground
            return q
        }
        // Normalise so the widest horizontal reach is exactly 1: the footprint stays the old sphere's.
        let reach = rough.map { max(abs($0.x), abs($0.z)) }.max()!
        let displaced = rough.map { $0 / reach }
        let triangles = faces.map { f -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) in
            let a = displaced[f.0], b = displaced[f.1], c = displaced[f.2]
            // Strong displacement can fold a face inward; keep every face outward-wound.
            return simd_dot(simd_cross(b - a, c - a), a + b + c) < 0 ? (a, c, b) : (a, b, c)
        }
        let geometry = Self.facetedGeometry(triangles) { p in
            CGPoint(x: atan2(p.x, p.z) / (2 * .pi) + 0.5, y: p.y * 0.5 + 0.5)
        }
        geometryCache[key] = geometry
        return geometry
    }

    /// A rock with its own material; same footprint as the old squashed sphere (1.4 × 0.8 × 1 radii).
    func rockNode(size: Double, material: SCNMaterial, variant: Int) -> SCNNode {
        let geometry = rockGeometry(variant: variant).copy() as! SCNGeometry
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.scale = SCNVector3(CoastScalar(size * 1.4), CoastScalar(size * 0.8), CoastScalar(size))
        return node
    }

    /// Hexagonal crystal cluster `height` metres tall: one main shard and three tilted satellites, base at y = 0.
    func crystalCluster(height: Double, material: SCNMaterial) -> SCNNode {
        let cluster = SCNNode()
        let shards: [(x: Double, z: Double, scale: Double, tilt: Double)] = [
            (0, 0, 1, 0), (0.16, 0.05, 0.62, 0.32), (-0.13, 0.09, 0.48, -0.38), (0.03, -0.15, 0.4, 0.25),
        ]
        for (index, shard) in shards.enumerated() {
            let h = height * shard.scale, r = height * (0.06 + 0.05 * shard.scale)
            let pivot = SCNNode()
            pivot.position = SCNVector3(CoastScalar(shard.x * height), 0, CoastScalar(shard.z * height))
            pivot.eulerAngles = SCNVector3(CoastScalar(shard.tilt * 0.5), CoastScalar(Double(index) * 1.1), CoastScalar(shard.tilt))
            let body = SCNCylinder(radius: r, height: h * 0.78); body.radialSegmentCount = 6; body.firstMaterial = material
            let bodyNode = SCNNode(geometry: body); bodyNode.position.y = CoastScalar(h * 0.39)
            let tip = SCNCone(topRadius: 0, bottomRadius: r, height: h * 0.22); tip.radialSegmentCount = 6; tip.firstMaterial = material
            let tipNode = SCNNode(geometry: tip); tipNode.position.y = CoastScalar(h * 0.89)
            pivot.addChildNode(bodyNode); pivot.addChildNode(tipNode)
            cluster.addChildNode(pivot)
        }
        return cluster
    }
    /// Valley-wall heightfield for one 26 m section. Rows run outward from the track edge (row 0 at |x| = 7.5),
    /// columns along local z. Noise is keyed by world distance, so neighbouring sections share their edge vertices.
    static func terrainVertices(side: Double, index: Int, icy: Bool, columns: Int = 41, rows: Int = 11) -> [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        result.reserveCapacity(columns * rows)
        let seed = side > 0 ? 7.0 : 0.0
        for row in 0..<rows { for column in 0..<columns {
            let z = -13 + Double(column) * 26 / Double(columns - 1)
            let distance = Double(index) * 26 - z
            let fraction = Double(row) / Double(rows - 1)
            let broad = valueNoise(distance * 0.11, fraction * 2.3, seed) - 0.5
            let detail = valueNoise(distance * 0.43, fraction * 6.1, seed + 3) - 0.5
            let ridge = (icy ? 11.0 : 12.0) + sin(distance * 0.025) * 3
            let y = row == 0 ? -1.3 : ridge * pow(fraction, 1.25) * (0.85 + broad * 0.7) + detail * 1.6 * fraction
            let x = side * (7.5 + fraction * 21.6 + broad * 2.4 * fraction)
            result.append(SIMD3(x, y, z))
        } }
        return result
    }

    /// Triangular-prism roof, ridge along z, eaves at y = 0, flat-shaded.
    func gableRoof(width: Double, length: Double, rise: Double, tint: String) -> SCNNode {
        let w = width / 2, l = length / 2
        let p: [SIMD3<Double>] = [SIMD3(-w, 0, -l), SIMD3(w, 0, -l), SIMD3(0, rise, -l), SIMD3(-w, 0, l), SIMD3(w, 0, l), SIMD3(0, rise, l)]
        let triangles = [(p[3], p[4], p[5]), (p[0], p[2], p[1]), (p[0], p[3], p[5]), (p[0], p[5], p[2]), (p[1], p[2], p[5]), (p[1], p[5], p[4])]
        let geometry = Self.facetedGeometry(triangles) { q in CGPoint(x: (q.x + q.z) * 0.25, y: q.y * 0.25) }
        geometry.firstMaterial = material(tint)
        return SCNNode(geometry: geometry)
    }

    /// Bioluminescent tree; `size` 1 is about 10 m tall. The trunk curves toward `outward` (±1 on x).
    func alienTreeNode(size: Double, outward: Double) -> SCNNode {
        let tree = SCNNode()
        let bark = material("496C65")
        func place(_ geometry: SCNGeometry, at p: SIMD3<Double>, euler: SIMD3<Double> = .zero) {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(CoastScalar(p.x), CoastScalar(p.y), CoastScalar(p.z))
            node.eulerAngles = SCNVector3(CoastScalar(euler.x), CoastScalar(euler.y), CoastScalar(euler.z))
            tree.addChildNode(node)
        }
        // Five tapered segments; each bends a little further. Rotating +y by `lean` about z gives (-sin, cos).
        var top = SIMD3<Double>(0, 0, 0), lean = 0.0
        for segment in 0..<5 {
            let length = 2.1
            lean -= 0.055 * outward
            let cone = SCNCone(topRadius: 0.68 - Double(segment) * 0.1, bottomRadius: 0.78 - Double(segment) * 0.1, height: length)
            cone.radialSegmentCount = 14; cone.firstMaterial = bark
            let direction = SIMD3(-sin(lean), cos(lean), 0)
            place(cone, at: top + direction * (length / 2), euler: SIMD3(0, 0, lean))
            top += direction * length
        }
        // Buttress roots: wide at the trunk, tapering outward and down to the ground (35° below horizontal).
        let drop = 35.0 * .pi / 180
        for i in 0..<4 {
            let angle = Double(i) * .pi / 2 + 0.4
            let axis = SIMD3(cos(angle) * cos(drop), -sin(drop), sin(angle) * cos(drop))
            let start = SIMD3(cos(angle) * 0.45, 1.05, sin(angle) * 0.45)
            let cone = SCNCone(topRadius: 0.05, bottomRadius: 0.32, height: 2.2); cone.radialSegmentCount = 8; cone.firstMaterial = bark
            let root = SCNNode(geometry: cone)
            let center = start + axis * 1.1
            root.position = SCNVector3(CoastScalar(center.x), CoastScalar(center.y), CoastScalar(center.z))
            root.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(axis.x), Float(axis.y), Float(axis.z)))
            tree.addChildNode(root)
        }
        // Three caps following the curve, each with a glowing gill ring and hanging seed pods.
        let gillGlow = material("7FE4BE", emissive: true), podGlow = material("8BF0CF", emissive: true), stemTint = material("2E5A50")
        for i in 0..<3 {
            let fraction = 0.56 + Double(i) * 0.21
            let center = SIMD3(top.x * fraction * fraction, top.y * fraction, 0)
            let radius = 3.8 - Double(i) * 0.7
            let cap = SCNSphere(radius: radius); cap.segmentCount = 24
            let capMaterial = material(i == 2 ? "62B4A7" : "477E80", unique: true)
            capMaterial.emission.contents = color("24766A"); capMaterial.emission.intensity = 0.15
            cap.firstMaterial = capMaterial
            let capNode = SCNNode(geometry: cap)
            capNode.position = SCNVector3(CoastScalar(center.x), CoastScalar(center.y), 0)
            capNode.scale = SCNVector3(1.1, 0.23, 0.85)
            tree.addChildNode(capNode)
            let gill = SCNTorus(ringRadius: radius * 0.82, pipeRadius: 0.07); gill.ringSegmentCount = 48; gill.pipeSegmentCount = 6
            gill.firstMaterial = gillGlow
            place(gill, at: center + SIMD3(0, -0.18, 0))
            for j in 0..<6 {
                let angle = Double(j) * .pi / 3 + Double(i) * 0.5
                let anchor = center + SIMD3(cos(angle) * radius * 0.7, -0.45, sin(angle) * radius * 0.55)
                let stem = SCNCylinder(radius: 0.025, height: 0.6); stem.radialSegmentCount = 5; stem.firstMaterial = stemTint
                place(stem, at: anchor)
                let pod = SCNSphere(radius: 0.14); pod.segmentCount = 8; pod.firstMaterial = podGlow
                place(pod, at: anchor + SIMD3(0, -0.36, 0))
            }
        }
        tree.scale = SCNVector3(CoastScalar(size), CoastScalar(size), CoastScalar(size))
        return tree
    }
}
