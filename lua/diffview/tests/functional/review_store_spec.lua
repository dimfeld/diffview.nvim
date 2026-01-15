local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq
local async_test = helpers.async_test

local uv = vim.loop

describe("diffview.review_store", function()
  local review_store = require("diffview.review_store")
  local ReviewStore = review_store.ReviewStore
  local ReviewState = review_store.ReviewState

  describe("ReviewStore:sanitize_branch()", function()
    it("replaces slashes with double underscores", function()
      local store = ReviewStore()

      eq("main", store:sanitize_branch("main"))
      eq("feature__add-login", store:sanitize_branch("feature/add-login"))
      eq("feature__nested__branch", store:sanitize_branch("feature/nested/branch"))
      eq("no-slashes", store:sanitize_branch("no-slashes"))
    end)

    it("handles edge cases", function()
      local store = ReviewStore()

      -- Empty string
      eq("", store:sanitize_branch(""))
      -- Only slashes
      eq("____", store:sanitize_branch("//"))
      -- Leading/trailing slashes
      eq("__branch__", store:sanitize_branch("/branch/"))
      -- Unicode characters in branch names
      eq("feature__bug-fix", store:sanitize_branch("feature/bug-fix"))
    end)
  end)

  describe("ReviewStore:get_cache_dir()", function()
    it("returns default cache directory when not configured", function()
      local store = ReviewStore()
      local cache_dir = store:get_cache_dir()

      -- Should contain the default path (with ~ expanded)
      assert(cache_dir:match("diffview%.nvim/reviews$"), "Expected default cache path")
    end)
  end)

  describe("ReviewStore:get_state_path()", function()
    it("returns correct path for repo and branch", function()
      local store = ReviewStore()
      local path = store:get_state_path("abc123def456", "feature/foo")

      -- Should end with repo_id/sanitized_branch.json
      assert(path:match("abc123def456/feature__foo%.json$"), "Expected correct state path")
    end)
  end)

  describe("ReviewState", function()
    local store

    before_each(function()
      store = ReviewStore()
      -- Override save_state to prevent actual file writes in tests
      store.save_state = function() end
    end)

    describe(":get_file()", function()
      it("returns nil for unreviewed files", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        eq(nil, state:get_file("some/file.lua"))
      end)

      it("returns entry for reviewed files", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        local entry = state:get_file("src/foo.lua")
        neq(nil, entry)
        eq("abc123", entry.blob_hash)
        eq(1705276800, entry.reviewed_at)
      end)
    end)

    describe(":set_file_reviewed()", function()
      it("stores the blob hash and timestamp", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        state:set_file_reviewed("src/bar.lua", "def456")

        local entry = state:get_file("src/bar.lua")
        neq(nil, entry)
        eq("def456", entry.blob_hash)
        assert(entry.reviewed_at > 0, "Expected positive timestamp")
      end)

      it("marks state as dirty", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        eq(false, state.dirty)
        state:set_file_reviewed("src/bar.lua", "def456")
        eq(true, state.dirty)
      end)
    end)

    describe(":clear_file()", function()
      it("removes the entry for a reviewed file", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        neq(nil, state:get_file("src/foo.lua"))
        state:clear_file("src/foo.lua")
        eq(nil, state:get_file("src/foo.lua"))
      end)

      it("does nothing for non-existent files", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        -- Should not error
        state:clear_file("non/existent.lua")
      end)

      it("does not mark state dirty when file doesn't exist", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        eq(false, state.dirty)
        state:clear_file("non/existent.lua")
        eq(false, state.dirty)
      end)

      it("marks state dirty when file exists", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        eq(false, state.dirty)
        state:clear_file("src/foo.lua")
        eq(true, state.dirty)
      end)
    end)

    describe(":clear_all()", function()
      it("removes all review entries", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
            ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = 1705276801 },
          },
        })

        neq(nil, state:get_file("src/foo.lua"))
        neq(nil, state:get_file("src/bar.lua"))

        state:clear_all()

        eq(nil, state:get_file("src/foo.lua"))
        eq(nil, state:get_file("src/bar.lua"))
      end)
    end)

    describe(":get_file_status()", function()
      it("returns 'unreviewed' for files not in state", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
        })

        eq("unreviewed", state:get_file_status("src/foo.lua", "abc123"))
      end)

      it("returns 'reviewed' when blob hash matches", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        eq("reviewed", state:get_file_status("src/foo.lua", "abc123"))
      end)

      it("returns 'reviewed' when current blob hash is nil", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        eq("reviewed", state:get_file_status("src/foo.lua", nil))
      end)

      it("returns 'changed' when blob hash differs", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        })

        eq("changed", state:get_file_status("src/foo.lua", "def456"))
      end)
    end)

    describe(":to_table() and from_table()", function()
      it("serializes and deserializes correctly", function()
        local original = ReviewState({
          repo_id = "test-repo",
          branch = "feature/foo",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
            ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = 1705276801 },
          },
        })

        local data = original:to_table()
        eq(1, data.version)
        eq("test-repo", data.repo_id)
        eq("feature/foo", data.branch)
        eq("abc123", data.files["src/foo.lua"].blob_hash)

        local restored = ReviewState.from_table(data, store)
        eq("test-repo", restored.repo_id)
        eq("feature/foo", restored.branch)
        eq("abc123", restored:get_file("src/foo.lua").blob_hash)
        eq("def456", restored:get_file("src/bar.lua").blob_hash)
      end)

      it("roundtrips through JSON encoding", function()
        local original = ReviewState({
          repo_id = "test-repo-123",
          branch = "main",
          store = store,
          files = {
            ["path/to/file.lua"] = { blob_hash = "deadbeef", reviewed_at = 1234567890 },
          },
        })

        local json_str = vim.json.encode(original:to_table())
        local decoded = vim.json.decode(json_str)
        local restored = ReviewState.from_table(decoded, store)

        eq("test-repo-123", restored.repo_id)
        eq("main", restored.branch)
        eq("deadbeef", restored:get_file("path/to/file.lua").blob_hash)
        eq(1234567890, restored:get_file("path/to/file.lua").reviewed_at)
      end)

      it("handles nil files in from_table", function()
        local data = {
          version = 1,
          repo_id = "test-repo",
          branch = "main",
          files = nil,
        }
        local restored = ReviewState.from_table(data, store)

        eq("test-repo", restored.repo_id)
        eq("main", restored.branch)
        eq(nil, restored:get_file("any/file.lua"))
      end)

      it("handles empty files in from_table", function()
        local data = {
          version = 1,
          repo_id = "test-repo",
          branch = "main",
          files = {},
        }
        local restored = ReviewState.from_table(data, store)

        eq("test-repo", restored.repo_id)
        eq("main", restored.branch)
        eq(nil, restored:get_file("any/file.lua"))
      end)

      it("returns empty state with warning for unsupported version", function()
        local data = {
          version = 999, -- Unsupported future version
          repo_id = "test-repo",
          branch = "main",
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        }
        local restored = ReviewState.from_table(data, store)

        -- Should return state with empty files due to unsupported version
        eq("test-repo", restored.repo_id)
        eq("main", restored.branch)
        eq(nil, restored:get_file("src/foo.lua")) -- Files should be discarded
      end)

      it("accepts version 1 data normally", function()
        local data = {
          version = 1,
          repo_id = "test-repo",
          branch = "main",
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        }
        local restored = ReviewState.from_table(data, store)

        eq("test-repo", restored.repo_id)
        eq("main", restored.branch)
        eq("abc123", restored:get_file("src/foo.lua").blob_hash)
      end)

      it("handles missing version field (backwards compatibility)", function()
        local data = {
          repo_id = "test-repo",
          branch = "main",
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
          },
        }
        local restored = ReviewState.from_table(data, store)

        -- Missing version should be treated as valid (for backwards compatibility)
        eq("test-repo", restored.repo_id)
        eq("main", restored.branch)
        eq("abc123", restored:get_file("src/foo.lua").blob_hash)
      end)
    end)

    describe("updating existing file", function()
      it("overwrites previous review entry when re-marking a file", function()
        local state = ReviewState({
          repo_id = "test-repo",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "old_hash", reviewed_at = 1705276800 },
          },
        })

        eq("old_hash", state:get_file("src/foo.lua").blob_hash)
        state:set_file_reviewed("src/foo.lua", "new_hash")
        eq("new_hash", state:get_file("src/foo.lua").blob_hash)
        -- Timestamp should be updated too
        assert(state:get_file("src/foo.lua").reviewed_at > 1705276800, "Expected updated timestamp")
      end)
    end)
  end)

  -- Integration tests for file I/O operations
  describe("File I/O integration tests", function()
    local test_cache_dir = "/tmp/claude/diffview_test_" .. os.time()
    local store

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

    -- Helper to read a file synchronously
    local function read_file(path)
      local stat = uv.fs_stat(path)
      if not stat then return nil end
      local fd = assert(uv.fs_open(path, "r", 438))
      local content = assert(uv.fs_read(fd, stat.size, 0))
      assert(uv.fs_close(fd))
      return content
    end

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

    describe("ensure_cache_dir()", function()
      it("creates the cache directory structure", async_test(function()
        local async = require("diffview.async")
        local repo_id = "test_repo_123"

        -- Directory should not exist initially
        local stat_before = uv.fs_stat(test_cache_dir .. "/" .. repo_id)
        eq(nil, stat_before)

        -- Create the directory
        async.await(store:ensure_cache_dir(repo_id))

        -- Directory should now exist
        local stat_after = uv.fs_stat(test_cache_dir .. "/" .. repo_id)
        neq(nil, stat_after)
        eq("directory", stat_after.type)
      end))

      it("succeeds when directory already exists", async_test(function()
        local async = require("diffview.async")
        local repo_id = "existing_repo"

        -- Create the directory first
        uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
        uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

        -- Should not error when calling ensure_cache_dir
        async.await(store:ensure_cache_dir(repo_id))

        -- Directory should still exist
        local stat = uv.fs_stat(test_cache_dir .. "/" .. repo_id)
        neq(nil, stat)
        eq("directory", stat.type)
      end))
    end)

    describe("save_state()", function()
      it("saves state to disk as JSON", async_test(function()
        local async = require("diffview.async")

        -- Create a state with some reviewed files
        local state = ReviewState({
          repo_id = "test_repo_save",
          branch = "main",
          store = store,
          files = {
            ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = 1705276800 },
            ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = 1705276801 },
          },
        })

        -- Save the state
        async.await(store:save_state(state))

        -- Verify the file was created
        local state_path = store:get_state_path("test_repo_save", "main")
        local content = read_file(state_path)
        neq(nil, content)

        -- Verify the content is valid JSON
        local decoded = vim.json.decode(content)
        eq(1, decoded.version)
        eq("test_repo_save", decoded.repo_id)
        eq("main", decoded.branch)
        eq("abc123", decoded.files["src/foo.lua"].blob_hash)
        eq("def456", decoded.files["src/bar.lua"].blob_hash)
      end))

      it("clears dirty flag after saving", async_test(function()
        local async = require("diffview.async")

        local state = ReviewState({
          repo_id = "test_repo_dirty",
          branch = "main",
          store = store,
        })

        state.dirty = true
        async.await(store:save_state(state))
        eq(false, state.dirty)
      end))

      it("handles branch names with slashes", async_test(function()
        local async = require("diffview.async")

        local state = ReviewState({
          repo_id = "test_repo_slash",
          branch = "feature/add-login",
          store = store,
          files = {
            ["src/auth.lua"] = { blob_hash = "auth123", reviewed_at = 1705276800 },
          },
        })

        async.await(store:save_state(state))

        -- Verify file was created with sanitized name
        local state_path = store:get_state_path("test_repo_slash", "feature/add-login")
        assert(state_path:match("feature__add%-login%.json$"), "Expected sanitized branch name in path")

        local content = read_file(state_path)
        neq(nil, content)

        local decoded = vim.json.decode(content)
        eq("feature/add-login", decoded.branch) -- Original branch name in data
      end))
    end)

    describe("load_state_sync()", function()
      -- Create a mock adapter for testing
      -- The hash must be at least 12 characters since we take first 12
      local function create_mock_adapter(hash_prefix)
        -- Ensure hash_prefix is exactly 12 characters by padding with zeros
        local padded_hash = hash_prefix .. string.rep("0", math.max(0, 12 - #hash_prefix))
        return {
          ctx = {
            toplevel = "/mock/repo/" .. hash_prefix,
          },
          exec_sync = function(self, args, opts)
            -- Simulate git rev-list --max-parents=0 HEAD
            if args[1] == "rev-list" and args[2] == "--max-parents=0" then
              return { padded_hash .. "abcdef1234" }, 0
            end
            return {}, 1
          end,
          _expected_repo_id = padded_hash:sub(1, 12),
        }
      end

      it("returns empty state when file does not exist", function()
        local adapter = create_mock_adapter("nonexistent")

        local state = store:load_state_sync(adapter, "main")

        eq(adapter._expected_repo_id, state.repo_id)
        eq("main", state.branch)
        eq(nil, state:get_file("any/file.lua"))
      end)

      it("loads persisted state from disk (roundtrip test)", async_test(function()
        local async = require("diffview.async")

        local adapter = create_mock_adapter("roundtrip00")
        local expected_repo_id = adapter._expected_repo_id

        -- First, save a state
        local original_state = ReviewState({
          repo_id = expected_repo_id,
          branch = "develop",
          store = store,
          files = {
            ["src/main.lua"] = { blob_hash = "main123", reviewed_at = 1705276800 },
            ["src/utils.lua"] = { blob_hash = "utils456", reviewed_at = 1705276801 },
            ["tests/test.lua"] = { blob_hash = "test789", reviewed_at = 1705276802 },
          },
        })

        async.await(store:save_state(original_state))

        -- Clear the repo_id_cache to force fresh lookup
        store.repo_id_cache = {}

        -- Now load it back
        local loaded_state = store:load_state_sync(adapter, "develop")

        eq(expected_repo_id, loaded_state.repo_id)
        eq("develop", loaded_state.branch)
        eq("main123", loaded_state:get_file("src/main.lua").blob_hash)
        eq("utils456", loaded_state:get_file("src/utils.lua").blob_hash)
        eq("test789", loaded_state:get_file("tests/test.lua").blob_hash)
        eq(1705276800, loaded_state:get_file("src/main.lua").reviewed_at)
      end))

      it("handles malformed JSON gracefully", function()
        local adapter = create_mock_adapter("malformed000")
        local repo_id = adapter._expected_repo_id

        -- Create the directory and write malformed JSON
        uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
        uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
        local state_path = store:get_state_path(repo_id, "main")
        write_file(state_path, "{ this is not valid json }")

        -- Should return empty state instead of crashing
        local state = store:load_state_sync(adapter, "main")

        eq(repo_id, state.repo_id)
        eq("main", state.branch)
        eq(nil, state:get_file("any/file.lua"))
      end)

      it("handles empty file gracefully", function()
        local adapter = create_mock_adapter("emptyfile00")
        local repo_id = adapter._expected_repo_id

        -- Create the directory and write an empty file
        uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
        uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
        local state_path = store:get_state_path(repo_id, "main")
        write_file(state_path, "")

        -- Should return empty state instead of crashing
        local state = store:load_state_sync(adapter, "main")

        eq(repo_id, state.repo_id)
        eq("main", state.branch)
        eq(nil, state:get_file("any/file.lua"))
      end)

      it("handles truncated JSON gracefully", function()
        local adapter = create_mock_adapter("truncated00")
        local repo_id = adapter._expected_repo_id

        -- Create the directory and write truncated JSON
        uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
        uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
        local state_path = store:get_state_path(repo_id, "main")
        write_file(state_path, '{"version": 1, "repo_id": "' .. repo_id .. '", "branch": "main", "files": {')

        -- Should return empty state instead of crashing
        local state = store:load_state_sync(adapter, "main")

        eq(repo_id, state.repo_id)
        eq("main", state.branch)
        eq(nil, state:get_file("any/file.lua"))
      end)
    end)

    describe("get_repo_id()", function()
      it("returns first 12 characters of initial commit hash", function()
        local adapter = {
          ctx = {
            toplevel = "/mock/test/repo",
          },
          exec_sync = function(self, args, opts)
            if args[1] == "rev-list" and args[2] == "--max-parents=0" then
              return { "abcdef1234567890fedcba0987654321" }, 0
            end
            return {}, 1
          end,
        }

        local repo_id = store:get_repo_id(adapter)
        eq("abcdef123456", repo_id)
      end)

      it("caches repo_id per toplevel path", function()
        local call_count = 0
        local adapter = {
          ctx = {
            toplevel = "/cached/repo",
          },
          exec_sync = function(self, args, opts)
            call_count = call_count + 1
            if args[1] == "rev-list" and args[2] == "--max-parents=0" then
              return { "cached12345678901234567890" }, 0
            end
            return {}, 1
          end,
        }

        -- First call should hit git
        local repo_id1 = store:get_repo_id(adapter)
        eq("cached123456", repo_id1)
        eq(1, call_count)

        -- Second call should use cache
        local repo_id2 = store:get_repo_id(adapter)
        eq("cached123456", repo_id2)
        eq(1, call_count) -- Should still be 1
      end)

      it("returns nil on git failure", function()
        local adapter = {
          ctx = {
            toplevel = "/failing/repo",
          },
          exec_sync = function(self, args, opts)
            return {}, 128 -- Git error
          end,
        }

        local repo_id = store:get_repo_id(adapter)
        eq(nil, repo_id)
      end)

      it("handles empty output from git", function()
        local adapter = {
          ctx = {
            toplevel = "/empty/output/repo",
          },
          exec_sync = function(self, args, opts)
            return {}, 0 -- Success but empty output
          end,
        }

        local repo_id = store:get_repo_id(adapter)
        eq(nil, repo_id)
      end)

      it("handles whitespace in git output", function()
        local adapter = {
          ctx = {
            toplevel = "/whitespace/repo",
          },
          exec_sync = function(self, args, opts)
            if args[1] == "rev-list" and args[2] == "--max-parents=0" then
              return { "  whitespace123456789012  \n" }, 0
            end
            return {}, 1
          end,
        }

        local repo_id = store:get_repo_id(adapter)
        eq("whitespace12", repo_id)
      end)
    end)

    describe("verify_blob_exists()", function()
      it("returns true when blob exists", function()
        local adapter = {
          ctx = {
            toplevel = "/test/repo",
          },
          exec_sync = function(self, args, opts)
            if args[1] == "cat-file" and args[2] == "-e" then
              eq("abc123def456", args[3])
              return {}, 0 -- Success, blob exists
            end
            return {}, 1
          end,
        }

        local exists = store:verify_blob_exists(adapter, "abc123def456")
        eq(true, exists)
      end)

      it("returns false when blob does not exist (garbage collected)", function()
        local adapter = {
          ctx = {
            toplevel = "/test/repo",
          },
          exec_sync = function(self, args, opts)
            if args[1] == "cat-file" and args[2] == "-e" then
              return { "fatal: Not a valid object name" }, 128 -- Git error, blob not found
            end
            return {}, 1
          end,
        }

        local exists = store:verify_blob_exists(adapter, "nonexistent123")
        eq(false, exists)
      end)

      it("returns false on git failure", function()
        local adapter = {
          ctx = {
            toplevel = "/test/repo",
          },
          exec_sync = function(self, args, opts)
            return {}, 1 -- General failure
          end,
        }

        local exists = store:verify_blob_exists(adapter, "anyhash123")
        eq(false, exists)
      end)

      it("passes the blob hash correctly to git command", function()
        local received_hash = nil
        local adapter = {
          ctx = {
            toplevel = "/test/repo",
          },
          exec_sync = function(self, args, opts)
            if args[1] == "cat-file" and args[2] == "-e" then
              received_hash = args[3]
              return {}, 0
            end
            return {}, 1
          end,
        }

        store:verify_blob_exists(adapter, "deadbeef12345678")
        eq("deadbeef12345678", received_hash)
      end)

      it("uses correct cwd from adapter context", function()
        local received_cwd = nil
        local adapter = {
          ctx = {
            toplevel = "/my/custom/repo/path",
          },
          exec_sync = function(self, args, opts)
            received_cwd = opts.cwd
            return {}, 0
          end,
        }

        store:verify_blob_exists(adapter, "somehash")
        eq("/my/custom/repo/path", received_cwd)
      end)
    end)

    describe("multiple branches", function()
      it("stores separate state files for different branches", async_test(function()
        local async = require("diffview.async")

        -- Create states for two different branches
        local state_main = ReviewState({
          repo_id = "multi_branch",
          branch = "main",
          store = store,
          files = {
            ["src/file.lua"] = { blob_hash = "main_hash", reviewed_at = 1705276800 },
          },
        })

        local state_feature = ReviewState({
          repo_id = "multi_branch",
          branch = "feature/new-feature",
          store = store,
          files = {
            ["src/file.lua"] = { blob_hash = "feature_hash", reviewed_at = 1705276801 },
          },
        })

        -- Save both
        async.await(store:save_state(state_main))
        async.await(store:save_state(state_feature))

        -- Verify both files exist with correct content
        local main_path = store:get_state_path("multi_branch", "main")
        local feature_path = store:get_state_path("multi_branch", "feature/new-feature")

        neq(main_path, feature_path) -- Different paths

        local main_content = vim.json.decode(read_file(main_path))
        local feature_content = vim.json.decode(read_file(feature_path))

        eq("main_hash", main_content.files["src/file.lua"].blob_hash)
        eq("feature_hash", feature_content.files["src/file.lua"].blob_hash)
      end))
    end)
  end)
end)
