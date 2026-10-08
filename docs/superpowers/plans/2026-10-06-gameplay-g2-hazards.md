# Gameplay Overhaul G2 — New Hazards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Portal Odyssey six hazards whose colliders depend on time or motion (a lane-changer, a timed laser gate, a gap wall, a stacked hazard, a real meteor and a collapsing deck). Each one telegraphs at least 1.0 s ahead on Standard and 0.8 s on Expert. What the player sees is exactly what collides, and the hazard-reading bot still clears every course.

**Architecture:**
- `TrackEntity` gains five persisted fields, each defaulted:
  - `targetLane`, `motionStart` and `motionLength`, for a lane shift driven by z;
  - `cyclePhase`, for a 0.9 s on / 0.9 s off laser;
  - `activeFrom`, the z at which a collider starts to exist.
- It also gains pure helpers (`laneOffset()`, `isOn(at:)`, `isActive`, `arrivalLane`) that the simulation, renderer and audits share.
- `collectAndCollide` evaluates colliders from those helpers at the current `elapsed` and z.
- Each hazard is one new Odyssey pattern (8–13). The patterns join the per-world pools at the pressure tier and later, through `WorldStage.hazardPatterns`.
- `CoastalWorld.syncEntities` drives the visuals from the same fields.
- `RouteAudit.drive` reads the hazards from their visible state only.
- `SkillAudit` gains three checks: bait escapes, telegraph lead times and hazard coverage.

**Tech Stack:** Swift 5.9, SceneKit, headless `swiftc` audits. No new dependencies and no new Sources files, so `xcodegen generate` is not needed.

**Spec:** `docs/superpowers/specs/2026-10-06-gameplay-overhaul-design.md` (sections G2, Compatibility and Verification). G1 results and rulings are in `work/g1-rulings.txt` and `work/g1-deferred-minors.txt`.

## Global Constraints

- iOS 16+ / macOS 13+, with one shared `Sources/` tree.
- Every row keeps at least one reachable exit.
- The hazard reader (`RouteAudit.drive`) clears 100% of Odyssey routes and survives 300 s of Endless on every seed, without boards. This covers both routes, both difficulties and all worlds.
- 0 unfair coins and pickups, at first sight and at collection time (`FAIRNESS unfairCoins=0`).
- The placed safe-line share is at or below 35% per mode (`PLACED-LINES`).
- Determinism holds, and Daily is reproducible.
- Checkpoints decode: every new persisted field uses a `decodeIfPresent` default.
- `Scripts/test.sh` and `bash Scripts/audit.sh` pass. A test that encodes old behaviour is updated in the same commit, with the reason stated.
- Mac and iOS builds succeed.
- `Scripts/render.sh` stays within +25% of harbor 286, orbit 117, mars 131, verdant 254, cryo 141, forge 149 and jetski 279 ms. The limits are 357.5 / 146.3 / 163.8 / 317.5 / 176.3 / 186.3 / 348.8 ms. One re-run is allowed.
- Environment:
  - `swiftc`, `xcodebuild` and `Scripts/*.sh` run outside the Claude sandbox.
  - Outputs go to `work/g2/`, never `$TMPDIR`.
  - `-O` builds do not print `precondition` messages, so rebuild without `-O` to read one.
  - zsh does not word-split `$VAR`, so use bash.
  - Every new Sources file needs `xcodegen generate`. This plan adds none.
- Telegraph timing is at least 1.0 s at Standard and 0.8 s at Expert.
- New models are cheap: radius-0 boxes (12 triangles each), no spheres, pooled like every other entity.
- Ghosts: G2 does not bump `GhostCourseKey`. G2 and G3 ship together, and G3 Task 4 bumps Odyssey to 9 and Endless/Sprint to 6. If G2 ever ships alone, bump Odyssey to 9 first.

## Reference facts (from the code, 2026-10-06; derivations shown)

**Speeds.** `WorldStage.speed`, revision ≥ 6, runs from start to finish linearly over stage progress:

| World | Standard (m/s) | Expert (m/s) |
|---|---|---|
| harbor | 17 → 29 | 20 → 35 |
| orbit | 29 → 33 | 35 → 39 |
| mars | 33 → 36 | 39 → 42 |
| verdant | 36 → 39 | 42 → 45 |
| cryo | 39 → 42 | 45 → 48 |
| forge | 42 → 45 | 48 → 51 |

- `extendJourneyCourse` uses `predictedSpeed = expeditionSpeed(at: progress of the row)`. That is at least the runner's speed whenever the runner is behind the row, because speed only rises with progress.
- Endless speed is `min(32, 12 + 0.18 t)` on Standard and `min(36, 16 + 0.24 t)` on Expert (`RunnerSimulation.swift` ~:564).

**Steering** (`stepWorld` ~:608): 9 lanes/s, or 3.8 lanes/s in Odyssey Cryo. One lane takes 1/9 = 0.111 s, or 1/3.8 = 0.263 s on Cryo.

**Collision** (`collectAndCollide` ~:767–919):
- Longitudinal window: `abs(z) < length/2 + 0.35`. Lateral: `abs(lateral − lane) < 0.55`.
- Bands:
  - barrier/root: `height < 1.03`
  - gap/iceCrack: `< 0.4`
  - meteor: `< 2.5`
  - arch/laserSweep: `!isRolling || height > 0.15`
  - tram: `< 2.45`
- A roll lasts 0.8 s. A roll in mid-air forces `verticalVelocity ≤ −15`.

**Jumps** (`worldStage.jumpVelocity` / `gravity`):

| Worlds | Velocity | Gravity | Airtime | Apex |
|---|---|---|---|---|
| harbor, verdant, cryo, forge, Endless | 8.5 | 22 | 0.773 s | 1.64 m |
| mars | 8.0 | 14 | 1.143 s | 2.29 m |
| orbit | 7.8 | 9 | 1.733 s | 3.38 m |

**Visibility:**
- `CoastalWorld.update` draws entities out to `min(200, max(135, speed × 3.2))` m in Odyssey (at least 3.2 s ahead) and 135 m in Endless.
- The shape-coded action cue shows while `z / (speed + oncoming) ≤ 2.7` s.
- Odyssey generates `max(210, speed × 6)` m ahead.

**Encounter interval floors** (`journeyEncounterInterval` ~:1374):
- 1.40 s (Expert 1.25)
- Orbit 2.13 (1.95), which finishes a whole low-gravity jump
- Cryo 1.65 (1.50)
- Pattern 3 also gets `max(…, (cryo ? 1.60 : 1.30) + (expert ? 0 : 0.14))`.

**Patterns 0–7** (`extendJourneyCourse` ~:1251–1318):
- 4 → 2 unless the world is harbor, mars or forge; 5 → 7 unless forge or harbor.
- Rows 0 and 1 are forced (0, then 3 on Orbit or 1 elsewhere).
- Forks and finales override the pattern.
- Odyssey Standard rows < 4 are coin teaching rows.

**Effective patterns per world after G2:**
- harbor {0–7, 8, 10, 11} = 11
- orbit {0, 1, 2, 3, 6, 7, 9, 10, 11, 13} = 10
- mars {0–4, 6, 7, 8, 10, 11, 12} = 11
- verdant {0, 1, 2, 3, 6, 7, 9, 10, 11} = 9 (G3 adds pattern 5)
- cryo {0, 1, 2, 3, 6, 7, 8, 10, 11, 13} = 10
- forge {0–7, 9, 10, 11} = 11

**G1 bait plan** (`placeCoins` ~:1428–1449):
- Bait ends `speed × reaction` before its solid, where reaction is 0.35 s (Odyssey Cryo 0.55).
- It resumes `max(2, speed × 0.15)` m behind the solid's far edge.
- The escape lane is `safe`.
- The G1 guard was `laneIsClear(safe, from: last, to: solid.z − hl)`. **Residual:** a review probe found pattern-3 follow beats with solids in every lane except `exit` (so the safe lane was covered), starting exactly at `solid.z − hl`. The strict `<` in `laneIsClear` passed them.
- Planning smoke run (6 seeds, scratch copy in `work/plancheck`):
  - The old guard gave **391** bait-escape violations.
  - The new guard gave 0, but the Odyssey safe share was 36.5% (4 seeds).
  - With the safe band narrowed to `0..<25`: Odyssey safe 31.5%, Endless 24.7%, with every reader run and fairness check green.
- Arc baits, where the last coin sits over a full-width jump row, are exempt from the escape lane's jump in the same row, because the same leap clears it.

**Lane-changer timing:**
- Lead `L` = reaction (1.0 s, Expert 0.8) + one lane of steering (0.111 s, Cryo 0.263): 1.111 s / 0.911 s, or on Cryo 1.263 s / 1.063 s.
- The shift completes at `complete = v × L + length/2 + 0.35`, the z where the front of its collision window is `v × L` ahead.
- `motionLength = v × 0.6`, the spec's 0.6 s slide. `motionStart = complete + v × 0.6`.
- Worst cases:
  - Harbor Std, v = 29, length 7: complete 36.1 m, start 53.5 m. Drawn from 135 m, so it telegraphs (135 − 53.5)/29 = 2.8 s before it moves.
  - Cryo Std, v = 42: complete 56.9, start 82.1. Drawn from 135 m, so (135 − 82.1)/42 = **1.26 s** ≥ 1.0.
  - Cryo Expert, v = 48: complete 54.9, start 83.7. Drawn from 153.6 m, so 1.46 s ≥ 0.8.
  - Mars Expert, v = 42, length 9: complete 43.1, start 68.3, so 1.59 s.

**Meteor timing:**
- Impact at `activeFrom = v × 1.0 + 1 + 0.35`: Mars Std 34.4–37.4 m, Expert 40.4–43.4 m.
- The target ring is drawn from ≥ 135 m, so it warns ≥ (135 − 43.4)/42 = 2.2 s before impact.
- The rock is seen falling over the last 36 m before impact, about 1 s.

**Deck timing:**
- Opens at `activeFrom = v × 0.5 + length/2 + 0.35`.
- Orbit gap length is `min(14, 7 + 2·tier)`, which is 9–13 at pressure and later: 18.9–23.9 m at Standard. Cryo ice length is `3.2 + tier` = 4.2–6.2 m: up to 27.5 m at Expert.
- The crack decal is drawn from ≥ 135 m, so it warns ≥ 3.4 s before arrival, which is ≥ 1.0.

**Laser timing:**
- The pass window is `±(0.55 + 0.35)/v` = ±0.031 s at 29 m/s, against a 0.9 s on/off phase.
- The reader samples arrival `elapsed + z/v` at ±(window + 0.05 s).

**Gap wall:** the opening is adjacent to the previous route. The worst lateral need is 2 lanes after a full-width row: 0.222 s, or 0.526 s on Cryo. Both are below the 1.25 s minimum interval.

