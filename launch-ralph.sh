#!/usr/bin/env bash
# Launch Ralph Wiggum for overnight TDD15 feature implementation

set -e

echo "🎯 Launching Ralph Wiggum - Overnight TDD15 Feature Implementation"
echo ""
echo "Configuration:"
echo "  Features:     10 P0 beads"
echo "  Methodology:  TDD15 (15-phase per feature)"
echo "  Max Iters:    150 (15 phases × 10 features)"
echo "  Agent:        claude-code"
echo "  Auto-commit:  enabled"
echo "  Auto-approve: enabled"
echo ""
echo "Progress tracking:"
echo "  - Watch: ralph --status"
echo "  - Add hints: ralph --add-context 'your hint'"
echo "  - Tasks: ralph --status --tasks"
echo ""
echo "Files:"
echo "  - Prompt: ralph-prompt.md"
echo "  - Features: ralph-features.json"
echo "  - Beads: bd list --status=in_progress"
echo ""
echo "Starting in 3 seconds... (Ctrl+C to cancel)"
sleep 3

ralph \
  --prompt-file ralph-prompt.md \
  --max-iterations 150 \
  --completion-promise "COMPLETE" \
  --allow-all \
  2>&1 | tee ralph-overnight-$(date +%Y%m%d-%H%M%S).log

echo ""
echo "✅ Ralph loop complete or stopped"
echo "Check ralph-overnight-*.log for full output"
