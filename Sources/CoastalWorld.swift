import SceneKit
import CoreGraphics
#if os(iOS)
import UIKit
typealias CoastColor = UIColor
typealias CoastScalar = Float
#else
import AppKit
typealias CoastColor = NSColor
typealias CoastScalar = CGFloat
#endif

/// A procedural, reusable seaside set. Gameplay owns all movement and collisions.
final class CoastalWorld {
    let scene = SCNScene()
    let camera = SCNNode()
    /// Accessibility affects presentation only; collision and input timing remain identical.
    var reducedMotion = false
    var highContrastCues = false
    var previewMode: RunMode = .endless
    var previewStage: WorldStage = .harbor
    private(set) var renderedStage: WorldStage = .harbor
    private var journeyRoot = SCNNode()
    private var journeySections: [SCNNode] = []
    private var journeyAnimated: [SCNNode] = []
    private var harborScenery: [SCNNode] = []
    private(set) var worldSun: SCNLight?
    private(set) var worldAmbient: SCNLight?
    private(set) var worldSunNode: SCNNode?
    private let portal = SCNNode()
    private let warpVeil = SCNNode()
    private var portalSurface: SCNNode?
    private var portalLoops: [SCNNode] = []
    private var portalSpecks: [SCNNode] = []
    private var harborBackground: Any?
    private var worldEntryTime = -100.0
    private var wasPortalTransitioning = false
    /// Called once an incrementally built destination is ready for renderer resource preparation.
    var onWorldPrepared: ((SCNNode) -> Void)?
    private struct Destination {
        let root: SCNNode
        var sections: [SCNNode]
        let sky: CGImage?
        let finale: SCNNode
    }
    private var destinations: [WorldStage: Destination] = [:]
    private static let skyNames: [WorldStage: String] = [.orbit: "OrbitSky", .mars: "MarsSky", .verdant: "VerdantSky", .cryo: "CryoSky", .forge: "ForgeSky"]
    private(set) var preparationNode: SCNNode?
    private(set) var preparationRevision = 0
    private var warmedStages: Set<WorldStage> = []
    private(set) var qualityLevel = 1
    private let harborFinale = SCNNode()
    private var finaleRoot = SCNNode()
    private let alternateRouteRoot = SCNNode()
    private var alternateRouteSections: [SCNNode] = []
    private var stridePhase = 0.0
    private var lastStrideDistance = 0.0
    private var takeoffStarted = -100.0
    private var routeOffset = 0.0
    private var routeHeight = 0.0
    private var currentRouteSimulation: RunnerSimulation?

    private let setRoot = SCNNode()
    private let player = SCNNode()
    private let body = SCNNode()
    private let leftArm = SCNNode()
    private let rightArm = SCNNode()
    private let leftLeg = SCNNode()
    private let rightLeg = SCNNode()
    private var shins: [SCNNode] = []
    private var forearms: [SCNNode] = []
    private var feet: [SCNNode] = []
    private let headRig = SCNNode()
    private let landingRoot = SCNNode()
    private var landingRings: [SCNNode] = []
    private var landingSparks: [SCNNode] = []
    private let abilityAura = SCNNode()
    private var ghostCourier: SCNNode?
    private var currentRunDistance = 0.0
    private var landingStarted = -100.0
    private var previousHeight = 0.0
    private var airborneBlend = 0.0
    private var rollBlend = 0.0
    private let scarf = SCNNode()
    private let boardNode = SCNNode()
    private let jetpackNode = SCNNode()
    private let playerShadow = SCNNode()
    private let drone = SCNNode()
    private let menuProps = SCNNode()
    private let waterMenuProps = SCNNode()
    private var segments: [SCNNode] = []
    private var waterGlints: [SCNNode] = []
    private var gulls: [SCNNode] = []
    private var exhaust: [SCNNode] = []
    private var rotorNodes: [SCNNode] = []
    private var liveNodes: [Int: SCNNode] = [:]
    private var liveKinds: [Int: String] = [:]
    private var pools: [String: [SCNNode]] = [:]
    private var materials: [String: SCNMaterial] = [:]
    var surfaceDetailEnabled = true
    private var clothing: [SCNMaterial] = []
    private var selectedCharacter = ""
    private var selectedBoard = ""
    private var aspect = 0.5
    private let water = SCNNode()
    private let ski = SCNNode()
    private let wake = SCNNode()
    private var spray: [SCNNode] = []
    private var roadways: [SCNNode] = []
    private var lastWaterMode = false
    private var lastTime = 0.0
    private var trickStartedAt: Double?
    private var bank = 0.0
    private var previousLateral = 0.0
    var textureCache: [String: CGImage] = [:]
    var geometryCache: [String: SCNGeometry] = [:]
    private let assetsURL: URL?

    private let cream = "D9E1E5"
    private let coral = "FF643E"
    private let mint = "17B8BB"
    private let ink = "101F31"
    private let gold = "FFC94D"
    private let track = "243643"
    private let segmentLength = 24.0

    init(assetsURL: URL? = nil) {
        self.assetsURL = assetsURL
        scene.background.contents = color("344465")
        scene.rootNode.addChildNode(setRoot)
        makeLighting()
        makeCamera()
        let beforeScenery = Set(scene.rootNode.childNodes.map { ObjectIdentifier($0) })
        makeOceanAndHorizon()
        harborScenery = scene.rootNode.childNodes.filter { !beforeScenery.contains(ObjectIdentifier($0)) }
        harborBackground = scene.background.contents
        scene.rootNode.addChildNode(journeyRoot)
        makePortal()
        for index in 0..<8 {
            let section = makeSection(index: index)
            section.position.z = scalar(-Double(index) * segmentLength)
            setRoot.addChildNode(section)
            segments.append(section)
        }
        withoutSurfaceDetail { makePlayer() }
        makeMotionEffects()
        makeDrone()
        withoutSurfaceDetail { makeJetSki() }
        makeMenuProps()
        makeFinale(stage: .harbor, into: harborFinale)
        scene.rootNode.addChildNode(harborFinale)
        finaleRoot = harborFinale
        makeAlternateRoute()
        applyLook(.harbor)
    }

    func resize(aspect: Double) {
        self.aspect = max(0.3, aspect)
        camera.camera?.fieldOfView = aspect < 0.8 ? 66 : 58
    }

    func applyQuality(_ quality: RenderQuality) {
        qualityLevel = quality == .performance ? 0 : quality == .ultra ? 2 : 1
        worldSun?.shadowMapSize = CGSize(width: qualityLevel == 0 ? 1024 : 2048, height: qualityLevel == 0 ? 1024 : 2048)
        worldSun?.shadowSampleCount = qualityLevel == 0 ? 2 : qualityLevel == 1 ? 4 : 8
        camera.camera?.screenSpaceAmbientOcclusionIntensity = qualityLevel == 0 ? 0 : qualityLevel == 1 ? 0.4 : 0.7
        camera.camera?.zFar = qualityLevel == 0 ? 280 : 380
        for (index, node) in portalSpecks.enumerated() { node.isHidden = qualityLevel == 0 && index % 2 == 1 }
        for (index, node) in spray.enumerated() { node.isHidden = qualityLevel == 0 && index % 2 == 1 }
        for (index, node) in landingSparks.enumerated() { node.isHidden = qualityLevel == 0 && index % 2 == 1 }
        applyLook(renderedStage)
    }

    func updateGhost(sample: GhostSample?) {
        guard let sample else { ghostCourier?.isHidden = true; return }
        if ghostCourier == nil {
            let ghost = player.clone() // shares the player's flat (detail-free) materials
            ghost.name = "personalGhost"
            ghost.opacity = 0.24
            ghost.enumerateChildNodes { node, _ in node.castsShadow = false }
            scene.rootNode.addChildNode(ghost)
            ghostCourier = ghost
        }
        guard let ghost = ghostCourier else { return }
        let separation = sample.distance - currentRunDistance
        ghost.isHidden = separation > 100 || separation < -7
        let route = currentRouteSimulation?.routeTransform(atAheadDistance: separation)
        ghost.position = vector(sample.x * 2.6 + (route?.lateralOffset ?? 0), sample.y + (route?.elevation ?? 0), -separation)
        ghost.scale = vector(1, sample.roll ? 0.45 : 1, 1)
        ghost.eulerAngles = SCNVector3Zero
        for (name, sign) in [("leftLeg", 1.0), ("rightLeg", -1.0), ("leftArm", -0.8), ("rightArm", 0.8)] {
            ghost.childNode(withName: name, recursively: true)?.eulerAngles.x = scalar(sample.y > 0.15 ? sign * 0.45 : sin(sample.time * 13) * sign * 0.7)
        }
        ghost.childNode(withName: "jetSki", recursively: true)?.isHidden = !lastWaterMode
        ghost.childNode(withName: "artifactAura", recursively: true)?.isHidden = true
    }

    func update(simulation: RunnerSimulation, character: String, board: String, time: Double) {
        currentRunDistance = simulation.distance
        currentRouteSimulation = simulation
        let isMenu = simulation.phase == .menu
        let running = simulation.phase == .running
        let activeMode = isMenu ? previewMode : simulation.mode
        let waterMode = activeMode == .jetSki || (!isMenu && simulation.isWaterTraversal)
        let stage: WorldStage = activeMode == .odyssey ? (isMenu ? previewStage : simulation.worldStage) : .harbor
        if stage != renderedStage {
            configureWorld(stage)
            if !isMenu && wasPortalTransitioning { worldEntryTime = time }
        }
        let route = isMenu ? (lateralOffset: 0.0, elevation: 0.0) : simulation.routeTransform(atAheadDistance: 0)
        routeOffset = route.lateralOffset
        routeHeight = route.elevation
        let offworld = stage != .harbor
        setRoot.isHidden = offworld
        harborScenery.forEach { $0.isHidden = offworld }
        journeyRoot.isHidden = !offworld
        let boosting = simulation.isBoosting && running
        let dt = min(0.05, max(0, time - lastTime))
        lastTime = time
        let steeringVelocity = (simulation.lateral - previousLateral) / max(0.01, dt)
        let routeAhead = isMenu ? route : simulation.routeTransform(atAheadDistance: 14)
        let curveLean = (route.lateralOffset - routeAhead.lateralOffset) * 0.05
        let desiredBank = max(-0.65, min(0.65, (waterMode ? -simulation.lateralVelocity * 0.12 : -steeringVelocity * 0.08) + curveLean))
        bank += (desiredBank - bank) * min(1, dt * 12)
        previousLateral = simulation.lateral
        if waterMode != lastWaterMode {
            lastWaterMode = waterMode
            roadways.forEach { $0.isHidden = waterMode }
            for (index, particle) in spray.enumerated() { particle.isHidden = !waterMode || (qualityLevel == 0 && index % 2 == 1) }
        }
        let travel = isMenu ? time * 1.5 : simulation.distance
        if !offworld {
            water.position.y = scalar(waterMode ? -0.13 : -1.1)
            water.geometry?.firstMaterial?.normal.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(30, 50, 1), SCNMatrix4MakeTranslation(scalar(time * 0.004), scalar(time * 0.013), 0))
            for (index, section) in segments.enumerated() {
                let z = travel.truncatingRemainder(dividingBy: segmentLength) - Double(index) * segmentLength + 12
                placeRouteSection(section, centerZ: z - 12, localCenterZ: -12, length: 24,
                                  simulation: simulation, menu: isMenu)
            }
        }
        menuProps.isHidden = !isMenu || waterMode || offworld
        waterMenuProps.isHidden = !isMenu || !waterMode
        menuProps.position.z = scalar(sin(time * 0.3) * 0.4)
        for (index, node) in waterGlints.enumerated() where !offworld {
            node.opacity = 0.15 + 0.16 * (sin(time * 0.65 + Double(index)) + 1)
        }
        for (index, gull) in gulls.enumerated() where !offworld {
            gull.position.x = scalar(sin(time * 0.18 + Double(index) * 2) * 19)
            gull.position.y = scalar(10 + sin(time * 0.4 + Double(index)) * 1.5)
            gull.eulerAngles.z = scalar(sin(time * 0.5 + Double(index)) * 0.15)
        }
        if selectedCharacter != character {
            selectedCharacter = character
            let tint = character == "sana" ? "EFB84D" : character == "rio" ? "79BACC" : coral
            clothing.forEach { $0.diffuse.contents = color(tint) }
        }
        if selectedBoard != board {
            selectedBoard = board
            let tint = board == "sunset" ? coral : board == "mint" ? mint : "69B8C5"
            boardNode.childNode(withName: "deck", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = color(tint)
        }

        let flying = simulation.activePowerUps[.jetpack, default: 0] > 0
        let surfing = simulation.boardTime > 0
        let roll = simulation.isRolling && !isMenu
        // Integrate travelled stride instead of elapsed * speed: acceleration can never snap a pose.
        let travelled = simulation.distance - lastStrideDistance
        if travelled < 0 || travelled > 100 { stridePhase = 0 }
        else if running { stridePhase += travelled / max(1, simulation.speed) * (12 + min(60, simulation.speed) * 0.13) }
        lastStrideDistance = simulation.distance
        let gait = isMenu ? time * 2.8 : stridePhase
        let motion = reducedMotion ? 0.0 : 1.0
        let portalJump = simulation.isPortalTransitioning && !reducedMotion ? sin(simulation.portalTransitionProgress * .pi) * 3.2 : 0
        let height = (isMenu ? 0 : simulation.height) + portalJump
        let bob = reducedMotion ? 0 : waterMode ? sin(time * 9) * 0.06 : running && height < 0.1 && !roll && !surfing ? abs(sin(gait)) * 0.075 : sin(time * 2) * 0.025
        // Stage the portrait menu hero above the mode picker, while the live camera remains unchanged.
        let menuDepth = isMenu && aspect < 0.8 ? -8.0 : 0.45
        let menuScale = isMenu && aspect < 0.8 ? 1.4 : 1.0
        player.scale = vector(menuScale, menuScale, menuScale)
        player.position = vector(isMenu ? -0.35 : simulation.lateral * 2.6 + routeOffset, height + routeHeight + bob + (waterMode ? 0.38 : surfing ? 0.18 : 0), isMenu ? menuDepth : simulation.isPortalTransitioning && !reducedMotion ? -simulation.portalTransitionProgress * 12 : 0)
        player.eulerAngles.y = scalar(isMenu ? -0.35 : waterMode ? bank * 0.35 : -Double(simulation.lane) * 0.035)
        if simulation.isTricking && trickStartedAt == nil { trickStartedAt = time }
        if !simulation.isTricking { trickStartedAt = nil }
        let trickProgress = min(1, max(0, (time - (trickStartedAt ?? time)) / 0.65))
        let trickRoll = trickStartedAt == nil || reducedMotion ? 0 : .pi * (1 - cos(.pi * trickProgress))
        player.eulerAngles.z = scalar(waterMode ? bank + trickRoll : bank * 0.15)
        player.eulerAngles.x = scalar(waterMode ? simulation.height > 0.2 ? -0.14 : sin(time * 6) * 0.025 : 0)
        player.opacity = simulation.invulnerableTime > 0 ? (reducedMotion ? 0.7 : 0.76 + sin(time * 7) * 0.16) : 1
        if running && previousHeight < 0.02 && height >= 0.02 { takeoffStarted = time }
        let airTarget = height > 0.12 && !flying ? 1.0 : 0.0
        airborneBlend += (airTarget - airborneBlend) * min(1, dt * 14)
        rollBlend += ((roll ? 1.0 : 0.0) - rollBlend) * min(1, dt * 20)
        if running && previousHeight > 0.13 && height <= 0.13 && !simulation.isPortalTransitioning {
            landingStarted = time
            landingRoot.position = vector(Double(player.position.x), routeHeight + (waterMode ? 0.02 : 0.065), Double(player.position.z))
        }
        previousHeight = height
        let landingAge = max(0, time - landingStarted)
        let takeoffAge = max(0, time - takeoffStarted)
        let launchCompression = takeoffAge < 0.10 ? (1 - takeoffAge / 0.10) * 0.10 : 0
        let compression = (landingAge < 0.32 ? sin(landingAge / 0.32 * .pi) * 0.22 : 0) + launchCompression
        let stride = (running && !waterMode && !surfing && !flying) ? 0.76 * (1 - airborneBlend) * (1 - rollBlend) : isMenu ? 0.045 : 0.08
        let gaitWave = sin(gait)
        body.position.y = scalar(rollBlend * 0.38 - (waterMode ? 0.32 : 0) - compression)
        body.eulerAngles.x = scalar(-rollBlend * .pi / 2 + (waterMode ? -0.38 : flying ? -0.12 : 0.055 + airborneBlend * 0.10))
        body.eulerAngles.y = scalar(gaitWave * stride * 0.12)
        body.eulerAngles.z = scalar(waterMode ? -bank * 0.22 : -bank * 0.20)
        body.scale = vector(1, 1 - rollBlend * 0.24 - compression * 0.12, 1)
        headRig.eulerAngles = vector(-airborneBlend * 0.09, -gaitWave * stride * 0.10, waterMode ? -bank * 0.12 : 0)
        for (i, leg) in [leftLeg, rightLeg].enumerated() {
            let cycle = gait + Double(i) * .pi
            let swing = sin(cycle)
            leg.eulerAngles.x = scalar(waterMode ? 0.8 : swing * stride + airborneBlend * (i == 0 ? 0.78 : -0.28) + rollBlend * 0.55 + compression * 1.4)
            leg.eulerAngles.z = scalar((i == 0 ? -1.0 : 1.0) * (surfing ? 0.12 : 0.02))
            if i < shins.count {
                // Heel lift happens on each leg's own recovery half-cycle, not both knees together.
                shins[i].eulerAngles.x = scalar(waterMode ? -1.2 : -max(0, -swing) * stride * 1.1 - airborneBlend * 0.85 - rollBlend * 1.1 - compression * 2.0)
            }
            if i < feet.count { feet[i].eulerAngles.x = scalar(waterMode ? 0.28 : max(0, swing) * stride * 0.25 + airborneBlend * 0.2) }
        }
        for (i, arm) in [leftArm, rightArm].enumerated() {
            let swing = sin(gait + Double(i) * .pi)
            arm.eulerAngles.x = scalar(waterMode ? 1.0 : -swing * stride * 0.72 - (flying ? 0.7 : 0.12) + airborneBlend * 0.58 + rollBlend * 1.05)
            arm.eulerAngles.z = scalar((i == 0 ? -1.0 : 1.0) * (waterMode ? 0.18 : surfing ? 0.78 : 0.12 + airborneBlend * 0.25))
            if i < forearms.count { forearms[i].eulerAngles.x = scalar(waterMode ? -0.22 : -0.48 - max(0, swing) * stride * 0.35 - airborneBlend * 0.48 - rollBlend * 0.4) }
        }
        updateMotionEffects(simulation: simulation, time: time, waterMode: waterMode)
        ski.isHidden = !waterMode
        wake.isHidden = !waterMode
        ski.position.y = scalar(-0.35)
        ski.eulerAngles.x = scalar(simulation.isBraking ? 0.12 : boosting ? -0.08 : 0)
        for (index, particle) in spray.enumerated() where waterMode {
            let age = (time * (boosting ? 1.8 : 1.1) + Double(index) / Double(spray.count)).truncatingRemainder(dividingBy: 1)
            let side = index % 2 == 0 ? -1.0 : 1.0
            particle.position = vector(Double(player.position.x) + side * (0.43 + age * 1.5) + bank * age * 4, 0.05 + sin(age * .pi) * (boosting ? 0.7 : 0.35) + abs(bank) * age, Double(player.position.z) + 0.8 + age * (boosting ? 10 : 7))
            particle.scale = vector(0.1 + age * 0.4, 0.1 + age * 0.6, 1)
            particle.opacity = waterMode && height < 0.5 ? (1 - age) * 0.75 : 0
        }
        wake.position = vector(Double(player.position.x), routeHeight + 0.015, Double(player.position.z) + 4.1)
        wake.eulerAngles.z = scalar(-bank * 0.55)
        wake.scale.x = scalar(1 + abs(bank) * 0.65)
        wake.opacity = height > 0.5 ? 0.25 : 0.72
        scarf.eulerAngles.x = scalar(0.13 + sin(time * 8) * 0.08)
        boardNode.isHidden = !surfing || waterMode
        boardNode.eulerAngles.z = scalar(reducedMotion ? 0 : sin(time * 4) * 0.055)
        jetpackNode.isHidden = !flying
        for (index, flame) in exhaust.enumerated() where flying {
            flame.scale = vector(1, 0.6 + abs(sin(time * 24 + Double(index))) * 0.7, 1)
        }
        playerShadow.position = vector(Double(player.position.x), routeHeight + 0.055, Double(player.position.z))
        playerShadow.isHidden = waterMode
        let shadowScale = max(0.35, 1 - height * 0.055)
        playerShadow.scale = vector(shadowScale, 1, shadowScale)
        playerShadow.opacity = flying ? 0.18 : 0.92
        drone.position = vector(sin(time * 0.9) * 0.8, 2.5 + sin(time * 2) * 0.16, running ? 4.5 : 5.8)
        drone.eulerAngles.z = scalar(sin(time * 0.9) * 0.12)
        drone.isHidden = isMenu || waterMode || offworld || (simulation.distance > 130 && simulation.invulnerableTime <= 0)
        if !drone.isHidden { for rotor in rotorNodes { rotor.eulerAngles.y = scalar(time * 45) } }

        let flightLift = reducedMotion ? 0 : flying ? min(height * 0.44, 3.0) : min(height * 0.12, 0.35)
        let desiredX = isMenu ? 0.35 : simulation.lateral * 0.3 + routeOffset
        let cameraHeight = waterMode ? 5.4 : 6.1
        camera.position = vector(desiredX, cameraHeight + routeHeight + flightLift + (boosting ? sin(time * 30) * 0.025 * motion : 0), aspect < 0.8 ? 11.8 : 10.4)
        let cameraRoute = isMenu ? route : simulation.routeTransform(atAheadDistance: 14)
        camera.look(at: vector((desiredX - routeOffset) * 0.25 + cameraRoute.lateralOffset, 0.5 + cameraRoute.elevation + flightLift, -14))
        camera.camera?.fieldOfView = (aspect < 0.8 ? 66 : 58) + (boosting && !reducedMotion ? 5 : 0)
        let visibilityDistance = simulation.mode == .odyssey ? min(200, max(135, simulation.speed * 3.2)) : 135
        syncEntities(simulation.entities, time: time, menu: isMenu || simulation.isPortalTransitioning,
                     visibilityDistance: visibilityDistance, simulation: simulation)
        updateAlternateRoute(simulation: simulation, menu: isMenu, travel: travel)
        updateFinale(simulation: simulation, time: time, menu: isMenu)
        updateJourney(simulation: simulation, time: time, menu: isMenu, travel: travel)
        if activeMode == .odyssey && !isMenu && running { prewarmNextDestination(after: stage) }
        wasPortalTransitioning = simulation.isPortalTransitioning
    }

    // MARK: - Shared art helpers

    func color(_ hex: String, alpha: Double = 1) -> CoastColor {
        let value = UInt64(hex, radix: 16) ?? 0xFFFFFF
        return CoastColor(red: CGFloat((value >> 16) & 255) / 255,
                          green: CGFloat((value >> 8) & 255) / 255,
                          blue: CGFloat(value & 255) / 255, alpha: CGFloat(alpha))
    }

    func material(_ hex: String, emissive: Bool = false, unique: Bool = false) -> SCNMaterial {
        let detailed = !emissive && surfaceDetailEnabled
        let key = hex + (emissive ? "-light" : "") + (detailed || emissive ? "" : "-flat")
        if !unique, let cached = materials[key] { return cached }
        let result = SCNMaterial()
        result.diffuse.contents = color(hex)
        result.lightingModel = .physicallyBased
        result.roughness.contents = 0.64
        result.metalness.contents = 0.02
        if ["D9E1E5", "101F31", "FFC94D", "69B8C5", "17B8BB"].contains(hex) {
            result.metalness.contents = 0.55
            result.roughness.contents = 0.27
        }
        if emissive { result.emission.contents = color(hex); result.emission.intensity = 1.8 }
        if detailed { applySurfaceDetail(to: result) }
        if !unique { materials[key] = result }
        return result
    }

