# Gameplay Overhaul G1 — Measurement and Coin Rules — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make coins an invitation rather than a route marker, and measure it. A coin-following bot measurably fails while a hazard-reading bot still clears every course.

**Architecture:**
- The existing `RouteAudit` reading bot stops reading coins and reads only hazards.
- A new `SkillAudit` drives a coin-follower bot and the reader through Odyssey and Endless, and checks that every generated coin is fair.
- The simulation gains a posture-aware low-coin rule and one shared coin-line placer used by both `extendTrack` (Endless/Sprint) and `extendJourneyCourse` (Odyssey). Pickups move off the safe lane.
- The ghost course revision is bumped so old recordings retire.

**Tech Stack:** Swift 5.9, headless `swiftc` audits. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-gameplay-overhaul-design.md` (G1 section, Compatibility)

## Global Constraints

- iOS 16+ / macOS 13+; one shared `Sources/` tree builds both targets.
- Each row keeps at least one reachable exit. The hazard-reading bot must clear 100% of Odyssey routes (`bash Scripts/audit.sh`, which includes `RouteAudit` safe/risky and relics) and survive 300 s of Endless on every seed, with no boards.
- No coin overlaps a collider in a way that forces a collision (`SkillAudit` fairness check: 0 unfair coins).
- `Scripts/test.sh` passes. A test that encodes the old "coins mark the safe lane" behaviour is updated in the same commit, with the reason in the commit message.
- Checkpoints still decode: no new persisted fields in G1.
- Daily Odyssey stays deterministic per date seed. Two runs with the same seed must produce identical tracks.
- Mac and iOS builds succeed. `Scripts/render.sh` stats stay inside the graphics budget: within +25% of harbor 286, orbit 117, mars 131, verdant 254, cryo 141, forge 149, jetski 279 ms.
- Environment: `swiftc`, `xcodebuild` and `Scripts/*.sh` must run outside the Claude sandbox, with outputs in `work/`. `precondition` messages do not print in `-O` builds. zsh does not word-split `$VAR`, so use bash for file-list variables.

## Reference facts (from the code, 2026-10-06)

- **Coin collection** (`collectAndCollide`, `RunnerSimulation.swift` ~:771–781):
  - A coin is collected when `abs(lateral - lane) < 0.55`, `abs(z) < 0.85` and `abs(y - (height + 0.9)) < 1.15`.
  - With a magnet, it is collected when `z < 16 && z > -2 && abs(y - height) < 8`.
- **Collision bands:**
  - barrier/root: `height < 1.03`
  - gap/iceCrack: `height < 0.4`
  - meteor: `< 2.5`
  - arch/laserSweep: `!isRolling || height > 0.15`
  - tram: `< tramRoofHeight - 0.35` (2.45)
  - buoy: `< 1.4`
  - waterTraffic: `< 1.8`
  - The longitudinal window is `abs(z) < length/2 + 0.35`.
- **Movement timing:** lane change is 9 lanes/s (Cryo 3.8). A roll lasts 0.8 s.
- **Endless (`extendTrack` ~:918–983):**
  - Rows are 26–30 m apart (Expert 23–27).
  - The primary obstacle is a barrier, arch or tram (with an optional ramp at `centerZ - 10`, length 7). A secondary arch or barrier appears after 65 m.
  - Coins sit on `safeLane` (~:964). Power-ups and keys are also on `safeLane` (~:972, ~:975).
- **Odyssey (`extendJourneyCourse` ~:1139–1314):**
  - There are patterns 0–7. Coins are placed per pattern in cases 0, 1, 2, 3 (first beat), 5, 6 and default; pattern 3's follow beat and pattern 4's roof coins are separate.
  - `addJourneyArc(lane:z:apex:speed:)` lays 5 coins over ±min(11, speed·0.24).
  - In patterns 2 and 7, `safe` is the jump lane.
- `RouteAudit.drive` (`Tests/Audits/RouteAudit.swift` :45–52) uses the nearest coin as a lane oracle on full-width rows.
- `GhostCourseKey` (`Sources/ReplayGhost.swift` :5) has `static let currentRevision = PortalJourney.currentRevision`. A ghost whose revision differs is rejected by its `isValid` guard (:26).
- The PRNG is `nextRandom()`. `add(_:lane:z:y:length:oncomingSpeed:)` appends an entity.

## File map

| File | Change |
|---|---|
| `Tests/Audits/RouteAudit.swift` | T1: read hazards, not coins, on full-width rows. |
| `Tests/Audits/SkillAudit.swift` | Create in T2: coin-follower and reader runs, Endless reader coverage. T3 adds the fairness check. T4 adds the coin-line distribution check. |
| `Scripts/audit.sh` | T2: build and run SkillAudit. |
| `Sources/RunnerSimulation.swift` | T3: low-coin reach rule. T4: `CoinLine`, `coinLine(roll:actionable:solid:)`, `laneIsClear`, `placeCoins`, the Endless and Odyssey call sites, pickups. |
| `Sources/ReplayGhost.swift` | T4: ghost revision 8. |

---

### Task 1: Reading bot reads hazards, not coins

**Files:**
- Modify: `Tests/Audits/RouteAudit.swift` (`drive`, lines ~36–52)

**Interfaces:**
- Produces: `RouteAudit.drive(_:allowVerticalActions:route:)` keeps the same signature but never reads `.coin` entities.

- [ ] **Step 1: Replace the coin oracle.** In `drive`, replace the `else { … choices … }` block and the following `if Set(row.map(\.lane)).count == 3, let marker = …coin… { target = marker.lane }` block with:

```swift
        else {
            // Full-width mixed rows expose a jump lane, a slide lane and a solid
            // lane. Read those shapes, and prefer a lane whose next hazard is not solid.
            let choices = row.filter { $0.kind != .tram && $0.kind != .meteor }
            func cost(_ e: TrackEntity) -> Int {
                let airborneSlide = run.height > 0.3 && [.arch, .laserSweep].contains(e.kind) ? 3 : 0
                let solidAfter = active.contains { $0.lane == e.lane && $0.z > e.z + 2 && $0.z < e.z + run.speed * 1.1 && [.tram, .meteor].contains($0.kind) } ? 4 : 0
                return abs(e.lane - run.lane) + airborneSlide + solidAfter
            }
            if let choice = choices.min(by: { cost($0) < cost($1) }) { target = choice.lane }
        }
        if Set(row.map(\.lane)).count == 3, row.allSatisfy({ [.gap, .barrier, .root, .iceCrack].contains($0.kind) }) {
            // A full-width leap: read the landing, not the coins. Commit before the
            // leap to the lane the next hazard row leaves open.
            let landing = active.filter { $0.z > first.z + 2 && $0.z < first.z + run.speed * 1.1 }
            if let next = landing.first {
                let landingRow = landing.filter { abs($0.z - next.z) < 2 }
                let open = (-1...1).filter { lane in !landingRow.contains { $0.lane == lane } }
                if let lane = open.min(by: { abs($0 - run.lane) < abs($1 - run.lane) }) { target = lane }
            }
        }
```

- [ ] **Step 2: Confirm no coin reads remain.** Run `grep -n "\.coin" Tests/Audits/RouteAudit.swift`. Expected: no matches.

- [ ] **Step 3: Run the route audits.** Run `bash Scripts/audit.sh` (sandbox disabled). Expected: every RESULT line reports `failures=0`, and the script exits 0.
  - If a route fails, refine only `drive`, using hazard reads (positions, kinds, lanes; never coins). Allow at most 3 iterations, and record every change and the seed that motivated it.
  - If it still fails after 3 iterations, report BLOCKED with the FAIL lines.

- [ ] **Step 4: Commit.**

```bash
git add Tests/Audits/RouteAudit.swift
git commit -m "test: route audit bot reads hazards instead of coins"
```

---

### Task 2: SkillAudit — coin-follower baseline and Endless reader

**Files:**
- Create: `Tests/Audits/SkillAudit.swift`
- Modify: `Scripts/audit.sh`

**Interfaces:**
- Consumes: T1 `RouteAudit.drive`, `RouteAudit.driveWater`.
- Produces:
  - `SkillAudit.followCoins(_ run: inout RunnerSimulation, route: BranchRoute)`
  - output lines `COIN-FOLLOWER odyssey …`, `COIN-FOLLOWER endless …` and `READER endless …`
  - a `precondition` that the reader survives every Endless seed

- [ ] **Step 1: Create the audit.** `Tests/Audits/SkillAudit.swift`:

```swift
import Foundation

/// Measures whether skill matters: a bot that only chases coins should fail, while the
/// hazard-reading RouteAudit bot clears everything. Compile with -D ROUTE_HELPER and RouteAudit.swift.
@main
struct SkillAudit {
    static let seeds = Int(ProcessInfo.processInfo.environment["QA_SEEDS"] ?? "30") ?? 30

    /// Steer to the nearest coin ahead; jump for high coins, roll for low ones. Ignores hazards entirely.
    static func followCoins(_ run: inout RunnerSimulation, route: BranchRoute) {
        guard !run.isPortalTransitioning else { return }
        defer { if run.routeChoiceAvailable { run.chooseRoute(route) } }
        if run.isWaterTraversal { RouteAudit.driveWater(&run); return }
        if let d = run.portalDistance, d < 5.5, run.height < 0.05 { run.act(.jump); return }
        guard let coin = run.entities.filter({ $0.kind == .coin && $0.z > 0.5 }).min(by: { $0.z < $1.z }) else { return }
        if coin.lane < run.lane { run.act(.left) } else if coin.lane > run.lane { run.act(.right) }
        guard coin.lane == run.lane, coin.z < run.speed * 0.35 else { return }
        if coin.y >= 1.4, run.height < 0.05 { run.act(.jump) }
        if coin.y <= 0.6, !run.isRolling { run.act(.roll) }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func main() {
        for expert in [false, true] {
            // Odyssey: share of coin-follower runs that crash before completing world 2.
            for route in [BranchRoute.safe, .risky] {
                var failedEarly = 0, worlds: [Double] = []
                for seed in 1...seeds {
                    var run = RunnerSimulation()
                    run.start(seed: UInt64(seed), boards: 0, mode: .odyssey, expert: expert)
                    var tick = 0
                    while run.phase == .running && tick < 90_000 { followCoins(&run, route: route); run.update(dt: 1.0 / 60); tick += 1 }
                    if run.phase == .crashed && run.stageIndex < 2 { failedEarly += 1 }
                    worlds.append(Double(run.stageIndex) + run.stageProgress)
                }
                let share = Double(failedEarly) / Double(seeds)
                print(String(format: "COIN-FOLLOWER odyssey route=%@ expert=%@: failedBeforeWorld2=%d/%d (%.0f%%, target >=%d%%) meanWorlds=%.2f",
                             route.rawValue, String(expert), failedEarly, seeds, share * 100, expert ? 85 : 70, worlds.reduce(0, +) / Double(seeds)))
            }
            // Endless: coin-follower survival time, capped at 300 s.
            var survival: [Double] = []
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                while run.phase == .running && run.elapsed < 300 { followCoins(&run, route: .safe); run.update(dt: 1.0 / 60) }
                survival.append(run.elapsed)
            }
            print(String(format: "COIN-FOLLOWER endless expert=%@: median=%.1fs (target <%ds) mean=%.1fs",
                         String(expert), median(survival), expert ? 60 : 90, survival.reduce(0, +) / Double(seeds)))
            // Endless: the hazard reader must survive the full 300 s on every seed.
            var survived = 0
            for seed in 1...seeds {
                var run = RunnerSimulation()
                run.start(seed: UInt64(seed), boards: 0, mode: .endless, expert: expert)
                while run.phase == .running && run.elapsed < 300 { RouteAudit.drive(&run); run.update(dt: 1.0 / 60) }
                if run.phase == .running { survived += 1 }
                else { print("READER-FAIL endless seed=\(seed) expert=\(expert) t=\(String(format: "%.1f", run.elapsed)) lane=\(run.lane) reason=\(run.crashReason)") }
            }
            print("READER endless expert=\(expert): survived=\(survived)/\(seeds) (300s)")
            precondition(survived == seeds, "Hazard reader must survive every Endless seed")
        }
        print("SkillAudit passed")
    }
}
```

- [ ] **Step 2: Add it to `Scripts/audit.sh`.** Before the final `printf`, add:

```bash
swiftc "${flags[@]}" -D ROUTE_HELPER "${core[@]}" Tests/Audits/RouteAudit.swift Tests/Audits/SkillAudit.swift -o "$audit_work/skill"
"$audit_work/skill"
```

- [ ] **Step 3: Run it and record the baseline.** Run `bash Scripts/audit.sh` (sandbox disabled). Expected: all route audits pass, then the SkillAudit lines followed by `SkillAudit passed`. Copy every COIN-FOLLOWER and READER line into your report and into the commit body: they are the G1 baseline.
  - If the reader fails an Endless seed, the generator has an unfair Endless row, or the reader mishandles one. Report DONE_WITH_CONCERNS with the READER-FAIL lines, and do not change the simulation.

- [ ] **Step 4: Commit.**

```bash
git add Tests/Audits/SkillAudit.swift Scripts/audit.sh
git commit -m "test: skill audit with coin-follower baseline and Endless reader"
```

---

### Task 3: Posture-aware low coins and the coin fairness check

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (`collectAndCollide`, the `reachable` line)
- Modify: `Tests/Audits/SkillAudit.swift` (fairness check)
- Modify: `Tests/SimulationTests.swift` (one new case)

**Interfaces:**
- Produces:
  - a coin with `y <= 0.6` is collected only while `isRolling && height < 0.2`
  - `SkillAudit.coinIsFair(_ coin: TrackEntity, among entities: [TrackEntity]) -> Bool`
  - a precondition that every generated coin is fair

- [ ] **Step 1: Write the failing simulation test.** In `Tests/SimulationTests.swift`, follow the existing test-case pattern: tuples of `(name, closure)` using `entity(...)` and `expect(...)`. Add a case named "low coins need a roll" that does three things:
  - Places a coin at `lane: 0, z: 0.4, y: 0.35` with the runner standing in lane 0, then runs `update(dt: 1.0 / 60)` and expects `coins == 0`.
  - On a fresh simulation with the same coin, calls `act(.roll)` first and expects `coins == 1` after the update.
  - Checks that a coin at `y: 0.9` is still collected standing.

  Mirror how the neighbouring "magnet collects coins…" case builds its simulation and track.

- [ ] **Step 2: Run it to verify it fails.** Build and run the simulation tests exactly as `Scripts/test.sh` does: the first `swiftc` line, then the executable. Expected: the new case fails on the standing-collection expectation.

- [ ] **Step 3: Implement the rule.** In `collectAndCollide`, replace `let reachable = abs(entity.y - (height + 0.9)) < 1.15` with:

```swift
                // Low coins mark a roll: standing runners pass over them.
                let reachable = entity.y <= 0.6 ? isRolling && height < 0.2 : abs(entity.y - (height + 0.9)) < 1.15
```

- [ ] **Step 4: Add the fairness check to SkillAudit.** Inside `struct SkillAudit`, add:

```swift
    /// A coin is fair if some non-colliding posture at its position can collect it.
    static func coinIsFair(_ coin: TrackEntity, among entities: [TrackEntity]) -> Bool {
        for o in entities where o.lane == coin.lane && RouteAudit.hazards.contains(o.kind) && o.oncomingSpeed == coin.oncomingSpeed {
            guard abs(coin.z - o.z) < o.length / 2 + 0.35 + 0.3 else { continue }
            switch o.kind {
            case .arch, .laserSweep:
                // Only a roll at height 0 passes; it reaches coins below 2.05 m.
                if coin.y >= 2.05 { return false }
            default:
                let minimumSafeHeight: Double
                switch o.kind {
                case .barrier, .root: minimumSafeHeight = 1.03
                case .gap, .iceCrack: minimumSafeHeight = 0.4
                case .meteor: minimumSafeHeight = 2.5
                case .tram: minimumSafeHeight = RunnerSimulation.tramRoofHeight - 0.35
                case .buoy: minimumSafeHeight = 1.4
                default: minimumSafeHeight = 1.8 // waterTraffic
                }
                // Reachable at a safe height h if |y - (h + 0.9)| < 1.15 for some h >= minimum, and not low.
                if coin.y <= 0.6 || coin.y <= minimumSafeHeight - 0.25 { return false }
            }
        }
        return true
    }
```

  Then make each of the three run loops in `main` (Odyssey follower, Endless follower, Endless reader) check new coins once, at generation time:
  - Before each loop, declare `var seen = Set<Int>()`.
  - After each `run.update(dt:)`, add:
    `for coin in run.entities where coin.kind == .coin && !seen.contains(coin.id) { seen.insert(coin.id); if !coinIsFair(coin, among: run.entities) { unfair += 1; if unfair <= 5 { print("UNFAIR coin id=\(coin.id) lane=\(coin.lane) z=\(coin.z) y=\(coin.y) mode=\(run.mode) world=\(run.worldStage)") } } }`
  - Declare `var unfair = 0` at the top of `main`.
  - Before `print("SkillAudit passed")`, add `print("FAIRNESS unfairCoins=\(unfair)"); precondition(unfair == 0, "Every coin must be collectible without a forced collision")`.

- [ ] **Step 5: Run the tests.** Run the simulation tests (they must now pass), then `Scripts/test.sh` and `bash Scripts/audit.sh` (all sandbox disabled).
  - Expected: every suite passes, `FAIRNESS unfairCoins=0`, and the reader keeps 30/30. Record the new COIN-FOLLOWER lines.
  - The existing Odyssey slide coins sit at y = 0.7, which is above 0.6, so they stay collectible standing until Task 4.
  - If `unfair > 0`, report the UNFAIR lines. They show existing generator coins that violate the rule. Report them as DONE_WITH_CONCERNS; do not change generation in this task.

- [ ] **Step 6: Commit.**

```bash
git add Sources/RunnerSimulation.swift Tests/Audits/SkillAudit.swift Tests/SimulationTests.swift
git commit -m "feat: low coins need a roll; audit every coin for fairness"
```

---

### Task 4: Coin lines, pickups off the safe lane, ghost revision

**Files:**
- Modify: `Sources/RunnerSimulation.swift` (new helpers; `extendTrack` coin, power-up and key lines; `extendJourneyCourse` per-pattern coins)
- Modify: `Sources/ReplayGhost.swift` (:5)
- Modify: `Tests/Audits/SkillAudit.swift` (distribution check)
- Modify any test that asserts coins or pickups on the safe lane; give the reason in the commit message.

**Interfaces:**
- Consumes: T3 low-coin rule; T3 `coinIsFair`; T2 SkillAudit.
- Produces:
  - `enum CoinLine: Equatable { case safe, action, risk, bait }` (nested in `RunnerSimulation`)
  - `static func coinLine(roll: UInt64, actionable: Bool, solid: Bool) -> CoinLine`
  - `private func laneIsClear(_ lane: Int, from: Double, to: Double) -> Bool`
  - `private mutating func placeCoins(_ line: CoinLine, z: Double, safe: Int, speed: Double, jumpApex: Double, jumpLanes: [Int], slideLanes: [Int], solids: [TrackEntity])`
  - `GhostCourseKey.currentRevision == 8`

- [ ] **Step 1: Write the failing distribution check.** In `SkillAudit.main`, before the loops, add:

```swift
        var tally: [RunnerSimulation.CoinLine: Int] = [:]
        for roll in UInt64(0)..<100 { tally[RunnerSimulation.coinLine(roll: roll, actionable: true, solid: true), default: 0] += 1 }
        precondition(tally[.safe, default: 0] <= 35, "At most 35% of rows may mark the safe lane")
        precondition(tally[.action, default: 0] > 0 && tally[.risk, default: 0] > 0 && tally[.bait, default: 0] > 0, "Every coin line type must occur")
        precondition(RunnerSimulation.coinLine(roll: 70, actionable: false, solid: false) == .safe, "Rows without hazards fall back to the safe line")
        print("COIN-LINES safe=\(tally[.safe, default: 0]) action=\(tally[.action, default: 0]) risk=\(tally[.risk, default: 0]) bait=\(tally[.bait, default: 0]) per 100 rows")
```

  Build SkillAudit as `audit.sh` does. Expected: a compile error, `type 'RunnerSimulation' has no member 'coinLine'`.

- [ ] **Step 2: Add the helpers to `RunnerSimulation`.** Put them next to `addJourneyArc`:

```swift
    enum CoinLine: Equatable { case safe, action, risk, bait }

    /// Coins are an invitation, not a route marker: at most 30% of rows mark the safe lane.
    static func coinLine(roll: UInt64, actionable: Bool, solid: Bool) -> CoinLine {
        switch roll % 100 {
        case 0..<30: return .safe
        case 30..<60: return actionable ? .action : .safe
        case 60..<85: return actionable ? .risk : (solid ? .bait : .safe)
        default: return solid ? .bait : (actionable ? .risk : .safe)
        }
    }

    private func laneIsClear(_ lane: Int, from: Double, to: Double) -> Bool {
        !entities.contains { e in
            Self.isObstacle(e.kind) && e.lane == lane && e.z + e.length / 2 > from && e.z - e.length / 2 < to
        }
    }

    /// Lays this row's coins. `safe` is the intended route lane, which may itself need a jump or roll.
    private mutating func placeCoins(_ line: CoinLine, z: Double, safe: Int, speed: Double, jumpApex: Double,
                                     jumpLanes: [Int], slideLanes: [Int], solids: [TrackEntity]) {
        let lowLine = [-3.0, -1.5, 0, 1.5, 3]
        func halfLength(_ lane: Int) -> Double {
            entities.filter { Self.isObstacle($0.kind) && $0.lane == lane && abs($0.z - z) < 1 }.map { $0.length / 2 }.max() ?? 0.5
        }
        // Action and risk lines only use lanes that stay clear after the hazard, so no line leads into a landing solid.
        let open = (jumpLanes + slideLanes).filter { laneIsClear($0, from: z + halfLength($0) + 0.5, to: z + max(speed * 1.2, halfLength($0) + 10)) }
        switch line {
        case .action where !open.isEmpty:
            let lane = open[Int(nextRandom() % UInt64(open.count))]
            if jumpLanes.contains(lane) { addJourneyArc(lane: lane, z: z, apex: jumpApex, speed: speed) }
            else { for offset in lowLine { add(.coin, lane: lane, z: z + offset, y: 0.35, length: 0.3) } }
        case .risk where !open.isEmpty:
            // Ground-height coins around a jump or slide hazard: they do not signal the action.
            let lane = open[Int(nextRandom() % UInt64(open.count))]
            let clearance = halfLength(lane) + 3
            for k in 0..<3 {
                add(.coin, lane: lane, z: z - clearance - Double(k) * 3, y: 0.9, length: 0.3)
                add(.coin, lane: lane, z: z + clearance + Double(k) * 3, y: 0.9, length: 0.3)
            }
        case .bait where solids.contains(where: { abs($0.lane - safe) == 1 }):
            // A greedy line in a solid's lane that ends with time left for one lane switch.
            let solid = solids.first { abs($0.lane - safe) == 1 }!
            let reaction = mode == .odyssey && worldStage == .cryo ? 0.55 : 0.35
            let last = solid.z - solid.length / 2 - speed * reaction
            for k in 0..<3 { add(.coin, lane: solid.lane, z: last - Double(k) * 3, y: 0.9, length: 0.3) }
            // The line resumes behind the solid: staying in lane for it is fatal, stepping out and back is not.
            for k in 0..<3 { add(.coin, lane: solid.lane, z: solid.z + solid.length / 2 + 2 + Double(k) * 3, y: 0.9, length: 0.3) }
        default:
            if jumpLanes.contains(safe) { addJourneyArc(lane: safe, z: z, apex: jumpApex, speed: speed) }
            else if slideLanes.contains(safe) { for offset in lowLine { add(.coin, lane: safe, z: z + offset, y: 0.35, length: 0.3) } }
            else { for offset in [-6.0, -3, 0, 3] { add(.coin, lane: safe, z: z + offset, y: 0.9, length: 0.3) } }
        }
    }
```

- [ ] **Step 3: Endless and Sprint call site.** In `extendTrack`, replace the coin loop (`for offset in stride(from: -8.0, through: 8.0, by: 4.0) { add(.coin, lane: safeLane, …) }`) and the power-up and key blocks that follow it with:

```swift
            // Coins are an invitation, not a route marker (see placeCoins).
            let rowHazards = entities.filter { Self.isObstacle($0.kind) && abs($0.z - centerZ) < 1 }
            let solids = rowHazards.filter { tram in
                tram.kind == .tram && tram.oncomingSpeed == 0 &&
                    !entities.contains { $0.kind == .ramp && $0.lane == tram.lane && abs($0.z - (tram.z - 10)) < 1 }
            }
            let line = Self.coinLine(roll: nextRandom() % 100,
                                     actionable: rowHazards.contains { $0.kind == .barrier || $0.kind == .arch },
                                     solid: !solids.isEmpty)
            placeCoins(line, z: centerZ, safe: safeLane, speed: speed, jumpApex: 1.45,
                       jumpLanes: rowHazards.filter { $0.kind == .barrier }.map(\.lane),
                       slideLanes: rowHazards.filter { $0.kind == .arch }.map(\.lane), solids: solids)
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
```

  Keep the Sprint checkpoint on `safeLane`. It is a route marker, not a pickup.

- [ ] **Step 4: Odyssey call site.** In `extendJourneyCourse`:
  - Immediately before `switch pattern {`, add `let rowStart = entities.count`.
  - Delete these primary-row coin placements:
    - case 0's `addJourneyArc(lane: safe, …)`
    - case 1's `for offset in [-6.0, -3, 0, 3, 6] { add(.coin, lane: safe, z: z + offset, y: 0.7, …) }`
    - case 2's `addJourneyArc`
    - case 3's first `for offset in [-6.0, -3, 0, 3] { add(.coin, lane: safe, …) }`
    - case 5's `for offset in [-6.0, -3, 0, 3, 6] { add(.coin, lane: safe, …) }`
    - case 6's `addJourneyArc`
    - the default case's `addJourneyArc`
  - Keep:
    - case 3's follow-beat exit coins
    - case 4's roof coins (`add(.coin, lane: safe, … y: relicY, … oncomingSpeed: velocity)` and the side-roof coin)
    - every `relicY` / `relicLane` / `relicZ` assignment
  - After the closing brace of the switch, and before `let milestones = …`, add:

```swift
            if pattern != 4 {
                let rowHazards = entities[rowStart...].filter { Self.isObstacle($0.kind) && abs($0.z - z) < 1 }
                let jumpLanes = rowHazards.filter { $0.kind == jumpKind }.map(\.lane)
                let slideLanes = rowHazards.filter { $0.kind == slideKind }.map(\.lane)
                let solids = rowHazards.filter { [.tram, .meteor].contains($0.kind) && $0.oncomingSpeed == 0 }
                let line = Self.coinLine(roll: nextRandom() % 100, actionable: !(jumpLanes + slideLanes).isEmpty, solid: !solids.isEmpty)
                placeCoins(line, z: z, safe: safe, speed: predictedSpeed, jumpApex: jumpHeight,
                           jumpLanes: jumpLanes, slideLanes: slideLanes, solids: Array(solids))
            }
```

- [ ] **Step 5: Retire old ghosts.** In `Sources/ReplayGhost.swift`, change `static let currentRevision = PortalJourney.currentRevision` to:

```swift
    /// Course generator revision for ghost recordings. It is bumped whenever generation changes,
    /// so old ghosts retire. It is independent of PortalJourney.currentRevision, which also archives world records.
    static let currentRevision = 8
```

  Then run `grep -rn "currentRevision" Tests Sources` and fix any test that assumes the ghost revision equals the journey revision.

- [ ] **Step 6: Run the checks.** Build and run SkillAudit, which must now compile and print COIN-LINES. Then run `Scripts/test.sh` and `bash Scripts/audit.sh`.
  - Expected:
    - every suite passes
    - every RouteAudit RESULT has `failures=0`
    - READER endless 30/30 for both difficulties
    - `FAIRNESS unfairCoins=0`
  - The COIN-FOLLOWER lines should show a large rise in failures against the T2/T3 baseline. They are reported, not asserted.
  - Update any test that fails because it expected coins or pickups on the safe lane. Keep the test's intent (for example, "a route exists"), change only the coin and pickup expectation, and explain each change in the commit message.

- [ ] **Step 7: Determinism.** Add one check to the end of `SkillAudit.main`: two runs with the same seed (Odyssey seed 4, the reader driving, 3,000 ticks) must have identical `entities`. Precondition message: "Same seed must generate the same track".

- [ ] **Step 8: Builds and render.**
  - Run the Mac and iOS builds (`xcodebuild … CODE_SIGNING_ALLOWED=NO`; iOS uses `-destination 'generic/platform=iOS'`). Both must succeed.
  - Run `Scripts/render.sh g1`. It must stay within the graphics budget; re-run once if a shot misses.

- [ ] **Step 9: Commit.**

```bash
git add Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Tests/Audits/SkillAudit.swift Tests
git commit -m "feat: coins invite actions, risks and bait instead of marking the safe lane"
```

---

## After G1

Report the COIN-FOLLOWER and READER lines from T2 (baseline), T3 and T4 side by side. The targets become binding at the end of G3. Then write the G2 plan (new hazards).
