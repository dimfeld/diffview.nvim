---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Cleanup stale review data
goal: ""
id: 8
uuid: 23bead4b-525b-482d-bf0c-51757bee0793
generatedBy: agent
status: in_progress
priority: medium
dependencies:
  - 9
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "9": 5c9e18fb-157d-4000-b111-45d034aedd0b
planGeneratedAt: 2026-01-16T10:13:56.188Z
promptsGeneratedAt: 2026-01-16T10:13:56.188Z
createdAt: 2026-01-15T01:45:14.898Z
updatedAt: 2026-01-16T10:15:33.401Z
tasks:
  - title: Add branch listing methods to ReviewStore
    done: false
    description: Add unsanitize_branch() helper and get_stored_branches(repo_id)
      method to ReviewStore in lua/diffview/review_store.lua. The
      unsanitize_branch function converts sanitized filenames back to possible
      branch names. The get_stored_branches method scans the repo directory and
      returns stored branch info.
  - title: Add get_all_branches method to GitAdapter
    done: false
    description: Add get_all_branches() method to
      lua/diffview/vcs/adapters/git/init.lua that returns all local and
      remote-tracking branch names. Uses git for-each-ref with refs/heads/ and
      refs/remotes/. Also extracts short forms from remote branches (e.g.,
      origin/main -> main).
  - title: Add age timestamp extraction to ReviewStore
    done: false
    description: Add get_latest_review_timestamp(file_path) method to ReviewStore
      that reads a JSON file and returns the most recent reviewed_at timestamp
      from the files entries. Returns nil on error or if no timestamps found.
  - title: Add cleanup_stale_branches method to ReviewStore
    done: false
    description: Add cleanup_stale_branches(adapter, opts) method to ReviewStore
      that compares stored branches against git branches and deletes stale ones.
      Supports dry_run mode and max_age_days parameter. Cleans up detached HEAD
      files based on age. Only deletes stale branches that are also older than
      max_age_days.
  - title: Add public cleanup API to review.lua
    done: false
    description: Add get_cleanup_preview(view) and cleanup_stale_reviews(view)
      functions to lua/diffview/review.lua. These wrap the ReviewStore cleanup
      methods and emit review_cleanup_completed event on success. Read
      cleanup_age_days from config.
  - title: Add cleanup configuration options
    done: false
    description: Add auto_cleanup (boolean, default false) and cleanup_age_days
      (integer, default 30) to the review section of config defaults in
      lua/diffview/config.lua.
  - title: Add review_cleanup action
    done: false
    description: Add review_cleanup to the action_names array in
      lua/diffview/actions.lua so it can be triggered via keymaps.
  - title: Add review_cleanup listener
    done: false
    description: Add review_cleanup listener function to
      lua/diffview/scene/views/diff/listeners.lua. Shows preview first, then
      prompts for confirmation with vim.ui.select before performing cleanup.
  - title: Add DiffviewReviewCleanup command
    done: false
    description: Add DiffviewReviewCleanup command to plugin/diffview.lua. Supports
      bang (!) for dry-run preview mode. Works with or without an active
      DiffView by creating a temporary adapter if needed.
  - title: Add auto-cleanup on DiffView open
    done: false
    description: Add auto-cleanup logic to DiffView:post_open() in
      lua/diffview/scene/views/diff/diff_view.lua. When review.auto_cleanup is
      enabled, run cleanup asynchronously after view opens and show notification
      if files were cleaned.
  - title: Add cleanup event emitter
    done: false
    description: Add DiffviewGlobal.emitter listener for review_cleanup_completed
      event in lua/diffview/init.lua that fires DiffviewReviewCleanupCompleted
      user autocommand.
  - title: Write tests for branch listing methods
    done: false
    description: "Create lua/diffview/tests/functional/review_cleanup_spec.lua with
      tests for get_stored_branches(): empty repo dir, correct branches,
      sanitized names with slashes, skips non-JSON files."
  - title: Write tests for timestamp extraction
    done: false
    description: "Add tests for get_latest_review_timestamp(): returns nil for
      non-existent file, nil for malformed JSON, correct timestamp for single
      entry, most recent for multiple entries."
  - title: Write tests for cleanup_stale_branches
    done: false
    description: "Add tests for cleanup_stale_branches(): error cases, dry run mode,
      actual deletion, preserving existing branches (local and remote),
      double-underscore ambiguity, detached HEAD age-based cleanup, max_age_days
      parameter."
  - title: Write tests for public cleanup API
    done: false
    description: "Add tests for review.cleanup_stale_reviews() and
      review.get_cleanup_preview(): disabled review, no view, event emission,
      correct file deletion."
