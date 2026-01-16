---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: option to only show changes in a file since last marked reviewed
goal: ""
id: 4
uuid: 0b764a53-420b-410c-8e39-5e5688e97542
generatedBy: agent
status: in_progress
priority: medium
dependencies:
  - 7
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "7": 9ce60301-7529-43d4-a46d-27c75a43f4d8
planGeneratedAt: 2026-01-16T02:05:48.392Z
promptsGeneratedAt: 2026-01-16T02:05:48.392Z
createdAt: 2026-01-15T00:26:26.637Z
updatedAt: 2026-01-16T02:18:12.516Z
tasks:
  - title: Extend ReviewEntry to store commit hash
    done: true
    description: Add commit_hash field to ReviewEntry in review_store.lua. Update
      set_file_reviewed to accept and store commit_hash. Field should be
      optional for backward compatibility with existing review state files.
  - title: Update mark_file_reviewed to store commit hash
    done: true
    description: Modify mark_file_reviewed in review.lua to get current HEAD commit
      hash using adapter:head_rev() and pass it to set_file_reviewed. Also
      update mark_all_reviewed.
  - title: Add review_filter_enabled state to DiffView
    done: false
    description: Add review_filter_enabled boolean field to DiffView class in
      diff_view.lua. Initialize to false in DiffView:init(). Add
      toggle_review_filter method that toggles state and refreshes panel.
  - title: Add review_toggle_filter action and keybinding
    done: false
    description: Add review_toggle_filter to action_names in actions.lua. Add
      listener in listeners.lua that calls view:toggle_review_filter(). Add
      <leader>rf keybinding to both view and file_panel sections in config.lua.
  - title: Implement file panel filtering in FilePanel
    done: false
    description: Modify ordered_file_list() in file_panel.lua to filter files by
      review status when view.review_filter_enabled is true. Only include files
      with status unreviewed or changed. Also filter in update_components() to
      hide filtered files from tree view.
  - title: Hide empty directories in tree view when filter active
    done: false
    description: When review filter is active in tree view mode, modify component
      creation to skip directories where all children are filtered out. May
      require modifying FileTree or the component schema generation.
  - title: Update panel rendering to show filter state
    done: false
    description: "Modify render.lua to show filter indicator in panel header when
      filter is active (e.g., [Pending: 5/12]). Update section counts to show
      filtered vs total counts."
  - title: Handle edge cases for filter toggle
    done: false
    description: When filter is toggled on and current file is filtered out, move to
      first visible file. When all files are marked reviewed with filter on,
      auto-disable the filter. Show message when filter results in empty list.
  - title: Add since_review_mode state to DiffView
    done: false
    description: Add since_review_mode boolean field to DiffView class. Add
      toggle_since_review_mode method that toggles state and re-opens current
      file if it has changed status.
  - title: Add review_toggle_since_review action and keybinding
    done: false
    description: Add review_toggle_since_review to action_names in actions.lua. Add
      listener in listeners.lua. Add <leader>rs keybinding to both view and
      file_panel sections in config.lua.
  - title: Implement since-review diff mode file opening
    done: false
    description: Modify _set_file or add wrapper in diff_view.lua to use alternate
      left revision when since_review_mode is true for changed files. Create
      GitRev with stored commit_hash. Requires understanding use_entry
      implementation.
  - title: Add commit existence verification
    done: false
    description: Add verify_commit_exists helper method to DiffView that checks if
      stored commit hash still exists using git cat-file -e. Use this to
      gracefully fall back to full diff when commit is unavailable after
      force-push.
  - title: Add visual indicator for since-review mode
    done: false
    description: "When viewing a file in since-review mode, show visual indicator.
      Options: echo message when opening file, indicator in panel current file
      line, or status line indicator. Choose most consistent with existing
      patterns."
  - title: Add tests for file panel filtering
    done: false
    description: "Create review_filter_spec.lua with tests for: filter toggle
      behavior, filtered file list contents, navigation with filter active,
      cursor handling when file is filtered out, tree view filtering,
      auto-disable when all reviewed."
  - title: Add tests for since-review diff mode
    done: false
    description: "Create since_review_diff_spec.lua with tests for: mode toggle,
      correct revision used for diff, fallback when commit unavailable, mode
      indicator display, interaction with filter."
  - title: Update documentation
    done: false
    description: Update doc/diffview.txt with new keybindings and actions. Update
      USAGE.md with section explaining filter and since-review mode features.
      Add notes about commit availability after force-push.
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

