---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Custom file list from JSON
goal: ""
id: 11
uuid: 5dcd69e7-cfd7-4f2c-a8b7-16bc79cfac87
generatedBy: agent
status: done
priority: medium
planGeneratedAt: 2026-01-22T16:03:47.303Z
promptsGeneratedAt: 2026-01-22T16:03:47.303Z
createdAt: 2026-01-22T14:46:09.574Z
updatedAt: 2026-01-22T22:45:54.305Z
tasks:
  - title: Create JSON loader module
    done: true
    description: Create `lua/diffview/json_loader.lua` with functions to load and
      validate JSON files. Implement `load_json(file_path)` that reads the file
      using vim.loop, parses with `vim.json.decode()`, and validates the schema
      (groups required, each group has name and files array with path fields).
      Return structured JsonData or error string.
  - title: Create GroupedFileDict class
    done: true
    description: Create `lua/diffview/grouped_file_dict.lua` with a class that
      supports arbitrary named groups. Implement `init(title)`, `add_group(name,
      files)`, `len()`, `iter()`, `update_file_trees()`, and `is_grouped()`
      methods. Each group should contain name, files array, and tree (FileTree
      instance).
  - title: Add json_view_open function to lib.lua
    done: true
    description: "Add `json_view_open(json_path, args)` to `lua/diffview/lib.lua`.
      This function should: load JSON via json_loader, get git adapter, parse
      rev args (reusing DiffviewOpen logic), run git diff to get file statuses,
      filter to only files in JSON with changes, build GroupedFileDict, warn
      about missing files, error if all groups empty, and create the diff view."
  - title: Modify FilePanel for custom groups
    done: true
    description: Update `lua/diffview/scene/views/diff/file_panel.lua` to detect
      GroupedFileDict and dynamically build component schema. Modify
      `update_components()` to iterate over groups and create title/files/margin
      sections for each. Update `ordered_file_list()` to return files from all
      groups.
  - title: Extend render.lua for custom groups
    done: true
    description: Modify `lua/diffview/scene/views/diff/render.lua` to handle
      GroupedFileDict. When `panel.files.groups` exists, iterate through groups
      and render each with its name as the section header, file count, and files
      using existing `render_files()` function. Also render the optional title
      in the header.
  - title: Register DiffviewOpenJson command
    done: true
    description: Add the `DiffviewOpenJson` command in `plugin/diffview.lua` that
      takes a JSON path and optional rev arguments. Add `open_json(json_path,
      rev_args)` to `lua/diffview/init.lua`. Add completion support in the
      completers table - complete file paths for first arg, rev args for
      subsequent args.
  - title: Write tests for JSON loading and grouped files
    done: true
    description: "Create tests in `lua/diffview/tests/functional/`:
      json_loader_spec.lua for parsing and validation,
      grouped_file_dict_spec.lua for group management and iteration. Test valid
      JSON, schema validation errors, missing fields, and edge cases like empty
      groups."
  - title: Write integration tests for DiffviewOpenJson
    done: true
    description: "Create json_view_spec.lua with integration tests covering: view
      creation with valid JSON and rev args, file filtering (files with no
      changes excluded), missing file warnings, all-groups-empty error, panel
      rendering with custom groups, and both tree and list view modes."
  - title: "Address Review Feedback: DiffviewOpenJson drops staged-only and
      untracked files in the default stage↔local case. `build_grouped_files`
      only calls `adapter:tracked_files` once with the left/right revs, so for
      the common `STAGE..LOCAL` default it only returns *unstaged* changes.
      Files that are staged-only or untracked (but listed in JSON) are silently
      filtered out because `file_exists_in_rev` returns true for local paths, so
      they aren't warned either. This violates the \"same rev argument behavior
      as DiffviewOpen\" requirement and yields incomplete file lists. Fix by
      mirroring `vcs.utils.diff_file_list`: when `left.type == STAGE` and
      `right.type == LOCAL`, add a second `tracked_files` call for staged
      (`--cached` / HEAD..index) and `untracked_files` when
      `adapter:show_untracked` is true, then union the results before filtering
      to JSON paths."
    done: true
    description: >-
      DiffviewOpenJson drops staged-only and untracked files in the default
      stage↔local case. `build_grouped_files` only calls `adapter:tracked_files`
      once with the left/right revs, so for the common `STAGE..LOCAL` default it
      only returns *unstaged* changes. Files that are staged-only or untracked
      (but listed in JSON) are silently filtered out because
      `file_exists_in_rev` returns true for local paths, so they aren't warned
      either. This violates the "same rev argument behavior as DiffviewOpen"
      requirement and yields incomplete file lists. Fix by mirroring
      `vcs.utils.diff_file_list`: when `left.type == STAGE` and `right.type ==
      LOCAL`, add a second `tracked_files` call for staged (`--cached` /
      HEAD..index) and `untracked_files` when `adapter:show_untracked` is true,
      then union the results before filtering to JSON paths.


      Suggestion: Reuse `vcs.utils.diff_file_list` and filter by JSON path set,
      or explicitly add staged/untracked retrieval and merge with the
      working/conflict entries before grouping.


      Related file: lua/diffview/lib.lua:97-181
  - title: "Address Review Feedback: Rev-arg completion is broken after the JSON
      path. `DiffviewOpenJson` delegates to `DiffviewOpen`'s completer, but
      `DiffviewOpen` sets `has_rev_arg` as soon as it sees any non-flag argument
      before the current one. The JSON path (arg2) counts as a rev arg, so rev
      candidates are never offered for arg3+. This contradicts the plan's
      \"reuse DiffviewOpen completion for rev args after the JSON path\"."
    done: true
    description: >-
      Rev-arg completion is broken after the JSON path. `DiffviewOpenJson`
      delegates to `DiffviewOpen`'s completer, but `DiffviewOpen` sets
      `has_rev_arg` as soon as it sees any non-flag argument before the current
      one. The JSON path (arg2) counts as a rev arg, so rev candidates are never
      offered for arg3+. This contradicts the plan's "reuse DiffviewOpen
      completion for rev args after the JSON path".


      Suggestion: Implement a dedicated completer that ignores arg2 (json path)
      when computing `has_rev_arg`, or wrap/shift `ctx.args` before delegating
      to `DiffviewOpen`.


      Related file: lua/diffview/init.lua:240-245
  - title: "Address Review Feedback: `read_file` leaks file descriptors on error
      paths. If `uv.fs_fstat` or `uv.fs_read` fails, the `assert` throws before
      `uv.fs_close`, leaving the FD open. This is a resource leak that can
      accumulate on repeated failures."
    done: true
    description: >-
      `read_file` leaks file descriptors on error paths. If `uv.fs_fstat` or
      `uv.fs_read` fails, the `assert` throws before `uv.fs_close`, leaving the
      FD open. This is a resource leak that can accumulate on repeated failures.


      Suggestion: Ensure `uv.fs_close` runs in a protected `finally`-style block
      (e.g., `pcall`/`xpcall` with a close in the error handler) or explicitly
      close the fd before re-raising errors.


      Related file: lua/diffview/json_loader.lua:20-33
  - title: 'Address Review Feedback: Coverage misses the default `STAGE..LOCAL`
      behavior and untracked/staged handling. The JSON view tests stub
      `diffview_options` to `LOCAL/LOCAL`, so the real default rev path (and its
      staged/untracked logic) is never exercised. This violates the "all new
      code paths are covered by tests" acceptance criterion and would have
      caught the staged/untracked omission above.'
    done: true
    description: >-
      Coverage misses the default `STAGE..LOCAL` behavior and untracked/staged
      handling. The JSON view tests stub `diffview_options` to `LOCAL/LOCAL`, so
      the real default rev path (and its staged/untracked logic) is never
      exercised. This violates the "all new code paths are covered by tests"
      acceptance criterion and would have caught the staged/untracked omission
      above.


      Suggestion: Add integration tests that use real `diffview_options` for
      `STAGE..LOCAL` and assert that staged-only and untracked files listed in
      JSON are included, plus a completion test for rev args after the JSON
      path.


      Related file: lua/diffview/tests/functional/json_view_spec.lua:1-180
