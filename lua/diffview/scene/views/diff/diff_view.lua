local async = require("diffview.async")
local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local CommitLogPanel = lazy.access("diffview.ui.panels.commit_log_panel", "CommitLogPanel") ---@type CommitLogPanel|LazyModule
local Diff = lazy.access("diffview.diff", "Diff") ---@type Diff|LazyModule
local EditToken = lazy.access("diffview.diff", "EditToken") ---@type EditToken|LazyModule
local EventName = lazy.access("diffview.events", "EventName") ---@type EventName|LazyModule
local File = lazy.access("diffview.vcs.file", "File") ---@type vcs.File|LazyModule
local FileDict = lazy.access("diffview.vcs.file_dict", "FileDict") ---@type FileDict|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local FilePanel = lazy.access("diffview.scene.views.diff.file_panel", "FilePanel") ---@type FilePanel|LazyModule
local GitRev = lazy.access("diffview.vcs.adapters.git.rev", "GitRev") ---@type GitRev|LazyModule
local PerfTimer = lazy.access("diffview.perf", "PerfTimer") ---@type PerfTimer|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local StandardView = lazy.access("diffview.scene.views.standard.standard_view", "StandardView") ---@type StandardView|LazyModule
local config = lazy.require("diffview.config") ---@module "diffview.config"
local debounce = lazy.require("diffview.debounce") ---@module "diffview.debounce"
local review = lazy.require("diffview.review") ---@module "diffview.review"
local review_store = lazy.require("diffview.review_store") ---@module "diffview.review_store"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local vcs_utils = lazy.require("diffview.vcs.utils") ---@module "diffview.vcs.utils"
local GitAdapter = lazy.access("diffview.vcs.adapters.git", "GitAdapter") ---@type GitAdapter|LazyModule

local api = vim.api
local await = async.await
local fmt = string.format
local logger = DiffviewGlobal.logger
local pl = lazy.access(utils, "path") ---@type PathLib

local M = {}

---@class DiffViewOptions
---@field show_untracked? boolean
---@field selected_file? string Path to the preferred initially selected file.

---@class DiffView : StandardView
---@operator call : DiffView
---@field adapter VCSAdapter
---@field rev_arg string
---@field path_args string[]
---@field left Rev
---@field right Rev
---@field options DiffViewOptions
---@field panel FilePanel
---@field commit_log_panel CommitLogPanel
---@field files FileDict
---@field file_idx integer
---@field merge_ctx? vcs.MergeContext
---@field initialized boolean
---@field valid boolean
---@field watcher uv_fs_poll_t # UV fs poll handle.
---@field review_state? ReviewState # Review state for tracking reviewed files.
---@field review_event_callbacks? table<string, function> # Callbacks for review event cleanup.
---@field review_filter_enabled boolean # Whether to filter panel to show only pending review files.
---@field since_review_mode boolean # Whether to show only changes since last review for "changed" files.
local DiffView = oop.create_class("DiffView", StandardView.__get())

---DiffView constructor
function DiffView:init(opt)
  self.valid = false
  self.files = FileDict()
  self.adapter = opt.adapter
  self.path_args = opt.path_args
  self.rev_arg = opt.rev_arg
  self.left = opt.left
  self.right = opt.right
  self.initialized = false
  self.options = opt.options or {}
  self.review_filter_enabled = false
  self.since_review_mode = false
  self.options.selected_file = self.options.selected_file
    and pl:chain(self.options.selected_file)
        :absolute()
        :relative(self.adapter.ctx.toplevel)
        :get()

  self:super({
    panel = FilePanel(
      self.adapter,
      self.files,
      self.path_args,
      self.rev_arg or self.adapter:rev_to_pretty_string(self.left, self.right)
    ),
  })

  -- Set panel's back-reference to this view
  self.panel.view = self

  self.attached_bufs = {}
  self.emitter:on("file_open_post", utils.bind(self.file_open_post, self))
  self.valid = true
end