**Checkpoint JSON:** `RunCheckpointStore.save` uses a default `JSONEncoder`, which throws on `Double.infinity`. So `TrackEntity.encode(to:)` writes the new fields only when they are not at their defaults, and `activeFrom = .infinity` is never written.

**Exhaustive `switch` over `EntityKind`** (from grep; GameUI's `switch kind` at :1054/:1062 is over `CRButton.Kind`):
- `CoastalWorld.buildEntity` (~:1176) has no `default`, so new kinds must be listed.
- These switches have a `default` but still need a new case:
  - `RunnerSimulation.encounterText` (~:210)
  - the `collides` switch (~:859)
  - the crash-reason switch (~:893)
  - `CoastalWorld.makeSignatureHazard` (~:2608)
  - `SkillAudit.coinIsFair` (:58), whose inner `default` treats unknown kinds as waterTraffic at 1.8 m, which would be wrong
- These have a `default` and need no change:
  - `CoastalWorld.syncEntities` (~:1117)
  - `makeEntity` (~:1166)
  - `makePowerUp` (~:1324)
  - `makeWorldObstacle` (~:2705)
  - `GameController.playHazardCue` (:421)
  - `RouteAudit.drive` (:75)
  - `SkillAudit.followCoins` (:31)
- Kind lists to extend: `RunnerSimulation.isObstacle`, `RouteAudit.hazards`, `CoastalWorld.addActionCue`, and the kind list in `GameController.playHazardCue`.

## File map

| File | Change |
|---|---|
| `Sources/RunnerSimulation.swift` | T1: bait escape guard and `baitEscapes`. T2: new `TrackEntity` fields, helpers and Codable; `add` parameters; collisions. T3–T6: patterns 8–13, arrival-lane reads, intervals, `encounterText` and crash reasons. T5: `.wall`, `.stack` and `isSolid`. |
| `Sources/ExpeditionExpansion.swift` | T3–T6: `WorldStage.hazardPatterns`. |
| `Sources/CoastalWorld.swift` | T3: lane-changer position and shift chevron. T4: laser on/off look. T5: wall and stack models and their cues. T6: meteor descent and the collapsing deck plate and crack. |
| `Sources/GameController.swift` | T3/T5: hazard audio cue reads the arrival lane and the new kinds. |
| `Tests/SimulationTests.swift` | T2: fields, helpers and colliders. T5: wall and stack. |
| `Tests/Audits/RouteAudit.swift` | T3: arrival lanes. T4: laser prediction. T5: hazard and solid sets. |
| `Tests/Audits/SkillAudit.swift` | T1: `Watch` and bait escapes. T2: telegraph and coverage checks. T3–T6: coverage entries and arrival lanes. T5: walls and stacks in `coinIsFair`. |
| `Tests/Audits/WorldCacheAudit.swift` | T3: the visual x includes `laneOffset()`. |
| `work/HazardPreview.swift` | T7: throwaway visual check, not committed (`work/` is gitignored). |

---

### Task 1: Bait escapes are a single adjacent switch (carried G1 residual)

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`placeCoins`: `baitPlan` and the `.bait` case; a new property next to `placedCoinLines`)
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: G1 `placeCoins`, `laneIsClear`, `SkillAudit.checkCoins`.
- Produces:
  - `RunnerSimulation.baitEscapes: [Int: Int]` (the last bait coin id → its solid's id; `private(set)`, not persisted)
  - `SkillAudit.Watch`, `SkillAudit.check(_:_:)`, `SkillAudit.checkBaitEscapes(_:checked:violations:)`
  - the output line `BAIT-ESCAPES violations=N`, with a precondition that N is 0

- [ ] **Step 1: Record bait escapes in the simulation.** In `RunnerSimulation`, directly below `private(set) var placedCoinLines: [CoinLine: Int] = [:]`, add:

```swift
    /// Last bait coin id → its solid's id, for the bait-escape audit. Not persisted: a restored run starts empty.
    private(set) var baitEscapes: [Int: Int] = [:]
```

  In `placeCoins`, replace the `.bait` case body (from `case .bait:` up to, but not including, `case .safe:`) with:

```swift
        case .bait:
            // A greedy line in a solid's lane that ends with time left for one lane switch.
            let (solid, last, arc) = bait!
            let lane = solid.lane
            let firstCoin = entities.count
            if arc { addJourneyArc(lane: lane, z: z, apex: jumpApex, speed: speed, until: last) }
            else { for k in 0..<3 { add(.coin, lane: lane, z: last - Double(k) * 3, y: 0.9, length: 0.3) } }
            // The audit checks the escape from the last pre-solid coin.
            if let lastCoin = entities[firstCoin...].max(by: { $0.z < $1.z }) { baitEscapes[lastCoin.id] = solid.id }
            // The line resumes behind the solid: staying in lane for it is fatal, stepping out and back is not.
            for k in 0..<3 where solid.z + solid.length / 2 + resume + Double(k) * 3 <= coinLimit {
                add(.coin, lane: lane, z: solid.z + solid.length / 2 + resume + Double(k) * 3, y: 0.9, length: 0.3)
            }
```

- [ ] **Step 2: Write the failing audit check.** In `SkillAudit`, add inside the struct (above `static func median`):

```swift
    /// Per-run audit state. Violation counters are global across runs.
    struct Watch { var seen: Set<Int> = [], flagged: Set<Int> = [], bait: Set<Int> = [] }
    static var unfair = 0, baitViolations = 0

    static func check(_ run: RunnerSimulation, _ watch: inout Watch) {
        checkCoins(run, seen: &watch.seen, flagged: &watch.flagged, unfair: &unfair)
        checkBaitEscapes(run, checked: &watch.bait, violations: &baitViolations)
    }

    /// A bait line's last coin must leave one adjacent lane clear of every hazard, from that coin until the runner
    /// has passed the solid and stepped back in behind it (far edge + resume switch), with collision padding.
    /// Checked once the coin is within 2 s, when every row that could block the escape has been generated.
    static func checkBaitEscapes(_ run: RunnerSimulation, checked: inout Set<Int>, violations: inout Int) {
        for (coinID, solidID) in run.baitEscapes where !checked.contains(coinID) {
            guard let coin = run.entities.first(where: { $0.id == coinID }), coin.z < run.speed * 2,
                  let solid = run.entities.first(where: { $0.id == solidID }) else { continue }
            checked.insert(coinID)
            let from = coin.z - 0.35, to = solid.z + solid.length / 2 + max(2, run.speed * 0.15) + 0.35
            // A jump in the bait lane before the solid (an arc bait's row) is leapt anyway; that leap also clears
            // a jump hazard in the same row of the escape lane.
            let jumps: Set<EntityKind> = [.gap, .barrier, .root, .iceCrack]
            let leaps = run.entities.filter { jumps.contains($0.kind) && $0.lane == coin.lane && $0.z + $0.length / 2 > coin.z - 1 && $0.z < solid.z }
            let escapes = [solid.lane - 1, solid.lane + 1].filter { lane in
                (-1...1).contains(lane) && !run.entities.contains { o in
                    RouteAudit.hazards.contains(o.kind) && o.lane == lane && o.z + o.length / 2 > from && o.z - o.length / 2 < to &&
                        !(jumps.contains(o.kind) && leaps.contains { abs($0.z - o.z) < 1 })
                }
            }
            if escapes.isEmpty {
                violations += 1
                if violations <= 5 {
                    print("BAIT-ESCAPE blocked coin=\(coinID) lane=\(coin.lane) z=\(coin.z) solid=\(solid.kind) lane=\(solid.lane) z=\(solid.z) length=\(solid.length) mode=\(run.mode) world=\(run.worldStage) expert=\(run.expert)")
                }
            }
        }
    }
```

  Then edit `main()`:
  - Delete the line `var unfair = 0`. The counter is now static.
  - Replace every `seen = Set<Int>(), flagged = Set<Int>()` with `watch = Watch()`. There are 5 places, in the Odyssey follower, Odyssey reader, Endless follower, Endless reader and Sprint loops. The new `Watch` definition is written differently so it does not match.
  - Replace every `checkCoins(run, seen: &seen, flagged: &flagged, unfair: &unfair)` with `check(run, &watch)`. There are 5 places.
  - Immediately before `print("FAIRNESS unfairCoins=…`, add:

```swift
        print("BAIT-ESCAPES violations=\(baitViolations) (last bait coin to resume switch; one adjacent lane clear)")
        precondition(baitViolations == 0, "Every bait escape must be a single adjacent lane switch")
```

- [ ] **Step 3: Run it to verify it fails.**

```bash
mkdir -p work/g2
swiftc -O -whole-module-optimization -swift-version 5 -module-cache-path work/g2/modules -D ROUTE_HELPER \
  Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift \
  Tests/Audits/RouteAudit.swift Tests/Audits/SkillAudit.swift -o work/g2/skill && work/g2/skill | tee work/g2/skill-t1-before.log
```

  Expected: `BAIT-ESCAPE blocked …` lines, then `BAIT-ESCAPES violations=N` with N > 0, then a trap.
  - If N is 0 on these seeds, record that in the report, keep the check, and continue: the review probe's evidence still justifies the fix.

- [ ] **Step 4: Fix the guard.** In `placeCoins`, replace the whole `func baitPlan(_ solid: TrackEntity) -> (last: Double, arc: Bool)? { … }` with:

```swift
        func baitPlan(_ solid: TrackEntity) -> (last: Double, arc: Bool)? {
            let lane = solid.lane
            guard abs(lane - safe) == 1 else { return nil }
            let hl = solid.length / 2
            let last = solid.z - hl - speed * reaction
            let arc = jumpLanes.contains(lane) && solid.z > z + 1
            // One adjacent switch out and back: the escape lane stays clear from the last bait coin, past the solid's
            // far edge, until the runner has stepped back in behind it (the resume switch), with collision padding.
            // An arc bait's runner is airborne over this row's jump, which also clears the escape lane's jump beside it.
            let escapeFrom = arc ? max(last - 0.35, z + halfLength(safe) + 0.1) : last - 0.35
            guard laneIsClear(safe, from: escapeFrom, to: solid.z + hl + resume + 0.35) else { return nil }
            let before = arc ? z <= last && laneIsClear(lane, from: z + halfLength(lane) + 0.1, to: solid.z - hl - 0.1)
                : laneIsClear(lane, from: last - 7.3, to: last + 1.3) && laneIsClear(lane, from: last + 1.3, to: solid.z - hl - 0.1)
            guard before, laneIsClear(lane, from: solid.z + hl + 0.1, to: solid.z + hl + resume + 7.3) else { return nil }
            return (last, arc)
        }
```

  The stricter guard removes some bait rows, and they fall back to other lines; on the planning smoke run, the placed Odyssey safe share rose to 36.5%. So also narrow the band that asks for the safe line. In `coinLine`, replace `case 0..<30: return .safe` with `case 0..<25: return .safe`, and replace `case 30..<60:` with `case 25..<60:`. Teaching rows (`roll % 60`) still lay only safe or action lines.

- [ ] **Step 5: Run it to verify it passes.** Re-run the Step 3 command, logging to `work/g2/skill-t1.log`.
  - Expected:
    - `COIN-LINES safe=25 …`
    - `BAIT-ESCAPES violations=0`
    - `FAIRNESS unfairCoins=0`
    - every READER line at 30/30
    - both `PLACED-LINES` safe shares ≤ 35% (the 6-seed planning smoke run gave Odyssey 31.5% and Endless 24.7%)
    - `SkillAudit passed`
  - If a safe share is still above 35%, report DONE_WITH_CONCERNS with both PLACED-LINES lines. Do not widen bait beyond a single adjacent switch.

- [ ] **Step 6: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t1.log`, both with the sandbox disabled. Expected: everything passes.

- [ ] **Step 7: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/Audits/SkillAudit.swift
git commit -m "fix: bait escape lane stays clear through the solid and the resume switch; audit every bait escape; safe-line band 25%"
```

---

### Task 2: Entity fields, helpers, colliders and audit infrastructure

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`TrackEntity` and its extension; `add`; `collectAndCollide`)
- Modify: `Tests/SimulationTests.swift`
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: T1 `Watch` and `check`.
- Produces:
  - `TrackEntity` fields: `targetLane: Int? = nil`, `motionStart: Double = 0`, `motionLength: Double = 0`, `cyclePhase: Double = -1`, `activeFrom: Double = .infinity`
  - `TrackEntity.cycleLength` (1.8), `arrivalLane: Int`, `laneOffset() -> Double`, `isOn(at:) -> Bool`, `isActive: Bool`
  - `add(_:lane:z:y:length:oncomingSpeed:targetLane:motionStart:motionLength:cyclePhase:activeFrom:)`
  - `SkillAudit.hazardFeature(_:)`, `SkillAudit.hazardWorlds` (empty here; T3–T6 fill it), `SkillAudit.checkTelegraphs(_:done:violations:)`
  - output lines `HAZARD-COVERAGE …` and `TELEGRAPHS lateChanges=N`

