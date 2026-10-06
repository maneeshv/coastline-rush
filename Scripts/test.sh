#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_work="$(mktemp -d /tmp/coastline-tests.XXXXXX)"
cd "$project_root"
core=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift)
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Tests/SimulationTests.swift -o "$test_work/simulation-tests"
"$test_work/simulation-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Tests/ChallengeTests.swift -o "$test_work/challenge-tests"
"$test_work/challenge-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/PlayerProfile.swift Sources/RunCheckpoint.swift \
  Sources/RunPresentation.swift Sources/GameController.swift \
  Tests/ControllerTests.swift -o "$test_work/controller-tests"
"$test_work/controller-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/PlayerProfile.swift Tests/ProfileTests.swift -o "$test_work/profile-tests"
"$test_work/profile-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  -O -D ROUTE_HELPER "${core[@]}" Tests/Audits/RouteAudit.swift Tests/JourneyTests.swift -o "$test_work/journey-tests"
"$test_work/journey-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  -O "${core[@]}" Tests/ExpansionTests.swift -o "$test_work/expansion-tests"
"$test_work/expansion-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  Tests/LookTests.swift -o "$test_work/look-tests"
"$test_work/look-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  Tests/MaterialTests.swift -o "$test_work/material-tests"
"$test_work/material-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  Tests/PropsTests.swift -o "$test_work/props-tests"
"$test_work/props-tests"
swiftc -swift-version 5 -module-cache-path "$test_work/modules" \
  "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift \
  Tests/MotionTests.swift -o "$test_work/motion-tests"
"$test_work/motion-tests"
printf 'Test executables retained at %s\n' "$test_work"
