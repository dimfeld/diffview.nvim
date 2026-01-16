if vim.g.diffview_nvim_loaded or not require("diffview.bootstrap") then
  return
end

vim.g.diffview_nvim_loaded = 1

local lazy = require("diffview.lazy")

---@module "diffview"
local arg_parser = lazy.require("diffview.arg_parser") ---@module "diffview.arg_parser"
local diffview = lazy.require("diffview") ---@module "diffview"

local api = vim.api
local command = api.nvim_create_user_command

-- NOTE: Need this wrapper around the completion function becuase it doesn't
-- exist yet.
local function completion(...)
  return diffview.completion(...)
end

-- Create commands
command("DiffviewOpen", function(ctx)
  diffview.open(arg_parser.scan(ctx.args).args)
end, { nargs = "*", complete = completion })

command("DiffviewFileHistory", function(ctx)
  local range

  if ctx.range > 0 then
    range = { ctx.line1, ctx.line2 }
  end

  diffview.file_history(range, arg_parser.scan(ctx.args).args)
end, { nargs = "*", complete = completion, range = true })

command("DiffviewClose", function()
  diffview.close()
end, { nargs = 0, bang = true })

command("DiffviewFocusFiles", function()
  diffview.emit("focus_files")
end, { nargs = 0, bang = true })

command("DiffviewToggleFiles", function()
  diffview.emit("toggle_files")
end, { nargs = 0, bang = true })

command("DiffviewRefresh", function()
  diffview.emit("refresh_files")
end, { nargs = 0, bang = true })

command("DiffviewLog", function()
  vim.cmd(("sp %s | norm! G"):format(
    vim.fn.fnameescape(DiffviewGlobal.logger.outfile)
  ))
end, { nargs = 0, bang = true })

command("DiffviewReviewCleanup", function(ctx)
  local lib = lazy.require("diffview.lib")
  local review = lazy.require("diffview.review")
  local utils = lazy.require("diffview.utils")

  local view = lib.get_current_view()
  if not view then
    -- Try to create a temporary adapter for current directory
    local adapter = diffview.get_adapter()
    if not adapter then
      utils.warn("Not in a git repository")
      return
    end
    -- Create minimal view-like object with adapter
    view = { adapter = adapter }
  end

  local dry_run = ctx.bang  -- Use ! for dry-run mode

  if dry_run then
    local preview = review.get_cleanup_preview(view)
    if preview.error then
      utils.warn("Preview failed: " .. preview.error)
      return
    end
    if #preview.deleted_branches == 0 then
      utils.info("No stale review data found")
    else
      utils.info(("Would clean up %d branch(es): %s"):format(
        preview.deleted_count,
        table.concat(preview.deleted_branches, ", ")
      ))
    end
  else
    -- Trigger the action which shows confirmation UI
    diffview.emit("review_cleanup")
  end
end, { nargs = 0, bang = true })
