import Foundation

/// Ordered destinations in a finite expedition. Physics and scenery share this vocabulary.
enum WorldStage: String, CaseIterable, Codable, Hashable {
    case harbor, orbit, mars, verdant, cryo, forge

    static let ordered = Self.allCases
    var title: String {
        switch self {
        case .harbor: return "The Departure"
        case .orbit: return "Orbital Causeway"
        case .mars: return "Mars Outpost"
        case .verdant: return "Verdant Nexus"
        case .cryo: return "Cryo Cathedral"
        case .forge: return "The Star Forge"
        }
    }
    var subtitle: String {
        switch self {
        case .harbor: return "Cargo jumps · low beam slides"
        case .orbit: return "Broken decks · low-gravity leaps"
        case .mars: return "Meteor fields · rover transfers"
        case .verdant: return "Rising roots · vine laser combos"
        case .cryo: return "Fracturing ice · steer before landing"
        case .forge: return "Sentinel sweeps · charging cargo"
        }
    }
    var artifactName: String {
        switch self {
        case .harbor: return "Tidal Compass"
        case .orbit: return "Stellar Gyroscope"
        case .mars: return "Martian Seed"
        case .verdant: return "Living Prism"
        case .cryo: return "Frozen Echo"
        case .forge: return "Star Heart"
        }
    }
    var length: Double {
        switch self {
        case .harbor: return 2_200
        case .orbit: return 3_100
        case .mars: return 3_500
        case .verdant: return 3_800
        case .cryo: return 4_100
        case .forge: return 4_400
        }
    }
    func length(forRevision revision: Int) -> Double {
        if revision < 5 { return legacyLength }
        guard revision == 5 else { return length }
        switch self {
        case .harbor: return 2_200
        case .orbit: return 2_500
        case .mars: return 2_750
        case .verdant: return 2_900
        case .cryo: return 3_000
        case .forge: return 3_300
        }
    }
    var accentHex: String {
        switch self {
        case .harbor: return "FFAB66"
        case .orbit: return "7DDCFF"
        case .mars: return "FF7255"
        case .verdant: return "A8FF83"
        case .cryo: return "9BDFFF"
        case .forge: return "FFC35C"
        }
    }
    var gravity: Double { self == .orbit ? 9 : self == .mars ? 14 : 22 }
    var jumpVelocity: Double { self == .orbit ? 7.8 : self == .mars ? 8.0 : 8.5 }
    var cruiseSpeed: Double {
        switch self {
        case .harbor: return 17
        case .orbit: return 29
        case .mars: return 33
        case .verdant: return 36
        case .cryo: return 39
        case .forge: return 42
        }
    }
    var peakSpeed: Double {
        switch self {
        case .harbor: return 29
        case .orbit: return 33
        case .mars: return 36
        case .verdant: return 39
        case .cryo: return 42
        case .forge: return 45
        }
    }
    /// Distance-based acceleration makes checkpoint resumes and seeded routes identical.
    /// Each destination inherits the previous world's peak; a portal never resets pace.
    func speed(at progress: Double, expert: Bool, revision: Int = PortalJourney.currentRevision) -> Double {
        if revision < 5 { return legacySpeed + (expert ? 2 : 0) }
        let start: Double
        let finish: Double
        if revision == 5 {
            let index = Self.ordered.firstIndex(of: self)!
            start = [17.0, 19, 20, 21, 22, 23][index] + (expert ? 3 : 0)
            finish = [29.0, 32, 34, 35, 36, 38][index] + (expert ? 6 : 0)
        } else {
            start = cruiseSpeed + (expert ? (self == .harbor ? 3 : 6) : 0)
            finish = peakSpeed + (expert ? 6 : 0)
        }
        return start + (finish - start) * min(1, max(0, progress))
    }
    func portalClearance(expert: Bool, revision: Int = PortalJourney.currentRevision) -> Double {
        if revision < 5 { return 60 }
        // More than three seconds to recover from the final encounter and read the gate.
        return max(110, speed(at: 1, expert: expert, revision: revision) * 3.6)
    }
    /// Later destinations skip the introductory encounter pools. Their clean landing
    /// gives time to read the environment without reducing the expedition's speed.
    func difficultyTier(at progress: Double, revision: Int = PortalJourney.currentRevision) -> JourneyDifficultyTier {
        let local = JourneyDifficultyTier.at(progress)
        guard revision >= 6 else { return local }
        let floor: JourneyDifficultyTier
        switch self {
        case .harbor: floor = .warmup
        case .orbit, .mars: floor = .pressure
        case .verdant, .cryo: floor = .intense
        case .forge: floor = .overdrive
        }
        return local.rawValue >= floor.rawValue ? local : floor
    }
    var legacyLength: Double {
        switch self {
        case .harbor: return 360
        case .orbit: return 440
        case .mars: return 480
        case .verdant: return 460
        case .cryo: return 480
        case .forge: return 520
        }
    }
    var legacySpeed: Double {
        switch self {
        case .harbor: return 15
        case .orbit: return 16
        case .mars, .verdant: return 17
        case .cryo: return 16
        case .forge: return 18
        }
    }

}