When viewing a diff, there should be an option to have the diff view show only:
1. Files that have changed since they were last marked reviewed
2. Files that have not been reviewed yet

At the same time, we should be able to toggle the view itself, so that if there is a previous review, we only show changes since the change where the file was last marked reviewed.

---

## Expected Behavior/Outcome

This feature introduces two complementary capabilities for code reviewers:

### 1. File Panel Filtering by Review Status
Users can toggle a filter to show only files that need attention in the file panel:
- **Filter ON**: Only display files with status `"unreviewed"` or `"changed"`
- **Filter OFF**: Display all files (current behavior)
- Toggle should be clearly visible in the UI (e.g., indicator in panel header)

### 2. Per-File "Changes Since Review" Diff Mode
For files that have `"changed"` status (previously reviewed but modified), users can toggle the diff view to show:
- **Normal mode**: Full diff (current behavior) - comparing `left` and `right` revisions as specified
- **Since-review mode**: Only changes since the commit where the file was last marked reviewed

### States Defined
- **File Panel Filter State**: Boolean toggle affecting which files appear in the file panel
- **Per-File Diff Mode**: When viewing a "changed" file, ability to switch between full diff and since-review diff
- **Combined State**: Both can be active simultaneously (filtered list + since-review diffs)

## Key Findings

### Product & User Story
- **Primary User Story**: As a code reviewer who has already reviewed some files in a PR, when the PR is updated, I want to only see the files that have new changes so I can efficiently re-review without re-reading unchanged files.
- **Secondary User Story**: For files I previously reviewed that have new changes, I want to see only the delta since my last review, not the entire file diff from the branch base.

### Design & UX Approach
- **File Panel Filter Toggle**: A keybinding (e.g., `<leader>rf` or similar) to toggle filtering
- **Panel Header Indicator**: Show "(Pending: X/Y)" or similar when filter is active to indicate filtered state
- **Since-Review Diff Toggle**: A keybinding (e.g., `<leader>rs`) to toggle per-file diff mode when on a "changed" file
- **Visual Indicator**: When viewing since-review diff, show indicator (e.g., in status line or file header)

### Technical Plan & Risks
- **File Filtering**: Relatively straightforward - filter the `ordered_file_list()` or render conditionally in `render.lua`
- **Since-Review Diff**: More complex - requires storing the commit SHA at review time and computing a new diff with that as the left revision
- **Risk**: The current `ReviewEntry` only stores `blob_hash` and `reviewed_at`, not the commit SHA when reviewed. We need to extend this.
- **Risk**: If the commit where the file was reviewed has been rebased/amended, the stored commit may not exist. Need graceful fallback.

### Pragmatic Effort Estimate
Medium complexity. File panel filtering is straightforward. The since-review diff mode requires data model changes and careful handling of git edge cases.

## Acceptance Criteria

- [ ] Keybinding to toggle file panel filter showing only pending review files
- [ ] Panel header shows filter state indicator when active (e.g., "Pending: 5/12")
- [ ] Filtered panel respects current listing style (list and tree modes)
- [ ] Navigation commands still work correctly when filter is active
- [ ] Keybinding to toggle since-review diff mode for current file (when file is "changed")
- [ ] Since-review diff shows changes between reviewed commit and current state
- [ ] Visual indicator when viewing since-review diff mode
- [ ] Graceful handling when reviewed commit is unavailable (fall back to full diff)
- [ ] Review state stores commit SHA in addition to blob hash
- [ ] All new code paths are covered by tests

## Dependencies & Constraints

- **Dependencies**:
  - Relies on existing review state system (plan 3, completed)
  - Relies on navigation commands (plan 7, completed)
  - Uses `ReviewState` from `review_store.lua`
  - Uses VCS adapter's `rev_to_args()` and diff computation
- **Technical Constraints**:
  - Must work with both list and tree listing styles
  - Since-review diff only applicable to `"changed"` files
  - Git blob/commit may be garbage collected after force-push
  - Performance: filtering should be fast even with large file lists

## Implementation Notes

### Recommended Approach

