import Foundation

enum RunPhase: Equatable, Codable { case menu, running, paused, crashed, finished }
enum RunnerAction: String, Codable { case left, right, jump, roll, board, ability }
enum PowerUp: String, CaseIterable, Codable { case magnet, jetpack, sneakers, multiplier }
enum EntityKind: String, Codable {
    case coin, key, barrier, arch, tram, ramp, magnet, jetpack, sneakers, multiplier
    case checkpoint, buoy, gate, waveRamp, airRing, airHazard, relic
    case gap, meteor, root, iceCrack, laserSweep, waterTraffic, wall, stack
}

enum RunMode: String, CaseIterable, Codable {
    case endless, harborSprint, jetSki, odyssey

    var title: String {
        switch self {
        case .odyssey: return "Portal Odyssey"
        case .endless: return "Coastal Rush"
        case .harborSprint: return "Harbor Sprint"
        case .jetSki: return "Wave Rider"
        }
    }
    var subtitle: String {
        switch self {
        case .odyssey: return "Six worlds. One extraordinary journey."
        case .endless: return "Chain daring escapes. Chase your record."
        case .harborSprint: return "1,500 meters. Every checkpoint counts."
        case .jetSki: return "Race the slalom. Master the water."
        }
    }
    var instructions: String {
        switch self {
        case .odyssey: return "Master six worlds: jump gaps, slide beams and read moving hazards. Risky relic routes charge your artifact ability (E). Jump at a portal for a precision bonus, or let Portal Assist carry you through. Gold requires a clean stage, two relics, two skill actions and a precision entry."
        case .endless: return "Swipe to dodge, jump and slide. Double-tap or B activates your hoverboard. Close calls and clean escapes build your combo. Airborne drones can hit your jetpack."
        case .harborSprint: return "Reach 1,500 m before time runs out. Cross the illuminated checkpoints for extra time. Keep moving to keep your combo."
        case .jetSki: return "Carve through gates and moving boats. Down brakes and tightens steering; B boosts. Wakes launch you. In the air, chain Up, Left and Right tricks, then release before landing to bank the score. Currents push your craft; missed gates cost time."
        }
    }
}

/// New challenge state lives together so pre-challenge snapshots can recover their old run.
struct RunChallenge: Codable {
    var mode: RunMode = .endless
    var expert = false
    var combo = 0
    var bestCombo = 0
    var nearMisses = 0
    var gatesCleared = 0
    var gatesMissed = 0
    var timeRemaining = 60.0
    var boostCharge = 0.65
    var boostTime = 0.0
    var brakeTime = 0.0
    var trickTime = 0.0
    var trickUsed = false
    var comboTime = 0.0
    var eventText = ""
    var eventTime = 0.0
    var nextCheckpointDistance = 200.0
    var previousSafeLane = 0
    var previousWaterGate = 0
    var previousAirLane = 0
    var closestApproaches: [Int: Double] = [:]
    var nextAirPattern = 0.0
}

/// Longitudinal positions and lengths are centered. Positive z is ahead of the runner.
struct TrackEntity: Identifiable, Equatable, Codable {
    var id: Int
    var kind: EntityKind
    var lane: Int
    var z: Double
    var y: Double
    var length: Double
    /// Additional forward velocity toward the runner; stationary scenery defaults to zero.
    var oncomingSpeed: Double = 0
    /// A lane-changer slides from `lane` into `targetLane` while z runs from `motionStart` to `motionStart - motionLength`.
    var targetLane: Int? = nil
    var motionStart: Double = 0
    var motionLength: Double = 0
    /// A timed laser's phase (seconds) on a 1.8 s cycle: on 0.9 s, then off 0.9 s. Negative means always on.
    var cyclePhase: Double = -1
    /// The collider exists only once z <= activeFrom: a meteor's impact, a deck's collapse.
    var activeFrom: Double = .infinity
}

extension TrackEntity {
    static let cycleLength = 1.8

    /// The lane the entity occupies when it reaches the runner; its telegraph shows this lane.
    var arrivalLane: Int { targetLane ?? lane }

    /// Eased lateral offset, in lanes, from `lane` toward `targetLane` at the current z.
    func laneOffset() -> Double {
        guard let target = targetLane, motionLength > 0 else { return 0 }
        let p = min(1, max(0, (motionStart - z) / motionLength))
        return Double(target - lane) * p * p * (3 - 2 * p)
    }

    /// A timed laser is on for the first half of each cycle; untimed entities are always on.
    func isOn(at time: Double) -> Bool {
        guard cyclePhase >= 0 else { return true }
        let t = (time + cyclePhase).truncatingRemainder(dividingBy: Self.cycleLength)
        return (t < 0 ? t + Self.cycleLength : t) < Self.cycleLength / 2
    }

    var isActive: Bool { z <= activeFrom }

    /// A lane-changer that has not yet reached its arrival lane (its shift chevron is still showing).
    var isShifting: Bool { targetLane != nil && abs(Double(arrivalLane - lane) - laneOffset()) > 0.001 }

    private enum CodingKeys: String, CodingKey {
        case id, kind, lane, z, y, length, oncomingSpeed, targetLane, motionStart, motionLength, cyclePhase, activeFrom
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        kind = try values.decode(EntityKind.self, forKey: .kind)
        lane = try values.decode(Int.self, forKey: .lane)
        z = try values.decode(Double.self, forKey: .z)
        y = try values.decode(Double.self, forKey: .y)
        length = try values.decode(Double.self, forKey: .length)
        oncomingSpeed = try values.decodeIfPresent(Double.self, forKey: .oncomingSpeed) ?? 0
        targetLane = try values.decodeIfPresent(Int.self, forKey: .targetLane)
        motionStart = try values.decodeIfPresent(Double.self, forKey: .motionStart) ?? 0
        motionLength = try values.decodeIfPresent(Double.self, forKey: .motionLength) ?? 0
        cyclePhase = try values.decodeIfPresent(Double.self, forKey: .cyclePhase) ?? -1
        activeFrom = try values.decodeIfPresent(Double.self, forKey: .activeFrom) ?? .infinity
    }

    /// New fields are written only when set. JSONEncoder rejects infinity, so the default activeFrom is never written.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(lane, forKey: .lane)
        try values.encode(z, forKey: .z)
        try values.encode(y, forKey: .y)
        try values.encode(length, forKey: .length)
        try values.encode(oncomingSpeed, forKey: .oncomingSpeed)
        try values.encodeIfPresent(targetLane, forKey: .targetLane)
        if motionStart != 0 { try values.encode(motionStart, forKey: .motionStart) }
        if motionLength != 0 { try values.encode(motionLength, forKey: .motionLength) }
        if cyclePhase >= 0 { try values.encode(cyclePhase, forKey: .cyclePhase) }
        if activeFrom.isFinite { try values.encode(activeFrom, forKey: .activeFrom) }
    }
}

/// Deterministic, platform-independent game rules. Call update with elapsed real seconds.
struct RunnerSimulation: Codable {
    private(set) var phase: RunPhase = .menu
    private(set) var lane = 0
    private(set) var lateral = 0.0
    private(set) var height = 0.0
    private(set) var isRolling = false
    private(set) var distance = 0.0
    private(set) var speed = 12.0
    private(set) var coins = 0
    private(set) var keys = 0
    private(set) var score = 0
    private(set) var multiplier = 1
    private(set) var boardTime = 0.0
    private(set) var invulnerableTime = 0.0
    private(set) var activePowerUps: [PowerUp: Double] = [:]
    private(set) var entities: [TrackEntity] = []
    private(set) var elapsed = 0.0
    private(set) var jumps = 0
    private(set) var rolls = 0
    private(set) var dodges = 0
    private(set) var boardsUsed = 0
    private(set) var availableBoards = 3
    private(set) var crashReason = ""
    private var challenge = RunChallenge()
    private var journey = PortalJourney()
    private var enhancements = RunEnhancements()
    private var expansion = ExpeditionExpansion()

    var expeditionStyle: ExpeditionStyle { expansion.style }
    var expeditionCycle: Int { expansion.cycle }
    var isPractice: Bool { mode == .odyssey && expeditionStyle == .practice }
    /// Practice cannot settle currency, unlocks, achievements, ghosts or records.
    /// Endless banks earned currency but needs its own score category in the profile.
    var isCompetitiveRun: Bool { !isPractice }
    var selectedPerks: [ExpeditionPerk] { expansion.selectedPerks }
    var decisionPlan: [ExpeditionDecision] { expansion.decisions }
    var branchRoute: BranchRoute { expansion.route }
    private var hasCurrentReplayDecision: Bool { expansion.replayPlan?.contains(where: { $0.world == stageIndex }) == true }
    var isExpansionActive: Bool { mode == .odyssey && routeRevision >= 7 }
    var routeChoiceAvailable: Bool {
        isExpansionActive && !isPractice && dailyID == nil && !hasCurrentReplayDecision &&
        [.running, .paused].contains(phase) && stageProgress >= 0.20 && stageProgress < 0.26
    }
    var routeChoiceRemaining: Double { max(0, (stageLength * 0.26 - stageDistance) / max(1, speed)) }
    var routeProgress: Double {
        guard isExpansionActive, stageProgress >= 0.32, stageProgress <= 0.55 else { return 0 }
        return (stageProgress - 0.32) / 0.23
    }
    var routeIsActive: Bool { isExpansionActive && stageProgress >= 0.32 && stageProgress < 0.55 }
    var isWaterTraversal: Bool { mode == .jetSki || (routeIsActive && worldStage == .harbor && branchRoute == .safe) }
    var routeLateralOffset: Double { routeTransform(atAheadDistance: 0).lateralOffset }
    var routeElevation: Double { routeTransform(atAheadDistance: 0).elevation }
    func routeTransform(atAheadDistance ahead: Double, route: BranchRoute? = nil) -> (lateralOffset: Double, elevation: Double) {
        guard isExpansionActive else { return (0, 0) }
        let selected = route ?? (branchRoute == .undecided ? .safe : branchRoute)
        guard selected != .undecided else { return (0, 0) }
        let p = (stageDistance + ahead) / stageLength
        guard p > 0.32 && p < 0.55 else { return (0, 0) }
        let ramp = min(1, max(0, min((p - 0.32) / 0.035, (0.55 - p) / 0.035)))
        let blend = ramp * ramp * (3 - 2 * ramp)
        return ((selected == .risky ? 8 : -8) * blend, selected == .risky ? 2.8 * blend : 0)
    }
    var finaleActive: Bool { isExpansionActive && stageProgress >= 0.72 && stageDistance < stageLength - portalApproachLength }
    var finaleProgress: Double { finaleActive ? min(1, max(0, (stageProgress - 0.72) / (1 - portalApproachLength / stageLength - 0.72))) : 0 }
    var finaleTitle: String { worldStage.finaleTitle }
    var finaleTimeRemaining: Double { max(0, (stageLength - portalApproachLength - stageDistance) / max(1, speed)) }
    var totalFinalesCleared: Int { expansion.totalFinalesCleared }
    var completedObjectiveCount: Int { expansion.completedObjectives }
    var objectiveStatus: [ExpeditionObjectiveStatus] {
        guard isExpansionActive else { return [] }
        var goals = [
            ExpeditionObjectiveStatus(id: "relics", title: "Collect two relics", progress: min(2, stageRelics), target: 2),
            ExpeditionObjectiveStatus(id: "finale", title: "Six clean finale actions", progress: expansion.finaleHits == 0 ? min(6, expansion.finaleSkillActions) : 0, target: 6),
            ExpeditionObjectiveStatus(id: "unprotected", title: "Eight actions without protection", progress: expansion.usedProtection || stageHits > 0 ? 0 : min(8, stageSkillActions), target: 8)
        ]
        if worldStage == .mars { goals.append(ExpeditionObjectiveStatus(id: "rovers", title: "Ride four rover roofs", progress: min(4, expansion.roverTransfers), target: 4)) }
        if worldStage == .harbor { goals.append(ExpeditionObjectiveStatus(id: "water", title: "Bank two water trick landings", progress: min(2, enhancements.cleanLandings - expansion.stageCleanLandings), target: 2)) }
        return goals
    }
    var maximumAbilityCharges: Int { selectedPerks.contains(.relicCapacitor) ? 5 : 3 }
    var abilityChargeCost: Int {
        selectedAbility == .phaseStep && selectedPerks.contains(.longPhase) || selectedAbility == .airDash && selectedPerks.contains(.dashDividend) ? 2 : 1
    }
    var availablePerks: [ExpeditionPerk] { ExpeditionPerk.allCases.filter { !selectedPerks.contains($0) } }
    var canChoosePerk: Bool {
        isExpansionActive && !isPractice && dailyID == nil && !hasCurrentReplayDecision && stagesCleared > 0 &&
        expansion.stagePerk == nil && !availablePerks.isEmpty && [.running, .paused].contains(phase) &&
        !isPortalTransitioning && stageDistance < stageOpeningLength - 15
    }

