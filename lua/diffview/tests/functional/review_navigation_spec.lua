local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

local config = require("diffview.config")
local review = require("diffview.review")

describe("review navigation", function()
  local original_config
  local original_vim_v_count1

  before_each(function()
    -- Store original config
    original_config = config._config

    -- Store and mock vim.v.count1
    original_vim_v_count1 = vim.v.count1
  end)

  after_each(function()
    -- Restore original config
    config._config = original_config

    -- Restore vim.v.count1
    vim.v.count1 = original_vim_v_count1
  end)

  -- Helper to mock vim.v.count1
  local function set_count(count)
    vim.v = vim.v or {}
    rawset(vim.v, "count1", count)
  end

  -- Helper to create a mock file entry
  local function create_file_entry(path)
    return { path = path }
  end

  -- Helper to create a mock panel
  local function create_mock_panel(files, cur_file)
    local panel = {
      _files = files,
      cur_file = cur_file,
      ordered_file_list = function(self)
        return self._files
      end,
      set_cur_file = function(self, file)
        self.cur_file = file
        self._set_cur_file_called = file
      end,
      highlight_file = function(self, file)
        self._highlighted_file = file
      end,
      is_focused = function()
        return false
      end,
      _set_cur_file_called = nil,
      _highlighted_file = nil,
    }
    return panel
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

  -- Helper to create a mock DiffView
  local function create_mock_view(opts)
    opts = opts or {}
    local files = opts.files or {}
    local cur_file = opts.cur_file or files[1]
    local file_statuses = opts.file_statuses or {}
    local blob_hashes = opts.blob_hashes

    local panel = create_mock_panel(files, cur_file)

    local echo_messages = {}
    local info_messages = {}
    local set_file_calls = {}

    -- Track the original utils functions
    local utils = require("diffview.utils")
    local original_info = utils.info

    local mock_view = {
      panel = panel,
      review_state = opts.review_enabled ~= false and create_mock_review_state(file_statuses) or nil,
      adapter = create_mock_adapter(blob_hashes),
      review_filter_enabled = false,
      review_status_cache = nil,
      review_status_cache_head = nil,
      review_status_cache_valid = false,
      files = {
        len = function()
          return #files
        end,
        iter = function()
          local idx = 0
          return function()
            idx = idx + 1
            if idx <= #files then
              return idx, files[idx]
            end
          end
        end,
      },
      nulled = false,
      cur_layout = {
        open_null = function() end,
      },
      ensure_layout = function() end,
      file_safeguard = function(self)
        return #files == 0
      end,
      _set_file = function(self, file)
        table.insert(set_file_calls, file)
      end,
      -- Test tracking
      _test_echo_messages = echo_messages,
      _test_info_messages = info_messages,
      _test_set_file_calls = set_file_calls,
      _test_utils_info = original_info,
      -- Store file_statuses for cache building
      _test_file_statuses = file_statuses,
    }

    return mock_view
  end

  -- Helper to load navigation methods onto a mock view
  local function add_navigation_methods(mock_view)
    local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
    local utils = require("diffview.utils")
    local api = vim.api

    -- Track info messages
    local orig_info = utils.info
    utils.info = function(msg)
      table.insert(mock_view._test_info_messages, msg)
    end

    -- Track echo messages
    local orig_nvim_echo = api.nvim_echo
    api.nvim_echo = function(chunks, ...)
      if chunks and chunks[1] and chunks[1][1] then
        table.insert(mock_view._test_echo_messages, chunks[1][1])
      end
    end

    -- Add cache methods - simplified mock that uses file_statuses directly
    mock_view.ensure_review_status_cache = function(self)
      if not self.review_status_cache_valid then
        -- Build cache from file_statuses
        self.review_status_cache = {}
        if self._test_file_statuses then
          for path, status in pairs(self._test_file_statuses) do
            self.review_status_cache[path] = status
          end
        end
        self.review_status_cache_valid = true
      end
    end

    mock_view.invalidate_review_status_cache = function(self, reason)
      self.review_status_cache_valid = false
    end

    mock_view.get_cached_review_status = function(self, file_entry)
      if not self.review_state then return nil end
      if not file_entry or not file_entry.path then return nil end
      self:ensure_review_status_cache()
      return self.review_status_cache and self.review_status_cache[file_entry.path]
    end

    -- Add the navigation methods from DiffView prototype
    mock_view._navigate_review_file = DiffView._navigate_review_file
    mock_view._navigate_review_file_from_entry = DiffView._navigate_review_file_from_entry
    mock_view.next_pending_review_file = DiffView.next_pending_review_file
    mock_view.next_pending_review_file_from = DiffView.next_pending_review_file_from
    mock_view.prev_pending_review_file = DiffView.prev_pending_review_file
    mock_view.prev_pending_review_file_from = DiffView.prev_pending_review_file_from
    mock_view.next_unreviewed_file = DiffView.next_unreviewed_file
    mock_view.prev_unreviewed_file = DiffView.prev_unreviewed_file

    -- Return cleanup function
    return function()
      utils.info = orig_info
      api.nvim_echo = orig_nvim_echo
    end
  end

  describe("next_pending_review_file", function()
    it("navigates to next unreviewed file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/another.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/unreviewed.lua"] = "unreviewed",
          ["src/another.lua"] = "reviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      eq(files[2], result)
      eq(files[2], mock_view.panel._set_cur_file_called)
      eq(files[2], mock_view.panel._highlighted_file)
      eq(1, #mock_view._test_set_file_calls)
      eq(files[2], mock_view._test_set_file_calls[1])

      cleanup()
    end)

    it("navigates to next changed file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/changed.lua"),
        create_file_entry("src/unreviewed.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/changed.lua"] = "changed",
          ["src/unreviewed.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      eq(files[2], result)

      cleanup()
    end)

    it("includes both unreviewed and changed files in pending", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1], -- On the unreviewed file
        file_statuses = {
          ["src/unreviewed.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/changed.lua"] = "changed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      -- From unreviewed, should go to changed (skipping reviewed)
      local result = mock_view:next_pending_review_file()
      eq(files[3], result)

      cleanup()
    end)

    it("shows correct position message", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "changed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      mock_view:next_pending_review_file()

      eq(1, #mock_view._test_echo_messages)
      eq("Pending review [1/2]", mock_view._test_echo_messages[1])

      cleanup()
    end)
  end)

  describe("next_pending_review_file_from", function()
    it("navigates to the next pending file after the given file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/first.lua"),
        create_file_entry("src/pending.lua"),
        create_file_entry("src/current.lua"),
        create_file_entry("src/next_pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3],
        file_statuses = {
          ["src/first.lua"] = "reviewed",
          ["src/pending.lua"] = "unreviewed",
          ["src/current.lua"] = "reviewed",
          ["src/next_pending.lua"] = "changed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file_from(files[3])

      eq(files[4], result)
      eq(files[4], mock_view.panel._set_cur_file_called)
      eq(files[4], mock_view.panel._highlighted_file)
      eq(files[4], mock_view._test_set_file_calls[1])

      cleanup()
    end)

    it("wraps to the first pending file when none remain after the given file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending_first.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/current.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3],
        file_statuses = {
          ["src/pending_first.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/current.lua"] = "reviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file_from(files[3])

      eq(files[1], result)
      eq(files[1], mock_view.panel._set_cur_file_called)
      eq(files[1], mock_view.panel._highlighted_file)
      eq(files[1], mock_view._test_set_file_calls[1])

      cleanup()
    end)
  end)

  describe("prev_pending_review_file_from", function()
    it("navigates to the previous pending file before the given file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/prev_pending.lua"),
        create_file_entry("src/current.lua"),
        create_file_entry("src/pending_after.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[2],
        file_statuses = {
          ["src/prev_pending.lua"] = "changed",
          ["src/current.lua"] = "reviewed",
          ["src/pending_after.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file_from(files[2])

      eq(files[1], result)
      eq(files[1], mock_view.panel._set_cur_file_called)
      eq(files[1], mock_view.panel._highlighted_file)
      eq(files[1], mock_view._test_set_file_calls[1])

      cleanup()
    end)

    it("wraps to the last pending file when none remain before the given file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/current.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/last_pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/current.lua"] = "reviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/last_pending.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file_from(files[1])

      eq(files[3], result)
      eq(files[3], mock_view.panel._set_cur_file_called)
      eq(files[3], mock_view.panel._highlighted_file)
      eq(files[3], mock_view._test_set_file_calls[1])

      cleanup()
    end)
  end)

  describe("prev_pending_review_file", function()
    it("navigates to previous pending file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3],
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file()

      eq(files[1], result)

      cleanup()
    end)

    it("navigates backwards through multiple pending files", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
        create_file_entry("src/pending3.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3],
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "changed",
          ["src/pending3.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file()
      eq(files[2], result)

      cleanup()
    end)
  end)

  describe("next_unreviewed_file", function()
    it("navigates to next unreviewed file only", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/changed.lua"),
        create_file_entry("src/unreviewed.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/changed.lua"] = "changed",
          ["src/unreviewed.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_unreviewed_file()

      -- Should skip the "changed" file and go directly to "unreviewed"
      eq(files[3], result)

      cleanup()
    end)

    it("does NOT include changed files", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/changed.lua"] = "changed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_unreviewed_file()

      -- Should return nil since there are no unreviewed files
      eq(nil, result)
      eq(1, #mock_view._test_info_messages)
      eq("No unreviewed files", mock_view._test_info_messages[1])

      cleanup()
    end)

    it("shows correct position message", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/unreviewed1.lua"),
        create_file_entry("src/changed.lua"),
        create_file_entry("src/unreviewed2.lua"),
        create_file_entry("src/unreviewed3.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/unreviewed1.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
          ["src/unreviewed2.lua"] = "unreviewed",
          ["src/unreviewed3.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      mock_view:next_unreviewed_file()

      eq(1, #mock_view._test_echo_messages)
      eq("Unreviewed [2/3]", mock_view._test_echo_messages[1])

      cleanup()
    end)
  end)

  describe("prev_unreviewed_file", function()
    it("navigates to previous unreviewed file only", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/unreviewed1.lua"),
        create_file_entry("src/changed.lua"),
        create_file_entry("src/unreviewed2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3],
        file_statuses = {
          ["src/unreviewed1.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
          ["src/unreviewed2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_unreviewed_file()

      -- Should skip the "changed" file
      eq(files[1], result)

      cleanup()
    end)
  end)

  describe("wrapping behavior", function()
    it("wraps from last to first file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3], -- On the last pending file
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      -- Should wrap to the first pending file
      eq(files[1], result)

      cleanup()
    end)

    it("wraps from first to last file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1], -- On the first pending file
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file()

      -- Should wrap to the last pending file
      eq(files[3], result)

      cleanup()
    end)

    it("wraps correctly with unreviewed-only navigation", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/unreviewed1.lua"),
        create_file_entry("src/changed.lua"),
        create_file_entry("src/unreviewed2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[3], -- On the last unreviewed file
        file_statuses = {
          ["src/unreviewed1.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
          ["src/unreviewed2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_unreviewed_file()

      -- Should wrap to the first unreviewed file (skipping changed)
      eq(files[1], result)

      cleanup()
    end)
  end)

  describe("count support", function()
    it("skips multiple files with count", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
        create_file_entry("src/pending3.lua"),
        create_file_entry("src/pending4.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "unreviewed",
          ["src/pending3.lua"] = "unreviewed",
          ["src/pending4.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(2) -- Skip 2 files

      local result = mock_view:next_pending_review_file()

      -- Should jump to the third pending file (skipping 2)
      eq(files[3], result)

      cleanup()
    end)

    it("wraps correctly with count", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
        create_file_entry("src/pending3.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[2], -- On the second file
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "unreviewed",
          ["src/pending3.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(3) -- Skip 3 files (should wrap)

      local result = mock_view:next_pending_review_file()

      -- From index 2, +3 = 5, 5 mod 3 = 2, so should land on files[2]
      eq(files[2], result)

      cleanup()
    end)

    it("count works with prev navigation", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
        create_file_entry("src/pending3.lua"),
        create_file_entry("src/pending4.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[4],
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "unreviewed",
          ["src/pending3.lua"] = "unreviewed",
          ["src/pending4.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(2) -- Skip 2 files backwards

      local result = mock_view:prev_pending_review_file()

      -- Should jump back 2 files
      eq(files[2], result)

      cleanup()
    end)
  end)

  describe("edge cases", function()
    it("returns nil when no files match", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed1.lua"),
        create_file_entry("src/reviewed2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed1.lua"] = "reviewed",
          ["src/reviewed2.lua"] = "reviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      eq(nil, result)
      eq(1, #mock_view._test_info_messages)
      eq("No pending review files", mock_view._test_info_messages[1])

      cleanup()
    end)

    it("shows info message when review mode is not enabled", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/file.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        review_enabled = false, -- Review state is nil
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      eq(nil, result)
      eq(1, #mock_view._test_info_messages)
      eq("Review mode is not enabled", mock_view._test_info_messages[1])

      cleanup()
    end)

    it("handles single matching file", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/only_pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[2], -- Already on the only pending file
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/only_pending.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      -- Should stay on the same file (wraps to itself)
      eq(files[2], result)
      eq("Pending review [1/1]", mock_view._test_echo_messages[1])

      cleanup()
    end)

    it("handles empty file list", function()
      config._config = { review = { enabled = true } }

      local mock_view = create_mock_view({
        files = {},
        file_statuses = {},
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      eq(nil, result)

      cleanup()
    end)

    it("navigates correctly when current file is not in matching set", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1], -- On a reviewed file (not in pending set)
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending1.lua"] = "unreviewed",
          ["src/pending2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      -- Should go to first pending file
      eq(files[2], result)
      eq("Pending review [1/2]", mock_view._test_echo_messages[1])

      cleanup()
    end)

    it("prev navigates correctly when current file is not in matching set", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/pending1.lua"),
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending2.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[2], -- On a reviewed file (not in pending set)
        file_statuses = {
          ["src/pending1.lua"] = "unreviewed",
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending2.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:prev_pending_review_file()

      -- Should go to previous pending file before the current file
      eq(files[1], result)

      cleanup()
    end)
  end)

  describe("file highlighting and selection", function()
    it("highlights the target file in panel", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      mock_view:next_pending_review_file()

      eq(files[2], mock_view.panel._highlighted_file)

      cleanup()
    end)

    it("sets cur_file in panel", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      mock_view:next_pending_review_file()

      eq(files[2], mock_view.panel._set_cur_file_called)

      cleanup()
    end)

    it("calls _set_file to open the file in diff view", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/pending.lua"),
      }

      local mock_view = create_mock_view({
        files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/pending.lua"] = "unreviewed",
        },
      })

      local cleanup = add_navigation_methods(mock_view)
      set_count(1)

      mock_view:next_pending_review_file()

      eq(1, #mock_view._test_set_file_calls)
      eq(files[2], mock_view._test_set_file_calls[1])

      cleanup()
    end)
  end)
end)

describe("review navigation actions registration", function()
  it("navigation actions are registered in actions module", function()
    local actions = require("diffview.actions")

    -- Verify the action functions exist
    assert.is_function(actions.review_next_pending)
    assert.is_function(actions.review_prev_pending)
    assert.is_function(actions.review_next_unreviewed)
    assert.is_function(actions.review_prev_unreviewed)
  end)
end)

describe("review navigation performance optimizations", function()
  local original_config
  local original_vim_v_count1

  before_each(function()
    original_config = config._config
    original_vim_v_count1 = vim.v.count1
  end)

  after_each(function()
    config._config = original_config
    vim.v.count1 = original_vim_v_count1
  end)

  local function set_count(count)
    vim.v = vim.v or {}
    rawset(vim.v, "count1", count)
  end

  local function create_file_entry(path)
    return { path = path }
  end

  describe("skip filter optimization when panel already filtered", function()
    -- Helper to create a mock view with tracking for optimization verification
    local function create_optimized_mock_view(opts)
      opts = opts or {}
      local files = opts.files or {}
      local filtered_files = opts.filtered_files or files  -- Pre-filtered list
      local cur_file = opts.cur_file or files[1]
      local file_statuses = opts.file_statuses or {}
      local review_filter_enabled = opts.review_filter_enabled or false

      local status_lookups = {}

      -- Mock panel that returns filtered_files when filter is enabled
      local panel = {
        _files = files,
        _filtered_files = filtered_files,
        cur_file = cur_file,
        ordered_file_list = function(self)
          -- When filter is enabled, return pre-filtered list (simulates real behavior)
          if review_filter_enabled then
            return self._filtered_files
          end
          return self._files
        end,
        set_cur_file = function(self, file)
          self.cur_file = file
        end,
        highlight_file = function(self, file)
          self._highlighted_file = file
        end,
        is_focused = function()
          return false
        end,
      }

      local mock_review_state = {
        file_statuses = file_statuses,
        get_file_status = function(self, path, blob_hash)
          return self.file_statuses[path]
        end,
      }

      local mock_adapter = {
        file_blob_hash = function(self, path, rev)
          return "hash_" .. path
        end,
        head_rev = function()
          return { commit = "abc123" }
        end,
        file_blob_hashes_batch = function(self, paths, rev)
          local result = {}
          for _, path in ipairs(paths) do
            result[path] = "hash_" .. path
          end
          return result
        end,
      }

      local echo_messages = {}
      local info_messages = {}
      local set_file_calls = {}

      local mock_view = {
        panel = panel,
        review_state = mock_review_state,
        review_filter_enabled = review_filter_enabled,
        review_status_cache = nil,
        review_status_cache_head = nil,
        review_status_cache_valid = false,
        adapter = mock_adapter,
        files = {
          len = function()
            return #files
          end,
          iter = function()
            local idx = 0
            return function()
              idx = idx + 1
              if idx <= #files then
                return idx, files[idx]
              end
            end
          end,
        },
        nulled = false,
        cur_layout = {
          open_null = function() end,
        },
        ensure_layout = function() end,
        file_safeguard = function(self)
          return #files == 0
        end,
        _set_file = function(self, file)
          table.insert(set_file_calls, file)
        end,
        -- Test tracking
        _test_echo_messages = echo_messages,
        _test_info_messages = info_messages,
        _test_set_file_calls = set_file_calls,
        _test_status_lookups = status_lookups,
      }

      return mock_view, status_lookups
    end

    -- Helper to load navigation and cache methods onto a mock view
    local function add_optimized_navigation_methods(mock_view)
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
      local utils = require("diffview.utils")
      local api = vim.api

      -- Track info messages
      local orig_info = utils.info
      utils.info = function(msg)
        table.insert(mock_view._test_info_messages, msg)
      end

      -- Track echo messages
      local orig_nvim_echo = api.nvim_echo
      api.nvim_echo = function(chunks, ...)
        if chunks and chunks[1] and chunks[1][1] then
          table.insert(mock_view._test_echo_messages, chunks[1][1])
        end
      end

      -- Store file_statuses reference for cache building
      local file_statuses = mock_view.review_state and mock_view.review_state.file_statuses or {}

      -- Add simplified cache methods that use file_statuses directly
      mock_view.ensure_review_status_cache = function(self)
        if not self.review_status_cache_valid then
          -- Build cache from file_statuses
          self.review_status_cache = {}
          for path, status in pairs(file_statuses) do
            self.review_status_cache[path] = status
          end
          self.review_status_cache_valid = true
        end
      end

      mock_view.invalidate_review_status_cache = function(self, reason)
        self.review_status_cache_valid = false
      end

      mock_view.get_cached_review_status = function(self, file_entry)
        if not self.review_state then return nil end
        if not file_entry or not file_entry.path then return nil end
        self:ensure_review_status_cache()
        return self.review_status_cache and self.review_status_cache[file_entry.path]
      end

      -- Add the navigation methods from DiffView prototype
      mock_view._navigate_review_file = DiffView._navigate_review_file
      mock_view._navigate_review_file_from_entry = DiffView._navigate_review_file_from_entry
      mock_view.next_pending_review_file = DiffView.next_pending_review_file
      mock_view.next_pending_review_file_from = DiffView.next_pending_review_file_from
      mock_view.prev_pending_review_file = DiffView.prev_pending_review_file
      mock_view.prev_pending_review_file_from = DiffView.prev_pending_review_file_from
      mock_view.next_unreviewed_file = DiffView.next_unreviewed_file
      mock_view.prev_unreviewed_file = DiffView.prev_unreviewed_file

      return function()
        utils.info = orig_info
        api.nvim_echo = orig_nvim_echo
      end
    end

    it("skips status filtering when review_filter_enabled and navigating pending files", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      -- When filter is enabled, panel only returns pending files
      local filtered_files = {
        files[2],  -- unreviewed
        files[3],  -- changed
      }

      local mock_view = create_optimized_mock_view({
        files = files,
        filtered_files = filtered_files,
        cur_file = files[2],  -- Start on unreviewed
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/unreviewed.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
        },
        review_filter_enabled = true,
      })

      local cleanup = add_optimized_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      -- Should navigate to the next pending file (changed)
      eq(files[3], result)

      -- The optimization should have used the filtered list directly without
      -- re-checking statuses. We verify this by checking the echo message
      -- shows the correct count based on the filtered list.
      eq(1, #mock_view._test_echo_messages)
      eq("Pending review [2/2]", mock_view._test_echo_messages[1])

      cleanup()
    end)

    it("still filters correctly when review_filter_enabled is false", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_view = create_optimized_mock_view({
        files = files,
        filtered_files = files,  -- When not filtered, panel returns all files
        cur_file = files[1],  -- Start on reviewed file
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/unreviewed.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
        },
        review_filter_enabled = false,
      })

      local cleanup = add_optimized_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_pending_review_file()

      -- Should navigate to the first pending file (unreviewed)
      eq(files[2], result)

      -- Should show correct count from filtering (2 pending files out of 3 total)
      eq("Pending review [1/2]", mock_view._test_echo_messages[1])

      cleanup()
    end)

    it("uses cached status for unreviewed-only navigation", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/reviewed.lua"),
        create_file_entry("src/unreviewed.lua"),
        create_file_entry("src/changed.lua"),
      }

      local mock_view = create_optimized_mock_view({
        files = files,
        filtered_files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/reviewed.lua"] = "reviewed",
          ["src/unreviewed.lua"] = "unreviewed",
          ["src/changed.lua"] = "changed",
        },
        review_filter_enabled = false,
      })

      local cleanup = add_optimized_navigation_methods(mock_view)
      set_count(1)

      local result = mock_view:next_unreviewed_file()

      -- Should navigate to the only unreviewed file (not changed)
      eq(files[2], result)

      -- Unreviewed count should be 1
      eq("Unreviewed [1/1]", mock_view._test_echo_messages[1])

      cleanup()
    end)

    it("builds cache once and reuses for multiple navigation operations", function()
      config._config = { review = { enabled = true } }

      local files = {
        create_file_entry("src/unreviewed1.lua"),
        create_file_entry("src/unreviewed2.lua"),
        create_file_entry("src/unreviewed3.lua"),
      }

      local mock_view = create_optimized_mock_view({
        files = files,
        filtered_files = files,
        cur_file = files[1],
        file_statuses = {
          ["src/unreviewed1.lua"] = "unreviewed",
          ["src/unreviewed2.lua"] = "unreviewed",
          ["src/unreviewed3.lua"] = "unreviewed",
        },
        review_filter_enabled = false,
      })

      local cleanup = add_optimized_navigation_methods(mock_view)
      set_count(1)

      -- First navigation should build cache
      mock_view:next_unreviewed_file()

      -- Cache should now be valid
      eq(true, mock_view.review_status_cache_valid)
      neq(nil, mock_view.review_status_cache)

      -- Second navigation should reuse cache (not rebuild)
      local cache_before = mock_view.review_status_cache
      mock_view:next_unreviewed_file()
      eq(cache_before, mock_view.review_status_cache)

      cleanup()
    end)
  end)
end)