    private func vector(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 { SCNVector3(x, y, z) }
    private func scalar(_ value: Double) -> CoastScalar { CoastScalar(value) }

    /// Original smooth surface mesh for tailored suit panels and bracers, articulated by the rig.
    private func sculptedMesh(rings: [(Double, Double, Double)], tint: String) -> SCNNode {
        let segments = 24
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uv: [CGPoint] = []
        var indices: [Int32] = []
        for (row, section) in rings.enumerated() {
            let before = rings[max(0, row - 1)], after = rings[min(rings.count - 1, row + 1)]
            let dy = max(0.01, after.0 - before.0)
            for column in 0...segments {
                let angle = Double(column) / Double(segments) * .pi * 2
                let c = cos(angle), s = sin(angle)
                vertices.append(vector(section.1 * c, section.0, section.2 * s))
                let n = simd_normalize(SIMD3<Float>(Float(c / section.1), Float(-((after.1 - before.1) * c * c / section.1 + (after.2 - before.2) * s * s / section.2) / dy), Float(s / section.2)))
                normals.append(vector(Double(n.x), Double(n.y), Double(n.z)))
                uv.append(CGPoint(x: Double(column) / Double(segments), y: Double(row) / Double(max(1, rings.count - 1))))
                if row < rings.count - 1 && column < segments {
                    let a = Int32(row * (segments + 1) + column), b = a + Int32(segments + 1)
                    indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.firstMaterial = material(tint)
        return SCNNode(geometry: geometry)
    }

    private func makeMotionEffects() {
        scene.rootNode.addChildNode(landingRoot)
        for i in 0..<3 {
            let ripple = ring(0.55, tube: 0.018 + Double(i) * 0.008, tint: i == 1 ? "FFCD92" : "85E2EC", at: vector(0, Double(i) * 0.018, 0), into: landingRoot, glow: true)
            ripple.castsShadow = false; landingRings.append(ripple)
        }
        for i in 0..<18 {
            let speck = box(0.03, 0.03, 0.14, i % 2 == 0 ? "FFD9B0" : "AAE6F4", radius: 0, into: landingRoot)
            speck.geometry?.firstMaterial = material(i % 2 == 0 ? "FFD9B0" : "AAE6F4", emissive: true)
            speck.castsShadow = false; landingSparks.append(speck)
        }
        for i in 0..<3 {
            let orbit = ring(0.8 + Double(i) * 0.10, tube: 0.017, tint: "8CF3ED", at: vector(0, 1.15, 0), into: abilityAura, glow: true)
            orbit.eulerAngles = vector(Double(i) * .pi / 3, 0, Double(i) * .pi / 3)
            orbit.castsShadow = false
        }
        abilityAura.name = "artifactAura"
        player.addChildNode(abilityAura)
        abilityAura.isHidden = true
        landingRoot.isHidden = true
    }

    private func updateMotionEffects(simulation: RunnerSimulation, time: Double, waterMode: Bool) {
        let age = time - landingStarted
        landingRoot.isHidden = reducedMotion || age < 0 || age > 0.55
        if !landingRoot.isHidden {
            for (i, ripple) in landingRings.enumerated() {
                let progress = max(0, age - Double(i) * 0.035) / 0.55
                let radius = 0.6 + progress * (waterMode ? 4 : 2)
                ripple.scale = vector(radius, 1, radius)
                ripple.opacity = max(0, 1 - progress) * 0.55
            }
            for (i, spark) in landingSparks.enumerated() {
                let angle = Double(i) / Double(landingSparks.count) * .pi * 2
                let spread = 0.25 + age * (2.2 + Double(i % 4) * 0.55)
                spark.position = vector(cos(angle) * spread, max(0, sin(age / 0.55 * .pi)) * (waterMode ? 0.6 : 0.35), sin(angle) * spread)
                spark.eulerAngles = vector(0, -angle, angle)
                spark.opacity = max(0, 1 - age / 0.55)
            }
        }
        abilityAura.isHidden = !simulation.isAbilityActive
        abilityAura.eulerAngles.y = scalar(reducedMotion ? 0 : time * 2)
        abilityAura.opacity = reducedMotion ? 0.55 : 0.52 + sin(time * 4) * 0.09
    }

    @discardableResult private func box(_ w: Double, _ h: Double, _ d: Double, _ hex: String,
                                       at position: SCNVector3 = SCNVector3Zero,
                                       radius: Double = 0.025, into parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNBox(width: w, height: h, length: d, chamferRadius: radius > 0.04 ? min(radius, min(w, min(h, d)) * 0.45) : 0)
        shape.chamferSegmentCount = radius > 0.1 ? 3 : 1
        shape.firstMaterial = material(hex)
        let node = SCNNode(geometry: shape)
        node.position = position
        parent?.addChildNode(node)
        return node
    }

    @discardableResult private func sphere(_ radius: Double, _ hex: String, at position: SCNVector3,
                                          scale: SCNVector3 = SCNVector3(1, 1, 1), into parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNSphere(radius: radius)
        shape.segmentCount = 24
        shape.firstMaterial = material(hex)
        let node = SCNNode(geometry: shape)
        node.position = position
        node.scale = scale
        parent?.addChildNode(node)
        return node
    }

    @discardableResult private func cylinder(_ radius: Double, _ height: Double, _ hex: String,
                                            at position: SCNVector3, into parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNCylinder(radius: radius, height: height)
        shape.radialSegmentCount = 20
        shape.firstMaterial = material(hex)
        let node = SCNNode(geometry: shape)
        node.position = position
        parent?.addChildNode(node)
        return node
    }

    @discardableResult private func capsule(_ radius: Double, _ height: Double, _ hex: String,
                                           at position: SCNVector3, into parent: SCNNode? = nil) -> SCNNode {
        let shape = SCNCapsule(capRadius: radius, height: height)
        shape.radialSegmentCount = 20
        shape.capSegmentCount = 8
        shape.firstMaterial = material(hex)
        let node = SCNNode(geometry: shape)
        node.position = position
        parent?.addChildNode(node)
        return node
    }

    private func shadow(width: Double, length: Double) -> SCNNode {
        let geometry = SCNPlane(width: width, height: length)
        let mat = SCNMaterial()
        mat.diffuse.contents = shadowTexture()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        geometry.firstMaterial = mat
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = scalar(-.pi / 2)
        node.castsShadow = false
        return node
    }

    private func shadowTexture() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                                      bytesPerRow: 256, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [color("081421", alpha: 0.85).cgColor, color("163E49", alpha: 0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 7,
                                       endCenter: CGPoint(x: 32, y: 32), endRadius: 31, options: [])
        }
        return context.makeImage()
    }

    // MARK: - Light, sea and distant landmarks

    private func skyGradient() -> CGImage? {
        image(width: 8, height: 512) { ctx in
            let colors = [color("DF997D").cgColor, color("59749A").cgColor, color("142B50").cgColor, color("0C1933").cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.28, 0.66, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        }
    }

    private func makeLighting() {
        scene.lightingEnvironment.contents = loadAsset("HarborSky") ?? environmentMap()
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        worldAmbient = ambient.light
        scene.rootNode.addChildNode(ambient)
        let sunlight = SCNNode()
        sunlight.light = SCNLight()
        sunlight.light?.type = .directional
        worldSun = sunlight.light
        worldSunNode = sunlight
        sunlight.light?.castsShadow = true
        sunlight.light?.shadowColor = color("091529", alpha: 0.9)
        sunlight.light?.shadowRadius = 3
        sunlight.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sunlight.light?.shadowSampleCount = 8
        sunlight.light?.orthographicScale = 34
        sunlight.light?.shadowBias = 0.01
        sunlight.light?.zNear = 0.5
        sunlight.light?.zFar = 95
        scene.rootNode.addChildNode(sunlight)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = color("72B8F8")
        rim.light?.intensity = 310
        rim.eulerAngles = vector(-0.45, 2.5, 0)
        scene.rootNode.addChildNode(rim)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.color = color("68DBFF")
        fill.light?.intensity = 170
        fill.light?.attenuationStartDistance = 4
        fill.light?.attenuationEndDistance = 17
        fill.position = vector(0, 5, 5)
        scene.rootNode.addChildNode(fill)
    }

    private func makeCamera() {
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.15
        camera.camera?.zFar = 380
        camera.camera?.fieldOfView = 66
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.7
        camera.camera?.screenSpaceAmbientOcclusionRadius = 2
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.03
        scene.rootNode.addChildNode(camera)
    }

    private func makeOceanAndHorizon() {
        scene.background.contents = loadAsset("HarborSky") ?? skyPanorama()
        let plane = SCNPlane(width: 500, height: 420)
        plane.widthSegmentCount = 120
        plane.heightSegmentCount = 100
        let oceanMat = material("126479", unique: true)
        oceanMat.roughness.contents = 0.18
        oceanMat.metalness.contents = 0.65
        oceanMat.normal.contents = texture("water-normal")
        oceanMat.normal.intensity = 0.55
        oceanMat.normal.wrapS = .repeat
        oceanMat.normal.wrapT = .repeat
        oceanMat.shaderModifiers = [.surface: """
        #pragma body
        float2 uv = _surface.diffuseTexcoord * 240.0;
        float ripple = sin(uv.x * 1.7 + uv.y * 2.2 + scn_frame.time * 1.4) * sin(uv.y * 2.8 - scn_frame.time * 0.7);
        _surface.normal = normalize(_surface.normal + _surface.tangent * ripple * 0.07 + _surface.bitangent * cos(uv.x * 1.6 + scn_frame.time) * 0.04);
        _surface.diffuse.rgb *= 0.82 + 0.18 * ripple;
        _surface.roughness = 0.14 + 0.1 * (ripple * 0.5 + 0.5);
        """]
        plane.firstMaterial = oceanMat
        water.geometry = plane
        water.eulerAngles.x = scalar(-.pi / 2)
        water.position = vector(0, -1.1, -105)
        water.castsShadow = false
        scene.rootNode.addChildNode(water)
        // The photographic dusk panorama stays visible between the distant towers.
        // Far skyline, with window atlases, gives landscape screens a populated horizon.
        for i in 0..<15 {
            let x = -110 + Double(i) * 15.7
            if abs(x) < 15 { continue }
            let tower = box(5 + Double(i % 3), 8 + Double((i * 7) % 24), 6, "213449", at: vector(x, Double(8 + (i * 7) % 24) / 2 - 1, -150 - Double(i % 4) * 7), radius: 0.08, into: scene.rootNode)
            tower.geometry?.firstMaterial = facadeMaterial(variant: i)
            tower.castsShadow = false
        }
        makeLighthouse(at: vector(-27, -0.7, -78))
        makeBoat(at: vector(20, -0.9, -40), tint: coral, size: 1.4)
        makeBoat(at: vector(-30, -0.9, -62), tint: mint, size: 1.2)
        makeBoat(at: vector(43, -0.9, -90), tint: cream, size: 2.0)
        for i in 0..<2 { makeCrane(at: vector(i % 2 == 0 ? 29 : -34, 0, -65 - Double(i) * 36)) }
    }

    private func makeLighthouse(at position: SCNVector3) {
        let root = SCNNode()
        sphere(1, "C8BA91", at: vector(0, -0.4, 0), scale: vector(8, 2, 6), into: root)
        cylinder(1.35, 7.8, cream, at: vector(0, 3.6, 0), into: root)
        cylinder(1.39, 1, coral, at: vector(0, 4.3, 0), into: root)
        cylinder(1.7, 0.25, ink, at: vector(0, 7.5, 0), into: root)
        cylinder(1.15, 1.3, "9AD9D4", at: vector(0, 8.15, 0), into: root)
        let top = SCNCone(topRadius: 0.1, bottomRadius: 1.65, height: 1)
        top.radialSegmentCount = 12
        top.firstMaterial = material(coral)
        let roof = SCNNode(geometry: top)
        roof.position = vector(0, 9.2, 0)
        root.addChildNode(roof)
        root.position = position
        setRoot.addChildNode(root)
    }

    private func makeBoat(at position: SCNVector3, tint: String, size: Double) {
        let boat = SCNNode()
        sphere(1, cream, at: vector(0, 0, 0), scale: vector(0.9, 0.35, 2.7), into: boat)
        box(1.45, 0.12, 3.7, tint, at: vector(0, 0.2, 0), radius: 0.12, into: boat)
        cylinder(0.055, 6.5, cream, at: vector(0, 3.3, 0), into: boat)
        let vertices = [vector(0.07, 1, 0), vector(0.07, 6.35, 0), vector(0.07, 1, 2.35)]
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: [Int32(0), 1, 2], primitiveType: .triangles)])
        let mat = material("FFF8E1", unique: true)
        mat.isDoubleSided = true
        geometry.firstMaterial = mat
        boat.addChildNode(SCNNode(geometry: geometry))
        boat.position = position
        boat.eulerAngles.y = scalar(-0.6)
        boat.scale = vector(size, size, size)
        setRoot.addChildNode(boat)
    }

    // MARK: - Repeating causeway sections

    private func makeSection(index: Int) -> SCNNode {
        let section = SCNNode()
        let roadway = SCNNode()
        roadways.append(roadway)
        section.addChildNode(roadway)
        box(11.6, 0.9, 24, "293D4C", at: vector(0, -0.53, -12), radius: 0, into: roadway)
        let surface = box(8.15, 0.14, 24, track, at: vector(0, -0.065, -12), radius: 0, into: roadway)
        let asphalt = material(track, unique: true)
        asphalt.diffuse.contents = texture("asphalt")
        asphalt.normal.contents = texture("stone-normal")
        asphalt.normal.intensity = 0.3
        asphalt.roughness.contents = texture("roughness")
        asphalt.metalness.contents = 0.22
        for prop in [asphalt.diffuse, asphalt.normal, asphalt.roughness] {
            prop.wrapS = .repeat; prop.wrapT = .repeat
            prop.contentsTransform = SCNMatrix4MakeScale(3, 8, 1)
            prop.maxAnisotropy = 8
            prop.mipFilter = .linear
        }
        surface.geometry?.firstMaterial = asphalt
        for side in [-1.0, 1.0] {
            let pavement = box(1.35, 0.15, 24, "596B76", at: vector(side * 4.78, 0.03, -12), radius: 0.01, into: roadway)
            let stone = material("596B76", unique: true)
            stone.diffuse.contents = texture("paving")
            stone.normal.contents = texture("stone-normal")
            stone.normal.intensity = 0.25
            stone.diffuse.wrapS = .repeat; stone.diffuse.wrapT = .repeat
            stone.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 10, 1)
            for prop in [stone.diffuse, stone.normal] { prop.mipFilter = .linear; prop.maxAnisotropy = 8 }
            pavement.geometry?.firstMaterial = stone
            box(0.13, 0.2, 24, cream, at: vector(side * 4.05, 0.02, -12), radius: 0.025, into: roadway)
            let glow = box(0.035, 0.025, 24, "42E1DE", at: vector(side * 4.01, 0.13, -12), radius: 0, into: roadway)
            glow.geometry?.firstMaterial = material("42E1DE", emissive: true)
            let quay = box(side < 0 ? 11 : 4.2, 1.05, 24, "465565", at: vector(side < 0 ? -11.45 : 8.05, -0.41, -12), radius: 0.015, into: section)
            let quayMat = material("465565", unique: true)
            quayMat.diffuse.contents = texture("paving")
            quayMat.normal.contents = texture("stone-normal")
            quayMat.normal.intensity = 0.3
            quayMat.diffuse.wrapS = .repeat; quayMat.diffuse.wrapT = .repeat
            quayMat.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 8, 1)
            for prop in [quayMat.diffuse, quayMat.normal] { prop.mipFilter = .linear; prop.maxAnisotropy = 8 }
            quay.geometry?.firstMaterial = quayMat
            box(0.22, 0.18, 24, "8898A4", at: vector(side * 5.98, 0.2, -12), radius: 0.025, into: section)
            for z in stride(from: -1.0, through: -24.0, by: -2.5) {
                let edge = glowPlane(width: 0.5, length: 2.8, tint: "85D8E1", opacity: 0.18)
                edge.position = vector(side * 5.85, -0.10, z)
                section.addChildNode(edge)
            }
            // Dock edges remain visible in water mode, defining the racing channel.
            box(0.23, 0.4, 24, "23313D", at: vector(side * 7.0, -0.45, -12), radius: 0.02, into: section)
            for z in stride(from: -2.0, through: -24.0, by: -4.0) {
                cylinder(0.16, 1.4, "233645", at: vector(side * 6.9, -0.15, z), into: section)
                cylinder(0.18, 0.08, cream, at: vector(side * 6.9, 0.48, z), into: section)
                box(0.09, 0.75, 0.09, "526A7B", at: vector(side * 5.6, 0.34, z), radius: 0.025, into: roadway)
            }
            box(0.09, 0.07, 24, "93ABBB", at: vector(side * 5.6, 0.72, -12), radius: 0.025, into: roadway)
            box(0.06, 0.035, 24, "526A7B", at: vector(side * 5.6, 0.38, -12), radius: 0.01, into: roadway)
            if side < 0 {
                makeHouse(into: section, at: vector(-11.5, -0.3, -7), facing: side, variant: index)
                if index % 3 != 1 { makeHouse(into: section, at: vector(-15.5, -0.3, -20), facing: side, variant: index + 4) }
            } else if index % 3 == 2 {
                makeHouse(into: section, at: vector(13.5, -0.3, -15), facing: side, variant: index + 2)
            } else {
                box(8, 0.35, 3.5, "374553", at: vector(11, -0.25, -10), radius: 0.03, into: section)
                for p in 0..<5 { box(0.15, 0.035, 3.5, "718394", at: vector(7.5+Double(p)*1.5, -0.06, -10), radius: 0.015, into: section) }
                let yacht = makeMooredYacht()
                yacht.position = vector(13, -0.68, -16)
                yacht.eulerAngles.y = scalar(0.3)
                section.addChildNode(yacht)
            }
            if index % 2 == 0 { makePalm(into: section, at: vector(side * 7.7, -0.2, -17), lean: side * 0.09, variation: index) }
            let lamp = SCNNode()
            cylinder(0.065, 4.7, "243849", at: vector(0, 2.35, 0), into: lamp)
            box(1.3, 0.07, 0.15, "243849", at: vector(-side * 0.5, 4.63, 0), radius: 0.03, into: lamp)
            let lantern = box(0.84, 0.035, 0.23, "FFCF92", at: vector(-side * 0.71, 4.58, 0), radius: 0.02, into: lamp)
            lantern.geometry?.firstMaterial = material("FFCF92", emissive: true)
            let pool = glowPlane(width: 3.6, length: 5.5, tint: "FFBE78", opacity: 0.18)
            pool.position = vector(-side * 0.9, 0.13, 0)
            lamp.addChildNode(pool)
            lamp.position = vector(side * 5.1, 0, -18)
            roadway.addChildNode(lamp)
            // Realistic maritime clutter and utility detail, outside the play corridor.
            for c in 0..<3 {
                let cargo = box(1.3, 1.0 + Double(c % 2) * 0.8, 1.2, c % 2 == 0 ? "A76C46" : "497483", at: vector(side * (7.8 + Double(c % 2) * 1.4), 0.4, -3 - Double(c) * 1.4), radius: 0.04, into: section)
                for line in [-0.4, 0.4] { box(0.07, 1.05, 1.22, "273744", at: vector(line, 0, 0), radius: 0.01, into: cargo) }
            }
        }
        for lane in [-1.0, 0.0, 1.0] {
            for offset in [-0.73, 0.73] {
                box(0.095, 0.026, 24, "A9BCC9", at: vector(lane * 2.6 + offset, 0.018, -12), radius: 0.012, into: roadway)
                box(0.045, 0.015, 24, "152536", at: vector(lane * 2.6 + offset + 0.085, 0.012, -12), radius: 0, into: roadway)
            }
            for z in stride(from: -2.0, through: -24.0, by: -2.0) {
                box(1.73, 0.009, 0.2, "30434D", at: vector(lane * 2.6, 0.005, z), radius: 0.01, into: roadway)
            }
        }
        for line in [-1.3, 1.3] {
            for z in [-3.0, -11, -19] { box(0.08, 0.02, 1.8, "C4BBA5", at: vector(line, 0.017, z), radius: 0.012, into: roadway) }
        }
        if index == 5 { makeGantry(into: section, z: -23) }
        roadway.removeFromParentNode()
        let mergedRoad = flattenPreservingHierarchy(roadway)
        roadways.removeLast()
        roadways.append(mergedRoad)
        let mergedScenery = flattenPreservingHierarchy(section)
        mergedScenery.name = "routeScenery"
        mergedRoad.name = "routeDeck"
        let result = SCNNode()
        result.addChildNode(mergedScenery)
        result.addChildNode(mergedRoad)
        return result
    }

    func makeHouse(into parent: SCNNode, at position: SCNVector3, facing: Double, variant: Int) {
        let house = houseNode(at: position, facing: facing, variant: variant)
        // Merge static surfaces per building. Restore placement explicitly because
        // flattenedClone bakes children but intentionally omits this root's transform.
        let placement = house.transform
        house.transform = SCNMatrix4Identity
        let merged = house.flattenedClone()
        merged.transform = placement
        parent.addChildNode(merged)
    }

    /// The unmerged house; kept separate so tests can measure it (merged geometry reports no bounds off-screen).
    func houseNode(at position: SCNVector3, facing: Double, variant: Int) -> SCNNode {
        let house = SCNNode()
        box(6.6, 0.8, 8.8, "334553", at: vector(0, -0.15, 0), radius: 0.08, into: house)
        let palette = ["46586A", "845E53", "34616B", "616274", "44536E", "806C5E"]
        let tint = palette[variant % palette.count]
        let height = 4.9 + Double(variant % 4) * 1.25
        let wall = box(5.7, height, 8, tint, at: vector(0, height / 2, 0), radius: 0.08, into: house)
        let wallMat = material(tint, unique: true)
        wallMat.diffuse.contents = texture("wall-\(variant % 6)")
        wallMat.normal.contents = texture("stone-normal")
        wallMat.normal.intensity = 0.18
        wallMat.roughness.contents = 0.82
        wallMat.diffuse.wrapS = .repeat; wallMat.diffuse.wrapT = .repeat
        wallMat.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 2, 1)
        for prop in [wallMat.diffuse, wallMat.normal] { prop.mipFilter = .linear; prop.maxAnisotropy = 8 }
        wall.geometry?.firstMaterial = wallMat
        box(5.94, 0.25, 8.24, "89979F", at: vector(0, height + 0.03, 0), radius: 0.04, into: house)
        box(5.76, 0.3, 0.16, tint, at: vector(0, height + 0.25, 3.95), radius: 0.025, into: house)
        let front = -facing * 2.87
        for level in 0..<Int(height / 2.7) {
            let y = 1.5 + Double(level) * 2.65
            box(0.15, 0.1, 8.15, "9EA6A6", at: vector(front, y + 1.12, 0), radius: 0.015, into: house)
            for j in 0..<4 {
                let z = -2.9 + Double(j) * 1.94
                box(0.14, 1.72, 1.12, "182B41", at: vector(front, y, z), radius: 0.03, into: house)
                let glass = box(0.05, 1.52, 0.95, "F4BF7F", at: vector(front - facing * 0.08, y, z), radius: 0.02, into: house)
                let lit = (variant * 3 + level * 2 + j) % 5 < 3
                glass.geometry?.firstMaterial = material(lit ? ((variant + j) % 2 == 0 ? "E6B879" : "C48C59") : "213C53", emissive: lit)
                box(0.06, 0.035, 0.94, "313A44", at: vector(front - facing * 0.12, y + 0.15, z), radius: 0, into: house)
                box(0.07, 1.52, 0.035, "313A44", at: vector(front - facing * 0.12, y, z), radius: 0, into: house)
                if level > 0 {
                    box(0.62, 0.1, 1.32, "71838F", at: vector(front - facing * 0.22, y - 0.87, z), radius: 0.02, into: house)
                    box(0.04, 0.48, 1.23, "253F52", at: vector(front - facing * 0.53, y - 0.59, z), radius: 0.01, into: house)
                }
            }
        }
        for level in 0..<Int(height / 2.7) {
            let y = 1.5 + Double(level) * 2.65
            box(5.75, 0.10, 0.12, "9EA6A6", at: vector(0, y + 1.12, 4.02), radius: 0.015, into: house)
            for x in [-1.75, 0, 1.75] {
                box(1.05, 1.7, 0.12, "162B3D", at: vector(x, y, 4.04), radius: 0.025, into: house)
                let glass = box(0.88, 1.48, 0.05, "E7AF73", at: vector(x, y, 4.12), radius: 0.02, into: house)
                let lit = abs(Int(x * 10) + level + variant) % 5 < 3
                glass.geometry?.firstMaterial = material(lit ? (level % 2 == 0 ? "DCA875" : "BC8658") : "20394E", emissive: lit)
                box(0.035, 1.49, 0.035, "304556", at: vector(x, y, 4.16), radius: 0, into: house)
                box(0.89, 0.045, 0.035, "304556", at: vector(x, y + 0.12, 4.16), radius: 0, into: house)
                box(1.18, 0.08, 0.38, "728A96", at: vector(x, y - 0.84, 4.18), radius: 0.02, into: house)
            }
        }
        // Shop canopies, lit signage and roof equipment break up the repeated façades.
        let awning = box(1.3, 0.09, 5.0, variant % 2 == 0 ? "AE533E" : "2E7180", at: vector(front - facing * 0.53, 2.65, 0), radius: 0.025, into: house)
        awning.eulerAngles.z = scalar(facing * 0.11)
        let sign = box(0.12, 0.62, 3.3, "152F45", at: vector(front - facing * 0.08, 3.13, 0), radius: 0.04, into: house)
        let signage = material("FFFFFF", unique: true)
        signage.diffuse.contents = texture(variant % 2 == 0 ? "sign-marina" : "sign-coast")
        signage.emission.contents = signage.diffuse.contents
        signage.emission.intensity = 0.7
        sign.geometry?.firstMaterial = signage
        if variant % 3 == 0 {
            for x in [-1.1, 1.1] {
                box(0.9, 0.7, 1.5, "384753", at: vector(x, height + 0.55, 1.7), radius: 0.07, into: house)
                cylinder(0.28, 1.2, "69747C", at: vector(x, height + 0.7, -1.7), into: house)
            }
        }
        switch variant % 3 {
        case 1:
            // Gable roof along the quay, with a chimney.
            let roof = gableRoof(width: 6.1, length: 8.5, rise: 1.9, tint: "4A3A3A")
            roof.position = vector(0, height + 0.15, 0)
            house.addChildNode(roof)
            box(0.55, 1.6, 0.55, "5E4B45", at: vector(-1.2, height + 1.5, -2.4), radius: 0.06, into: house)
        case 2:
            // Set-back penthouse floor, away from the quay front, with its own cornice.
            let penthouse = box(4.1, 1.7, 6.2, tint, at: vector(facing * 0.5, height + 1.0, 0), radius: 0.08, into: house)
            penthouse.geometry?.firstMaterial = wallMat
            box(4.4, 0.18, 6.5, "89979F", at: vector(facing * 0.5, height + 1.92, 0), radius: 0.04, into: house)
        default: break
        }
        house.position = position
        return house
    }

    private func makePalm(into parent: SCNNode, at position: SCNVector3, lean: Double, variation: Int) {
        let palm = SCNNode()
        let tall = 6.5 + Double(variation % 3) * 0.55
        let trunk = cylinder(0.16, tall, "B69A70", at: vector(0, tall / 2, 0), into: palm)
        trunk.eulerAngles.z = scalar(lean)
        let crownX = -sin(lean) * tall * 0.5
        for index in 0..<7 {
            let angle = Double(index) * .pi * 2 / 7
            let leaf = sphere(1, index % 2 == 0 ? "235E58" : "397A62", at: vector(crownX + cos(angle) * 1.08, tall - 0.02, sin(angle) * 1.08), scale: vector(1.6, 0.10, 0.32), into: palm)
            leaf.eulerAngles.y = scalar(-angle)
            leaf.eulerAngles.z = scalar(-cos(angle) * 0.23)
        }
        for index in 0..<3 {
            sphere(0.18, "947447", at: vector(crownX - 0.18 + Double(index) * 0.17, tall - 0.25, 0), into: palm)
        }
        palm.position = position
        parent.addChildNode(palm)
    }

    private func makeBunting(into parent: SCNNode, z: Double) {
        for side in [-1.0, 1.0] {
            cylinder(0.055, 6.4, cream, at: vector(side * 5.5, 3.2, z), into: parent)
        }
        box(11, 0.026, 0.026, "C3B697", at: vector(0, 6.15, z), radius: 0, into: parent)
        for index in 0..<11 {
            let x = -4.7 + Double(index) * 0.94
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: [vector(-0.3, 0, 0), vector(0.3, 0, 0), vector(0, -0.58, 0)])], elements: [SCNGeometryElement(indices: [Int32(0), 1, 2], primitiveType: .triangles)])
            let mat = material(index % 3 == 0 ? coral : index % 3 == 1 ? cream : mint, unique: true)
            mat.isDoubleSided = true
            geometry.firstMaterial = mat
            let flag = SCNNode(geometry: geometry)
            flag.position = vector(x, 6.1, z)
            parent.addChildNode(flag)
        }
    }

    // MARK: - Courier, board and chase drone

    private func makePlayer() {
        leftLeg.name = "leftLeg"; rightLeg.name = "rightLeg"
        leftArm.name = "leftArm"; rightArm.name = "rightArm"
        scene.rootNode.addChildNode(player)
        player.addChildNode(body)
        let shirt = sculptedMesh(rings: [(-0.43, 0.23, 0.16), (-0.30, 0.25, 0.17),
                                        (0.06, 0.31, 0.20), (0.28, 0.35, 0.19), (0.39, 0.22, 0.14)], tint: coral)
        shirt.position = vector(0, 1.23, 0)
        body.addChildNode(shirt)
        let shirtMat = material(coral, unique: true)
        shirtMat.normal.contents = texture("cloth-normal")
        shirtMat.normal.intensity = 0.25
        shirtMat.roughness.contents = 0.8
        shirt.geometry?.firstMaterial = shirtMat
        clothing.append(shirtMat)
        box(0.55, 0.34, 0.40, "152637", at: vector(0, 0.81, 0), radius: 0.14, into: body)
        cylinder(0.115, 0.20, "BD846C", at: vector(0, 1.73, 0), into: body)
        sphere(0.31, "CB977C", at: vector(0, 1.98, -0.005), scale: vector(0.92, 1.1, 0.93), into: body)
        sphere(0.32, "132435", at: vector(0, 2.08, 0.055), scale: vector(1.01, 0.95, 0.95), into: body)
        let cap = sphere(0.35, cream, at: vector(0, 2.13, 0), scale: vector(1.04, 0.95, 1.03), into: body)
        let helmetMat = material("D95238", unique: true)
        helmetMat.metalness.contents = 0.0
        helmetMat.roughness.contents = 0.7
        cap.geometry?.firstMaterial = helmetMat
        let visor = sphere(0.31, "164F68", at: vector(0, 2.09, -0.115), scale: vector(1.04, 0.48, 1.0), into: body)
        visor.geometry?.firstMaterial?.metalness.contents = 0.9
        visor.geometry?.firstMaterial?.roughness.contents = 0.12
        box(0.08, 0.10, 0.66, coral, at: vector(0, 2.43, 0), radius: 0.03, into: body)
        for x in [-0.24, 0.24] {
            box(0.04, 0.36, 0.40, "253A4B", at: vector(x, 2.18, 0.1), radius: 0.02, into: body)
        }
        box(0.12, 0.12, 0.035, coral, at: vector(0, 2.26, -0.31), radius: 0.025, into: body)
        // Ears and face are visible during the three-quarter menu idle.
        sphere(0.074, "CB977C", at: vector(-0.29, 1.99, 0), into: body)
        sphere(0.074, "CB977C", at: vector(0.29, 1.99, 0), into: body)
        for x in [-0.10, 0.10] { sphere(0.024, ink, at: vector(x, 2.02, -0.267), into: body) }
        sphere(0.046, "D49B75", at: vector(0, 1.95, -0.29), scale: vector(0.8, 1, 1), into: body)
        // Independent neck rig stabilizes the gaze while the torso counter-rotates.
        headRig.position = vector(0, 1.65, 0)
        for node in body.childNodes where Double(node.position.y) >= 1.73 {
            node.position.y -= scalar(1.65)
            headRig.addChildNode(node)
        }
        body.addChildNode(headRig)
        for side in [-1.0, 1.0] {
            let seam = box(0.035, 0.64, 0.04, "C3DDE5", at: vector(side * 0.25, 1.2, -0.18), radius: 0.01, into: body)
            seam.eulerAngles.z = scalar(side * 0.12)
            box(0.09, 0.11, 0.045, "182937", at: vector(side * 0.27, 1.41, -0.20), radius: 0.02, into: body)
            let shoulder = sphere(0.16, side < 0 ? "DCE5E9" : "203B4A", at: vector(side * 0.34, 1.49, 0), scale: vector(1, 0.55, 1.2), into: body)
            shoulder.geometry?.firstMaterial?.roughness.contents = 0.35
        }
        box(0.23, 0.15, 0.06, "193744", at: vector(0.12, 1.42, -0.19), radius: 0.025, into: body)
        leftArm.position = vector(-0.36, 1.47, 0)
        rightArm.position = vector(0.36, 1.47, 0)
        for arm in [leftArm, rightArm] {
            let sleeve = capsule(0.13, 0.41, coral, at: vector(0, -0.15, 0), into: arm)
            let mat = material(coral, unique: true)
            sleeve.geometry?.firstMaterial = mat
            clothing.append(mat)
            let elbow = SCNNode(); elbow.position = vector(0, -0.31, 0)
            sphere(0.098, "243C4A", at: SCNVector3Zero, into: elbow)
            let bracer = sculptedMesh(rings: [(-0.29, 0.075, 0.085), (-0.10, 0.10, 0.10), (0, 0.09, 0.09)], tint: "213B4B")
            elbow.addChildNode(bracer)
            box(0.13, 0.19, 0.06, "A9C0CF", at: vector(0, -0.13, -0.085), radius: 0.035, into: elbow)
            sphere(0.094, "192F40", at: vector(0, -0.33, -0.025), scale: vector(0.85, 1.16, 0.85), into: elbow)
            for finger in 0..<3 {
                capsule(0.018, 0.08, "778D99", at: vector(-0.035 + Double(finger) * 0.035, -0.385, -0.055), into: elbow)
            }
            arm.addChildNode(elbow); forearms.append(elbow)
            body.addChildNode(arm)
        }
        leftLeg.position = vector(-0.18, 0.77, 0)
        rightLeg.position = vector(0.18, 0.77, 0)
        for leg in [leftLeg, rightLeg] {
            capsule(0.135, 0.37, "172A3C", at: vector(0, -0.14, 0), into: leg)
            sphere(0.12, "263F50", at: vector(0, -0.32, 0), into: leg)
            let shin = SCNNode()
            shin.position = vector(0, -0.31, 0)
            capsule(0.105, 0.31, "172A3C", at: vector(0, -0.13, 0), into: shin)
            box(0.17, 0.16, 0.075, "435A6A", at: vector(0, -0.10, -0.09), radius: 0.05, into: shin)
            box(0.035, 0.28, 0.05, "7EA5AC", at: vector(0.09, -0.11, 0), radius: 0.01, into: shin)
            let ankle = SCNNode(); ankle.position = vector(0, -0.35, 0)
            box(0.24, 0.18, 0.43, cream, at: vector(0, 0, -0.07), radius: 0.075, into: ankle)
            box(0.245, 0.045, 0.43, coral, at: vector(0, -0.08, -0.07), radius: 0.016, into: ankle)
            for lace in 0..<3 { box(0.14, 0.014, 0.018, "273F51", at: vector(0, 0.09, -0.06 - Double(lace) * 0.05), radius: 0, into: ankle) }
            glowBox(0.17, 0.027, 0.025, "A0ECEB", at: vector(0, -0.02, 0.15), into: ankle)
            shin.addChildNode(ankle); feet.append(ankle)
            leg.addChildNode(shin)
            shins.append(shin)
            body.addChildNode(leg)
        }
        // A hard-shell expedition pack has its own frame, inset plates and restrained light strip.
        let pack = sculptedMesh(rings: [(0.88, 0.19, 0.12), (0.96, 0.29, 0.17), (1.36, 0.27, 0.16), (1.51, 0.19, 0.11)], tint: "293E4E")
        pack.position.z = scalar(0.29); body.addChildNode(pack)
        for side in [-1.0, 1.0] {
            let shell = box(0.19, 0.44, 0.05, "A8B7BF", at: vector(side * 0.16, 1.2, 0.445), radius: 0.07, into: body)
            shell.eulerAngles.z = scalar(side * 0.08)
            for seam in 0..<3 { box(0.13, 0.013, 0.02, "223C4B", at: vector(side * 0.16, 1.1 + Double(seam) * 0.07, 0.478), radius: 0, into: body) }
        }
        box(0.5, 0.16, 0.265, "1A293A", at: vector(0.08, 1.40, 0.32), radius: 0.06, into: body)
        box(0.065, 0.19, 0.03, "BA8658", at: vector(0.08, 1.29, 0.449), radius: 0.01, into: body)
        let spine = box(0.28, 0.035, 0.025, "69F4E0", at: vector(0.08, 1.23, 0.465), radius: 0.01, into: body)
        spine.geometry?.firstMaterial = material("69F4E0", emissive: true)
        for x in [-0.21, 0.30] { box(0.045, 0.50, 0.025, "718594", at: vector(x, 1.2, 0.45), radius: 0.015, into: body) }
        let strap = box(0.08, 0.80, 0.06, "D8BB86", at: vector(-0.17, 1.26, 0.235), radius: 0.015, into: body)
        strap.eulerAngles.z = scalar(-0.30)
        cylinder(0.18, 0.16, mint, at: vector(0, 1.66, 0), into: body)
        scarf.position = vector(0.08, 1.65, 0.14)
        box(0.16, 0.40, 0.055, mint, at: vector(0, -0.16, 0.12), radius: 0.025, into: scarf)
        body.addChildNode(scarf)
        makeCourierArmor()
        let deck = box(0.73, 0.15, 1.7, "69B8C5", at: vector(0, 0.04, -0.05), radius: 0.2, into: boardNode)
        deck.name = "deck"
        deck.geometry?.firstMaterial = material("69B8C5", unique: true)
        box(0.22, 0.018, 1.45, cream, at: vector(0, 0.125, -0.05), radius: 0.04, into: boardNode)
        for z in [-0.48, 0.43] {
            let thruster = cylinder(0.18, 0.08, gold, at: vector(0, -0.065, z), into: boardNode)
            thruster.geometry?.firstMaterial = material(gold, emissive: true)
        }
        player.addChildNode(boardNode)
        boardNode.isHidden = true
        for x in [-0.25, 0.25] {
            capsule(0.15, 0.59, cream, at: vector(x, 1.25, 0.40), into: jetpackNode)
            cylinder(0.17, 0.12, coral, at: vector(x, 1.03, 0.40), into: jetpackNode)
            let flame = sphere(0.13, gold, at: vector(x, 0.74, 0.40), scale: vector(1, 2.1, 1), into: jetpackNode)
            flame.geometry?.firstMaterial = material(gold, emissive: true)
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

    private func makeDrone() {
        box(0.60, 0.30, 0.46, cream, radius: 0.14, into: drone)
        box(0.32, 0.12, 0.02, ink, at: vector(0, 0, -0.235), radius: 0.04, into: drone)
        sphere(0.055, coral, at: vector(0.07, 0, -0.26), into: drone)
        for x in [-0.43, 0.43] {
            box(0.31, 0.06, 0.08, ink, at: vector(x * 0.74, 0, 0), into: drone)
            cylinder(0.10, 0.10, mint, at: vector(x, 0.09, 0), into: drone)
            let rotor = box(0.46, 0.025, 0.08, ink, at: vector(x, 0.17, 0), radius: 0.025, into: drone)
            rotorNodes.append(rotor)
        }
        scene.rootNode.addChildNode(drone)
    }

    // MARK: - Obstacles and pooled pickups

    private func syncEntities(_ entities: [TrackEntity], time: Double, menu: Bool, visibilityDistance: Double, simulation: RunnerSimulation) {
        let visible = menu ? [] : entities.filter { $0.z > -12 && $0.z < visibilityDistance }
        let identifiers = Set(visible.map(\.id))
        for identifier in Array(liveNodes.keys) where !identifiers.contains(identifier) {
            recycleEntity(identifier)
        }
        trimEntityPools()
        for entity in visible {
            let key = String(describing: entity.kind) + (lastWaterMode ? "-water" : "-land") + String(describing: renderedStage)
            let node: SCNNode
            if let existing = liveNodes[entity.id] {
                node = existing
            } else {
                if var bucket = pools[key], let reused = bucket.popLast() {
                    pools[key] = bucket
                    node = reused
                } else {
                    node = makeEntity(kind: entity.kind)
                    addActionCue(to: node, kind: entity.kind)
                }
                liveNodes[entity.id] = node
                liveKinds[entity.id] = key
                scene.rootNode.addChildNode(node)
            }
            let path = simulation.routeTransform(atAheadDistance: entity.z)
            node.position = vector(Double(entity.lane) * 2.6 + path.lateralOffset, entity.y + path.elevation, -entity.z)
            switch entity.kind {
            case .tram:
                node.scale = vector(1, 1, entity.length / 8)
                let tramColors = ["146B79", "9C4B3E", "C59043"]
                node.childNode(withName: "tramBody", recursively: false)?.geometry?.firstMaterial?.diffuse.contents = color(tramColors[entity.id % tramColors.count])
                if let beacon = node.childNode(withName: "warningBeacon", recursively: false) {
                    beacon.isHidden = entity.oncomingSpeed <= 0
                    beacon.opacity = reducedMotion ? 0.8 : 0.70 + sin(time * 4) * 0.2
                }
            case .ramp:
                node.scale = vector(1, 1, entity.length / 6)
            case .gap:
                node.scale.z = scalar(entity.length / 7)
            case .meteor:
                let descent = max(0, min(1, (entity.z - 18) / 36))
                node.childNode(withName: "impactRock", recursively: false)?.position.y = scalar(1.05 + descent * 16)
                node.childNode(withName: "impactRock", recursively: false)?.eulerAngles = vector(time * 0.55, time * 0.35, 0.24)
                node.childNode(withName: "target", recursively: false)?.opacity = reducedMotion ? 0.8 : 0.65 + sin(time * 4) * 0.15
            case .root:
                node.childNode(withName: "rootCrown", recursively: false)?.scale.y = scalar(0.90 + sin(time * 2 + Double(entity.id)) * 0.10)
            case .iceCrack:
                node.scale.z = scalar(entity.length / 3.2)
                node.childNode(withName: "crackWarning", recursively: false)?.opacity = reducedMotion ? 0.8 : 0.7 + sin(time * 4) * 0.15
            case .laserSweep:
                node.childNode(withName: "beam", recursively: false)?.opacity = reducedMotion ? 0.88 : 0.86 + sin(time * 4) * 0.10
            case .waterTraffic:
                node.position.y += scalar(sin(time * 3 + Double(entity.id)) * 0.075)
                node.eulerAngles.z = scalar(sin(time * 2 + Double(entity.id)) * 0.045)
            case .coin, .key, .relic:
                node.eulerAngles.y = scalar(time * 2.1 + Double(entity.id) * 0.25)
            case .magnet, .jetpack, .sneakers, .multiplier:
                node.position.y += scalar(sin(time * 3 + Double(entity.id)) * 0.09)
                node.eulerAngles.y = scalar(time * 1.3)
            default: break
            }
            if let cue = node.childNode(withName: "actionCue", recursively: false) {
                let approach = entity.z / max(1, simulation.speed + entity.oncomingSpeed)
                cue.isHidden = approach > 2.7 || entity.z < 1 || lastWaterMode
                cue.opacity = highContrastCues ? 1 : 0.74
                cue.scale.x = highContrastCues ? 1.35 : 1
                cue.childNode(withName: "cueBackplate", recursively: false)?.isHidden = !highContrastCues
                cue.scale.z = 1 / max(0.01, node.scale.z)
                cue.position.z = scalar((entity.length * 0.5 + 2.0) / Double(max(0.01, node.scale.z)))
            }
        }
    }

    private func makeEntity(kind: EntityKind) -> SCNNode {
        // Pickups stay clean: flat materials keep coins, keys and power-ups readable.
        switch kind {
        case .coin, .key, .magnet, .jetpack, .sneakers, .multiplier, .relic: return withoutSurfaceDetail { buildEntity(kind: kind) }
        default: return buildEntity(kind: kind)
        }
    }

    private func buildEntity(kind: EntityKind) -> SCNNode {
        if let signature = makeSignatureHazard(kind) { return signature }
        if kind == .relic { return makeWorldRelic() }
        if renderedStage != .harbor, let node = makeWorldObstacle(kind) { return node }
        switch kind {
        case .tram: return makeTram()
        case .barrier: return lastWaterMode ? makeWaterCargo() : makeBarrier()
        case .arch: return makeArch()
        case .ramp: return makeRamp()
        case .coin: return makeCoin()
        case .key: return makeKey()
        case .magnet, .jetpack, .sneakers, .multiplier: return makePowerUp(kind)
        case .checkpoint: return makeCheckpoint(water: false)
        case .gate: return makeCheckpoint(water: true)
        case .buoy: return makeBuoy()
        case .waveRamp: return makeWaveRamp()
        case .airRing: return makeAirRing(hazard: false)
        case .airHazard: return makeAirRing(hazard: true)
        case .relic: return makeWorldRelic()
        case .gap, .meteor, .root, .iceCrack, .laserSweep, .waterTraffic: return SCNNode()
        }
    }

    private func makeTram() -> SCNNode {
        let root = SCNNode()
        let shade = shadow(width: 2.35, length: 8.0)
        shade.position.y = scalar(0.01)
        root.addChildNode(shade)
        let carriage = box(2.12, 2.11, 7.8, mint, at: vector(0, 1.61, 0), radius: 0.21, into: root)
        carriage.name = "tramBody"
        carriage.geometry?.firstMaterial = material(mint, unique: true)
        let beacon = sphere(0.12, coral, at: vector(0, 2.94, 3.5), scale: vector(1, 0.75, 1), into: root)
        beacon.name = "warningBeacon"
        beacon.geometry?.firstMaterial = material(coral, emissive: true)
        beacon.isHidden = true
        box(2.16, 0.24, 7.9, cream, at: vector(0, 2.68, 0), radius: 0.11, into: root)
        box(2.11, 0.41, 7.83, cream, at: vector(0, 0.74, 0), radius: 0.06, into: root)
        box(2.1, 0.08, 7.84, "D6A84C", at: vector(0, 1.01, 0), radius: 0.025, into: root)
        for end in [-1.0, 1.0] {
            box(1.68, 0.85, 0.09, ink, at: vector(0, 1.92, end * 3.91), radius: 0.13, into: root)
            box(0.055, 0.85, 0.1, cream, at: vector(0, 1.92, end * 3.96), radius: 0.01, into: root)
            box(0.60, 0.18, 0.07, ink, at: vector(0, 2.49, end * 3.92), radius: 0.05, into: root)
            box(1.80, 0.16, 0.20, ink, at: vector(0, 0.42, end * 3.91), radius: 0.08, into: root)
            for x in [-0.7, 0.7] {
                let lamp = sphere(0.12, "FFF3BC", at: vector(x, 1.16, end * 3.97), scale: vector(1, 1, 0.4), into: root)
                lamp.geometry?.firstMaterial = material("FFF3BC", emissive: true)
            }
        }
        for side in [-1.0, 1.0] {
            for z in [-2.65, -1.32, 0, 1.32, 2.65] {
                box(0.055, 0.87, 1.04, "16384F", at: vector(side * 1.065, 1.95, z), radius: 0.07, into: root)
                box(0.06, 0.075, 0.85, "57B0D7", at: vector(side * 1.099, 2.29, z), radius: 0.015, into: root)
            }
            for z in [-2.55, 2.55] {
                let wheel = cylinder(0.34, 0.16, ink, at: vector(side * 0.91, 0.36, z), into: root)
                wheel.eulerAngles.z = scalar(.pi / 2)
                let hub = cylinder(0.17, 0.18, "A4B6A8", at: vector(side * 0.95, 0.36, z), into: root)
                hub.eulerAngles.z = scalar(.pi / 2)
            }
        }
        // Roof details stay below the 2.8 metre walkable roof plane.
        for z in [-2.5, 0, 2.5] {
            box(0.85, 0.035, 0.6, "657A8A", at: vector(0, 2.817, z), radius: 0.08, into: root)
        }
        return root
    }

    private func makeBarrier() -> SCNNode {
        let root = SCNNode()
        for x in [-0.82, 0.82] {
            box(0.14, 0.88, 0.16, cream, at: vector(x, 0.44, 0), radius: 0.025, into: root)
            box(0.39, 0.12, 0.72, ink, at: vector(x, 0.06, 0), radius: 0.035, into: root)
        }
        box(2.08, 0.55, 0.26, coral, at: vector(0, 0.73, 0), radius: 0.06, into: root)
        for index in -2...2 {
            let stripe = box(0.18, 0.46, 0.015, cream, at: vector(Double(index) * 0.4, 0.73, 0.14), radius: 0.01, into: root)
            stripe.eulerAngles.z = scalar(-0.38)
        }
        return root
    }

    private func makeArch() -> SCNNode {
        let root = SCNNode()
        for x in [-1.0, 1.0] {
            box(0.22, 2.65, 0.38, ink, at: vector(x, 1.325, 0), radius: 0.055, into: root)
            box(0.42, 0.13, 0.74, "577C7C", at: vector(x, 0.065, 0), radius: 0.04, into: root)
        }
        box(2.15, 1.87, 0.43, coral, at: vector(0, 1.72, 0), radius: 0.1, into: root)
        box(2.17, 0.14, 0.46, cream, at: vector(0, 0.80, 0), radius: 0.025, into: root)
        for index in -2...2 {
            let bar = box(0.17, 0.26, 0.02, "D58E63", at: vector(Double(index) * 0.38, 1.0, 0.225), radius: 0.01, into: root)
            bar.eulerAngles.z = scalar(-0.38)
        }
        // Downward chevron communicates sliding under the shutter.
        let left = box(0.40, 0.11, 0.025, cream, at: vector(-0.15, 1.88, 0.23), radius: 0.03, into: root)
        left.eulerAngles.z = scalar(-0.64)
        let right = box(0.40, 0.11, 0.025, cream, at: vector(0.15, 1.88, 0.23), radius: 0.03, into: root)
        right.eulerAngles.z = scalar(0.64)
        return root
    }

    private func makeRamp() -> SCNNode {
        let root = SCNNode()
        let vertices = [vector(-1.07, 0, 3), vector(1.07, 0, 3), vector(-1.07, 0, -3), vector(1.07, 0, -3), vector(-1.07, 2.8, -3), vector(1.07, 2.8, -3)]
        let indices: [Int32] = [0, 5, 4, 0, 1, 5, 0, 4, 2, 1, 3, 5, 2, 5, 3, 2, 4, 5, 0, 3, 1, 0, 2, 3]
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.firstMaterial = material("DEB17B")
        root.addChildNode(SCNNode(geometry: geometry))
        for index in 0..<8 {
            let z = 2.8 - Double(index) * 0.78
            let y = (3 - z) / 6 * 2.8 + 0.023
            let slat = box(2.12, 0.045, 0.075, "F5D6A0", at: vector(0, y, z), radius: 0.01, into: root)
            slat.eulerAngles.x = scalar(atan(2.8 / 6))
        }
        return root
    }

    private func makeCoin() -> SCNNode {
        let root = SCNNode()
        let rim = cylinder(0.31, 0.11, gold, at: vector(0, 0, 0), into: root)
        rim.eulerAngles.x = scalar(.pi / 2)
        let face = cylinder(0.235, 0.12, "F8B83D", at: vector(0, 0, 0), into: root)
        face.eulerAngles.x = scalar(.pi / 2)
        box(0.062, 0.25, 0.125, "FFE397", radius: 0.015, into: root)
        return root
    }

    private func makeKey() -> SCNNode {
        let root = SCNNode()
        let loop = SCNTorus(ringRadius: 0.2, pipeRadius: 0.06)
        loop.ringSegmentCount = 16
        loop.pipeSegmentCount = 6
        loop.firstMaterial = material("FFE2A0")
        let ring = SCNNode(geometry: loop)
        ring.eulerAngles.x = scalar(.pi / 2)
        ring.position.y = scalar(0.18)
        root.addChildNode(ring)
        box(0.09, 0.40, 0.09, gold, at: vector(0, -0.17, 0), radius: 0.025, into: root)
        box(0.22, 0.07, 0.09, gold, at: vector(0.06, -0.30, 0), radius: 0.02, into: root)
        return root
    }

    private func makePowerUp(_ kind: EntityKind) -> SCNNode {
        let root = SCNNode()
        let tint: String = kind == .magnet ? "EA8376" : kind == .jetpack ? "71CBD1" : kind == .sneakers ? "A6CE84" : "EDC15A"
        let halo = SCNTorus(ringRadius: 0.58, pipeRadius: 0.035)
        halo.ringSegmentCount = 20
        halo.pipeSegmentCount = 5
        halo.firstMaterial = material(tint, emissive: true)
        let ring = SCNNode(geometry: halo)
        ring.eulerAngles.x = scalar(.pi / 2)
        root.addChildNode(ring)
        switch kind {
        case .magnet:
            let arc = SCNTorus(ringRadius: 0.25, pipeRadius: 0.12)
            arc.ringSegmentCount = 16
            arc.pipeSegmentCount = 6
            arc.firstMaterial = material(coral)
            let arch = SCNNode(geometry: arc)
            arch.eulerAngles.x = scalar(.pi / 2)
            root.addChildNode(arch)
            for x in [-0.25, 0.25] { box(0.20, 0.23, 0.20, cream, at: vector(x, 0.22, 0), radius: 0.025, into: root) }
        case .jetpack:
            for x in [-0.20, 0.20] {
                capsule(0.14, 0.68, cream, at: vector(x, 0, 0), into: root)
                cylinder(0.15, 0.12, coral, at: vector(x, -0.26, 0), into: root)
                sphere(0.09, gold, at: vector(x, -0.44, 0), scale: vector(1, 2, 1), into: root)
            }
            box(0.28, 0.32, 0.20, mint, radius: 0.03, into: root)
        case .sneakers:
            for x in [-0.22, 0.22] {
                box(0.28, 0.28, 0.60, cream, at: vector(x, 0, 0), radius: 0.1, into: root)
                box(0.29, 0.07, 0.61, "9CC87C", at: vector(x, -0.14, 0), radius: 0.025, into: root)
                box(0.15, 0.04, 0.20, coral, at: vector(x, 0.15, 0), radius: 0.02, into: root)
            }
        default:
            let starVertices = (0..<10).map { index -> SCNVector3 in
                let angle = Double(index) * .pi / 5 + .pi / 2
                let radius = index % 2 == 0 ? 0.45 : 0.21
                return vector(cos(angle) * radius, sin(angle) * radius, 0)
            }
            var vertices = starVertices
            vertices.append(vector(0, 0, 0))
            var indices: [Int32] = []
            for index in 0..<10 { indices += [10, Int32(index), Int32((index + 1) % 10)] }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            let mat = material(gold, unique: true)
            mat.isDoubleSided = true
            geometry.firstMaterial = mat
            root.addChildNode(SCNNode(geometry: geometry))
        }
        return root
    }

    private func makeMenuProps() {
        let tram = makeTram()
        tram.position = vector(2.6, 0, -13)
        menuProps.addChildNode(tram)
        for index in 0..<8 {
            let coin = withoutSurfaceDetail { makeCoin() }
            coin.position = vector(-2.6, 1.0, -5 - Double(index) * 2.6)
            coin.eulerAngles.y = scalar(Double(index) * 0.22)
            menuProps.addChildNode(coin)
        }
        scene.rootNode.addChildNode(menuProps)
        for (lane, z) in [(0.0, -15.0), (2.6, -38.0)] {
            let gate = makeCheckpoint(water: true)
            gate.position = vector(lane, 0.9, z)
            waterMenuProps.addChildNode(gate)
        }
        let buoy = makeBuoy()
        buoy.position = vector(-2.6, 0, -8)
        waterMenuProps.addChildNode(buoy)
        let ramp = makeWaveRamp()
        ramp.position = vector(2.6, 0, -25)
        waterMenuProps.addChildNode(ramp)
        scene.rootNode.addChildNode(waterMenuProps)
    }

    // MARK: - Original maritime props and physically based surface library

    private func makeJetSki() {
        ski.name = "jetSki"
        let hull = SCNNode()
        // A stepped, tapered hull with a sharp bow, chines and a dark underside.
        let sections: [(Double, Double, Double)] = [(1.65, 0.48, 0.12), (1.1, 0.66, 0.2), (-0.65, 0.6, 0.3), (-1.65, 0.13, 0.46)]
        var vertices: [SCNVector3] = []
        for (z, halfWidth, deckY) in sections {
            vertices += [vector(-halfWidth, deckY, z), vector(halfWidth, deckY, z), vector(-halfWidth * 0.6, -0.16, z), vector(halfWidth * 0.6, -0.16, z)]
        }
        var indices: [Int32] = []
        for i in 0..<3 {
            let a = Int32(i * 4), b = a + 4
            indices += [a, b, a+1, a+1, b, b+1, a, a+2, b, a+2, b+2, b, a+1, b+1, a+3, a+3, b+1, b+3, a+2, a+3, b+2, a+3, b+3, b+2]
        }
        indices += [0, 1, 2, 1, 3, 2, 12, 14, 13, 13, 14, 15]
        let geom = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let mat = material("E2E9ED", unique: true)
        mat.metalness.contents = 0.55
        mat.roughness.contents = 0.2
        geom.firstMaterial = mat
        hull.geometry = geom
        ski.addChildNode(hull)
        let upper = sphere(1, coral, at: vector(0, 0.28, -0.58), scale: vector(0.5, 0.25, 0.91), into: ski)
        upper.geometry?.firstMaterial?.roughness.contents = 0.25
        box(0.43, 0.22, 1.4, "142736", at: vector(0, 0.35, 0.55), radius: 0.18, into: ski)
        box(0.51, 0.08, 1.35, "2C4656", at: vector(0, 0.48, 0.58), radius: 0.035, into: ski)
        for side in [-1.0, 1.0] {
            box(0.18, 0.05, 1.55, "102130", at: vector(side * 0.46, 0.26, 0.53), radius: 0.04, into: ski)
            let trim = box(0.06, 0.06, 2.25, "33DBE4", at: vector(side * 0.54, 0.22, -0.05), radius: 0.025, into: ski)
            trim.geometry?.firstMaterial = material("33DBE4", emissive: true)
            for z in [-0.7, -0.52, -0.34] { box(0.16, 0.055, 0.09, "152A39", at: vector(side * 0.43, 0.46, z), radius: 0.01, into: ski) }
        }
        let stem = cylinder(0.055, 0.61, "657D8E", at: vector(0, 0.77, -0.51), into: ski)
        stem.eulerAngles.x = scalar(-0.23)
        let handle = cylinder(0.058, 0.91, "172734", at: vector(0, 1.07, -0.58), into: ski)
        handle.eulerAngles.z = scalar(.pi / 2)
        box(0.19, 0.1, 0.2, "0A354C", at: vector(0, 1.12, -0.55), radius: 0.04, into: ski)
        let screen = box(0.13, 0.012, 0.13, "5AF5E1", at: vector(0, 1.17, -0.55), radius: 0.02, into: ski)
        screen.geometry?.firstMaterial = material("5AF5E1", emissive: true)
        let jet = cylinder(0.19, 0.25, "182836", at: vector(0, 0.06, 1.55), into: ski)
        jet.eulerAngles.x = scalar(.pi / 2)
        player.addChildNode(ski)
        ski.isHidden = true
        let wakeShape = SCNPlane(width: 3.6, height: 8)
        let wakeMat = SCNMaterial()
        wakeMat.lightingModel = .constant
        wakeMat.diffuse.contents = texture("wake")
        wakeMat.isDoubleSided = true
        wakeMat.writesToDepthBuffer = false
        wakeShape.firstMaterial = wakeMat
        wake.geometry = wakeShape
        wake.eulerAngles.x = scalar(-.pi / 2)
        wake.castsShadow = false
        scene.rootNode.addChildNode(wake)
        for _ in 0..<38 {
            let plane = SCNPlane(width: 1, height: 1)
            let foam = SCNMaterial()
            foam.diffuse.contents = texture("spray")
            foam.lightingModel = .constant
            foam.isDoubleSided = true
            foam.writesToDepthBuffer = false
            plane.firstMaterial = foam
            let particle = SCNNode(geometry: plane)
            particle.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(particle)
            particle.castsShadow = false
            particle.opacity = 0
            spray.append(particle)
        }
    }

    private func makeCheckpoint(water: Bool) -> SCNNode {
        let root = SCNNode()
        let tint = water ? "58F1D9" : "FFD979"
        for side in [-1.0, 1.0] {
            let column = cylinder(water ? 0.16 : 0.10, water ? 2.8 : 3.4, "263C53", at: vector(side * 1.13, water ? 0.65 : 0.65, 0), into: root)
            column.castsShadow = false
            let strip = cylinder(0.11, 2.5, tint, at: vector(side * 1.13, 0.65, 0), into: root)
            strip.geometry?.firstMaterial = material(tint, emissive: true)
            if water {
                cylinder(0.37, 0.3, "E96345", at: vector(side * 1.13, -0.72, 0), into: root)
                cylinder(0.4, 0.14, cream, at: vector(side * 1.13, -0.55, 0), into: root)
            }
        }
        let banner = box(2.45, 0.23, 0.25, tint, at: vector(0, water ? 2.2 : 2.5, 0), radius: 0.06, into: root)
        banner.geometry?.firstMaterial = material(tint, emissive: true)
        let arrowL = box(0.38, 0.10, 0.06, cream, at: vector(-0.13, 1.9, 0), radius: 0.03, into: root)
        arrowL.eulerAngles.z = scalar(-0.6)
        let arrowR = box(0.38, 0.1, 0.06, cream, at: vector(0.13, 1.9, 0), radius: 0.03, into: root)
        arrowR.eulerAngles.z = scalar(0.6)
        return root
    }

    private func makeBuoy() -> SCNNode {
        let root = SCNNode()
        cylinder(0.67, 0.36, "FF693E", at: vector(0, 0.2, 0), into: root)
        let cone = SCNCone(topRadius: 0.14, bottomRadius: 0.5, height: 1.05)
        cone.radialSegmentCount = 24
        cone.firstMaterial = material("EF693B")
        let cap = SCNNode(geometry: cone)
        cap.position.y = scalar(0.83)
        root.addChildNode(cap)
        cylinder(0.31, 0.15, "E9DFCC", at: vector(0, 0.83, 0), into: root)
        cylinder(0.04, 0.7, ink, at: vector(0, 1.56, 0), into: root)
        let lamp = sphere(0.11, "FFD080", at: vector(0, 1.96, 0), into: root)
        lamp.geometry?.firstMaterial = material("FFD080", emissive: true)
        return root
    }

    private func makeWaveRamp() -> SCNNode {
        let root = makeRamp()
        root.scale = vector(1, 0.39, 0.83)
        for child in root.childNodes { child.geometry?.firstMaterial = material("31758B") }
        for x in [-0.95, 0.95] {
            let strip = box(0.09, 0.055, 6.6, "65F9EC", at: vector(x, 1.45, 0), radius: 0.02, into: root)
            strip.eulerAngles.x = scalar(atan(2.8 / 6))
            strip.geometry?.firstMaterial = material("65F9EC", emissive: true)
        }
        return root
    }

    private func makeAirRing(hazard: Bool) -> SCNNode {
        let root = SCNNode()
        let ring = SCNTorus(ringRadius: hazard ? 0.85 : 0.72, pipeRadius: hazard ? 0.11 : 0.055)
        ring.ringSegmentCount = 40
        ring.pipeSegmentCount = 8
        ring.firstMaterial = material(hazard ? "FF493F" : "5DFADE", emissive: true)
        let loop = SCNNode(geometry: ring)
        loop.eulerAngles.x = scalar(.pi / 2)
        root.addChildNode(loop)
        if hazard {
            box(1.8, 0.18, 0.28, "24364B", radius: 0.05, into: root)
            box(0.2, 1.6, 0.23, "B95147", radius: 0.05, into: root)
            for x in [-0.68, 0.68] { sphere(0.15, "F75D3D", at: vector(x, 0, 0.16), into: root) }
        }
        return root
    }

    private func makeGantry(into parent: SCNNode, z: Double) {
        let root = SCNNode()
        for x in [-6.8, 6.8] {
            box(0.26, 8.0, 0.3, "2C4357", at: vector(x, 4, 0), radius: 0.025, into: root)
            box(0.45, 0.2, 0.52, "677D8D", at: vector(x, 0, 0), radius: 0.03, into: root)
        }
        box(13.8, 0.25, 0.35, "2D4151", at: vector(0, 7.8, 0), radius: 0.04, into: root)
        box(13.8, 0.13, 0.13, "7B8FA0", at: vector(0, 8.45, 0), radius: 0.02, into: root)
        for i in -6...6 {
            let brace = box(0.075, 0.86, 0.08, "6B8191", at: vector(Double(i), 8.12, 0), radius: 0.01, into: root)
            brace.eulerAngles.z = scalar(i % 2 == 0 ? 0.65 : -0.65)
        }
        root.position.z = scalar(z)
        parent.addChildNode(root)
    }

    private func makeCrane(at position: SCNVector3) {
        let root = SCNNode()
        for x in [-2.0, 2.0] { box(0.35, 19, 0.35, "465366", at: vector(x, 9.5, 0), radius: 0, into: root) }
        box(24, 0.6, 1.2, "44566C", at: vector(6, 19, 0), radius: 0.04, into: root)
        for i in 0..<10 {
            let brace = box(0.12, 3.0, 0.12, "718091", at: vector(-1.5 + Double(i) * 2.2, 20.3, 0), radius: 0, into: root)
            brace.eulerAngles.z = scalar(i % 2 == 0 ? 0.65 : -0.65)
        }
        box(23, 0.15, 0.15, "718091", at: vector(7, 21.4, 0), radius: 0, into: root)
        box(0.07, 12, 0.07, "6B8194", at: vector(15, 13, 0), radius: 0, into: root)
        let beacon = sphere(0.14, "FF523C", at: vector(-2, 21.7, 0), into: root)
        beacon.geometry?.firstMaterial = material("FF523C", emissive: true)
        root.position = position
        scene.rootNode.addChildNode(root)
    }

    private func glowPlane(width: Double, length: Double, tint: String, opacity: Double) -> SCNNode {
        let plane = SCNPlane(width: width, height: length)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = texture("glow")
        mat.multiply.contents = color(tint)
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        plane.firstMaterial = mat
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = scalar(-.pi / 2)
        node.opacity = opacity
        node.castsShadow = false
        return node
    }

    private func image(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(context)
        return context.makeImage()
    }

    private func environmentMap() -> CGImage? {
        image(width: 512, height: 256) { ctx in
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("152A3D").cgColor, color("6A8BA7").cgColor, color("A9BAD4").cgColor, color("435E87").cgColor] as CFArray, locations: [0, 0.43, 0.55, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 256), options: [])
            ctx.setFillColor(color("FFD5A0").cgColor)
            ctx.fillEllipse(in: CGRect(x: 75, y: 128, width: 58, height: 35))
            ctx.setFillColor(color("B9F4FF").cgColor)
            ctx.fill(CGRect(x: 320, y: 125, width: 48, height: 44))
        }
    }

    private func facadeMaterial(variant: Int) -> SCNMaterial {
        let mat = material("344B67", unique: true)
        mat.diffuse.contents = texture("windows-\(variant % 3)")
        mat.emission.contents = mat.diffuse.contents
        mat.emission.intensity = 0.45
        mat.roughness.contents = 0.35
        return mat
    }

    /// Small deterministic texture atlases, generated once. No network or runtime assets.
    private func texture(_ name: String) -> CGImage? {
        if let cached = textureCache[name] { return cached }
        let size = name.hasPrefix("sign") || name == "asphalt" || name == "paving" ? 512 : 256
        let result = image(width: size, height: size) { ctx in
            var rng: UInt64 = 0xCA57CAFE
            func random() -> Double {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return Double((rng >> 33) & 0xFFFF) / 65535
            }
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            if name == "spray" {
                for _ in 0..<200 {
                    let angle = random() * .pi * 2, r = random() * 100
                    ctx.setFillColor(color("E3F4F9", alpha: (1-r/110) * 0.7).cgColor)
                    ctx.fillEllipse(in: CGRect(x: 128 + cos(angle)*r, y: 128 + sin(angle)*r, width: 5+random()*16, height: 5+random()*12))
                }
            } else if name == "glow" {
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("FFFFFF", alpha: 0.7).cgColor, color("FFFFFF", alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
            } else if name == "wake" {
                // Connected turbulent foam ribbons avoid a trail of discrete balls.
                ctx.setLineCap(.round)
                for side in [-1.0, 1.0] {
                    for layer in 0..<7 {
                        ctx.setStrokeColor(color("DCF5F7", alpha: 0.055 + Double(layer) * 0.011).cgColor)
                        ctx.setLineWidth(CGFloat(21 - layer * 2))
                        ctx.move(to: CGPoint(x: 128 + side * 12, y: 254))
                        for y in stride(from: 250.0, through: 0, by: -4.0) {
                            let fraction = 1 - y / 256
                            let x = 128 + side * (12 + fraction * 95) + sin(y * 0.17 + Double(layer)) * 3
                            ctx.addLine(to: CGPoint(x: x, y: y))
                        }
                        ctx.strokePath()
                    }
                }
                for _ in 0..<2000 {
                    let y = random() * 256
                    let width = (1 - y / 256) * 105 + 12
                    let edge = random() < 0.5 ? -1.0 : 1.0
                    let x = 128 + edge * width * (0.65 + random() * 0.35)
                    ctx.setFillColor(color("D7F7FA", alpha: (0.1 + random() * 0.6) * y / 256).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: 3 + random() * 6, height: 2 + random() * 4))
                }
            } else if name.contains("normal") {
                ctx.setFillColor(color("8080FF").cgColor); ctx.fill(bounds)
                for y in stride(from: 0, to: size, by: 2) {
                    for x in stride(from: 0, to: size, by: 2) {
                        let wave = name == "water-normal" ? sin(Double(x) * 0.12 + sin(Double(y) * 0.08) * 2) * 0.14 : name == "cloth-normal" ? Double((x + y) % 4) * 0.025 : (random() - 0.5) * 0.15
                        ctx.setFillColor(CGColor(red: 0.5 + wave, green: 0.5 + (random() - 0.5) * 0.11, blue: 1, alpha: 1))
                        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    }
                }
            } else if name.hasPrefix("wall") {
                let palette = ["566A7B", "966F5D", "477776", "7F7A88", "546785", "927B66"]
                let index = Int(name.suffix(1)) ?? 0
                ctx.setFillColor(color(palette[index]).cgColor); ctx.fill(bounds)
                for _ in 0..<13000 {
                    ctx.setFillColor(CGColor(gray: random(), alpha: 0.12))
                    ctx.fill(CGRect(x: random()*256, y: random()*256, width: 1+random()*3, height: 1+random()*3))
                }
                ctx.setStrokeColor(color("1B2C3B", alpha: 0.35).cgColor); ctx.setLineWidth(1)
                for row in 0..<16 {
                    let y = Double(row)*16
                    ctx.move(to: CGPoint(x: 0,y:y));ctx.addLine(to:CGPoint(x:256,y:y));ctx.strokePath()
                    for col in 0..<6 { let x = Double(col)*48 + (row%2 == 0 ? 0:24); ctx.move(to:CGPoint(x:x,y:y));ctx.addLine(to:CGPoint(x:x,y:y+16));ctx.strokePath() }
                }
            } else if name.hasPrefix("windows") {
                ctx.setFillColor(color("1B2E43").cgColor); ctx.fill(bounds)
                for y in stride(from: 8, to: 256, by: 24) {
                    for x in stride(from: 8, to: 256, by: 26) {
                        ctx.setFillColor(color(random() > 0.4 ? "D6A677" : "355976").cgColor)
                        ctx.fill(CGRect(x: x, y: y, width: 12, height: 15))
                        ctx.setFillColor(color("142438").cgColor)
                        ctx.fill(CGRect(x: x + 5, y: y, width: 2, height: 15))
                    }
                }
            } else if name.hasPrefix("sign") {
                ctx.setFillColor(color("113347").cgColor); ctx.fill(bounds)
                ctx.setStrokeColor(color("5EE8D8").cgColor); ctx.setLineWidth(12)
                ctx.stroke(CGRect(x: 15, y: 15, width: 482, height: 482))
                // Minimal nautical insignia is legible at speed from either side.
                ctx.setStrokeColor(color("F4D4A3").cgColor); ctx.setLineWidth(15)
                ctx.strokeEllipse(in: CGRect(x: 150, y: 130, width: 210, height: 210))
                for offset in [-50.0, 0, 50] {
                    ctx.move(to: CGPoint(x: 145, y: 175 + offset)); ctx.addLine(to: CGPoint(x: 365, y: 250 + offset)); ctx.strokePath()
                }
            } else if name == "asphalt" {
                let s = Double(size)
                ctx.setFillColor(color("263744").cgColor); ctx.fill(bounds)
                for _ in 0..<52000 {
                    ctx.setFillColor(CGColor(gray: random(), alpha: 0.12))
                    ctx.fill(CGRect(x: random() * s, y: random() * s, width: 1 + random() * 2, height: 1 + random()))
                }
                // Patch repairs: fresher rectangles with a sealed seam.
                for _ in 0..<4 {
                    let rect = CGRect(x: random() * s * 0.8, y: random() * s * 0.8, width: 50 + random() * 110, height: 40 + random() * 90)
                    ctx.setFillColor(color("1D2C38", alpha: 0.55).cgColor); ctx.fill(rect)
                    ctx.setStrokeColor(color("0E1822", alpha: 0.8).cgColor); ctx.setLineWidth(2); ctx.stroke(rect)
                }
                // Oil stains.
                let stain = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("0B121A", alpha: 0.32).cgColor, color("0B121A", alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                for _ in 0..<6 {
                    let center = CGPoint(x: random() * s, y: random() * s)
                    ctx.drawRadialGradient(stain, startCenter: center, startRadius: 0, endCenter: center, endRadius: 12 + random() * 30, options: [])
                }
                // Branching cracks.
                ctx.setStrokeColor(color("0C1824", alpha: 0.8).cgColor); ctx.setLineCap(.round)
                for _ in 0..<7 {
                    var point = CGPoint(x: random() * s, y: random() * s), heading = random() * .pi * 2
                    ctx.setLineWidth(0.8 + random() * 1.2)
                    ctx.move(to: point)
                    for _ in 0..<(6 + Int(random() * 10)) {
                        heading += (random() - 0.5) * 1.1
                        point = CGPoint(x: point.x + cos(heading) * (6 + random() * 12), y: point.y + sin(heading) * (6 + random() * 12))
                        ctx.addLine(to: point)
                    }
                    ctx.strokePath()
                }
            } else {
                let s = Double(size)
                let base = name == "paving" ? "61717D" : "686868"
                ctx.setFillColor(color(base).cgColor); ctx.fill(bounds)
                for _ in 0..<(16000 * size * size / 65536) {
                    let x = random() * s, y = random() * s
                    let val = name == "roughness" ? 0.22 + random() * 0.42 : random()
                    ctx.setFillColor(CGColor(gray: val, alpha: name == "roughness" ? 0.7 : 0.13))
                    ctx.fill(CGRect(x: x, y: y, width: 1 + random() * 2, height: 1 + random()))
                }
                if name == "paving" {
                    let slab = size / 4
                    // Each slab weathers to its own tone before the joints are drawn.
                    for row in 0..<4 { for column in 0..<4 {
                        ctx.setFillColor(CGColor(gray: random() < 0.5 ? 0.15 : 0.85, alpha: 0.05 + random() * 0.04))
                        ctx.fill(CGRect(x: column * slab, y: row * slab, width: slab, height: slab))
                    } }
                    ctx.setStrokeColor(color("263B4B").cgColor); ctx.setLineWidth(3)
                    for n in stride(from: 0, to: size, by: slab) {
                        ctx.move(to: CGPoint(x: 0, y: n)); ctx.addLine(to: CGPoint(x: size, y: n)); ctx.strokePath()
                        ctx.move(to: CGPoint(x: n, y: 0)); ctx.addLine(to: CGPoint(x: n, y: size)); ctx.strokePath()
                    }
                }
            }
        }
        textureCache[name] = result
        return result
    }


    private func skyPanorama() -> CGImage? {
        image(width: 1024, height: 512) { ctx in
            let colors = ["07182D", "183254", "567299", "DC9E86", "E9BD96", "4A5C7C", "15223C"].map { color($0).cgColor } as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.24, 0.39, 0.49, 0.53, 0.67, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x:0,y:512), options: [])
            for i in 0..<22 {
                let y = 270.0 + Double((i*17)%76)
                let x = Double((i*139)%1024)
                ctx.setFillColor(color("A6A8B4", alpha: 0.10).cgColor)
                ctx.fillEllipse(in:CGRect(x:x,y:y,width:130+Double(i%4)*55,height:4+Double(i%3)*3))
            }
        }
    }

    private func makeMooredYacht() -> SCNNode {
        let root = SCNNode()
        let hull = sphere(1, "C5D1DC", at: vector(0, 0.2, 0), scale: vector(1.2, 0.55, 3.6), into: root)
        hull.geometry?.firstMaterial = material("C5D1DC", unique: true)
        hull.geometry?.firstMaterial?.roughness.contents = 0.3
        box(1.55, 0.35, 4.3, "264858", at: vector(0, 0.5, -0.15), radius: 0.14, into: root)
        box(1.2, 0.8, 1.9, "D9E1E5", at: vector(0, 1.03, -0.55), radius: 0.17, into: root)
        box(1.23, 0.45, 1.95, "214F6B", at: vector(0, 1.19, -0.55), radius: 0.13, into: root)
        box(1.47, 0.13, 2.2, "D9E1E5", at: vector(0, 1.64, -0.55), radius: 0.06, into: root)
        cylinder(0.045, 2.2, "8198A7", at: vector(0, 2.4, -0.6), into: root)
        for x in [-0.7, 0.7] {
            let lamp = sphere(0.08, "F7BC7A", at: vector(x, 0.72, 1.5), into: root)
            lamp.geometry?.firstMaterial = material("F7BC7A", emissive: true)
        }
        return root
    }


    private func flattenPreservingHierarchy(_ source: SCNNode) -> SCNNode {
        let flat = SCNNode()
        func visit(_ node: SCNNode, transform: simd_float4x4) {
            let accumulated = transform * node.simdTransform
            if let geometry = node.geometry {
                let leaf = SCNNode(geometry: geometry)
                leaf.simdTransform = accumulated
                leaf.opacity = node.opacity
                leaf.castsShadow = node.castsShadow
                flat.addChildNode(leaf)
            }
            for child in node.childNodes { visit(child, transform: accumulated) }
        }
        for child in source.childNodes { visit(child, transform: matrix_identity_float4x4) }
        return flat.flattenedClone()
    }


    private func loadAsset(_ name: String) -> CGImage? {
        let key = "asset-" + name
        if let cached = textureCache[key] { return cached }
        let url = assetsURL?.appendingPathComponent(name + ".png") ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        #if os(iOS)
        let result = UIImage(contentsOfFile: url.path)?.cgImage
        #else
        let source = NSImage(contentsOf: url)
        let result = source?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        if let result { textureCache[key] = result }
        return result
    }



    private func makeWaterCargo() -> SCNNode {
        let root = SCNNode()
        box(2.05, 0.93, 0.95, "A95C39", at: vector(0, 0.5, 0), radius: 0.045, into: root)
        for x in [-0.77, 0.77] { box(0.10, 0.96, 0.99, "283D4D", at: vector(x, 0.5, 0), radius: 0.015, into: root) }
        for z in [-0.51, 0.51] {
            let reflector = box(1.8, 0.11, 0.025, "FFE1A3", at: vector(0, 0.88, z), radius: 0.01, into: root)
            reflector.geometry?.firstMaterial = material("FFE1A3", emissive: true)
        }
        return root
    }

}

