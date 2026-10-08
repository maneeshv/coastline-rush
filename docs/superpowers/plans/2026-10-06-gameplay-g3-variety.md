# Gameplay Overhaul G3 — Variety, Escalation and Balance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the course repeating itself, keep Endless escalating after the speed cap, tighten Expert forgiveness, and retire stale ghosts. Then report both bots against the spec targets: a coin-follower should fail and a hazard reader should clear everything.

**Architecture:**
- Odyssey pattern choice moves from a weighted random pick to a seeded, persisted shuffle bag per world and tier, with no pattern repeated within the last 3 rows.
- Forks and finales keep their authored sets but use a per-seed order computed from `runSeed`. That order is stateless, so Daily follows its date seed.
- Endless gains gated row types: full-width jump and slide rows, jump→slide compounds, and the G2 hazards. After the speed cap, spacing tightens toward a floor over 120 s.
- Expert hitboxes and board windows change in `collectAndCollide` and `act(.board)`.
- Ghost revisions bump.
- `LegacyContinuityAudit` gains a `verify` mode, and `audit.sh` runs it against the pre-overhaul source.
- `SkillAudit` gains pattern, escalation and teaching-row checks, and prints the coin-follower numbers against their targets.

**Tech Stack:** Swift 5.9, SceneKit/SwiftUI (help text only), headless `swiftc` audits. No new dependencies and no new Sources files, so `xcodegen generate` is not needed.

**Spec:** `docs/superpowers/specs/2026-10-06-gameplay-overhaul-design.md` (sections G3, Compatibility and Verification). This plan requires the G2 plan (`2026-10-06-gameplay-g2-hazards.md`) to be implemented first. The "replace this" code below is quoted as G2 leaves it.

## Global Constraints

- iOS 16+ / macOS 13+, with one shared `Sources/` tree.
- Every row keeps at least one reachable exit.
- The hazard reader clears 100% of Odyssey routes and survives 300 s of Endless on every seed, without boards.
- 0 unfair coins and pickups, at first sight and at collection time.
- The placed safe-line share is at or below 35% per mode.
- Determinism holds, and Daily is reproducible.
- Checkpoints decode: every new persisted field uses a `decodeIfPresent` default.
- `Scripts/test.sh` and `bash Scripts/audit.sh` pass. Any test that encodes old behaviour is updated in the same commit, with the reason stated.
- Mac and iOS builds succeed.
- `Scripts/render.sh` stays within +25% of harbor 286, orbit 117, mars 131, verdant 254, cryo 141, forge 149 and jetski 279 ms. The limits are 357.5 / 146.3 / 163.8 / 317.5 / 176.3 / 186.3 / 348.8 ms. One re-run is allowed.
- Environment:
  - `swiftc`, `xcodebuild` and `Scripts/*.sh` run outside the Claude sandbox.
  - Outputs go to `work/g3/`, never `$TMPDIR`.
  - `-O` builds do not print `precondition` messages.
  - zsh does not word-split `$VAR`, so use bash.
  - Every new Sources file needs `xcodegen generate`. This plan adds none.
- The coin-follower targets are reported and reviewed with the user. The final task makes at most one bounded tuning pass: interval and floor constants only, at most 3 iterations, and the reader stays at 100%.

## Reference facts (from the code after G2; derivations shown)

**Odyssey pools** (`extendJourneyCourse`, after G2 Task 3):
- Base pools: warmup `[0,0,1,2,3,4]`, pressure `[0,1,2,2,3,4,5,6]`, intense `[0,1,2,3,3,4,5,6,7]`, overdrive `[0,1,2,2,3,4,5,6,6,7,7]`.
- `WorldStage.hazardPatterns` is added from the pressure tier on, and from row 4 on.
- The pick is `pool[nextRandom() % count]`, which allows back-to-back repeats.

**Remaps:**
- 4 → 2 unless the world is harbor, mars or forge.
- 5 → 7 unless forge or harbor. G3 adds Verdant to the 5 exceptions.

**Effective patterns per world after G2:**
- harbor 11, orbit 10, mars 11, verdant **9**, cryo 10, forge 11.
- With pattern 5 enabled, Verdant has {0, 1, 2, 3, 5, 6, 7, 9, 10, 11} = 10.
- Across all worlds, patterns 0–13 make 14 distinct.

**Bag feasibility.** The fewest unique entries any pool has is 4: an Orbit-style warmup `[0,0,1,2,3,4]` after the 4 → 2 remap is {0, 1, 2, 3}. That pool is reachable only in revision-5 stages, which have no tier floor. 4 is more than the 3-row window, so a fresh bag always holds a pattern outside the window.

**Forks and finales:**
- Fork patterns:
  - safe route: `row % 3 == 0 ? 0 : 3`
  - Mars and Harbor risky: `row % 2 == 0 ? 4 : 7`
  - other risky: `[2, 6, 7, 3][row % 4]`
- Finales use `worldStage.finalePatterns[finaleRows % count]`.
- `runSeed` (`enhancements.runSeed`) is persisted, and is the date seed for Daily.

**Endless** (`extendTrack`, ~:930–1003):
- Speed is `min(32, 12 + 0.18t)` on Standard and `min(36, 16 + 0.24t)` on Expert. The cap arrives at (32 − 12)/0.18 = **111.1 s** on Standard and (36 − 16)/0.24 = **83.3 s** on Expert.
- Rows are spaced `26 + [0, 4]` m (Expert `23 + [0, 4]`), with 2-obstacle rows (primary plus secondary after 65 m).
- Rows are generated 190 m ahead.

**Endless jump physics:**
- Velocity 8.5, gravity 22, so airtime is 0.773 s and the apex is 1.64 m.
- The reader jumps 0.32 s before a barrier and lands 0.453 s after it.
- A following row the reader must jump needs a grounded trigger 0.32 s ahead of it, so the gap is ≥ 0.773 + 0.05 ≈ **0.9 s × arrival speed**.

**Compound** (jump row, then slide row at +0.75 s):
- Landing is at +0.453 s. The reader's roll trigger fires 0.30 s before the slide row, at +0.45 s.
- A roll in mid-air sets `verticalVelocity ≤ −15`, so a runner at the 1.64 m apex is down within 0.11 s.
- The 0.8 s roll covers the slide row.
- The next row is ≥ 0.9 s after the slide row.

**Spacing floor:**
- Standard 22 m: at 32 m/s that is 0.69 s a row, above the existing Expert minimum of 23/36 = 0.64 s, which the reader already survives.
- Expert 20 m: at 36 m/s, 0.56 s.
- Tightening ends 120 s after the cap: at 231 s on Standard and 203 s on Expert. Both are inside the reader's 300 s runs.

**Endless lane-changer:**
- Length 12. Lead 1.0 + 1/9 = 1.111 s on Standard, 0.911 s on Expert.
- At 32 m/s: complete = 32 × 1.111 + 6.35 = 41.9 m, start 61.1 m. Drawn from 135 m, so it telegraphs (135 − 61.1)/32 = 2.3 s ≥ 1.0.
- Expert at 36 m/s: start 60.7 m, so 2.07 s ≥ 0.8.

**Collision** (`collectAndCollide`):
- Window `abs(z) < length/2 + 0.35`. Lateral `abs(lateral − lanePos) < 0.55`.
- Near miss: `closest >= 0.55` (and < 0.98).
- Board: `boardTime = 30`. A hit clears obstacles within `abs(z) < 18` in every mode.
- Revive gives 3.0 s. A portal arrival gives 3 s. Both are unchanged.

**Ghosts** (`ReplayGhost.swift`): `currentRevision = 8`, `legacyModeRevision = 5`, Jet Ski `4`.

**LegacyContinuityAudit:**
- It is not in `audit.sh`, and there is no archived baseline in the repository.
- The last pre-overhaul commit is `e3049e5`. Sources are unchanged from there back to `5efe7b2`.
- Revision-4 stages use `extendLegacyJourneyCourse`, which the overhaul never touches. Revision 5 and 6 stages run the current pattern code.

**G1 numbers** (`work/g1fix`):
- Coin-follower: Odyssey failed before world 2 in 100% of runs (Std and Expert). Endless median 28.5 s (Std) and 11.3 s (Expert).
- PLACED-LINES safe: Odyssey 33.1%, Endless 30.2%.

## File map