function DiffView:post_open()
  vim.cmd("redraw")

  self.commit_log_panel = CommitLogPanel(self.adapter, {
    name = fmt("diffview://%s/log/%d/%s", self.adapter.ctx.dir, self.tabpage, "commit_log"),
  })

  -- Load review state if review mode is enabled
  local cfg = config.get_config()
  if cfg.review and cfg.review.enabled and self.adapter:instanceof(GitAdapter.__get()) then
    local branch = self.adapter:get_current_branch()
    local store = review_store.get_store()
    self.review_state = store:load_state_sync(self.adapter, branch)
  end

  if cfg.watch_index and self.adapter:instanceof(GitAdapter.__get()) then
    self.watcher = vim.loop.new_fs_poll()
    self.watcher:start(
      self.adapter.ctx.dir .. "/index",
      1000,
      ---@diagnostic disable-next-line: unused-local
      vim.schedule_wrap(function(err, prev, cur)
        if not err then
          if self:is_cur_tabpage() then
            self:update_files()
          end
        end
      end)
    )
  end

  self:init_event_listeners()
  self:init_review_event_listeners()

  vim.schedule(function()
    self:file_safeguard()
    if self.files:len() == 0 then
      self:update_files()
    end
    self.ready = true
  end)
end

---@param e Event
---@param new_entry FileEntry
---@param old_entry FileEntry
---@diagnostic disable-next-line: unused-local
function DiffView:file_open_post(e, new_entry, old_entry)
  if new_entry.layout:is_nulled() then return end
  if new_entry.kind == "conflicting" then
    local file = new_entry.layout:get_main_win().file

    local count_conflicts = vim.schedule_wrap(function()
      local conflicts = vcs_utils.parse_conflicts(api.nvim_buf_get_lines(file.bufnr, 0, -1, false))

      new_entry.stats = new_entry.stats or {}
      new_entry.stats.conflicts = #conflicts

      self.panel:render()
      self.panel:redraw()
    end)

    count_conflicts()

    if file.bufnr and not self.attached_bufs[file.bufnr] then
      self.attached_bufs[file.bufnr] = true

      local work = debounce.throttle_trailing(
        1000,
        true,
        vim.schedule_wrap(function()
          if not self:is_cur_tabpage() or self.cur_entry ~= new_entry then
            self.attached_bufs[file.bufnr] = false
            return
          end

          count_conflicts()
        end)
      )

      api.nvim_create_autocmd(
        { "TextChanged", "TextChangedI" },
        {
          buffer = file.bufnr,
          callback = function()
            if not self.attached_bufs[file.bufnr] then
              work:close()
              return true
            end

            work()
          end,
        }
      )
    end
  end
end

---@override
function DiffView:close()
  if not self.closing:check() then
    self.closing:send()

    -- Clean up review event listeners
    if self.review_event_callbacks then
      DiffviewGlobal.emitter:off(self.review_event_callbacks.file_marked, "review_file_marked")
      DiffviewGlobal.emitter:off(self.review_event_callbacks.file_cleared, "review_file_cleared")
      DiffviewGlobal.emitter:off(self.review_event_callbacks.all_cleared, "review_all_cleared")
      DiffviewGlobal.emitter:off(self.review_event_callbacks.repo_cleared, "review_repo_cleared")
      self.review_event_callbacks = nil
    end

    if self.watcher then
      self.watcher:stop()
      self.watcher:close()
    end

    for _, file in self.files:iter() do
      file:destroy()
    end

    self.commit_log_panel:destroy()
    DiffView.super_class.close(self)
  end
end

---Create a modified FileEntry for since-review mode that uses the review commit as the left revision.
---@param self DiffView
---@param file FileEntry The original file entry
---@param review_entry ReviewEntry The review entry with commit_hash
---@return FileEntry modified_entry A new FileEntry with since-review revisions
---@private
DiffView._create_since_review_entry = function(self, file, review_entry)
  -- Create a new Rev for the left side using the review commit
  local review_rev = GitRev(RevType.COMMIT, review_entry.commit_hash)

  -- Create the new revisions map (left = review commit, right = same as original)
  local new_revs = {
    a = review_rev,
    b = file.revs.b, -- Keep the original right revision
    c = file.revs.c,
    d = file.revs.d,
  }

  -- Create a new FileEntry with the modified revisions
  local since_review_entry = FileEntry.with_layout(file.layout.class, {
    adapter = file.adapter,
    path = file.path,
    oldpath = file.oldpath,
    revs = new_revs,
    status = file.status,
    stats = file.stats,
    kind = file.kind,
    commit = file.commit,
    get_data = nil, -- Use default data fetching
    nulled = false,
  })

  return since_review_entry
