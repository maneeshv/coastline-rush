import Foundation

/// Overrides every store operation used by ProfileStore; no preferences reach disk.
private final class ProfileMemoryDefaults: UserDefaults {
    var storage: [String: Any] = [:]

    override func data(forKey defaultName: String) -> Data? { storage[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
}

@main
enum ProfileTests {
    private static var checks = 0

    static func main() throws {
        testPurchases()
        testUpgradeCaps()
        let run = makeCompletedRun()
        testRunAccounting(run)
        testMissions(run)
        testDailyRewards()
        testDailyChallenge()
        try testModeRecords()
        try testMigrationAndCorruption()
        try testJourneyMigration()
        try testSaveReload()
        try testV4MigrationAndMastery()
        try testLongStageRecordMigration()
        try testMomentumRecordMigration()
        try testGhostReplay()
        testDailyOdyssey()
        try testExpansionMigration()
        testExpeditionAccounting()
        try testSkillChallenges()
        try testExpansionGhostIdentity()
        print("PASS: \(checks) profile assertions across 19 groups; no player preferences written.")
    }

    private static func testExpansionMigration() throws {
        let old = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":918,"keys":12,"boards":8,"worldRecordRevision":6,"worldBestTimes":{"mars":99},"worldBestScores":{"mars":3000},"worldMedals":{"mars":3},"modeRecords":{"odyssey.standard":9000}}"#.utf8))
        expect(old.coins == 918 && old.keys == 12 && old.boards == 8 && old.medal(for: .mars) == .gold, "V7 migration retains wallet, inventory and earned mastery")
        expect(old.archivedWorldRecords["6"]?.times["mars"] == 99 && old.worldBestTimes.isEmpty, "V6 stage records are archived before authored route comparisons")
        expect(old.selectedExpeditionStyle == .campaign && !old.reducedMotion && !old.highContrastCues, "New settings have stable backwards-compatible defaults")
        expect(old.skillChallenges.allSatisfy { $0.progress == 0 && !$0.claimed }, "Old saves do not invent skill achievement evidence")
        expect(old.modeBestScore(mode: .odyssey) == 9000 && old.modeBestScore(mode: .odyssey, expeditionStyle: .endless) == 0, "Existing campaign record stays separate from new Endless Odyssey")
        var custom = old
        custom.selectedExpeditionStyle = .endless; custom.reducedMotion = true; custom.highContrastCues = true
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(custom))
        expect(restored.selectedExpeditionStyle == .endless && restored.reducedMotion && restored.highContrastCues, "Expedition and accessibility preferences round-trip")
        expect(restored.archivedWorldRecords["6"]?.times["mars"] == 99, "Repeated V7 loads retain the migration archive")
        let damaged = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"selectedExpeditionStyle":"practice","skillRiskyWorlds":["unknown","mars","mars"],"skillFinaleWorlds":["mars","orbit"],"skillRoverTransfers":999,"skillObjectiveBest":-3,"claimedSkillChallengeIDs":["invented"],"endlessWorldBestTimes":{"unknown":1,"mars":-1,"orbit":92},"endlessWorldBestScores":{"mars":-5,"unknown":10},"modeRecords":{"odyssey.endless.standard":24000,"odyssey.practice.standard":80000}}"#.utf8))
        expect(damaged.selectedExpeditionStyle == .campaign, "Practice is not persisted as a normal next-run selection")
        expect(damaged.skillRiskyWorlds == [.mars] && damaged.skillFinaleWorlds == [.mars, .orbit], "Skill world evidence is unique and only accepts known worlds")
        expect(damaged.skillRoverTransfers == 4 && damaged.skillObjectiveBest == 0 && damaged.claimedSkillChallengeIDs.isEmpty, "Skill counters and claims are bounded")
        expect(damaged.endlessWorldBestTimes == ["orbit":92] && damaged.endlessWorldBestScores == ["mars":0], "Endless world records reject malformed entries")
        expect(damaged.modeBestScore(mode: .odyssey, expeditionStyle: .endless) == 24000 && damaged.modeBestScore(mode: .odyssey, expeditionStyle: .practice) == 0, "Only competitive expedition styles retain record keys")
    }

