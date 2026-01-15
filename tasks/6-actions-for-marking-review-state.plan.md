---
# yaml-language-server: $schema=https://raw.githubusercontent.com/dimfeld/llmutils/main/schema/rmplan-plan-schema.json
title: Actions for marking review state
goal: ""
id: 6
uuid: 7b6950a9-0254-43a1-9590-9d8a0e509bd4
generatedBy: agent
status: in_progress
priority: medium
dependencies:
  - 2
parent: 1
references:
  "1": 6d222e2b-71b2-42ca-9e26-231b4726a946
  "2": aae1042d-6942-47bc-8470-5d7ac9ca8bc6
planGeneratedAt: 2026-01-15T21:19:51.170Z
promptsGeneratedAt: 2026-01-15T21:19:51.170Z
createdAt: 2026-01-15T01:45:08.558Z
updatedAt: 2026-01-15T21:20:40.401Z
tasks:
  - title: Add review action names to actions.lua registry
    done: false
    description: >-
      Add the three new action names to the `action_names` array in
      `lua/diffview/actions.lua` (around lines 618-648):


      1. `review_mark_file` - For marking the current file as reviewed

      2. `review_mark_all` - For marking all files in the view as reviewed

      3. `review_clear_file` - For clearing the review state of the current file


      This automatically generates the event-emitting functions that call
      `require("diffview").emit(action_name)`.
  - title: Implement review_mark_file listener in DiffView
    done: false
    description: >-
      Add the `review_mark_file` listener handler in
      `lua/diffview/scene/views/diff/listeners.lua`:


      1. Add `lazy.require` for the review module at the top of the file

      2. Implement the listener that:
         - Gets the current file with `view:infer_cur_file()`
         - Returns early if no file is selected
         - Calls `review.mark_file_reviewed(view, file)`
         - The review.lua function handles validation, storage, and event emission

      No feedback message needed - the UI indicator (Plan 3) provides visual
      feedback.
  - title: Implement review_mark_all listener in DiffView
    done: false
    description: >-
      Add the `review_mark_all` listener handler in
      `lua/diffview/scene/views/diff/listeners.lua`:


      1. Implement the listener that calls `review.mark_all_reviewed(view)`

      2. The review.lua function handles:
         - Iterating all files in view.files
         - Getting blob hashes for each
         - Storing with skip_save optimization (saves once at end)
         - Emitting events for each file

      No feedback message needed.
  - title: Implement review_clear_file listener in DiffView
    done: false
    description: >-
      Add the `review_clear_file` listener handler in
      `lua/diffview/scene/views/diff/listeners.lua`:


      1. Implement the listener that:
         - Gets the current file with `view:infer_cur_file()`
         - Returns early if no file is selected
         - Calls `review.clear_file_review(view, file)`
         - The review.lua function handles validation, storage, and event emission

      No feedback message needed.
  - title: Write unit tests for review action listeners
    done: false
    description: >-
      Create `lua/diffview/tests/functional/review_actions_spec.lua` with tests
      for:


      1. Test `review_mark_file` listener:
         - With valid file selected
         - With no file selected (should be no-op)
         - With review disabled (should be no-op)

      2. Test `review_mark_all` listener:
         - With multiple files in view
         - With empty file list (should handle gracefully)
         - With review disabled (should be no-op)

      3. Test `review_clear_file` listener:
         - With valid file selected
         - With no file selected (should be no-op)

      Use existing test patterns from `review_api_spec.lua` as a template.
      Create mock view objects with appropriate fields.
tags: []
---

Implement the core actions for managing review state on files.

## Actions Required

### Mark File as Reviewed
- Mark the currently selected/viewed file as reviewed
- Store the file path and its current git blob hash in the review storage
- Update the file panel to reflect the new reviewed state

### Mark All Files as Reviewed
- Mark all files in the current diff view as reviewed
- Useful when you've gone through everything and want to mark it all at once

### Clear File Review State
- Remove the review state for a specific file
- The file will appear as "unreviewed" again

## Integration Points
- These actions should be available as commands that can be bound to keys (see plan 5)
- They should update the file panel display (see plan 3)
- They interact with the storage system (see plan 2)

---

## Research

### Overview

This plan implements user-facing actions for managing file review state in the diffview.nvim plugin. The actions allow users to mark files as reviewed (storing the current blob hash), mark all files reviewed at once, and clear review state. These actions bridge the existing review storage system (Plan 2, already complete) with user interactions via keymaps (Plan 5) and visual feedback (Plan 3).

### Key Findings

#### 1. Existing Review API (Ready to Use)

The review storage system from Plan 2 is fully implemented and provides all the functionality needed:

**Location:** `lua/diffview/review.lua`

