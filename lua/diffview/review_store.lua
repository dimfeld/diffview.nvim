local async = require("diffview.async")
local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local config = lazy.require("diffview.config") ---@module "diffview.config"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local await = async.await
local uv = vim.loop

local M = {}

-- Default cache directory path
local DEFAULT_CACHE_DIR = "~/.cache/diffview.nvim/reviews"

---@class ReviewEntry
---@field blob_hash string|nil Git blob hash of the file content when marked reviewed (nil for deleted files)
---@field reviewed_at number Unix timestamp of when the file was reviewed
---@field commit_hash? string Git commit hash when file was marked reviewed (optional for backward compatibility)
---@field deleted? boolean True if the file was deleted when marked reviewed

---@class ReviewState : diffview.Object
---@operator call : ReviewState
---@field repo_id string Identifier for the repository
---@field branch string Branch name
---@field files table<string, ReviewEntry> Map of file paths to review entries
---@field store ReviewStore Reference back to the store for saving
---@field dirty boolean Whether there are unsaved changes
local ReviewState = oop.create_class("ReviewState")

---@param opt { repo_id: string, branch: string, store: ReviewStore, files?: table<string, ReviewEntry> }
function ReviewState:init(opt)
  self.repo_id = opt.repo_id
  self.branch = opt.branch
  self.store = opt.store
  self.files = opt.files or {}
  self.dirty = false
end

---Get the review entry for a file
---@param path string Relative path to the file in the repo
---@return ReviewEntry|nil
function ReviewState:get_file(path)
  return self.files[path]
end

---Mark a file as reviewed
---@param path string Relative path to the file in the repo
---@param blob_hash string|nil Git blob hash of the file content (nil for deleted files)
---@param commit_hash? string Git commit hash at the time of review (optional for backward compatibility)
---@param skip_save? boolean If true, skip automatic save (useful for batch operations)
---@param deleted? boolean True if the file was deleted when marked reviewed
function ReviewState:set_file_reviewed(path, blob_hash, commit_hash, skip_save, deleted)
  self.files[path] = {
    blob_hash = deleted and nil or blob_hash,
    reviewed_at = os.time(),
    commit_hash = commit_hash,  -- may be nil for legacy compatibility
    deleted = deleted or nil,
  }
  self.dirty = true
  -- Trigger save asynchronously (unless skip_save is true for batch operations)
  if not skip_save then
    self.store:save_state(self)
  end
end

---Clear review status for a file
---@param path string Relative path to the file in the repo
function ReviewState:clear_file(path)
  if self.files[path] then
    self.files[path] = nil
    self.dirty = true
    self.store:save_state(self)
  end
end

---Clear all review statuses
function ReviewState:clear_all()
  self.files = {}
  self.dirty = true
  self.store:save_state(self)
end

---Get the review status of a file
---@param path string Relative path to the file in the repo
---@param current_blob_hash string|nil Current blob hash of the file
---@return "unreviewed"|"reviewed"|"changed"
function ReviewState:get_file_status(path, current_blob_hash)
  local entry = self.files[path]
  if not entry then
    return "unreviewed"
  end
  if entry.deleted then
    return current_blob_hash and "changed" or "reviewed"
  end
  if not current_blob_hash then
    return "reviewed"
  end
  if entry.blob_hash == current_blob_hash then
    return "reviewed"
  end
  return "changed"
end

---Serialize the review state to a table suitable for JSON encoding
---@return table
function ReviewState:to_table()
  return {
    version = 1,
    repo_id = self.repo_id,
    branch = self.branch,
    files = self.files,
  }
end

---Create a ReviewState from a deserialized JSON table
---@param data table
---@param store ReviewStore
---@return ReviewState
function ReviewState.from_table(data, store)
  -- Check version compatibility
  if data.version and data.version ~= 1 then
    utils.warn(("Unsupported review state version: %s, expected 1"):format(tostring(data.version)))
    -- Return empty state for unsupported versions
    return ReviewState({
      repo_id = data.repo_id or "unknown",
      branch = data.branch or "unknown",
      store = store,
      files = {},
    })
  end

  return ReviewState({
    repo_id = data.repo_id,
    branch = data.branch,
    store = store,
    files = data.files or {},
  })
end

M.ReviewState = ReviewState

