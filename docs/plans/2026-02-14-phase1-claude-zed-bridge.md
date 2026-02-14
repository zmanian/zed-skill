# Phase 1: Claude Code <-> Zed Bridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a seamless review workflow where Claude Code edits in an external terminal are easily found, navigated, and reviewed in Zed.

**Architecture:** A PostToolUse hook in Claude Code writes a per-session change manifest to disk. A Zed task reads the manifest and opens all changed files at the right lines. Git review keybindings let you cycle through diffs, stage/revert per hunk.

**Tech Stack:** Bash (hook script), jq (JSON processing), Zed config (JSON)

---

### Task 1: Create the PostToolUse Hook Script

**Files:**
- Create: `hooks/post-tool-use.sh`

**Step 1: Write the hook script**

```bash
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
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Skip if missing required fields
if [ "$FILE_PATH" = "null" ] || [ -z "$FILE_PATH" ]; then
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
  jq -n \
    --arg sid "$SESSION_ID" \
    --arg ts "$TIMESTAMP" \
    '{session_id: $sid, started: $ts, changes: []}' > "$MANIFEST"
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
```

**Step 2: Make it executable**

Run: `chmod +x hooks/post-tool-use.sh`

**Step 3: Test the hook with sample Edit input**

Run:
```bash
echo '{"session_id":"test123","tool_name":"Edit","tool_input":{"file_path":"/tmp/test-hook.txt","old_string":"hello","new_string":"world"},"tool_response":{"success":true}}' | bash hooks/post-tool-use.sh
```

Create a test file first: `echo "hello world" > /tmp/test-hook.txt`

Expected: `~/.claude/changes/test123.json` exists with one change entry, `latest.json` symlink points to it.

**Step 4: Test with sample Write input**

Run:
```bash
echo '{"session_id":"test123","tool_name":"Write","tool_input":{"file_path":"/tmp/test-hook-new.txt","content":"new file"},"tool_response":{"success":true}}' | bash hooks/post-tool-use.sh
```

Expected: `test123.json` now has two entries (accumulated).

**Step 5: Test with missing file_path (should be a no-op)**

Run:
```bash
echo '{"session_id":"test123","tool_name":"Edit","tool_input":{},"tool_response":{"success":true}}' | bash hooks/post-tool-use.sh
```

Expected: Exit 0, no changes to manifest.

**Step 6: Clean up test artifacts and commit**

Run:
```bash
rm -f /tmp/test-hook.txt /tmp/test-hook-new.txt
rm -rf ~/.claude/changes/test123.json
git add hooks/post-tool-use.sh
git commit -m "feat: add PostToolUse hook for change tracking"
```

---

### Task 2: Create the Zed Review Task

**Files:**
- Create: `examples/tasks.json`

**Step 1: Write the review task**

```json
[
  {
    "label": "Review Claude Changes",
    "command": "bash",
    "args": [
      "-c",
      "MANIFEST=\"$HOME/.claude/changes/latest.json\"; if [ ! -f \"$MANIFEST\" ] || [ ! -s \"$MANIFEST\" ]; then echo 'No Claude changes found.'; exit 0; fi; FILES=$(jq -r '[.changes[] | .file + \":\" + (.line | tostring)] | unique | .[]' \"$MANIFEST\"); if [ -z \"$FILES\" ]; then echo 'No files in manifest.'; exit 0; fi; echo \"Opening $(echo \"$FILES\" | wc -l | tr -d ' ') changed files...\"; echo $FILES | xargs zed"
    ],
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "no_focus",
    "hide": "on_success"
  },
  {
    "label": "Clear Claude Change Manifest",
    "command": "bash",
    "args": [
      "-c",
      "MANIFEST=\"$HOME/.claude/changes/latest.json\"; if [ -L \"$MANIFEST\" ]; then rm -f \"$(readlink \"$MANIFEST\")\" \"$MANIFEST\"; echo 'Manifest cleared.'; else echo 'No manifest found.'; fi"
    ],
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "no_focus",
    "hide": "on_success"
  }
]
```

**Step 2: Validate JSON syntax**

