---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Storage for review state
goal: ""
id: 2
uuid: aae1042d-6942-47bc-8470-5d7ac9ca8bc6
generatedBy: agent
status: done
priority: medium
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
planGeneratedAt: 2026-01-15T08:23:14.945Z
promptsGeneratedAt: 2026-01-15T08:23:14.945Z
createdAt: 2026-01-15T00:25:49.542Z
updatedAt: 2026-01-15T19:27:20.406Z
tasks:
  - title: Add review configuration options to config.lua
    done: true
    description: >-
      Add new configuration options under a `review` key in the config:

      - `review.enabled` (boolean, default: true) - Enable/disable review mode
      entirely

      - `review.cache_dir` (string, default: nil) - Custom cache directory,
      falls back to `~/.cache/diffview.nvim/reviews/`


      Follow the existing pattern in config.lua for defining defaults and
      merging user config.
  - title: Create ReviewStore module with OOP structure
    done: true
    description: >-
      Create `lua/diffview/review_store.lua` with:

      1. `ReviewStore` class using `oop.create_class()`

      2. Singleton pattern (module-level instance variable)

      3. `ReviewEntry` structure: `{ blob_hash: string, reviewed_at: number }`

      4. `ReviewState` class with fields: `repo_id`, `branch`, `files`
      (table<string, ReviewEntry>)

      5. `ReviewStore:init()` that reads cache_dir from config

      6. `ReviewStore:get_cache_dir()` that returns configured or default cache
      path
  - title: Implement repo identification using initial commit hash
    done: true
    description: >-
      Add method `ReviewStore:get_repo_id(adapter)` that:

      1. Runs `git rev-list --max-parents=0 HEAD` via adapter's exec_sync

      2. Takes first 12 characters of the initial commit SHA as the repo
      identifier

      3. Caches result per adapter.ctx.toplevel to avoid repeated git calls


      This ensures multiple checkouts/clones of the same repo share review
      state.
  - title: Implement branch name sanitization
    done: true
    description: |-
      Add method `ReviewStore:sanitize_branch(branch)` that:
      1. Replaces `/` with `__` in branch names
      2. Returns the sanitized string suitable for use as a filename

      Example: `feature/add-login` becomes `feature__add-login`
  - title: Implement file I/O operations for review state
    done: true
    description: >-
      Add async methods to ReviewStore:

      1. `ensure_cache_dir(repo_id)` - Create `<cache_dir>/<repo_id>/` directory
      if missing using path.lua async.mkdir

      2. `get_state_path(repo_id, branch)` - Return full path to JSON file

      3. `load_state(adapter, branch)` - Read JSON file, parse with
      vim.json.decode, return ReviewState or new empty state

      4. `save_state(state)` - Serialize with vim.json.encode, write immediately
      with async.write_file


      On I/O errors, show warning via `utils.warn()` and continue gracefully.
  - title: Implement ReviewState class with file management methods
    done: true
    description: >-
      Add methods to ReviewState class:

      1. `get_file(path)` - Return ReviewEntry or nil

      2. `set_file_reviewed(path, blob_hash)` - Store entry with current
      timestamp, trigger save

      3. `clear_file(path)` - Remove entry, trigger save

      4. `clear_all()` - Empty files table, trigger save

      5. `get_file_status(path, current_blob_hash)` - Compare hashes, return
      'unreviewed' | 'reviewed' | 'changed'
  - title: Add branch name retrieval to GitAdapter
    done: true
    description: >-
      Add method `GitAdapter:get_current_branch()` that:

      1. Runs `git rev-parse --abbrev-ref HEAD`

      2. Returns branch name or the commit SHA if in detached HEAD state


      Check if this method already exists; if similar functionality exists,
      reuse it.
  - title: Implement blob hash verification
    done: true
    description: |-
      Add method `ReviewStore:verify_blob_exists(adapter, blob_hash)` that:
      1. Runs `git cat-file -e <blob_hash>` via adapter
      2. Returns true if exit code is 0 (blob exists)
      3. Returns false if blob was garbage collected

      This is needed for Plan 4 when showing diff since last review.
  - title: Integrate ReviewStore with DiffView
    done: true
    description: >-
      Modify `lua/diffview/scene/views/diff/diff_view.lua`:

      1. Add `review_state` field to DiffView class

      2. In `post_open()`, after files are loaded, call
      `review_store:load_state(adapter, branch)`

      3. Store result in `self.review_state`

      4. Add method `get_file_review_status(file_entry)` that delegates to
      review_state


      Only load if `config.review.enabled` is true.
  - title: Create public API for review functions
    done: true
    description: >-
      Add `lua/diffview/review.lua` with public functions:

      1. `mark_file_reviewed(view, file_entry)` - Get blob hash via adapter,
      call review_state:set_file_reviewed

      2. `mark_all_reviewed(view)` - Iterate all files in view.files, mark each
      reviewed

      3. `clear_file_review(view, file_entry)` - Call review_state:clear_file

      4. `clear_all_reviews(view)` - Call review_state:clear_all

      5. `get_file_status(view, file_entry)` - Return review status


      Expose via `require('diffview').review` table in init.lua.
  - title: Emit events when review state changes
    done: true
    description: >-
      When review state changes, emit events via DiffviewGlobal.emitter:

      1. `review_file_marked` - When a file is marked reviewed

      2. `review_file_cleared` - When a file's review is cleared

      3. `review_all_cleared` - When all reviews are cleared


      Include view and file_entry in event payload. FilePanel will use these in
      Plan 3.
  - title: Handle detached HEAD state
    done: true
    description: >-
      In `GitAdapter:get_current_branch()`:

      1. If `git rev-parse --abbrev-ref HEAD` returns 'HEAD', we're in detached
      state

      2. In that case, get the commit SHA via `git rev-parse HEAD`

      3. Return a prefix like `detached-<short-sha>` as the branch identifier


      This ensures reviews still work when not on a branch.
  - title: Write unit tests for ReviewStore
    done: true
    description: |-
      Create `lua/diffview/tests/review_store_spec.lua` with tests for:
      1. `sanitize_branch()` - Test `/` replacement
      2. `get_file_status()` - Test unreviewed/reviewed/changed states
      3. `set_file_reviewed()` and `get_file()` - Test storage and retrieval
      4. `clear_file()` and `clear_all()` - Test clearing state
      5. JSON serialization/deserialization roundtrip
      6. Config option handling (enabled, cache_dir)

      Follow existing test patterns in the codebase.
  - title: "Address Review Feedback: The save_state() function uses synchronous
      uv.fs_open/fs_write/fs_close calls inside an async.void wrapper. While
      wrapped in async.void, the actual file operations are blocking synchronous
      calls. More critically, set_file_reviewed(), clear_file(), and clear_all()
      all trigger save_state() immediately on every single file mark/clear
      operation. This means if a user calls mark_all_reviewed() on a view with
      100 files, it will write to disk 100 times in rapid succession, causing
      performance degradation and potential race conditions with rapid
      successive writes."
    done: true
    description: >-
      The save_state() function uses synchronous uv.fs_open/fs_write/fs_close
      calls inside an async.void wrapper. While wrapped in async.void, the
      actual file operations are blocking synchronous calls. More critically,
      set_file_reviewed(), clear_file(), and clear_all() all trigger
      save_state() immediately on every single file mark/clear operation. This
      means if a user calls mark_all_reviewed() on a view with 100 files, it
      will write to disk 100 times in rapid succession, causing performance
      degradation and potential race conditions with rapid successive writes.


      Suggestion: Have mark_all_reviewed() in review.lua set all files first
      then save once at the end rather than triggering save on each
      set_file_reviewed() call. Add a flag to set_file_reviewed() to indicate
      whether or not it should trigger a save (default true).


      Related file: lua/diffview/review_store.lua:48-72, 284-288
