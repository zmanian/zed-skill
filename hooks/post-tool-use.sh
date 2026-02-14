#!/bin/bash
# PostToolUse hook: records Edit/Write changes to a session manifest
# for review in Zed.
#
# Reads Claude Code's PostToolUse JSON from stdin.
# Appends file:line entries to ~/.claude/changes/<session_id>.json
# Updates symlink ~/.claude/changes/latest.json -> current session.

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Skip if missing required fields
if [ "$FILE_PATH" = "null" ] || [ -z "$FILE_PATH" ]; then
  exit 0
fi
if [ "$SESSION_ID" = "null" ] || [ -z "$SESSION_ID" ]; then
  exit 0
fi

# For Edit tool, estimate line from old_string (first line of match)
# For Write tool, line is 1 (new file / full rewrite)
LINE=1
if [ "$TOOL_NAME" = "Edit" ]; then
  OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
  if [ -n "$OLD_STRING" ] && [ -f "$FILE_PATH" ]; then
    FIRST_LINE=$(echo "$OLD_STRING" | head -1)
    MATCH=$(grep -n -F -m1 "$FIRST_LINE" "$FILE_PATH" 2>/dev/null || true)
    if [ -n "$MATCH" ]; then
      LINE=$(echo "$MATCH" | cut -d: -f1)
    fi
  fi
fi

# Ensure changes directory exists
CHANGES_DIR="$HOME/.claude/changes"
mkdir -p "$CHANGES_DIR"

MANIFEST="$CHANGES_DIR/$SESSION_ID.json"

# Create manifest if it doesn't exist
if [ ! -f "$MANIFEST" ]; then
  PROJECT=""
  if [ -n "$CWD" ]; then
    PROJECT=$(basename "$CWD")
  fi
  jq -n \
    --arg sid "$SESSION_ID" \
    --arg ts "$TIMESTAMP" \
    --arg proj "$PROJECT" \
    '{session_id: $sid, started: $ts, project: $proj, label: "", changes: []}' > "$MANIFEST"
fi

# Append the change entry
TEMP=$(mktemp)
jq \
  --arg file "$FILE_PATH" \
  --argjson line "$LINE" \
  --arg tool "$TOOL_NAME" \
  --arg ts "$TIMESTAMP" \
  '.changes += [{file: $file, line: $line, tool: $tool, timestamp: $ts}]' \
  "$MANIFEST" > "$TEMP" && mv "$TEMP" "$MANIFEST"

# Update latest symlink
ln -sf "$MANIFEST" "$CHANGES_DIR/latest.json"

exit 0