// MARK: - Portal Odyssey worlds
// Detached destination roots are incrementally prebuilt; at most the active and next world are retained.
private extension CoastalWorld {
    var worldPalette: (floor: String, edge: String, stone: String, glow: String, sky: String, haze: String) {
        switch renderedStage {
        case .harbor: return ("243643", "A1C4CF", "506C80", "67E8F9", "14233F", "354B66")
        case .orbit: return ("202D45", "8FABC4", "465973", "69E9FF", "020714", "081329")
        case .mars: return ("8C5743", "D4B08A", "A84C33", "FFBD70", "361B28", "8D5344")
        case .verdant: return ("213D40", "82A295", "325C58", "57F6BD", "061F26", "17423D")
        case .cryo: return ("557B92", "D2EAF1", "739DBB", "96DFFF", "101B3A", "365470")
        case .forge: return ("302C35", "8B7B79", "514147", "FF884A", "220E20", "603131")
        }
    }

    func configureWorld(_ stage: WorldStage) {
        preparationNode = nil
        // Return obstacles to their bounded pools. IDs are run-local, so detach all live nodes.
        for id in Array(liveNodes.keys) { recycleEntity(id) }
        if renderedStage != .harbor, var old = destinations[renderedStage] {
            old.sections = journeySections
            destinations[renderedStage] = old
        }
        journeyRoot.removeFromParentNode()
        renderedStage = stage
        journeySections = []
        journeyAnimated = []
        if stage == .harbor {
            journeyRoot = SCNNode()
            scene.rootNode.addChildNode(journeyRoot)
            finaleRoot = harborFinale
            scene.background.contents = harborBackground
            scene.lightingEnvironment.contents = loadAsset("HarborSky") ?? environmentMap()
            worldSun?.shadowBias = 0.01; worldSun?.zFar = 95; worldSun?.orthographicScale = 34
        } else {
            // Practice-world selection may arrive without an approach: finish only that destination.
            while destinations[stage]?.sections.count ?? 0 < 9 { buildDestinationSlice(stage) }
            if let destination = destinations[stage] {
                journeyRoot = destination.root
                journeySections = destination.sections
                finaleRoot = destination.finale
                scene.rootNode.addChildNode(journeyRoot)
                scene.background.contents = destination.sky
                scene.lightingEnvironment.contents = destination.sky
            }
            worldSun?.shadowBias = 2.0; worldSun?.zFar = 320; worldSun?.orthographicScale = 60
        }
        applyLook(stage)
        let stages = WorldStage.allCases
        let next = stages.firstIndex(of: stage).flatMap { $0 + 1 < stages.count ? stages[$0 + 1] : nil }
        destinations = destinations.filter { $0.key == stage || $0.key == next }
        // Off-world skies are 2048x1024 decoded images; keep only the current and next stage's. HarborSky is never evicted.
        for (other, name) in Self.skyNames where other != stage && other != next { textureCache["asset-" + name] = nil }
        warmedStages = warmedStages.filter { $0 == stage || $0 == next }
        // Pools survive stage changes, but never retain more than 96 entity hierarchies.
        trimEntityPools()
        for section in alternateRouteSections {
            section.childNode(withName: "deck", recursively: false)?.geometry?.firstMaterial = deckMaterial(for: stage)
        }
    }

