# Portal momentum validation

Validated current v6 sources after the pattern-7 side-gap portal-clearance fix.

- Journey regressions: 27/27 pass, including 20 normal/precision portal boundaries across both difficulties, later-world tier floors, bounded HUD progress, high-speed Air Dash expiry, restart reset, v4/v5 checkpoint migration, 144 seed/world/difficulty clear landing and portal-approach combinations, and eight full generated skill routes.
- Ordinary audit: 60/60 complete six-world routes, zero hits, 300 speed-retaining world transitions, 5,070 checkpoint round trips with one-second future-state comparisons, peak 51.000 m/s, maximum 66 live entities.
- Relic audit: 60/60 complete routes, 360 gold stage medals, all 1,080 relics, zero hits, 300 speed-retaining transitions, 5,070 checkpoint round trips, peak 51.000 m/s, maximum 66 live entities.
- These 120 audit expeditions used production-generated tracks and no fixture replacements, boards, abilities, or revives. The existing solver required no changes to navigate the faster routes.
- First-seed Standard stage durations: 97.93 / 100.15 / 101.52 / 101.39 / 101.28 / 101.19 seconds; expedition total including transit 613.06 seconds.
- First-seed Expert stage durations: 82.08 / 83.87 / 86.46 / 87.40 / 88.21 / 88.92 seconds; expedition total including transit 526.53 seconds.

Density assertions preserve recovery floors: Harbor and Mars clearly increase obstacle count per second within the stage. Orbit already starts near its long low-gravity recovery floor; Cryo and Forge retain intense/overdrive pressure at entry, so their count rates are approximately flat while speed rises. Exact sampled rates are in journey-tests.log.

A stronger clearance test exposed a 0.904m side-gap extension into Orbital Causeway's promised clear portal approach (seed 6, Standard). Root fixed the v6 follow-beat guard to account for the full gap half-length; v5 generator behavior remains preserved. All tests and audits above were rerun after that fix.

These checks establish deterministic simulation feasibility. They do not establish human touchscreen performance or physical-device frame timing.