- [ ] **Step 1: Write the failing simulation tests.** In `Tests/SimulationTests.swift`, add these cases to the `cases` array, directly after the `"entity saves preserve speed and accept older stationary entities"` case:

```swift
            ("new entity fields decode with defaults and round-trip", {
                let legacy = Data(#"{"id":1,"kind":"meteor","lane":0,"z":30,"y":0,"length":2}"#.utf8)
                let old = try JSONDecoder().decode(TrackEntity.self, from: legacy)
                try expect(old.targetLane == nil && old.motionStart == 0 && old.motionLength == 0 && old.cyclePhase == -1 && old.activeFrom == .infinity,
                           "Old entities must decode with inert defaults")
                let plain = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
                try expect(!plain.contains("activeFrom") && !plain.contains("targetLane") && !plain.contains("cyclePhase") && !plain.contains("motion"),
                           "Default fields must not be written (JSON cannot hold an infinite activeFrom)")
                var moving = entity(.tram, lane: -1, z: 40, length: 7)
                moving.targetLane = 0; moving.motionStart = 30; moving.motionLength = 6; moving.cyclePhase = 0.4; moving.activeFrom = 12
                let restored = try JSONDecoder().decode(TrackEntity.self, from: JSONEncoder().encode(moving))
                try expect(restored == moving, "Set fields must survive a checkpoint")
            }),
            ("lane offset, laser cycle and activation are pure functions of z and time", {
                var shifting = entity(.tram, lane: -1, z: 31, length: 7)
                shifting.targetLane = 0; shifting.motionStart = 30; shifting.motionLength = 6
                try expect(shifting.laneOffset() == 0 && shifting.arrivalLane == 0, "No shift before motionStart; arrival lane is the target")
                shifting.z = 27
                try expect(abs(shifting.laneOffset() - 0.5) < 1e-9, "Halfway through the shift the offset is half a lane")
                shifting.z = 20
                try expect(shifting.laneOffset() == 1, "The shift completes at motionStart - motionLength")
                var laser = entity(.laserSweep)
                try expect(laser.isOn(at: 0.5) && laser.isOn(at: 1.5), "Untimed lasers are always on")
                laser.cyclePhase = 0
                try expect(laser.isOn(at: 0.1) && !laser.isOn(at: 1.0) && laser.isOn(at: 1.85), "Timed lasers are on 0.9 s, off 0.9 s")
                var meteor = entity(.meteor, z: 12, length: 2)
                meteor.activeFrom = 10
                try expect(!meteor.isActive, "Inactive before its activation z")
                meteor.z = 10
                try expect(meteor.isActive, "Active from its activation z")
            }),
            ("colliders follow lane shifts, laser cycles and activation", {
                func shifting() -> TrackEntity {
                    var tram = entity(.tram, lane: -1, z: 30, y: 0, length: 7)
                    tram.targetLane = 0; tram.motionStart = 26; tram.motionLength = 6
                    return tram
                }
                var hit = fixture([shifting()])
                hit.update(dt: 3)
                try expect(hit.phase == .crashed, "A tram shifting into the runner's lane must collide")
                var left = fixture([shifting()])
                left.act(.left)
                left.update(dt: 3)
                try expect(left.phase == .running, "The lane a shifting tram leaves must be safe")
                func laser(_ phase: Double) -> TrackEntity {
                    var beam = entity(.laserSweep, z: 6, y: 0, length: 1.1)
                    beam.cyclePhase = phase
                    return beam
                }
                var on = fixture([laser(0)])
                on.update(dt: 1)
                try expect(on.phase == .crashed, "A laser that is on while a standing runner passes collides")
                var off = fixture([laser(0.9)])
                off.update(dt: 1)
                try expect(off.phase == .running, "A laser that is off lets a standing runner through")
                var rolled = fixture([laser(0)])
                rolled.act(.roll)
                rolled.update(dt: 1)
                try expect(rolled.phase == .running, "Rolling is always safe under a timed laser")
                var meteor = entity(.meteor, z: 6, y: 0, length: 2)
                meteor.activeFrom = -50
                var dormant = fixture([meteor])
                dormant.update(dt: 1)
                try expect(dormant.phase == .running, "An inactive collider cannot hit")
                meteor.activeFrom = 20
                var impact = fixture([meteor])
                impact.update(dt: 1)
                try expect(impact.phase == .crashed, "An active collider hits")
            }),
```

  Timing for the fixtures. The fixture is Endless Standard at about 12 m/s, starting at `elapsed = 0`:
  - The laser at z = 6 is in the window `|z| < 0.9` for t ∈ [0.425, 0.575] s. Phase 0 is on then. Phase 0.9 maps that to [1.325, 1.475], which is off.
  - The tram shift completes at z = 20, so its front window reaches the runner fully in lane 0.

- [ ] **Step 2: Run them to verify they fail.**

```bash
swiftc -swift-version 5 -module-cache-path work/g2/modules Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift \
  Sources/RunnerSimulation.swift Tests/SimulationTests.swift -o work/g2/simulation-tests && work/g2/simulation-tests
```

  Expected: a compile error, `value of type 'TrackEntity' has no member 'targetLane'`.

- [ ] **Step 3: Add the fields.** In `struct TrackEntity`, after `var oncomingSpeed: Double = 0`, add:

```swift
    /// A lane-changer slides from `lane` into `targetLane` while z runs from `motionStart` to `motionStart - motionLength`.
    var targetLane: Int? = nil
    var motionStart: Double = 0
    var motionLength: Double = 0
    /// A timed laser's phase (seconds) on a 1.8 s cycle: on 0.9 s, then off 0.9 s. Negative means always on.
    var cyclePhase: Double = -1
    /// The collider exists only once z <= activeFrom: a meteor's impact, a deck's collapse.
    var activeFrom: Double = .infinity
```

  Replace the whole `extension TrackEntity { … }` (the CodingKeys and `init(from:)`) with:

```swift
extension TrackEntity {
    static let cycleLength = 1.8

    /// The lane the entity occupies when it reaches the runner; its telegraph shows this lane.
    var arrivalLane: Int { targetLane ?? lane }

    /// Eased lateral offset, in lanes, from `lane` toward `targetLane` at the current z.
    func laneOffset() -> Double {
        guard let target = targetLane, motionLength > 0 else { return 0 }
        let p = min(1, max(0, (motionStart - z) / motionLength))
        return Double(target - lane) * p * p * (3 - 2 * p)
    }

    /// A timed laser is on for the first half of each cycle; untimed entities are always on.
    func isOn(at time: Double) -> Bool {
        guard cyclePhase >= 0 else { return true }
        let t = (time + cyclePhase).truncatingRemainder(dividingBy: Self.cycleLength)
        return (t < 0 ? t + Self.cycleLength : t) < Self.cycleLength / 2
    }

    var isActive: Bool { z <= activeFrom }

    private enum CodingKeys: String, CodingKey {
        case id, kind, lane, z, y, length, oncomingSpeed, targetLane, motionStart, motionLength, cyclePhase, activeFrom
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        kind = try values.decode(EntityKind.self, forKey: .kind)
        lane = try values.decode(Int.self, forKey: .lane)
        z = try values.decode(Double.self, forKey: .z)
        y = try values.decode(Double.self, forKey: .y)
        length = try values.decode(Double.self, forKey: .length)
        oncomingSpeed = try values.decodeIfPresent(Double.self, forKey: .oncomingSpeed) ?? 0
        targetLane = try values.decodeIfPresent(Int.self, forKey: .targetLane)
        motionStart = try values.decodeIfPresent(Double.self, forKey: .motionStart) ?? 0
        motionLength = try values.decodeIfPresent(Double.self, forKey: .motionLength) ?? 0
        cyclePhase = try values.decodeIfPresent(Double.self, forKey: .cyclePhase) ?? -1
        activeFrom = try values.decodeIfPresent(Double.self, forKey: .activeFrom) ?? .infinity
    }

    /// New fields are written only when set. JSONEncoder rejects infinity, so the default activeFrom is never written.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(lane, forKey: .lane)
        try values.encode(z, forKey: .z)
        try values.encode(y, forKey: .y)
        try values.encode(length, forKey: .length)
        try values.encode(oncomingSpeed, forKey: .oncomingSpeed)
        try values.encodeIfPresent(targetLane, forKey: .targetLane)
        if motionStart != 0 { try values.encode(motionStart, forKey: .motionStart) }
        if motionLength != 0 { try values.encode(motionLength, forKey: .motionLength) }
        if cyclePhase >= 0 { try values.encode(cyclePhase, forKey: .cyclePhase) }
        if activeFrom.isFinite { try values.encode(activeFrom, forKey: .activeFrom) }
    }
}
```

