import Foundation
@main struct ObjectiveAudit {
    static func main() {
        for expert in [false, true] {
            for world in [0, 2] {
                var run = RunnerSimulation()
                run.start(seed: 23, boards: 0, mode: .odyssey, expert: expert, startStage: world)
                var frames = 0, highFrames = 0, roofFrames = 0
                var maximumHeight = 0.0
                var heldRoofID: Int? = nil
                while run.phase == .running && run.stagesCleared == 0 && frames < 10000 {
                    if world == 2, heldRoofID == nil, run.height > 0.25,
                                let roof = run.entities.first(where: { vehicle in vehicle.kind == .tram && vehicle.lane == run.lane && vehicle.z > -5 && vehicle.z < 14 && run.entities.contains(where: { ramp in ramp.kind == .ramp && ramp.lane == vehicle.lane && abs(ramp.z + 9 - vehicle.z) < 0.5 }) }) { heldRoofID = roof.id }
                    let heldLane = heldRoofID.flatMap { id in run.entities.first(where: { $0.id == id && $0.z > -$0.length/2 - 0.6 })?.lane }
                    if heldLane == nil { heldRoofID = nil }
                    RouteAudit.drive(&run, route: world == 0 ? .safe : .risky)
                    if let heldLane {
                                if heldLane < run.lane { run.act(.left) }
                                if heldLane > run.lane { run.act(.right) }
                                if run.routeChoiceAvailable { run.chooseRoute(.risky) }
                    }
                    if run.isWaterTraversal && run.height > 0.7 && run.trickChain == 0 { run.act(.jump) }
                    run.update(dt: 1.0/60)
                    frames += 1
                    maximumHeight = max(maximumHeight, run.height)
                    if run.height >= 2.4 { highFrames += 1 }
                    if run.entities.contains(where: { $0.kind == .tram && abs($0.z) <= $0.length/2+0.3 && abs(run.lateral - Double($0.lane)) < 0.52 && run.height >= 2.4 }) { roofFrames += 1 }
                }
                guard let result = run.stageResults.first else { fatalError("Could not clear world \(world) expert=\(expert): \(run.crashReason)") }
                guard result.hits == 0 && result.finaleCleared && result.objectivesCompleted == 4 else { fatalError("World objectives required protection or failed") }
                print("OBJECTIVE world=\(world) expert=\(expert) roofTransfers=\(result.roverTransfers) cleanLandings=\(run.cleanLandings) finale=\(result.finaleCleared) objectives=\(result.objectivesCompleted) skill=\(result.skillActions) branch=\(result.branchRoute) high=\(highFrames) roofFrames=\(roofFrames) maxHeight=\(maximumHeight)")
                if world == 0 && run.cleanLandings < 2 { fatalError("Water objective not demonstrated") }
                if world == 2 && result.roverTransfers < 4 { fatalError("Rover transfer objective was not demonstrated") }
            }
        }
    }
}
