#!/bin/bash
# FX and camera shots: Scripts/fx.sh <label>  ->  work/shots/<label>/*.png, each with its live particle count.
set -euo pipefail
cd "$(dirname "$0")/.."
label="${1:-fx}"
mkdir -p work/mc "work/shots/$label"
sources=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift)
sources+=(Sources/World*.swift)
swiftc -O -swift-version 5 -module-cache-path work/mc "${sources[@]}" Scripts/FXPreview.swift -o work/fx-preview
./work/fx-preview "work/shots/$label"
