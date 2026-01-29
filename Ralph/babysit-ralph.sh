#!/usr/bin/env bash
# Babysit Ralph for 8 hours - monitor and assist

DURATION_HOURS=8
CHECK_INTERVAL=60  # Check every 60 seconds
TOTAL_CHECKS=$((DURATION_HOURS * 60))

echo "🤖 Starting Ralph Babysitter"
echo "Duration: ${DURATION_HOURS} hours"
echo "Checking every ${CHECK_INTERVAL} seconds"
echo "Total checks: ${TOTAL_CHECKS}"
echo ""

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION_HOURS * 3600))

for ((i=1; i<=TOTAL_CHECKS; i++)); do
  CURRENT_TIME=$(date +%s)
  ELAPSED=$((CURRENT_TIME - START_TIME))
  REMAINING=$((END_TIME - CURRENT_TIME))

  # Check if Ralph is still running
  if ! pgrep -f "ralph.*ralph-prompt-with-red-queen" > /dev/null; then
    echo ""
    echo "⚠️  Ralph process not found!"
    echo "Time elapsed: $((ELAPSED / 3600))h $(( (ELAPSED % 3600) / 60))m"
    echo ""
    echo "Checking completion status..."

    # Check if it completed successfully
    if tail -100 ralph-full-*.log 2>/dev/null | grep -q "<promise>COMPLETE</promise>"; then
      echo "✅ Ralph completed successfully!"
      exit 0
    else
      echo "❌ Ralph stopped unexpectedly"
      echo "Last log entries:"
      tail -20 ralph-full-*.log 2>/dev/null
      exit 1
    fi
  fi

  # Every 10 checks (10 minutes), show detailed status
  if (( i % 10 == 0 )); then
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🤖 Ralph Babysitter - Check $i / $TOTAL_CHECKS"
    echo "⏰ Elapsed: $(echo "$ELAPSED / 3600" | bc)h $(( (ELAPSED % 3600) / 60))m"
    echo "⏱️  Remaining: $(echo "$REMAINING / 3600" | bc)h $(( (REMAINING % 3600) / 60))m"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    ./monitor-ralph-full.sh

    # Check for struggle indicators
    if ralph --status 2>/dev/null | grep -q "STRUGGLE\|STUCK\|ERROR"; then
      echo ""
      echo "⚠️  Detected struggle indicators - adding context hint"
      ralph --add-context "If stuck, try a different approach or skip to next bead"
    fi
  fi

  # Brief status every check
  ITER=$(ralph --status 2>/dev/null | grep "Iteration:" | awk '{print $2}' || echo "?")
  BEADS_CLOSED=$(bd stats 2>/dev/null | grep "Closed:" | awk '{print $2}' | tr -d ',' || echo "0")

  printf "\r[Check %4d/%d] ⏰ %dh%02dm elapsed | 📊 Iter:%s | ✅ Beads:%s/186 " \
    "$i" "$TOTAL_CHECKS" \
    "$((ELAPSED / 3600))" "$(( (ELAPSED % 3600) / 60))" \
    "$ITER" "$BEADS_CLOSED"

  # Wait for next check
  sleep $CHECK_INTERVAL

  # Check if we've reached the end time
  if (( CURRENT_TIME >= END_TIME )); then
    echo ""
    echo ""
    echo "⏱️  8-hour babysitting period complete!"
    echo ""
    ./monitor-ralph-full.sh
    exit 0
  fi
done

echo ""
echo "✅ Babysitting complete after ${DURATION_HOURS} hours"