- [ ] **Step 4: Extend `add`.** Replace `private mutating func add(_ kind: EntityKind, lane: Int, z: Double, y: Double, length: Double, oncomingSpeed: Double = 0) { … }` with:

```swift
    private mutating func add(_ kind: EntityKind, lane: Int, z: Double, y: Double, length: Double,
                              oncomingSpeed: Double = 0, targetLane: Int? = nil, motionStart: Double = 0,
                              motionLength: Double = 0, cyclePhase: Double = -1, activeFrom: Double = .infinity) {
        entities.append(TrackEntity(id: nextID, kind: kind, lane: lane, z: z, y: y, length: length,
                                    oncomingSpeed: oncomingSpeed, targetLane: targetLane, motionStart: motionStart,
                                    motionLength: motionLength, cyclePhase: cyclePhase, activeFrom: activeFrom))
        nextID += 1
    }
```

- [ ] **Step 5: Colliders read the helpers.** Make three replacements in `collectAndCollide`.

  First, replace `let aligned = abs(lateral - Double(entity.lane)) < 0.55` with:

```swift
            // Colliders sit where they are drawn: a lane-changer's lane interpolates with z.
            let aligned = abs(lateral - (Double(entity.lane) + entity.laneOffset())) < 0.55
```

  Second, replace:

```swift
            if invulnerableTime > 0 { continue }
            challenge.closestApproaches[entity.id] = min(challenge.closestApproaches[entity.id] ?? 100, abs(lateral - Double(entity.lane)))
```

  with:

```swift
            if invulnerableTime > 0 { continue }
            // A meteor before impact or a deck before collapse has no collider yet.
            guard entity.isActive else { continue }
            challenge.closestApproaches[entity.id] = min(challenge.closestApproaches[entity.id] ?? 100,
                                                         abs(lateral - (Double(entity.lane) + entity.laneOffset())))
```

  Third, replace `case .laserSweep, .arch: collides = !isRolling || height > 0.15` with:

```swift
            case .laserSweep, .arch: collides = entity.isOn(at: elapsed) && (!isRolling || height > 0.15)
```

- [ ] **Step 6: Run them to verify they pass.** Re-run the Step 2 command. Expected: every case passes, including the three new ones.

- [ ] **Step 7: Add the telegraph and coverage infrastructure to SkillAudit.** Replace the T1 `Watch`, counters and `check` with:

```swift
    /// Per-run audit state. Violation counters and coverage are global across runs.
    struct Watch { var seen: Set<Int> = [], flagged: Set<Int> = [], bait: Set<Int> = [], telegraphs: Set<Int> = [], features: Set<Int> = [] }
    static var unfair = 0, baitViolations = 0, telegraphViolations = 0
    static var coverage: [String: Set<WorldStage>] = [:]

    static func check(_ run: RunnerSimulation, _ watch: inout Watch) {
        checkCoins(run, seen: &watch.seen, flagged: &watch.flagged, unfair: &unfair)
        checkBaitEscapes(run, checked: &watch.bait, violations: &baitViolations)
        checkTelegraphs(run, done: &watch.telegraphs, violations: &telegraphViolations)
        if run.mode == .odyssey {
            for e in run.entities where watch.features.insert(e.id).inserted {
                if let feature = hazardFeature(e) { coverage[feature, default: []].insert(run.worldStage) }
            }
        }
    }

    /// The G2 hazard an entity shows, read from its visible state.
    static func hazardFeature(_ e: TrackEntity) -> String? {
        if e.targetLane != nil { return "lane-changer" }
        if e.kind == .laserSweep && e.cyclePhase >= 0 { return "timed-laser" }
        if e.kind.rawValue == "wall" { return "gap-wall" }
        if e.kind.rawValue == "stack" { return "stacked" }
        if e.kind == .meteor && e.activeFrom.isFinite { return "real-meteor" }
        if (e.kind == .gap || e.kind == .iceCrack) && e.activeFrom.isFinite { return "collapsing-deck" }
        return nil
    }

    /// G2 hazards and the Odyssey worlds that must generate them. Each hazard task adds its entry.
    static let hazardWorlds: [String: Set<WorldStage>] = [:]

    /// Live check of the G2 lead-time rules at the moment each change happens, against the runner's real speed:
    /// a lane shift completes >= 1.0 s (Expert 0.8 s) ahead, a meteor lands >= 1.0 s ahead, a deck opens >= 0.5 s ahead.
    static func checkTelegraphs(_ run: RunnerSimulation, done: inout Set<Int>, violations: inout Int) {
        let slack = run.speed / 60 + 0.01 // the change is seen up to one frame late
        for e in run.entities where !done.contains(e.id) {
            let need: Double
            if e.targetLane != nil && e.z <= e.motionStart - e.motionLength { need = run.expert ? 0.8 : 1.0 }
            else if e.activeFrom.isFinite && e.isActive { need = e.kind == .meteor ? 1.0 : 0.5 }
            else { continue }
            done.insert(e.id)
            let edge = e.z - e.length / 2 - 0.35
            if edge + slack < run.speed * need {
                violations += 1
                if violations <= 5 { print("TELEGRAPH late \(e.kind) id=\(e.id) edge=\(edge) needs=\(run.speed * need) world=\(run.worldStage) expert=\(run.expert)") }
            }
        }
    }
```

  `hazardFeature` compares `rawValue` for `wall` and `stack` so this compiles before Task 5 adds those cases.

  In `main()`, immediately before the `BAIT-ESCAPES` print, add:

```swift
        let missing = hazardWorlds.filter { coverage[$0.key] != $0.value }
        let leaks = coverage.filter { hazardWorlds[$0.key] != $0.value }
        print("HAZARD-COVERAGE " + hazardWorlds.keys.sorted().map { key in
            "\(key)=\(coverage[key, default: []].map(\.rawValue).sorted().joined(separator: "+"))" }.joined(separator: " "))
        precondition(missing.isEmpty && leaks.isEmpty, "Each G2 hazard must appear in exactly its worlds: missing=\(missing.keys.sorted()) leaks=\(leaks.keys.sorted())")
        print("TELEGRAPHS lateChanges=\(telegraphViolations) (shift >= 1.0/0.8 s, impact >= 1.0 s, collapse >= 0.5 s)")
        precondition(telegraphViolations == 0, "Lane shifts, impacts and collapses must keep their lead time")
```

- [ ] **Step 8: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t2.log`, both with the sandbox disabled.
  - Expected: everything passes, with `HAZARD-COVERAGE` (empty), `TELEGRAPHS lateChanges=0`, and the RouteAudit checkpoint round-trips still matching. No generator sets the new fields yet, so routes, coins and ghosts are unchanged.

- [ ] **Step 9: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/SimulationTests.swift Tests/Audits/SkillAudit.swift
git commit -m "feat: entity lane shifts, laser cycles and activation drive colliders; audit telegraphs and hazard coverage"
```

---

### Task 3: Lane-changer (Harbor, Mars, Cryo)

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`extendJourneyCourse`, `journeyEncounterInterval`, `placeCoins`, `laneIsClear`, `oncomingLaneIsFair`, `encounterText`)
- Modify: `Sources/ExpeditionExpansion.swift`
- Modify: `Sources/CoastalWorld.swift` (`syncEntities`, a new `addShiftCue`)
- Modify: `Sources/GameController.swift` (`playHazardCue`)
- Modify: `Tests/Audits/RouteAudit.swift`, `Tests/Audits/SkillAudit.swift`, `Tests/Audits/WorldCacheAudit.swift`

**Interfaces:**
- Consumes: T2 fields, helpers and `add` parameters; T2 coverage and telegraph checks.
- Produces:
  - `WorldStage.hazardPatterns: [Int]`
  - Odyssey pattern 8
  - every lane read in generation, rendering and the audits uses `arrivalLane`, or `lane + laneOffset()` for live positions
  - `CoastalWorld.addShiftCue(to:)`

- [ ] **Step 1: Write the failing coverage entry.** In `SkillAudit`, replace `static let hazardWorlds: [String: Set<WorldStage>] = [:]` with:

```swift
    static let hazardWorlds: [String: Set<WorldStage>] = [
        "lane-changer": [.harbor, .mars, .cryo],
    ]
```

  Run the T1 Step 3 SkillAudit command, logging to `work/g2/skill-t3-before.log`. Expected: `HAZARD-COVERAGE lane-changer=`, then a trap on the coverage precondition.

- [ ] **Step 2: Add the per-world hazard pools.** In `Sources/ExpeditionExpansion.swift`, inside `extension WorldStage`, after `finalePatterns`, add:

```swift
    /// G2 hazard patterns this world adds to its pressure-and-later pools (8 lane-changer).
    var hazardPatterns: [Int] {
        switch self {
        case .harbor: return [8]
        case .orbit: return []
        case .mars: return [8]
        case .verdant: return []
        case .cryo: return [8]
        case .forge: return []
        }
    }
```

- [ ] **Step 3: Generate pattern 8.** All edits in this step are in `extendJourneyCourse`, not `extendLegacyJourneyCourse`.

  (a) Replace:

```swift
            let candidates = [-1, 0, 1].filter { abs($0 - challenge.previousSafeLane) <= 1 }
            let safe = candidates[Int(nextRandom() % UInt64(candidates.count))]
```

  (the occurrence directly after `let row = enhancements.generatedRows` / `enhancements.generatedRows += 1` that follows `let tier = …`) with:

```swift
            let previousSafe = challenge.previousSafeLane
            let candidates = [-1, 0, 1].filter { abs($0 - previousSafe) <= 1 }
            let safe = candidates[Int(nextRandom() % UInt64(candidates.count))]
```

  (b) Replace the pool block:

```swift
            let pool: [Int]
            switch tier {
            case .warmup: pool = [0, 0, 1, 2, 3, 4]
            case .pressure: pool = [0, 1, 2, 2, 3, 4, 5, 6]
            case .intense: pool = [0, 1, 2, 3, 3, 4, 5, 6, 7]
            case .overdrive: pool = [0, 1, 2, 2, 3, 4, 5, 6, 6, 7, 7]
            }
            var pattern = pool[Int(nextRandom() % UInt64(pool.count))]
```

  with:

