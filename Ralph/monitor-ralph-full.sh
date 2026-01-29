#!/usr/bin/env bash
# Monitor Ralph + Red Queen progress in real-time

clear

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      Ralph Wiggum + Red Queen - Live Progress Monitor         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Ralph Status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Ralph Loop Status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ralph --status --tasks 2>/dev/null || echo "  Ralph not running or status unavailable"
echo ""

# Ralph Tasks
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Ralph Tasks:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ralph --list-tasks 2>/dev/null | head -20 || echo "  No tasks or Ralph not running"
echo ""

# Beads Progress
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Beads Overall Progress:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bd stats
echo ""

# Current Work
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔄 Currently In Progress:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CURRENT=$(bd list --status=in_progress 2>/dev/null | head -10)
if [ -n "$CURRENT" ]; then
  echo "$CURRENT"
else
  echo "  No beads in progress"
fi
echo ""

# Recent Completions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Recently Completed (last 5):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bd list --status=closed 2>/dev/null | head -5
echo ""

# Next Up
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏭️  Next Ready Beads (top 5):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bd ready 2>/dev/null | head -5
echo ""

# Git Activity
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Recent Git Activity (last 10 commits):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
git log --oneline --decorate -10 2>/dev/null || echo "  No git history available"
echo ""

# TDD15 + Red Queen Commit Analysis
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧬 Workflow Phase Distribution (last 50 commits):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if git log --oneline -50 2>/dev/null | grep -q "RED\|GREEN\|REFACTOR\|VERIFY\|RQ-"; then
  RED_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "RED:" || echo 0)
  GREEN_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "GREEN:" || echo 0)
  REFACTOR_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "REFACTOR:" || echo 0)
  VERIFY_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "VERIFY:" || echo 0)
  RQ_FIX_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "RQ-FIX:" || echo 0)
  RQ_COMPLETE_COUNT=$(git log --oneline -50 2>/dev/null | grep -c "RQ-COMPLETE:" || echo 0)

  echo "  TDD15 Phases:"
  echo "    RED:      $RED_COUNT commits"
  echo "    GREEN:    $GREEN_COUNT commits"
  echo "    REFACTOR: $REFACTOR_COUNT commits"
  echo "    VERIFY:   $VERIFY_COUNT commits"
  echo ""
  echo "  Red Queen Evolution:"
  echo "    RQ-FIX:      $RQ_FIX_COUNT commits (defenses hardened)"
  echo "    RQ-COMPLETE: $RQ_COMPLETE_COUNT commits (evolution complete)"
else
  echo "  No TDD15/Red Queen commits yet"
fi
echo ""

# Progress Estimate
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 Progress Estimate:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_BEADS=186
CLOSED=$(bd stats 2>/dev/null | grep "Closed:" | awk '{print $2}' | tr -d ',' || echo "0")
OPEN=$(bd stats 2>/dev/null | grep "Open:" | awk '{print $2}' | tr -d ',' || echo "186")
PERCENT=$(( ${CLOSED:-0} * 100 / TOTAL_BEADS ))

echo "  Total Beads:    $TOTAL_BEADS"
echo "  Completed:      $CLOSED ($PERCENT%)"
echo "  Remaining:      $OPEN"
echo ""

# Progress bar
BAR_WIDTH=50
FILLED=$(( PERCENT * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))
printf "  Progress: ["
printf "%${FILLED}s" | tr ' ' '█'
printf "%${EMPTY}s" | tr ' ' '░'
printf "] %d%%\n" "$PERCENT"
echo ""

# Commands
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Useful Commands:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  watch -n 10 ./monitor-ralph-full.sh  # Auto-refresh every 10s"
echo "  tail -f ralph-full-*.log             # Watch live log"
echo "  ralph --add-context 'hint'           # Add guidance"
echo "  bd show <bead_id>                    # View bead details"
echo "  git log --grep='RQ-FIX' -10          # See recent Red Queen fixes"
echo "  kill \$(pgrep -f ralph)                # Stop Ralph gracefully"
echo ""
