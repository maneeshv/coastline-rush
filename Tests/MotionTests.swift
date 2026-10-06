import Foundation
import SceneKit

/// Scenery must travel past the runner continuously. A section may only be recycled
/// (jump to the far end) once it is entirely behind the camera.
@main struct MotionTests {
    static func sections(_ world: CoastalWorld, _ label: String) -> [SCNNode] {
        Mirror(reflecting: world).children.first { $0.label == label }!.value as! [SCNNode]
    }

    static func main() {
        // (mode, start stage, section list, metres of geometry behind the section origin)
        let cases: [(RunMode, Int, String, Double)] = [(.endless, 0, "segments", 24), (.odyssey, 2, "journeySections", 13)]
        for (mode, stage, label, behind) in cases {
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            var run = RunnerSimulation(); run.start(seed: 9, mode: mode, startStage: stage)
            var time = 0.0, lastDistance = 0.0, recycled = 0
            var last: [Double] = []
            while run.distance < 160 && run.phase == .running {
                run.replaceTrackForTesting(run.entities.filter { $0.z > 40 }, generate: true)
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                world.update(simulation: run, character: "milo", board: "tideline", time: time)
                let now = sections(world, label).map { Double($0.worldPosition.z) }
                let moved = run.distance - lastDistance
                for (index, z) in now.enumerated() where index < last.count {
                    let step = z - last[index]
                    guard abs(step - moved) > 1 else { continue }
                    // The only legal jump: a section entirely behind the camera (z ≈ 10–12) goes to the far end.
                    precondition(last[index] - behind > 10, "\(label)[\(index)] jumped \(String(format: "%.2f", step)) m at distance \(String(format: "%.1f", run.distance)) while visible (z \(String(format: "%.1f", last[index])))")
                    precondition(step < 0, "\(label)[\(index)] recycled toward the camera")
                    recycled += 1
                }
                last = now; lastDistance = run.distance
            }
            precondition(recycled > 0, "\(label): expected sections to recycle over 160 m")
            print("\(label): continuous, \(recycled) recycles behind the camera")
        }
        print("MotionTests passed")
    }
}
