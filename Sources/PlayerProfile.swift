import Foundation

struct Mission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let progress: Int
    let target: Int
    let reward: Int

    var complete: Bool { progress >= target }
}

struct SkillChallenge: Identifiable {
    let id: String
    let title: String
    let detail: String
    let progress: Int
    let target: Int
    let reward: Int
    let claimed: Bool
    var complete: Bool { progress >= target }
}

struct ShopCharacter: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let cost: Int
}

struct ShopBoard: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let cost: Int
}

enum GameCatalog {
    static let characters: [ShopCharacter] = [
        .init(id: "milo", name: "Milo", subtitle: "The coastline is his playground.", cost: 0),
        .init(id: "sana", name: "Sana", subtitle: "Chasing sunshine, finding shortcuts.", cost: 750),
        .init(id: "rio", name: "Rio", subtitle: "A little rhythm. A lot of speed.", cost: 1_500)
    ]

    static let boards: [ShopBoard] = [
        .init(id: "tideline", name: "Tideline", subtitle: "Classic sea-blue cruising.", cost: 0),
        .init(id: "sunset", name: "Sunset", subtitle: "Made for the golden hour.", cost: 500),
        .init(id: "mint", name: "Mint", subtitle: "Fresh air. Fresh lines.", cost: 900)
    ]

    static func name(forPower power: PowerUp) -> String {
        switch power {
        case .magnet: return "Coin magnet"
        case .jetpack: return "Jetpack"
        case .sneakers: return "Super sneakers"
        case .multiplier: return "Score boost"
        }
    }
}

struct ArchivedWorldRecords: Codable {
    var times: [String: Double] = [:]
    var scores: [String: Int] = [:]
}

struct PlayerProfile: Codable {
    static let maximumUpgradeLevel = 5

    var coins: Int = 0
    var keys: Int = 3
    var boards: Int = 3
    var bestScore: Int = 0
    var totalDistance: Double = 0
    var totalCoins: Int = 0
    var totalRuns: Int = 0
    var totalJumps: Int = 0
    var totalRolls: Int = 0
    var selectedCharacter: String = "milo"
    var selectedBoard: String = "tideline"
    var unlockedCharacters: [String] = ["milo"]
    var unlockedBoards: [String] = ["tideline"]
    var upgradeLevels: [String: Int] = [:]
    var missionTier: Int = 0
    var claimedMissionIDs: [String] = []
    var lastDailyClaim: String = ""
    var dailyStreak: Int = 0
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var tutorialCompleted: Bool = false
    var recentScores: [Int] = []
    var dailyChallengeDate: String = ""
    var dailyChallengeBest: Int = 0
    var selectedMode: RunMode = .odyssey
    var selectedExpert: Bool = false
    var selectedExpeditionStyle: ExpeditionStyle = .campaign
    var modeRecords: [String: Int] = [:]
    var bestCombo: Int = 0
    var totalNearMisses: Int = 0
    var totalGatesCleared: Int = 0

    var highestUnlockedWorld: Int = 0
    var selectedWorld: Int = 0
    var collectedRelicWorlds: Set<WorldStage> = []
    var completedExpeditions: Int = 0
    var worldBestDistances: [String: Double] = [:]

    // Per-world records survive crashes and can only improve.
    var worldMedals: [String: Int] = [:]
    var worldBestTimes: [String: Double] = [:]
    var worldBestScores: [String: Int] = [:]
    var worldRecordRevision = PortalJourney.currentRevision
    var legacyWorldBestTimes: [String: Double] = [:]
    var legacyWorldBestScores: [String: Int] = [:]
    var archivedWorldRecords: [String: ArchivedWorldRecords] = [:]
    var selectedArtifact: ArtifactAbility = .shield
    var graphicsQuality: RenderQuality = .automatic
    var reducedMotion = false
    var highContrastCues = false
    var portalAssist: Bool = true
    var swipeSensitivity: Double = 1
    var ghostEnabled: Bool = true
    var personalGhosts: [GhostReplay] = []
    var dailyOdysseyDate: String = ""
    var dailyOdysseyBest: Int = 0
    var endlessWorldBestTimes: [String: Double] = [:]
    var endlessWorldBestScores: [String: Int] = [:]
    private(set) var skillRiskyWorlds: Set<WorldStage> = []
    private(set) var skillFinaleWorlds: Set<WorldStage> = []
    private(set) var skillShieldlessOrbit = false
    private(set) var skillRoverTransfers = 0
    private(set) var skillObjectiveBest = 0
    private(set) var claimedSkillChallengeIDs: Set<String> = []