```lua
-- Mark a single file as reviewed
M.mark_file_reviewed(view, file_entry) -> boolean

-- Mark all files in the view as reviewed (optimized: saves once at end)
M.mark_all_reviewed(view) -> integer (count of files marked)

-- Clear review status for a file
M.clear_file_review(view, file_entry) -> boolean

-- Clear all reviews for the current branch
M.clear_all_reviews(view) -> boolean

-- Get review status
M.get_file_status(view, file_entry) -> "unreviewed"|"reviewed"|"changed"|nil
```

These functions handle:
- Validation (review enabled, view/file_entry valid)
- Getting blob hash via `view.adapter:file_blob_hash(path, "HEAD")`
- Storing to the ReviewState
- Emitting events for UI updates (`review_file_marked`, `review_file_cleared`, `review_all_cleared`)

#### 2. Action System Architecture

Actions in diffview.nvim follow a consistent pattern:

**Pattern A: Event-Emitting Actions** (Most Common)

For simple actions, add the name to `action_names` in `lua/diffview/actions.lua`:

```lua
-- In actions.lua (lines 618-648)
local action_names = {
  "close",
  "select_next_entry",
  -- ... add new action names here
  "review_mark_file",     -- NEW
  "review_mark_all",      -- NEW
  "review_clear_file",    -- NEW
}

-- This generates:
M.review_mark_file = function()
  require("diffview").emit("review_mark_file")
end
```

**Pattern B: Direct Implementation Actions**

For actions needing complex logic before emitting, implement directly:

```lua
function M.goto_file()
  -- Complex logic here
  local file, cursor = prepare_goto_file()
  if file then
    -- Do the work
  end
end
```

**Pattern C: Parameterized Actions (Function Generators)**

For actions with parameters:

```lua
function M.conflict_choose(target)
  return function()
    -- Use 'target' parameter
  end
end
```

#### 3. Listener Implementation Pattern

Actions that use the event system need handlers in listener files:

**Location:** `lua/diffview/scene/views/diff/listeners.lua`

```lua
return function(view)
  return {
    -- Listener for the action event
    select_next_entry = function()
      view:next_file(true)
    end,

    -- New review actions would go here
    review_mark_file = function()
      -- implementation
    end,
  }
end
```

Each listener receives the `view` instance and has access to:
- `view.panel` - The file panel
- `view.files` - The FileDict with all files
- `view.cur_entry` - Currently selected file
- `view.review_state` - The ReviewState (if review enabled)
- `view:infer_cur_file()` - Get file from cursor or current entry
- `view.adapter` - Git adapter for VCS operations

#### 4. Getting the Current File

Multiple patterns exist for getting the file to operate on:

**Pattern 1: `view:infer_cur_file()`**
Returns the file at cursor if in panel, or the currently selected file otherwise. Used by `toggle_stage_entry`, `restore_entry`.

```lua
local file = view:infer_cur_file()
if file then
  -- file is a FileEntry
end
```

**Pattern 2: `view.cur_entry`**
The currently active (displayed) file entry.

```lua
local file = view.cur_entry
if file then
  -- file is the displayed FileEntry
end
```

**Pattern 3: `view.panel:get_item_at_cursor()`**
Gets item under cursor in panel (could be file or directory).

```lua
local item = view.panel:get_item_at_cursor()
if item and type(item.collapsed) ~= "boolean" then
  -- item is a FileEntry (not a directory)
end
```

For review actions, `view:infer_cur_file()` is the best choice as it works both from the panel and from the diff view.

#### 5. File Panel Update Mechanism

When review state changes, the UI needs to update. The existing event system handles this:

**Events emitted by review.lua:**
- `review_file_marked` - payload: `{ view, file_entry, blob_hash }`
- `review_file_cleared` - payload: `{ view, file_entry }`
- `review_all_cleared` - payload: `{ view }`

**Panel update pattern:**
```lua
view.panel:render()
view.panel:redraw()
```

Or for full refresh:
```lua
view.panel:update_components()
view.panel:render()
view.panel:redraw()
```

Plan 3 will handle subscribing to these events and re-rendering the panel.

#### 6. FileHistoryView Consideration

The codebase has two view types:
- `DiffView` - For comparing branches/commits/working tree (has `review_state`)
- `FileHistoryView` - For file history (no `review_state` currently)

The review system is currently only integrated with `DiffView`. The actions should check for the correct view type and `review_state` availability.

#### 7. Existing Similar Actions as Templates

**`toggle_stage_entry`** (listeners.lua:130-191) - Good template for file-modifying actions:
- Gets file with `view:infer_cur_file(true)`
- Performs operation based on file state
- Updates the view: `view:update_files()`
- Emits event: `view.emitter:emit(EventName.FILES_STAGED, view)`

**`restore_entry`** (listeners.lua:222-246) - Shows async pattern:
- Uses `async.void()` wrapper
- Gets file, validates
- Performs operation
- Updates view

#### 8. Configuration and Keymaps

Keymaps are defined in `lua/diffview/config.lua`:

