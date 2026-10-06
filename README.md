# Coastline Rush — Portal Odyssey · v8

An original native 3D runner for iPhone, iPad, and Mac. Cross six worlds in Portal Odyssey: a dusk harbor, orbital causeway, Mars outpost, alien ruins, frozen moon, and stellar forge. Complete each stage and jump through its portal without leaving the run. Campaign and Endless Odyssey now include branching routes, run perks and authored finales. The Atlas offers short finale practice; the original Coastal Rush, Sprint and Jet Ski modes are also included.

Built with SwiftUI, SceneKit, and AVFoundation. The 3D art and surface textures are procedural, the harbor and orbital skies and Mars rock albedo are original generated images, the Mars, Verdant, Cryo and Forge skies are procedural, the music and sound effects are original, and all resources are bundled. No third-party runtime packages, accounts, internet connection, or subscriptions are required.

## Play on Mac

Open the supplied **Coastline Rush.app**. Use arrow keys or WASD to change lanes, jump, and roll. Space also jumps; B activates a board; E uses an artifact; Escape or P pauses; Return starts or resumes a run. Mouse swipes and double-click board activation also work.

## Run on iPhone or iPad

1. Open `CoastlineRush.xcodeproj` in Xcode.
2. Select the **CoastlineRush-iOS** scheme and an iPhone simulator, then Run.
3. For a physical device, select your Apple development team in Signing & Capabilities, choose your connected device, and Run. The bundle identifier can be changed for your team.

The project targets iOS 16+ and macOS 13+. It includes a separate native macOS app target, rather than relying on iPhone app compatibility. The generated Xcode project is included; XcodeGen is only needed after changing `project.yml` or adding/removing source files.

## Controls

| Action | iPhone / iPad | Mac |
|---|---|---|
| Change lane | Swipe left / right | Left / right, A / D |
| Jump | Swipe up | Up, W, or Space |
| Roll / fast-fall | Swipe down | Down or S |
| Activate board | Double-tap or board button | B, double-click, or board button |
| Artifact ability | Artifact button | E or artifact button |
| Continuous Jet Ski steering | Drag sideways | Drag sideways, or A / D |
| Pause | Pause button | Escape, P, or pause button |

On iPad, attached keyboards also support arrows, WASD, Space, B, E, and Escape.

## Portal Odyssey: six worlds in one run

Select **Portal Odyssey**, then **Begin Odyssey**. The Star Atlas shows the six destinations, their mechanics, recovered artifacts and unlocked starting points. Each stage has a fixed distance and a clear final approach. Jump within the final 14m for a precision entry and bonus. Portal assist is enabled by default and carries the runner through automatically; turning it off preserves safe waiting at the gateway. Forward motion and combos continue through the protected transition. Opening Loadout pauses the run. Portal arrivals offer optional perk tradeoffs.

The worlds change geometry, lighting, soundtrack and gameplay: long low-gravity leaps in orbit, rover routes on Mars, laser arches in alien ruins, slower steering on ice, and moving cargo at the stellar forge. Every world also mixes in hazards that change as you approach: vehicles that shift lanes, timed laser gates, gap walls, stacked barriers, real meteor impacts and collapsing decks, each telegraphed at least a second ahead. Three optional relic pickups appear in each world, placed on action routes or riskier alternatives. Each normally earns one of up to three artifact charges; run perks can change capacity and recharge rules. Choose Air Dash, Phase Step, or Aegis Shield before a run or in a safe gateway/landing zone. Bronze rewards completion; Silver requires no impacts and two clean obstacle actions; Gold also requires two relics and a precision portal entry. Recovered artifact types and unlocked destinations save during the run, independently from the coins banked at its end.

In Campaign, crossing the sixth portal finishes the route. Endless Odyssey loops into a faster next cycle with separate records. Atlas Practice starts the final segment of a world without changing progression or currency. A full expedition requires starting at The Departure and crossing all six portals; a late-world practice finish does not count as a full expedition. Read `V8.md` for the gameplay overhaul (coins, new hazards, variety), `V7.md` for the seven-part expansion, `V6.md` for continuous speed across portals, `V5.md` for the extended-stage upgrade, and `V4.md` for earlier upgrade details and `JOURNEY.md` for the original stage plan.