| File | Change |
|---|---|
| `Sources/RunnerSimulation.swift` | T1: `PatternBag` (persisted), `PatternRecord`/`patternLog`, `drawPattern`, `seededOrder` and the selection block. T2: Endless escalation, spacing constants and `escalationFirstSeen`. T3: `collisionPadding`, `lateralTolerance`, board window and clear radius. T6: `placedLineLog`, `placeCoins` returns its line, and the `coinLine` doc. T7: `RunMode.instructions`. |
| `Sources/ReplayGhost.swift` | T4: revisions 9 and 6. |
| `Sources/GameUI.swift` | T7: help text. |
| `Tests/SimulationTests.swift` | T2: procedural-row invariant. T3: board and hitbox cases. |
| `Tests/ProfileTests.swift` | T4: ghost revisions. |
| `Tests/Audits/SkillAudit.swift` | T1: patterns and Daily determinism. T2: escalation. T6: Sprint precondition, teaching rows and collection window. T8: targets. |
| `Tests/Audits/LegacyContinuityAudit.swift` | T5: `verify` mode. |
| `Scripts/audit.sh` | T5: legacy continuity against `e3049e5`. |
| `README.md`, `V8.md` (new, at the repository root) | T7 docs; T8 verification numbers. |

---

### Task 1: Shuffle bag, per-seed forks and finales, and ten patterns per world

**Files:**
- Modify: `Sources/RunnerSimulation.swift`
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: G2 `WorldStage.hazardPatterns`, patterns 8–13 and `previousSafe`.
- Produces:
  - `struct PatternBag: Codable, Equatable` (persisted under the key `patternBag`)
  - `struct PatternRecord`, and `RunnerSimulation.patternLog: [PatternRecord]` (not persisted)
  - `drawPattern(from:key:)` and `seededOrder(_:salt:)`
  - `SkillAudit.checkPatterns(_:)` and the output line `PATTERNS …`

- [ ] **Step 1: Write the failing audit.** In `SkillAudit`, add inside the struct:

```swift
    static var patternsByWorld: [WorldStage: Set<Int>] = [:]
    static var bagRepeats = 0
    /// Every world must build 10+ effective patterns (14+ overall), and a bag row never repeats one of the
    /// previous three rows of its world.
    static func checkPatterns(_ log: [PatternRecord]) {
        var window: [Int] = [], world: WorldStage? = nil
        for record in log {
            if record.world != world { window = []; world = record.world }
            patternsByWorld[record.world, default: []].insert(record.pattern)
            if record.fromBag && window.contains(record.pattern) {
                bagRepeats += 1
                if bagRepeats <= 5 { print("BAG-REPEAT world=\(record.world) pattern=\(record.pattern) after \(window)") }
            }
            window = Array((window + [record.pattern]).suffix(3))
        }
    }
```

  In `main()`, in the Odyssey reader loop, directly after `placed[run.mode, default: [:]].merge(run.placedCoinLines, uniquingKeysWith: +)`, add `checkPatterns(run.patternLog)`.

  Immediately before the `HAZARD-COVERAGE` print, add:

```swift
        let distinct = Set(patternsByWorld.values.flatMap { $0 })
        print("PATTERNS total=\(distinct.count) " + WorldStage.allCases.map { "\($0.rawValue)=\(patternsByWorld[$0, default: []].count)" }.joined(separator: " ") + " bagRepeats=\(bagRepeats)")
        precondition(distinct.count >= 14 && WorldStage.allCases.allSatisfy { patternsByWorld[$0, default: []].count >= 10 },
                     "Odyssey needs 14+ patterns and 10+ effective patterns per world")
        precondition(bagRepeats == 0, "A bag row must not repeat a pattern from the last three rows")
```

  At the end of `main()`, after the existing determinism precondition, add:

```swift
        // Daily follows its date alone: any launch seed rebuilds the same course, forks and finales included.
        func dailyTrack(seed: UInt64) -> [TrackEntity] {
            var run = RunnerSimulation()
            run.start(seed: seed, boards: 0, mode: .odyssey, dailyID: "2026-10-06")
            for _ in 0..<3_000 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60) }
            return run.entities
        }
        precondition(dailyTrack(seed: 1) == dailyTrack(seed: 2), "Daily Odyssey must reproduce from its date alone")
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
mkdir -p work/g3
swiftc -O -whole-module-optimization -swift-version 5 -module-cache-path work/g3/modules -D ROUTE_HELPER \
  Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift \
  Tests/Audits/RouteAudit.swift Tests/Audits/SkillAudit.swift -o work/g3/skill && work/g3/skill | tee work/g3/skill-t1-before.log
```

  Expected: a compile error, `cannot find type 'PatternRecord' in scope`.

- [ ] **Step 3: Add the bag state.** In `Sources/RunnerSimulation.swift`, directly after `struct RunChallenge { … }`, add:

```swift
/// Odyssey shuffle-bag state, persisted so a restored run draws exactly the patterns the original would have.
struct PatternBag: Codable, Equatable {
    var key = -1
    var remaining: [Int] = []
    var recent: [Int] = []
}

/// One generated Odyssey row, for audits. Not persisted.
struct PatternRecord: Equatable {
    let world: WorldStage
    let pattern: Int
    /// Drawn from the shuffle bag: not a forced opening row, a fork row or a finale row.
    let fromBag: Bool
}
```

  In `RunnerSimulation`, directly below `private(set) var baitEscapes: [Int: Int] = [:]`, add:

```swift
    private var patternBag = PatternBag()
    /// Every generated Odyssey row, for audits. Not persisted: a restored run starts a new log.
    private(set) var patternLog: [PatternRecord] = []
```

  In the `CodingKeys` enum of the `extension RunnerSimulation` that holds `init(from:)`, append `, patternBag` to the end of the `case` list. In `init(from:)`, after the `generateTrack = …` line, add:

```swift
        patternBag = try values.decodeIfPresent(PatternBag.self, forKey: .patternBag) ?? patternBag
```

- [ ] **Step 4: Add the bag draw and the per-seed order.** Directly above `private func journeyEncounterInterval`, add:

```swift
    /// Shuffle-bag pattern choice: each pool entry is used once per bag, and a pattern from the last three rows is
    /// skipped while the bag (refilled as needed) holds another. Draws use the course RNG, so seeds and Daily replay.
    private mutating func drawPattern(from pool: [Int], key: Int) -> Int {
        if patternBag.key != key { patternBag.key = key; patternBag.remaining = [] }
        let recent = patternBag.recent
        if !patternBag.remaining.contains(where: { !recent.contains($0) }) {
            var fresh = pool
            for i in stride(from: fresh.count - 1, to: 0, by: -1) { fresh.swapAt(i, Int(nextRandom() % UInt64(i + 1))) }
            patternBag.remaining += fresh
        }
        // Every pool holds at least four distinct patterns, so a fresh bag always has one outside the 3-row window.
        let index = patternBag.remaining.firstIndex { !recent.contains($0) }!
        return patternBag.remaining.remove(at: index)
    }

    /// A per-seed permutation of an authored fork or finale set. It reads runSeed (Daily: the date seed) and never
    /// draws from the course RNG, so it needs no persisted state.
    private func seededOrder(_ items: [Int], salt: UInt64) -> [Int] {
        var state = (runSeed ^ (salt &* 0x9E37_79B9_7F4A_7C15)) | 1
        var order = items
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            order.swapAt(i, Int((state &* 2_685_821_657_736_338_717) % UInt64(i + 1)))
        }
        return order
    }
```

- [ ] **Step 5: Use them in `extendJourneyCourse`.** Replace this block, as G2 leaves it, from `let base: [Int]` through the 5 → 7 remap line:

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
            // Guarantee an early introduction to each world's vertical action.
            if row == 0 { pattern = 0 }
            if row == 1 { pattern = worldStage == .orbit ? 3 : 1 }
            if inBranch {
                if branchRoute == .safe { pattern = row % 3 == 0 ? 0 : 3 }
                else if worldStage == .mars || worldStage == .harbor { pattern = row % 2 == 0 ? 4 : 7 }
                else { pattern = [2, 6, 7, 3][row % 4] }
            }
            if inFinale {
                let phrase = worldStage.finalePatterns
                pattern = phrase[expansion.finaleRows % phrase.count]
                expansion.finaleRows += 1
            }
            let canTransfer = [.harbor, .mars, .forge].contains(worldStage)
            if pattern == 4 && !canTransfer { pattern = 2 }
            if pattern == 5 && worldStage != .forge && worldStage != .harbor { pattern = 7 }
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
            let world = worldStage
            let canTransfer = [.harbor, .mars, .forge].contains(world)
            // World remaps come first, so the bag holds the patterns this world actually builds. Verdant keeps
            // charging cargo (5), which gives every world at least ten effective patterns.
            func effective(_ p: Int) -> Int {
                if p == 4 && !canTransfer { return 2 }
                if p == 5 && ![.forge, .harbor, .verdant].contains(world) { return 7 }
                return p
            }
            // New hazards join pressure and later tiers, never a world's first rows.
            let pool = (base + (tier == .warmup || row < 4 ? [] : world.hazardPatterns)).map(effective)
            var pattern = drawPattern(from: pool, key: stageIndex * 16 + tier.rawValue * 2 + (row < 4 ? 0 : 1))
            // Guarantee an early introduction to each world's vertical action.
            if row == 0 { pattern = 0 }
            if row == 1 { pattern = world == .orbit ? 3 : 1 }
            // Forks and finales keep their authored sets, in a per-seed order (Daily: per date).
            let salt = UInt64(stageIndex * 8 + expeditionCycle * 64)
            if inBranch {
                if branchRoute == .safe { pattern = seededOrder([0, 3, 3], salt: salt + 1)[row % 3] }
                else if world == .mars || world == .harbor { pattern = seededOrder([4, 7], salt: salt + 2)[row % 2] }
                else { pattern = seededOrder([2, 6, 7, 3], salt: salt + 3)[row % 4] }
            }
            if inFinale {
                let phrase = seededOrder(world.finalePatterns, salt: salt + 4)
                pattern = phrase[expansion.finaleRows % phrase.count]
                expansion.finaleRows += 1
            }
            pattern = effective(pattern)
