local helpers = require("diffview.tests.helpers")
local eq = helpers.eq
local async_test = helpers.async_test
local await = require("diffview.async").await

local config = require("diffview.config")
local renderer = require("diffview.renderer")
local stub = require("luassert.stub")
local uv = vim.loop
local arg_parser = require("diffview.arg_parser")

local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
local GroupedFileDict = require("diffview.grouped_file_dict").GroupedFileDict
local RevType = require("diffview.vcs.rev").RevType
local diffview = require("diffview")
local lib = require("diffview.lib")
local json_loader = require("diffview.json_loader")
local utils = require("diffview.utils")
local vcs = require("diffview.vcs")

local function rm_rf(path)
  local stat = uv.fs_stat(path)
  if not stat then return end

  if stat.type == "directory" then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then break end
        rm_rf(path .. "/" .. name)
      end
    end
    uv.fs_rmdir(path)
  else
    uv.fs_unlink(path)
  end
end

local function write_file(path, content)
  local fd = assert(uv.fs_open(path, "w", 438))
  assert(uv.fs_write(fd, content, 0))
  assert(uv.fs_close(fd))
end

local function run_git(cwd, args)
  local cmd = vim.tbl_flatten({ "git", "-C", cwd, args })
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    error(string.format("git command failed (%s): %s", table.concat(cmd, " "), output))
  end
  return output
end

local function make_waitable(...)
  local values = { ... }
  return {
    await = function() return unpack(values) end,
  }
end

local function make_file(path, kind, status)
  local basename = path:match("[^/]+$") or path
  local extension = basename:match("%.([^%.]+)$")
  local parent_path = path:match("(.+)/[^/]+$") or ""
  return {
    path = path,
    basename = basename,
    extension = extension,
    parent_path = parent_path,
    kind = kind or "working",
    status = status or "M",
  }
end

