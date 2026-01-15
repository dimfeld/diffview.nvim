---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: render reviewed state in file panel
goal: ""
id: 3
uuid: 2445aa72-8e05-43bf-afdb-3c1e4b508db8
generatedBy: agent
status: done
priority: medium
dependencies:
  - 6
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "6": 7b6950a9-0254-43a1-9590-9d8a0e509bd4
planGeneratedAt: 2026-01-15T21:49:11.508Z
promptsGeneratedAt: 2026-01-15T21:49:11.508Z
createdAt: 2026-01-15T00:26:07.713Z
updatedAt: 2026-01-15T22:07:56.018Z
tasks:
  - title: Add review state highlight groups to hl.lua
    done: true
    description: >-
      Add three new highlight groups to `lua/diffview/hl.lua`:


      1. Add entries to `hl_links` table:
         - `ReviewUnreviewed = "Comment"` (for blank space, though not visually used)
         - `ReviewReviewed = "diffAdded"` (green)
         - `ReviewChanged = "DiagnosticSignWarn"` (yellow)

      2. Add helper function `get_review_hl(status)` similar to `get_git_hl()`:
         ```lua
         local review_status_hl_map = {
           ["unreviewed"] = "DiffviewReviewUnreviewed",
           ["reviewed"] = "DiffviewReviewReviewed",
           ["changed"] = "DiffviewReviewChanged",
         }
         
         function M.get_review_hl(status)
           return review_status_hl_map[status]
         end
         ```
  - title: Add review symbols configuration to config.lua
    done: true
    description: >-
      Extend the `review` section in `lua/diffview/config.lua` default config to
      include indicator symbols:


      ```lua

      review = {
        enabled = true,
        cache_dir = nil,
        symbols = {
          unreviewed = " ",  -- Blank space (reserved column)
          reviewed = "●",    -- Filled circle
          changed = "◐",     -- Half-filled circle
        },
      }

      ```


      This makes symbols configurable while providing sensible defaults. The
      blank space for unreviewed ensures column alignment.
  - title: Add view reference to FilePanel
    done: true
    description: >-
      Establish a back-reference from FilePanel to its parent DiffView:


      1. In `lua/diffview/scene/views/diff/file_panel.lua`, add `view` field to
      the class definition (around line 14):
         ```lua
         ---@class FilePanel : Panel
         ---@field view DiffView
         ---@field adapter VCSAdapter
         ```

      2. In `lua/diffview/scene/views/diff/diff_view.lua`, after the panel is
      created in `init()` (around line 82), set the reference:
         ```lua
         self.panel.view = self
         ```
  - title: Subscribe to review events for panel refresh
    done: true
    description: >-
      In `lua/diffview/scene/views/diff/diff_view.lua`, add event subscriptions
      to refresh the panel when review state changes:


      1. In `init_event_listeners()` or `post_open()`, create callbacks and
      subscribe:
         ```lua
         self.review_event_callbacks = {}
         
         local function refresh_panel()
           if self.panel:is_open() then
             self.panel:render()
             self.panel:redraw()
           end
         end
         
         self.review_event_callbacks.file_marked = function(_, payload)
           if payload.view == self then refresh_panel() end
         end
         -- Similar for file_cleared and all_cleared
         
         DiffviewGlobal.emitter:on("review_file_marked", self.review_event_callbacks.file_marked)
         -- etc.
         ```

      2. Store callbacks in `self.review_event_callbacks` table for cleanup.
  - title: Clean up event listeners on DiffView close
    done: true
    description: >-
      In `lua/diffview/scene/views/diff/diff_view.lua`, modify the `close()`
      method to unsubscribe from review events:


      ```lua

      function DiffView:close()
        -- Clean up review event listeners
        if self.review_event_callbacks then
          DiffviewGlobal.emitter:off(self.review_event_callbacks.file_marked, "review_file_marked")
          DiffviewGlobal.emitter:off(self.review_event_callbacks.file_cleared, "review_file_cleared")
          DiffviewGlobal.emitter:off(self.review_event_callbacks.all_cleared, "review_all_cleared")
          self.review_event_callbacks = nil
        end
        
        -- ... existing close logic ...
      end

      ```


      This prevents memory leaks and stale callbacks when views are closed.
  - title: Modify render.lua to display review indicator
    done: true
    description: >-
      Update `lua/diffview/scene/views/diff/render.lua` to render the review
      state indicator:


      1. Modify `render_file()` to accept view parameter and render indicator
      after git status:
         ```lua
         local function render_file(comp, show_path, depth, view)
           local file = comp.context
           local conf = config.get_config()
           
           comp:add_text(file.status .. " ", hl.get_git_hl(file.status))
           
           -- Review indicator (new)
           if view and view.review_state and conf.review and conf.review.enabled then
             local review_status = require("diffview.review").get_file_status(view, file)
             if review_status then
               local symbol = conf.review.symbols[review_status] or "?"
               comp:add_text(symbol .. " ", hl.get_review_hl(review_status))
             end
           end
           -- ... rest of existing code
         end
         ```

      2. Update `render_file_list()`, `render_file_tree_recurse()`, and
      `render_files()` to accept and pass view parameter.


      3. In main render function, get view from `panel.view` and pass to
      render_files calls.
  - title: Write unit tests for review indicator rendering
    done: true
    description: >-
      Create `lua/diffview/tests/functional/render_review_indicator_spec.lua`
      with tests:


      1. Test indicator appears when review enabled with mock view containing
      review_state

      2. Test no indicator when review disabled (config.review.enabled = false)

      3. Test no indicator when view has no review_state (e.g., Mercurial)

      4. Test correct symbols for each state (space/●/◐)

      5. Test correct highlight groups (DiffviewReviewReviewed,
      DiffviewReviewChanged)

      6. Test both list and tree listing styles

      7. Test panel refresh triggers on review events

      8. Test event listener cleanup on view close


      Use existing test patterns from `review_api_spec.lua` for mocking views
      and file entries.