end

---@private
---@param self DiffView
---@param file FileEntry
DiffView._set_file = async.void(function(self, file)
  self.panel:render()
  self.panel:redraw()
  vim.cmd("redraw")

  self.cur_layout:detach_files()
  local cur_entry = self.cur_entry
  self.emitter:emit("file_open_pre", file, cur_entry)
  self.nulled = false

  -- Determine which entry to use (original or since-review modified)
  local entry_to_use = file
  local using_since_review = false

  if self.since_review_mode then
    local status = review.get_file_status(self, file)
    if status == "changed" then
      local review_entry, err = self:get_since_review_entry(file)
      if review_entry then
        entry_to_use = self:_create_since_review_entry(file, review_entry)
        using_since_review = true
        -- Show indicator that we're viewing since-review diff
        api.nvim_echo({{ fmt("[Since review: %s]", review_entry.commit_hash:sub(1, 7)), "Comment" }}, false, {})
      elseif err then
        -- Fall back to full diff and warn user
        utils.info(fmt("Since-review mode: %s - showing full diff", err))
      end
    end
  end

  -- When using since-review mode with a temporary entry, the temporary entry
  -- will be garbage collected after use (layout files are transferred to cur_layout)
  await(self:use_entry(entry_to_use))

  self.emitter:emit("file_open_post", file, cur_entry)

  -- Track opened state on the original file entry, not the temporary since-review entry
  if not file.opened then
    file.opened = true
    DiffviewGlobal.emitter:emit("file_open_new", file)
  end
end)

---Open the next file.
---@param highlight? boolean Bring the cursor to the file entry in the panel.
---@return FileEntry?
function DiffView:next_file(highlight)
  self:ensure_layout()

  if self:file_safeguard() then return end

  if self.files:len() > 1 or self.nulled then
    local cur = self.panel:next_file()

    if cur then
      if highlight or not self.panel:is_focused() then
        self.panel:highlight_file(cur)
      end

      self:_set_file(cur)

      return cur
    end
  end
end

---Open the previous file.
---@param highlight? boolean Bring the cursor to the file entry in the panel.
---@return FileEntry?
function DiffView:prev_file(highlight)
  self:ensure_layout()

  if self:file_safeguard() then return end

  if self.files:len() > 1 or self.nulled then
    local cur = self.panel:prev_file()

    if cur then
      if highlight or not self.panel:is_focused() then
        self.panel:highlight_file(cur)
      end

      self:_set_file(cur)

      return cur
    end
  end
end

---Set the active file.
---@param self DiffView
---@param file FileEntry
---@param focus? boolean Bring focus to the diff buffers.
---@param highlight? boolean Bring the cursor to the file entry in the panel.
DiffView.set_file = async.void(function(self, file, focus, highlight)
  ---@diagnostic disable: invisible
  self:ensure_layout()

  if self:file_safeguard() or not file then return end

  for _, f in self.files:iter() do
    if f == file then
      self.panel:set_cur_file(file)

      if highlight or not self.panel:is_focused() then
        self.panel:highlight_file(file)
      end

      await(self:_set_file(file))

      if focus then
        api.nvim_set_current_win(self.cur_layout:get_main_win().id)
      end
    end
  end
  ---@diagnostic enable: invisible
end)

---Set the active file.
---@param self DiffView
---@param path string
---@param focus? boolean Bring focus to the diff buffers.
---@param highlight? boolean Bring the cursor to the file entry in the panel.
DiffView.set_file_by_path = async.void(function(self, path, focus, highlight)
  ---@type FileEntry
  for _, file in self.files:iter() do
    if file.path == path then
      await(self:set_file(file, focus, highlight))
      return
    end
  end
end)

