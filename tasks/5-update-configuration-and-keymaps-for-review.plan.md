---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: update configuration and keymaps for review commands
goal: ""
id: 5
uuid: 409b88c6-22c0-43f9-97ec-ff6a12b9b0df
generatedBy: agent
status: done
priority: medium
dependencies:
  - 4
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "4": 0b764a53-420b-410c-8e39-5e5688e97542
planGeneratedAt: 2026-01-16T07:11:45.679Z
promptsGeneratedAt: 2026-01-16T07:11:45.679Z
createdAt: 2026-01-15T00:28:09.548Z
updatedAt: 2026-01-16T07:24:37.377Z
tasks:
  - title: Add review keymaps to view group
    done: true
    description: Add keymaps for review_mark_file, review_mark_all, and
      review_clear_file to the view keymap group in lua/diffview/config.lua
  - title: Add review keymaps to file_panel group
    done: true
    description: Add the same three keymaps to the file_panel keymap group in
      lua/diffview/config.lua
  - title: Update doc/diffview.txt with keymap documentation
    done: true
    description: Add a summary of default review keymaps to the review configuration
      section in doc/diffview.txt
  - title: Update USAGE.md with marking files section
    done: true
    description: Add a new subsection documenting the mark/clear keymaps to the PR
      review workflow in USAGE.md
  - title: Run tests to verify no regressions
    done: true
    description: Execute make test to ensure all existing tests pass
changedFiles:
  - .rmfilter/config/rmplan.yml
  - AGENTS.md
  - CLAUDE.md
  - README.md
  - USAGE.md
  - doc/diffview.txt
  - doc/diffview_defaults.txt
  - lua/diffview/actions.lua
  - lua/diffview/config.lua
  - lua/diffview/hl.lua
  - lua/diffview/init.lua
  - lua/diffview/review.lua
  - lua/diffview/review_store.lua
  - lua/diffview/scene/views/diff/diff_view.lua
  - lua/diffview/scene/views/diff/file_panel.lua
  - lua/diffview/scene/views/diff/listeners.lua
  - lua/diffview/scene/views/diff/render.lua
  - lua/diffview/tests/functional/git_adapter_spec.lua
  - lua/diffview/tests/functional/render_review_indicator_spec.lua
  - lua/diffview/tests/functional/review_actions_spec.lua
  - lua/diffview/tests/functional/review_api_spec.lua
  - lua/diffview/tests/functional/review_filter_spec.lua
  - lua/diffview/tests/functional/review_navigation_spec.lua
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/tests/functional/since_review_diff_spec.lua
  - lua/diffview/ui/models/file_tree/file_tree.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

Here we want to add configuration for defaults and new key maps for the review commands.

## Research

### Overview

This plan addresses adding keymaps for review actions that currently exist but lack default keybindings, and potentially adding new configuration options to customize review behavior.

### Current State Analysis

#### Review Actions (lua/diffview/actions.lua:635-643)

The following review-related actions exist:

| Action | Has Keymap | Current Binding |
|--------|-----------|-----------------|
| `review_mark_file` | **NO** | - |
| `review_mark_all` | **NO** | - |
| `review_clear_file` | **NO** | - |
| `review_next_pending` | Yes | `]r` |
| `review_prev_pending` | Yes | `[r` |
| `review_next_unreviewed` | Yes | `]R` |
| `review_prev_unreviewed` | Yes | `[R` |
| `review_toggle_filter` | Yes | `<leader>rf` |
| `review_toggle_since_review` | Yes | `<leader>rs` |

**Three actions need default keymaps: `review_mark_file`, `review_mark_all`, `review_clear_file`**

#### Current Review Configuration (lua/diffview/config.lua:114-122)

```lua
review = {
  enabled = true,
  cache_dir = nil, -- Falls back to ~/.cache/diffview.nvim/reviews/
  symbols = {
    unreviewed = " ",  -- Blank space (reserved column)
    reviewed = "●",    -- Filled circle
    changed = "◐",     -- Half-filled circle
  },
}
```

#### Where Keymaps Are Defined

Keymaps for review actions need to be added to **two locations** in lua/diffview/config.lua:

