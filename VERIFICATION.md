# Coastline Rush v7 — verification

Verified October 4, 2026. This report distinguishes deterministic gameplay checks, native rendering, simulator inspection and physical-device testing. Evidence logs are in Verification-V7; the previous report is preserved as VERIFICATION-V6.md.

## Seven-item delivery

| Item | Implemented | Verification |
|---|---|---|
| Six authored finales | Unique action sequences and cached setpieces | 1,440 generated finale clears, native screenshots of all six |
| Real branch routes | Split/elevated geometry, aligned colliders, double-coin risk route, Harbor water branch, Mars roof transfers | 240 campaign runs, 1,583 renderer/collider alignment checks |
| Artifact perk tradeoffs | Three upgrades, charge/capacity costs, checkpoint/replay identity | Rule/controller/profile checks; native iPhone UI selection persisted Relic Capacitor |
| Character and world presentation | Richer armored courier, integrated stride, steering lean, weighted takeoff/landing, six setpieces | 12 scene fixtures, 11 baseline comparisons, four poses inspected |
| High-speed readability and replay | Compact HUD, action cues/sounds, contrast, OS/game reduced motion, bounded crash review | Native simulator playback; immutable replay and settings tests |
| Skills and modes | Five once-only skill contracts, practice, Endless Odyssey, optional water segment | Practice economy isolation, actual skill-objective completion, multi-cycle speed audits |
| Performance/device work | Local diagnostics, bounded scene caches, thermal quality fallback, sustained native probe | Mac probe and three native build targets passed; physical iPhone testing remains pending |

## Logic and persistence

The final Scripts/test.sh run passed:

- 25 simulation tests and 25 original challenge tests.
- 26 controller/checkpoint tests, including replay immutability/bounds, practice economy isolation and diagnostics labeling.
- 257 profile assertions across 19 groups.
- 28 journey tests and 138 expansion checks.

Practice cannot bank currency or change inventory, records, missions, medals or unlocks. Skill contracts are idempotent across repeated checkpoint saves and claims. Endless has separate records and cannot award a finite campaign win. Replay holds only approximately three seconds/48 frames and never mutates the live simulation or wallet.

A partial-ghost regression was found and fixed: choices in worlds beyond the recorded ghost now return to normal. The generated ghost audit preserved six route decisions and three perks through 758 ControllerSave/RunSession round trips, with 3,068 samples. Artifact changes after a normal run starts disable that run's ghost recording; artifacts cannot change during the recorded portion of a ghost race.

## Generated route fairness and speed

240 full campaign runs passed: 30 seeds × two difficulties × safe/risky routes × ordinary/mastery policies. The solver uses visible hazard rows, lane movement, jump/slide and water steering; it uses no boards, artifact protection, revives or collision bypasses.

- All 1,440 finales cleared with no hits.
- 20,280 checkpoint comparisons continued with identical future state.
- 1,200 portal crossings retained the underlying running-speed curve.
- Mastery runs collected all 2,160 available relics and earned 720 gold medals.
- Safe Harbor routes cleared 1,140 water gates.
- Maximum 69 live simulation entities in this campaign matrix.

All 12 generated practice world/difficulty routes passed. Four Endless runs completed 13 worlds each, including two wraparounds, on safe/risky routes and both difficulties. Underlying speed never dropped at a portal and stayed within the 65/71m/s ceilings. Temporary braking/boosts are intentionally distinct from this underlying curve.

Actual generated objective runs demonstrated three clean Harbor trick landings on each difficulty, and 15/14 actual Mars rover roof rides, with all four local objectives. Standing on a ramp without reaching the moving roof does not count. The standalone Wave Rider audit also passed 60 boosted runs with 2,579 gates and zero misses.

The route audit found a branch-boundary generation loop. Fixed boundary-speed calculations and a forward margin removed the fixed-point loop; the full campaign matrix passed afterward. Legacy continuity was checked against the archived v6 source: 611 snapshots matched across v4/v5/v6 saves, all worlds and both difficulties, excluding only the new default expansion field and normalizing unordered sets.

These automated routes demonstrate feasibility, persistence and the tested invariants. They do not replace human difficulty tuning.

## Native rendering and visual inspection

The final renderer passed 120 arrival/fork/finale snapshots over 30 world changes. Destination cache stayed at or below two worlds, recycled entity pool at or below 96, sampled live renderer entities at or below 30, and attached nodes at or below 1,240. All 120 player and 1,463 entity visual/collider transform comparisons passed. All four quality modes applied successfully.

Native fixtures were inspected for all six finales, branch entry/plateau/merge, courier poses, reduced motion and high contrast. Inspection caught a false-looking rail crossing during fork merges; alternate rails now hide until the decks have enough separation. The final renderer audit was rerun after this fix. The original full-audit invocation overlapped that edit at its final compile step; its successful frozen-source retry is logged separately as cache-final.log.

The art is stylized procedural geometry with original textures and skies. No claim of AAA production character assets or photorealism is made.

A 606.9-second native macOS SceneKit probe exercised all six worlds and their finales at 480×800 points, balanced quality and 2× MSAA, during some concurrent build work. It recorded 63,564 callback intervals. The last 720-callback window measured 120 callbacks/s, p95 8.5ms, p99 8.6ms, zero intervals above 33ms, and p95 main simulation/scene update time 0.2ms; thermal state was nominal. The requested frame limit was 60, but SceneKit callbacks arrived at the display's higher cadence. These are callback/CPU numbers, not presented FPS or GPU frame times. The probe uses an automated driver and restarts completed practice segments; it is not a clean human run. The last renderer rail-visibility correction was subsequently validated by the final cache/alignment audit.

## Native builds and UI

All final Xcode builds succeeded:

- macOS Release, arm64 + x86_64 universal.
- iOS Simulator Debug.
- iPhone hardware Release, unsigned compile.

The locally signed Mac app was launched and its About dialog showed 7.0.0 (7). The existing profile's 690 coins, zero keys and prior best were retained. No fixtures were written to the Mac profile.

The dedicated iPhone 17 Pro / iOS 26.5 QA simulator verified the Campaign/Endless menu, Atlas practice, free practice retry, settings toggles, measured diagnostics, in-game crash replay, compact HUD, fork-choice UI and portal perk selection/persistence. Generated UI fixtures were used for portal/fork inspection; the fork UI fixture cleared immediate obstacles only to inspect controls, and is not counted as route-fairness evidence. Original QA simulator preferences were backed up and restored after testing.

## Still requires hardware

No physical iPhone was connected (`devicectl list devices`: no devices found). Therefore real touch-to-photon latency, haptic feel, sustained mobile GPU/presentation timing, device thermal behavior and battery use are not verified. The hardware-target compile and simulator tests do not establish those results. On-device installation requires the owner's Apple development team/provisioning.

Context7 documentation lookup was attempted but its configured API key was invalid. Native SDK compilation supplied API validation. Apple documentation links were also attempted, but the web reader did not return their content. Claude's screenshot-only consultation informed HUD/readability changes; automatic approval review rejected source-file sharing, so source code was not sent to that consultation.