describe("diffview.json_view_open", function()
  local test_dir
  local stubs

  local function track_stub(target, name, fn)
    local s = stub(target, name, fn)
    stubs[#stubs + 1] = s
    return s
  end

  before_each(function()
    stubs = {}
    test_dir = vim.fn.tempname() .. "_diffview_json_view"
    rm_rf(test_dir)
    assert(uv.fs_mkdir(test_dir, tonumber("0755", 8)))
  end)

  after_each(function()
    for _, s in ipairs(stubs) do
      s:revert()
    end
    stubs = {}
    lib.views = {}
    rm_rf(test_dir)
  end)

  it("builds grouped files and warns on missing files", function()
    local data = {
      title = "Review",
      groups = {
        {
          name = "Group A",
          files = {
            { path = "keep.lua" },
            { path = "missing.lua" },
          },
        },
        {
          name = "Group B",
          files = {
            { path = "unchanged.lua" },
          },
        },
      },
    }

    write_file(test_dir .. "/keep.lua", "print('ok')")
    write_file(test_dir .. "/unchanged.lua", "noop")

    track_stub(json_loader, "load_json", function() return data, nil end)

    local file_entry = make_file("keep.lua", "working", "M")

    local adapter = {
      ctx = {
        toplevel = test_dir,
        dir = test_dir,
        path_args = {},
      },
      diffview_options = function()
        return {
          left = { type = RevType.LOCAL },
          right = { type = RevType.LOCAL },
          options = {},
        }
      end,
      rev_to_pretty_string = function() return "" end,
      rev_to_args = function() return {} end,
      tracked_files = function() return make_waitable(nil, { file_entry }, {}) end,
      show_untracked = function() return false end,
      get_merge_context = function() return nil end,
      instanceof = function() return true end,
    }

    track_stub(vcs, "get_adapter", function() return nil, adapter end)

    local warn_stub = track_stub(utils, "warn", function() end)
    local err_stub = track_stub(utils, "err", function() end)

    local view = lib.json_view_open(test_dir .. "/review.json", {})

    assert(view ~= nil, "Expected view to be created")
    eq(true, view.files:is_grouped())
    eq("Review", view.files.title)
    eq(1, #view.files.groups)
    eq("Group A", view.files.groups[1].name)
    eq("keep.lua", view.files.groups[1].files[1].path)

    assert.stub(err_stub).was_not.called()
    assert.stub(warn_stub).was.called_with("Some files not found: missing.lua")
  end)

  it("reuses entries for duplicate paths across groups", function()
    local data = {
      title = "Review",
      groups = {
        {
          name = "Group A",
          files = {
            { path = "shared.lua" },
          },
        },
        {
          name = "Group B",
          files = {
            { path = "shared.lua" },
          },
        },
      },
    }

    write_file(test_dir .. "/shared.lua", "print('ok')")

    track_stub(json_loader, "load_json", function() return data, nil end)

    local file_entry = make_file("shared.lua", "working", "M")

    local adapter = {
      ctx = {
        toplevel = test_dir,
        dir = test_dir,
        path_args = {},
      },
      diffview_options = function()
        return {
          left = { type = RevType.LOCAL },
          right = { type = RevType.LOCAL },
          options = {},
        }
      end,
      rev_to_pretty_string = function() return "" end,
      rev_to_args = function() return {} end,
      tracked_files = function() return make_waitable(nil, { file_entry }, {}) end,
      show_untracked = function() return false end,
      get_merge_context = function() return nil end,
      instanceof = function() return true end,
    }

    track_stub(vcs, "get_adapter", function() return nil, adapter end)

    local warn_stub = track_stub(utils, "warn", function() end)
    local err_stub = track_stub(utils, "err", function() end)

    local view = lib.json_view_open(test_dir .. "/review.json", {})

    assert(view ~= nil, "Expected view to be created")
    eq(2, #view.files.groups)
    assert.are.equal(file_entry, view.files.groups[1].files[1])
    assert.are.equal(file_entry, view.files.groups[2].files[1])

    assert.stub(err_stub).was_not.called()
    assert.stub(warn_stub).was_not.called()
  end)

  it(
    "adds section descriptions before changed files",
    async_test(function()
      local data = {
        title = "Review",
        groups = {
          {
            name = "Group A",
            description = "Start here.\nThen review the file.",
            files = {
              { path = "keep.lua" },
            },
          },
        },
      }

      write_file(test_dir .. "/keep.lua", "print('ok')")

      track_stub(json_loader, "load_json", function() return data, nil end)

      local file_entry = make_file("keep.lua", "working", "M")

      local adapter = {
        ctx = {
          toplevel = test_dir,
          dir = test_dir,
          path_args = {},
        },
        diffview_options = function()
          return {
            left = { type = RevType.LOCAL },
            right = { type = RevType.LOCAL },
            options = {},
          }
        end,
        rev_to_pretty_string = function() return "" end,
        rev_to_args = function() return {} end,
        tracked_files = function() return make_waitable(nil, { file_entry }, {}) end,
        show_untracked = function() return false end,
        get_merge_context = function() return nil end,
        instanceof = function() return true end,
      }

      track_stub(vcs, "get_adapter", function() return nil, adapter end)

      local warn_stub = track_stub(utils, "warn", function() end)
      local view = lib.json_view_open(test_dir .. "/review.json", {})

      assert(view ~= nil, "Expected view to be created")
      eq(1, #view.files.groups)
      eq(2, #view.files.groups[1].files)

      local description = view.files.groups[1].files[1]
      eq(true, description.is_json_description)
      eq("Description", description.path)
      eq("Description", description.basename)
      eq("", description.parent_path)
      eq({ "Start here.", "Then review the file." }, description.layout.b.file.get_data())
      local bufnr = await(description.layout.b.file:create_buffer())
      eq(
        { "Start here.", "Then review the file." },
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      )
      eq("markdown", vim.bo[bufnr].filetype)
      eq(file_entry, view.files.groups[1].files[2])

      assert.stub(warn_stub).was_not.called()
    end)
  )

  it("opens description-only sections", function()
    local data = {
      title = "Review",
      groups = {
        {
          name = "Context",
          description = "No changed files are required.",
          files = {},
        },
      },
    }

    track_stub(json_loader, "load_json", function() return data, nil end)

    local adapter = {
      ctx = {
        toplevel = test_dir,
        dir = test_dir,
        path_args = {},
      },
      diffview_options = function()
        return {
          left = { type = RevType.LOCAL },
          right = { type = RevType.LOCAL },
          options = {},
        }
      end,
      rev_to_pretty_string = function() return "" end,
      rev_to_args = function() return {} end,
      get_merge_context = function() return nil end,
      instanceof = function() return true end,
    }

    track_stub(vcs, "get_adapter", function() return nil, adapter end)

    local err_stub = track_stub(utils, "err", function() end)
    local view = lib.json_view_open(test_dir .. "/review.json", {})

    assert(view ~= nil, "Expected view to be created")
    eq(1, #view.files.groups)
    eq("Context", view.files.groups[1].name)
    eq("Description", view.files.groups[1].files[1].path)
    eq({ "No changed files are required." }, view.files.groups[1].files[1].layout.b.file.get_data())
    assert.stub(err_stub).was_not.called()
  end)

  it("errors when no changed files remain", function()
    local data = {
      title = "Empty",
      groups = {
        {
          name = "Group A",
          files = {
            { path = "only.lua" },
          },
        },
      },
    }

    write_file(test_dir .. "/only.lua", "print('still no diff')")

    track_stub(json_loader, "load_json", function() return data, nil end)

    local adapter = {
      ctx = {
        toplevel = test_dir,
        dir = test_dir,
        path_args = {},
      },
      diffview_options = function()
        return {
          left = { type = RevType.LOCAL },
          right = { type = RevType.LOCAL },
          options = {},
        }
      end,
      rev_to_pretty_string = function() return "" end,
      rev_to_args = function() return {} end,
      tracked_files = function() return make_waitable(nil, {}, {}) end,
      show_untracked = function() return false end,
      get_merge_context = function() return nil end,
      instanceof = function() return true end,
    }

    track_stub(vcs, "get_adapter", function() return nil, adapter end)

    local err_stub = track_stub(utils, "err", function() end)

    local view = lib.json_view_open(test_dir .. "/review.json", {})

    eq(nil, view)
    assert.stub(err_stub).was.called_with("No files with changes found at specified revisions.")
    eq(0, #lib.views)
  end)

  it("includes staged-only and untracked files for stage..local", function()
    local data = {
      title = "Stage Review",
      groups = {
        {
          name = "Group A",
          files = {
            { path = "staged.lua" },
            { path = "unstaged.lua" },
            { path = "untracked.lua" },
          },
        },
      },
    }

    track_stub(json_loader, "load_json", function() return data, nil end)

    local staged_entry = make_file("staged.lua", "staged", "A")
    local working_entry = make_file("unstaged.lua", "working", "M")
    local untracked_entry = make_file("untracked.lua", "working", "?")

    local adapter = {
      ctx = {
        toplevel = test_dir,
        dir = test_dir,
        path_args = {},
      },
      diffview_options = function()
        return {
          left = { type = RevType.STAGE },
          right = { type = RevType.LOCAL },
          options = {},
        }
      end,
      rev_to_pretty_string = function() return "" end,
      rev_to_args = function() return {} end,
      tracked_files = function(_, _, _, _, kind)
        if kind == "working" then return make_waitable(nil, { working_entry }, {}) end
        if kind == "staged" then return make_waitable(nil, { staged_entry }, {}) end
        return make_waitable(nil, {}, {})
      end,
      untracked_files = function() return make_waitable(nil, { untracked_entry }) end,
      show_untracked = function() return true end,
      head_rev = function() return { commit = "HEAD" } end,
      Rev = setmetatable({
        new_null_tree = function() return { commit = "NULL" } end,
      }, {
        __call = function(_, rev_type, value) return { type = rev_type, value = value } end,
      }),
      get_merge_context = function() return nil end,
      instanceof = function() return true end,
    }

    track_stub(vcs, "get_adapter", function() return nil, adapter end)

    local warn_stub = track_stub(utils, "warn", function() end)
    local view = lib.json_view_open(test_dir .. "/review.json", {})

    assert(view ~= nil, "Expected view to be created")
    eq(1, #view.files.groups)
    eq(3, #view.files.groups[1].files)
    eq({ "staged.lua", "unstaged.lua", "untracked.lua" }, {
      view.files.groups[1].files[1].path,
      view.files.groups[1].files[2].path,
      view.files.groups[1].files[3].path,
    })
    assert.stub(warn_stub).was_not.called()
  end)

  it(
    "includes staged and untracked files for stage..local with git adapter",
    async_test(function()
      run_git(test_dir, { "init" })
      run_git(test_dir, { "config", "user.email", "diffview@example.com" })
      run_git(test_dir, { "config", "user.name", "Diffview Tests" })
      run_git(test_dir, { "config", "status.showUntrackedFiles", "all" })

      write_file(test_dir .. "/unstaged.lua", "initial\n")
      run_git(test_dir, { "add", "unstaged.lua" })
      run_git(test_dir, { "commit", "-m", "initial" })

      write_file(test_dir .. "/unstaged.lua", "modified\n")
      write_file(test_dir .. "/staged.lua", "staged\n")
      run_git(test_dir, { "add", "staged.lua" })
      write_file(test_dir .. "/untracked.lua", "untracked\n")

      local data = {
        title = "Stage Review",
        groups = {
          {
            name = "Group A",
            files = {
              { path = "staged.lua" },
              { path = "unstaged.lua" },
              { path = "untracked.lua" },
            },
          },
        },
      }

      write_file(test_dir .. "/review.json", vim.json.encode(data))

      local view = lib.json_view_open(test_dir .. "/review.json", { "-C=" .. test_dir })

      assert(view ~= nil, "Expected view to be created")
      eq(1, #view.files.groups)
      eq(3, #view.files.groups[1].files)
      eq({ "staged.lua", "unstaged.lua", "untracked.lua" }, {
        view.files.groups[1].files[1].path,
        view.files.groups[1].files[2].path,
        view.files.groups[1].files[3].path,
      })
    end)
  )
end)

describe("diffview.file_panel grouped", function()
  it("builds components for grouped list mode", function()
    local files = GroupedFileDict("Review")
    local file_a = make_file("src/a.lua")
    local file_b = make_file("src/b.lua")
    local file_c = make_file("docs/c.md")

    files:add_group("Group A", { file_a, file_b })
    files:add_group("Group B", { file_c })

    local panel = {
      render_data = renderer.RenderData("panel_test"),
      files = files,
      listing_style = "list",
      tree_options = config.get_config().file_panel.tree_options,
    }

    panel.should_show_file = FilePanel.should_show_file
    panel.update_components = FilePanel.update_components

    panel:update_components()

    eq({ "group_1", "group_2" }, panel.group_component_names)
    eq(2, #panel.components.group_1.files)
    eq(file_a, panel.components.group_1.files[1].comp.context)
    eq(file_b, panel.components.group_1.files[2].comp.context)
    eq(1, #panel.components.group_2.files)
    eq(file_c, panel.components.group_2.files[1].comp.context)
  end)

  it("orders grouped files for list and tree modes", function()
    local files = GroupedFileDict()
    local description = make_file("Description", "working", " ")
    description.is_json_description = true
    local file_a = make_file("src/components/Button.lua")
    local file_b = make_file("lib/utils/helpers.lua")

    files:add_group("Group A", { description, file_a })
    files:add_group("Group B", { file_b })

    local list_panel = {
      files = files,
      listing_style = "list",
      view = nil,
    }

    list_panel.should_show_file = FilePanel.should_show_file
    list_panel.ordered_file_list = FilePanel.ordered_file_list

    local list_order = list_panel:ordered_file_list()
    eq({ description, file_a, file_b }, list_order)

    local tree_panel = {
      files = files,
      listing_style = "tree",
      view = nil,
    }

    tree_panel.should_show_file = FilePanel.should_show_file
    tree_panel.ordered_file_list = FilePanel.ordered_file_list

    local tree_order = tree_panel:ordered_file_list()
    eq({ description, file_a, file_b }, tree_order)
  end)
end)

describe("diffview.render grouped", function()
  local original_config

  before_each(function()
    original_config = config._config
    config._config = vim.tbl_deep_extend("force", {}, config.defaults)
    config._config.use_icons = false
  end)

  after_each(function() config._config = original_config end)

  it("renders grouped headers and title", function()
    local files = GroupedFileDict("My Review")
    local description = make_file("Description", "working", " ")
    description.is_json_description = true
    local file_a = make_file("src/a.lua")
    local file_b = make_file("api/b.lua")

    files:add_group("Frontend", { description, file_a })
    files:add_group("Backend", { file_b })

    local panel = {
      adapter = {
        ctx = { toplevel = "/repo" },
      },
      files = files,
      listing_style = "list",
      tree_options = config.get_config().file_panel.tree_options,
      render_data = renderer.RenderData("render_test"),
      rev_pretty_name = nil,
      path_args = {},
      help_mapping = nil,
      view = nil,
      infer_width = function() return 80 end,
    }

    panel.should_show_file = FilePanel.should_show_file
    panel.update_components = FilePanel.update_components

    panel:update_components()

    local render = require("diffview.scene.views.diff.render")
    render(panel)

    eq("My Review", panel.components.path.comp.lines[2])
    eq("Frontend (2)", panel.components.group_1.title.comp.lines[1])
    assert(
      panel.components.group_1.files[1].comp.lines[1]:match("Description"),
      "Expected description entry to render as Description"
    )
    eq("Backend (1)", panel.components.group_2.title.comp.lines[1])
  end)
end)

describe("diffview.completers DiffviewOpenJson", function()
  local stubs

  before_each(function() stubs = {} end)

  after_each(function()
    for _, s in ipairs(stubs) do
      s:revert()
    end
    stubs = {}
  end)

  it("suggests rev args after the JSON path", function()
    local adapter = {
      comp = {
        open = {
          get_all_names = function() return { "--cached" } end,
          get_completion = function() return { "--cached" } end,
        },
      },
      rev_candidates = function() return { "HEAD", "main..feature" } end,
      path_candidates = function() return {} end,
    }

    stubs[#stubs + 1] = stub(diffview, "get_adapter", function() return adapter end)

    local cmd_line = "DiffviewOpenJson review.json "
    local ctx = arg_parser.scan(cmd_line, { cur_pos = #cmd_line + 1 })
    local candidates = diffview.completers.DiffviewOpenJson(ctx)

    assert.is_true(vim.tbl_contains(candidates, "HEAD"))
    assert.is_true(vim.tbl_contains(candidates, "main..feature"))
  end)
end)