```

  The G2 gap-wall override (`if pattern == 10 && safe == previousSafe { … }`) stays directly after this block.

  Then, directly before `let rowStart = entities.count`, add:

```swift
            // The 3-row window covers every built row, forced and authored ones included.
            patternBag.recent = Array((patternBag.recent + [pattern]).suffix(3))
            patternLog.append(PatternRecord(world: worldStage, pattern: pattern, fromBag: row >= 2 && !inBranch && !inFinale))
```

  This sits after the `localLimit` `continue`, so skipped rows neither enter the window nor the log.

- [ ] **Step 6: Run it to verify it passes.** Re-run the Step 2 command, logging to `work/g3/skill-t1.log`.
  - Expected:
    - `PATTERNS total=14` with every world ≥ 10, including `verdant=10`
    - `bagRepeats=0`
    - every READER line at 30/30
    - FAIRNESS 0
    - PLACED-LINES ≤ 35%
    - the Daily precondition passes
    - `SkillAudit passed`
  - If a shuffled finale or fork order makes the reader fail, read the FAIL lines. Refine `RouteAudit.drive` only, at most 3 iterations, or report BLOCKED with the failing pattern order. Do not change the authored sets.

- [ ] **Step 7: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t1.log`.
  - RouteAudit's checkpoint round-trips (every 401 ticks, comparing 60 future ticks) and JourneyTests' re-decode every 601 ticks prove that `patternBag` persists. A missing key fails as `Checkpoint future mismatch`.
  - The v3–v6 snapshot tests in JourneyTests prove that a checkpoint without `patternBag` still decodes.

- [ ] **Step 8: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/Audits/SkillAudit.swift
git commit -m "feat: seeded shuffle bag for Odyssey patterns; per-seed fork and finale order; ten patterns in every world"
```

---

### Task 2: Endless escalation

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`extendTrack`; new constants; `escalationFirstSeen`)
- Modify: `Tests/SimulationTests.swift` (`"procedural rows retain an open lane and increase difficulty"`)
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Consumes: G2 `.wall`, `.stack`, `isSolid`, the `add` parameters, and the arrival-lane reads in `oncomingLaneIsFair`, `placeCoins` and the audits.
- Produces:
  - `static let endlessSpacing` and `static let endlessSpacingFloor`, the balance knobs
  - `RunnerSimulation.escalationFirstSeen: [Int: Double]` (not persisted)
  - output line `ENDLESS-ESCALATION …`

- [ ] **Step 1: Write the failing audit.** In `SkillAudit`, add inside the struct:

```swift
    static var escalationSeen: [Bool: Set<Int>] = [:]
    static var earlyEscalation = 0
    /// Endless row types 0–6 (0/1 full-width jump/slide, 2 compound, 3 lane-changer, 4 gap wall, 5 stack, 6 timed laser)
    /// must all appear, each only after its gate: full-width at half the gate, the rest at the gate (60 s, Expert 30 s).
    static func checkEscalation(_ run: RunnerSimulation) {
        let gate = run.expert ? 30.0 : 60.0
        for (kind, first) in run.escalationFirstSeen {
            escalationSeen[run.expert, default: []].insert(kind)
            if first < (kind <= 1 ? gate / 2 : gate) { earlyEscalation += 1 }
        }
    }
```

  In the Endless reader loop, directly after `placed[run.mode, default: [:]].merge(run.placedCoinLines, uniquingKeysWith: +)`, add `checkEscalation(run)`. Before the `PATTERNS` print, add:

```swift
        print("ENDLESS-ESCALATION standard=\(escalationSeen[false, default: []].sorted()) expert=\(escalationSeen[true, default: []].sorted()) early=\(earlyEscalation)")
        precondition([false, true].allSatisfy { escalationSeen[$0, default: []] == Set(0...6) } && earlyEscalation == 0,
                     "Endless must escalate through every row type, each after its gate")
```

  Run the T1 Step 2 command. Expected: a compile error, `value of type 'RunnerSimulation' has no member 'escalationFirstSeen'`.

- [ ] **Step 2: Add the constants and the tally.** Directly below `static let laneWidth = 2.6`, add:

```swift
    /// Endless row spacing (m) before the speed cap, and the floor reached 120 s after it. Balance-pass knobs.
    static let endlessSpacing = (standard: 26.0, expert: 23.0)
    static let endlessSpacingFloor = (standard: 22.0, expert: 20.0)
```

  Below `private(set) var patternLog`, add:

```swift
    /// First elapsed time each Endless escalation row type (0–6) was generated, for audits. Not persisted.
    private(set) var escalationFirstSeen: [Int: Double] = [:]