**Part 1: Extend Review State Data Model**
1. Add `commit_hash` field to `ReviewEntry` in `review_store.lua`
2. Update `mark_file_reviewed` in `review.lua` to store current HEAD commit hash
3. Handle backward compatibility for existing review state files (missing `commit_hash`)

**Part 2: File Panel Filtering**
1. Add `review_filter_pending` boolean to `DiffView` state
2. Add action and keybinding for toggling the filter
3. Modify `ordered_file_list()` in `FilePanel` to optionally filter by review status
4. Update `render.lua` to show filter state and counts in header
5. Ensure navigation still works (already uses `ordered_file_list()`)

**Part 3: Since-Review Diff Mode**
1. Add `since_review_mode` boolean per file or view-level
2. Add action and keybinding for toggling
3. When enabled for a "changed" file, create alternate revisions:
   - Left: The commit where file was reviewed
   - Right: Current state (same as normal right rev)
4. Modify file opening to use alternate revisions when mode is active
5. Add visual indicator in diff view

### Potential Gotchas
- **Tree view rendering**: Filter needs to properly handle tree structure (hide directories with no visible children)
- **Cursor position**: When toggling filter, cursor may need to move to valid file
- **Commit availability**: Reviewed commit may be garbage collected after force-push; verify with `git cat-file -e`
- **Mixed states**: User could be viewing a file in since-review mode, toggle filter off, see file disappear - need thoughtful UX
- **Staged/conflicting files**: Consider if filtering applies to all sections or just working files

### Design Decisions (Resolved)
- **Since-review diff mode scope**: View-level toggle - once enabled, applies to all "changed" files as user navigates
- **Empty filter behavior**: Auto-disable filter when no pending files remain after marking files reviewed
- **Keybindings**: `<leader>rf` for review filter toggle, `<leader>rs` for since-review diff toggle
- **Tree view filtering**: Hide empty directories when all their children are filtered out

---

## Research

### Overview

This feature adds two complementary capabilities to the diffview.nvim review workflow:
1. **File panel filtering** - Show only files needing review attention (unreviewed or changed)
2. **Since-review diff mode** - For changed files, show only changes since the file was last reviewed

The existing review system provides the foundation but needs extension to store commit information.

### Current Review State System

**File**: `lua/diffview/review_store.lua`

The `ReviewEntry` structure currently stores:
```lua
---@class ReviewEntry
---@field blob_hash string Git blob hash of the file content when marked reviewed
---@field reviewed_at number Unix timestamp of when the file was reviewed
```

This allows detecting `"changed"` status by comparing stored blob hash against current blob hash, but doesn't preserve the commit context needed for a since-review diff.

**Determining File Status** (`review_store.lua:82-94`):
```lua
function ReviewState:get_file_status(path, current_blob_hash)
  local entry = self.files[path]
  if not entry then
    return "unreviewed"
  end
  if not current_blob_hash then
    return "reviewed"
  end
  if entry.blob_hash == current_blob_hash then
    return "reviewed"
  end
  return "changed"
end
```

### How Files Are Marked Reviewed

**File**: `lua/diffview/review.lua`

The `mark_file_reviewed` function (`review.lua:30-61`) stores the blob hash at HEAD:
```lua
local function get_file_blob_hash(view, file_entry)
  return view.adapter:file_blob_hash(file_entry.path, "HEAD")
end

function M.mark_file_reviewed(view, file_entry)
  local blob_hash = get_file_blob_hash(view, file_entry)
  view.review_state:set_file_reviewed(file_entry.path, blob_hash)
end
```

The current implementation uses `HEAD` as the revision for blob hash, but doesn't store the actual commit SHA. To enable since-review diffs, we need to also store this commit hash.

### Git Adapter Commit Operations

**File**: `lua/diffview/vcs/adapters/git/init.lua`

**Getting HEAD commit hash** (`head_rev()` method):
```lua
function GitAdapter:head_rev()
  local out = self:exec_sync({ "rev-parse", "HEAD" }, self.ctx.toplevel)
  return GitRev(RevType.COMMIT, out[1])
end
```

**Converting revisions to diff arguments** (`rev_to_args()`, line 1542-1572):
- `COMMIT..COMMIT` → `left_sha..right_sha`
- `COMMIT` vs `LOCAL` → `left_sha`
- Handles staging area comparisons

