# Zed Skill Development Design

## Goal

Make the workflow of running Claude Code in an external terminal (Warp/Ghostty) while reviewing changes in Zed seamless. Also expand the skill to cover Zed features currently missing (AI/MCP/ACP, git, LSP, snippets, debugging, remote dev).

## Architecture

```
Claude Code (Warp/Ghostty)
    |
    +-- PostToolUse hook (Edit/Write tools)
    |       |
    |       v
    |   ~/.claude/changes/<session-id>.json  (change manifest)
    |   ~/.claude/changes/latest.json        (symlink to current)
    |
    +-------------------------------------------+
                                                v
                                    Zed (watching project)
                                      +-- "Review Claude Changes" task
                                      |     reads manifest -> opens files at lines
                                      +-- Git panel review keybindings
                                      |     cycle modified files, view diffs, stage/revert
                                      +-- Workspace layout
                                            git panel visible, optimized for review
```

The hook is write-only, the task is read-only. No running server, no daemon. A JSON file on disk is the coordination point.

## Components

### 1. Claude Code PostToolUse Hook

A shell script that fires after `Edit` and `Write` tool calls.

**Behavior:**
- Receives tool call JSON on stdin
- Checks if tool is `Edit` or `Write`
- Extracts `file_path` and line number (for Edit, from the old_string match location)
- Appends an entry to `~/.claude/changes/<session-id>.json`
- Maintains a symlink `~/.claude/changes/latest.json` -> current session file

**Location:** `hooks/post-tool-use.sh` in this repo. User configures it in `.claude/settings.json`.

### 2. Change Manifest Format

```json
{
  "session_id": "abc123",
  "started": "2026-02-14T10:30:00Z",
  "changes": [
    {
      "file": "/Users/zakimanian/project/src/lib.rs",
      "line": 42,
      "tool": "Edit",
      "timestamp": "2026-02-14T10:31:15Z"
    },
    {
      "file": "/Users/zakimanian/project/src/main.rs",
      "line": 1,
      "tool": "Write",
      "timestamp": "2026-02-14T10:31:20Z"
    }
  ]
}
```

Changes accumulate per session so the user can review at their own pace.

### 3. Zed Task -- "Review Claude Changes"

A Zed task that:
1. Reads `~/.claude/changes/latest.json`
2. Extracts unique file:line pairs
3. Runs `zed file1:line1 file2:line2 ...` to open them all

Defined in global `tasks.json` or per-project `.zed/tasks.json`.

### 4. Git Review Keybindings

Keybindings optimized for reviewing external changes:
- Trigger the review task (open all Claude-changed files)
- Cycle through modified files in the git panel
- Toggle inline diff view
- Stage/revert the current file
- Jump to next/previous hunk

### 5. Workspace Layout

Settings that keep the git panel visible on the right dock during review, so modified files are always visible alongside the editor.

## Repo Structure

```
zed-skill/
  SKILL.md                          # Main skill (updated)
  hooks/
    post-tool-use.sh                # Claude Code hook script
  examples/
    keymap.json                     # Review workflow keybindings
    tasks.json                      # Review task definitions
    settings.json                   # Recommended layout settings
  docs/
    plans/
      2026-02-14-zed-skill-development-design.md  # This file
```

## Development Phases

### Phase 1: Claude Code <-> Zed Bridge
- Build the PostToolUse hook script
- Define the change manifest format
- Create the Zed "Review Claude Changes" task
- Add git review keybindings to the skill
- Add workspace layout recommendations

### Phase 2: AI/MCP/ACP Integration
- MCP server configuration in settings.json
- ACP agent setup and management
- Assistant panel configuration (model selection, providers)
- Inline assist workflows

### Phase 3: Git + LSP Configuration
- Git panel usage and configuration
- Staging/unstaging workflows, branch management
- Per-language LSP settings
- initialization_options, semantic tokens
- Language-specific examples (Rust, TypeScript, Python, Solidity)

### Phase 4: Snippets + Debugging + Layout + Remote
- Snippet extension setup and language-specific snippets
- DAP configuration, launch configs, Rust/Python debugging
- Dock and panel configuration
- SSH remoting and remote MCP servers

## Non-Goals

- Vim mode bindings (user doesn't use vim mode)
- Zed extension development guide (niche, not needed)
- Collaboration/channels documentation (not a current need)
- Running an MCP server daemon for coordination (overkill)