```swift
            let base: [Int]
            switch tier {
            case .warmup: base = [0, 0, 1, 2, 3, 4]
            case .pressure: base = [0, 1, 2, 2, 3, 4, 5, 6]
            case .intense: base = [0, 1, 2, 3, 3, 4, 5, 6, 7]
            case .overdrive: base = [0, 1, 2, 2, 3, 4, 5, 6, 6, 7, 7]
            }
            // New hazards join pressure and later tiers, never a world's first rows.
            let pool = base + (tier == .warmup || row < 4 ? [] : worldStage.hazardPatterns)
            var pattern = pool[Int(nextRandom() % UInt64(pool.count))]
```

  (c) Replace `var relicLane = safe` with:

```swift
            var relicLane = safe
            // The lane coins and the next row treat as this row's route; a lane-changer moves it.
            var routeLane = safe
```

  (d) Insert this case directly before `default: // Two mixed actions …`:

```swift
            case 8: // Lane-changer: a blocked lane's vehicle slides into the open lane, so the open lane swaps.
                // It leaves a lane next to both the open lane and the previous route: the new exit is one switch away.
                let origins = blocked.filter { abs($0 - safe) == 1 && abs($0 - previousSafe) <= 1 }
                let origin = origins[Int(nextRandom() % UInt64(origins.count))]
                let other = blocked.first { $0 != origin }!
                let length = worldStage == .mars ? 9.0 : 7.0
                // The shift completes a reaction (1.0 s, Expert 0.8 s) plus one lane of steering before the runner reaches it.
                let lead = (expert ? 0.8 : 1.0) + (worldStage == .cryo ? 1 / 3.8 : 1 / 9.0)
                let complete = predictedSpeed * lead + length / 2 + 0.35
                add(.tram, lane: origin, z: z, y: 0, length: length, targetLane: safe,
                    motionStart: complete + predictedSpeed * 0.6, motionLength: predictedSpeed * 0.6)
                add(solid, lane: other, z: z, y: 0, length: solidLength)
                challenge.previousSafeLane = origin
                routeLane = origin
                relicLane = origin
```

  (e) In the coin block after the switch, replace:

```swift
                let laterSolids = entities[rowStart...].filter { [.tram, .meteor].contains($0.kind) && $0.oncomingSpeed == 0 &&
                    $0.z > z + 1 && $0.z <= z + predictedSpeed * 1.2 && abs($0.lane - safe) == 1 }
```

  with:

```swift
                let laterSolids = entities[rowStart...].filter { [.tram, .meteor].contains($0.kind) && $0.oncomingSpeed == 0 &&
                    $0.z > z + 1 && $0.z <= z + predictedSpeed * 1.2 && abs($0.arrivalLane - routeLane) == 1 }
```

  and replace `placeCoins(line, z: z, safe: safe, speed: predictedSpeed,` with `placeCoins(line, z: z, safe: routeLane, speed: predictedSpeed,`.

  The lane-changer itself is a static `.tram`, so it already enters `solids`. Its bait line uses the arrival lane, the lane that looks open, which is the lure this hazard is for.

  (f) In `journeyEncounterInterval`, replace `if pattern == 3 {` with `if [3, 8].contains(pattern) {`. A lane-changer row needs the same lane-switch budget as a weave.

- [ ] **Step 4: Arrival-lane reads in the generator.**
  - In `placeCoins`:
    - In `func halfLength`, replace `$0.lane == lane` with `$0.arrivalLane == lane`.
    - In `baitPlan` and in the `.bait` case, replace `let lane = solid.lane` with `let lane = solid.arrivalLane`. There are 2 places.
  - In `laneIsClear`, replace `e.lane == lane` with `e.arrivalLane == lane`.
  - In `oncomingLaneIsFair`, replace `rows[Int((entity.z * 1_000).rounded()), default: []].insert(entity.lane)` with `rows[Int((entity.z * 1_000).rounded()), default: []].insert(entity.arrivalLane)`. A lane-changer row's only exit is the lane it leaves, so an oncoming tram must never be allowed into it.
  - In `encounterText`, replace the `.tram` line with:

```swift
        case .tram: return entity.targetLane != nil ? "SHIFTING CARGO · TAKE THE LANE IT LEAVES" : worldStage == .mars ? "ROVER TRANSFER · TAKE THE RAMP" : "MOVING CARGO · CHANGE LANES"
```

- [ ] **Step 5: The reader and the audits read the arrow.**

  In `RouteAudit.drive`, replace:

```swift
        let active = run.entities.filter { (flying ? $0.kind == .airHazard : hazards.contains($0.kind)) && $0.z + $0.length / 2 > -0.5 }.sorted { $0.z < $1.z }
```

  with:

```swift
        // A lane-changer is read from its shift chevron: plan around the lane it will occupy on arrival.
        let active = run.entities.filter { (flying ? $0.kind == .airHazard : hazards.contains($0.kind)) && $0.z + $0.length / 2 > -0.5 }
            .map { e -> TrackEntity in var read = e; read.lane = e.arrivalLane; return read }
            .sorted { $0.z < $1.z }
```

  In `SkillAudit`:
  - In `followCoins`, replace `$0.lane == run.lane + step` with `$0.arrivalLane == run.lane + step`.
  - In `coinIsFair`, replace `for o in entities where o.lane == coin.lane &&` with `for o in entities where o.arrivalLane == coin.lane &&`.
  - In `checkBaitEscapes`, replace `[solid.lane - 1, solid.lane + 1]` with `[solid.arrivalLane - 1, solid.arrivalLane + 1]` and `o.lane == lane && o.z + o.length / 2 > from` with `o.arrivalLane == lane && o.z + o.length / 2 > from`.

  The shift always completes at least `v × 1.0` ahead, so at collection time the live lane equals `arrivalLane`.

  In `Tests/Audits/WorldCacheAudit.swift`, replace:

```swift
                        guard abs(Double(node.position.x) - (Double(entity.lane) * 2.6 + route.lateralOffset)) < 0.001,
```

  with:

```swift
                        guard abs(Double(node.position.x) - ((Double(entity.lane) + entity.laneOffset()) * 2.6 + route.lateralOffset)) < 0.001,
```

  In `Sources/GameController.swift` `playHazardCue`, replace `abs(Double(entity.lane) - run.lateral) < 0.55` with `abs(Double(entity.arrivalLane) - run.lateral) < 0.55`.

- [ ] **Step 6: Visuals.** In `CoastalWorld.syncEntities`, replace:

```swift
            node.position = vector(Double(entity.lane) * 2.6 + path.lateralOffset, entity.y + path.elevation, -entity.z)
```

  with:

```swift
            // Drawn where it collides: a lane-changer's x follows the same eased offset as its collider.
            node.position = vector((Double(entity.lane) + entity.laneOffset()) * 2.6 + path.lateralOffset, entity.y + path.elevation, -entity.z)
```

  In the `.tram` case, replace:

```swift
                if let beacon = node.childNode(withName: "warningBeacon", recursively: false) {
                    beacon.isHidden = entity.oncomingSpeed <= 0
```

  with:

```swift
                if let cue = node.childNode(withName: "shiftCue", recursively: false) {
                    // The chevron points at the lane the vehicle will take and stays until the shift completes.
                    let remaining = Double(entity.arrivalLane - entity.lane) - entity.laneOffset()
                    cue.isHidden = entity.arrivalLane == entity.lane || abs(remaining) < 0.001
                    cue.eulerAngles.y = scalar(entity.arrivalLane > entity.lane ? 0 : .pi)
                    cue.scale = vector(highContrastCues ? 1.4 : 1, highContrastCues ? 1.4 : 1, 1 / max(0.01, entity.length / 8))
                    cue.opacity = reducedMotion ? 1 : 0.75 + sin(time * 6) * 0.25
                }
                if let beacon = node.childNode(withName: "warningBeacon", recursively: false) {
                    beacon.isHidden = entity.oncomingSpeed <= 0 && entity.targetLane == nil
```

  In the pooled creation path, replace:

```swift
                    node = makeEntity(kind: entity.kind)
                    addActionCue(to: node, kind: entity.kind)
```

  with:

```swift
                    node = makeEntity(kind: entity.kind)
                    addActionCue(to: node, kind: entity.kind)
                    if entity.kind == .tram { addShiftCue(to: node) }
```

  Directly after `func addActionCue(to root: SCNNode, kind: EntityKind) { … }`, add:

```swift
    /// A lane-changer's chevron points at the lane it will take: a shape, not a colour. Two radius-0 boxes, pooled with the tram.
    func addShiftCue(to root: SCNNode) {
        let cue = SCNNode()
        cue.name = "shiftCue"
        cue.isHidden = true
        // Two strokes form a ">" in plan view pointing toward +x; the sync turns it toward the target lane.
        for side in [-1.0, 1.0] {
            let stroke = glowBox(0.62, 0.07, 0.14, "FFE3A1", at: vector(0, 3.25, side * 0.16), into: cue)
            stroke.eulerAngles.y = scalar(side * 0.54)
            stroke.castsShadow = false
        }
        root.addChildNode(cue)
    }
```

- [ ] **Step 7: Run it to verify it passes.** Re-run the SkillAudit command, logging to `work/g2/skill-t3.log`.
  - Expected:
    - `HAZARD-COVERAGE lane-changer=cryo+harbor+mars`
    - `TELEGRAPHS lateChanges=0`
    - `BAIT-ESCAPES violations=0`
    - `FAIRNESS unfairCoins=0`
    - every READER line at 30/30
    - both PLACED-LINES safe shares ≤ 35%
    - `SkillAudit passed`
  - If the reader fails a lane-changer row:
    - Print the failing row from the FAIL lines.
    - Refine only `RouteAudit.drive`, using visible reads (kinds, lanes, z and arrival lanes). Allow at most 3 iterations, and record each change and its seed.
    - If it still fails, report BLOCKED with the FAIL lines.

- [ ] **Step 8: Run the full suites and render.**
  - Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t3.log`. `WorldCacheAudit` must PASS, which proves every shifting tram is drawn at its collider x.
  - Run `bash Scripts/render.sh g2-t3 2>&1 | tee work/g2/render-t3.log`. Every `ms=` value must be within the Global Constraints limits. One re-run is allowed.

- [ ] **Step 9: Commit.**

```bash
git add Sources/RunnerSimulation.swift Sources/ExpeditionExpansion.swift Sources/CoastalWorld.swift Sources/GameController.swift Tests/Audits
git commit -m "feat: lane-changers shift into the open lane with a telegraphed chevron (Harbor, Mars, Cryo)"
```

---

### Task 4: Timed laser gate (Orbit, Verdant, Forge)

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`extendJourneyCourse`, `encounterText`, crash reasons)
- Modify: `Sources/ExpeditionExpansion.swift`
- Modify: `Sources/CoastalWorld.swift` (the `.laserSweep` model and sync)
- Modify: `Tests/Audits/RouteAudit.swift`, `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: T2 `isOn(at:)` and the `cyclePhase` parameter on `add`; T3 `hazardPatterns` and the pool wiring.
- Produces:
  - Odyssey pattern 9
  - `RouteAudit.laserOnDuringPass(_:_:) -> Bool`
  - the laser model's `bloom` and `standby` child nodes

