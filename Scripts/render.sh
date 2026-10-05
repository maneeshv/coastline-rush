#!/bin/bash
# Offscreen renders of every world: Scripts/render.sh <label>  ->  work/shots/<label>/*.png
set -euo pipefail
cd "$(dirname "$0")/.."
label="${1:-latest}"
mkdir -p work/mc "work/shots/$label"
sources=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift)
for extra in Sources/WorldLook.swift Sources/WorldMaterials.swift Sources/WorldFX.swift; do [ -f "$extra" ] && sources+=("$extra"); done
swiftc -O -swift-version 5 -module-cache-path work/mc "${sources[@]}" Scripts/RenderPreview.swift -o work/render
./work/render "work/shots/$label"