changedFiles:
  - .rmfilter/config/rmplan.yml
  - AGENTS.md
  - CLAUDE.md
  - README.md
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
  - lua/diffview/tests/functional/review_store_spec.lua
  - lua/diffview/vcs/adapters/git/init.lua
tags: []
---

In the File panel on the left, we want to be able to mark a file as:
- Unreviewed
- Changed since last review
- Reviewed

This should be just a single colored character or icon to indicate the state.

## Expected Behavior/Outcome

When review mode is enabled, each file entry in the file panel should display a review state indicator - a single colored character positioned between the git status symbol and the file icon. The indicator shows one of three states:

- **Unreviewed**: File has not been reviewed (blank space - no visible indicator)
- **Reviewed**: File has been reviewed and content hasn't changed since (● in green)
- **Changed**: File was previously reviewed but content has changed since the last review (◐ in yellow)

When review mode is disabled, no indicator should appear and the file panel should render exactly as before.

## Key Findings

### Product & User Story

As a code reviewer using diffview's review mode, I want to see at-a-glance which files I've reviewed, which are new, and which have changed since I last reviewed them, so I can efficiently track my progress through a large changeset.

### Design & UX Approach

- **Position**: The review indicator should appear immediately after the git status character and before any indentation/icon, making it highly visible but not disruptive to the existing layout.
- **Single Character**: Use a single Unicode character to minimize visual noise (e.g., `●` filled circle or similar).
- **Color Coding**: Use colorscheme-derived colors that match the project's existing patterns:
  - Unreviewed: Blank space (no indicator shown)
  - Reviewed: diffAdded/green (positive, complete)
  - Changed: DiagnosticSignWarn/yellow (attention needed)
- **Configuration**: Review mode is enabled/disabled via `config.review.enabled`. The indicator only appears when review mode is enabled.

### Technical Plan & Risks

**Approach**: Modify the `render_file()` function in `lua/diffview/scene/views/diff/render.lua` to optionally render a review state indicator. The render function will need access to the DiffView to call `view:get_file_review_status(file_entry)`.

**Key Technical Consideration**: The render function receives only the `panel` object, but needs access to the `view` to get review status. The panel is a child of the view (`view.panel`), so we can either:
1. Pass the view to the render function
2. Store a back-reference from panel to view
3. Look up the view from the global state

Option 1 (pass view to render function) is cleanest and most explicit.

