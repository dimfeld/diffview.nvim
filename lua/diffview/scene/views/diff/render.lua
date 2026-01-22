local lazy = require("diffview.lazy")

local config = lazy.require("diffview.config") ---@module "diffview.config"
local hl = lazy.require("diffview.hl") ---@module "diffview.hl"
local review = lazy.require("diffview.review") ---@module "diffview.review"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local pl = lazy.access(utils, "path") ---@type PathLib

---Count pending review files (unreviewed or changed) vs total files.
---@param panel FilePanel
---@param view DiffView|nil
---@return integer pending_count, integer total_count
local function count_pending_files(panel, view)
  if not view or not view.review_state then
    return 0, 0
  end

  local pending = 0
  local total = 0

  for _, file in panel.files:iter() do
    total = total + 1
    local status = review.get_file_status(view, file)
    if status == "unreviewed" or status == "changed" then
      pending = pending + 1
    end
  end

  return pending, total
end

---Count visible files in a section when filter is active.
---@param files table[] The file list for the section
---@param view DiffView|nil
---@return integer visible_count
local function count_visible_section_files(files, view)
  if not view or not view.review_filter_enabled then
    return #files
  end

  local count = 0
  for _, file in ipairs(files) do
    local status = review.get_file_status(view, file)
    if status == "unreviewed" or status == "changed" then
      count = count + 1
    end
  end
  return count
end

---@param comp  RenderComponent
---@param show_path boolean
---@param depth integer|nil
---@param view DiffView|nil
local function render_file(comp, show_path, depth, view)
  ---@type FileEntry
  local file = comp.context
  local conf = config.get_config()

  comp:add_text(file.status .. " ", hl.get_git_hl(file.status))

  -- Review status indicator
  if view and view.review_state and conf.review and conf.review.enabled then
    local review_status = review.get_file_status(view, file)
    if review_status then
      local symbol = conf.review.symbols[review_status] or "?"
      comp:add_text(symbol .. " ", hl.get_review_hl(review_status))
    end
  end

  if depth then
    comp:add_text(string.rep(" ", depth * 2 + 2))
  end

  local icon, icon_hl = hl.get_file_icon(file.basename, file.extension)
  comp:add_text(icon, icon_hl)
  comp:add_text(file.basename, file.active and "DiffviewFilePanelSelected" or "DiffviewFilePanelFileName")

  if file.stats then
    if file.stats.additions then
      comp:add_text(" " .. file.stats.additions, "DiffviewFilePanelInsertions")
      comp:add_text(", ")
      comp:add_text(tostring(file.stats.deletions), "DiffviewFilePanelDeletions")
    elseif file.stats.conflicts then
      local has_conflicts = file.stats.conflicts > 0
      comp:add_text(
        " " .. (has_conflicts and file.stats.conflicts or config.get_config().signs.done),
        has_conflicts and "DiffviewFilePanelConflicts" or "DiffviewFilePanelInsertions"
      )
    end
  end

  if file.kind == "conflicting" and not (file.stats and file.stats.conflicts) then
    comp:add_text(" !", "DiffviewFilePanelConflicts")
  end

  if show_path then
    comp:add_text(" " .. file.parent_path, "DiffviewFilePanelPath")
  end

  comp:ln()
end

---@param comp RenderComponent
---@param view DiffView|nil
local function render_file_list(comp, view)
  for _, file_comp in ipairs(comp.components) do
    render_file(file_comp, true, nil, view)
  end
end

---@param ctx DirData
---@param tree_options TreeOptions
---@return string
local function get_dir_status_text(ctx, tree_options)
  local folder_statuses = tree_options.folder_statuses

  if folder_statuses == "always" or (folder_statuses == "only_folded" and ctx.collapsed) then
    return ctx.status
  end

  return " "
end

---@param depth integer
---@param comp RenderComponent
---@param view DiffView|nil
local function render_file_tree_recurse(depth, comp, view)
  local conf = config.get_config()

  if comp.name == "file" then
    render_file(comp, false, depth, view)
    return
  end

  if comp.name ~= "directory" then return end

  -- Directory component structure:
  -- {
  --   name = "directory",
  --   context = <DirData>,
  --   { name = "dir_name" },
  --   { name = "items", ...<files> },
  -- }

  local dir = comp.components[1]
  local items = comp.components[2]
  local ctx = comp.context --[[@as DirData ]]

  dir:add_text(
    get_dir_status_text(ctx, conf.file_panel.tree_options) .. " ",
    hl.get_git_hl(ctx.status)
  )
  dir:add_text(string.rep(" ", depth * 2))
  dir:add_text(ctx.collapsed and conf.signs.fold_closed or conf.signs.fold_open, "DiffviewNonText")

  if conf.use_icons then
    dir:add_text(
      " " .. (ctx.collapsed and conf.icons.folder_closed or conf.icons.folder_open) .. " ",
      "DiffviewFolderSign"
    )
  end

  dir:add_text(ctx.name, "DiffviewFolderName")
  dir:ln()

  if not ctx.collapsed then
    for _, item in ipairs(items.components) do
      render_file_tree_recurse(depth + 1, item, view)
    end
  end