changedFiles:
  - .rmfilter/config/rmplan.yml
  - AGENTS.md
  - CLAUDE.md
  - lua/diffview/config.lua
  - lua/diffview/init.lua
  - lua/diffview/review.lua
  - lua/diffview/review_store.lua
  - lua/diffview/scene/views/diff/diff_view.lua
  - lua/diffview/tests/functional/git_adapter_spec.lua
  - lua/diffview/tests/functional/review_api_spec.lua
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

Create a system for storing entries about when a file was reviewed. Each review entry should include:
- The repository directory
- The branch name
- The path to each file marked reviewed
- The **git blob hash** of the file content when marked reviewed
- Timestamp of when the file was reviewed

## Why Blob Hash?

We use the git blob hash (content hash) rather than commit hash because:
1. **Survives rebases** - After rebasing, commit hashes change but blob hashes for unchanged content remain the same
2. **Enables diffing** - We can retrieve the old content with `git cat-file blob <hash>` even if the original commit no longer exists
3. **Accurate change detection** - Same content = same hash, regardless of git history

## Change Detection

To check if a file changed since review:
```
current_blob = git rev-parse HEAD:path/to/file
changed = (current_blob != stored_blob)
```

## Showing Diff Since Last Review

To show only changes since the last review:
```
old_content = git cat-file blob <stored_blob>
# diff old_content against current file
```