    var portalAssist: Bool { enhancements.portalAssist }
    var dailyID: String? { enhancements.dailyID }
    var runSeed: UInt64 { enhancements.runSeed }
    var startWorldIndex: Int { enhancements.startWorldIndex }
    var selectedAbility: ArtifactAbility? { enhancements.selectedAbility }
    var abilityCharges: Int { enhancements.abilityCharges }
    var abilityTime: Double { enhancements.abilityTime }
    var isAbilityActive: Bool { enhancements.abilityTime > 0 || enhancements.shieldArmed }
    var activeAbility: ArtifactAbility? { enhancements.shieldArmed ? .shield : enhancements.activeAbility }
    var canChooseAbility: Bool { !isAbilityActive && (phase == .menu || (isPractice && elapsed < 2) || (mode == .odyssey && (stageDistance < stageOpeningLength - 15 || (portalDistance ?? 999) <= portalApproachLength || isPortalTransitioning))) }
    var canActivateAbility: Bool { phase == .running && mode == .odyssey && !isPortalTransitioning && !portalReady && abilityCharges >= abilityChargeCost && selectedAbility != nil && !isAbilityActive }
    var stageResults: [WorldStageResult] { enhancements.stageResults }
    var stageHits: Int { enhancements.stageHits }
    var stageRelics: Int { artifactsCollected - enhancements.stageStartRelics }
    var stageSkillActions: Int { enhancements.stageSkillActions }
    var waterCurrent: Double { enhancements.waterCurrent }
    var lateralVelocity: Double { enhancements.lateralVelocity }
    var trickChain: Int { enhancements.trickChain }
    var cleanLandings: Int { enhancements.cleanLandings }
    var landingImpact: Double { enhancements.landingImpact }
    /// The last generated row's route lane (read-only, for audits and tests).
    var previousRouteLane: Int { challenge.previousSafeLane }
    var encounterDistance: Double? { upcomingEncounter?.z }
    var encounterText: String {
        guard let entity = upcomingEncounter else { return "" }
        switch entity.kind {
        case .gap: return entity.activeFrom.isFinite ? "COLLAPSING DECK · JUMP THE CRACKS" : "BROKEN ORBITAL DECK · JUMP"
        case .meteor: return "METEOR IMPACT · CHANGE LANES"
        case .root: return "RISING ROOTS · JUMP"
        case .iceCrack: return entity.activeFrom.isFinite ? "COLLAPSING ICE · JUMP THE CRACKS" : "FRACTURING ICE · JUMP"
        case .laserSweep: return entity.cyclePhase >= 0 ? "TIMED LASER · SLIDE OR TIME IT" : worldStage == .forge ? "SENTINEL SWEEP · SLIDE" : "VINE LASERS · SLIDE"
        case .waterTraffic: return "CROSSING TRAFFIC · CARVE OR BRAKE"
        case .arch: return "LOW BEAM · SLIDE"
        case .barrier: return "CARGO LINE · JUMP"
        case .tram: return entity.targetLane != nil ? "SHIFTING CARGO · TAKE THE LANE IT LEAVES" : worldStage == .mars ? "ROVER TRANSFER · TAKE THE RAMP" : "MOVING CARGO · CHANGE LANES"
        case .wall: return "GAP WALL · FIND THE OPENING"
        case .stack: return "STACKED BARRIER · CHANGE LANES"
        default: return ""
        }
    }
    private var upcomingEncounter: TrackEntity? {
        // Row-mates share a z. Only a stack and the G2 specials outrank the rest (a stack hides among its jump and
        // slide lanes; a tram beside a timed laser must not rename it); otherwise the first-added entity names the row.
        func rank(_ e: TrackEntity) -> Int {
            if e.kind == .stack { return 0 }
            if e.targetLane != nil || e.cyclePhase >= 0 || e.activeFrom.isFinite { return 1 }
            return 2
        }
        return entities.filter { Self.isObstacle($0.kind) && $0.z > 0 && $0.z < max(65, speed * 2.5) }
            .min { ($0.z, rank($0)) < ($1.z, rank($1)) }
    }

    var worldStage: WorldStage { WorldStage.ordered[stageIndex] }
    var stageIndex: Int { min(WorldStage.ordered.count - 1, max(0, journey.stageIndex)) }
    var stageDistance: Double { journey.stageDistance }
    var routeRevision: Int { journey.routeRevision }
    var stageLength: Double {
        let original = worldStage.length(forRevision: routeRevision)
        guard isExpansionActive && expeditionCycle > 0 else { return original }
        let originalAverage = (worldStage.speed(at: 0, expert: expert) + worldStage.speed(at: 1, expert: expert)) / 2
        let actualAverage = (expeditionSpeed(at: 0) + expeditionSpeed(at: 1)) / 2
        return original * actualAverage / originalAverage
    }
    var stageProgress: Double { min(1, max(0, stageDistance / stageLength)) }
    var difficultyTier: JourneyDifficultyTier { isExpansionActive && expeditionCycle > 0 ? .overdrive : worldStage.difficultyTier(at: stageProgress, revision: routeRevision) }
    var difficultyProgress: Double {
        // A world may begin above the local tier floor. Progress starts at its landing
        // rather than showing a negative meter until the old warm-up boundary.
        let openingTier = worldStage.difficultyTier(at: 0, revision: routeRevision)
        let start = difficultyTier == openingTier ? 0 : difficultyTier.startProgress
        return min(1, max(0, (stageProgress - start) / (difficultyTier.endProgress - start)))
    }
    var stageTargetSpeed: Double {
        expeditionSpeed(at: stageProgress)
    }
    private func expeditionSpeed(at progress: Double) -> Double {
        let original = worldStage.speed(at: progress, expert: expert, revision: routeRevision)
        guard isExpansionActive && expeditionStyle == .endless else { return original }
        return min(expert ? 71 : 65, original + Double(expeditionCycle) * (expert ? 31 : 28))
    }
    var portalApproachLength: Double { routeRevision < 7 ? worldStage.portalClearance(expert: expert, revision: routeRevision) : max(110, expeditionSpeed(at: 1) * 3.6) }
    var stageOpeningLength: Double { routeRevision < 5 ? 65 : max(70, expeditionSpeed(at: 0) * 3.2) }

    var portalDistance: Double? {
        guard mode == .odyssey, !journeyComplete else { return nil }
        let remaining = max(0, stageLength - stageDistance)
        return remaining <= max(160, portalApproachLength + 35) ? remaining : nil
    }
    var portalReady: Bool { mode == .odyssey && stageDistance >= stageLength && !isPortalTransitioning && !journeyComplete }
    var isPortalTransitioning: Bool { journey.transitionTime != nil }
    var portalTransitionProgress: Double { min(1, max(0, (journey.transitionTime ?? 0) / 1.6)) }
    var stagesCleared: Int { journey.stagesCleared }
    var artifactsCollected: Int { journey.artifactsCollected }
    var collectedArtifactWorlds: Set<WorldStage> { journey.collectedArtifactWorlds }
    var journeyComplete: Bool { journey.complete }

    var mode: RunMode { challenge.mode }
    var expert: Bool { challenge.expert }
    var combo: Int { challenge.combo }
    var bestCombo: Int { challenge.bestCombo }
    var nearMisses: Int { challenge.nearMisses }
    var gatesCleared: Int { challenge.gatesCleared }
    var gatesMissed: Int { challenge.gatesMissed }
    var timeRemaining: Double { challenge.timeRemaining }
    var boostCharge: Double { challenge.boostCharge }
    var isBoosting: Bool { challenge.boostTime > 0 }
    var isBraking: Bool { challenge.brakeTime > 0 }
    var isTricking: Bool { challenge.trickTime > 0 }
    var eventText: String { challenge.eventText }
    var eventTime: Double { challenge.eventTime }
    var courseTarget: Double { mode == .harborSprint ? 1_500 : mode == .jetSki ? 1_800 : 0 }

    static let tramRoofHeight = 2.8
    static let laneWidth = 2.6

    private var randomState: UInt64 = 1
    private var nextID = 0
    private var nextPatternDistance = 28.0
    private var verticalVelocity = 0.0
    private var rollTime = 0.0
    private var grounded = true
    private var baseMultiplier = 1
    private var powerDurations: [PowerUp: Double] = [:]
    private var preciseScore = 0.0
    private var processedObstacles: Set<Int> = []
    /// Coin lines actually laid this run, for audits. Not persisted: a restored run starts a new tally.
    private(set) var placedCoinLines: [CoinLine: Int] = [:]
    /// Last bait coin id → its solid's id, for the bait-escape audit. Not persisted: a restored run starts empty.
    private(set) var baitEscapes: [Int: Int] = [:]
    private var generateTrack = true

    mutating func start(seed: UInt64 = 0xC0A5711E, baseMultiplier: Int = 1,
                        durations: [PowerUp: Double] = [:], boards: Int = 3,
                        headstart: Bool = false, mode: RunMode = .endless, expert: Bool = false, startStage: Int = 0,
                        portalAssist: Bool = true, dailyID: String? = nil, expeditionStyle: ExpeditionStyle = .campaign, replayPlan: [ExpeditionDecision]? = nil) {
        self = RunnerSimulation()
        self.randomState = dailyID.map(Self.dailyOdysseySeed(for:)) ?? (seed == 0 ? 0xC0A5711E : seed)
        enhancements.runSeed = randomState
        enhancements.dailyID = mode == .odyssey ? dailyID : nil
        enhancements.portalAssist = portalAssist
        enhancements.startWorldIndex = min(WorldStage.ordered.count - 1, max(0, startStage))
        self.baseMultiplier = max(1, baseMultiplier)
        self.multiplier = self.baseMultiplier
        self.powerDurations = durations
        self.availableBoards = max(0, boards)
        self.phase = .running
        self.challenge.mode = mode
        self.challenge.expert = expert
        self.challenge.timeRemaining = expert && mode != .endless ? 45 : 60
        self.speed = mode == .jetSki ? 19 : expert ? 16 : 12
        if mode == .odyssey {
            expansion.style = dailyID == nil ? expeditionStyle : .campaign
            expansion.replayPlan = replayPlan
            journey.stageIndex = min(WorldStage.ordered.count - 1, max(0, startStage))
            if isPractice { journey.stageDistance = stageLength * 0.70; expansion.route = .safe }
            configureExpansionArrival()
            speed = stageTargetSpeed
            nextPatternDistance = isPractice ? speed * 2 : stageOpeningLength
        }
        if headstart && mode != .jetSki && mode != .odyssey { activate(.jetpack, duration: 8) }
        showEvent(mode == .jetSki ? "FOLLOW THE GATES" : mode == .harborSprint ? "RACE THE CLOCK" : "BUILD YOUR COMBO")
        if mode == .odyssey { showEvent(worldStage.title.uppercased()) }
        extendTrack()
    }

