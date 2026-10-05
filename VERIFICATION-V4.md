# Verification — v4 World Mastery, 4 October 2026

## Final native builds

All shipped sources built with Xcode 26.5 / Swift 6.3.2, Swift 5 language mode. Deployment targets remain iOS 16+ and macOS 13+. Version 4.0.0, build 4.

| Target | Configuration | Result |
|---|---|---|
| macOS | Release, arm64 + x86_64 | Succeeded |
| iOS Simulator | Debug, generic simulator | Succeeded |
| iPhone / iPad | Release, generic device, signing disabled | Succeeded |

The Mars rock texture, original panoramas, six world ambiences and sound effects are bundled. There are no third-party runtime dependencies.

## Automated rules and persistence

`Scripts/test.sh` passes 90 named tests and 185 additional profile assertions:

- 25 simulation tests: collision, movement, powers, determinism and entity migration.
- 25 challenge tests: Sprint and Jet Ski clocks, gates, currents, continuous steering, boats, boosts, chained tricks and landing rewards.
- 23 controller/checkpoint tests: atomic settlement, old saves, world unlocks, artifact/loadout pause, ghost recording/playback/restore, optional replay corruption, daily rules, graphics preferences, sampled HUD updates and idle rendering.
- 17 journey tests: required world actions, moving rover transfers, continuous assisted and precision portals, pause/resource clocks, ability charges, mastery, legacy v3 snapshots and daily seeds.
- 185 profile assertions in 13 groups: purchases, rewards, upgrades, migrations, monotonic mastery, bounded/exact-course ghosts and separate daily records.

The final renderer guard changes were followed by another passing 23-test controller run and all three native builds. Other production rule/profile files remained unchanged from the full suite.

## Independent generated-course audits

The independent audit uses actual generated entities and simulation actions, without replacing the course or granting collision protection:

- 60/60 six-world expeditions: 30 seeds on both Standard and Expert, no boards, abilities or revives; zero stage impacts.
- 60/60 additional mastery expeditions: all 18 relics and Gold in every world; 1,080 relics and 360 gold medals, without boards, abilities or revives.
- Each Odyssey set performed 1,470 periodic Codable restores and checked an equivalent future branch.
- 60/60 full Jet Ski courses: 2,579 gates, zero misses, with moving-traffic timing and boost use.
- 626 full ControllerSave/RunSession/GhostRecorder round trips, six paused portal transitions, 1,755 replay samples and six persisted medals. Largest observed save was approximately 233KB.
- Thirty cyclic world selections/prewarms retained at most two destination records, 86 pooled entities (cap 96) and 19 live opening entities; 25 preparation callbacks. All quality settings applied successfully.

The source harnesses are included under `Tests/Audits`. Run `bash Scripts/audit.sh` on macOS to reproduce. These sampled checks establish feasibility; they do not prove every seed or assess human difficulty. Retained object counts are not draw-call or peak-memory measurements.

## Native visuals and interactions

All six world renders, Jet Ski, portal approach/flight and real simulation run/jump/land/roll poses were generated through native SceneKit/Metal and inspected. Terrain inspection caught and fixed canyon back-face gaps; the final Mars meshes have continuous layered ridges, normals, UVs and the original rock texture.

The dedicated Coastline Rush QA iPhone simulator was used for native menu, performance/settings, gameplay, pause, results, Atlas, artifact selection and personal-ghost checks. An active run restored paused after reinstall. Opening Loadout paused the run; selecting Phase Step updated the actual loadout; closing it returned to the same paused distance. Race Your Ghost started a matching course and displayed the live ghost comparison. The ordinary simulator and normal Mac profile were not replaced by QA fixtures. The final sandbox-signed Mac app was opened and its menu/settings inspected; the existing wallet remained intact.

Current previews are prefixed `Preview/V4-`. Other preview files document earlier versions. Visual inspection and native button/keyboard interaction are separate from the generated-course audits above.

## Performance evidence and limits

A 12-second visible Mac probe used the actual production controller, render relay and SCNView with generated Harbor obstacles. Host: Apple M5 Pro, 18 logical CPUs, 64GiB, macOS 26.6.2. Window: 1,280×800 points, approximately 2,560×1,600 pixels, Ultra, 4× MSAA. The first two seconds were excluded.

After removing redundant redraw requests and unchanged quality assignments, 1,191 measured renderer callback intervals had median 8.333ms, p95 8.561ms, p99 8.841ms and maximum 83.117ms. Callback frequency was approximately 119.10Hz despite a 60fps request. These are **renderer callbacks, not measured presentation FPS or GPU completion time**. The maximum interval shows a remaining hitch; the short probe does not establish sustained, hitch-free performance. Two probes used different seeds, so their comparison is not a controlled speedup claim. See `Tests/Audits/RESULTS.md` for details.

Physical iPhone/iPad swipe feel, haptics, sustained frame pacing, thermal behavior, battery use and speaker/headphone output remain unmeasured. Input buffering and water steering were verified in simulation; simulator buttons and keyboard were exercised. No physical-touch or mobile FPS claim is made.

## Saves, art and distribution

Legacy wallets, preferences and active-run snapshots migrate without a reset. World progress and mastery save during a run; economy settles exactly once at the end. Ghosts are bounded, keyed to the generator/course identity and optional to restore. Late-world practice does not count as a full expedition.

The art is original stylized procedural 3D with an articulated courier, generated skies/rock albedo and original synthesized audio. It is not a photorealistic AAA character library. Forge uses sentinel sweep/cargo encounters, not combat AI. Fable consultation did not yield a substantive final recommendation; Opus 5.5 was unavailable. See `V4.md` for provenance.

The Mac app is locally ad-hoc signed with sandbox entitlement, not Developer ID notarized. Its signature, version, universal architecture and bundled Mars texture were checked before packaging. The iOS device build is unsigned. Physical installation, TestFlight or App Store release still requires the owner's Apple development team and provisioning. No store publication, cloud sync, global leaderboard, ads, real-money purchases or live-service backend was introduced.
