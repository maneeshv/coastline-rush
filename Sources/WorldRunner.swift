import SceneKit

/// The runner: an about-7-heads figure built from lathe shells. Each rig bone carries one merged geometry
/// (one element per material), so the rig is 14 visible geometry nodes instead of ~120 primitives.
extension CoastalWorld {
    typealias Shell = (rings: [(Double, Double, Double)], at: SIMD3<Double>, material: SCNMaterial)

    func shell(_ rings: [(Double, Double, Double)], _ material: SCNMaterial, at offset: SIMD3<Double> = .zero) -> Shell {
        (rings, offset, material)
    }

    /// Lathe surface around the y axis: rings are (y, radiusX, radiusZ), ascending in y; 24 segments, analytic normals,
    /// optional flat end caps (planar UVs). End rings must keep a radius above 0: the normal divides by it. Without caps this is exactly the old `sculptedMesh` surface.
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
                add(0, section.0, 0, n, 0.5, 0.5)
                for column in 0...segments {
                    let angle = Double(column) / Double(segments) * .pi * 2
                    add(section.1 * cos(angle), section.0, section.2 * sin(angle), n, 0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5)
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

        // Torso on the pose root: pelvis, shirt, chest plate with emblem, belt, hip plates, collar, neck, chest light.
        let hipPlate: [(Double, Double, Double)] = [(1.16, 0.03, 0.08), (1.24, 0.045, 0.11), (1.34, 0.04, 0.10)]
        body.geometry = shellGeometry([
            shell([(1.14, 0.17, 0.13), (1.22, 0.22, 0.15), (1.32, 0.23, 0.16), (1.42, 0.21, 0.15)], suit),
            shell([(1.38, 0.20, 0.145), (1.50, 0.215, 0.15), (1.66, 0.25, 0.165), (1.82, 0.30, 0.18), (1.94, 0.33, 0.18), (2.00, 0.27, 0.15), (2.04, 0.12, 0.10)], shirt),
            shell([(1.66, 0.20, 0.15), (1.80, 0.25, 0.175), (1.92, 0.24, 0.17)], material("405B6A"), at: SIMD3(0, 0, -0.03)),
            shell([(1.69, 0.005, 0.006), (1.73, 0.05, 0.010), (1.77, 0.005, 0.006)], shirt, at: SIMD3(0, 0, -0.197)),
            shell([(1.36, 0.235, 0.17), (1.42, 0.24, 0.175)], material("6D899A")),
            shell(hipPlate, material("6D899A"), at: SIMD3(-0.21, 0, 0)),
            shell(hipPlate, material("6D899A"), at: SIMD3(0.21, 0, 0)),
            shell([(2.00, 0.15, 0.13), (2.08, 0.14, 0.12), (2.14, 0.115, 0.105)], material("17B8BB")),
            shell([(2.02, 0.09, 0.085), (2.18, 0.08, 0.08)], material("BD846C")),
            shell([(1.84, 0.08, 0.012), (1.87, 0.08, 0.012)], material("B2E3DB", emissive: true), at: SIMD3(0, 0, -0.205)),
        ])

        // Expedition pack, hung from its top strap so it can swing (follow-through): body, plate with seams, rails, glow spine, lid.
        let rail: [(Double, Double, Double)] = [(-0.55, 0.018, 0.03), (-0.18, 0.018, 0.03)]
        pack.position = vector(0, 1.96, 0.22)
        pack.geometry = shellGeometry([
            shell([(-0.62, 0.17, 0.08), (-0.55, 0.24, 0.11), (-0.20, 0.24, 0.11), (-0.06, 0.17, 0.08)], material("293E4E"), at: SIMD3(0, 0, 0.04)),
            shell([(-0.52, 0.20, 0.09), (-0.26, 0.20, 0.09)], material("A8B7BF"), at: SIMD3(0, 0, 0.07)),
            shell(rail, material("A8B7BF"), at: SIMD3(-0.235, 0, 0.06)),
            shell(rail, material("A8B7BF"), at: SIMD3(0.235, 0, 0.06)),
            shell([(-0.42, 0.10, 0.01), (-0.39, 0.10, 0.01)], material("69F4E0", emissive: true), at: SIMD3(0, 0, 0.165)),
            shell([(-0.50, 0.018, 0.008), (-0.28, 0.018, 0.008)], material("69F4E0", emissive: true), at: SIMD3(0, 0, 0.165)),
            shell([(-0.10, 0.22, 0.10), (-0.04, 0.20, 0.09), (-0.02, 0.15, 0.07)], material("172A3C"), at: SIMD3(0, 0, 0.05)),
            shell([(-0.47, 0.205, 0.093), (-0.46, 0.205, 0.093)], material("172A3C"), at: SIMD3(0, 0, 0.07)),
            shell([(-0.33, 0.205, 0.093), (-0.32, 0.205, 0.093)], material("172A3C"), at: SIMD3(0, 0, 0.07)),
        ])
        body.addChildNode(pack)

        // Head, chin (local y 0.07) to crest (0.46): 0.39 m, about 0.152 of the 2.56 m figure.
        let helmet = material("D95238", unique: true)
        helmet.metalness.contents = 0.0
        helmet.roughness.contents = 0.7
        let visor = material("164F68", unique: true)
        visor.metalness.contents = 0.9
        visor.roughness.contents = 0.12
        headRig.position = vector(0, RunnerPose.neckHeight, 0)
        headRig.geometry = shellGeometry([
            shell([(0.07, 0.074, 0.074), (0.11, 0.126, 0.126), (0.20, 0.163, 0.168), (0.30, 0.158, 0.163)], skin, at: SIMD3(0, 0, -0.005)),
            shell([(0.17, 0.178, 0.189), (0.24, 0.20, 0.21), (0.33, 0.194, 0.205), (0.37, 0.172, 0.183), (0.40, 0.13, 0.14), (0.42, 0.085, 0.095), (0.435, 0.04, 0.045), (0.44, 0.01, 0.012)], helmet, at: SIMD3(0, 0, 0.04)),
            shell([(0.235, 0.15, 0.13), (0.27, 0.165, 0.14), (0.30, 0.15, 0.13)], visor, at: SIMD3(0, 0, -0.055)),
            shell([(0.262, 0.168, 0.143), (0.272, 0.168, 0.143)], glow, at: SIMD3(0, 0, -0.057)),
            shell([(0.30, 0.03, 0.12), (0.37, 0.035, 0.165), (0.44, 0.03, 0.15), (0.46, 0.02, 0.10)], material("FF643E"), at: SIMD3(0, 0, 0.04)),
            shell([(0.12, 0.16, 0.05), (0.20, 0.20, 0.05), (0.28, 0.20, 0.05)], material("2C4659")),
            shell([(0.33, 0.07, 0.012), (0.35, 0.07, 0.012)], glow, at: SIMD3(0, 0, 0.245)),
        ])
        body.addChildNode(headRig)

        scarf.position = vector(0, 2.04, 0.16)
        scarf.geometry = shellGeometry([
            shell([(-0.48, 0.075, 0.02), (-0.30, 0.08, 0.022), (-0.05, 0.085, 0.025), (0.0, 0.08, 0.025)], material("17B8BB"), at: SIMD3(0.05, 0, 0)),
        ])
        body.addChildNode(scarf)

        // Arms: shoulder pivots wide of the chest for a heroic silhouette; elbow at −0.46, fingertips at y ~1.00.
        let rim = material("9ADBDC", emissive: true), cuffGrey = material("A6B8C4"), glove = material("192F40")
        for (i, arm) in [leftArm, rightArm].enumerated() {
            let side = i == 0 ? -1.0 : 1.0
            let plate = material(i == 0 ? "CBD8DD" : "597888")
            arm.position = vector(side * 0.40, 1.98, 0)
            arm.geometry = shellGeometry([
                shell([(-0.44, 0.075, 0.075), (-0.30, 0.085, 0.09), (-0.12, 0.10, 0.105), (0.02, 0.105, 0.11)], sleeve),
                shell([(-0.13, 0.105, 0.115), (-0.08, 0.13, 0.14), (-0.02, 0.137, 0.145), (0.04, 0.133, 0.14), (0.08, 0.11, 0.12), (0.105, 0.07, 0.08), (0.12, 0.02, 0.025)], plate, at: SIMD3(side * 0.02, 0, 0)),
                shell([(-0.03, 0.143, 0.151), (-0.015, 0.143, 0.151)], rim, at: SIMD3(side * 0.02, 0, 0)),
                shell([(-0.50, 0.07, 0.07), (-0.42, 0.085, 0.085)], material("243C4A")),
                shell([(-0.52, 0.05, 0.04), (-0.47, 0.065, 0.055), (-0.41, 0.05, 0.04)], plate, at: SIMD3(0, 0, 0.05)),
            ])
            let elbow = SCNNode()
            elbow.position = vector(0, -0.46, 0)
            elbow.geometry = shellGeometry([
                shell([(-0.30, 0.06, 0.065), (-0.14, 0.075, 0.08), (0.0, 0.07, 0.075)], material("213B4B")),
                shell([(-0.52, 0.01, 0.012), (-0.51, 0.03, 0.04), (-0.49, 0.045, 0.058), (-0.46, 0.052, 0.066), (-0.40, 0.06, 0.075), (-0.34, 0.058, 0.07), (-0.31, 0.055, 0.065)], glove),
                shell([(-0.33, 0.07, 0.085), (-0.29, 0.078, 0.092), (-0.27, 0.072, 0.086)], cuffGrey),
                shell([(-0.305, 0.081, 0.095), (-0.297, 0.081, 0.095)], rim),
                shell([(-0.20, 0.035, 0.01), (-0.17, 0.035, 0.01)], material("9ADBDC", emissive: true), at: SIMD3(0, 0, 0.075)),
            ])
            arm.addChildNode(elbow); forearms.append(elbow)
            body.addChildNode(arm)
        }

        // Legs: hip at 1.26 (half of 2.56), knee at 0.68, ankle at 0.12, sole at 0.
        let tread = material("233544"), shinGlow = material("A0ECEB", emissive: true)
        let lace: [(Double, Double, Double)] = [(-0.006, 0.05, 0.012), (0.006, 0.05, 0.012)]
        for (i, leg) in [leftLeg, rightLeg].enumerated() {
            let side = i == 0 ? -1.0 : 1.0
            leg.position = vector(side * 0.15, 1.26, 0)
            leg.geometry = shellGeometry([
                shell([(-0.60, 0.085, 0.09), (-0.45, 0.10, 0.11), (-0.22, 0.125, 0.135), (-0.02, 0.135, 0.14), (0.06, 0.11, 0.12)], suit),
                shell([(-0.40, 0.09, 0.10), (-0.18, 0.11, 0.12)], material("4A6575"), at: SIMD3(0, 0, -0.04)),
                shell([(-0.66, 0.06, 0.05), (-0.62, 0.08, 0.07), (-0.54, 0.08, 0.07), (-0.50, 0.06, 0.05)], material("B3C4CB"), at: SIMD3(0, 0, -0.07)),
            ])
            let shin = SCNNode()
            shin.position = vector(0, -0.58, 0)
            shin.geometry = shellGeometry([
                shell([(-0.54, 0.06, 0.065), (-0.40, 0.075, 0.08), (-0.18, 0.09, 0.10), (0.0, 0.08, 0.09)], suit),
                shell([(-0.40, 0.07, 0.075), (-0.10, 0.085, 0.095)], material("435A6A"), at: SIMD3(0, 0, -0.03)),
                shell([(-0.42, 0.055, 0.04), (-0.25, 0.07, 0.065), (-0.08, 0.06, 0.05)], suit, at: SIMD3(0, 0, 0.03)),
                shell([(-0.30, 0.012, 0.008), (-0.16, 0.012, 0.008)], shinGlow, at: SIMD3(0, 0, -0.122)),
                shell([(-0.30, 0.012, 0.008), (-0.20, 0.012, 0.008)], shinGlow, at: SIMD3(0, 0, 0.097)),
            ])
            let ankle = SCNNode()
            ankle.position = vector(0, -0.56, 0)
            ankle.geometry = shellGeometry([
                shell([(-0.09, 0.105, 0.20), (-0.03, 0.11, 0.21), (0.04, 0.095, 0.16), (0.10, 0.07, 0.09), (0.115, 0.04, 0.05), (0.12, 0.01, 0.012)], material("D9E1E5"), at: SIMD3(0, 0, -0.07)),
                shell([(-0.10, 0.113, 0.213), (-0.075, 0.111, 0.21)], material("FF643E"), at: SIMD3(0, 0, -0.07)),
                shell([(-0.12, 0.114, 0.217), (-0.10, 0.116, 0.219)], tread, at: SIMD3(0, 0, -0.07)),
                shell([(-0.075, 0.085, 0.07), (-0.02, 0.092, 0.08), (0.02, 0.07, 0.06)], tread, at: SIMD3(0, 0, -0.20)),
                shell(lace, tread, at: SIMD3(0, 0.05, -0.212)),
                shell(lace, tread, at: SIMD3(0, 0.07, -0.19)),
                shell(lace, tread, at: SIMD3(0, 0.09, -0.167)),
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

    /// Poses the rig for one frame. `amount` scales the run cycle (1 running on foot, a small idle otherwise);
    /// air, roll, landing and water layers blend over it. Hip sway and bob move `body`, never `player`.
    func poseRunner(gait: Double, amount: Double, waterMode: Bool, surfing: Bool, flying: Bool, landingAge: Double,
                    takeoffAge: Double, speed: Double, height: Double, time: Double, dt: Double) {
        let gaitPose = RunnerPose.limbs(phase: gait), torso = RunnerPose.torso(phase: gait)
        let air = airborneBlend, tuck = rollBlend
        // Knees give on landing (0.32 s); takeoff is a stretch, applied below.
        let crouch = landingAge < 0.32 ? sin(landingAge / 0.32 * .pi) : 0
        // Reduced Motion keeps the cycle but halves the hip sway, twist, tilt and squash, and drops the roll's spin.
        let gentle = reducedMotion ? 0.5 : 1.0
        for i in 0..<2 {
            let side = i == 0 ? -1.0 : 1.0
            var j = RunnerPose.mix(RunnerPose.rest, i == 0 ? gaitPose.left : gaitPose.right, amount)
            j = RunnerPose.mix(j, i == 0 ? RunnerPose.airLeft : RunnerPose.airRight, air)
            j = RunnerPose.mix(j, RunnerPose.tuck, tuck)
            if waterMode { j = RunnerPose.ride }
            j.thigh += crouch * 0.5; j.shin -= crouch * 1.0
            let leg = i == 0 ? leftLeg : rightLeg, arm = i == 0 ? leftArm : rightArm
            leg.eulerAngles = vector(j.thigh, 0, side * (waterMode ? RunnerPose.rideSplay : surfing ? 0.12 : 0.02))
            shins[i].eulerAngles.x = scalar(j.shin)
            feet[i].eulerAngles.x = scalar(j.foot)
            arm.eulerAngles = vector(j.arm - (flying ? 0.7 : 0), 0, side * (waterMode ? 0.18 : surfing ? 0.78 : 0.10 + air * 0.25 - tuck * 0.15))
            forearms[i].eulerAngles.x = scalar(j.forearm)
        }
        let bob = reducedMotion ? 0 : torso.bob * amount
        let sway = torso.sway * amount * gentle, yaw = torso.yaw * amount * gentle, tilt = torso.roll * amount * gentle
        let lean = waterMode ? RunnerPose.rideLean : flying ? 0.12 : torso.lean * amount - air * 0.08
        let lift = waterMode ? RunnerPose.rideDrop : bob - crouch * 0.14
        let squash = RunnerPose.volumeScale(1 + (RunnerPose.squash(landingAge: landingAge, takeoffAge: takeoffAge) - 1) * gentle)
        let ball = 1 + (RunnerPose.tuckScale - 1) * tuck
        // The spin only turns the body while it is tucked (the pitch below is weighted by `tuck`), and any remainder is
        // dropped once the tuck has released, so a long frame or a cancelled roll can never pitch the upright runner.
        rollSpin = tuck < 0.05 ? 0 : RunnerPose.advanceSpin(rollSpin, rolling: tuck > 0.5 && !reducedMotion, dt: dt)
        // The tuck spins about the ball's centre (body-space y), which rests tuckRadius above the deck. SceneKit's
        // `pivot` offsets after rotating, so the centre is compensated in `position`. With tuck 0 the centre is the soles.
        // The body sinks to the ball and the pitch only applies as the limbs are mostly folded (`fold`, a smoothstep of `tuck` that is 0 below 0.55 and 1 from 0.95),
        // so a half-unfurled runner during the blend never dips below the deck.
        let foldT = min(1, max(0, (tuck - 0.55) / 0.40))
        let fold = foldT * foldT * (3 - 2 * foldT)
        let centre = fold * RunnerPose.tuckCentre * squash.y * ball
        // A jump can cancel a roll mid-spin, which drops the target pitch by up to 2.4 rad in a frame or two; the shown pitch
        // follows it at no more than 30 rad/s (the roll itself turns at 7.9), so the unroll takes five or more frames.
        let pitchTarget = -lean * (1 - fold) - rollSpin * fold
        var gap = pitchTarget - shownPitch
        gap -= (gap / (2 * .pi)).rounded() * 2 * .pi   // a full turn is the same pose, so close the gap the short way
        shownPitch += max(-30 * dt, min(30 * dt, gap))
        shownPitch -= (shownPitch / (2 * .pi)).rounded() * 2 * .pi
        let pitch = shownPitch
        body.position = vector(sway, lift + (RunnerPose.tuckRadius - lift) * fold - centre * cos(pitch),
                               (waterMode ? RunnerPose.rideShift : 0) - centre * sin(pitch))
        body.eulerAngles = vector(pitch, yaw, tilt - bank * (waterMode ? 0.22 : 0.20))
        body.scale = vector(squash.x * ball, squash.y * ball, squash.z * ball)
        // Foot plant: the run cycle's bob and toe-down keys sink the stance boot up to 0.14 m into the deck, so lift the body
        // by however far the lower boot's sole (toe, middle, heel) is below it, with a smooth max over both feet.
        // The same lift keeps head, shoulders and hips off the deck while a cancelled roll is still unrolling.
        var plant = 0.0
        if !waterMode && !surfing && !flying {
            func smoothMax(_ a: Double, _ b: Double) -> Double { (a + b + ((a - b) * (a - b) + 0.0004).squareRoot()) / 2 }
            func lowest(_ node: SCNNode, _ points: [(Double, Double, Double)]) -> Double {
                points.map { Double(node.convertPosition(vector($0.0, $0.1, $0.2), to: player).y) }.min()!
            }
            let soles = [(0.0, -0.12, -0.285), (0, -0.12, -0.07), (0, -0.12, 0.145)]   // toe, middle, heel, 0.12 below the ankle
            var needed = smoothMax(smoothMax(-lowest(feet[0], soles), -lowest(feet[1], soles)), 0)
            // Reduced Motion keeps the body at the stride's peak need instead of bouncing with each footfall.
            if reducedMotion { needed = max(needed, plantHold - dt * 0.03); plantHold = needed }
            plant = needed * (1 - air) * (1 - fold)   // position-based: 0 unless a boot is under the deck, so no `amount` weight (a landing right after a roll has it near 0)
            var all = [-lowest(body, [(0, 2.55, 0), (0, 1.3, 0.3), (0, 1.3, -0.3), (0, 2.0, 0.35), (0, 2.0, -0.35)])]
            all += [-lowest(feet[0], soles), -lowest(feet[1], soles), -lowest(shins[0], [(0, 0, 0)]), -lowest(shins[1], [(0, 0, 0)])]
            let pitched = min(1, max(0, (abs(shownPitch) - 0.2) / 0.3))
            // Position-based, so it is 0 whenever the body is already clear of the deck (a full tuck rests above it).
            plant = max(plant, max(0, all.max()!) * (1 - fold * fold * fold * fold) * pitched)
            body.position.y += scalar(plant)
        }
        // Head stabilisation: counter 90% of the body's pitch, twist, tilt and half its bob; tuck the chin while rolling.
        let steady = 1 - tuck
        headRig.position.y = scalar(RunnerPose.neckHeight - bob * 0.5 * steady)
        headRig.eulerAngles = vector(lean * 0.9 * steady - tuck * 0.9, -yaw * 0.9,
                                     waterMode ? -bank * 0.12 : -(tilt - bank * 0.20) * 0.9)
        // Follow-through: the scarf streams back with speed and lags vertical motion; the pack swings on its strap.
        // The water drop is a constant offset, not motion, so entering or leaving water does not kick the springs.
        let rise = height + (waterMode ? 0 : lift + plant)
        let riseVelocity = RunnerPose.riseVelocity(from: lastRunnerLift, to: rise, dt: dt)
        lastRunnerLift = rise
        let flutter = reducedMotion ? 0 : sin(time * 9) * 0.05
        scarfSwing = RunnerPose.step(scarfSwing, target: 0.30 + 0.55 * min(1, speed / 40) - max(-0.4, min(0.4, riseVelocity * 0.05)) + flutter,
                                     dt: dt, stiffness: 60, damping: 7)
        scarf.eulerAngles.x = scalar(-scarfSwing.value)
        packSwing = RunnerPose.step(packSwing, target: max(-0.15, min(0.15, -riseVelocity * 0.03)), dt: dt, stiffness: 160, damping: 14)
        pack.eulerAngles.x = scalar(-packSwing.value)
    }
}
