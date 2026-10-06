# Coastline Rush gameplay overhaul — design

Date: 2026-10-06. Approved by the user in chat. Scope: Portal Odyssey and Endless (Coastal Rush); Harbor Sprint and Jet Ski inherit shared changes only. This spec lifts the graphics-overhaul constraint "no changes to `RunnerSimulation`".

## Goal

Make the game harder but fair, and more varied:
- A player who only follows coins should fail most Standard runs.
- A player who reads hazards should still be able to clear every course.
- Expert is noticeably tougher on top of Standard.

## Diagnosis (evidence: code analysis 2026-10-06, `RunnerSimulation.swift`)

1. **Coins mark safety.** Every generator places coin lines, arcs, power-ups and keys on the lane it already chose as safe: `extendTrack` around :964–975, and the `extendJourneyCourse` cases around :1238–1302. Following coins is a complete strategy. In Endless it never requires a jump or a slide.
2. **There are four collision classes:** jump, slide, solid, and water. Every other kind is a reskin. Meteors and lasers animate only in the renderer; their colliders are static. Nothing changes lane.
3. **Repetition.**
   - Odyssey has 8 patterns per world, 6–8 effective.
   - The fork and the finale use fixed orders, which covers about 47% of each stage.
   - Back-to-back repeats are possible.
4. **Endless stops escalating** when speed caps at 32 m/s, around 111 s in. It never builds full-width rows.
5. **Generous forgiveness.**
   - Collision padding is ±(length/2 + 0.35) and the lateral tolerance is 0.55 lanes.
   - A board absorbs a hit anywhere in a 30 s window and clears obstacles within 18 m.
   - There are many invulnerability windows.

## Design

### G1. Measurement and coin rules

- **Coin-follower bot** (`Tests/Audits/CoinFollowerAudit.swift`).
  - Behaviour (as implemented in `Tests/Audits/SkillAudit.swift`):
    - Lane choice comes from coins: it steers to the lane of the nearest coin ahead, and takes that lane's ramp to reach roof coins.
    - It never sideswipes a vehicle: it does not steer into a lane where a hazard overlaps the runner.
    - It has perfect jump and roll reflexes for whatever is directly in its own lane, with the reader's timing.
    - It never dodges what is ahead: lane changes come only from coins.
  - Coverage: Odyssey safe/risky × Standard/Expert over 30 seeds, plus Endless capped at 300 s.
  - Reports: death rate, mean distance, and the world reached.