    func prewarmNextDestination(after stage: WorldStage) {
        let stages = WorldStage.allCases
        guard let index = stages.firstIndex(of: stage), index + 1 < stages.count else { return }
        let next = stages[index + 1]
        guard destinations[next]?.sections.count ?? 0 < 9 else { return }
        buildDestinationSlice(next)
        if destinations[next]?.sections.count == 9, !warmedStages.contains(next), let root = destinations[next]?.root {
            warmedStages.insert(next)
            preparationNode = root
            preparationRevision += 1
            onWorldPrepared?(root)
        }
    }

    /// Construct a single section per game frame, using detached nodes on the scene's owning thread.
    func buildDestinationSlice(_ stage: WorldStage) {
        let savedStage = renderedStage
        let savedRoot = journeyRoot
        let savedSections = journeySections
        renderedStage = stage
        defer { renderedStage = savedStage; journeyRoot = savedRoot; journeySections = savedSections }
        if destinations[stage] == nil {
            journeyRoot = SCNNode()
            makeWorldHorizon()
            let sky = loadAsset(Self.skyNames[stage] ?? "") ?? worldSky()
            let finale = SCNNode()
            makeFinale(stage: stage, into: finale)
            journeyRoot.addChildNode(finale)
            destinations[stage] = Destination(root: journeyRoot, sections: [], sky: sky, finale: finale)
            // Horizon and panorama decoding are their own frame slice.
            return
        }
        guard var destination = destinations[stage], destination.sections.count < 9 else { return }
        journeyRoot = destination.root
        let index = destination.sections.count
        let section = makeWorldSection(index: index)
        section.position.z = scalar(-Double(index) * 26)
        destination.root.addChildNode(section)
        destination.sections.append(section)
        destinations[stage] = destination
    }

