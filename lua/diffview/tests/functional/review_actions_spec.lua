local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

local config = require("diffview.config")
local review = require("diffview.review")

describe("review action listeners", function()
  local original_config
  local listeners_module

  before_each(function()
    -- Store original config
    original_config = config._config

    -- Load the listeners module - it returns a function that takes a view
    listeners_module = require("diffview.scene.views.diff.listeners")
  end)

  after_each(function()
    -- Restore original config
    config._config = original_config
  end)

  -- Helper to create a mock view with common defaults
  local function create_mock_view(opts)
    opts = opts or {}

    local marked_files = {}
    local cleared_files = {}
    local mock_store = { save_state = function() end }

    local mock_review_state = nil
    if opts.review_enabled ~= false then
      mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash, skip_save)
          marked_files[path] = { hash = hash, commit_hash = commit_hash, skip_save = skip_save }
        end,
        clear_file = function(_, path)
          table.insert(cleared_files, path)
        end,
        store = mock_store,
      }
    end

    local blob_hashes = opts.blob_hashes or {}
    local mock_commit_hash = opts.commit_hash or "abc123def456"
    local mock_adapter = {
      file_blob_hash = function(_, path, rev)
        return blob_hashes[path]
      end,
      head_rev = function()
        return { commit = mock_commit_hash }
      end,
    }

    local file_entries = opts.files or {}
    local mock_files = {
      iter = function()
        local idx = 0
        return function()
          idx = idx + 1
          if idx <= #file_entries then
            return idx, file_entries[idx]
          end
        end
      end,
    }

    local cur_file = opts.cur_file

    local mock_view = {
      review_state = mock_review_state,
      adapter = mock_adapter,
      files = mock_files,
      cur_entry = cur_file,
      infer_cur_file = function()
        return cur_file
      end,
      -- Track what was marked/cleared for assertions
      _test_marked_files = marked_files,
      _test_cleared_files = cleared_files,
    }

    return mock_view
  end

  describe("review_mark_file listener", function()
    it("calls review.mark_file_reviewed when file is selected", function()
      config._config = { review = { enabled = true } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local listeners = listeners_module(mock_view)
      listeners.review_mark_file()

      -- Verify the file was marked
      neq(nil, mock_view._test_marked_files["src/test.lua"])
      eq("abc123", mock_view._test_marked_files["src/test.lua"].hash)
    end)

    it("auto-advances to the next file when configured", function()
      config._config = { review = { enabled = true, auto_advance = "next" } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local next_file_calls = 0
      local next_pending_calls = 0

      mock_view.next_file = function(_, highlight)
        next_file_calls = next_file_calls + 1
        eq(true, highlight)
      end
      mock_view.next_pending_review_file = function()
        next_pending_calls = next_pending_calls + 1
      end

      local listeners = listeners_module(mock_view)
      listeners.review_mark_file()

      eq(1, next_file_calls)
      eq(0, next_pending_calls)
    end)

    it("auto-advances to the next pending file when configured", function()
      config._config = { review = { enabled = true, auto_advance = "next_pending" } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local next_file_calls = 0
      local next_pending_calls = 0
      local next_pending_args = {}

      mock_view.next_file = function()
        next_file_calls = next_file_calls + 1
      end
      mock_view.next_pending_review_file_from = function(_, file)
        next_pending_calls = next_pending_calls + 1
        table.insert(next_pending_args, file)
      end

      local listeners = listeners_module(mock_view)
      listeners.review_mark_file()

      eq(0, next_file_calls)
      eq(1, next_pending_calls)
      eq(file_entry, next_pending_args[1])
    end)

    it("does nothing when no file is selected", function()
      config._config = { review = { enabled = true } }

      local mock_view = create_mock_view({
        cur_file = nil, -- No file selected
        blob_hashes = {},
      })

      local listeners = listeners_module(mock_view)

      -- Should not error
      listeners.review_mark_file()

      -- No files should be marked
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)

    it("does nothing when review is disabled", function()
      config._config = { review = { enabled = false } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
        review_enabled = false,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local listeners = listeners_module(mock_view)
      listeners.review_mark_file()

      -- No files should be marked (review is disabled)
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)

    it("does nothing when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local file_entry = { path = "src/test.lua" }
      -- Create view with review_state explicitly set to nil
      local mock_view = {
        review_state = nil,
        adapter = {
          file_blob_hash = function()
            return "abc123"
          end,
          head_rev = function()
            return { commit = "abc123def456" }
          end,
        },
        files = { iter = function() return function() end end },
        infer_cur_file = function()
          return file_entry
        end,
        _test_marked_files = {},
        _test_cleared_files = {},
      }

      local listeners = listeners_module(mock_view)
      listeners.review_mark_file()

      -- No files should be marked
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)
  end)

  describe("review_mark_all listener", function()
    it("calls review.mark_all_reviewed with multiple files", function()
      config._config = { review = { enabled = true } }

      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/bar.lua" },
        { path = "tests/test.lua" },
      }
      local mock_view = create_mock_view({
        files = file_entries,
        blob_hashes = {
          ["src/foo.lua"] = "hash111",
          ["src/bar.lua"] = "hash222",
          ["tests/test.lua"] = "hash333",
        },
      })

      local listeners = listeners_module(mock_view)
      listeners.review_mark_all()

      -- Verify all files were marked
      eq(3, vim.tbl_count(mock_view._test_marked_files))
      eq("hash111", mock_view._test_marked_files["src/foo.lua"].hash)
      eq("hash222", mock_view._test_marked_files["src/bar.lua"].hash)
      eq("hash333", mock_view._test_marked_files["tests/test.lua"].hash)
    end)

    it("handles empty file list gracefully", function()
      config._config = { review = { enabled = true } }

      local mock_view = create_mock_view({
        files = {}, -- Empty file list
        blob_hashes = {},
      })

      local listeners = listeners_module(mock_view)

      -- Should not error with empty file list
      listeners.review_mark_all()

      -- No files should be marked
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)

    it("does nothing when review is disabled", function()
      config._config = { review = { enabled = false } }

      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/bar.lua" },
      }
      local mock_view = create_mock_view({
        files = file_entries,
        review_enabled = false,
        blob_hashes = {
          ["src/foo.lua"] = "hash111",
          ["src/bar.lua"] = "hash222",
        },
      })

      local listeners = listeners_module(mock_view)
      listeners.review_mark_all()

      -- No files should be marked (review is disabled)
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)

    it("does nothing when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/bar.lua" },
      }
      -- Create view with review_state explicitly set to nil
      local mock_view = {
        review_state = nil,
        adapter = {
          file_blob_hash = function(_, path)
            return "hash_" .. path
          end,
          head_rev = function()
            return { commit = "abc123def456" }
          end,
        },
        files = {
          iter = function()
            local idx = 0
            return function()
              idx = idx + 1
              if idx <= #file_entries then
                return idx, file_entries[idx]
              end
            end
          end,
        },
        infer_cur_file = function() return nil end,
        _test_marked_files = {},
        _test_cleared_files = {},
      }

      local listeners = listeners_module(mock_view)
      listeners.review_mark_all()

      -- No files should be marked
      eq(0, vim.tbl_count(mock_view._test_marked_files))
    end)

    it("skips files that fail to get blob hash", function()
      config._config = { review = { enabled = true } }

      local file_entries = {
        { path = "src/existing.lua" },
        { path = "src/deleted.lua" },
        { path = "src/another.lua" },
      }
      local mock_view = create_mock_view({
        files = file_entries,
        blob_hashes = {
          ["src/existing.lua"] = "hash111",
          ["src/deleted.lua"] = nil, -- Simulates deleted/unreachable file
          ["src/another.lua"] = "hash333",
        },
      })

      local listeners = listeners_module(mock_view)
      listeners.review_mark_all()

      -- Only 2 files should be marked (one failed)
      eq(2, vim.tbl_count(mock_view._test_marked_files))
      neq(nil, mock_view._test_marked_files["src/existing.lua"])
      eq(nil, mock_view._test_marked_files["src/deleted.lua"])
      neq(nil, mock_view._test_marked_files["src/another.lua"])
    end)
  end)

  describe("review_clear_file listener", function()
    it("calls review.clear_file_review when file is selected", function()
      config._config = { review = { enabled = true } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
      })

      local listeners = listeners_module(mock_view)
      listeners.review_clear_file()

      -- Verify the file was cleared
      eq(1, #mock_view._test_cleared_files)
      eq("src/test.lua", mock_view._test_cleared_files[1])
    end)

    it("does nothing when no file is selected", function()
      config._config = { review = { enabled = true } }

      local mock_view = create_mock_view({
        cur_file = nil, -- No file selected
      })

      local listeners = listeners_module(mock_view)

      -- Should not error
      listeners.review_clear_file()

      -- No files should be cleared
      eq(0, #mock_view._test_cleared_files)
    end)

    it("does nothing when review is disabled", function()
      config._config = { review = { enabled = false } }

      local file_entry = { path = "src/test.lua" }
      local mock_view = create_mock_view({
        cur_file = file_entry,
        review_enabled = false,
      })

      local listeners = listeners_module(mock_view)
      listeners.review_clear_file()

      -- No files should be cleared (review is disabled)
      eq(0, #mock_view._test_cleared_files)
    end)

    it("does nothing when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local file_entry = { path = "src/test.lua" }
      -- Create view with review_state explicitly set to nil
      local mock_view = {
        review_state = nil,
        adapter = {
          file_blob_hash = function()
            return "abc123"
          end,
        },
        files = { iter = function() return function() end end },
        infer_cur_file = function()
          return file_entry
        end,
        _test_marked_files = {},
        _test_cleared_files = {},
      }

      local listeners = listeners_module(mock_view)
      listeners.review_clear_file()

      -- No files should be cleared
      eq(0, #mock_view._test_cleared_files)
    end)
  end)
end)

describe("review actions registration", function()
  it("review actions are registered in actions module", function()
    local actions = require("diffview.actions")

    -- Verify the action functions exist
    assert.is_function(actions.review_mark_file)
    assert.is_function(actions.review_mark_all)
    assert.is_function(actions.review_clear_file)
  end)
end)
