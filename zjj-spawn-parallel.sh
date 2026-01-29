#!/usr/bin/env bash
# zjj parallel bead spawner - spawn N Opus agents with full Red Queen

set -euo pipefail

WORKER_COUNT=${1:-8}
REPO_ROOT="/home/lewis/src/nuoc"
RALPH_PROMPT="$REPO_ROOT/Ralph/ralph-prompt-zjj-opus-full-rq.md"

echo "🚀 Spawning $WORKER_COUNT parallel zjj workers with Opus + full Red Queen..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get ready beads
READY_BEADS=($(cd "$REPO_ROOT" && bd ready | grep -oE 'nuoc-[a-z0-9]+' | head -"$WORKER_COUNT"))

if [ ${#READY_BEADS[@]} -eq 0 ]; then
  echo "❌ No ready beads found"
  exit 1
fi

echo "📋 Found ${#READY_BEADS[@]} ready beads:"
printf '  - %s\n' "${READY_BEADS[@]}"
echo ""

# Spawn workers in background
for BEAD_ID in "${READY_BEADS[@]}"; do
  echo "🔧 Spawning worker for $BEAD_ID..."

  (
    cd "$REPO_ROOT"

    # Spawn zjj agent with custom prompt
    zjj spawn "$BEAD_ID" \
      --agent-command=claude \
      --agent-args="--prompt" "--prompt-file" "$RALPH_PROMPT" \
      --background \
      --timeout=14400  # 4 hours
  ) &

  # Stagger spawns to avoid resource spikes
  sleep 0.5
done

echo ""
echo "✅ Spawned ${#READY_BEADS[@]} zjj workers in background"
echo ""
echo "📍 Monitor workers:"
echo "   zjj list                - List all workers"
echo "   zjj status              - Detailed status"
echo "   zjj dashboard           - Interactive TUI"
echo ""
echo "🎯 Each worker will:"
echo "   1. Claim bead (bd update --status=in_progress)"
echo "   2. Run Opus with full TDD15 (15 phases)"
echo "   3. Run full Red Queen (10 generations)"
echo "   4. Auto-merge to main on success"
echo "   5. Close bead (bd close)"
echo "   6. Cleanup workspace"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for all background spawns
wait

echo ""
echo "🎉 All workers spawned! Monitor with: zjj dashboard"
