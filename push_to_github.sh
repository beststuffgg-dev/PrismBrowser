#!/bin/bash
#
# push_to_github.sh — publish this repo to GitHub.
#
# Usage:
#   ./push_to_github.sh <repo-name> [--private]
#
# Requires the GitHub CLI (https://cli.github.com):  brew install gh
# Run `gh auth login` once first if you haven't.

set -euo pipefail

REPO="${1:-prism-browser}"
VIS="--public"
[ "${2:-}" = "--private" ] && VIS="--private"

cd "$(cd "$(dirname "$0")" && pwd)"

# Clear any stale lock files left over from a previous environment.
if [ -d .git ]; then
    rm -f .git/*.lock .git/HEAD.lock .git/index.lock 2>/dev/null || true
    find .git/objects -name 'tmp_obj_*' -delete 2>/dev/null || true
fi

# Initialize the repo + first commit if not already done.
if [ ! -d .git ]; then
    echo "▸ Initializing git repo…"
    git init -q
    git add -A
    git commit -q -m "Initial commit: Prism 3D-aesthetic macOS browser with AI agent + 3MF support"
else
    # Capture any uncommitted changes.
    git add -A
    git diff --cached --quiet || git commit -q -m "Update"
fi

if command -v gh >/dev/null; then
    echo "▸ Creating GitHub repo '$REPO' and pushing…"
    git branch -M main
    gh repo create "$REPO" $VIS --source=. --remote=origin --push
    echo "✓ Pushed. View it with: gh repo view --web"
else
    cat <<'MANUAL'
✗ GitHub CLI (gh) not found. Two options:

A) Install it, then re-run this script:
     brew install gh && gh auth login

B) Do it manually:
     1. Create an empty repo at https://github.com/new (no README/.gitignore)
     2. Then run:
          git branch -M main
          git remote add origin https://github.com/<you>/<repo>.git
          git push -u origin main
MANUAL
    exit 1
fi