```

- [ ] **Step 3: Replace the Endless row loop.** In `extendTrack`, replace the whole `while nextPatternDistance < distance + 190 { … }` loop with:

```swift
        while nextPatternDistance < distance + 190 {
            let at = nextPatternDistance
            let centerZ = at - distance
            let previousSafe = challenge.previousSafeLane
            // Escalation draws only once its first gate opens, so the opening course is unchanged. Full-width rows open
            // at half the gate; compounds and the G2 hazards at the gate (60 s Standard, 30 s Expert).
            let gate = expert ? 30.0 : 60.0
            var escalation = elapsed >= gate / 2 ? Int(nextRandom() % 10) : 9
            if elapsed < gate && escalation >= 2 { escalation = 9 }
            if escalation <= 6 && escalationFirstSeen[escalation] == nil { escalationFirstSeen[escalation] = elapsed }
            // Each row has a visible route; consecutive clear lanes are at most one lane apart.
            // Shorter rows and higher speed force decisions without impossible lateral jumps.
            let candidates = [-1, 0, 1].filter { abs($0 - previousSafe) <= 1 }
            var safeLane = candidates[Int(nextRandom() % UInt64(candidates.count))]
            if safeLane == previousSafe && nextRandom() % 3 != 0 {
                safeLane = safeLane == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
            }
            // A gap wall's opening always moves one lane from the previous route.
            if escalation == 4 && safeLane == previousSafe {
                safeLane = previousSafe == 0 ? (nextRandom() % 2 == 0 ? -1 : 1) : 0
            }
            challenge.previousSafeLane = safeLane
            var routeLane = safeLane
            let pattern = Int(nextRandom() % 9)
            var obstacleLanes = [-1, 0, 1].filter { $0 != safeLane }
            if nextRandom() % 2 == 0 { obstacleLanes.reverse() }
            let primary = obstacleLanes[0]
            // Rows arrive about 190 m later, by which time the run is faster.
            let arrivalSpeed = min(expert ? 36 : 32, speed + (expert ? 0.24 : 0.18) * 190 / max(1, speed))
            let secondary: EntityKind = pattern % 2 == 0 ? .arch : .barrier
            let secondaryLength = secondary == .barrier ? 0.8 : 1.1
            switch escalation {
            case 0, 1: // Full-width jump or slide: lane changes alone cannot solve it.
                for lane in -1...1 {
                    add(escalation == 0 ? .barrier : .arch, lane: lane, z: centerZ, y: 0, length: escalation == 0 ? 0.8 : 1.1)
                }
            case 2: // Jump, then slide: the slide row arrives 0.75 s after the jump row.
                for lane in -1...1 { add(.barrier, lane: lane, z: centerZ, y: 0, length: 0.8) }
                for lane in -1...1 { add(.arch, lane: lane, z: centerZ + arrivalSpeed * 0.75, y: 0, length: 1.1) }
            case 3: // Lane-changer: a blocked lane's tram shifts into the open lane, so the open lane swaps.
                // It leaves a lane next to both the open lane and the previous route.
                let origin = obstacleLanes.first { abs($0 - safeLane) == 1 && abs($0 - previousSafe) <= 1 }!
                let complete = arrivalSpeed * ((expert ? 0.8 : 1.0) + 1 / 9.0) + 6 + 0.35
                add(.tram, lane: origin, z: centerZ, y: 0, length: 12, targetLane: safeLane,
                    motionStart: complete + arrivalSpeed * 0.6, motionLength: arrivalSpeed * 0.6)
                add(secondary, lane: obstacleLanes.first { $0 != origin }!, z: centerZ, y: 0, length: secondaryLength)
                challenge.previousSafeLane = origin
                routeLane = origin
            case 4: // Gap wall: one opening, one lane from the previous route.
                for lane in obstacleLanes { add(.wall, lane: lane, z: centerZ, y: 0, length: 1.0) }
            case 5, 6: // A stacked barrier or a timed laser takes the primary slot.
                if escalation == 5 { add(.stack, lane: primary, z: centerZ, y: 0, length: 1.0) }
                else { add(.laserSweep, lane: primary, z: centerZ, y: 0, length: 1.1, cyclePhase: Double(nextRandom() % 18) / 10) }
                add(secondary, lane: obstacleLanes[1], z: centerZ, y: 0, length: secondaryLength)
            default:
                if pattern == 0 || (at < 90 && !expert) {
                    add(.barrier, lane: primary, z: centerZ, y: 0, length: 0.8)
                } else if pattern == 1 || pattern == 5 {
                    add(.arch, lane: primary, z: centerZ, y: 0, length: 1.1)
                } else {
                    let oncoming = distance > 500 && (pattern == 6 || pattern == 8)
                        && oncomingLaneIsFair(primary, aheadOf: centerZ)
                    add(.tram, lane: primary, z: centerZ, y: 0, length: 12,
                        oncomingSpeed: oncoming ? 8 + Double(nextRandom() % 5) : 0)
                    if !oncoming && (pattern == 2 || pattern == 4 || pattern == 7) {
                        add(.ramp, lane: primary, z: centerZ - 10, y: 0, length: 7)
                        for offset in [-3.5, -0.5, 2.5, 5.0] {
                            add(.coin, lane: primary, z: centerZ + offset, y: Self.tramRoofHeight + 0.9, length: 0.3)
                        }
                    }
                }
                if expert || at > 65 {
                    add(secondary, lane: obstacleLanes[1], z: centerZ, y: 0, length: secondaryLength)
                }
            }
            // Coins are an invitation, not a route marker (see placeCoins).
            let rowHazards = entities.filter { Self.isObstacle($0.kind) && abs($0.z - centerZ) < 1 }
            let solids = rowHazards.filter { e in
                Self.isSolid(e.kind) && e.oncomingSpeed == 0 &&
                    !entities.contains { $0.kind == .ramp && $0.lane == e.lane && abs($0.z - (e.z - 10)) < 1 }
            }
            // Standard opens with teaching rows: only safe or action lines. One draw per row either way.
            let teaching = !expert && at < 160
            let roll = nextRandom() % 100
            let isSlide: (TrackEntity) -> Bool = { $0.kind == .arch || $0.kind == .laserSweep }
            let line = Self.coinLine(roll: teaching ? roll % 60 : roll,
                                     actionable: rowHazards.contains { $0.kind == .barrier || isSlide($0) },
                                     solid: !solids.isEmpty)
            // After the speed cap, rows tighten toward the floor over the next 120 s.
            let capTime = expert ? (36.0 - 16) / 0.24 : (32.0 - 12) / 0.18
            let tighten = min(1, max(0, (elapsed - capTime) / 120))
            let opening = expert ? Self.endlessSpacing.expert : Self.endlessSpacing.standard
            let tightest = expert ? Self.endlessSpacingFloor.expert : Self.endlessSpacingFloor.standard
            let baseSpacing = opening - (opening - tightest) * tighten
            placeCoins(line, z: centerZ, safe: routeLane, speed: arrivalSpeed, jumpApex: 1.45,
                       jumpLanes: rowHazards.filter { $0.kind == .barrier }.map(\.lane),
                       slideLanes: rowHazards.filter(isSlide).map(\.lane), solids: solids, teaching: teaching,
                       // The next row starts at least baseSpacing on; its tram reaches 6 m back, plus the 1.3 m coin margin.
                       coinLimit: centerZ + baseSpacing - 7.3)
            // Pickups sit off the safe lane, behind this row's hazards: collecting one is a choice.
            let pickupLane = obstacleLanes[Int(nextRandom() % 2)]
            if at > 100 && nextRandom() % 7 == 0 {
                // Sprint checkpoints are a ground slalom: flight would hide their route and
                // could turn a beneficial pickup into a forced missed time extension.
                let availablePowers = PowerUp.allCases.filter { mode != .harborSprint || $0 != .jetpack }
                let power = availablePowers[Int(nextRandom() % UInt64(availablePowers.count))]
                add(EntityKind(rawValue: power.rawValue)!, lane: pickupLane, z: centerZ + 10, y: 1, length: 0.8)
            }
            if at > 250 && nextRandom() % 18 == 0 {
                add(.key, lane: pickupLane, z: centerZ + 13, y: 1, length: 0.5)
            }
            if mode == .harborSprint && at >= challenge.nextCheckpointDistance {
                add(.checkpoint, lane: routeLane, z: centerZ, y: 1, length: 0.5)
                challenge.nextCheckpointDistance += 200
            }
            // A full-width row leaves a whole jump (0.773 s) plus a grounded reaction before the next row;
            // a compound counts that from its slide row.
            var spacing = baseSpacing + Double(nextRandom() % 5)
            if escalation <= 1 { spacing = max(spacing, arrivalSpeed * 0.9) }
            if escalation == 2 { spacing = max(spacing, arrivalSpeed * (0.75 + 0.9)) }
            nextPatternDistance += spacing
        }
```

  Before half the gate, the RNG draws happen in the same order as in G2, so the opening of every Endless and Sprint run is unchanged.

- [ ] **Step 4: Update the procedural-row test (reason: Endless now has full-width rows by design).** In `Tests/SimulationTests.swift`, in the case `"procedural rows retain an open lane and increase difficulty"`, replace everything from `simulation.update(dt: 0.2)` through the closing brace of the `for obstacle in obstacles { for point in … }` loop with:

```swift
                        simulation.update(dt: 0.2)
                        let obstacles = simulation.entities.filter { [.barrier, .arch, .tram, .laserSweep, .wall, .stack].contains($0.kind) }
                        let oncoming = obstacles.filter { $0.oncomingSpeed > 0 }
                        if !oncoming.isEmpty {
                            sawAnyOncoming = true
                            try expect(simulation.distance > 500, "Moving trams must wait until the advanced section")
                        }
                        if simulation.entities.contains(where: { $0.kind == .ramp }) { sawStationaryRoof = true }
                        // G3 Endless has full-width jump/slide rows, so a lane-only escape is no longer guaranteed.
                        // At every collider edge and centre (moving trams cross rows), some lane must hold no solid
                        // and never ask for a jump and a slide at the same point.
                        for obstacle in obstacles {
                            for point in [obstacle.z - obstacle.length / 2 - 0.35,
                                          obstacle.z, obstacle.z + obstacle.length / 2 + 0.35] {
                                let here = obstacles.filter { abs($0.z - point) <= $0.length / 2 + 0.35 + 0.000_001 }
                                let passable = (-1...1).contains { lane in
                                    let kinds = here.filter { $0.arrivalLane == lane }.map(\.kind)
                                    return !kinds.contains { [.tram, .wall, .stack].contains($0) }
                                        && !(kinds.contains(.barrier) && kinds.contains { $0 == .arch || $0 == .laserSweep })
                                }
                                try expect(passable, "Generated an impassable row: every lane is solid or needs a jump and a slide at once")
                            }
                        }
```

  This keeps the `sawAnyOncoming`, `sawStationaryRoof`, speed and entity-bound assertions.

- [ ] **Step 5: Run it to verify it passes.**
  - Run SkillAudit, logging to `work/g3/skill-t2.log`. Expected:
    - `ENDLESS-ESCALATION standard=[0, 1, 2, 3, 4, 5, 6] expert=[0, 1, 2, 3, 4, 5, 6] early=0`
    - `READER endless` at 30/30 on both difficulties
    - `TELEGRAPHS lateChanges=0`
    - FAIRNESS 0
    - PLACED-LINES endless safe ≤ 35%
    - `BAIT-ESCAPES violations=0`
  - If the Endless reader fails:
    - First refine `RouteAudit.drive` with visible reads only, at most 3 iterations, recording seeds.
    - If it still fails at the spacing floor, raise `endlessSpacingFloor` by 1 m per iteration, at most 2 iterations, and record each value.
    - If it still fails, report BLOCKED with the READER-FAIL lines.
  - If the Endless safe share exceeds 35%: compounds give safe lines, because their slide row sits inside the action-lane look-ahead. Report it with the PLACED-LINES numbers rather than changing coin rules here; Task 8 owns balance.

- [ ] **Step 6: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t2.log`. All must pass.