---Get an updated list of files.
---@param self DiffView
---@param callback fun(err?: string[], files: FileDict)
DiffView.get_updated_files = async.wrap(function(self, callback)
  vcs_utils.diff_file_list(
    self.adapter,
    self.left,
    self.right,
    self.path_args,
    self.options,
    {
      default_layout = DiffView.get_default_layout(),
      merge_layout = DiffView.get_default_merge_layout(),
    },
    callback
  )
end)

---Update the file list, including stats and status for all files.
DiffView.update_files = debounce.debounce_trailing(
  100,
  true,
  ---@param self DiffView
  ---@param callback fun(err?: string[])
  async.wrap(function(self, callback)
    await(async.scheduler())

    -- Never update unless the view is in focus
    if self.tabpage ~= api.nvim_get_current_tabpage() then
      callback({ "The update was cancelled." })
      return
    end

    ---@type PerfTimer
    local perf = PerfTimer("[DiffView] Status Update")
    self:ensure_layout()

    -- If left is tracking HEAD and right is LOCAL: Update HEAD rev.
    local new_head
    if self.left.track_head and self.right.type == RevType.LOCAL then
      new_head = self.adapter:head_rev()
      if new_head and self.left.commit ~= new_head.commit then
        self.left = new_head
      else
        new_head = nil
      end
      perf:lap("updated head rev")
    end

    local index_stat = pl:stat(pl:join(self.adapter.ctx.dir, "index"))

    ---@type string[]?, FileDict
    local err, new_files = await(self:get_updated_files())
    await(async.scheduler())

    if err then
      utils.err("Failed to update files in a diff view!", true)
      logger:error("[DiffView] Failed to update files!")
      callback(err)
      return
    end

    -- Stop the update if the view is no longer in focus.
    if self.tabpage ~= api.nvim_get_current_tabpage() then
      callback({ "The update was cancelled." })
      return
    end

    perf:lap("received new file list")

    local files = {
      { cur_files = self.files.conflicting, new_files = new_files.conflicting },
      { cur_files = self.files.working, new_files = new_files.working },
      { cur_files = self.files.staged, new_files = new_files.staged },
    }

    for _, v in ipairs(files) do
      -- We diff the old file list against the new file list in order to find
      -- the most efficient way to morph the current list into the new. This
      -- way we avoid having to discard and recreate buffers for files that
      -- exist in both lists.
      ---@param aa FileEntry
      ---@param bb FileEntry
      local diff = Diff(v.cur_files, v.new_files, function(aa, bb)
        return aa.path == bb.path and aa.oldpath == bb.oldpath
      end)

      local script = diff:create_edit_script()
      local ai = 1
      local bi = 1

      for _, opr in ipairs(script) do
        if opr == EditToken.NOOP then
          -- Update status and stats
          local a_stats = v.cur_files[ai].stats
          local b_stats = v.new_files[bi].stats

          if a_stats then
            v.cur_files[ai].stats = vim.tbl_extend("force", a_stats, b_stats or {})
          else
            v.cur_files[ai].stats = v.new_files[bi].stats
          end

          v.cur_files[ai].status = v.new_files[bi].status
          v.cur_files[ai]:validate_stage_buffers(index_stat)

          if new_head then
            v.cur_files[ai]:update_heads(new_head)
          end

          ai = ai + 1
          bi = bi + 1

        elseif opr == EditToken.DELETE then
          if self.panel.cur_file == v.cur_files[ai] then
            local file_list = self.panel:ordered_file_list()
            if file_list[1] == self.panel.cur_file then
              self.panel:set_cur_file(nil)
            else
              self.panel:set_cur_file(self.panel:prev_file())
            end
          end

          v.cur_files[ai]:destroy()
          table.remove(v.cur_files, ai)

        elseif opr == EditToken.INSERT then
          table.insert(v.cur_files, ai, v.new_files[bi])
          ai = ai + 1
          bi = bi + 1

        elseif opr == EditToken.REPLACE then
          if self.panel.cur_file == v.cur_files[ai] then
            local file_list = self.panel:ordered_file_list()
            if file_list[1] == self.panel.cur_file then
              self.panel:set_cur_file(nil)
            else
              self.panel:set_cur_file(self.panel:prev_file())
            end
          end

          v.cur_files[ai]:destroy()
          v.cur_files[ai] = v.new_files[bi]
          ai = ai + 1
          bi = bi + 1
        end
      end
    end

    perf:lap("updated file list")

    self.merge_ctx = next(new_files.conflicting) and self.adapter:get_merge_context() or nil

    if self.merge_ctx then
      for _, entry in ipairs(self.files.conflicting) do
        entry:update_merge_context(self.merge_ctx)
      end
    end

    FileEntry.update_index_stat(self.adapter, index_stat)
    self.files:update_file_trees()
    self.panel:update_components()
    self.panel:render()
    self.panel:redraw()
    perf:lap("panel redrawn")
    self.panel:reconstrain_cursor()

    if utils.vec_indexof(self.panel:ordered_file_list(), self.panel.cur_file) == -1 then
      self.panel:set_cur_file(nil)
    end

    -- Set initially selected file
    if not self.initialized and self.options.selected_file then
      for _, file in self.files:iter() do
        if file.path == self.options.selected_file then
          self.panel:set_cur_file(file)
          break
        end
      end
    end
    self:set_file(self.panel.cur_file or self.panel:next_file(), false, not self.initialized)

    self.update_needed = false
    perf:time()
    logger:lvl(5):debug(perf)
    logger:fmt_info(
      "[%s] Completed update for %d files successfully (%.3f ms)",
      self.class:name(),
      self.files:len(),
      perf.final_time
    )
    self.emitter:emit("files_updated", self.files)

    callback()
  end)
)

