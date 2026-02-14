#!/bin/bash
# Lists Claude Code sessions with change manifests and opens
# the selected session's changed files in Zed.
# Uses claude to generate human-readable session names.
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

# Generate AI labels for sessions that don't have one yet
for M in "${MANIFESTS[@]}"; do
  LABEL=$(jq -r '.label // empty' "$M")
  if [ -z "$LABEL" ]; then
    PROJECT=$(jq -r '.project // empty' "$M")
    FILES=$(jq -r '[.changes[].file] | unique | .[] | split("/") | .[-1]' "$M" 2>/dev/null | sort -u | tr '\n' ', ' | sed 's/,$//')
    COUNT=$(jq -r '.changes | length' "$M")

    # Build a prompt for claude to name this session
    PROMPT="Generate a short label (3-6 words, no quotes, no punctuation) for a coding session. Project: ${PROJECT:-unknown}. Files changed: ${FILES}. Number of edits: ${COUNT}. Reply with ONLY the label, nothing else."

    # Try to get AI label, fall back to project name
    if command -v claude &>/dev/null; then
      AI_LABEL=$(claude -p "$PROMPT" 2>/dev/null | head -1 | tr -d '"' || true)
      if [ -n "$AI_LABEL" ] && [ ${#AI_LABEL} -lt 60 ]; then
        LABEL="$AI_LABEL"
      fi
    fi

    # Fallback: use project + top files
    if [ -z "$LABEL" ]; then
      if [ -n "$PROJECT" ]; then
        LABEL="$PROJECT: $FILES"
      else
        LABEL="$FILES"
      fi
    fi

    # Save label back to manifest
    TEMP=$(mktemp)
    jq --arg label "$LABEL" '.label = $label' "$M" > "$TEMP" && mv "$TEMP" "$M"
  fi
done

echo "Available Claude Code sessions:"
echo ""
for i in "${!MANIFESTS[@]}"; do
  M="${MANIFESTS[$i]}"
  LABEL=$(jq -r '.label // "unnamed"' "$M")
  STARTED=$(jq -r '.started // "unknown"' "$M")
  COUNT=$(jq -r '.changes | length' "$M")
  # Format timestamp to be more readable
  if command -v gdate &>/dev/null; then
    DISPLAY_TIME=$(gdate -d "$STARTED" +"%H:%M" 2>/dev/null || echo "$STARTED")
  else
    DISPLAY_TIME=$(echo "$STARTED" | sed 's/T/ /' | sed 's/Z//' | cut -c12-16)
  fi
  echo "  $((i+1))) $LABEL  ($COUNT edits, $DISPLAY_TIME UTC)"
done

echo ""
echo -n "Pick a session (1-${#MANIFESTS[@]}), or 'a' for all: "
read -r CHOICE

if [ "$CHOICE" = "a" ] || [ "$CHOICE" = "A" ]; then
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