- [ ] **Step 7: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/SimulationTests.swift Tests/Audits/SkillAudit.swift
git commit -m "feat: Endless escalates with full-width rows, compounds and the new hazards; spacing tightens after the speed cap

The procedural-row test now asserts a passable lane rather than a lane-only escape: full-width jump and slide rows are new by design."
```

---

### Task 3: Forgiveness

> **Controller ruling (spec corrected).** In this code, padding and tolerance are hitbox extents, so larger values are stricter. The spec now says Expert 0.50 / 0.65, matching its intent that Expert is tougher.

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`act(.board)`, `collectAndCollide`, the dodge loop in `stepWorld`)
- Modify: `Tests/SimulationTests.swift`

**Interfaces:**
- Produces:
  - `var collisionPadding: Double` and `var lateralTolerance: Double` (internal, read-only)
  - board window 20 s (Expert 12 s)
  - board clear radius only in Endless and Harbor Sprint

- [ ] **Step 1: Write the failing tests.** In `Tests/SimulationTests.swift`, replace the whole case `"board naturally expires after thirty active seconds"` (reason: the spec shortens boards) with these three cases:

```swift
            ("board naturally expires after twenty active seconds, twelve on Expert", {
                var simulation = fixture(boards: 1)
                simulation.act(.board)
                simulation.update(dt: 19)
                try expect(simulation.boardTime > 0.9, "Board expired early")
                simulation.update(dt: 1.1)
                try expect(simulation.boardTime == 0, "Board should expire after twenty seconds")
                var expert = RunnerSimulation()
                expert.start(seed: 42, boards: 1, expert: true)
                expert.replaceTrackForTesting([])
                expert.act(.board)
                try expect(expert.boardTime == 12, "Expert boards protect for twelve seconds")
            }),
            ("board clear radius applies only in Endless and Sprint", {
                let track = [entity(.barrier, id: 1, z: 5, y: 0, length: 0.8), entity(.barrier, id: 2, lane: 1, z: 12, y: 0, length: 0.8)]
                var endless = fixture(track, boards: 1)
                endless.act(.board)
                endless.update(dt: 0.6)
                try expect(endless.phase == .running && !endless.entities.contains { $0.id == 2 }, "An Endless board burst clears nearby hazards")
                var odyssey = RunnerSimulation()
                odyssey.start(seed: 42, boards: 1, mode: .odyssey)
                odyssey.replaceTrackForTesting(track)
                odyssey.act(.board)
                odyssey.update(dt: 0.4)
                try expect(odyssey.phase == .running && odyssey.entities.contains { $0.id == 2 }, "An Odyssey board absorbs the hit without clearing the track")
            }),
            ("expert collisions use the spec's padding and lateral tolerance", {
                var standard = RunnerSimulation(); standard.start(seed: 1)
                var expert = RunnerSimulation(); expert.start(seed: 1, expert: true)
                try expect(standard.collisionPadding == 0.35 && standard.lateralTolerance == 0.55, "Standard hitboxes are unchanged")
                try expect(expert.collisionPadding == 0.50 && expert.lateralTolerance == 0.65, "Expert hitboxes are larger (stricter)")
            }),
```

  Run the G2 Task 2 simulation-test command (with `work/g3/` paths). Expected: a compile error, `value of type 'RunnerSimulation' has no member 'collisionPadding'`.

- [ ] **Step 2: Implement.** Directly below `var courseTarget: Double { … }`, add:

```swift
    /// Collider padding along the track and the lateral overlap that counts as a hit. Coins keep 0.55.
    var collisionPadding: Double { expert ? 0.50 : 0.35 }
    var lateralTolerance: Double { expert ? 0.65 : 0.55 }
```

  In `act(_:)`, `case .board:`, replace `boardTime = 30` with:

```swift
            boardTime = expert ? 12 : 20
```

  In `collectAndCollide`, replace `abs(entity.z) < entity.length / 2 + 0.35,` with `abs(entity.z) < entity.length / 2 + collisionPadding,`. Then replace `guard aligned else { continue }`, the one directly before `let collides: Bool`, with:

```swift
            guard abs(lateral - (Double(entity.lane) + entity.laneOffset())) < lateralTolerance else { continue }
```

  In the board branch, replace:

```swift
                    // A shield burst clears nearby obstacles so a long tram cannot hit twice.
                    for nearby in entities where Self.isObstacle(nearby.kind) && abs(nearby.z) < 18 {
                        collected.insert(nearby.id)
                    }
```

  with:

```swift
                    // In Endless and Sprint a board burst clears nearby obstacles. Odyssey keeps its track; the
                    // 2 s of protection still covers a long tram, which cannot hit twice (processedObstacles).
                    if mode == .endless || mode == .harborSprint {
                        for nearby in entities where Self.isObstacle(nearby.kind) && abs(nearby.z) < 18 {
                            collected.insert(nearby.id)
                        }
                    }