- [ ] **Step 1: Write the failing coverage entry.** In `SkillAudit.hazardWorlds`, add `"timed-laser": [.orbit, .verdant, .forge],` after the lane-changer entry. Run SkillAudit, logging to `work/g2/skill-t4-before.log`. Expected: a trap on coverage, with `timed-laser=` empty.

- [ ] **Step 2: Pools.** In `hazardPatterns`, set `case .orbit: return [9]`, `case .verdant: return [9]` and `case .forge: return [9]`, and update the doc comment to read `(8 lane-changer, 9 timed laser)`.

- [ ] **Step 3: Generate pattern 9.** Insert this case before `default:` in `extendJourneyCourse`:

```swift
            case 9: // Timed laser gate: on 0.9 s, off 0.9 s. Rolling is always safe; a reader can time a run-through.
                let phase = Double(nextRandom() % 18) / 10
                add(.laserSweep, lane: safe, z: z, y: 0, length: 1.1, cyclePhase: phase)
                add(.laserSweep, lane: blocked[0], z: z, y: 0, length: 1.1,
                    cyclePhase: (phase + 0.9).truncatingRemainder(dividingBy: TrackEntity.cycleLength))
                add(solid, lane: blocked[1], z: z, y: 0, length: solidLength)
                relicY = 0.7
```

  In the coin block, replace `let slideLanes = rowHazards.filter { $0.kind == slideKind }.map(\.lane)` with:

```swift
                let slideLanes = rowHazards.filter { $0.kind == slideKind || $0.kind == .laserSweep }.map(\.lane)
```

  This is needed because Orbit's `slideKind` is `.arch`.

  The interval needs no extra budget. A slide row's floor (1.40 s, Orbit 2.13 s) already lets the previous jump land, and a roll lasts 0.8 s.

- [ ] **Step 4: Text.**

  In `encounterText`, replace the `.laserSweep` line with:

```swift
        case .laserSweep: return entity.cyclePhase >= 0 ? "TIMED LASER · SLIDE OR TIME IT" : worldStage == .forge ? "SENTINEL SWEEP · SLIDE" : "VINE LASERS · SLIDE"
```

  In the crash-reason switch, replace the `.laserSweep` line with:

```swift
                    case .laserSweep: crashReason = entity.cyclePhase >= 0 ? "Slide under the timed laser, or pass while its beam is dashed (off)." : "Slide under the sweeping beam. Land before trying to pass beneath it."
```

- [ ] **Step 5: The reader predicts the laser.** In `RouteAudit`, add inside the struct (above `static func driveWater`):

```swift
    /// A timed laser is read from its visible cycle: roll only if it is on at any moment of the pass,
    /// predicting arrival as elapsed + z / speed. Untimed slide hazards are always on.
    static func laserOnDuringPass(_ e: TrackEntity, _ run: RunnerSimulation) -> Bool {
        let arrival = run.elapsed + e.z / max(1, run.speed)
        let window = (e.length / 2 + 0.35) / max(1, run.speed) + 0.05
        return [arrival - window, arrival, arrival + window].contains { e.isOn(at: $0) }
    }
```

  In `drive`, replace:

```swift
        case .arch, .laserSweep:
            if obstacle.z < run.speed * 0.30, !run.isRolling { run.act(.roll) }
```

  with:

```swift
        case .arch, .laserSweep:
            if obstacle.z < run.speed * 0.30, !run.isRolling, laserOnDuringPass(obstacle, run) { run.act(.roll) }
```

- [ ] **Step 6: Visuals.** In `makeSignatureHazard`, `case .laserSweep:`, replace:

```swift
            let bloom = glowBox(2.1, 0.38, 0.035, "FF8769", at: vector(0, 1.40, 0), into: root)
            bloom.opacity = 0.20; bloom.geometry?.firstMaterial?.writesToDepthBuffer = false
```

  with:

```swift
            let bloom = glowBox(2.1, 0.38, 0.035, "FF8769", at: vector(0, 1.40, 0), into: root)
            bloom.name = "bloom"
            bloom.opacity = 0.20; bloom.geometry?.firstMaterial?.writesToDepthBuffer = false
            // Off state: a dashed line replaces the solid beam (shape, not colour). Three radius-0 boxes.
            let standby = SCNNode(); standby.name = "standby"; standby.isHidden = true; root.addChildNode(standby)
            for x in [-0.6, 0.0, 0.6] { glowBox(0.28, 0.05, 0.05, "FF896D", at: vector(x, 1.40, 0), into: standby).castsShadow = false }
```

  In `syncEntities`, replace:

```swift
            case .laserSweep:
                node.childNode(withName: "beam", recursively: false)?.opacity = reducedMotion ? 0.88 : 0.86 + sin(time * 4) * 0.10
```

  with:

```swift
            case .laserSweep:
                // The collider's state drives the look, from simulation time: solid beam = on, dashes = off.
                let on = entity.isOn(at: simulation.elapsed)
                let beam = node.childNode(withName: "beam", recursively: false)
                beam?.isHidden = !on
                beam?.opacity = reducedMotion ? 0.88 : 0.86 + sin(time * 4) * 0.10
                node.childNode(withName: "bloom", recursively: false)?.isHidden = !on
                if let standby = node.childNode(withName: "standby", recursively: false) {
                    standby.isHidden = on
                    standby.opacity = highContrastCues ? 1 : 0.6
                }
```

- [ ] **Step 7: Run it to verify it passes.** Run SkillAudit, logging to `work/g2/skill-t4.log`.
  - Expected:
    - `timed-laser=forge+orbit+verdant`
    - every READER line at 30/30
    - all binding lines green
    - `SkillAudit passed`
  - A reader failure on a laser row means the prediction is wrong. Compare the reader's `arrival` against the crash time in the FAIL line, fix `laserOnDuringPass` (at most 3 iterations), or report BLOCKED.

- [ ] **Step 8: Run the full suites and render.** Run `Scripts/test.sh`, `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t4.log` and `bash Scripts/render.sh g2-t4 2>&1 | tee work/g2/render-t4.log`. All must pass, within budget.

- [ ] **Step 9: Commit.**

```bash
git add Sources/RunnerSimulation.swift Sources/ExpeditionExpansion.swift Sources/CoastalWorld.swift Tests/Audits
git commit -m "feat: timed laser gates collide only while on; the reader predicts the cycle (Orbit, Verdant, Forge)"
```

---

### Task 5: Gap wall and stacked hazard (all worlds; new kinds)

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`EntityKind`, `isObstacle`, a new `isSolid`, `collides`, crash reasons, `encounterText`, `extendJourneyCourse`)
- Modify: `Sources/ExpeditionExpansion.swift`
- Modify: `Sources/CoastalWorld.swift` (`buildEntity`, `makeSignatureHazard`, `addActionCue`)
- Modify: `Sources/GameController.swift` (`playHazardCue`)
- Modify: `Tests/SimulationTests.swift`, `Tests/Audits/RouteAudit.swift`, `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: T3 `previousSafe`, `routeLane` and the pool wiring.
- Produces:
  - `EntityKind.wall` and `.stack`
  - `private static func isSolid(_:) -> Bool`
  - `RouteAudit.solids`
  - Odyssey patterns 10 and 11

- [ ] **Step 1: Write the failing tests.** Add this case to `SimulationTests` after the T2 cases:

```swift
            ("walls and stacked hazards stop jumps and rolls alike", {
                for kind in [EntityKind.wall, .stack] {
                    var jumped = fixture([entity(kind, z: 5, y: 0, length: 1.0)])
                    jumped.act(.jump); jumped.update(dt: 1)
                    try expect(jumped.phase == .crashed, "\(kind) must stop a jump")
                    var rolled = fixture([entity(kind, z: 5, y: 0, length: 1.0)])
                    rolled.act(.roll); rolled.update(dt: 1)
                    try expect(rolled.phase == .crashed, "\(kind) must stop a roll")
                    var dodged = fixture([entity(kind, z: 5, y: 0, length: 1.0)])
                    dodged.act(.left); dodged.update(dt: 1)
                    try expect(dodged.phase == .running, "\(kind) is solid only in its own lane")
                }
            }),
```

  In `SkillAudit.hazardWorlds`, add `"gap-wall": Set(WorldStage.allCases),` and `"stacked": Set(WorldStage.allCases),`.

  Run the T2 Step 2 simulation-test command. Expected: a compile error, `type 'EntityKind' has no member 'wall'`.

- [ ] **Step 2: Add the kinds.**
  - In `enum EntityKind`, replace `case gap, meteor, root, iceCrack, laserSweep, waterTraffic` with `case gap, meteor, root, iceCrack, laserSweep, waterTraffic, wall, stack`.
  - Replace `isObstacle` and add `isSolid` below it:

```swift
    private static func isObstacle(_ kind: EntityKind) -> Bool {
        [.barrier, .arch, .tram, .buoy, .airHazard, .gap, .meteor, .root, .iceCrack, .laserSweep, .waterTraffic, .wall, .stack].contains(kind)
    }
    /// Hazards that no jump or roll clears.
    private static func isSolid(_ kind: EntityKind) -> Bool { [.tram, .meteor, .wall, .stack].contains(kind) }
```

  - In the `collides` switch, add before `default: collides = false`:

```swift
            case .wall, .stack: collides = true // full height; a stack's barrier and bar leave no jump or roll line
```

  - In the crash-reason switch, add before `default:`:

```swift
                    case .wall: crashReason = "Steer to the opening in the wall. It moves one lane from your last route."
                    case .stack: crashReason = "A barrier under a beam blocks both jumps and slides. Change lanes."
```

  - In `encounterText`, add before `default: return ""`:

```swift
        case .wall: return "GAP WALL · FIND THE OPENING"
        case .stack: return "STACKED BARRIER · CHANGE LANES"
```

- [ ] **Step 3: Generate patterns 10 and 11.**

  In `extendJourneyCourse`, change `let safe = candidates[…]` (from T3 (a)) to `var safe = candidates[Int(nextRandom() % UInt64(candidates.count))]`, and change `let blocked = [-1, 0, 1].filter { $0 != safe }` to `var blocked = [-1, 0, 1].filter { $0 != safe }`.

  Directly after the line `if pattern == 5 && worldStage != .forge && worldStage != .harbor { pattern = 7 }`, add:

```swift
            // A gap wall's opening always moves one lane from the previous route.
            if pattern == 10 && safe == previousSafe {
                safe = previousSafe == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
                challenge.previousSafeLane = safe
                blocked = [-1, 0, 1].filter { $0 != safe }
            }
