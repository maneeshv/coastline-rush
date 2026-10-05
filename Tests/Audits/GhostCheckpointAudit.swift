import Foundation

@main struct GhostCheckpointAudit {
    static func main() throws {
        var run = RunnerSimulation(); run.start(seed: 4, boards: 0, mode: .odyssey)
        run.chooseAbility(.phaseStep)
        var profile = PlayerProfile(), recorder = GhostRecorder()
        var course = GhostCourseKey(mode: .odyssey, expert: false, seed: 4, startWorld: 0, artifact: .phaseStep)
        var tick = 0, checkpoints = 0, maxSaveBytes = 0, previousStage = 0
        var portalPauses = Set<Int>()
        while run.phase == .running && tick < 90_000 {
            if run.canChoosePerk, let perk = run.availablePerks.first { run.choosePerk(perk) }
            RouteAudit.drive(&run, route: run.stageIndex % 2 == 0 ? .risky : .safe)
            run.update(dt: 1.0 / 60); tick += 1
            course.decisionPlan = run.decisionPlan
            recorder.append(GhostSample(time: run.elapsed, distance: run.distance, stageIndex: run.stageIndex,
                stageDistance: run.stageDistance, x: run.lateral, y: run.height, roll: run.isRolling), force: run.stageIndex != previousStage || run.phase == .finished)
            previousStage = run.stageIndex
            if run.isPortalTransitioning && !portalPauses.contains(run.stageIndex) {
                portalPauses.insert(run.stageIndex)
                let before = run.portalTransitionProgress, elapsed = run.elapsed, distance = run.distance
                run.pause(); run.update(dt: 30)
                guard run.portalTransitionProgress == before && run.elapsed == elapsed && run.distance == distance else { fatalError("Pause advanced portal") }
                run.resume()
            }
            if tick % 197 == 0 || run.isPortalTransitioning {
                profile.syncJourney(run)
                let record = ControllerSave(profile: profile, session: RunSession(run: run, hasRevived: false, spentRunKeys: 0,
                    isDailyRun: false, dailyRunDate: "2026-10-04", ghostRecorder: recorder, ghostCourse: course))
                let data = try JSONEncoder().encode(record)
                let restored = try JSONDecoder().decode(ControllerSave.self, from: data)
                guard let session = restored.session, let restoredRecorder = session.ghostRecorder else { fatalError("Checkpoint dropped session or ghost") }
                guard session.ghostCourse == course && restoredRecorder.samples == recorder.samples && session.run.stageResults == run.stageResults,
                      session.run.decisionPlan == run.decisionPlan, session.run.selectedPerks == run.selectedPerks else { fatalError("Checkpoint ghost/course/mastery mismatch") }
                run = session.run; recorder = restoredRecorder; profile = restored.profile
                maxSaveBytes = max(maxSaveBytes, data.count); checkpoints += 1
            }
        }
        guard run.journeyComplete, portalPauses.count == 6, course.decisionPlan.count == 6,
              run.selectedPerks.count == 3 else { fatalError("Route or decision plan incomplete") }
        let replay = recorder.replay(course: course, score: run.score, completed: true)!
        profile.recordGhost(replay); profile.syncJourney(run)
        guard profile.personalGhosts.count == 1, profile.highestUnlockedWorld == 5, profile.worldMedals.count == 6 else { fatalError("Persistent progress incomplete") }
        for sample in replay.samples {
            guard replay.sample(at: sample.time)?.stageIndex == sample.stageIndex else { fatalError("Ghost interpolated across a portal") }
        }
        guard profile.matchingGhost(for: course) != nil,
              profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: true, seed: 4, startWorld: 0)) == nil,
              profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: false, seed: 5, startWorld: 0)) == nil,
              profile.matchingGhost(for: GhostCourseKey(mode: .odyssey, expert: false, seed: 4, startWorld: 1)) == nil
        else { fatalError("Ghost matched an unrelated course") }
        var alteredRoute = course
        alteredRoute.decisionPlan[0].route = .safe
        var alteredArtifact = course
        alteredArtifact.artifact = .airDash
        var alteredPerk = course
        alteredPerk.decisionPlan[1].perk = nil
        guard profile.matchingGhost(for: alteredRoute) == nil,
              profile.matchingGhost(for: alteredArtifact) == nil,
              profile.matchingGhost(for: alteredPerk) == nil else { fatalError("Ghost ignored a route, artifact or perk mismatch") }
        print("PASS real generated mixed-fork 6-world run with \(checkpoints) full ControllerSave/RunSession/GhostRecorder JSON round-trips; six paused portals; \(replay.samples.count) ghost samples; 6 persisted medals; 6 preserved route decisions and 3 perk upgrades; maxSaveBytes=\(maxSaveBytes)")
    }
}