```

  In `stepWorld`'s dodge loop, replace `if closest >= 0.55 {` with:

```swift
                    if closest >= lateralTolerance {
```

  A pass outside the hitbox but within 0.98 lanes is a close call. A pass nearer than that was clean, and it can only happen through a jump or a roll.

  The Aegis shield, revive (3.0 s) and portal arrival (3 s) are unchanged.

- [ ] **Step 3: Run it to verify it passes.**
  - Run the simulation tests: all pass.
  - Run SkillAudit, logging to `work/g3/skill-t3.log`. Every READER line must be 30/30 (the reader uses no boards) and all binding lines green.

- [ ] **Step 4: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t3.log`. All must pass. Update any other test that asserted a 30 s board, giving the reason in the commit message.

- [ ] **Step 5: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests
git commit -m "feat: Expert hitbox padding and tolerance, 20/12 s boards, board clear radius only in Endless and Sprint

Board test now expects 20 s (12 s Expert): the spec shortens the protection window."
```

---

### Task 4: Ghost retirement

**Files:**
- Modify: `Sources/ReplayGhost.swift`
- Modify: `Tests/ProfileTests.swift`

**Interfaces:**
- Produces: `GhostCourseKey.currentRevision == 9`, `legacyModeRevision == 6`, and `revision(for: .jetSki) == 4`.

- [ ] **Step 1: Write the failing test.** In `Tests/ProfileTests.swift`, directly after the line `expect(GhostCourseKey(mode: .endless, expert: false, seed: 42, startWorld: 0).revision == GhostCourseKey.legacyModeRevision, "Endless ghosts use the current generator revision")`, add:

```swift
        expect(GhostCourseKey.revision(for: .odyssey) == 9 && GhostCourseKey.revision(for: .endless) == 6
               && GhostCourseKey.revision(for: .harborSprint) == 6 && GhostCourseKey.revision(for: .jetSki) == 4,
               "G3 generation retires Odyssey, Endless and Sprint ghosts; Jet Ski generation is unchanged")
        var g1Odyssey = GhostCourseKey(mode: .odyssey, expert: false, seed: 42, startWorld: 0); g1Odyssey.revision = 8
        var g1Endless = GhostCourseKey(mode: .endless, expert: false, seed: 42, startWorld: 0); g1Endless.revision = 5
        expect(!g1Odyssey.isValid && !g1Endless.isValid && GhostCourseKey(mode: .jetSki, expert: false, seed: 42, startWorld: 0).isValid,
               "G1-era Odyssey and Endless ghosts are discarded; Jet Ski ghosts stay valid")
```

  Run `Scripts/test.sh`. Expected: the profile tests report this expectation failing.

- [ ] **Step 2: Implement.** In `Sources/ReplayGhost.swift`, replace:

```swift
    static let currentRevision = 8
    /// Endless and Sprint ghosts: bumped to 5 when G1 changed their coin and pickup generation.
    static let legacyModeRevision = 5
    /// Jet Ski generation did not change in G1, so its ghosts keep revision 4.
```

  with:

```swift
    /// 8: G1 coin lines. 9: G2 hazards and the G3 shuffle bag, fork and finale order.
    static let currentRevision = 9
    /// Endless and Sprint ghosts: 5 for G1 coins and pickups, 6 for G3 escalation and forgiveness.
    static let legacyModeRevision = 6
    /// Jet Ski generation has not changed since revision 4, so its ghosts stay valid.
```

- [ ] **Step 3: Run it to verify it passes.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t4.log`. Both must pass. `GhostCheckpointAudit` records with the current revision.

- [ ] **Step 4: Commit.**

```bash
git add Sources/ReplayGhost.swift Tests/ProfileTests.swift
git commit -m "feat: retire G1-era Odyssey (rev 9) and Endless/Sprint (rev 6) ghosts; Jet Ski stays at 4"
```

---

### Task 5: Re-baseline LegacyContinuityAudit and add it to audit.sh

**Files:**
- Modify: `Tests/Audits/LegacyContinuityAudit.swift`
- Modify: `Scripts/audit.sh`

**Interfaces:**
- Produces:
  - `legacy-probe create <dir> <out.json>` (unchanged behaviour) and `legacy-probe verify <dir> <baseline.json>`
  - an `audit.sh` step that builds `create` from `e3049e5` (pre-overhaul) and `verify` from HEAD

- [ ] **Step 1: Write the failing audit step.** In `Scripts/audit.sh`, directly before the final `printf`, add:

```bash
# Legacy checkpoints: v4 stages (frozen legacy generator) must match the pre-overhaul build exactly;
# v5/v6 stages adopt the current generator (spec: resumed runs build new rows with new rules) and must reach their portal.
mkdir -p "$audit_work/legacy-base"
git archive e3049e5 Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift | tar -x -C "$audit_work/legacy-base"
swiftc "${flags[@]}" "$audit_work"/legacy-base/Sources/*.swift Tests/Audits/LegacyContinuityAudit.swift -o "$audit_work/legacy-base-probe"
swiftc "${flags[@]}" "${core[@]}" Tests/Audits/LegacyContinuityAudit.swift -o "$audit_work/legacy-probe"
"$audit_work/legacy-base-probe" create "$audit_work/legacy" "$audit_work/legacy-baseline.json"
"$audit_work/legacy-probe" verify "$audit_work/legacy" "$audit_work/legacy-baseline.json"
```

  Run `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t5-before.log`. Expected: the last step verifies nothing. The old probe treats any mode other than `create` as a plain run, so it overwrites the baseline JSON with its own output and prints `Captured …` a second time. Confirm this from the log: there is no `PASS legacy continuity` line.

- [ ] **Step 2: Implement `verify`.** Replace `Tests/Audits/LegacyContinuityAudit.swift` with:

```swift
import Foundation

/// Legacy checkpoint continuity probe.
///   create <dir> <out.json>        writes v4/v5/v6 checkpoints for every world and difficulty, drives each to its portal
///                                   with a fixed input script under protection, and saves the snapshots.
///   verify <dir> <baseline.json>   drives the same checkpoints with this build. Revision-4 stages use the frozen legacy
///                                   generator and must match the baseline exactly. v5/v6 stages adopt the current
///                                   generator (spec: a resumed run builds new rows with new rules), so they must only
///                                   decode and reach their portal.
/// Scripts/audit.sh compiles `create` against the pre-overhaul sources (e3049e5) and `verify` against HEAD.
/// This is a generator and physics continuity probe, not a survival test: protection keeps the fixed input script alive.
@main struct LegacyContinuityAudit {
    static func main() throws {
        guard CommandLine.arguments.count == 4, ["create", "verify"].contains(CommandLine.arguments[1]) else {
            fatalError("Usage: legacy-probe create|verify checkpoint-directory json")
        }
        let create = CommandLine.arguments[1] == "create"
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        var samples: [String: [RunnerSimulation]] = [:]
        for revision in [4, 5, 6] {
            for expert in [false, true] {
                for stage in 0..<6 {
                    let key = "r\(revision)-e\(expert)-s\(stage)"
                    let path = directory.appendingPathComponent(key + ".json")
                    if create {
                        var run = RunnerSimulation()
                        run.start(seed: UInt64(93 + stage), boards: 0, mode: .odyssey, expert: expert, startStage: stage)
                        var object = try JSONSerialization.jsonObject(with: encoder.encode(run)) as! [String: Any]
                        var journey = object["journey"] as! [String: Any]
                        journey["routeRevision"] = revision
                        object["journey"] = journey
                        object["invulnerableTime"] = 10_000.0
                        object["entities"] = []
                        object["nextPatternDistance"] = revision == 4 ? 65.0 : run.stageOpeningLength
                        var enhancement = object["enhancements"] as! [String: Any]
                        enhancement["generatedRows"] = 0
                        object["enhancements"] = enhancement
                        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: path)
                    }
                    var run = try decoder.decode(RunnerSimulation.self, from: Data(contentsOf: path))
                    samples[key] = [run]
                    var tick = 0
                    while run.phase == .running && !run.isPortalTransitioning && tick < 12_000 {
                        if tick % 77 == 0 { run.act(.jump) }
                        if tick % 137 == 0 { run.act(.roll) }
                        if tick % 179 == 0 { run.act(.right) }
                        if tick % 211 == 0 { run.act(.left) }
                        run.update(dt: 1.0 / 60)
                        tick += 1
                        if tick % 300 == 0 { samples[key]!.append(run) }
                        if tick == 400 {
                            run.act(.jump); run.update(dt: 0.08)
                            run = try decoder.decode(RunnerSimulation.self, from: encoder.encode(run))
                            samples[key]!.append(run)
                        }
                    }
                    guard run.isPortalTransitioning else { fatalError("Did not reach portal: \(key) \(run.phase)") }
                    samples[key]!.append(run)
                }
            }
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        if create {
            try encoder.encode(samples).write(to: output)
            print("Captured \(samples.count) legacy stages and \(samples.values.reduce(0) { $0 + $1.count }) state snapshots")
            return
        }
        let baseline = try decoder.decode([String: [RunnerSimulation]].self, from: Data(contentsOf: output))
        var compared = 0
        for (key, snapshots) in samples.sorted(by: { $0.key < $1.key }) where key.hasPrefix("r4-") {
            guard let old = baseline[key], old.count == snapshots.count else { fatalError("Legacy r4 snapshot count changed: \(key)") }
            for (index, (a, b)) in zip(old, snapshots).enumerated() {
                guard a.entities == b.entities, a.distance == b.distance, a.score == b.score, a.coins == b.coins,
                      a.stageIndex == b.stageIndex, a.phase == b.phase, a.lateral == b.lateral, a.height == b.height else {
                    fatalError("Legacy r4 stage diverged from the pre-overhaul build: \(key) snapshot \(index)")
                }
                compared += 1
            }
        }
        let regenerated = samples.keys.filter { !$0.hasPrefix("r4-") }.count
        print("PASS legacy continuity: \(compared) r4 snapshots match the pre-overhaul build; \(regenerated) v5/v6 stages decode and reach their portal under the current generator")
    }
}
```

- [ ] **Step 3: Run it to verify it passes.** Run `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t5.log`. Expected: `Captured 36 legacy stages …`, then `PASS legacy continuity: N r4 snapshots match …; 24 v5/v6 stages …`, with every other audit still passing.
  - If an r4 snapshot diverges, the overhaul changed a shared code path that v4 saves depend on. Report BLOCKED with the key and snapshot index, and do not weaken the comparison. Compare `collectAndCollide` and `stepWorld` between `e3049e5` and HEAD to name the line.

- [ ] **Step 4: Commit.**

```bash
git add Tests/Audits/LegacyContinuityAudit.swift Scripts/audit.sh
git commit -m "test: legacy continuity verifies v4 saves against the pre-overhaul build in audit.sh; v5/v6 adopt the new generator"
```

---

### Task 6: G1 deferred minors worth fixing

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`coinLine` doc; `placeCoins` returns its line; `placedLineLog`; both call sites)
- Modify: `Tests/Audits/SkillAudit.swift`

**Interfaces:**
- Produces:
  - `struct LinePlacement`, and `RunnerSimulation.placedLineLog: [LinePlacement]` (not persisted)
  - `@discardableResult placeCoins(…) -> CoinLine`
  - `SkillAudit.checkTeaching(_:)`, and output lines `TEACHING …` and `READER sprint …`

Folded in from `work/g1-deferred-minors.txt`:
- the `coinLine` doc says 30% where the bound is 35%
- Sprint has no reader-survival precondition
- the teaching rows have no per-position check
- the collection-time check can miss an item collected in the frame it enters `|z| < 1.2`

The other minors were judged harmless or already fixed:
- jetpack hoist, duplicate lookups, the lenient first-sight window and the oncoming-pickup window are harmless;
- Jet Ski ghosts are already at 4.

- [ ] **Step 1: Write the failing checks.** In `SkillAudit`, add inside the struct:

```swift
    static var teachingViolations = 0, invitationsAfterTeaching = 0
    /// Standard teaching rows (Odyssey rows 0–3 of each world; Endless/Sprint rows before 160 m) lay only safe or action
    /// lines, and the rows right after them sometimes lay risk or bait lines, so teaching really ends.
    static func checkTeaching(_ run: RunnerSimulation) {
        guard !run.expert else { return }
        let limit = run.mode == .odyssey ? 4 : 160
        for p in run.placedLineLog {
            if p.position < limit && p.line != .safe && p.line != .action { teachingViolations += 1 }
            if p.position >= limit && p.position < limit * 2 && (p.line == .risk || p.line == .bait) { invitationsAfterTeaching += 1 }
        }
    }
```

  In `main()`:
  - Call `checkTeaching(run)` directly after `checkPatterns(run.patternLog)` in the Odyssey reader loop.
  - Call it again directly after `checkEscalation(run)` in the Endless reader loop.
  - Replace the Sprint loop:

```swift
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .harborSprint, expert: expert)
                var watch = Watch()
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60); check(run, &watch) }
            }
```

    with:

```swift
            // Harbor Sprint shares the Endless generator. A hazard crash would silently shrink fairness coverage.
            var sprintCrashes = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .harborSprint, expert: expert)
                var watch = Watch()
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60); check(run, &watch) }
                if run.phase == .crashed && !run.crashReason.hasPrefix("Time ran out") {
                    sprintCrashes += 1
                    print("READER-FAIL sprint seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) reason=\(run.crashReason)")
                }
            }
            print("READER sprint expert=\(expert): hazardCrashes=\(sprintCrashes)/\(seeds)")
            precondition(sprintCrashes == 0, "Hazard reader must not crash into a hazard in Harbor Sprint")
```

  - Before the `FAIRNESS` print, add:

```swift
        print("TEACHING violations=\(teachingViolations) invitationsJustAfter=\(invitationsAfterTeaching)")
        precondition(teachingViolations == 0 && invitationsAfterTeaching > 0, "Standard teaching rows hold only safe or action lines, and end on time")
```

  In `checkCoins`, replace `if abs(item.z) < 1.2 && !flagged.contains(item.id)` with:

```swift
            // One frame of travel wider, so an item that enters reach and is collected in the same frame is still checked.
            if abs(item.z) < 1.2 + run.speed / 60 && !flagged.contains(item.id)
```

  Run the T1 Step 2 SkillAudit command. Expected: a compile error, `value of type 'RunnerSimulation' has no member 'placedLineLog'`.

- [ ] **Step 2: Implement.** In `Sources/RunnerSimulation.swift`, after `struct PatternRecord { … }`, add:

```swift
/// One coin line laid on a row, for the teaching-row audit. Odyssey: (world, row); Endless/Sprint: (0, metres). Not persisted.
struct LinePlacement: Equatable {
    let world: Int
    let position: Int
    let line: RunnerSimulation.CoinLine
}
```

  Below `private(set) var escalationFirstSeen`, add:

```swift
    /// Coin lines laid per row, for audits. Not persisted.
    private(set) var placedLineLog: [LinePlacement] = []
```

  Replace the `coinLine` doc comment `/// Coins are an invitation, not a route marker: at most 30% of rows mark the safe lane.` with:

```swift
    /// Coins are an invitation, not a route marker: only the first band of rolls asks for the safe line.
    /// Fallbacks can raise the placed share, which SkillAudit binds at 35% per mode.
```

  Change the `placeCoins` declaration line `private mutating func placeCoins(` to `@discardableResult private mutating func placeCoins(`, and its closing `) {` to `) -> CoinLine {`. After `placedCoinLines[placed, default: 0] += 1`, at the end of `placeCoins`, add `return placed`.

  At the Odyssey call site, replace `placeCoins(line, z: z, safe: routeLane, speed: predictedSpeed,` with `let placed = placeCoins(line, z: z, safe: routeLane, speed: predictedSpeed,`, and directly after that call's closing parenthesis add:

```swift
                placedLineLog.append(LinePlacement(world: stageIndex, position: row, line: placed))
```

  At the Endless call site (T2), replace `placeCoins(line, z: centerZ, safe: routeLane, speed: arrivalSpeed, jumpApex: 1.45,` with `let placed = placeCoins(line, z: centerZ, safe: routeLane, speed: arrivalSpeed, jumpApex: 1.45,`, and directly after that call's closing parenthesis add:

```swift
            placedLineLog.append(LinePlacement(world: 0, position: Int(at), line: placed))
```

- [ ] **Step 3: Run it to verify it passes.** Run SkillAudit, logging to `work/g3/skill-t6.log`. Expected:
  - `TEACHING violations=0 invitationsJustAfter=` a positive number
  - `READER sprint expert=false: hazardCrashes=0/30` and the same for Expert
  - FAIRNESS 0 (now checked one frame wider)
  - `SkillAudit passed`

  If FAIRNESS rises above 0 because of the wider window, the UNFAIR lines are real collection-time faults. Report them with the lines; do not narrow the window.

- [ ] **Step 4: Run the full suites.** Run `Scripts/test.sh` and `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-t6.log`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/Audits/SkillAudit.swift
git commit -m "test: Sprint reader precondition, per-position teaching-row check, one-frame collection window; fix coinLine doc"
```

---

### Task 7: Docs and in-game help

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`RunMode.instructions`)
- Modify: `Sources/GameUI.swift` (help rows)
- Modify: `README.md`
- Create: `V8.md` (repository root, next to `V7.md`)

**Interfaces:**
- Produces: player-facing text that describes the G1–G3 rules.

- [ ] **Step 1: Mode instructions.** In `RunMode.instructions`, replace the `.odyssey` and `.endless` strings with:

```swift
        case .odyssey: return "Master six worlds: jump gaps, slide beams and read moving hazards. Watch for vehicles that shift lanes, timed lasers, gap walls, stacked barriers, meteor rings and cracking decks. Coins tempt; they do not mark the safe lane. Risky relic routes charge your artifact ability (E). Jump at a portal for a precision bonus, or let Portal Assist carry you through. Gold requires a clean stage, two relics, two skill actions and a precision entry."
        case .endless: return "Swipe to dodge, jump and slide. Double-tap or B activates your hoverboard. Rows grow to full width, chain a jump into a slide and add shifting trams, walls and timed lasers as the run goes on. Close calls and clean escapes build your combo. Airborne drones can hit your jetpack."
```

- [ ] **Step 2: Help text.** In `GameUI.swift`'s help view:
  - Replace `CRHelpRow(title: "Expert", detail: "Faster starts, tighter patterns and a separate personal best for each mode.")` with:

```swift
                CRHelpRow(title: "Expert", detail: "Faster starts, tighter patterns, stricter collisions, 12-second boards and a separate personal best for each mode.")
                CRHelpRow(title: "Reading hazards", detail: "A chevron on a vehicle points to the lane it is moving into. Solid lasers are on and dashed lasers are off; rolling is always safe. Crossed bars mark walls and stacked barriers that nothing clears. Rings mark where a meteor will land, and zigzag cracks mark a deck that is about to open. Coins are a temptation, not a route.")
```

  - Under `section("THE RULES")`, replace `detail: "Ride it before a tricky stretch. One crash, one board.")` with:

```swift
                          detail: "It lasts 20 seconds (12 on Expert). One crash, one board.")