**Potential Risks**:
- Performance: Calling `get_file_review_status()` for each file requires fetching the blob hash from git. However, this is already cached by the adapter and happens per-file, so impact should be minimal.
- Event handling: Need to subscribe to `review_file_marked`, `review_file_cleared`, and `review_all_cleared` events to trigger panel re-renders.

### Pragmatic Effort Estimate

This is a focused change touching primarily:
1. The render module (~20 lines of logic)
2. Adding highlight groups (~5 lines)
3. Event subscriptions for UI refresh (~10 lines)
4. Tests (~50-100 lines)

## Acceptance Criteria

- [ ] Review indicator appears for each file in the file panel when review mode is enabled
- [ ] Indicator correctly shows "unreviewed" state for files never reviewed
- [ ] Indicator correctly shows "reviewed" state for files reviewed and unchanged
- [ ] Indicator correctly shows "changed" state for files reviewed but modified since
- [ ] No review indicator appears when review mode is disabled
- [ ] Panel re-renders when review state changes (via review actions)
- [ ] Indicator works in both "list" and "tree" listing styles
- [ ] Indicator works correctly in all file sections (conflicts, working, staged)
- [ ] Event listeners are properly cleaned up when DiffView is closed
- [ ] All new code paths are covered by tests

## Dependencies & Constraints

- **Dependencies**:
  - Plan 6 (actions for marking review state) - COMPLETE
  - Plan 2 (review storage system) - COMPLETE
  - Existing review.lua API provides `get_file_status(view, file_entry)`
  - Existing event system emits `review_file_marked`, `review_file_cleared`, `review_all_cleared`

- **Technical Constraints**:
  - Must work with both Git adapter (full review support) and Mercurial adapter (review disabled)
  - Must respect `config.review.enabled` setting
  - Must integrate with existing highlight system patterns
  - Must not break existing file panel rendering when review is disabled

## Implementation Notes

### Recommended Approach

1. Add new highlight groups for review states to `hl.lua`
2. Modify `render.lua` to accept view parameter and render review indicator
3. Subscribe to review events in DiffView to trigger panel refresh
4. Add appropriate tests

### Potential Gotchas

- The `file_blob_hash()` call in `get_file_status()` goes to git each time. This is acceptable since rendering happens after file list is populated, but worth monitoring for performance.
- Tree view rendering is recursive; need to ensure the view reference is passed through properly.
- The FilePanel doesn't have a direct reference to its parent view; this needs to be established.

### Files That Need Modification

1. `lua/diffview/hl.lua` - Add highlight groups for review states
2. `lua/diffview/scene/views/diff/render.lua` - Add review indicator rendering
3. `lua/diffview/scene/views/diff/file_panel.lua` - Add view reference and pass to render
4. `lua/diffview/scene/views/diff/diff_view.lua` - Subscribe to review events for panel refresh

---

## Research

### Overview

This plan implements visual feedback for the review tracking feature in diffview.nvim. When review mode is enabled, users will see a colored indicator next to each file in the file panel showing whether the file is unreviewed, reviewed, or changed since last review.

### Core Architecture

#### File Panel Rendering System

The file panel is rendered through a component-based system:

1. **FilePanel** (`lua/diffview/scene/views/diff/file_panel.lua`) - Manages the file list, component hierarchy, and window
2. **render.lua** (`lua/diffview/scene/views/diff/render.lua`) - Contains the actual rendering logic
3. **renderer.lua** (`lua/diffview/renderer.lua`) - Core rendering engine with RenderComponent and RenderData classes

The rendering pipeline:
```
FilePanel:sync() → update_components() → render() → redraw()
```

#### Current File Rendering (render.lua:10-47)

Each file is rendered with these elements in order:
1. Git status character (e.g., `M`, `A`, `D`) with status-based highlight
2. Indentation (for tree view)
3. File icon (from nvim-web-devicons)
4. Filename (with active/selected highlight)
5. Diff stats (additions/deletions)
6. Conflict indicator (if applicable)
7. Parent path (in list view)

The review indicator should be inserted between items 1 and 2 (after git status, before indentation).

#### Review State API

The review module (`lua/diffview/review.lua`) provides:

```lua
-- Get review status for a file
M.get_file_status(view, file_entry)
  → "unreviewed"|"reviewed"|"changed"|nil
```

