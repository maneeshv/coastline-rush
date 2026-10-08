#!/bin/bash
# Runner close-ups: Scripts/runner.sh <label>  ->  work/shots/<label>/*.png and the runner's node/geometry/material counts.
set -euo pipefail
cd "$(dirname "$0")/.."
label="${1:-runner}"
mkdir -p work/mc "work/shots/$label"
sources=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift Sources/ReplayGhost.swift Sources/CoastalWorld.swift)
sources+=(Sources/World*.swift)
swiftc -O -swift-version 5 -module-cache-path work/mc "${sources[@]}" Scripts/RunnerPreview.swift -o work/runner-preview
./work/runner-preview "work/shots/$label"