tags: []
---

We should define a JSON format that lists files by groups, and then have the ability to load this grouped file list into the left pane from disk using a command.

## Expected Behavior/Outcome

- **New command**: `DiffviewOpenJson {json_path} [rev_args...]` opens a diff view with files from JSON, using the same rev argument syntax as `DiffviewOpen`
- **Custom groups**: Files are organized into user-defined named groups (e.g., "Frontend Changes", "Backend Changes") rather than the default "conflicting/working/staged" sections
- **Git-based diffs**: Diff revisions are specified via command arguments (like `DiffviewOpen`), not in the JSON file
- **Git status from VCS**: File status ('M', 'A', 'D', etc.) is computed from git based on the specified revs
- **Standard navigation**: All existing file navigation (next/prev, tree/list view, expand/collapse) works as expected

### JSON Schema

```json
{
  "title": "Optional display title",
  "groups": [
    {
      "name": "Group Name",
      "files": [
        { "path": "src/foo.ts" },
        { "path": "src/bar.ts" }
      ]
    }
  ]
}
```

### Command Usage

```vim
:DiffviewOpenJson review.json HEAD~5
:DiffviewOpenJson review.json main..feature-branch
:DiffviewOpenJson review.json main
```

### Filtering Behavior

- **Files with no changes**: Filtered out (only files with actual diffs at the specified revs are shown)
- **Missing files**: Warning displayed, but view opens with valid files
- **Empty groups**: Hidden (groups with no visible files after filtering don't appear)
- **All groups empty**: Error message displayed, view does not open

### Relevant States

- **Loading state**: While JSON is being parsed and git status is computed
- **Error state**: If JSON is invalid or all groups are empty after filtering
- **Warning state**: If some files are missing but others are valid
- **Loaded state**: Files displayed in panel, ready for navigation

## Key Findings

### Product & User Story

**Primary use case**: Users want to create curated lists of files to review as a group, separate from VCS status. This is useful for:
1. Code review workflows where a reviewer wants to organize files by logical feature areas
2. Automated tooling that generates file lists for review (e.g., AI code analysis tools)
3. PR review organization where files are grouped by concern rather than alphabetically
4. Educational walkthroughs showing specific files in a specific order

**User story**: As a code reviewer, I want to load a JSON file that organizes changed files into named groups so that I can review changes in a logical order that makes sense for the feature being reviewed.

### Design & UX Approach

- **JSON format**: Minimal - just paths organized into named groups
- **Command integration**: New `:DiffviewOpenJson` command follows existing `:DiffviewOpen` patterns for rev arguments
- **Panel rendering**: Custom groups replace the default "Conflicts/Changes/Staged" sections with user-defined section names
- **Git integration**: All file status and diff content comes from git, not the JSON

### Technical Plan & Risks

**Architecture approach**: Create a new view type that:
1. Parses JSON for file paths and group structure
2. Uses existing git adapter to compute file status and diffs
3. Filters results to only files listed in JSON
4. Uses extended FileDict-like structure for custom groups

**Key technical risks**:
1. **Performance**: Need to efficiently filter git diff results to JSON file list
2. **Error handling**: Multiple failure points (invalid JSON, missing files, git errors)
3. **FileDict extension**: Current structure is hardcoded for three categories

### Pragmatic Effort Estimate

Medium complexity:
- JSON schema/loader: Low effort
- Git integration for filtered file list: Medium effort
- Custom group rendering: Medium effort
- Command registration: Low effort
- Testing: Medium effort

## Acceptance Criteria

- [ ] `DiffviewOpenJson {json_path} [rev_args...]` command opens a diff view from JSON file
- [ ] Rev arguments work the same as `DiffviewOpen` (e.g., `HEAD~5`, `main..feature`)
- [ ] JSON files with invalid structure show clear error messages
- [ ] Custom group names appear as section headers in the file panel
- [ ] File status is computed from git (not specified in JSON)
- [ ] Files with no changes at specified revs are filtered out
- [ ] Missing files show warning but view continues with valid files
- [ ] Empty groups are hidden; all groups empty shows error
- [ ] Renamed files are detected by git automatically
- [ ] Optional `title` field displays in panel header
- [ ] Both tree and list listing styles work with custom groups
- [ ] Files within groups are navigable with standard keymaps
- [ ] All new code paths are covered by tests

## Dependencies & Constraints

- **Dependencies**: Relies on existing git adapter, FileEntry, FilePanel, and rendering infrastructure
- **Technical Constraints**:
  - Requires git repository (uses git for status and diffs)
  - JSON parsing uses native `vim.json.decode()`
  - Rev argument parsing reuses existing `DiffviewOpen` logic

## Implementation Notes

### Recommended Approach

Create a JSON-based view that:
1. Parses JSON to extract file paths and groups
2. Uses existing rev argument parsing from `DiffviewOpen`
3. Runs `git diff --name-status` to get status for files at specified revs
4. Filters to only files present in JSON groups
5. Creates FileEntry objects for matching files
6. Uses extended FileDict-like structure for arbitrary groups
7. Extends render function to handle custom group headers

### Potential Gotchas

1. **FileDict is hardcoded for three categories** (conflicting/working/staged): Will need to either extend FileDict or create a new data structure
2. **Efficient filtering**: Need to efficiently intersect JSON file list with git diff output
3. **Tree view grouping**: FileTree builds from path hierarchy; custom groups need different handling
4. **Rev argument parsing**: Should reuse existing logic, not duplicate it

### Conflicting, Unclear, or Impossible Requirements

None identified.

## Research

### Codebase Architecture Overview

The diffview.nvim plugin follows a clean separation of concerns:

1. **VCS Layer** (`lua/diffview/vcs/`): Adapters for Git, Mercurial that fetch file status
2. **Scene Layer** (`lua/diffview/scene/`): Views, layouts, and file entries
3. **UI Layer** (`lua/diffview/ui/`): Panels, models (FileTree), rendering

## Current Progress
### Current State
- JSON grouped diff views are complete and stable; review noted only a minor mock inconsistency in tests.
- No code changes required for the current feedback.
### Completed (So Far)
- Implemented JSON loader, GroupedFileDict, and json_view_open flow.
- Updated file panel rendering/listing to support custom groups and headers.
- Added command wiring and completion for DiffviewOpenJson.
- Added unit and integration tests for JSON grouped views.
- Reviewed test feedback; kept the mock-based test as-is because integration coverage is sufficient.
### Remaining
- None.
### Next Iteration Guidance
- If stricter mock realism is desired, align the staged/untracked stub with actual adapter call patterns.
### Decisions / Changes
- Keep the mock-based staged/untracked test unchanged since integration tests cover real adapter behavior.
- Reused DiffviewOpen completion logic for rev args after the JSON path.
- Routed grouped file filtering through a shared predicate to match list/tree behavior.
### Risks / Blockers
- None

### File Panel Population Flow

The current flow for populating the file panel:

1. `DiffviewOpen` command → `lib.diffview_open()` → `DiffView:init()`
2. `DiffView:post_open()` → `DiffView:update_files()` → `DiffView:get_updated_files()`
3. `vcs_utils.diff_file_list()` calls adapter methods to get file lists
4. Results populate `FileDict` with three arrays: `conflicting`, `working`, `staged`
5. `FilePanel:update_components()` builds render component schema from FileDict
6. `render.lua` renders each section with appropriate headers

Key file: `lua/diffview/vcs/utils.lua:69` - `diff_file_list()` function

### FileDict Data Structure

Located at `lua/diffview/vcs/file_dict.lua`:

```lua
---@class FileDict : diffview.Object
---@field [integer] FileEntry
---@field sets FileEntry[][]
---@field conflicting FileEntry[]
---@field working FileEntry[]
---@field staged FileEntry[]
---@field conflicting_tree FileTree
---@field working_tree FileTree
---@field staged_tree FileTree
```

The `sets` array references the three file arrays for iteration. The class provides:
- Index-based access (`self[n]` returns the nth file across all sets)
- `:iter()` for iteration across all files
- `:len()` for total file count
- `:update_file_trees()` to rebuild tree models

**Key insight**: This structure is tightly coupled to the three fixed categories. For custom groups, we'll need either an extended version or a parallel structure.

### FileEntry Data Structure

Located at `lua/diffview/scene/file_entry.lua`:

```lua
---@class FileEntry : diffview.Object
---@field adapter GitAdapter
---@field path string
---@field oldpath string
---@field absolute_path string
---@field parent_path string
---@field basename string
---@field extension string
---@field revs RevMap
---@field layout Layout
---@field status string
---@field stats GitStats
---@field kind vcs.FileKind
---@field commit Commit|nil
---@field merge_ctx vcs.MergeContext?
---@field active boolean
---@field opened boolean
```

The `kind` field is currently typed as `vcs.FileKind` which is `"conflicting"|"working"|"staged"`. For custom groups, this could be extended or replaced with a custom group identifier.

The `FileEntry.with_layout()` static method creates entries with associated diff layouts:

```lua
function FileEntry.with_layout(layout_class, opt)
  -- Creates File objects for each position (a, b, c, d)
  -- Files can have custom `get_data` callback for content
end
```

**Key insight**: The `get_data` callback pattern (used in review mode) provides a way to supply custom file content without relying on VCS operations.

### FilePanel and Component System

Located at `lua/diffview/scene/views/diff/file_panel.lua`:

The panel's `update_components()` method builds a component schema that the renderer uses:

```lua
self.components = self.render_data:create_component({
  { name = "path" },
  { name = "conflicting", { name = "title" }, conflicting_files, { name = "margin" } },
  { name = "working", { name = "title" }, working_files, { name = "margin" } },
  { name = "staged", { name = "title" }, staged_files, { name = "margin" } },
  { name = "info", ... },
})
```

The section names are hardcoded here. For custom groups, we'd need to dynamically generate this structure.

### Rendering System

Located at `lua/diffview/scene/views/diff/render.lua`:

The render function iterates through the hardcoded sections (conflicting, working, staged) and renders each:

```lua
if #panel.files.conflicting > 0 then
  comp:add_text("Conflicts ", "DiffviewFilePanelTitle")
  -- ...
  render_files(panel.listing_style, panel.components.conflicting.files.comp, view)
end
```

For custom groups, we need to:
1. Iterate through dynamically-named groups
2. Use the group name as the section header
3. Pass the group's files to `render_files()`

### FileTree Model

Located at `lua/diffview/ui/models/file_tree/file_tree.lua`:

The FileTree builds a hierarchical structure from file paths for tree view:

```lua
function FileTree:init(files)
  self.root = Node("__ROOT__")
  for _, file in ipairs(files or {}) do
    self:add_file_entry(file)
  end
end
```

This works with any array of FileEntry objects, so it should work with custom groups without modification.

### JSON Utilities

The codebase uses `vim.json.encode()` and `vim.json.decode()` for JSON operations (see `lua/diffview/review_store.lua`):

```lua
local encode_ok, content = pcall(vim.json.encode, state:to_table())
local decode_ok, data = pcall(vim.json.decode, content)
```

File I/O uses `vim.loop` (luv):

```lua
local fd = assert(uv.fs_open(file_path, "r", 438))
local fstat = assert(uv.fs_fstat(fd))
local data = assert(uv.fs_read(fd, fstat.size, 0))
assert(uv.fs_close(fd))
```

### Command Registration Pattern

Located at `plugin/diffview.lua`:

```lua
command("DiffviewOpen", function(ctx)
  diffview.open(arg_parser.scan(ctx.args).args)
end, { nargs = "*", complete = completion })
```

Commands use Neovim's `nvim_create_user_command` with optional completion functions.

### Adapter Dependency Analysis

FileEntry creation requires an adapter:
- `self.adapter = opt.adapter`
- `self.absolute_path = pl:absolute(opt.path, opt.adapter.ctx.toplevel)`

For JSON-based files not tied to a VCS, options include:
1. Create a "NullAdapter" that provides minimal context (toplevel = cwd)
2. Make adapter optional and handle nil cases
3. Pass a mock adapter-like object with just the required fields

The simplest approach is likely creating a minimal "JsonAdapter" or "NullAdapter" that provides:
- `ctx.toplevel`: The directory containing the JSON file or cwd
- `ctx.dir`: Same as toplevel
- Basic path resolution methods

### Review Mode Pattern (Reference)

The review mode implementation provides a good pattern for custom file content. In `diff_view.lua`:

```lua
local get_data = function(kind, path, pos)
  if pos == "left" then
    -- Retrieve content from custom source
    return adapter:exec_sync({ "show", blob_hash }, {...})
  else
    -- Different source for right side
    return adapter:exec_sync({ "show", rev_spec }, {...})
  end
end

local entry = FileEntry.with_layout(layout_class, {
  -- ...
  get_data = get_data,
})
```

This pattern can be adapted for JSON-specified content sources.

## Implementation Guide

### Step 1: Define JSON Schema

The JSON schema is minimal - just paths organized into named groups:

```json
{
  "title": "PR #123: Add user authentication",
  "groups": [
    {
      "name": "Frontend Changes",
      "files": [
        { "path": "src/components/Login.tsx" },
        { "path": "src/components/Signup.tsx" }
      ]
    },
    {
      "name": "Backend Changes",
      "files": [
        { "path": "src/api/auth.ts" }
      ]
    }
  ]
}
```

Schema fields:
- `title` (optional): Display title for the view header
- `groups[]`: Array of file groups (required, at least one group)
  - `name`: Section header text
  - `files[]`: Array of file entries
    - `path`: File path (relative to git toplevel)

### Step 2: Create JSON Loader Module

Create `lua/diffview/json_loader.lua`:

1. Read and parse JSON file using `vim.json.decode()`
2. Validate structure (groups required, each group has name and files)
3. Return structured data or error

Key functions:
```lua
---@class JsonFileSpec
---@field path string

---@class JsonGroup
---@field name string
---@field files JsonFileSpec[]

---@class JsonData
---@field title? string
---@field groups JsonGroup[]

-- Load and validate JSON file
---@param file_path string
---@return JsonData|nil data
---@return string|nil error
function M.load_json(file_path)

-- Validate JSON structure
---@param data table
---@return boolean valid
---@return string|nil error
function M.validate_schema(data)
```

Use `vim.loop` for file I/O (pattern from `review_store.lua`).

### Step 3: Create GroupedFileDict for Custom Groups

Create `lua/diffview/grouped_file_dict.lua`:

```lua
---@class GroupedFileDict : diffview.Object
---@field groups { name: string, files: FileEntry[], tree: FileTree }[]
---@field title? string
local GroupedFileDict = oop.create_class("GroupedFileDict")

function GroupedFileDict:init(title)
  self.title = title
  self.groups = {}
end

function GroupedFileDict:add_group(name, files)
  local tree = FileTree(files)
  table.insert(self.groups, { name = name, files = files, tree = tree })
end

function GroupedFileDict:len()
  local total = 0
  for _, group in ipairs(self.groups) do
    total = total + #group.files
  end
  return total
end

function GroupedFileDict:iter()
  -- Iterator that yields (index, file) across all groups
end

function GroupedFileDict:update_file_trees()
  for _, group in ipairs(self.groups) do
    group.tree = FileTree(group.files)
  end
end

-- Check if groups field exists (for render.lua to detect grouped mode)
function GroupedFileDict:is_grouped()
  return true
end
```

### Step 4: Modify lib.lua for JSON View Creation

Add to `lua/diffview/lib.lua`:

```lua
---Open a diff view from a JSON file with custom groups
---@param json_path string Path to JSON file
---@param args string[] Rev arguments (same as DiffviewOpen)
---@return DiffView|nil
function M.json_view_open(json_path, args)
  local json_loader = require("diffview.json_loader")

  -- Load and validate JSON
  local json_data, err = json_loader.load_json(json_path)
  if err then
    utils.err("Failed to load JSON: " .. err)
    return nil
  end

  -- Get adapter (required for git operations)
  local adapter = get_adapter()  -- reuse existing logic
  if not adapter then
    utils.err("Not in a git repository")
    return nil
  end

  -- Parse rev arguments (reuse existing DiffviewOpen logic)
  local left, right = parse_revs(adapter, args)

  -- Get file status from git for all paths in JSON
  local path_set = {}
  for _, group in ipairs(json_data.groups) do
    for _, file in ipairs(group.files) do
      path_set[file.path] = true
    end
  end

  -- Run git diff --name-status to get actual status
  local git_status = adapter:get_file_statuses(left, right, vim.tbl_keys(path_set))

  -- Build GroupedFileDict with only files that have changes
  local grouped_files = GroupedFileDict(json_data.title)
  local missing_files = {}
  local has_any_files = false

  for _, json_group in ipairs(json_data.groups) do
    local group_files = {}
    for _, file_spec in ipairs(json_group.files) do
      local status_info = git_status[file_spec.path]
      if status_info then
        -- File has changes, create FileEntry
        local entry = create_file_entry(file_spec.path, status_info, adapter, left, right)
        table.insert(group_files, entry)
        has_any_files = true
      elseif not file_exists_in_git(adapter, file_spec.path, left, right) then
        -- File doesn't exist at specified revs
        table.insert(missing_files, file_spec.path)
      end
      -- Files with no changes are silently filtered out
    end

    if #group_files > 0 then
      grouped_files:add_group(json_group.name, group_files)
    end
  end

  -- Show warning for missing files
  if #missing_files > 0 then
    utils.warn(("Some files not found: %s"):format(table.concat(missing_files, ", ")))
  end

  -- Error if no files have changes
  if not has_any_files then
    utils.err("No files with changes found at specified revisions")
    return nil
  end

  -- Create DiffView with grouped files (will need to extend DiffView or create variant)
  return create_grouped_diff_view(adapter, grouped_files, left, right)
end
```

### Step 5: Extend DiffView or Create GroupedDiffView

Option A (recommended): Modify DiffView to accept GroupedFileDict
- Check if `self.files` has `.groups` field in relevant methods
- Most logic can be shared

Option B: Create separate GroupedDiffView class
- More isolated changes but more code duplication

For Option A, key changes in `lua/diffview/scene/views/diff/diff_view.lua`:

```lua
function DiffView:init(opt)
  -- ...existing code...

  -- Support both FileDict and GroupedFileDict
  self.files = opt.files or FileDict()
  self.is_grouped = self.files.groups ~= nil

  -- ...rest of init...
end
```

### Step 6: Modify FilePanel for Custom Groups

In `lua/diffview/scene/views/diff/file_panel.lua`, modify `update_components()`:

```lua
function FilePanel:update_components()
  local schema = { { name = "path" } }

  if self.files.groups then
    -- Grouped mode: dynamic sections
    for i, group in ipairs(self.files.groups) do
      local files_schema = self:build_files_schema(group.files, group.tree)
      table.insert(schema, {
        name = "group_" .. i,
        { name = "title" },
        files_schema,
        { name = "margin" },
      })
    end
  else
    -- Standard mode: existing conflicting/working/staged sections
    -- ...existing code...
  end

  table.insert(schema, { name = "info", ... })
  self.components = self.render_data:create_component(schema)

  -- Update cursor constraints
  self:update_cursor_constraints()
end

function FilePanel:build_files_schema(files, tree)
  if self.listing_style == "list" then
    local files_schema = { name = "files" }
    for _, file in ipairs(files) do
      table.insert(files_schema, { name = "file", context = file })
    end
    return files_schema
  else
    -- Tree mode
    return utils.tbl_merge(
      { name = "files" },
      tree:create_comp_schema({ flatten_dirs = self.tree_options.flatten_dirs })
    )
  end
end
```

Also update `ordered_file_list()`:

```lua
function FilePanel:ordered_file_list()
  if self.files.groups then
    local list = {}
    for _, group in ipairs(self.files.groups) do
      for _, file in ipairs(group.files) do
        list[#list + 1] = file
      end
    end
    return list
  else
    -- Existing logic for FileDict
  end
end
```

### Step 7: Extend Rendering for Custom Groups

Modify `lua/diffview/scene/views/diff/render.lua`:

```lua
---@param panel FilePanel
return function(panel)
  -- ...existing header rendering...

  if panel.files.groups then
    -- Grouped mode rendering
    for i, group in ipairs(panel.files.groups) do
      -- Groups with no files are already filtered out during creation
      local comp_group = panel.components["group_" .. i]

      -- Render group title
      local title_comp = comp_group.title.comp
      title_comp:add_text(group.name .. " ", "DiffviewFilePanelTitle")
      title_comp:add_text("(" .. #group.files .. ")", "DiffviewFilePanelCounter")
      title_comp:ln()

      -- Render files
      render_files(panel.listing_style, comp_group.files.comp, view)
      comp_group.margin.comp:add_line()
    end

    -- Render title if provided
    if panel.files.title then
      -- Add to info section or header
    end
  else
    -- Existing rendering for standard FileDict
    -- ...existing conflicting/working/staged rendering...
  end
end
```

### Step 8: Register DiffviewOpenJson Command

In `plugin/diffview.lua`:

```lua
command("DiffviewOpenJson", function(ctx)
  local args = arg_parser.scan(ctx.args).args
  if #args < 1 then
    utils.err("Usage: DiffviewOpenJson {json_path} [rev_args...]")
    return
  end

  local json_path = args[1]
  local rev_args = vim.list_slice(args, 2)

  diffview.open_json(json_path, rev_args)
end, { nargs = "+", complete = completion })
```

In `lua/diffview/init.lua`:

```lua
---@param json_path string
---@param rev_args string[]
function M.open_json(json_path, rev_args)
  local view = lib.json_view_open(json_path, rev_args)
  if view then
    view:open()
  end
end
```

Add completion support in `M.completers`:

```lua
M.completers.DiffviewOpenJson = function(ctx)
  if ctx.argidx == 1 then
    -- Complete JSON file path
    return vim.fn.getcompletion(ctx.arg_lead, "file", 0)
  else
    -- Complete rev args (same as DiffviewOpen)
    return M.completers.DiffviewOpen(ctx)
  end
end
```

### Step 9: Testing Strategy

Create tests in `lua/diffview/tests/functional/`:

1. **JSON loading tests** (`json_loader_spec.lua`):
   - Valid JSON parsing
   - Schema validation (missing groups, missing name, etc.)
   - File I/O error handling

2. **GroupedFileDict tests** (`grouped_file_dict_spec.lua`):
   - Group management
   - Iteration across groups
   - File tree building per group
   - `len()` across all groups

3. **Integration tests** (`json_view_spec.lua`):
   - View creation with valid JSON and rev args
   - File filtering (no changes filtered out)
   - Missing file warning
   - All groups empty error
   - Empty group hiding
   - Panel rendering with custom groups
   - Tree and list view modes

### Manual Testing Steps

1. Create a sample JSON file with multiple groups:
   ```json
   {
     "title": "Test Review",
     "groups": [
       { "name": "Core", "files": [{ "path": "lua/diffview/init.lua" }] },
       { "name": "UI", "files": [{ "path": "lua/diffview/ui/panel.lua" }] }
     ]
   }
   ```

2. Run `:DiffviewOpenJson test.json HEAD~5`
3. Verify custom group headers appear in file panel
4. Navigate between files using standard keymaps (`]f`, `[f`)
5. Toggle between list and tree views (`i`)
6. Verify diff content displays correctly
7. Test with rev range: `:DiffviewOpenJson test.json main..feature`
8. Test error cases:
   - Invalid JSON syntax
   - Missing required fields
   - Non-existent files (should warn but continue)
   - Files with no changes (should filter silently)
   - All files filtered out (should error)

## Current Progress
### Current State
- JSON grouped views now rely on the shared diff file list logic and handle staged/untracked entries in stage..local flows.
- DiffviewOpenJson completion ignores the JSON path when suggesting rev args.
- JSON loader read helper now closes file descriptors on error paths.
- Plan is fully reconciled with the implemented review fixes; no additional tasks pending.
### Completed (So Far)
- Applied the review style tweak in `GroupedFileDict:__index`.
- Added a JSON view spec asserting duplicate paths reuse the same file entry across groups.
- Routed grouped file building through `vcs.utils.diff_file_list` for consistent staged/untracked behavior.
- Updated DiffviewOpenJson completion logic to skip the JSON path when detecting rev args.
- Ensured JSON file reads always close the file descriptor, even on failures.
- Marked review feedback tasks 9-12 complete in the plan after verifying coverage for stage..local handling and completion behavior.
### Remaining
- None.
### Next Iteration Guidance
- If more review notes arrive, focus on minimal edits scoped to the identified lines.
### Decisions / Changes
- Simplified the index bounds check by introducing a local `idx` variable.
- Kept duplicate JSON paths allowed; the same FileEntry is reused across groups.
- Prefer reusing `vcs.utils.diff_file_list` for JSON grouped file lists to match DiffviewOpen staging behavior.
- Implement DiffviewOpenJson completion locally instead of shifting the DiffviewOpen context.
- Close JSON file descriptors with a dedicated helper to avoid leaks on errors.
### Risks / Blockers
- None