---@class ReviewStore : diffview.Object
---@operator call : ReviewStore
---@field private cache_dir string|nil Configured cache directory
---@field private repo_id_cache table<string, string> Cache of toplevel paths to repo IDs
local ReviewStore = oop.create_class("ReviewStore")

-- Singleton instance
---@type ReviewStore|nil
local store_instance = nil

---Get the singleton instance of ReviewStore
---@return ReviewStore
function M.get_store()
  if not store_instance then
    store_instance = ReviewStore()
  end
  return store_instance
end

function ReviewStore:init()
  local cfg = config.get_config()
  self.cache_dir = cfg.review and cfg.review.cache_dir or nil
  self.repo_id_cache = {}
end

---Get the cache directory path, expanding ~ if needed
---@return string
function ReviewStore:get_cache_dir()
  local dir = self.cache_dir or DEFAULT_CACHE_DIR
  -- Expand ~ to home directory
  if dir:sub(1, 1) == "~" then
    local home = uv.os_homedir()
    dir = home .. dir:sub(2)
  end
  return dir
end

---Get the repository ID from the initial commit hash
---This ensures multiple checkouts/clones of the same repo share review state
---@param adapter VCSAdapter The VCS adapter
---@return string|nil repo_id The first 12 characters of the initial commit SHA, or nil on error
function ReviewStore:get_repo_id(adapter)
  local toplevel = adapter.ctx.toplevel

  -- Check cache first
  if self.repo_id_cache[toplevel] then
    return self.repo_id_cache[toplevel]
  end

  -- Get the initial commit hash
  local out, code = adapter:exec_sync({
    "rev-list",
    "--max-parents=0",
    "HEAD",
  }, {
    cwd = toplevel,
    retry = 2,
    fail_on_empty = true,
  })

  if code ~= 0 or not out or #out == 0 then
    utils.warn("Failed to get repository ID for review state")
    return nil
  end

  -- Take first 12 characters of the initial commit SHA
  local repo_id = vim.trim(out[1]):sub(1, 12)

  -- Cache the result
  self.repo_id_cache[toplevel] = repo_id

  return repo_id
end