    init() {}

    var masteryCount: Int { worldMedals.values.reduce(0) { $0 + min(3, max(0, $1)) } }
    func medal(for stage: WorldStage) -> WorldMedal? { WorldMedal(rawValue: worldMedals[stage.rawValue] ?? 0) }

    mutating func recordStage(_ result: WorldStageResult, expeditionStyle: ExpeditionStyle = .campaign) {
        guard expeditionStyle != .practice else { return }
        let key = result.stage.rawValue
        worldMedals[key] = max(worldMedals[key] ?? 0, result.medal.rawValue)
        recordSkillProgress(result)
        if expeditionStyle == .endless {
            endlessWorldBestScores[key] = max(endlessWorldBestScores[key] ?? 0, min(Self.counterLimit, max(0, result.score)))
            if result.elapsed.isFinite && result.elapsed > 0 {
                endlessWorldBestTimes[key] = min(endlessWorldBestTimes[key] ?? .greatestFiniteMagnitude, min(86_400, result.elapsed))
            }
            recordWorld(result.stage, distance: result.stage.length(forRevision: result.routeRevision))
            return
        }
        if result.routeRevision < PortalJourney.currentRevision {
            archiveRecords(revision: result.routeRevision,
                           times: result.elapsed.isFinite && result.elapsed > 0 ? [key: min(86_400, result.elapsed)] : [:],
                           scores: [key: min(Self.counterLimit, max(0, result.score))])
            recordWorld(result.stage, distance: result.stage.length(forRevision: result.routeRevision))
            return
        }
        worldBestScores[key] = max(worldBestScores[key] ?? 0, min(Self.counterLimit, max(0, result.score)))
        if result.elapsed.isFinite && result.elapsed > 0 {
            worldBestTimes[key] = min(worldBestTimes[key] ?? Double.greatestFiniteMagnitude, min(86_400, result.elapsed))
        }
        recordWorld(result.stage, distance: result.stage.length)
    }

    private mutating func archiveRecords(revision: Int, times: [String: Double], scores: [String: Int]) {
        if revision < 5 {
            legacyWorldBestTimes.merge(times, uniquingKeysWith: min)
            legacyWorldBestScores.merge(scores, uniquingKeysWith: max)
        } else {
            let key = String(revision)
            var records = archivedWorldRecords[key] ?? ArchivedWorldRecords()
            records.times.merge(times, uniquingKeysWith: min)
            records.scores.merge(scores, uniquingKeysWith: max)
            archivedWorldRecords[key] = records
        }
    }

    func matchingGhost(for course: GhostCourseKey) -> GhostReplay? {
        guard course.isValid else { return nil }
        return personalGhosts.first { $0.course == course }
    }

    func preferredGhost(forMode mode: RunMode, expert: Bool, startWorld: Int, expeditionStyle: ExpeditionStyle = .campaign) -> GhostReplay? {
        personalGhosts.filter { $0.course.mode == mode && $0.course.expert == expert && $0.course.startWorld == startWorld && $0.course.expeditionStyle == expeditionStyle && $0.course.isValid }
            .sorted { $0.recordedAt > $1.recordedAt }.first
    }

    mutating func recordGhost(_ replay: GhostReplay) {
        guard let safe = replay.sanitized() else { return }
        if let index = personalGhosts.firstIndex(where: { $0.course == safe.course }) {
            guard safe.beats(personalGhosts[index]) else { return }
            personalGhosts[index] = safe
        } else { personalGhosts.append(safe) }
        personalGhosts = Array(personalGhosts.sorted { $0.recordedAt > $1.recordedAt }.prefix(8))
    }

    func dailyOdysseyScore(now: Date = Date()) -> Int {
        dailyOdysseyDate == Self.dayKey(now) ? dailyOdysseyBest : 0
    }

    mutating func recordDailyOdyssey(score: Int, day: String) {
        guard !day.isEmpty, Self.validDayKey(day), day >= dailyOdysseyDate else { return }
        if day != dailyOdysseyDate { dailyOdysseyDate = day; dailyOdysseyBest = 0 }
        dailyOdysseyBest = max(dailyOdysseyBest, min(Self.counterLimit, max(0, score)))
    }