/// Kept separate from challenge data so old saves decode without new required keys.
struct PortalJourney: Codable {
    static let currentRevision = 7
    var routeRevision = Self.currentRevision
    var stageIndex = 0
    var stageDistance = 0.0
    var transitionTime: Double? = nil
    var stagesCleared = 0
    var artifactsCollected = 0
    var collectedArtifactWorlds: Set<WorldStage> = []
    var collectedRelicIDs: Set<Int> = []
    var generatedRelics = 0
    var complete = false
}

/// Saved v4/v5 stages finish with their original speed, geometry, and length. Their
/// next portal enters the current route, avoiding mid-jump changes to saved hazards.
extension PortalJourney {
    private enum CodingKeys: String, CodingKey {
        case routeRevision, stageIndex, stageDistance, transitionTime, stagesCleared,
             artifactsCollected, collectedArtifactWorlds, collectedRelicIDs, generatedRelics, complete
    }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        routeRevision = try values.decodeIfPresent(Int.self, forKey: .routeRevision) ?? 4
        stageIndex = try values.decodeIfPresent(Int.self, forKey: .stageIndex) ?? 0
        stageDistance = try values.decodeIfPresent(Double.self, forKey: .stageDistance) ?? 0
        transitionTime = try values.decodeIfPresent(Double.self, forKey: .transitionTime)
        stagesCleared = try values.decodeIfPresent(Int.self, forKey: .stagesCleared) ?? 0
        artifactsCollected = try values.decodeIfPresent(Int.self, forKey: .artifactsCollected) ?? 0
        collectedArtifactWorlds = try values.decodeIfPresent(Set<WorldStage>.self, forKey: .collectedArtifactWorlds) ?? []
        collectedRelicIDs = try values.decodeIfPresent(Set<Int>.self, forKey: .collectedRelicIDs) ?? []
        generatedRelics = try values.decodeIfPresent(Int.self, forKey: .generatedRelics) ?? 0
        complete = try values.decodeIfPresent(Bool.self, forKey: .complete) ?? false
    }
}

enum JourneyDifficultyTier: Int, CaseIterable {
    case warmup, pressure, intense, overdrive
    var title: String {
        switch self {
        case .warmup: return "Warm-up"
        case .pressure: return "Pressure"
        case .intense: return "Intense"
        case .overdrive: return "Overdrive"
        }
    }
    static func at(_ progress: Double) -> Self {
        progress < 0.20 ? .warmup : progress < 0.45 ? .pressure : progress < 0.72 ? .intense : .overdrive
    }
    var startProgress: Double {
        switch self { case .warmup: return 0; case .pressure: return 0.20; case .intense: return 0.45; case .overdrive: return 0.72 }
    }
    var endProgress: Double {
        switch self { case .warmup: return 0.20; case .pressure: return 0.45; case .intense: return 0.72; case .overdrive: return 1 }
    }
}

/// Visual quality is shared with preferences without importing a rendering framework.
enum RenderQuality: String, CaseIterable, Codable {
    case automatic, performance, balanced, ultra
    var title: String { rawValue.capitalized }
}

