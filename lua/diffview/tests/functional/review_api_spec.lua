local review = require("diffview.review")
local review_store = require("diffview.review_store")
local config = require("diffview.config")

describe("diffview.review", function()
  local original_config

  before_each(function()
    -- Store original config
    original_config = config._config
  end)

  after_each(function()
    -- Restore original config
    config._config = original_config
  end)

  describe("mark_file_reviewed()", function()
    it("returns false when review is disabled", function()
      config._config = { review = { enabled = false } }

      local result = review.mark_file_reviewed({}, {})
      assert.is_false(result)
    end)

    it("returns false when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.mark_file_reviewed(nil, { path = "test.lua" })
      assert.is_false(result)
    end)

    it("returns false when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local result = review.mark_file_reviewed({}, { path = "test.lua" })
      assert.is_false(result)
    end)

    it("returns false when file_entry is nil", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.mark_file_reviewed(mock_view, nil)
      assert.is_false(result)
    end)

    it("returns false when file_entry has no path", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.mark_file_reviewed(mock_view, {})
      assert.is_false(result)
    end)

    it("returns false when adapter cannot get blob hash", function()
      config._config = { review = { enabled = true } }

      local mock_review_state = {
        set_file_reviewed = function() end,
      }
      local mock_adapter = {
        file_blob_hash = function()
          return nil
        end,
        head_rev = function()
          return { commit = "abc123def456" }
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_false(result)
    end)

    it("returns true and marks file when everything is valid", function()
      config._config = { review = { enabled = true } }

      local marked_path, marked_hash, marked_commit = nil, nil, nil
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_path = path
          marked_hash = hash
          marked_commit = commit_hash
        end,
      }
      local mock_adapter = {
        file_blob_hash = function(_, path, rev)
          return "blob_hash_123"
        end,
        head_rev = function()
          return { commit = "commit_sha_456" }
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_true(result)
      assert.equals("src/test.lua", marked_path)
      assert.equals("blob_hash_123", marked_hash)
      assert.equals("commit_sha_456", marked_commit)
    end)

    it("stores nil commit_hash when head_rev returns nil", function()
      config._config = { review = { enabled = true } }

      local marked_commit = "not_set"
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_commit = commit_hash
        end,
      }
      local mock_adapter = {
        file_blob_hash = function()
          return "blob_hash_123"
        end,
        head_rev = function()
          return nil -- Simulates edge case where head_rev fails
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_true(result) -- Should still succeed with nil commit_hash
      assert.is_nil(marked_commit) -- commit_hash should be nil
    end)

    it("stores nil commit_hash when head_rev.commit is nil", function()
      config._config = { review = { enabled = true } }

      local marked_commit = "not_set"
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_commit = commit_hash
        end,
      }
      local mock_adapter = {
        file_blob_hash = function()
          return "blob_hash_123"
        end,
        head_rev = function()
          return { commit = nil } -- Rev object without commit field
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_true(result) -- Should still succeed with nil commit_hash
      assert.is_nil(marked_commit) -- commit_hash should be nil
    end)
  end)

  describe("mark_all_reviewed()", function()
    it("returns 0 when review is disabled", function()
      config._config = { review = { enabled = false } }

      local result = review.mark_all_reviewed({})
      assert.equals(0, result)
    end)

    it("returns 0 when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.mark_all_reviewed(nil)
      assert.equals(0, result)
    end)

    it("returns 0 when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local result = review.mark_all_reviewed({})
      assert.equals(0, result)
    end)

    it("returns 0 when view has no files", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.mark_all_reviewed(mock_view)
      assert.equals(0, result)
    end)

    it("marks all files and returns correct count", function()
      config._config = { review = { enabled = true } }

      local marked_files = {}
      local mock_store = { save_state = function() end }
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_files[path] = { hash = hash, commit_hash = commit_hash }
        end,
        store = mock_store,
      }
      -- Create a mock files object with an iter() method
      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/bar.lua" },
        { path = "tests/test.lua" },
      }
      local blob_hashes = {
        ["src/foo.lua"] = "hash111",
        ["src/bar.lua"] = "hash222",
        ["tests/test.lua"] = "hash333",
      }
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
      local mock_adapter = {
        file_blob_hash = function(_, path, rev)
          return blob_hashes[path]
        end,
        head_rev = function()
          return { commit = "head_commit_sha" }
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)
      assert.equals(3, result)
      assert.equals("hash111", marked_files["src/foo.lua"].hash)
      assert.equals("hash222", marked_files["src/bar.lua"].hash)
      assert.equals("hash333", marked_files["tests/test.lua"].hash)
      -- Verify all files share the same commit hash
      assert.equals("head_commit_sha", marked_files["src/foo.lua"].commit_hash)
      assert.equals("head_commit_sha", marked_files["src/bar.lua"].commit_hash)
      assert.equals("head_commit_sha", marked_files["tests/test.lua"].commit_hash)
    end)

    it("skips files that fail to get blob hash", function()
      config._config = { review = { enabled = true } }

      local marked_files = {}
      local mock_store = { save_state = function() end }
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_files[path] = hash
        end,
        store = mock_store,
      }
      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/deleted.lua" },
        { path = "src/bar.lua" },
      }
      local blob_hashes = {
        ["src/foo.lua"] = "hash111",
        ["src/deleted.lua"] = nil, -- Simulates a deleted file or error
        ["src/bar.lua"] = "hash333",
      }
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
      local mock_adapter = {
        file_blob_hash = function(_, path, rev)
          return blob_hashes[path]
        end,
        head_rev = function()
          return { commit = "head_commit_sha" }
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)
      assert.equals(2, result)
      assert.equals("hash111", marked_files["src/foo.lua"])
      assert.is_nil(marked_files["src/deleted.lua"])
      assert.equals("hash333", marked_files["src/bar.lua"])
    end)

    it("uses batch save: calls set_file_reviewed with skip_save=true and saves once at end", function()
      config._config = { review = { enabled = true } }

      -- Track how set_file_reviewed is called
      local set_file_calls = {}
      local save_state_calls = 0

      -- Mock store with save_state tracking
      local mock_store = {
        save_state = function()
          save_state_calls = save_state_calls + 1
        end,
      }

      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash, skip_save)
          table.insert(set_file_calls, {
            path = path,
            hash = hash,
            commit_hash = commit_hash,
            skip_save = skip_save,
          })
        end,
        store = mock_store,
      }

      local file_entries = {
        { path = "src/a.lua" },
        { path = "src/b.lua" },
        { path = "src/c.lua" },
      }
      local blob_hashes = {
        ["src/a.lua"] = "hash_a",
        ["src/b.lua"] = "hash_b",
        ["src/c.lua"] = "hash_c",
      }
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
      local mock_adapter = {
        file_blob_hash = function(_, path)
          return blob_hashes[path]
        end,
        head_rev = function()
          return { commit = "head_commit_sha" }
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)

      -- Verify all files were marked
      assert.equals(3, result)
      assert.equals(3, #set_file_calls)

      -- Verify each call used skip_save=true and has commit_hash
      for _, call in ipairs(set_file_calls) do
        assert.is_true(call.skip_save, "set_file_reviewed should be called with skip_save=true")
        assert.equals("head_commit_sha", call.commit_hash, "set_file_reviewed should pass commit_hash")
      end

      -- Verify save_state was called exactly once (at the end)
      assert.equals(1, save_state_calls, "save_state should be called exactly once for batch operation")
    end)

    it("does not call save_state when no files are marked", function()
      config._config = { review = { enabled = true } }

      local save_state_calls = 0
      local mock_store = {
        save_state = function()
          save_state_calls = save_state_calls + 1
        end,
      }
      local mock_review_state = {
        set_file_reviewed = function() end,
        store = mock_store,
      }

      -- All files fail to get blob hash
      local file_entries = {
        { path = "src/deleted1.lua" },
        { path = "src/deleted2.lua" },
      }
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
      local mock_adapter = {
        file_blob_hash = function()
          return nil -- All blob hash lookups fail
        end,
        head_rev = function()
          return { commit = "head_commit_sha" }
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)

      -- No files marked
      assert.equals(0, result)
      -- save_state should NOT be called since count is 0
      assert.equals(0, save_state_calls, "save_state should not be called when no files are marked")
    end)

    it("handles nil commit_hash when head_rev returns nil", function()
      config._config = { review = { enabled = true } }

      local marked_commits = {}
      local mock_store = { save_state = function() end }
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash, commit_hash)
          marked_commits[path] = commit_hash
        end,
        store = mock_store,
      }
      local file_entries = {
        { path = "src/foo.lua" },
        { path = "src/bar.lua" },
      }
      local blob_hashes = {
        ["src/foo.lua"] = "hash111",
        ["src/bar.lua"] = "hash222",
      }
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
      local mock_adapter = {
        file_blob_hash = function(_, path)
          return blob_hashes[path]
        end,
        head_rev = function()
          return nil -- Simulates edge case where head_rev fails
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)

      -- Files should still be marked even with nil commit_hash
      assert.equals(2, result)
      -- Both should have nil commit_hash
      assert.is_nil(marked_commits["src/foo.lua"])
      assert.is_nil(marked_commits["src/bar.lua"])
    end)
  end)

  describe("clear_file_review()", function()
    it("returns false when review is disabled", function()
      config._config = { review = { enabled = false } }

      local result = review.clear_file_review({}, {})
      assert.is_false(result)
    end)

    it("returns false when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_file_review(nil, { path = "test.lua" })
      assert.is_false(result)
    end)

    it("returns false when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_file_review({}, { path = "test.lua" })
      assert.is_false(result)
    end)

    it("returns false when file_entry is nil", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.clear_file_review(mock_view, nil)
      assert.is_false(result)
    end)

    it("returns false when file_entry has no path", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.clear_file_review(mock_view, {})
      assert.is_false(result)
    end)

    it("returns true and clears file when everything is valid", function()
      config._config = { review = { enabled = true } }

      local cleared_path = nil
      local mock_review_state = {
        clear_file = function(_, path)
          cleared_path = path
        end,
      }
      local mock_view = { review_state = mock_review_state }
      local file_entry = { path = "src/test.lua" }

      local result = review.clear_file_review(mock_view, file_entry)
      assert.is_true(result)
      assert.equals("src/test.lua", cleared_path)
    end)
  end)

  describe("clear_all_reviews()", function()
    it("returns false when review is disabled", function()
      config._config = { review = { enabled = false } }

      local result = review.clear_all_reviews({})
      assert.is_false(result)
    end)

    it("returns false when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_all_reviews(nil)
      assert.is_false(result)
    end)

    it("returns false when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local result = review.clear_all_reviews({})
      assert.is_false(result)
    end)

    it("returns true and clears all when review_state exists", function()
      config._config = { review = { enabled = true } }

      local cleared = false
      local mock_review_state = {
        clear_all = function(_)
          cleared = true
        end,
      }
      local mock_view = { review_state = mock_review_state }

      local result = review.clear_all_reviews(mock_view)
      assert.is_true(result)
      assert.is_true(cleared)
    end)
  end)

  describe("get_file_status()", function()
    it("returns nil when review is disabled", function()
      config._config = { review = { enabled = false } }

      local result = review.get_file_status({}, {})
      assert.is_nil(result)
    end)

    it("returns nil when view is nil", function()
      config._config = { review = { enabled = true } }

      local result = review.get_file_status(nil, { path = "test.lua" })
      assert.is_nil(result)
    end)

    it("returns nil when view has no review_state", function()
      config._config = { review = { enabled = true } }

      local result = review.get_file_status({}, { path = "test.lua" })
      assert.is_nil(result)
    end)

    it("returns nil when file_entry is nil", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.get_file_status(mock_view, nil)
      assert.is_nil(result)
    end)

    it("returns nil when file_entry has no path", function()
      config._config = { review = { enabled = true } }

      local mock_view = { review_state = {} }
      local result = review.get_file_status(mock_view, {})
      assert.is_nil(result)
    end)
  end)

  describe("get_store()", function()
    it("returns the ReviewStore singleton", function()
      local store = review.get_store()
      assert.is_not_nil(store)
      assert.is_table(store)
    end)

    it("returns the same instance on multiple calls", function()
      local store1 = review.get_store()
      local store2 = review.get_store()
      assert.equals(store1, store2)
    end)
  end)

  describe("event emission", function()
    local captured_events
    local event_listeners

    before_each(function()
      captured_events = {}
      event_listeners = {}
      -- Register event listeners
      local function capture_event(event_name)
        return function(_, payload)
          table.insert(captured_events, {
            name = event_name,
            payload = payload,
          })
        end
      end
      event_listeners.review_file_marked = capture_event("review_file_marked")
      event_listeners.review_file_cleared = capture_event("review_file_cleared")
      event_listeners.review_all_cleared = capture_event("review_all_cleared")

      DiffviewGlobal.emitter:on("review_file_marked", event_listeners.review_file_marked)
      DiffviewGlobal.emitter:on("review_file_cleared", event_listeners.review_file_cleared)
      DiffviewGlobal.emitter:on("review_all_cleared", event_listeners.review_all_cleared)
    end)

    after_each(function()
      -- Unregister event listeners
      DiffviewGlobal.emitter:off(event_listeners.review_file_marked)
      DiffviewGlobal.emitter:off(event_listeners.review_file_cleared)
      DiffviewGlobal.emitter:off(event_listeners.review_all_cleared)
    end)

    it("emits review_file_marked event when marking a file as reviewed", function()
      config._config = { review = { enabled = true } }

      local mock_review_state = {
        set_file_reviewed = function() end,
      }
      local mock_adapter = {
        file_blob_hash = function()
          return "blob_hash_123"
        end,
        head_rev = function()
          return { commit = "commit_sha_456" }
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_true(result)

      assert.equals(1, #captured_events)
      assert.equals("review_file_marked", captured_events[1].name)
      assert.equals(mock_view, captured_events[1].payload.view)
      assert.equals(file_entry, captured_events[1].payload.file_entry)
      assert.equals("blob_hash_123", captured_events[1].payload.blob_hash)
      assert.equals("commit_sha_456", captured_events[1].payload.commit_hash)
    end)

    it("emits review_file_marked for each file when marking all reviewed", function()
      config._config = { review = { enabled = true } }

      local mock_store = { save_state = function() end }
      local mock_review_state = {
        set_file_reviewed = function() end,
        store = mock_store,
      }
      local file_entries = {
        { path = "src/a.lua" },
        { path = "src/b.lua" },
      }
      local blob_hashes = {
        ["src/a.lua"] = "hash_a",
        ["src/b.lua"] = "hash_b",
      }
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
      local mock_adapter = {
        file_blob_hash = function(_, path)
          return blob_hashes[path]
        end,
        head_rev = function()
          return { commit = "commit_sha_all" }
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)
      assert.equals(2, result)

      -- Check that two events were emitted
      assert.equals(2, #captured_events)
      assert.equals("review_file_marked", captured_events[1].name)
      assert.equals("review_file_marked", captured_events[2].name)

      -- Verify event payloads contain correct data
      local event_paths = {}
      local event_hashes = {}
      for _, event in ipairs(captured_events) do
        event_paths[event.payload.file_entry.path] = true
        event_hashes[event.payload.file_entry.path] = event.payload.blob_hash
        -- Verify commit_hash is included in events
        assert.equals("commit_sha_all", event.payload.commit_hash)
      end
      assert.is_true(event_paths["src/a.lua"])
      assert.is_true(event_paths["src/b.lua"])
      assert.equals("hash_a", event_hashes["src/a.lua"])
      assert.equals("hash_b", event_hashes["src/b.lua"])
    end)

    it("emits review_file_cleared event when clearing a file review", function()
      config._config = { review = { enabled = true } }

      local mock_review_state = {
        clear_file = function() end,
      }
      local mock_view = { review_state = mock_review_state }
      local file_entry = { path = "src/cleared.lua" }

      local result = review.clear_file_review(mock_view, file_entry)
      assert.is_true(result)

      assert.equals(1, #captured_events)
      assert.equals("review_file_cleared", captured_events[1].name)
      assert.equals(mock_view, captured_events[1].payload.view)
      assert.equals(file_entry, captured_events[1].payload.file_entry)
    end)

    it("emits review_all_cleared event when clearing all reviews", function()
      config._config = { review = { enabled = true } }

      local mock_review_state = {
        clear_all = function() end,
      }
      local mock_view = { review_state = mock_review_state }

      local result = review.clear_all_reviews(mock_view)
      assert.is_true(result)

      assert.equals(1, #captured_events)
      assert.equals("review_all_cleared", captured_events[1].name)
      assert.equals(mock_view, captured_events[1].payload.view)
    end)

    it("does not emit events when operation fails", function()
      config._config = { review = { enabled = true } }

      -- No review_state - should fail
      local result = review.mark_file_reviewed({}, { path = "test.lua" })
      assert.is_false(result)
      assert.equals(0, #captured_events)

      -- No blob hash - should fail
      local mock_review_state = { set_file_reviewed = function() end }
      local mock_adapter = {
        file_blob_hash = function() return nil end,
        head_rev = function() return { commit = "commit_sha" } end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      result = review.mark_file_reviewed(mock_view, { path = "test.lua" })
      assert.is_false(result)
      assert.equals(0, #captured_events)
    end)
  end)
end)

describe("diffview module integration", function()
  it("exposes review API via require('diffview').review", function()
    local diffview = require("diffview")
    assert.is_not_nil(diffview.review)
    assert.is_table(diffview.review)
  end)

  it("review API has all expected functions", function()
    local diffview = require("diffview")
    assert.is_function(diffview.review.mark_file_reviewed)
    assert.is_function(diffview.review.mark_all_reviewed)
    assert.is_function(diffview.review.clear_file_review)
    assert.is_function(diffview.review.clear_all_reviews)
    assert.is_function(diffview.review.get_file_status)
    assert.is_function(diffview.review.get_store)
    assert.is_function(diffview.review.cleanup_stale_reviews)
    assert.is_function(diffview.review.get_cleanup_preview)
  end)
end)

describe("review status caching", function()
  local review_store_mod = require("diffview.review_store")

  describe("DiffView cache behavior", function()
    -- Helper to create a mock DiffView-like object for cache testing
    local function create_mock_diff_view(options)
      options = options or {}

      local mock_files = options.files or {}
      local mock_review_files = options.review_files or {}

      local mock = {
        review_state = nil,  -- Will be set below if review enabled
        review_status_cache = nil,
        review_status_cache_head = nil,
        review_status_cache_valid = false,
        files = {
          iter = function()
            local idx = 0
            return function()
              idx = idx + 1
              if idx <= #mock_files then
                return idx, mock_files[idx]
              end
            end
          end,
        },
        adapter = {
          head_rev = function()
            return { commit = options.head_commit or "abc123" }
          end,
          file_blob_hash = function(_, path, rev)
            options.file_blob_hash_calls = (options.file_blob_hash_calls or 0) + 1
            return options.blob_hashes and options.blob_hashes[path]
          end,
          file_blob_hashes_batch = function(_, paths, rev)
            options.batch_calls = (options.batch_calls or 0) + 1
            options.batch_paths = paths
            local result = {}
            for _, path in ipairs(paths) do
              result[path] = options.blob_hashes and options.blob_hashes[path]
            end
            return result
          end,
        },
      }

      -- Add mock review_state if review files provided
      if next(mock_review_files) then
        local mock_store = { save_state = function() end }
        mock.review_state = review_store_mod.ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = mock_store,
          files = mock_review_files,
        })
      end

      -- Import DiffView methods (we'll call them with mock as self)
      local DiffView = require("diffview.scene.views.diff.diff_view").DiffView

      -- Copy cache methods to mock (bound to mock)
      mock.invalidate_review_status_cache = function(self, reason)
        DiffView.invalidate_review_status_cache(self, reason)
      end
      mock.rebuild_review_status_cache = function(self)
        DiffView.rebuild_review_status_cache(self)
      end
      mock.ensure_review_status_cache = function(self)
        DiffView.ensure_review_status_cache(self)
      end
      mock.get_cached_review_status = function(self, file_entry)
        return DiffView.get_cached_review_status(self, file_entry)
      end

      return mock, options
    end

    it("rebuild_review_status_cache uses batch lookup for paths needing blob comparison", function()
      local mock_files = {
        { path = "src/a.lua" },
        { path = "src/b.lua" },
        { path = "src/c.lua" },
      }
      local mock_review_files = {
        ["src/a.lua"] = { blob_hash = "hash_a", reviewed_at = os.time() },
        ["src/b.lua"] = { blob_hash = "hash_b", reviewed_at = os.time() },
        -- src/c.lua is unreviewed
      }
      local blob_hashes = {
        ["src/a.lua"] = "hash_a",  -- Same hash = reviewed
        ["src/b.lua"] = "hash_b_new",  -- Different hash = changed
      }
      local options = {
        files = mock_files,
        review_files = mock_review_files,
        blob_hashes = blob_hashes,
        head_commit = "commit_xyz",
      }
      local mock = create_mock_diff_view(options)

      mock:rebuild_review_status_cache()

      -- Verify cache was built
      assert.is_true(mock.review_status_cache_valid)
      assert.equals("commit_xyz", mock.review_status_cache_head)

      -- Verify statuses are correct
      assert.equals("reviewed", mock.review_status_cache["src/a.lua"])
      assert.equals("changed", mock.review_status_cache["src/b.lua"])
      assert.equals("unreviewed", mock.review_status_cache["src/c.lua"])

      -- Verify batch was called (not per-file calls)
      assert.equals(1, options.batch_calls)
      -- Only paths with review entries (needing blob comparison) should be in batch
      assert.equals(2, #options.batch_paths)
    end)

    it("rebuild_review_status_cache uses commit_hash short-circuit", function()
      local mock_files = {
        { path = "src/a.lua" },
        { path = "src/b.lua" },
        { path = "src/c.lua" },
      }
      local head_commit = "head_abc123"
      local mock_review_files = {
        ["src/a.lua"] = {
          blob_hash = "old_hash",
          reviewed_at = os.time(),
          commit_hash = head_commit,  -- Matches HEAD - should short-circuit
        },
        ["src/b.lua"] = {
          blob_hash = "hash_b",
          reviewed_at = os.time(),
          commit_hash = "other_commit",  -- Different commit - needs blob lookup
        },
        -- src/c.lua is unreviewed
      }
      local blob_hashes = {
        ["src/b.lua"] = "hash_b",  -- Same as reviewed hash
      }
      local options = {
        files = mock_files,
        review_files = mock_review_files,
        blob_hashes = blob_hashes,
        head_commit = head_commit,
      }
      local mock = create_mock_diff_view(options)

      mock:rebuild_review_status_cache()

      -- Verify statuses
      assert.equals("reviewed", mock.review_status_cache["src/a.lua"])  -- Short-circuited
      assert.equals("reviewed", mock.review_status_cache["src/b.lua"])  -- Blob hash matched
      assert.equals("unreviewed", mock.review_status_cache["src/c.lua"])

      -- Only src/b.lua should have been in the batch (src/a.lua was short-circuited)
      assert.equals(1, options.batch_calls)
      assert.equals(1, #options.batch_paths)
      assert.equals("src/b.lua", options.batch_paths[1])
    end)

    it("invalidate_review_status_cache marks cache as invalid", function()
      local mock = create_mock_diff_view({
        files = { { path = "test.lua" } },
        review_files = {},
      })

      -- Build cache first
      mock.review_status_cache = { ["test.lua"] = "reviewed" }
      mock.review_status_cache_head = "some_commit"
      mock.review_status_cache_valid = true

      -- Invalidate
      mock:invalidate_review_status_cache("test_reason")

      -- Cache should be marked invalid but not cleared
      assert.is_false(mock.review_status_cache_valid)
      -- Cache data is still there (lazy rebuild)
      assert.is_not_nil(mock.review_status_cache)
    end)

    it("ensure_review_status_cache rebuilds when invalid", function()
      local mock_files = { { path = "src/test.lua" } }
      -- Need at least one review file to create review_state
      local mock_review_files = {
        ["src/other.lua"] = { blob_hash = "hash_other", reviewed_at = os.time() },
      }
      local options = {
        files = mock_files,
        review_files = mock_review_files,
        head_commit = "commit_123",
      }
      local mock = create_mock_diff_view(options)

      -- Start with invalid cache
      assert.is_false(mock.review_status_cache_valid)

      -- Ensure cache
      mock:ensure_review_status_cache()

      -- Should have rebuilt
      assert.is_true(mock.review_status_cache_valid)
      assert.equals("unreviewed", mock.review_status_cache["src/test.lua"])
    end)

    it("ensure_review_status_cache does not rebuild when valid", function()
      local options = {
        files = { { path = "src/test.lua" } },
        review_files = {},
        head_commit = "commit_123",
      }
      local mock = create_mock_diff_view(options)

      -- Build cache manually
      mock.review_status_cache = { ["src/test.lua"] = "reviewed" }
      mock.review_status_cache_head = "commit_123"
      mock.review_status_cache_valid = true

      -- Ensure cache (should not rebuild)
      mock:ensure_review_status_cache()

      -- Should still have original data
      assert.equals("reviewed", mock.review_status_cache["src/test.lua"])
      -- No batch calls should have happened
      assert.is_nil(options.batch_calls)
    end)

    it("get_cached_review_status returns nil when no review_state", function()
      local mock = create_mock_diff_view({
        files = { { path = "test.lua" } },
        review_files = {},  -- This creates review_state
      })
      mock.review_state = nil  -- Remove it

      local status = mock:get_cached_review_status({ path = "test.lua" })
      assert.is_nil(status)
    end)

    it("get_cached_review_status returns cached status after rebuild", function()
      local mock_files = { { path = "src/foo.lua" } }
      local mock_review_files = {
        ["src/foo.lua"] = { blob_hash = "hash_123", reviewed_at = os.time() },
      }
      local options = {
        files = mock_files,
        review_files = mock_review_files,
        blob_hashes = { ["src/foo.lua"] = "hash_123" },
        head_commit = "commit_abc",
      }
      local mock = create_mock_diff_view(options)

      local status = mock:get_cached_review_status({ path = "src/foo.lua" })
      assert.equals("reviewed", status)

      -- Should have triggered rebuild
      assert.is_true(mock.review_status_cache_valid)
    end)

    it("rebuild handles empty file list", function()
      -- Need review_state for rebuild to proceed
      local mock_review_files = {
        ["src/other.lua"] = { blob_hash = "hash_other", reviewed_at = os.time() },
      }
      local options = {
        files = {},  -- Empty file list
        review_files = mock_review_files,
        head_commit = "commit_123",
      }
      local mock = create_mock_diff_view(options)

      mock:rebuild_review_status_cache()

      assert.is_true(mock.review_status_cache_valid)
      assert.equals("commit_123", mock.review_status_cache_head)
      -- No batch calls for empty list
      assert.is_nil(options.batch_calls)
    end)

    it("rebuild handles files with no paths gracefully", function()
      -- Need review_state for rebuild to proceed
      local mock_review_files = {
        ["src/other.lua"] = { blob_hash = "hash_other", reviewed_at = os.time() },
      }
      local options = {
        files = { { path = "valid.lua" }, { name = "no_path_file" }, { path = nil } },
        review_files = mock_review_files,
        head_commit = "commit_123",
      }
      local mock = create_mock_diff_view(options)

      mock:rebuild_review_status_cache()

      assert.is_true(mock.review_status_cache_valid)
      -- Only valid.lua should be in cache
      assert.equals("unreviewed", mock.review_status_cache["valid.lua"])
    end)
  end)

  describe("commit_hash short-circuit", function()
    it("treats file as reviewed when commit_hash matches HEAD", function()
      -- Create a mock ReviewState with a file that has matching commit_hash
      local mock_store = { save_state = function() end }
      local review_state = review_store_mod.ReviewState({
        repo_id = "test-repo",
        branch = "main",
        store = mock_store,
        files = {
          ["src/foo.lua"] = {
            blob_hash = "old_blob_hash",  -- Different from current
            reviewed_at = os.time(),
            commit_hash = "abc123",  -- Will match HEAD
          },
        },
      })

      -- When commit_hash matches, status should be "reviewed" regardless of blob_hash
      -- This is tested via the cache rebuild logic
      assert.equals("reviewed", review_state:get_file_status("src/foo.lua", "old_blob_hash"))
    end)

    it("uses blob_hash comparison when commit_hash is missing", function()
      local mock_store = { save_state = function() end }
      local review_state = review_store_mod.ReviewState({
        repo_id = "test-repo",
        branch = "main",
        store = mock_store,
        files = {
          ["src/foo.lua"] = {
            blob_hash = "blob_hash_123",
            reviewed_at = os.time(),
            -- No commit_hash - legacy entry
          },
        },
      })

      -- Should use blob_hash comparison
      assert.equals("reviewed", review_state:get_file_status("src/foo.lua", "blob_hash_123"))
      assert.equals("changed", review_state:get_file_status("src/foo.lua", "different_hash"))
    end)

    it("uses blob_hash comparison when commit_hash differs from HEAD", function()
      local mock_store = { save_state = function() end }
      local review_state = review_store_mod.ReviewState({
        repo_id = "test-repo",
        branch = "main",
        store = mock_store,
        files = {
          ["src/foo.lua"] = {
            blob_hash = "blob_hash_123",
            reviewed_at = os.time(),
            commit_hash = "old_commit",  -- Different from HEAD
          },
        },
      })

      -- When commit_hash doesn't match HEAD, fall back to blob_hash comparison
      assert.equals("reviewed", review_state:get_file_status("src/foo.lua", "blob_hash_123"))
      assert.equals("changed", review_state:get_file_status("src/foo.lua", "new_blob_hash"))
    end)
  end)

  describe("get_file_status with caching", function()
    it("uses view's cached method when available", function()
      config._config = { review = { enabled = true } }

      local cached_status_calls = 0
      local mock_view = {
        review_state = {},
        get_cached_review_status = function(_, file_entry)
          cached_status_calls = cached_status_calls + 1
          return "reviewed"
        end,
      }

      local result = review.get_file_status(mock_view, { path = "test.lua" })
      assert.equals("reviewed", result)
      assert.equals(1, cached_status_calls)
    end)

    it("falls back to direct lookup when cache method is unavailable", function()
      config._config = { review = { enabled = true } }

      local direct_calls = 0
      local mock_review_state = {
        get_file_status = function(_, path, blob_hash)
          direct_calls = direct_calls + 1
          return "unreviewed"
        end,
      }
      local mock_adapter = {
        file_blob_hash = function()
          return "some_hash"
        end,
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        -- No get_cached_review_status method
      }

      local result = review.get_file_status(mock_view, { path = "test.lua" })
      assert.equals("unreviewed", result)
      assert.equals(1, direct_calls)
    end)
  end)
end)