    /// Monotonic exploration progress is safe to save before a run is settled.
    /// Coins, inventory, run counts and expedition wins are only settled by recordRun.
    mutating func syncJourney(_ run: RunnerSimulation) {
        guard run.mode == .odyssey && !run.isPractice else { return }
        highestUnlockedWorld = max(highestUnlockedWorld, min(WorldStage.allCases.count - 1, max(0, run.stageIndex)))
        collectedRelicWorlds.formUnion(run.collectedArtifactWorlds)
        for result in run.stageResults { recordStage(result, expeditionStyle: run.expeditionStyle) }
        recordWorld(run.worldStage, distance: run.stageDistance)
    }

    mutating func recordWorld(_ stage: WorldStage, distance: Double) {
        guard distance.isFinite else { return }
        worldBestDistances[stage.rawValue] = max(worldBestDistances[stage.rawValue] ?? 0, min(stage.length, max(0, distance)))
    }

    func worldBestDistance(_ stage: WorldStage) -> Double { worldBestDistances[stage.rawValue] ?? 0 }


    var baseMultiplier: Int { min(30, max(1, missionTier + 1)) }

    func powerUpDuration(_ power: PowerUp) -> Double {
        let base: Double = power == .multiplier ? 12 : 10
        return base + Double(upgradeLevel(power) * 2)
    }

    func upgradeCost(_ power: PowerUp) -> Int {
        let level = upgradeLevel(power)
        return level < Self.maximumUpgradeLevel ? 200 * (level + 1) : 0
    }

    mutating func purchaseUpgrade(_ power: PowerUp) -> Bool {
        let cost = upgradeCost(power)
        guard cost > 0, coins >= cost else { return false }
        coins -= cost
        upgradeLevels[power.rawValue] = upgradeLevel(power) + 1
        return true
    }

    mutating func purchaseCharacter(_ id: String) -> Bool {
        guard let character = GameCatalog.characters.first(where: { $0.id == id }),
              !unlockedCharacters.contains(id), coins >= character.cost else { return false }
        coins -= character.cost
        unlockedCharacters.append(id)
        selectedCharacter = id
        return true
    }

    mutating func purchaseBoard(_ id: String) -> Bool {
        guard let board = GameCatalog.boards.first(where: { $0.id == id }),
              !unlockedBoards.contains(id), coins >= board.cost else { return false }
        coins -= board.cost
        unlockedBoards.append(id)
        selectedBoard = id
        return true
    }

    mutating func buyBoards() -> Bool {
        guard coins >= 150, boards <= Self.inventoryLimit - 3 else { return false }
        coins -= 150
        boards += 3
        return true
    }

    mutating func buyKeys() -> Bool {
        guard coins >= 250, keys < Self.inventoryLimit else { return false }
        coins -= 250
        keys += 1
        return true
    }

    /// Rewards are based on UTC calendar days, so time-zone changes cannot claim twice.
    /// A future saved claim blocks earlier dates rather than resetting the streak.
    @discardableResult
    mutating func claimDaily(now: Date = Date()) -> Int {
        let day = Self.dayKey(now)
        guard day > lastDailyClaim else { return 0 }
        let previousDay = Self.dayKey(now.addingTimeInterval(-86_400))
        dailyStreak = lastDailyClaim == previousDay ? min(365_000, dailyStreak + 1) : 1
        lastDailyClaim = day
        let reward = 100 + 25 * min(6, dailyStreak - 1)
        coins = Self.add(coins, reward)
        return reward
    }

    func canClaimDaily(now: Date = Date()) -> Bool {
        Self.dayKey(now) > lastDailyClaim
    }

    func dailyBest(now: Date = Date()) -> Int {
        dailyChallengeDate == Self.dayKey(now) ? dailyChallengeBest : 0
    }

    /// Each course and difficulty has its own record; a faster course never
    /// replaces the target a player is chasing in another mode.
    func modeBestScore(mode: RunMode, expert: Bool = false, expeditionStyle: ExpeditionStyle = .campaign) -> Int {
        guard mode != .odyssey || expeditionStyle != .practice else { return 0 }
        return modeRecords[Self.modeRecordKey(mode: mode, expert: expert, expeditionStyle: expeditionStyle)] ?? 0
    }

    private static func modeRecordKey(mode: RunMode, expert: Bool, expeditionStyle: ExpeditionStyle = .campaign) -> String {
        let variant = mode == .odyssey && expeditionStyle == .endless ? ".endless" : ""
        return "\(mode.rawValue)\(variant).\(expert ? "expert" : "standard")"
    }