---Ensures there are files to load, and loads the null buffer otherwise.
---@return boolean
function DiffView:file_safeguard()
  if self.files:len() == 0 then
    local cur = self.panel.cur_file

    if cur then
      cur.layout:detach_files()
    end

    self.cur_layout:open_null()
    self.nulled = true

    return true
  end
  return false
end

function DiffView:on_files_staged(callback)
  self.emitter:on(EventName.FILES_STAGED, callback)
end

function DiffView:init_event_listeners()
  local listeners = require("diffview.scene.views.diff.listeners")(self)
  for event, callback in pairs(listeners) do
    self.emitter:on(event, callback)
  end
end

---Subscribe to global review events to refresh the panel when review state changes.
function DiffView:init_review_event_listeners()
  -- Store callbacks for cleanup
  self.review_event_callbacks = {}

  local function refresh_panel()
    if self.panel:is_open() then
      self.panel:update_components()
      self.panel:render()
      self.panel:redraw()
    end
  end

  self.review_event_callbacks.file_marked = function(_, payload)
    if payload.view == self then
      refresh_panel()

      -- Auto-disable filter when all files are marked reviewed
      if self.review_filter_enabled then
        local visible_files = self.panel:ordered_file_list()
        if #visible_files == 0 then
          self.review_filter_enabled = false
          self.panel:update_components()
          self.panel:render()
          self.panel:redraw()
          api.nvim_echo({{ "All files reviewed - filter disabled" }}, false, {})
        end
      end
    end
  end

  self.review_event_callbacks.file_cleared = function(_, payload)
    if payload.view == self then
      refresh_panel()
    end
  end

  self.review_event_callbacks.all_cleared = function(_, payload)
    if payload.view == self then
      -- Disable review filter if active since there's nothing to filter
      if self.review_filter_enabled then
        self.review_filter_enabled = false
      end
      refresh_panel()
    end
  end

  self.review_event_callbacks.repo_cleared = function(_, payload)
    if payload.view == self then
      -- Disable review filter if active since there's nothing to filter
      if self.review_filter_enabled then
        self.review_filter_enabled = false
      end
      refresh_panel()
    end
  end

  DiffviewGlobal.emitter:on("review_file_marked", self.review_event_callbacks.file_marked)
  DiffviewGlobal.emitter:on("review_file_cleared", self.review_event_callbacks.file_cleared)
  DiffviewGlobal.emitter:on("review_all_cleared", self.review_event_callbacks.all_cleared)
  DiffviewGlobal.emitter:on("review_repo_cleared", self.review_event_callbacks.repo_cleared)