---Check if a git blob still exists (hasn't been garbage collected)
---@param adapter VCSAdapter The VCS adapter
---@param blob_hash string The git blob hash to check
---@return boolean exists True if the blob exists, false if garbage collected
function ReviewStore:verify_blob_exists(adapter, blob_hash)
  local _, code = adapter:exec_sync({
    "cat-file",
    "-e",
    blob_hash,
  }, {
    cwd = adapter.ctx.toplevel,
    retry = 2,
  })
  return code == 0
end

---Sanitize a branch name for use as a filename
---Replaces / with __ to make it filesystem-safe
---@param branch string The branch name
---@return string sanitized The sanitized branch name
function ReviewStore:sanitize_branch(branch)
  return branch:gsub("/", "__")
end

---Convert a sanitized filename back to possible branch names
---Since we can't know if double underscores were originally slashes or literal,
---we return both possibilities.
---@param filename string The sanitized filename (e.g., "feature__foo.json")
---@return string[] possible_branches List of possible original branch names
function ReviewStore:unsanitize_branch(filename)
  -- Strip .json extension
  local name = filename:gsub("%.json$", "")

  -- If there are no double underscores, only one possibility
  if not name:find("__") then
    return { name }
  end

  -- Return both: the literal name and the one with __ replaced by /
  local with_slashes = name:gsub("__", "/")
  return { name, with_slashes }
end

---@class StoredBranchInfo
---@field filename string The JSON filename (e.g., "main.json")
---@field possible_branches string[] List of possible original branch names

---Get all stored branches for a repository
---Scans the repo directory and returns information about stored branch files
---@param repo_id string The repository ID
---@return StoredBranchInfo[] stored_branches List of stored branch information
function ReviewStore:get_stored_branches(repo_id)
  local cache_dir = self:get_cache_dir()
  local repo_dir = utils.path:join(cache_dir, repo_id)

  -- Check if directory exists
  local stat = utils.path:stat(repo_dir)
  if not stat or stat.type ~= "directory" then
    return {}
  end

  local result = {}
  local handle = uv.fs_scandir(repo_dir)
  if handle then
    while true do
      local name, ftype = uv.fs_scandir_next(handle)
      if not name then break end
      -- Only process .json files
      if ftype == "file" and name:match("%.json$") then
        table.insert(result, {
          filename = name,
          possible_branches = self:unsanitize_branch(name),
        })
      end
    end
  end

  return result
end

---Get the full path to the state file for a repo and branch
---@param repo_id string The repository ID
---@param branch string The branch name
---@return string path The full path to the JSON file
function ReviewStore:get_state_path(repo_id, branch)
  local cache_dir = self:get_cache_dir()
  local sanitized_branch = self:sanitize_branch(branch)
  return utils.path:join(cache_dir, repo_id, sanitized_branch .. ".json")
end

---Ensure the cache directory exists for a given repo
---@param self ReviewStore
---@param repo_id string The repository ID
ReviewStore.ensure_cache_dir = async.void(function(self, repo_id)
  local cache_dir = self:get_cache_dir()
  local repo_dir = utils.path:join(cache_dir, repo_id)

  -- Check if directory already exists
  local stat = utils.path:stat(repo_dir)
  if stat and stat.type == "directory" then
    return
  end

  -- Create the directory with parents
  local ok, err = pcall(function()
    await(utils.path:mkdir(repo_dir, { parents = true }))
  end)

  if not ok then
    utils.warn(("Failed to create cache directory: %s"):format(err))
  end
end)

---Save review state to disk
---@param self ReviewStore
---@param state ReviewState The state to save
ReviewStore.save_state = async.void(function(self, state)
  if not state.repo_id or state.repo_id == "unknown" then
    utils.warn("Cannot save review state: unknown repository ID")
    return
  end

  -- Ensure directory exists
  await(self:ensure_cache_dir(state.repo_id))

  local state_path = self:get_state_path(state.repo_id, state.branch)

  -- Serialize to JSON
  local encode_ok, content = pcall(vim.json.encode, state:to_table())
  if not encode_ok or not content then
    utils.warn("Failed to serialize review state to JSON")
    return
  end

  -- Write to file
  local ok, err = pcall(function()
    local fd = assert(uv.fs_open(state_path, "w", 438)) -- 438 = 0666
    assert(uv.fs_write(fd, content, 0))
    assert(uv.fs_close(fd))
  end)

  if not ok then
    utils.warn(("Failed to save review state to %s: %s"):format(state_path, err))
    return
  end

  state.dirty = false
end)

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

---Load review state synchronously (blocking)
---@param adapter VCSAdapter The VCS adapter
---@param branch string The branch name
---@return ReviewState The loaded or new review state
function ReviewStore:load_state_sync(adapter, branch)
  local repo_id = self:get_repo_id(adapter)
  if not repo_id then
    return ReviewState({
      repo_id = "unknown",
      branch = branch,
      store = self,
    })
  end

  local state_path = self:get_state_path(repo_id, branch)

  -- Check if file exists
  local stat = utils.path:stat(state_path)
  if not stat then
    return ReviewState({
      repo_id = repo_id,
      branch = branch,
      store = self,
    })
  end

  -- Read the file synchronously
  local ok, content = pcall(function()
    local fd = assert(uv.fs_open(state_path, "r", 438))
    local fstat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, fstat.size, 0))
    assert(uv.fs_close(fd))
    return data
  end)

  if not ok or not content then
    utils.warn(("Failed to read review state from %s"):format(state_path))
    return ReviewState({
      repo_id = repo_id,
      branch = branch,
      store = self,
    })
  end

  -- Parse JSON
  local decode_ok, data = pcall(vim.json.decode, content)
  if not decode_ok or not data then
    utils.warn(("Failed to parse review state from %s"):format(state_path))
    return ReviewState({
      repo_id = repo_id,
      branch = branch,
      store = self,
    })
  end

  return ReviewState.from_table(data, self)
end

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
---Compares stored branch files against git branches and deletes stale ones.
---A branch is considered stale if:
---  1. It doesn't exist in git (local or remote), AND
---  2. Its most recent review timestamp is older than max_age_days
---Detached HEAD files are always cleaned up based on age alone.
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
        local delete_ok = pcall(uv.fs_unlink, file_path)
        if delete_ok then
          result.deleted_count = result.deleted_count + 1
        end
      else
        result.deleted_count = result.deleted_count + 1
      end
    end
  end

  return result
end

M.ReviewStore = ReviewStore

return M