**File blob hash lookup** (`file_blob_hash()` method):
```lua
function GitAdapter:file_blob_hash(path, rev_arg)
  local out, code = self:exec_sync({
    "rev-parse", fmt("%s:%s", rev_arg or "HEAD", path)
  }, self.ctx.toplevel)
  if code == 0 then return vim.trim(out[1]) end
end
```

**Verifying commit exists** (`verify_rev_arg()` method):
Can be used to check if a stored commit still exists after rebases.

### File Panel Architecture

**File**: `lua/diffview/scene/views/diff/file_panel.lua`

**Current file list retrieval** (`ordered_file_list()`, line 183-203):
```lua
function FilePanel:ordered_file_list()
  if self.listing_style == "list" then
    local list = {}
    for _, file in self.files:iter() do
      list[#list + 1] = file
    end
    return list
  else
    -- Tree mode: get leaves from all three trees
    local nodes = utils.vec_join(
      self.files.conflicting_tree.root:leaves(),
      self.files.working_tree.root:leaves(),
      self.files.staged_tree.root:leaves()
    )
    return vim.tbl_map(function(node) return node.data end, nodes)
  end
end
```

This is the key extension point for filtering. We can either:
1. Filter here based on view state
2. Create a separate method `filtered_file_list()` that `ordered_file_list()` calls
3. Filter during component creation in `update_components()`

**Component structure** (`update_components()`, line 89-179):
The panel creates components from the three file lists (conflicting, working, staged). Filtering could happen at component creation time to completely hide filtered files from the render.

### Rendering Architecture

**File**: `lua/diffview/scene/views/diff/render.lua`

**Panel header rendering** (line 163-173):
```lua
comp:add_line(
  pl:truncate(pl:vim_fnamemodify(panel.adapter.ctx.toplevel, ":~"), width - 6),
  "DiffviewFilePanelRootPath"
)

if conf.show_help_hints and panel.help_mapping then
  comp:add_text("Help: ", "DiffviewFilePanelPath")
  comp:add_line(panel.help_mapping, "DiffviewFilePanelCounter")
end
```

This is where we'd add filter state indicator.

**Section rendering** (line 175-207):
Each section (Conflicts, Changes, Staged) is rendered with a count:
```lua
comp:add_text("Changes ", "DiffviewFilePanelTitle")
comp:add_text("(" .. #panel.files.working .. ")", "DiffviewFilePanelCounter")
```

With filtering, we'd want to show something like `(5/12)` or `(filtered: 5/12)`.

### DiffView File Opening

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

**Setting active file** (`_set_file()`, line 217-235):
```lua
DiffView._set_file = async.void(function(self, file)
  self.panel:render()
  self.panel:redraw()
  self.cur_layout:detach_files()
  await(self:use_entry(file))
end)
```

The `use_entry` method (inherited from StandardView) handles the actual file loading. For since-review mode, we'd need to either:
1. Modify the file entry's revisions before calling `use_entry`
2. Create a modified copy of the file entry
3. Add a view-level override for the left revision

### FileEntry and Revisions

**File**: `lua/diffview/scene/file_entry.lua`

Each `FileEntry` has a `revs` field containing the revisions for the diff:
```lua
---@class FileEntry
---@field revs RevMap -- { a: Rev, b: Rev, c?: Rev, d?: Rev }
```

For standard two-way diffs, `a` is left and `b` is right.

**Revision override for since-review mode**:
When a file has `"changed"` status and since-review mode is active, we'd create an alternate `Rev` for the left side using the stored review commit.

### Existing Navigation Commands

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

The navigation methods already use review status filtering (lines 636-701):
```lua
function DiffView:_navigate_review_file(delta, status_filter, label)
  local files = self.panel:ordered_file_list()
  local matching_files = {}
  for _, file in ipairs(files) do
    local status = review.get_file_status(self, file)
    if status_filter(status) then
      matching_files[#matching_files + 1] = file
    end
  end
  -- ... navigation logic
end
```

This pattern can be adapted for the panel filter toggle.

### Event System

**Global events** (from `DiffviewGlobal.emitter`):
- `review_file_marked` - When a file is marked reviewed
- `review_file_cleared` - When review is cleared for a file
- `review_all_cleared` - When all reviews cleared