Run: `python3 -c "import json; json.load(open('examples/tasks.json'))" && echo "Valid JSON"`
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add examples/tasks.json
git commit -m "feat: add Zed tasks for reviewing Claude changes"
```

---

### Task 3: Create Git Review Keybindings

**Files:**
- Create: `examples/keymap.json`

**Step 1: Write the review keybindings**

These are macOS keybindings for the Claude change review workflow. They avoid conflicting with Zed defaults.

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-shift-r": "git_panel::ToggleFocus",
      "ctrl-shift-d": "git::Diff"
    }
  },
  {
    "context": "Editor",
    "bindings": {
      "alt-]": "editor::GoToHunk",
      "alt-[": "editor::GoToPreviousHunk",
      "alt-\\": "editor::ExpandAllDiffHunks",
      "alt-'": "editor::ToggleSelectedDiffHunks"
    }
  },
  {
    "context": "GitPanel",
    "bindings": {
      "cmd-shift-o": "git::OpenModifiedFiles"
    }
  }
]
```

**Step 2: Validate JSON syntax**

Run: `python3 -c "import json; json.load(open('examples/keymap.json'))" && echo "Valid JSON"`
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add examples/keymap.json
git commit -m "feat: add git review keybindings for change review workflow"
```

---

### Task 4: Create Recommended Settings

**Files:**
- Create: `examples/settings.json`

**Step 1: Write recommended settings for the review workflow**

```json
{
  "git_panel": {
    "button": true,
    "dock": "right",
    "default_width": 320,
    "status_style": "icon",
    "sort_by_path": false,
    "collapse_untracked_diff": false,
    "tree_view": false
  },
  "git": {
    "git_gutter": "tracked_files",
    "inline_blame": {
      "enabled": true,
      "delay_ms": 600,
      "show_commit_summary": true
    },
    "hunk_style": "staged_hollow"
  }
}
```

**Step 2: Validate JSON syntax**

Run: `python3 -c "import json; json.load(open('examples/settings.json'))" && echo "Valid JSON"`
Expected: `Valid JSON`

**Step 3: Commit**

```bash
git add examples/settings.json
git commit -m "feat: add recommended settings for review workflow"
```

---

### Task 5: Add Hook Installation Docs to SKILL.md

**Files:**
- Modify: `SKILL.md`

**Step 1: Add a new section after the "Gotchas" section**

Add the following section to the end of SKILL.md:

```markdown
---

## Claude Code Integration: Change Review Workflow

This workflow bridges Claude Code (running in Warp, Ghostty, or any external terminal) with Zed for seamless change review.

### How It Works

1. A PostToolUse hook in Claude Code records every file edit to a session manifest
2. A Zed task reads the manifest and opens all changed files at the right lines
3. Git review keybindings let you cycle through diffs, stage/revert per hunk

### Setup

**Step 1: Install the hook**

Copy the hook script to a permanent location:

```bash
mkdir -p ~/.claude/hooks
cp hooks/post-tool-use.sh ~/.claude/hooks/post-tool-use.sh
chmod +x ~/.claude/hooks/post-tool-use.sh
```

