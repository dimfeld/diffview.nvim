local lazy = require("diffview.lazy")

local DiffView = lazy.access("diffview.scene.views.diff.diff_view", "DiffView") ---@type DiffView|LazyModule
local FileHistoryView =
  lazy.access("diffview.scene.views.file_history.file_history_view", "FileHistoryView") ---@type FileHistoryView|LazyModule
local StandardView = lazy.access("diffview.scene.views.standard.standard_view", "StandardView") ---@type StandardView|LazyModule
local GroupedFileDict = lazy.access("diffview.grouped_file_dict", "GroupedFileDict") ---@type GroupedFileDict|LazyModule
local Diff1 = lazy.access("diffview.scene.layouts.diff_1", "Diff1") ---@type Diff1|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local GitAdapter = lazy.access("diffview.vcs.adapters.git", "GitAdapter") ---@type GitAdapter|LazyModule
local Rev = lazy.access("diffview.vcs.rev", "Rev") ---@type Rev|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local async = lazy.require("diffview.async") ---@module "diffview.async"
local arg_parser = lazy.require("diffview.arg_parser") ---@module "diffview.arg_parser"
local config = lazy.require("diffview.config") ---@module "diffview.config"
local vcs = lazy.require("diffview.vcs") ---@module "diffview.vcs"
local vcs_utils = lazy.require("diffview.vcs.utils") ---@module "diffview.vcs.utils"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local json_loader = lazy.require("diffview.json_loader") ---@module "diffview.json_loader"

local api = vim.api
local await = async.await
local logger = DiffviewGlobal.logger
local pl = lazy.access(utils, "path") ---@type PathLib

local M = {}

---@type View[]
M.views = {}

local function split_description_lines(description)
  return vim.split(description, "\n", { plain = true })
end

local function has_description_content(description)
  return description ~= nil and vim.trim(description) ~= ""
end

local function create_description_entry(adapter, group_index, description)
  local internal_path = (".diffview-json/descriptions/%d/Description"):format(group_index)
  local entry = FileEntry.with_layout(Diff1.__get(), {
    adapter = adapter,
    path = internal_path,
    oldpath = internal_path,
    revs = {
      a = Rev(RevType.CUSTOM, "description"),
      b = Rev(RevType.CUSTOM, "description"),
      c = Rev(RevType.CUSTOM, "description"),
      d = Rev(RevType.CUSTOM, "description"),
    },
    status = " ",
    stats = nil,
    kind = "working",
    binary = false,
    filetype = "markdown",
    get_data = function() return split_description_lines(description) end,
    nulled = false,
  })

  entry.path = "Description"
  entry.oldpath = "Description"
  entry.absolute_path = pl:absolute(entry.path, adapter.ctx.toplevel)
  entry.parent_path = ""
  entry.basename = "Description"
  entry.extension = nil
  entry.is_json_description = true

  return entry
end

function M.diffview_open(args)
  local default_args = config.get_config().default_args.DiffviewOpen
  local argo = arg_parser.parse(utils.flatten({ default_args, args }))
  local rev_arg = argo.args[1]

  logger:info("[command call] :DiffviewOpen " .. table.concat(
    utils.flatten({
      default_args,
      args,
    }),
    " "
  ))

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.post_args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  ---@cast adapter -?

  local opts = adapter:diffview_options(argo)

  if opts == nil then return end

  local v = DiffView({
    adapter = adapter,
    rev_arg = rev_arg,
    path_args = adapter.ctx.path_args,
    left = opts.left,
    right = opts.right,
    options = opts.options,
  })

  if not v:is_valid() then return end

  table.insert(M.views, v)
  logger:debug("DiffView instantiation successful!")

  return v
end

function M.diffview_show(args)
  local default_args = config.get_config().default_args.DiffviewOpen
  local argo = arg_parser.parse(utils.flatten({ default_args, args }))
  local rev_arg = argo.args[1]

  logger:info("[command call] :DiffviewShow " .. table.concat(
    utils.flatten({
      default_args,
      args,
    }),
    " "
  ))

  if not rev_arg then
    utils.err("Usage: DiffviewShow {rev} [options] [ -- {paths...}]")
    return
  elseif argo.args[2] then
    utils.err("DiffviewShow accepts exactly one revision.")
    return
  end

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.post_args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  ---@cast adapter -?

  if type(adapter.show_single_commit_rev_arg) ~= "function" then
    utils.err(("The active %s adapter does not support :DiffviewShow."):format(adapter:bin()))
    return
  end

  local show_rev_arg = adapter:show_single_commit_rev_arg(rev_arg)
  if not show_rev_arg then return end

  argo.args[1] = show_rev_arg

  local opts = adapter:diffview_options(argo)

  if opts == nil then return end

  local v = DiffView({
    adapter = adapter,
    rev_arg = rev_arg,
    path_args = adapter.ctx.path_args,
    left = opts.left,
    right = opts.right,
    options = opts.options,
  })

  if not v:is_valid() then return end

  table.insert(M.views, v)
  logger:debug("DiffView instantiation successful!")

  return v
