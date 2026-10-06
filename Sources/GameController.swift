import Foundation
import Combine

#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum GamePanel: String, Identifiable {
    case missions, locker, upgrades, settings, help, scores, journey, loadout
    var id: String { rawValue }
}

/// Owns a run and commits its economy exactly once, even after a revive.
final class GameController: ObservableObject {
    // Hot simulation state is not a SwiftUI publisher. The HUD is sampled at
    // 20 Hz while the native scene follows the renderer's frame cadence.
    var run = RunnerSimulation()
    @Published var profile: PlayerProfile
    @Published var panel: GamePanel?
    @Published var toast: String?
    @Published var isDailyRun = false
    @Published var selectedMode: RunMode = .endless {
        didSet { profile.selectedMode = selectedMode; save(); refreshWorld() }
    }
    @Published var selectedExpert = false {
        didSet { profile.selectedExpert = selectedExpert; save() }
    }
    @Published private(set) var selectedWorld = 0
    @Published private(set) var selectedExpeditionStyle: ExpeditionStyle = .campaign
    @Published private(set) var isReplaying = false
    @Published private(set) var replayProgress = 0.0
    private var crashReplay = CrashReplayBuffer()
    private var diagnostics = RunDiagnostics()
    private var systemReducedMotion = false
    private var lastWarningID: Int?
    private var lastWarningTime = -Double.infinity
    var replayDuration: Double { crashReplay.duration }
    var replayAvailable: Bool { run.phase == .crashed && crashReplay.frames.count > 1 }
    var replayFrameCount: Int { crashReplay.frames.count }
    var performanceReport: String {
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return diagnostics.report(quality: effectiveQuality.rawValue, thermal: thermal, replayFrames: replayFrameCount)
    }
    var selectedStage: WorldStage { WorldStage.allCases[min(WorldStage.allCases.count - 1, max(0, selectedWorld))] }
    @Published private(set) var achievedPersonalBest = false
    let world = CoastalWorld()
    private let audio = GameAudio()
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastFrameTime: Double?
    private let usesLiveFrames: Bool
    private var hudElapsed = 0.0
    private var qualityElapsed = 0.0
    private(set) var effectiveQuality: RenderQuality = .balanced
    private var hasAppliedQuality = false
    var onRenderSettingsChanged: (() -> Void)?
    var shouldAnimateScene: Bool { appActive && panel == nil && (isReplaying ? replayProgress < 1 : (run.phase == .running || run.phase == .menu)) }
    var preferredFrameRate: Int { run.phase == .menu ? 30 : 60 }
    #if os(iOS)
    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let mediumFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)
    #endif
    private var worldTime = 0.0
    private var didRecord = false
    private var hasRevived = false
    private var spentRunKeys = 0
    private var appActive = true
    private let defaults: UserDefaults
    private var lastCheckpoint = ProcessInfo.processInfo.systemUptime
    private var checkpointElapsed = 0.0
    private var toastID = 0
    private var terminationObserver: NSObjectProtocol?
    // Capture the date when the daily run starts so midnight cannot change its identity.
    private var dailyRunDate = ""
    private var ghostRecorder = GhostRecorder()
    private var ghostCourse: GhostCourseKey?
    private(set) var ghostReplay: GhostReplay?
    private(set) var ghostSample: GhostSample?

    var canRevive: Bool { run.phase == .crashed && !run.isPractice && !hasRevived && (profile.keys > 0 || run.keys > spentRunKeys) }

    init(defaults: UserDefaults = .standard, startsTimer: Bool = true) {
        self.defaults = defaults
        self.usesLiveFrames = startsTimer
        let stored = RunCheckpointStore.load(defaults: defaults)
        profile = stored?.profile ?? ProfileStore.load(defaults: defaults)
        selectedMode = profile.selectedMode
        selectedExpert = profile.selectedExpert
        selectedWorld = profile.selectedWorld
        selectedExpeditionStyle = profile.selectedExpeditionStyle
        if let session = stored?.session,
           session.run.phase == .running || session.run.phase == .paused || session.run.phase == .crashed {
            run = session.run
            run.pause()
            hasRevived = session.hasRevived
            spentRunKeys = min(run.keys, max(0, session.spentRunKeys))
            isDailyRun = session.isDailyRun
            dailyRunDate = session.dailyRunDate
            ghostRecorder = session.ghostRecorder ?? GhostRecorder()
            ghostCourse = session.ghostCourse
            if let course = ghostCourse, course.isValid { ghostReplay = profile.matchingGhost(for: course) }
            if !isDailyRun {
                selectedMode = run.mode
                selectedExpert = run.expert
                profile.selectedMode = selectedMode
                profile.selectedExpert = selectedExpert
                if !run.isPractice { selectedExpeditionStyle = run.expeditionStyle }
            }
        }
        audio.setEnabled(profile.soundEnabled)
        world.reducedMotion = profile.reducedMotion || systemReducedMotion
        world.highContrastCues = profile.highContrastCues
        world.previewMode = selectedMode
        world.previewStage = selectedStage
        world.update(simulation: run, character: profile.selectedCharacter, board: profile.selectedBoard, time: 0)
        updateQuality()
        #if os(macOS)
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.save() }
        #endif
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func start(daily: Bool = false, replay: GhostReplay? = nil, practiceStage: Int? = nil) {
        stopCrashReplay()
        if run.phase == .running || run.phase == .paused || run.phase == .crashed { commitRun() }
        panel = nil
        isDailyRun = daily
        achievedPersonalBest = false
        dailyRunDate = Self.dayStamp()
        let seed = replay?.course.seed ?? (daily ? RunnerSimulation.dailyOdysseySeed(for: dailyRunDate) : UInt64.random(in: 1...UInt64.max))
        let durations = Dictionary(uniqueKeysWithValues: PowerUp.allCases.map { ($0, profile.powerUpDuration($0)) })
        run.start(seed: seed, baseMultiplier: profile.baseMultiplier, durations: durations, boards: practiceStage == nil ? profile.boards : max(3, profile.boards),
                  mode: replay?.course.mode ?? (daily || practiceStage != nil ? .odyssey : selectedMode), expert: replay?.course.expert ?? (daily ? false : selectedExpert),
                  startStage: practiceStage ?? replay?.course.startWorld ?? (daily || selectedMode != .odyssey ? 0 : min(profile.highestUnlockedWorld, selectedWorld)),
                  portalAssist: profile.portalAssist, dailyID: daily ? dailyRunDate : nil,
                  expeditionStyle: practiceStage != nil ? .practice : replay?.course.expeditionStyle ?? (daily ? .campaign : selectedExpeditionStyle),
                  replayPlan: replay?.course.decisionPlan)
        run.chooseAbility(replay?.course.artifact ?? profile.selectedArtifact)
        ghostRecorder = GhostRecorder()
        ghostCourse = run.mode == .odyssey && run.expeditionStyle != .campaign ? nil : replay?.course ?? GhostCourseKey(mode: run.mode, expert: run.expert, seed: run.runSeed, startWorld: run.startWorldIndex, expeditionStyle: run.expeditionStyle, decisionPlan: run.decisionPlan, artifact: run.mode == .odyssey ? run.selectedAbility : nil)
        ghostReplay = replay ?? ghostCourse.flatMap { profile.matchingGhost(for: $0) }
        crashReplay = CrashReplayBuffer()
        diagnostics = RunDiagnostics()
        lastWarningID = nil
        lastWarningTime = -Double.infinity
        crashReplay.append(run, worldTime: worldTime, force: true)
        ghostSample = nil
        recordGhostFrame(force: true)
        if !profile.tutorialCompleted { run.pause() }
        didRecord = false
        hasRevived = false
        spentRunKeys = 0
        lastTick = ProcessInfo.processInfo.systemUptime
        lastFrameTime = nil
        audio.setSoundscape(mode: run.mode, world: run.worldStage)
        audio.play(.start)
        audio.setMusicPlaying(profile.soundEnabled && appActive && run.phase == .running)
        save()
        refreshWorld()
        publishHUD()
    }

    func selectMode(_ mode: RunMode) { selectedMode = mode }
    func setExpeditionStyle(_ style: ExpeditionStyle) {
        guard style != .practice else { return }
        selectedExpeditionStyle = style; profile.selectedExpeditionStyle = style; save()
    }
    func startPractice(stage: WorldStage) {
        guard let index = WorldStage.allCases.firstIndex(of: stage) else { return }
        start(practiceStage: index)
    }
    func chooseRoute(_ route: BranchRoute) { run.chooseRoute(route); save(); publishHUD() }
    func choosePerk(_ perk: ExpeditionPerk) { run.choosePerk(perk); save(); publishHUD() }
    func startCrashReplay() {
        guard replayAvailable else { return }
        panel = nil; isReplaying = true; replayProgress = 0; lastFrameTime = nil
        audio.setMusicPlaying(false); refreshWorld(); publishHUD()
    }
    func seekCrashReplay(_ fraction: Double) {
        guard isReplaying, fraction.isFinite else { return }
        replayProgress = min(1, max(0, fraction)); refreshWorld(); publishHUD()
    }
    func stopCrashReplay() {
        guard isReplaying else { return }
        isReplaying = false; lastFrameTime = nil; refreshWorld(); publishHUD()
    }
    func setReducedMotion(_ enabled: Bool) { profile.reducedMotion = enabled; save(); refreshWorld(); publishHUD() }
    func setHighContrastCues(_ enabled: Bool) { profile.highContrastCues = enabled; save(); refreshWorld(); publishHUD() }
    func setSystemReducedMotion(_ enabled: Bool) { systemReducedMotion = enabled; refreshWorld() }
    func claimSkillChallenge(_ id: String) {
        let reward = profile.claimSkillChallenge(id)
        if reward > 0 { save(); audio.play(.power); notify("Skill challenge · +\(reward) coins") }
    }
    func selectWorld(_ index: Int) {
        guard run.phase == .menu, (0..<WorldStage.allCases.count).contains(index), index <= profile.highestUnlockedWorld else { return }
        selectedWorld = index
        profile.selectedWorld = index
        selectedMode = .odyssey
        save()
    }
    func toggleExpert() { selectedExpert.toggle() }

    func perform(_ action: RunnerAction) {
        guard run.phase == .running, panel == nil, !isReplaying else { return }
        diagnostics.markInput(at: ProcessInfo.processInfo.systemUptime)
        let previousJumps = run.jumps
        let previousRolls = run.rolls
        let previousLane = run.lane
        let previousBoards = run.boardsUsed
        let wasBoosting = run.isBoosting
        let wasTransitioning = run.isPortalTransitioning
        let previousCharges = run.abilityCharges
        run.act(action)
        if run.isPortalTransitioning && !wasTransitioning { audio.play(.portal); haptic(.heavy); save() }
        if run.jumps > previousJumps { audio.play(.jump); haptic(.light) }
        if run.rolls > previousRolls { audio.play(.slide); haptic(.light) }
        if run.lane != previousLane { haptic(.light) }
        if run.boardsUsed > previousBoards { audio.play(.power); haptic(.medium); notify("Board on · one crash covered"); save() }
        if case .board = action {
            if run.isWaterTraversal {
                if !wasBoosting && run.isBoosting { audio.play(.power); haptic(.medium) }
                else if !run.isBoosting { notify("Boost charging · clear gates to refill") }
            } else if previousBoards == run.boardsUsed, run.availableBoards == 0 {
                notify("Out of boards · restock at the harbor")
            }
        }
        if run.abilityCharges < previousCharges { audio.play(.power); haptic(.medium); save() }
        publishHUD()
    }

    func pause() { stopCrashReplay(); run.pause(); audio.setMusicPlaying(false); save(); lastFrameTime = nil; publishHUD() }
    func resume() { guard profile.tutorialCompleted else { return }; panel = nil; run.resume(); lastTick = ProcessInfo.processInfo.systemUptime; lastFrameTime = nil; audio.setMusicPlaying(profile.soundEnabled && appActive); publishHUD() }
    func togglePause() { if run.phase == .running { pause() } else if run.phase == .paused { resume() } }
    func showPanel(_ value: GamePanel) { if run.phase == .running { pause() }; panel = value }

    func revive() {
        guard canRevive else { return }
        stopCrashReplay()
        crashReplay = CrashReplayBuffer()
        if profile.keys > 0 { profile.keys -= 1 }
        else { spentRunKeys += 1 }
        hasRevived = true
        run.revive()
        save()
        audio.play(.power)
        audio.setMusicPlaying(profile.soundEnabled && appActive)
        lastTick = ProcessInfo.processInfo.systemUptime
        notify(run.mode == .jetSki ? "Back on the water · 3 seconds of protection" : "Back on track · 3 seconds of protection")
        publishHUD()
    }

    func finish() { stopCrashReplay(); run.finish(); commitRun(); audio.setMusicPlaying(false); publishHUD() }
    func returnToMenu() {
        stopCrashReplay()
        commitRun()
        crashReplay = CrashReplayBuffer()
        run = RunnerSimulation()
        ghostRecorder = GhostRecorder()
        ghostCourse = nil
        ghostReplay = nil
        ghostSample = nil
        world.updateGhost(sample: nil)
        panel = nil
        isDailyRun = false
        audio.setMusicPlaying(false)
        refreshWorld()
        publishHUD()
    }

    func setActive(_ active: Bool) {
        appActive = active
        if !active { pause() }
        lastTick = ProcessInfo.processInfo.systemUptime
        lastFrameTime = nil
        publishHUD()
    }

    func dismissTutorial() { profile.tutorialCompleted = true; save() }
    func claimDaily() {
        let reward = profile.claimDaily()
        if reward > 0 { save(); audio.play(.power); notify("Daily delivery · +\(reward) coins") }
        else { notify("Delivery collected · come back tomorrow") }
    }
    func claimMission(_ id: String) {
        let reward = profile.claimMission(id)
        if reward > 0 { save(); audio.play(.power); notify("Mission complete · +\(reward) coins") }
    }
    func purchaseCharacter(_ id: String) {
        if profile.purchaseCharacter(id) { profile.selectedCharacter = id; save(); audio.play(.power) }
        else { notify("Earn more coins to unlock this runner") }
    }
    func purchaseBoard(_ id: String) {
        if profile.purchaseBoard(id) { profile.selectedBoard = id; save(); audio.play(.power) }
        else { notify("Earn more coins to unlock this board") }
    }
    func selectCharacter(_ id: String) { guard profile.unlockedCharacters.contains(id) else { return }; profile.selectedCharacter = id; save() }
    func selectBoard(_ id: String) { guard profile.unlockedBoards.contains(id) else { return }; profile.selectedBoard = id; save() }
    func upgrade(_ power: PowerUp) {
        if profile.purchaseUpgrade(power) { save(); audio.play(.power); notify("\(GameCatalog.name(forPower: power)) upgraded") }
        else { notify(profile.upgradeCost(power) == 0 ? "Fully upgraded" : "More coins needed for this upgrade") }
    }
    func buyBoards() {
        if profile.buyBoards() {
            save()
            notify(run.phase == .paused || run.phase == .running || run.phase == .crashed
                ? "Three boards added · ready next run" : "Three boards ready to ride")
        } else { notify("You need 150 coins for three boards") }
    }
    func buyKeys() { if profile.buyKeys() { save(); notify("One rescue key added") } else { notify("You need 250 coins for a rescue key") } }
    func toggleSound() { profile.soundEnabled.toggle(); audio.setEnabled(profile.soundEnabled); audio.setMusicPlaying(profile.soundEnabled && run.phase == .running && appActive); save() }
    func toggleHaptics() { profile.hapticsEnabled.toggle(); save(); haptic(.light) }

    /// Called by a coalescing renderer delegate on the main queue. There is no
    /// competing timer and no unbounded queue of delayed simulation frames.
    func renderFrame(at time: Double) {
        guard usesLiveFrames, shouldAnimateScene, time.isFinite else { return }
        defer { lastFrameTime = time }
        guard let previous = lastFrameTime else { return }
        diagnostics.recordInterval(time - previous)
        advance(dt: min(0.05, max(0, time - previous)))
    }

    /// All frame-driven accounting passes through this path, including course
    /// completion. Keeping it separate from the wall clock makes settlement
    /// deterministic to exercise without waiting through a whole race.
    func advance(dt: Double) {
        guard appActive, dt.isFinite, dt >= 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        diagnostics.beginTick(at: now)
        defer { diagnostics.endTick(milliseconds: (ProcessInfo.processInfo.systemUptime - now) * 1_000) }
        if isReplaying {
            replayProgress = min(1, replayProgress + dt / max(0.001, replayDuration))
            refreshWorld(); hudElapsed += dt
            if hudElapsed >= 0.05 { publishHUD() }
            if replayProgress >= 1 { lastFrameTime = nil; publishHUD() }
            return
        }
        // Pause if a sheet is opened directly through SwiftUI's item binding.
        if panel != nil, run.phase == .running { pause() }
        let oldStage = run.worldStage
        let oldStageLength = run.stageLength
        let oldStageIndex = run.stageIndex
        let oldRelics = run.artifactsCollected
        let oldTransition = run.isPortalTransitioning
        let oldCoins = run.coins
        let oldPowers = Set(run.activePowerUps.keys)
        let oldBoard = run.boardTime
        let oldPhase = run.phase
        let oldGates = run.gatesCleared
        let oldMissedGates = run.gatesMissed
        let oldNearMisses = run.nearMisses
        let wasAirborne = run.height > 0.1
        if oldPhase == .running { checkpointElapsed += min(60, dt) }
        run.update(dt: dt)
        if oldPhase == .running { recordGhostFrame(force: run.phase != .running || oldStage != run.worldStage) }
        if run.mode == .odyssey {
            if run.stageIndex != oldStageIndex {
                if !run.isPractice { profile.recordWorld(oldStage, distance: oldStageLength) }
                audio.play(.arrival); haptic(.medium)
            }
            if run.isPortalTransitioning && !oldTransition { audio.play(.portal); haptic(.heavy) }
            if run.artifactsCollected > oldRelics { audio.play(.relic); haptic(.medium) }
            // A finished run must be saved only after commitRun banks its rewards.
            // Saving a profile without a session here would create a crash window
            // in which the final portal discards the still-unsettled expedition.
            if run.phase != .finished,
               run.stageIndex != oldStageIndex || run.artifactsCollected != oldRelics || run.isPortalTransitioning != oldTransition { save() }
        }
        if run.coins > oldCoins { audio.play(.coin) }
        if !Set(run.activePowerUps.keys).subtracting(oldPowers).isEmpty { audio.play(.power); haptic(.medium) }
        if oldBoard > 0, run.boardTime == 0, run.invulnerableTime > 0 { audio.play(.shield); haptic(.heavy); notify("Board saved you!") }
        if oldPhase == .running, run.phase == .crashed { audio.play(.crash); audio.setMusicPlaying(false); haptic(.heavy) }
        if run.gatesCleared > oldGates { audio.play(.power); haptic(.light) }
        if run.gatesMissed > oldMissedGates { haptic(.medium) }
        if run.nearMisses > oldNearMisses { haptic(.light) }
        if wasAirborne, run.height <= 0.1, run.phase == .running { haptic(.light) }
        if run.phase == .finished, !didRecord {
            commitRun()
            audio.setMusicPlaying(false)
            audio.play(.power)
            haptic(.medium)
        }
        if (oldPhase == .running && run.phase == .crashed) || (run.phase == .running && (checkpointElapsed >= 5 || now - lastCheckpoint >= 5)) { save() }
        if run.phase == .running || run.phase == .menu { worldTime += dt }
        if oldPhase == .running { crashReplay.append(run, worldTime: worldTime, force: run.phase == .crashed) }
        playHazardCue()
        audio.setSoundscape(mode: run.mode, world: run.worldStage)
        audio.setVehicleState(speed: run.speed, active: run.phase == .running && run.isWaterTraversal, boosting: run.isBoosting)
        if shouldAnimateScene || oldPhase != run.phase || oldStage != run.worldStage { refreshWorld() }
        qualityElapsed += dt
        if qualityElapsed >= 1 { qualityElapsed = 0; updateQuality() }
        hudElapsed += dt
        if hudElapsed >= 0.05 || oldPhase != run.phase || oldStage != run.worldStage { publishHUD() }
    }

    private func publishHUD() {
        hudElapsed = 0
        objectWillChange.send()
        onRenderSettingsChanged?()
    }

    private func playHazardCue() {
        guard run.phase == .running, !run.isWaterTraversal, run.elapsed - lastWarningTime >= 0.8,
              let obstacle = run.entities.filter({ entity in
                  [.barrier, .root, .arch, .laserSweep, .gap, .iceCrack, .tram, .meteor].contains(entity.kind) &&
                  abs(Double(entity.arrivalLane) - run.lateral) < 0.55 && entity.z > 0 && entity.z / max(1, run.speed) < 1.4
              }).min(by: { $0.z < $1.z }), obstacle.id != lastWarningID else { return }
        lastWarningID = obstacle.id; lastWarningTime = run.elapsed
        switch obstacle.kind {
        case .barrier, .root, .gap, .iceCrack: audio.play(.warningJump)
        case .arch, .laserSweep: audio.play(.warningSlide)
        default: audio.play(.warningDodge)
        }
    }

    private func refreshWorld() {
        if isReplaying, let frame = crashReplay.frame(at: replayProgress) {
            world.update(simulation: frame.run, character: profile.selectedCharacter, board: profile.selectedBoard, time: frame.worldTime)
            world.updateGhost(sample: nil)
            return
        }
        world.reducedMotion = profile.reducedMotion || systemReducedMotion
        world.highContrastCues = profile.highContrastCues
        world.previewMode = selectedMode
        world.previewStage = selectedStage
        world.update(simulation: run, character: profile.selectedCharacter, board: profile.selectedBoard, time: worldTime)
        ghostSample = profile.ghostEnabled ? ghostReplay?.sample(at: run.elapsed) : nil
        if ghostSample?.stageIndex != run.stageIndex || run.isPortalTransitioning || run.phase == .menu { ghostSample = nil }
        world.updateGhost(sample: ghostSample)
    }

    private func updateQuality() {
        let process = ProcessInfo.processInfo
        let requested = profile.graphicsQuality
        let resolved: RenderQuality
        if process.thermalState == .serious || process.thermalState == .critical || process.isLowPowerModeEnabled {
            resolved = .performance
        } else if requested != .automatic {
            resolved = requested
        } else {
            #if os(iOS)
            resolved = process.physicalMemory <= 3_500_000_000 ? .performance : .balanced
            #else
            resolved = .ultra
            #endif
        }
        guard !hasAppliedQuality || effectiveQuality != resolved else { return }
        hasAppliedQuality = true
        effectiveQuality = resolved
        world.applyQuality(resolved)
        onRenderSettingsChanged?()
    }

    func setGraphicsQuality(_ quality: RenderQuality) { profile.graphicsQuality = quality; updateQuality(); save(); publishHUD() }
    func setPortalAssist(_ enabled: Bool) { profile.portalAssist = enabled; run.configurePortalAssist(enabled); save(); publishHUD() }
    func setSwipeSensitivity(_ sensitivity: Double) { profile.swipeSensitivity = min(1.5, max(0.65, sensitivity)); save() }
    func setGhostEnabled(_ enabled: Bool) { profile.ghostEnabled = enabled; save(); publishHUD() }
    func equipArtifact(_ artifact: ArtifactAbility) {
        guard run.canChooseAbility else { return }
        guard ghostReplay.map({ run.elapsed > $0.duration }) ?? true else { notify("Ghost race uses its recorded artifact"); return }
        if artifact != run.selectedAbility {
            if run.elapsed > 0 { ghostCourse = nil }
            else { ghostCourse?.artifact = artifact }
        }
        profile.selectedArtifact = artifact; run.chooseAbility(artifact); save(); publishHUD()
    }
    func activateArtifact() { perform(.ability) }
    func steerWater(_ target: Double?) {
        guard run.phase == .running, panel == nil, !isReplaying else { return }
        diagnostics.markInput(at: ProcessInfo.processInfo.systemUptime)
        run.steerWater(target)
    }

    func racePersonalGhost() {
        guard selectedMode != .odyssey || selectedExpeditionStyle == .campaign else { return }
        let startIndex = selectedMode == .odyssey ? selectedWorld : 0
        guard let replay = profile.preferredGhost(forMode: selectedMode, expert: selectedExpert, startWorld: startIndex) else { return }
        start(replay: replay)
    }

    private func recordGhostFrame(force: Bool = false) {
        guard ghostCourse != nil else { return }
        ghostRecorder.append(GhostSample(time: run.elapsed, distance: run.distance,
                                        stageIndex: run.stageIndex, stageDistance: run.stageDistance,
                                        x: run.lateral, y: run.height, roll: run.isRolling), force: force)
    }

    private func commitRun() {
        guard !didRecord, run.phase != .menu else { return }
        didRecord = true
        achievedPersonalBest = !run.isPractice && run.score > profile.modeBestScore(mode: run.mode, expert: run.expert, expeditionStyle: run.expeditionStyle)
        profile.recordRun(run)
        if !run.isPractice { profile.keys = max(0, profile.keys - spentRunKeys) }
        ghostCourse?.decisionPlan = run.decisionPlan
        if let course = ghostCourse, let replay = ghostRecorder.replay(course: course, score: run.score,
            completed: run.mode == .odyssey ? run.journeyComplete : run.courseTarget > 0 && run.distance >= run.courseTarget) {
            profile.recordGhost(replay)
        }
        if isDailyRun {
            if run.mode == .odyssey { profile.recordDailyOdyssey(score: run.score, day: dailyRunDate) }
            else {
                if profile.dailyChallengeDate != dailyRunDate { profile.dailyChallengeDate = dailyRunDate; profile.dailyChallengeBest = 0 }
                profile.dailyChallengeBest = max(profile.dailyChallengeBest, run.score)
            }
        }
        save()
    }

    private func save() {
        profile.syncJourney(run)
        let session: RunSession? = !didRecord && run.phase != .menu && run.phase != .finished
            ? RunSession(run: run, hasRevived: hasRevived, spentRunKeys: spentRunKeys,
                         isDailyRun: isDailyRun, dailyRunDate: dailyRunDate,
                         ghostRecorder: ghostCourse == nil ? nil : ghostRecorder, ghostCourse: ghostCourse)
            : nil
        if RunCheckpointStore.save(ControllerSave(profile: profile, session: session), defaults: defaults) {
            lastCheckpoint = ProcessInfo.processInfo.systemUptime
            checkpointElapsed = 0
        }
    }
    private func notify(_ message: String) {
        toastID += 1
        let id = toastID
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in if self?.toastID == id { self?.toast = nil } }
    }
    private enum Feedback { case light, medium, heavy }
    private func haptic(_ feedback: Feedback) {
        guard profile.hapticsEnabled else { return }
        #if os(iOS)
        let generator = feedback == .light ? lightFeedback : feedback == .medium ? mediumFeedback : heavyFeedback
        generator.impactOccurred()
        generator.prepare()
        #endif
    }
    private static func dayStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
