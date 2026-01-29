#!/usr/bin/env bash
# Sync all zjj workers back to main

set -euo pipefail

echo "🔄 Syncing all zjj workers to main..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

zjj sync

echo ""
echo "✅ All workers synced"
echo ""
echo "📍 Next steps:"
echo "   zjj status              - Check worker status"
echo "   zjj list                - List all workers"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
