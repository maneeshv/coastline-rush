import Foundation

@main
struct ExpansionTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !value() { fatalError("Expansion check failed: " + message) }
    }
    static func fixture(_ run: RunnerSimulation, progress: Double? = nil,
                        revision: Int? = nil, charges: Int? = nil, stripExpansion: Bool = false) throws -> RunnerSimulation {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run)) as! [String: Any]
        var journey = object["journey"] as! [String: Any]
        if let progress {
            let local = run.stageLength * progress
            journey["stageDistance"] = local
            object["distance"] = local
            object["nextPatternDistance"] = local + run.stageTargetSpeed * 3
            object["entities"] = []
        }
        if let revision { journey["routeRevision"] = revision }
        object["journey"] = journey
        if stripExpansion { object.removeValue(forKey: "expansion") }
        if let charges {
            var enhancements = object["enhancements"] as! [String: Any]
            enhancements["abilityCharges"] = charges
            object["enhancements"] = enhancements
        }
        return try JSONDecoder().decode(RunnerSimulation.self, from: JSONSerialization.data(withJSONObject: object))
    }
    static func crossStage(_ run: inout RunnerSimulation) {
        let cleared = run.stagesCleared
        run.replaceTrackForTesting([])
        for _ in 0..<1_500 where run.phase == .running && run.stagesCleared == cleared { run.update(dt: 0.25) }
    }
    static func main() throws {
        var standard = RunnerSimulation()
        standard.start(seed: 19, mode: .odyssey)
        expect(standard.routeRevision == 7 && standard.expeditionStyle == .campaign, "new expedition uses v7")
        expect(!standard.canChoosePerk && standard.isCompetitiveRun, "first world cannot repeatedly upgrade")
        var choice = try fixture(standard, progress: 0.23)
        choice.replaceTrackForTesting([])
        choice.chooseRoute(.risky)
        expect(choice.branchRoute == .risky && choice.decisionPlan.first?.route == .risky, "route records player intent")
        choice = try fixture(choice, progress: 0.40)
        expect(choice.routeIsActive && choice.routeElevation == 2.8 && choice.routeLateralOffset == 8, "risky fork has separate elevated route")
        expect(choice.routeTransform(atAheadDistance: 0, route: .safe).lateralOffset == -8, "renderer can display alternative fork")
        choice.chooseRoute(.safe)
        expect(choice.branchRoute == .risky, "cannot swap course after lock")
        choice.replaceTrackForTesting([TrackEntity(id: 99, kind: .coin, lane: 0, z: 0.4, y: 0.9, length: 0.3)])
        choice.update(dt: 0.025)
        expect(choice.coins == 2, "risky route pays double coin value")
        let roundTrip = try JSONDecoder().decode(RunnerSimulation.self, from: JSONEncoder().encode(choice))
        expect(roundTrip.decisionPlan == choice.decisionPlan && roundTrip.branchRoute == .risky, "fork persists in checkpoint")

        var boundary = try fixture(standard, progress: 0.28)
        boundary.replaceTrackForTesting([], generate: true)
        boundary.update(dt: 0.01)
        expect(boundary.phase == .running && !boundary.entities.isEmpty, "fork boundary generation advances rather than converging forever")

        var water = try fixture(standard, progress: 0.23)
        water.chooseRoute(.safe)
        water = try fixture(water, progress: 0.40)
        water.replaceTrackForTesting([])
        water.update(dt: 0.01)
        expect(water.isWaterTraversal, "harbor channel switches actual physics")
        water.steerWater(1)
        water.update(dt: 0.10)
        expect(water.lateral > 0 && water.lateral < 1, "water steering has momentum")
        let unbrakedBase = water.stageTargetSpeed
        water.act(.roll); water.update(dt: 0.01)
        expect(water.isBraking && water.speed < unbrakedBase && water.stageTargetSpeed >= unbrakedBase, "water brake does not reset expedition base pace")
        water = try fixture(water, progress: 0.56)
        water.update(dt: 0.01)
        expect(!water.isWaterTraversal && !water.isBraking && water.height == 0, "shore exit restores foot controls safely")

        var legacy = try fixture(standard, progress: 0.40, revision: 6, stripExpansion: true)
        expect(!legacy.isExpansionActive && legacy.routeLateralOffset == 0 && !legacy.isWaterTraversal, "old current stage retains geometry")
        crossStage(&legacy)
        expect(legacy.routeRevision == 7 && legacy.stageIndex == 1 && legacy.isExpansionActive, "old save upgrades only at next portal")

        var perks = standard
        crossStage(&perks)
        expect(perks.canChoosePerk, "next world offers optional upgrade")
        perks.choosePerk(.longPhase)
        perks.choosePerk(.dashDividend)
        expect(perks.selectedPerks == [.longPhase] && !perks.canChoosePerk, "one perk per arrival")
        perks.chooseAbility(.phaseStep)
        perks = try fixture(perks, charges: 1)
        expect(!perks.canActivateAbility && perks.abilityChargeCost == 2, "long phase requires doubled charge cost")
        perks = try fixture(perks, charges: 2)
        perks.act(.ability)
        expect(perks.abilityTime == 1.8 && perks.abilityCharges == 0, "long phase applies duration and cost")
        crossStage(&perks)
        expect(perks.stageResults.last?.usedProtection == true, "phase use prevents no-protection award")
        perks.choosePerk(.relicCapacitor)
        expect(perks.maximumAbilityCharges == 5, "capacitor expands stored charges")
        perks.replaceTrackForTesting([TrackEntity(id: 301, kind: .relic, lane: 0, z: 0.4, y: 0.9, length: 0.6)])
        perks.update(dt: 0.02)
        expect(perks.abilityCharges == 0, "capacitor trades recharge frequency for capacity")
        perks.replaceTrackForTesting([TrackEntity(id: 302, kind: .relic, lane: 0, z: 0.4, y: 0.9, length: 0.6)])
        perks.update(dt: 0.02)
        expect(perks.abilityCharges == 1, "second relic recharges capacitor")

        let plan = [ExpeditionDecision(world: 0, route: .risky), ExpeditionDecision(world: 1, route: .safe, perk: .dashDividend)]
        var replay = RunnerSimulation()
        replay.start(seed: 19, mode: .odyssey, replayPlan: plan)
        replay = try fixture(replay, progress: 0.27)
        replay.replaceTrackForTesting([])
        replay.update(dt: 0.01)
        expect(replay.branchRoute == .risky && !replay.routeChoiceAvailable, "ghost replay fixes route choice")
        crossStage(&replay)
        expect(replay.selectedPerks == [.dashDividend] && !replay.canChoosePerk, "ghost replay fixes perk choice")
        var partialReplay = RunnerSimulation()
        partialReplay.start(seed: 19, mode: .odyssey, replayPlan: [plan[0]])
        crossStage(&partialReplay)
        expect(partialReplay.canChoosePerk, "a partial ghost does not lock later world upgrades")
        partialReplay = try fixture(partialReplay, progress: 0.23)
        expect(partialReplay.routeChoiceAvailable, "a partial ghost does not lock later world forks")
        partialReplay.chooseRoute(.risky)
        expect(partialReplay.branchRoute == .risky, "later unrecorded worlds accept route input")
        var daily = RunnerSimulation()
        daily.start(seed: 2, mode: .odyssey, dailyID: "2026-10-04", expeditionStyle: .endless)
        daily = try fixture(daily, progress: 0.27)
        daily.replaceTrackForTesting([]); daily.update(dt: 0.01)
        expect(daily.branchRoute == .safe && daily.expeditionStyle == .campaign, "daily keeps a fixed campaign route")
        crossStage(&daily)
        expect(daily.selectedPerks == [.longPhase] && !daily.canChoosePerk, "daily fixes shared upgrade order")

        for world in 0..<6 {
            var practice = RunnerSimulation()
            practice.start(seed: 7, mode: .odyssey, startStage: world, expeditionStyle: .practice)
            expect(practice.isPractice && !practice.isCompetitiveRun && practice.stageProgress >= 0.70, "practice starts at finale preparation")
            practice.chooseAbility(.phaseStep)
            expect(practice.selectedAbility == .phaseStep, "practice accepts the equipped artifact before its opening ends")
            crossStage(&practice)
            expect(practice.phase == .finished && practice.stagesCleared == 1 && practice.stageResults.count == 1, "practice ends at one portal")
            expect(practice.elapsed > 20 && practice.elapsed < 40, "practice lasts about thirty seconds")
        }

        for expert in [false, true] {
            var endless = RunnerSimulation()
            endless.start(seed: 19, boards: 0, mode: .odyssey, expert: expert, expeditionStyle: .endless)
            var previous = endless.stageTargetSpeed
            for _ in 0..<20 {
                var previousFrame = endless.stageTargetSpeed
                let cleared = endless.stagesCleared
                endless.replaceTrackForTesting([])
                for _ in 0..<1_500 where endless.stagesCleared == cleared {
                    endless.update(dt: 0.25)
                    if endless.stageTargetSpeed + 0.000001 < previousFrame { fatalError("Endless base pace dropped at portal") }
                    previousFrame = endless.stageTargetSpeed
                }
                expect(endless.phase == .running && !endless.journeyComplete, "endless continues beyond sixth portal")
                expect(endless.stageTargetSpeed >= previous, "endless portal preserves accumulated speed")
                previous = endless.stageTargetSpeed
            }
            expect(endless.expeditionCycle == 3 && endless.stageResults.count == 12, "endless history remains bounded")
            expect(endless.stageTargetSpeed <= (expert ? 71 : 65), "endless speed has playable ceiling")
        }
        print("PASS \(checks) expedition expansion checks")
    }
}