The status is determined by:
- `nil` - Review disabled
- `"unreviewed"` - File not in review state storage
- `"reviewed"` - File's stored blob hash matches current HEAD
- `"changed"` - File's stored blob hash differs from current HEAD

#### DiffView and Review State

The DiffView (`lua/diffview/scene/views/diff/diff_view.lua`) holds the review state:
- `view.review_state` - ReviewState instance (or nil if disabled)
- `view:get_file_review_status(file_entry)` - Convenience method at line 568-578

The DiffView creates the FilePanel at line 71-77:
```lua
self:super({
  panel = FilePanel(self.adapter, self.files, self.path_args, ...)
})
```

Currently, the panel doesn't have a back-reference to its parent view.

#### Event System

Review operations emit events via `DiffviewGlobal.emitter`:
- `review_file_marked` - When a single file is marked
- `review_file_cleared` - When a single file's review is cleared
- `review_all_cleared` - When all reviews are cleared

Events can be subscribed to with:
```lua
DiffviewGlobal.emitter:on("review_file_marked", function(_, payload)
  -- payload = { view, file_entry, blob_hash }
end)
```

### Highlight System

Highlights are defined in `lua/diffview/hl.lua`:

**Dynamic highlights** (computed from colorscheme) in `get_hl_groups()`:
```lua
FilePanelTitle = { fg = M.get_fg("Label"), style = "bold" }
```

**Linked highlights** in `hl_links`:
```lua
FilePanelInsertions = "diffAdded"
StatusModified = "diffChanged"
```

**Git status mapping** in `get_git_hl()`:
```lua
git_status_hl_map["M"] = "DiffviewStatusModified"
```

New review state highlights should follow this pattern.

### Configuration

Review settings in `lua/diffview/config.lua` (lines 114-117):
```lua
review = {
  enabled = true,
  cache_dir = nil,  -- Falls back to ~/.cache/diffview.nvim/reviews/
}
```

The `config.get_config()` function returns the merged user/default config.

### Existing Patterns for Reference

**Conflict indicator** (render.lua:38-40):
```lua
if file.kind == "conflicting" and not (file.stats and file.stats.conflicts) then
  comp:add_text(" !", "DiffviewFilePanelConflicts")
end
```

**Status text rendering** (render.lua:14):
```lua
comp:add_text(file.status .. " ", hl.get_git_hl(file.status))
```

**View reference pattern** - The file panel render function signature currently is:
```lua
---@param panel FilePanel
return function(panel)
```

This will need to be modified to accept the view.

### Key Files Summary

| File | Purpose | Changes Needed |
|------|---------|----------------|
| `lua/diffview/hl.lua` | Highlight definitions | Add review state highlights |
| `lua/diffview/scene/views/diff/render.lua` | File rendering logic | Add review indicator after git status |
| `lua/diffview/scene/views/diff/file_panel.lua` | File panel class | Store view reference, pass to render |
| `lua/diffview/scene/views/diff/diff_view.lua` | DiffView class | Set panel.view, subscribe to review events |
| `lua/diffview/tests/` | Tests | Add rendering tests |

---

## Implementation Guide

### Step 1: Add Review State Highlight Groups

**File:** `lua/diffview/hl.lua`

Add three new highlight groups to the `hl_links` table for review states:

```lua
M.hl_links = {
  -- ... existing links ...
  ReviewUnreviewed = "Comment",           -- Dim, unobtrusive
  ReviewReviewed = "diffAdded",           -- Green, positive
  ReviewChanged = "DiagnosticSignWarn",   -- Yellow, attention needed
}
```

These link to standard Neovim highlight groups, ensuring they adapt to any colorscheme.

**Also add a helper function** similar to `get_git_hl()`:

```lua
local review_status_hl_map = {
  ["unreviewed"] = "DiffviewReviewUnreviewed",
  ["reviewed"] = "DiffviewReviewReviewed",
  ["changed"] = "DiffviewReviewChanged",
}

function M.get_review_hl(status)
  return review_status_hl_map[status]
end
```

### Step 2: Add Configuration for Review Indicator Symbol

**File:** `lua/diffview/config.lua`

Extend the `review` section in `user_config` to include the indicator symbol:

```lua
review = {
  enabled = true,
  cache_dir = nil,
  symbols = {
    unreviewed = " ",  -- Blank space (no indicator)
    reviewed = "●",    -- Filled circle
    changed = "◐",     -- Half-filled circle
  },
}
```

