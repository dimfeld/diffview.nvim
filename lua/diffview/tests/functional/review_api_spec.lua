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
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_false(result)
    end)

    it("returns true and marks file when everything is valid", function()
      config._config = { review = { enabled = true } }

      local marked_path, marked_hash = nil, nil
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash)
          marked_path = path
          marked_hash = hash
        end,
      }
      local mock_adapter = {
        file_blob_hash = function(_, path, rev)
          return "abc123def456"
        end,
      }
      local mock_view = { review_state = mock_review_state, adapter = mock_adapter }
      local file_entry = { path = "src/test.lua" }

      local result = review.mark_file_reviewed(mock_view, file_entry)
      assert.is_true(result)
      assert.equals("src/test.lua", marked_path)
      assert.equals("abc123def456", marked_hash)
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
        set_file_reviewed = function(_, path, hash)
          marked_files[path] = hash
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
      }
      local mock_view = {
        review_state = mock_review_state,
        adapter = mock_adapter,
        files = mock_files,
      }

      local result = review.mark_all_reviewed(mock_view)
      assert.equals(3, result)
      assert.equals("hash111", marked_files["src/foo.lua"])
      assert.equals("hash222", marked_files["src/bar.lua"])
      assert.equals("hash333", marked_files["tests/test.lua"])
    end)

    it("skips files that fail to get blob hash", function()
      config._config = { review = { enabled = true } }

      local marked_files = {}
      local mock_store = { save_state = function() end }
      local mock_review_state = {
        set_file_reviewed = function(_, path, hash)
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
        set_file_reviewed = function(_, path, hash, skip_save)
          table.insert(set_file_calls, {
            path = path,
            hash = hash,
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

      -- Verify each call used skip_save=true
      for _, call in ipairs(set_file_calls) do
        assert.is_true(call.skip_save, "set_file_reviewed should be called with skip_save=true")
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
      local mock_adapter = { file_blob_hash = function() return nil end }
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
  end)
end)