```

  Insert these cases before `default:`:

```swift
            case 10: // Gap wall: full-height walls in two lanes; the one opening is never the previous row's route.
                for lane in blocked { add(.wall, lane: lane, z: z, y: 0, length: 1.0) }
            case 11: // Stacked hazard: it looks like a jump and a slide at once, and allows neither.
                add(jumpKind, lane: safe, z: z, y: 0, length: jumpLength)
                add(slideKind, lane: blocked[0], z: z, y: 0, length: 1.1)
                add(.stack, lane: blocked[1], z: z, y: 0, length: 1.0)
                relicY = jumpHeight
```

  In the coin block, make walls and stacks bait anchors. Replace:

```swift
                let solids = rowHazards.filter { [.tram, .meteor].contains($0.kind) && $0.oncomingSpeed == 0 }
```

  with:

```swift
                let solids = rowHazards.filter { Self.isSolid($0.kind) && $0.oncomingSpeed == 0 }
```

  and replace `let laterSolids = entities[rowStart...].filter { [.tram, .meteor].contains($0.kind) &&` with `let laterSolids = entities[rowStart...].filter { Self.isSolid($0.kind) &&`.

  In `hazardPatterns`, append `10, 11` to every world:
  - `.harbor: [8, 10, 11]`
  - `.orbit: [9, 10, 11]`
  - `.mars: [8, 10, 11]`
  - `.verdant: [9, 10, 11]`
  - `.cryo: [8, 10, 11]`
  - `.forge: [9, 10, 11]`

  Update the comment to read `(8 lane-changer, 9 timed laser, 10 gap wall, 11 stacked)`.

  Neither pattern needs an extra interval. The wall's worst lateral need is 2 lanes: 0.53 s on Cryo, below its 1.50 s floor. Pattern 11 has the same shape as pattern 2.

- [ ] **Step 4: Visuals.**

  In `CoastalWorld.buildEntity`, replace `case .gap, .meteor, .root, .iceCrack, .laserSweep, .waterTraffic: return SCNNode()` with:

```swift
        case .gap, .meteor, .root, .iceCrack, .laserSweep, .waterTraffic, .wall, .stack: return SCNNode()
```

  In `makeSignatureHazard`, insert before `default: return nil`:

```swift
        case .wall:
            // Full-height slab: nothing passes over or under. Crossed bars read as "blocked" without colour.
            let palette = worldPalette
            box(2.3, 3.6, 1.0, palette.stone, at: vector(0, 1.8, 0), radius: 0, into: root)
            box(2.4, 0.18, 1.08, palette.edge, at: vector(0, 3.62, 0), radius: 0, into: root)
            for side in [-1.0, 1.0] {
                let bar = glowBox(0.16, 2.6, 0.04, "FFB36B", at: vector(0, 1.8, 0.52), into: root)
                bar.eulerAngles.z = scalar(side * 0.6)
            }
        case .stack:
            // A low barrier under an overhead beam, joined by struts: one solid block, not two separate actions.
            let palette = worldPalette
            box(2.05, 0.96, 0.95, palette.stone, at: vector(0, 0.48, 0), radius: 0, into: root)
            for side in [-1.0, 1.0] { box(0.22, 2.6, 0.4, palette.edge, at: vector(side * 1.06, 1.3, 0), radius: 0, into: root) }
            box(2.3, 0.55, 0.7, palette.stone, at: vector(0, 2.0, 0), radius: 0, into: root)
            for x in [-0.45, 0.45] { glowBox(0.07, 0.8, 0.03, "FFF0D1", at: vector(x, 1.36, 0.37), into: root) }
            glowBox(1.75, 0.08, 0.03, "FFB369", at: vector(0, 0.9, 0.49), into: root)
```

  In `addActionCue`, replace `let dodge = [EntityKind.meteor, .tram, .airHazard].contains(kind)` with:

```swift
        let dodge = [EntityKind.meteor, .tram, .airHazard, .wall, .stack].contains(kind)
```

  In `GameController.playHazardCue`, replace `[.barrier, .root, .arch, .laserSweep, .gap, .iceCrack, .tram, .meteor].contains(entity.kind) &&` with:

```swift
                  [.barrier, .root, .arch, .laserSweep, .gap, .iceCrack, .tram, .meteor, .wall, .stack].contains(entity.kind) &&
```

  Its `default` already plays the dodge warning.

- [ ] **Step 5: The reader and the fairness audit.**

  In `RouteAudit`, replace the `hazards` line with:

```swift
    static let hazards: Set<EntityKind> = [.barrier, .arch, .tram, .gap, .meteor, .root, .iceCrack, .laserSweep, .buoy, .waterTraffic, .wall, .stack]
    /// Hazards that no jump or roll clears.
    static let solids: Set<EntityKind> = [.tram, .meteor, .wall, .stack]
```

  In `drive`:
  - In `freeCost`, replace `[.tram, .meteor].contains($0.kind)` with `solids.contains($0.kind)`.
  - Replace `let choices = row.filter { $0.kind != .tram && $0.kind != .meteor }` with `let choices = row.filter { !solids.contains($0.kind) }`.
  - In `cost`, replace `[.tram, .meteor].contains($0.kind)` with `solids.contains($0.kind)`.

  In `SkillAudit.coinIsFair`, change the outer `switch o.kind {` so that it starts:

```swift
            switch o.kind {
            case .wall, .stack:
                return false // nothing reaches a coin inside a solid wall
            case .arch, .laserSweep:
```

  In `hazardFeature`, replace the two `rawValue` comparisons with `e.kind == .wall` and `e.kind == .stack`.

- [ ] **Step 6: Run them to verify they pass.**
  - Run the simulation tests: every case passes.
  - Run SkillAudit, logging to `work/g2/skill-t5.log`. Expected:
    - `gap-wall=cryo+forge+harbor+mars+orbit+verdant`
    - `stacked=` the same six worlds
    - every READER line at 30/30
    - all binding lines green
  - Reader failures follow the same rule as T3 Step 7: at most 3 refinement iterations, or report BLOCKED.

- [ ] **Step 7: Run the full suites, builds and render.**
  - Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t5.log`.
  - Build for Mac and iOS:
    - `xcodebuild -project CoastlineRush.xcodeproj -scheme CoastlineRush-macOS -configuration Debug -destination platform=macOS,arch=arm64 -derivedDataPath ./.derived CODE_SIGNING_ALLOWED=NO build > work/g2/build-mac.log`
    - the same command with `-scheme CoastlineRush-iOS -destination generic/platform=iOS`, logging to `work/g2/build-ios.log`
    - Both must print `BUILD SUCCEEDED`. A missed exhaustive `switch` fails here.
  - Run `bash Scripts/render.sh g2-t5 2>&1 | tee work/g2/render-t5.log`. It must be within budget.

- [ ] **Step 8: Commit.**

```bash
git add Sources Tests
git commit -m "feat: gap walls and stacked hazards in every world, with shape-coded cues"
```

---

### Task 6: Real meteor (Mars) and collapsing deck (Orbit, Cryo)

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`extendJourneyCourse`, `journeyEncounterInterval`, `encounterText`)
- Modify: `Sources/ExpeditionExpansion.swift`
- Modify: `Sources/CoastalWorld.swift` (meteor sync; the `.gap` and `.iceCrack` models and sync)
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: T2 `activeFrom` and `isActive`; T2 `checkTelegraphs`; T3–T5 pools.
- Produces:
  - Odyssey patterns 12 and 13
  - every newly generated Odyssey meteor carries `activeFrom`
  - deck models gain `deckPlate` and `crackDecal` child nodes

- [ ] **Step 1: Write the failing coverage entries.** In `SkillAudit.hazardWorlds`, add `"real-meteor": [.mars],` and `"collapsing-deck": [.orbit, .cryo],`. Run SkillAudit, logging to `work/g2/skill-t6-before.log`. Expected: a trap on coverage.

- [ ] **Step 2: Generate patterns 12 and 13.**

  In `extendJourneyCourse`, replace `case 3: // A lane weave gains a second beat as the stage intensifies.` and the line after it:

```swift
                for lane in blocked { add(solid, lane: lane, z: z, y: 0, length: solidLength) }
```

  with:

```swift
            case 3, 12: // A lane weave gains a second beat as the stage intensifies.
                for lane in blocked { add(solid, lane: lane, z: z, y: 0, length: solidLength) }
                // Pattern 12 (Mars): one rock landed before first sight; beside it a ring marks a late impact,
                // so the lane that looks open is not.
                if pattern == 12 { entities[rowStart].activeFrom = z + 40 }
```

  The rest of case 3, its follow beat, is unchanged.

  Insert this case before `default:`:

```swift
            case 13: // Collapsing deck: every lane cracks, then opens late; at intense tiers the landing has solids too.
                let opens = predictedSpeed * 0.5 + jumpLength / 2 + 0.35
                for lane in -1...1 { add(jumpKind, lane: lane, z: z, y: 0, length: jumpLength, activeFrom: opens) }
                relicY = jumpHeight
                if tier.rawValue >= JourneyDifficultyTier.intense.rawValue {
                    let landingOffset = predictedSpeed * (worldStage == .orbit ? 0.88 : 0.48)
                    if at + landingOffset + solidLength / 2 < localLimit {
                        for lane in blocked { add(solid, lane: lane, z: z + landingOffset, y: 0, length: solidLength) }
                    }
                }
```

  Directly after the switch's closing brace, before `if pattern == 4 {`, add:

```swift
            // Meteors land late: the ring warns, the rock falls, and only then does the collider exist (>= 1.0 s ahead).
            for index in rowStart..<entities.count where entities[index].kind == .meteor && !entities[index].activeFrom.isFinite {
                entities[index].activeFrom = predictedSpeed * 1.0 + entities[index].length / 2 + 0.35
            }
```

  In `journeyEncounterInterval`, replace `if [3, 8].contains(pattern) {` with `if [3, 8, 12].contains(pattern) {`. Pattern 13 uses the base floor, as pattern 6 does: Orbit's floor of 2.13 s covers a whole low-gravity jump.

  In `hazardPatterns`:
  - `.orbit: [9, 10, 11, 13]`
  - `.mars: [8, 10, 11, 12]`
  - `.cryo: [8, 10, 11, 13]`
  - Leave harbor, verdant and forge as they are.
  - Update the comment to read `(8 lane-changer, 9 timed laser, 10 gap wall, 11 stacked, 12 meteor strike, 13 collapsing deck)`.

  In `encounterText`, replace the `.gap` and `.iceCrack` lines with:

```swift
        case .gap: return entity.activeFrom.isFinite ? "COLLAPSING DECK · JUMP THE CRACKS" : "BROKEN ORBITAL DECK · JUMP"
        case .iceCrack: return entity.activeFrom.isFinite ? "COLLAPSING ICE · JUMP THE CRACKS" : "FRACTURING ICE · JUMP"
```

  Cryo's collapsing deck uses Cryo's jump kind, `.iceCrack`. It has the same jump class and collision band as `.gap`, and looks like ice; see the deviations note at the end of this plan.

- [ ] **Step 3: Visuals.**

  In `syncEntities`, replace the `.meteor` case's first line:

```swift
                let descent = max(0, min(1, (entity.z - 18) / 36))
```

  with:

```swift
                // The rock lands exactly where its collider becomes active; legacy meteors (no activeFrom) land 18 m out.
                let impact = entity.activeFrom.isFinite ? entity.activeFrom : 18
                let descent = max(0, min(1, (entity.z - impact) / 36))
```

  Replace the `.gap` and `.iceCrack` cases:

```swift
            case .gap:
                node.scale.z = scalar(entity.length / 7)
```

  and

```swift
            case .iceCrack:
                node.scale.z = scalar(entity.length / 3.2)
                node.childNode(withName: "crackWarning", recursively: false)?.opacity = reducedMotion ? 0.8 : 0.7 + sin(time * 4) * 0.15
```

  with one case:

```swift
            case .gap, .iceCrack:
                node.scale.z = scalar(entity.length / (entity.kind == .gap ? 7 : 3.2))
                node.childNode(withName: "crackWarning", recursively: false)?.opacity = reducedMotion ? 0.8 : 0.7 + sin(time * 4) * 0.15
                // Before collapse the deck is intact under a zigzag crack; after it, the void shows. Same z as the collider.
                let intact = !entity.isActive
                node.childNode(withName: "deckPlate", recursively: false)?.isHidden = !intact
                if let crack = node.childNode(withName: "crackDecal", recursively: false) {
                    crack.isHidden = !intact
                    crack.scale.x = scalar(highContrastCues ? 1.6 : 1)
                }
```

  In `makeSignatureHazard`, at the end of `case .gap:` (after the arrow loop), add:

```swift
            // Collapsing deck: an intact plate under a zigzag crack until the collider opens. Radius-0 boxes.
            let plate = box(2.56, 0.05, 7, worldPalette.floor, at: vector(0, 0.03, 0), radius: 0, into: root)
            plate.name = "deckPlate"; plate.isHidden = true
            plate.geometry?.firstMaterial = deckMaterial(for: renderedStage)
            let crack = SCNNode(); crack.name = "crackDecal"; crack.isHidden = true; root.addChildNode(crack)
            for i in 0..<6 {
                let stroke = glowBox(0.08, 0.02, 1.3, "FFD08A", at: vector(i % 2 == 0 ? -0.2 : 0.2, 0.065, -3 + Double(i) * 1.2), into: crack)
                stroke.eulerAngles.y = scalar(i % 2 == 0 ? 0.5 : -0.5)
                stroke.castsShadow = false
            }
```

  At the end of `case .iceCrack:` (after the `crackWarning` loop), add:

```swift
            let plate = box(2.5, 0.05, 3.2, "A6D9E9", at: vector(0, 0.03, 0), radius: 0, into: root)
            plate.name = "deckPlate"; plate.isHidden = true
            plate.geometry?.firstMaterial = iceMaterial()
            let crack = SCNNode(); crack.name = "crackDecal"; crack.isHidden = true; root.addChildNode(crack)
            for i in 0..<3 {
                let stroke = glowBox(0.08, 0.02, 1.1, "E6FBFF", at: vector(i % 2 == 0 ? -0.2 : 0.2, 0.065, -1.0 + Double(i) * 1.0), into: crack)
                stroke.eulerAngles.y = scalar(i % 2 == 0 ? 0.5 : -0.5)
                stroke.castsShadow = false
            }
```

  The target ring's existing opacity pulse already uses `reducedMotion ? 0.8 : …`.

- [ ] **Step 4: Run it to verify it passes.** Run SkillAudit, logging to `work/g2/skill-t6.log`.
  - Expected:
    - `real-meteor=mars`
    - `collapsing-deck=cryo+orbit`
    - `TELEGRAPHS lateChanges=0`
    - every READER line at 30/30
    - all binding lines green
  - The reader jumps every gap and iceCrack it reaches, cracked or open, so its logic needs no change. If it fails, follow T3 Step 7.

- [ ] **Step 5: Run the full suites and render.** Run `Scripts/test.sh`, `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-t6.log` and `bash Scripts/render.sh g2-t6 2>&1 | tee work/g2/render-t6.log`. All must pass, within budget.

- [ ] **Step 6: Commit.**

```bash
git add Sources Tests/Audits/SkillAudit.swift
git commit -m "feat: meteors collide only after their telegraphed impact; decks collapse after a crack warning"
```

---

### Task 7: Final verification, hazard preview and G2 report

**Files:**
- Create (not committed): `work/HazardPreview.swift`
- Commit: none, unless a check needs a fix.

**Interfaces:**
- Consumes: T1–T6.
- Produces: the G2 report, `work/g2/report.txt`.

- [ ] **Step 1: Full suites, builds and render.**
  - Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g2/audit-final.log`.
  - Run both `xcodebuild` commands from T5 Step 7.
  - Run `bash Scripts/render.sh g2-final 2>&1 | tee work/g2/render-final.log`.
  - Expected: all pass, and every `ms=` value is within the limits.
  - The standard shots run the first 6 s of each world, which is rows 0–3 and so contains no new hazards. Step 2 renders the new hazards on purpose.

- [ ] **Step 2: Render the hazards side by side.** Create `work/HazardPreview.swift`:

```swift
import AppKit
import Metal
import SceneKit

/// Throwaway visual check: every G2 hazard in every world, held still at fixed z. Not part of the build.
@main struct HazardPreview {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "work/shots/g2-hazards")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
        let size = CGSize(width: 900, height: 1500)
        for stage in 0..<6 {
            let world = CoastalWorld(assetsURL: resources)
            world.applyQuality(.ultra)
            world.resize(aspect: Double(size.width / size.height))
            var run = RunnerSimulation()
            run.start(seed: 7, mode: .odyssey, startStage: stage)
            func e(_ id: Int, _ kind: EntityKind, _ lane: Int, _ z: Double, _ length: Double) -> TrackEntity {
                TrackEntity(id: 10_000 + id, kind: kind, lane: lane, z: z, y: 0, length: length)
            }
            var shifting = e(1, .tram, -1, 34, 7); shifting.targetLane = 0; shifting.motionStart = 38; shifting.motionLength = 8
            var laserOn = e(2, .laserSweep, 1, 20, 1.1); laserOn.cyclePhase = 0
            var laserOff = e(3, .laserSweep, 0, 20, 1.1); laserOff.cyclePhase = 0.9
            var meteor = e(4, .meteor, 1, 46, 2); meteor.activeFrom = 30
            var deck = e(5, stage == 4 ? .iceCrack : .gap, 0, 58, 7); deck.activeFrom = 20
            run.replaceTrackForTesting([shifting, laserOn, laserOff, meteor, deck,
                                        e(6, .wall, -1, 72, 1), e(7, .wall, 0, 72, 1), e(8, .stack, 1, 72, 1)])
            var time = 0.0
            for _ in 0..<20 { time += 1.0 / 60; world.update(simulation: run, character: "milo", board: "tideline", time: time) }
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = world.scene
            renderer.pointOfView = world.camera
            _ = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let started = Date()
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let ms = Date().timeIntervalSince(started) * 1000
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
            try png.write(to: out.appendingPathComponent("\(WorldStage.ordered[stage].rawValue).png"))
            print(WorldStage.ordered[stage].rawValue, String(format: "ms=%.1f", ms))
        }
    }
}
```

  Build and run it, with the sandbox disabled:

```bash
swiftc -O -swift-version 5 -module-cache-path work/mc Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift \
  Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  work/HazardPreview.swift -o work/hazard-preview && ./work/hazard-preview work/shots/g2-hazards | tee work/g2/hazard-preview.log
```

  Open the six PNGs with the Read tool and confirm:
  - The left tram is offset toward the centre lane with a ">" chevron on its roof.
  - The right laser has a solid beam and the centre laser has three dashes.
  - The meteor rock is in mid-air above its rings.
  - The centre deck is intact with a zigzag crack.
  - There are two walls with crossed bars and a stack (barrier, beam and struts).
  - The dodge cues (X) are on the walls and stack.
  - Each hazard reads clearly against its world.

  Record each world's `ms` beside its render budget. This preview shows more hazards than any real row, so a value above the limit is reported, not failed.

- [ ] **Step 3: Write the report.** Create `work/g2/report.txt` containing these lines from `work/g2/audit-final.log`:
  - every `COIN-FOLLOWER`, `READER`, `PLACED-LINES`, `HAZARD-COVERAGE`, `TELEGRAPHS`, `BAIT-ESCAPES` and `FAIRNESS` line
  - the render `ms` values (standard and preview)
  - the T1 bait-escape count before the fix

  Put the G1 numbers beside them, from `work/g1fix/skill-*.log`:
  - Odyssey followers 100% failed before world 2 on both difficulties
  - Endless median 28.5 s (Std) / 11.3 s (Expert)
  - PLACED-LINES Odyssey safe 33.1%, Endless safe 30.2%

  The coin-follower numbers are informational until G3.

- [ ] **Step 4: Commit only if a fix was needed.** If Steps 1–2 required a code change, commit it with the reason. Otherwise there is nothing to commit; `work/` is gitignored.

## Deliberate deviations from the controller's wording

- **`activeFrom` encoding.** `activeFrom` keeps its `.infinity` default in memory, but it is written only when finite. The default `JSONEncoder` used by `RunCheckpointStore.save` throws on infinity, which would silently stop every checkpoint save.
- **Bait escape padding.** The guard is `laneIsClear(safe, from: last − 0.35, to: solid.z + hl + resume + 0.35)`. That is the controller's range plus collision padding at both ends and the resume switch, matching the audit's own window, so the generator is never more lenient than the audit. Arc baits start the window behind the same row's jump, which the leap clears; without that exemption the audit flags fair in-flight escapes.
- **Safe-line band.** The safe-line band narrows from `0..<30` to `0..<25`. Measured: the stricter bait guard pushed the placed Odyssey safe share to 36.5% without it.
- **Cryo's collapsing deck** uses `.iceCrack`, Cryo's jump kind, rather than `.gap`. It has the same collision class, and `.gap` would draw an orbital deck in an ice world.
- **Hazard pools are wired per task**, together with each hazard, and coverage is checked per task, rather than all in Task 7. That way each task can be tested on its own through the reader. Task 7 is the final verification.
- **All newly generated Odyssey meteors get `activeFrom`**, not only pattern 12's. This keeps every meteor's visual landing equal to its collider. Pattern 12 adds a landed-early rock beside a late ring.