    /// Call once when a run ends. Revive spending is handled when the revive occurs.
    mutating func recordRun(_ run: RunnerSimulation) {
        guard !run.isPractice else { return }
        syncJourney(run)
        if run.mode == .odyssey, run.expeditionStyle == .campaign, run.journeyComplete, run.stagesCleared == WorldStage.allCases.count { completedExpeditions = Self.add(completedExpeditions, 1) }
        coins = Self.add(coins, run.coins)
        keys = Self.add(keys, run.keys, limit: Self.inventoryLimit)
        boards = max(0, boards - min(Self.inventoryLimit, max(0, run.boardsUsed)))
        bestScore = max(bestScore, min(Self.counterLimit, max(0, run.score)))
        let recordKey = Self.modeRecordKey(mode: run.mode, expert: run.expert, expeditionStyle: run.expeditionStyle)
        modeRecords[recordKey] = max(modeRecords[recordKey] ?? 0, min(Self.counterLimit, max(0, run.score)))
        bestCombo = max(bestCombo, min(Self.counterLimit, max(0, run.bestCombo)))
        totalNearMisses = Self.add(totalNearMisses, run.nearMisses)
        totalGatesCleared = Self.add(totalGatesCleared, run.gatesCleared)
        if run.distance.isFinite {
            totalDistance = min(Self.distanceLimit, totalDistance + max(0, run.distance))
        }
        totalCoins = Self.add(totalCoins, run.coins)
        totalRuns = Self.add(totalRuns, 1)
        totalJumps = Self.add(totalJumps, run.jumps)
        totalRolls = Self.add(totalRolls, run.rolls)
        recentScores.insert(min(Self.counterLimit, max(0, run.score)), at: 0)
        recentScores = Array(recentScores.prefix(10))
    }

    /// Progress is made from completed-stage evidence. Set union and maxima make
    /// checkpoint saves, crash recovery and repeat syncs safe to call many times.
    private mutating func recordSkillProgress(_ result: WorldStageResult) {
        guard result.routeRevision >= 7 else { return }
        if result.branchRoute == .risky { skillRiskyWorlds.insert(result.stage) }
        if result.finaleCleared { skillFinaleWorlds.insert(result.stage) }
        if result.stage == .orbit && !result.usedProtection && result.hits == 0 && result.skillActions >= 8 { skillShieldlessOrbit = true }
        if result.stage == .mars { skillRoverTransfers = max(skillRoverTransfers, min(4, max(0, result.roverTransfers))) }
        skillObjectiveBest = max(skillObjectiveBest, min(3, max(0, result.objectivesCompleted)))
    }

    var skillChallenges: [SkillChallenge] {
        func challenge(_ id: String, _ title: String, _ detail: String, _ progress: Int, _ target: Int, _ reward: Int) -> SkillChallenge {
            SkillChallenge(id: id, title: title, detail: detail, progress: min(target, progress), target: target, reward: reward,
                           claimed: claimedSkillChallengeIDs.contains(id))
        }
        return [
            challenge("risk-explorer", "Take the high road", "Clear risky routes in three different worlds.", skillRiskyWorlds.count, 3, 350),
            challenge("orbit-unprotected", "Unshielded orbit", "Clear Orbit without a hit or protection, with eight clean skill actions.", skillShieldlessOrbit ? 1 : 0, 1, 450),
            challenge("six-finales", "Finale specialist", "Clear all six finales cleanly, with at least two skill actions in each.", skillFinaleWorlds.count, 6, 750),
            challenge("rover-rider", "Convoy rider", "Ride four rover roofs and finish Mars in one attempt.", skillRoverTransfers, 4, 400),
            challenge("objective-master", "Complete the assignment", "Finish a world with three local objectives complete.", skillObjectiveBest, 3, 350)
        ]
    }

    @discardableResult
    mutating func claimSkillChallenge(_ id: String) -> Int {
        guard let challenge = skillChallenges.first(where: { $0.id == id }), challenge.complete, !challenge.claimed else { return 0 }
        claimedSkillChallengeIDs.insert(id)
        coins = Self.add(coins, challenge.reward)
        return challenge.reward
    }

    var missions: [Mission] {
        let tier = min(10_000, max(0, missionTier))
        let prefix = "tier-\(tier)"
        let reward = min(500, 100 + tier * 25)
        let distanceTarget = 1_200 + tier * 1_800
        let coinTarget = 60 + tier * 100
        let skillTarget = 12 + tier * 12
        let usesJumps = tier.isMultiple(of: 2)
        return [
            Mission(id: "\(prefix)-distance", title: "Coast explorer", detail: "Travel \(distanceTarget)m in total", progress: Self.distanceCount(totalDistance), target: distanceTarget, reward: reward),
            Mission(id: "\(prefix)-coins", title: "Pocket sunshine", detail: "Collect \(coinTarget) coins in runs", progress: totalCoins, target: coinTarget, reward: reward),
            Mission(id: "\(prefix)-skill", title: usesJumps ? "Catch some air" : "Keep it low", detail: "\(usesJumps ? "Jump" : "Roll") \(skillTarget) times in total", progress: usesJumps ? totalJumps : totalRolls, target: skillTarget, reward: reward)
        ]
    }

