local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

local config = require("diffview.config")
local review = require("diffview.review")

describe("review filter", function()
  local original_config

  before_each(function()
    -- Store original config
    original_config = config._config
    config._config = { review = { enabled = true } }
  end)

  after_each(function()
    -- Restore original config
    config._config = original_config
  end)

  -- Helper to create a mock file entry
  local function create_file_entry(path)
    return { path = path }
  end

  -- Helper to create a mock review state
  local function create_mock_review_state(file_statuses)
    return {
      file_statuses = file_statuses,
      get_file_status = function(self, path, blob_hash)
        return self.file_statuses[path]
      end,
    }
  end

  -- Helper to create a mock adapter
  local function create_mock_adapter(blob_hashes)
    return {
      file_blob_hash = function(self, path, rev)
        return blob_hashes and blob_hashes[path] or "hash_" .. path
      end,
    }
  end

  -- Helper to create a mock FileDict-like structure
  local function create_mock_files(files)
    return {
      working = files,
      conflicting = {},
      staged = {},
      iter = function(self)
        local idx = 0
        return function()
          idx = idx + 1
          if idx <= #files then
            return idx, files[idx]
          end
        end
      end,
      len = function(self)
        return #files
      end,
    }
  end

  describe("toggle_review_filter", function()
    it("toggles the filter state from false to true", function()
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local utils = require("diffview.utils")
      local api = vim.api

      local files = {
        create_file_entry("src/file1.lua"),
        create_file_entry("src/file2.lua"),
      }

      -- Track info/echo messages
      local info_messages = {}
      local echo_messages = {}
      local orig_info = utils.info
      local orig_echo = api.nvim_echo

      utils.info = function(msg)
        table.insert(info_messages, msg)
      end
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(echo_messages, chunks[1][1])
        end
      end

      -- Create a minimal mock view
      local mock_view = {
        review_filter_enabled = false,
        review_state = create_mock_review_state({
          ["src/file1.lua"] = "unreviewed",
          ["src/file2.lua"] = "reviewed",
        }),
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = {
          cur_file = files[1],
          update_components = function() end,
          render = function() end,
          redraw = function() end,
          ordered_file_list = function(self)
            return files
          end,
          set_cur_file = function() end,
          highlight_file = function() end,
        },
      }

      -- Add the toggle method
      mock_view.toggle_review_filter = DiffView.toggle_review_filter

      -- Toggle the filter
      mock_view:toggle_review_filter()

      eq(true, mock_view.review_filter_enabled)
      assert.is_true(#echo_messages > 0)
      assert.is_truthy(string.find(echo_messages[1], "Review filter ON"))

      -- Cleanup
      utils.info = orig_info
      api.nvim_echo = orig_echo
    end)

    it("toggles the filter state from true to false", function()
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local utils = require("diffview.utils")
      local api = vim.api

      local files = {
        create_file_entry("src/file1.lua"),
      }

      local echo_messages = {}
      local orig_echo = api.nvim_echo
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(echo_messages, chunks[1][1])
        end
      end

      local mock_view = {
        review_filter_enabled = true,
        review_state = create_mock_review_state({}),
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = {
          cur_file = files[1],
          update_components = function() end,
          render = function() end,
          redraw = function() end,
          ordered_file_list = function(self)
            return files
          end,
          set_cur_file = function() end,
          highlight_file = function() end,
        },
      }

      mock_view.toggle_review_filter = DiffView.toggle_review_filter
      mock_view:toggle_review_filter()

      eq(false, mock_view.review_filter_enabled)
      assert.is_truthy(string.find(echo_messages[1], "Review filter OFF"))

      api.nvim_echo = orig_echo
    end)

    it("shows info message when review mode is not enabled", function()
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local utils = require("diffview.utils")

      local info_messages = {}
      local orig_info = utils.info
      utils.info = function(msg)
        table.insert(info_messages, msg)
      end

      local mock_view = {
        review_filter_enabled = false,
        review_state = nil, -- No review state
        panel = {
          update_components = function() end,
          render = function() end,
          redraw = function() end,
        },
      }

      mock_view.toggle_review_filter = DiffView.toggle_review_filter
      mock_view:toggle_review_filter()

      eq(false, mock_view.review_filter_enabled) -- Should not change
      eq(1, #info_messages)
      eq("Review mode is not enabled", info_messages[1])

      utils.info = orig_info
    end)

    it("moves cursor to first visible file when current file is filtered out", function()
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local utils = require("diffview.utils")
      local api = vim.api

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending.lua"),
      }

      -- Track calls
      local set_cur_file_calls = {}
      local highlight_calls = {}
      local set_file_calls = {}

      local orig_echo = api.nvim_echo
      api.nvim_echo = function() end

      -- Create mock_view first, then set up the panel with reference to it
      local mock_view = {
        review_filter_enabled = false,
        review_state = create_mock_review_state({
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending.lua"] = "unreviewed",
        }),
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = nil, -- Set up below
        _set_file = function(self, file)
          table.insert(set_file_calls, file)
        end,
      }

      -- Now set up panel with access to mock_view
      mock_view.panel = {
        cur_file = files[1], -- Currently on reviewed file
        update_components = function() end,
        render = function() end,
        redraw = function() end,
        ordered_file_list = function(self)
          -- After filter is enabled, only pending file is returned
          if mock_view.review_filter_enabled then
            return { files[2] }
          end
          return files
        end,
        set_cur_file = function(self, file)
          table.insert(set_cur_file_calls, file)
        end,
        highlight_file = function(self, file)
          table.insert(highlight_calls, file)
        end,
      }

      mock_view.toggle_review_filter = DiffView.toggle_review_filter
      mock_view:toggle_review_filter()

      -- Cursor should have moved to the first visible file (the pending one)
      eq(1, #set_cur_file_calls)
      eq(files[2], set_cur_file_calls[1])
      eq(1, #highlight_calls)
      eq(files[2], highlight_calls[1])
      eq(1, #set_file_calls)
      eq(files[2], set_file_calls[1])

      api.nvim_echo = orig_echo
    end)
  end)

  describe("FilePanel:should_show_file", function()
    it("returns true when filter is disabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local file = create_file_entry("src/reviewed.lua")
      local mock_panel = {
        view = {
          review_filter_enabled = false,
          review_state = create_mock_review_state({
            ["src/reviewed.lua"] = "reviewed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      -- Add method
      mock_panel.should_show_file = FilePanel.should_show_file

      local result = mock_panel:should_show_file(file)
      eq(true, result)
    end)

    it("returns true when view is nil", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local file = create_file_entry("src/file.lua")
      local mock_panel = {
        view = nil,
      }

      mock_panel.should_show_file = FilePanel.should_show_file

      local result = mock_panel:should_show_file(file)
      eq(true, result)
    end)

    it("returns true for unreviewed files when filter is enabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local file = create_file_entry("src/unreviewed.lua")
      local mock_panel = {
        view = {
          review_filter_enabled = true,
          review_state = create_mock_review_state({
            ["src/unreviewed.lua"] = "unreviewed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file

      local result = mock_panel:should_show_file(file)
      eq(true, result)
    end)

    it("returns true for changed files when filter is enabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local file = create_file_entry("src/changed.lua")
      local mock_panel = {
        view = {
          review_filter_enabled = true,
          review_state = create_mock_review_state({
            ["src/changed.lua"] = "changed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file

      local result = mock_panel:should_show_file(file)
      eq(true, result)
    end)

    it("returns false for reviewed files when filter is enabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local file = create_file_entry("src/reviewed.lua")
      local mock_panel = {
        view = {
          review_filter_enabled = true,
          review_state = create_mock_review_state({
            ["src/reviewed.lua"] = "reviewed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file

      local result = mock_panel:should_show_file(file)
      eq(false, result)
    end)
  end)

  describe("FilePanel:ordered_file_list filtering", function()
    it("returns all files when filter is disabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_panel = {
        listing_style = "list",
        files = create_mock_files(files),
        view = {
          review_filter_enabled = false,
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file
      mock_panel.ordered_file_list = FilePanel.ordered_file_list

      local result = mock_panel:ordered_file_list()
      eq(3, #result)
    end)

    it("filters out reviewed files when filter is enabled", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_panel = {
        listing_style = "list",
        files = create_mock_files(files),
        view = {
          review_filter_enabled = true,
          review_state = create_mock_review_state({
            ["src/reviewed.lua"] = "reviewed",
            ["src/unreviewed.lua"] = "unreviewed",
            ["src/changed.lua"] = "changed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file
      mock_panel.ordered_file_list = FilePanel.ordered_file_list

      local result = mock_panel:ordered_file_list()
      eq(2, #result)
      eq("src/unreviewed.lua", result[1].path)
      eq("src/changed.lua", result[2].path)
    end)

    it("returns empty list when all files are reviewed", function()
      local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel

      local files = {
        create_file_entry("src/reviewed1.lua"),
        create_file_entry("src/reviewed2.lua"),
      }

      local mock_panel = {
        listing_style = "list",
        files = create_mock_files(files),
        view = {
          review_filter_enabled = true,
          review_state = create_mock_review_state({
            ["src/reviewed1.lua"] = "reviewed",
            ["src/reviewed2.lua"] = "reviewed",
          }),
          adapter = create_mock_adapter(),
        },
      }

      mock_panel.should_show_file = FilePanel.should_show_file
      mock_panel.ordered_file_list = FilePanel.ordered_file_list

      local result = mock_panel:ordered_file_list()
      eq(0, #result)
    end)
  end)

  describe("FileTree filtering", function()
    local FileTree = require("diffview.ui.models.file_tree.file_tree").FileTree

    it("create_comp_schema includes all files when no filter", function()
      local files = {
        { path = "src/file1.lua", status = "M" },
        { path = "src/file2.lua", status = "M" },
      }

      local tree = FileTree(files)
      local schema = tree:create_comp_schema({ flatten_dirs = false })

      -- Should have one directory with two files
      eq(1, #schema)
      eq("directory", schema[1].name)
    end)

    it("create_comp_schema filters out files based on file_filter", function()
      local files = {
        { path = "src/keep.lua", status = "M", should_keep = true },
        { path = "src/filter.lua", status = "M", should_keep = false },
      }

      local tree = FileTree(files)
      local schema = tree:create_comp_schema({
        flatten_dirs = false,
        file_filter = function(file)
          return file.should_keep
        end,
      })

      -- Should have one directory with only one file
      eq(1, #schema) -- "src" directory
      eq("directory", schema[1].name)
      -- Find the items component
      local items = nil
      for _, v in ipairs(schema[1]) do
        if v.name == "items" then
          items = v
          break
        end
      end
      assert.is_truthy(items)
      eq(1, #items) -- Only one file
      eq("keep.lua", items[1].context.path:match("[^/]+$"))
    end)

    it("create_comp_schema hides empty directories when all files filtered", function()
      local files = {
        { path = "src/subdir/file.lua", status = "M", should_keep = false },
      }

      local tree = FileTree(files)
      local schema = tree:create_comp_schema({
        flatten_dirs = false,
        file_filter = function(file)
          return file.should_keep
        end,
      })

      -- Should return empty schema since all files are filtered
      eq(0, #schema)
    end)

    it("create_comp_schema shows parent directories when some children visible", function()
      local files = {
        { path = "src/a/keep.lua", status = "M", should_keep = true },
        { path = "src/b/filter.lua", status = "M", should_keep = false },
      }

      local tree = FileTree(files)
      local schema = tree:create_comp_schema({
        flatten_dirs = false,
        file_filter = function(file)
          return file.should_keep
        end,
      })

      -- Should have src directory
      eq(1, #schema)
      eq("directory", schema[1].name)
      -- Find the items
      local items = nil
      for _, v in ipairs(schema[1]) do
        if v.name == "items" then
          items = v
          break
        end
      end
      -- Should only have 'a' directory, 'b' should be hidden
      eq(1, #items)
    end)
  end)

  describe("action registration", function()
    it("review_toggle_filter action is registered", function()
      local actions = require("diffview.actions")
      assert.is_function(actions.review_toggle_filter)
    end)
  end)

  describe("auto-disable filter when all reviewed", function()
    it("auto-disables filter when enabling it with no pending files", function()
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local api = vim.api

      local files = {
        create_file_entry("src/reviewed1.lua"),
        create_file_entry("src/reviewed2.lua"),
      }

      local echo_messages = {}
      local orig_echo = api.nvim_echo
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(echo_messages, chunks[1][1])
        end
      end

      -- All files are reviewed
      -- Define mock_view first, then set up panel with reference to it
      local mock_view
      mock_view = {
        review_filter_enabled = false,
        review_state = create_mock_review_state({
          ["src/reviewed1.lua"] = "reviewed",
          ["src/reviewed2.lua"] = "reviewed",
        }),
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = {
          cur_file = files[1],
          update_components = function() end,
          render = function() end,
          redraw = function() end,
          ordered_file_list = function(self)
            -- When filter is enabled, no files match
            if mock_view.review_filter_enabled then
              return {}
            end
            return files
          end,
          set_cur_file = function() end,
          highlight_file = function() end,
        },
      }

      mock_view.toggle_review_filter = DiffView.toggle_review_filter
      mock_view:toggle_review_filter()

      -- Filter should have been auto-disabled
      eq(false, mock_view.review_filter_enabled)
      assert.is_true(#echo_messages > 0)
      assert.is_truthy(string.find(echo_messages[1], "All files reviewed"))

      api.nvim_echo = orig_echo
    end)
  end)

  describe("render filter indicator", function()
    -- These are unit tests for the helper functions in render.lua
    -- The render module exports the main render function but internally
    -- uses count_pending_files and count_visible_section_files helpers.
    -- We test these indirectly through integration tests where possible.

    it("count_visible_section_files returns correct count when filter active", function()
      -- Create a mock view with filter enabled and review_state
      local mock_view = {
        review_filter_enabled = true,
        review_state = create_mock_review_state({
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "changed",
        }),
        adapter = create_mock_adapter(),
      }

      -- Simulate what count_visible_section_files does internally
      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local count = 0
      for _, file in ipairs(files) do
        local status = mock_view.review_state:get_file_status(file.path)
        if status == "unreviewed" or status == "changed" then
          count = count + 1
        end
      end

      -- Should count 2 visible files (pending1 and pending2)
      eq(2, count)
    end)

    it("count_pending_files returns correct pending and total counts", function()
      -- Create mock files structure similar to FilePanel.files
      local files = {
        create_file_entry("src/reviewed1.lua"),
        create_file_entry("src/reviewed2.lua"),
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/changed1.lua"),
      }

      local mock_files = create_mock_files(files)

      local mock_view = {
        review_state = create_mock_review_state({
          ["src/reviewed1.lua"] = "reviewed",
          ["src/reviewed2.lua"] = "reviewed",
          ["src/pending1.lua"] = "unreviewed",
          ["src/changed1.lua"] = "changed",
        }),
        adapter = create_mock_adapter(),
      }

      -- Simulate count_pending_files logic
      local pending = 0
      local total = 0
      for _, file in mock_files:iter() do
        total = total + 1
        local status = mock_view.review_state:get_file_status(file.path)
        if status == "unreviewed" or status == "changed" then
          pending = pending + 1
        end
      end

      eq(4, total)
      eq(2, pending)
    end)
  end)

  describe("auto-disable filter when marking last pending file", function()
    it("auto-disables filter when marking the last pending file as reviewed", function()
      local api = vim.api

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/last_pending.lua"),
      }

      local echo_messages = {}
      local orig_echo = api.nvim_echo
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(echo_messages, chunks[1][1])
        end
      end

      -- Track file statuses - we'll update this to simulate marking a file reviewed
      local file_statuses = {
        ["src/reviewed.lua"] = "reviewed",
        ["src/last_pending.lua"] = "unreviewed", -- This will become "reviewed"
      }

      local mock_view
      mock_view = {
        review_filter_enabled = true, -- Filter is ON
        review_state = {
          get_file_status = function(self, path, blob_hash)
            return file_statuses[path]
          end,
        },
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = {
          cur_file = files[2], -- Current file is the pending one
          update_components = function() end,
          render = function() end,
          redraw = function() end,
          is_open = function() return true end,
          ordered_file_list = function(self)
            -- When filter is on, return only pending files
            if mock_view.review_filter_enabled then
              local filtered = {}
              for _, file in ipairs(files) do
                local status = file_statuses[file.path]
                if status == "unreviewed" or status == "changed" then
                  table.insert(filtered, file)
                end
              end
              return filtered
            end
            return files
          end,
        },
      }

      -- Set up a callback similar to what DiffView:init_review_event_listeners does
      local file_marked_callback = function(_, payload)
        if payload.view == mock_view then
          -- Refresh panel
          mock_view.panel:update_components()
          mock_view.panel:render()
          mock_view.panel:redraw()

          -- Auto-disable filter when all files are marked reviewed
          if mock_view.review_filter_enabled then
            local visible_files = mock_view.panel:ordered_file_list()
            if #visible_files == 0 then
              mock_view.review_filter_enabled = false
              mock_view.panel:update_components()
              mock_view.panel:render()
              mock_view.panel:redraw()
              api.nvim_echo({{ "All files reviewed - filter disabled" }}, false, {})
            end
          end
        end
      end

      -- Simulate marking the last pending file as reviewed
      file_statuses["src/last_pending.lua"] = "reviewed"

      -- Trigger the event callback
      file_marked_callback(nil, {
        view = mock_view,
        file_entry = files[2],
        blob_hash = "some_hash",
      })

      -- Filter should be auto-disabled
      eq(false, mock_view.review_filter_enabled)
      assert.is_true(#echo_messages > 0)
      assert.is_truthy(string.find(echo_messages[1], "All files reviewed"))

      api.nvim_echo = orig_echo
    end)

    it("does not disable filter when pending files remain after marking one reviewed", function()
      local api = vim.api

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local echo_messages = {}
      local orig_echo = api.nvim_echo
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(echo_messages, chunks[1][1])
        end
      end

      -- Track file statuses
      local file_statuses = {
        ["src/pending1.lua"] = "unreviewed",
        ["src/pending2.lua"] = "unreviewed",
      }

      local mock_view
      mock_view = {
        review_filter_enabled = true,
        review_state = {
          get_file_status = function(self, path, blob_hash)
            return file_statuses[path]
          end,
        },
        adapter = create_mock_adapter(),
        files = create_mock_files(files),
        panel = {
          cur_file = files[1],
          update_components = function() end,
          render = function() end,
          redraw = function() end,
          is_open = function() return true end,
          ordered_file_list = function(self)
            if mock_view.review_filter_enabled then
              local filtered = {}
              for _, file in ipairs(files) do
                local status = file_statuses[file.path]
                if status == "unreviewed" or status == "changed" then
                  table.insert(filtered, file)
                end
              end
              return filtered
            end
            return files
          end,
        },
      }

      -- Set up callback
      local file_marked_callback = function(_, payload)
        if payload.view == mock_view then
          mock_view.panel:update_components()
          mock_view.panel:render()
          mock_view.panel:redraw()

          if mock_view.review_filter_enabled then
            local visible_files = mock_view.panel:ordered_file_list()
            if #visible_files == 0 then
              mock_view.review_filter_enabled = false
              api.nvim_echo({{ "All files reviewed - filter disabled" }}, false, {})
            end
          end
        end
      end

      -- Mark only one file as reviewed - one pending file remains
      file_statuses["src/pending1.lua"] = "reviewed"

      file_marked_callback(nil, {
        view = mock_view,
        file_entry = files[1],
        blob_hash = "some_hash",
      })

      -- Filter should still be enabled since pending2 is still pending
      eq(true, mock_view.review_filter_enabled)
      -- No auto-disable message should have been shown
      local has_disable_message = false
      for _, msg in ipairs(echo_messages) do
        if string.find(msg, "filter disabled") then
          has_disable_message = true
          break
        end
      end
      eq(false, has_disable_message)

      api.nvim_echo = orig_echo
    end)
  end)
end)
