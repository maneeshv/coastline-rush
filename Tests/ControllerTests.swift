import Foundation
import Combine

// Run from the workspace root:
// swiftc -swift-version 5 -module-cache-path work/SwiftModuleCache \
// outputs/CoastlineRush/Sources/{RunnerSimulation,PlayerProfile,RunCheckpoint,GameController}.swift \
// outputs/CoastlineRush/Tests/ControllerTests.swift -o work/controller-tests

// These lightweight presentation substitutes let the production controller and
// persistence run in an isolated command-line test without creating an app window.
final class CoastalWorld {
    var reducedMotion = false
    var highContrastCues = false
    var previewMode: RunMode = .endless
    var previewStage: WorldStage = .harbor
    private(set) var updates = 0
    func update(simulation: RunnerSimulation, character: String, board: String, time: Double) { updates += 1 }
    func applyQuality(_ quality: RenderQuality) {}
    func updateGhost(sample: GhostSample?) {}
}
final class GameAudio {
    enum Effect { case coin, jump, slide, power, crash, shield, start, portal, arrival, relic, warningJump, warningSlide, warningDodge }
    func setEnabled(_ value: Bool) {}
    func setSoundscape(mode: RunMode, world: WorldStage) {}
    func setVehicleState(speed: Double, active: Bool, boosting: Bool) {}
    func setMusicPlaying(_ value: Bool) {}
    func play(_ effect: Effect) {}
}

final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    private(set) var checkpoints: [Data] = []
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
        if defaultName == "coastlineRush.controller.v1", let data = value as? Data { checkpoints.append(data) }
    }
}

@main
struct ControllerTests {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
    static func entity(_ kind: EntityKind, id: Int = 1, z: Double = 0) -> TrackEntity {
        TrackEntity(id: id, kind: kind, lane: 0, z: z, y: 0.9, length: 0.8)
    }
    static func controller(_ defaults: UserDefaults) -> GameController {
        let isFresh = defaults.data(forKey: "coastlineRush.controller.v1") == nil
        let game = GameController(defaults: defaults, startsTimer: false)
        game.dismissTutorial()
        if isFresh { game.selectMode(.endless) }
        return game
    }
    static func crash(_ controller: GameController) {
        controller.run.replaceTrackForTesting([entity(.barrier, z: 5)])
        controller.run.update(dt: 1)
    }

