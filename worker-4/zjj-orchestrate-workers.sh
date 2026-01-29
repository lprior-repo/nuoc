#!/usr/bin/env bash
# zjj worker orchestrator - attaches to each workspace and runs Ralph workflow

set -euo pipefail

WORKER_COUNT=${1:-4}
REPO_ROOT="/home/lewis/src/nuoc"
RALPH_PROMPT="$REPO_ROOT/Ralph/ralph-prompt-fast-zjj.md"

echo "🤖 zjj Worker Orchestrator"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get existing zjj workers
WORKERS=($(zjj list | grep -E '^bead-' | awk '{print $1}' | head -"$WORKER_COUNT"))

if [ ${#WORKERS[@]} -eq 0 ]; then
  echo "❌ No zjj workers found. Run ./zjj-spawn-workers.sh first."
  exit 1
fi

echo "📋 Found ${#WORKERS[@]} workers:"
printf '  - %s\n' "${WORKERS[@]}"
echo ""

# For each worker, start Ralph in background
for WORKER in "${WORKERS[@]}"; do
  echo "🚀 Starting Ralph in $WORKER..."

  (
    cd "$REPO_ROOT"
    zjj attach "$WORKER" -c "claude --prompt '$RALPH_PROMPT' < /dev/null" &
  ) &

  sleep 1
done

echo ""
echo "✅ Ralph workers started in ${#WORKERS[@]} zjj sessions"
echo ""
echo "📍 Monitor:"
echo "   zjj status              - Worker status"
echo "   zjj attach <worker>     - Attach to worker"
echo "   zjj sync                - Sync all workers"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for all background jobs
wait
