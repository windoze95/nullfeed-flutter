#!/usr/bin/env bash
# Sync all agent instruction files from the canonical AGENTS.md.
# Run this after editing AGENTS.md, or let CI catch drift.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO_ROOT/AGENTS.md"

TARGETS=(
  "$REPO_ROOT/.cursorrules"
  "$REPO_ROOT/.windsurfrules"
  "$REPO_ROOT/.clinerules"
  "$REPO_ROOT/.continuerules"
  "$REPO_ROOT/CLAUDE.md"
  "$REPO_ROOT/.github/copilot-instructions.md"
)

if [ ! -f "$SOURCE" ]; then
  echo "Error: AGENTS.md not found at $SOURCE"
  exit 1
fi

for target in "${TARGETS[@]}"; do
  mkdir -p "$(dirname "$target")"
  cp "$SOURCE" "$target"
  echo "Synced: ${target#$REPO_ROOT/}"
done

echo "All agent instruction files synced from AGENTS.md."
