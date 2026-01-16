local lazy = require("diffview.lazy")

local config = lazy.require("diffview.config") ---@module "diffview.config"
local review_store = lazy.require("diffview.review_store") ---@module "diffview.review_store"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local M = {}

---Check if review mode is enabled
---@return boolean
local function is_review_enabled()
  local cfg = config.get_config()
  return cfg.review and cfg.review.enabled
end

---Get the blob hash for a file entry at HEAD
---@param view DiffView
---@param file_entry FileEntry
---@return string|nil
local function get_file_blob_hash(view, file_entry)
  -- Get the blob hash for the current state of the file
  -- Use "HEAD" to get the committed version's blob hash
  return view.adapter:file_blob_hash(file_entry.path, "HEAD")
end

---Get the current HEAD commit hash
---@param view DiffView
---@return string|nil commit_hash The HEAD commit SHA, or nil on error
local function get_head_commit_hash(view)
  local head_rev = view.adapter:head_rev()
  if head_rev and head_rev.commit then
    return head_rev.commit
  end
  return nil
end

---Mark a file as reviewed
---@param view DiffView
---@param file_entry FileEntry
---@return boolean success Whether the operation succeeded
function M.mark_file_reviewed(view, file_entry)
  if not is_review_enabled() then
    return false
  end

  if not view or not view.review_state then
    utils.warn("No review state available for this view")
    return false
  end

  if not file_entry or not file_entry.path then
    utils.warn("Invalid file entry")
    return false
  end

  local blob_hash = get_file_blob_hash(view, file_entry)
  if not blob_hash then
    utils.warn("Could not get blob hash for file: " .. file_entry.path)
    return false
  end

  local commit_hash = get_head_commit_hash(view)
  view.review_state:set_file_reviewed(file_entry.path, blob_hash, commit_hash)

  -- Emit event for UI updates
  DiffviewGlobal.emitter:emit("review_file_marked", {
    view = view,
    file_entry = file_entry,
    blob_hash = blob_hash,
    commit_hash = commit_hash,
  })

  return true
end

---Mark all files in the view as reviewed
---@param view DiffView
---@return integer count Number of files marked as reviewed
function M.mark_all_reviewed(view)
  if not is_review_enabled() then
    return 0
  end

  if not view or not view.review_state then
    utils.warn("No review state available for this view")
    return 0
  end

  if not view.files then
    return 0
  end

  -- Get commit hash once for all files (they all share the same HEAD)
  local commit_hash = get_head_commit_hash(view)

  local count = 0
  for _, file_entry in view.files:iter() do
    local blob_hash = get_file_blob_hash(view, file_entry)
    if blob_hash then
      -- Use skip_save=true to avoid saving on every file
      view.review_state:set_file_reviewed(file_entry.path, blob_hash, commit_hash, true)
      count = count + 1

      -- Emit event for each file
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = file_entry,
        blob_hash = blob_hash,
        commit_hash = commit_hash,
      })
    end
  end

  -- Save once after all files are marked
  if count > 0 then
    view.review_state.store:save_state(view.review_state)
  end

  return count
end

---Clear review status for a file
---@param view DiffView
---@param file_entry FileEntry
---@return boolean success Whether the operation succeeded
function M.clear_file_review(view, file_entry)
  if not is_review_enabled() then
    return false
  end

  if not view or not view.review_state then
    utils.warn("No review state available for this view")
    return false
  end

  if not file_entry or not file_entry.path then
    utils.warn("Invalid file entry")
    return false
  end

  view.review_state:clear_file(file_entry.path)

  -- Emit event for UI updates
  DiffviewGlobal.emitter:emit("review_file_cleared", {
    view = view,
    file_entry = file_entry,
  })

  return true
end

---Clear all reviews for the current branch
---@param view DiffView
---@return boolean success Whether the operation succeeded
function M.clear_all_reviews(view)
  if not is_review_enabled() then
    return false
  end

  if not view or not view.review_state then
    utils.warn("No review state available for this view")
    return false
  end

  view.review_state:clear_all()

  -- Emit event for UI updates
  DiffviewGlobal.emitter:emit("review_all_cleared", {
    view = view,
  })

  return true
end

---Get the review status of a file
---@param view DiffView
---@param file_entry FileEntry
---@return "unreviewed"|"reviewed"|"changed"|nil status The review status, or nil if review is disabled
function M.get_file_status(view, file_entry)
  if not is_review_enabled() then
    return nil
  end

  if not view or not view.review_state then
    return nil
  end

  if not file_entry or not file_entry.path then
    return nil
  end

  local current_blob_hash = get_file_blob_hash(view, file_entry)
  return view.review_state:get_file_status(file_entry.path, current_blob_hash)
end

---Get the ReviewStore singleton
---@return ReviewStore
function M.get_store()
  return review_store.get_store()
end

return M
