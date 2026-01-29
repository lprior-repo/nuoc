#!/usr/bin/env bash
# Monitor Ralph progress while it runs

clear

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           Ralph Wiggum - Live Progress Monitor                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Ralph Status:"
ralph --status
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🎯 Beads Progress:"
bd stats
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "🔄 In Progress Issues:"
bd list --status=in_progress | head -20
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✅ Recently Closed Issues:"
bd list --status=closed | head -10
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📝 Features Status:"
if [ -f ralph-features.json ]; then
  echo "  Total: $(jq '.features | length' ralph-features.json)"
  echo "  Passed: $(jq '[.features[] | select(.passes == true)] | length' ralph-features.json)"
  echo "  Remaining: $(jq '[.features[] | select(.passes == false)] | length' ralph-features.json)"
  echo ""
  echo "  Next up:"
  jq -r '.features[] | select(.passes == false) | "    - \(.bead_id): \(.title)"' ralph-features.json | head -3
else
  echo "  ralph-features.json not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Commands:"
echo "  watch -n 10 ./monitor-ralph.sh    # Auto-refresh every 10s"
echo "  ralph --add-context 'hint'        # Add guidance for next iteration"
echo "  tail -f ralph-overnight-*.log     # Watch live log"
echo "  kill \$(pgrep -f ralph)             # Stop Ralph gracefully"
echo ""
