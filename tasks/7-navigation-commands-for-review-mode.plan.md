---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Navigation commands for review mode
goal: ""
id: 7
uuid: 9ce60301-7529-43d4-a46d-27c75a43f4d8
generatedBy: agent
status: done
priority: medium
dependencies:
  - 3
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "3": 2445aa72-8e05-43bf-afdb-3c1e4b508db8
planGeneratedAt: 2026-01-15T22:50:19.842Z
promptsGeneratedAt: 2026-01-15T22:50:19.842Z
createdAt: 2026-01-15T01:45:14.237Z
updatedAt: 2026-01-15T23:03:18.553Z
tasks:
  - title: Add action names to actions.lua
    done: true
    description: "Add four new action names to the action_names list in
      lua/diffview/actions.lua: review_next_pending, review_prev_pending,
      review_next_unreviewed, review_prev_unreviewed"
  - title: Implement navigation methods in DiffView
    done: true
    description: "Add helper function and four navigation methods to
      lua/diffview/scene/views/diff/diff_view.lua: next_pending_review_file,
      prev_pending_review_file, next_unreviewed_file, prev_unreviewed_file.
      Methods should filter files by review status, support count prefix, wrap
      around, and show position feedback."
  - title: Add event listeners
    done: true
    description: "Add four new listener entries to
      lua/diffview/scene/views/diff/listeners.lua that delegate to the DiffView
      navigation methods: review_next_pending, review_prev_pending,
      review_next_unreviewed, review_prev_unreviewed"
  - title: Add default keybindings
    done: true
    description: "Add keybindings to both view and file_panel sections in
      lua/diffview/config.lua: ]r/[r for pending review navigation, ]R/[R for
      unreviewed-only navigation"
  - title: Add tests for review navigation
    done: true
    description: "Create lua/diffview/tests/functional/review_navigation_spec.lua
      with tests covering: basic navigation for pending and unreviewed, wrapping
      behavior, count support, edge cases (no matches, review disabled), and
      position feedback"
  - title: Update documentation
    done: true
    description: Update doc/diffview.txt with new keybindings and actions. Update
      USAGE.md with Review Navigation section explaining the new commands.
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
  - lua/diffview/tests/functional/review_navigation_spec.lua
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

Implement navigation commands to quickly move between files based on their review state.

## Navigation Commands

### Jump to Next/Previous Unreviewed File
- Navigate to the next file that has not been marked as reviewed
- Navigate to the previous file that has not been marked as reviewed
- Should wrap around at the end/beginning of the file list

### Jump to Next/Previous Changed-Since-Review File
- Navigate to the next file that was previously reviewed but has changed since
- Navigate to the previous file that was previously reviewed but has changed since
- These files have a different status than "unreviewed" (see plan 3)

## Behavior Notes
- Navigation should select the file in the file panel and open it in the diff view
- Should follow existing diffview navigation patterns for consistency
- Consider what happens when there are no matching files (show message? stay in place?)

---

## Expected Behavior/Outcome

When review mode is enabled, users can navigate directly to files based on their review status:

1. **Next/Previous Pending Review** (`]r`/`[r`): Jump to files with status `"unreviewed"` OR `"changed"` - any file needing attention
2. **Next/Previous Unreviewed Only** (`]R`/`[R`): Jump to files with status `"unreviewed"` only (never marked as reviewed)

Navigation behavior:
- Commands work from both file panel and diff view windows
- Opens the target file in diff view and highlights it in the file panel
- Wraps around at list boundaries (like existing `next_file`/`prev_file`)
- Supports Vim count prefix (e.g., `3]r` jumps 3 unreviewed files forward)
- Shows informational message when no matching files exist

## Key Findings

### Product & User Story
- **User Story**: As a code reviewer using diffview.nvim, I want to quickly navigate between unreviewed files so I can efficiently work through a review without manually scanning the file list.
- **Additional Story**: When I've reviewed some files but the PR was updated, I want to quickly find files that changed since my last review.

### Design & UX Approach
- Follow existing navigation patterns like `next_conflict`/`prev_conflict` which use `[x` and `]x` keybindings
- Keybindings:
  - `]r` / `[r` - Next/previous file needing review (unreviewed OR changed)
  - `]R` / `[R` - Next/previous unreviewed file only (never reviewed)
- The lowercase version is for "any file I need to look at", uppercase is more specific
- Show echo message like conflict navigation: "Pending review [2/5]" or "Unreviewed [1/3]"
- When no matching files: show info message and stay in place

### Technical Plan & Risks
- **Low Risk**: Implementation follows well-established patterns in the codebase
- **Consideration**: Need to handle both list and tree view modes (use `ordered_file_list()`)
- **Consideration**: Performance is not a concern as file lists are typically small

### Pragmatic Effort Estimate
Small feature with clear patterns to follow. The existing `next_file`/`prev_file` and `next_conflict`/`prev_conflict` implementations provide excellent templates.

## Acceptance Criteria

- [ ] `]r` navigates to the next file needing review (unreviewed OR changed)
- [ ] `[r` navigates to the previous file needing review
- [ ] `]R` navigates to the next unreviewed-only file
- [ ] `[R` navigates to the previous unreviewed-only file
- [ ] Navigation wraps around at list boundaries
- [ ] Vim count prefix works (e.g., `2]r` skips 2 files)
- [ ] Echo message shows current position: "Pending review [N/M]" or "Unreviewed [N/M]"
- [ ] Info message shown when no matching files exist
- [ ] Commands work from both file panel and diff view buffers
- [ ] File is highlighted in panel and opened in diff view
- [ ] All new code paths are covered by tests

## Dependencies & Constraints

- **Dependencies**:
  - Relies on existing review state system (plan 3, already implemented)
  - Uses `review.get_file_status()` API to check file states
  - Uses `FilePanel:ordered_file_list()` for navigation order
- **Technical Constraints**:
  - Must handle both "list" and "tree" listing styles
  - Review must be enabled and view must have `review_state` initialized

## Implementation Notes

### Recommended Approach
1. Add new action names to `actions.lua` action_names list
2. Implement listener handlers in `listeners.lua` that call new `DiffView` methods
3. Add navigation methods to `DiffView` class that filter files by review status
4. Add default keybindings to `config.lua` in both `view` and `file_panel` sections
5. Add tests covering navigation, wrapping, count support, and edge cases

### Potential Gotchas
- Must check `view.review_state` exists before attempting to get file status
- File status requires blob hash lookup which uses `view.adapter:file_blob_hash()`
- The `ordered_file_list()` method respects the current listing style (list vs tree)

### Key Files to Modify
- `lua/diffview/actions.lua` - Add action names
- `lua/diffview/scene/views/diff/listeners.lua` - Add event handlers
- `lua/diffview/scene/views/diff/diff_view.lua` - Add navigation methods
- `lua/diffview/config.lua` - Add default keybindings
- `lua/diffview/tests/` - Add test coverage
- `doc/diffview.txt` - Document new keybindings and actions
- `USAGE.md` - Update usage guide with review navigation

---

## Research

### Overview
This plan implements navigation commands to jump between files based on their review status. The existing codebase has well-established patterns for file navigation and review state tracking that we can leverage.

### Review State System (Already Implemented)

**Location**: `lua/diffview/review.lua` and `lua/diffview/review_store.lua`

The review system tracks three file states:
- `"unreviewed"` - File has never been marked as reviewed
- `"reviewed"` - File was marked reviewed and blob hash matches current content
- `"changed"` - File was previously reviewed but content has changed since

**Key API** (`lua/diffview/review.lua:162-176`):
```lua
function M.get_file_status(view, file_entry)
  -- Returns "unreviewed"|"reviewed"|"changed"|nil
  local current_blob_hash = get_file_blob_hash(view, file_entry)
  return view.review_state:get_file_status(file_entry.path, current_blob_hash)
end
```

**Important checks**:
- Review must be enabled: `config.get_config().review.enabled`
- View must have review state: `view.review_state ~= nil`

### Existing Navigation Patterns

**Pattern 1: next_file/prev_file** (`lua/diffview/scene/views/diff/diff_view.lua:239-280`)

The existing file navigation uses:
1. `self.panel:next_file()` / `self.panel:prev_file()` to get the next/prev file
2. `self.panel:highlight_file(cur)` to move cursor in panel
3. `self:_set_file(cur)` to open the file in diff view

**FilePanel navigation** (`lua/diffview/scene/views/diff/file_panel.lua:216-242`):
```lua
function FilePanel:next_file()
  local files = self:ordered_file_list()  -- Gets files in display order
  local i = utils.vec_indexof(files, self.cur_file)
  if i ~= -1 then
    -- Uses vim.v.count1 for count support, modulo for wrapping
    self:set_cur_file(files[(i + vim.v.count1 - 1) % #files + 1])
    return self.cur_file
  end
end
```

**Pattern 2: next_conflict/prev_conflict** (`lua/diffview/actions.lua:176-238`)

The conflict navigation pattern shows how to:
1. Search through a list for matching items
2. Handle wrapping with modulo
3. Display position feedback: `"Conflict [%d/%d]"`
4. Support count prefix with `vim.v.count1`

### Action System Architecture

**Action Definition** (`lua/diffview/actions.lua:618-657`):
Actions are registered in the `action_names` list and automatically wrapped to emit events:
```lua
local action_names = {
  "next_entry",
  "prev_entry",
  "review_mark_file",
  -- ... add new actions here
}

for _, name in ipairs(action_names) do
  M[name] = function()
    require("diffview").emit(name)
  end
end
```

**Event Listeners** (`lua/diffview/scene/views/diff/listeners.lua`):
Listeners connect events to view methods:
```lua
return function(view)
  return {
    select_next_entry = function()
      view:next_file(true)
    end,
    review_mark_file = function()
      local file = view:infer_cur_file()
      if not file then return end
      review.mark_file_reviewed(view, file)
    end,
  }
end
```

### Keybinding Configuration

**Default keybindings** (`lua/diffview/config.lua:129-267`):

Keybindings are defined per-context (`view`, `file_panel`, etc.):
```lua
keymaps = {
  view = {
    { "n", "[x", actions.prev_conflict, { desc = "Jump to previous conflict" } },
    { "n", "]x", actions.next_conflict, { desc = "Jump to next conflict" } },
  },
  file_panel = {
    -- Same keybindings available in file panel
    { "n", "[x", actions.prev_conflict, { desc = "Go to the previous conflict" } },
    { "n", "]x", actions.next_conflict, { desc = "Go to the next conflict" } },
  },
}
```

### Utility Functions

**Messaging** (`lua/diffview/utils.lua:50-58`):
```lua
M.info(msg, schedule)  -- Info-level notification
M.warn(msg, schedule)  -- Warning-level notification
```

**Echo message** (used in `actions.lua:216`):
```lua
api.nvim_echo({{ ("Conflict [%d/%d]"):format(next_idx, #conflicts) }}, false, {})
```

**Vector utilities** (`lua/diffview/utils.lua`):
- `utils.vec_indexof(list, item)` - Find index of item in list
- `utils.vec_join(...)` - Concatenate vectors

### Test Patterns

Tests are located in `lua/diffview/tests/functional/` and use Plenary's Busted runner.

**Example structure** (from `review_actions_spec.lua`):
```lua
describe("review actions", function()
  local view, mock_file, files

  before_each(function()
    -- Setup mock objects
  end)

  after_each(function()
    -- Cleanup
  end)

  describe("review_mark_file action", function()
    it("should mark current file as reviewed", function()
      -- Test implementation
    end)
  end)
end)
```

### FileDict and File Iteration

**FileDict** (`lua/diffview/vcs/file_dict.lua`):
Contains three file lists and provides iteration:
```lua
-- Iterate all files
for _, file in view.files:iter() do
  -- file is a FileEntry
end

-- Get total count
view.files:len()
```

**ordered_file_list()** (`lua/diffview/scene/views/diff/file_panel.lua:183-203`):
Returns files in display order, handling both list and tree modes.

---

## Implementation Guide

### Step 1: Add Action Names

**File**: `lua/diffview/actions.lua`

Add four new action names to the `action_names` list (around line 618):
```lua
local action_names = {
  -- ... existing actions ...
  "review_next_pending",      -- unreviewed OR changed
  "review_prev_pending",      -- unreviewed OR changed
  "review_next_unreviewed",   -- unreviewed only
  "review_prev_unreviewed",   -- unreviewed only
}
```

This automatically creates the action functions that emit events.

### Step 2: Implement Navigation Methods in DiffView

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

Add a helper function and four navigation methods. The helper finds files matching a review status and navigates to them with wrapping support.

**Helper function** (add near other navigation methods around line 280):

The helper should:
1. Get the ordered file list from the panel
2. Filter files matching the target status using `review.get_file_status()`
3. Find the current position in the filtered list
4. Calculate the next position using modulo arithmetic (like `next_file`)
5. Use `vim.v.count1` for count support
6. Return the target file, its index, and total count of matching files

**Navigation methods**:

Add four public methods that:
1. Call `self:ensure_layout()` and `self:file_safeguard()` like existing methods
2. Check if `self.review_state` exists (return early if not)
3. Call the helper with the appropriate status filter
4. If a file is found:
   - Highlight it in the panel
   - Open it with `self:_set_file()`
   - Echo the position message
5. If no files match:
   - Show info message
   - Return nil

Reference the existing `next_file` method (line 239-257) for the structure.

### Step 3: Add Event Listeners

**File**: `lua/diffview/scene/views/diff/listeners.lua`

Add four new listener entries to the returned table (after the existing review actions around line 345):

```lua
review_next_pending = function()
  view:next_pending_review_file()
end,
review_prev_pending = function()
  view:prev_pending_review_file()
end,
review_next_unreviewed = function()
  view:next_unreviewed_file()
end,
review_prev_unreviewed = function()
  view:prev_unreviewed_file()
end,
```

These simply delegate to the DiffView methods added in Step 2.

### Step 4: Add Default Keybindings

**File**: `lua/diffview/config.lua`

Add keybindings to both `view` (line 131) and `file_panel` (line 179) sections:

In `view` section (around line 145, after conflict keybindings):
```lua
{ "n", "]r", actions.review_next_pending, { desc = "Jump to next file pending review" } },
{ "n", "[r", actions.review_prev_pending, { desc = "Jump to previous file pending review" } },
{ "n", "]R", actions.review_next_unreviewed, { desc = "Jump to next unreviewed file" } },
{ "n", "[R", actions.review_prev_unreviewed, { desc = "Jump to previous unreviewed file" } },
```

In `file_panel` section (around line 216, after conflict keybindings):
```lua
{ "n", "]r", actions.review_next_pending, { desc = "Jump to next file pending review" } },
{ "n", "[r", actions.review_prev_pending, { desc = "Jump to previous file pending review" } },
{ "n", "]R", actions.review_next_unreviewed, { desc = "Jump to next unreviewed file" } },
{ "n", "[R", actions.review_prev_unreviewed, { desc = "Jump to previous unreviewed file" } },
```

### Step 5: Add Tests

**File**: `lua/diffview/tests/functional/review_navigation_spec.lua` (new file)

Create comprehensive tests covering:

1. **Basic navigation for pending review** (`]r`/`[r`):
   - `next_pending_review_file` navigates to next unreviewed OR changed file
   - `prev_pending_review_file` navigates backward
   - Both statuses are included in the "pending" set

2. **Basic navigation for unreviewed only** (`]R`/`[R`):
   - `next_unreviewed_file` navigates to unreviewed files only
   - `prev_unreviewed_file` navigates backward
   - Does NOT include "changed" files

3. **Wrapping behavior**:
   - Navigation wraps from last to first file
   - Navigation wraps from first to last file

4. **Count support**:
   - Count prefix skips multiple files (mock `vim.v.count1`)

5. **Edge cases**:
   - No files match (returns nil, shows message)
   - Review disabled (graceful no-op)
   - Only one matching file (stays on same file)

6. **Position feedback**:
   - Verify echo message format "Pending review [N/M]" or "Unreviewed [N/M]"

Use existing test patterns from `review_actions_spec.lua` for mocking.

### Manual Testing Steps

1. Open diffview with multiple changed files: `:DiffviewOpen`
2. Mark some files as reviewed using the existing keybinding
3. Test `]r` jumps to next file needing review (unreviewed or changed)
4. Test `[r` jumps to previous file needing review
5. Test `]R` jumps to next unreviewed-only file
6. Test wrapping: when on last matching file, navigation goes to first
7. Test count: `2]r` skips two files
8. Test when all files reviewed: should show "No files pending review"
9. Edit a reviewed file externally, refresh, test `]r` finds the changed file
10. Test `]R` does NOT find the changed file (only unreviewed)
11. Test in both list view (`i` to toggle) and tree view

### Step 6: Update Documentation

**File**: `doc/diffview.txt`

Add the new keybindings to the keymaps documentation section. Look for the existing conflict navigation keybindings (`[x`, `]x`) and add the review navigation keybindings nearby:

```
]r                              Jump to next file pending review
[r                              Jump to previous file pending review
]R                              Jump to next unreviewed file
[R                              Jump to previous unreviewed file
```

Also add the new actions to the available actions section:
- `review_next_pending` - Jump to next file pending review (unreviewed or changed)
- `review_prev_pending` - Jump to previous file pending review
- `review_next_unreviewed` - Jump to next unreviewed file
- `review_prev_unreviewed` - Jump to previous unreviewed file

**File**: `USAGE.md`

Add a section under the existing review documentation explaining the navigation commands:

```markdown
### Review Navigation

When reviewing files, you can quickly navigate between files that need attention:

- `]r` / `[r` - Jump to next/previous file pending review (unreviewed or changed)
- `]R` / `[R` - Jump to next/previous unreviewed file only

These commands work from both the file panel and diff view windows. They support
Vim count prefixes (e.g., `2]r` skips two files) and wrap around at list boundaries.
```