    private static func testExpeditionAccounting() {
        func fixture(_ style: ExpeditionStyle) -> RunnerSimulation {
            var run = RunnerSimulation()
            run.start(seed: 507, boards: 3, mode: .odyssey, startStage: 2, expeditionStyle: style)
            var pickups = (0..<5).map { TrackEntity(id: $0, kind: .coin, lane: 0, z: 0.1, y: 0.9, length: 0.3) }
            pickups.append(TrackEntity(id: 10, kind: .key, lane: 0, z: 0.1, y: 0.9, length: 0.3))
            run.replaceTrackForTesting(pickups)
            run.update(dt: 0.03)
            run.act(.board); run.act(.jump); run.update(dt: 2); run.finish()
            expect(run.coins == 5 && run.keys == 1 && run.score > 0, "Expansion fixture collects actual simulation pickups")
            return run
        }
        var practiceProfile = PlayerProfile()
        let practice = fixture(.practice)
        practiceProfile.syncJourney(practice); practiceProfile.recordRun(practice)
        expect(practiceProfile.coins == 0 && practiceProfile.keys == 3 && practiceProfile.boards == 3, "Practice does not earn or consume persistent inventory")
        expect(practiceProfile.totalRuns == 0 && practiceProfile.totalDistance == 0 && practiceProfile.totalJumps == 0 && practiceProfile.totalCoins == 0, "Practice cannot advance lifetime missions")
        expect(practiceProfile.highestUnlockedWorld == 0 && practiceProfile.worldBestDistances.isEmpty && practiceProfile.worldMedals.isEmpty && practiceProfile.collectedRelicWorlds.isEmpty, "Practice cannot unlock or master worlds")
        expect(practiceProfile.bestScore == 0 && practiceProfile.modeRecords.isEmpty && practiceProfile.recentScores.isEmpty, "Practice cannot create score records")
        let endless = fixture(.endless)
        var endlessProfile = PlayerProfile(); endlessProfile.modeRecords["odyssey.standard"] = 100
        endlessProfile.recordRun(endless)
        expect(endlessProfile.coins == 5 && endlessProfile.keys == 4 && endlessProfile.totalRuns == 1, "Endless Odyssey banks earned pickups and lifetime progress")
        expect(endlessProfile.modeBestScore(mode: .odyssey) == 100 && endlessProfile.modeBestScore(mode: .odyssey, expeditionStyle: .endless) == endless.score, "Endless records cannot overwrite campaign records")
        expect(endlessProfile.completedExpeditions == 0, "Endless settlement never earns a six-world campaign win")
        let result = WorldStageResult(stage: .mars, medal: .gold, score: 999, relics: 1, hits: 0, elapsed: 85, precisionPortal: true, skillActions: 8)
        practiceProfile.recordStage(result, expeditionStyle: .practice)
        expect(practiceProfile.worldMedals.isEmpty && practiceProfile.skillChallenges.allSatisfy { $0.progress == 0 }, "Direct practice stage settlement is also excluded")
        endlessProfile.recordStage(result, expeditionStyle: .endless)
        expect(endlessProfile.endlessWorldBestScores["mars"] == 999 && endlessProfile.endlessWorldBestTimes["mars"] == 85 && endlessProfile.worldBestScores.isEmpty && endlessProfile.worldBestTimes.isEmpty, "Endless stage timings and scores are stored independently")
    }