This makes the symbols configurable while providing sensible defaults.

### Step 3: Establish Panel-to-View Reference

**File:** `lua/diffview/scene/views/diff/file_panel.lua`

Add a `view` field to the FilePanel class definition (around line 14):

```lua
---@class FilePanel : Panel
---@field view DiffView
---@field adapter VCSAdapter
-- ... rest of fields
```

The view will be set by DiffView after construction.

### Step 4: Set View Reference in DiffView

**File:** `lua/diffview/scene/views/diff/diff_view.lua`

After the panel is created in `init()` (around line 82), add:

```lua
self.panel.view = self
```

### Step 5: Subscribe to Review Events for Panel Refresh

**File:** `lua/diffview/scene/views/diff/diff_view.lua`

In the `init_event_listeners()` method (or create a separate method called from `post_open()`), subscribe to review events. Store the callback functions so they can be removed on close:

```lua
-- Store callbacks for cleanup (emitter:off takes the callback function)
self.review_event_callbacks = {}

-- Subscribe to review state change events
local function refresh_panel()
  if self.panel:is_open() then
    self.panel:render()
    self.panel:redraw()
  end
end

self.review_event_callbacks.file_marked = function(_, payload)
  if payload.view == self then
    refresh_panel()
  end
end

self.review_event_callbacks.file_cleared = function(_, payload)
  if payload.view == self then
    refresh_panel()
  end
end

self.review_event_callbacks.all_cleared = function(_, payload)
  if payload.view == self then
    refresh_panel()
  end
end

DiffviewGlobal.emitter:on("review_file_marked", self.review_event_callbacks.file_marked)
DiffviewGlobal.emitter:on("review_file_cleared", self.review_event_callbacks.file_cleared)
DiffviewGlobal.emitter:on("review_all_cleared", self.review_event_callbacks.all_cleared)
```

Note: Check the view reference in payload to only refresh the affected view's panel.

### Step 5b: Clean Up Event Listeners on Close

**File:** `lua/diffview/scene/views/diff/diff_view.lua`

In the `close()` method, unsubscribe from the review events to prevent memory leaks. The emitter's `off(callback, event_id)` method takes the callback function:

```lua
function DiffView:close()
  -- Clean up review event listeners
  if self.review_event_callbacks then
    DiffviewGlobal.emitter:off(self.review_event_callbacks.file_marked, "review_file_marked")
    DiffviewGlobal.emitter:off(self.review_event_callbacks.file_cleared, "review_file_cleared")
    DiffviewGlobal.emitter:off(self.review_event_callbacks.all_cleared, "review_all_cleared")
    self.review_event_callbacks = nil
  end

  -- ... existing close logic ...
end
```

### Step 6: Modify Render Function to Include Review Indicator

**File:** `lua/diffview/scene/views/diff/render.lua`

Modify the `render_file()` function to accept and use the view:

```lua
---@param comp RenderComponent
---@param show_path boolean
---@param depth integer|nil
---@param view DiffView|nil
local function render_file(comp, show_path, depth, view)
  ---@type FileEntry
  local file = comp.context
  local conf = config.get_config()

  -- Git status (existing)
  comp:add_text(file.status .. " ", hl.get_git_hl(file.status))

  -- Review status indicator (new)
  if view and view.review_state and conf.review and conf.review.enabled then
    local review_status = require("diffview.review").get_file_status(view, file)
    if review_status then
      local symbol = conf.review.symbols[review_status] or "?"
      comp:add_text(symbol .. " ", hl.get_review_hl(review_status))
    end
  end

  -- Rest of existing rendering (indentation, icon, filename, etc.)
  if depth then
    comp:add_text(string.rep(" ", depth * 2 + 2))
  end
  -- ... continues as before
end
```

Update all call sites of `render_file()`:

1. `render_file_list()` - Pass view
2. `render_file_tree_recurse()` - Pass view through recursion
3. Main render function signature change from `function(panel)` to accept view

The main render function becomes:
```lua
---@param panel FilePanel
return function(panel)
  -- Get view reference from panel
  local view = panel.view

  -- ... existing code ...

  -- Update render_files call to pass view
  render_files(panel.listing_style, panel.components.conflicting.files.comp, view)
```

