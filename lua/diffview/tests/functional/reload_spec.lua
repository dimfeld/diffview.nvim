vim.cmd("runtime plugin/diffview.lua")

local diffview = require("diffview")
local lib = require("diffview.lib")
local config = require("diffview.config")
local utils = require("diffview.utils")
local stub = require("luassert.stub")
local async_test = require("diffview.tests.helpers").async_test
local async = require("diffview.async")

describe("DiffviewReload", function()
  local repo
  local original_defaults
  local error_stub

  local function git(args)
    local output = vim.fn.system(vim.list_extend({ "git", "-C", repo }, args))
    assert.equals(0, vim.v.shell_error, output)
    return vim.trim(output)
  end

  before_each(function()
    repo = vim.fn.tempname()
    vim.fn.mkdir(repo, "p")
    git({ "init" })
    git({ "config", "user.email", "test@example.com" })
    git({ "config", "user.name", "Test" })
    vim.fn.writefile({ "first" }, repo .. "/file.txt")
    git({ "add", "." })
    git({ "commit", "-m", "First" })
    original_defaults = config.get_config().default_args.DiffviewOpen
    config.get_config().default_args.DiffviewOpen = { "--untracked-files=no" }
  end)

  after_each(function()
    if error_stub then
      error_stub:revert()
      error_stub = nil
    end
    while #lib.views > 0 do
      local view = lib.views[1]
      view:close()
      lib.dispose_view(view)
    end
    config.get_config().default_args.DiffviewOpen = original_defaults
  end)

  it("resolves HEAD again and retains arguments and defaults", function()
    local args = { "HEAD", "-C=" .. repo, "--", "file.txt" }
    diffview.open(args)
    local old = lib.get_current_view()
    local first = old.left.commit
    local paths = vim.deepcopy(old.path_args)
    args[1] = "invalid"
    config.get_config().default_args.DiffviewOpen = { "invalid" }
    vim.fn.writefile({ "second" }, repo .. "/file.txt")
    git({ "commit", "-am", "Second" })
    vim.cmd("DiffviewReload")
    local current = lib.get_current_view()
    assert.is_not.equals(old, current)
    assert.is_not.equals(first, current.left.commit)
    assert.equals(git({ "rev-parse", "HEAD" }), current.left.commit)
    assert.same(paths, current.path_args)
    assert.is_false(current.options.show_untracked)
    assert.equals(1, #lib.views)
    vim.cmd("DiffviewReload")
    assert.equals(1, #lib.views)
  end)

  it("reopens DiffviewShow with its original revision expression", function()
    vim.fn.writefile({ "second" }, repo .. "/file.txt")
    git({ "commit", "-am", "Second" })
    diffview.show({ "HEAD", "-C=" .. repo })
    vim.fn.writefile({ "third" }, repo .. "/file.txt")
    git({ "commit", "-am", "Third" })
    vim.cmd("DiffviewReload")
    local current = lib.get_current_view()
    assert.equals(git({ "rev-parse", "HEAD" }), current.right.commit)
    assert.equals(git({ "rev-parse", "HEAD^" }), current.left.commit)
  end)

  it(
    "reloads JSON groups and resolves revisions again",
    async_test(function()
      local json_path = repo .. "/review.json"
      local function write_groups(name)
        vim.fn.writefile({
          vim.fn.json_encode({
            groups = { { name = name, files = { { path = "file.txt" } } } },
          }),
        }, json_path)
      end
      vim.fn.writefile({ "second" }, repo .. "/file.txt")
      git({ "commit", "-am", "Second" })
      write_groups("Original")
      diffview.open_json(json_path, { "HEAD~1", "-C=" .. repo })
      async.await(async.scheduler())
      assert.is_not_nil(lib.get_current_view())
      vim.fn.writefile({ "third" }, repo .. "/file.txt")
      git({ "commit", "-am", "Third" })
      write_groups("Updated")
      diffview.reload()
      async.await(async.scheduler())
      local current = lib.get_current_view()
      assert.equals(git({ "rev-parse", "HEAD~1" }), current.left.commit)
      assert.equals("Updated", current.files.groups[1].name)
    end)
  )

  it("keeps the current view when its revision no longer exists", function()
    git({ "branch", "review" })
    diffview.open({ "review", "-C=" .. repo })
    local old = lib.get_current_view()
    git({ "branch", "-D", "review" })
    error_stub = stub(utils, "err")
    vim.cmd("DiffviewReload")
    assert.equals(old, lib.get_current_view())
    assert.equals(1, #lib.views)
  end)

  it("does nothing outside a diff view", function()
    vim.cmd("DiffviewReload")
    assert.equals(0, #lib.views)
  end)
end)