- **Reading bot.** The existing `RouteAudit` hazard-reading bot must keep a 100% clear rate, and every existing audit stays green.
- **Binding status.** The coin-follower and reader survival numbers are informational until G3. From G1 these are binding:
  - The placed safe-line share (the lines actually laid, after fallbacks, in the reader's Odyssey and Endless runs) is at most 35% per mode.
  - 0 unfair coins and pickups, checked at first sight and again at collection time against live hazard positions.
- **Acceptance targets (Standard):**
  - The coin-follower fails at least 70% of Odyssey runs before completing world 2.
  - Its median Endless survival is under 90 s.
  - Expert targets: at least 85% of Odyssey runs failed, and median Endless survival under 60 s.
- **Coin placement.** Each row picks one of these line types instead of always using the safe lane:
  - `safeLine`: current behaviour, at most 35% of rows.
  - `actionLine`: an arc over a jump hazard (must jump), or a low line at y = 0.35 under a slide hazard (must roll).
  - `riskLine`: ground-height coins before and after a jump or slide hazard in its lane. The coins do not signal the action, so only a player who reads the hazard collects them safely. (Added during G1 planning: a bot that follows coins and acts on what they signal survives every feasible bait line, so risk lines are what separate coin-following from reading the track.)
  - `baitLine`: starts in a lane that is blocked later in the row, so collecting the full line needs a late lane switch inside the feasibility budget.
- **Reach rule.** The coin reach check becomes posture-aware: a coin at y ≤ 0.6 is collected only while rolling. Standing no longer collects low coins.
- **Coins never overlap a collider.** A new feasibility check asserts that every coin is reachable without colliding.
- **Pickups.** Power-ups and keys are placed on non-safe lanes that are reachable within the row budget.

### G2. New hazards (simulation + 3D visuals + action cues)

Each hazard has a real time- or motion-dependent collider. It telegraphs at least 1.0 s at Standard and 0.8 s at Expert before it becomes dangerous. Each also gets a procedural model and a shape-coded cue, and High Contrast cues apply to all of them.

| Hazard | Behaviour | Worlds | Collision class |
|---|---|---|---|
| Lane-changer | A tram, rover or ice block slides one lane over a 0.6 s window, starting at a telegraphed z | Harbor, Mars, Cryo | solid; collider lane interpolates |
| Timed laser gate | On/off cycle (on 0.9 s, off 0.9 s, phase per entity); dangerous only while on | Orbit, Verdant, Forge | slide while on, open while off |
| Gap wall | Spans two lanes, with one opening that differs from the previous row | All | solid on two lanes |
| Stacked hazard | Low barrier plus overhead bar in one lane; can't be jumped or rolled | All | solid |
| Real meteor | The collider exists only from impact time (a target ring warns first) until it clears | Mars | solid after impact |
| Collapsing deck | A deck gap opens after a crack warning | Orbit, Cryo | jump after collapse |

- **New entity data.** `TrackEntity` gains optional fields, all decoded with defaults so old checkpoints still load:
  - `targetLane: Int?`
  - `motionStart: Double`
  - `cyclePhase: Double`
  - `activeFrom: Double`
- **Collisions.** `collectAndCollide` evaluates colliders at the current simulation time and position.
- **Renderer.** `CoastalWorld.syncEntities` drives the visuals from the same fields, so what you see always matches the collision.
- **Feasibility.** The `RouteAudit` bot and the feasibility budgets learn the new hazards, and every generated row keeps at least one reachable exit.

### G3. Variety and rising difficulty

- **Pattern library.** Odyssey grows from 8 to at least 14 encounter patterns, mixing the new hazards. Each world gets at least 10 effective patterns.
- **Shuffle bag.** Each tier uses a shuffle bag, with no repeat within the last 3 rows.
- **Forks and finales.** Their order is shuffled per seed. Daily Odyssey stays deterministic, because it is seeded by date.
- **Endless.**
  - Full-width jump and slide rows, plus jump→slide compounds.
  - After the speed cap, spacing keeps tightening toward a floor over the next 120 s.
  - Compound patterns begin at 60 s on Standard and 30 s on Expert.
- **Forgiveness.**
  - Expert: collision padding 0.35 → 0.50 and lateral tolerance 0.55 → 0.65. (Corrected during G3 planning: in this code these are hitbox extents, so larger values are stricter; the original 0.20 / 0.45 would have made Expert easier, contradicting "Expert noticeably tougher".)
  - Board protection window: 30 s → 20 s on Standard, 12 s on Expert.
  - The board's 18 m clear radius applies only in Endless and Sprint, not Odyssey.
  - Revive and portal invulnerability are unchanged.

### Compatibility

- **Checkpoints.** Existing checkpoints decode. A resumed run keeps its saved entities and generates new rows with the new rules.
- **Ghosts.** The ghost course revision (`GhostCourseKey.currentRevision`, decoupled from `PortalJourney.currentRevision` so world records are not archived) is bumped whenever generation changes, in G1 and again in G3. Personal ghosts with an older revision are discarded on load. Records, medals, coins and unlocks are kept.
- **Daily Odyssey.** It still reproduces from its date seed under the new revision.
- **Accessibility.** Reduced Motion keeps the essential movement cues. Telegraphs never rely on colour alone.

## Phasing (one implementation plan per phase)

1. **G1:** coin-follower audit (baseline numbers first), coin line types, posture-aware reach, pickups off the safe lane, and the coin-collider check.
2. **G2:** new entity fields and collision timing, then the six hazards with their visuals and cues, plus audit and bot support.
3. **G3:** pattern library and shuffle bag, Endless escalation, forgiveness changes, the ghost revision bump, and the final balance pass against the targets.

After G3: the graphics overhaul resumes with Phase 3 (runner). That work must budget for the Mars and Verdant frame times, which are near the +25% limit.

## Verification, per phase

- `Scripts/test.sh` and `bash Scripts/audit.sh` pass. Tests that encode the old easy behaviour are updated in the same commit, with the reason given.
- The coin-follower audit is reported against the targets at the end of G1, G2 and G3. Targets are binding at the end of G3, when the full balance pass is done; G1 and G2 report progress toward them.
- The reading bot keeps its 100% clear rate.
- Mac and iOS builds succeed.
- `Scripts/render.sh` renders and stats stay inside the graphics budget.