tags: []
---

Implement cleanup functionality to remove review data for branches that no longer exist.

## Why Cleanup is Needed
- Review state is stored per branch
- When branches are deleted (after merging PRs, etc.), the review data becomes stale
- Over time this can accumulate and waste storage space

## Cleanup Approach

### Automatic Cleanup (on startup or periodic)
- When diffview loads, check stored review data against existing branches
- Remove review entries for branches that no longer exist in the repository
- Should be efficient and not slow down normal operations

### Manual Cleanup Command
- Provide a command to manually trigger cleanup
- Could show what will be removed before doing it

## Considerations
- Need to handle multiple repositories (each repo has its own branches)
- Should be resilient to temporary branch unavailability (e.g., during fetch)
- Consider age-based cleanup as an additional strategy (remove reviews older than X days)

## Research

### Storage Architecture

The review state is stored in JSON files at `~/.cache/diffview.nvim/reviews/<repo_id>/<sanitized_branch>.json` (configurable via `config.review.cache_dir`).

**Key structures in `lua/diffview/review_store.lua`:**

- **Repository ID**: First 12 characters of the initial commit SHA (`git rev-list --max-parents=0 HEAD`). This allows multiple clones/checkouts of the same repo to share review state.
- **Branch sanitization**: Forward slashes in branch names are replaced with `__` (e.g., `feature/foo` → `feature__foo.json`)
- **Storage format**: JSON with `{ version: 1, repo_id, branch, files: { [path]: { blob_hash, reviewed_at, commit_hash? } } }`

**Key classes:**
- `ReviewStore` (singleton via `M.get_store()`) - manages all I/O operations
- `ReviewState` - per-branch in-memory state

### Existing Cleanup Methods

`ReviewStore:clear_repo_state(repo_id)` at `review_store.lua:307-334`:
- Scans the repo directory for all `*.json` files
- Deletes each JSON file and counts deletions
- Attempts to remove the empty directory afterward
- Returns count of deleted files

### Branch Detection in Git Adapter

`lua/diffview/vcs/adapters/git/init.lua`:
- `get_current_branch()` (lines 1311-1366): Gets current branch via `git rev-parse --abbrev-ref HEAD`
- `rev_candidates()` (lines 2109-2155): Lists all branches via `git rev-parse --symbolic --branches --tags --remotes`

For cleanup, we need to list **local branches only**. The git command is:
```
git rev-parse --symbolic --branches
```
Or more reliably:
```
git for-each-ref --format='%(refname:short)' refs/heads/
```

### Plugin Initialization Pattern

In `lua/diffview/init.lua`:
- `M.init()` sets up autocommands in the `diffview_nvim` augroup
- Autocommands include: `TabEnter`, `TabLeave`, `TabClosed`, `BufWritePost`, `WinClosed`, `ColorScheme`
- Event emitters forward internal events to user autocommands (e.g., `DiffviewViewOpened`)

For automatic cleanup, options include:
1. Run on plugin init (`M.init()`)
2. Run when opening a DiffView (`DiffView:post_open()`)
3. Run via a VimLeavePre autocommand
4. Periodic timer via `vim.loop.new_timer()`

### Action/Command Pattern

Actions are defined in `lua/diffview/actions.lua`:
- Dynamic dispatch via event emission
- Listener functions handle actual logic in `lua/diffview/scene/views/diff/listeners.lua`
- Commands defined in `plugin/diffview.lua` using `nvim_create_user_command`

For a manual cleanup command, follow the pattern of `:DiffviewClose`, `:DiffviewRefresh`, etc.

### Test Patterns

Tests in `lua/diffview/tests/functional/`:
- Use Plenary's Busted runner
- Helpers in `lua/diffview/tests/helpers.lua` provide `eq`, `neq`, `async_test`
- File I/O tests create temp directories in `/tmp/claude/`
- Mock objects simulate views, adapters, and panel components

### Key Files That Will Be Modified/Created

