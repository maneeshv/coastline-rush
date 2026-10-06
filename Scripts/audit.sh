#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
audit_work="$(mktemp -d /tmp/coastline-audit.XXXXXX)"
cd "$project_root"
flags=(-O -whole-module-optimization -swift-version 5 -module-cache-path "$audit_work/modules")
core=(Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift)
swiftc "${flags[@]}" "${core[@]}" Tests/Audits/RouteAudit.swift -o "$audit_work/routes"
for route in safe risky; do
  QA_SEEDS=30 QA_ROUTE="$route" "$audit_work/routes"
  QA_SEEDS=30 QA_ROUTE="$route" QA_RELICS=1 "$audit_work/routes"
done
swiftc "${flags[@]}" -D ROUTE_HELPER "${core[@]}" Tests/Audits/RouteAudit.swift Tests/Audits/ExpansionRouteAudit.swift -o "$audit_work/expansion-routes"
"$audit_work/expansion-routes"
swiftc "${flags[@]}" -D ROUTE_HELPER "${core[@]}" Tests/Audits/RouteAudit.swift Tests/Audits/ObjectiveAudit.swift -o "$audit_work/objectives"
QA_RELICS=1 "$audit_work/objectives"
swiftc "${flags[@]}" "${core[@]}" Tests/Audits/WaterAudit.swift -o "$audit_work/water"
"$audit_work/water"
swiftc "${flags[@]}" -D ROUTE_HELPER "${core[@]}" Sources/ReplayGhost.swift Sources/PlayerProfile.swift Sources/RunCheckpoint.swift Tests/Audits/RouteAudit.swift Tests/Audits/GhostCheckpointAudit.swift -o "$audit_work/checkpoints"
"$audit_work/checkpoints"
swiftc "${flags[@]}" "${core[@]}" Sources/ReplayGhost.swift Sources/CoastalWorld.swift Sources/World*.swift Tests/Audits/WorldCacheAudit.swift -o "$audit_work/cache"
"$audit_work/cache"
swiftc "${flags[@]}" -D ROUTE_HELPER "${core[@]}" Tests/Audits/RouteAudit.swift Tests/Audits/SkillAudit.swift -o "$audit_work/skill"
"$audit_work/skill"
# Legacy checkpoints: v4 stages (frozen legacy generator) must match the pre-overhaul build exactly;
# v5/v6 stages adopt the current generator (spec: resumed runs build new rows with new rules) and must reach their portal.
mkdir -p "$audit_work/legacy-base"
git archive e3049e5 Sources/PortalJourney.swift Sources/ExpeditionExpansion.swift Sources/RunnerSimulation.swift | tar -x -C "$audit_work/legacy-base"
swiftc "${flags[@]}" "$audit_work"/legacy-base/Sources/*.swift Tests/Audits/LegacyContinuityAudit.swift -o "$audit_work/legacy-base-probe"
swiftc "${flags[@]}" "${core[@]}" Tests/Audits/LegacyContinuityAudit.swift -o "$audit_work/legacy-probe"
"$audit_work/legacy-base-probe" create "$audit_work/legacy" "$audit_work/legacy-baseline.json"
"$audit_work/legacy-probe" verify "$audit_work/legacy" "$audit_work/legacy-baseline.json"
printf 'Audit executables retained at %s\n' "$audit_work"