    func recycleEntity(_ identifier: Int) {
        guard let node = liveNodes.removeValue(forKey: identifier), let key = liveKinds.removeValue(forKey: identifier) else { return }
        node.removeFromParentNode()
        node.opacity = 1; node.eulerAngles = SCNVector3Zero; node.scale = vector(1, 1, 1)
        if pools[key, default: []].count < 24 { pools[key, default: []].append(node) }
    }

    func trimEntityPools() {
        var budget = 96
        let ordered = pools.keys.sorted { a, b in
            let current = String(describing: renderedStage)
            let aCurrent = a.hasSuffix(current), bCurrent = b.hasSuffix(current)
            return aCurrent == bCurrent ? a < b : aCurrent
        }
        for key in ordered {
            let kept = Array(pools[key, default: []].prefix(max(0, budget)))
            pools[key] = kept
            budget -= kept.count
        }
        pools = pools.filter { !$0.value.isEmpty }
    }

    func worldSky() -> CGImage? {
        image(width: 1024, height: 512) { ctx in
            let colors = [color(worldPalette.haze).cgColor, color(worldPalette.sky).cgColor,
                          color("01030B").cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
            }
            for i in 0..<380 {
                let x = Double((i * 641 + 131) % 1024)
                let y = 170 + Double((i * 173 + 37) % 338)
                let a = 0.25 + Double(i % 7) * 0.1
                ctx.setFillColor(color(i % 3 == 0 ? "A6CCFF" : "E2EBFF", alpha: a).cgColor)
                let r = i % 13 == 0 ? 1.6 : 0.7
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
    }

    @discardableResult func glowBox(_ w: Double, _ h: Double, _ d: Double, _ tint: String,
                                    at position: SCNVector3, into root: SCNNode) -> SCNNode {
        let node = box(w, h, d, tint, at: position, radius: 0, into: root)
        node.geometry?.firstMaterial = material(tint, emissive: true)
        node.castsShadow = false
        return node
    }

    @discardableResult func ring(_ radius: Double, tube: Double, tint: String, at position: SCNVector3,
                                into root: SCNNode, glow: Bool = false) -> SCNNode {
        let geometry = SCNTorus(ringRadius: radius, pipeRadius: tube)
        geometry.ringSegmentCount = radius > 12 ? 96 : 48
        geometry.pipeSegmentCount = 8
        geometry.firstMaterial = material(tint, emissive: glow)
        let node = SCNNode(geometry: geometry)
        node.position = position
        root.addChildNode(node)
        return node
    }

    func planetTexture(_ tint: String) -> CGImage? {
        let key = "planet-" + tint
        if let result = textureCache[key] { return result }
        let result = image(width: 1024, height: 512) { ctx in
            ctx.setFillColor(color(tint).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            for row in 0..<256 {
                let latitude = Double(row) / 256
                let wave = sin(latitude * 53) * 0.5 + sin(latitude * 119) * 0.3
                let shade = wave > 0 ? "CFBBA5" : "493F61"
                ctx.setFillColor(color(shade, alpha: abs(wave) * 0.42).cgColor)
                ctx.fill(CGRect(x: 0, y: row * 2, width: 1024, height: 2))
            }
            for i in 0..<80 {
                let x = (i * 313) % 1024; let y = (i * 137) % 512
                ctx.setFillColor(color("EAD6B8", alpha: 0.035).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 35 + (i % 6) * 13, height: 4 + i % 10))
            }
        }
        textureCache[key] = result
        return result
    }

    func makeWorldHorizon() {
        let palette = worldPalette
        switch renderedStage {
        case .orbit:
            let planet = sphere(37, "AC9DC1", at: vector(-43, 46, -173), into: journeyRoot)
            planet.geometry?.firstMaterial = material("AC9DC1", unique: true)
            planet.geometry?.firstMaterial?.diffuse.contents = planetTexture("8276A5")
            planet.geometry?.firstMaterial?.roughness.contents = 0.94
            planet.geometry?.firstMaterial?.lightingModel = .constant
            planet.geometry?.firstMaterial?.shaderModifiers = [.surface: """
            #pragma body
            float light = max(0.0, dot(normalize(_surface.normal), normalize(float3(-0.5, 0.65, 0.7))));
            _surface.diffuse.rgb *= 0.12 + light * 0.88;
            """]
            planet.eulerAngles.z = scalar(-0.24)
            let bands = SCNNode(); bands.position = planet.position; bands.eulerAngles = vector(0.23, 0, -0.32)
            for i in 0..<7 {
                let loop = ring(47 + Double(i) * 1.8, tube: i % 2 == 0 ? 0.67 : 0.35,
                                tint: i % 2 == 0 ? "BAA9C9" : "635C7E", at: SCNVector3Zero, into: bands)
                loop.opacity = 0.82
            }
            journeyRoot.addChildNode(bands)
            sphere(5.2, "879EB7", at: vector(37, 28, -160), into: journeyRoot)
            // A complete orbital station silhouette hangs above the far end of the causeway.
            let station = SCNNode(); station.position = vector(21, 16, -102)
            let wheel = ring(9, tube: 0.55, tint: "8293A6", at: SCNVector3Zero, into: station)
            wheel.eulerAngles.x = scalar(.pi / 2)
            for i in 0..<8 {
                let spoke = box(0.35, 17.8, 0.45, "546478", radius: 0, into: station)
                spoke.eulerAngles.z = scalar(Double(i) * .pi / 4)
            }
            sphere(2.2, "B5BDCA", at: SCNVector3Zero, into: station)
            for x in [-14.0, 14.0] {
                box(12, 5, 0.18, "173D64", at: vector(x, 0, 0), radius: 0, into: station)
                for j in -4...4 { glowBox(0.08, 4.8, 0.2, "4B98C4", at: vector(x + Double(j) * 1.3, 0, 0.1), into: station) }
                box(12, 0.25, 0.3, "A7B6C5", at: vector(x, 0, 0), radius: 0, into: station)
            }
            station.eulerAngles = vector(0.15, -0.2, 0.2)
            journeyRoot.addChildNode(flattenPreservingHierarchy(station)); journeyRoot.childNodes.last?.position = station.position
        case .mars:
            makeDistantMountains(tint: "743C38", icy: false)
            let sun = sphere(6, "FFE0BC", at: vector(49, 28, -198), into: journeyRoot)
            sun.geometry?.firstMaterial = material("FFD4A4", emissive: true)
            let base = SCNNode(); base.position = vector(-32, -1, -94)
            for i in 0..<3 {
                let dome = sphere(7 - Double(i), "BDD5CE", at: vector(Double(i) * 12, 0, Double(i) * -10), scale: vector(1, 0.68, 1), into: base)
                dome.geometry?.firstMaterial = material("99C1BC", unique: true)
                dome.geometry?.firstMaterial?.metalness.contents = 0.65
                dome.geometry?.firstMaterial?.roughness.contents = 0.22
                cylinder(7.2 - Double(i), 0.9, "CCC5AC", at: vector(Double(i) * 12, 0.45, Double(i) * -10), into: base)
                for angle in 0..<6 {
                    let rib = ring(7.05 - Double(i), tube: 0.06, tint: "E2DACA", at: vector(Double(i) * 12, 0, Double(i) * -10), into: base)
                    rib.eulerAngles = vector(.pi / 2, Double(angle) * .pi / 6, 0); rib.scale.y = scalar(0.68)
                }
            }
            journeyRoot.addChildNode(base)
            cylinder(0.24, 16, "D8C4A8", at: vector(26, 7, -79), into: journeyRoot)
            let dish = sphere(3, "D6CFBA", at: vector(26, 15, -79), scale: vector(1, 0.18, 1), into: journeyRoot)
            dish.eulerAngles.z = scalar(0.8)
        case .verdant:
            makeDistantMountains(tint: "154342", icy: false)
            for i in 0..<7 {
                let x = (i % 2 == 0 ? -1.0 : 1.0) * (18 + Double(i) * 5)
                makeAlienTree(into: journeyRoot, at: vector(x, -0.5, -55 - Double(i) * 17), size: 1.5 + Double(i % 3) * 0.4)
            }
            let temple = SCNNode(); temple.position = vector(0, 0, -172)
            for side in [-1.0, 1.0] {
                let pillar = box(8, 37, 9, "31564F", at: vector(side * 15, 17, 0), radius: 0.7, into: temple)
                pillar.eulerAngles.z = scalar(side * -0.14)
                glowBox(0.6, 31, 0.3, "72EFD4", at: vector(side * 15, 17, 4.6), into: temple)
            }
            let crown = ring(13, tube: 1.5, tint: "49786A", at: vector(0, 34, 0), into: temple)
            crown.eulerAngles.x = scalar(.pi / 2)
            let glyph = ring(9.5, tube: 0.15, tint: "78F3CF", at: vector(0, 34, 0.4), into: temple, glow: true)
            glyph.eulerAngles.x = scalar(.pi / 2)
            journeyRoot.addChildNode(temple)
            makeAurora(tint: "36BCA4", height: 43)
        case .cryo:
            makeDistantMountains(tint: "7592AE", icy: true)
            sphere(17, "ADC1D7", at: vector(-44, 40, -185), into: journeyRoot)
            makeAurora(tint: "56D8BE", height: 37)
            makeAurora(tint: "857DD8", height: 53)
            for index in 0..<3 {
                let arch = ring(18 + Double(index) * 2, tube: 2.2, tint: "9DC6D5", at: vector(index == 1 ? -15 : 21, 0, -84 - Double(index) * 36), into: journeyRoot)
                arch.eulerAngles.x = scalar(.pi / 2)
                arch.scale = vector(0.8, 1.6, 1)
                arch.geometry?.firstMaterial = iceMaterial()
            }
        case .forge:
            let reactor = SCNNode(); reactor.position = vector(0, 23, -167)
            for i in 0..<4 {
                let halo = ring(20 + Double(i) * 4, tube: i == 0 ? 1.2 : 0.7,
                                tint: i % 2 == 0 ? "EC885D" : "8D7373", at: SCNVector3Zero, into: reactor, glow: i == 0)
                halo.eulerAngles = vector(.pi / 2, Double(i) * 0.33, Double(i) * 0.4)
            }
            let core = sphere(15, "F5B775", at: SCNVector3Zero, into: reactor)
            core.geometry?.firstMaterial = material("FFAA62", unique: true)
            core.geometry?.firstMaterial?.emission.contents = color("F67B35")
            core.geometry?.firstMaterial?.emission.intensity = 0.75
            core.geometry?.firstMaterial?.shaderModifiers = [.surface: """
            #pragma body
            float v = sin(_surface.position.x * 0.8 + scn_frame.time) * cos(_surface.position.y * 0.7 - scn_frame.time * 0.6);
            _surface.diffuse.rgb *= 0.55 + 0.45 * v;
            _surface.emission.rgb *= 0.65 + 0.35 * v;
            """]
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3
                let spoke = box(1.5, 76, 1.5, "5E555B", radius: 0, into: reactor)
                spoke.eulerAngles.z = scalar(angle)
            }
            journeyRoot.addChildNode(reactor)
            for side in [-1.0, 1.0] {
                for i in 0..<4 {
                    let tower = cylinder(4.0, 30 + Double(i) * 8, "584851", at: vector(side * (25 + Double(i) * 11), 5, -64 - Double(i) * 23), into: journeyRoot)
                    for j in 0..<3 { ring(4.08, tube: 0.16, tint: "FF8F5B", at: vector(0, Double(j) * 9 - 6, 0), into: tower, glow: true) }
                }
            }
        case .harbor: break
        }
        // Small foreground details scroll independently from fixed landmarks for real depth cues.
        if renderedStage != .orbit {
            let ground = box(360, 2, 300, palette.stone, at: vector(0, -4, -135), radius: 0, into: journeyRoot)
            if renderedStage != .forge {
                let groundMaterial = terrainSurface(tint: palette.stone, icy: renderedStage == .cryo).copy() as! SCNMaterial
                groundMaterial.diffuse.wrapS = .repeat; groundMaterial.diffuse.wrapT = .repeat
                groundMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(20, 18, 1)
                ground.geometry?.firstMaterial = groundMaterial
            }
            if renderedStage == .forge {
                ground.geometry?.firstMaterial = material("78392F", unique: true)
                ground.geometry?.firstMaterial?.emission.contents = color("BC4525")
                ground.geometry?.firstMaterial?.emission.intensity = 0.34
            }
        }
    }

    func deckMaterial(for stage: WorldStage) -> SCNMaterial {
        let key = "deck-v4-" + stage.rawValue
        if let existing = materials[key] { return existing }
        let palette = worldPalette
        let mat = material(palette.floor, unique: true)
        mat.roughness.contents = stage == .cryo ? 0.16 : stage == .mars || stage == .verdant ? 0.88 : 0.45
        mat.metalness.contents = stage == .orbit || stage == .forge ? 0.65 : 0.12
        mat.diffuse.contents = image(width: 1024, height: 1024) { ctx in
            ctx.setFillColor(color(palette.floor).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            ctx.saveGState(); ctx.scaleBy(x: 4.0 / 3.0, y: 4.0 / 3.0)
            for i in 0..<2200 {
                let x = (i * 229 + 47) % 768, y = (i * 367 + 19) % 768
                ctx.setFillColor(color(i % 2 == 0 ? "D3D1C0" : "111C2B", alpha: stage == .mars ? 0.14 : 0.045).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: i % 4 + 1, height: i % 5 + 1))
            }
            switch stage {
            case .orbit, .forge:
                for row in 0..<6 { for column in 0..<3 {
                    let rect = CGRect(x: column * 256 + 7, y: row * 128 + 7, width: 242, height: 114)
                    ctx.setStrokeColor(color(stage == .orbit ? "7E93A8" : "79656B", alpha: 0.52).cgColor); ctx.setLineWidth(2); ctx.stroke(rect)
                    ctx.setFillColor(color("0B182B", alpha: 0.55).cgColor)
                    for side in [0, 1] { for end in [0, 1] { ctx.fillEllipse(in: CGRect(x: rect.minX + 8 + Double(side) * 222, y: rect.minY + 8 + Double(end) * 94, width: 4, height: 4)) } }
                    for j in 0..<9 {
                        ctx.setStrokeColor(color(stage == .orbit ? "A1B1BD" : "DD9B64", alpha: 0.12).cgColor)
                        ctx.move(to: CGPoint(x: rect.minX + 25 + Double(j) * 21, y: rect.minY + 39)); ctx.addLine(to: CGPoint(x: rect.minX + 34 + Double(j) * 21, y: rect.minY + 48)); ctx.strokePath()
                    }
                } }
            case .mars:
                for x in [25.0, 743.0] {
                    ctx.setFillColor(color("DEBC89", alpha: 0.7).cgColor); ctx.fill(CGRect(x: x, y: 0, width: 6, height: 768))
                }
                for row in 0..<12 {
                    ctx.setStrokeColor(color("442F2D", alpha: 0.27).cgColor); ctx.setLineWidth(5)
                    ctx.move(to: CGPoint(x: 40, y: row * 64)); ctx.addLine(to: CGPoint(x: 728, y: row * 64 + 8)); ctx.strokePath()
                }
            case .verdant:
                for row in 0..<6 { for column in 0..<4 {
                    let rect = CGRect(x: column * 192 + (row % 2) * 22, y: row * 128, width: 187, height: 122)
                    ctx.setStrokeColor(color("102C2C", alpha: 0.9).cgColor); ctx.setLineWidth(5); ctx.stroke(rect)
                    ctx.setStrokeColor(color("90B99B", alpha: 0.14).cgColor); ctx.setLineWidth(1); ctx.stroke(rect.insetBy(dx: 7, dy: 7))
                    ctx.setFillColor(color("9EE4B5", alpha: 0.25).cgColor); ctx.fill(CGRect(x: rect.midX, y: rect.midY, width: 3, height: 13))
                } }
            case .cryo:
                for i in 0..<21 {
                    let x = Double((i * 149) % 768), y = Double((i * 211) % 768)
                    ctx.setStrokeColor(color("D9F6FA", alpha: 0.3).cgColor); ctx.setLineWidth(i % 4 == 0 ? 2 : 0.8)
                    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + 37, y: y + 49)); ctx.addLine(to: CGPoint(x: x + 21, y: y + 86)); ctx.addLine(to: CGPoint(x: x + 59, y: y + 128)); ctx.strokePath()
                }
            case .harbor: break
            }
            ctx.restoreGState()
            var rng: UInt64 = 0xDEC0_5EED &+ UInt64(stage.rawValue.unicodeScalars.reduce(0) { $0 &* 31 &+ UInt64($1.value) })
            func random() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double((rng >> 33) & 0xFFFF) / 65535 }
            // Lane wear: lanes at x = -2.6, 0, 2.6 m on the 8.5 m deck are polished by traffic.
            for lane in [-2.6, 0.0, 2.6] {
                let center = (lane + 4.25) / 8.5 * 1024
                for band in 0..<6 {
                    let width = 150.0 - Double(band) * 22
                    ctx.setFillColor(color(stage == .cryo ? "E4F4FA" : "0A121C", alpha: 0.018).cgColor)
                    ctx.fill(CGRect(x: center - width / 2, y: 0, width: width, height: 1024))
                }
            }
            // Scuffs.
            ctx.setLineCap(.round)
            for _ in 0..<160 {
                let x = random() * 1024, y = random() * 1024, length = 8 + random() * 40, angle = (random() - 0.5) * 0.6 + .pi / 2
                ctx.setStrokeColor(color(random() < 0.5 ? "05090F" : "C9CFD3", alpha: 0.10 + random() * 0.08).cgColor)
                ctx.setLineWidth(0.8 + random() * 1.6)
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length)); ctx.strokePath()
            }
            // Per-world decal layer.
            switch stage {
            case .orbit, .forge:
                let stripe = stage == .orbit ? "E9B44C" : "F08A3C"
                for edge in [30.0, 954.0] {
                    ctx.saveGState(); ctx.clip(to: CGRect(x: edge, y: 0, width: 40, height: 1024))
                    for y in stride(from: -40.0, to: 1064, by: 40) {
                        ctx.setFillColor(color(stripe, alpha: 0.35).cgColor)
                        ctx.move(to: CGPoint(x: edge, y: y)); ctx.addLine(to: CGPoint(x: edge + 40, y: y + 20))
                        ctx.addLine(to: CGPoint(x: edge + 40, y: y + 40)); ctx.addLine(to: CGPoint(x: edge, y: y + 20)); ctx.fillPath()
                    }
                    ctx.restoreGState()
                }
                if stage == .forge {
                    let temper = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("5A6BB0", alpha: 0.14).cgColor, color("B5652A", alpha: 0.10).cgColor, color("B5652A", alpha: 0).cgColor] as CFArray, locations: [0, 0.5, 1])!
                    for _ in 0..<5 {
                        let c = CGPoint(x: 150 + random() * 724, y: random() * 1024)
                        ctx.drawRadialGradient(temper, startCenter: c, startRadius: 0, endCenter: c, endRadius: 40 + random() * 60, options: [])
                    }
                }
            case .mars:
                for lane in [-2.6, 0.0, 2.6] {
                    let center = (lane + 4.25) / 8.5 * 1024
                    for track in [-45.0, 45.0] {
                        for y in stride(from: 0.0, to: 1024, by: 14) {
                            ctx.setFillColor(color("3A2522", alpha: 0.22).cgColor)
                            ctx.fill(CGRect(x: center + track - 9, y: y, width: 18, height: 6))
                        }
                    }
                }
                let dust = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("D9A37A", alpha: 0.22).cgColor, color("D9A37A", alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                for _ in 0..<10 {
                    let c = CGPoint(x: random() < 0.5 ? random() * 120 : 904 + random() * 120, y: random() * 1024)
                    ctx.drawRadialGradient(dust, startCenter: c, startRadius: 0, endCenter: c, endRadius: 50 + random() * 70, options: [])
                }
            case .verdant:
                for _ in 0..<70 {
                    // Tile joints of the scaled 768-space grid: 192 × 4/3 = 256 px columns, 128 × 4/3 px rows.
                    let joint = CGPoint(x: Double(Int(random() * 5)) * 256, y: Double(Int(random() * 7)) * 128 * 4 / 3)
                    ctx.setFillColor(color("4C8A5C", alpha: 0.28).cgColor)
                    ctx.fillEllipse(in: CGRect(x: joint.x - 14 + random() * 10, y: joint.y - 10 + random() * 8, width: 18 + random() * 22, height: 10 + random() * 14))
                }
                for _ in 0..<40 {
                    ctx.setFillColor(color("9EF4C8", alpha: 0.45).cgColor)
                    ctx.fillEllipse(in: CGRect(x: random() * 1024, y: random() * 1024, width: 3, height: 3))
                }
            case .cryo:
                let frost = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color("F2FBFF", alpha: 0.25).cgColor, color("F2FBFF", alpha: 0).cgColor] as CFArray, locations: [0, 1])!
                for _ in 0..<12 {
                    let c = CGPoint(x: random() * 1024, y: random() * 1024)
                    ctx.drawRadialGradient(frost, startCenter: c, startRadius: 0, endCenter: c, endRadius: 40 + random() * 80, options: [])
                }
            case .harbor: break
            }
        }
        mat.diffuse.wrapS = .repeat; mat.diffuse.wrapT = .repeat
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(1, 2, 1)
        mat.normal.contents = texture(stage == .cryo ? "water-normal" : "cloth-normal")
        mat.normal.intensity = stage == .cryo ? 0.09 : 0.10
        for prop in [mat.diffuse, mat.normal] { prop.mipFilter = .linear; prop.maxAnisotropy = 8 }
        materials[key] = mat
        return mat
    }

    func makeWorldSection(index: Int) -> SCNNode {
        let root = SCNNode()
        let palette = worldPalette
        let roadway = box(8.5, 0.55, 26, palette.floor, at: vector(0, -0.35, 0), radius: 0, into: root)
        roadway.geometry?.firstMaterial = deckMaterial(for: renderedStage)
        // The three travel lanes remain legible in every biome. All tall scenery stays outside ±5m.
        for side in [-1.0, 1.0] {
            box(0.28, 0.5, 26, palette.edge, at: vector(side * 4.25, -0.03, 0), radius: 0, into: root)
            glowBox(0.075, 0.04, 26, palette.glow, at: vector(side * 4.15, 0.24, 0), into: root)
        }
        for x in [-1.3, 1.3] {
            for j in 0..<4 {
                let marker = glowBox(renderedStage == .verdant ? 0.11 : 0.045, 0.012,
                                    renderedStage == .cryo ? 0.36 : renderedStage == .verdant ? 0.18 : 1.2,
                                    palette.edge, at: vector(x, -0.063, -10 + Double(j) * 6.5), into: root)
                if renderedStage == .verdant { marker.eulerAngles.y = scalar(.pi / 4) }
            }
        }
        // World-specific near-field construction replaces the same painted road in each biome.
        for z in [-12.0, -6, 0, 6, 12] {
            switch renderedStage {
            case .orbit:
                for x in [-2.65, 0, 2.65] {
                    box(2.35, 0.025, 0.085, "667B91", at: vector(x, -0.052, z), radius: 0, into: root)
                    for side in [-1.0, 1.0] { box(0.11, 0.06, 0.25, "ABB4B6", at: vector(x + side * 1.07, -0.025, z), radius: 0.02, into: root) }
                }
            case .mars:
                for side in [-1.0, 1.0] {
                    let cable = cylinder(0.075, 5.8, "543D37", at: vector(side * 3.92, 0.10, z), into: root)
                    cable.eulerAngles.x = scalar(.pi / 2)
                    box(0.48, 0.18, 0.8, "C4AA8C", at: vector(side * 4.3, 0.22, z), radius: 0.06, into: root)
                }
            case .verdant:
                for side in [-1.0, 1.0] {
                    let tendril = capsule(0.13, 2.2, "416B52", at: vector(side * 4.48, 0.02, z), into: root)
                    tendril.eulerAngles = vector(.pi / 2, side * 0.2, 0)
                    sphere(0.15, "92DCA9", at: vector(side * 4.45, 0.2, z + 1), scale: vector(1, 0.5, 1), into: root)
                }
            case .cryo:
                for side in [-1.0, 1.0] {
                    let frozen = box(0.7, 0.14, 1.5, "B3D8E5", at: vector(side * 3.82, 0.02, z), radius: 0.05, into: root)
                    frozen.geometry?.firstMaterial = iceMaterial(); frozen.eulerAngles.y = scalar(side * 0.18)
                }
            case .forge:
                box(8.2, 0.055, 0.14, "6D6670", at: vector(0, -0.04, z), radius: 0, into: root)
                for side in [-1.0, 1.0] {
                    let vent = box(0.5, 0.15, 1.1, "151E2A", at: vector(side * 3.80, 0.04, z), radius: 0, into: root)
                    for k in 0..<4 { glowBox(0.35, 0.018, 0.06, "F5AD6C", at: vector(0, 0.08, -0.36 + Double(k) * 0.23), into: vent) }
                }
            case .harbor: break
            }
        }
        let deckNodes = Set(root.childNodes.map { ObjectIdentifier($0) })
        switch renderedStage {
        case .orbit:
            for side in [-1.0, 1.0] {
                for z in [-8.0, 6.0] {
                    let beam = box(0.45, 5.5, 0.55, "677C96", at: vector(side * 5.3, -2.8, z), radius: 0, into: root)
                    beam.eulerAngles.z = scalar(side * 0.5)
                    box(4, 0.3, 0.7, "697C94", at: vector(side * 5.7, -1.2, z), radius: 0, into: root)
                    glowBox(0.3, 0.22, 1.1, "9DEAFF", at: vector(side * 4.5, 0.25, z), into: root)
                }
                if index % 2 == 0 {
                    let sat = SCNNode(); sat.position = vector(side * (14 + Double(index % 3) * 3), 3 + Double(index % 2), -4)
                    box(1.5, 1.8, 1.7, "BAA995", radius: 0.2, into: sat)
                    for x in [-4.0, 4.0] {
                        box(5.5, 0.12, 3.5, "173A70", at: vector(x, 0, 0), radius: 0, into: sat)
                        for k in -2...2 { glowBox(0.045, 0.02, 3.4, "619DD1", at: vector(x + Double(k), 0.08, 0), into: sat) }
                    }
                    cylinder(0.05, 3.5, "C1D1DE", at: vector(0, 2, 0), into: sat)
                    sat.eulerAngles = vector(0.2, Double(index) * 0.6, side * 0.25)
                    root.addChildNode(sat)
                }
            }
            if index % 3 == 0 {
                for side in [-1.0, 1.0] {
                    let mast = box(0.55, 8, 0.8, "7B8EA4", at: vector(side * 5.8, 3.8, -7), radius: 0.08, into: root)
                    mast.eulerAngles.z = scalar(side * -0.15)
                    glowBox(0.08, 6.6, 0.1, "80D6EC", at: vector(side * 5.15, 3.6, -6.5), into: root)
                }
                // Keep the top of the vista open: support pylons sit outside the track.
            }
        case .mars:
            for side in [-1.0, 1.0] {
                makeTerrain(into: root, side: side, index: index, tint: index % 2 == 0 ? "A85B3E" : "BD7047", height: 7 + Double(index % 4) * 3, icy: false)
                for j in 0..<3 {
                    makeRock(into: root, at: vector(side * (6.7 + Double(j) * 3.7), -0.9, Double(j) * 7 - 9), size: 0.9 + Double((index + j) % 4) * 0.5, tint: "BE7653")
                }
            }
            if index % 3 == 1 { makeRover(into: root, at: vector(index % 2 == 0 ? -9 : 9, -0.5, 2)) }
            if index % 3 == 2 {
                let crater = ring(3.4, tube: 0.8, tint: "733E35", at: vector(11, -1, -5), into: root)
                crater.scale.y = scalar(0.3)
            }
        case .verdant:
            for side in [-1.0, 1.0] {
                box(10, 1, 26, "294D43", at: vector(side * 10.5, -0.8, 0), radius: 0, into: root)
                makeAlienTree(into: root, at: vector(side * (8 + Double(index % 3)), -0.2, -5), size: 0.65 + Double(index % 4) * 0.15)
                for j in 0..<4 {
                    makeCrystal(into: root, at: vector(side * (5.7 + Double(j) * 1.4), -0.2, Double(j) * 4 - 5), height: 0.6 + Double((j + index) % 4) * 0.35, tint: j % 2 == 0 ? "81DAB6" : "756BC4")
                }
                let ruin = box(1.7, 5 + Double(index % 3), 1.6, "42695D", at: vector(side * 14, 2.1, 6), radius: 0.15, into: root)
                ruin.eulerAngles.z = scalar(side * 0.14)
                for j in 0..<3 { glowBox(0.6, 0.1, 0.025, "85E9C8", at: vector(side * 14, Double(j) * 0.8 + 1, 6.82), into: root) }
            }
        case .cryo:
            for side in [-1.0, 1.0] {
                makeTerrain(into: root, side: side, index: index, tint: "7097B7", height: 6 + Double(index % 3) * 4, icy: true)
                for j in 0..<4 {
                    makeCrystal(into: root, at: vector(side * (6.5 + Double(j) * 2.3), -0.3, Double(j) * 5.5 - 10), height: 2 + Double((j + index) % 4) * 1.1, tint: "A8DDEB")
                }
                if index % 3 == 0 {
                    let arch = ring(7.2, tube: 0.8, tint: "BBDFE8", at: vector(side * 11, 0, -7), into: root)
                    arch.eulerAngles.x = scalar(.pi / 2); arch.scale.y = scalar(1.5)
                    arch.geometry?.firstMaterial = iceMaterial()
                }
            }
        case .forge:
            for side in [-1.0, 1.0] {
                box(2.6, 1.0, 26, "51434B", at: vector(side * 6.2, -0.8, 0), radius: 0, into: root)
                let lava = glowBox(2, 0.08, 26, "ED642D", at: vector(side * 6.2, -0.15, 0), into: root)
                lava.geometry?.firstMaterial = material("C64D24", unique: true)
                lava.geometry?.firstMaterial?.emission.contents = color("FF6929")
                lava.geometry?.firstMaterial?.emission.intensity = 0.6
                for j in 0..<3 {
                    box(4.3, 0.3, 0.6, "968078", at: vector(side * 6.5, 0.3, Double(j) * 9 - 9), radius: 0, into: root)
                    let pipe = cylinder(0.6, 26, "685962", at: vector(side * 9.2, 0.6, 0), into: root)
                    pipe.eulerAngles.x = scalar(.pi / 2)
                }
                let tower = cylinder(1.5, 8, "59434B", at: vector(side * 12.5, 2.8, -7), into: root)
                for k in 0..<4 { ring(1.55, tube: 0.12, tint: "FE9559", at: vector(0, Double(k) * 1.8 - 2.7, 0), into: tower, glow: true) }
                sphere(0.8, "F4995F", at: vector(side * 12.5, 7.0, -7), into: root).geometry?.firstMaterial = material("FFBA80", emissive: true)
            }
            if index % 2 == 0 {
                for side in [-1.0, 1.0] {
                    let pylon = box(1.2, 13, 1.1, "685761", at: vector(side * 7.4, 4.8, -8), radius: 0.12, into: root)
                    pylon.eulerAngles.z = scalar(side * -0.16)
                }
                box(12.5, 1.2, 1.2, "6A5961", at: vector(0, 11.2, -8), radius: 0.12, into: root)
                glowBox(10.2, 0.16, 0.1, "F5A277", at: vector(0, 10.7, -7.34), into: root)
            }
        case .harbor: break
        }
        let deckRoot = SCNNode(), sceneryRoot = SCNNode()
        for child in root.childNodes {
            (deckNodes.contains(ObjectIdentifier(child)) ? deckRoot : sceneryRoot).addChildNode(child)
        }
        let result = SCNNode()
        let deck = flattenPreservingHierarchy(deckRoot); deck.name = "routeDeck"
        let scenery = flattenPreservingHierarchy(sceneryRoot); scenery.name = "routeScenery"
        result.addChildNode(deck); result.addChildNode(scenery)
        return result
    }

    func terrainSurface(tint: String, icy: Bool) -> SCNMaterial {
        let key = "strata-" + tint
        if let cached = materials[key] { return cached }
        let surface = material(tint, unique: true)
        surface.isDoubleSided = true
        surface.roughness.contents = icy ? 0.38 : 0.96
        surface.metalness.contents = icy ? 0.18 : 0
        surface.diffuse.contents = image(width: 1024, height: 512) { ctx in
            ctx.setFillColor(color(tint).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
            for y in 0..<512 {
                let wave = sin(Double(y) * 0.19) * 0.5 + sin(Double(y) * 0.67) * 0.3
                ctx.setStrokeColor(color(wave > 0 ? (icy ? "CCE9EF" : "E6B38C") : "272630", alpha: abs(wave) * (icy ? 0.17 : 0.25)).cgColor)
                ctx.setLineWidth(1 + Double(y % 3))
                ctx.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0, through: 1024, by: 16) {
                    ctx.addLine(to: CGPoint(x: Double(x), y: Double(y) + sin(Double(x) * 0.007 + Double(y) * 0.024) * 8))
                }
                ctx.strokePath()
            }
            for i in 0..<5200 {
                ctx.setFillColor(color(i % 3 == 0 ? "EDC6A4" : "25212B", alpha: 0.09).cgColor)
                ctx.fill(CGRect(x: (i * 223) % 1024, y: (i * 157) % 512, width: i % 3 + 1, height: 1))
            }
        }
        if renderedStage == .mars, !icy, let rockAlbedo = loadAsset("MarsRock-v4") {
            surface.diffuse.contents = rockAlbedo
            surface.diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        }
        surface.diffuse.wrapS = .repeat; surface.diffuse.wrapT = .repeat
        surface.normal.contents = texture("cloth-normal"); surface.normal.intensity = icy ? 0.08 : 0.28
        for prop in [surface.diffuse, surface.normal] { prop.mipFilter = .linear; prop.maxAnisotropy = 8 }
        materials[key] = surface
        return surface
    }

    func terrainMesh(vertices: [SCNVector3], indices: [Int32], tint: String, icy: Bool) -> SCNNode {
        var normals = Array(repeating: SIMD3<Float>(repeating: 0), count: vertices.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            let a = vertices[ia], b = vertices[ib], c = vertices[ic]
            let ab = SIMD3<Float>(Float(b.x - a.x), Float(b.y - a.y), Float(b.z - a.z))
            let ac = SIMD3<Float>(Float(c.x - a.x), Float(c.y - a.y), Float(c.z - a.z))
            var n = simd_cross(ab, ac)
            if n.y < 0 { n = -n }
            normals[ia] += n; normals[ib] += n; normals[ic] += n
        }
        let unitNormals = normals.map { n -> SCNVector3 in
            let normal = simd_length_squared(n) > 0.0001 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0)
            return vector(Double(normal.x), Double(normal.y), Double(normal.z))
        }
        let coordinates = vertices.map { CGPoint(x: Double($0.x + $0.z) * 0.035, y: Double($0.y) * 0.08) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: unitNormals), SCNGeometrySource(textureCoordinates: coordinates)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.firstMaterial = terrainSurface(tint: tint, icy: icy)
        return SCNNode(geometry: geometry)
    }

    func makeDistantMountains(tint: String, icy: Bool) {
        // Irregular connected ridgelines: each peak has shoulders and secondary erosion features.
        for layer in 0..<3 {
            var vertices: [SCNVector3] = [], indices: [Int32] = []
            let columns = 144, rows = 7
            for row in 0..<rows { for column in 0..<columns {
                let x = -230 + Double(column) * 460 / Double(columns - 1)
                let phase = Double(column) * 0.115 + Double(layer) * 1.7
                let erosion = (Self.valueNoise(Double(column) * 0.09, Double(layer) * 3.1, 11) - 0.5) * 10
                let ridge = 22 + pow(abs(sin(phase)), 1.6) * 22 + sin(phase * 2.7) * 6 + cos(phase * 5.3) * 2.5 + erosion
                let crest = 1 - abs(Double(row) - 3) / 3.5
                let y = -7 + ridge * crest * (0.65 + Double(layer) * 0.22)
                vertices.append(vector(x, y, -172 - Double(layer) * 29 - Double(row) * 7.3))
            } }
            for row in 0..<(rows - 1) { for column in 0..<(columns - 1) {
                let a = Int32(row * columns + column), b = a + Int32(columns)
                indices += [a, a + 1, b, a + 1, b + 1, b]
            } }
            let mountain = terrainMesh(vertices: vertices, indices: indices, tint: tint, icy: icy)
            mountain.castsShadow = false
            journeyRoot.addChildNode(mountain)
        }
    }

    func makeTerrain(into root: SCNNode, side: Double, index: Int, tint: String, height: Double, icy: Bool) {
        let columns = 41, rows = 11
        let vertices = Self.terrainVertices(side: side, index: index, icy: icy, columns: columns, rows: rows).map { vector($0.x, $0.y, $0.z) }
        var indices: [Int32] = []
        for row in 0..<(rows - 1) { for column in 0..<(columns - 1) {
            let a = Int32(row * columns + column), b = a + Int32(columns)
            if side > 0 { indices += [a, b, a + 1, a + 1, b, b + 1] }
            else { indices += [a, a + 1, b, a + 1, b + 1, b] }
        } }
        root.addChildNode(terrainMesh(vertices: vertices, indices: indices, tint: tint, icy: icy))
    }

    func makeRock(into root: SCNNode, at position: SCNVector3, size: Double, tint: String) {
        let variant = Int(abs(Double(position.x) * 7 + Double(position.z) * 13))
        let surface = renderedStage == .mars ? terrainSurface(tint: tint, icy: false) : material(tint)
        let node = rockNode(size: size, material: surface, variant: variant)
        node.position = position
        node.eulerAngles = vector(0.2, Double(position.z), 0.3)
        root.addChildNode(node)
    }

    func makeCrystal(into root: SCNNode, at position: SCNVector3, height: Double, tint: String) {
        let cluster = crystalCluster(height: height, material: renderedStage == .cryo ? iceMaterial() : material(tint))
        cluster.position = position
        cluster.eulerAngles.z = scalar(sin(Double(position.z)) * 0.22)
        root.addChildNode(cluster)
        let spark = sphere(0.06, tint, at: vector(0, height, 0), into: cluster)
        spark.geometry?.firstMaterial = material(tint, emissive: true)
    }

    func iceMaterial() -> SCNMaterial {
        let key = "journey-ice"
        if let result = materials[key] { return result }
        let result = material("A4D1E1", unique: true)
        result.roughness.contents = 0.18; result.metalness.contents = 0.25
        result.normal.contents = texture("water-normal"); result.normal.intensity = 0.14
        result.fresnelExponent = 2
        materials[key] = result; return result
    }

    func makeAlienTree(into root: SCNNode, at position: SCNVector3, size: Double) {
        let tree = alienTreeNode(size: size, outward: Double(position.x) < 0 ? -1 : 1)
        tree.position = position
        root.addChildNode(tree)
    }

    func makeRover(into root: SCNNode, at position: SCNVector3) {
        let rover = SCNNode(); rover.position = position; rover.eulerAngles.y = scalar(-0.5)
        box(2.5, 1, 3.2, "D7CAB3", at: vector(0, 0.9, 0), radius: 0.15, into: rover)
        box(1.4, 0.8, 1.5, "BDBFAF", at: vector(0, 1.7, -0.3), radius: 0.12, into: rover)
        for side in [-1.0, 1.0] { for z in [-1.1, 0, 1.1] {
            let tire = cylinder(0.54, 0.4, "353840", at: vector(side * 1.35, 0.43, z), into: rover)
            tire.eulerAngles.z = scalar(.pi / 2)
        } }
        cylinder(0.08, 2.4, "ADA998", at: vector(0, 2.5, 0.2), into: rover)
        box(0.8, 0.25, 0.35, "314356", at: vector(0, 3.7, 0.2), radius: 0.08, into: rover)
        root.addChildNode(rover)
    }

    func makeAurora(tint: String, height: Double) {
        let geometry = SCNPlane(width: 280, height: 35)
        geometry.widthSegmentCount = 40
        let mat = material(tint, unique: true)
        mat.lightingModel = .constant; mat.isDoubleSided = true
        mat.blendMode = .add; mat.writesToDepthBuffer = false
        mat.transparency = 0.999
        mat.shaderModifiers = [.surface: """
        #pragma transparent
        #pragma body
        float2 uv = _surface.diffuseTexcoord;
        float ribbon = sin(uv.x * 17.0 + scn_frame.time * 0.1) * 0.12 + 0.45;
        float falloff = exp(-abs(uv.y - ribbon) * 12.0);
        float curtains = 0.45 + 0.55 * pow(sin(uv.x * 120.0 + sin(uv.x * 23.0)) * 0.5 + 0.5, 2.0);
        _surface.diffuse.rgb *= falloff * curtains * 0.35;
        _surface.diffuse.a = falloff * curtains * 0.35;
        """]
        geometry.firstMaterial = mat
        let node = SCNNode(geometry: geometry); node.position = vector(0, height, -220)
        node.castsShadow = false; node.renderingOrder = -1; journeyRoot.addChildNode(node)
    }

    func makeSignatureHazard(_ kind: EntityKind) -> SCNNode? {
        let root = SCNNode()
        switch kind {
        case .gap:
            // A void inset and broken deck lips distinguish jumps from a solid barricade.
            let void = box(2.58, 0.045, 7, "020610", at: vector(0, 0.015, 0), radius: 0, into: root)
            void.geometry?.firstMaterial = material("020610", unique: true)
            void.geometry?.firstMaterial?.lightingModel = .constant
            for side in [-1.0, 1.0] {
                box(0.09, 0.25, 7.1, "687F9B", at: vector(side * 1.27, 0.02, 0), radius: 0, into: root)
                glowBox(0.05, 0.03, 7, "75DDEC", at: vector(side * 1.21, 0.17, 0), into: root)
            }
            for z in [-3.5, 3.5] {
                box(2.6, 0.20, 0.22, "8297AE", at: vector(0, 0.02, z), radius: 0.03, into: root)
                for x in [-0.9, -0.3, 0.3, 0.9] {
                    let arrow = glowBox(0.27, 0.025, 0.18, "FFCF83", at: vector(x, 0.15, z), into: root)
                    arrow.eulerAngles.y = scalar(.pi / 4)
                }
            }
        case .meteor:
            let target = SCNNode(); target.name = "target"; root.addChildNode(target)
            for i in 0..<3 { ring(0.7 + Double(i) * 0.25, tube: 0.035, tint: "FF7547", at: vector(0, 0.03 + Double(i) * 0.005, 0), into: target, glow: true) }
            for side in [-1.0, 1.0] { glowBox(0.04, 0.02, 2.6, "FFAA72", at: vector(side * 1.12, 0.06, 0), into: target) }
            let rock = SCNNode(); rock.name = "impactRock"; root.addChildNode(rock)
            makeRock(into: rock, at: SCNVector3Zero, size: 1.05, tint: "624139")
            for i in 0..<6 {
                let angle = Double(i) * .pi / 3
                let fissure = glowBox(0.05, 0.75, 0.06, "F89454", at: vector(cos(angle) * 0.73, 0, sin(angle) * 0.73), into: rock)
                fissure.eulerAngles.z = scalar(angle)
            }
            let tail = sphere(0.45, "F4B07A", at: vector(0.3, 1.6, -0.5), scale: vector(1, 2.4, 1), into: rock)
            tail.geometry?.firstMaterial = material("EF7844", emissive: true); tail.opacity = 0.3; tail.castsShadow = false
        case .root:
            let crown = SCNNode(); crown.name = "rootCrown"; root.addChildNode(crown)
            for i in 0..<7 {
                let x = -0.98 + Double(i) * 0.33
                let wood = capsule(0.20, 1.05, i % 2 == 0 ? "315F4B" : "5E8161", at: vector(x, 0.42 + sin(Double(i)) * 0.09, 0), into: crown)
                wood.eulerAngles = vector(0.23, 0, i % 2 == 0 ? 0.65 : -0.65)
                let vein = sphere(0.04, "94F3B6", at: vector(x, 0.87, 0.18), into: crown)
                vein.geometry?.firstMaterial = material("94F3B6", emissive: true)
            }
            for side in [-1.0, 1.0] {
                let leaf = sphere(0.65, "386852", at: vector(side * 0.92, 0.36, 0.30), scale: vector(0.65, 0.11, 1), into: crown)
                leaf.eulerAngles = vector(-0.15, side * 0.7, side * 0.35)
            }
            glowBox(1.8, 0.035, 0.045, "CAEEB4", at: vector(0, 0.96, 0.28), into: root)
        case .iceCrack:
            let fissure = box(2.5, 0.05, 3.2, "0B2449", at: vector(0, 0.015, 0), radius: 0, into: root)
            fissure.geometry?.firstMaterial = material("10253E", unique: true)
            fissure.geometry?.firstMaterial?.lightingModel = .constant
            for side in [-1.0, 1.0] {
                for i in 0..<6 {
                    let shard = box(0.65, 0.15, 0.40, "B9E7EF", at: vector(side * (0.95 + Double(i % 2) * 0.16), 0.06, -1.4 + Double(i) * 0.55), radius: 0, into: root)
                    shard.eulerAngles.y = scalar(side * (i % 2 == 0 ? 0.45 : -0.2))
                    shard.geometry?.firstMaterial = iceMaterial()
                }
            }
            let warning = SCNNode(); warning.name = "crackWarning"; root.addChildNode(warning)
            for z in [-1.65, 1.65] { glowBox(2.3, 0.025, 0.07, "B5EFFF", at: vector(0, 0.12, z), into: warning) }
        case .laserSweep:
            for side in [-1.0, 1.0] {
                cylinder(0.20, 2.3, renderedStage == .verdant ? "456B55" : "635463", at: vector(side * 1.10, 1.14, 0), into: root)
                let emitter = sphere(0.27, "E1845E", at: vector(side * 1.10, 1.38, 0), into: root)
                emitter.geometry?.firstMaterial = material("FF9870", emissive: true)
                for i in 0..<3 { ring(0.22, tube: 0.04, tint: "29323F", at: vector(side * 1.10, 1.9 + Double(i) * 0.11, 0), into: root) }
            }
            let beam = glowBox(2.12, 0.13, 0.13, "FF896D", at: vector(0, 1.40, 0), into: root)
            beam.name = "beam"
            let bloom = glowBox(2.1, 0.38, 0.035, "FF8769", at: vector(0, 1.40, 0), into: root)
            bloom.opacity = 0.20; bloom.geometry?.firstMaterial?.writesToDepthBuffer = false
            for side in [-1.0, 1.0] {
                let chevron = glowBox(0.37, 0.08, 0.05, "FFF0D1", at: vector(side * 0.14, 1.92, 0), into: root)
                chevron.eulerAngles.z = scalar(side * 0.6)
            }
        case .waterTraffic:
            let hull = sculptedMesh(rings: [(-0.25, 0.50, 1.70), (0, 0.90, 2.50), (0.22, 1.02, 2.28), (0.40, 0.76, 1.95)], tint: "DFE6E7")
            hull.position.y = scalar(0.18); root.addChildNode(hull)
            box(1.4, 0.27, 3.65, "BB513D", at: vector(0, 0.65, 0), radius: 0.12, into: root)
            box(1.02, 0.62, 1.35, "264A5D", at: vector(0, 1.0, -0.30), radius: 0.18, into: root)
            box(1.24, 0.12, 1.85, "EBE8D8", at: vector(0, 1.36, -0.25), radius: 0.08, into: root)
            for side in [-1.0, 1.0] {
                glowBox(0.09, 0.10, 3.6, "FFA978", at: vector(side * 0.84, 0.51, 0), into: root)
                cylinder(0.04, 0.65, "9BB6C4", at: vector(side * 0.65, 1.03, 0.75), into: root)
                let bowLamp = sphere(0.09, side < 0 ? "FF7D73" : "78E7C0", at: vector(side * 0.78, 0.63, 1.78), into: root)
                bowLamp.geometry?.firstMaterial = material(side < 0 ? "FF7D73" : "78E7C0", emissive: true)
            }
            let foam = SCNPlane(width: 2.8, height: 7)
            let foamMat = SCNMaterial(); foamMat.diffuse.contents = texture("wake"); foamMat.lightingModel = .constant
            foamMat.isDoubleSided = true; foamMat.writesToDepthBuffer = false; foam.firstMaterial = foamMat
            let wakeNode = SCNNode(geometry: foam); wakeNode.eulerAngles.x = scalar(-.pi / 2); wakeNode.position = vector(0, 0.015, -4.2)
            wakeNode.opacity = 0.65; wakeNode.castsShadow = false; root.addChildNode(wakeNode)
        default: return nil
        }
        return root
    }

    func makeWorldObstacle(_ kind: EntityKind) -> SCNNode? {
        let palette = worldPalette
        let root = SCNNode()
        switch kind {
        case .barrier:
            // Jumpable obstacles keep the same collision silhouette even when their material changes.
            if renderedStage == .cryo {
                box(2.05, 0.92, 0.92, "A6D9E9", at: vector(0, 0.48, 0), radius: 0.16, into: root).geometry?.firstMaterial = iceMaterial()
                for x in [-0.65, 0, 0.65] { makeCrystal(into: root, at: vector(x, 0.62, 0), height: 0.48, tint: "BAE9F0") }
            } else {
                box(2.05, 0.96, 0.95, palette.stone, at: vector(0, 0.51, 0), radius: 0.12, into: root)
                for x in [-0.7, 0.7] { box(0.12, 1.0, 1.0, palette.edge, at: vector(x, 0.52, 0), radius: 0.015, into: root) }
            }
            glowBox(1.75, 0.10, 0.025, "FFB369", at: vector(0, 0.89, 0.5), into: root)
        case .arch:
            for side in [-1.0, 1.0] {
                box(0.25, 2.5, 0.42, palette.edge, at: vector(side * 1.06, 1.2, 0), radius: 0.06, into: root)
            }
            box(2.3, 0.62, 0.7, palette.stone, at: vector(0, 2.0, 0), radius: 0.1, into: root)
            glowBox(2.08, 0.12, 0.05, "FF8964", at: vector(0, 1.74, 0.38), into: root)
            for x in [-0.72, 0, 0.72] {
                let stripe = box(0.22, 0.4, 0.035, "F1C294", at: vector(x, 2.04, 0.375), radius: 0, into: root)
                stripe.eulerAngles.z = scalar(-0.35)
            }
        case .tram:
            box(2.1, 2.8, 7.8, palette.stone, at: vector(0, 1.4, 0), radius: 0.23, into: root)
            box(2.15, 0.23, 7.9, palette.edge, at: vector(0, 2.83, 0), radius: 0.08, into: root)
            for x in [-0.91, 0.91] {
                glowBox(0.05, 0.13, 7.75, palette.glow, at: vector(x, 2.53, 0), into: root)
            }
            if renderedStage == .mars {
                for side in [-1.0, 1.0] { for z in [-2.7, 0, 2.7] {
                    let wheel = cylinder(0.55, 0.15, "343946", at: vector(side * 1.08, 0.55, z), into: root)
                    wheel.eulerAngles.z = scalar(.pi / 2)
                } }
                box(1.75, 0.7, 0.04, "294454", at: vector(0, 1.92, 3.92), radius: 0.1, into: root)
            } else {
                for z in [-2.7, -0.9, 0.9, 2.7] {
                    box(2.14, 2.5, 0.12, palette.edge, at: vector(0, 1.35, z), radius: 0, into: root)
                }
                if renderedStage == .cryo {
                    root.childNodes.first?.geometry?.firstMaterial = iceMaterial()
                }
            }
            for x in [-0.7, 0.7] { glowBox(0.34, 0.2, 0.045, "FFC889", at: vector(x, 0.7, 3.93), into: root) }
            let beacon = sphere(0.13, "FF694C", at: vector(0, 3.08, 3.4), into: root)
            beacon.name = "warningBeacon"; beacon.geometry?.firstMaterial = material("FF694C", emissive: true)
        case .ramp:
            let ramp = makeRamp()
            ramp.childNodes.first?.geometry?.firstMaterial = material(palette.edge)
            return ramp
        case .airHazard:
            let drone = makeAirRing(hazard: true)
            for x in [-0.8, 0.8] { glowBox(0.25, 0.05, 0.8, "FF714C", at: vector(x, 0.15, 0), into: drone) }
            return drone
        default: return nil
        }
        let shade = shadow(width: 2.4, length: kind == .tram ? 8 : 1.4)
        shade.position.y = scalar(0.012); root.addChildNode(shade)
        return root
    }

    func makeWorldRelic() -> SCNNode {
        let root = SCNNode()
        let tint = worldPalette.glow
        let orb = SCNPyramid(width: 0.62, height: 0.75, length: 0.62)
        orb.firstMaterial = material(tint, emissive: true)
        let top = SCNNode(geometry: orb); top.position.y = scalar(-0.02); root.addChildNode(top)
        let bottom = SCNNode(geometry: orb); bottom.eulerAngles.z = scalar(.pi); root.addChildNode(bottom)
        for i in 0..<2 {
            let orbit = ring(0.65 + Double(i) * 0.14, tube: 0.045, tint: "F3D99B", at: SCNVector3Zero, into: root, glow: true)
            orbit.eulerAngles = vector(.pi / 2, Double(i) * .pi / 2, 0.45)
        }
        return root
    }

    func makePortal() {
        scene.rootNode.addChildNode(portal)
        portal.isHidden = true
        for i in 0..<4 {
            let loop = ring(4.4 + Double(i) * 0.28, tube: i == 0 ? 0.15 : 0.06,
                            tint: i % 2 == 0 ? "83EFF4" : "BD9CFA", at: vector(0, 4.45, -Double(i) * 0.1), into: portal, glow: true)
            loop.eulerAngles.x = scalar(.pi / 2); portalLoops.append(loop)
        }
        for i in 0..<24 {
            let angle = Double(i) / 24 * .pi * 2
            let glyph = box(0.12, i % 3 == 0 ? 0.48 : 0.2, 0.08, "C4F3FF",
                            at: vector(sin(angle) * 4.95, 4.45 + cos(angle) * 4.95, 0.12), radius: 0, into: portal)
            glyph.eulerAngles.z = scalar(-angle)
            glyph.geometry?.firstMaterial = material("C4F3FF", emissive: true)
        }
        let disk = SCNPlane(width: 8.65, height: 8.65)
        let field = SCNMaterial()
        field.lightingModel = .constant; field.isDoubleSided = true; field.writesToDepthBuffer = false
        field.diffuse.contents = color("56C6E3"); field.blendMode = .alpha
        field.transparency = 0.999
        field.shaderModifiers = [.surface: """
        #pragma transparent
        #pragma body
        float2 uv = (_surface.diffuseTexcoord - 0.5) * 2.0;
        float r = length(uv);
        if (r > 0.999) discard_fragment();
        float a = atan2(uv.y, uv.x);
        float spiral = sin(a * 5.0 + r * 22.0 - scn_frame.time * 4.0) * 0.5 + 0.5;
        float ring = pow(1.0 - abs(sin(r * 18.0 - scn_frame.time)), 7.0);
        float center = exp(-r * r * 13.0);
        float3 nebula = mix(float3(0.12, 0.07, 0.3), float3(0.13, 0.56, 0.73), spiral * 0.7);
        _surface.diffuse.rgb = nebula + ring * float3(0.13, 0.25, 0.3) + center * float3(0.75, 0.9, 1.0);
        _surface.diffuse.a = (1.0 - smoothstep(0.92, 1.0, r)) * 0.96;
        """]
        disk.firstMaterial = field
        let fieldNode = SCNNode(geometry: disk); fieldNode.position = vector(0, 4.45, -0.22)
        fieldNode.castsShadow = false; portal.addChildNode(fieldNode); portalSurface = fieldNode
        for i in 0..<32 {
            let spark = sphere(0.025 + Double(i % 3) * 0.016, "A2F3FF", at: SCNVector3Zero, into: portal)
            spark.geometry?.firstMaterial = material(i % 2 == 0 ? "8FDFFF" : "C4A0FF", emissive: true)
            spark.castsShadow = false; portalSpecks.append(spark)
        }
        // A camera-space veil masks the world replacement, then clears onto the new landing strip.
        let veil = SCNPlane(width: 8, height: 8)
        let mat = SCNMaterial(); mat.lightingModel = .constant
        mat.diffuse.contents = color("A7E5FC"); mat.writesToDepthBuffer = false; mat.readsFromDepthBuffer = false
        veil.firstMaterial = mat; warpVeil.geometry = veil; warpVeil.position.z = scalar(-0.4)
        warpVeil.renderingOrder = 1000; warpVeil.opacity = 0; warpVeil.castsShadow = false
        camera.addChildNode(warpVeil)
    }

    func updateJourney(simulation: RunnerSimulation, time: Double, menu: Bool, travel: Double) {
        for (index, section) in journeySections.enumerated() {
            section.isHidden = qualityLevel == 0 && index > 6
            let z = travel.truncatingRemainder(dividingBy: 26) - Double(index) * 26 + 13
            placeRouteSection(section, centerZ: z, localCenterZ: 0, length: 26,
                              simulation: simulation, menu: menu)
        }
        portalSurface?.isHidden = reducedMotion
        let odyssey = (menu ? previewMode : simulation.mode) == .odyssey
        let transitioning = odyssey && simulation.isPortalTransitioning && !menu
        let remaining = simulation.portalDistance
        portal.isHidden = !odyssey || menu || (remaining == nil && !transitioning)
        if !portal.isHidden {
            portal.position.z = scalar(transitioning ? -4.5 - simulation.portalTransitionProgress * 8 : -max(4.5, remaining ?? 4.5))
            let pulse = reducedMotion ? 1 : 1 + sin(time * 2.8) * 0.012
            portal.scale = vector(pulse, pulse, 1)
            for (i, loop) in portalLoops.enumerated() {
                loop.eulerAngles.z = scalar(reducedMotion ? 0 : sin(time * 0.5 + Double(i)) * 0.04)
                loop.opacity = reducedMotion ? 0.88 : 0.8 + sin(time * 2 + Double(i)) * 0.12
            }
            for (i, spark) in portalSpecks.enumerated() {
                spark.isHidden = reducedMotion || (qualityLevel == 0 && i % 2 == 1)
                let angle = Double(i) / 32 * .pi * 2 + time * 0.45
                let radius = 4.6 + sin(time + Double(i)) * 0.6
                spark.position = vector(cos(angle) * radius, 4.45 + sin(angle) * radius, sin(time * 1.3 + Double(i)) * 0.7)
            }
        }
        let progress = simulation.portalTransitionProgress
        let entryFade = max(0, 1 - (time - worldEntryTime) / 0.45)
        warpVeil.geometry?.firstMaterial?.diffuse.contents = color(reducedMotion ? "101D2F" : "A7E5FC")
        warpVeil.opacity = transitioning ? min(1, max(0, (progress - 0.48) / 0.34)) : entryFade
        if transitioning && !reducedMotion {
            camera.camera?.fieldOfView = (aspect < 0.8 ? 66 : 58) + sin(progress * .pi / 2) * 24
            player.eulerAngles.x = scalar(-sin(progress * .pi) * 0.35)
        }
    }
}

