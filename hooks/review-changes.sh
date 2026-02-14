#!/bin/bash
# Lists Claude Code sessions with change manifests and opens
# the selected session's changed files in Zed.
set -euo pipefail

CHANGES_DIR="$HOME/.claude/changes"

if [ ! -d "$CHANGES_DIR" ]; then
  echo "No changes directory found."
  exit 0
fi

# Find all session manifests (exclude latest.json symlink)
MANIFESTS=()
while IFS= read -r f; do
  MANIFESTS+=("$f")
done < <(find "$CHANGES_DIR" -name '*.json' -not -name 'latest.json' -type f | sort -t/ -k1 -r)

if [ ${#MANIFESTS[@]} -eq 0 ]; then
  echo "No session manifests found."
  exit 0
fi

echo "Available Claude Code sessions:"
echo ""
for i in "${!MANIFESTS[@]}"; do
  M="${MANIFESTS[$i]}"
  STARTED=$(jq -r '.started // "unknown"' "$M")
  COUNT=$(jq -r '.changes | length' "$M")
  SID=$(jq -r '.session_id // "unknown"' "$M")
  SHORT_SID="${SID:0:8}"
  # Show first few unique files
  TOP_FILES=$(jq -r '[.changes[].file] | unique | .[:3] | .[] | split("/") | .[-1]' "$M" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
  echo "  $((i+1))) [$SHORT_SID] $STARTED - $COUNT changes ($TOP_FILES)"
done

echo ""
echo -n "Pick a session (1-${#MANIFESTS[@]}), or 'a' for all: "
read -r CHOICE

if [ "$CHOICE" = "a" ] || [ "$CHOICE" = "A" ]; then
  # Aggregate all sessions
  FILES=$(jq -r '[.changes[] | .file + ":" + (.line | tostring)] | unique | .[]' "${MANIFESTS[@]}")
elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#MANIFESTS[@]} ]; then
  IDX=$((CHOICE - 1))
  FILES=$(jq -r '[.changes[] | .file + ":" + (.line | tostring)] | unique | .[]' "${MANIFESTS[$IDX]}")
else
  echo "Invalid choice."
  exit 1
fi

if [ -z "$FILES" ]; then
  echo "No files in selected session(s)."
  exit 0
fi

FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')
echo "Opening $FILE_COUNT files..."
echo "$FILES" | xargs zed