The view subscribes to these to refresh the panel. Filter state changes should also trigger panel refresh.

### Action System

**File**: `lua/diffview/actions.lua`

Actions are defined in `action_names` list and automatically create event emitters:
```lua
local action_names = {
  "review_mark_file",
  "review_mark_all",
  "review_clear_file",
  "review_clear_all",
  -- ... add new actions here
}
```

New actions needed:
- `review_toggle_filter` - Toggle panel filtering
- `review_toggle_since_review` - Toggle since-review diff mode

### Configuration

**File**: `lua/diffview/config.lua`

Review configuration (line 114-122):
```lua
review = {
  enabled = true,
  cache_dir = nil,
  symbols = {
    unreviewed = " ",
    reviewed = "●",
    changed = "◐",
  },
},
```

May want to add:
- `filter_default` - Whether filter is on by default when opening diff view
- `since_review_default` - Whether since-review mode is on by default for changed files

### Git Edge Cases

**Commit availability after rebase/force-push**:
When a PR is force-pushed, the commit where a file was reviewed may be garbage collected. We need to:
1. Verify commit exists with `git cat-file -e <commit_hash>`
2. Fall back to full diff if commit is unavailable
3. Optionally show a warning message

**File renames**:
If a file is renamed after being reviewed, the stored path won't match. The current system doesn't track renames for review state. This is an edge case that may produce "unreviewed" status for the new path.

### Test Patterns

**File**: `lua/diffview/tests/functional/review_navigation_spec.lua`

Comprehensive test patterns exist for review navigation. Similar patterns can be used for:
- Filter toggle tests
- Filtered navigation tests
- Since-review diff mode tests

---

## Implementation Guide

### Phase 1: Extend Review State Data Model

**Goal**: Store commit hash alongside blob hash when marking files reviewed.

#### Step 1.1: Update ReviewEntry Type

**File**: `lua/diffview/review_store.lua`

Add `commit_hash` to the `ReviewEntry` type definition:
```lua
---@class ReviewEntry
---@field blob_hash string Git blob hash of the file content when marked reviewed
---@field reviewed_at number Unix timestamp of when the file was reviewed
---@field commit_hash? string Git commit hash when file was marked reviewed
```

The field is optional for backward compatibility with existing saved state.

#### Step 1.2: Update mark_file_reviewed to Store Commit Hash

**File**: `lua/diffview/review.lua`

Modify `mark_file_reviewed` to also get and store the current HEAD commit:
1. Add a helper function to get the current HEAD commit hash (use `adapter:head_rev()`)
2. Pass the commit hash to `set_file_reviewed`

Modify `ReviewState:set_file_reviewed` in `review_store.lua` to accept and store `commit_hash`:
```lua
function ReviewState:set_file_reviewed(path, blob_hash, commit_hash, skip_save)
  self.files[path] = {
    blob_hash = blob_hash,
    reviewed_at = os.time(),
    commit_hash = commit_hash,  -- may be nil for legacy compatibility
  }
```

#### Step 1.3: Handle Backward Compatibility

Files saved before this change won't have `commit_hash`. The code should:
1. Gracefully handle `nil` commit_hash in `ReviewEntry`
2. When `commit_hash` is nil, since-review diff mode should be unavailable (fall back to full diff)
3. Add migration note in documentation

### Phase 2: File Panel Filtering

**Goal**: Allow users to toggle the file panel to show only files needing review attention.

#### Step 2.1: Add Filter State to DiffView

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

Add a field to track filter state:
```lua
---@field review_filter_enabled boolean Whether to filter panel to pending review files
```

Initialize to `false` in `DiffView:init()`.

Add a method to toggle:
```lua
function DiffView:toggle_review_filter()
  self.review_filter_enabled = not self.review_filter_enabled
  self.panel:update_components()
  self.panel:render()
  self.panel:redraw()
  -- Handle cursor position if current file is filtered out
end
```

#### Step 2.2: Add Action and Keybinding

**File**: `lua/diffview/actions.lua`

Add action name: `"review_toggle_filter"`

**File**: `lua/diffview/scene/views/diff/listeners.lua`

Add listener:
```lua
review_toggle_filter = function()
  view:toggle_review_filter()
end,
```