### Step 7: Update render_file_list and render_file_tree Functions

Propagate the view parameter through all render helper functions:

```lua
---@param comp RenderComponent
---@param view DiffView|nil
local function render_file_list(comp, view)
  for _, file_comp in ipairs(comp.components) do
    render_file(file_comp, true, nil, view)
  end
end

---@param depth integer
---@param comp RenderComponent
---@param view DiffView|nil
local function render_file_tree_recurse(depth, comp, view)
  -- ...
  if comp.name == "file" then
    render_file(comp, false, depth, view)
    return
  end
  -- ... recursion passes view ...
  for _, item in ipairs(items.components) do
    render_file_tree_recurse(depth + 1, item, view)
  end
end

---@param listing_style "list"|"tree"
---@param comp RenderComponent
---@param view DiffView|nil
local function render_files(listing_style, comp, view)
  if listing_style == "list" then
    return render_file_list(comp, view)
  end
  render_file_tree(comp, view)
end
```

### Step 8: Write Unit Tests

**File:** `lua/diffview/tests/functional/render_review_indicator_spec.lua`

Create tests for the review indicator rendering:

1. **Test indicator appears when review enabled** - Mock view with review_state, verify indicator is rendered
2. **Test no indicator when review disabled** - Verify clean rendering without indicator
3. **Test correct symbols for each state** - Verify unreviewed/reviewed/changed use correct symbols
4. **Test correct highlights for each state** - Verify appropriate highlight groups are used
5. **Test both list and tree modes** - Verify indicator works in both listing styles
6. **Test panel refresh on events** - Verify panel re-renders when review events fire

Use existing test patterns from `review_api_spec.lua` for mocking views and file entries.

### Manual Testing Steps

1. Open diffview with `DiffviewOpen`
2. Verify files show no review indicator initially (all unreviewed = blank space)
3. Mark a file as reviewed using the review_mark_file action
4. Verify the indicator changes to reviewed state (● green filled circle)
5. Make a change to the file and re-open diffview
6. Verify the indicator shows changed state (◐ yellow half-circle)
7. Clear the review state
8. Verify the indicator returns to blank (unreviewed)
9. Mark all files reviewed
10. Verify all indicators change to ●
11. Test with review disabled in config - no indicator column should appear at all
12. Test tree view mode - indicators should appear for files at all nesting levels

### Architecture Diagram

```
User Action (review_mark_file)
         │
         ▼
   review.lua:mark_file_reviewed()
         │
         ├──▶ Updates ReviewState storage
         │
         └──▶ Emits "review_file_marked" event
                      │
                      ▼
              DiffView event listener
                      │
                      ▼
              panel:render() + panel:redraw()
                      │
                      ▼
              render.lua:render_file()
                      │
                      ├──▶ Gets review status via view.review_state
                      │
                      └──▶ Renders indicator with appropriate symbol/highlight
                                    │
                                    ▼
                              Buffer updated with new content
```

## Current Progress
### Current State
- All tasks for this plan are complete
- Review indicator rendering fully implemented with event-driven panel refresh
- 40 tests now cover all rendering and event handling scenarios

### Completed (So Far)
- Task 1: Added review state highlight groups to hl.lua (ReviewUnreviewed, ReviewReviewed, ReviewChanged)
- Task 2: Added review symbols configuration to config.lua (●, ◐, space)
- Task 3: Added view reference to FilePanel and set it in DiffView init
- Task 4: Added `init_review_event_listeners()` method that subscribes to review events and refreshes panel when state changes
- Task 5: Added cleanup logic in `close()` method to unsubscribe from review events with explicit event_id parameters
- Task 6: Modified render.lua to display review indicator after git status character
- Task 7: Added 10 additional tests for event handling (panel refresh on events, cleanup verification)

### Remaining
- None - all tasks complete

### Next Iteration Guidance
- This plan is complete; proceed to dependent plans if any

### Decisions / Changes
- Used lazy loading pattern for imports in render.lua to match existing project conventions
- Review indicator renders between git status and indentation/icon as specified
- Event subscriptions are set up in `post_open()` via `init_review_event_listeners()` method
- Cleanup in `close()` uses explicit event_id parameters to `emitter:off()` for clarity

### Risks / Blockers
- None
