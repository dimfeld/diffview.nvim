---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Clear all review state for a branch
goal: Add actions with confirmation dialogs to clear review state at branch
  level (<leader>rC) and repository level (<leader>rX)
id: 9
uuid: 5c9e18fb-157d-4000-b111-45d034aedd0b
generatedBy: agent
status: in_progress
priority: medium
dependencies:
  - 5
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "5": 409b88c6-22c0-43f9-97ec-ff6a12b9b0df
planGeneratedAt: 2026-01-16T09:19:08.889Z
promptsGeneratedAt: 2026-01-16T09:19:08.889Z
createdAt: 2026-01-15T01:45:15.566Z
updatedAt: 2026-01-16T09:31:48.682Z
tasks:
  - title: Add action names to actions.lua
    done: true
    description: >-
      Add "review_clear_all" and "review_clear_repo" to the action_names array
      in lua/diffview/actions.lua. These will be auto-generated as action
      functions that emit events.


      Location: Around line 635, in the action_names array, alongside other
      review actions.
  - title: Add branch clear listener with confirmation
    done: true
    description: >-
      Add a listener for the review_clear_all event in
      lua/diffview/scene/views/diff/listeners.lua.


      The listener should:

      1. Check if view.review_state exists, warn if not

      2. Count files with vim.tbl_count(view.review_state.files)

      3. If count is 0, show "No files are currently marked as reviewed" info
      message

      4. Show vim.ui.select() confirmation with file count and branch name

      5. On "Yes", call review.clear_all_reviews(view)


      Location: After the review_clear_file listener (around line 341-345)
  - title: Add repository clear method to ReviewStore
    done: true
    description: >-
      Add ReviewStore:clear_repo_state(repo_id) method to
      lua/diffview/review_store.lua.


      Implementation:

      1. Get cache_dir and build repo_dir path

      2. Check if repo_dir exists with utils.path:stat()

      3. Iterate with uv.fs_scandir(repo_dir) and uv.fs_scandir_next()

      4. Delete each .json file with uv.fs_unlink()

      5. Optionally remove empty directory with uv.fs_rmdir()

      6. Return count of deleted files


      Location: After the save_state method (around line 302)
  - title: Add repository clear wrapper to review.lua
    done: true
    description: |-
      Add review.clear_repo_reviews(view) function to lua/diffview/review.lua.

      Implementation:
      1. Check review is enabled
      2. Get repo_id from store:get_repo_id(view.adapter)
      3. Call store:clear_repo_state(repo_id)
      4. Clear in-memory view.review_state.files if it exists
      5. Emit "review_repo_cleared" event with view, repo_id, deleted_count

      Location: After clear_all_reviews function
  - title: Add repository clear event listener to DiffView
    done: true
    description: >-
      Add listener for "review_repo_cleared" event in
      lua/diffview/scene/views/diff/diff_view.lua.


      Pattern: Same as existing "review_all_cleared" listener - refresh panel
      and disable review filter if active.


      Location: After the review_all_cleared listener (around line 663)
  - title: Add repository clear listener with confirmation
    done: true
    description: >-
      Add a listener for the review_clear_repo event in
      lua/diffview/scene/views/diff/listeners.lua.


      The listener should:

      1. Get repo_id from store:get_repo_id(view.adapter)

      2. Count branch files by scanning the repo directory

      3. If count is 0, show "No review state exists for this repository" info
      message

      4. Show vim.ui.select() confirmation with branch count

      5. On "Yes", call review.clear_repo_reviews(view)


      Location: After review_clear_all listener
  - title: Add default keymaps
    done: false
    description: >-
      Add keymaps to both view and file_panel sections in
      lua/diffview/config.lua:


      { "n", "<leader>rC", actions.review_clear_all, { desc = "Clear all review
      state for this branch" } }

      { "n", "<leader>rX", actions.review_clear_repo, { desc = "Clear all review
      state for this repository" } }


      Location: After the review_clear_file keymap in each section
  - title: Add documentation to doc/diffview.txt
    done: false
    description: >-
      Add action documentation for review_clear_all and review_clear_repo with
      anchor tags.

      Add keymap documentation showing <leader>rC and <leader>rX in the Maps
      section.


      Follow existing patterns for review_* actions.
  - title: Update doc/diffview_defaults.txt
    done: false
    description: |-
      Add the new keymaps to both view and file_panel sections.
      This file should mirror config.lua exactly.
  - title: Update USAGE.md
    done: false
    description: >-
      Add "Clearing Review State" section after "Marking Files as Reviewed"
      section.

      Document both <leader>rC (branch) and <leader>rX (repository) with use
      cases.
  - title: Write tests
    done: false
    description: |-
      Create lua/diffview/tests/functional/review_clear_spec.lua with tests for:

      Branch clear tests:
      - ReviewStore:clear_all clears in-memory state
      - review.clear_all_reviews emits review_all_cleared event
      - Listener handles empty state case

      Repository clear tests:
      - ReviewStore:clear_repo_state deletes all JSON files
      - ReviewStore:clear_repo_state returns correct count
      - ReviewStore:clear_repo_state handles non-existent directory
      - review.clear_repo_reviews clears in-memory state
      - review.clear_repo_reviews emits review_repo_cleared event
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
  - lua/diffview/tests/functional/review_clear_spec.lua
  - lua/diffview/tests/functional/review_filter_spec.lua
  - lua/diffview/tests/functional/review_navigation_spec.lua
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/tests/functional/since_review_diff_spec.lua
  - lua/diffview/ui/models/file_tree/file_tree.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

Implement the ability to clear all review state for a branch, allowing the user to start a fresh review.

## Use Cases
- Starting over on a review after significant changes
- Clearing state when the previous review is no longer relevant
- Resetting when the blob hashes are stale (garbage collected)

## Actions Required

### Clear All Review State for Current Branch
- Remove all review entries for the current repository + branch combination
- All files will appear as "unreviewed" after this action
- Should prompt for confirmation before clearing

### Optional: Clear Review State for Specific Repository
- Remove all review entries for a specific repository (all branches)
- Useful when a repository is removed or relocated

## Integration
- Should be available as a command that can be bound to a key
- Consider adding to a menu or command palette if diffview has one

## Expected Behavior

### Branch-Level Clear (`<leader>rC`)
1. User presses `<leader>rC` in a diffview
2. If no review state exists, show warning message
3. If no files are marked as reviewed, show "nothing to clear" message
4. Otherwise, show confirmation dialog with file count and branch name
5. On "Yes": Clear all review state for current branch, UI refreshes automatically
6. On "No" or cancel: No action taken

### Repository-Level Clear (`<leader>rX`)
1. User presses `<leader>rX` in a diffview
2. If no review state exists for repository, show "no state exists" message
3. Otherwise, show confirmation dialog with branch count
4. On "Yes": Delete all branch state files for repository, clear in-memory state, UI refreshes
5. On "No" or cancel: No action taken

### States
- **No review state**: View doesn't have review state (e.g., review feature disabled)
- **Empty state**: Review state exists but no files are marked reviewed
- **Has reviewed files**: One or more files are marked as reviewed
- **Repository has state**: At least one branch has review state files on disk

## Acceptance Criteria

- [ ] `<leader>rC` clears all review state for current branch with confirmation
- [ ] `<leader>rC` shows file count and branch name in confirmation prompt
- [ ] `<leader>rC` shows appropriate message when no files are reviewed
- [ ] `<leader>rX` clears all review state for repository (all branches) with confirmation
- [ ] `<leader>rX` shows branch count in confirmation prompt
- [ ] `<leader>rX` shows appropriate message when no state exists
- [ ] Confirmation dialogs work with vim.ui.select() (compatible with UI plugins)
- [ ] UI automatically refreshes after clearing
- [ ] Review filter is disabled after clearing if it was active
- [ ] Actions are available in both `view` and `file_panel` contexts
- [ ] Actions are documented in help file (doc/diffview.txt)
- [ ] Keymaps are documented in defaults file (doc/diffview_defaults.txt)
- [ ] Workflow documentation added to USAGE.md
- [ ] Tests cover clearing logic and event emission

## Research

### Overview

This plan implements the ability to clear all review state for the current branch, allowing users to start fresh when reviewing code. The existing review system tracks which files have been reviewed in a branch, storing blob hashes to detect when files have changed since review. This feature adds a "clear all" operation with confirmation to prevent accidental data loss.

### Key Findings

#### 1. Existing Review State Architecture

The review system is well-architected with clear separation of concerns:

- **`lua/diffview/review_store.lua`** - Persistence layer with `ReviewStore` (singleton) and `ReviewState` classes
- **`lua/diffview/review.lua`** - High-level API for review operations with event emission
- **`lua/diffview/scene/views/diff/listeners.lua`** - Event handlers that connect actions to review operations
- **`lua/diffview/actions.lua`** - Action functions that emit events

**Critical Finding:** The `ReviewState:clear_all()` method already exists at `lua/diffview/review_store.lua:75-79`:
```lua
function ReviewState:clear_all()
  self.files = {}
  self.dirty = true
  self.store:save_state(self)
end
```

And the `review.clear_all_reviews()` wrapper exists at `lua/diffview/review.lua:155-173`:
```lua
function M.clear_all_reviews(view)
  if not is_review_enabled() then return false end
  if not view or not view.review_state then
    utils.warn("No review state available for this view")
    return false
  end
  view.review_state:clear_all()
  DiffviewGlobal.emitter:emit("review_all_cleared", { view = view })
  return true
end
```

The core clearing logic is already implemented. The missing piece is exposing this to users through an action with confirmation.

#### 2. Action/Keymap Pattern

Actions follow this pattern:
1. Define action in `lua/diffview/actions.lua` as a function that emits an event
2. Register event name in `action_names` array (line 618-657) for auto-generation
3. Add listener in `lua/diffview/scene/views/diff/listeners.lua`
4. Add default keymap in `lua/diffview/config.lua` in appropriate context groups

Example from existing review actions (`actions.lua:635-637`):
```lua
"review_clear_file",
"review_mark_all",
"review_mark_file",
```

These are auto-generated via the loop at lines 659-663:
```lua
for _, name in ipairs(action_names) do
  M[name] = function()
    require("diffview").emit(name)
  end
end
```

#### 3. Confirmation Dialog Pattern

The plugin uses `vim.ui.input()` and `vim.ui.select()` for user prompts:

- **`vim.ui.input()`** - Used via `utils.input()` wrapper in `lua/diffview/utils.lua:1199`
- **`vim.ui.select()`** - Used directly in `lua/diffview/scene/views/file_history/option_panel.lua:73`

For confirmation dialogs, `vim.ui.select()` will be used as it allows UI plugins like dressing.nvim to provide a more modern interface:
```lua
vim.ui.select({ "Yes", "No" }, {
  prompt = "Clear all review state for this branch?",
}, function(choice)
  if choice == "Yes" then
    -- perform action
  end
end)
```

This is asynchronous so the action logic must be inside the callback.

#### 4. Keymap Conventions for Review Actions

Existing review keymaps use `<leader>r` prefix:
- `<leader>rf` - Toggle review filter
- `<leader>rs` - Toggle since-review diff mode
- `<leader>rm` - Mark current file as reviewed
- `<leader>rM` - Mark all files as reviewed
- `<leader>rc` - Clear review status for current file

Suggested keymap for clearing all: `<leader>rC` (capital C for "Clear all", distinguishing from lowercase `c` for single file)

#### 5. Event System Integration

The `DiffView` class already listens for `"review_all_cleared"` event at `lua/diffview/scene/views/diff/diff_view.lua:618-663`:
```lua
DiffviewGlobal.emitter:on("review_all_cleared", function(data)
  if self == data.view then
    vim.schedule(function()
      if self.panel:is_valid() then
        self.panel:render()
        self.panel:redraw()
        if self.review_filter_active then
          self:set_review_filter(false)
        end
      end
    end)
  end
end)
```

This means the UI will automatically update when `review.clear_all_reviews()` is called - no additional UI refresh code needed.

#### 6. Documentation Locations

New features must be documented in:
1. `doc/diffview.txt` - Main help file
   - Add action documentation with anchor tag `*diffview-actions-review_clear_all*`
   - Add keymap to the "Maps" section
2. `doc/diffview_defaults.txt` - Rendered defaults (keep in sync with config.lua)
3. `USAGE.md` - Practical workflow documentation (add to review workflow section ~line 158)
4. `README.md` - If showing example config (optional for this feature)

#### 7. Repository-Wide Clear

The plan also requires clearing all review state for a repository (all branches). This requires:
- Getting the repo_id from the current adapter
- Iterating over all `.json` files in `~/.cache/diffview.nvim/reviews/{repo_id}/`
- Deleting each file and optionally the directory

**Filesystem APIs available** (from `vim.loop` / `uv`):
- `uv.fs_scandir(path)` - Get directory handle for iteration
- `uv.fs_scandir_next(handle)` - Get next entry (name, type)
- `uv.fs_unlink(path)` - Delete a file
- `uv.fs_rmdir(path)` - Delete an empty directory
- `uv.fs_stat(path)` - Check if path exists and get type

The test file at `lua/diffview/tests/functional/review_store_spec.lua:506-523` has a reference `rm_rf()` implementation that can be adapted.

**Implementation approach:**
1. Add `ReviewStore:clear_repo_state(repo_id)` method to delete all branch files for a repo
2. Add `review.clear_repo_reviews(view)` wrapper that gets repo_id from view's adapter
3. Create new action `review_clear_repo` with confirmation
4. Use different keymap (suggested: `<leader>rX` - "X" for "expunge entire repo")

### Technical Constraints

1. **Async operations:** The `ReviewStore.save_state` is an async function using coroutines. The clear operation itself is synchronous (just clears in-memory state) but triggers an async save.

2. **View context required:** The `review.clear_all_reviews()` function requires a valid `DiffView` with `review_state`. This is already handled by the function itself with appropriate warnings.

3. **Event emission:** The `"review_all_cleared"` event is already emitted by the existing `clear_all_reviews` function, so UI updates are handled automatically.

### Dependencies & Prerequisites

- **Dependencies:** This plan depends on Plan 5 (review state foundation) which is marked as a dependency and completed
- **No external dependencies:** Uses only existing Neovim APIs (`vim.ui.select` or `vim.fn.confirm`)

## Implementation Guide

### Step 1: Add Action Name to actions.lua

Add `"review_clear_all"` to the `action_names` array in `lua/diffview/actions.lua`. This auto-generates the action function that emits the event.

**File:** `lua/diffview/actions.lua`
**Location:** Around line 635, in the `action_names` array

Add `"review_clear_all"` alongside the other review actions:
```lua
"review_clear_all",    -- Add this
"review_clear_file",
"review_mark_all",
```

### Step 2: Add Listener with Confirmation Dialog

Add a listener for the `review_clear_all` event in the diff view listeners that shows a confirmation dialog before clearing.

**File:** `lua/diffview/scene/views/diff/listeners.lua`
**Location:** After the `review_clear_file` listener (around line 341-345)

The listener should:
1. Check if there's anything to clear (show warning if no review state)
2. Show a confirmation dialog using `vim.ui.select()` (async, supports UI plugins)
3. Call `review.clear_all_reviews(view)` if confirmed
4. The event system will handle UI refresh automatically

Example pattern:
```lua
review_clear_all = function()
  if not view.review_state then
    utils.warn("No review state available")
    return
  end
  local file_count = vim.tbl_count(view.review_state.files)
  if file_count == 0 then
    utils.info("No files are currently marked as reviewed")
    return
  end
  vim.ui.select({ "Yes", "No" }, {
    prompt = ("Clear review state for %d file(s) on branch '%s'?"):format(file_count, view.review_state.branch),
  }, function(choice)
    if choice == "Yes" then
      review.clear_all_reviews(view)
    end
  end)
end,
```

### Step 3: Add Default Keymaps

Add the keymap to both `view` and `file_panel` context groups, following the pattern of existing review keymaps.

**File:** `lua/diffview/config.lua`

**Location 1:** `view` keymaps section (around line 154, after `review_clear_file`)
```lua
{ "n", "<leader>rC",  actions.review_clear_all,             { desc = "Clear all review state for this branch" } },
```

**Location 2:** `file_panel` keymaps section (around line 234, after `review_clear_file`)
```lua
{ "n", "<leader>rC", actions.review_clear_all,             { desc = "Clear all review state for this branch" } },
```

### Step 4: Add Documentation to doc/diffview.txt

Add action documentation in the "Available Actions" section and keymap documentation in the "Maps" section.

**File:** `doc/diffview.txt`

**Action documentation** (find the review actions section, should be near other `review_*` actions):
```
                                                *diffview-actions-review_clear_all*
review_clear_all()
        Contexts: `view`, `file_panel`

        Clear all review state for the current branch. Shows a confirmation
        dialog before clearing. After clearing, all files will appear as
        "unreviewed".
```

**Keymap documentation** (in the Maps section under view and file_panel):
```
`<leader>rC`    Clear all review state for the current branch (with confirmation)
```

### Step 5: Update doc/diffview_defaults.txt

Keep this file in sync with config.lua. Add the new keymap entry to both view and file_panel sections.

**File:** `doc/diffview_defaults.txt`

This file should mirror config.lua exactly - add the same keymap lines to the corresponding sections.

### Step 6: Update USAGE.md

Add documentation about clearing all review state to the review workflow section.

**File:** `USAGE.md`
**Location:** After the "Marking Files as Reviewed" section (around line 158)

Add:
```markdown
### Clearing Review State

If you need to start over on a review, you can clear review state:

- `<leader>rC` - Clear all review state for this branch (with confirmation)
- `<leader>rX` - Clear all review state for this repository (all branches, with confirmation)

Clearing branch state is useful when:
- The previous review is no longer relevant
- You want to start fresh after significant changes to the branch
- Review state has become stale (e.g., blob hashes point to garbage-collected objects)

Clearing repository state is useful when:
- A repository has been relocated or removed
- You want to clear all historical review data
```

### Step 7: Add Repository-Wide Clear to ReviewStore

Add a method to `ReviewStore` that deletes all branch files for a given repository.

**File:** `lua/diffview/review_store.lua`
**Location:** After the `save_state` method (around line 302)

Add method `ReviewStore:clear_repo_state(repo_id)`:
```lua
---Clear all review state for a repository (all branches)
---@param repo_id string The repository ID
---@return integer deleted_count Number of branch files deleted
function ReviewStore:clear_repo_state(repo_id)
  local cache_dir = self:get_cache_dir()
  local repo_dir = utils.path:join(cache_dir, repo_id)

  local stat = utils.path:stat(repo_dir)
  if not stat or stat.type ~= "directory" then
    return 0
  end

  local deleted_count = 0
  local handle = uv.fs_scandir(repo_dir)
  if handle then
    while true do
      local name, ftype = uv.fs_scandir_next(handle)
      if not name then break end
      if ftype == "file" and name:match("%.json$") then
        local file_path = utils.path:join(repo_dir, name)
        local ok = pcall(uv.fs_unlink, file_path)
        if ok then deleted_count = deleted_count + 1 end
      end
    end
  end

  -- Optionally remove the empty directory
  pcall(uv.fs_rmdir, repo_dir)

  return deleted_count
end
```

### Step 8: Add Repository-Wide Clear to review.lua

Add the high-level wrapper function.

**File:** `lua/diffview/review.lua`
**Location:** After `clear_all_reviews` function

```lua
---Clear all reviews for the repository (all branches)
---@param view DiffView
---@return integer deleted_count Number of branch files deleted, or 0 on error
function M.clear_repo_reviews(view)
  if not is_review_enabled() then
    return 0
  end

  if not view or not view.adapter then
    utils.warn("No adapter available for this view")
    return 0
  end

  local store = review_store.get_store()
  local repo_id = store:get_repo_id(view.adapter)
  if not repo_id then
    utils.warn("Could not determine repository ID")
    return 0
  end

  local deleted_count = store:clear_repo_state(repo_id)

  -- Clear the in-memory state if it exists
  if view.review_state then
    view.review_state.files = {}
    view.review_state.dirty = false
  end

  -- Emit event for UI updates
  DiffviewGlobal.emitter:emit("review_repo_cleared", {
    view = view,
    repo_id = repo_id,
    deleted_count = deleted_count,
  })

  return deleted_count
end
```

### Step 9: Add Event Listener for Repository Clear

Add event listener to DiffView for the new `review_repo_cleared` event.

**File:** `lua/diffview/scene/views/diff/diff_view.lua`
**Location:** After the `review_all_cleared` listener (around line 663)

```lua
DiffviewGlobal.emitter:on("review_repo_cleared", function(data)
  if self == data.view then
    vim.schedule(function()
      if self.panel:is_valid() then
        self.panel:render()
        self.panel:redraw()
        if self.review_filter_active then
          self:set_review_filter(false)
        end
      end
    end)
  end
end)
```

### Step 10: Add Repository Clear Action and Listener

Add the action name and listener for repository-wide clear.

**File:** `lua/diffview/actions.lua`
**Location:** In `action_names` array, add `"review_clear_repo"`

**File:** `lua/diffview/scene/views/diff/listeners.lua`
**Location:** After `review_clear_all` listener

```lua
review_clear_repo = function()
  local store = review_store.get_store()
  local repo_id = store:get_repo_id(view.adapter)
  if not repo_id then
    utils.warn("Could not determine repository ID")
    return
  end

  -- Count branches to show in confirmation
  local cache_dir = store:get_cache_dir()
  local repo_dir = utils.path:join(cache_dir, repo_id)
  local branch_count = 0
  local stat = utils.path:stat(repo_dir)
  if stat and stat.type == "directory" then
    local handle = uv.fs_scandir(repo_dir)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then break end
        if name:match("%.json$") then branch_count = branch_count + 1 end
      end
    end
  end

  if branch_count == 0 then
    utils.info("No review state exists for this repository")
    return
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = ("Clear review state for %d branch(es) in this repository?"):format(branch_count),
  }, function(choice)
    if choice == "Yes" then
      review.clear_repo_reviews(view)
    end
  end)
end,
```

### Step 11: Add Repository Clear Keymap

**File:** `lua/diffview/config.lua`

Add to both `view` and `file_panel` sections:
```lua
{ "n", "<leader>rX", actions.review_clear_repo,            { desc = "Clear all review state for this repository" } },
```

### Step 12: Write Tests

Add tests for both clearing operations.

**File:** `lua/diffview/tests/functional/review_clear_spec.lua` (new file)

Test cases for branch clear:
1. Action is properly registered and callable
2. Clearing with no review state shows appropriate message
3. Clearing with empty state shows "nothing to clear" message
4. Confirmation dialog cancellation does not clear state
5. Confirmation dialog acceptance clears all files
6. Event `review_all_cleared` is emitted after clearing

Test cases for repository clear:
1. `ReviewStore:clear_repo_state` deletes all JSON files in repo directory
2. `ReviewStore:clear_repo_state` returns correct count
3. `ReviewStore:clear_repo_state` handles non-existent directory
4. `review.clear_repo_reviews` clears in-memory state
5. `review.clear_repo_reviews` emits `review_repo_cleared` event
6. Listener properly refreshes UI after repo clear

### Step 13: Update Documentation

**File:** `doc/diffview.txt`

Add action documentation:
```
                                                *diffview-actions-review_clear_all*
review_clear_all()
        Contexts: `view`, `file_panel`

        Clear all review state for the current branch. Shows a confirmation
        dialog before clearing. After clearing, all files will appear as
        "unreviewed".

                                                *diffview-actions-review_clear_repo*
review_clear_repo()
        Contexts: `view`, `file_panel`

        Clear all review state for the current repository (all branches).
        Shows a confirmation dialog before clearing. This is useful when
        a repository has been relocated or you want to clear all historical
        review data.
```

Add keymap documentation:
```
`<leader>rC`    Clear all review state for the current branch (with confirmation)
`<leader>rX`    Clear all review state for this repository (with confirmation)
```

### Manual Testing Steps

**Branch-level clear:**
1. Open a diffview: `:DiffviewOpen`
2. Mark some files as reviewed with `<leader>rm`
3. Verify files show reviewed status (filled circle indicator)
4. Press `<leader>rC` - confirmation dialog should appear showing file count and branch name
5. Press "No" or Escape - state should remain unchanged
6. Press `<leader>rC` again, this time press "Yes"
7. All files should now show as unreviewed (empty indicator)
8. Verify the review filter is auto-disabled if it was active

**Repository-level clear:**
1. Switch to different branches and mark files as reviewed
2. Return to original branch
3. Press `<leader>rX` - confirmation should show branch count
4. Confirm clearing
5. Verify files on current branch are unreviewed
6. Switch to other branches and verify they're also cleared

### Rationale

1. **Why `vim.ui.select()` over `vim.fn.confirm()`?** - `vim.ui.select()` can be customized by UI plugins like dressing.nvim, providing a more modern and consistent interface. While it requires callback handling, this pattern is already used elsewhere in the codebase.

2. **Why `<leader>rC`?** - Follows existing convention of `<leader>r` prefix for review actions. Capital `C` distinguishes "Clear all" from lowercase `c` "Clear file" and indicates it's a more significant action.

3. **Why `<leader>rX`?** - "X" suggests "expunge" or "delete all" and is visually distinct from `C`. It's also an uncommon key for review operations, reducing accidental use.

4. **Why show counts in confirmation?** - Gives user context about the impact of the action, helping prevent accidental clearing.

## Current Progress
### Current State
- Core implementation of branch-level and repository-level review state clearing is complete
- Actions, listeners, store methods, and event handling are all implemented and tested
- Tests written and passing (17 new tests in review_clear_spec.lua)

### Completed (So Far)
- Task 1: Added `review_clear_all` and `review_clear_repo` action names to actions.lua
- Task 2: Added `review_clear_all` listener with confirmation dialog in listeners.lua
- Task 3: Added `ReviewStore:clear_repo_state(repo_id)` method in review_store.lua
- Task 4: Added `review.clear_repo_reviews(view)` wrapper in review.lua
- Task 5: Added `review_repo_cleared` event listener in diff_view.lua with proper cleanup
- Task 6: Added `review_clear_repo` listener with confirmation dialog in listeners.lua

### Remaining
- Task 7: Add default keymaps to config.lua
- Task 8: Add documentation to doc/diffview.txt
- Task 9: Update doc/diffview_defaults.txt
- Task 10: Update USAGE.md
- Task 11: Write tests (partial - core tests done, may need additional coverage)

### Next Iteration Guidance
- Next batch should focus on Tasks 7-10 (keymaps and documentation)
- All keymaps should be added to both `view` and `file_panel` sections
- Documentation should follow existing patterns for review_* actions

### Decisions / Changes
- The `review_clear_repo` listener was implemented alongside Task 4 since they're closely related
- Event listener cleanup is properly handled in DiffView:close()

### Risks / Blockers
- None
