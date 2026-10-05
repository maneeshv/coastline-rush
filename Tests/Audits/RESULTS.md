# Independent v4 QA

The independent harnesses exercise production simulation, persistence and SceneKit implementations. They do not edit production sources, replace the generated track, grant invulnerability, spend boards, activate artifact abilities, or revive the runner.

| Audit | Result | Evidence |
| --- | --- | --- |
| Ordinary Odyssey routes | 60/60 complete six-world routes, 30 seeds on each difficulty; 1,470 checkpoint restores with equivalent 60-frame future branches; maximum 51 active entities | `route-audit.log` |
| Mastery routes | 60/60 complete six-world routes; all 1,080 possible relics collected; all 360 gold medals earned; 1,470 checkpoint restores | `mastery-audit.log` |
| Wave Rider | 60/60 complete generated 1,800 m courses; 2,579 gates cleared, none missed; both difficulties; boost used when charged | `water-audit.log` |
| Ghost + checkpoint integration | One complete generated six-world run through 626 production `ControllerSave` / `RunSession` / `GhostRecorder` round-trips; six paused portals; 1,755 recorded samples; six persisted medals; largest observed save 233,292 bytes | `ghost-checkpoint-audit.log` |
| Native world caches | 30 cyclic destination selections and next-world prewarms; at most two cached destination records, 86 pooled entity hierarchies and 19 active entity hierarchies in these opening snapshots; 25 resource-preparation callbacks | `world-cache-audit.log` |
| Quality presets | All four settings applied to the native SceneKit world without errors | `world-cache-audit.log` |
| Native Mac callback cadence, final sources | 12-second visible production-controller probe; first 2 seconds excluded; median 8.333 ms, p95 8.561 ms, p99 8.841 ms, maximum 83.117 ms across 1,191 intervals | `frame-cadence-final.log` |

The route policy reads generated entities and uses real steering, jumps, slides and rover roofs. Mastery routes explicitly jump from a moving rover roof toward the following cargo line. The water policy waits for crossing traffic to pass before turning into the next gate lane. An earlier naive solver changed lane immediately after each pickup/gate and crashed; those were corrected solver policies, not patched production hazards.

Ghost validation uses actual production data types without UI stubs. It checks preserved recording samples and course identity, exact stage results after decoding, stationary pause during all six portals, no interpolation between worlds, and rejection of unrelated seeds, difficulties and practice starts. The independent audit does not claim to have driven touch gestures or a live `GameController` view; the root task separately verifies native UI and controller integration.

No actionable production blocker was found in this scope. These are bounded deterministic feasibility checks, not a proof over every random seed or an assessment of human difficulty. The SceneKit cache test verifies retained object counts, not GPU frame times or peak process memory. Physical iPhone touch feel, haptics, sustained frame pacing, thermal behavior and battery use remain unmeasured.

## Native Mac timing context

The timing probe uses the actual `GameController`, `GameFrameRelay`, `DesktopGameView`, `CoastalWorld`, and generated Harbor Odyssey course, with bundled panorama textures. A delegate records real `renderer(_:updateAtTime:)` callbacks and forwards them to the production relay. The normal production controller advances gameplay while a bounded autoplayer supplies movement. This is not an offscreen renderer or software-only simulation benchmark.

Observed hardware was Apple M5 Pro, 18 logical CPUs, 64 GiB memory, macOS 26.6.2 (25G83). The visible window was 1,280 × 800 points at 2× backing scale (approximately 2,560 × 1,600 pixels), Ultra quality with 4× MSAA. The scene requested 60 FPS. Callback frequency must **not** be labeled display/presentation FPS or GPU completion time. There is no physical iPhone FPS claim.

After the first probe, the root task made two narrow production refinements: `GameFrameRelay.refresh` skips redundant active redraw requests and only changes rendering properties when their values change; `GameController.updateQuality` only reapplies scene quality after the effective quality changes. The same native probe was rebuilt and run once more for 12 seconds.

| Callback metric | Before guards | Final source |
| --- | ---: | ---: |
| Measured intervals after 2-second warm-up | 1,173 | 1,191 |
| Median | 8.334 ms | 8.333 ms |
| p95 | 8.456 ms | 8.561 ms |
| p99 | 11.962 ms | 8.841 ms |
| Maximum | 139.271 ms | 83.117 ms |
| Mean callback frequency | 117.35 Hz | 119.10 Hz |

The median was effectively unchanged, p95 was slightly higher, and p99/maximum were lower in the second observed window. These are two short samples using different generated seeds; they do not isolate causality or establish an overall performance gain. Callbacks remained near 120 Hz despite a requested 60 FPS. The final 83.117 ms maximum means the probe still does not establish hitch-free performance. Original and final logs are retained; `source-hashes-final.txt` identifies the exact final source files.

The native UI executable required the normal macOS window-server environment outside the command sandbox. The first sandboxed launch aborted before producing measurements; only the completed native launch above supplies timing evidence. Context7 documentation lookup returned an invalid API key; the probe reused compiled production APIs and checked Apple's callback documentation entry as fallback.

## Reproduce

From the project folder, run `bash Scripts/audit.sh`. The packaged audit harnesses generate real courses and compile directly against the shipped production sources. The original timing probe is retained in the development workspace under `work/v4-qa/`; its measured limitations are recorded above.
