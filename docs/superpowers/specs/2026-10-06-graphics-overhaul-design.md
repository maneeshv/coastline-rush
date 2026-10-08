# Coastline Rush graphics overhaul — design

Date: 2026-10-06. Approach A: fully procedural, original assets, SceneKit only. No new dependencies, no downloaded art.

## Goal

Make the six Odyssey worlds, the harbor modes and the runner look like a polished stylized 3D game instead of colored primitives. Gameplay is out of scope and must not change.

## Diagnosis (baseline renders in `work/shots/before/`)

1. Mars, Verdant, Cryo and Forge have no sky asset. `buildDestinationSlice` falls back to `worldSky()`, a flat gradient with dot stars that is also used as the lighting environment, so those worlds light flat.
2. `material()` produces one flat color at roughness 0.64. Procedural textures are 256 px noise. Decks are large flat repeating tiles.
3. Props are raw primitives: sphere rocks, 5-sided cone crystals, disc trees, unchamfered boxes.
4. The runner is stacked primitives with stubby proportions; animation is sine-driven.
5. No ambient particles, no haze layering, no speed cues; the camera is high and static.
6. SceneKit grading, contrast, saturation, white balance, grain and motion blur are unused; all worlds share one tone.

## Architecture

New files, each an `extension CoastalWorld`:

| File | Responsibility |
|---|---|
| `Sources/WorldLook.swift` | Per-stage look table and `applyLook(_:)`: sun color/intensity/direction, ambient, environment intensity, fog, exposure, contrast, saturation, white balance, grain, bloom, procedural color-grading LUT (dropped in phase 1; see the LUT note under Phase 1). Called from `configureWorld` and `init`. |
| `Sources/WorldMaterials.swift` | World-space surface-detail shader modifier (albedo breakup, roughness variation, cavity darkening, edge wear), higher-resolution texture builders, deck decals. |
| `Sources/WorldFX.swift` | Ambient particle systems per stage, speed lines, footstep dust, landing burst, camera follow/lag/FOV/lean. |

The shared helpers in `CoastalWorld.swift` (`color`, `material`, `box`, `sphere`, `cylinder`, `capsule`, `image`, `texture`, `loadAsset`, `flattenPreservingHierarchy`, `sculptedMesh`, and the state they touch) change from `private` to internal so the extensions can use them. After adding files, regenerate the project with `xcodegen` and add the new sources to the `WorldCacheAudit` compile line in `Scripts/audit.sh` (and to `Scripts/RenderPreview.swift`'s documented compile command).

## Phase 1 — skies, lighting, grading

- `Scripts/generate_skies.swift` writes `Resources/MarsSky.png`, `VerdantSky.png`, `CryoSky.png`, `ForgeSky.png`: 2048×1024 equirectangular, horizon at mid-height, fbm clouds/nebula, star field, sun or planet glow, seamless horizontally. The existing loader picks them up by name.
- `WorldLook` targets: Harbor warm/cool dusk; Mars dusty ochre haze; Verdant bioluminescent teal; Cryo cold high-key; Forge deep contrast with orange glow; Orbit crisp black with strong rim light.
- LUT: generated in code (CoreGraphics strip, 16³ or 32³ layout as `colorGrading.contents`); verify SceneKit's expected LUT layout during implementation.
  - Note: the color-grading LUT was dropped during phase 1: SceneKit samples it by linear color with no half-texel offset, which floors the darks. Grading uses SCNCamera contrast/saturation/white balance instead; a custom SCNTechnique post pass is the phase 4 fallback if split-toning is wanted.

## Phase 2 — surfaces and geometry

- Surface-detail shader applied to terrain, decks, rocks, buildings and large props.
- Textures 512–1024 px with tile breakup; deck panel seams, wear and markings.
- Noise-displaced icosphere rocks; hexagonal-prism crystal clusters; denser fbm terrain heightfield; curved-trunk layered alien trees; harbor houses with roof variation and chamfered edges.
- Static geometry stays merged via `flattenPreservingHierarchy`.

## Phase 3 — runner

- Taller heroic proportions, larger on screen, built from `sculptedMesh` shells.
- Pose-curve run cycle (contact/down/passing/up) with easing, hip sway, arm counter-swing, head stabilization, follow-through; landing squash; roll tuck.
- Keep node names `leftLeg`, `rightLeg`, `leftArm`, `rightArm`, `jetSki`, `artifactAura`, `personalGhost` and the `player.position` contract with the simulation route.
- Note: the roll tuck is a 0.74-scale spinning ball (ceiling 1.30 m, no lower than the deck; the harbor shutter at 0.73 m was already clipped by the old roll); the old rig's elbows bent backward and the new tables bend them forward; the ghost stays a frozen-pose clone with its pose root reset.

## Phase 4 — FX and camera

- Ambient particles: harbor mist, orbit star streaks, Mars dust, Verdant spores, Cryo snow, Forge embers.
- Speed lines above a speed threshold, footstep dust, landing burst; pickup sparkle only if a pickup event is available without simulation changes.
- Camera: slightly lower, smoothed follow lag, speed-scaled FOV, subtle lean into lane changes.
- Phase 4 gaps from phase 1: per-world white balance is unused (temperature/tint 0 everywhere), and the rim light is identical in every world (Orbit needs a strong rim).
- Note: the camera sits at 5.3/10.0 m (portrait) and 4.8/8.9 m (landscape), follows at rate 7/s (snapping in the menu, on replay rewind and under Reduced Motion), widens by up to 3° with speed and leans bank × 0.06; the runner is ≥1.15× its phase-3 screen height in every FXTests case. Particles are pooled SCNParticleSystems (≤7 in the scene) on one generated sprite; looping systems restart with reset(), one-shots by re-adding; motion blur stays off on every tier. Ambient particles die at least 5 m (three sprite sizes for mist) in front of the lens and fade out over their last 30%; harbor mist is born only over the water (|x| ≥ 6 m).

## Constraints

- No changes to `RunnerSimulation`, collisions, hitboxes, lane spacing (2.6 m) or entity placement. Tall scenery stays outside ±5 m of the track centerline.
- Quality tiers via `applyQuality`: performance = half particles, no motion blur or grain; balanced = moderate; ultra = full.
- Reduced Motion: no camera shake, no speed lines, no FOV pulse.
- Entity pools and node counts stay within `WorldCacheAudit` bounds (≤2 destinations, ≤96 pooled).
- Missing assets keep falling back to procedural images.

## Verification, per phase

1. `Scripts/RenderPreview.swift` before/after renders of harbor, orbit, mars, verdant, cryo, forge and jetski, shown to the user.
2. `Scripts/test.sh` and `Scripts/audit.sh` pass.
3. `xcodebuild` succeeds for `CoastlineRush-macOS` and `CoastlineRush-iOS`.
4. Rough frame-time comparison from the render harness.
