#!/usr/bin/env bash
# zjj parallel bead worker spawner
# Spawns N isolated zjj sessions, each working on a separate bead with Ralph + Red Queen

set -euo pipefail

MAX_WORKERS=${1:-8}
REPO_ROOT="/home/lewis/src/nuoc"

echo "🚀 Spawning $MAX_WORKERS parallel zjj bead workers..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get ready beads
READY_BEADS=($(cd "$REPO_ROOT" && bd ready | grep -oE 'nuoc-[a-z0-9]+' | head -"$MAX_WORKERS"))

echo "📋 Found ${#READY_BEADS[@]} ready beads to process:"
printf '  - %s\n' "${READY_BEADS[@]}"
echo ""

# Spawn workers in parallel
for i in "${!READY_BEADS[@]}"; do
  BEAD_ID="${READY_BEADS[$i]}"
  WORKER_NAME="bead-$BEAD_ID"

  echo "🔧 Spawning worker [$((i+1))/$MAX_WORKERS]: $WORKER_NAME"

  # Create zjj workspace for this bead
  (
    cd "$REPO_ROOT"
    zjj add "$WORKER_NAME" || echo "Workspace $WORKER_NAME already exists"
  ) &

  # Stagger spawns to avoid resource spikes
  sleep 0.5
done

echo ""
echo "✅ Spawned ${#READY_BEADS[@]} zjj workers"
echo ""
echo "📍 Worker commands:"
echo "   zjj status              - See all workers"
echo "   zjj attach <worker>     - Enter a worker"
echo "   zjj sync                - Sync all workers back to main"
echo "   zjj list                - List all workers"
echo ""
echo "🎯 Each worker will:"
echo "   1. Claim its bead (bd update --status=in_progress)"
echo "   2. Run TDD15 (8 phases, fast mode)"
echo "   3. Run Red Queen (3 generations)"
echo "   4. Close bead (bd close)"
echo "   5. Mark task complete"
echo "   6. Request next bead"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
