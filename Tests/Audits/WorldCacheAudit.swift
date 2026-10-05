import Foundation
import SceneKit

@main struct WorldCacheAudit {
    static func value(_ world: CoastalWorld, _ name: String) -> Any {
        Mirror(reflecting: world).children.first { $0.label == name }!.value
    }
    static func dictionaryCount(_ world: CoastalWorld, _ name: String) -> Int { Mirror(reflecting: value(world, name)).children.count }
    static func poolCount(_ world: CoastalWorld) -> Int {
        Mirror(reflecting: value(world, "pools")).children.reduce(0) { count, item in
            count + ((Array(Mirror(reflecting: item.value).children).last?.value as? [SCNNode])?.count ?? 0)
        }
    }
    static func main() throws {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let world = CoastalWorld(assetsURL: resources)
        var maxDestinations = 0, maxPools = 0, maxLive = 0, maxSceneNodes = 0, snapshots = 0, alignedEntities = 0
        var warmCallbacks = 0, time = 0.0
        world.onWorldPrepared = { _ in warmCallbacks += 1 }
        for iteration in 0..<5 {
            for index in 0..<6 {
                var run = RunnerSimulation(); run.start(seed: UInt64(iteration + 1), mode: .odyssey, startStage: index)
                for progress in [0.0, 0.40, 0.80, 0.94] {
                    // Visit the physical fork and authored finale, not only empty
                    // arrival snapshots. Collision removal is deliberate: this
                    // probe checks retained renderer resources, not survivability.
                    while run.stageProgress < progress && run.phase == .running {
                        if run.routeChoiceAvailable { run.chooseRoute(iteration % 2 == 0 ? .safe : .risky) }
                        run.replaceTrackForTesting(run.entities.filter { $0.z > 35 }, generate: true)
                        run.update(dt: 0.25)
                    }
                    for _ in 0..<4 {
                        time += 1.0 / 60.0
                        world.update(simulation: run, character: "milo", board: "tideline", time: time)
                    }
                    snapshots += 1
                    let destinations = dictionaryCount(world, "destinations")
                    let pooled = poolCount(world)
                    let live = dictionaryCount(world, "liveNodes")
                    guard destinations <= 2, pooled <= 96 else { fatalError("Unbounded cache: destinations=\(destinations), pool=\(pooled)") }
                    maxDestinations = max(maxDestinations, destinations); maxPools = max(maxPools, pooled); maxLive = max(maxLive, live)
                    var nodes = 0
                    world.scene.rootNode.enumerateChildNodes { _, _ in nodes += 1 }
                    maxSceneNodes = max(maxSceneNodes, nodes)
                    let player = value(world, "player") as! SCNNode
                    let playerRoute = run.routeTransform(atAheadDistance: 0)
                    guard abs(Double(player.position.x) - (run.lateral * 2.6 + playerRoute.lateralOffset)) < 0.001,
                          abs(Double(player.position.y) - (run.height + playerRoute.elevation)) < 0.50 else {
                        fatalError("Player visual detached from its simulation route")
                    }
                    let entityNodes = value(world, "liveNodes") as! [Int: SCNNode]
                    for entity in run.entities {
                        guard let node = entityNodes[entity.id] else { continue }
                        let route = run.routeTransform(atAheadDistance: entity.z)
                        guard abs(Double(node.position.x) - (Double(entity.lane) * 2.6 + route.lateralOffset)) < 0.001,
                              abs(Double(node.position.y) - (entity.y + route.elevation)) < 0.10 else {
                            fatalError("Entity \(entity.id) visual detached from its collider route")
                        }
                        alignedEntities += 1
                    }
                }
            }
        }
        print("PASS 30 world selections, \(snapshots) arrival/fork/finale snapshots + next-world prewarms: destinations<=\(maxDestinations), pool<=\(maxPools), live<=\(maxLive), attachedSceneNodes<=\(maxSceneNodes), preparationCallbacks=\(warmCallbacks)")
        print("PASS \(snapshots) player and \(alignedEntities) entity route/collider alignment checks")
        for quality in RenderQuality.allCases { world.applyQuality(quality) }
        print("PASS all render quality settings apply")
    }
}