**Step 2: Configure Claude Code**

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/post-tool-use.sh"
          }
        ]
      }
    ]
  }
}
```

**Step 3: Add the Zed tasks**

Merge the contents of `examples/tasks.json` into your global Zed tasks file:
- macOS: `~/Library/Application Support/Zed/tasks.json`
- Linux: `~/.config/zed/tasks.json`

**Step 4: Add review keybindings (optional)**

Merge `examples/keymap.json` into your Zed keymap:
- macOS: `~/Library/Application Support/Zed/keymap.json`
- Linux: `~/.config/zed/keymap.json`

**Step 5: Configure git panel (optional)**

Merge `examples/settings.json` into your Zed settings to dock the git panel on the right for a review-friendly layout.

### Usage

1. Run Claude Code in your terminal -- it edits files as usual
2. Switch to Zed
3. Run the **"Review Claude Changes"** task from the command palette (`cmd-shift-p` > "task: spawn" > "Review Claude Changes")
4. All files Claude edited open at the relevant lines
5. Use `alt-]` / `alt-[` to jump between diff hunks
6. Use `alt-\` to expand all diffs inline
7. Use the git panel to stage/revert changes
8. When done reviewing, run **"Clear Claude Change Manifest"** to reset

### Change Manifest

Changes accumulate per Claude Code session at `~/.claude/changes/<session-id>.json`. A symlink at `~/.claude/changes/latest.json` always points to the current session.

```json
{
  "session_id": "abc123",
  "started": "2026-02-14T10:30:00Z",
  "changes": [
    {"file": "/path/to/file.rs", "line": 42, "tool": "Edit", "timestamp": "..."},
    {"file": "/path/to/new.rs", "line": 1, "tool": "Write", "timestamp": "..."}
  ]
}
```
```

**Step 2: Verify the full SKILL.md is valid markdown**

Run: `wc -l SKILL.md` (should be significantly longer than before)

**Step 3: Commit**

```bash
git add SKILL.md
git commit -m "docs: add Claude Code integration and review workflow to skill"
```

---

### Task 6: Update SKILL.md with Git Panel Reference

**Files:**
- Modify: `SKILL.md`

**Step 1: Add git panel actions to the Common Actions Reference section**

After the Terminal actions table, add:

```markdown
### Git
| Action | Description |
|--------|-------------|
| `git_panel::ToggleFocus` | Toggle/focus git panel |
| `git::Diff` | Open project diff view |
| `git::OpenModifiedFiles` | Open all modified files |
| `git::StageAndNext` | Stage current hunk, advance to next |
| `git::UnstageAndNext` | Unstage current hunk, advance to next |
| `git::ToggleStaged` | Toggle staged state |
| `git::Commit` | Commit staged changes |
| `git::GenerateCommitMessage` | AI-generated commit message |
| `git::Fetch` | Fetch from remote |
| `git::Push` | Push to remote |
| `git::Pull` | Pull from remote |
| `git::Restore` | Restore/undo changes |
| `editor::GoToHunk` | Navigate to next diff hunk |
| `editor::GoToPreviousHunk` | Navigate to previous diff hunk |
| `editor::ExpandAllDiffHunks` | Expand all hunks inline |
| `editor::ToggleSelectedDiffHunks` | Toggle diff for selected hunks |
```

**Step 2: Add git settings reference**

After the Settings section's existing content, add a `### Git Settings` subsection with the git and git_panel settings from `examples/settings.json`, with comments explaining each option.

**Step 3: Commit**

```bash
git add SKILL.md
git commit -m "docs: add git panel actions and settings reference"
```

---

### Task 7: End-to-End Integration Test

**Step 1: Verify hook runs correctly**

Run:
```bash
echo "test line" > /tmp/e2e-test.txt
echo '{"session_id":"e2e-test","tool_name":"Edit","tool_input":{"file_path":"/tmp/e2e-test.txt","old_string":"test line","new_string":"changed line"},"tool_response":{"success":true}}' | bash hooks/post-tool-use.sh
cat ~/.claude/changes/e2e-test.json
```

Expected: JSON with one change entry, file `/tmp/e2e-test.txt`, line 1, tool "Edit".

**Step 2: Verify manifest accumulation**

Run:
```bash
echo '{"session_id":"e2e-test","tool_name":"Write","tool_input":{"file_path":"/tmp/e2e-test-2.txt","content":"new file"},"tool_response":{"success":true}}' | bash hooks/post-tool-use.sh
jq '.changes | length' ~/.claude/changes/e2e-test.json
```

Expected: `2`

**Step 3: Verify latest symlink**

Run: `readlink ~/.claude/changes/latest.json`
Expected: path ending in `e2e-test.json`

**Step 4: Verify Zed task command works**

Run:
```bash
MANIFEST="$HOME/.claude/changes/latest.json"
jq -r '[.changes[] | .file + ":" + (.line | tostring)] | unique | .[]' "$MANIFEST"
```

Expected: Two lines with file:line pairs.

**Step 5: Clean up**

Run:
```bash
rm -f /tmp/e2e-test.txt /tmp/e2e-test-2.txt
rm -f ~/.claude/changes/e2e-test.json
# Only remove latest.json if it points to our test
[ "$(readlink ~/.claude/changes/latest.json)" = "$HOME/.claude/changes/e2e-test.json" ] && rm -f ~/.claude/changes/latest.json
```

**Step 6: Final push**

```bash
git push
```

---

## Future Phases (not in this plan)

- **Phase 2:** AI/MCP/ACP integration sections in SKILL.md
- **Phase 3:** Git + LSP configuration sections
- **Phase 4:** Snippets, debugging, layout, remote dev sections