enum ArtifactAbility: String, CaseIterable, Codable {
    case airDash, phaseStep, shield
    var title: String {
        switch self { case .airDash: return "Air Dash"; case .phaseStep: return "Phase Step"; case .shield: return "Aegis Shield" }
    }
    var detail: String {
        switch self {
        case .airDash: return "Leap forward with a burst of speed. Clear gaps, but avoid overhead beams."
        case .phaseStep: return "Phase through hazards for 1.2 seconds. Timing matters."
        case .shield: return "Arm a shield that absorbs one impact. It cannot earn a clean-stage medal."
        }
    }
    var symbol: String {
        switch self { case .airDash: return "wind"; case .phaseStep: return "sparkles"; case .shield: return "shield.lefthalf.filled" }
    }
}

enum WorldMedal: Int, CaseIterable, Codable, Comparable {
    case bronze = 1, silver = 2, gold = 3
    var title: String { self == .gold ? "Gold" : self == .silver ? "Silver" : "Bronze" }
    static func < (lhs: WorldMedal, rhs: WorldMedal) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct WorldStageResult: Codable, Equatable {
    var routeRevision = PortalJourney.currentRevision
    let stage: WorldStage
    let medal: WorldMedal
    let score: Int
    let relics: Int
    let hits: Int
    let elapsed: Double
    let precisionPortal: Bool
    let skillActions: Int
    var usedProtection = false
    var branchRoute: BranchRoute = .undecided
    var finaleCleared = false
    var perk: ExpeditionPerk? = nil
    var roverTransfers = 0
    var objectivesCompleted = 0
}

extension WorldStageResult {
    private enum CodingKeys: String, CodingKey {
        case routeRevision, stage, medal, score, relics, hits, elapsed, precisionPortal, skillActions, usedProtection, branchRoute, finaleCleared, perk, roverTransfers, objectivesCompleted
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        routeRevision = try values.decodeIfPresent(Int.self, forKey: .routeRevision) ?? 4
        stage = try values.decode(WorldStage.self, forKey: .stage)
        medal = try values.decode(WorldMedal.self, forKey: .medal)
        score = try values.decode(Int.self, forKey: .score)
        relics = try values.decode(Int.self, forKey: .relics)
        hits = try values.decode(Int.self, forKey: .hits)
        elapsed = try values.decode(Double.self, forKey: .elapsed)
        precisionPortal = try values.decode(Bool.self, forKey: .precisionPortal)
        skillActions = try values.decode(Int.self, forKey: .skillActions)
        usedProtection = try values.decodeIfPresent(Bool.self, forKey: .usedProtection) ?? false
        branchRoute = try values.decodeIfPresent(BranchRoute.self, forKey: .branchRoute) ?? .undecided
        finaleCleared = try values.decodeIfPresent(Bool.self, forKey: .finaleCleared) ?? false
        perk = try values.decodeIfPresent(ExpeditionPerk.self, forKey: .perk)
        roverTransfers = try values.decodeIfPresent(Int.self, forKey: .roverTransfers) ?? 0
        objectivesCompleted = try values.decodeIfPresent(Int.self, forKey: .objectivesCompleted) ?? 0
    }
}

/// A versioned, separately defaulted payload keeps all v1-v3 checkpoints readable.
struct RunEnhancements: Codable {
    var portalAssist = true
    var dailyID: String? = nil
    var runSeed: UInt64 = 0xC0A5711E
    var startWorldIndex = 0
    var selectedAbility: ArtifactAbility? = nil
    var abilityCharges = 0
    var activeAbility: ArtifactAbility? = nil
    var abilityTime = 0.0
    var shieldArmed = false
    var stageResults: [WorldStageResult] = []
    var stageElapsed = 0.0
    var stageStartScore = 0
    var stageStartRelics = 0
    var stageHits = 0
    var stageSkillActions = 0
    var precisionPortal = false
    var generatedRows = 0
    var portalJumpTime = 0.0
    var portalEntryHeight = 0.0
    var jumpBuffer = 0.0
    var landingImpact = 0.0
    var lateralVelocity = 0.0
    var waterCurrent = 0.0
    var waterSteeringTarget: Double? = nil
    var trickActions: Set<String> = []
    var trickChain = 0
    var trickPendingPoints = 0.0
    var trickCooldown = 0.0
    var airTime = 0.0
    var cleanLandings = 0
}