If the blob was garbage collected, fall back to showing the full diff with a message that the previous review state is no longer available.

## Storage Location

This should be stored under ~/.cache/diffview.nvim/, and can use sqlite if that's convenient in Lua/neovim or just a set of files otherwise.

---

## Research

### Overview

This plan implements a persistent storage system for tracking which files have been reviewed in a diff view. The storage needs to track review state per repository, per branch, per file, enabling users to resume reviews across sessions and detect which files have changed since their last review.

### Key Findings

#### 1. No Existing Persistence Mechanism

The diffview.nvim codebase currently has **no persistent storage system**. All state is runtime-only:
- Configuration is loaded from user setup and stored in `config._config`
- Global state lives in `DiffviewGlobal.state` (runtime table)
- Views maintain their own in-memory state
- The Logger writes to a temporary file, but this is for debugging, not structured data

This means we need to build the storage layer from scratch.

#### 2. Existing Path and File Utilities

The codebase has comprehensive file/path utilities we can leverage:

**PathLib** (`lua/diffview/path.lua`):
- `pl:join(...)` - Join path segments
- `pl:parent(path)` - Get parent directory
- `pl:is_dir(path)` - Check if directory exists
- `pl:readable(path)` - Check if file is readable
- `pl:vim_expand(path)` - Expand vim path variables

**Async File Operations** (`lua/diffview/path.lua`):
- `async.mkdir(path, mode)` - Create directory asynchronously
- `async.read_file(path)` - Read file asynchronously
- `async.write_file(path, content)` - Write file asynchronously

#### 3. Git Blob Hash Retrieval

The GitAdapter already has a method for getting blob hashes:

**`GitAdapter:file_blob_hash(path, rev_arg)`** (lua/diffview/vcs/adapters/git/init.lua, lines 1314-1328):
```lua
function GitAdapter:file_blob_hash(path, rev_arg)
  local out, code = self:exec_sync({
    "rev-parse",
    "--revs-only",
    fmt("%s:%s", rev_arg or "", path)
  }, {
    cwd = self.ctx.toplevel,
    retry = 2,
    fail_on_empty = true,
  })
  if code ~= 0 then return end
  return vim.trim(out[1])
end
```

This is exactly what we need for storing the blob hash when marking a file as reviewed. It handles retries and returns nil on failure.

#### 4. Async Patterns in the Codebase

The codebase uses a custom async/await system (`lua/diffview/async.lua`):
- `async.wrap(fn)` - Wraps callback-based functions for await
- `async.void(fn)` - Fire-and-forget async operations
- `async.sync_wrap(fn)` - Blocking wait for sync contexts

Storage operations should be async to avoid blocking the UI.

#### 5. OOP System

The codebase uses a custom OOP system (`lua/diffview/oop.lua`):
- `oop.create_class("ClassName", SuperClass)` - Creates a class
- Classes have `init()` constructor method
- Supports inheritance and metamethods

The ReviewStore should be a proper class following this pattern.

#### 6. Repository Context

Each DiffView/GitAdapter has context about the repository:
- `adapter.ctx.toplevel` - Repository root directory (absolute path)
- `adapter.ctx.dir` - `.git` directory path
- Current branch can be obtained via `git rev-parse --abbrev-ref HEAD`

#### 7. FileEntry Structure

FileEntry objects (`lua/diffview/scene/file_entry.lua`) contain:
- `path` - Relative path in repo
- `absolute_path` - Full path on disk
- `status` - Git status (M, A, D, R, etc.)
- `stats` - Git stats (additions, deletions, conflicts)
- `kind` - "conflicting", "working", or "staged"

We need to extend this or create a parallel tracking system for review state.

#### 8. Event System

The codebase uses EventEmitter (`lua/diffview/events.lua`) for pub/sub:
- `emitter:on(event_id, callback)` - Subscribe to events
- `emitter:emit(event_id, ...)` - Emit events
- Events like `files_updated`, `file_open_post` exist