// MARK: - Expedition choreography
private extension CoastalWorld {
    /// Both decks follow the same deterministic curve used by the route selector. The lane
    /// coordinates remain local to the chosen deck, so the visible surface and collision agree.
    func placeRouteSection(_ section: SCNNode, centerZ: Double, localCenterZ: Double,
                           length: Double, simulation: RunnerSimulation, menu: Bool) {
        let selected: BranchRoute = simulation.branchRoute == .undecided ? .safe : simulation.branchRoute
        let center = menu ? (lateralOffset: 0.0, elevation: 0.0) : simulation.routeTransform(atAheadDistance: -centerZ, route: selected)
        let near = menu ? center : simulation.routeTransform(atAheadDistance: -centerZ - length * 0.5, route: selected)
        let far = menu ? center : simulation.routeTransform(atAheadDistance: -centerZ + length * 0.5, route: selected)
        let yaw = atan2(near.lateralOffset - far.lateralOffset, length)
        let pitch = atan2(far.elevation - near.elevation, length)
        section.eulerAngles = vector(pitch, yaw, 0)
        // Clear the fork corridor of tall repeating props; either real route can occupy it.
        if let scenery = section.childNode(withName: "routeScenery", recursively: false) {
            let forkClearance = min(1, max(abs(center.lateralOffset), max(abs(near.lateralOffset), abs(far.lateralOffset))) / 1.5)
            let finaleClearance = !menu && simulation.isExpansionActive ? min(1, max(0, (simulation.stageProgress - 0.66) / 0.035)) : 0
            scenery.opacity = 1 - max(forkClearance, finaleClearance)
            scenery.isHidden = scenery.opacity < 0.001
        }
        section.position = vector(center.lateralOffset - sin(yaw) * localCenterZ,
                                  center.elevation + sin(pitch) * localCenterZ, centerZ - cos(yaw) * localCenterZ)
    }

