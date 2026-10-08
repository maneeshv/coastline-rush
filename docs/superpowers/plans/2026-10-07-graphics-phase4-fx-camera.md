# Graphics Overhaul Phase 4 — FX and Camera — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the runner a lower, closer, smoothed gameplay camera with speed-scaled field of view and a lane-change lean; give each world its own white balance, rim light and ambient particles; and add speed lines, footstep dust, an upgraded landing burst and a pickup sparkle, all within the BASE frame budget.

**Architecture:**
- Camera math lives in `Sources/WorldCamera.swift` as `enum CameraRig` (pure functions), plus `CoastalWorld.updateCamera(...)`. It replaces the inline camera block in `update`.
- FX live in `Sources/WorldFX.swift`: the per-world `AmbientFX` table and a few pooled `SCNParticleSystem`s. They are built once in `init`, re-dressed in `applyLook` (world or quality change) and driven per frame from `update`.
- White balance and the rim light are two more columns in the existing `WorldLook` table.
- Particles use one generated 64 px soft dot. Large soft sprites, few particles, no downloaded art.

**Tech Stack:** Swift 5.9, SceneKit (`SCNParticleSystem`, `SCNCamera`), simd. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-graphics-overhaul-design.md`. The Phase 4, Constraints and Verification sections are binding. Phase 3 carry-over: `work/phase3/phase3-ledger.md` (runner screen size). Runner map: `work/phase3-runner-map.md`.

## Global Constraints

- iOS 16+ / macOS 13+. One shared `Sources/` tree builds both targets.
- No gameplay changes. Do not edit `Sources/RunnerSimulation.swift`, `Sources/GameController.swift`, collisions, hitboxes, lane spacing (2.6 m) or entity placement. FX read only public simulation state (`speed`, `coins`, `height`, `lateral`, `isBoosting`…).
- Quality tiers go through `applyQuality`. The spec says: "performance = half particles, no motion blur or grain; balanced = moderate; ultra = full". Here every particle count and burst size is multiplied by `fxScale` = 0.5 / 0.75 / 1.0. Motion blur stays off on every tier (see Reference facts).
- Reduced Motion (`reducedMotion`) gives: no camera shake, no speed lines, no field-of-view change (speed or boost), no camera lean, no follow lag, and no landing burst (the landing rings were already gated).
- Respect the `WorldCacheAudit` bounds (≤2 destinations, ≤96 pooled entities). Every particle emitter is pooled: built once, never created per frame or per event. The scene never holds more than 7 particle systems.
- Missing assets keep falling back to procedural images. Particles use one generated sprite (`softDot`).
- Contracts that must survive every task:
  - `player.position` is untouched: WorldCacheAudit checks x within 0.001 and y within 0.50 of the simulation.
  - Node names and Mirror-read stored properties from Phase 3 (`player`, `body`, `headRig`, `shins`, `forearms`, `feet`, `clothing`, `boardNode`, `jetpackNode`, `abilityAura`, `ski`, `scarf`, `segments`, `journeySections`, `pools`, `liveNodes`, `destinations`). FXTests also reads `landingRoot`.
  - The menu framing is unchanged: camera (0.35, 6.1, 11.8 portrait / 10.4 landscape), field of view 66/58. FXTests asserts it.
- Test bounds are fixed; implementers may tune values only inside the tuning ranges below. Record every tuned value in the commit message.
  - `CameraRig` offsets ±0.3 m; `followRate` 5–10; speed widening 2–4°; lean factor 0.04–0.08.
  - Particle `count` ±25% (never above 160), `size` ±40%, `opacity` and colours free; speed-line and dust rates ±30%.
  - White balance within the LookTests bounds (|temperature| ≤ 0.6, |tint| ≤ 0.25); rim intensities ±20% (Orbit stays ≥ 2× every other world).
- Minimal code: no speculative abstractions. Reuse `material()`/`color()`/`image()`/`vector()`/`scalar()` and `textureCache`.
- Environment:
  - `swiftc`, `xcodebuild`, `xcodegen` and `Scripts/*.sh` run outside the Claude sandbox.
  - Outputs go to `work/phase4/` (gitignored), never `$TMPDIR`.
  - Use bash, not zsh: zsh does not word-split `$VAR`.
  - `-O` builds do not print `precondition` messages. `Scripts/test.sh` builds without `-O`.
  - A new `Sources/` file needs `xcodegen generate`. The new files are named `World*.swift`, so the `Sources/World*.swift` glob in `Scripts/test.sh`, `Scripts/audit.sh`, `Scripts/render.sh` and `Scripts/runner.sh` compiles them with no script edit.
- Commits end with the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Task gate (run at the end of every task; `L` is the task label, e.g. `p4-t1`)

The A/B render needs a `BASE` copy, set up once in Task 1 Step 1. `BASE` is fixed at `3781698`, the phase-4 start, so the +5% budget is cumulative and does not ratchet task by task.

1. Run the tests and audits. Both must print `exit=0`:
   ```bash
   bash Scripts/test.sh > work/phase4/$L-test.log 2>&1; echo exit=$?
   bash Scripts/audit.sh > work/phase4/$L-audit.log 2>&1; echo exit=$?
   ```
2. Build for Mac and iOS. Both must end `** BUILD SUCCEEDED **`:
   ```bash
   xcodebuild -project CoastlineRush.xcodeproj -scheme CoastlineRush-macOS -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath ./.derived CODE_SIGNING_ALLOWED=NO build > work/phase4/$L-mac.log 2>&1; tail -1 work/phase4/$L-mac.log
   xcodebuild -project CoastlineRush.xcodeproj -scheme CoastlineRush-iOS -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath ./.derived CODE_SIGNING_ALLOWED=NO build > work/phase4/$L-ios.log 2>&1; tail -1 work/phase4/$L-ios.log
   ```
3. Run the A/B render. BASE and HEAD alternate in the same session. Run nothing else heavy while it runs: a concurrent test build inflated one pass by 20–40% in the planning runs.
   - Every shot must print `ok`. The timing rule is unchanged from Phase 3: HEAD mean ms ≤ 1.05 × BASE mean ms.
   - The exposure rule is wider than in Phase 3, because white balance, the rim and the mist change exposure on purpose: mean within ±0.05 of BASE. The planning build measured these shifts: harbor +0.034, orbit +0.038, jetski +0.024, the others ≤ 0.006. Also check that no `clipped=` share rises by more than 1 point.
   - Verdant runs at about 303 ms in BASE, at the historical limit, so its ratio is the one to watch.
   - If a shot prints `FAIL`, run one more pair (`for i in 3; do … done`) and re-run the awk. It averages every run. A single pass 40% or more over the others is an outlier: the planning runs saw one Verdant pass at 447 ms against 303–311 ms. Report it, and judge the shot on the other pairs.
   - If a shot still fails, cut cost before committing: fewer particles, smaller sprites, shorter `life`. Never commit an over-budget task. Report it as BLOCKED instead.
   ```bash
   for i in 1 2; do
     (cd work/phase4/base && bash Scripts/render.sh ab) > "work/phase4/$L-base-$i.log"
     bash Scripts/render.sh "$L-ab" > "work/phase4/$L-head-$i.log"
   done
   awk '/ ms=/ { split($NF, v, "="); split($2, m, "="); side = FILENAME ~ /-base-/ ? "base" : "head"
                 ms[side, $1] += v[2]; mean[side, $1] += m[2]; n[side, $1]++ }
        END { for (k in ms) { split(k, p, SUBSEP); if (p[1] != "head") continue; s = p[2]
                b = ms["base", s] / n["base", s]; h = ms["head", s] / n["head", s]
                d = mean["head", s] / n["head", s] - mean["base", s] / n["base", s]; if (d < 0) d = -d
                printf "%-8s base %6.1f head %6.1f ratio %.3f mean-delta %.3f %s\n", s, b, h, h / b, d, (h / b <= 1.05 && d <= 0.05) ? "ok" : "FAIL" } }' \
     work/phase4/$L-base-*.log work/phase4/$L-head-*.log | sort | tee work/phase4/$L-ab.txt
   ```
4. Render the FX shots: `bash Scripts/fx.sh $L > work/phase4/$L-fx.log 2>&1; cat work/phase4/$L-fx.log`.
   - Open the shots named in the task with Read.
   - Record each shot's `particles=` value in the commit message. HEAD's `render.sh` also prints `particles=` per world, before `ms=`.

## Reference facts (probed at `3781698`; probes in `work/phase4/probe/`)

- **Runner screen size (the Phase 3 carry-over).** The share is the runner's visible bounding box, projected through the gameplay camera, as a fraction of screen height. It is the mean over frames 151–180, with seed 3 and an empty track.
  - Phase 3 baseline, portrait (0.46) / landscape (16:9): endless 0.1618 / 0.2130; Odyssey harbor 0.1612 / 0.2120; Forge at 42 m/s 0.1608 / 0.2114.
  - In short, the runner fills about 16% of the screen height in portrait and 21% in landscape. The target is ≥ 1.15× in every case.
  - A single frame varies ±4% with the gait pose, which is why the test takes the mean.
- **The planning build with this plan's camera** measured these shares: endless 0.2011 / 0.2673 (×1.243 / ×1.255); Odyssey harbor 0.2000 / 0.2657 (×1.241 / ×1.253); Forge 0.1888 / 0.2497 (×1.174 / ×1.181). Forge has the least margin, because the field of view is widest there.
- **Hazard look-ahead** is the screen y of the deck at z −100…−135 on the outer lanes, against the runner's head.
  - BASE: deck 0.247 / 0.310 and head −0.108 / −0.168.
  - Planning build at cruise: deck 0.214 / 0.236 and head −0.125 / −0.130.
  - Planning build at Forge: deck 0.203 / 0.222 and head −0.113 / −0.116.
  - Hazards at 200 m (Odyssey's longest `visibilityDistance`) stay on screen too. The horizon moves slightly toward the centre; nothing leaves the frame.
- **Recycling (MotionTests, `recycledZ`/`arrivalFade`) reads no camera value.**
  - Harbor segments leave once their origin passes world z 36, which puts their geometry beyond z 12. Journey sections leave past z 39.
  - `arrivalFade` depends on the far end of the window only.
  - The camera moves from z 11.8 / 10.4 to z 10.0 / 8.9, toward the runner, so recycled sections stay behind it. FXTests asserts camera z < 12 on every frame.
- **`SCNNode.look(at:)` keeps the node's current up vector.** A roll applied after it therefore accumulates frame after frame: the first build drifted to about 15° after one lane change. `updateCamera` uses `look(at:up:localFront:)` with world up.
- **SceneKit white balance units:** temperature +0.3 shifts mid-grey by r +0.015 / b −0.014, and 1.0 shifts it by r +0.045 / b −0.05. Tint > 0 is magenta and < 0 is green. It needs `wantsHDR`, which is already on.
- **`SCNParticleSystem` offscreen (SCNRenderer `snapshot(atTime:)`)**, which decides how the A/B measures particles:
  - Simulation starts at the first render and advances by the time delta between snapshots.
  - `warmupDuration` pre-simulates at the first render. `RenderPreview` takes one untimed warm-up snapshot and then 5 timed ones, so with `warmupDuration = life` the timed frames render a fully populated ambient system. The A/B is therefore honest without a harness change. `particles=` in its output confirms the live count.
  - Re-adding a **looping** system to the same node (`removeAllParticleSystems` + `addParticleSystem`) makes it render nothing. Restart looping systems with `reset()`.
  - A finished **one-shot** (`loops = false`) does not restart with `reset()`. It restarts by re-adding it.
  - `emittingDirection` must be a unit vector, because SceneKit multiplies `particleVelocity` by its length. An unnormalised (2.2, 0.2, 33) sent the ambient particles off at about 1,300 m/s, and the view was empty.
  - `fx.sh` also renders every sim frame (small and untimed), so event FX (bursts, dust, speed lines) simulate between events as they do in the app.
- **Pickup event:** `RunnerSimulation.coins` is public read. A rise in it is a pickup, with no simulation change. The sparkle uses that, not entity disappearance (which would misfire on recycling and portals).
- **The drone** (harbor, first 130 m) sits at z 4.5, between the camera and the runner. The closer camera would enlarge it by about 33% over the runner, so it keeps its old offset from the camera (3.6 m below, 7.3 m ahead) and its old place in the frame.
- **The landing burst today** is 3 rings plus 18 emissive box "sparks", which is 21 draws. Task 4 replaces the 18 boxes with two pooled particle systems: spark streaks and a dust ring. The rings stay. This upgrades the burst without duplicating it, and saves 16 draws.
- **Motion blur:** none, on every tier. The spec requires only that performance has none. Speed lines carry the speed cue, and SceneKit's motion blur adds a full-screen pass on a frame where Verdant is already at its limit.
- Line numbers below are at `3781698`; match by content.

## File map

| File | Change |
|---|---|
| `Sources/WorldCamera.swift` | Create (T1): `enum CameraRig`, `updateCamera`. |
| `Sources/WorldFX.swift` | Create (T3): `AmbientFX`, `WorldStage.ambient`, `fxScale`, `softDot`, `dress`, `makeFX`, `applyAmbient`, `updateAmbient`. T4 appends `deckDust`, `makeMotionFX`, `applyBurstQuality`, `burst`, `updateMotionFX`. |
| `Sources/WorldLook.swift` | T2: white balance and rim columns, `applyLook` sets the rim. T3: `applyLook` calls `applyAmbient`. |
| `Sources/CoastalWorld.swift` | T1: camera state and call, drone, portal field of view. T2: `worldRim`. T3: ambient emitter, `image()` internal. T4: burst systems replace the spark boxes. |
| `Tests/FXTests.swift` | Create (T1), extended in T3 and T4. |
| `Tests/LookTests.swift` | T2. |
| `Scripts/test.sh` | T1: compile and run FXTests. |
| `Scripts/FXPreview.swift`, `Scripts/fx.sh` | Create (T1), extended in T3 and T4. |
| `Scripts/RenderPreview.swift` | T1: print `particles=` before `ms=`. |
| `CoastlineRush.xcodeproj` | Regenerate with `xcodegen generate` (T1, T3). |
| `docs/superpowers/specs/2026-10-06-graphics-overhaul-design.md` | T5: one note under Phase 4. |

---

### Task 1: Camera rig, FXTests and the FX harness

**Files:**
- Create: `Sources/WorldCamera.swift`, `Tests/FXTests.swift`, `Scripts/FXPreview.swift`, `Scripts/fx.sh`
- Modify: `Sources/CoastalWorld.swift`. Edits are listed in Step 4. Lines: L59–60 `routeOffset`/`routeHeight`, L112 `aspect`, L121 `bank`, L254 `dt`, L309 `motion`, L369 drone, L375–380 camera block, L2810 portal field of view.
- Modify: `Scripts/test.sh`, `Scripts/RenderPreview.swift`
- Regenerate: `CoastlineRush.xcodeproj`

**Interfaces:**
- Produces:
  - `enum CameraRig` with:
    - `static func offset(portrait: Bool, water: Bool) -> (height: Double, depth: Double)`;
    - `static func menuOffset(portrait: Bool, water: Bool) -> (height: Double, depth: Double)`;
    - `static let lookAhead = 14.0, lookHeight = 0.9, followRate = 7.0, fovRate = 3.0`;
    - `static func baseFieldOfView(portrait: Bool) -> Double`;
    - `static func fieldOfView(portrait: Bool, speed: Double, boosting: Bool, reducedMotion: Bool) -> Double`;
    - `static func follow(_ current: SIMD3<Double>, toward target: SIMD3<Double>, rate: Double, dt: Double) -> SIMD3<Double>`;
    - `static func lean(bank: Double, reducedMotion: Bool) -> Double`.
  - `CoastalWorld` gains:
    - `var cameraEye: SIMD3<Double>`, `var cameraTarget: SIMD3<Double>`, `var cameraFOV: Double` (the smoothed rig state; Tasks 3 and 4 read `cameraEye`);
    - `func updateCamera(menu:waterMode:lateral:speed:boosting:flightLift:ahead:time:dt:snap:)`;
    - internal `routeOffset`, `routeHeight`, `aspect`.
  - `Tests/FXTests.swift` with the helpers `field(_:_:)`, `project(_:_:aspect:)`, `runnerExtent(_:aspect:)`, `running(_:stage:aspect:frames:reducedMotion:fps:)` and `step(_:_:_:fps:)`. It ends with `print("FXTests passed")`, and later tasks insert blocks before that line.
  - `bash Scripts/fx.sh <label>` writes `work/shots/<label>/{top-speed,top-speed-reduced-motion,lane-lean,lane-lean-wide}.png`. Each line prints `name particles=N speed=S fov=F`. Later tasks insert shots before `print("wrote", out.path)`.
- Starting values:
  - Run framing: portrait height 5.3 m and depth 10.0 m (was 6.1 / 11.8); landscape 4.8 m and 10.4 → 8.9 m. On water, height is 0.6 m lower. The camera looks at a point 0.9 m up and 14 m ahead (the look point was 0.5 m up).
  - Base field of view 64° portrait / 56° landscape (was 66 / 58). It widens by up to 3° (smoothstep, 14 → 44 m/s) and by 5° more while boosting. It eases at rate 3/s.
  - Follow: `follow` at rate 7/s on eye and target. It snaps on the first frame, on rewound time (crash replay), on jumps over 6 m, in the menu and under Reduced Motion.
  - Lean: roll = `bank × 0.06`. That is 1–2° in a lane change, at most 2.2°.

- [ ] **Step 1: Set up BASE.**

```bash
mkdir -p work/phase4 && rm -rf work/phase4/base && mkdir -p work/phase4/base
git archive 3781698 | tar -x -C work/phase4/base
```

- [ ] **Step 2: Write the failing test.** Create `Tests/FXTests.swift`:

```swift
import Foundation
import SceneKit

/// Phase 4 camera and FX: runner screen size, hazard look-ahead, follow lag, lean, Reduced Motion, particles and quality tiers.
@main struct FXTests {
    static func field<T>(_ world: CoastalWorld, _ label: String) -> T {
        Mirror(reflecting: world).children.first { $0.label == label }!.value as! T
    }

    /// Normalised device coordinates (−1…1, y up) of a world point seen by the gameplay camera at `aspect` (width / height).
    static func project(_ world: CoastalWorld, _ p: SIMD3<Double>, aspect: Double) -> SIMD2<Double> {
        let projection = world.camera.camera!.projectionTransform(withViewportSize: CGSize(width: 1000 * aspect, height: 1000))
        let m = simd_double4x4(SCNMatrix4Mult(SCNMatrix4Invert(world.camera.worldTransform), projection))
        let c = m * SIMD4(p.x, p.y, p.z, 1)
        return SIMD2(c.x / c.w, c.y / c.w)
    }

    /// Lowest and highest screen y of the runner: its visible geometry's bounding-box corners, projected.
    static func runnerExtent(_ world: CoastalWorld, aspect: Double) -> (low: Double, high: Double) {
        var low = Double.infinity, high = -Double.infinity
        func visit(_ node: SCNNode) {
            guard !node.isHidden else { return }
            if let g = node.geometry {
                let (a, b) = g.boundingBox
                for k in 0..<8 {
                    let w = node.convertPosition(SCNVector3(k & 1 == 0 ? a.x : b.x, k & 2 == 0 ? a.y : b.y, k & 4 == 0 ? a.z : b.z), to: nil)
                    let y = project(world, SIMD3(Double(w.x), Double(w.y), Double(w.z)), aspect: aspect).y
                    low = min(low, y); high = max(high, y)
                }
            }
            node.childNodes.forEach(visit)
        }
        visit(field(world, "player"))
        return (low, high)
    }

    /// A fresh world after `frames` of running on an empty track.
    static func running(_ mode: RunMode, stage: Int, aspect: Double, frames: Int = 180, reducedMotion: Bool = false,
                        fps: Double = 60) -> (CoastalWorld, RunnerSimulation, Double) {
        let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
        world.resize(aspect: aspect)
        world.reducedMotion = reducedMotion
        var run = RunnerSimulation(); run.start(seed: 3, mode: mode, startStage: stage)
        var time = 0.0
        for _ in 0..<frames { step(world, &run, &time, fps: fps) }
        return (world, run, time)
    }

    static func step(_ world: CoastalWorld, _ run: inout RunnerSimulation, _ time: inout Double, fps: Double = 60) {
        run.replaceTrackForTesting([], generate: false)
        run.update(dt: 1 / fps); time += 1 / fps
        world.update(simulation: run, character: "milo", board: "tideline", time: time)
    }

    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)
        let portrait = 0.46, landscape = 16.0 / 9
        // 1. Runner screen size: the mean share over frames 151–180 (seed 3, empty track), so no single gait pose decides it.
        //    Phase 3 (3781698) values, measured with this exact setup: (mode, stage, portrait 0.46, landscape 16:9).
        //    The spec wants the runner larger on screen: at least 1.15× in every case, including Forge at 42 m/s where the
        //    speed-scaled field of view is widest.
        let phase3: [(RunMode, Int, Double, Double)] = [(.endless, 0, 0.1618, 0.2130), (.odyssey, 0, 0.1612, 0.2120), (.odyssey, 5, 0.1608, 0.2114)]
        for (mode, stage, p3Portrait, p3Landscape) in phase3 {
            for (aspect, before) in [(portrait, p3Portrait), (landscape, p3Landscape)] {
                var (world, run, time) = running(mode, stage: stage, aspect: aspect, frames: 150)
                var share = 0.0, lowest = 1.0
                for _ in 0..<30 {
                    step(world, &run, &time)
                    let e = runnerExtent(world, aspect: aspect)
                    share += (e.high - e.low) / 2 / 30; lowest = min(lowest, e.low)
                }
                print(String(format: "runner share %@ stage %d aspect %.2f speed %.1f: %.4f (phase 3 %.4f, ×%.3f)", "\(mode)", stage, aspect, run.speed, share, before, share / before))
                precondition(share >= before * 1.15, "runner must be ≥1.15× its phase-3 screen height (\(share) vs \(before))")
                precondition(lowest > -0.95, "runner's feet must stay on screen (\(lowest))")
            }
        }

        // 2. Readability: hazards telegraphed at spawn distance (135 m; Odyssey shows up to 200 m) stay on screen, under the
        //    HUD band and clear of the runner's head, in both orientations, at cruise and top speed, through a lane change.
        //    MotionTests' recycling assumes the camera never sits behind world z 12, where sections leave.
        for aspect in [portrait, landscape] {
            for (mode, stage) in [(RunMode.endless, 0), (.odyssey, 5)] {
                var (world, run, time) = running(mode, stage: stage, aspect: aspect, frames: 120)
                for frame in 0..<60 {
                    if frame == 0 { run.act(.right) }
                    if frame == 30 { run.act(.left); run.act(.left) }
                    step(world, &run, &time)
                    precondition(world.camera.position.z < 12, "camera behind the recycle line (z \(world.camera.position.z))")
                    let head = runnerExtent(world, aspect: aspect).high
                    for z in [-100.0, -135, -200] {
                        let route = run.routeTransform(atAheadDistance: -z)
                        for lane in [-1.0, 0, 1] {
                            for y in [0.0, 2.8] {
                                let s = project(world, SIMD3(lane * 2.6 + route.lateralOffset, y + route.elevation, z), aspect: aspect)
                                precondition(abs(s.x) < 0.95 && s.y > -0.95 && s.y < 0.85, "hazard at z \(z) lane \(lane) y \(y) off screen or under the HUD: \(s) (aspect \(aspect), frame \(frame))")
                                precondition(s.y > head + 0.2, "hazard at z \(z) too close to the runner's head: \(s.y) vs \(head) (aspect \(aspect), frame \(frame))")
                            }
                        }
                    }
                }
            }
        }

        // 3. Follow lag is frame-rate independent: a step target lands in the same place at 30, 60 and 120 fps.
        var ends: [SIMD3<Double>] = []
        for fps in [30.0, 60, 120] {
            var p = SIMD3<Double>(0, 0, 0)
            for _ in 0..<Int(fps / 2) { p = CameraRig.follow(p, toward: SIMD3(1, 2, 3), rate: CameraRig.followRate, dt: 1 / fps) }
            ends.append(p)
        }
        precondition(simd_distance(ends[0], ends[1]) < 1e-9 && simd_distance(ends[1], ends[2]) < 1e-9, "follow depends on frame rate: \(ends)")
        //    In the world: the same lane change at 30 and 120 fps puts the camera within 3 cm after 0.5 s, and the camera
        //    visibly lags the runner during the change, settles within a second and leans subtly.
        var afterHalf: [Double] = []
        for fps in [30.0, 120] {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: Int(fps * 2), fps: fps)
            run.act(.right)
            for _ in 0..<Int(fps / 2) { step(world, &run, &time, fps: fps) }
            afterHalf.append(Double(world.camera.position.x))
        }
        precondition(abs(afterHalf[0] - afterHalf[1]) < 0.03, "camera x after 0.5 s differs between 30 and 120 fps: \(afterHalf)")
        do {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 120)
            run.act(.right)
            var lag = 0.0, lean = 0.0
            for _ in 0..<60 {
                step(world, &run, &time)
                lag = max(lag, abs(Double(world.camera.position.x) - run.lateral * 0.3))
                lean = max(lean, abs(Double(world.camera.simdWorldRight.y)))
            }
            print(String(format: "lane change: max camera lag %.3f m, max lean %.4f", lag, lean))
            precondition(lag > 0.05, "camera must lag the runner during a lane change (\(lag))")
            precondition(abs(Double(world.camera.position.x) - run.lateral * 0.3) < 0.01, "camera must settle within a second")
            precondition(lean > 0.004 && lean < 0.05, "camera must lean subtly into the lane change (\(lean))")
        }

        // 4. Reduced Motion: no lag, no lean, no speed-scaled or boost field of view. The menu keeps its old framing.
        do {
            var (world, run, time) = running(.odyssey, stage: 5, aspect: portrait, frames: 120, reducedMotion: true)
            run.act(.right)
            for _ in 0..<40 {
                step(world, &run, &time)
                precondition(abs(Double(world.camera.position.x) - run.lateral * 0.3) < 1e-4, "Reduced Motion: the camera must not lag")
                precondition(abs(Double(world.camera.simdWorldRight.y)) < 1e-3, "Reduced Motion: the camera must not lean (\(world.camera.simdWorldRight))")
                precondition(abs(Double(world.camera.camera!.fieldOfView) - CameraRig.baseFieldOfView(portrait: true)) < 1e-6, "Reduced Motion: fixed field of view")
            }
        }
        for (aspect, depth) in [(portrait, 11.8), (landscape, 10.4)] {
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            world.resize(aspect: aspect)
            world.update(simulation: RunnerSimulation(), character: "milo", board: "tideline", time: 1)
            let p = world.camera.position
            precondition(abs(Double(p.x) - 0.35) < 1e-4 && abs(Double(p.y) - 6.1) < 1e-4 && abs(Double(p.z) - depth) < 1e-4, "menu framing changed: \(p)")
        }
        print("FXTests passed")
    }
}
```

- [ ] **Step 3: Run it to verify it fails.**
Run (bash): `swiftc -swift-version 5 -module-cache-path work/mc Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift Tests/FXTests.swift -o work/phase4/fx-tests`
Expected: a compile error `cannot find 'CameraRig' in scope`.

- [ ] **Step 4: Implement.** Create `Sources/WorldCamera.swift`:

```swift
import SceneKit

/// Gameplay camera rig: where the camera sits, how it follows, how wide it sees and how far it leans.
/// Pure math (Foundation + simd), so FXTests can check it without rendering.
enum CameraRig {
    /// Run framing: height above the route and distance behind the runner. The menu keeps the old framing
    /// (`menuOffset`) and leaving it glides into this one.
    static func offset(portrait: Bool, water: Bool) -> (height: Double, depth: Double) {
        ((portrait ? 5.3 : 4.8) - (water ? 0.6 : 0), portrait ? 10.0 : 8.9)
    }
    static func menuOffset(portrait: Bool, water: Bool) -> (height: Double, depth: Double) {
        (water ? 5.4 : 6.1, portrait ? 11.8 : 10.4)
    }
    /// The camera looks at a point this far ahead of the runner and this high above the route.
    static let lookAhead = 14.0, lookHeight = 0.9
    /// Exponential follow rates (1/s): each frame the camera closes 1 − e^(−rate·dt) of the gap.
    static let followRate = 7.0, fovRate = 3.0
    static func baseFieldOfView(portrait: Bool) -> Double { portrait ? 64 : 56 }
    /// Widens by up to 3° between 14 and 44 m/s, and by 5° more while boosting. Reduced Motion: fixed.
    static func fieldOfView(portrait: Bool, speed: Double, boosting: Bool, reducedMotion: Bool) -> Double {
        let base = baseFieldOfView(portrait: portrait)
        guard !reducedMotion else { return base }
        let t = min(1, max(0, (speed - 14) / 30))
        return base + 3 * t * t * (3 - 2 * t) + (boosting ? 5 : 0)
    }
    /// Frame-rate independent: two steps of dt land exactly where one step of 2·dt does (for a fixed target).
    static func follow(_ current: SIMD3<Double>, toward target: SIMD3<Double>, rate: Double, dt: Double) -> SIMD3<Double> {
        target + (current - target) * exp(-rate * dt)
    }
    /// Roll about the view axis (radians), the same way the runner banks. Reduced Motion: none.
    static func lean(bank: Double, reducedMotion: Bool) -> Double { reducedMotion ? 0 : bank * 0.06 }
}

extension CoastalWorld {
    /// Places the gameplay camera. `snap` skips the lag (the first frame, or rewound time such as a crash replay).
    /// The menu and Reduced Motion never lag.
    func updateCamera(menu: Bool, waterMode: Bool, lateral: Double, speed: Double, boosting: Bool, flightLift: Double,
                      ahead: (lateralOffset: Double, elevation: Double), time: Double, dt: Double, snap: Bool) {
        let portrait = aspect < 0.8
        let x = menu ? 0.35 : lateral * 0.3 + routeOffset
        let rig = menu ? CameraRig.menuOffset(portrait: portrait, water: waterMode) : CameraRig.offset(portrait: portrait, water: waterMode)
        let eye = SIMD3(x, rig.height + routeHeight + flightLift, rig.depth)
        let target = SIMD3((x - routeOffset) * 0.25 + ahead.lateralOffset, (menu ? 0.5 : CameraRig.lookHeight) + ahead.elevation + flightLift, -CameraRig.lookAhead)
        let fov = menu ? (portrait ? 66 : 58) : CameraRig.fieldOfView(portrait: portrait, speed: speed, boosting: boosting, reducedMotion: reducedMotion)
        if snap || menu || reducedMotion || simd_distance(eye, cameraEye) > 6 {
            cameraEye = eye; cameraTarget = target; cameraFOV = fov
        } else {
            cameraEye = CameraRig.follow(cameraEye, toward: eye, rate: CameraRig.followRate, dt: dt)
            cameraTarget = CameraRig.follow(cameraTarget, toward: target, rate: CameraRig.followRate, dt: dt)
            cameraFOV = fov + (cameraFOV - fov) * exp(-CameraRig.fovRate * dt)
        }
        let shake = boosting && !reducedMotion ? sin(time * 30) * 0.025 : 0
        camera.position = vector(cameraEye.x, cameraEye.y + shake, cameraEye.z)
        // An explicit world up: plain look(at:) keeps the node's current up, so last frame's lean would accumulate.
        camera.look(at: vector(cameraTarget.x, cameraTarget.y, cameraTarget.z), up: vector(0, 1, 0), localFront: vector(0, 0, -1))
        camera.simdLocalRotate(by: simd_quatf(angle: Float(menu ? 0 : CameraRig.lean(bank: bank, reducedMotion: reducedMotion)), axis: SIMD3<Float>(0, 0, 1)))
        camera.camera?.fieldOfView = CGFloat(cameraFOV)
    }
}
```

Then edit `Sources/CoastalWorld.swift`. Each find text occurs exactly once:

1. Access: route offset and height. Find:

```swift
    private var routeOffset = 0.0
    private var routeHeight = 0.0
```

   Replace with:

```swift
    var routeOffset = 0.0
    var routeHeight = 0.0
```

2. Access: aspect. Find:

```swift
    private var aspect = 0.5
```

   Replace with:

```swift
    var aspect = 0.5
```

3. Camera rig state, after `var bank = 0.0`. Find:

```swift
    var bank = 0.0
```

   Replace with:

```swift
    var bank = 0.0
    var cameraEye = SIMD3<Double>(0, 0, 0)
    var cameraTarget = SIMD3<Double>(0, 0, 0)
    var cameraFOV = 66.0
```

4. Snap on the first frame and on rewound time (crash replay), in `update` before `dt`. Find:

```swift
        let dt = min(0.05, max(0, time - lastTime))
```

   Replace with:

```swift
        let rewound = time < lastTime || lastTime == 0
        let dt = min(0.05, max(0, time - lastTime))
```

5. Delete the now-unused `motion` (the shake moves into `updateCamera`). Delete:

```swift
        let motion = reducedMotion ? 0.0 : 1.0
```

6. Delete the drone's world-fixed position (it moves below the camera block). Delete:

```swift
        drone.position = vector(sin(time * 0.9) * 0.8, 2.5 + sin(time * 2) * 0.16, running ? 4.5 : 5.8)
```

7. Replace the camera block. Find:

```swift
        let desiredX = isMenu ? 0.35 : simulation.lateral * 0.3 + routeOffset
        let cameraHeight = waterMode ? 5.4 : 6.1
        camera.position = vector(desiredX, cameraHeight + routeHeight + flightLift + (boosting ? sin(time * 30) * 0.025 * motion : 0), aspect < 0.8 ? 11.8 : 10.4)
        let cameraRoute = isMenu ? route : simulation.routeTransform(atAheadDistance: 14)
        camera.look(at: vector((desiredX - routeOffset) * 0.25 + cameraRoute.lateralOffset, 0.5 + cameraRoute.elevation + flightLift, -14))
        camera.camera?.fieldOfView = (aspect < 0.8 ? 66 : 58) + (boosting && !reducedMotion ? 5 : 0)
```

   Replace with:

```swift
        updateCamera(menu: isMenu, waterMode: waterMode, lateral: simulation.lateral, speed: simulation.speed, boosting: boosting, flightLift: flightLift,
                     ahead: isMenu ? route : simulation.routeTransform(atAheadDistance: CameraRig.lookAhead), time: time, dt: dt, snap: rewound)
        // The drone keeps its old place in the frame (3.6 m under and 7.3 m ahead of the camera), so the closer camera does not enlarge it over the runner.
        drone.position = vector(cameraEye.x + sin(time * 0.9) * 0.8, cameraEye.y - 3.6 + sin(time * 2) * 0.16, cameraEye.z - 7.3)
```

8. The portal widens from the rig's current field of view (`updateJourney`). Find:

```swift
            camera.camera?.fieldOfView = (aspect < 0.8 ? 66 : 58) + sin(progress * .pi / 2) * 24
```

   Replace with:

```swift
            camera.camera?.fieldOfView = CGFloat(cameraFOV + sin(progress * .pi / 2) * 24)
```

- [ ] **Step 5: Run the test to verify it passes.** Run the Step 3 command, then `./work/phase4/fx-tests`.
  - Expected: six `runner share …` lines, each at ×1.15 or more. The planning build printed ×1.243, ×1.255, ×1.241, ×1.253, ×1.174 and ×1.181. Then `lane change: max camera lag 0.190 m, max lean 0.0285`, then `FXTests passed`.
  - Red checks done in planning (each mutant failed its test):
    - plain `look(at:)` → `hazard at z -100.0 too close to the runner's head`, because the lean accumulates;
    - follow by `1 − rate·dt` → `follow depends on frame rate`;
    - lean not gated → `Reduced Motion: the camera must not lean`;
    - the old offsets → `runner must be ≥1.15× its phase-3 screen height` (×1.045).

- [ ] **Step 6: Wire the test and the harness.**
  - In `Scripts/test.sh`, replace the final `printf` line with:

```bash
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  Tests/FXTests.swift -o "$test_work/fx-tests"
"$test_work/fx-tests"
printf 'Test executables retained at %s\n' "$test_work"
```

  - In `Scripts/RenderPreview.swift`, replace the final `print(name, …)` line with:

```swift
            // Live particles the emitters sustain (looping rate × life, plus attached bursts). ms stays last: the A/B awk reads $NF.
            var particles = 0.0
            world.scene.rootNode.enumerateHierarchy { node, _ in
                for s in node.particleSystems ?? [] { particles += Double(s.birthRate) * Double(s.loops ? s.particleLifeSpan : s.emissionDuration) }
            }
            print(name, String(format: "mean=%.3f", sum / Double(max(1, samples))), "crushed=\(pct(crushed))", "clipped=\(pct(clipped))",
                  String(format: "particles=%.0f", particles), String(format: "ms=%.1f", ms))
```

  - Create `Scripts/FXPreview.swift`:

```swift
// FX and camera shots: Scripts/fx.sh <label>  ->  work/shots/<label>/*.png, each with its live particle count.
// Every sim frame is also rendered (small, untimed) so particle systems simulate between events, as they do in the app.
import AppKit
import Metal
import SceneKit

@main struct FXPreview {
    static let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")

    /// Live particles the attached emitters sustain: looping systems rate × life, plus each attached burst's size.
    static func particles(_ scene: SCNScene) -> Double {
        var total = 0.0
        scene.rootNode.enumerateHierarchy { node, _ in
            for s in node.particleSystems ?? [] { total += Double(s.birthRate) * Double(s.loops ? s.particleLifeSpan : s.emissionDuration) }
        }
        return total
    }

    struct Shot {
        let world: CoastalWorld, renderer: SCNRenderer, size: CGSize
        var run = RunnerSimulation(), time = 0.0
        init(_ mode: RunMode, stage: Int, size: CGSize = CGSize(width: 900, height: 1500), reducedMotion: Bool = false) {
            world = CoastalWorld(assetsURL: FXPreview.resources)
            world.applyQuality(.ultra)
            world.resize(aspect: Double(size.width / size.height))
            world.reducedMotion = reducedMotion
            renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = world.scene
            renderer.pointOfView = world.camera
            self.size = size
            run.start(seed: 7, mode: mode, startStage: stage)
        }
        /// Steps the sim at 60 fps. `track` replaces the entities each frame (default: keep the 18 m ahead of the runner clear).
        mutating func step(_ frames: Int, track: ((RunnerSimulation) -> [TrackEntity])? = nil) {
            for _ in 0..<frames {
                run.replaceTrackForTesting(track?(run) ?? run.entities.filter { $0.z > 18 }, generate: track == nil)
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                world.update(simulation: run, character: "milo", board: "tideline", time: time)
                _ = renderer.snapshot(atTime: time, with: CGSize(width: 90, height: 150), antialiasingMode: .none)
            }
        }
        func shoot(_ name: String, into out: URL) throws {
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed: \(name)") }
            try png.write(to: out.appendingPathComponent(name + ".png"))
            print(name, String(format: "particles=%.0f speed=%.1f fov=%.1f", FXPreview.particles(world.scene), run.speed, Double(world.camera.camera!.fieldOfView)))
        }
    }

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "work/shots/fx")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Top speed: Forge cruise (42 m/s), widest field of view (and speed lines from Task 4); then Reduced Motion.
        var fast = Shot(.odyssey, stage: 5)
        fast.step(240)
        try fast.shoot("top-speed", into: out)
        var calm = Shot(.odyssey, stage: 5, reducedMotion: true)
        calm.step(240)
        try calm.shoot("top-speed-reduced-motion", into: out)
        // Lane-change lean and lag, portrait and landscape, 6 frames into a move right on Mars.
        for (name, size) in [("lane-lean", CGSize(width: 900, height: 1500)), ("lane-lean-wide", CGSize(width: 1600, height: 900))] {
            var lean = Shot(.odyssey, stage: 2, size: size)
            lean.step(150)
            lean.run.act(.right)
            lean.step(6)
            try lean.shoot(name, into: out)
        }
        print("wrote", out.path)
    }
}
```

  - Create `Scripts/fx.sh`, then run `chmod +x Scripts/fx.sh`:

```bash
#!/bin/bash
# FX and camera shots: Scripts/fx.sh <label>  ->  work/shots/<label>/*.png, each with its live particle count.
set -euo pipefail
cd "$(dirname "$0")/.."
label="${1:-fx}"
mkdir -p work/mc "work/shots/$label"
sources=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift)
sources+=(Sources/World*.swift)
swiftc -O -swift-version 5 -module-cache-path work/mc "${sources[@]}" Scripts/FXPreview.swift -o work/fx-preview
./work/fx-preview "work/shots/$label"
```

  - Run `xcodegen generate`. `git diff --stat CoastlineRush.xcodeproj` must show only `WorldCamera.swift` references for both targets.

- [ ] **Step 7: Task gate** with `L=p4-t1`.
  - Expected A/B on the planning build (camera only, 2 pairs): ratios 0.966–1.022, and every mean-delta ≤ 0.010.
  - Open `lane-lean`, `lane-lean-wide`, `top-speed` and `top-speed-reduced-motion`. The runner must be visibly larger and lower in frame. A slight roll must show in `lane-lean*` (none in the Reduced Motion shot), with the far track still visible.
  - Also run `bash Scripts/runner.sh p4-t1-runner`. Its `gameplay.png` is the live camera. Its `menu.png` must match `work/shots/p3-final/menu.png` in framing.

- [ ] **Step 8: Commit.**

```bash
git add Sources/WorldCamera.swift Sources/CoastalWorld.swift Tests/FXTests.swift Scripts/test.sh Scripts/FXPreview.swift Scripts/fx.sh Scripts/RenderPreview.swift CoastlineRush.xcodeproj
git commit -m "feat: gameplay camera rig: lower and closer (runner ×1.17–1.26 on screen), frame-rate-independent follow, speed-scaled FOV, lane-change lean

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Per-world white balance and rim light

**Files:**
- Modify: `Sources/WorldLook.swift` (the struct at L4–15, the table at L18–58, `applyLook` L75)
- Modify: `Sources/CoastalWorld.swift` (L29 `worldSunNode`; `makeLighting` rim at L581–587)
- Test: `Tests/LookTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `WorldLook.rimColor: String` and `WorldLook.rimIntensity: Double`;
  - `CoastalWorld.worldRim: SCNLight?` (`private(set)`).
- Starting values:

| World | temperature | tint | rim colour | rim intensity |
|---|---|---|---|---|
| harbor | 0.25 | 0.05 | 72B8F8 | 310 (today's value) |
| orbit | −0.35 | 0.0 | A9D4FF | 1100 |
| mars | 0.45 | 0.08 | FFB27A | 360 |
| verdant | −0.15 | −0.2 | 7DFFD8 | 380 |
| cryo | −0.5 | −0.03 | BFE3FF | 420 |
| forge | 0.55 | 0.1 | FF8A4A | 450 |

- [ ] **Step 1: Write the failing test.** Apply these edits to `Tests/LookTests.swift`:

1. Doc line. Find:

```swift
/// Verifies that every world applies its look and that the grading LUT stays off.
```

   Replace with:

```swift
/// Verifies that every world applies its look (grading, fog, white balance, rim) and that the grading LUT stays off.
```

2. Per-world checks. Find:

```swift
            precondition(abs(Double(world.scene.fogEndDistance) - look.fogEnd) < 0.001, "\(stage): fog not applied")
```

   Replace with:

```swift
            precondition(abs(Double(world.scene.fogEndDistance) - look.fogEnd) < 0.001, "\(stage): fog not applied")
            precondition(abs(Double(camera.whiteBalanceTemperature) - look.temperature) < 0.001 && abs(Double(camera.whiteBalanceTint) - look.tint) < 0.001, "\(stage): white balance not applied")
            precondition(abs(Double(world.worldRim!.intensity) - look.rimIntensity) < 0.001, "\(stage): rim light not applied")
```

3. Table checks. Find:

```swift
        // 2. Performance tier drops grain; ultra keeps it.
```

   Replace with:

```swift
        // Phase 4: each world has its own bounded white balance, and Orbit's rim light is at least twice any other world's.
        let looks = WorldStage.allCases.map(\.look)
        precondition(Set(looks.map { "\($0.temperature) \($0.tint)" }).count == looks.count, "every world needs its own white balance")
        precondition(looks.allSatisfy { abs($0.temperature) <= 0.6 && abs($0.tint) <= 0.25 }, "white balance outside ±0.6 temperature / ±0.25 tint")
        precondition(WorldStage.allCases.allSatisfy { $0 == .orbit || WorldStage.orbit.look.rimIntensity >= 2 * $0.look.rimIntensity }, "Orbit needs the strong rim")
        // 2. Performance tier drops grain; ultra keeps it.
```

- [ ] **Step 2: Run it to verify it fails.**
Run (bash): `swiftc -swift-version 5 -module-cache-path work/mc Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift Tests/LookTests.swift -o work/phase4/look-tests`
Expected: compile errors `value of type 'CoastalWorld' has no member 'worldRim'` and `… 'WorldLook' has no member 'rimIntensity'`.

- [ ] **Step 3: Implement.** Edit `Sources/WorldLook.swift`:

1. WorldLook fields. Find:

```swift
    var temperature: Double, tint: Double
```

   Replace with:

```swift
    /// White balance in SceneKit's normalised units: temperature > 0 warms (0.3 is subtle, 1 strong); tint > 0 is magenta, < 0 green.
    var temperature: Double, tint: Double
    /// Back light from behind-right that outlines the runner and props. Orbit's is the strongest.
    var rimColor: String, rimIntensity: Double
```

2. Harbor. Find:

```swift
exposure: -0.35, contrast: 0.08, saturation: 1.06, temperature: 0, tint: 0,
                             bloomIntensity: 0.32,
```

   Replace with:

```swift
exposure: -0.35, contrast: 0.08, saturation: 1.06, temperature: 0.25, tint: 0.05,
                             rimColor: "72B8F8", rimIntensity: 310, bloomIntensity: 0.32,
```

3. Orbit. Find:

```swift
exposure: 1.3, contrast: 0.0, saturation: 1.05, temperature: 0, tint: 0,
                             bloomIntensity: 0.45,
```

   Replace with:

```swift
exposure: 1.3, contrast: 0.0, saturation: 1.05, temperature: -0.35, tint: 0.0,
                             rimColor: "A9D4FF", rimIntensity: 1100, bloomIntensity: 0.45,
```

4. Mars. Find:

```swift
exposure: -0.2, contrast: 0.10, saturation: 1.02, temperature: 0, tint: 0,
                             bloomIntensity: 0.3,
```

   Replace with:

```swift
exposure: -0.2, contrast: 0.10, saturation: 1.02, temperature: 0.45, tint: 0.08,
                             rimColor: "FFB27A", rimIntensity: 360, bloomIntensity: 0.3,
```

5. Verdant. Find:

```swift
exposure: -0.15, contrast: 0.12, saturation: 1.12, temperature: 0, tint: 0,
                             bloomIntensity: 0.55,
```

   Replace with:

```swift
exposure: -0.15, contrast: 0.12, saturation: 1.12, temperature: -0.15, tint: -0.2,
                             rimColor: "7DFFD8", rimIntensity: 380, bloomIntensity: 0.55,
```

6. Cryo. Find:

```swift
exposure: -0.55, contrast: 0.06, saturation: 0.95, temperature: 0, tint: 0,
                             bloomIntensity: 0.4,
```

   Replace with:

```swift
exposure: -0.55, contrast: 0.06, saturation: 0.95, temperature: -0.5, tint: -0.03,
                             rimColor: "BFE3FF", rimIntensity: 420, bloomIntensity: 0.4,
```

7. Forge. Find:

```swift
exposure: -0.2, contrast: 0.18, saturation: 1.08, temperature: 0, tint: 0,
                             bloomIntensity: 0.6,
```

   Replace with:

```swift
exposure: -0.2, contrast: 0.18, saturation: 1.08, temperature: 0.55, tint: 0.1,
                             rimColor: "FF8A4A", rimIntensity: 450, bloomIntensity: 0.6,
```

8. ApplyLook sets the rim. Find:

```swift
        worldAmbient?.color = color(look.ambientColor)
```

   Replace with:

```swift
        worldRim?.color = color(look.rimColor)
        worldRim?.intensity = CGFloat(look.rimIntensity)
        worldAmbient?.color = color(look.ambientColor)
```

Then edit `Sources/CoastalWorld.swift`:

1. Store the rim light, after `worldSunNode`. Find:

```swift
    private(set) var worldSunNode: SCNNode?
```

   Replace with:

```swift
    private(set) var worldSunNode: SCNNode?
    private(set) var worldRim: SCNLight?
```

2. MakeLighting: the rim's colour and intensity come from the look. Find:

```swift
        rim.light?.color = color("72B8F8")
        rim.light?.intensity = 310
```

   Replace with:

```swift
        worldRim = rim.light   // colour and intensity per world: applyLook
```

- [ ] **Step 4: Run the test to verify it passes.** Run the Step 2 command, then `./work/phase4/look-tests`. Expected: `LookTests passed`.
  - Red check done in planning: Orbit's rim at 600 → `Orbit needs the strong rim`.

- [ ] **Step 5: Task gate** with `L=p4-t2`.
  - The planning build at this stage (2 pairs) measured ratios 0.98–1.01 and an orbit mean shift of +0.035 (the strong rim and the cool balance). Harbor was +0.010 here; it reaches +0.034 once Task 3's mist is added. Both are within the ±0.05 rule.
  - Open `work/shots/p4-t2-ab/orbit.png`. The runner's edges (helmet, pauldrons) must read as rim-lit against the black sky, without clipping white.
  - Open `harbor.png` and `forge.png` (warmer) and `cryo.png` (cooler) against BASE `work/phase4/base/work/shots/ab/`.

- [ ] **Step 6: Commit.**

```bash
git add Sources/WorldLook.swift Sources/CoastalWorld.swift Tests/LookTests.swift
git commit -m "feat: per-world white balance and rim light (strong rim in Orbit)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Ambient particles per world

**Files:**
- Create: `Sources/WorldFX.swift`
- Modify: `Sources/CoastalWorld.swift` (L76 stored property; L154 `init`; L1464 `image()` access; the `update` line after Task 1's drone line)
- Modify: `Sources/WorldLook.swift` (`applyLook`, L97)
- Modify: `Tests/FXTests.swift`, `Scripts/FXPreview.swift`
- Regenerate: `CoastlineRush.xcodeproj`

**Interfaces:**
- Consumes: `cameraEye`, `routeHeight` (Task 1).
- Produces:
  - `struct AmbientFX` and `WorldStage.ambient`;
  - `CoastalWorld.fxScale: Double` (0.5 / 0.75 / 1.0);
  - `func softDot() -> CGImage?`;
  - `func dress(_:life:size:tint:opacity:additive:)`;
  - `func makeFX()`, `func applyAmbient(_:)`, `func updateAmbient(speed:)`;
  - stored `ambientNode: SCNNode`, `ambientFX: SCNParticleSystem`;
  - internal `image(width:height:draw:)`.
- Starting values (live particles at ultra; the budget is ≤ 160 per world):

| World | look | count | life s | size m | drift m/s | flow × run | heights m | blend |
|---|---|---|---|---|---|---|---|---|
| harbor | sea mist C9D8E6 α0.12 | 16 | 6 | 6.0 ±1.5 | (0.4, 0.05, 0) | 1 | 0.2–3 | alpha |
| orbit | star streaks DDEBFF α0.8, stretch 0.08 | 80 | 1.2 | 0.10 | 0 | 1.8 | 1–14 | additive |
| mars | dust E8B48A α0.5 | 120 | 3 | 0.25 ±0.10 | (2.2, 0.2, 0) crosswind | 1 | 0.1–6 | alpha |
| verdant | spores B8FFE6 α0.8 | 70 | 5 | 0.20 | (0, 0.35, 0) rising | 1 | 0.3–7 | additive |
| cryo | snow F2F8FF α0.85 | 160 | 3 | 0.18 | (0.4, −1.8, 0) falling | 1 | 0.5–9 | alpha |
| forge | embers FFA050 α0.9, stretch 0.02 | 90 | 2.2 | 0.18 | (0, 1.6, 0) rising | 1 | 0–6 | additive |

  - The emitter volume is 22 × (heights) × 56 m, centred 22 m ahead and following the camera's x.
  - At run speed, a particle's life is cut to the time it takes to travel 25 m, so the budget stays in view; the birth rate holds the live count.

- [ ] **Step 1: Write the failing test.** In `Tests/FXTests.swift`, insert before `print("FXTests passed")`:

```swift
        // 5. Ambient particles: each world has its own; the live budget is count × tier scale; the flow heading is a unit
        //    vector (SceneKit multiplies particleVelocity by its length).
        do {
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            var time = 0.0
            for (quality, scale) in [(RenderQuality.performance, 0.5), (.balanced, 0.75), (.ultra, 1.0)] {
                world.applyQuality(quality)
                for (index, stage) in WorldStage.allCases.enumerated() {
                    var run = RunnerSimulation(); run.start(seed: 3, mode: .odyssey, startStage: index)
                    for _ in 0..<3 { step(world, &run, &time) }
                    let a = stage.ambient, fx = world.ambientFX
                    let live = Double(fx.birthRate * fx.particleLifeSpan)
                    precondition(abs(live - a.count * scale) < 0.5, "\(stage) \(quality): \(live) live particles, expected \(a.count * scale)")
                    precondition(a.count <= 160 && a.size <= 6, "\(stage): ambient budget is ≤160 particles of ≤6 m")
                    let d = fx.emittingDirection
                    precondition(abs(Double(d.x * d.x + d.y * d.y + d.z * d.z) - 1) < 1e-3, "\(stage): ambient heading must be a unit vector")
                }
            }
            precondition(Set(WorldStage.allCases.map(\.ambient.tint)).count == WorldStage.allCases.count, "every world needs its own ambient particles")
        }
```

- [ ] **Step 2: Run it to verify it fails.** Compile FXTests (the Task 1 Step 3 command). Expected: compile errors `type 'WorldStage' has no member 'ambient'` and `value of type 'CoastalWorld' has no member 'ambientFX'`.

- [ ] **Step 3: Implement.** Create `Sources/WorldFX.swift`:

```swift
import SceneKit

/// A world's ambient particles. `count` is the live particles at ultra quality.
struct AmbientFX {
    var tint: String, opacity: Double
    var count: Double, life: Double, size: Double, sizeVariation: Double
    /// World-space drift (m/s) on top of the run: the air streams past at `flow` × run speed (1 = still air).
    var drift: SIMD3<Double>, flow: Double
    /// Birth heights above the route (m).
    var low: Double, high: Double
    var additive: Bool, stretch: Double
}

extension WorldStage {
    var ambient: AmbientFX {
        switch self {
        case .harbor:   // low sea mist: few, huge, faint
            return AmbientFX(tint: "C9D8E6", opacity: 0.12, count: 16, life: 6, size: 6.0, sizeVariation: 1.5,
                             drift: SIMD3(0.4, 0.05, 0), flow: 1, low: 0.2, high: 3, additive: false, stretch: 0)
        case .orbit:    // star streaks rushing past faster than the run
            return AmbientFX(tint: "DDEBFF", opacity: 0.8, count: 80, life: 1.2, size: 0.10, sizeVariation: 0.03,
                             drift: SIMD3(0, 0, 0), flow: 1.8, low: 1, high: 14, additive: true, stretch: 0.08)
        case .mars:     // dust on a crosswind
            return AmbientFX(tint: "E8B48A", opacity: 0.5, count: 120, life: 3, size: 0.25, sizeVariation: 0.10,
                             drift: SIMD3(2.2, 0.2, 0), flow: 1, low: 0.1, high: 6, additive: false, stretch: 0)
        case .verdant:  // rising bioluminescent spores
            return AmbientFX(tint: "B8FFE6", opacity: 0.8, count: 70, life: 5, size: 0.20, sizeVariation: 0.08,
                             drift: SIMD3(0, 0.35, 0), flow: 1, low: 0.3, high: 7, additive: true, stretch: 0)
        case .cryo:     // falling snow
            return AmbientFX(tint: "F2F8FF", opacity: 0.85, count: 160, life: 3, size: 0.18, sizeVariation: 0.06,
                             drift: SIMD3(0.4, -1.8, 0), flow: 1, low: 0.5, high: 9, additive: false, stretch: 0)
        case .forge:    // rising embers
            return AmbientFX(tint: "FFA050", opacity: 0.9, count: 90, life: 2.2, size: 0.18, sizeVariation: 0.05,
                             drift: SIMD3(0, 1.6, 0), flow: 1, low: 0, high: 6, additive: true, stretch: 0.02)
        }
    }
}

extension CoastalWorld {
    /// Particle budget per quality tier: performance half, balanced three quarters, ultra full.
    var fxScale: Double { [0.5, 0.75, 1.0][qualityLevel] }

    /// A 64 px soft round sprite shared by every particle system (generated and cached).
    func softDot() -> CGImage? {
        if let cached = textureCache["fx-dot"] { return cached }
        let dot = image(width: 64, height: 64) { ctx in
            let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [color("FFFFFF").cgColor, color("FFFFFF", alpha: 0.35).cgColor, color("FFFFFF", alpha: 0).cgColor] as CFArray,
                                  locations: [0, 0.35, 1])!
            ctx.drawRadialGradient(fade, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        textureCache["fx-dot"] = dot
        return dot
    }

    /// Soft sprites, unsorted, alpha or additive. Opacity rides on the colour's alpha.
    func dress(_ system: SCNParticleSystem, life: Double, size: Double, tint: String, opacity: Double, additive: Bool) {
        system.particleImage = softDot()
        system.particleLifeSpan = CGFloat(life)
        system.particleSize = CGFloat(size)
        system.particleColor = color(tint, alpha: opacity)
        system.blendMode = additive ? .additive : .alpha
        system.sortingMode = .none
    }

    /// Builds the pooled ambient emitter once. Nothing is created per frame. A looping system restarts with `reset()`
    /// and is never re-added: re-adding a looping system to the same node stops it rendering (probe at 3781698).
    func makeFX() {
        ambientFX.birthLocation = .volume
        ambientNode.addParticleSystem(ambientFX)
        scene.rootNode.addChildNode(ambientNode)
    }

    /// Re-dresses the pooled ambient system for `stage` and restarts it pre-warmed, so the old world's particles vanish with it.
    func applyAmbient(_ stage: WorldStage) {
        let a = stage.ambient
        dress(ambientFX, life: a.life, size: a.size, tint: a.tint, opacity: a.opacity, additive: a.additive)
        ambientFX.particleSizeVariation = CGFloat(a.sizeVariation)
        ambientFX.stretchFactor = CGFloat(a.stretch)
        ambientFX.birthRate = CGFloat(a.count / a.life * fxScale)
        ambientFX.warmupDuration = CGFloat(a.life)   // offscreen snapshots and a new world start fully populated
        ambientFX.emitterShape = SCNBox(width: 22, height: CGFloat(a.high - a.low), length: 56, chamferRadius: 0)
        ambientFX.reset()
    }

    /// Per frame: the ambient volume follows the camera and the air streams past at run speed.
    func updateAmbient(speed: Double) {
        let a = renderedStage.ambient
        // The volume spans 50 m ahead to 6 m behind the runner. At speed a particle lives only while it travels about 25 m,
        // so the budget stays in view instead of streaming past the camera; the birth rate keeps the live count fixed.
        ambientNode.position = vector(cameraEye.x, routeHeight + (a.low + a.high) / 2, -22)
        let flow = a.drift + SIMD3(0, 0, a.flow * speed)
        let life = min(a.life, 25 / max(0.1, a.flow * speed))
        let heading = simd_normalize(flow)   // must be a unit vector: SceneKit scales particleVelocity by its length
        ambientFX.emittingDirection = vector(heading.x, heading.y, heading.z)
        ambientFX.particleVelocity = CGFloat(simd_length(flow))
        ambientFX.particleLifeSpan = CGFloat(life)
        ambientFX.birthRate = CGFloat(a.count * fxScale / life)
    }
}
```

Edit `Sources/CoastalWorld.swift`:

1. Pooled ambient emitter, after `private var landingSparks: [SCNNode] = []`. Find:

```swift
    private var landingSparks: [SCNNode] = []
```

   Replace with:

```swift
    private var landingSparks: [SCNNode] = []
    let ambientNode = SCNNode()
    let ambientFX = SCNParticleSystem()
```

2. Init builds the FX after the motion effects. Find:

```swift
        makeMotionEffects()
```

   Replace with:

```swift
        makeMotionEffects()
        makeFX()
```

3. Access: image(). Find:

```swift
    private func image(width: Int
```

   Replace with:

```swift
    func image(width: Int
```

4. Update: drive the ambient flow after the camera. Find:

```swift
        drone.position = vector(cameraEye.x + sin(time * 0.9) * 0.8, cameraEye.y - 3.6 + sin(time * 2) * 0.16, cameraEye.z - 7.3)
```

   Replace with:

```swift
        drone.position = vector(cameraEye.x + sin(time * 0.9) * 0.8, cameraEye.y - 3.6 + sin(time * 2) * 0.16, cameraEye.z - 7.3)
        updateAmbient(speed: running ? simulation.speed : 1.5)
```

Edit `Sources/WorldLook.swift`:

1. ApplyLook re-dresses the ambient particles (it already runs on every world change and quality change). Find:

```swift
        lens.colorGrading.contents = nil
```

   Replace with:

```swift
        lens.colorGrading.contents = nil
        applyAmbient(stage)
```

Run `xcodegen generate` (it adds `WorldFX.swift`).

- [ ] **Step 4: Run the test to verify it passes.** Compile and run FXTests. Expected: `FXTests passed`.

- [ ] **Step 5: Add the shots.** In `Scripts/FXPreview.swift`, insert before `print("wrote", out.path)`:

```swift
        // Ambient particles per world, 3 s in.
        for (index, name) in ["harbor", "orbit", "mars", "verdant", "cryo", "forge"].enumerated() {
            var shot = Shot(.odyssey, stage: index)
            shot.step(180)
            try shot.shoot("ambient-" + name, into: out)
        }
```

- [ ] **Step 6: Task gate** with `L=p4-t3`.
  - `fx.sh` printed these on the planning build: `ambient-harbor particles=16`, `orbit 115`, `mars 136`, `verdant 95`, `cryo 191`, `forge 122`. These include Task 4's speed lines, which add about 32 from 26 m/s; without them, expect the table's counts.
  - `render.sh` prints the same numbers, so the A/B timed frames include the particles.
  - Open the six `ambient-*` shots. Each world's particles must read (mist banks, streaks, dust, spores, snow, embers) without hiding the track or the hazards. Tune within the ranges.

- [ ] **Step 7: Commit.**

```bash
git add Sources/WorldFX.swift Sources/CoastalWorld.swift Sources/WorldLook.swift Tests/FXTests.swift Scripts/FXPreview.swift CoastlineRush.xcodeproj
git commit -m "feat: per-world ambient particles (mist, star streaks, dust, spores, snow, embers), pooled and quality-scaled

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Speed lines, footstep dust, landing burst and pickup sparkle

**Files:**
- Modify: `Sources/WorldFX.swift` (append)
- Modify: `Sources/CoastalWorld.swift`
  - L76 `landingSparks` becomes the pooled systems.
  - L154 `init`, L178 `applyQuality`, L332 landing.
  - The `update` line after `updateAmbient`.
  - L437–441 spark boxes, L463–469 spark animation.
- Modify: `Tests/FXTests.swift`, `Scripts/FXPreview.swift`

**Interfaces:**
- Consumes:
  - `dress`, `fxScale`, `softDot`, `applyAmbient`, `ambientFX` (Task 3);
  - `cameraEye`, `camera` (Task 1);
  - `feet`, `player`, `landingRoot`, `gait` and `gaitAmount` (Phase 3).
- Produces:
  - `WorldStage.deckDust: String`;
  - stored `landingSparkFX`, `landingDustFX`, `speedLines`, `sparkleFX: SCNParticleSystem`, `footDust: [SCNNode]`, `sparkleRoot: SCNNode`, `lastCoins: Int`;
  - `func makeMotionFX()`, `func applyBurstQuality()`, `func burst(_:at:)`;
  - `func updateMotionFX(simulation:running:gait:footing:height:boosting:)`.
- Starting values:
  - **Speed lines:** 90/s × 0.35 s, which is about 32 live at full. They are 0.025 m streaks (stretch 0.05) at 30 m/s, camera-local. They are born on a 3.2 ± 1.0 m ring 12 m ahead.
    - Off below 26 m/s, full at 40 m/s (smoothstep), and full while boosting.
    - Odyssey cruise speeds: harbor 17 (none), orbit 29, mars 33, verdant 36, cryo 39, forge 42.
  - **Footstep dust:** 70/s while a foot is in its first 0.6 rad of stance, which is about 3 puffs per step. Puffs are 0.4 m, α0.5, 0.45 s, in the world's `deckDust` colour. They leave at 0.9 × run speed and rise at 1.2 m/s².
  - **Landing:**
    - about 20 spark streaks (FFD9B0, 3.5 ± 1.5 m/s, gravity −6, 0.45 s);
    - about 22 dust puffs (0.45 m, 2.2 m/s, 0.6 s, in `deckDust`, or E6F7FF spray on water);
    - all of it from a 0.45 m ring under the existing ripple rings.
  - **Sparkle:** about 17 gold FFD66B sparks, 0.09 m, 2.4 m/s, 0.4 s, from a 0.3 m sphere at the runner's chest. It fires when `coins` rises.
  - `deckDust` per world: harbor 7E8A94, orbit 9FB4CC, mars C98A5E, verdant 7FC9A8, cryo E8F2FF, forge 8A6A5A.

- [ ] **Step 1: Write the failing test.** In `Tests/FXTests.swift`, insert before `print("FXTests passed")`:

```swift
        // 6. Speed lines: none below 26 m/s, in the menu or under Reduced Motion; on at Forge cruise; half on performance.
        do {
            func lines(_ mode: RunMode, _ stage: Int, _ quality: RenderQuality = .ultra, reducedMotion: Bool = false) -> Double {
                let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
                world.applyQuality(quality); world.reducedMotion = reducedMotion
                var run = RunnerSimulation(); run.start(seed: 3, mode: mode, startStage: stage)
                var time = 0.0
                for _ in 0..<30 { step(world, &run, &time) }
                return Double(world.speedLines.birthRate)
            }
            precondition(lines(.odyssey, 0) == 0, "no speed lines at harbor cruise (17 m/s)")
            precondition(lines(.odyssey, 5) > 0, "speed lines at Forge cruise (42 m/s)")
            precondition(abs(lines(.odyssey, 5, .performance) - lines(.odyssey, 5) * 0.5) < 1e-6, "performance halves the speed lines")
            precondition(lines(.odyssey, 5, reducedMotion: true) == 0, "Reduced Motion: no speed lines")
            let menu = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            menu.update(simulation: RunnerSimulation(), character: "milo", board: "tideline", time: 1)
            precondition(menu.speedLines.birthRate == 0, "no speed lines in the menu")
        }

        // 7. Footstep dust opens and closes with each stance, never in the air or on the jet ski.
        do {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 60)
            var open = [0, 0], shut = [0, 0]
            for _ in 0..<60 {
                step(world, &run, &time)
                for i in 0..<2 { if (world.footDust[i].particleSystems?.first?.birthRate ?? 0) > 0 { open[i] += 1 } else { shut[i] += 1 } }
            }
            precondition(open.allSatisfy { $0 > 0 } && shut.allSatisfy { $0 > 0 }, "each foot must puff on contact only (open \(open), shut \(shut))")
            run.act(.jump)
            for _ in 0..<12 {
                step(world, &run, &time)
                if run.height > 0.1 { precondition(world.footDust.allSatisfy { ($0.particleSystems?.first?.birthRate ?? 0) == 0 }, "no footstep dust in the air") }
            }
            var (water, ride, rideTime) = running(.jetSki, stage: 0, aspect: portrait, frames: 60)
            for _ in 0..<30 {
                step(water, &ride, &rideTime)
                precondition(water.footDust.allSatisfy { ($0.particleSystems?.first?.birthRate ?? 0) == 0 }, "no footstep dust on the jet ski")
            }
        }

        // 8. Bursts: a landing restarts the pooled sparks and dust (not under Reduced Motion); a collected coin restarts the
        //    sparkle. Across all of it the scene never holds more than the 7 pooled systems: nothing is created per frame or event.
        for reducedMotion in [false, true] {
            var (world, run, time) = running(.endless, stage: 0, aspect: portrait, frames: 60, reducedMotion: reducedMotion)
            let landing: SCNNode = field(world, "landingRoot")
            var pooled = Set<ObjectIdentifier>()
            func census() {
                world.scene.rootNode.enumerateHierarchy { node, _ in (node.particleSystems ?? []).forEach { pooled.insert(ObjectIdentifier($0)) } }
                precondition(pooled.count <= 7, "particle systems must be pooled (\(pooled.count) distinct)")
            }
            run.act(.jump)
            for _ in 0..<5 { step(world, &run, &time); census() }
            while run.height > 0 { step(world, &run, &time); census() }
            step(world, &run, &time); census()
            let attached = landing.particleSystems ?? []
            if reducedMotion { precondition(attached.isEmpty, "Reduced Motion: no landing burst") }
            else { precondition(attached.contains(world.landingSparkFX) && attached.contains(world.landingDustFX), "a landing must restart the pooled burst") }
            precondition(world.sparkleRoot.particleSystems?.isEmpty ?? true, "no sparkle before a pickup")
            let coins = run.coins
            var placed = false
            for _ in 0..<60 where run.coins == coins {
                run.replaceTrackForTesting(placed ? run.entities : [TrackEntity(id: 9_000, kind: .coin, lane: run.lane, z: 6, y: 0.9, length: 0.6)])
                placed = true
                run.update(dt: 1.0 / 60); time += 1.0 / 60
                world.update(simulation: run, character: "milo", board: "tideline", time: time); census()
            }
            precondition(run.coins > coins, "test setup: the coin must be collected")
            precondition(world.sparkleRoot.particleSystems?.contains(world.sparkleFX) ?? false, "a pickup must restart the pooled sparkle")
            for _ in 0..<120 { step(world, &run, &time); census() }
        }
        do {   // bursts scale with the tier too
            let world = CoastalWorld(assetsURL: URL(fileURLWithPath: "Resources"))
            world.applyQuality(.ultra)
            let full = [world.landingSparkFX, world.landingDustFX, world.sparkleFX].map { Double($0.birthRate) }
            world.applyQuality(.performance)
            let half = [world.landingSparkFX, world.landingDustFX, world.sparkleFX].map { Double($0.birthRate) }
            precondition(zip(full, half).allSatisfy { abs($0 * 0.5 - $1) < 1e-6 }, "performance halves every burst")
        }
```

- [ ] **Step 2: Run it to verify it fails.** Compile FXTests. Expected: compile errors `value of type 'CoastalWorld' has no member 'speedLines'` (and `footDust`, `landingSparkFX`, `sparkleRoot`).

- [ ] **Step 3: Implement.** Append to `Sources/WorldFX.swift`:

```swift

extension WorldStage {
    /// Footstep and landing dust on this world's deck.
    var deckDust: String {
        switch self {
        case .harbor: return "7E8A94"
        case .orbit: return "9FB4CC"
        case .mars: return "C98A5E"
        case .verdant: return "7FC9A8"
        case .cryo: return "E8F2FF"
        case .forge: return "8A6A5A"
        }
    }
}

extension CoastalWorld {
    /// Speed lines, footstep dust, the landing burst and the pickup sparkle: all pooled, built once.
    /// One-shot bursts restart by re-adding them (`burst`); `reset()` does not restart a finished one-shot.
    func makeMotionFX() {
        // Speed lines: thin streaks born on a ring 12 m ahead in camera space, flying out past the screen edges.
        dress(speedLines, life: 0.35, size: 0.025, tint: "FFFFFF", opacity: 0.35, additive: true)
        speedLines.emitterShape = SCNTorus(ringRadius: 3.2, pipeRadius: 1.0)
        speedLines.birthLocation = .volume
        speedLines.emittingDirection = vector(0, 1, 0)   // the emitter is turned so its +y points at the camera
        speedLines.particleVelocity = 30
        speedLines.stretchFactor = 0.05
        speedLines.isLocal = true
        speedLines.warmupDuration = 0.35
        speedLines.birthRate = 0
        let lineNode = SCNNode()
        lineNode.position = vector(0, 0.6, -12)
        lineNode.eulerAngles.x = scalar(.pi / 2)
        lineNode.addParticleSystem(speedLines)
        camera.addChildNode(lineNode)
        // Footstep dust: one emitter per foot, open only while that foot is planted. The puffs drift up and are left behind.
        for _ in 0..<2 {
            let puff = SCNParticleSystem()
            dress(puff, life: 0.45, size: 0.4, tint: "7E8A94", opacity: 0.5, additive: false)
            puff.emittingDirection = vector(0, 0, 1)
            puff.spreadingAngle = 6
            puff.acceleration = vector(0, 1.2, 0)
            puff.particleSizeVariation = 0.15
            puff.birthRate = 0
            let node = SCNNode()
            node.addParticleSystem(puff)
            scene.rootNode.addChildNode(node)
            footDust.append(node)
        }
        // Landing: spark streaks and a dust ring burst from the ripple rings' centre (landingRoot).
        dress(landingSparkFX, life: 0.45, size: 0.04, tint: "FFD9B0", opacity: 1, additive: true)
        landingSparkFX.particleColorVariation = SCNVector4(0.15, 0.3, 0, 0)
        landingSparkFX.particleVelocity = 3.5
        landingSparkFX.particleVelocityVariation = 1.5
        landingSparkFX.stretchFactor = 0.04
        landingSparkFX.acceleration = vector(0, -6, 0)
        dress(landingDustFX, life: 0.6, size: 0.45, tint: "7E8A94", opacity: 0.45, additive: false)
        landingDustFX.particleVelocity = 2.2
        // Pickup sparkle: a quick gold burst at the runner's chest whenever the coin count rises.
        dress(sparkleFX, life: 0.4, size: 0.09, tint: "FFD66B", opacity: 1, additive: true)
        sparkleFX.emitterShape = SCNSphere(radius: 0.3)
        sparkleFX.particleVelocity = 2.4
        let ring = SCNTorus(ringRadius: 0.45, pipeRadius: 0.06)
        for system in [landingSparkFX, landingDustFX, sparkleFX] {
            if system !== sparkleFX { system.emitterShape = ring }
            system.birthLocation = .surface
            system.birthDirection = .surfaceNormal
            system.emissionDuration = 0.05
            system.loops = false
        }
        scene.rootNode.addChildNode(sparkleRoot)
        applyBurstQuality()
    }

    /// Burst sizes follow the quality tier: about 20 sparks, 22 dust puffs and 17 sparkles at ultra.
    func applyBurstQuality() {
        landingSparkFX.birthRate = CGFloat(400 * fxScale)
        landingDustFX.birthRate = CGFloat(450 * fxScale)
        sparkleFX.birthRate = CGFloat(350 * fxScale)
    }

    /// Restarts pooled one-shot bursts at `node`.
    func burst(_ systems: [SCNParticleSystem], at node: SCNNode) {
        node.removeAllParticleSystems()
        systems.forEach(node.addParticleSystem)
    }

    /// Per frame: speed lines, footstep dust and the pickup sparkle. `footing` is the run cycle's strength while running
    /// on foot (0 otherwise) and `gait` its phase (left contact at 0, right at π).
    func updateMotionFX(simulation: RunnerSimulation, running: Bool, gait: Double, footing: Double, height: Double, boosting: Bool) {
        // Speed lines from 26 m/s (full at 40) or while boosting; never under Reduced Motion.
        let t = min(1, max(0, (simulation.speed - 26) / 14))
        let lines = running && !reducedMotion ? max(t * t * (3 - 2 * t), boosting ? 1 : 0) : 0
        speedLines.birthRate = CGFloat(lines * 90 * fxScale)
        // Each foot puffs for the first 0.6 rad of its stance; the dust is left behind at 0.9 × run speed.
        for (i, node) in footDust.enumerated() {
            var since = (gait - Double(i) * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if since < 0 { since += 2 * .pi }
            let planted = running && footing > 0.6 && height < 0.05 && since < 0.6
            let foot = feet[i].worldPosition
            node.position = vector(Double(foot.x), routeHeight + 0.06, Double(foot.z))
            node.particleSystems?.first?.birthRate = CGFloat(planted ? 70 * fxScale : 0)
            node.particleSystems?.first?.particleVelocity = CGFloat(simulation.speed * 0.9)
        }
        // Pickup sparkle: the simulation exposes `coins`, so a rise is a pickup (no simulation change).
        if running && simulation.coins > lastCoins {
            sparkleRoot.position = vector(Double(player.position.x), Double(player.position.y) + 1.25, -0.3)
            burst([sparkleFX], at: sparkleRoot)
        }
        lastCoins = simulation.coins
    }
}
```

Edit `Sources/WorldFX.swift` (inside `applyAmbient`):

1. ApplyAmbient also tints the footstep dust for the world. Find:

```swift
        ambientFX.reset()
```

   Replace with:

```swift
        for puff in footDust.compactMap({ $0.particleSystems?.first }) { puff.particleColor = color(stage.deckDust, alpha: 0.5) }
        ambientFX.reset()
```

Edit `Sources/CoastalWorld.swift`:

1. Replace the 18 spark boxes with pooled particle systems. Find:

```swift
    private var landingSparks: [SCNNode] = []
```

   Replace with:

```swift
    let landingSparkFX = SCNParticleSystem()
    let landingDustFX = SCNParticleSystem()
    let speedLines = SCNParticleSystem()
    var footDust: [SCNNode] = []
    let sparkleRoot = SCNNode()
    let sparkleFX = SCNParticleSystem()
    var lastCoins = 0
```

2. Init. Find:

```swift
        makeFX()
```

   Replace with:

```swift
        makeFX()
        makeMotionFX()
```

3. ApplyQuality: bursts scale with the tier (was: hide every other spark box on performance). Find:

```swift
        for (index, node) in landingSparks.enumerated() { node.isHidden = qualityLevel == 0 && index % 2 == 1 }
```

   Replace with:

```swift
        applyBurstQuality()
```

4. Landing: restart the burst with the world's dust (spray on water); none under Reduced Motion. Find:

```swift
            landingRoot.position = vector(Double(player.position.x), routeHeight + (waterMode ? 0.02 : 0.065), Double(player.position.z))
```

   Replace with:

```swift
            landingRoot.position = vector(Double(player.position.x), routeHeight + (waterMode ? 0.02 : 0.065), Double(player.position.z))
            landingDustFX.particleColor = color(waterMode ? "E6F7FF" : renderedStage.deckDust, alpha: 0.45)
            if !reducedMotion { burst([landingSparkFX, landingDustFX], at: landingRoot) }
```

5. Update: motion FX after the ambient flow. Find:

```swift
        updateAmbient(speed: running ? simulation.speed : 1.5)
```

   Replace with:

```swift
        updateAmbient(speed: running ? simulation.speed : 1.5)
        updateMotionFX(simulation: simulation, running: running, gait: gait, footing: running && !waterMode && !surfing && !flying ? gaitAmount : 0,
                       height: height, boosting: boosting)
```

6. MakeMotionEffects: delete the spark boxes. Delete:

```swift
        for i in 0..<18 {
            let speck = box(0.03, 0.03, 0.14, i % 2 == 0 ? "FFD9B0" : "AAE6F4", radius: 0, into: landingRoot)
            speck.geometry?.firstMaterial = material(i % 2 == 0 ? "FFD9B0" : "AAE6F4", emissive: true)
            speck.castsShadow = false; landingSparks.append(speck)
        }
```

7. UpdateMotionEffects: delete the spark animation (the rings stay). Delete:

```swift
            for (i, spark) in landingSparks.enumerated() {
                let angle = Double(i) / Double(landingSparks.count) * .pi * 2
                let spread = 0.25 + age * (2.2 + Double(i % 4) * 0.55)
                spark.position = vector(cos(angle) * spread, max(0, sin(age / 0.55 * .pi)) * (waterMode ? 0.6 : 0.35), sin(angle) * spread)
                spark.eulerAngles = vector(0, -angle, angle)
                spark.opacity = max(0, 1 - age / 0.55)
            }
```

- [ ] **Step 4: Run the test to verify it passes.** Compile and run FXTests. Expected: `FXTests passed`.
  - Red checks done in planning. Each of these failed its test:
    - dropping the Reduced Motion gate on the landing burst → `Reduced Motion: no landing burst`;
    - leaving `emittingDirection` unnormalised → `ambient heading must be a unit vector`;
    - a fresh copy of the spark system per landing → `a landing must restart the pooled burst`;
    - speed lines not gated → `Reduced Motion: no speed lines`;
    - footstep dust without the height and footing checks → `no footstep dust in the air`.

- [ ] **Step 5: Add the shots.** In `Scripts/FXPreview.swift`, insert before `print("wrote", out.path)`:

```swift
        // Footsteps on Mars: 3 frames after a foot's dust opens.
        var steps = Shot(.odyssey, stage: 2)
        steps.step(150)
        while steps.world.footDust.allSatisfy({ ($0.particleSystems?.first?.birthRate ?? 0) == 0 }) { steps.step(1) }
        steps.step(3)
        try steps.shoot("footstep", into: out)
        // Landing burst, 6 frames after touchdown in the harbor.
        var land = Shot(.endless, stage: 0)
        land.step(120)
        land.run.act(.jump)
        land.step(5)
        while land.run.height > 0 { land.step(1) }
        land.step(6)
        try land.shoot("landing", into: out)
        // Pickup sparkle: a coin placed in the runner's lane, shot 4 frames after it is collected.
        var pickup = Shot(.endless, stage: 0)
        pickup.step(120)
        let coins = pickup.run.coins
        var placed = false
        while pickup.run.coins == coins {
            pickup.step(1) { run in
                defer { placed = true }
                return placed ? run.entities : [TrackEntity(id: 9_000, kind: .coin, lane: run.lane, z: 8, y: 0.9, length: 0.6)]
            }
        }
        pickup.step(4) { $0.entities }
        try pickup.shoot("sparkle", into: out)
```

- [ ] **Step 6: Task gate** with `L=p4-t4`.
  - Open `top-speed` (streaks sweeping out from mid-frame) and `top-speed-reduced-motion` (none).
  - Open `footstep` (puffs at the planted boot; on the planning build they read faintly at full-frame scale, so raise `size`/`opacity` within the ranges if they are invisible), `landing` (sparks and a dust ring inside the ripple rings; the drone no longer covers the runner) and `sparkle` (a gold burst at the chest).
  - `WorldCacheAudit` prints `attachedSceneNodes<=1586` on the planning build, against 1599 at BASE: 18 spark boxes removed, 5 FX nodes added.

- [ ] **Step 7: Commit.**

```bash
git add Sources/WorldFX.swift Sources/CoastalWorld.swift Tests/FXTests.swift Scripts/FXPreview.swift
git commit -m "feat: speed lines, footstep dust, particle landing burst (replaces 18 spark boxes) and coin pickup sparkle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Final verification and before/after report

**Files:**
- Modify: `docs/superpowers/specs/2026-10-06-graphics-overhaul-design.md` (one note under Phase 4)

**Interfaces:**
- Consumes: everything above. No code changes.

- [ ] **Step 1: Full gate** with `L=p4-final`. Run the A/B with three pairs (`for i in 1 2 3`) for a steadier final table. Keep `work/phase4/p4-final-ab.txt`.
  - The planning build's 3-pair table, at the code of Tasks 1–4 (`work/phase4/p4-st4-ab.txt`), read:
    - cryo 1.006, forge 1.011, harbor 1.000, jetski 1.014, mars 1.000, orbit 1.005, verdant 1.012;
    - mean-deltas: harbor 0.034, orbit 0.038, jetski 0.024, the rest ≤ 0.006.

- [ ] **Step 2: Spec note.** Under `## Phase 4 — FX and camera` in the spec, after the last bullet, add this line. Write tuned values in place of the starting ones.
  - `- Note: the camera sits at 5.3/10.0 m (portrait) and 4.8/8.9 m (landscape), follows at rate 7/s (snapping in the menu, on replay rewind and under Reduced Motion), widens by up to 3° with speed and leans bank × 0.06; the runner is ≥1.15× its phase-3 screen height in every FXTests case. Particles are pooled SCNParticleSystems (≤7 in the scene) on one generated sprite; looping systems restart with reset(), one-shots by re-adding; motion blur stays off on every tier.`

- [ ] **Step 3: Before/after pairs.**
  - World pairs: `work/phase4/base/work/shots/ab/<world>.png` against `work/shots/p4-final-ab/<world>.png` for the seven worlds.
  - FX shots: `work/shots/p4-final/` for all of `ambient-*`, `top-speed*`, `lane-lean*`, `footstep`, `landing` and `sparkle`.
  - Runner: `bash Scripts/runner.sh p4-final-runner`. Compare `gameplay.png` and `menu.png` with `work/shots/p3-final/`. The menu must be identical in framing.
  - Open each with Read. Give the controller the paths with a one-line verdict per pair.

- [ ] **Step 4: Report.** Return the following to the controller:
  - the FXTests runner-share lines (×ratios);
  - the A/B table;
  - the `particles=` line per shot;
  - every tuned value against its starting value;
  - any deferred minor issues.

- [ ] **Step 5: Commit.**

```bash
git add docs/superpowers/specs/2026-10-06-graphics-overhaul-design.md
git commit -m "docs: phase 4 FX and camera note (rig values, particle pooling rules, no motion blur)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Spec coverage (self-review)

| Spec / controller requirement | Task |
|---|---|
| Ambient particles: harbor mist, orbit star streaks, Mars dust, Verdant spores, Cryo snow, Forge embers | T3 |
| Speed lines above a threshold (26 m/s; boost forces them) | T4 |
| Footstep dust on footfalls (the gait phase, from Phase 3) | T4 |
| Upgraded landing burst, not duplicated: particle sparks and dust replace the 18 boxes; the rings stay | T4 |
| Pickup sparkle only if observable without simulation changes: `coins` rise | T4 |
| Camera slightly lower, frame-rate-independent lag, speed-scaled field of view, lane-change lean | T1 |
| Per-world white balance and rim light, strong rim in Orbit | T2 |
| Runner screen height ≥ 1.15 × Phase 3, measured (baseline 0.161 portrait, 0.212 landscape) | T1 test 1 |
| Hazards at z −100 / −135 (and −200) on every lane on screen in portrait and landscape; camera stays clear of the recycle line | T1 test 2 |
| Quality tiers: performance half, balanced 0.75, ultra full; no grain on performance (LookTests); no motion blur on any tier | T3, T4 tests; LookTests |
| Reduced Motion: no shake, speed lines, field-of-view change, lean or lag; no landing burst | T1 test 4, T4 tests |
| WorldCacheAudit bounds; pooled emitters (≤ 7 systems, none per frame) | Task gate audit; T4 test 8 |
| A/B within +5% of BASE `3781698` with honest particles (warm-up and `particles=` printed) | Task gate; Reference facts |
| `World*.swift` naming, `xcodegen`, FXTests in `test.sh`, harness shots in `work/shots/<label>/` with particle counts | T1, T3 |
| Before/after renders, test/audit/builds, frame-time comparison | Task gate, T5 |

Placeholder scan: every code step shows its code, and no step defers work. Names are consistent across tasks: `cameraEye`, `fxScale`, `dress`, `applyAmbient`, `updateAmbient`, `makeMotionFX`, `updateMotionFX`, `burst`, `deckDust`, `landingSparkFX`, `landingDustFX`, `speedLines`, `footDust`, `sparkleRoot`, `sparkleFX`, `lastCoins`.

## Planning validation (scratch builds, `work/phase4/st1`…`st4`)

The planner built every task's code on scratch copies of `3781698`. Each copy was cut by `work/phase4/stages/build.py` from the same text this plan shows (`stages/code.py`). Results:

| Check | st1 (T1) | st2 (T1–2) | st3 (T1–3) | st4 (T1–4) |
|---|---|---|---|---|
| `Scripts/test.sh` (all suites, including FXTests, LookTests, MotionTests, RunnerTests, MaterialTests) | exit 0 | exit 0 | exit 0 | exit 0 |
| New tests fail before their task's code | FXTests: `cannot find 'CameraRig'` | LookTests: no `worldRim` / `rimIntensity` | FXTests: no `ambient` / `ambientFX` | FXTests: no `speedLines` / `footDust` |
| `xcodegen generate` pbxproj diff | +6 lines (`WorldCamera.swift`) | — | +12 (`WorldFX.swift` too) | +12 |
| `xcodebuild` macOS / iOS | SUCCEEDED / SUCCEEDED | — | — | SUCCEEDED / SUCCEEDED |
| `Scripts/audit.sh` | — | — | — | Route, water, checkpoint, cache, skill and resume audits PASS. `WorldCacheAudit`: destinations≤2, pool≤96, attachedSceneNodes≤1586 (BASE 1599). The legacy-continuity step's `git archive e3049e5 Sources/…` cannot run from a nested scratch directory; it touches only simulation files, which this plan does not change. |
| A/B vs BASE (ms ratio; mean-delta) | camera build, 2 pairs: 0.966–1.022; ≤ 0.010 | 2 pairs: 0.98–1.01 (harbor's BASE side had one 366 ms outlier); orbit +0.035 | — | 3 pairs: 1.000–1.014, all `ok`; harbor +0.034, orbit +0.038, jetski +0.024 |

- **FXTests (st4):**
  - runner share ×1.243 / ×1.255 (endless), ×1.241 / ×1.253 (Odyssey harbor), ×1.174 / ×1.181 (Forge, 42 m/s);
  - lane change: max lag 0.190 m, max lean 0.0285.
- **Mutation checks (st4):** 10 of 10 mutants failed their test. They were:
  - the Reduced Motion landing gate;
  - an unnormalised heading;
  - a new system per landing;
  - plain `look(at:)`;
  - frame-rate-dependent follow;
  - lean under Reduced Motion;
  - the old camera offsets;
  - speed lines under Reduced Motion;
  - dust in the air;
  - a weak Orbit rim.
- **`fx.sh` (st4)** printed `particles=` per shot:
  - top-speed 122 (fov 67.0), and Reduced Motion 90 (fov 64.0, no lines);
  - lane-lean 136;
  - ambient: harbor 16, orbit 115, mars 136, verdant 95, cryo 191, forge 122;
  - footstep 136, landing 58, sparkle 34.
- **Shots viewed:**
  - ambient particles read in every world;
  - speed lines show at Forge and are absent under Reduced Motion;
  - the lean is visible in the lane change;
  - the landing sparks and dust ring are inside the ripple rings;
  - the gold sparkle is at the chest;
  - the runner is larger and lower in frame.
- **Planning artefacts:** in `work/phase4/` (`stages/`, `probe/`, `st1`…`st4`, `p4-st4-ab.txt`, `sheet-*.png`).