**File**: `lua/diffview/config.lua`

Add keybinding to both `view` and `file_panel` sections:
```lua
{ "n", "<leader>rf", actions.review_toggle_filter, { desc = "Toggle review filter (show only pending)" } },
```

#### Step 2.3: Modify FilePanel to Support Filtering

**File**: `lua/diffview/scene/views/diff/file_panel.lua`

Option A: Filter in `ordered_file_list()`:
```lua
function FilePanel:ordered_file_list()
  local files = -- ... existing list building logic

  -- Apply review filter if enabled
  if self.view and self.view.review_filter_enabled then
    local filtered = {}
    for _, file in ipairs(files) do
      local status = review.get_file_status(self.view, file)
      if status == "unreviewed" or status == "changed" then
        filtered[#filtered + 1] = file
      end
    end
    return filtered
  end

  return files
end
```

Option B: Filter during component creation in `update_components()` for proper tree handling.

For tree view, we need to handle empty directories when all children are filtered. This is more complex and may require modifying the FileTree to support filtering.

**Recommended**: Start with Option A which works for both list and tree views without modifying tree structure. The tree will still show directory hierarchy but files won't be selectable via navigation. For a cleaner implementation, also filter in `update_components()`.

#### Step 2.4: Update Panel Rendering to Show Filter State

**File**: `lua/diffview/scene/views/diff/render.lua`

Add filter indicator to the panel header (after the root path):
```lua
-- After root path line
if view and view.review_filter_enabled then
  comp:add_text(" [Pending: ", "DiffviewFilePanelPath")
  local pending_count = -- count pending files
  local total_count = -- count total files
  comp:add_text(string.format("%d/%d", pending_count, total_count), "DiffviewFilePanelCounter")
  comp:add_text("]", "DiffviewFilePanelPath")
  comp:ln()
end
```

Update section counts to show filtered vs total:
```lua
-- In Changes section
if view and view.review_filter_enabled then
  local shown = -- filtered count
  local total = #panel.files.working
  comp:add_text(string.format("(%d/%d)", shown, total), "DiffviewFilePanelCounter")
else
  comp:add_text("(" .. #panel.files.working .. ")", "DiffviewFilePanelCounter")
end
```

#### Step 2.5: Handle Edge Cases

1. **Cursor on filtered file**: When filter is enabled and current file is no longer visible, move to first visible file
2. **All files reviewed**: Show message "No files pending review" when filter results in empty list
3. **Filter persistence**: Decide if filter state persists when switching tabs or is per-session

### Phase 3: Since-Review Diff Mode

**Goal**: For "changed" files, allow toggling to show only changes since the last review.

#### Step 3.1: Add Since-Review Mode State

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

Add state tracking:
```lua
---@field since_review_mode boolean Whether showing since-review diffs for changed files
```

Add toggle method:
```lua
function DiffView:toggle_since_review_mode()
  if not self.review_state then
    utils.info("Review mode is not enabled")
    return
  end

  self.since_review_mode = not self.since_review_mode

  -- Re-open current file with new revision context
  if self.cur_entry then
    local status = review.get_file_status(self, self.cur_entry)
    if status == "changed" then
      self:_set_file(self.cur_entry)
    else
      utils.info("Since-review mode only applies to changed files")
    end
  end

  -- Update UI indicator
  self.panel:render()
  self.panel:redraw()
end
```

#### Step 3.2: Modify File Opening for Since-Review Mode

When `since_review_mode` is true and opening a "changed" file, we need to compute the diff differently.

**Option A: Create modified FileEntry**

Before calling `use_entry`, create a copy of the file entry with modified revisions:
```lua
-- In _set_file or a wrapper method
if self.since_review_mode then
  local status = review.get_file_status(self, file)
  if status == "changed" then
    local review_entry = self.review_state:get_file(file.path)
    if review_entry and review_entry.commit_hash then
      -- Verify commit exists
      if self:verify_commit_exists(review_entry.commit_hash) then
        -- Create modified revisions
        local left_rev = GitRev(RevType.COMMIT, review_entry.commit_hash)
        -- Use modified file entry or modify how use_entry works
      end
    end
  end
end
```

**Option B: Override revision at use_entry level**

Add a parameter to `use_entry` that allows overriding the left revision.