end

local function file_exists_in_rev(adapter, path, rev)
  if rev.type == RevType.LOCAL then
    return pl:stat(pl:join(adapter.ctx.toplevel, path)) ~= nil
  elseif not adapter:instanceof(GitAdapter.__get()) then
    return true
  elseif rev.type == RevType.STAGE then
    local _, code = adapter:exec_sync({ "cat-file", "-e", ":" .. path }, {
      cwd = adapter.ctx.toplevel,
      silent = true,
    })
    return code == 0
  elseif rev.type == RevType.COMMIT then
    local _, code = adapter:exec_sync({ "cat-file", "-e", rev.commit .. ":" .. path }, {
      cwd = adapter.ctx.toplevel,
      silent = true,
    })
    return code == 0
  end

  return true
end

local function build_grouped_files(adapter, left, right, dv_opt, data)
  local paths = {}
  local path_set = {}

  for _, group in ipairs(data.groups) do
    for _, file_spec in ipairs(group.files) do
      if not path_set[file_spec.path] then
        path_set[file_spec.path] = true
        paths[#paths + 1] = file_spec.path
      end
    end
  end

  local err, file_dict
  if #paths > 0 then
    local layout_opt = {
      default_layout = DiffView.get_default_layout(),
      merge_layout = DiffView.get_default_merge_layout(),
    }
    async.sync_void(function()
      err, file_dict =
        await(vcs_utils.diff_file_list(adapter, left, right, paths, dv_opt, layout_opt))
    end)()

    if err then return nil, err end
  end

  file_dict = file_dict or { working = {}, staged = {}, conflicting = {} }

  local entry_by_path = {}
  local entry_priority = {}
  local function add_entry(entry, priority)
    if not entry then return end
    if entry_priority[entry.path] == nil or priority > entry_priority[entry.path] then
      entry_by_path[entry.path] = entry
      entry_priority[entry.path] = priority
    end
    if
      entry.oldpath
      and (entry_priority[entry.oldpath] == nil or priority > entry_priority[entry.oldpath])
    then
      entry_by_path[entry.oldpath] = entry
      entry_priority[entry.oldpath] = priority
    end
  end

  for _, entry in ipairs(file_dict.conflicting or {}) do
    add_entry(entry, 3)
  end
  for _, entry in ipairs(file_dict.working or {}) do
    add_entry(entry, 2)
  end
  for _, entry in ipairs(file_dict.staged or {}) do
    -- Note: For JSON views we prefer working/untracked entries over staged ones
    -- when both exist for the same path, so staged is lower priority here.
    add_entry(entry, 1)
  end

  local exists_cache = {}
  local function path_exists(path)
    if exists_cache[path] ~= nil then return exists_cache[path] end

    local exists = file_exists_in_rev(adapter, path, left)
      or file_exists_in_rev(adapter, path, right)
    exists_cache[path] = exists
    return exists
  end

  local missing = {}
  local missing_map = {}
  local grouped_files = GroupedFileDict(data.title)
  local has_any = false
  local merge_ctx = nil

  for group_index, group in ipairs(data.groups) do
    local group_entries = {}
    if has_description_content(group.description) then
      group_entries[#group_entries + 1] =
        create_description_entry(adapter, group_index, group.description)
      has_any = true
    end

    for _, file_spec in ipairs(group.files) do
      local entry = entry_by_path[file_spec.path]
      if entry then
        group_entries[#group_entries + 1] = entry
        has_any = true
        if entry.kind == "conflicting" then
          merge_ctx = merge_ctx or adapter:get_merge_context()
          if merge_ctx then entry:update_merge_context(merge_ctx) end
        end
      elseif not path_exists(file_spec.path) and not missing_map[file_spec.path] then
        missing_map[file_spec.path] = true
        missing[#missing + 1] = file_spec.path
      end
    end

    if #group_entries > 0 then grouped_files:add_group(group.name, group_entries) end
  end

  return grouped_files, nil, missing, has_any
end

function M.json_view_open(json_path, args)
  json_path = vim.fn.expand(json_path)
  local default_args = config.get_config().default_args.DiffviewOpen
  local argo = arg_parser.parse(utils.flatten({ default_args, args }))
  local rev_arg = argo.args[1]

  logger:info("[command call] :DiffviewOpenJson " .. table.concat(
    utils.flatten({
      json_path,
      default_args,
      args,
    }),
    " "
  ))

  local data, json_err = json_loader.load_json(json_path)
  if json_err then
    utils.err("Failed to load JSON: " .. json_err)
    return
  end

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.post_args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  ---@cast adapter -?

  local opts = adapter:diffview_options(argo)
  if opts == nil then return end

  local grouped_files, build_err, missing, has_any =
    build_grouped_files(adapter, opts.left, opts.right, opts.options, data)

  if build_err then
    utils.err(build_err)
    return
  end

  if not has_any or grouped_files:len() == 0 then
    utils.err("No files with changes found at specified revisions.")
    return
  end

  if missing and #missing > 0 then
    utils.warn(("Some files not found: %s"):format(table.concat(missing, ", ")))
  end

  local v = DiffView({
    adapter = adapter,
    rev_arg = rev_arg,
    path_args = adapter.ctx.path_args,
    left = opts.left,
    right = opts.right,
    options = opts.options,
    files = grouped_files,
  })

  if not v:is_valid() then return end

  table.insert(M.views, v)
  logger:debug("DiffView instantiation successful!")

  return v
end

---@param range? { [1]: integer, [2]: integer }
---@param args string[]
function M.file_history(range, args)
  local default_args = config.get_config().default_args.DiffviewFileHistory
  local argo = arg_parser.parse(utils.flatten({ default_args, args }))

  logger:info("[command call] :DiffviewFileHistory " .. table.concat(
    utils.flatten({
      default_args,
      args,
    }),
    " "
  ))

  local err, adapter = vcs.get_adapter({
    cmd_ctx = {
      path_args = argo.args,
      cpath = argo:get_flag("C", { no_empty = true, expand = true }),
    },
  })

  if err then
    utils.err(err)
    return
  end

  ---@cast adapter -?

  local log_options = adapter:file_history_options(range, adapter.ctx.path_args, argo)

  if log_options == nil then return end

  local v = FileHistoryView({
    adapter = adapter,
    log_options = log_options,
  })

  if not v:is_valid() then return end

  table.insert(M.views, v)
  logger:debug("FileHistoryView instantiation successful!")

  return v
end

---@param view View
function M.add_view(view) table.insert(M.views, view) end

---@param view View
function M.dispose_view(view)
  for j, v in ipairs(M.views) do
    if v == view then
      table.remove(M.views, j)
      return
    end
  end
end

---Close and dispose of views that have no tabpage.
function M.dispose_stray_views()
  local tabpage_map = {}
  for _, id in ipairs(api.nvim_list_tabpages()) do
    tabpage_map[id] = true
  end

  local dispose = {}
  for _, view in ipairs(M.views) do
    if not tabpage_map[view.tabpage] then
      -- Need to schedule here because the tabnr's don't update fast enough.
      vim.schedule(function() view:close() end)
      table.insert(dispose, view)
    end
  end

  for _, view in ipairs(dispose) do
    M.dispose_view(view)
  end
end

---Get the currently open Diffview.
---@return View?
function M.get_current_view()
  local tabpage = api.nvim_get_current_tabpage()
  for _, view in ipairs(M.views) do
    if view.tabpage == tabpage then return view end
  end

  return nil
end

function M.tabpage_to_view(tabpage)
  for _, view in ipairs(M.views) do
    if view.tabpage == tabpage then return view end
  end
end

---Get the first tabpage that is not a view. Tries the previous tabpage first.
---If there are no non-view tabpages: returns nil.
---@return number|nil
function M.get_prev_non_view_tabpage()
  local tabs = api.nvim_list_tabpages()
  if #tabs > 1 then
    local seen = {}
    for _, view in ipairs(M.views) do
      seen[view.tabpage] = true
    end

    local prev_tab = utils.tabnr_to_id(vim.fn.tabpagenr("#")) or -1
    if api.nvim_tabpage_is_valid(prev_tab) and not seen[prev_tab] then
      return prev_tab
    else
      for _, id in ipairs(tabs) do
        if not seen[id] then return id end
      end
    end
  end
end

---@param bufnr integer
---@param ignore? vcs.File[]
---@return boolean
function M.is_buf_in_use(bufnr, ignore)
  local ignore_map = ignore and utils.vec_slice(ignore) or {}
  utils.add_reverse_lookup(ignore_map)

  for _, view in ipairs(M.views) do
    if view:instanceof(StandardView.__get()) then
      ---@cast view StandardView

      for _, file in ipairs(view.cur_entry and view.cur_entry.layout:files() or {}) do
        if file:is_valid() and file.bufnr == bufnr then
          if not ignore_map[file] then return true end
        end
      end
    end
  end

  return false
end

function M.update_colors()
  for _, view in ipairs(M.views) do
    if view:instanceof(StandardView.__get()) then
      ---@cast view StandardView
      if view.panel:buf_loaded() then
        view.panel:render()
        view.panel:redraw()
      end
    end
  end
end

return M