1. **`lua/diffview/review_store.lua`** - Add methods for:
   - Getting all repo IDs from cache directory
   - Getting all branches stored for a repo
   - Checking if a branch exists in git
   - Cleanup method to prune stale branches

2. **`lua/diffview/review.lua`** - Add public API:
   - `cleanup_stale_reviews(adapter, opts)` - main cleanup function
   - `get_cleanup_preview(adapter)` - dry-run to show what would be removed

3. **`lua/diffview/init.lua`** - Add:
   - Automatic cleanup on startup (optional, controlled by config)
   - User autocommand emitter for cleanup events

4. **`lua/diffview/config.lua`** - Add configuration:
   - `review.auto_cleanup` (boolean)
   - `review.cleanup_age_days` (optional age-based threshold)

5. **`plugin/diffview.lua`** - Add command:
   - `:DiffviewReviewCleanup` - manual trigger with optional dry-run

6. **`lua/diffview/scene/views/diff/listeners.lua`** - Add listener:
   - `review_cleanup` action handler with confirmation UI

7. **`lua/diffview/actions.lua`** - Add action:
   - `review_cleanup` in the action_names array

8. **Tests** - New test file:
   - `lua/diffview/tests/functional/review_cleanup_spec.lua`

### Potential Challenges

1. **Multi-repo handling**: The cache directory may contain state for multiple repositories. Need to determine which repo the user is currently in, or clean up all repos.

2. **Performance on startup**: If auto-cleanup is enabled, it should be non-blocking and not slow down Neovim startup. Use async patterns.

3. **Remote branches**: Check both local and remote-tracking branches (`refs/heads/` and `refs/remotes/`) to preserve review state for branches that exist on remote but aren't checked out locally.

4. **Detached HEAD state**: Files stored as `detached-<sha>.json` are cleaned up based on age (30 days default). These can't be matched to branches.

5. **Concurrent access**: Multiple Neovim instances might access the same cache. File operations should be atomic where possible.

6. **Age-based cleanup**: Uses `reviewed_at` timestamps from JSON files for accurate age determination. Required I/O is acceptable since cleanup isn't performance-critical.

## Design Decisions

The following decisions were made during planning:

1. **Remote branch handling**: Check both local (`refs/heads/`) and remote-tracking branches (`refs/remotes/`). A branch that exists on remote but not locally should preserve its review state.

2. **Age-based cleanup**: Included in initial implementation. Uses `reviewed_at` timestamps from JSON files (not file mtime) for accuracy.

3. **Age threshold**: Default is 30 days. Configurable via `review.cleanup_age_days`.

4. **Age scope**: Age-based cleanup only applies to:
   - Detached HEAD files (`detached-*.json`) which can't be matched to branches
   - Stale branch files (branches that no longer exist in git)
   - Branches that still exist are NEVER deleted based on age alone

5. **Command interface**: Use `:DiffviewReviewCleanup` for cleanup with confirmation, and `:DiffviewReviewCleanup!` (bang) for dry-run preview.

## Expected Behavior/Outcome

### User-Facing Behavior

1. **Automatic cleanup (optional)**: When enabled, stale review data is cleaned up silently in the background when opening a DiffView for a repository.

2. **Manual cleanup command**: `:DiffviewReviewCleanup` shows a preview of what will be removed and prompts for confirmation.

3. **Cleanup summary**: After cleanup, a notification shows how many branch files were removed.

### States

- **No stale data**: Cleanup completes with "No stale review data found"
- **Stale data found**: Shows branches to be removed, confirms with user (manual), or removes silently (auto)
- **Error state**: Git command fails, gracefully skip cleanup with warning

## Key Findings

### Product & User Story

As a developer using diffview.nvim's review tracking feature, I want stale review data for deleted branches to be automatically cleaned up so that my cache directory doesn't grow indefinitely with orphaned data.

### Design & UX Approach

- **Manual command**: Explicit `:DiffviewReviewCleanup` with dry-run preview and confirmation dialog
- **Auto cleanup**: Optional, runs on DiffView open, silent unless errors occur
- **Conservative defaults**: Auto cleanup disabled by default; users opt-in
- **Transparent**: Shows what branches will be/were cleaned up

### Technical Plan & Risks

**Approach**: Compare stored branch files against `git for-each-ref` output for local branches.

**Risks**:
- Git command could fail (network issues during fetch, corrupted repo)
- Race condition if branch is being created while cleanup runs
- User might want to keep review state for a branch they plan to recreate

