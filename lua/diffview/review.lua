local lazy = require("diffview.lazy")

local config = lazy.require("diffview.config") ---@module "diffview.config"
local review_store = lazy.require("diffview.review_store") ---@module "diffview.review_store"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local M = {}

---@param status? string
---@return boolean
local function is_deleted_status(status)
  if not status or status == "" then return false end
  return status:find("D", 1, true) ~= nil
end

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
  local is_deleted = not blob_hash and is_deleted_status(file_entry.status)
  if not blob_hash and not is_deleted then
    utils.warn("Could not get blob hash for file: " .. file_entry.path)
    return false
  end

  local commit_hash = get_head_commit_hash(view)
  view.review_state:set_file_reviewed(file_entry.path, blob_hash, commit_hash, nil, is_deleted)

  -- Emit event for UI updates
  DiffviewGlobal.emitter:emit("review_file_marked", {
    view = view,
    file_entry = file_entry,
    blob_hash = blob_hash,
    commit_hash = commit_hash,
    deleted = is_deleted,
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
    local is_deleted = not blob_hash and is_deleted_status(file_entry.status)
    if blob_hash or is_deleted then
      -- Use skip_save=true to avoid saving on every file
      view.review_state:set_file_reviewed(file_entry.path, blob_hash, commit_hash, true, is_deleted)
      count = count + 1

      -- Emit event for each file
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = file_entry,
        blob_hash = blob_hash,
        commit_hash = commit_hash,
        deleted = is_deleted,
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

---Get the review status of a file
---Uses the view's cached status when available for performance.
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

  -- Use the view's cached status method if available (DiffView has it)
  if view.get_cached_review_status then
    return view:get_cached_review_status(file_entry)
  end

  -- Fall back to direct lookup (expensive - spawns a git process per file)
  local current_blob_hash = get_file_blob_hash(view, file_entry)
  return view.review_state:get_file_status(file_entry.path, current_blob_hash)
end

---Get the ReviewStore singleton
---@return ReviewStore
function M.get_store()
  return review_store.get_store()
end

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

return M
