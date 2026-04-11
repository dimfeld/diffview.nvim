if vim.g.diffview_nvim_loaded or not require("diffview.bootstrap") then return end

vim.g.diffview_nvim_loaded = 1

local lazy = require("diffview.lazy")

---@module "diffview"
local arg_parser = lazy.require("diffview.arg_parser") ---@module "diffview.arg_parser"
local diffview = lazy.require("diffview") ---@module "diffview"

local api = vim.api
local command = api.nvim_create_user_command

-- NOTE: Need this wrapper around the completion function becuase it doesn't
-- exist yet.
local function completion(...) return diffview.completion(...) end

-- Create commands
command(
  "DiffviewOpen",
  function(ctx) diffview.open(arg_parser.scan(ctx.args).args) end,
  { nargs = "*", complete = completion }
)

command(
  "DiffviewShow",
  function(ctx) diffview.show(arg_parser.scan(ctx.args).args) end,
  { nargs = "*", complete = completion }
)

command("DiffviewOpenJson", function(ctx)
  local args = arg_parser.scan(ctx.args).args
  if #args < 1 then
    local utils = lazy.require("diffview.utils")
    utils.err("Usage: DiffviewOpenJson {json_path} [rev_args...]")
    return
  end

  local json_path = args[1]
  local rev_args = vim.list_slice(args, 2)
  diffview.open_json(json_path, rev_args)
end, { nargs = "+", complete = completion })

command("DiffviewFileHistory", function(ctx)
  local range

  if ctx.range > 0 then range = { ctx.line1, ctx.line2 } end

  diffview.file_history(range, arg_parser.scan(ctx.args).args)
end, { nargs = "*", complete = completion, range = true })

command("DiffviewClose", function() diffview.close() end, { nargs = 0, bang = true })

command(
  "DiffviewFocusFiles",
  function() diffview.emit("focus_files") end,
  { nargs = 0, bang = true }
)

command(
  "DiffviewToggleFiles",
  function() diffview.emit("toggle_files") end,
  { nargs = 0, bang = true }
)

command(
  "DiffviewRefresh",
  function() diffview.emit("refresh_files") end,
  { nargs = 0, bang = true }
)

command(
  "DiffviewLog",
  function() vim.cmd(("sp %s | norm! G"):format(vim.fn.fnameescape(DiffviewGlobal.logger.outfile))) end,
  { nargs = 0, bang = true }
)

command("DiffviewReviewCleanup", function(ctx)
  local lib = lazy.require("diffview.lib")
  local review = lazy.require("diffview.review")
  local utils = lazy.require("diffview.utils")

  local view = lib.get_current_view()
  local has_active_view = view ~= nil

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

  local dry_run = ctx.bang -- Use ! for dry-run mode

  if dry_run then
    local preview = review.get_cleanup_preview(view)
    if preview.error then
      utils.warn("Preview failed: " .. preview.error)
      return
    end
    if #preview.deleted_branches == 0 then
      utils.info("No stale review data found")
    else
      utils.info(
        ("Would clean up %d branch(es): %s"):format(
          preview.deleted_count,
          table.concat(preview.deleted_branches, ", ")
        )
      )
    end
  elseif has_active_view then
    -- Use the action listener which has confirmation UI
    diffview.emit("review_cleanup")
  else
    -- No active view - implement confirmation dialog directly here
    local preview = review.get_cleanup_preview(view)

    if preview.error then
      utils.warn("Cleanup preview failed: " .. preview.error)
      return
    end

    if #preview.deleted_branches == 0 then
      utils.info("No stale review data found for this repository")
      return
    end

    -- Build confirmation message
    local branch_list = table.concat(preview.deleted_branches, ", ")
    if #branch_list > 60 then branch_list = branch_list:sub(1, 57) .. "..." end

    vim.ui.select({ "Yes", "No" }, {
      prompt = ("Clean up review state for %d stale branch(es)? [%s]"):format(
        preview.deleted_count,
        branch_list
      ),
    }, function(choice)
      if choice == "Yes" then
        local result = review.cleanup_stale_reviews(view)
        if result.error then
          utils.warn("Cleanup failed: " .. result.error)
        else
          utils.info(("Cleaned up review state for %d branch(es)"):format(result.deleted_count))
        end
      end
    end)
  end
end, { nargs = 0, bang = true })