end

---Infer the current selected file. If the file panel is focused: return the
---file entry under the cursor. Otherwise return the file open in the view.
---Returns nil if no file is open in the view, or there is no entry under the
---cursor in the file panel.
---@param allow_dir? boolean Allow directory nodes from the file tree.
---@return (FileEntry|DirData)?
function DiffView:infer_cur_file(allow_dir)
  if self.panel:is_focused() then
    ---@type any
    local item = self.panel:get_item_at_cursor()
    if not item then return end
    if not allow_dir and type(item.collapsed) == "boolean" then return end

    return item
  else
    return self.panel.cur_file
  end
end

---Check whether or not the instantiation was successful.
---@return boolean
function DiffView:is_valid()
  return self.valid
end

---Get the review status for a file entry.
---@param file_entry FileEntry
---@return "unreviewed"|"reviewed"|"changed"|nil status The review status, or nil if review is disabled
function DiffView:get_file_review_status(file_entry)
  if not self.review_state then
    return nil
  end

  if not file_entry or not file_entry.path then
    return nil
  end

  -- Get the current blob hash to compare against the stored hash
  local current_blob_hash = self.adapter:file_blob_hash(file_entry.path, "HEAD")
  return self.review_state:get_file_status(file_entry.path, current_blob_hash)
end