We can emit events when review state changes so the UI can react.

### Storage Format Considerations

#### Option A: JSON Files (Recommended)

```
~/.cache/diffview.nvim/reviews/
└── <repo_hash>/
    └── <branch_name>.json
```

Each JSON file contains:
```json
{
  "version": 1,
  "repo_path": "/absolute/path/to/repo",
  "branch": "feature-branch",
  "files": {
    "src/foo.lua": {
      "blob_hash": "abc123...",
      "reviewed_at": 1705276800
    },
    "src/bar.lua": {
      "blob_hash": "def456...",
      "reviewed_at": 1705276801
    }
  }
}
```

**Pros:**
- Simple to implement with `vim.json.encode/decode`
- Human-readable for debugging
- No external dependencies
- Each branch is a separate file (easy cleanup)

**Cons:**
- Full file rewrite on each update
- Potentially slow for very large reviews (unlikely in practice)

#### Option B: SQLite

```
~/.cache/diffview.nvim/reviews.db
```

**Pros:**
- Efficient updates
- Query capabilities
- Atomic transactions

**Cons:**
- Requires SQLite library (`sqlite.lua` or LuaJIT FFI)
- More complex implementation
- Adds dependency

**Decision:** Use JSON files. Simple, no dependencies, human-readable for debugging.

### Key Repository Identification

We need a stable identifier for each repository that:
1. Is filesystem-safe (can be used in filenames)
2. Is unique per repo
3. Survives directory moves and works across multiple checkouts

**Decision:** Use a hash of the **initial commit SHA** (obtained via `git rev-list --max-parents=0 HEAD`). This approach:
- Survives repo moves and renames
- Shares review state across multiple checkouts of the same repo
- Shares review state across clones
- Works with git worktrees

### Branch Name Handling

Branch names can contain characters that are problematic in filenames:
- `/` (e.g., `feature/foo`) - Replace with `__`

**Decision:** Sanitize by replacing `/` with `__`. Simple and human-readable (e.g., `feature__add-login.json`).

### Scope Decisions

- **Git only** - Mercurial support deferred to future work
- **DiffView only** - FileHistoryView not included in initial implementation
- **Branch-only state** - Review state is per-branch, not per-revision-range
- **Immediate writes** - No debouncing; save on every mark action
- **Public API** - Expose review functions via `require("diffview").review`
- **Error handling** - Show `vim.notify` warning on I/O failures

### Architectural Pattern

```
ReviewStore (singleton)
├── load_repo_state(repo_path, branch) -> ReviewState
├── save_repo_state(state)
├── get_file_review(state, path) -> ReviewEntry | nil
├── set_file_reviewed(state, path, blob_hash)
├── clear_file_review(state, path)
├── clear_all_reviews(state)
└── cleanup_stale_branches(repo_path, existing_branches)

ReviewState
├── repo_path: string
├── branch: string
├── files: table<string, ReviewEntry>
├── dirty: boolean
└── save() -> async

ReviewEntry
├── blob_hash: string
├── reviewed_at: number (timestamp)
```

### Integration Points

1. **DiffView** - Needs access to ReviewStore to:
   - Load review state when opening a view
   - Check file review status for rendering
   - Update review state when user marks file reviewed

2. **FilePanel** - Needs to:
   - Render review status indicator per file
   - React to review state changes (re-render)

3. **Actions** - New actions needed:
   - `review_mark_file` - Mark current file reviewed
   - `review_mark_all` - Mark all files reviewed
   - `review_clear_file` - Clear review for current file
   - `review_clear_all` - Clear all reviews

4. **Config** - New configuration options:
   - `review.enabled` - Enable/disable review mode (default: true)
   - `review.cache_dir` - Custom cache directory (default: `~/.cache/diffview.nvim/reviews/`)

### Potential Gotchas

1. **Concurrent Access** - Multiple Neovim instances could modify the same review file. Use file locking or accept last-write-wins semantics.

2. **Garbage Collected Blobs** - If `git gc` removes the blob, we can't show the diff. Need to handle this gracefully with a fallback message.

3. **Large Repositories** - Repos with thousands of changed files could make the JSON file large. Consider pagination or lazy loading if this becomes an issue.

4. **Detached HEAD** - When in detached HEAD state, there's no branch name. Use the commit hash or a special identifier.