The recommended approach depends on how deeply `use_entry` is coupled to the FileEntry's revisions. Research `use_entry` implementation in `StandardView` to determine the cleanest approach.

#### Step 3.3: Verify Reviewed Commit Exists

Add helper method to check if the stored commit is still available:
```lua
function DiffView:verify_commit_exists(commit_hash)
  local _, code = self.adapter:exec_sync({ "cat-file", "-e", commit_hash }, self.adapter.ctx.toplevel)
  return code == 0
end
```

If commit doesn't exist:
1. Show warning message
2. Fall back to full diff
3. Optionally offer to clear the outdated review state

#### Step 3.4: Add Action and Keybinding

**File**: `lua/diffview/actions.lua`

Add action: `"review_toggle_since_review"`

**File**: `lua/diffview/config.lua`

Add keybinding:
```lua
{ "n", "<leader>rs", actions.review_toggle_since_review, { desc = "Toggle since-review diff mode" } },
```

#### Step 3.5: Add Visual Indicator

When viewing a file in since-review mode, add indicator. Options:
1. Add to file panel's current file line
2. Add to diff window status line
3. Add echo message when opening file

### Phase 4: Testing

**New test file**: `lua/diffview/tests/functional/review_filter_spec.lua`

Cover:
1. Filter toggle behavior
2. Filtered file list contents
3. Navigation with filter active
4. Cursor handling when file is filtered out
5. Tree view filtering

**New test file**: `lua/diffview/tests/functional/since_review_diff_spec.lua`

Cover:
1. Since-review mode toggle
2. Correct revision used for diff
3. Fallback when commit unavailable
4. Mode indicator display
5. Mode with filter active

### Phase 5: Documentation

**File**: `doc/diffview.txt`

Add documentation for:
- New keybindings (`<leader>rf`, `<leader>rs`)
- New actions (`review_toggle_filter`, `review_toggle_since_review`)
- Explanation of since-review diff mode
- Notes about commit availability after force-push

**File**: `USAGE.md`

Add section explaining:
- How to filter the file panel for efficient re-reviews
- How to view only changes since last review
- Workflow recommendations for PR reviews

### Manual Testing Steps

1. **Setup**: Open a PR with multiple files, mark some as reviewed
2. **Filter test**: Toggle filter, verify only pending files shown
3. **Navigation test**: With filter on, verify `]r` works correctly
4. **Tree view test**: Toggle to tree view, verify filter works
5. **Since-review test**: Edit a reviewed file, toggle since-review mode
6. **Commit unavailable test**: Force-push to remove reviewed commit, verify graceful fallback
7. **Combined test**: Use both filter and since-review mode together

### Why This Approach

1. **Data Model Extension**: Adding `commit_hash` is backward-compatible and minimal
2. **Filter at ordered_file_list**: Leverages existing navigation that uses this method
3. **Since-review as mode**: Allows user to compare full diff vs incremental changes
4. **Graceful degradation**: Falls back to full diff when commit unavailable
5. **Consistent UX**: Follows existing toggle patterns in the codebase

## Current Progress
### Current State
- Data model extended to store commit_hash when marking files reviewed
- Foundation in place for since-review diff mode (Tasks 1-2 complete)

### Completed (So Far)
- Task 1: Added `commit_hash` optional field to ReviewEntry in review_store.lua
- Task 2: Updated mark_file_reviewed and mark_all_reviewed in review.lua to capture HEAD commit hash via adapter:head_rev()
- Event payloads (review_file_marked) now include commit_hash
- Added 9 new tests covering commit_hash storage, backward compatibility, and edge cases

### Remaining
- Tasks 3-8: File panel filtering by review status
- Tasks 9-13: Since-review diff mode implementation
- Tasks 14-16: Additional tests and documentation

### Next Iteration Guidance
- Tasks 3-8 form the file panel filtering feature set (recommended next batch)
- Tasks 3-4 add the filter state and action/keybinding
- Tasks 5-7 implement the actual filtering logic and UI
- Task 8 handles edge cases

### Decisions / Changes
- commit_hash is optional in ReviewEntry for backward compatibility with existing saved state
- head_rev() returns a GitRev object; we extract .commit field for the hash
- nil commit_hash is handled gracefully throughout

### Risks / Blockers
- None