end

---@param comp RenderComponent
---@param view DiffView|nil
local function render_file_tree(comp, view)
  for _, c in ipairs(comp.components) do
    render_file_tree_recurse(0, c, view)
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

---@param panel FilePanel
return function(panel)
  if not panel.render_data then
    return
  end

  panel.render_data:clear()
  local conf = config.get_config()
  local width = panel:infer_width()
  local view = panel.view

  local comp = panel.components.path.comp

  comp:add_line(
    pl:truncate(pl:vim_fnamemodify(panel.adapter.ctx.toplevel, ":~"), width - 6),
    "DiffviewFilePanelRootPath"
  )

  if conf.show_help_hints and panel.help_mapping then
    comp:add_text("Help: ", "DiffviewFilePanelPath")
    comp:add_line(panel.help_mapping, "DiffviewFilePanelCounter")
  end

  -- Show filter indicator when review filter is active
  if view and view.review_filter_enabled then
    local pending, total = count_pending_files(panel, view)
    comp:add_text("[Pending: ", "DiffviewFilePanelPath")
    comp:add_text(string.format("%d/%d", pending, total), "DiffviewFilePanelCounter")
    comp:add_text("]", "DiffviewFilePanelPath")
    comp:ln()
  end

  if conf.show_help_hints and panel.help_mapping then
    comp:ln()
  end

  if panel.files.is_grouped and panel.files:is_grouped() then
    if panel.files.title then
      comp:add_line(panel.files.title, "DiffviewFilePanelTitle")
      comp:ln()
    end

    for i, group in ipairs(panel.files.groups) do
      local group_comp = panel.components["group_" .. i]
      comp = group_comp.title.comp
      comp:add_text(group.name .. " ", "DiffviewFilePanelTitle")
      if view and view.review_filter_enabled then
        local visible = count_visible_section_files(group.files, view)
        comp:add_text(string.format("(%d/%d)", visible, #group.files), "DiffviewFilePanelCounter")
      else
        comp:add_text("(" .. #group.files .. ")", "DiffviewFilePanelCounter")
      end
      comp:ln()

      render_files(panel.listing_style, group_comp.files.comp, view)
      group_comp.margin.comp:add_line()
    end
  else
    if #panel.files.conflicting > 0 then
      comp = panel.components.conflicting.title.comp
      comp:add_text("Conflicts ", "DiffviewFilePanelTitle")
      if view and view.review_filter_enabled then
        local visible = count_visible_section_files(panel.files.conflicting, view)
        comp:add_text(string.format("(%d/%d)", visible, #panel.files.conflicting), "DiffviewFilePanelCounter")
      else
        comp:add_text("(" .. #panel.files.conflicting .. ")", "DiffviewFilePanelCounter")
      end
      comp:ln()

      render_files(panel.listing_style, panel.components.conflicting.files.comp, view)
      panel.components.conflicting.margin.comp:add_line()
    end

    local has_other_files = #panel.files.conflicting > 0 or #panel.files.staged > 0

    -- Don't show the 'Changes' section if it's empty and we have other visible
    -- sections.
    if #panel.files.working > 0 or not has_other_files then
      comp = panel.components.working.title.comp
      comp:add_text("Changes ", "DiffviewFilePanelTitle")
      if view and view.review_filter_enabled then
        local visible = count_visible_section_files(panel.files.working, view)
        comp:add_text(string.format("(%d/%d)", visible, #panel.files.working), "DiffviewFilePanelCounter")
      else
        comp:add_text("(" .. #panel.files.working .. ")", "DiffviewFilePanelCounter")
      end
      comp:ln()

      render_files(panel.listing_style, panel.components.working.files.comp, view)
      panel.components.working.margin.comp:add_line()
    end

    if #panel.files.staged > 0 then
      comp = panel.components.staged.title.comp
      comp:add_text("Staged changes ", "DiffviewFilePanelTitle")
      if view and view.review_filter_enabled then
        local visible = count_visible_section_files(panel.files.staged, view)
        comp:add_text(string.format("(%d/%d)", visible, #panel.files.staged), "DiffviewFilePanelCounter")
      else
        comp:add_text("(" .. #panel.files.staged .. ")", "DiffviewFilePanelCounter")
      end
      comp:ln()

      render_files(panel.listing_style, panel.components.staged.files.comp, view)
      panel.components.staged.margin.comp:add_line()
    end
  end

  if panel.rev_pretty_name or (panel.path_args and #panel.path_args > 0) then
    local extra_info = utils.vec_join({ panel.rev_pretty_name }, panel.path_args or {})

    comp = panel.components.info.title.comp
    comp:add_line("Showing changes for:", "DiffviewFilePanelTitle")

    comp = panel.components.info.entries.comp

    for _, arg in ipairs(extra_info) do
      local relpath = pl:relative(arg, panel.adapter.ctx.toplevel)
      if relpath == "" then relpath = "." end
      comp:add_line(pl:truncate(relpath, width - 5), "DiffviewFilePanelPath")
    end
  end
end