```lua
keymaps = {
  view = {
    -- Actions available in diff view windows
    { "n", "<tab>", actions.select_next_entry, { desc = "..." } },
  },
  file_panel = {
    -- Actions available in file panel
    { "n", "j", actions.next_entry, { desc = "..." } },
  },
}
```

Plan 5 will add the default keymaps for review actions. This plan focuses on implementing the actions themselves.

### Architectural Decisions

1. **Use event-emitting pattern**: Add action names to `action_names` array for simplicity and consistency.

2. **Listeners in DiffView only**: Review actions only make sense in DiffView context (FileHistoryView doesn't have review_state).

3. **Use `view:infer_cur_file()`**: Works from both panel and diff view contexts.

4. **Rely on existing review.lua API**: Don't duplicate logic; call the existing well-tested functions.

5. **Let Plan 3 handle UI updates**: The events are already emitted; Plan 3 will listen and re-render.

### Dependencies

- **Plan 2 (Complete)**: Storage system is fully implemented
- **Plan 3 (Pending)**: Will consume the events we emit for visual updates
- **Plan 5 (Pending)**: Will add default keymaps for these actions

### Potential Considerations

1. **Review not enabled**: Actions should gracefully handle `review_state` being nil (review disabled in config).

2. **FileHistoryView**: Actions will be no-ops if triggered from FileHistoryView since it lacks review_state.

3. **No files in view**: `mark_all_reviewed` should handle empty file list gracefully.

### Design Decisions (Confirmed)

1. **Silent feedback**: Actions do not show messages - the visual indicator in the file panel (Plan 3) provides sufficient feedback.

2. **No toggle action**: Separate mark/clear actions provide explicit control; no combined toggle action.

3. **No auto-advance**: After marking a file, selection stays on current file - user controls navigation.

4. **Scope boundary**: `review_clear_file` only clears single file; bulk clear with confirmation is Plan 9.

---

## Implementation Guide

### Step 1: Add Action Names to Registry

**File:** `lua/diffview/actions.lua`

Add the new action names to the `action_names` array (around line 618-648):

```lua
local action_names = {
  -- ... existing actions ...
  "review_mark_file",
  "review_mark_all",
  "review_clear_file",
}
```

This automatically creates functions like `M.review_mark_file = function() require("diffview").emit("review_mark_file") end`.

### Step 2: Implement DiffView Listeners

**File:** `lua/diffview/scene/views/diff/listeners.lua`

Add the listener handlers for the new actions. These should:
1. Get the current file using `view:infer_cur_file()`
2. Call the appropriate function from `lua/diffview/review.lua`
3. Handle edge cases (no file, review disabled)

**Implementation approach for each action:**

**`review_mark_file`:**
- Get current file with `view:infer_cur_file()`
- Call `review.mark_file_reviewed(view, file)`
- The review.lua function handles validation and event emission

**`review_mark_all`:**
- Call `review.mark_all_reviewed(view)`
- Optionally show count of files marked via `utils.info()`

**`review_clear_file`:**
- Get current file with `view:infer_cur_file()`
- Call `review.clear_file_review(view, file)`

### Step 3: Write Unit Tests

**File:** `lua/diffview/tests/functional/review_actions_spec.lua`

Test the action system integration:
1. Test that calling `actions.review_mark_file()` emits the correct event
2. Test listener handlers with mock view objects
3. Test edge cases (no file selected, review disabled)

Use the existing test patterns from `review_api_spec.lua` and `review_store_spec.lua` as templates.

### Manual Testing Steps

1. Open a diff view with `DiffviewOpen`
2. Navigate to a file (either select in panel or view the diff)
3. Trigger `review_mark_file` action
4. Verify file is marked (check with `review.get_file_status()`)
5. Trigger `review_mark_all` action
6. Verify all files are marked
7. Trigger `review_clear_file` action
8. Verify file status is cleared
9. Test with review disabled in config
10. Test from FileHistoryView (should be no-op)

### Acceptance Criteria

- [ ] `review_mark_file` action marks the current file as reviewed
- [ ] `review_mark_all` action marks all files as reviewed
- [ ] `review_clear_file` action clears the review state for current file
- [ ] Actions work from both file panel and diff view windows
- [ ] Actions are no-ops when review is disabled
- [ ] Actions are no-ops when no file is selected
- [ ] Events are emitted for UI updates (verified via Plan 3)
- [ ] Unit tests cover the action handlers

### Dependencies & Constraints

- **Dependencies**: Plan 2 (storage) must be complete (it is)
- **Technical Constraints**: Must use existing review.lua API; must follow action system patterns

### Implementation Notes

- **Recommended Approach**: Use the event-emitting pattern (add to `action_names`) rather than direct implementation, as this is the established pattern for most actions.

- **Potential Gotcha**: The `view:infer_cur_file()` function can return `nil` if no file is selected and the cursor isn't on a file entry. Always check for nil before passing to review functions.

- **No blocking requirements identified**: The review.lua API handles all validation and error cases internally.