## Continuous momentum across worlds

Portal transitions retain your running speed. Each world starts at the previous world's peak and accelerates further: Standard progresses from 17 to 45m/s across the expedition; Expert from 20 to 51m/s. Arrival gives approximately three seconds of clear track at the retained pace. Later worlds enter stronger encounter pools instead of repeating a long beginner section.

Worlds span 2.2–4.4km and last about 98–102 seconds on Standard. The full expedition takes about 10m13s. Distinct world mechanics, mixed actions and compound lane decisions keep pressure rising while preserving enough recovery time for low-gravity jumps and ice steering. See `V6.md` for the complete curve and stage design.

Existing paused v4/v5/v6 runs finish their current world under the old rules and adopt the new curve at their next portal. Start a new Odyssey for the full updated expedition.

## Original modes, two difficulty levels

Select a mode at the harbor, then choose **Standard** or **Expert**. Each combination has its own personal best.

| Mode | Objective | What changes |
|---|---|---|
| Endless / Coastal Rush | Chase a score for as long as you survive | Denser lane decisions, jump/slide risks, roof routes, near misses, aerial rings and collidable drones. From 30 s (15 s Expert) full-width jump and slide rows; from 60 s (30 s Expert) jump-then-slide compounds, shifting trams, gap walls, stacked barriers and timed lasers; after the speed cap, rows keep tightening for two minutes |
| Harbor Sprint | Reach 1,500m before the clock expires | 60s Standard / 45s Expert; correctly crossed checkpoints add 4s / 3s. Jetpacks are excluded so flight cannot force missed checkpoints. Gets the same escalation as Endless (compound rows, shifting trams, walls, stacks, timed lasers) |
| Jet Ski / Wave Rider | Finish the 1,800m slalom | 60s / 45s; gates add 0.8s / 0.5s; a missed gate costs 4s and breaks the chain. Boost and clean ramp tricks buy a faster finish |

On the water, **down brakes**, **up, left and right chain distinct tricks after a ramp launches you**, and **B / double-tap / Boost spends half a full boost meter**. Gates and clean trick landings replenish boost. Sideways dragging steers continuously with momentum and currents; brake to settle the craft before landing. Moving boats add timing decisions. A failed landing loses the pending trick bonus. A boost lasts 2.6s and adds speed, without consuming a board or providing collision immunity. Braking cancels boost. Boost can only begin while on the water surface.

Clean obstacle escapes, close calls, gates, and tricks extend a five-second flow chain. Skill bonuses increase with the chain; a collision or missed gate breaks it. Cruising in a safely adjacent lane does not earn a near-miss bonus.

## Visual worlds

- Six distinct world environments, animated layered portals, rotating artifacts, giant planets, alien plants, ice arches, and reactor bridges.
- Original panoramic dusk and orbital skies with matching image-based lighting.
- Physically based wet road, water, stone, paint, glass and metal materials, with procedural surface/normal detail.
- Warm lit façades, balconies, quays, yacht berths, cranes, layered skyline, street pools of light and soft shadows.
- Helmeted articulated runner, dedicated jet-ski hull and crouched riding pose, banking, animated surface ripples, wake and spray.
- HDR camera, restrained bloom and ambient occlusion, speed-sensitive framing, dark translucent UI and mode-specific HUD.
- Jet-ski engine/spray audio responding to speed and boost.

This remains a stylized native 3D game. It does not use photoreal character scans, ray-traced reflections, or a AAA asset library. See `ART_DIRECTION.md` for the screenshot critique and asset provenance.

## Included gameplay