    @discardableResult
    mutating func claimMission(_ id: String) -> Int {
        guard !claimedMissionIDs.contains(id),
              let mission = missions.first(where: { $0.id == id }), mission.complete else { return 0 }
        coins = Self.add(coins, mission.reward)
        claimedMissionIDs.append(id)
        if missions.allSatisfy({ claimedMissionIDs.contains($0.id) }) {
            missionTier = min(10_000, missionTier + 1)
        }
        // Older IDs cannot be claimed because only the current tier is eligible.
        claimedMissionIDs = Array(claimedMissionIDs.suffix(120))
        return mission.reward
    }

    /// Optional challenge runs can record their daily score independently of lifetime stats.
    mutating func recordDailyChallenge(score: Int, now: Date = Date()) {
        let day = Self.dayKey(now)
        if day != dailyChallengeDate {
            dailyChallengeDate = day
            dailyChallengeBest = 0
        }
        dailyChallengeBest = max(dailyChallengeBest, min(Self.counterLimit, max(0, score)))
    }

    private func upgradeLevel(_ power: PowerUp) -> Int {
        min(Self.maximumUpgradeLevel, max(0, upgradeLevels[power.rawValue] ?? 0))
    }

    private static let counterLimit = 1_000_000_000
    private static let inventoryLimit = 1_000_000
    private static let distanceLimit = 1_000_000_000_000.0

    private static func add(_ lhs: Int, _ rhs: Int, limit: Int = counterLimit) -> Int {
        let left = min(limit, max(0, lhs))
        let right = min(limit, max(0, rhs))
        return left + min(limit - left, right)
    }