    /// Stable across processes and platforms, unlike Swift's randomized Hasher.
    static func dailyOdysseySeed(for dayID: String) -> UInt64 {
        dayID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    mutating func steerWater(_ normalizedTarget: Double?) {
        guard phase == .running, isWaterTraversal else { return }
        if let target = normalizedTarget, target.isFinite {
            enhancements.waterSteeringTarget = max(-1, min(1, target))
            lane = Int((enhancements.waterSteeringTarget ?? 0).rounded())
            if !grounded && height > 0.45 && abs(target) > 0.55 {
                performWaterTrick(target < 0 ? .left : .right)
            }
        } else {
            enhancements.waterSteeringTarget = nil
            lane = Int(max(-1, min(1, lateral.rounded())))
        }
    }

    mutating func configurePortalAssist(_ enabled: Bool) { enhancements.portalAssist = enabled }
    mutating func chooseAbility(_ ability: ArtifactAbility) {
        guard canChooseAbility else { return }
        enhancements.selectedAbility = ability
    }

    mutating func chooseRoute(_ route: BranchRoute) {
        guard routeChoiceAvailable, route != .undecided else { return }
        expansion.route = route
        updateDecision()
    }

    mutating func choosePerk(_ perk: ExpeditionPerk) {
        guard canChoosePerk, availablePerks.contains(perk) else { return }
        applyPerk(perk)
    }

    mutating func act(_ action: RunnerAction) {
        guard phase == .running, !isPortalTransitioning else { return }
        if portalReady {
            if action == .jump { beginPortal(precision: false) }
            return
        }
        if isWaterTraversal && !grounded && height > 0.45 && [.jump, .left, .right].contains(action) {
            performWaterTrick(action)
        }
        switch action {
        case .left:
            enhancements.waterSteeringTarget = nil
            lane = max(-1, lane - 1)
            if routeChoiceAvailable { chooseRoute(.safe) }
        case .right:
            enhancements.waterSteeringTarget = nil
            lane = min(1, lane + 1)
            if routeChoiceAvailable { chooseRoute(.risky) }
        case .jump:
            if isWaterTraversal { return }
            guard activePowerUps[.jetpack] == nil else { return }
            guard grounded else {
                // A late swipe just before landing is remembered; held/repeated swipes
                // during the arc do not create an automatic second jump.
                if verticalVelocity < 0 && height < 0.9 { enhancements.jumpBuffer = 0.12 }
                return
            }
            launchJump()
        case .roll:
            if isWaterTraversal {
                if challenge.brakeTime <= 0 { rolls += 1 }
                challenge.brakeTime = 0.85
                challenge.boostTime = 0
                return
            }
            guard activePowerUps[.jetpack] == nil else { return }
            if !isRolling { rolls += 1 }
            rollTime = 0.8
            isRolling = true
            enhancements.jumpBuffer = 0
            if !grounded { verticalVelocity = min(verticalVelocity, -15) }
        case .board:
            if isWaterTraversal {
                guard challenge.boostCharge >= 0.5, !isBoosting, grounded else { return }
                challenge.boostCharge -= 0.5
                challenge.boostTime = 2.6
                challenge.brakeTime = 0
                showEvent("BOOST ENGAGED")
                return
            }
            guard availableBoards > 0, boardTime <= 0 else { return }
            availableBoards -= 1
            boardsUsed += 1
            boardTime = 30
            if isExpansionActive { expansion.usedProtection = true }
        case .ability:
            guard canActivateAbility, let ability = selectedAbility else { return }
            enhancements.abilityCharges -= abilityChargeCost
            enhancements.activeAbility = ability
            switch ability {
            case .airDash:
                enhancements.abilityTime = selectedPerks.contains(.dashDividend) ? 0.8 : 0.55
                if selectedPerks.contains(.dashDividend) { expansion.dashRewardTime = 1.6 }
                grounded = false; isRolling = false; rollTime = 0
                height = max(height, 1.4)
                verticalVelocity = max(verticalVelocity, 4)
            case .phaseStep:
                enhancements.abilityTime = selectedPerks.contains(.longPhase) ? 1.8 : 1.2
                invulnerableTime = max(invulnerableTime, enhancements.abilityTime)
                if isExpansionActive { expansion.usedProtection = true }
            case .shield:
                enhancements.shieldArmed = true
                if isExpansionActive { expansion.usedProtection = true }
            }
            showEvent(ability.title.uppercased() + " ENGAGED")
        }
    }

    private mutating func launchJump() {
        isRolling = false; rollTime = 0
        enhancements.jumpBuffer = 0
        verticalVelocity = activePowerUps[.sneakers] == nil ? (mode == .odyssey ? worldStage.jumpVelocity : 8.5) : 11.8
        grounded = false
        jumps += 1
        if mode == .odyssey, let remaining = portalDistance, remaining <= 14 {
            enhancements.portalJumpTime = 1.25
        }
    }

    private mutating func performWaterTrick(_ action: RunnerAction) {
        guard enhancements.trickCooldown <= 0, !enhancements.trickActions.contains(action.rawValue),
              enhancements.trickChain < 3 else { return }
        enhancements.trickActions.insert(action.rawValue)
        enhancements.trickChain += 1
        enhancements.trickPendingPoints += 100 * Double(enhancements.trickChain)
        enhancements.trickCooldown = 0.18
        challenge.trickUsed = true
        challenge.trickTime = 0.3
        jumps += 1
        showEvent("\(enhancements.trickChain)× AIR COMBO · LAND TO BANK")
    }

    mutating func update(dt: Double) {
        guard phase == .running, dt.isFinite, dt > 0 else { return }
        var remaining = min(dt, 60)
        while remaining > 0.000_000_1, phase == .running {
            let step = min(remaining, 1.0 / 90.0)
            stepWorld(step)
            remaining -= step
        }
    }

    mutating func pause() { if phase == .running { phase = .paused } }
    mutating func resume() { if phase == .paused { phase = .running } }

    /// The economy decides whether to spend a key; this restores the interrupted run.
    mutating func revive() {
        guard phase == .crashed else { return }
        if isExpansionActive { expansion.usedProtection = true }
        phase = .running
        crashReason = ""
        invulnerableTime = 3.0
        verticalVelocity = 0
        isRolling = false
        rollTime = 0
        height = 0
        grounded = true
        challenge.boostTime = 0
        challenge.brakeTime = 0
        challenge.trickTime = 0
        challenge.timeRemaining = max(challenge.timeRemaining, 15)
        entities.removeAll { Self.isObstacle($0.kind) && $0.z < 18 && $0.z > -$0.length / 2 - 2 }
    }

    mutating func finish() {
        guard phase != .menu else { return }
        phase = .finished
    }

    /// A deterministic test fixture; production starts always enable procedural generation.
    mutating func replaceTrackForTesting(_ track: [TrackEntity], generate: Bool = false) {
        entities = track
        nextID = max(nextID, (track.map(\.id).max() ?? -1) + 1)
        processedObstacles.removeAll()
        challenge.closestApproaches.removeAll()
        generateTrack = generate
    }

    private mutating func stepWorld(_ dt: Double) {
        if isPortalTransitioning { advancePortal(dt); return }
        if portalReady {
            if portalAssist { beginPortal(precision: false) }
            return
        }
        elapsed += dt
        if mode == .odyssey { enhancements.stageElapsed += dt }
        expansion.dashRewardTime = max(0, expansion.dashRewardTime - dt)
        enhancements.landingImpact = max(0, enhancements.landingImpact - dt * 3)
        enhancements.jumpBuffer = max(0, enhancements.jumpBuffer - dt)
        enhancements.portalJumpTime = max(0, enhancements.portalJumpTime - dt)
        enhancements.trickCooldown = max(0, enhancements.trickCooldown - dt)
        enhancements.abilityTime = max(0, enhancements.abilityTime - dt)
        if enhancements.abilityTime == 0 && !enhancements.shieldArmed { enhancements.activeAbility = nil }
        challenge.boostTime = max(0, challenge.boostTime - dt)
        challenge.brakeTime = max(0, challenge.brakeTime - dt)
        challenge.trickTime = max(0, challenge.trickTime - dt)
        challenge.eventTime = max(0, challenge.eventTime - dt)
        // Safe landing and portal lanes are interludes, not combo penalties.
        if mode != .odyssey || (stageDistance > stageOpeningLength - 10 && (portalDistance ?? 999) > portalApproachLength) {
            challenge.comboTime = max(0, challenge.comboTime - dt)
        }
        if challenge.comboTime == 0 { challenge.combo = 0 }
        if mode == .jetSki {
            speed = min(expert ? 34 : 31, (expert ? 23 : 19) + elapsed * 0.11)
            if isBoosting { speed += 10 }
            if isBraking { speed *= 0.58 }
            // Gates and tricks are the main recharge. Passive recharge prevents a dead meter.
            challenge.boostCharge = min(1, challenge.boostCharge + dt * 0.007)
        } else if mode == .odyssey {
            speed = stageTargetSpeed
            if isWaterTraversal {
                if isBoosting { speed += 10 }
                if isBraking { speed *= 0.72 }
                challenge.boostCharge = min(1, challenge.boostCharge + dt * 0.007)
            }
            if enhancements.activeAbility == .airDash && abilityTime > 0 {
                speed = routeRevision >= 6 ? speed + 6 : min(expert ? 50 : 44, speed + 6)
            }
        } else {
            speed = min(expert ? 36 : 32, (expert ? 16 : 12) + elapsed * (expert ? 0.24 : 0.18))
        }
        let travel = mode == .odyssey ? min(speed * dt, max(0, stageLength - stageDistance)) : speed * dt
        let previousTier = difficultyTier
        distance += travel
        if mode == .odyssey {
            journey.stageDistance += travel
            updateExpansionTraversal()
            if routeRevision >= 5 && difficultyTier != previousTier {
                showEvent(difficultyTier.title.uppercased() + " · SPEED AND HAZARDS RISING")
            }
        }
        boardTime = max(0, boardTime - dt)
        invulnerableTime = max(0, invulnerableTime - dt)
        rollTime = max(0, rollTime - dt)
        isRolling = rollTime > 0

        for power in Array(activePowerUps.keys) {
            let time = (activePowerUps[power] ?? 0) - dt
            if time > 0 {
                activePowerUps[power] = time
            } else {
                activePowerUps.removeValue(forKey: power)
                if power == .jetpack {
                    verticalVelocity = 0
                    grounded = false
                    invulnerableTime = max(invulnerableTime, 1.2)
                }
            }
        }
        multiplier = baseMultiplier * (activePowerUps[.multiplier] == nil ? 1 : 2)
        preciseScore += travel * Double(multiplier) * 5
        score = Int(preciseScore)
        if isWaterTraversal {
            // A damped craft has momentum, unlike lane-snapping on land. Braking
            // makes a tighter turn, while deterministic crosscurrents push the hull.
            enhancements.waterCurrent = sin(distance * 0.025) * 0.42 + sin(distance * 0.071) * 0.18
            let stiffness = isBraking ? 60.0 : isBoosting ? 30.0 : 42.0
            let damping = isBraking ? 13.0 : 10.0
            let acceleration = ((enhancements.waterSteeringTarget ?? Double(lane)) - lateral) * stiffness - enhancements.lateralVelocity * damping + enhancements.waterCurrent * (grounded ? 3 : 0.6)
            enhancements.lateralVelocity = max(-5, min(5, enhancements.lateralVelocity + acceleration * dt))
            lateral = max(-1.16, min(1.16, lateral + enhancements.lateralVelocity * dt))
        } else {
            let oldLateral = lateral
            let steeringRate = mode == .odyssey && worldStage == .cryo ? 3.8 : 9.0
            lateral += max(-dt * steeringRate, min(dt * steeringRate, Double(lane) - lateral))
            enhancements.lateralVelocity = (lateral - oldLateral) / dt
        }
        for index in entities.indices {
            // In Odyssey, cargo begins its charge only after the preceding encounter
            // is behind the player. It cannot overtake an earlier required jump row.
            let closing = (mode == .odyssey || mode == .jetSki) && entities[index].oncomingSpeed > 0 && entities[index].z > 32 ? 0 : entities[index].oncomingSpeed
            entities[index].z -= travel + closing * dt
        }
        updateHeight(dt)
        if grounded && enhancements.jumpBuffer > 0 && !isWaterTraversal { launchJump() }
        collectAndCollide()
        guard phase == .running else { return }

        // Count a dodge once the complete obstacle has passed, including long trams.
        for entity in entities where Self.isObstacle(entity.kind) {
            if entity.z + entity.length / 2 < -0.6 && !processedObstacles.contains(entity.id) {
                processedObstacles.insert(entity.id)
                dodges += 1
                if let closest = challenge.closestApproaches[entity.id], closest < 0.98 {
                    if closest >= 0.55 {
                        challenge.nearMisses += 1
                        rewardSkill(points: 45, message: "CLOSE CALL +45")
                    } else {
                        if mode == .odyssey { enhancements.stageSkillActions += 1 }
                        if finaleActive { expansion.finaleSkillActions += 1 }
                        if expansion.dashRewardTime > 0 { preciseScore += 75 * Double(multiplier) }
                        rewardSkill(points: 60, message: [.arch, .laserSweep].contains(entity.kind) ? "CLEAN SLIDE +60" : "CLEAN ESCAPE +60")
                    }
                }
            }
        }
        for gate in entities where [.gate, .checkpoint, .airRing].contains(gate.kind)
            && gate.z < (gate.kind == .airRing ? -1.8 : -0.9) && !processedObstacles.contains(gate.id) {
            processedObstacles.insert(gate.id)
            challenge.gatesMissed += 1
            challenge.combo = 0
            challenge.comboTime = 0
            if gate.kind == .gate {
                challenge.timeRemaining = max(0, challenge.timeRemaining - 4)
                challenge.boostCharge = max(0, challenge.boostCharge - 0.08)
                showEvent(mode == .odyssey ? "GATE MISSED · BOOST LOST" : "GATE MISSED  −4s")
            } else if gate.kind == .checkpoint {
                showEvent("CHECKPOINT MISSED")
            } else {
                showEvent("RING MISSED · COMBO LOST")
            }
        }
        if mode == .harborSprint || mode == .jetSki {
            challenge.timeRemaining = max(0, challenge.timeRemaining - dt)
            if distance >= courseTarget {
                phase = .finished
                showEvent("COURSE COMPLETE")
            } else if challenge.timeRemaining <= 0 {
                phase = .crashed
                crashReason = mode == .jetSki ? "Time ran out. Cross slalom gates to earn time; use boost on clear straights." : "Time ran out. Follow the illuminated checkpoints to extend your sprint."
            }
        }
        score = Int(preciseScore)
        let discardedIDs = entities.filter { $0.z + $0.length / 2 < -22 }.map(\.id)
        entities.removeAll { $0.z + $0.length / 2 < -22 }
        for id in discardedIDs {
            processedObstacles.remove(id)
            challenge.closestApproaches.removeValue(forKey: id)
        }
        if generateTrack && phase == .running { extendTrack() }
        if mode != .odyssey && activePowerUps[.jetpack] != nil && phase == .running { extendAirCourse() }
        if portalReady {
            let precision = enhancements.portalJumpTime > 0 && height > 0.2 && !isRolling
            if portalAssist || precision {
                beginPortal(precision: precision)
            } else {
                height = 0; verticalVelocity = 0; grounded = true
                isRolling = false; rollTime = 0
                showEvent("PORTAL OPEN · JUMP TO ENTER")
            }
        }
    }

    private mutating func updateHeight(_ dt: Double) {
        if activePowerUps[.jetpack] != nil {
            height += min(6.2 - height, dt * 12)
            verticalVelocity = 0
            grounded = false
            isRolling = false
            rollTime = 0
            return
        }

        if isWaterTraversal {
            if grounded {
                height = 0
                challenge.trickUsed = false
            } else {
                enhancements.airTime += dt
                verticalVelocity -= 18 * dt
                height += verticalVelocity * dt
                if height <= 0 {
                    height = 0
                    enhancements.landingImpact = min(1, abs(verticalVelocity) / 12)
                    verticalVelocity = 0
                    grounded = true
                    let stable = challenge.trickTime <= 0 && abs(enhancements.lateralVelocity) < 3.4
                    if enhancements.trickChain > 0 {
                        if stable {
                            enhancements.cleanLandings += 1
                            rewardSkill(points: enhancements.trickPendingPoints,
                                        message: "\(enhancements.trickChain)× CLEAN LANDING +\(Int(enhancements.trickPendingPoints))")
                            challenge.boostCharge = min(1, challenge.boostCharge + 0.12 * Double(enhancements.trickChain))
                        } else {
                            challenge.combo = 0; challenge.comboTime = 0
                            challenge.boostCharge = max(0, challenge.boostCharge - 0.1)
                            challenge.brakeTime = 0.45
                            showEvent("ROUGH LANDING · RELEASE TRICKS EARLIER")
                        }
                    }
                    challenge.trickTime = 0
                    enhancements.trickChain = 0
                    enhancements.trickPendingPoints = 0
                    enhancements.trickActions.removeAll()
                    enhancements.airTime = 0
                }
            }
            return
        }

        var support = 0.0
        for entity in entities where abs(lateral - (Double(entity.lane) + entity.laneOffset())) < 0.52 {
            if entity.kind == .ramp && abs(entity.z) <= entity.length / 2 + 0.1 {
                let progress = min(1, max(0, (entity.length / 2 - entity.z) / entity.length))
                support = max(support, progress * Self.tramRoofHeight)
            }
            if entity.kind == .tram && abs(entity.z) <= entity.length / 2 + 0.3,
               height >= Self.tramRoofHeight - 0.4 {
                support = max(support, Self.tramRoofHeight)
                if isExpansionActive && worldStage == .mars && expansion.traversedRoofs.insert(entity.id).inserted {
                    expansion.roverTransfers += 1
                }
            }
        }

        // Ramp support is allowed to rise beneath a runner who is on the ground.
        if grounded && support >= height - 0.12 {
            height = support
            verticalVelocity = 0
        } else {
            grounded = false
            verticalVelocity -= (mode == .odyssey ? worldStage.gravity : 22) * dt
            height += verticalVelocity * dt
            if height <= support && verticalVelocity <= 0 {
                enhancements.landingImpact = min(1, abs(verticalVelocity) / 14)
                height = support
                verticalVelocity = 0
                grounded = true
            }
        }
    }

    private mutating func collectAndCollide() {
        var collected = Set<Int>()
        // Read from a snapshot because jetpack activation adds airborne coin trails.
        for entity in entities {
            // Colliders sit where they are drawn: a lane-changer's lane interpolates with z.
            let aligned = abs(lateral - (Double(entity.lane) + entity.laneOffset())) < 0.55
            let near = abs(entity.z) < 0.85
            if entity.kind == .coin {
                let magnet = activePowerUps[.magnet] != nil && entity.z < 16 && entity.z > -2
                // Low coins mark a roll: standing runners pass over them.
                let reachable = entity.y <= 0.6 ? isRolling && height < 0.2 : abs(entity.y - (height + 0.9)) < 1.15
                if (aligned && near && reachable) || (magnet && abs(entity.y - height) < 8) {
                    let coinValue = routeIsActive && branchRoute == .risky ? 2 : 1
                    coins += coinValue
                    preciseScore += Double(coinValue * 10 * multiplier)
                    collected.insert(entity.id)
                }
                continue
            }
            if entity.kind == .relic {
                if mode == .odyssey && aligned && near && abs(entity.y - (height + 0.9)) < 1.3
                    && !journey.collectedRelicIDs.contains(entity.id) {
                    journey.collectedRelicIDs.insert(entity.id)
                    journey.artifactsCollected += 1
                    journey.collectedArtifactWorlds.insert(worldStage)
                    expansion.capacitorRelics += 1
                    if !selectedPerks.contains(.relicCapacitor) || expansion.capacitorRelics % 2 == 0 {
                        enhancements.abilityCharges = min(maximumAbilityCharges, enhancements.abilityCharges + 1)
                    }
                    if enhancements.selectedAbility == nil {
                        enhancements.selectedAbility = worldStage == .orbit || worldStage == .cryo ? .airDash : worldStage == .mars || worldStage == .forge ? .phaseStep : .shield
                    }
                    preciseScore += 250 * Double(multiplier)
                    showEvent("RELIC +250 · ARTIFACT CHARGE \(abilityCharges)/\(maximumAbilityCharges)")
                    collected.insert(entity.id)
                }
                continue
            }
            if entity.kind == .key {
                if aligned && near && abs(entity.y - (height + 0.9)) < 1.3 {
                    keys += 1
                    collected.insert(entity.id)
                }
                continue
            }
            if let power = PowerUp(rawValue: entity.kind.rawValue) {
                if aligned && near && abs(entity.y - (height + 0.9)) < 1.5 {
                    activate(power)
                    collected.insert(entity.id)
                }
                continue
            }
            if [.gate, .checkpoint, .airRing].contains(entity.kind) {
                let onPlane = entity.kind == .airRing ? activePowerUps[.jetpack] != nil && abs(height + 0.9 - entity.y) < 1.5 : height < (isWaterTraversal ? 4.2 : 3)
                // Credit a flight ring after its drone row is behind the pilot. This gives
                // the next-ring cue only when an immediate lane change is safe.
                let gateCrossing = entity.kind == .airRing ? entity.z <= -0.8 && entity.z >= -1.8 : near
                if aligned && gateCrossing && onPlane && !processedObstacles.contains(entity.id) {
                    processedObstacles.insert(entity.id)
                    collected.insert(entity.id)
                    challenge.gatesCleared += 1
                    let bonus = entity.kind == .checkpoint ? (expert ? 3.0 : 4.0) : entity.kind == .gate ? (expert ? 0.5 : 0.8) : 0
                    if mode != .endless { challenge.timeRemaining = min(90, challenge.timeRemaining + bonus) }
                    if entity.kind == .gate { challenge.boostCharge = min(1, challenge.boostCharge + 0.16) }
                    let label = entity.kind == .checkpoint ? (expert ? "CHECKPOINT +3s" : "CHECKPOINT +4s") : entity.kind == .gate ? (expert ? "PERFECT GATE +0.5s" : "PERFECT GATE +0.8s") : "AIR RING +90"
                    rewardSkill(points: entity.kind == .checkpoint ? 150 : 90, message: mode == .odyssey && entity.kind == .gate ? "PERFECT GATE · BOOST +16%" : label)
                }
                continue
            }
            if entity.kind == .waveRamp {
                if aligned && abs(entity.z) < 1.0 && grounded && !processedObstacles.contains(entity.id) {
                    processedObstacles.insert(entity.id)
                    grounded = false
                    verticalVelocity = isBoosting ? 11.5 : 9.5
                    enhancements.trickActions.removeAll()
                    enhancements.trickChain = 0
                    enhancements.trickPendingPoints = 0
                    enhancements.trickCooldown = 0
                    enhancements.airTime = 0
                    showEvent("WAKE JUMP · UP / LEFT / RIGHT TO COMBO")
                }
                continue
            }
            guard Self.isObstacle(entity.kind),
                  abs(entity.z) < entity.length / 2 + 0.35,
                  !processedObstacles.contains(entity.id) else { continue }
            let inFlight = activePowerUps[.jetpack] != nil
            if inFlight && entity.kind != .airHazard { continue }
            if !inFlight && entity.kind == .airHazard { continue }
            if invulnerableTime > 0 { continue }
            // A meteor before impact or a deck before collapse has no collider yet.
            guard entity.isActive else { continue }
            // A timed laser that is off is no threat: standing through it earns no dodge credit.
            guard entity.isOn(at: elapsed) else { continue }
            challenge.closestApproaches[entity.id] = min(challenge.closestApproaches[entity.id] ?? 100,
                                                         abs(lateral - (Double(entity.lane) + entity.laneOffset())))
            guard aligned else { continue }
            let collides: Bool
            switch entity.kind {
            case .barrier, .root: collides = height < 1.03
            case .gap, .iceCrack: collides = height < 0.4
            case .meteor: collides = height < 2.5
            case .laserSweep: collides = height < worldStage.stackTop && (!isRolling || height > 0.15) // frame drawn to stackTop
            case .arch: collides = !isRolling || height > 0.15
            case .waterTraffic: collides = height < 1.8
            case .tram: collides = height < Self.tramRoofHeight - 0.35
            case .buoy: collides = height < 1.4
            case .airHazard: collides = inFlight && abs(height - entity.y) < 2.0
            case .wall: collides = height < Self.wallTop // drawn 3.8 m tall; only a sneakers jump in low gravity clears it
            case .stack: collides = height < worldStage.stackTop // a normal jump or roll never clears it
            default: collides = false
            }
            if collides {
                processedObstacles.insert(entity.id)
                challenge.combo = 0
                challenge.comboTime = 0
                challenge.boostTime = 0
                if mode == .odyssey { enhancements.stageHits += 1 }
                if finaleActive { expansion.finaleHits += 1 }
                if enhancements.shieldArmed {
                    enhancements.shieldArmed = false
                    enhancements.activeAbility = nil
                    invulnerableTime = 2
                    enhancements.landingImpact = 1
                    for nearby in entities where Self.isObstacle(nearby.kind) && abs(nearby.z) < 18 { collected.insert(nearby.id) }
                    showEvent("AEGIS ABSORBED IMPACT")
                } else if boardTime > 0 {
                    boardTime = 0
                    invulnerableTime = 2
                    // A shield burst clears nearby obstacles so a long tram cannot hit twice.
                    for nearby in entities where Self.isObstacle(nearby.kind) && abs(nearby.z) < 18 {
                        collected.insert(nearby.id)
                    }
                } else {
                    phase = .crashed
                    switch entity.kind {
                    case .barrier: crashReason = "Jump over the cargo barriers."
                    case .gap: crashReason = "Jump across the broken orbital deck. Start the leap before the glowing edge."
                    case .root: crashReason = "Jump over the rising roots. Watch their glowing growth lines."
                    case .iceCrack: crashReason = "Jump the fractured ice. Steer before the next landing."
                    case .meteor: crashReason = "Change lanes before the meteor impact marker reaches you."
                    case .laserSweep: crashReason = entity.cyclePhase >= 0 ? "Slide under the timed laser, or pass while its beam is dashed (off)." : "Slide under the sweeping beam. Land before trying to pass beneath it."
                    case .waterTraffic: crashReason = "Carve around the approaching boats. Brake early or take a wake jump."
                    case .arch: crashReason = mode == .odyssey ? "Slide under the energy beams or change lanes." : "Slide under the low signs."
                    case .tram: crashReason = mode == .odyssey ? (worldStage == .mars ? "Dodge the rovers or take a ramp onto their roof." : "Choose a clear lane around the cargo. Watch its approach before crossing.") : "Dodge trams or take a ramp onto the roof."
                    case .buoy: crashReason = "Steer around the course buoys. Brake before tight turns; ramps let you jump the water hazards."
                    case .airHazard: crashReason = "Dodge the airborne drones. Follow the glowing rings through the flight route."
                    case .wall: crashReason = "Steer to the opening in the wall. It moves one lane from your last route."
                    case .stack: crashReason = "A barrier under a beam blocks both jumps and slides. Change lanes."
                    default: crashReason = "Give it another run."
                    }
                    break
                }
            }
        }
        entities.removeAll { collected.contains($0.id) }
        // Collected gates and shield-cleared hazards leave before the normal rear pruning.
        // Forget their bookkeeping too, so a long endless run cannot accumulate stale IDs.
        for id in collected {
            processedObstacles.remove(id)
            challenge.closestApproaches.removeValue(forKey: id)
        }
        score = Int(preciseScore)
    }

    private mutating func extendTrack() {
        if mode == .odyssey {
            extendJourneyCourse()
            return
        }
        if mode == .jetSki {
            extendWaterCourse()
            return
        }
        while nextPatternDistance < distance + 190 {
            let at = nextPatternDistance
            let centerZ = at - distance
            // Each row has a visible route; consecutive clear lanes are at most one lane apart.
            // Shorter rows and higher speed force decisions without impossible lateral jumps.
            let candidates = [-1, 0, 1].filter { abs($0 - challenge.previousSafeLane) <= 1 }
            var safeLane = candidates[Int(nextRandom() % UInt64(candidates.count))]
            if safeLane == challenge.previousSafeLane && nextRandom() % 3 != 0 {
                safeLane = safeLane == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
            }
            challenge.previousSafeLane = safeLane
            let pattern = Int(nextRandom() % 9)
            var obstacleLanes = [-1, 0, 1].filter { $0 != safeLane }
            if nextRandom() % 2 == 0 { obstacleLanes.reverse() }
            let primary = obstacleLanes[0]
            if pattern == 0 || (at < 90 && !expert) {
                add(.barrier, lane: primary, z: centerZ, y: 0, length: 0.8)
            } else if pattern == 1 || pattern == 5 {
                add(.arch, lane: primary, z: centerZ, y: 0, length: 1.1)
            } else {
                let oncoming = distance > 500 && (pattern == 6 || pattern == 8)
                    && oncomingLaneIsFair(primary, aheadOf: centerZ)
                add(.tram, lane: primary, z: centerZ, y: 0, length: 12,
                    oncomingSpeed: oncoming ? 8 + Double(nextRandom() % 5) : 0)
                if !oncoming && (pattern == 2 || pattern == 4 || pattern == 7) {
                    add(.ramp, lane: primary, z: centerZ - 10, y: 0, length: 7)
                    for offset in [-3.5, -0.5, 2.5, 5.0] {
                        add(.coin, lane: primary, z: centerZ + offset, y: Self.tramRoofHeight + 0.9, length: 0.3)
                    }
                }
            }
            if expert || at > 65 {
                let secondary: EntityKind = pattern % 2 == 0 ? .arch : .barrier
                add(secondary, lane: obstacleLanes[1], z: centerZ, y: 0,
                    length: secondary == .barrier ? 0.8 : 1.1)
            }
            // Coins are an invitation, not a route marker (see placeCoins).
            let rowHazards = entities.filter { Self.isObstacle($0.kind) && abs($0.z - centerZ) < 1 }
            let solids = rowHazards.filter { tram in
                tram.kind == .tram && tram.oncomingSpeed == 0 &&
                    !entities.contains { $0.kind == .ramp && $0.lane == tram.lane && abs($0.z - (tram.z - 10)) < 1 }
            }
            // Standard opens with teaching rows: only safe or action lines. One draw per row either way.
            let teaching = !expert && at < 160
            let roll = nextRandom() % 100
            let line = Self.coinLine(roll: teaching ? roll % 60 : roll,
                                     actionable: rowHazards.contains { $0.kind == .barrier || $0.kind == .arch },
                                     solid: !solids.isEmpty)
            // Rows arrive about 190 m later, by which time the run is faster.
            let arrivalSpeed = min(expert ? 36 : 32, speed + (expert ? 0.24 : 0.18) * 190 / max(1, speed))
            placeCoins(line, z: centerZ, safe: safeLane, speed: arrivalSpeed, jumpApex: 1.45,
                       jumpLanes: rowHazards.filter { $0.kind == .barrier }.map(\.lane),
                       slideLanes: rowHazards.filter { $0.kind == .arch }.map(\.lane), solids: solids, teaching: teaching,
                       // The next row starts at least 23 (expert) or 26 m on; its tram reaches 6 m back, plus the 1.3 m coin margin.
                       coinLimit: centerZ + (expert ? 23 : 26) - 7.3)
            // Pickups sit off the safe lane, behind this row's hazards: collecting one is a choice.
            let pickupLane = obstacleLanes[Int(nextRandom() % 2)]
            if at > 100 && nextRandom() % 7 == 0 {
                // Sprint checkpoints are a ground slalom: flight would hide their route and
                // could turn a beneficial pickup into a forced missed time extension.
                let availablePowers = PowerUp.allCases.filter { mode != .harborSprint || $0 != .jetpack }
                let power = availablePowers[Int(nextRandom() % UInt64(availablePowers.count))]
                add(EntityKind(rawValue: power.rawValue)!, lane: pickupLane, z: centerZ + 10, y: 1, length: 0.8)
            }
            if at > 250 && nextRandom() % 18 == 0 {
                add(.key, lane: pickupLane, z: centerZ + 13, y: 1, length: 0.5)
            }
            if mode == .harborSprint && at >= challenge.nextCheckpointDistance {
                add(.checkpoint, lane: safeLane, z: centerZ, y: 1, length: 0.5)
                challenge.nextCheckpointDistance += 200
            }
            // Clearance exceeds the full tram length; at top speed there is >=0.65 s per row.
            nextPatternDistance += (expert ? 23 : 26) + Double(nextRandom() % 5)
        }
    }

    private mutating func applyPerk(_ perk: ExpeditionPerk) {
        guard !selectedPerks.contains(perk) else { return }
        expansion.selectedPerks.append(perk)
        expansion.stagePerk = perk
        // A capacitor upgrade starts a new two-relic recharge cycle.
        if perk == .relicCapacitor { expansion.capacitorRelics = 0 }
        updateDecision()
        showEvent(perk.title.uppercased() + " INSTALLED")
    }

    private mutating func updateDecision() {
        guard expeditionStyle == .campaign else { return }
        let choice = ExpeditionDecision(world: stageIndex, route: branchRoute, perk: expansion.stagePerk)
        if let index = expansion.decisions.firstIndex(where: { $0.world == stageIndex }) { expansion.decisions[index] = choice }
        else { expansion.decisions.append(choice) }
    }

    private mutating func configureExpansionArrival() {
        guard isExpansionActive else { return }
        expansion.route = isPractice ? .safe : .undecided
        expansion.stagePerk = nil
        expansion.usedProtection = boardTime > 0 || enhancements.shieldArmed
        expansion.finaleRows = 0
        expansion.finaleSkillActions = 0
        expansion.finaleHits = 0
        expansion.roverTransfers = 0
        expansion.traversedRoofs.removeAll()
        expansion.stageCleanLandings = enhancements.cleanLandings
        expansion.wasWater = false
        if let planned = expansion.replayPlan?.first(where: { $0.world == stageIndex }) {
            if let perk = planned.perk, stagesCleared > 0 { applyPerk(perk) }
        } else if dailyID != nil, stagesCleared > 0, !availablePerks.isEmpty {
            // Every daily entrant gets the same upgrade order and safe fork.
            applyPerk(availablePerks[0])
        }
        updateDecision()
    }

    private mutating func updateExpansionTraversal() {
        guard isExpansionActive else { return }
        if stageProgress >= 0.26 && branchRoute == .undecided {
            let planned = expansion.replayPlan?.first(where: { $0.world == stageIndex })?.route
            expansion.route = dailyID != nil ? .safe : (planned == .safe || planned == .risky ? planned! : lane > 0 ? .risky : .safe)
            updateDecision()
            showEvent(expansion.route.title(in: worldStage).uppercased())
        }
        let water = isWaterTraversal
        if water != expansion.wasWater {
            // Shore transitions have a long, hazard-free run-up and exit. The
            // vehicle handoff cannot inherit an airborne jump or a held brake.
            height = 0; verticalVelocity = 0; grounded = true
            isRolling = false; rollTime = 0
            challenge.brakeTime = 0; challenge.boostTime = 0
            challenge.trickTime = 0
            enhancements.waterSteeringTarget = nil
            enhancements.lateralVelocity = 0
            enhancements.trickChain = 0
            enhancements.trickPendingPoints = 0
            enhancements.trickActions.removeAll()
            expansion.wasWater = water
            showEvent(water ? "TIDAL CHANNEL · CARVE / BRAKE / BOOST" : "BACK ON FOOT · MOMENTUM RETAINED")
        }
    }

    private mutating func beginPortal(precision: Bool) {
        guard mode == .odyssey, !isPortalTransitioning, !journeyComplete else { return }
        journey.transitionTime = 0
        enhancements.portalEntryHeight = height
        enhancements.precisionPortal = precision
        if !precision { jumps += 1 }
        if precision { rewardSkill(points: 200, message: "PRECISION PORTAL +200") }
        else { showEvent("GATEWAY LINKED") }
        entities.removeAll()
        processedObstacles.removeAll()
        challenge.closestApproaches.removeAll()
        isRolling = false; rollTime = 0
        enhancements.jumpBuffer = 0
    }

    private mutating func advancePortal(_ dt: Double) {
        guard let transition = journey.transitionTime else { return }
        journey.transitionTime = min(1.6, transition + dt)
        // Transit keeps visual forward motion, while freezing purchased resources and
        // obstacle physics. It contributes to total route distance, never stage time.
        distance += speed * dt
        elapsed += dt
        height = enhancements.portalEntryHeight * (1 - portalTransitionProgress) + sin(portalTransitionProgress * .pi) * 2.2
        lateral += (0 - lateral) * min(1, dt * 5)
        guard journey.transitionTime! >= 1.6 - 0.000_001 else { return }
        journey.stagesCleared += 1
        journey.transitionTime = nil
        let clean = enhancements.stageHits == 0 && enhancements.stageSkillActions >= 2
        let medal: WorldMedal = clean && stageRelics >= 2 && enhancements.precisionPortal ? .gold : clean ? .silver : .bronze
        preciseScore += 500 * Double(multiplier)
        score = Int(preciseScore)
        let goalsCompleted = objectiveStatus.filter(\.completed).count
        let finaleCleared = isExpansionActive && expansion.finaleHits == 0 && expansion.finaleSkillActions >= 2
        expansion.completedObjectives += goalsCompleted
        if finaleCleared { expansion.totalFinalesCleared += 1 }
        enhancements.stageResults.append(WorldStageResult(routeRevision: routeRevision, stage: worldStage, medal: medal,
            score: score - enhancements.stageStartScore, relics: stageRelics, hits: enhancements.stageHits,
            elapsed: enhancements.stageElapsed, precisionPortal: enhancements.precisionPortal,
            skillActions: enhancements.stageSkillActions, usedProtection: expansion.usedProtection,
            branchRoute: branchRoute, finaleCleared: finaleCleared, perk: expansion.stagePerk,
            roverTransfers: expansion.roverTransfers, objectivesCompleted: goalsCompleted))
        if expeditionStyle == .endless && enhancements.stageResults.count > 12 {
            enhancements.stageResults.removeFirst(enhancements.stageResults.count - 12)
        }
        if isPractice || (stageIndex == WorldStage.ordered.count - 1 && expeditionStyle != .endless) {
            journey.complete = true
            phase = .finished
            height = 0
            showEvent(isPractice ? "PRACTICE COMPLETE · TRY A CLEANER LINE" : stagesCleared == 6 ? "ODYSSEY COMPLETE · SIX WORLDS CONNECTED" : "ROUTE COMPLETE · FINAL GATEWAY REACHED")
            return
        }
        if stageIndex == WorldStage.ordered.count - 1 {
            journey.stageIndex = 0
            expansion.cycle += 1
        } else { journey.stageIndex += 1 }
        journey.routeRevision = PortalJourney.currentRevision
        journey.stageDistance = 0
        journey.generatedRelics = 0
        journey.collectedRelicIDs.removeAll()
        enhancements.stageElapsed = 0
        enhancements.stageStartScore = score
        enhancements.stageStartRelics = artifactsCollected
        enhancements.stageHits = 0
        enhancements.stageSkillActions = 0
        enhancements.precisionPortal = false
        enhancements.generatedRows = 0
        enhancements.portalJumpTime = 0
        enhancements.abilityTime = 0
        if !enhancements.shieldArmed { enhancements.activeAbility = nil }
        entities.removeAll()
        processedObstacles.removeAll()
        challenge.closestApproaches.removeAll()
        activePowerUps.removeAll()
        invulnerableTime = 3
        multiplier = baseMultiplier
        height = 0; verticalVelocity = 0; grounded = true
        lane = 0; lateral = 0; enhancements.lateralVelocity = 0
        isRolling = false; rollTime = 0
        challenge.comboTime = max(challenge.comboTime, 5)
        challenge.previousSafeLane = 0
        configureExpansionArrival()
        nextPatternDistance = distance + stageOpeningLength
        speed = stageTargetSpeed
        showEvent(worldStage.title.uppercased() + " · " + worldStage.subtitle.uppercased())
        if generateTrack { extendTrack() }
    }

    /// Encounters are assembled in time, not fixed meters: high-speed rows remain
    /// readable, while shorter decision windows and compound beats raise pressure.
    private mutating func extendJourneyCourse() {
        if routeRevision < 5 { extendLegacyJourneyCourse(); return }
        let stageStart = distance - stageDistance
        let hazardLimit = stageStart + stageLength - portalApproachLength
        let horizon = max(210, speed * 6)
        while nextPatternDistance < min(distance + horizon, hazardLimit - 18) {
            let at = nextPatternDistance
            let local = at - stageStart
            let progress = min(1, max(0, local / stageLength))
            let predictedSpeed = expeditionSpeed(at: progress)
            let branchStart = stageLength * 0.32
            let branchEnd = stageLength * 0.55
            // A skip target must be fixed for the boundary. Recomputing it from
            // the skipped position's accelerating speed converges without ever
            // crossing the boundary, trapping generation inside this while loop.
            let entryClearance = expeditionSpeed(at: 0.32) * 2.4
            let exitClearance = expeditionSpeed(at: 0.55) * 2.4
            let changeClearance = progress < 0.32 ? entryClearance : exitClearance
            // Keep both forks empty until the physical choice has locked. No
            // already-spawned hazard changes position when a player chooses.
            if isExpansionActive && !isPractice {
                if local >= branchStart - entryClearance && local < branchStart + entryClearance {
                    nextPatternDistance = stageStart + branchStart + entryClearance + 1
                    continue
                }
                if local >= branchStart && stageProgress < 0.26 { return }
                if local >= branchEnd - exitClearance && local < branchEnd + exitClearance {
                    nextPatternDistance = stageStart + branchEnd + exitClearance + 1
                    continue
                }
            }
            let inBranch = isExpansionActive && progress >= 0.32 && progress < 0.55
            let inFinale = isExpansionActive && progress >= 0.72
            let localLimit = isExpansionActive && !isPractice && progress < 0.32 ? min(hazardLimit, stageStart + branchStart - changeClearance) :
                inBranch ? min(hazardLimit, stageStart + branchEnd - changeClearance) : hazardLimit
            if inBranch && worldStage == .harbor && branchRoute == .safe {
                addJourneyWaterRow(z: at - distance, predictedSpeed: predictedSpeed, local: local, limit: localLimit)
                nextPatternDistance += predictedSpeed * (expert ? 1.65 : 1.9)
                continue
            }
            let tier = isExpansionActive && expeditionCycle > 0 || inBranch && branchRoute == .risky ? JourneyDifficultyTier.overdrive : worldStage.difficultyTier(at: progress, revision: routeRevision)
            let z = at - distance
            let row = enhancements.generatedRows
            enhancements.generatedRows += 1
            let previousSafe = challenge.previousSafeLane
            let candidates = [-1, 0, 1].filter { abs($0 - previousSafe) <= 1 }
            var safe = candidates[Int(nextRandom() % UInt64(candidates.count))]
            challenge.previousSafeLane = safe
            var blocked = [-1, 0, 1].filter { $0 != safe }
            // No short repeating cycle. Later tiers unlock compound choices and
            // weight them more heavily; the PRNG makes each seeded run reproducible.
            let base: [Int]
            switch tier {
            case .warmup: base = [0, 0, 1, 2, 3, 4]
            case .pressure: base = [0, 1, 2, 2, 3, 4, 5, 6]
            case .intense: base = [0, 1, 2, 3, 3, 4, 5, 6, 7]
            case .overdrive: base = [0, 1, 2, 2, 3, 4, 5, 6, 6, 7, 7]
            }
            // New hazards join pressure and later tiers, never a world's first rows.
            let pool = base + (tier == .warmup || row < 4 ? [] : worldStage.hazardPatterns)
            var pattern = pool[Int(nextRandom() % UInt64(pool.count))]
            // Guarantee an early introduction to each world's vertical action.
            if row == 0 { pattern = 0 }
            if row == 1 { pattern = worldStage == .orbit ? 3 : 1 }
            if inBranch {
                if branchRoute == .safe { pattern = row % 3 == 0 ? 0 : 3 }
                else if worldStage == .mars || worldStage == .harbor { pattern = row % 2 == 0 ? 4 : 7 }
                else { pattern = [2, 6, 7, 3][row % 4] }
            }
            if inFinale {
                let phrase = worldStage.finalePatterns
                pattern = phrase[expansion.finaleRows % phrase.count]
                expansion.finaleRows += 1
            }
            let canTransfer = [.harbor, .mars, .forge].contains(worldStage)
            if pattern == 4 && !canTransfer { pattern = 2 }
            if pattern == 5 && worldStage != .forge && worldStage != .harbor { pattern = 7 }
            // A gap wall's opening always moves one lane from the previous route.
            if pattern == 10 && safe == previousSafe {
                safe = previousSafe == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
                challenge.previousSafeLane = safe
                blocked = [-1, 0, 1].filter { $0 != safe }
            }
            var interval = journeyEncounterInterval(progress: progress, pattern: pattern)
            if inBranch && branchRoute == .safe { interval += 0.45 }
            let gap = predictedSpeed * interval
            var relicLane = safe
            // The lane coins and the next row treat as this row's route; a lane-changer moves it.
            var routeLane = safe
            // Ground-coin offsets for the safe line; a lane-changer row moves them before the vehicle's near edge.
            var safeOffsets = [-6.0, -3, 0, 3]
            var relicZ = z
            var relicY = 0.9
            var relicVelocity = 0.0
            let jumpKind: EntityKind = worldStage == .orbit ? .gap : worldStage == .cryo ? .iceCrack : worldStage == .verdant ? .root : .barrier
            let slideKind: EntityKind = [.verdant, .forge].contains(worldStage) ? .laserSweep : .arch
            let jumpLength: Double = jumpKind == .gap ? min(14, 7 + Double(tier.rawValue) * 2) : jumpKind == .iceCrack ? 3.2 + Double(tier.rawValue) : 1.1
            let jumpHeight = worldStage == .orbit ? 3.1 : worldStage == .mars ? 2.0 : 1.45
            let solid: EntityKind = worldStage == .mars ? .meteor : .tram
            let solidLength = solid == .meteor ? 2.0 : 7.0
            if isExpansionActive && at + max(10, predictedSpeed * 0.3) >= localLimit {
                nextPatternDistance = localLimit + changeClearance * 2
                continue
            }
            let rowStart = entities.count
            switch pattern {
            case 0: // Full-width leap: lane changes alone cannot solve the route.
                for lane in -1...1 { add(jumpKind, lane: lane, z: z, y: 0, length: jumpLength) }
                relicY = jumpHeight
            case 1: // Full-width crouch, scheduled after enough time to land.
                for lane in -1...1 { add(slideKind, lane: lane, z: z, y: 0, length: 1.1) }
                relicY = 0.7
            case 2: // Read the lanes: jump / slide / blocked, then commit.
                add(jumpKind, lane: safe, z: z, y: 0, length: jumpLength)
                add(slideKind, lane: blocked[0], z: z, y: 0, length: 1.1)
                add(solid, lane: blocked[1], z: z, y: 0, length: solidLength)
                relicY = jumpHeight
            case 3, 12: // A lane weave gains a second beat as the stage intensifies.
                for lane in blocked { add(solid, lane: lane, z: z, y: 0, length: solidLength) }
                // Pattern 12 (Mars): one rock landed before first sight; beside it a ring marks a late impact,
                // so the lane that looks open is not.
                if pattern == 12 { entities[rowStart].activeFrom = z + 40 }
                if tier != .warmup {
                    let choices = [-1, 0, 1].filter { $0 != safe && abs($0 - safe) == 1 }
                    let exit = choices[Int(nextRandom() % UInt64(choices.count))]
                    let followZ = z + gap * 0.52
                    if at + gap * 0.52 + solidLength / 2 < localLimit {
                        for lane in -1...1 where lane != exit { add(solid, lane: lane, z: followZ, y: 0, length: solidLength) }
                        for offset in [-3.0, 0, 3] { add(.coin, lane: exit, z: followZ + offset, y: 0.9, length: 0.3) }
                        challenge.previousSafeLane = exit
                        relicLane = exit; relicZ = followZ
                    }
                }
            case 4: // Commit to a rover/cargo roof. Its ramp travels with the vehicle.
                let velocity = worldStage == .mars ? -1.5 : 0.0
                add(.tram, lane: safe, z: z, y: 0, length: 9, oncomingSpeed: velocity)
                add(.ramp, lane: safe, z: z - 9, y: 0, length: 7, oncomingSpeed: velocity)
                for lane in blocked { add(solid, lane: lane, z: z, y: 0, length: solidLength) }
                relicY = Self.tramRoofHeight + 0.9; relicVelocity = velocity
                for offset in [-3.0, 0, 3] { add(.coin, lane: safe, z: z + offset, y: relicY, length: 0.3, oncomingSpeed: velocity) }
                if tier.rawValue >= JourneyDifficultyTier.intense.rawValue {
                    // A second adjacent roof rewards an early transfer without
                    // removing the original roof's safe landing route.
                    let side = blocked.min { abs($0 - safe) < abs($1 - safe) }!
                    let roofZ = z + gap * 0.48
                    if at + gap * 0.48 + 5 < localLimit {
                        add(.tram, lane: side, z: roofZ, y: 0, length: 9)
                        add(.ramp, lane: side, z: roofZ - 9, y: 0, length: 7)
                        add(.coin, lane: side, z: roofZ, y: relicY, length: 0.3)
                    }
                }
            case 5: // Charge only in the final approach; it cannot overtake prior rows.
                add(.tram, lane: blocked[0], z: z, y: 0, length: 7, oncomingSpeed: 5 + Double(tier.rawValue))
                add(slideKind, lane: blocked[1], z: z, y: 0, length: 1.1)
                relicLane = blocked[1]; relicY = 0.7
            case 6: // Leap, then steer in flight between landing hazards.
                for lane in -1...1 { add(jumpKind, lane: lane, z: z, y: 0, length: jumpLength) }
                relicY = jumpHeight
                let landingOffset = predictedSpeed * (worldStage == .orbit ? 0.88 : worldStage == .mars ? 0.62 : 0.48)
                if at + landingOffset + solidLength / 2 < localLimit {
                    for lane in blocked { add(solid, lane: lane, z: z + landingOffset, y: 0, length: solidLength) }
                }
            case 8: // Lane-changer: a blocked lane's vehicle slides into the open lane, so the open lane swaps.
                // It leaves a lane next to both the open lane and the previous route: the new exit is one switch away.
                let origins = blocked.filter { abs($0 - safe) == 1 && abs($0 - previousSafe) <= 1 }
                let origin = origins[Int(nextRandom() % UInt64(origins.count))]
                let other = blocked.first { $0 != origin }!
                let length = worldStage == .mars ? 9.0 : 7.0
                // The shift completes a reaction (1.0 s, Expert 0.8 s) plus one lane of steering before the runner reaches it.
                let lead = (expert ? 0.8 : 1.0) + (worldStage == .cryo ? 1 / 3.8 : 1 / 9.0)
                let complete = predictedSpeed * lead + length / 2 + 0.35
                add(.tram, lane: origin, z: z, y: 0, length: length, targetLane: safe,
                    motionStart: complete + predictedSpeed * 0.6, motionLength: predictedSpeed * 0.6)
                add(solid, lane: other, z: z, y: 0, length: solidLength)
                challenge.previousSafeLane = origin
                routeLane = origin
                relicLane = origin
                // The vehicle still fills its origin lane until the shift: coins and relic wait before its near edge.
                safeOffsets = [0.0, 3, 6, 9].map { -(length / 2 + 1.3) - $0 }
                relicZ = z + safeOffsets[0]
            case 9: // Timed laser gate: on 0.9 s, off 0.9 s. Rolling is always safe; a reader can time a run-through.
                let phase = Double(nextRandom() % 18) / 10
                add(.laserSweep, lane: safe, z: z, y: 0, length: 1.1, cyclePhase: phase)
                add(.laserSweep, lane: blocked[0], z: z, y: 0, length: 1.1,
                    cyclePhase: (phase + 0.9).truncatingRemainder(dividingBy: TrackEntity.cycleLength))
                add(solid, lane: blocked[1], z: z, y: 0, length: solidLength)
                relicY = 0.7
            case 10: // Gap wall: full-height walls in two lanes; the one opening is never the previous row's route.
                for lane in blocked { add(.wall, lane: lane, z: z, y: 0, length: 1.0) }
            case 11: // Stacked hazard: it looks like a jump and a slide at once, and allows neither.
                add(jumpKind, lane: safe, z: z, y: 0, length: jumpLength)
                add(slideKind, lane: blocked[0], z: z, y: 0, length: 1.1)
                add(.stack, lane: blocked[1], z: z, y: 0, length: 1.0)
                relicY = jumpHeight
            case 13: // Collapsing deck: every lane cracks, then opens late; at intense tiers the landing has solids too.
                let opens = predictedSpeed * 0.5 + jumpLength / 2 + 0.35
                for lane in -1...1 { add(jumpKind, lane: lane, z: z, y: 0, length: jumpLength, activeFrom: opens) }
                relicY = jumpHeight
                if tier.rawValue >= JourneyDifficultyTier.intense.rawValue {
                    let landingOffset = predictedSpeed * (worldStage == .orbit ? 0.88 : 0.48)
                    if at + landingOffset + solidLength / 2 < localLimit {
                        for lane in blocked { add(solid, lane: lane, z: z + landingOffset, y: 0, length: solidLength) }
                    }
                }
            default: // Two mixed actions with an open adjacent escape on each beat.
                add(jumpKind, lane: safe, z: z, y: 0, length: jumpLength)
                add(solid, lane: blocked[0], z: z, y: 0, length: solidLength)
                add(slideKind, lane: blocked[1], z: z, y: 0, length: 1.1)
                relicY = jumpHeight
                let followZ = z + gap * 0.52
                let followClearance = routeRevision >= 6 ? max(4, jumpLength / 2) : 4
                if at + gap * 0.52 + followClearance < localLimit {
                    // The jump lane stays clear throughout its arc. Side-lane
                    // machinery adds pressure without an unavoidable mid-air beam.
                    add(solid, lane: blocked[1], z: followZ, y: 0, length: solidLength)
                    add(jumpKind, lane: blocked[0], z: followZ, y: 0, length: jumpLength)
                }
            }
            // Meteors land late: the ring warns, the rock falls, and only then does the collider exist (>= 1.0 s ahead).
            for index in rowStart..<entities.count where entities[index].kind == .meteor && !entities[index].activeFrom.isFinite {
                entities[index].activeFrom = predictedSpeed * 1.0 + entities[index].length / 2 + 0.35
            }
            if pattern == 4 {
                // The roof coins ask for a ramp leap: an action line.
                placedCoinLines[.action, default: 0] += 1
            } else {
                let rowHazards = entities[rowStart...].filter { Self.isObstacle($0.kind) && abs($0.z - z) < 1 }
                let jumpLanes = rowHazards.filter { $0.kind == jumpKind }.map(\.lane)
                let slideLanes = rowHazards.filter { $0.kind == slideKind || $0.kind == .laserSweep }.map(\.lane)
                let solids = rowHazards.filter { Self.isSolid($0.kind) && $0.oncomingSpeed == 0 }
                // Landing and follow-beat solids next to the safe lane can anchor bait too (patterns 3, 6 and 7).
                let laterSolids = entities[rowStart...].filter { Self.isSolid($0.kind) && $0.oncomingSpeed == 0 &&
                    $0.z > z + 1 && $0.z <= z + predictedSpeed * 1.2 && abs($0.arrivalLane - routeLane) == 1 }
                // Standard opens each world with four teaching rows: only safe or action lines.
                let teaching = !expert && row < 4
                let roll = nextRandom() % 100
                let line = Self.coinLine(roll: teaching ? roll % 60 : roll, actionable: !(jumpLanes + slideLanes).isEmpty,
                                         solid: !(solids + laterSolids).isEmpty)
                placeCoins(line, z: z, safe: routeLane, speed: predictedSpeed, jumpApex: jumpHeight, jumpLanes: jumpLanes,
                           slideLanes: slideLanes, solids: Array(solids), laterSolids: laterSolids, teaching: teaching,
                           safeOffsets: safeOffsets)
            }
            let milestones = [0.25, 0.51, 0.77]
            if journey.generatedRelics < 3 && local >= stageLength * milestones[journey.generatedRelics] {
                add(.relic, lane: relicLane, z: relicZ, y: relicY, length: 0.6, oncomingSpeed: relicVelocity)
                journey.generatedRelics += 1
            }
            // Jitter is bounded so the late-stage cadence is less predictable without
            // dropping below the physical jump/recovery and lane-change budgets.
            nextPatternDistance += gap + Double(nextRandom() % 5)
        }
    }

    private mutating func addJourneyWaterRow(z: Double, predictedSpeed: Double, local: Double, limit: Double) {
        let row = enhancements.generatedRows
        enhancements.generatedRows += 1
        let previous = challenge.previousWaterGate
        let gateLane = previous == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
        challenge.previousWaterGate = gateLane
        add(.gate, lane: gateLane, z: z, y: 0.9, length: 0.5)
        for other in -1...1 where other != gateLane { add(.buoy, lane: other, z: z, y: 0, length: 1.2) }
        for offset in [-8.0, -4, 0, 4, 8] { add(.coin, lane: gateLane, z: z + offset, y: 0.9, length: 0.3) }
        let absolute = distance + z
        if row % 3 == 1 && absolute + predictedSpeed * 0.6 + 8 < limit {
            add(.waterTraffic, lane: gateLane == 0 ? 1 : -gateLane, z: z + predictedSpeed * 0.5, y: 0, length: 5, oncomingSpeed: 4)
        }
        if row % 3 == 0 && absolute + predictedSpeed * 1.4 < limit {
            add(.waveRamp, lane: gateLane, z: z + predictedSpeed * 0.30, y: 0, length: 5)
            add(.coin, lane: gateLane, z: z + predictedSpeed * 0.75, y: 2.6, length: 0.3)
        }
        // The normal three relic milestones still exist on either fork.
        let milestones = [0.25, 0.51, 0.77]
        if journey.generatedRelics < 3 && local >= stageLength * milestones[journey.generatedRelics] {
            add(.relic, lane: gateLane, z: z, y: 0.9, length: 0.6)
            journey.generatedRelics += 1
        }
    }

    private func journeyEncounterInterval(progress: Double, pattern: Int) -> Double {
        let isRiskyFork = isExpansionActive && branchRoute == .risky && progress >= 0.32 && progress < 0.55
        let tier = isExpansionActive && expeditionCycle > 0 || isRiskyFork ? JourneyDifficultyTier.overdrive : worldStage.difficultyTier(at: progress, revision: routeRevision)
        let base: Double
        switch tier {
        case .warmup: base = 2.65
        case .pressure: base = 2.10
        case .intense: base = 1.65
        case .overdrive: base = 1.38
        }
        let pressure = base - Double(stageIndex) * 0.025 - (expert ? 0.16 : 0)
        // A compound row's second beat still has >=0.60 seconds to react; ice's
        // slower lane commitment gets a larger margin. Low gravity must finish
        // a whole jump before another mandatory jump or full-width slide appears.
        let floor = worldStage == .orbit ? (expert ? 1.95 : 2.13) : worldStage == .cryo ? (expert ? 1.50 : 1.65) : (expert ? 1.25 : 1.40)
        var interval = max(floor, pressure)
        if pattern == 4 { interval = max(interval, (worldStage == .mars ? 1.75 : 1.65) + (expert ? 0 : 0.12)) }
        if [3, 8, 12].contains(pattern) { interval = max(interval, (worldStage == .cryo ? 1.60 : 1.30) + (expert ? 0 : 0.14)) }
        return interval
    }

    enum CoinLine: Hashable { case safe, action, risk, bait }

    /// Coins are an invitation, not a route marker: at most 30% of rows mark the safe lane.
    static func coinLine(roll: UInt64, actionable: Bool, solid: Bool) -> CoinLine {
        switch roll % 100 {
        case 0..<25: return .safe
        case 25..<60: return actionable ? .action : (solid ? .bait : .safe)
        case 60..<85: return actionable ? .risk : (solid ? .bait : .safe)
        default: return solid ? .bait : (actionable ? .risk : .safe)
        }
    }

    private func laneIsClear(_ lane: Int, from: Double, to: Double) -> Bool {
        !entities.contains { e in
            Self.isObstacle(e.kind) && e.arrivalLane == lane && e.z + e.length / 2 > from && e.z - e.length / 2 < to
        }
    }

    /// Lays this row's coins. `safe` is the intended route lane, which may itself need a jump or roll.
    /// `laterSolids` are landing or follow-beat solids after this row that may also anchor a bait line.
    /// `coinLimit` is the furthest z a resume coin may take before the next row could place a collider.
    private mutating func placeCoins(_ line: CoinLine, z: Double, safe: Int, speed: Double, jumpApex: Double,
                                     jumpLanes: [Int], slideLanes: [Int], solids: [TrackEntity], laterSolids: [TrackEntity] = [],
                                     teaching: Bool = false, coinLimit: Double = .infinity,
                                     safeOffsets: [Double] = [-6.0, -3, 0, 3]) {
        let lowLine = [-3.0, -1.5, 0, 1.5, 3]
        func halfLength(_ lane: Int) -> Double {
            entities.filter { Self.isObstacle($0.kind) && $0.arrivalLane == lane && abs($0.z - z) < 1 }.map { $0.length / 2 }.max() ?? 0.5
        }
        // Action and risk lines only use lanes that stay clear after the hazard, so no line leads into a landing solid.
        // Risk coins sit on both sides of the hazard, so the approach side must be clear too. Every stretch keeps
        // 1.3 m past its outermost coin: a coin within 1.2 m of a collider's edge overlaps it at collection.
        let open = (jumpLanes + slideLanes).filter { laneIsClear($0, from: z + halfLength($0) + 0.5, to: z + max(speed * 1.2, halfLength($0) + 10.3)) }
        let openBefore = open.filter { laneIsClear($0, from: z - halfLength($0) - 10.3, to: z - halfLength($0) - 0.1) }
        // Bait ends `reaction` seconds before its solid, and only where no other hazard covers the pre-solid,
        // gap and resume stretches. Behind this row's jump the pre-solid bait is the jump's arc, cut short:
        // the player leaps, then steers in flight.
        let reaction = mode == .odyssey && worldStage == .cryo ? 0.55 : 0.35
        // The resume line starts a lane switch (0.15 s) behind the solid.
        let resume = max(2, speed * 0.15)
        func baitPlan(_ solid: TrackEntity) -> (last: Double, arc: Bool)? {
            let lane = solid.arrivalLane
            guard abs(lane - safe) == 1 else { return nil }
            let hl = solid.length / 2
            let last = solid.z - hl - speed * reaction
            let arc = jumpLanes.contains(lane) && solid.z > z + 1
            // One adjacent switch out and back: the escape lane stays clear from the last bait coin, past the solid's
            // far edge, until the runner has stepped back in behind it (the resume switch), with collision padding.
            // An arc bait's runner is airborne over this row's jump, which also clears the escape lane's jump beside it.
            let escapeFrom = arc ? max(last - 0.35, z + halfLength(safe) + 0.1) : last - 0.35
            guard laneIsClear(safe, from: escapeFrom, to: solid.z + hl + resume + 0.35) else { return nil }
            let before = arc ? z <= last && laneIsClear(lane, from: z + halfLength(lane) + 0.1, to: solid.z - hl - 0.1)
                : laneIsClear(lane, from: last - 7.3, to: last + 1.3) && laneIsClear(lane, from: last + 1.3, to: solid.z - hl - 0.1)
            guard before, laneIsClear(lane, from: solid.z + hl + 0.1, to: solid.z + hl + resume + 7.3) else { return nil }
            return (last, arc)
        }
        var bait: (solid: TrackEntity, last: Double, arc: Bool)? = nil
        for solid in solids + laterSolids where bait == nil {
            if let plan = baitPlan(solid) { bait = (solid, plan.last, plan.arc) }
        }
        // Action and risk lines never use the safe lane: there they would mark the route like a safe line.
        let actionLanes = open.filter { $0 != safe }
        let riskLanes = openBefore.filter { $0 != safe }
        func available(_ candidate: CoinLine) -> Bool {
            switch candidate {
            case .safe: return true
            case .action: return !actionLanes.isEmpty
            case .risk: return !riskLanes.isEmpty
            case .bait: return bait != nil
            }
        }
        // A requested invitation the row cannot hold falls back to another invitation before the safe line.
        // Teaching rows only show safe or action lines.
        let order: [CoinLine] = teaching ? [line == .action ? .action : .safe] : [line] + (line == .safe ? [] : [.action, .risk, .bait])
        let placed = order.first(where: available) ?? .safe
        switch placed {
        case .action:
            let lane = actionLanes[Int(nextRandom() % UInt64(actionLanes.count))]
            if jumpLanes.contains(lane) { addJourneyArc(lane: lane, z: z, apex: jumpApex, speed: speed) }
            else { for offset in lowLine { add(.coin, lane: lane, z: z + offset, y: 0.35, length: 0.3) } }
        case .risk:
            // Ground-height coins around a jump or slide hazard: they do not signal the action.
            let lane = riskLanes[Int(nextRandom() % UInt64(riskLanes.count))]
            let clearance = halfLength(lane) + 3
            for k in 0..<3 {
                add(.coin, lane: lane, z: z - clearance - Double(k) * 3, y: 0.9, length: 0.3)
                add(.coin, lane: lane, z: z + clearance + Double(k) * 3, y: 0.9, length: 0.3)
            }
        case .bait:
            // A greedy line in a solid's lane that ends with time left for one lane switch.
            let (solid, last, arc) = bait!
            let lane = solid.arrivalLane
            let firstCoin = entities.count
            if arc { addJourneyArc(lane: lane, z: z, apex: jumpApex, speed: speed, until: last) }
            else { for k in 0..<3 { add(.coin, lane: lane, z: last - Double(k) * 3, y: 0.9, length: 0.3) } }
            // The audit checks the escape from the last pre-solid coin.
            if let lastCoin = entities[firstCoin...].max(by: { $0.z < $1.z }) { baitEscapes[lastCoin.id] = solid.id }
            // The line resumes behind the solid: staying in lane for it is fatal, stepping out and back is not.
            for k in 0..<3 where solid.z + solid.length / 2 + resume + Double(k) * 3 <= coinLimit {
                add(.coin, lane: lane, z: solid.z + solid.length / 2 + resume + Double(k) * 3, y: 0.9, length: 0.3)
            }
        case .safe:
            if jumpLanes.contains(safe) { addJourneyArc(lane: safe, z: z, apex: jumpApex, speed: speed) }
            else if slideLanes.contains(safe) { for offset in lowLine { add(.coin, lane: safe, z: z + offset, y: 0.35, length: 0.3) } }
            else { for offset in safeOffsets { add(.coin, lane: safe, z: z + offset, y: 0.9, length: 0.3) } }
        }
        placedCoinLines[placed, default: 0] += 1
    }

    /// Coins over a jump; `until` cuts the arc short (a bait arc ends before a landing solid).
    private mutating func addJourneyArc(lane: Int, z: Double, apex: Double, speed: Double, until: Double = .infinity) {
        let extent = min(11, speed * 0.24)
        for fraction in [-1.0, -0.5, 0, 0.5, 1] where z + extent * fraction <= until {
            add(.coin, lane: lane, z: z + extent * fraction, y: apex - abs(fraction) * 0.55, length: 0.3)
        }
    }

    private mutating func extendLegacyJourneyCourse() {
        let stageStart = distance - stageDistance
        let hazardLimit = stageStart + stageLength - 80
        while nextPatternDistance < min(distance + 190, hazardLimit) {
            let at = nextPatternDistance
            let local = at - stageStart
            let z = at - distance
            let row = enhancements.generatedRows
            enhancements.generatedRows += 1
            let candidates = [-1, 0, 1].filter { abs($0 - challenge.previousSafeLane) <= 1 }
            let safe = candidates[Int(nextRandom() % UInt64(candidates.count))]
            challenge.previousSafeLane = safe
            let blocked = [-1, 0, 1].filter { $0 != safe }
            let beat = row % 4
            var required: EntityKind? = nil
            switch worldStage {
            case .harbor: required = beat == 0 ? .barrier : beat == 2 ? .arch : nil
            case .orbit: required = beat % 2 == 0 ? .gap : nil
            case .mars: required = beat == 2 ? .barrier : nil
            case .verdant: required = beat % 2 == 0 ? .root : .laserSweep
            case .cryo: required = beat == 0 || beat == 3 ? .iceCrack : beat == 2 ? .arch : nil
            case .forge: required = beat == 0 || beat == 3 ? .laserSweep : beat == 2 ? .barrier : nil
            }
            var relicLane = safe
            var relicY = 2.3
            var relicZ = z
            var relicVelocity = 0.0
            if let required {
                let length = required == .gap ? 7.0 : required == .iceCrack ? 3.2 : 1.1
                for lane in -1...1 { add(required, lane: lane, z: z, y: 0, length: length) }
                relicY = [.arch, .laserSweep].contains(required) ? 0.7 : required == .gap ? 3.6 : 2.3
                // The vertical coin arc is the route marker: all lanes share a fair
                // jump/slide solution, so lateral dodging alone cannot solve a world.
                for offset in [-7.0, -3.5, 0, 3.5, 7.0] {
                    add(.coin, lane: safe, z: z + offset,
                        y: [.arch, .laserSweep].contains(required) ? 0.7 : relicY - abs(offset) * 0.1, length: 0.3)
                }
            } else if worldStage == .mars && beat == 1 {
                // A rover transfer is a real elevated route with a supported ramp.
                // Meteor markers block the two ground lanes; the roof is safe.
                let roverVelocity = local < stageLength - 120 ? -1.5 : 0.0
                add(.tram, lane: safe, z: z, y: 0, length: 9, oncomingSpeed: roverVelocity)
                add(.ramp, lane: safe, z: z - 9, y: 0, length: 7, oncomingSpeed: roverVelocity)
                for lane in blocked { add(.meteor, lane: lane, z: z, y: 0, length: 2) }
                relicY = Self.tramRoofHeight + 0.9
                relicVelocity = roverVelocity
                for offset in [-3.0, 0, 3] { add(.coin, lane: safe, z: z + offset, y: relicY, length: 0.3, oncomingSpeed: roverVelocity) }
            } else if worldStage == .mars {
                for lane in blocked { add(.meteor, lane: lane, z: z, y: 0, length: 2) }
                for offset in [-8.0, -4, 0, 4] { add(.coin, lane: safe, z: z + offset, y: 0.9, length: 0.3) }
                // Leaving the ground route for this side jump is optional. A grounded
                // player may pass through the meteor lane after the impact goes by.
                relicZ = z + 12
                add(.barrier, lane: safe, z: relicZ, y: 0, length: 1.1)
            } else {
                let primary: EntityKind = worldStage == .forge || worldStage == .harbor ? .tram : .barrier
                let moving = worldStage == .forge
                add(primary, lane: blocked[0], z: z, y: 0, length: primary == .tram ? 9 : 1.1, oncomingSpeed: moving ? 5 : 0)
                add(.arch, lane: blocked[1], z: z, y: 0, length: 1.1)
                relicLane = blocked[0]
                if primary == .tram && !moving {
                    add(.ramp, lane: blocked[0], z: z - 9, y: 0, length: 7)
                    relicY = Self.tramRoofHeight + 0.9
                } else if moving {
                    // The moving crate is a dodge encounter. Its relic sits on the
                    // slide route, leaving the ground lane available for safety.
                    relicLane = blocked[1]; relicY = 0.7
                }
                for offset in [-8.0, -4, 0, 4, 8] { add(.coin, lane: safe, z: z + offset, y: 0.9, length: 0.3) }
            }
            let milestones = [0.22, 0.44, 0.62]
            if journey.generatedRelics < 3 && local >= stageLength * milestones[journey.generatedRelics] {
                add(.relic, lane: relicLane, z: relicZ, y: relicY, length: 0.6, oncomingSpeed: relicVelocity)
                journey.generatedRelics += 1
            }
            // Even the shortest expert interval exceeds a full jump + slide reset.
            // The long orbital arc gets its own cadence, independent of frame rate.
            let gap: Double = worldStage == .orbit ? 46 : worldStage == .cryo ? 42 : 38
            nextPatternDistance += gap + Double(nextRandom() % 4) - (expert ? 2 : 0)
        }
    }

    private mutating func extendWaterCourse() {
        while nextPatternDistance < distance + 210 {
            let z = nextPatternDistance - distance
            let last = challenge.previousWaterGate
            let gateLane = last == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
            challenge.previousWaterGate = gateLane
            add(.gate, lane: gateLane, z: z, y: 0.9, length: 0.5)
            let blocked = [-1, 0, 1].filter { $0 != gateLane }
            add(.buoy, lane: blocked[0], z: z, y: 0, length: 1.2)
            add(.buoy, lane: blocked[1], z: z, y: 0, length: 1.2)
            for offset in [-9.0, -5.0, -1.0, 3.0, 7.0] {
                add(.coin, lane: gateLane, z: z + offset, y: 0.9, length: 0.3)
            }
            // Boats cross the exit of the gate in an off-route lane. Their charge
            // begins locally, so they cannot overtake and block an earlier gate.
            if nextPatternDistance > 120 && nextRandom() % 2 == 0 {
                add(.waterTraffic, lane: blocked[0], z: z + 11, y: 0, length: 5, oncomingSpeed: 4)
            }
            // Wake ramps are optional, but completing a multi-input air combination
            // recharges boost faster than safe gate-only cruising.
            if nextRandom() % 2 == 0 && nextPatternDistance > 80 {
                add(.waveRamp, lane: gateLane, z: z + 10, y: 0, length: 5)
                for offset in [18.0, 23.0, 28.0] {
                    add(.coin, lane: gateLane, z: z + offset, y: 2.7, length: 0.3)
                }
            }
            nextPatternDistance += (expert ? 37 : 43) + Double(nextRandom() % 5)
        }
    }

    private mutating func extendAirCourse() {
        let remaining = activePowerUps[.jetpack] ?? 0
        guard remaining > 1.6 else { return }
        let horizon = min(140.0, speed * max(0, remaining - 1.5))
        while challenge.nextAirPattern < distance + horizon {
            let z = challenge.nextAirPattern - distance
            if z > 20 {
                let candidates = [-1, 0, 1].filter { abs($0 - challenge.previousAirLane) <= 1 }
                let safe = candidates[Int(nextRandom() % UInt64(candidates.count))]
                challenge.previousAirLane = safe
                add(.airRing, lane: safe, z: z, y: 7.1, length: 0.5)
                let hazardLane = [-1, 0, 1].filter { $0 != safe }[Int(nextRandom() % 2)]
                add(.airHazard, lane: hazardLane, z: z, y: 6.2, length: 2)
                if expert {
                    let other = [-1, 0, 1].first { $0 != safe && $0 != hazardLane }!
                    add(.airHazard, lane: other, z: z, y: 6.2, length: 2)
                }
            }
            challenge.nextAirPattern += expert ? 28 : 34
        }
    }

    private mutating func rewardSkill(points: Double, message: String) {
        challenge.combo += 1
        challenge.bestCombo = max(challenge.bestCombo, challenge.combo)
        challenge.comboTime = 5
        let chainBonus = 1 + Double(min(challenge.combo - 1, 12)) * 0.12
        preciseScore += points * chainBonus * Double(multiplier)
        showEvent(message)
    }

    private mutating func showEvent(_ message: String) {
        challenge.eventText = message
        challenge.eventTime = 2.0
    }

    /// An approaching tram can overtake earlier patterns. Its lane must already be occupied
    /// in every earlier two-obstacle row, so it never fills that row's only clear lane.
    private func oncomingLaneIsFair(_ lane: Int, aheadOf z: Double) -> Bool {
        guard !entities.contains(where: { $0.oncomingSpeed > 0 && $0.z + $0.length / 2 > -1 }) else {
            return false
        }
        // A tram at z closing at v (8...12) meets a static item as the runner reaches it, near z·s/(s+v).
        // No ground coin, key or power-up may sit in that window: the tram would sweep through it.
        let s = max(1, speed)
        let sweep = (z * s / (s + 12) - 10)...(z * s / (s + 8) + 10)
        guard !entities.contains(where: { $0.lane == lane && sweep.contains($0.z) &&
            (($0.kind == .coin && $0.y < 5) || $0.kind == .key || PowerUp(rawValue: $0.kind.rawValue) != nil) }) else {
            return false
        }
        var rows: [Int: Set<Int>] = [:]
        for entity in entities where Self.isObstacle(entity.kind)
            && entity.oncomingSpeed == 0 && entity.z < z && entity.z + entity.length / 2 > -1 {
            rows[Int((entity.z * 1_000).rounded()), default: []].insert(entity.arrivalLane)
        }
        return rows.values.allSatisfy { $0.count < 2 || $0.contains(lane) }
    }

    private mutating func activate(_ power: PowerUp, duration: Double? = nil) {
        let defaults: [PowerUp: Double] = [.magnet: 12, .jetpack: 10, .sneakers: 14, .multiplier: 16]
        let requested = duration ?? powerDurations[power] ?? defaults[power] ?? 10
        activePowerUps[power] = max(1, requested.isFinite ? requested : 10)
        if power == .multiplier { multiplier = baseMultiplier * 2 }
        if power == .jetpack {
            grounded = false
            verticalVelocity = 0
            challenge.previousAirLane = lane
            challenge.nextAirPattern = distance + max(38, speed * 2.2)
            showEvent("FLIGHT ROUTE · DODGE THE DRONES")
            // The trail leads into the flight route and stops before the first drone row; air rings mark the way after that.
            let firstDroneRow = max(38, speed * 2.2)
            for index in 0..<(mode == .odyssey ? 0 : 30) where 13 + Double(index) * 3 < firstDroneRow - 3 {
                let trailLane = ((index / 6) % 3) - 1
                add(.coin, lane: trailLane, z: 13 + Double(index) * 3,
                    y: 7.1, length: 0.3)
            }
        }
    }

    private mutating func add(_ kind: EntityKind, lane: Int, z: Double, y: Double, length: Double,
                              oncomingSpeed: Double = 0, targetLane: Int? = nil, motionStart: Double = 0,
                              motionLength: Double = 0, cyclePhase: Double = -1, activeFrom: Double = .infinity) {
        entities.append(TrackEntity(id: nextID, kind: kind, lane: lane, z: z, y: y, length: length,
                                    oncomingSpeed: oncomingSpeed, targetLane: targetLane, motionStart: motionStart,
                                    motionLength: motionLength, cyclePhase: cyclePhase, activeFrom: activeFrom))
        nextID += 1
    }

    /// Xorshift64*: state belongs to the simulation so replay is reproducible.
    private mutating func nextRandom() -> UInt64 {
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        return randomState &* 2_685_821_657_736_338_717
    }
    private static func isObstacle(_ kind: EntityKind) -> Bool {
        [.barrier, .arch, .tram, .buoy, .airHazard, .gap, .meteor, .root, .iceCrack, .laserSweep, .waterTraffic, .wall, .stack].contains(kind)
    }
    static let wallTop = 3.8
    /// Hazards that no normal jump or roll clears.
    private static func isSolid(_ kind: EntityKind) -> Bool { [.tram, .meteor, .wall, .stack].contains(kind) }
}


extension RunnerSimulation {
    private enum CodingKeys: String, CodingKey {
        case expansion, enhancements, phase, lane, lateral, height, isRolling, distance, speed, coins, keys, score, multiplier, boardTime, invulnerableTime, activePowerUps, entities, elapsed, jumps, rolls, dodges, boardsUsed, availableBoards, crashReason, challenge, journey, randomState, nextID, nextPatternDistance, verticalVelocity, rollTime, grounded, baseMultiplier, powerDurations, preciseScore, processedObstacles, generateTrack
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        phase = try values.decodeIfPresent(RunPhase.self, forKey: .phase) ?? phase
        lane = try values.decodeIfPresent(Int.self, forKey: .lane) ?? lane
        lateral = try values.decodeIfPresent(Double.self, forKey: .lateral) ?? lateral
        height = try values.decodeIfPresent(Double.self, forKey: .height) ?? height
        isRolling = try values.decodeIfPresent(Bool.self, forKey: .isRolling) ?? isRolling
        distance = try values.decodeIfPresent(Double.self, forKey: .distance) ?? distance
        speed = try values.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        coins = try values.decodeIfPresent(Int.self, forKey: .coins) ?? coins
        keys = try values.decodeIfPresent(Int.self, forKey: .keys) ?? keys
        score = try values.decodeIfPresent(Int.self, forKey: .score) ?? score
        multiplier = try values.decodeIfPresent(Int.self, forKey: .multiplier) ?? multiplier
        boardTime = try values.decodeIfPresent(Double.self, forKey: .boardTime) ?? boardTime
        invulnerableTime = try values.decodeIfPresent(Double.self, forKey: .invulnerableTime) ?? invulnerableTime
        activePowerUps = try values.decodeIfPresent([PowerUp: Double].self, forKey: .activePowerUps) ?? activePowerUps
        entities = try values.decodeIfPresent([TrackEntity].self, forKey: .entities) ?? entities
        elapsed = try values.decodeIfPresent(Double.self, forKey: .elapsed) ?? elapsed
        jumps = try values.decodeIfPresent(Int.self, forKey: .jumps) ?? jumps
        rolls = try values.decodeIfPresent(Int.self, forKey: .rolls) ?? rolls
        dodges = try values.decodeIfPresent(Int.self, forKey: .dodges) ?? dodges
        boardsUsed = try values.decodeIfPresent(Int.self, forKey: .boardsUsed) ?? boardsUsed
        availableBoards = try values.decodeIfPresent(Int.self, forKey: .availableBoards) ?? availableBoards
        crashReason = try values.decodeIfPresent(String.self, forKey: .crashReason) ?? crashReason
        challenge = try values.decodeIfPresent(RunChallenge.self, forKey: .challenge) ?? challenge
        journey = try values.decodeIfPresent(PortalJourney.self, forKey: .journey) ?? journey
        if let savedEnhancements = try values.decodeIfPresent(RunEnhancements.self, forKey: .enhancements) {
            enhancements = savedEnhancements
        } else {
            // An old checkpoint has no per-stage skill history. Begin new mastery
            // accounting here instead of counting relics/score earned in earlier worlds.
            enhancements.stageStartRelics = journey.artifactsCollected
            enhancements.stageStartScore = score
            enhancements.startWorldIndex = stageIndex
        }
        expansion = try values.decodeIfPresent(ExpeditionExpansion.self, forKey: .expansion) ?? ExpeditionExpansion()
        randomState = try values.decodeIfPresent(UInt64.self, forKey: .randomState) ?? randomState
        nextID = try values.decodeIfPresent(Int.self, forKey: .nextID) ?? nextID
        nextPatternDistance = try values.decodeIfPresent(Double.self, forKey: .nextPatternDistance) ?? nextPatternDistance
        verticalVelocity = try values.decodeIfPresent(Double.self, forKey: .verticalVelocity) ?? verticalVelocity
        rollTime = try values.decodeIfPresent(Double.self, forKey: .rollTime) ?? rollTime
        grounded = try values.decodeIfPresent(Bool.self, forKey: .grounded) ?? grounded
        baseMultiplier = try values.decodeIfPresent(Int.self, forKey: .baseMultiplier) ?? baseMultiplier
        powerDurations = try values.decodeIfPresent([PowerUp: Double].self, forKey: .powerDurations) ?? powerDurations
        preciseScore = try values.decodeIfPresent(Double.self, forKey: .preciseScore) ?? preciseScore
        processedObstacles = try values.decodeIfPresent(Set<Int>.self, forKey: .processedObstacles) ?? processedObstacles
        generateTrack = try values.decodeIfPresent(Bool.self, forKey: .generateTrack) ?? generateTrack
    }
}