### Why This Approach

1. **Consistency**: Follows exact same patterns as existing `next_file` and `next_conflict` commands
2. **Discoverability**: Uses conventional Vim `[` / `]` navigation with mnemonic keys (`r` for review)
3. **Complete feature**: Includes count support, wrapping, and feedback like existing navigation
4. **Maintainability**: Minimal new code, reuses existing utilities and patterns
5. **Testability**: Clear separation allows unit testing navigation logic

## Current Progress
### Current State
- All tasks completed: Navigation commands for review mode are fully implemented, tested, and documented

### Completed (So Far)
- Added four action names to `actions.lua`: `review_next_pending`, `review_prev_pending`, `review_next_unreviewed`, `review_prev_unreviewed`
- Implemented navigation methods in `diff_view.lua` with helper function `_navigate_review_file()`
- Added event listeners in `listeners.lua` delegating to DiffView methods
- Added default keybindings (`]r`/`[r` for pending, `]R`/`[R` for unreviewed-only) to both `view` and `file_panel` sections in `config.lua`
- Updated `doc/diffview_defaults.txt` with the new keybindings
- Created comprehensive test suite in `review_navigation_spec.lua` (26 tests)
- Updated `doc/diffview.txt` with new actions documentation (review_next_pending, review_prev_pending, review_next_unreviewed, review_prev_unreviewed)
- Added "Navigating Between Files Pending Review" section to `USAGE.md`

### Remaining
- None

### Next Iteration Guidance
- None - plan is complete

### Decisions / Changes
- Navigation methods follow the `next_conflict`/`prev_conflict` pattern for position feedback
- Helper function `_navigate_review_file()` centralizes navigation logic with delta and status_filter parameters
- "Pending review" includes both "unreviewed" AND "changed" files; "Unreviewed" is strictly unreviewed-only

### Risks / Blockers
- None
