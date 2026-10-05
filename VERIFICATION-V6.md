# Verification — v6 Continuous Momentum, 4 October 2026

## Native builds and app verification

Version 6.0.0, build 6. Deployment targets remain iOS 16+ and macOS 13+.

| Target | Build | Result |
|---|---|---|
| macOS | Release, arm64 + x86_64 | Passed |
| iOS Simulator | Debug, generic simulator | Passed |
| iPhone / iPad | Release, generic device, signing disabled | Passed |

All three builds were repeated after the final portal-clearance correction. The locally signed Mac app was opened; its About dialog confirms version 6.0.0 (6), and the player's existing wallet and best score were preserved. It is left at the main menu.

A native iPhone simulator portal test resumed a real generated Harbor run from a paused precision transition. The HUD displayed **104km/h in Harbor before arrival and 104km/h in Orbit after arrival**, with a 3,100m next-world target and Pressure encounter tier. The run was produced by driving the generated course without replacing obstacles or granting protection. Only the dedicated Coastline Rush QA simulator received the fixture; its existing save was backed up and restored afterward.

## Automated tests

`Scripts/test.sh` passes **100 named tests plus 203 profile assertions**:

- 25 simulation tests.
- 25 challenge tests for the original modes and water mechanics.
- 23 controller/checkpoint tests.
- 27 journey tests, including all normal/precision world boundaries on both difficulties, later-world encounter tiers, bounded HUD progress, high-speed Air Dash expiry, restart reset, v4/v5 migration, 144 clear landing/portal-approach cases, and eight complete generated routes.
- 203 profile assertions, including independent v4/v5/v6 record preservation, exact legacy completion distance, ghost compatibility, economy and sanitization.

## Full generated expeditions

After the final clearance fix:

- **60/60 ordinary expeditions** passed with zero stage hits, 300 speed-retaining transitions and 5,070 checkpoint future comparisons.
- **60/60 relic-priority expeditions** passed with all 1,080 relics and 360 Gold medals, another 300 speed-retaining transitions and 5,070 checkpoint comparisons.
- Base speed was checked for nondecrease at every simulated frame, including portals. Peak observed speed: 51m/s. Maximum live entity count: 66.
- No route audit used boards, abilities, revives, protection, or substituted tracks. The existing action driver needed no changes for the faster courses.
- A separate full ControllerSave/RunSession/GhostRecorder check passed 758 JSON round trips, paused all six portals, kept 3,068 bounded replay samples and persisted six medals. Maximum observed save: 501,173 bytes.

The action driver reads spawned geometry and visible coin markers. It makes idealized frame-by-frame decisions; this verifies sampled route feasibility, not human difficulty. JourneyTests and the audit share that driver. No claim is made about every possible seed.

## Timing and pressure

Measured Standard stage times: 97.93, 100.15, 101.52, 101.39, 101.28 and 101.19 seconds. Full expedition including transit: **613.06s Standard / 526.53s Expert** without boosts or revives.

Harbor and Mars increase within-stage obstacle counts per second. Orbit begins near its long-flight recovery floor; Cryo and Forge begin with already intense/overdrive encounter density. Their measured rates remain roughly steady while speed increases. This is intentional: the later worlds skip the slow introduction while retaining physically possible jumps, slides and lane changes.

A stronger approach test found one long side-gap extending 0.904m into Orbit's clear portal zone. The v6 generator now checks the gap's complete half-length before adding that follow-up encounter. The full test suite, route audits and native builds above passed after the fix.

## Legacy replay and records

Pristine v5 sources and final v6 sources produced identical complete saved state at **356 sampled points across 24 v4/v5 world/difficulty cases**, including restoration in midair and future obstacle generation through portal entry. Comparison normalized only two unordered Sets. This consistency probe uses invulnerability to observe the whole stage; the separate survival audits above do not.

Existing current stages retain their original rules until the next portal. Player records preserve separate old course generations, and only incompatible Odyssey ghosts are invalidated. See `Tests/Audits/V6-results.md` and the accompanying V6 logs for retained evidence. `Scripts/audit.sh` reproduces the generated-route, ghost and other native audits.

## Limits and packaging

Physical iPhone/iPad touch feel, haptics, sustained FPS, thermal behavior and battery life remain unmeasured. This update makes no performance or human-difficulty calibration claim. Historical measurements are retained in `VERIFICATION-V4.md` and `VERIFICATION-V5.md` and are not new v6 measurements.

The Mac app is locally ad-hoc signed with the sandbox entitlement, not Developer ID notarized. Package verification checks the extracted signature, version, universal architecture, resources and byte-for-byte source archive contents. The iOS device build is unsigned; physical installation and store release require the owner's signing team and provisioning. No store publication or cloud deployment was performed.