    func makeAlternateRoute() {
        alternateRouteRoot.name = "alternateExpeditionRoute"
        scene.rootNode.addChildNode(alternateRouteRoot)
        let prototype = SCNNode()
        do {
            let section = prototype
            let deck = box(8.45, 0.40, 16.12, "394951", at: vector(0, -0.26, 0), radius: 0, into: section)
            deck.name = "deck"
            for side in [-1.0, 1.0] {
                box(0.16, 0.38, 16.1, "9EB2BD", at: vector(side * 4.2, 0.03, 0), radius: 0, into: section)
                glowBox(0.07, 0.04, 16.1, "E6B568", at: vector(side * 4.08, 0.25, 0), into: section)
            }
            for x in [-1.3, 1.3] {
                for z in [-6.0, 0, 6] { box(0.07, 0.025, 1.3, "B6C5CA", at: vector(x, -0.04, z), radius: 0, into: section) }
            }
        }
        let deck = prototype.childNode(withName: "deck", recursively: false)!
        deck.removeFromParentNode()
        let railMesh = flattenPreservingHierarchy(prototype); railMesh.name = "routeRails"
        let optimized = SCNNode(); optimized.addChildNode(deck); optimized.addChildNode(railMesh)
        // Clone shared geometry once. The fork adds only 18 reusable two-part deck sections.
        for _ in 0..<18 {
            let section = optimized.clone()
            alternateRouteRoot.addChildNode(section)
            alternateRouteSections.append(section)
        }
    }