- Three lanes, responsive lane transitions, jump physics, fast-fall rolls, progressive speed, and earlier obstacles with readable safe paths.
- Cargo barriers, low signs, stationary trams, oncoming trams, and connected roof ramps with elevated coin trails.
- Seeded courses with validated action sequences: Odyssey draws at least ten encounter patterns per world from a shuffle bag (no pattern within three rows of itself), shuffles fork and finale order per seed, and includes full-width jumps and slides, rover roof transfers, lane-changing vehicles, timed lasers, gap walls, stacked barriers, real meteor impacts and collapsing decks. Every row keeps a reachable exit.
- Coins, rare rescue keys, a coin magnet, jetpack with aerial rings, coin trails and drone hazards, super sneakers, and a double-score pickup.
- Consumable boards lasting up to 20 seconds (12 on Expert) and absorbing one crash, with short protection after a board breaks. In Endless and Harbor Sprint the break also clears hazards within 18 m.
- Coins are an invitation, not a route marker: lines arc over jumps, run low under slides, sit beside hazards or bait a late lane change. Low coins need a roll.
- One key-based revive per run with a protected restart, pause/resume, results, and local personal bests.
- Three selectable/unlockable runner colorways and three board styles.
- Five upgrade levels for each power-up, board/key purchases with earned coins, three tiered missions, and an increasing score multiplier.
- A daily reward streak and a repeatable six-world Daily Odyssey, seeded by UTC date, with its own local daily best.
- Per-world Bronze/Silver/Gold mastery and exact-course personal ghost races, with bounded recordings saved on this device.
- Automatic/Fast/Balanced/Ultra graphics, portal assistance, adjustable swipe sensitivity and ghost visibility settings.
- Original looping soundtrack and effects, optional iPhone haptics, mute controls, and a how-to-play guide.
- Local profile persistence plus an active-run checkpoint every five seconds and when pausing, backgrounding, buying, or reviving. Interrupted runs restore paused; collected coins bank when a run is finished.

Daily courses reset at midnight UTC. Rewards and scores stay on this device. There is no backend, cross-device sync, global leaderboard, advertising, real-money purchase flow, or live seasonal content in this build.

## Project layout

- `RunnerSimulation.swift` / `PortalJourney.swift` / `ExpeditionExpansion.swift`: deterministic movement, six-stage progression, portals, relics, collision rules, procedural tracks, and power-ups.
- `CoastalWorld.swift`: reusable 3D environment, runner animation, obstacles, and pooled pickup geometry.
- `GameController.swift` / `RunPresentation.swift`: live update loop, input actions, audio, economy, lifecycle, bounded crash replay and local diagnostics.
- `PlayerProfile.swift` / `RunCheckpoint.swift` / `ReplayGhost.swift`: mastery, persistent saves, course identity, bounded recording and ghost playback.
- `GameUI.swift` / `GameSurface.swift`: responsive SwiftUI interface and platform input/rendering bridge.
- `Resources`: icons, privacy manifest, original skies, and music/ambiences/effects.
- `V8.md`: gameplay overhaul: coin lines, moving hazards, pattern variety, Endless escalation and Expert rules.
- `V7.md`: authored finales, branches, perk tradeoffs, practice, Endless, skill contracts and replay.
- `V6.md`: continuous portal momentum, stage progression, speed boundaries and migration.
- `V5.md`: historical extended-stage design and save migration.
- `V4.md`: v4 changes, controls, implementation limits and texture provenance.
- `JOURNEY.md`: original world design and sci-fi asset provenance.
- `Tests`: executable simulation, progression, and controller regressions using isolated in-memory saves.

## Build and test

From this folder:

```sh
./Scripts/test.sh
xcodebuild -project CoastlineRush.xcodeproj -scheme CoastlineRush-macOS -configuration Release -derivedDataPath /tmp/CoastlineRush-build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CoastlineRush.xcodeproj -scheme CoastlineRush-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/CoastlineRush-iOS-build CODE_SIGNING_ALLOWED=NO build
```

To regenerate the project when its file list changes:

```sh
xcodegen generate
```

The tests run gameplay and economy logic without a graphics device or real player save. See `VERIFICATION.md` for the checks performed on this delivered build.

The supplied Mac build uses local signing for this machine. Distributing through TestFlight, the App Store, or to other Macs requires your own signing, provisioning, and release review. Physical-device performance and haptics should be validated on the devices you plan to ship to.
