#!/bin/bash
# save-to-github.sh — Formal commit workflow for Alchitry Pt V2 NeoRV32 project
# Usage: ./scripts/save-to-github.sh "commit message"

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_WORKSPACE="${HOME}/.openclaw-codecbot/workspaces/codecbot"
COMMIT_MSG="${1:-$(date '+%Y-%m-%d %H:%M:%S') automatic save}"

echo "=== Alchitry Pt V2 NeoRV32 — Save to GitHub ==="
echo ""

# 1. Sync agent workspace to repo
echo "[1/5] Syncing agent workspace to repo..."
if [ -d "$AGENT_WORKSPACE" ]; then
    rsync -av --delete \
        --exclude='.openclaw/' \
        --exclude='memory/' \
        --exclude='*.log' \
        "$AGENT_WORKSPACE/" \
        "$REPO_ROOT/agent-workspace/"
    echo "    ✓ Synced agent-workspace/"
else
    echo "    ⚠ Agent workspace not found at $AGENT_WORKSPACE"
fi

# 2. Stage all changes
echo ""
echo "[2/5] Staging changes..."
cd "$REPO_ROOT"
git add -A

# 3. Show diff stats
echo ""
echo "[3/5] Changes to be committed:"
echo "---"
git diff --cached --stat | head -50
echo "---"

# Check if there's anything to commit
if git diff --cached --quiet; then
    echo ""
    echo "No changes to commit."
    exit 0
fi

# 4. Commit
echo ""
echo "[4/5] Committing with message:"
echo "    '$COMMIT_MSG'"
git commit -m "$COMMIT_MSG"
echo "    ✓ Committed"

# 5. Push
echo ""
echo "[5/5] Pushing to GitHub..."
git push origin main
echo "    ✓ Pushed to origin/main"

echo ""
echo "=== Save complete ==="
echo "Commit: $(git rev-parse --short HEAD)"
echo ""
