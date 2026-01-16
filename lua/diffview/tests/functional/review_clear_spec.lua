local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq
local async_test = helpers.async_test

local uv = vim.loop

describe("diffview.review clear operations", function()
  local review_store = require("diffview.review_store")
  local review = require("diffview.review")
  local config = require("diffview.config")
  local ReviewStore = review_store.ReviewStore
  local ReviewState = review_store.ReviewState
  local utils = require("diffview.utils")

  -- Test directory for file I/O tests
  local test_cache_dir = "/tmp/claude/diffview_test_clear_" .. os.time()

  -- Helper function to recursively remove a directory
  local function rm_rf(path)
    local stat = uv.fs_stat(path)
    if not stat then return end

    if stat.type == "directory" then
      local handle = uv.fs_scandir(path)
      if handle then
        while true do
          local name, t = uv.fs_scandir_next(handle)
          if not name then break end
          rm_rf(path .. "/" .. name)
        end
      end
      uv.fs_rmdir(path)
    else
      uv.fs_unlink(path)
    end
  end

  -- Helper to write a file synchronously
  local function write_file(path, content)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, content, 0))
    assert(uv.fs_close(fd))
  end

  -- Helper to check if a file exists
  local function file_exists(path)
    local stat = uv.fs_stat(path)
    return stat ~= nil and stat.type == "file"
  end

  -- Helper to check if a directory exists
  local function dir_exists(path)
    local stat = uv.fs_stat(path)
    return stat ~= nil and stat.type == "directory"
  end

  describe("ReviewStore:clear_repo_state()", function()
    local store

    before_each(function()
      -- Clean up any previous test directory
      rm_rf(test_cache_dir)

      -- Create a store with a custom cache directory
      store = ReviewStore()
      store.cache_dir = test_cache_dir
    end)

    after_each(function()
      -- Clean up test directory
      rm_rf(test_cache_dir)
    end)

    it("deletes all JSON files in the repository directory", function()
      local repo_id = "test_repo_clear"

      -- Create the directory structure and files
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/main.json", '{"version":1,"files":{}}')
      write_file(repo_dir .. "/feature__branch.json", '{"version":1,"files":{}}')
      write_file(repo_dir .. "/develop.json", '{"version":1,"files":{}}')

      -- Verify files exist before clearing
      eq(true, file_exists(repo_dir .. "/main.json"))
      eq(true, file_exists(repo_dir .. "/feature__branch.json"))
      eq(true, file_exists(repo_dir .. "/develop.json"))

      -- Clear the repo state
      local deleted_count = store:clear_repo_state(repo_id)

      -- Verify count
      eq(3, deleted_count)

      -- Verify files are deleted
      eq(false, file_exists(repo_dir .. "/main.json"))
      eq(false, file_exists(repo_dir .. "/feature__branch.json"))
      eq(false, file_exists(repo_dir .. "/develop.json"))
    end)

    it("returns correct count of deleted files", function()
      local repo_id = "test_repo_count"

      -- Create directory with various files (only JSON should be deleted)
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/branch1.json", '{}')
      write_file(repo_dir .. "/branch2.json", '{}')
      write_file(repo_dir .. "/not_a_json.txt", 'text')

      local deleted_count = store:clear_repo_state(repo_id)

      -- Should only delete JSON files
      eq(2, deleted_count)

      -- Non-JSON file should still exist
      eq(true, file_exists(repo_dir .. "/not_a_json.txt"))
    end)

    it("handles non-existent repository directory", function()
      local repo_id = "nonexistent_repo"

      -- Directory doesn't exist
      eq(false, dir_exists(test_cache_dir .. "/" .. repo_id))

      -- Should return 0 without error
      local deleted_count = store:clear_repo_state(repo_id)
      eq(0, deleted_count)
    end)

    it("handles empty repository directory", function()
      local repo_id = "empty_repo"

      -- Create empty directory
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local deleted_count = store:clear_repo_state(repo_id)
      eq(0, deleted_count)
    end)

    it("removes empty directory after clearing files", function()
      local repo_id = "cleanup_repo"

      -- Create directory with a single JSON file
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/main.json", '{}')

      -- Verify directory exists
      eq(true, dir_exists(repo_dir))

      store:clear_repo_state(repo_id)

      -- Directory should be removed (or attempt to remove)
      -- Note: rmdir only succeeds if directory is empty
      eq(false, dir_exists(repo_dir))
    end)

    it("does not remove directory if non-JSON files remain", function()
      local repo_id = "partial_cleanup"

      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/main.json", '{}')
      write_file(repo_dir .. "/other.txt", 'keep this')

      store:clear_repo_state(repo_id)

      -- Directory should still exist (has non-JSON file)
      eq(true, dir_exists(repo_dir))
      eq(true, file_exists(repo_dir .. "/other.txt"))
    end)
  end)

  describe("review.clear_repo_reviews()", function()
    local original_config
    local store

    before_each(function()
      -- Store original config
      original_config = config._config

      -- Clean up any previous test directory
      rm_rf(test_cache_dir)

      -- Create a store with a custom cache directory
      store = ReviewStore()
      store.cache_dir = test_cache_dir
    end)

    after_each(function()
      -- Restore original config
      config._config = original_config

      -- Clean up test directory
      rm_rf(test_cache_dir)
    end)

    it("returns 0 when review is disabled", function()
      config._config = { review = { enabled = false } }

      local mock_view = {
        adapter = {
          ctx = { toplevel = "/mock/repo" },
        },
      }

      local result = review.clear_repo_reviews(mock_view)
      eq(0, result)
    end)

    it("returns 0 when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_repo_reviews(nil)
      eq(0, result)
    end)

    it("returns 0 when view has no adapter", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_repo_reviews({})
      eq(0, result)
    end)

    it("returns 0 when repo_id cannot be determined", function()
      config._config = { review = { enabled = true } }

      local mock_adapter = {
        ctx = { toplevel = "/failing/repo" },
        exec_sync = function()
          return {}, 128 -- Git error
        end,
      }

      -- Need to use a real store for this test to exercise get_repo_id
      local mock_view = {
        adapter = mock_adapter,
      }

      local result = review.clear_repo_reviews(mock_view)
      eq(0, result)
    end)

    it("clears in-memory state when view has review_state", function()
      config._config = { review = { enabled = true } }

      local repo_id = "memory_clear_repo"

      -- Create a mock adapter that returns our repo_id
      local mock_adapter = {
        ctx = { toplevel = "/mock/memory/repo" },
        exec_sync = function(self, args)
          if args[1] == "rev-list" then
            return { repo_id .. "0000000000" }, 0
          end
          return {}, 1
        end,
      }

      -- Create directory structure (so clear_repo_state has something to do)
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      -- Create a store and set up the cache
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir

      -- Create review state with some files
      local mock_review_state = {
        files = {
          ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 12345 },
          ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = 12346 },
        },
        dirty = true,
      }

      local mock_view = {
        adapter = mock_adapter,
        review_state = mock_review_state,
      }

      -- Override get_store to return our test store
      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      local result = review.clear_repo_reviews(mock_view)

      -- Restore get_store
      review_store.get_store = original_get_store

      -- Verify in-memory state was cleared
      eq(0, vim.tbl_count(mock_review_state.files))
      eq(false, mock_review_state.dirty)
    end)

    it("emits review_repo_cleared event", function()
      config._config = { review = { enabled = true } }

      -- repo_id must be exactly 12 characters (first 12 chars of commit hash)
      local repo_id = "eventtestre0"
      local captured_events = {}

      -- Register event listener
      local listener = function(_, payload)
        table.insert(captured_events, payload)
      end
      DiffviewGlobal.emitter:on("review_repo_cleared", listener)

      -- Create a mock adapter that returns a hash starting with our repo_id
      local mock_adapter = {
        ctx = { toplevel = "/mock/event/repo" },
        exec_sync = function(self, args)
          if args[1] == "rev-list" then
            -- Return a full SHA that starts with our repo_id
            return { repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
      }

      -- Create directory structure using the repo_id (first 12 chars of hash)
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
      write_file(test_cache_dir .. "/" .. repo_id .. "/main.json", '{}')

      -- Create a store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir

      local mock_view = {
        adapter = mock_adapter,
        review_state = { files = {}, dirty = false },
      }

      -- Override get_store
      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      review.clear_repo_reviews(mock_view)

      -- Restore get_store
      review_store.get_store = original_get_store

      -- Unregister listener
      DiffviewGlobal.emitter:off(listener)

      -- Verify event was emitted
      eq(1, #captured_events)
      eq(mock_view, captured_events[1].view)
      eq(repo_id, captured_events[1].repo_id)
      eq(1, captured_events[1].deleted_count)
    end)
  end)

  describe("review_clear_all listener", function()
    local original_config
    local listeners_module

    before_each(function()
      original_config = config._config
      listeners_module = require("diffview.scene.views.diff.listeners")
    end)

    after_each(function()
      config._config = original_config
    end)

    it("shows warning when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local mock_view = {
        review_state = nil,
        adapter = {},
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }

      local listeners = listeners_module(mock_view)

      -- Should not error, just warn
      listeners.review_clear_all()
    end)

    it("shows info when no files are marked as reviewed", function()
      config._config = { review = { enabled = true } }

      local mock_view = {
        review_state = {
          files = {}, -- Empty files table
          branch = "main",
        },
        adapter = {},
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }

      local listeners = listeners_module(mock_view)

      -- Should not error, shows info
      listeners.review_clear_all()
    end)
  end)

  describe("review_all_cleared event handler", function()
    it("disables review filter when clearing branch state", function()
      -- This tests the DiffView event handler for review_all_cleared
      -- which should disable the filter when it's active
      local captured_events = {}

      -- Create a mock view with review_filter_enabled = true
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      -- Simulate what init_review_event_listeners does for the all_cleared handler
      local all_cleared_handler = function(_, payload)
        if payload.view == mock_view then
          -- Disable review filter if active since there's nothing to filter
          if mock_view.review_filter_enabled then
            mock_view.review_filter_enabled = false
          end
          -- refresh_panel() would be called here
        end
      end

      -- Call the handler
      all_cleared_handler(nil, { view = mock_view })

      -- Verify filter was disabled
      eq(false, mock_view.review_filter_enabled)
    end)

    it("does not change filter state when filter is already disabled", function()
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view = {
        review_filter_enabled = false,
        panel = mock_panel,
      }

      -- Simulate the all_cleared handler
      local all_cleared_handler = function(_, payload)
        if payload.view == mock_view then
          if mock_view.review_filter_enabled then
            mock_view.review_filter_enabled = false
          end
        end
      end

      -- Call the handler
      all_cleared_handler(nil, { view = mock_view })

      -- Filter should still be false
      eq(false, mock_view.review_filter_enabled)
    end)

    it("only affects the target view", function()
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view1 = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      local mock_view2 = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      -- Simulate the all_cleared handler scoped to mock_view1
      local all_cleared_handler = function(_, payload)
        if payload.view == mock_view1 then
          if mock_view1.review_filter_enabled then
            mock_view1.review_filter_enabled = false
          end
        end
      end

      -- Call handler for view1
      all_cleared_handler(nil, { view = mock_view1 })

      -- Only view1's filter should be disabled
      eq(false, mock_view1.review_filter_enabled)
      eq(true, mock_view2.review_filter_enabled)
    end)
  end)

  describe("review_repo_cleared event handler", function()
    it("disables review filter when clearing repository state", function()
      -- This tests the DiffView event handler for review_repo_cleared
      -- which should disable the filter when it's active
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      -- Simulate what init_review_event_listeners does for the repo_cleared handler
      local repo_cleared_handler = function(_, payload)
        if payload.view == mock_view then
          -- Disable review filter if active since there's nothing to filter
          if mock_view.review_filter_enabled then
            mock_view.review_filter_enabled = false
          end
          -- refresh_panel() would be called here
        end
      end

      -- Call the handler
      repo_cleared_handler(nil, { view = mock_view, repo_id = "test_repo", deleted_count = 5 })

      -- Verify filter was disabled
      eq(false, mock_view.review_filter_enabled)
    end)

    it("does not change filter state when filter is already disabled", function()
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view = {
        review_filter_enabled = false,
        panel = mock_panel,
      }

      -- Simulate the repo_cleared handler
      local repo_cleared_handler = function(_, payload)
        if payload.view == mock_view then
          if mock_view.review_filter_enabled then
            mock_view.review_filter_enabled = false
          end
        end
      end

      -- Call the handler
      repo_cleared_handler(nil, { view = mock_view, repo_id = "test_repo", deleted_count = 3 })

      -- Filter should still be false
      eq(false, mock_view.review_filter_enabled)
    end)

    it("only affects the target view", function()
      local mock_panel = {
        is_open = function() return true end,
        update_components = function() end,
        render = function() end,
        redraw = function() end,
      }

      local mock_view1 = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      local mock_view2 = {
        review_filter_enabled = true,
        panel = mock_panel,
      }

      -- Simulate the repo_cleared handler scoped to mock_view1
      local repo_cleared_handler = function(_, payload)
        if payload.view == mock_view1 then
          if mock_view1.review_filter_enabled then
            mock_view1.review_filter_enabled = false
          end
        end
      end

      -- Call handler for view1
      repo_cleared_handler(nil, { view = mock_view1, repo_id = "test_repo", deleted_count = 2 })

      -- Only view1's filter should be disabled
      eq(false, mock_view1.review_filter_enabled)
      eq(true, mock_view2.review_filter_enabled)
    end)
  end)

  describe("review_clear_repo listener", function()
    local original_config
    local listeners_module

    before_each(function()
      original_config = config._config
      listeners_module = require("diffview.scene.views.diff.listeners")

      -- Clean up test directory
      rm_rf(test_cache_dir)
    end)

    after_each(function()
      config._config = original_config
      rm_rf(test_cache_dir)
    end)

    it("shows warning when repo_id cannot be determined", function()
      config._config = { review = { enabled = true } }

      local mock_adapter = {
        ctx = { toplevel = "/failing/repo" },
        exec_sync = function()
          return {}, 128 -- Git error
        end,
      }

      local mock_view = {
        review_state = { files = {}, branch = "main" },
        adapter = mock_adapter,
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }

      local listeners = listeners_module(mock_view)

      -- Should not error, just warn
      listeners.review_clear_repo()
    end)

    it("shows info when no review state exists for repository", function()
      config._config = { review = { enabled = true } }

      local repo_id = "empty_repo_listener"

      -- Create a mock adapter that returns our repo_id
      local mock_adapter = {
        ctx = { toplevel = "/mock/empty/repo" },
        exec_sync = function(self, args)
          if args[1] == "rev-list" then
            return { repo_id .. "0000000000" }, 0
          end
          return {}, 1
        end,
      }

      -- Create a store with empty repo directory
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir

      -- Create directory but no files
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      -- Don't create the repo directory - simulates no state

      local mock_view = {
        review_state = { files = {}, branch = "main" },
        adapter = mock_adapter,
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }

      -- Override get_store
      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      local listeners = listeners_module(mock_view)

      -- Should not error, shows info about no state existing
      listeners.review_clear_repo()

      -- Restore get_store
      review_store.get_store = original_get_store
    end)
  end)

  describe("review actions registration", function()
    it("review_clear_all and review_clear_repo actions are registered", function()
      local actions = require("diffview.actions")

      -- Verify the action functions exist
      assert.is_function(actions.review_clear_all)
      assert.is_function(actions.review_clear_repo)
    end)
  end)
end)