5. **Worktrees** - Git worktrees share the object store but have different working directories. The repo identification should handle this.

---

## Implementation Guide

### Step 1: Create the ReviewStore Module

Create a new module at `lua/diffview/review_store.lua`:

1. Define the `ReviewStore` class using `oop.create_class()`
2. Implement singleton pattern (store instance in module-level variable)
3. Define data structures for `ReviewState` and `ReviewEntry`

Key methods to implement:
- `ReviewStore:init()` - Initialize with cache directory path from config
- `ReviewStore:get_cache_dir()` - Returns configured cache dir or `~/.cache/diffview.nvim/reviews/`
- `ReviewStore:repo_key(adapter)` - Returns hash of initial commit SHA (via `git rev-list --max-parents=0 HEAD`)
- `ReviewStore:branch_filename(branch)` - Returns sanitized branch filename (replace `/` with `__`)

### Step 2: Implement File I/O Operations

Add async methods for persistence:

1. `ReviewStore:ensure_cache_dir()` - Create cache directory if missing
   - Use `async.mkdir()` from path.lua
   - Create nested structure: `~/.cache/diffview.nvim/reviews/<repo_hash>/`

2. `ReviewStore:load_state(toplevel, branch)` - Load review state from disk
   - Compute file path from repo + branch
   - Read file with `async.read_file()`
   - Parse JSON with `vim.json.decode()`
   - Return `ReviewState` object or new empty state

3. `ReviewStore:save_state(state)` - Persist review state to disk
   - Serialize with `vim.json.encode()`
   - Write with `async.write_file()`
   - Write immediately on each call (no debouncing)
   - On I/O failure, show warning via `vim.notify`

### Step 3: Implement Review State Management

1. `ReviewState:get_file(path)` - Get review entry for a file
   - Returns `{ blob_hash, reviewed_at }` or nil

2. `ReviewState:set_file_reviewed(path, blob_hash)` - Mark file reviewed
   - Store blob hash and current timestamp
   - Mark state as dirty

3. `ReviewState:clear_file(path)` - Remove review for a file
   - Delete entry from files table
   - Mark state as dirty

4. `ReviewState:clear_all()` - Clear all reviews
   - Empty the files table
   - Mark state as dirty

5. `ReviewState:is_file_changed(path, current_blob_hash)` - Check if file changed
   - Compare stored hash with current hash
   - Returns: "unreviewed" | "reviewed" | "changed"

### Step 4: Integrate with DiffView

Modify `lua/diffview/scene/views/diff/diff_view.lua`:

1. Add `review_state` field to DiffView
2. Load review state in `post_open()` after files are loaded
3. Expose method `get_file_review_status(file_entry)` that returns review state

The review state should be loaded once when the view opens and cached. Changes are persisted immediately but loaded state is kept in memory.

### Step 5: Implement Blob Hash Verification

Add a method to check if a stored blob still exists:

```lua
ReviewStore:verify_blob_exists(adapter, blob_hash)
  -- Run: git cat-file -e <blob_hash>
  -- Returns true if blob exists, false if garbage collected
```

This is needed when showing "diff since last review" - if the blob is gone, we need to show a message and fall back to full diff.

### Step 6: Add Branch Name Retrieval

The GitAdapter needs a method to get the current branch name:

```lua
GitAdapter:get_current_branch()
  -- Run: git rev-parse --abbrev-ref HEAD
  -- Returns branch name or "HEAD" if detached
```

This may already exist or be easy to add based on existing patterns.

### Step 7: Create Public API

Add functions to `lua/diffview/init.lua` or a new `lua/diffview/review.lua`:

- `review.mark_file_reviewed(view, file_entry)` - Mark file as reviewed
- `review.mark_all_reviewed(view)` - Mark all files as reviewed
- `review.clear_file_review(view, file_entry)` - Clear file review
- `review.clear_all_reviews(view)` - Clear all reviews for current branch
- `review.get_file_status(view, file_entry)` - Get review status

These will be called by actions and can be used programmatically.

### Step 8: Emit Events for UI Updates

When review state changes, emit events so the UI can update:

```lua
DiffviewGlobal.emitter:emit("review_state_changed", {
  view = view,
  file = file_entry,
  status = new_status
})
```

The FilePanel can listen to this and re-render affected files.

### Step 9: Handle Edge Cases

