import Foundation

/// Expedition options share the runner's controls and course; practice never settles
/// currency or competitive records, while Endless repeats with a bounded speed ceiling.
enum ExpeditionStyle: String, CaseIterable, Codable {
    case campaign, endless, practice
    var title: String { self == .campaign ? "Six-world expedition" : self == .endless ? "Endless Odyssey" : "Finale practice" }
    var detail: String {
        switch self {
        case .campaign: return "Connect six worlds, choose routes and build your artifacts."
        case .endless: return "Loop through altered worlds. Momentum carries over; pressure keeps rising."
        case .practice: return "Rehearse a world's final 30 seconds. No currency or record rewards."
        }
    }
}

enum BranchRoute: String, CaseIterable, Codable, Hashable {
    case undecided, safe, risky
    func title(in world: WorldStage) -> String {
        switch (self, world) {
        case (.undecided, _): return "Choose your route"
        case (.safe, .harbor): return "Tidal channel"
        case (.risky, .harbor): return "Cargo rooftops"
        case (.safe, .mars): return "Crater floor"
        case (.risky, .mars): return "Rover convoy"
        case (.safe, .orbit): return "Service causeway"
        case (.risky, .orbit): return "Outer ring"
        case (.safe, .verdant): return "Forest floor"
        case (.risky, .verdant): return "Canopy bridge"
        case (.safe, .cryo): return "Glacier shelf"
        case (.risky, .cryo): return "Crystal ridge"
        case (.safe, .forge): return "Service conduit"
        case (.risky, .forge): return "Reactor gantry"
        }
    }
    func detail(in world: WorldStage) -> String {
        if self == .undecided { return "Steer left or right before the fork." }
        if self == .safe && world == .harbor { return "Jet Ski gates, wakes and tricks. Down brakes; B boosts." }
        return self == .safe ? "Fewer compound hazards. A lower route with room to recover." : "Elevated action route. Denser combinations and double coin value."
    }
}

enum ExpeditionPerk: String, CaseIterable, Codable, Hashable {
    case longPhase, dashDividend, relicCapacitor
    var title: String {
        switch self { case .longPhase: return "Extended Phase"; case .dashDividend: return "Dash Dividend"; case .relicCapacitor: return "Relic Capacitor" }
    }
    var detail: String {
        switch self {
        case .longPhase: return "Phase lasts 1.8s instead of 1.2s, but costs 2 charges."
        case .dashDividend: return "Air Dash lasts 0.8s and clean escapes earn +75, but costs 2 charges."
        case .relicCapacitor: return "Store 5 charges instead of 3, but recharge once per 2 relics."
        }
    }
    var symbol: String { self == .longPhase ? "sparkles" : self == .dashDividend ? "wind" : "bolt.fill" }
}

struct ExpeditionDecision: Codable, Equatable, Hashable {
    let world: Int
    var route: BranchRoute
    var perk: ExpeditionPerk?
    init(world: Int, route: BranchRoute = .undecided, perk: ExpeditionPerk? = nil) {
        self.world = world; self.route = route; self.perk = perk
    }
}

struct ExpeditionObjectiveStatus: Identifiable, Equatable {
    let id: String
    let title: String
    let progress: Int
    let target: Int
    var completed: Bool { progress >= target }
}

/// Defaulted independently so a v6 checkpoint keeps its exact live geometry until
/// the next portal. Choices and replay scripts are persisted with simulation state.
struct ExpeditionExpansion: Codable {
    var style: ExpeditionStyle = .campaign
    var cycle = 0
    var route: BranchRoute = .undecided
    var selectedPerks: [ExpeditionPerk] = []
    var stagePerk: ExpeditionPerk? = nil
    var decisions: [ExpeditionDecision] = []
    var replayPlan: [ExpeditionDecision]? = nil
    var usedProtection = false
    var finaleRows = 0
    var finaleSkillActions = 0
    var finaleHits = 0
    var completedObjectives = 0
    var totalFinalesCleared = 0
    var roverTransfers = 0
    var traversedRoofs: Set<Int> = []
    var stageCleanLandings = 0
    var capacitorRelics = 0
    var dashRewardTime = 0.0
    var wasWater = false
}

extension WorldStage {
    var finaleTitle: String {
        switch self {
        case .harbor: return "HARBOR LOCKDOWN"
        case .orbit: return "COLLAPSING CAUSEWAY"
        case .mars: return "ROVER CONVOY ESCAPE"
        case .verdant: return "THE LIVING GAUNTLET"
        case .cryo: return "GLACIER FRACTURE"
        case .forge: return "SENTINEL SHOWDOWN"
        }
    }
    /// Deliberately authored action phrases, repeated with alternating safe lanes.
    /// The same jump/landing budgets as the main course keep every phrase solvable.
    var finalePatterns: [Int] {
        switch self {
        case .harbor: return [5, 0, 1, 4, 3, 0, 1, 5]
        case .orbit: return [0, 6, 3, 0, 2, 6, 3]
        case .mars: return [4, 3, 4, 2, 6, 4, 3]
        case .verdant: return [0, 1, 7, 6, 1, 3, 0]
        case .cryo: return [6, 3, 0, 1, 6, 3, 2]
        case .forge: return [5, 1, 6, 3, 5, 0, 1]
        }
    }
}