    static func main() throws {
        let cases: [(String, () throws -> Void)] = [
            ("crash replay stays bounded and cannot change game or wallet", {
                let game = controller(MemoryDefaults())
                game.start()
                for _ in 0..<180 { game.run.replaceTrackForTesting([]); game.advance(dt: 1.0 / 30) }
                game.run.replaceTrackForTesting([entity(.tram, z: 1)])
                game.advance(dt: 0.1)
                try expect(game.run.phase == .crashed && game.replayAvailable, "Crash did not freeze a replay")
                try expect(game.replayFrameCount <= 48 && game.replayDuration <= 3.15, "Replay grew without bound")
                let runData = try JSONEncoder().encode(game.run)
                let coins = game.profile.coins
                game.startCrashReplay()
                game.seekCrashReplay(0.5)
                for _ in 0..<120 { game.advance(dt: 1.0 / 30) }
                try expect(game.isReplaying && game.replayProgress == 1 && !game.shouldAnimateScene, "Replay did not stop at crash frame")
                let before = try JSONSerialization.jsonObject(with: runData) as! NSDictionary
                let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(game.run)) as! NSDictionary
                try expect(before == after && game.profile.coins == coins, "Playback mutated authoritative run or wallet")
                game.seekCrashReplay(-5)
                try expect(game.replayProgress == 0 && game.shouldAnimateScene, "Replay cannot scrub backwards")
                game.stopCrashReplay()
                try expect(game.run.phase == .crashed && !game.isReplaying, "Closing replay changed crash state")
            }),
            ("practice and accessibility settings survive without spending rewards", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                let coins = game.profile.coins, keys = game.profile.keys, boards = game.profile.boards
                game.setReducedMotion(true); game.setHighContrastCues(true)
                game.setExpeditionStyle(.endless)
                game.startPractice(stage: .mars)
                try expect(game.run.isPractice && game.run.worldStage == .mars, "Practice did not select Mars")
                game.perform(.board)
                game.run.replaceTrackForTesting([entity(.coin), entity(.key, id: 2)])
                game.advance(dt: 0.05)
                game.finish()
                try expect(game.profile.coins == coins && game.profile.keys == keys && game.profile.boards == boards, "Practice altered wallet")
                try expect(!game.achievedPersonalBest && game.profile.personalGhosts.isEmpty, "Practice created a record")
                let restored = controller(defaults)
                try expect(restored.selectedExpeditionStyle == .endless && restored.world.reducedMotion && restored.world.highContrastCues, "Settings were not restored")
                game.setReducedMotion(false); game.setSystemReducedMotion(true)
                try expect(game.world.reducedMotion, "OS motion preference was ignored")
            }),
            ("diagnostics describe measured callback data accurately", {
                var diagnostics = RunDiagnostics()
                for i in 0..<1000 { diagnostics.recordInterval(i % 20 == 0 ? 0.04 : 1.0 / 60) }
                diagnostics.markInput(at: 1); diagnostics.beginTick(at: 1.012); diagnostics.endTick(milliseconds: 4)
                let report = diagnostics.report(quality: "balanced", thermal: "nominal", replayFrames: 48)
                try expect(report.contains("1000 measured") && report.contains("36 / 720"), "Diagnostics window did not stay bounded")
                try expect(report.contains("12.0 ms") && report.contains("not GPU presentation"), "Diagnostics mislabeled timing")
            }),
            ("artifact choices pause time and optional replay corruption preserves a run", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.odyssey); game.start()
                game.run.replaceTrackForTesting([entity(.relic)])
                game.advance(dt: 0.1)
                game.showPanel(.loadout)
                let distance = game.run.distance
                game.advance(dt: 3)
                try expect(game.run.phase == .paused && game.run.distance == distance, "Choosing equipment consumed gameplay time")
                game.equipArtifact(.phaseStep)
                try expect(game.run.selectedAbility == .phaseStep, "Paused safe-zone loadout did not equip")
                game.resume(); game.activateArtifact()
                try expect(game.run.abilityCharges == 0 && game.run.isAbilityActive, "Artifact charge/activation mismatch")
                game.pause()
                let restored = controller(defaults)
                try expect(restored.run.isAbilityActive && restored.run.abilityCharges == 0, "Restore duplicated an ability charge")
                let data = defaults.data(forKey: "coastlineRush.controller.v1")!
                var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                var session = object["session"] as! [String: Any]
                session["ghostRecorder"] = "damaged optional replay"
                object["session"] = session
                let decoded = try JSONDecoder().decode(ControllerSave.self, from: JSONSerialization.data(withJSONObject: object))
                try expect(decoded.session?.run.distance == restored.run.distance, "Bad optional replay discarded active run")
            }),
            ("ghost race recreates the recorded course and survives a checkpoint", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.start()
                let seed = game.run.runSeed
                game.run.replaceTrackForTesting([])
                for _ in 0..<20 { game.advance(dt: 0.1) }
                game.finish()
                try expect(game.profile.personalGhosts.count == 1, "Completed attempt was not recorded")
                game.racePersonalGhost()
                try expect(game.run.runSeed == seed && game.ghostReplay?.course.seed == seed, "Ghost race changed course seed")
                game.run.replaceTrackForTesting([])
                game.advance(dt: 0.5)
                try expect(game.ghostSample != nil, "Compatible ghost did not play")
                game.pause()
                let restored = controller(defaults)
                try expect(restored.run.phase == .paused && restored.ghostReplay?.course.seed == seed, "Checkpoint lost ghost opponent")
                restored.resume()
                restored.run.replaceTrackForTesting([])
                restored.advance(dt: 0.5)
                restored.finish()
                try expect(restored.profile.personalGhosts.count == 1, "Same course duplicated instead of keeping best")
                let final = RunCheckpointStore.load(defaults: defaults)
                try expect(final?.session == nil, "Settled ghost session persisted")
            }),
            ("render cadence samples HUD and paused worlds stop updating", {
                let game = GameController(defaults: MemoryDefaults(), startsTimer: true)
                game.dismissTutorial(); game.selectMode(.endless); game.start()
                game.run.replaceTrackForTesting([])
                var changes = 0
                let token = game.objectWillChange.sink { changes += 1 }
                for frame in 0...60 { game.renderFrame(at: 100 + Double(frame) / 60) }
                try expect(game.run.distance > 10, "Renderer callbacks did not advance game")
                try expect(changes >= 10 && changes <= 25, "HUD was not throttled: \(changes)")
                game.pause()
                let stopped = game.run.distance
                let updates = game.world.updates
                for frame in 61...90 { game.renderFrame(at: 100 + Double(frame) / 60); game.advance(dt: 0.016) }
                try expect(game.run.distance == stopped && game.world.updates == updates, "Paused game updated scenery or physics")
                game.resume()
                game.renderFrame(at: 200)
                try expect(game.run.distance == stopped, "Resume consumed wall clock pause")
                game.renderFrame(at: 200.016)
                try expect(game.run.distance > stopped, "Resume failed to restart render cadence")
                withExtendedLifetime(token) {}
            }),
            ("v4 preferences persist and daily Odyssey has stable rules", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.setGraphicsQuality(.performance); game.setPortalAssist(false)
                game.setSwipeSensitivity(9); game.setGhostEnabled(false); game.equipArtifact(.airDash)
                let restored = controller(defaults)
                try expect(restored.profile.graphicsQuality == .performance && !restored.profile.portalAssist && !restored.profile.ghostEnabled, "Settings lost")
                try expect(restored.profile.swipeSensitivity == 1.5 && restored.profile.selectedArtifact == .airDash, "Input/loadout settings lost")
                restored.start(daily: true)
                let seed = restored.run.runSeed
                restored.finish(); restored.start(daily: true)
                try expect(restored.run.mode == .odyssey && !restored.run.expert && restored.run.stageIndex == 0 && restored.run.runSeed == seed, "Daily seed/rules drifted")
            }),
            ("new profiles feature Odyssey while existing course preferences survive", {
                let defaults = MemoryDefaults()
                let fresh = GameController(defaults: defaults, startsTimer: false)
                try expect(fresh.selectedMode == .odyssey && fresh.selectedWorld == 0, "Fresh profile did not feature the expedition")
                fresh.selectMode(.jetSki)
                let restored = GameController(defaults: defaults, startsTimer: false)
                try expect(restored.selectedMode == .jetSki, "Existing mode choice was overwritten by Odyssey")
                restored.selectWorld(3)
                try expect(restored.selectedWorld == 0 && restored.selectedMode == .jetSki, "Locked world selection bypassed progression")
            }),
            ("portal and relic progress checkpoint without settling the run", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.odyssey)
                game.setPortalAssist(false)
                game.start()
                game.run.replaceTrackForTesting([entity(.relic), entity(.coin, id: 2, z: 1)])
                game.advance(dt: 0.1)
                try expect(game.profile.collectedRelicWorlds.contains(.harbor), "Relic collection was not saved immediately")
                try expect(game.profile.coins == 0 && game.profile.totalRuns == 0, "Relic checkpoint settled the wallet early")
                for _ in 0..<Int(ceil(game.run.stageLength / game.run.speed / 0.25) + 20) where !game.run.portalReady { game.advance(dt: 0.25) }
                try expect(game.run.portalReady, "Fixture never reached the first portal")
                game.perform(.jump)
                let crossing = controller(defaults)
                try expect(crossing.run.isPortalTransitioning && crossing.run.phase == .paused, "Portal entry did not checkpoint paused")
                crossing.resume()
                crossing.advance(dt: 2)
                try expect(crossing.run.stageIndex == 1 && crossing.profile.highestUnlockedWorld == 1, "Portal arrival did not unlock the next world")
                try expect(crossing.profile.worldBestDistance(.harbor) == WorldStage.harbor.length, "Cleared-world record was not completed")
                let arrived = controller(defaults)
                try expect(arrived.run.stageIndex == 1 && arrived.profile.highestUnlockedWorld == 1, "Arrival was not saved immediately")
                arrived.finish(); arrived.finish()
                try expect(arrived.profile.coins == 1 && arrived.profile.totalRuns == 1 && arrived.profile.collectedRelicWorlds.count == 1,
                           "Journey checkpoints duplicated or lost settlement")
                arrived.returnToMenu(); arrived.selectWorld(1); arrived.start()
                try expect(arrived.run.stageIndex == 1, "Unlocked destination could not be used as a starting point")
            }),
            ("six-world victories settle once and later-world practice is not a full expedition", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.odyssey); game.setPortalAssist(false); game.start()
                for stage in WorldStage.allCases {
                    game.run.replaceTrackForTesting([entity(.coin)])
                    for _ in 0..<Int(ceil(game.run.stageLength / game.run.speed / 0.25) + 20) where !game.run.portalReady { game.advance(dt: 0.25) }
                    try expect(game.run.portalReady, "Route fixture failed to reach a gateway")
                    game.perform(.jump)
                    let writesBeforeArrival = defaults.checkpoints.count
                    game.advance(dt: 2)
                    if stage == .forge {
                        try expect(defaults.checkpoints.count == writesBeforeArrival + 1,
                                   "Final portal wrote an intermediate, unsettled save")
                        let finalSave = try JSONDecoder().decode(ControllerSave.self, from: defaults.checkpoints.last!)
                        try expect(finalSave.session == nil && finalSave.profile.totalRuns == 1 && finalSave.profile.coins == 6 && finalSave.profile.completedExpeditions == 1,
                                   "Final portal did not atomically bank coins, expedition award and run removal")
                    }
                }
                try expect(game.run.journeyComplete && game.run.phase == .finished && game.profile.completedExpeditions == 1,
                           "Six-world victory did not settle the expedition")
                game.advance(dt: 1); game.finish()
                try expect(game.profile.completedExpeditions == 1 && game.profile.totalRuns == 1, "Victory banked more than once")
                game.returnToMenu(); game.selectWorld(5); game.start()
                game.run.replaceTrackForTesting([])
                for _ in 0..<Int(ceil(game.run.stageLength / game.run.speed / 0.25) + 20) where !game.run.portalReady { game.advance(dt: 0.25) }
                game.perform(.jump); game.advance(dt: 2)
                try expect(game.run.journeyComplete && game.run.stagesCleared == 1 && game.profile.completedExpeditions == 1,
                           "Late-world practice was counted as a full expedition")
            }),
            ("new players get a stopped clock while reading the first-run briefing", {
                let game = GameController(defaults: MemoryDefaults(), startsTimer: false)
                game.selectMode(.jetSki)
                game.start()
                try expect(game.run.phase == .paused, "First-run briefing started the race clock")
                game.resume()
                try expect(game.run.phase == .paused, "Keyboard resume bypassed the first-run briefing")
                game.advance(dt: 5)
                try expect(game.run.distance == 0 && game.run.timeRemaining == 60, "Reading instructions consumed race time")
                game.dismissTutorial()
                game.resume()
                game.advance(dt: 1)
                try expect(game.run.phase == .running && game.run.distance > 0, "Briefing acknowledgement did not start the race")
            }),
            ("course preferences persist and daily challenge keeps its fixed rules", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.jetSki)
                game.toggleExpert()
                let restored = controller(defaults)
                try expect(restored.selectedMode == .jetSki && restored.selectedExpert, "Mode/difficulty selection was not saved")
                restored.start(daily: true)
                try expect(restored.run.mode == .odyssey && !restored.run.expert, "Daily course used the selected mode/difficulty")
                restored.run.replaceTrackForTesting([])
                restored.advance(dt: 1)
                restored.pause()
                let daily = controller(defaults)
                try expect(daily.run.mode == .odyssey && !daily.run.expert && daily.isDailyRun, "Daily checkpoint lost its fixed rules")
                try expect(daily.selectedMode == .jetSki && daily.selectedExpert, "Daily course overwrote the player's normal selection")
                daily.returnToMenu()
                daily.start()
                try expect(daily.run.mode == .jetSki && daily.run.expert, "Normal run did not resume selected course/difficulty")
                daily.pause()
                let race = controller(defaults)
                try expect(race.run.phase == .paused && race.run.mode == .jetSki && race.run.expert, "Active course/difficulty was not checkpointed")
            }),
            ("a record is measured against its own course and difficulty", {
                let game = controller(MemoryDefaults())
                game.start()
                game.run.replaceTrackForTesting([])
                game.advance(dt: 10)
                game.finish()
                let aggregate = game.profile.bestScore
                game.selectMode(.jetSki)
                game.start()
                game.run.replaceTrackForTesting([])
                game.advance(dt: 1)
                game.finish()
                try expect(game.achievedPersonalBest, "A first water-course record was hidden by an endless record")
                try expect(game.profile.bestScore == aggregate, "Lower course record replaced the aggregate best")
                try expect(game.profile.modeBestScore(mode: .jetSki) == game.run.score, "Water-course record was not recorded")
                game.toggleExpert()
                game.start()
                game.run.replaceTrackForTesting([])
                game.advance(dt: 0.5)
                game.finish()
                try expect(game.achievedPersonalBest && game.profile.modeBestScore(mode: .jetSki, expert: true) == game.run.score,
                           "Expert records were merged with standard records")
            }),
            ("water boost never charges a board consumable", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.jetSki)
                game.profile.boards = 0
                game.start()
                game.run.replaceTrackForTesting([])
                game.perform(.board)
                try expect(game.run.isBoosting, "Initial boost charge could not activate a boost")
                try expect(game.run.boardsUsed == 0 && game.run.availableBoards == 0, "Water boost changed board inventory")
                try expect(!(game.toast ?? "").contains("Out of boards"), "Water boost incorrectly asked the player to buy boards")
                game.advance(dt: 1)
                game.pause()
                let restored = controller(defaults)
                restored.finish()
                try expect(restored.profile.boards == 0 && restored.profile.totalRuns == 1, "Water course settlement changed inventory or duplicated the run")
            }),
            ("course completion banks rewards once without a finish button", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.harborSprint)
                game.start()
                var course = (0..<8).map { index in
                    TrackEntity(id: index + 1, kind: .checkpoint, lane: 0, z: Double(index * 180 + 10), y: 1, length: 0.5)
                }
                course.append(entity(.coin, id: 20, z: 1))
                course.append(entity(.key, id: 21, z: 2))
                game.run.replaceTrackForTesting(course)
                for _ in 0..<18 where game.run.phase == .running { game.advance(dt: 10) }
                try expect(game.run.phase == .finished && game.run.distance >= game.run.courseTarget, "Course never reached its finish line")
                try expect(game.profile.totalRuns == 1 && game.profile.coins == 1 && game.profile.keys == 4, "Automatic finish did not bank run rewards")
                try expect(game.profile.modeBestScore(mode: .harborSprint) == game.run.score, "Automatic finish did not record course score")
                try expect(game.profile.totalGatesCleared == game.run.gatesCleared && game.profile.bestCombo == game.run.bestCombo,
                           "Course skill statistics were not settled")
                try expect(RunCheckpointStore.load(defaults: defaults)?.session == nil, "Finished course remained as a restorable active run")
                game.advance(dt: 1)
                game.finish()
                game.returnToMenu()
                let restored = controller(defaults)
                try expect(restored.run.phase == .menu && restored.profile.totalRuns == 1 && restored.profile.keys == 4,
                           "Completed course was restored or banked again")
            }),
            ("race clock pauses and reviving an expired race preserves accounting", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.selectMode(.harborSprint)
                game.start()
                game.run.replaceTrackForTesting([])
                game.advance(dt: 5)
                game.pause()
                let remaining = game.run.timeRemaining
                game.advance(dt: 10)
                try expect(game.run.timeRemaining == remaining, "Pause consumed race time")
                let restored = controller(defaults)
                try expect(restored.run.timeRemaining == remaining, "Checkpoint changed the remaining race time")
                restored.resume()
                restored.advance(dt: 60)
                try expect(restored.run.phase == .crashed && restored.canRevive, "Expired race did not permit its one rescue")
                restored.revive()
                try expect(restored.run.phase == .running && restored.run.timeRemaining >= 15 && restored.profile.keys == 2,
                           "Revive did not grant recovery time and charge exactly one key")
                restored.finish()
                try expect(controller(defaults).profile.keys == 2, "Expired race charged the rescue key again at settlement")
            }),
            ("new personal best distinguishes records from ties", {
                let game = controller(MemoryDefaults())
                game.start()
                game.run.replaceTrackForTesting([])
                game.run.update(dt: 1)
                game.finish()
                try expect(game.achievedPersonalBest, "First score should set a record")
                let best = game.profile.bestScore
                game.start()
                game.run.replaceTrackForTesting([])
                game.run.update(dt: 1)
                game.finish()
                try expect(game.run.score == best && !game.achievedPersonalBest, "A tie should not announce a new record")
            }),
            ("simulation checkpoint preserves deterministic continuation", {
                var first = RunnerSimulation()
                first.start(seed: 127, durations: [.magnet: 12], boards: 4)
                first.replaceTrackForTesting([entity(.magnet)], generate: true)
                first.act(.board)
                first.update(dt: 0.1)
                first.act(.right)
                first.act(.jump)
                first.update(dt: 0.08)
                let encoded = try JSONEncoder().encode(first)
                var second = try JSONDecoder().decode(RunnerSimulation.self, from: encoded)
                for index in 0..<240 {
                    if index == 50 { first.act(.left); second.act(.left) }
                    if index == 130 { first.act(.jump); second.act(.jump) }
                    first.update(dt: 1.0 / 60.0)
                    second.update(dt: 1.0 / 60.0)
                }
                try expect(first.entities == second.entities, "Generator or entity state changed after decode")
                try expect(first.distance == second.distance && first.score == second.score, "Continuation changed score or distance")
                try expect(first.height == second.height && first.lateral == second.lateral, "Jump/lane physics did not survive decode")
                try expect(first.activePowerUps == second.activePowerUps && first.boardTime == second.boardTime, "Power timers changed")
            }),
            ("legacy profile migrates and authoritative envelope takes precedence", {
                let defaults = MemoryDefaults()
                var legacy = PlayerProfile()
                legacy.coins = 345
                ProfileStore.save(legacy, defaults: defaults)
                let game = controller(defaults)
                try expect(game.profile.coins == 345, "Legacy profile was not loaded")
                game.start()
                legacy.coins = 900
                ProfileStore.save(legacy, defaults: defaults)
                let restored = controller(defaults)
                try expect(restored.profile.coins == 345, "Legacy value overrode the authoritative envelope")
                try expect(restored.run.phase == .paused, "Running saves must restore paused")
            }),
            ("damaged transient checkpoint preserves the authoritative wallet", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.profile.coins = 825
                game.profile.selectedCharacter = "sana"
                game.profile.unlockedCharacters.append("sana")
                game.start()
                guard let data = defaults.data(forKey: "coastlineRush.controller.v1"),
                      var encoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw Failure(description: "Fixture did not create a saved checkpoint")
                }
                encoded["session"] = ["run": "damaged transient state"]
                defaults.set(try JSONSerialization.data(withJSONObject: encoded), forKey: "coastlineRush.controller.v1")
                let restored = controller(defaults)
                try expect(restored.run.phase == .menu && restored.profile.coins == 825 && restored.profile.selectedCharacter == "sana",
                           "Transient run corruption erased the saved profile")
            }),
            ("active run is checkpointed within five seconds", {
                let defaults = MemoryDefaults()
                let game = GameController(defaults: defaults)
                game.dismissTutorial()
                game.start()
                game.run.replaceTrackForTesting([])
                for frame in 0...330 { game.renderFrame(at: 100 + Double(frame) / 60) }
                let saved = RunCheckpointStore.load(defaults: defaults)?.session
                try expect((saved?.run.distance ?? 0) > 30, "Periodic checkpoint did not capture progress")
                game.setActive(false)
            }),
            ("background restore retains earned rewards and consumed boards", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.profile.coins = 100
                game.start()
                game.run.replaceTrackForTesting([entity(.coin), entity(.key, id: 2)])
                game.perform(.board)
                game.run.update(dt: 0.1)
                game.setActive(false)
                let restored = controller(defaults)
                try expect(restored.run.phase == .paused, "Backgrounded run did not restore paused")
                try expect(restored.run.coins == 1 && restored.run.keys == 1, "Unbanked rewards were lost")
                try expect(restored.run.availableBoards == 2 && restored.run.boardsUsed == 1, "Used board was restored incorrectly")
                restored.finish()
                restored.finish()
                restored.returnToMenu()
                let finished = controller(defaults)
                try expect(finished.run.phase == .menu, "Finished session was resurrected")
                try expect(finished.profile.coins == 101 && finished.profile.keys == 4, "Rewards were not credited exactly once")
                try expect(finished.profile.boards == 2 && finished.profile.totalRuns == 1, "Boards/run count were credited more than once")
            }),
            ("freshly collected key can revive and cannot be credited twice", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.profile.keys = 0
                game.start()
                game.run.replaceTrackForTesting([entity(.key)])
                game.run.update(dt: 0.1)
                crash(game)
                try expect(game.canRevive, "Collected key was unavailable for revival")
                game.revive()
                try expect(game.run.phase == .running && game.profile.keys == 0, "Revival did not consume the fresh key")
                let restored = controller(defaults)
                try expect(restored.run.phase == .paused, "Revived session was not saved")
                restored.resume()
                restored.run.replaceTrackForTesting([])
                restored.run.update(dt: 4)
                crash(restored)
                try expect(!restored.canRevive, "Relaunch bypassed the one-revive limit")
                restored.finish()
                let finished = controller(defaults)
                try expect(finished.profile.keys == 0 && finished.profile.totalRuns == 1, "Spent run key was credited again")
            }),
            ("banked rescue key spending and crashed state survive relaunch", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.start()
                crash(game)
                game.setActive(false)
                let crashed = controller(defaults)
                try expect(crashed.run.phase == .crashed && crashed.canRevive, "Crash recovery UI state was lost")
                crashed.revive()
                let revived = controller(defaults)
                try expect(revived.profile.keys == 2, "Spent banked key was restored")
                revived.finish()
                try expect(controller(defaults).profile.keys == 2, "Finishing subtracted the rescue key twice")
            }),
            ("paused shopping preserves run accounting across restarts", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.profile.coins = 500
                game.start()
                game.run.replaceTrackForTesting([entity(.coin)])
                game.perform(.board)
                game.run.update(dt: 0.1)
                game.pause()
                game.buyBoards()
                game.buyKeys()
                let restored = controller(defaults)
                try expect(restored.profile.coins == 100 && restored.profile.boards == 6 && restored.profile.keys == 4, "Shop transaction was lost")
                restored.start()
                try expect(restored.profile.coins == 101 && restored.profile.boards == 5 && restored.profile.totalRuns == 1, "Prior run was not settled once before restart")
                try expect(restored.run.availableBoards == 5, "Restart did not use updated inventory")
            }),
            ("daily run identity survives checkpoint and settlement", {
                let defaults = MemoryDefaults()
                let game = controller(defaults)
                game.start(daily: true)
                game.run.replaceTrackForTesting([])
                game.run.update(dt: 1)
                game.pause()
                let savedDate = RunCheckpointStore.load(defaults: defaults)?.session?.dailyRunDate
                let restored = controller(defaults)
                try expect(restored.isDailyRun && !(savedDate ?? "").isEmpty, "Daily identity was not restored")
                restored.finish()
                let finished = controller(defaults)
                try expect(finished.profile.dailyOdysseyDate == savedDate && finished.profile.dailyOdysseyBest > 0, "Daily score was not recorded under its starting date")
            })
        ]
        var failures: [String] = []
        for (name, body) in cases {
            do { try body(); print("PASS \(name)") }
            catch { failures.append("\(name): \(error)"); print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failures.count)/\(cases.count) controller/checkpoint tests passed")
        if !failures.isEmpty { throw Failure(description: failures.joined(separator: "\n")) }
    }
}