    private static func testSkillChallenges() throws {
        func result(_ stage: WorldStage, revision: Int = 7, protected: Bool = false, hits: Int = 0, actions: Int = 8) -> WorldStageResult {
            WorldStageResult(routeRevision: revision, stage: stage, medal: .gold, score: 900, relics: 2, hits: hits, elapsed: 100,
                             precisionPortal: true, skillActions: actions, usedProtection: protected, branchRoute: .risky,
                             finaleCleared: true, roverTransfers: 4, objectivesCompleted: 3)
        }
        var profile = PlayerProfile()
        expect(profile.claimSkillChallenge("six-finales") == 0 && profile.claimSkillChallenge("invented") == 0, "Unknown or incomplete skill challenges cannot pay")
        profile.recordStage(result(.orbit, revision: 6))
        expect(profile.skillChallenges.allSatisfy { $0.progress == 0 }, "Legacy results cannot fabricate V7 achievements")
        profile.recordStage(result(.orbit, protected: true))
        profile.recordStage(result(.orbit, hits: 1))
        profile.recordStage(result(.orbit, actions: 7))
        expect(!profile.skillShieldlessOrbit, "Unshielded Orbit requires no protection, no hit, and eight actions together")
        for stage in WorldStage.allCases { profile.recordStage(result(stage)) }
        expect(profile.skillChallenges.count == 5 && profile.skillChallenges.allSatisfy(\.complete), "Distinct stage evidence completes all five skill challenges")
        let before = profile.coins
        let totalReward = profile.skillChallenges.reduce(0) { $0 + $1.reward }
        for challenge in profile.skillChallenges {
            expect(profile.claimSkillChallenge(challenge.id) == challenge.reward, "Skill challenge pays its displayed reward")
            expect(profile.claimSkillChallenge(challenge.id) == 0, "Skill reward cannot be claimed twice")
        }
        expect(profile.coins == before + totalReward, "Exactly the advertised skill rewards enter the wallet")
        for _ in 0..<10 { profile.recordStage(result(.mars)) }
        expect(profile.skillRiskyWorlds.count == 6 && profile.skillFinaleWorlds.count == 6 && profile.skillRoverTransfers == 4, "Repeated checkpoint-stage sync does not inflate skill progress")
        var restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.skillChallenges.allSatisfy { $0.complete && $0.claimed }, "Progress and claims survive save reload")
        expect(restored.claimSkillChallenge("rover-rider") == 0 && restored.coins == profile.coins, "Reload does not re-enable a previously claimed reward")
    }

    private static func testExpansionGhostIdentity() throws {
        let decisions = [ExpeditionDecision(world: 0, route: .safe), ExpeditionDecision(world: 1, route: .risky, perk: .longPhase)]
        let course = GhostCourseKey(mode: .odyssey, expert: true, seed: 77, startWorld: 0, decisionPlan: decisions, artifact: .phaseStep)
        expect(course.isValid, "Campaign ghost accepts a bounded chronological choice plan")
        let restored = try JSONDecoder().decode(GhostCourseKey.self, from: JSONEncoder().encode(course))
        expect(restored == course && restored.decisionPlan == decisions && restored.artifact == .phaseStep, "Ghost course retains exact perk, route and artifact decisions")
        var other = course; other.artifact = .shield
        expect(other != course, "Artifact is part of campaign ghost identity")
        other = course; other.decisionPlan[1].route = .safe
        expect(other != course, "Branch choice is part of campaign ghost identity")
        other = course; other.expeditionStyle = .endless
        expect(!other.isValid, "Endless loops cannot use a monotonic campaign ghost")
        other.expeditionStyle = .practice
        expect(!other.isValid, "Practice does not compete with campaign ghosts")
        other = course; other.decisionPlan.append(ExpeditionDecision(world: 2, route: .safe, perk: .longPhase))
        expect(!other.isValid, "Replays reject duplicate perks the simulation could not earn")
        other = course; other.decisionPlan.reverse()
        expect(!other.isValid, "Replays reject out-of-order world decisions")
        other = course; other.decisionPlan.append(ExpeditionDecision(world: 8, route: .safe))
        expect(!other.isValid, "Replays reject unknown worlds")
        other = course; other.decisionPlan = Array(repeating: decisions[0], count: 7)
        expect(!other.isValid, "Replay plans remain bounded")
        let oldMode = try JSONDecoder().decode(GhostCourseKey.self, from: Data(#"{"mode":"endless","expert":false,"seed":42,"startWorld":0,"revision":6}"#.utf8))
        expect(oldMode.isValid && oldMode.decisionPlan.isEmpty && oldMode.artifact == nil, "Original mode ghosts remain compatible when new fields are absent")
        var retired = oldMode; retired.revision = 4
        expect(!retired.isValid, "Endless ghosts recorded before the G1 generator change retire")
        let oldOdyssey = try JSONDecoder().decode(GhostCourseKey.self, from: Data(#"{"mode":"odyssey","expert":false,"seed":42,"startWorld":0,"revision":6}"#.utf8))
        expect(!oldOdyssey.isValid, "Older Odyssey geometry never races the current generator")
        let jetSki = try JSONDecoder().decode(GhostCourseKey.self, from: Data(#"{"mode":"jetSki","expert":false,"seed":42,"startWorld":0,"revision":4}"#.utf8))
        expect(jetSki.isValid && GhostCourseKey(mode: .jetSki, expert: false, seed: 42, startWorld: 0).revision == 4, "Jet Ski ghosts survive G1: its generator did not change")
        var odysseyV7 = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0); odysseyV7.revision = 7
        expect(!odysseyV7.isValid, "Odyssey ghosts recorded before the G1 coin lines retire")
        let normalized = GhostCourseKey(mode: .jetSki, expert: false, seed: 77, startWorld: 0, expeditionStyle: .endless, decisionPlan: decisions, artifact: .phaseStep)
        expect(normalized.isValid && normalized.decisionPlan.isEmpty && normalized.artifact == nil, "Original modes ignore expedition-only menu settings")
    }

    private static func testJourneyMigration() throws {
        expect(PlayerProfile().selectedMode == .odyssey, "Brand-new profiles feature Odyssey")
        let old = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":975,"keys":8,"selectedMode":"jetSki"}"#.utf8))
        expect(old.coins == 975 && old.keys == 8 && old.selectedMode == .jetSki, "Journey migration preserves existing wallet and choice")
        expect(old.highestUnlockedWorld == 0 && old.collectedRelicWorlds.isEmpty && old.completedExpeditions == 0, "Old saves start with a clean atlas")
        let oldest = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":61}"#.utf8))
        expect(oldest.selectedMode == .endless && oldest.coins == 61, "Pre-mode saves retain the original run choice")
        let damaged = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":123,"highestUnlockedWorld":999,"selectedWorld":99,"completedExpeditions":-5,"collectedRelicWorlds":["mars","unknown","mars"],"worldBestDistances":{"mars":99999,"orbit":-10}}"#.utf8))
        expect(damaged.coins == 123 && damaged.highestUnlockedWorld == 5 && damaged.selectedWorld == 5, "Atlas sanitization erased wallet or accepted invalid indices")
        expect(damaged.collectedRelicWorlds == [.mars] && damaged.completedExpeditions == 0, "Damaged relic or completion fields were not sanitized")
        expect(damaged.worldBestDistance(.mars) == WorldStage.mars.length && damaged.worldBestDistance(.orbit) == 0, "World records escaped their bounds")
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(damaged))
        expect(restored.collectedRelicWorlds == [.mars] && restored.worldBestDistance(.mars) == WorldStage.mars.length, "Journey data did not round-trip")
    }

    private static func testV4MigrationAndMastery() throws {
        let old = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":777,"dailyChallengeDate":"2026-10-04","dailyChallengeBest":9900}"#.utf8))
        expect(old.coins == 777 && old.dailyChallengeBest == 9900, "V4 migration retains wallet and legacy daily records")
        expect(old.dailyOdysseyBest == 0 && old.personalGhosts.isEmpty && old.worldMedals.isEmpty, "V4 does not compare legacy courses with new Odyssey")
        expect(old.portalAssist && old.ghostEnabled && old.graphicsQuality == .automatic && old.swipeSensitivity == 1, "V4 input and rendering defaults are accessible")
        let damaged = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"worldMedals":{"mars":999,"unknown":3,"orbit":-4},"worldBestTimes":{"mars":-10,"orbit":50},"worldBestScores":{"mars":-500},"swipeSensitivity":100,"selectedArtifact":"invalid","graphicsQuality":"invalid"}"#.utf8))
        expect(damaged.worldMedals["mars"] == 3 && damaged.worldMedals["orbit"] == 0 && damaged.worldMedals["unknown"] == nil, "Mastery rejects unknown worlds and bounds medals")
        expect(damaged.legacyWorldBestTimes["mars"] == nil && damaged.legacyWorldBestTimes["orbit"] == 50 && damaged.legacyWorldBestScores["mars"] == 0, "World records reject negative values")
        expect(damaged.swipeSensitivity == 1.5 && damaged.selectedArtifact == .shield && damaged.graphicsQuality == .automatic, "Corrupt settings use safe choices")
        var profile = PlayerProfile()
        profile.recordStage(WorldStageResult(stage: .mars, medal: .gold, score: 800, relics: 2, hits: 0, elapsed: 30, precisionPortal: true, skillActions: 2))
        profile.recordStage(WorldStageResult(stage: .mars, medal: .bronze, score: 600, relics: 0, hits: 1, elapsed: 40, precisionPortal: false, skillActions: 0))
        expect(profile.medal(for: .mars) == .gold && profile.worldBestScores["mars"] == 800 && profile.worldBestTimes["mars"] == 30, "Weaker attempts never overwrite mastery records")
        expect(profile.worldBestDistance(.mars) == WorldStage.mars.length, "A medal records a completed world")
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.medal(for: .mars) == .gold && restored.masteryCount == 3, "Mastery survives persistence")
    }

    private static func testLongStageRecordMigration() throws {
        var profile = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":777,"highestUnlockedWorld":3,"worldMedals":{"mars":3},"worldBestTimes":{"mars":28},"worldBestScores":{"mars":800},"worldBestDistances":{"mars":480}}"#.utf8))
        expect(profile.coins == 777 && profile.highestUnlockedWorld == 3 && profile.medal(for: .mars) == .gold, "Long-stage migration preserves wallet, unlocks and earned mastery")
        expect(profile.worldBestTimes.isEmpty && profile.worldBestScores.isEmpty && profile.legacyWorldBestTimes["mars"] == 28, "Short-stage records must not compete with longer courses")
        expect(profile.worldBestDistance(.mars) == 480, "Migration must not claim old players completed the longer course")
        profile.recordStage(WorldStageResult(routeRevision: 4, stage: .mars, medal: .silver, score: 900, relics: 1, hits: 0, elapsed: 27, precisionPortal: false, skillActions: 2))
        expect(profile.legacyWorldBestTimes["mars"] == 27 && profile.legacyWorldBestScores["mars"] == 900 && profile.worldBestTimes.isEmpty, "Resumed legacy stage stays in its record archive")
        expect(profile.worldBestDistance(.mars) == 480, "Legacy completion must record legacy length")
        profile.recordStage(WorldStageResult(stage: .mars, medal: .silver, score: 2000, relics: 1, hits: 0, elapsed: 104, precisionPortal: false, skillActions: 4))
        expect(profile.worldBestTimes["mars"] == 104 && profile.worldBestScores["mars"] == 2000, "New course establishes independent records")
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.worldBestTimes == profile.worldBestTimes && restored.legacyWorldBestTimes == profile.legacyWorldBestTimes, "Migration is idempotent after saving")
        var oldOdyssey = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0); oldOdyssey.revision = 4
        expect(!oldOdyssey.isValid, "Short-stage ghosts cannot race extended Odyssey")
        expect(GhostCourseKey(mode: .endless, expert: false, seed: 42, startWorld: 0).revision == GhostCourseKey.legacyModeRevision, "Endless ghosts use the current generator revision")
        expect(GhostCourseKey.revision(for: .odyssey) == 9 && GhostCourseKey.revision(for: .endless) == 6
               && GhostCourseKey.revision(for: .harborSprint) == 6 && GhostCourseKey.revision(for: .jetSki) == 4,
               "G3 generation retires Odyssey, Endless and Sprint ghosts; Jet Ski generation is unchanged")
        var g1Odyssey = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0); g1Odyssey.revision = 8
        var g1Endless = GhostCourseKey(mode: .endless, expert: false, seed: 42, startWorld: 0); g1Endless.revision = 5
        expect(!g1Odyssey.isValid && !g1Endless.isValid && GhostCourseKey(mode: .jetSki, expert: false, seed: 42, startWorld: 0).isValid,
               "G1-era Odyssey and Endless ghosts are discarded; Jet Ski ghosts stay valid")
    }

    private static func testMomentumRecordMigration() throws {
        var profile = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"coins":777,"worldRecordRevision":5,"highestUnlockedWorld":5,"worldMedals":{"mars":3},"worldBestTimes":{"mars":104},"worldBestScores":{"mars":2000},"legacyWorldBestTimes":{"mars":28},"legacyWorldBestScores":{"mars":800}}"#.utf8))
        expect(profile.worldRecordRevision == PortalJourney.currentRevision && profile.worldBestTimes.isEmpty, "New momentum route starts a separate timing table")
        expect(profile.archivedWorldRecords["5"]?.times["mars"] == 104 && profile.legacyWorldBestTimes["mars"] == 28, "Migration retains both v4 and v5 records without comparing different routes")
        expect(profile.coins == 777 && profile.highestUnlockedWorld == 5 && profile.medal(for: .mars) == .gold, "Momentum migration preserves the player's progress")
        profile.recordStage(WorldStageResult(routeRevision: 5, stage: .mars, medal: .silver, score: 2100, relics: 1, hits: 0, elapsed: 103, precisionPortal: false, skillActions: 4))
        expect(profile.worldBestDistance(.mars) == 2750, "Resumed v5 result credits the correct v5 length")
        expect(profile.archivedWorldRecords["5"]?.times["mars"] == 103 && profile.archivedWorldRecords["5"]?.scores["mars"] == 2100, "Resumed v5 results stay in the matching archive")
        profile.recordStage(WorldStageResult(stage: .mars, medal: .silver, score: 3000, relics: 1, hits: 0, elapsed: 101, precisionPortal: false, skillActions: 4))
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.worldBestTimes["mars"] == 101 && restored.archivedWorldRecords["5"]?.times["mars"] == 103 && restored.legacyWorldBestTimes["mars"] == 28, "All three course generations persist independently")
        var oldCourse = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0); oldCourse.revision = 5
        expect(!oldCourse.isValid, "Speed-reset ghosts cannot race the momentum route")
        let damaged = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"archivedWorldRecords":{"5":{"times":{"mars":-1,"orbit":90,"unknown":99},"scores":{"mars":-8,"unknown":99}},"999":{"times":{"orbit":1},"scores":{}}}}"#.utf8))
        expect(damaged.archivedWorldRecords["999"] == nil && damaged.archivedWorldRecords["5"]?.times["mars"] == nil && damaged.archivedWorldRecords["5"]?.times["unknown"] == nil, "Damaged archived routes and times are bounded")
        expect(damaged.archivedWorldRecords["5"]?.scores["mars"] == 0, "Archived scores use the same safeguards as current records")
    }

    private static func testGhostReplay() throws {
        let key = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0)
        func sample(_ time: Double, stage: Int = 0) -> GhostSample {
            GhostSample(time: time, distance: time * 15, stageIndex: stage, stageDistance: time * 15, x: time.truncatingRemainder(dividingBy: 2), y: 0.5, roll: false)
        }
        var recorder = GhostRecorder()
        for frame in 0...60_000 { recorder.append(sample(Double(frame) / 60)) }
        expect(recorder.samples.count <= GhostReplay.maximumSamples && recorder.samples.count > 1_000, "Long recordings remain bounded without losing their full duration")
        expect((recorder.samples.last?.time ?? 0) > 999, "Long recordings keep the end of the attempt")
        expect(recorder.sampleInterval > 0.1, "Recorder adapts density for long attempts")
        let count = recorder.samples.count
        recorder.append(sample(-1), force: true)
        recorder.append(sample(0), force: true)
        expect(recorder.samples.count == count, "Bad and non-monotonic samples cannot enter a recording")
        let long = recorder.replay(course: key, score: 900, completed: false)!
        expect(long.sample(at: -1) == nil && long.sample(at: 2_000) == nil, "Ghost never appears before or after its recorded attempt")
        let simple = GhostReplay(course: key, score: 700, completed: false, recordedAt: Date(timeIntervalSince1970: 100), samples: [sample(0), sample(2)])
        let midpoint = simple.sample(at: 1)!
        expect(midpoint.distance == 15 && midpoint.time == 1, "Ghost positions interpolate between samples")
        let portal = GhostReplay(course: key, score: 100, completed: false, recordedAt: Date(), samples: [sample(0), sample(2, stage: 1)])
        expect(portal.sample(at: 1)?.stageIndex == 0 && portal.sample(at: 2)?.stageIndex == 1, "Portal playback does not interpolate across worlds")
        var profile = PlayerProfile()
        profile.recordGhost(simple)
        expect(profile.matchingGhost(for: key)?.score == 700, "Matching course offers its personal ghost")
        expect(profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: true, seed: 42, startWorld: 0)) == nil, "Difficulty is part of ghost identity")
        expect(profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: false, seed: 43, startWorld: 0)) == nil, "Unrelated random seed cannot supply a ghost")
        expect(profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 1)) == nil, "Practice starts never compare with full expeditions")
        profile.recordGhost(GhostReplay(course: key, score: 100, completed: false, recordedAt: Date(), samples: simple.samples))
        expect(profile.matchingGhost(for: key)?.score == 700, "A weaker ghost never replaces a personal best")
        profile.recordGhost(GhostReplay(course: key, score: 500, completed: true, recordedAt: Date(), samples: simple.samples))
        expect(profile.matchingGhost(for: key)?.completed == true, "A completed run outranks an incomplete attempt")
        for seed in 100...120 {
            profile.recordGhost(GhostReplay(course: GhostCourseKey(mode: .endless, expert: false, seed: UInt64(seed), startWorld: 0), score: seed, completed: false, recordedAt: Date(timeIntervalSince1970: Double(seed + 10_000)), samples: simple.samples))
        }
        expect(profile.personalGhosts.count == 8, "Profile retains only eight bounded personal courses")
        var invalid = key; invalid.revision = 0
        profile.recordGhost(GhostReplay(course: invalid, score: 999, completed: true, recordedAt: Date(), samples: simple.samples))
        expect(profile.personalGhosts.allSatisfy { $0.course.isValid }, "Old generator revisions cannot enter a new race")
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.personalGhosts.count == 8 && restored.personalGhosts == profile.personalGhosts, "Bounded personal ghosts round-trip exactly")
        let restoredRecorder = try JSONDecoder().decode(GhostRecorder.self, from: JSONEncoder().encode(recorder))
        expect(restoredRecorder.samples == recorder.samples && restoredRecorder.sampleInterval == recorder.sampleInterval, "Checkpoint recording resumes with its original cadence")
    }

    private static func testDailyOdyssey() {
        var profile = PlayerProfile()
        profile.recordDailyOdyssey(score: 500, day: "2026-10-04")
        profile.recordDailyOdyssey(score: 100, day: "2026-10-04")
        expect(profile.dailyOdysseyBest == 500, "Same-day Odyssey records only improve")
        profile.recordDailyOdyssey(score: 50, day: "2026-10-05")
        expect(profile.dailyOdysseyBest == 50 && profile.dailyOdysseyDate == "2026-10-05", "A new daily route gets a fresh record")
        profile.recordDailyOdyssey(score: 999, day: "2026-10-04")
        profile.recordDailyOdyssey(score: 999, day: "not-a-day")
        expect(profile.dailyOdysseyBest == 50 && profile.dailyOdysseyDate == "2026-10-05", "Stale or malformed dates cannot overwrite today's target")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ description: String,
                               file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), description, file: file, line: line)
        checks += 1
    }

    private static func testPurchases() {
        var profile = PlayerProfile()
        expect(!profile.buyBoards(), "Cannot buy boards without coins")
        expect(!profile.buyKeys(), "Cannot buy keys without coins")
        expect(!profile.purchaseCharacter("sana"), "Cannot overdraw for a character")
        expect(!profile.purchaseBoard("mint"), "Cannot overdraw for a board skin")
        expect(!profile.purchaseUpgrade(.jetpack), "Cannot overdraw for an upgrade")
        expect(profile.coins == 0, "Failed purchases do not change balance")
        expect(!profile.purchaseCharacter("unknown"), "Unknown character is rejected")
        expect(!profile.purchaseBoard("unknown"), "Unknown board is rejected")
        profile.coins = 750
        expect(profile.purchaseCharacter("sana"), "Can spend the exact character price")
        expect(profile.coins == 0 && profile.selectedCharacter == "sana", "Character unlock equips and charges once")
        expect(!profile.purchaseCharacter("sana"), "Owned character cannot be charged again")
        expect(profile.unlockedCharacters.filter { $0 == "sana" }.count == 1, "Character is not duplicated")
        profile.coins = 900
        expect(profile.purchaseBoard("mint"), "Can purchase a board skin")
        expect(profile.coins == 0 && profile.selectedBoard == "mint", "Board skin unlock equips and charges once")
        expect(!profile.purchaseBoard("mint"), "Owned board skin cannot be charged again")
        profile.coins = 150
        expect(profile.buyBoards(), "Board bundle can use exact balance")
        expect(profile.coins == 0 && profile.boards == 6, "Bundle grants exactly three consumables")
        profile.coins = 250
        expect(profile.buyKeys(), "Key can use exact balance")
        expect(profile.coins == 0 && profile.keys == 4, "Key purchase cannot overdraw")
        profile.coins = 1_000
        profile.boards = 1_000_000
        profile.keys = 1_000_000
        expect(!profile.buyBoards() && !profile.buyKeys(), "Full inventories reject purchases")
        expect(profile.coins == 1_000, "Inventory cap does not charge the player")
    }

    private static func testUpgradeCaps() {
        var profile = PlayerProfile()
        profile.coins = 100_000
        for power in PowerUp.allCases {
            let initialDuration = profile.powerUpDuration(power)
            for level in 0..<PlayerProfile.maximumUpgradeLevel {
                let cost = profile.upgradeCost(power)
                let before = profile.coins
                expect(cost > 0 && profile.purchaseUpgrade(power), "Upgrade \(power) level \(level) is purchasable")
                expect(profile.coins == before - cost, "Upgrade charges its displayed price")
            }
            let before = profile.coins
            expect(profile.upgradeCost(power) == 0 && !profile.purchaseUpgrade(power), "Maximum upgrade cannot be purchased again")
            expect(profile.coins == before, "Maximum upgrade never charges")
            expect(profile.powerUpDuration(power) == initialDuration + 10, "Five upgrades extend duration by ten seconds")
        }
        profile.missionTier = 500
        expect(profile.baseMultiplier == 30, "Permanent multiplier caps at thirty")
    }

    private static func makeCompletedRun() -> RunnerSimulation {
        var run = RunnerSimulation()
        run.start(seed: 123, boards: 3)
        var pickups = (0..<60).map {
            TrackEntity(id: $0, kind: .coin, lane: 0, z: 0.5, y: 0.9, length: 0.3)
        }
        pickups.append(TrackEntity(id: 60, kind: .key, lane: 0, z: 0.5, y: 0.9, length: 0.3))
        run.replaceTrackForTesting(pickups)
        run.update(dt: 0.03)
        run.act(.board)
        for _ in 0..<12 { run.act(.jump); run.update(dt: 1) }
        run.act(.roll)
        run.update(dt: 1)
        run.update(dt: 60)
        run.update(dt: 30)
        run.finish()
        expect(run.coins == 60 && run.keys == 1, "Fixture collects real simulation pickups")
        expect(run.jumps == 12 && run.rolls == 1 && run.boardsUsed == 1, "Fixture uses real simulation actions")
        expect(run.distance >= 1_200 && run.score > 0, "Fixture completes a scored run")
        return run
    }

    private static func testRunAccounting(_ run: RunnerSimulation) {
        var profile = PlayerProfile()
        profile.recordRun(run)
        expect(profile.coins == 60 && profile.keys == 4, "Run pickups enter the wallet")
        expect(profile.boards == 2, "Used boards are consumed once when recording the run")
        expect(profile.totalCoins == 60 && profile.totalRuns == 1, "Lifetime collection and runs are recorded")
        expect(profile.totalJumps == 12 && profile.totalRolls == 1, "Lifetime actions are recorded")
        expect(profile.bestScore == run.score && profile.totalDistance == run.distance, "Score and distance are recorded")
        expect(profile.recentScores == [run.score], "Recent scores start with the completed run")
        profile.boards = 0
        profile.coins = 1_000_000_000
        profile.keys = 1_000_000
        profile.totalCoins = 1_000_000_000
        profile.totalRuns = 1_000_000_000
        for _ in 0..<12 { profile.recordRun(run) }
        expect(profile.boards == 0, "Recording consumed boards cannot create a negative inventory")
        expect(profile.coins == 1_000_000_000 && profile.keys == 1_000_000, "Wallet caps do not overflow")
        expect(profile.totalCoins == 1_000_000_000 && profile.totalRuns == 1_000_000_000, "Lifetime counters saturate safely")
        expect(profile.recentScores.count == 10, "Only the ten latest scores are retained")
    }

    private static func testMissions(_ run: RunnerSimulation) {
        var profile = PlayerProfile()
        expect(profile.claimMission(profile.missions[0].id) == 0, "Incomplete mission cannot pay out")
        expect(profile.claimMission("invented") == 0, "Unknown mission cannot pay out")
        profile.recordRun(run)
        let missions = profile.missions
        expect(missions.count == 3 && missions.allSatisfy(\.complete), "Run completes first mission set")
        for (index, mission) in missions.enumerated() {
            let before = profile.coins
            expect(profile.claimMission(mission.id) == mission.reward, "Completed mission pays its displayed reward")
            expect(profile.coins == before + mission.reward, "Reward enters wallet exactly once")
            expect(profile.claimMission(mission.id) == 0, "Duplicate mission claim is rejected")
            expect(profile.coins == before + mission.reward, "Duplicate claim cannot change balance")
            if index < 2 { expect(profile.missionTier == 0, "Tier advances only after all three claims") }
        }
        expect(profile.missionTier == 1 && profile.baseMultiplier == 2, "Three claims increase permanent multiplier")
        expect(Set(profile.missions.map(\.id)).isDisjoint(with: missions.map(\.id)), "Next tier has distinct mission IDs")
        expect(profile.claimMission(missions[0].id) == 0, "Previous tier cannot be claimed again")
        expect(profile.missions[2].progress == profile.totalRolls, "Second tier tracks rolls")
    }

    private static func testDailyRewards() {
        var profile = PlayerProfile()
        let utc = ISO8601DateFormatter()
        let beforeMidnight = utc.date(from: "2026-10-04T23:59:59Z")!
        let afterMidnight = utc.date(from: "2026-10-05T00:00:00Z")!
        expect(profile.canClaimDaily(now: beforeMidnight), "New profile can claim daily gift")
        expect(profile.claimDaily(now: beforeMidnight) == 100, "First daily reward is one hundred coins")
        expect(!profile.canClaimDaily(now: beforeMidnight) && profile.claimDaily(now: beforeMidnight) == 0, "Same UTC day cannot pay twice")
        expect(profile.claimDaily(now: beforeMidnight.addingTimeInterval(-86_400)) == 0, "Backdating cannot reclaim gifts")
        expect(profile.claimDaily(now: afterMidnight) == 125 && profile.dailyStreak == 2, "UTC midnight advances streak after one second")
        for day in 1...8 { _ = profile.claimDaily(now: afterMidnight.addingTimeInterval(Double(day) * 86_400)) }
        expect(profile.dailyStreak == 10, "Consecutive UTC days retain streak")
        expect(profile.claimDaily(now: afterMidnight.addingTimeInterval(9 * 86_400)) == 250, "Streak reward caps at two hundred fifty")
        expect(profile.claimDaily(now: afterMidnight.addingTimeInterval(11 * 86_400)) == 100 && profile.dailyStreak == 1, "Missing a UTC day restarts streak")
    }

    private static func testDailyChallenge() {
        var profile = PlayerProfile()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        profile.recordDailyChallenge(score: 100, now: day)
        profile.recordDailyChallenge(score: 90, now: day)
        expect(profile.dailyChallengeBest == 100, "Lower challenge score cannot replace daily best")
        profile.recordDailyChallenge(score: 120, now: day)
        expect(profile.dailyChallengeBest == 120, "Higher challenge score replaces daily best")
        expect(profile.dailyBest(now: day) == 120, "Current daily best is displayed")
        expect(profile.dailyBest(now: day.addingTimeInterval(86_400)) == 0, "Yesterday's score is not displayed as today's best")
        profile.recordDailyChallenge(score: 20, now: day.addingTimeInterval(86_400))
        expect(profile.dailyChallengeBest == 20, "Next day starts an independent daily best")
    }

    private static func testMigrationAndCorruption() throws {
        let decoder = JSONDecoder()
        let oldSave = try decoder.decode(PlayerProfile.self, from: Data("{}".utf8))
        expect(oldSave.boards == 3 && oldSave.keys == 3 && oldSave.soundEnabled, "Missing fields retain starting defaults")
        let damaged = Data(#"{"coins":-1,"keys":"oops","boards":9223372036854775807,"selectedCharacter":"missing","unlockedCharacters":["missing","sana","sana"],"upgradeLevels":{"magnet":99,"fake":5},"missionTier":9223372036854775807,"lastDailyClaim":"tomorrow","dailyChallengeDate":"2026-99-99","dailyChallengeBest":55,"recentScores":[-10,100]}"#.utf8)
        let healed = try decoder.decode(PlayerProfile.self, from: damaged)
        expect(healed.coins == 0 && healed.keys == 3 && healed.boards == 1_000_000, "Negative, wrong-type and excessive fields recover")
        expect(healed.selectedCharacter == "milo" && healed.unlockedCharacters == ["milo", "sana"], "Unknown and duplicate character IDs recover")
        expect(healed.upgradeLevels["magnet"] == 5 && healed.upgradeLevels["fake"] == nil, "Upgrade catalog and cap are enforced on load")
        expect(healed.baseMultiplier == 30 && healed.missionTier == 10_000, "Corrupt tier is bounded without overflow")
        expect(healed.lastDailyClaim.isEmpty && healed.dailyChallengeDate.isEmpty && healed.dailyChallengeBest == 0, "Invalid dates recover")
        expect(healed.recentScores == [0, 100] && healed.bestScore == 100, "Recent scores clamp and preserve highest score")
        expect(healed.modeBestScore(mode: .endless) == 100, "Legacy best migrates to the standard endless record")
        expect(healed.modeBestScore(mode: .jetSki) == 0 && healed.modeBestScore(mode: .endless, expert: true) == 0, "Legacy scores do not invent new course records")
    }

    private static func testModeRecords() throws {
        var profile = PlayerProfile()
        for mode in [RunMode.endless, .harborSprint, .jetSki] {
            for expert in [false, true] {
                var run = RunnerSimulation()
                run.start(seed: 143, mode: mode, expert: expert)
                run.replaceTrackForTesting([])
                run.update(dt: expert ? 2 : 1)
                run.finish()
                profile.recordRun(run)
                expect(profile.modeBestScore(mode: mode, expert: expert) == run.score, "Every course/difficulty stores its own score")
            }
        }
        expect(profile.modeRecords.count == 6 && profile.totalRuns == 6, "Six course/difficulty records remain independent")
        expect(profile.bestScore == profile.modeRecords.values.max(), "Aggregate best remains the highest course score")
        profile.selectedMode = .jetSki
        profile.selectedExpert = true
        profile.modeRecords["unknown.expert"] = 55
        profile.modeRecords["\(RunMode.harborSprint.rawValue).standard"] = -10
        profile.bestCombo = -1
        profile.totalNearMisses = Int.max
        let restored = try JSONDecoder().decode(PlayerProfile.self, from: JSONEncoder().encode(profile))
        expect(restored.selectedMode == .jetSki && restored.selectedExpert, "Mode and difficulty preferences survive a save")
        expect(restored.modeRecords["unknown.expert"] == nil, "Unknown course records are discarded")
        expect(restored.modeBestScore(mode: .harborSprint) == 0, "Negative course records recover safely")
        expect(restored.bestCombo == 0 && restored.totalNearMisses == 1_000_000_000, "Skill counters sanitize with the other profile statistics")
        let legacy = try JSONDecoder().decode(PlayerProfile.self, from: Data(#"{"bestScore":420,"recentScores":[100,300]}"#.utf8))
        expect(legacy.modeBestScore(mode: .endless) == 420 && legacy.bestScore == 420, "Existing player records remain available after migration")
    }

    private static func testSaveReload() throws {
        let memory = ProfileMemoryDefaults()
        var profile = PlayerProfile()
        profile.coins = 5_000
        _ = profile.purchaseCharacter("rio")
        _ = profile.purchaseUpgrade(.jetpack)
        profile.hapticsEnabled = false
        profile.tutorialCompleted = true
        ProfileStore.save(profile, defaults: memory)
        let restored = ProfileStore.load(defaults: memory)
        expect(restored.coins == profile.coins && restored.selectedCharacter == "rio", "Wallet and selection survive in-memory save")
        expect(restored.upgradeLevels["jetpack"] == 1 && !restored.hapticsEnabled && restored.tutorialCompleted, "Upgrades and preferences survive reload")
        expect(memory.storage.count == 1, "Persistence uses a single versioned save record")
        let saveKey = try requireValue(memory.storage.keys.first)
        memory.storage[saveKey] = Data("not valid JSON".utf8)
        expect(ProfileStore.load(defaults: memory).keys == 3, "Unreadable save safely returns default profile")
        memory.storage[saveKey] = Data("[]".utf8)
        expect(ProfileStore.load(defaults: memory).boards == 3, "Wrong root type safely returns default profile")
    }

    private static func requireValue<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "ProfileTests", code: 1) }
        return value
    }
}