```

- [ ] **Step 3: README.**
  - Change the title line to `# Coastline Rush — Portal Odyssey · v8`.
  - In the Portal Odyssey section, replace `Read \`V7.md\` for the seven-part expansion,` with `Read \`V8.md\` for the gameplay overhaul (coins, new hazards, variety), \`V7.md\` for the seven-part expansion,`.
  - In the second paragraph of that section, after the sentence ending `moving cargo at the stellar forge.`, add: `Every world also mixes in hazards that change as you approach: vehicles that shift lanes, timed laser gates, gap walls, stacked barriers, real meteor impacts and collapsing decks, each telegraphed at least a second ahead.`
  - In the modes table, replace the Endless row's last cell `Denser lane decisions, jump/slide risks, roof routes, near misses, aerial rings and collidable drones` with `Denser lane decisions, jump/slide risks, roof routes, near misses, aerial rings and collidable drones. From 30 s (15 s Expert) full-width jump and slide rows; from 60 s (30 s Expert) jump-then-slide compounds, shifting trams, gap walls, stacked barriers and timed lasers; after the speed cap, rows keep tightening for two minutes`.
  - In "Included gameplay", replace `- Consumable boards lasting up to 30 seconds and absorbing one crash; short protection after a board breaks.` with:

```markdown
- Consumable boards lasting up to 20 seconds (12 on Expert) and absorbing one crash, with short protection after a board breaks. In Endless and Harbor Sprint the break also clears hazards within 18 m.
- Coins are an invitation, not a route marker: lines arc over jumps, run low under slides, sit beside hazards or bait a late lane change. Low coins need a roll.
```

  - Replace `- Seeded courses with validated action sequences: Odyssey includes full-width jumps and slides, moving rover roof transfers, meteor warnings, cracked ice, and sentinel sweeps. Endless retains lane escape routes.` with:

```markdown
- Seeded courses with validated action sequences: Odyssey draws at least ten encounter patterns per world from a shuffle bag (no pattern within three rows of itself), shuffles fork and finale order per seed, and includes full-width jumps and slides, rover roof transfers, lane-changing vehicles, timed lasers, gap walls, stacked barriers, real meteor impacts and collapsing decks. Every row keeps a reachable exit.
```

  Expert uses larger collision margins (0.50 / 0.65); describe them as "stricter collisions".

- [ ] **Step 4: Create `V8.md`.**