    private static func distanceCount(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(Double(counterLimit), max(0, value)))
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    fileprivate mutating func sanitize() {
        coins = min(Self.counterLimit, max(0, coins))
        keys = min(Self.inventoryLimit, max(0, keys))
        boards = min(Self.inventoryLimit, max(0, boards))
        bestScore = min(Self.counterLimit, max(0, bestScore))
        totalDistance = totalDistance.isFinite ? min(Self.distanceLimit, max(0, totalDistance)) : 0
        totalCoins = min(Self.counterLimit, max(0, totalCoins))
        totalRuns = min(Self.counterLimit, max(0, totalRuns))
        totalJumps = min(Self.counterLimit, max(0, totalJumps))
        totalRolls = min(Self.counterLimit, max(0, totalRolls))
        missionTier = min(10_000, max(0, missionTier))
        dailyStreak = min(365_000, max(0, dailyStreak))
        dailyChallengeBest = min(Self.counterLimit, max(0, dailyChallengeBest))
        bestCombo = min(Self.counterLimit, max(0, bestCombo))
        totalNearMisses = min(Self.counterLimit, max(0, totalNearMisses))
        totalGatesCleared = min(Self.counterLimit, max(0, totalGatesCleared))
        let validRecordKeys = Set(RunMode.allCases.flatMap { mode in
            [Self.modeRecordKey(mode: mode, expert: false), Self.modeRecordKey(mode: mode, expert: true)]
        } + [Self.modeRecordKey(mode: .odyssey, expert: false, expeditionStyle: .endless),
             Self.modeRecordKey(mode: .odyssey, expert: true, expeditionStyle: .endless)])
        modeRecords = modeRecords.filter { validRecordKeys.contains($0.key) }
            .mapValues { min(Self.counterLimit, max(0, $0)) }
        swipeSensitivity = swipeSensitivity.isFinite ? min(1.5, max(0.65, swipeSensitivity)) : 1
        // Practice is launched from the Atlas and is never the next paid run.
        if selectedExpeditionStyle == .practice { selectedExpeditionStyle = .campaign }
        skillRoverTransfers = min(4, max(0, skillRoverTransfers))
        skillObjectiveBest = min(3, max(0, skillObjectiveBest))
        claimedSkillChallengeIDs.formIntersection(Set(skillChallenges.map(\.id)))
        dailyOdysseyBest = min(Self.counterLimit, max(0, dailyOdysseyBest))
        if !Self.validDayKey(dailyOdysseyDate) { dailyOdysseyDate = ""; dailyOdysseyBest = 0 }
        let validWorlds = Set(WorldStage.allCases.map(\.rawValue))
        worldMedals = worldMedals.filter { validWorlds.contains($0.key) }.mapValues { min(3, max(0, $0)) }
        worldBestScores = worldBestScores.filter { validWorlds.contains($0.key) }.mapValues { min(Self.counterLimit, max(0, $0)) }
        worldBestTimes = worldBestTimes.filter { validWorlds.contains($0.key) && $0.value.isFinite && $0.value > 0 }.mapValues { min(86_400, $0) }
        endlessWorldBestScores = endlessWorldBestScores.filter { validWorlds.contains($0.key) }.mapValues { min(Self.counterLimit, max(0, $0)) }
        endlessWorldBestTimes = endlessWorldBestTimes.filter { validWorlds.contains($0.key) && $0.value.isFinite && $0.value > 0 }.mapValues { min(86_400, $0) }
        legacyWorldBestScores = legacyWorldBestScores.filter { validWorlds.contains($0.key) }.mapValues { min(Self.counterLimit, max(0, $0)) }
        legacyWorldBestTimes = legacyWorldBestTimes.filter { validWorlds.contains($0.key) && $0.value.isFinite && $0.value > 0 }.mapValues { min(86_400, $0) }
        archivedWorldRecords = archivedWorldRecords.filter { (5..<PortalJourney.currentRevision).contains(Int($0.key) ?? 0) }.mapValues { records in
            ArchivedWorldRecords(
                times: records.times.filter { validWorlds.contains($0.key) && $0.value.isFinite && $0.value > 0 }.mapValues { min(86_400, $0) },
                scores: records.scores.filter { validWorlds.contains($0.key) }.mapValues { min(Self.counterLimit, max(0, $0)) })
        }
        let restoredGhosts = personalGhosts
        personalGhosts = []
        for ghost in restoredGhosts.prefix(32) { recordGhost(ghost) }
        highestUnlockedWorld = min(WorldStage.allCases.count - 1, max(0, highestUnlockedWorld))
        selectedWorld = min(highestUnlockedWorld, max(0, selectedWorld))
        completedExpeditions = min(Self.counterLimit, max(0, completedExpeditions))
        worldBestDistances = Dictionary(uniqueKeysWithValues: WorldStage.allCases.map { stage in
            let value = worldBestDistances[stage.rawValue] ?? 0
            return (stage.rawValue, value.isFinite ? min(stage.length, max(0, value)) : 0)
        })
        unlockedCharacters = Self.unique(["milo"] + unlockedCharacters.filter { id in GameCatalog.characters.contains(where: { $0.id == id }) })
        unlockedBoards = Self.unique(["tideline"] + unlockedBoards.filter { id in GameCatalog.boards.contains(where: { $0.id == id }) })
        if !unlockedCharacters.contains(selectedCharacter) { selectedCharacter = "milo" }
        if !unlockedBoards.contains(selectedBoard) { selectedBoard = "tideline" }
        upgradeLevels = Dictionary(uniqueKeysWithValues: PowerUp.allCases.map { ($0.rawValue, upgradeLevel($0)) })
        claimedMissionIDs = Array(Self.unique(claimedMissionIDs.filter { $0.count < 64 }).suffix(120))
        recentScores = recentScores.prefix(10).map { min(Self.counterLimit, max(0, $0)) }
        bestScore = max(bestScore, recentScores.max() ?? 0)
        bestScore = max(bestScore, modeRecords.values.max() ?? 0)
        if !Self.validDayKey(lastDailyClaim) { lastDailyClaim = ""; dailyStreak = 0 }
        if !Self.validDayKey(dailyChallengeDate) { dailyChallengeDate = ""; dailyChallengeBest = 0 }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func validDayKey(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private enum CodingKeys: String, CodingKey {
        case coins, keys, boards, bestScore, totalDistance, totalCoins, totalRuns, totalJumps, totalRolls
        case selectedCharacter, selectedBoard, unlockedCharacters, unlockedBoards, upgradeLevels
        case missionTier, claimedMissionIDs, lastDailyClaim, dailyStreak, soundEnabled, hapticsEnabled
        case tutorialCompleted, recentScores, dailyChallengeDate, dailyChallengeBest
        case selectedMode, selectedExpert, modeRecords, bestCombo, totalNearMisses, totalGatesCleared
        case selectedExpeditionStyle, reducedMotion, highContrastCues
        case highestUnlockedWorld, selectedWorld, collectedRelicWorlds, completedExpeditions, worldBestDistances
        case worldMedals, worldBestTimes, worldBestScores, selectedArtifact, graphicsQuality, portalAssist, swipeSensitivity, ghostEnabled, personalGhosts
        case worldRecordRevision, legacyWorldBestTimes, legacyWorldBestScores
        case archivedWorldRecords
        case dailyOdysseyDate, dailyOdysseyBest
        case endlessWorldBestTimes, endlessWorldBestScores
        case skillRiskyWorlds, skillFinaleWorlds, skillShieldlessOrbit, skillRoverTransfers, skillObjectiveBest, claimedSkillChallengeIDs
    }

    /// Missing or damaged individual fields keep their defaults when the save evolves.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        coins = (try? values.decode(Int.self, forKey: .coins)) ?? coins
        keys = (try? values.decode(Int.self, forKey: .keys)) ?? keys
        boards = (try? values.decode(Int.self, forKey: .boards)) ?? boards
        bestScore = (try? values.decode(Int.self, forKey: .bestScore)) ?? bestScore
        totalDistance = (try? values.decode(Double.self, forKey: .totalDistance)) ?? totalDistance
        totalCoins = (try? values.decode(Int.self, forKey: .totalCoins)) ?? totalCoins
        totalRuns = (try? values.decode(Int.self, forKey: .totalRuns)) ?? totalRuns
        totalJumps = (try? values.decode(Int.self, forKey: .totalJumps)) ?? totalJumps
        totalRolls = (try? values.decode(Int.self, forKey: .totalRolls)) ?? totalRolls
        selectedCharacter = (try? values.decode(String.self, forKey: .selectedCharacter)) ?? selectedCharacter
        selectedBoard = (try? values.decode(String.self, forKey: .selectedBoard)) ?? selectedBoard
        unlockedCharacters = (try? values.decode([String].self, forKey: .unlockedCharacters)) ?? unlockedCharacters
        unlockedBoards = (try? values.decode([String].self, forKey: .unlockedBoards)) ?? unlockedBoards
        upgradeLevels = (try? values.decode([String: Int].self, forKey: .upgradeLevels)) ?? upgradeLevels
        missionTier = (try? values.decode(Int.self, forKey: .missionTier)) ?? missionTier
        claimedMissionIDs = (try? values.decode([String].self, forKey: .claimedMissionIDs)) ?? claimedMissionIDs
        lastDailyClaim = (try? values.decode(String.self, forKey: .lastDailyClaim)) ?? lastDailyClaim
        dailyStreak = (try? values.decode(Int.self, forKey: .dailyStreak)) ?? dailyStreak
        soundEnabled = (try? values.decode(Bool.self, forKey: .soundEnabled)) ?? soundEnabled
        hapticsEnabled = (try? values.decode(Bool.self, forKey: .hapticsEnabled)) ?? hapticsEnabled
        tutorialCompleted = (try? values.decode(Bool.self, forKey: .tutorialCompleted)) ?? tutorialCompleted
        recentScores = (try? values.decode([Int].self, forKey: .recentScores)) ?? recentScores
        dailyChallengeDate = (try? values.decode(String.self, forKey: .dailyChallengeDate)) ?? dailyChallengeDate
        dailyChallengeBest = (try? values.decode(Int.self, forKey: .dailyChallengeBest)) ?? dailyChallengeBest
        selectedMode = (try? values.decode(RunMode.self, forKey: .selectedMode)) ?? .endless
        selectedExpert = (try? values.decode(Bool.self, forKey: .selectedExpert)) ?? selectedExpert
        selectedExpeditionStyle = (try? values.decode(ExpeditionStyle.self, forKey: .selectedExpeditionStyle)) ?? .campaign
        reducedMotion = (try? values.decode(Bool.self, forKey: .reducedMotion)) ?? false
        highContrastCues = (try? values.decode(Bool.self, forKey: .highContrastCues)) ?? false
        if let records = try? values.decode([String: Int].self, forKey: .modeRecords) {
            modeRecords = records
        } else {
            // Before courses existed every score belonged to the standard run.
            modeRecords = [Self.modeRecordKey(mode: .endless, expert: false): max(bestScore, recentScores.max() ?? 0)]
        }
        bestCombo = (try? values.decode(Int.self, forKey: .bestCombo)) ?? bestCombo
        totalNearMisses = (try? values.decode(Int.self, forKey: .totalNearMisses)) ?? totalNearMisses
        totalGatesCleared = (try? values.decode(Int.self, forKey: .totalGatesCleared)) ?? totalGatesCleared
        highestUnlockedWorld = (try? values.decode(Int.self, forKey: .highestUnlockedWorld)) ?? 0
        selectedWorld = (try? values.decode(Int.self, forKey: .selectedWorld)) ?? 0
        let relicNames = (try? values.decode([String].self, forKey: .collectedRelicWorlds)) ?? []
        collectedRelicWorlds = Set(relicNames.compactMap(WorldStage.init(rawValue:)))
        completedExpeditions = (try? values.decode(Int.self, forKey: .completedExpeditions)) ?? 0
        worldBestDistances = (try? values.decode([String: Double].self, forKey: .worldBestDistances)) ?? [:]
        worldMedals = (try? values.decode([String: Int].self, forKey: .worldMedals)) ?? [:]
        worldBestTimes = (try? values.decode([String: Double].self, forKey: .worldBestTimes)) ?? [:]
        worldBestScores = (try? values.decode([String: Int].self, forKey: .worldBestScores)) ?? [:]
        worldRecordRevision = (try? values.decode(Int.self, forKey: .worldRecordRevision)) ?? 4
        legacyWorldBestTimes = (try? values.decode([String: Double].self, forKey: .legacyWorldBestTimes)) ?? [:]
        legacyWorldBestScores = (try? values.decode([String: Int].self, forKey: .legacyWorldBestScores)) ?? [:]
        archivedWorldRecords = (try? values.decode([String: ArchivedWorldRecords].self, forKey: .archivedWorldRecords)) ?? [:]
        if worldRecordRevision < PortalJourney.currentRevision {
            archiveRecords(revision: worldRecordRevision, times: worldBestTimes, scores: worldBestScores)
            worldBestTimes = [:]; worldBestScores = [:]
            worldRecordRevision = PortalJourney.currentRevision
        }
        selectedArtifact = (try? values.decode(ArtifactAbility.self, forKey: .selectedArtifact)) ?? .shield
        graphicsQuality = (try? values.decode(RenderQuality.self, forKey: .graphicsQuality)) ?? .automatic
        portalAssist = (try? values.decode(Bool.self, forKey: .portalAssist)) ?? true
        swipeSensitivity = (try? values.decode(Double.self, forKey: .swipeSensitivity)) ?? 1
        ghostEnabled = (try? values.decode(Bool.self, forKey: .ghostEnabled)) ?? true
        personalGhosts = (try? values.decode([GhostReplay].self, forKey: .personalGhosts)) ?? []
        dailyOdysseyDate = (try? values.decode(String.self, forKey: .dailyOdysseyDate)) ?? ""
        dailyOdysseyBest = (try? values.decode(Int.self, forKey: .dailyOdysseyBest)) ?? 0
        endlessWorldBestTimes = (try? values.decode([String: Double].self, forKey: .endlessWorldBestTimes)) ?? [:]
        endlessWorldBestScores = (try? values.decode([String: Int].self, forKey: .endlessWorldBestScores)) ?? [:]
        skillRiskyWorlds = Set(((try? values.decode([String].self, forKey: .skillRiskyWorlds)) ?? []).compactMap(WorldStage.init(rawValue:)))
        skillFinaleWorlds = Set(((try? values.decode([String].self, forKey: .skillFinaleWorlds)) ?? []).compactMap(WorldStage.init(rawValue:)))
        skillShieldlessOrbit = (try? values.decode(Bool.self, forKey: .skillShieldlessOrbit)) ?? false
        skillRoverTransfers = (try? values.decode(Int.self, forKey: .skillRoverTransfers)) ?? 0
        skillObjectiveBest = (try? values.decode(Int.self, forKey: .skillObjectiveBest)) ?? 0
        claimedSkillChallengeIDs = (try? values.decode(Set<String>.self, forKey: .claimedSkillChallengeIDs)) ?? []
        sanitize()
    }
}

enum ProfileStore {
    private static let saveKey = "coastlineRush.profile.v1"

    /// Tests can inject an isolated UserDefaults suite without touching the player's save.
    static func load(defaults: UserDefaults = .standard) -> PlayerProfile {
        guard let data = defaults.data(forKey: saveKey),
              let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data) else { return PlayerProfile() }
        return profile
    }

    static func save(_ profile: PlayerProfile, defaults: UserDefaults = .standard) {
        var safeProfile = profile
        safeProfile.sanitize()
        guard let data = try? JSONEncoder().encode(safeProfile) else { return }
        defaults.set(data, forKey: saveKey)
    }
}