    func updateAlternateRoute(simulation: RunnerSimulation, menu: Bool, travel: Double) {
        alternateRouteRoot.isHidden = menu || simulation.mode != .odyssey || simulation.routeRevision < 7 || simulation.isPortalTransitioning
        guard !alternateRouteRoot.isHidden else { return }
        let selected: BranchRoute = simulation.branchRoute == .undecided ? .safe : simulation.branchRoute
        let other: BranchRoute = selected == .risky ? .safe : .risky
        for (index, section) in alternateRouteSections.enumerated() {
            let z = travel.truncatingRemainder(dividingBy: 16) - Double(index) * 16 + 8
            let curve = simulation.routeTransform(atAheadDistance: -z, route: other)
            let chosenCurve = simulation.routeTransform(atAheadDistance: -z, route: selected)
            // Do not draw z-fighting duplicate surfaces where the fork joins the main deck.
            section.isHidden = abs(curve.lateralOffset - chosenCurve.lateralOffset) < 0.4 ||
                (renderedStage == .harbor && other == .safe) || (qualityLevel == 0 && index > 13)
            if !section.isHidden {
                // The inner alternate rail must not cut across the chosen lanes at the merge.
                section.childNode(withName: "routeRails", recursively: false)?.isHidden =
                    abs(curve.lateralOffset - chosenCurve.lateralOffset) < 8.8
                let near = simulation.routeTransform(atAheadDistance: -z - 8, route: other)
                let far = simulation.routeTransform(atAheadDistance: -z + 8, route: other)
                section.position = vector(curve.lateralOffset, curve.elevation, z)
                section.eulerAngles = vector(atan2(far.elevation - near.elevation, 16), atan2(near.lateralOffset - far.lateralOffset, 16), 0)
            }
        }
    }

    /// Shape-coded cues remain useful without color perception: chevron = jump, down arrow
    /// = slide, crossed bars = change lanes. All are attached to actual collidable entities.
    func addActionCue(to root: SCNNode, kind: EntityKind) {
        let cue = SCNNode()
        cue.name = "actionCue"
        let jump = [EntityKind.barrier, .gap, .root, .iceCrack].contains(kind)
        let slide = [EntityKind.arch, .laserSweep].contains(kind)
        let dodge = [EntityKind.meteor, .tram, .airHazard].contains(kind)
        guard jump || slide || dodge else { return }
        let backplate = box(1.25, 0.02, 0.9, "101925", at: vector(0, 0.064, -0.05), radius: 0.06, into: cue)
        backplate.name = "cueBackplate"; backplate.castsShadow = false
        backplate.geometry?.firstMaterial = material("101925", unique: true)
        backplate.geometry?.firstMaterial?.lightingModel = .constant
        let tint = jump ? "FFE3A1" : slide ? "9DEBF2" : "FFB499"
        for side in [-1.0, 1.0] {
            let stroke = glowBox(0.56, 0.033, 0.09, tint,
                                 at: vector(side * (dodge ? 0 : 0.2), 0.09, 0), into: cue)
            stroke.eulerAngles.y = scalar(dodge ? side * .pi / 4 : side * (jump ? -.pi / 4 : .pi / 4))
            stroke.castsShadow = false
        }
        if slide { glowBox(0.07, 0.033, 0.5, tint, at: vector(0, 0.09, -0.22), into: cue).castsShadow = false }
        cue.isHidden = true
        root.addChildNode(cue)
    }

    func makeFinale(stage: WorldStage, into root: SCNNode) {
        root.name = "finale-\(stage.rawValue)"
        root.isHidden = true
        // These silhouettes occupy the margins or safe overhead airspace. Track hazards are
        // always the simulation's entities, never invisible collisions with scenery.
        switch stage {
        case .harbor:
            let crane = SCNNode(); crane.name = "harborCrane"; crane.position = vector(15, 0, 0); root.addChildNode(crane)
            for x in [-3.0, 3] {
                box(1.3, 23, 1.4, "BA7650", at: vector(x, 10.5, 0), radius: 0.12, into: crane)
                for y in stride(from: 1.0, through: 20.0, by: 4) {
                    let strut = box(7.2, 0.34, 0.45, "80949C", at: vector(0, y, 0), radius: 0, into: crane)
                    strut.eulerAngles.z = scalar(x < 0 ? 0.58 : -0.58)
                }
            }
            box(25, 1.1, 2.1, "D7A06C", at: vector(-5, 22, 0), radius: 0.12, into: crane)
            let carriage = SCNNode(); carriage.name = "finaleMover"; carriage.position = vector(0, 14, 0); crane.addChildNode(carriage)
            for x in [-2.0, 2] { cylinder(0.045, 8, "D4E0DE", at: vector(x, 4, 0), into: carriage) }
            box(6.5, 3.4, 4, "4B727D", at: vector(0, -1.5, 0), radius: 0.16, into: carriage)
            for x in stride(from: -2.8, through: 2.8, by: 0.7) { box(0.10, 3.2, 4.1, "8AA9AD", at: vector(x, -1.5, 0), radius: 0, into: carriage) }
            for side in [-1.0, 1.0] { glowBox(0.7, 0.26, 0.06, "FFCB8F", at: vector(side * 2.5, -0.7, 2.1), into: carriage) }
        case .orbit:
            for side in [-1.0, 1.0] {
                for i in 0..<5 {
                    let chunk = SCNNode(); chunk.name = "falling-\(i + (side > 0 ? 5 : 0))"
                    chunk.position = vector(side * (9 + Double(i % 2)), -1, -Double(i) * 13)
                    root.addChildNode(chunk)
                    box(6, 0.8, 10, "667B92", radius: 0.1, into: chunk)
                    for x in [-2.4, 2.4] { glowBox(0.07, 0.08, 9.7, "77DCEF", at: vector(x, 0.44, 0), into: chunk) }
                    let spar = box(0.35, 5, 0.5, "9EADBB", at: vector(side * 2.3, -2, 0), radius: 0, into: chunk)
                    spar.eulerAngles.z = scalar(side * 0.65)
                }
            }
            for side in [-1.0, 1.0] { box(0.7, 23, 1, "8B9CAF", at: vector(side * 11, 9.5, -60), radius: 0.1, into: root) }
            box(23, 0.7, 1, "A7B7C6", at: vector(0, 21, -60), radius: 0.1, into: root)
        case .mars:
            let crawler = SCNNode(); crawler.name = "marsCrawler"; crawler.position = vector(18, -2.7, 0); root.addChildNode(crawler)
            box(10, 4, 18, "8E5B47", at: vector(0, 4.0, 0), radius: 0.4, into: crawler)
            box(10.5, 0.8, 18.5, "D0AB80", at: vector(0, 6.0, 0), radius: 0.18, into: crawler)
            box(7.5, 3.4, 7, "C5A17A", at: vector(0, 8.0, 2), radius: 0.3, into: crawler)
            box(6.9, 1.7, 0.08, "254653", at: vector(0, 8.3, 5.56), radius: 0.12, into: crawler)
            for side in [-1.0, 1.0] {
                for z in [-6.0, 0, 6] {
                    let wheelPivot = SCNNode(); wheelPivot.name = "crawlerWheel"
                    wheelPivot.position = vector(side * 5.5, 2.5, z); crawler.addChildNode(wheelPivot)
                    let wheel = cylinder(2.8, 1.1, "252C31", at: SCNVector3Zero, into: wheelPivot)
                    wheel.eulerAngles.z = scalar(.pi / 2)
                    let hub = cylinder(1.4, 1.15, "9E8C74", at: SCNVector3Zero, into: wheelPivot)
                    hub.eulerAngles.z = scalar(.pi / 2)
                    for n in 0..<8 {
                        let angle = Double(n) * .pi / 4
                        let tread = box(1.16, 0.24, 0.65, "4E4B43", at: vector(0, cos(angle) * 2.8, sin(angle) * 2.8), radius: 0.02, into: wheelPivot)
                        tread.eulerAngles.x = scalar(-angle)
                    }
                }
                glowBox(0.9, 0.4, 0.12, "FFD6A2", at: vector(side * 3.7, 5.1, 9.2), into: crawler)
            }
            let arm = SCNNode(); arm.name = "finaleMover"; arm.position = vector(0, 10.1, -3); crawler.addChildNode(arm)
            let boom = box(16, 1.3, 1.8, "C38C5D", at: vector(-5, 3.0, 0), radius: 0.12, into: arm)
            boom.eulerAngles.z = scalar(-0.22)
            let drill = cylinder(1.5, 4.2, "6D6860", at: vector(-12, 2.8, 0), into: arm)
            drill.name = "crawlerDrill"
            for i in 0..<5 { ring(1.55, tube: 0.15, tint: "A5A89A", at: vector(-12, 1.2 + Double(i) * 0.6, 0), into: arm) }
            for z in [-7.0, 0, 7] {
                let exhaust = cylinder(0.35, 3, "68625B", at: vector(3.8, 8.1, z), into: crawler)
                box(0.9, 0.2, 0.9, "343E44", at: vector(0, 1.45, 0), radius: 0.04, into: exhaust)
            }
        case .verdant:
            let reactor = SCNNode(); reactor.name = "verdantReactor"; reactor.position = vector(-14, 7, -12); root.addChildNode(reactor)
            let core = sphere(3.8, "478A72", at: SCNVector3Zero, into: reactor)
            core.name = "finaleCore"; core.geometry?.firstMaterial = material("68DBAE", emissive: true)
            for i in 0..<4 {
                let hoop = ring(5 + Double(i % 2), tube: 0.33, tint: "526E63", at: SCNVector3Zero, into: reactor)
                hoop.eulerAngles = vector(Double(i) * .pi / 3, Double(i) * .pi / 4, 0.3)
                hoop.name = "reactorRing"
            }
            for side in [-1.0, 1.0] {
                let rootStem = capsule(0.6, 18, "365849", at: vector(side * 5.5, -3, 0), into: reactor)
                rootStem.eulerAngles.z = scalar(side * 0.4)
                for i in 0..<4 { makeAlienTree(into: root, at: vector(side * (9 + Double(i % 2) * 3), -1, -Double(i) * 16), size: 1.2) }
            }
        case .cryo:
            for side in [-1.0, 1.0] {
                for i in 0..<4 {
                    let arch = SCNNode(); arch.position = vector(side * 10, 0, -Double(i) * 21); root.addChildNode(arch)
                    let shaft = box(2.8, 21, 3.3, "9FCAD9", at: vector(0, 7, 0), radius: 0.3, into: arch)
                    shaft.geometry?.firstMaterial = iceMaterial(); shaft.eulerAngles.z = scalar(-side * 0.18)
                    let fragment = SCNNode(); fragment.name = "falling-\(i + (side > 0 ? 4 : 0))"; fragment.position = vector(side * 7, 16, -Double(i) * 21); root.addChildNode(fragment)
                    makeCrystal(into: fragment, at: SCNVector3Zero, height: 4.5, tint: "CEEFF4")
                    for k in 0..<4 { glowBox(0.05, 2.8, 0.08, "D8F6FA", at: vector(side * 0.8, 2 + Double(k) * 3.3, 1.7), into: arch) }
                }
            }
            box(22, 1.2, 3.4, "ACDAE5", at: vector(0, 18.2, -64), radius: 0.18, into: root).geometry?.firstMaterial = iceMaterial()
        case .forge:
            let sentinel = SCNNode(); sentinel.name = "forgeSentinel"; sentinel.position = vector(-16, -1.25, 0); root.addChildNode(sentinel)
            let dais = box(16, 0.8, 18, "51434B", at: vector(-16, -2.2, 0), radius: 0.18, into: root)
            dais.geometry?.firstMaterial = deckMaterial(for: .forge)
            for side in [-1.0, 1.0] { glowBox(0.16, 0.07, 17.5, "D79367", at: vector(-16 + side * 7.8, -1.73, 0), into: root) }
            let torso = sculptedMesh(rings: [(4, 2.8, 1.8), (7, 4, 2.3), (11, 3.7, 2), (13, 2.0, 1.7)], tint: "514652")
            sentinel.addChildNode(torso)
            box(4.5, 3.1, 3.2, "817378", at: vector(0, 14.1, 0), radius: 0.38, into: sentinel)
            glowBox(3.8, 0.42, 0.12, "FFD0A1", at: vector(0, 14.4, 1.66), into: sentinel)
            let core = sphere(1.15, "F4A472", at: vector(0, 8.2, 2.0), scale: vector(1, 1, 0.45), into: sentinel)
            core.name = "finaleCore"; core.geometry?.firstMaterial = material("F4A472", emissive: true)
            for side in [-1.0, 1.0] {
                let leg = capsule(1.3, 6.5, "6B5E65", at: vector(side * 2.2, 2.7, 0), into: sentinel)
                leg.eulerAngles.z = scalar(side * 0.12)
                box(2.7, 1, 4.6, "3F3B45", at: vector(side * 2.5, -0.05, 0.9), radius: 0.2, into: sentinel)
                let arm = SCNNode(); arm.name = side < 0 ? "sentinelLeft" : "finaleMover"; arm.position = vector(side * 4.1, 10.8, 0); sentinel.addChildNode(arm)
                sphere(1.55, "8A7779", at: SCNVector3Zero, into: arm)
                capsule(1.1, 6.5, "65535D", at: vector(side * 0.5, -3.1, 0), into: arm)
                let gauntlet = box(2.8, 2.4, 3.3, "413D4D", at: vector(side * 0.65, -5.5, 0.4), radius: 0.28, into: arm)
                for i in 0..<3 { glowBox(0.12, 1.6, 0.1, "F9AA72", at: vector(-0.7 + Double(i) * 0.7, 0, 1.7), into: gauntlet) }
            }
        }
    }

    func updateFinale(simulation: RunnerSimulation, time: Double, menu: Bool) {
        harborFinale.isHidden = renderedStage != .harbor
        let show = !menu && simulation.mode == .odyssey && simulation.routeRevision >= 7 && simulation.stageProgress >= 0.66 && !simulation.isPortalTransitioning
        finaleRoot.isHidden = !show
        guard show else { return }
        let progress = max(0, min(1, (simulation.stageProgress - 0.66) / 0.31))
        finaleRoot.opacity = min(1, progress * 5) * min(1, max(0, (1 - simulation.stageProgress) / 0.025))
        finaleRoot.position.z = scalar(-85 + progress * 47)
        let motionTime = reducedMotion ? 0 : time
        if let mover = finaleRoot.childNode(withName: "finaleMover", recursively: true) {
            mover.eulerAngles.z = scalar(sin(motionTime * 0.35) * (renderedStage == .forge ? 0.14 : 0.06))
        }
        if let crawler = finaleRoot.childNode(withName: "marsCrawler", recursively: false) {
            crawler.position.y = scalar(-2.7 + (reducedMotion ? 0 : sin(time * 3) * 0.10))
            for wheel in crawler.childNodes where wheel.name == "crawlerWheel" { wheel.eulerAngles.x = scalar(motionTime * 0.8) }
        }
        if let core = finaleRoot.childNode(withName: "finaleCore", recursively: true) { core.opacity = reducedMotion ? 0.86 : 0.86 + sin(time * 2.2) * 0.10 }
        for node in finaleRoot.childNodes {
            if let name = node.name, name.hasPrefix("falling-"), let index = Int(name.dropFirst(8)) {
                let delay = Double(index % 5) * 0.13
                let collapse = max(0, min(1, (progress - delay) * 2))
                let side = Double(node.position.x) < 0 ? -1.0 : 1.0
                node.position.y = scalar((renderedStage == .cryo ? 16.0 : -1.0) - collapse * (reducedMotion ? 4 : 18))
                node.eulerAngles = vector(collapse * 0.4, 0, side * collapse * 0.3)
            }
        }
    }
}

private extension CoastalWorld {
    func makeCourierArmor() {
        // Independent panels articulate with the joints. The cloth remains visible between
        // shells, so the runner reads as a person in a suit rather than stacked rigid boxes.
        for (index, arm) in [leftArm, rightArm].enumerated() {
            let side = index == 0 ? -1.0 : 1.0
            let pauldron = sculptedMesh(rings: [(-0.21, 0.12, 0.13), (-0.12, 0.17, 0.18), (0.08, 0.17, 0.17), (0.16, 0.08, 0.10)], tint: index == 0 ? "CBD8DD" : "597888")
            pauldron.position = vector(side * 0.02, 0, 0)
            arm.addChildNode(pauldron)
            box(0.035, 0.22, 0.16, "F6C58A", at: vector(side * 0.16, -0.02, 0), radius: 0.012, into: arm)
            if index < forearms.count {
                let wrist = forearms[index]
                box(0.12, 0.11, 0.06, "0C1E2B", at: vector(0, -0.16, 0.085), radius: 0.025, into: wrist)
                glowBox(0.065, 0.045, 0.012, "9ADBDC", at: vector(0, -0.15, 0.12), into: wrist)
                box(0.10, 0.045, 0.055, "A6B8C4", at: vector(0, -0.31, 0.035), radius: 0.015, into: wrist)
            }
        }
        for (index, leg) in [leftLeg, rightLeg].enumerated() {
            let side = index == 0 ? -1.0 : 1.0
            let thigh = box(0.16, 0.22, 0.07, "4A6575", at: vector(side * 0.07, -0.16, -0.08), radius: 0.055, into: leg)
            thigh.eulerAngles.z = scalar(side * 0.08)
            box(0.15, 0.11, 0.08, "B3C4CB", at: vector(0, -0.31, -0.1), radius: 0.04, into: leg)
            if index < feet.count {
                let boot = feet[index]
                box(0.25, 0.10, 0.16, "3C5262", at: vector(0, 0.025, -0.23), radius: 0.045, into: boot)
                for tread in 0..<4 { box(0.23, 0.023, 0.026, "233544", at: vector(0, -0.10, -0.21 + Double(tread) * 0.085), radius: 0, into: boot) }
            }
        }
        for side in [-1.0, 1.0] {
            let collar = box(0.16, 0.11, 0.23, "B4C5CC", at: vector(side * 0.15, 1.6, 0), radius: 0.045, into: body)
            collar.eulerAngles.z = scalar(-side * 0.22)
            let helmetRail = box(0.06, 0.27, 0.28, "AAC0CE", at: vector(side * 0.27, 0.49, 0.10), radius: 0.035, into: headRig)
            helmetRail.eulerAngles.z = scalar(-side * 0.2)
            cylinder(0.09, 0.055, "2C4659", at: vector(side * 0.31, 0.41, 0.06), into: headRig).eulerAngles.z = scalar(.pi / 2)
            for i in 0..<3 { box(0.06, 0.018, 0.025, "173141", at: vector(side * 0.15, 0.55 + Double(i) * 0.055, 0.31), radius: 0, into: headRig) }
        }
        glowBox(0.21, 0.033, 0.018, "9ADBDD", at: vector(0, 0.55, 0.349), into: headRig)
        let chest = box(0.30, 0.27, 0.07, "405B6A", at: vector(0, 1.39, -0.195), radius: 0.07, into: body)
        glowBox(0.16, 0.024, 0.013, "B2E3DB", at: vector(0, 0.015, -0.044), into: chest)
        for side in [-1.0, 1.0] {
            let hip = box(0.18, 0.23, 0.24, "6D899A", at: vector(side * 0.27, 0.88, 0.07), radius: 0.055, into: body)
            hip.eulerAngles.z = scalar(side * 0.1)
        }
    }
}
