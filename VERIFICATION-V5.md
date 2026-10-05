# Verification — v5 Extended Odyssey, 4 October 2026

## Shipped targets

All production sources built successfully with Xcode 26.5, Swift 5 language mode. Version 5.0.0, build 5; deployment targets iOS 16+ and macOS 13+.

| Target | Configuration | Result |
|---|---|---|
| macOS | Release, arm64 + x86_64 | Succeeded |
| iOS Simulator | Debug, generic simulator | Succeeded |
| iPhone / iPad | Release, generic device, signing disabled | Succeeded |

The Mac app was locally signed with the sandbox entitlement, opened, and inspected. Its existing wallet, unlocks and relic collection remained intact. The atlas displays new world lengths while retaining the player's actual prior distances, e.g. 360m best against a new 2,200m Harbor stage. The updated app is left at its menu.

## Automated rules and persistence

`Scripts/test.sh` passes **95 named tests and 194 additional profile assertions**:

- 25 simulation tests: collision, movement, powers, seeded generation and persistence.
- 25 challenge tests: original Sprint and Jet Ski rules, clocks, gates, steering, currents, boats, boost and tricks.
- 23 controller/checkpoint tests: atomic settlement, unlocks, ghosts, active runs, preferences, daily rules and renderer cadence.
- 22 journey tests: extended duration, monotonic bounded acceleration, later-world and Expert escalation, aggregate obstacle density, required vertical actions, portal safety, abilities, relics, mastery and old-stage migration.
- 194 profile assertions: economy, records, ghost compatibility and long-course migration. Old short-stage records remain archived and cannot override longer-course times; earned medals and unlocks survive.

## Generated course checks

The included action driver reads spawned obstacle geometry and visible coin arcs without inspecting random-generator state. These are idealized, frame-by-frame simulated decisions, not a human playtest.

- **60/60 full expeditions:** 30 seeds on Standard and Expert; no replaced track, boards, abilities or revives. Maximum observed active entity count: 66.
- **60/60 additional relic-priority expeditions:** all 1,080 relics and 360 Gold world medals.
- Across those two sets, **10,500 checkpoint round trips**, each comparing the next 60 frames against an uninterrupted branch.
- A separate full ControllerSave/RunSession/GhostRecorder audit passed **765 round trips**, paused each of the six portals, retained 3,173 bounded replay samples and persisted six world medals. Largest observed save: 499,860 bytes.
- Lane-only control fails the generated worlds; jumps and slides are required.

JourneyTests and RouteAudit share their action driver and therefore do not constitute independent player strategies. No claim is made about every possible seed. `Tests/Audits/V5-results.txt` documents the measurements and limitations; accompanying V5 logs retain results. Use `Scripts/audit.sh` to reproduce the extended audits.

## Measured progression

Standard simulated stage durations were 97.93, 100.26, 104.23, 105.82, 105.53 and 110.47 seconds. A full route including portal transit took **10m34s Standard / 9m06s Expert**, without Air Dash or revives. See `V5.md` for stage distances and speeds.

Obstacle pressure counts distinct hazardous entities generated per second in the 15–35% and 65–85% progress windows, averaged over five fixed seeds. The density probe removes approaching hazards only to observe distribution without deaths; the survival audits above retain every actual obstacle.

| World | Standard late / early density | Expert late / early density |
|---|---:|---:|
| Harbor | 1.950× | 1.710× |
| Orbit | 1.232× | 1.305× |
| Mars | 1.867× | 1.789× |
| Verdant | 1.857× | 1.814× |
| Cryo | 1.750× | 1.611× |
| Forge | 1.738× | 1.866× |

Orbit deliberately keeps enough spacing to finish its longer low-gravity jumps. Later tiers add compound lane decisions as well as speed. These measurements show increased obstacle pressure; they do not quantify perceived human difficulty.

## Native visual verification

The dedicated Coastline Rush QA iPhone simulator restored a pre-update Orbital Causeway run paused at its original 440m stage length, with the HUD marked CLASSIC. A separate QA fixture was then produced by driving a real generated Expert Forge route to 80% progress without replacement obstacles or protection. After restoration and resume, the actual native UI showed OVERDRIVE, 145–146km/h and approximately 2,640m / 3,300m, with readable hazard, combo and artifact controls. The simulator's prior save was backed up and restored after inspection. The player's Mac save was not replaced with a fixture.

The existing world art and renderer are unchanged. Historical visual and frame-cadence evidence is retained in `VERIFICATION-V4.md`; its measurements must not be interpreted as new v5 performance results.

## Limits and distribution

Physical iPhone/iPad touch feel, sustained frame pacing, thermals, battery use and haptics remain unmeasured. Automated feasibility does not replace human difficulty calibration. No new frame-rate or performance improvement claim is made.

The supplied Mac app is locally ad-hoc signed, not Developer ID notarized. Its universal architecture, version and packaged signature are checked. The iOS device build is unsigned; physical installation and store release still require the owner's Apple signing team and provisioning. No store publication or backend deployment was performed.