1. **`view` keymap group** (lines 131-163): Active in diff buffers when inside a Diffview tab
2. **`file_panel` keymap group** (lines 185-235): Active in the file panel

The existing review keymaps (`]r`, `[r`, etc.) are duplicated in both groups, so the new keymaps should follow the same pattern.

#### Keymap Format

Keymaps use this structure (as seen in existing entries):
```lua
{ "n", "<key>", actions.action_name, { desc = "Description" } }
```

#### Action Implementations (lua/diffview/scene/views/diff/listeners.lua:333-362)

The review actions are implemented as event listeners:
- `review_mark_file`: Gets current file from cursor, calls `review.mark_file_reviewed(view, file)`
- `review_mark_all`: Calls `review.mark_all_reviewed(view)`
- `review_clear_file`: Gets current file from cursor, calls `review.clear_file_review(view, file)`

### Existing Documentation

#### In doc/diffview.txt

- Review configuration documented at lines 684-732 (`*diffview-config-review*`)
- Review actions documented at lines 1196-1215 (`*diffview-actions-review_*`)
- Keymaps section at lines 841-899 (`*diffview-config-keymaps*`)

#### In USAGE.md

- Comprehensive PR review workflow guide (lines 1-160)
- Documents navigation keymaps (`]r`, `[r`, `]R`, `[R`) at lines 84-104
- Documents filter toggle (`<leader>rf`) at lines 106-124
- Documents since-review mode (`<leader>rs`) at lines 125-156

### Key Findings

**Product & User Story**
- Users reviewing PRs need a way to mark files as reviewed without having to look up the action name
- The review_mark_file action is documented but lacks a default keymap, making it less discoverable
- Three useful actions (`review_mark_file`, `review_mark_all`, `review_clear_file`) exist without keymaps

**Design & UX Approach**
- Keymaps should follow existing conventions:
  - Review keymaps use `<leader>r` prefix
  - Navigation uses `]r`/`[r` pattern
- Suggested keymaps (following the `<leader>r` prefix pattern):
  - `<leader>rm` - Mark file as reviewed (m for "mark")
  - `<leader>rM` - Mark all files as reviewed (capital M for "all")
  - `<leader>rc` - Clear file review status (c for "clear")

**Technical Plan & Risks**
- Low risk: Only adding new default keymaps
- Changes required in lua/diffview/config.lua (add to both `view` and `file_panel`)
- Documentation updates needed in doc/diffview.txt and USAGE.md
- No new configuration options identified as necessary (existing config is comprehensive)

**Pragmatic Effort Estimate**
- Small scope: Adding 6 keymap entries (3 in each of 2 groups) and documentation updates

### Files to Modify

1. **lua/diffview/config.lua**: Add keymaps to `view` and `file_panel` groups
2. **doc/diffview.txt**: Document the new keymaps in the keymaps section
3. **USAGE.md**: Add keybinding information for mark/clear actions

### Acceptance Criteria

- [ ] `review_mark_file` has a default keymap in both `view` and `file_panel`
- [ ] `review_mark_all` has a default keymap in both `view` and `file_panel`
- [ ] `review_clear_file` has a default keymap in both `view` and `file_panel`
- [ ] doc/diffview.txt documents the new keymaps
- [ ] USAGE.md documents the new keymaps in the PR review workflow section
- [ ] All existing tests pass (`make test`)

### Dependencies & Constraints

- **Dependencies**: Depends on plan 4 (review feature implementation) being complete
- **Technical Constraints**: Keymaps must not conflict with existing default keymaps

## Implementation Guide

### Step 1: Add Keymaps to `view` Group

Edit lua/diffview/config.lua and add the following entries after the existing review keymaps (after line 151, which has `review_toggle_since_review`):

```lua
{ "n", "<leader>rm", actions.review_mark_file,   { desc = "Mark the current file as reviewed" } },
{ "n", "<leader>rM", actions.review_mark_all,    { desc = "Mark all files as reviewed" } },
{ "n", "<leader>rc", actions.review_clear_file,  { desc = "Clear review status for the current file" } },
```

