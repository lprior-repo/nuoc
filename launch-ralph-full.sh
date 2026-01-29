#!/usr/bin/env bash
# Launch Ralph Wiggum - Full 186 Beads with TDD15 + Red Queen Self-Healing

set -e

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║     Ralph Wiggum - TDD15 + Red Queen Self-Healing Loop          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Total Beads:  186"
echo "  Methodology:  TDD15 (15 phases) + Red Queen (10 generations)"
echo "  Per Bead:     ~28 iterations (15 TDD + 10 RQ + 3 fixes)"
echo "  Total Est:    ~5,200 iterations"
echo "  Max Iters:    6,000 (safety margin)"
echo "  Agent:        natural (Ralph's default)"
echo "  Tasks Mode:   ENABLED (dynamic - queries bd ready)"
echo "  Auto-commit:  enabled"
echo "  Auto-approve: enabled"
echo ""
echo "Workflow per Bead:"
echo "  1. TDD15: RED → GREEN → REFACTOR → VERIFY"
echo "  2. Red Queen: Adversarial evolution (5-10 generations)"
echo "  3. Self-healing: Fix → Defend → Evolve"
echo ""
echo "Progress tracking:"
echo "  - Status: ralph --status --tasks"
echo "  - Monitor: ./monitor-ralph-full.sh"
echo "  - Tasks: ralph --list-tasks"
echo "  - Beads: bd stats"
echo "  - Logs: tail -f ralph-full-*.log"
echo ""
echo "Files:"
echo "  - Prompt: ralph-prompt-with-red-queen.md"
echo "  - Beads: bd ready (dynamic)"
echo ""
echo "Expected duration: 8-12 hours for all 186 beads"
echo ""
echo "Starting in 5 seconds... (Ctrl+C to cancel)"
sleep 5

ralph \
  --prompt-file ralph-prompt-with-red-queen.md \
  --max-iterations 6000 \
  --completion-promise "COMPLETE" \
  --tasks \
  --task-promise "READY_FOR_NEXT_TASK" \
  --allow-all \
  2>&1 | tee ralph-full-$(date +%Y%m%d-%H%M%S).log

echo ""
echo "✅ Ralph loop complete or stopped"
echo ""
echo "Final status:"
bd stats
echo ""
echo "Check ralph-full-*.log for complete output"
