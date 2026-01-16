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
---@field blob_hash string Git blob hash of the file content when marked reviewed
---@field reviewed_at number Unix timestamp of when the file was reviewed
---@field commit_hash? string Git commit hash when file was marked reviewed (optional for backward compatibility)

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
---@param blob_hash string Git blob hash of the file content
---@param commit_hash? string Git commit hash at the time of review (optional for backward compatibility)
---@param skip_save? boolean If true, skip automatic save (useful for batch operations)
function ReviewState:set_file_reviewed(path, blob_hash, commit_hash, skip_save)
  self.files[path] = {
    blob_hash = blob_hash,
    reviewed_at = os.time(),
    commit_hash = commit_hash,  -- may be nil for legacy compatibility
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

M.ReviewStore = ReviewStore

return M