1. **Detached HEAD**: Use commit hash as "branch" identifier
2. **Missing blob**: Check with `git cat-file -e`, show fallback message
3. **Concurrent writes**: Use simple last-write-wins (review state is not critical data)
4. **Review disabled**: Check `config.review.enabled` before any operations

### Manual Testing Steps

1. Open a diff view with multiple files
2. Verify review state file doesn't exist initially
3. Mark a file as reviewed, verify file is created
4. Close and reopen view, verify state is loaded
5. Modify a reviewed file, verify "changed" status
6. Clear review and verify file is updated
7. Test with special branch names (slashes, unicode)
8. Test detached HEAD state
9. Test cleanup of non-existent branches

### Dependencies

- Plan 2 is foundational and has no dependencies on other plans
- Plans 3, 6, 7, 4, 5, 9, 8 all depend on this storage system being in place

### Acceptance Criteria

- [ ] ReviewStore module created with proper OOP structure
- [ ] Review state persists to `~/.cache/diffview.nvim/reviews/`
- [ ] State loads correctly when reopening a diff view
- [ ] Files can be marked as reviewed with blob hash stored
- [ ] Changed files are detected by comparing blob hashes
- [ ] Blob existence verification works for garbage-collected blobs
- [ ] Branch names with special characters are handled
- [ ] Detached HEAD state is handled gracefully
- [ ] Configuration options work (`review.enabled`, `review.cache_dir`)
- [ ] Public API exposed via `require("diffview").review`
- [ ] Multiple checkouts of same repo share review state
- [ ] I/O errors show warning notification
- [ ] Unit tests cover core ReviewStore operations

## Current Progress
### Current State
- All 14 tasks complete with full test coverage (131 tests passing: 46 for ReviewStore, 39 for Review API, 9 for GitAdapter, rest for other modules)
- Plan is complete and ready for dependent plans to proceed

### Completed (So Far)
- Task 1: Added review.enabled and review.cache_dir config options
- Task 2: Created ReviewStore class with singleton pattern
- Task 3: Implemented get_repo_id() using initial commit hash (12 chars)
- Task 4: Implemented sanitize_branch() replacing / with __
- Task 5: Implemented ensure_cache_dir(), get_state_path(), load_state_sync(), save_state()
- Task 6: Implemented ReviewState with get_file(), set_file_reviewed(), clear_file(), clear_all(), get_file_status()
- Task 7: Implemented GitAdapter:get_current_branch() at lua/diffview/vcs/adapters/git/init.lua:1313-1366
- Task 8: Implemented ReviewStore:verify_blob_exists() using git cat-file -e
- Task 9: Integrated ReviewStore with DiffView - added review_state field, loading in post_open(), get_file_review_status() method
- Task 10: Created public API at lua/diffview/review.lua with mark_file_reviewed, mark_all_reviewed, clear_file_review, clear_all_reviews, get_file_status
- Task 11: Events emitted via DiffviewGlobal.emitter: review_file_marked, review_file_cleared, review_all_cleared
- Task 12: Detached HEAD handling integrated into get_current_branch() - returns "detached-<short-sha>" format
- Task 13: Unit tests complete - review_store_spec.lua covers sanitize_branch, get_file_status, set_file_reviewed/get_file, clear_file/clear_all, JSON roundtrip, config options; review_api_spec.lua covers public API and event emission
- Task 14: Added skip_save parameter to set_file_reviewed() and updated mark_all_reviewed() to save only once at the end (batch operation optimization)

### Remaining
- None

### Next Iteration Guidance
- Plan complete. Dependent plans (3, 4, 5, 6, 7, 8, 9) can now proceed.

### Decisions / Changes
- Used synchronous load_state_sync() instead of async load_state() because async.void() cannot return values in this codebase's async pattern
- Added version field validation in from_table() for future migration support
- Test file placed in lua/diffview/tests/functional/ to match existing test structure
- review.enabled check implemented in DiffView:post_open() and review API functions
- get_current_branch() returns fallback strings ("unknown", "detached-unknown") rather than nil to ensure review state can always be saved
- DiffView:get_file_review_status() implemented as a convenience method alongside review.get_file_status()
- Events include appropriate payloads: review_file_marked includes view, file_entry, blob_hash; clear events include view, file_entry
- Task 14: Added skip_save parameter (default false) to set_file_reviewed() for batch operations; mark_all_reviewed() now saves once at end instead of N times

### Risks / Blockers
- None