```markdown
# Coastline Rush v8 — Harder, Fairer, More Varied

Following coins is no longer a strategy, and reading the track always is. Every course is still validated by a hazard-reading bot that clears all of it, and coin placement is audited so no coin or pickup forces a collision.

## Coins invite, they do not guide (G1)

Each row lays one coin line:

| Line | What it asks |
|---|---|
| Safe | Marks the open lane (a minority of rows; never more than 35% of those laid) |
| Action | An arc over a jump, or a low line you must roll under |
| Risk | Ground coins before and after a jump or slide; they do not signal the action |
| Bait | Starts in a lane that is blocked later; one adjacent lane change saves you, and the line resumes behind the obstacle |

Low coins (y ≤ 0.6) are collected only while rolling. Power-ups and keys sit off the safe lane. Standard runs open with a few teaching rows that use only safe and action lines.

## Hazards that move (G2)

Each hazard is telegraphed at least 1.0 s ahead (0.8 s on Expert) by a shape, not only a colour, and its collider always matches what you see.

| Hazard | Worlds | Read it by |
|---|---|---|
| Lane-changer | Harbor, Mars, Cryo | A chevron on the vehicle points to the lane it is taking; the lane it leaves becomes the exit |
| Timed laser gate | Orbit, Verdant, Forge | Solid beam on, dashed beam off (0.9 s each); rolling is always safe |
| Gap wall | All | Crossed bars on two full-height walls; the opening moves one lane from your last route |
| Stacked hazard | All | A barrier under a beam, joined by struts: neither a jump nor a roll passes |
| Real meteor | Mars | A target ring; the rock lands at least a second before you reach it |
| Collapsing deck | Orbit, Cryo | A zigzag crack on an intact deck; it opens at least half a second before you arrive |

## Variety and rising pressure (G3)

- Portal Odyssey has 14 encounter patterns, at least 10 per world, drawn from a seeded shuffle bag. No pattern repeats within three rows. Fork and finale orders are shuffled per seed; the Daily Odyssey follows its date.
- Endless adds full-width jump and slide rows from 30 s (15 s on Expert). From 60 s (30 s on Expert) it adds jump-then-slide compounds, lane-changing trams, gap walls, stacked barriers and timed lasers. After the speed cap, rows keep tightening for two minutes.
- Boards protect for 20 s (12 s on Expert). Their 18 m clearing burst applies in Endless and Harbor Sprint only. Expert collision padding and lateral tolerance grow to 0.50 and 0.65, so near-misses count as hits sooner. Revive and portal protection are unchanged.

## Compatibility

- Saved runs resume: they keep their entities and build new rows with the new rules. Saves from v4 finish their stage exactly as before.
- Personal ghosts from earlier Odyssey (revision 8 and older) and Endless/Sprint (revision 5 and older) courses no longer match and are discarded. Jet Ski ghosts stay. Records, medals, coins and unlocks are kept.
```

- [ ] **Step 5: Builds and tests.** Run `Scripts/test.sh` and both `xcodebuild` commands (G2 Task 5 Step 7 form, logging to `work/g3/build-mac.log` and `work/g3/build-ios.log`). All must pass and print `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit.**

```bash
git add Sources/RunnerSimulation.swift Sources/GameUI.swift README.md V8.md
git commit -m "docs: v8 gameplay overhaul notes, README and in-game help for the new hazards and rules"
```

---

### Task 8: Balance pass and report

**Files:**
- Modify: `Tests/Audits/SkillAudit.swift` (header and target prints)
- Modify (only if the bounded pass tunes): `Sources/RunnerSimulation.swift` (`endlessSpacing`, `endlessSpacingFloor`, the `journeyEncounterInterval` base and floor literals)
- Modify: `V8.md` (verification section)

**Interfaces:**
- Produces: `COIN-FOLLOWER` lines that report `MET` or `MISSED` against the spec targets, and the final G3 report `work/g3/report.txt`.

- [ ] **Step 1: Print against the targets.**
  - In `SkillAudit`, replace the header doc comment's sentence `Coin-follower and reader survival numbers are informational until G3.` with `Coin-follower numbers are reported against the spec targets (MET/MISSED) for review with the user; they are not preconditions.`
  - Replace the Odyssey follower print with:

```swift
                let target = expert ? 85.0 : 70.0
                print(String(format: "COIN-FOLLOWER odyssey route=%@ expert=%@: failedBeforeWorld2=%d/%d (%.0f%%, target >=%.0f%% %@) meanWorlds=%.2f",
                             route.rawValue, String(expert), failedEarly, seeds, share * 100, target, share * 100 >= target ? "MET" : "MISSED",
                             worlds.reduce(0, +) / Double(seeds)))
```

  - Replace the Endless follower print with:

```swift
            let medianTarget = expert ? 60.0 : 90.0
            print(String(format: "COIN-FOLLOWER endless expert=%@: median=%.1fs (target <%.0fs %@) mean=%.1fs",
                         String(expert), median(survival), medianTarget, median(survival) < medianTarget ? "MET" : "MISSED",
                         survival.reduce(0, +) / Double(seeds)))
```

- [ ] **Step 2: Measure.** Run `bash Scripts/audit.sh 2>&1 | tee work/g3/audit-balance-0.log`, then `grep -E "COIN-FOLLOWER|READER|PLACED-LINES|PATTERNS|ENDLESS-ESCALATION|TELEGRAPHS|BAIT-ESCAPES|TEACHING|FAIRNESS|HAZARD-COVERAGE|PASS legacy" work/g3/audit-balance-0.log`.

- [ ] **Step 3: One bounded tuning pass, only if a target is MISSED.**
  - If every COIN-FOLLOWER line says `MET`, skip this step. G1 already met all four targets: 100%, 100%, 28.5 s and 11.3 s.
  - Otherwise, change only interval and floor constants, for at most 3 iterations, each followed by a full `bash Scripts/audit.sh`:
    - Endless median too high: lower `endlessSpacingFloor` by 1 m per iteration, with Standard ≥ 20 and Expert ≥ 18.
    - Odyssey follower share too low: lower the `journeyEncounterInterval` base literals (2.65 / 2.10 / 1.65 / 1.38) by 0.05 per iteration. Never lower the per-world floor literals, which are physical jump and steering budgets.
  - Revert an iteration at once if any READER line drops below 30/30, if FAIRNESS, TELEGRAPHS or BAIT-ESCAPES becomes non-zero, or if either safe share exceeds 35%.
  - Record every iteration's constants and the lines it produced.
  - Stop after 3 iterations, even with a target still missed. The controller reviews the numbers with the user.

- [ ] **Step 4: Builds and render.** Run both `xcodebuild` commands and `bash Scripts/render.sh g3-final 2>&1 | tee work/g3/render-final.log`. Every `ms=` value must be within the Global Constraints limits; one re-run is allowed.

- [ ] **Step 5: Write the report.** Create `work/g3/report.txt` containing:
  - the Step 2 grep output, or the last kept iteration's output;
  - the G1 baselines from the Reference facts and the G2 numbers from `work/g2/report.txt`, side by side;
  - every tuning iteration, if there were any;
  - the render `ms` values.

  Append to `V8.md`:

```markdown
## Verification

Measured with `bash Scripts/audit.sh` (30 seeds per configuration) at the end of G3:
```

  Below that heading, paste every `COIN-FOLLOWER`, `READER`, `PLACED-LINES`, `PATTERNS` and `FAIRNESS` line from the final log as a fenced text block, followed by one sentence naming the render result, for example `All seven render shots stayed within the +25% frame-time budget.`

- [ ] **Step 6: Commit.**

```bash
git add Tests/Audits/SkillAudit.swift V8.md Sources/RunnerSimulation.swift
git commit -m "test: report coin-follower numbers against the spec targets; G3 balance verification"
```

  Leave `Sources/RunnerSimulation.swift` out of the `git add` if Step 3 was skipped.

## Deliberate deviations and decisions

- **Expert hitboxes:** 0.50 / 0.65 per the corrected spec (larger extents are stricter in this code).
- **Verdant pattern 5:** Verdant keeps pattern 5 (charging cargo with a slide) instead of remapping it to 7. Without it Verdant has 9 effective patterns, and the spec requires 10.
- **Full-width row gate:** full-width Endless rows open at half the compound gate (30 s, or 15 s on Expert). The spec sets only the compound gate (60/30). This ramps difficulty instead of adding everything at once.
- **Bag repeat window:** the bag's 3-row window covers forced, fork and finale rows too, so bag rows also avoid them. The audit exempts fork and finale rows themselves, because the safe fork's authored set is {0, 3}.
- **Legacy baseline:** `LegacyContinuityAudit` compares only v4 stages exactly, against `e3049e5`. v5/v6 stages are expected to change, because the spec says resumed runs build new rows with new rules. They must decode and reach their portal.