Insert these after the `review_toggle_since_review` line but before the conflict resolution keymaps (the `<leader>co` line).

### Step 2: Add Keymaps to `file_panel` Group

Add the same keymaps to the `file_panel` group in lua/diffview/config.lua. Insert after line 228 (which has `review_toggle_since_review`), before line 229 (which has `g?`):

```lua
{ "n", "<leader>rm", actions.review_mark_file,   { desc = "Mark the current file as reviewed" } },
{ "n", "<leader>rM", actions.review_mark_all,    { desc = "Mark all files as reviewed" } },
{ "n", "<leader>rc", actions.review_clear_file,  { desc = "Clear review status for the current file" } },
```

### Step 3: Update doc/diffview.txt

Add documentation for the new keymaps. The keymaps section (around line 841) should include a note about the review keymaps. Since the defaults are documented by reference to the code, we should verify the existing action documentation is sufficient.

The actions `review_mark_file`, `review_mark_all`, and `review_clear_file` are already documented at lines 1196-1215. No changes needed to action documentation.

However, consider adding a summary of default keymaps for review actions in the review configuration section (around line 732) after the example:

```
        Default Review Keymaps: ~
            Keymaps for review actions are available in both the diff view
            and file panel contexts.

            `]r` / `[r`      Jump to next/previous file pending review
            `]R` / `[R`      Jump to next/previous unreviewed file
            `<leader>rf`     Toggle review filter (show only pending)
            `<leader>rs`     Toggle since-review diff mode
            `<leader>rm`     Mark current file as reviewed
            `<leader>rM`     Mark all files as reviewed
            `<leader>rc`     Clear review status for current file
```

### Step 4: Update USAGE.md

Add keybinding documentation to the "Review a PR" section. After the "Viewing Only Changes Since Last Review" subsection (around line 157), add a new subsection:

```markdown
### Marking Files as Reviewed

As you work through a PR, you can mark files as reviewed to track your progress:

- `<leader>rm` - Mark the current file as reviewed
- `<leader>rM` - Mark all files as reviewed
- `<leader>rc` - Clear the review status for the current file

When you mark a file as reviewed, the plugin records the file's current blob hash.
If the file changes later (e.g., after the author pushes updates), it will show
as "changed" (◐) instead of "reviewed" (●), indicating you need to re-review it.

The review state persists across Neovim sessions, stored in
`~/.cache/diffview.nvim/reviews/` by default.
```

### Step 5: Run Tests

Execute `make test` to ensure all existing tests pass and no regressions were introduced.

### Manual Testing Steps

1. Open a diff view: `:DiffviewOpen`
2. Navigate to a file in the file panel
3. Press `<leader>rm` to mark the file as reviewed
4. Verify the review symbol changes from unreviewed to reviewed (●)
5. Press `<leader>rc` to clear the review
6. Verify the symbol changes back to unreviewed
7. Press `<leader>rM` to mark all files as reviewed
8. Verify all files show as reviewed
9. Close and reopen diffview, verify review state persisted
10. Test the same keymaps from the diff buffer (not file panel)
11. Press `g?` to open help panel and verify new keymaps appear

## Current Progress
### Current State
- All tasks complete, plan marked as done

### Completed (So Far)
- Added keymaps `<leader>rm`, `<leader>rM`, `<leader>rc` to view group in config.lua
- Added keymaps `<leader>rm`, `<leader>rM`, `<leader>rc` to file_panel group in config.lua
- Added Default Review Keymaps summary to doc/diffview.txt (after review config example)
- Added "Marking Files as Reviewed" section to USAGE.md
- Added keymaps to doc/diffview_defaults.txt (both view and file_panel sections)
- Added keymaps to README.md example configuration (both view and file_panel sections)
- All 269 tests pass

### Remaining
- None

### Next Iteration Guidance
- None - plan complete

### Decisions / Changes
- Followed suggested keymap conventions: `<leader>rm` (mark), `<leader>rM` (mark all), `<leader>rc` (clear)
- Code review identified doc/diffview_defaults.txt and README.md also needed updating to stay in sync

### Risks / Blockers
- None
