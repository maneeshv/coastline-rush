# Portal Odyssey

A finite expedition through six worlds. Run a stage, reach its portal, jump through, and land in a completely different place. The journey happens inside the live run, without a loading menu between worlds.

| World | Identity | Play rhythm | Discoverable artifact |
|---|---|---|---|
| The Departure | Familiar dusk waterfront, the first gateway | Learn the portal approach and takeoff | Tidal Compass |
| Orbital Causeway | Suspended causeway, satellites, a giant planet and deep space | Longer low-gravity jumps | Stellar Gyroscope |
| Mars Outpost | Rust-red canyons, outposts and exploration hardware | Reduced-gravity arcs around rover convoys | Martian Seed |
| Verdant Nexus | Bioluminescent alien vegetation and ancient structures | Alternate jumping and sliding through ruins | Living Prism |
| Cryo Cathedral | Frozen terrain, ice arches and cold celestial light | Plan lane changes earlier | Frozen Echo |
| The Star Forge | Reactor bridges, energy cores and a stellar furnace | Read moving hazards and finish the expedition | Star Heart |

## How progression works

- Progress is distance within the current stage, rather than a single endless speed ramp.
- The last approach to a portal is clear of hazards. V4 jumps through automatically with portal assist; an intentional jump in the last 14m earns precision credit. With assistance disabled, the gateway safely waits for your jump.
- Jump with an upward swipe, Up/W/Space, or the portal button. The short transition protects the runner, preserves combos and keeps visual movement. Pausing freezes it.
- Each new world has a clear landing stretch, different scenery and a distinct play rhythm.
- Three optional relic pickups appear in each world. Discovering a world's artifact adds it to the persistent collection and earns an ability charge. V4 places relics on action routes or harder alternatives; missing one never blocks a portal. See `V4.md` for mastery and loadouts.
- Unlocked worlds can be selected for practice. Completing the whole expedition and practicing its final stage are different accomplishments.
- Existing Endless, Sprint and Jet Ski modes remain available.

There are six authored world identities in this version. Procedural obstacle layouts vary between runs; the game does not claim an unlimited number of unique planets.

## Art and sound

All world structures, terrain, planets, portals and artifact models are original procedural SceneKit geometry. Harbor assets from v2 remain included. The sky below is an original generated texture used behind the Orbital Causeway scene; it is not a pre-rendered substitute for the playable world.

`Resources/OrbitSky.png` was generated with the built-in image-generation tool (opaque, no reference images), then copied into the project. Prompt:

> Use case: stylized-concept. Asset type: original equirectangular space sky texture for a premium stylized native 3D sci-fi portal runner. 2:1 wide panorama, seamless-feeling left and right edges. Primary request: beautiful deep outer space starfield with delicate pale blue and violet nebula wisps arching across the upper hemisphere, sparse high-detail pinprick stars at varied apparent distances, immense negative space and depth. Background only, no foreground planets (real 3D planets will be rendered separately), no terrain or structures. Lower hemisphere almost black midnight indigo with a few stars. Sophisticated restrained cinematic astrophotography-inspired texture, high detail, very dark but with luminous fine nebula filaments, avoid overexposed galactic cores or busy colored clouds. No text, UI, spacecraft, people, logos, watermark or lens flare. Not a screenshot or collage.

`Scripts/generate_journey_audio.py` synthesizes six looping world ambiences plus portal, arrival and relic cues using only the Python standard library. All outputs are bundled and play offline.