---Helper function to navigate to files matching a review status filter.
---@param delta integer Direction to navigate (+1 for next, -1 for previous)
---@param status_filter fun(status: string|nil): boolean Function to filter files by status
---@param label string Label for the status message (e.g., "Pending review", "Unreviewed")
---@return FileEntry|nil target_file The file navigated to, or nil if none found
---@private
function DiffView:_navigate_review_file(delta, status_filter, label)
  self:ensure_layout()

  if self:file_safeguard() then return nil end

  if not self.review_state then
    utils.info("Review mode is not enabled")
    return nil
  end

  local files = self.panel:ordered_file_list()
  if #files == 0 then
    return nil
  end

  -- Build list of files matching the filter
  local matching_files = {}
  for _, file in ipairs(files) do
    local status = review.get_file_status(self, file)
    if status_filter(status) then
      matching_files[#matching_files + 1] = file
    end
  end

  if #matching_files == 0 then
    utils.info(("No %s files"):format(label:lower()))
    return nil
  end

  -- Find current position in the matching files list
  local cur_file = self.panel.cur_file
  local cur_matching_idx = 0
  for i, file in ipairs(matching_files) do
    if file == cur_file then
      cur_matching_idx = i
      break
    end
  end

  -- Calculate next position using count and modulo for wrapping
  local count = vim.v.count1
  local next_idx

  if cur_matching_idx == 0 then
    -- Current file is not in the matching list, go to first match in direction
    if delta > 0 then
      next_idx = 1
    else
      next_idx = #matching_files
    end
  else
    next_idx = (cur_matching_idx + delta * count - 1) % #matching_files + 1
  end

  local target_file = matching_files[next_idx]

  -- Navigate to the file
  self.panel:set_cur_file(target_file)
  self.panel:highlight_file(target_file)
  self:_set_file(target_file)

  -- Show position message
  api.nvim_echo({{ ("%s [%d/%d]"):format(label, next_idx, #matching_files) }}, false, {})

  return target_file
end

---Navigate to the next file pending review (unreviewed or changed).
---@return FileEntry|nil
function DiffView:next_pending_review_file()
  return self:_navigate_review_file(1, function(status)
    return status == "unreviewed" or status == "changed"
  end, "Pending review")
end

---Navigate to the previous file pending review (unreviewed or changed).
---@return FileEntry|nil
function DiffView:prev_pending_review_file()
  return self:_navigate_review_file(-1, function(status)
    return status == "unreviewed" or status == "changed"
  end, "Pending review")
end

---Navigate to the next unreviewed file (never reviewed).
---@return FileEntry|nil
function DiffView:next_unreviewed_file()
  return self:_navigate_review_file(1, function(status)
    return status == "unreviewed"
  end, "Unreviewed")
end

---Navigate to the previous unreviewed file (never reviewed).
---@return FileEntry|nil
function DiffView:prev_unreviewed_file()
  return self:_navigate_review_file(-1, function(status)
    return status == "unreviewed"
  end, "Unreviewed")
end

---Toggle the review filter to show only files pending review.
---When enabled, only files with status "unreviewed" or "changed" are shown.
function DiffView:toggle_review_filter()
  if not self.review_state then
    utils.info("Review mode is not enabled")
    return
  end

  self.review_filter_enabled = not self.review_filter_enabled

  -- Update the panel to reflect the filter state
  self.panel:update_components()
  self.panel:render()
  self.panel:redraw()

  -- Check for edge cases when enabling the filter
  if self.review_filter_enabled then
    local visible_files = self.panel:ordered_file_list()
    local total_files = self.files:len()

    -- If no files pending review, auto-disable the filter
    if #visible_files == 0 then
      self.review_filter_enabled = false
      self.panel:update_components()
      self.panel:render()
      self.panel:redraw()
      api.nvim_echo({{ "All files reviewed - filter disabled" }}, false, {})
      return
    end

    -- If current file is now filtered out, move to first visible file
    if self.panel.cur_file then
      local cur_visible = false
      for _, file in ipairs(visible_files) do
        if file == self.panel.cur_file then
          cur_visible = true
          break
        end
      end

      if not cur_visible then
        self.panel:set_cur_file(visible_files[1])
        self.panel:highlight_file(visible_files[1])
        self:_set_file(visible_files[1])
      end
    end

    api.nvim_echo({{ ("Review filter ON: showing %d/%d files pending review"):format(#visible_files, total_files) }}, false, {})
  else
    api.nvim_echo({{ "Review filter OFF: showing all files" }}, false, {})
  end
end

---Verify that a git commit exists (hasn't been garbage collected).
---@param commit_hash string The commit hash to verify
---@return boolean exists True if the commit exists
function DiffView:verify_commit_exists(commit_hash)
  if not commit_hash then
    return false
  end
  local _, code = self.adapter:exec_sync({
    "cat-file", "-e", commit_hash,
  }, self.adapter.ctx.toplevel)
  return code == 0
end

---Toggle since-review diff mode.
---When enabled, files with "changed" status show only changes since the
---commit where they were last marked as reviewed.
function DiffView:toggle_since_review_mode()
  if not self.review_state then
    utils.info("Review mode is not enabled")
    return
  end

  self.since_review_mode = not self.since_review_mode

  -- Provide feedback about the mode change
  if self.since_review_mode then
    api.nvim_echo({{ "Since-review mode ON: showing changes since last review for changed files" }}, false, {})
  else
    api.nvim_echo({{ "Since-review mode OFF: showing full diff" }}, false, {})
  end

  -- Re-open the current file to reflect the new mode if it has "changed" status
  if self.cur_entry then
    local status = review.get_file_status(self, self.cur_entry)
    if status == "changed" then
      self:_set_file(self.cur_entry)
    elseif self.since_review_mode then
      -- File is not "changed", so mode won't affect it
      utils.info("Since-review mode only affects files with 'changed' status")
    end
  end

  -- Update panel to show mode indicator
  self.panel:render()
  self.panel:redraw()
end

---Get the review entry for a file if it exists and has commit_hash.
---@param file_entry FileEntry
---@return ReviewEntry|nil review_entry The review entry if valid for since-review mode
---@return string|nil error_message Error message if since-review is not available
function DiffView:get_since_review_entry(file_entry)
  if not self.review_state then
    return nil, "Review mode is not enabled"
  end

  if not file_entry or not file_entry.path then
    return nil, "Invalid file entry"
  end

  local review_entry = self.review_state:get_file(file_entry.path)
  if not review_entry then
    return nil, "File has not been reviewed"
  end

  if not review_entry.commit_hash then
    return nil, "Review was saved without commit information"
  end

  -- Verify the commit still exists
  if not self:verify_commit_exists(review_entry.commit_hash) then
    return nil, "Reviewed commit no longer exists (may have been rebased)"
  end

  return review_entry, nil
end

M.DiffView = DiffView

return M
