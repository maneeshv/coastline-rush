import SceneKit

/// The runner: an about-7-heads figure built from lathe shells. Each rig bone carries one merged geometry
/// (one element per material), so the rig is 14 visible geometry nodes instead of ~120 primitives.
extension CoastalWorld {
    typealias Shell = (rings: [(Double, Double, Double)], at: SIMD3<Double>, material: SCNMaterial)

    func shell(_ rings: [(Double, Double, Double)], _ material: SCNMaterial, at offset: SIMD3<Double> = .zero) -> Shell {
        (rings, offset, material)
    }

    /// Lathe surface around the y axis: rings are (y, radiusX, radiusZ), ascending in y; 24 segments, analytic normals,
    /// optional flat end caps. Without caps this is exactly the old `sculptedMesh` surface.
    func latheMesh(rings: [(Double, Double, Double)], caps: Bool, at offset: SIMD3<Double> = .zero)
        -> (vertices: [SCNVector3], normals: [SCNVector3], uv: [CGPoint], indices: [Int32]) {
        let segments = 24
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
        func add(_ x: Double, _ y: Double, _ z: Double, _ n: SIMD3<Float>, _ u: Double, _ v: Double) {
            vertices.append(vector(x + offset.x, y + offset.y, z + offset.z))
            normals.append(vector(Double(n.x), Double(n.y), Double(n.z)))
            uv.append(CGPoint(x: u, y: v))
        }
        for (row, section) in rings.enumerated() {
            let before = rings[max(0, row - 1)], after = rings[min(rings.count - 1, row + 1)]
            let dy = max(0.01, after.0 - before.0)
            for column in 0...segments {
                let angle = Double(column) / Double(segments) * .pi * 2
                let c = cos(angle), s = sin(angle)
                let n = simd_normalize(SIMD3<Float>(Float(c / section.1), Float(-((after.1 - before.1) * c * c / section.1 + (after.2 - before.2) * s * s / section.2) / dy), Float(s / section.2)))
                add(section.1 * c, section.0, section.2 * s, n, Double(column) / Double(segments), Double(row) / Double(max(1, rings.count - 1)))
                if row < rings.count - 1 && column < segments {
                    let a = Int32(row * (segments + 1) + column), b = a + Int32(segments + 1)
                    indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        if caps {
            for (section, down) in [(rings[0], true), (rings[rings.count - 1], false)] {
                let n = SIMD3<Float>(0, down ? -1 : 1, 0)
                let centre = Int32(vertices.count)
                add(0, section.0, 0, n, 0.5, down ? 0 : 1)
                for column in 0...segments {
                    let angle = Double(column) / Double(segments) * .pi * 2
                    add(section.1 * cos(angle), section.0, section.2 * sin(angle), n, 0.5 + cos(angle) * 0.5, down ? 0 : 1)
                }
                for column in 0..<segments {
                    let a = centre + 1 + Int32(column)
                    indices += down ? [centre, a, a + 1] : [centre, a + 1, a]
                }
            }
        }
        return (vertices, normals, uv, indices)
    }

    /// Closed shells merged into one geometry with shared vertex buffers and one element per distinct material.
    func shellGeometry(_ shells: [Shell]) -> SCNGeometry {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = []
        var groups: [(material: SCNMaterial, indices: [Int32])] = []
        for part in shells {
            let mesh = latheMesh(rings: part.rings, caps: true, at: part.at)
            let base = Int32(vertices.count)
            vertices += mesh.vertices; normals += mesh.normals; uv += mesh.uv
            let shifted = mesh.indices.map { $0 + base }
            if let i = groups.firstIndex(where: { $0.material === part.material }) { groups[i].indices += shifted }
            else { groups.append((part.material, shifted)) }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)],
                                   elements: groups.map { SCNGeometryElement(indices: $0.indices, primitiveType: .triangles) })
        geometry.materials = groups.map(\.material)
        return geometry
    }

    /// Built inside `withoutSurfaceDetail`, so every runner material is flat. Body space: y up, facing −z, soles at y 0.
    func makePlayer() {
        leftLeg.name = "leftLeg"; rightLeg.name = "rightLeg"
        leftArm.name = "leftArm"; rightArm.name = "rightArm"
        scene.rootNode.addChildNode(player)
        player.addChildNode(body)
        let shirt = material("FF643E", unique: true)
        shirt.normal.contents = texture("cloth-normal")
        shirt.normal.intensity = 0.25
        shirt.roughness.contents = 0.8
        let sleeve = material("FF643E", unique: true)
        sleeve.roughness.contents = 0.8
        clothing = [shirt, sleeve]
        let suit = material("172A3C"), skin = material("CB977C"), glow = material("9ADBDD", emissive: true)

        // Torso on the pose root: pelvis, shirt, chest plate, belt, collar, neck, chest light.
        body.geometry = shellGeometry([
            shell([(1.14, 0.17, 0.13), (1.22, 0.22, 0.15), (1.32, 0.23, 0.16), (1.42, 0.21, 0.15)], suit),
            shell([(1.38, 0.20, 0.145), (1.50, 0.215, 0.15), (1.66, 0.25, 0.165), (1.82, 0.30, 0.18), (1.94, 0.33, 0.18), (2.00, 0.27, 0.15), (2.04, 0.12, 0.10)], shirt),
            shell([(1.66, 0.20, 0.15), (1.80, 0.25, 0.175), (1.92, 0.24, 0.17)], material("405B6A"), at: SIMD3(0, 0, -0.03)),
            shell([(1.36, 0.215, 0.16), (1.42, 0.22, 0.165)], material("6D899A")),
            shell([(2.00, 0.14, 0.12), (2.09, 0.13, 0.11)], material("17B8BB")),
            shell([(2.02, 0.09, 0.085), (2.18, 0.08, 0.08)], material("BD846C")),
            shell([(1.84, 0.08, 0.012), (1.87, 0.08, 0.012)], material("B2E3DB", emissive: true), at: SIMD3(0, 0, -0.205)),
        ])

        // Expedition pack, hung from its top strap so it can swing (follow-through).
        pack.position = vector(0, 1.96, 0.22)
        pack.geometry = shellGeometry([
            shell([(-0.62, 0.17, 0.08), (-0.55, 0.24, 0.11), (-0.20, 0.24, 0.11), (-0.06, 0.17, 0.08)], material("293E4E"), at: SIMD3(0, 0, 0.04)),
            shell([(-0.52, 0.20, 0.09), (-0.26, 0.20, 0.09)], material("A8B7BF"), at: SIMD3(0, 0, 0.07)),
            shell([(-0.42, 0.10, 0.01), (-0.39, 0.10, 0.01)], material("69F4E0", emissive: true), at: SIMD3(0, 0, 0.165)),
        ])
        body.addChildNode(pack)

        // Head, chin (local y 0.07) to crest (0.43): 0.36 m, about 1/7 of the 2.53 m figure.
        let helmet = material("D95238", unique: true)
        helmet.metalness.contents = 0.0
        helmet.roughness.contents = 0.7
        let visor = material("164F68", unique: true)
        visor.metalness.contents = 0.9
        visor.roughness.contents = 0.12
        headRig.position = vector(0, RunnerPose.neckHeight, 0)
        headRig.geometry = shellGeometry([
            shell([(0.07, 0.07, 0.07), (0.11, 0.12, 0.12), (0.20, 0.155, 0.16), (0.30, 0.15, 0.155)], skin, at: SIMD3(0, 0, -0.005)),
            shell([(0.17, 0.165, 0.175), (0.24, 0.185, 0.195), (0.33, 0.18, 0.19), (0.39, 0.14, 0.15), (0.42, 0.06, 0.07)], helmet, at: SIMD3(0, 0, 0.04)),
            shell([(0.235, 0.15, 0.13), (0.27, 0.165, 0.14), (0.30, 0.15, 0.13)], visor, at: SIMD3(0, 0, -0.055)),
            shell([(0.30, 0.025, 0.17), (0.38, 0.03, 0.19), (0.43, 0.025, 0.15)], material("FF643E"), at: SIMD3(0, 0, 0.03)),
            shell([(0.20, 0.20, 0.05), (0.28, 0.20, 0.05)], material("2C4659")),
            shell([(0.33, 0.07, 0.012), (0.35, 0.07, 0.012)], glow, at: SIMD3(0, 0, 0.235)),
        ])
        body.addChildNode(headRig)

        scarf.position = vector(0, 2.04, 0.16)
        scarf.geometry = shellGeometry([
            shell([(-0.48, 0.075, 0.02), (-0.30, 0.08, 0.022), (-0.05, 0.085, 0.025), (0.0, 0.08, 0.025)], material("17B8BB"), at: SIMD3(0.05, 0, 0)),
        ])
        body.addChildNode(scarf)

        // Arms: shoulder pivots wide of the chest for a heroic silhouette; elbow at −0.46, fingertips at y ~1.08.
        for (i, arm) in [leftArm, rightArm].enumerated() {
            let side = i == 0 ? -1.0 : 1.0
            arm.position = vector(side * 0.40, 1.98, 0)
            arm.geometry = shellGeometry([
                shell([(-0.44, 0.075, 0.075), (-0.30, 0.085, 0.09), (-0.12, 0.10, 0.105), (0.02, 0.105, 0.11)], sleeve),
                shell([(-0.14, 0.12, 0.13), (-0.04, 0.155, 0.16), (0.06, 0.14, 0.15), (0.11, 0.07, 0.08)], material(i == 0 ? "CBD8DD" : "597888"), at: SIMD3(side * 0.02, 0, 0)),
                shell([(-0.50, 0.07, 0.07), (-0.42, 0.085, 0.085)], material("243C4A")),
            ])
            let elbow = SCNNode()
            elbow.position = vector(0, -0.46, 0)
            elbow.geometry = shellGeometry([
                shell([(-0.30, 0.06, 0.065), (-0.14, 0.075, 0.08), (0.0, 0.07, 0.075)], material("213B4B")),
                shell([(-0.44, 0.045, 0.06), (-0.38, 0.06, 0.075), (-0.31, 0.055, 0.065)], material("192F40")),
                shell([(-0.20, 0.035, 0.01), (-0.17, 0.035, 0.01)], material("9ADBDC", emissive: true), at: SIMD3(0, 0, 0.075)),
            ])
            arm.addChildNode(elbow); forearms.append(elbow)
            body.addChildNode(arm)
        }

        // Legs: hip at 1.26 (half of 2.53), knee at 0.68, ankle at 0.12, sole at 0.
        for (i, leg) in [leftLeg, rightLeg].enumerated() {
            let side = i == 0 ? -1.0 : 1.0
            leg.position = vector(side * 0.15, 1.26, 0)
            leg.geometry = shellGeometry([
                shell([(-0.60, 0.085, 0.09), (-0.45, 0.10, 0.11), (-0.22, 0.125, 0.135), (-0.02, 0.135, 0.14), (0.06, 0.11, 0.12)], suit),
                shell([(-0.40, 0.09, 0.10), (-0.18, 0.11, 0.12)], material("4A6575"), at: SIMD3(0, 0, -0.04)),
                shell([(-0.63, 0.085, 0.09), (-0.53, 0.09, 0.095)], material("B3C4CB"), at: SIMD3(0, 0, -0.03)),
            ])
            let shin = SCNNode()
            shin.position = vector(0, -0.58, 0)
            shin.geometry = shellGeometry([
                shell([(-0.54, 0.06, 0.065), (-0.40, 0.075, 0.08), (-0.18, 0.09, 0.10), (0.0, 0.08, 0.09)], suit),
                shell([(-0.40, 0.07, 0.075), (-0.10, 0.085, 0.095)], material("435A6A"), at: SIMD3(0, 0, -0.03)),
            ])
            let ankle = SCNNode()
            ankle.position = vector(0, -0.56, 0)
            ankle.geometry = shellGeometry([
                shell([(-0.09, 0.105, 0.20), (-0.03, 0.11, 0.21), (0.04, 0.095, 0.16), (0.10, 0.07, 0.09)], material("D9E1E5"), at: SIMD3(0, 0, -0.07)),
                shell([(-0.12, 0.10, 0.20), (-0.085, 0.105, 0.205)], material("FF643E"), at: SIMD3(0, 0, -0.07)),
                shell([(-0.04, 0.06, 0.01), (-0.02, 0.06, 0.01)], material("A0ECEB", emissive: true), at: SIMD3(0, 0, 0.15)),
            ])
            shin.addChildNode(ankle); feet.append(ankle)
            leg.addChildNode(shin); shins.append(shin)
            body.addChildNode(leg)
        }

        let deck = box(0.73, 0.15, 1.7, "69B8C5", at: vector(0, 0.04, -0.05), radius: 0.2, into: boardNode)
        deck.name = "deck"
        deck.geometry?.firstMaterial = material("69B8C5", unique: true)
        box(0.22, 0.018, 1.45, "D9E1E5", at: vector(0, 0.125, -0.05), radius: 0.04, into: boardNode)
        for z in [-0.48, 0.43] {
            let thruster = cylinder(0.18, 0.08, "FFC94D", at: vector(0, -0.065, z), into: boardNode)
            thruster.geometry?.firstMaterial = material("FFC94D", emissive: true)
        }
        player.addChildNode(boardNode)
        boardNode.isHidden = true
        // Jetpack sits over the pack, which is 0.45 m higher than on the old short torso.
        for x in [-0.25, 0.25] {
            capsule(0.15, 0.59, "D9E1E5", at: vector(x, 1.70, 0.44), into: jetpackNode)
            cylinder(0.17, 0.12, "FF643E", at: vector(x, 1.48, 0.44), into: jetpackNode)
            let flame = sphere(0.13, "FFC94D", at: vector(x, 1.19, 0.44), scale: vector(1, 2.1, 1), into: jetpackNode)
            flame.geometry?.firstMaterial = material("FFC94D", emissive: true)
            exhaust.append(flame)
        }
        body.addChildNode(jetpackNode)
        jetpackNode.isHidden = true
        playerShadow.geometry = shadow(width: 2.2, length: 1.6).geometry
        playerShadow.renderingOrder = 5
        playerShadow.eulerAngles.x = scalar(-.pi / 2)
        playerShadow.castsShadow = false
        scene.rootNode.addChildNode(playerShadow)
    }
}