**Mitigations**:
- Graceful error handling with warnings
- Dry-run mode for manual cleanup
- Age threshold as additional safeguard (don't delete recently-created state)

### Pragmatic Effort Estimate

This is a medium-complexity feature involving:
- Core logic for branch detection and cleanup (~100 lines)
- Configuration additions (~10 lines)
- Command and action registration (~30 lines)
- UI for preview/confirmation (~40 lines)
- Tests (~200 lines)

## Acceptance Criteria

- [ ] `ReviewStore:get_stored_branches(repo_id)` returns list of branches with stored review state
- [ ] `ReviewStore:cleanup_stale_branches(adapter, opts)` removes state for branches that no longer exist in git
- [ ] `:DiffviewReviewCleanup` command triggers cleanup with preview and confirmation
- [ ] `review_cleanup` action can be mapped to a keymap
- [ ] Optional auto-cleanup on DiffView open (controlled by `config.review.auto_cleanup`)
- [ ] Cleanup only affects the current repository
- [ ] `review_cleanup_completed` event is emitted after cleanup
- [ ] All new code paths are covered by tests

## Dependencies & Constraints

- **Dependencies**: Relies on existing `ReviewStore:clear_repo_state()` pattern, `GitAdapter:exec_sync()` for git commands
- **Technical Constraints**: Must handle repositories with many branches efficiently; should not block UI

## Implementation Notes

### Recommended Approach

1. **Add `get_stored_branches` to ReviewStore**: Scan repo directory and return branch names (unsanitized)
2. **Add `get_git_branches` helper**: Run `git for-each-ref --format='%(refname:short)' refs/heads/` via adapter
3. **Add `cleanup_stale_branches` to ReviewStore**: Compare stored vs git branches, delete files for non-existent branches
4. **Add public API in `review.lua`**: `cleanup_stale_reviews(view)` and `get_cleanup_preview(view)`
5. **Add config option**: `review.auto_cleanup = false`
6. **Add command**: `:DiffviewReviewCleanup` with optional `--dry-run` flag
7. **Add listener**: `review_cleanup` in listeners.lua with `vim.ui.select` confirmation
8. **Add auto-cleanup trigger**: In `DiffView:post_open()` if config enabled

### Potential Gotchas

1. **Branch name sanitization is one-way**: `feature/foo` → `feature__foo`, but `feature__foo` could also be a valid branch name. When listing stored branches, need to check both possible original names.

2. **Detached HEAD files**: `detached-<sha>.json` files don't correspond to branch names. Handle separately with age-based logic or skip them.

3. **Empty repo edge case**: A repo might have no branches if it's newly initialized. Handle gracefully.

4. **Windows path separators**: The branch sanitization assumes `/` as separator. Verify this works correctly on Windows.

## Implementation Guide

### Step 1: Add Branch Listing Methods to ReviewStore

**File**: `lua/diffview/review_store.lua`

Add two new methods to `ReviewStore`:

#### 1a. `unsanitize_branch(filename)`
A helper function to convert a sanitized filename back to possible branch names:
- Input: `"feature__foo.json"`
- Output: `{ "feature__foo", "feature/foo" }` (both possibilities since we can't know which was original)
- Strip `.json` extension, then return both the raw name and one with `__` replaced by `/`

#### 1b. `get_stored_branches(repo_id)`
Scan the repo directory and return a table of stored branch information:
```lua
---@return { filename: string, possible_branches: string[] }[]
function ReviewStore:get_stored_branches(repo_id)
  -- Use uv.fs_scandir to iterate the repo directory
  -- For each .json file, call unsanitize_branch
  -- Return list of { filename = "main.json", possible_branches = { "main" } }
end
```

This method should:
- Return empty table if repo directory doesn't exist
- Filter to only `.json` files
- Handle errors gracefully (return empty table)

### Step 2: Add Git Branch Listing to GitAdapter

**File**: `lua/diffview/vcs/adapters/git/init.lua`

Add a new method to get all branch names (local + remote):

```lua
---Get list of all branch names (local and remote-tracking)
---@return string[]|nil branches List of branch names, or nil on error
function GitAdapter:get_all_branches()
  -- Get both local and remote branches
  local out, code = self:exec_sync({
    "for-each-ref",
    "--format=%(refname:short)",
    "refs/heads/",
    "refs/remotes/",
  }, { cwd = self.ctx.toplevel, silent = true })

  if code ~= 0 then
    return nil
  end

  -- Filter out empty lines and normalize remote branch names
  -- e.g., "origin/main" -> also add "main" as a valid name
  local branches = {}
  local seen = {}

  for _, line in ipairs(out or {}) do
    if line ~= "" and not seen[line] then
      seen[line] = true
      table.insert(branches, line)

      -- For remote branches like "origin/main", also add the short form "main"
      local short = line:match("^[^/]+/(.+)$")
      if short and not seen[short] then
        seen[short] = true
        table.insert(branches, short)
      end
    end
  end

  return branches
end
```

Note: We include remote branches and their short forms so that a branch like `origin/feature/foo` will match a stored file for `feature/foo`.

### Step 3: Add Cleanup Logic to ReviewStore

**File**: `lua/diffview/review_store.lua`

Add a method to perform the actual cleanup:

```lua
---@class CleanupResult
---@field deleted_branches string[] Branch names that were deleted
---@field deleted_count integer Number of files deleted
---@field error string|nil Error message if cleanup failed

---@class CleanupOptions
---@field dry_run? boolean If true, don't actually delete, just return what would be deleted
---@field max_age_days? integer Age threshold in days (default: 30). Used for detached HEAD and stale branch cleanup.

---Get the most recent reviewed_at timestamp from a state file
---@param file_path string Path to the JSON file
---@return integer|nil timestamp The most recent reviewed_at timestamp, or nil on error
function ReviewStore:get_latest_review_timestamp(file_path)
  local ok, content = pcall(function()
    local fd = assert(uv.fs_open(file_path, "r", 438))
    local fstat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, fstat.size, 0))
    assert(uv.fs_close(fd))
    return data
  end)

  if not ok or not content then return nil end

  local decode_ok, data = pcall(vim.json.decode, content)
  if not decode_ok or not data or not data.files then return nil end

  local latest = 0
  for _, entry in pairs(data.files) do
    if entry.reviewed_at and entry.reviewed_at > latest then
      latest = entry.reviewed_at
    end
  end

  return latest > 0 and latest or nil
end

---Cleanup stale branches for a repository
---@param adapter VCSAdapter The VCS adapter
---@param opts? CleanupOptions
---@return CleanupResult
function ReviewStore:cleanup_stale_branches(adapter, opts)
  opts = opts or {}
  local max_age_days = opts.max_age_days or 30
  local max_age_seconds = max_age_days * 24 * 60 * 60
  local now = os.time()

  local result = { deleted_branches = {}, deleted_count = 0 }

  -- Get repo ID
  local repo_id = self:get_repo_id(adapter)
  if not repo_id then
    result.error = "Could not determine repository ID"
    return result
  end

  -- Get stored branches
  local stored = self:get_stored_branches(repo_id)
  if #stored == 0 then
    return result  -- Nothing to clean up
  end

  -- Get git branches (local + remote)
  local git_branches = adapter.get_all_branches and adapter:get_all_branches()
  if not git_branches then
    result.error = "Could not get git branches"
    return result
  end

  -- Create lookup set for efficient checking
  local git_branch_set = {}
  for _, branch in ipairs(git_branches) do
    git_branch_set[branch] = true
  end

  local cache_dir = self:get_cache_dir()
  local repo_dir = utils.path:join(cache_dir, repo_id)

  -- Find stale branches (stored branches that don't exist in git)
  for _, stored_info in ipairs(stored) do
    local is_stale = true
    local is_detached = stored_info.filename:match("^detached%-")

    -- Check if ANY of the possible branch names exists (skip for detached HEAD)
    if not is_detached then
      for _, possible_name in ipairs(stored_info.possible_branches) do
        if git_branch_set[possible_name] then
          is_stale = false
          break
        end
      end
    end

    -- For detached HEAD files or stale branches, check age
    if is_stale or is_detached then
      local file_path = utils.path:join(repo_dir, stored_info.filename)
      local latest_ts = self:get_latest_review_timestamp(file_path)

      if latest_ts then
        local age = now - latest_ts
        if age < max_age_seconds then
          is_stale = false  -- Too recent, don't delete
        end
      else
        -- Can't determine age, be conservative and skip
        is_stale = false
      end
    end

    if is_stale then
      table.insert(result.deleted_branches, stored_info.possible_branches[1])

      if not opts.dry_run then
        local file_path = utils.path:join(repo_dir, stored_info.filename)
        local ok = pcall(uv.fs_unlink, file_path)
        if ok then
          result.deleted_count = result.deleted_count + 1
        end
      else
        result.deleted_count = result.deleted_count + 1
      end
    end
  end

  return result
end
```

### Step 4: Add Public API to review.lua

**File**: `lua/diffview/review.lua`

Add two public functions:

```lua
---Preview what stale reviews would be cleaned up (dry run)
---@param view DiffView
---@return CleanupResult
function M.get_cleanup_preview(view)
  if not is_review_enabled() then
    return { deleted_branches = {}, deleted_count = 0, error = "Review is disabled" }
  end

  if not view or not view.adapter then
    return { deleted_branches = {}, deleted_count = 0, error = "No adapter available" }
  end

  local cfg = config.get_config()
  local max_age_days = cfg.review and cfg.review.cleanup_age_days or 30

  local store = review_store.get_store()
  return store:cleanup_stale_branches(view.adapter, { dry_run = true, max_age_days = max_age_days })
end

---Clean up stale reviews for the current repository
---@param view DiffView
---@return CleanupResult
function M.cleanup_stale_reviews(view)
  if not is_review_enabled() then
    return { deleted_branches = {}, deleted_count = 0, error = "Review is disabled" }
  end

  if not view or not view.adapter then
    return { deleted_branches = {}, deleted_count = 0, error = "No adapter available" }
  end

  local cfg = config.get_config()
  local max_age_days = cfg.review and cfg.review.cleanup_age_days or 30

  local store = review_store.get_store()
  local result = store:cleanup_stale_branches(view.adapter, { dry_run = false, max_age_days = max_age_days })

  if result.deleted_count > 0 then
    -- Emit event for UI updates and user notification
    DiffviewGlobal.emitter:emit("review_cleanup_completed", {
      view = view,
      deleted_branches = result.deleted_branches,
      deleted_count = result.deleted_count,
    })
  end

  return result
end
```

### Step 5: Add Configuration Options

**File**: `lua/diffview/config.lua`

In the `M.defaults` table, add to the `review` section:

```lua
review = {
  enabled = true,
  cache_dir = nil,
  auto_cleanup = false,  -- NEW: Enable automatic cleanup on DiffView open
  cleanup_age_days = 30, -- NEW: Age threshold for cleanup (stale branches and detached HEAD)
  symbols = {
    unreviewed = " ",
    reviewed = "●",
    changed = "◐",
  },
},
```

### Step 6: Add Action Registration

**File**: `lua/diffview/actions.lua`

Add `"review_cleanup"` to the `action_names` array (around line where other review actions are listed).

### Step 7: Add Listener for Manual Cleanup

**File**: `lua/diffview/scene/views/diff/listeners.lua`

Add the `review_cleanup` listener function in the returned listeners table:

```lua
review_cleanup = function()
  if not cfg.review or not cfg.review.enabled then
    utils.info("Review feature is not enabled")
    return
  end

  -- Get preview first
  local preview = review.get_cleanup_preview(view)

  if preview.error then
    utils.warn("Cleanup preview failed: " .. preview.error)
    return
  end

  if #preview.deleted_branches == 0 then
    utils.info("No stale review data found for this repository")
    return
  end

  -- Build confirmation message
  local branch_list = table.concat(preview.deleted_branches, ", ")
  if #branch_list > 60 then
    branch_list = branch_list:sub(1, 57) .. "..."
  end

  vim.ui.select({ "Yes", "No" }, {
    prompt = ("Clean up review state for %d stale branch(es)? [%s]"):format(
      preview.deleted_count,
      branch_list
    ),
  }, function(choice)
    if choice == "Yes" then
      local result = review.cleanup_stale_reviews(view)
      if result.error then
        utils.warn("Cleanup failed: " .. result.error)
      else
        utils.info(("Cleaned up review state for %d branch(es)"):format(result.deleted_count))
      end
    end
  end)
end,
```

### Step 8: Add User Command

**File**: `plugin/diffview.lua`

Add a new command for manual cleanup (after the other command definitions):

```lua
command("DiffviewReviewCleanup", function(ctx)
  local lib = require("diffview.lib")
  local review = require("diffview.review")
  local utils = require("diffview.utils")

  local view = lib.get_current_view()
  if not view then
    -- Try to create a temporary adapter for current directory
    local diffview = require("diffview")
    local adapter = diffview.get_adapter()
    if not adapter then
      utils.warn("Not in a git repository")
      return
    end
    -- Create minimal view-like object
    view = { adapter = adapter }
  end

  local dry_run = ctx.bang  -- Use ! for dry-run mode

  if dry_run then
    local preview = review.get_cleanup_preview(view)
    if preview.error then
      utils.warn("Preview failed: " .. preview.error)
      return
    end
    if #preview.deleted_branches == 0 then
      utils.info("No stale review data found")
    else
      utils.info(("Would clean up %d branch(es): %s"):format(
        preview.deleted_count,
        table.concat(preview.deleted_branches, ", ")
      ))
    end
  else
    -- Trigger the action which shows confirmation UI
    require("diffview").emit("review_cleanup")
  end
end, { nargs = 0, bang = true })
```

### Step 9: Add Optional Auto-Cleanup

**File**: `lua/diffview/scene/views/diff/diff_view.lua`

In the `DiffView:post_open()` method, add auto-cleanup logic after the review state is loaded:

```lua
function DiffView:post_open()
  -- ... existing code to load review state ...

  -- Auto-cleanup stale branches if enabled (after review state is loaded)
  local cfg = config.get_config()
  if cfg.review and cfg.review.enabled and cfg.review.auto_cleanup then
    -- Run async to not block view opening
    vim.schedule(function()
      local result = review.cleanup_stale_reviews(self)
      if result.deleted_count > 0 then
        utils.info(("Auto-cleaned %d stale branch review state(s)"):format(result.deleted_count))
      end
    end)
  end

  -- ... rest of existing code ...
end
```

### Step 10: Add Event Emitter for Cleanup Completion

**File**: `lua/diffview/init.lua`

In the user autocommand emitters section, add:

```lua
DiffviewGlobal.emitter:on("review_cleanup_completed", function(_)
  api.nvim_exec_autocmds("User", { pattern = "DiffviewReviewCleanupCompleted", modeline = false })
end)
```

### Step 11: Write Tests

**File**: `lua/diffview/tests/functional/review_cleanup_spec.lua`

Create comprehensive tests:

1. **`ReviewStore:get_stored_branches()` tests**:
   - Returns empty table when repo directory doesn't exist
   - Returns correct branches for stored JSON files
   - Handles branch names with slashes (sanitized as `__`)
   - Skips non-JSON files

2. **`ReviewStore:cleanup_stale_branches()` tests**:
   - Returns error when repo_id cannot be determined
   - Returns error when git branches cannot be listed
   - Dry run mode returns what would be deleted without deleting
   - Actually deletes files when not in dry run mode
   - Preserves branches that still exist in git (local or remote)
   - Handles the double-underscore ambiguity correctly
   - Cleans up detached HEAD files older than max_age_days
   - Preserves detached HEAD files newer than max_age_days
   - Cleans up stale branch files only if older than max_age_days
   - Respects configurable max_age_days parameter

3. **`ReviewStore:get_latest_review_timestamp()` tests**:
   - Returns nil for non-existent file
   - Returns nil for malformed JSON
   - Returns correct timestamp for single file entry
   - Returns most recent timestamp when multiple files exist

4. **`review.cleanup_stale_reviews()` tests**:
   - Returns appropriate result when review is disabled
   - Returns appropriate result when no view provided
   - Emits `review_cleanup_completed` event on successful cleanup
   - Clears correct files from disk

5. **Integration tests**:
   - Test with mock git adapter
   - Test command execution (`:DiffviewReviewCleanup`)

### Manual Testing Steps

1. Create a test repo with several branches
2. Open diffview and mark files as reviewed on multiple branches
3. Delete some branches via `git branch -d <name>`
4. Run `:DiffviewReviewCleanup!` (dry run) to see preview
5. Run `:DiffviewReviewCleanup` to perform actual cleanup
6. Verify the JSON files for deleted branches are removed
7. Verify JSON files for existing branches are preserved
8. Test auto-cleanup by enabling `review.auto_cleanup` and reopening diffview
