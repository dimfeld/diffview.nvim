local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

local uv = vim.loop

describe("diffview.review cleanup operations", function()
  local review_store = require("diffview.review_store")
  local ReviewStore = review_store.ReviewStore
  local utils = require("diffview.utils")

  -- Test directory for file I/O tests
  local test_cache_dir = "/tmp/claude/diffview_test_cleanup_" .. os.time()

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

  describe("ReviewStore:unsanitize_branch()", function()
    local store

    before_each(function()
      store = ReviewStore()
    end)

    it("returns single name for simple branch names", function()
      local result = store:unsanitize_branch("main.json")
      eq({ "main" }, result)
    end)

    it("returns two possibilities for names with double underscores", function()
      local result = store:unsanitize_branch("feature__foo.json")
      eq(2, #result)
      eq("feature__foo", result[1])
      eq("feature/foo", result[2])
    end)

    it("handles multiple double underscores", function()
      local result = store:unsanitize_branch("feature__nested__branch.json")
      eq(2, #result)
      eq("feature__nested__branch", result[1])
      eq("feature/nested/branch", result[2])
    end)

    it("handles names without double underscores", function()
      local result = store:unsanitize_branch("develop.json")
      eq({ "develop" }, result)
    end)

    it("handles single underscore correctly", function()
      local result = store:unsanitize_branch("my_branch.json")
      eq({ "my_branch" }, result)
    end)

    it("handles empty name after stripping extension", function()
      local result = store:unsanitize_branch(".json")
      eq({ "" }, result)
    end)
  end)

  describe("ReviewStore:get_stored_branches()", function()
    local store

    before_each(function()
      rm_rf(test_cache_dir)
      store = ReviewStore()
      store.cache_dir = test_cache_dir
    end)

    after_each(function()
      rm_rf(test_cache_dir)
    end)

    it("returns empty table when repo directory doesn't exist", function()
      local result = store:get_stored_branches("nonexistent_repo")
      eq({}, result)
    end)

    it("returns empty table when directory exists but is empty", function()
      local repo_id = "empty_repo_test"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local result = store:get_stored_branches(repo_id)
      eq({}, result)
    end)

    it("returns correct branches for stored JSON files", function()
      local repo_id = "test_repo_branches"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/main.json", '{"version":1,"files":{}}')
      write_file(repo_dir .. "/develop.json", '{"version":1,"files":{}}')

      local result = store:get_stored_branches(repo_id)
      eq(2, #result)

      -- Check that we got the expected branches
      local found_main = false
      local found_develop = false
      for _, info in ipairs(result) do
        if info.filename == "main.json" then
          found_main = true
          eq({ "main" }, info.possible_branches)
        elseif info.filename == "develop.json" then
          found_develop = true
          eq({ "develop" }, info.possible_branches)
        end
      end
      eq(true, found_main)
      eq(true, found_develop)
    end)

    it("handles branch names with slashes (sanitized as __)", function()
      local repo_id = "test_repo_slashes"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/feature__add-login.json", '{"version":1,"files":{}}')

      local result = store:get_stored_branches(repo_id)
      eq(1, #result)
      eq("feature__add-login.json", result[1].filename)
      eq(2, #result[1].possible_branches)
      eq("feature__add-login", result[1].possible_branches[1])
      eq("feature/add-login", result[1].possible_branches[2])
    end)

    it("handles nested branch names with multiple slashes", function()
      local repo_id = "test_repo_nested"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/feature__nested__branch.json", '{"version":1,"files":{}}')

      local result = store:get_stored_branches(repo_id)
      eq(1, #result)
      eq(2, #result[1].possible_branches)
      eq("feature__nested__branch", result[1].possible_branches[1])
      eq("feature/nested/branch", result[1].possible_branches[2])
    end)

    it("skips non-JSON files", function()
      local repo_id = "test_repo_non_json"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/main.json", '{"version":1,"files":{}}')
      write_file(repo_dir .. "/readme.txt", 'This is not JSON')
      write_file(repo_dir .. "/backup.json.bak", 'backup file')
      write_file(repo_dir .. ".DS_Store", 'hidden file')

      local result = store:get_stored_branches(repo_id)
      eq(1, #result)
      eq("main.json", result[1].filename)
    end)

    it("handles detached HEAD files", function()
      local repo_id = "test_repo_detached"
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      local repo_dir = utils.path:join(test_cache_dir, repo_id)
      write_file(repo_dir .. "/detached-abc123def.json", '{"version":1,"files":{}}')

      local result = store:get_stored_branches(repo_id)
      eq(1, #result)
      eq("detached-abc123def.json", result[1].filename)
      eq({ "detached-abc123def" }, result[1].possible_branches)
    end)
  end)

  describe("ReviewStore:get_latest_review_timestamp()", function()
    local store

    before_each(function()
      rm_rf(test_cache_dir)
      store = ReviewStore()
      store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
    end)

    after_each(function()
      rm_rf(test_cache_dir)
    end)

    it("returns nil for non-existent file", function()
      local result = store:get_latest_review_timestamp(test_cache_dir .. "/nonexistent.json")
      eq(nil, result)
    end)

    it("returns nil for malformed JSON", function()
      local file_path = test_cache_dir .. "/malformed.json"
      write_file(file_path, "{ this is not valid json }")

      local result = store:get_latest_review_timestamp(file_path)
      eq(nil, result)
    end)

    it("returns nil for empty file", function()
      local file_path = test_cache_dir .. "/empty.json"
      write_file(file_path, "")

      local result = store:get_latest_review_timestamp(file_path)
      eq(nil, result)
    end)

    it("returns nil for JSON without files field", function()
      local file_path = test_cache_dir .. "/no_files.json"
      write_file(file_path, '{"version":1,"repo_id":"test","branch":"main"}')

      local result = store:get_latest_review_timestamp(file_path)
      eq(nil, result)
    end)

    it("returns nil for JSON with empty files", function()
      local file_path = test_cache_dir .. "/empty_files.json"
      write_file(file_path, '{"version":1,"files":{}}')

      local result = store:get_latest_review_timestamp(file_path)
      eq(nil, result)
    end)

    it("returns correct timestamp for single file entry", function()
      local file_path = test_cache_dir .. "/single_file.json"
      local timestamp = 1705276800
      write_file(file_path, vim.json.encode({
        version = 1,
        files = {
          ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = timestamp },
        },
      }))

      local result = store:get_latest_review_timestamp(file_path)
      eq(timestamp, result)
    end)

    it("returns most recent timestamp when multiple files exist", function()
      local file_path = test_cache_dir .. "/multiple_files.json"
      local oldest = 1705276800
      local middle = 1705276900
      local newest = 1705277000
      write_file(file_path, vim.json.encode({
        version = 1,
        files = {
          ["src/foo.lua"] = { blob_hash = "abc123", reviewed_at = oldest },
          ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = newest },
          ["src/baz.lua"] = { blob_hash = "ghi789", reviewed_at = middle },
        },
      }))

      local result = store:get_latest_review_timestamp(file_path)
      eq(newest, result)
    end)

    it("handles files with missing reviewed_at field", function()
      local file_path = test_cache_dir .. "/missing_timestamp.json"
      local timestamp = 1705276800
      write_file(file_path, vim.json.encode({
        version = 1,
        files = {
          ["src/foo.lua"] = { blob_hash = "abc123" }, -- missing reviewed_at
          ["src/bar.lua"] = { blob_hash = "def456", reviewed_at = timestamp },
        },
      }))

      local result = store:get_latest_review_timestamp(file_path)
      eq(timestamp, result)
    end)
  end)

  describe("ReviewStore:cleanup_stale_branches()", function()
    local store
    local repo_id = "cleanup12345"  -- exactly 12 characters

    -- Create a mock adapter
    local function create_mock_adapter(branches, repo_id_override)
      local actual_repo_id = repo_id_override or repo_id
      return {
        ctx = {
          toplevel = "/mock/cleanup/repo/" .. actual_repo_id,
        },
        exec_sync = function(self, args, opts)
          if args[1] == "rev-list" and args[2] == "--max-parents=0" then
            -- Return a 40-character SHA that starts with the repo_id
            return { actual_repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
        get_all_branches = function(self)
          return branches
        end,
      }
    end

    before_each(function()
      rm_rf(test_cache_dir)
      store = ReviewStore()
      store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
    end)

    after_each(function()
      rm_rf(test_cache_dir)
    end)

    it("returns error when repo_id cannot be determined", function()
      local mock_adapter = {
        ctx = { toplevel = "/failing/repo" },
        exec_sync = function() return {}, 128 end,
        get_all_branches = function() return { "main" } end,
      }

      local result = store:cleanup_stale_branches(mock_adapter)
      neq(nil, result.error)
      eq("Could not determine repository ID", result.error)
      eq(0, result.deleted_count)
      eq({}, result.deleted_branches)
    end)

    it("returns error when git branches cannot be listed", function()
      local mock_adapter = create_mock_adapter(nil)
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
      write_file(test_cache_dir .. "/" .. repo_id .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = 1 } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      neq(nil, result.error)
      eq("Could not get git branches", result.error)
    end)

    it("returns empty result when no stored branches exist", function()
      local mock_adapter = create_mock_adapter({ "main", "develop" })
      -- Don't create any files

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)
      eq({}, result.deleted_branches)
    end)

    it("preserves branches that exist in git", function()
      local mock_adapter = create_mock_adapter({ "main", "develop" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state files for existing branches with old timestamps
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
      write_file(repo_dir .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/develop.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "def", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)
      eq({}, result.deleted_branches)

      -- Files should still exist
      eq(true, file_exists(repo_dir .. "/main.json"))
      eq(true, file_exists(repo_dir .. "/develop.json"))
    end)

    it("dry run mode returns what would be deleted without deleting", function()
      local mock_adapter = create_mock_adapter({ "main" })  -- only main exists
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state for non-existent branch with old timestamp
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
      write_file(repo_dir .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "def", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter, { dry_run = true })
      eq(nil, result.error)
      eq(1, result.deleted_count)
      eq(1, #result.deleted_branches)
      eq("deleted-branch", result.deleted_branches[1])

      -- Files should still exist in dry run mode
      eq(true, file_exists(repo_dir .. "/main.json"))
      eq(true, file_exists(repo_dir .. "/deleted-branch.json"))
    end)

    it("actually deletes files when not in dry run mode", function()
      local mock_adapter = create_mock_adapter({ "main" })  -- only main exists
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state for non-existent branch with old timestamp
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
      write_file(repo_dir .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "def", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter, { dry_run = false })
      eq(nil, result.error)
      eq(1, result.deleted_count)
      eq(1, #result.deleted_branches)
      eq("deleted-branch", result.deleted_branches[1])

      -- main.json should still exist, deleted-branch.json should be removed
      eq(true, file_exists(repo_dir .. "/main.json"))
      eq(false, file_exists(repo_dir .. "/deleted-branch.json"))
    end)

    it("preserves remote branches (origin/feature format)", function()
      local mock_adapter = create_mock_adapter({
        "main",
        "origin/feature/foo",  -- remote tracking branch
        "feature/foo",         -- short form is also added by get_all_branches
      })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state for feature/foo (which exists as origin/feature/foo)
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(repo_dir .. "/feature__foo.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)

      -- File should be preserved because feature/foo exists in git
      eq(true, file_exists(repo_dir .. "/feature__foo.json"))
    end)

    it("handles double-underscore ambiguity correctly", function()
      -- If a file is named "a__b.json", it could represent:
      -- - A branch literally named "a__b"
      -- - A branch named "a/b"
      -- We should preserve the file if EITHER exists in git
      local mock_adapter = create_mock_adapter({
        "main",
        "a__b",  -- literal branch name with double underscore
      })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(repo_dir .. "/a__b.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)

      -- File should be preserved because "a__b" exists in git
      eq(true, file_exists(repo_dir .. "/a__b.json"))
    end)

    it("handles double-underscore ambiguity when slash version exists", function()
      -- Same as above, but this time a/b exists instead of a__b
      local mock_adapter = create_mock_adapter({
        "main",
        "a/b",  -- branch with slash
      })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(repo_dir .. "/a__b.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)

      -- File should be preserved because "a/b" exists in git
      eq(true, file_exists(repo_dir .. "/a__b.json"))
    end)

    it("cleans up detached HEAD files older than max_age_days", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create detached HEAD file with old timestamp
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
      write_file(repo_dir .. "/detached-abc123def.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter, { max_age_days = 30 })
      eq(nil, result.error)
      eq(1, result.deleted_count)
      eq("detached-abc123def", result.deleted_branches[1])
      eq(false, file_exists(repo_dir .. "/detached-abc123def.json"))
    end)

    it("preserves detached HEAD files newer than max_age_days", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create detached HEAD file with recent timestamp
      local recent_timestamp = os.time() - (7 * 24 * 60 * 60)  -- 7 days ago
      write_file(repo_dir .. "/detached-abc123def.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = recent_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter, { max_age_days = 30 })
      eq(nil, result.error)
      eq(0, result.deleted_count)
      eq(true, file_exists(repo_dir .. "/detached-abc123def.json"))
    end)

    it("cleans up stale branch files only if older than max_age_days", function()
      local mock_adapter = create_mock_adapter({ "main" })  -- deleted-branch doesn't exist
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state for non-existent branch with recent timestamp
      local recent_timestamp = os.time() - (7 * 24 * 60 * 60)  -- 7 days ago
      write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = recent_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter, { max_age_days = 30 })
      eq(nil, result.error)
      eq(0, result.deleted_count)  -- Not deleted because too recent
      eq(true, file_exists(repo_dir .. "/deleted-branch.json"))
    end)

    it("respects configurable max_age_days parameter", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state with 10-day-old timestamp
      local ten_days_ago = os.time() - (10 * 24 * 60 * 60)
      write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = ten_days_ago } },
      }))

      -- With 30-day threshold, should NOT be deleted
      local result1 = store:cleanup_stale_branches(mock_adapter, { max_age_days = 30, dry_run = true })
      eq(0, result1.deleted_count)

      -- With 7-day threshold, should be deleted
      local result2 = store:cleanup_stale_branches(mock_adapter, { max_age_days = 7, dry_run = true })
      eq(1, result2.deleted_count)
    end)

    it("skips files with no determinable timestamp (conservative behavior)", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create state for non-existent branch with no files (can't determine timestamp)
      write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
        version = 1,
        files = {},
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(0, result.deleted_count)  -- Not deleted because can't determine age
      eq(true, file_exists(repo_dir .. "/deleted-branch.json"))
    end)

    it("handles multiple stale branches correctly", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      local old_timestamp = os.time() - (60 * 24 * 60 * 60)

      write_file(repo_dir .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/stale1.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "def", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/stale2.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "ghi", reviewed_at = old_timestamp } },
      }))
      write_file(repo_dir .. "/feature__stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "jkl", reviewed_at = old_timestamp } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)
      eq(nil, result.error)
      eq(3, result.deleted_count)

      -- main.json should still exist
      eq(true, file_exists(repo_dir .. "/main.json"))
      -- stale branches should be deleted
      eq(false, file_exists(repo_dir .. "/stale1.json"))
      eq(false, file_exists(repo_dir .. "/stale2.json"))
      eq(false, file_exists(repo_dir .. "/feature__stale.json"))
    end)

    it("uses default max_age_days of 30 when not specified", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create file 25 days old (should NOT be deleted with default 30 days)
      local twenty_five_days = os.time() - (25 * 24 * 60 * 60)
      write_file(repo_dir .. "/recent-stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = twenty_five_days } },
      }))

      -- Create file 35 days old (should be deleted with default 30 days)
      local thirty_five_days = os.time() - (35 * 24 * 60 * 60)
      write_file(repo_dir .. "/old-stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "def", reviewed_at = thirty_five_days } },
      }))

      local result = store:cleanup_stale_branches(mock_adapter)  -- no opts, use default
      eq(nil, result.error)
      eq(1, result.deleted_count)

      eq(true, file_exists(repo_dir .. "/recent-stale.json"))
      eq(false, file_exists(repo_dir .. "/old-stale.json"))
    end)
  end)

  describe("Public cleanup API (review.lua)", function()
    local review = require("diffview.review")
    local config = require("diffview.config")
    local store
    local repo_id = "publicapi123"  -- exactly 12 characters
    local original_config
    local original_get_store

    -- Create a mock adapter for testing
    local function create_mock_adapter(branches, repo_id_override)
      local actual_repo_id = repo_id_override or repo_id
      return {
        ctx = {
          toplevel = "/mock/public/repo/" .. actual_repo_id,
        },
        exec_sync = function(self, args, opts)
          if args[1] == "rev-list" and args[2] == "--max-parents=0" then
            -- Return a 40-character SHA that starts with the repo_id
            return { actual_repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
        get_all_branches = function(self)
          return branches
        end,
      }
    end

    before_each(function()
      rm_rf(test_cache_dir)
      store = ReviewStore()
      store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))

      -- Store original config and ensure review is enabled
      original_config = vim.deepcopy(config.get_config())

      -- Store and override review_store.get_store to return our test store
      original_get_store = review_store.get_store
      review_store.get_store = function()
        return store
      end
    end)

    after_each(function()
      rm_rf(test_cache_dir)
      -- Restore original config
      if original_config then
        config._config = original_config
      end
      -- Restore original get_store
      if original_get_store then
        review_store.get_store = original_get_store
      end
    end)

    describe("review.get_cleanup_preview()", function()
      it("returns error when review is disabled", function()
        -- Disable review in config
        local cfg = config.get_config()
        cfg.review = { enabled = false }

        local result = review.get_cleanup_preview({ adapter = create_mock_adapter({ "main" }) })
        eq("Review is disabled", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("returns error when view is nil", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local result = review.get_cleanup_preview(nil)
        eq("No adapter available", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("returns error when view.adapter is nil", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local result = review.get_cleanup_preview({ adapter = nil })
        eq("No adapter available", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("returns correct preview results with mock adapter", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local mock_adapter = create_mock_adapter({ "main" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        -- Create a stale branch file (old timestamp)
        local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
        write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
        }))

        -- Create a valid branch file
        write_file(repo_dir .. "/main.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "def", reviewed_at = os.time() } },
        }))

        local mock_view = { adapter = mock_adapter }
        local result = review.get_cleanup_preview(mock_view)

        eq(nil, result.error)
        eq(1, result.deleted_count)
        eq("stale-branch", result.deleted_branches[1])

        -- Files should still exist (dry run)
        eq(true, file_exists(repo_dir .. "/stale-branch.json"))
        eq(true, file_exists(repo_dir .. "/main.json"))
      end)

      it("respects cleanup_age_days from config", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 7 }  -- shorter threshold

        local mock_adapter = create_mock_adapter({ "main" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        -- Create a branch file 10 days old (would survive 30 days, but not 7)
        local ten_days_ago = os.time() - (10 * 24 * 60 * 60)
        write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = ten_days_ago } },
        }))

        local mock_view = { adapter = mock_adapter }
        local result = review.get_cleanup_preview(mock_view)

        eq(nil, result.error)
        eq(1, result.deleted_count)  -- Should be deleted with 7-day threshold
      end)
    end)

    describe("review.cleanup_stale_reviews()", function()
      it("returns error when review is disabled", function()
        local cfg = config.get_config()
        cfg.review = { enabled = false }

        local result = review.cleanup_stale_reviews({ adapter = create_mock_adapter({ "main" }) })
        eq("Review is disabled", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("returns error when view is nil", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local result = review.cleanup_stale_reviews(nil)
        eq("No adapter available", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("returns error when view.adapter is nil", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local result = review.cleanup_stale_reviews({ adapter = nil })
        eq("No adapter available", result.error)
        eq({}, result.deleted_branches)
        eq(0, result.deleted_count)
      end)

      it("emits review_cleanup_completed event on successful cleanup", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local mock_adapter = create_mock_adapter({ "main" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        -- Create a stale branch file
        local old_timestamp = os.time() - (60 * 24 * 60 * 60)
        write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
        }))

        -- Track emitted events
        local emitted_event = nil
        local emitted_data = nil
        local original_emit = DiffviewGlobal.emitter.emit
        DiffviewGlobal.emitter.emit = function(self, event, data)
          if event == "review_cleanup_completed" then
            emitted_event = event
            emitted_data = data
          end
          return original_emit(self, event, data)
        end

        local mock_view = { adapter = mock_adapter }
        local result = review.cleanup_stale_reviews(mock_view)

        -- Restore the original emit
        DiffviewGlobal.emitter.emit = original_emit

        eq(nil, result.error)
        eq(1, result.deleted_count)

        -- Verify event was emitted
        eq("review_cleanup_completed", emitted_event)
        neq(nil, emitted_data)
        eq(mock_view, emitted_data.view)
        eq(1, emitted_data.deleted_count)
        eq("stale-branch", emitted_data.deleted_branches[1])
      end)

      it("does not emit event when no files are deleted", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local mock_adapter = create_mock_adapter({ "main" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        -- Create only a valid branch file
        write_file(repo_dir .. "/main.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "def", reviewed_at = os.time() } },
        }))

        -- Track emitted events
        local event_emitted = false
        local original_emit = DiffviewGlobal.emitter.emit
        DiffviewGlobal.emitter.emit = function(self, event, data)
          if event == "review_cleanup_completed" then
            event_emitted = true
          end
          return original_emit(self, event, data)
        end

        local mock_view = { adapter = mock_adapter }
        local result = review.cleanup_stale_reviews(mock_view)

        -- Restore the original emit
        DiffviewGlobal.emitter.emit = original_emit

        eq(nil, result.error)
        eq(0, result.deleted_count)
        eq(false, event_emitted)  -- No event should be emitted
      end)

      it("actually deletes correct files from disk", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 30 }

        local mock_adapter = create_mock_adapter({ "main", "develop" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        local old_timestamp = os.time() - (60 * 24 * 60 * 60)
        local recent_timestamp = os.time() - (7 * 24 * 60 * 60)

        -- Valid branches (should be preserved)
        write_file(repo_dir .. "/main.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
        }))
        write_file(repo_dir .. "/develop.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "def", reviewed_at = old_timestamp } },
        }))

        -- Stale branch, old (should be deleted)
        write_file(repo_dir .. "/deleted-branch.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "ghi", reviewed_at = old_timestamp } },
        }))

        -- Stale branch, recent (should be preserved due to age)
        write_file(repo_dir .. "/recently-deleted.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "jkl", reviewed_at = recent_timestamp } },
        }))

        local mock_view = { adapter = mock_adapter }
        local result = review.cleanup_stale_reviews(mock_view)

        eq(nil, result.error)
        eq(1, result.deleted_count)
        eq("deleted-branch", result.deleted_branches[1])

        -- Verify file states
        eq(true, file_exists(repo_dir .. "/main.json"))
        eq(true, file_exists(repo_dir .. "/develop.json"))
        eq(false, file_exists(repo_dir .. "/deleted-branch.json"))
        eq(true, file_exists(repo_dir .. "/recently-deleted.json"))
      end)

      it("respects cleanup_age_days from config when deleting", function()
        local cfg = config.get_config()
        cfg.review = { enabled = true, cleanup_age_days = 5 }  -- Very short threshold

        local mock_adapter = create_mock_adapter({ "main" })
        local repo_dir = test_cache_dir .. "/" .. repo_id
        uv.fs_mkdir(repo_dir, tonumber("0755", 8))

        -- Create a branch file 10 days old (would survive 30 days, but not 5)
        local ten_days_ago = os.time() - (10 * 24 * 60 * 60)
        write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
          version = 1,
          files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = ten_days_ago } },
        }))

        local mock_view = { adapter = mock_adapter }
        local result = review.cleanup_stale_reviews(mock_view)

        eq(nil, result.error)
        eq(1, result.deleted_count)  -- Should be deleted with 5-day threshold
        eq(false, file_exists(repo_dir .. "/stale-branch.json"))
      end)
    end)
  end)

  describe("review_cleanup listener", function()
    local listeners_module
    local original_config
    local config = require("diffview.config")

    before_each(function()
      rm_rf(test_cache_dir)
      original_config = vim.deepcopy(config.get_config())
      listeners_module = require("diffview.scene.views.diff.listeners")
    end)

    after_each(function()
      rm_rf(test_cache_dir)
      config._config = original_config
    end)

    -- Helper to create a mock view for listener tests
    local function create_cleanup_mock_view(opts)
      opts = opts or {}
      local repo_id = opts.repo_id or "listener1234"  -- 12 characters

      local mock_adapter = {
        ctx = {
          toplevel = "/mock/listener/repo/" .. repo_id,
        },
        exec_sync = function(self, args, exec_opts)
          if args[1] == "rev-list" and args[2] == "--max-parents=0" then
            return { repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
        get_all_branches = function(self)
          return opts.branches or { "main" }
        end,
      }

      return {
        adapter = mock_adapter,
        review_state = opts.review_state or { files = {}, branch = "main" },
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }
    end

    it("shows info when review feature is disabled", function()
      local cfg = config.get_config()
      cfg.review = { enabled = false }

      local mock_view = create_cleanup_mock_view()
      local listeners = listeners_module(mock_view)

      -- Should not error
      listeners.review_cleanup()
    end)

    it("shows warning when preview fails", function()
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      -- Create adapter that will fail get_all_branches
      local mock_view = {
        adapter = {
          ctx = { toplevel = "/mock/fail/repo" },
          exec_sync = function(self, args)
            if args[1] == "rev-list" then
              return { "failingrepo0000000000000000000000000000" }, 0
            end
            return {}, 1
          end,
          get_all_branches = function()
            return nil  -- Simulates failure
          end,
        },
        review_state = { files = {}, branch = "main" },
        files = { iter = function() return function() end end },
        infer_cur_file = function() return nil end,
      }

      -- Override get_store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/failingrepo", tonumber("0755", 8))
      write_file(test_cache_dir .. "/failingrepo/main.json", '{"version":1,"files":{}}')

      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      local listeners = listeners_module(mock_view)

      -- Should not error, just show warning
      listeners.review_cleanup()

      review_store.get_store = original_get_store
    end)

    it("shows info when no stale data found", function()
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      local mock_view = create_cleanup_mock_view({ branches = { "main" } })
      local repo_id = "listener1234"

      -- Override get_store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))
      -- Create file for existing branch (main)
      write_file(test_cache_dir .. "/" .. repo_id .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = os.time() } },
      }))

      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      local listeners = listeners_module(mock_view)

      -- Should not error, shows info
      listeners.review_cleanup()

      review_store.get_store = original_get_store
    end)

    it("calls vim.ui.select when stale branches are found", function()
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      local mock_view = create_cleanup_mock_view({ branches = { "main" } })
      local repo_id = "listener1234"

      -- Override get_store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(test_cache_dir .. "/" .. repo_id .. "/stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      -- Track if vim.ui.select was called
      local ui_select_called = false
      local ui_select_items = nil
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        ui_select_called = true
        ui_select_items = items
        -- Simulate user choosing "No"
        on_choice("No")
      end

      local listeners = listeners_module(mock_view)
      listeners.review_cleanup()

      -- Restore
      vim.ui.select = original_ui_select
      review_store.get_store = original_get_store

      -- Verify vim.ui.select was called with Yes/No options
      eq(true, ui_select_called)
      eq({ "Yes", "No" }, ui_select_items)

      -- File should still exist since user chose "No"
      eq(true, file_exists(test_cache_dir .. "/" .. repo_id .. "/stale.json"))
    end)

    it("deletes files when user confirms with Yes", function()
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      local mock_view = create_cleanup_mock_view({ branches = { "main" } })
      local repo_id = "listener1234"

      -- Override get_store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(test_cache_dir .. "/" .. repo_id .. "/stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      -- Automatically confirm with "Yes"
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        on_choice("Yes")
      end

      local listeners = listeners_module(mock_view)
      listeners.review_cleanup()

      -- Restore
      vim.ui.select = original_ui_select
      review_store.get_store = original_get_store

      -- File should be deleted
      eq(false, file_exists(test_cache_dir .. "/" .. repo_id .. "/stale.json"))
    end)

    it("does not delete files when user cancels", function()
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      local mock_view = create_cleanup_mock_view({ branches = { "main" } })
      local repo_id = "listener1234"

      -- Override get_store
      local test_store = ReviewStore()
      test_store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))
      uv.fs_mkdir(test_cache_dir .. "/" .. repo_id, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(test_cache_dir .. "/" .. repo_id .. "/stale.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      local original_get_store = review_store.get_store
      review_store.get_store = function() return test_store end

      -- Simulate user pressing escape (nil choice)
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        on_choice(nil)  -- User pressed escape
      end

      local listeners = listeners_module(mock_view)
      listeners.review_cleanup()

      -- Restore
      vim.ui.select = original_ui_select
      review_store.get_store = original_get_store

      -- File should still exist
      eq(true, file_exists(test_cache_dir .. "/" .. repo_id .. "/stale.json"))
    end)
  end)

  describe("review_cleanup action registration", function()
    it("review_cleanup action is registered in actions module", function()
      local actions = require("diffview.actions")

      -- Verify the action function exists
      assert.is_function(actions.review_cleanup)
    end)
  end)

  describe("DiffviewReviewCleanup command registration", function()
    -- Note: Testing user commands in headless mode requires manually loading
    -- the plugin file since test initialization only loads the Lua modules

    it("command is registered when plugin file is sourced", function()
      -- Source the plugin file to register commands
      local plugin_path = vim.fn.fnamemodify(
        debug.getinfo(1, "S").source:sub(2),
        ":p:h:h:h:h:h"
      ) .. "/plugin/diffview.lua"

      -- The plugin file should exist
      local stat = vim.loop.fs_stat(plugin_path)
      neq(nil, stat, "Plugin file should exist at: " .. plugin_path)

      -- Source it to register commands
      vim.cmd("source " .. plugin_path)

      -- Now verify the command is registered
      local commands = vim.api.nvim_get_commands({})
      neq(nil, commands["DiffviewReviewCleanup"], "DiffviewReviewCleanup command should be registered")
    end)

    it("command supports bang modifier for dry-run", function()
      -- Note: This test relies on the previous test having sourced the plugin
      local commands = vim.api.nvim_get_commands({})
      local cmd_info = commands["DiffviewReviewCleanup"]

      -- If command not found, source the plugin first
      if not cmd_info then
        local plugin_path = vim.fn.fnamemodify(
          debug.getinfo(1, "S").source:sub(2),
          ":p:h:h:h:h:h"
        ) .. "/plugin/diffview.lua"
        vim.cmd("source " .. plugin_path)
        commands = vim.api.nvim_get_commands({})
        cmd_info = commands["DiffviewReviewCleanup"]
      end

      neq(nil, cmd_info, "Command should be registered")
      eq(true, cmd_info.bang, "Command should support bang modifier")
    end)
  end)

  describe("DiffviewReviewCleanup command without active view", function()
    -- These tests verify the inline confirmation dialog flow when the command
    -- is invoked outside of an active DiffView
    local config = require("diffview.config")
    local review = require("diffview.review")
    local store
    local repo_id = "cmdnoview123"  -- 12 characters
    local original_config
    local original_get_store
    local original_get_adapter

    -- Helper to create a mock adapter
    local function create_mock_adapter(branches, repo_id_override)
      local actual_repo_id = repo_id_override or repo_id
      return {
        ctx = {
          toplevel = "/mock/cmd/repo/" .. actual_repo_id,
        },
        exec_sync = function(self, args, opts)
          if args[1] == "rev-list" and args[2] == "--max-parents=0" then
            return { actual_repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
        get_all_branches = function(self)
          return branches
        end,
      }
    end

    before_each(function()
      rm_rf(test_cache_dir)
      store = ReviewStore()
      store.cache_dir = test_cache_dir
      uv.fs_mkdir(test_cache_dir, tonumber("0755", 8))

      -- Store original config and ensure review is enabled
      original_config = vim.deepcopy(config.get_config())
      local cfg = config.get_config()
      cfg.review = { enabled = true, cleanup_age_days = 30 }

      -- Store and override review_store.get_store to return our test store
      original_get_store = review_store.get_store
      review_store.get_store = function()
        return store
      end
    end)

    after_each(function()
      rm_rf(test_cache_dir)
      -- Restore original config
      if original_config then
        config._config = original_config
      end
      -- Restore original get_store
      if original_get_store then
        review_store.get_store = original_get_store
      end
      -- Restore original get_adapter if overridden
      if original_get_adapter then
        require("diffview").get_adapter = original_get_adapter
        original_get_adapter = nil
      end
    end)

    it("shows confirmation dialog when stale data exists without active view", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)  -- 60 days ago
      write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      -- Override diffview.get_adapter to return our mock
      local diffview_module = require("diffview")
      original_get_adapter = diffview_module.get_adapter
      diffview_module.get_adapter = function()
        return mock_adapter
      end

      -- Track vim.ui.select call
      local ui_select_called = false
      local ui_select_items = nil
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        ui_select_called = true
        ui_select_items = items
        -- Simulate user choosing "No" to avoid deletion
        on_choice("No")
      end

      -- Create the view object that the command would create
      local view = { adapter = mock_adapter }
      local preview = review.get_cleanup_preview(view)

      -- Simulate what the command does without active view
      if #preview.deleted_branches > 0 then
        -- Build confirmation message
        local branch_list = table.concat(preview.deleted_branches, ", ")
        if #branch_list > 60 then
          branch_list = branch_list:sub(1, 57) .. "..."
        end

        vim.ui.select({ "Yes", "No" }, {
          prompt = ("Clean up review state for %d stale branch(es)? [%s]"):format(
            preview.deleted_count,
            branch_list
          ),
        }, function(choice)
          if choice == "Yes" then
            review.cleanup_stale_reviews(view)
          end
        end)
      end

      -- Restore
      vim.ui.select = original_ui_select

      -- Verify vim.ui.select was called
      eq(true, ui_select_called)
      eq({ "Yes", "No" }, ui_select_items)

      -- File should still exist since user chose "No"
      eq(true, file_exists(repo_dir .. "/stale-branch.json"))
    end)

    it("deletes files when user confirms Yes without active view", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      -- Override diffview.get_adapter to return our mock
      local diffview_module = require("diffview")
      original_get_adapter = diffview_module.get_adapter
      diffview_module.get_adapter = function()
        return mock_adapter
      end

      -- Auto-confirm with "Yes"
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        on_choice("Yes")
      end

      -- Create the view object that the command would create
      local view = { adapter = mock_adapter }
      local preview = review.get_cleanup_preview(view)

      -- Simulate what the command does without active view
      if #preview.deleted_branches > 0 then
        local branch_list = table.concat(preview.deleted_branches, ", ")
        if #branch_list > 60 then
          branch_list = branch_list:sub(1, 57) .. "..."
        end

        vim.ui.select({ "Yes", "No" }, {
          prompt = ("Clean up review state for %d stale branch(es)? [%s]"):format(
            preview.deleted_count,
            branch_list
          ),
        }, function(choice)
          if choice == "Yes" then
            review.cleanup_stale_reviews(view)
          end
        end)
      end

      -- Restore
      vim.ui.select = original_ui_select

      -- File should be deleted
      eq(false, file_exists(repo_dir .. "/stale-branch.json"))
    end)

    it("does not delete files when user cancels (nil choice) without active view", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create stale branch file
      local old_timestamp = os.time() - (60 * 24 * 60 * 60)
      write_file(repo_dir .. "/stale-branch.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = old_timestamp } },
      }))

      -- Override diffview.get_adapter to return our mock
      local diffview_module = require("diffview")
      original_get_adapter = diffview_module.get_adapter
      diffview_module.get_adapter = function()
        return mock_adapter
      end

      -- Simulate user pressing escape (nil choice)
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        on_choice(nil)
      end

      -- Create the view object that the command would create
      local view = { adapter = mock_adapter }
      local preview = review.get_cleanup_preview(view)

      -- Simulate what the command does without active view
      if #preview.deleted_branches > 0 then
        local branch_list = table.concat(preview.deleted_branches, ", ")
        if #branch_list > 60 then
          branch_list = branch_list:sub(1, 57) .. "..."
        end

        vim.ui.select({ "Yes", "No" }, {
          prompt = ("Clean up review state for %d stale branch(es)? [%s]"):format(
            preview.deleted_count,
            branch_list
          ),
        }, function(choice)
          if choice == "Yes" then
            review.cleanup_stale_reviews(view)
          end
        end)
      end

      -- Restore
      vim.ui.select = original_ui_select

      -- File should still exist
      eq(true, file_exists(repo_dir .. "/stale-branch.json"))
    end)

    it("shows info when no stale data found without active view", function()
      local mock_adapter = create_mock_adapter({ "main" })
      local repo_dir = test_cache_dir .. "/" .. repo_id
      uv.fs_mkdir(repo_dir, tonumber("0755", 8))

      -- Create only valid branch file (exists in git)
      write_file(repo_dir .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = os.time() } },
      }))

      -- Override diffview.get_adapter to return our mock
      local diffview_module = require("diffview")
      original_get_adapter = diffview_module.get_adapter
      diffview_module.get_adapter = function()
        return mock_adapter
      end

      -- Track if vim.ui.select was called
      local ui_select_called = false
      local original_ui_select = vim.ui.select
      vim.ui.select = function(items, opts, on_choice)
        ui_select_called = true
        on_choice("No")
      end

      -- Create the view object that the command would create
      local view = { adapter = mock_adapter }
      local preview = review.get_cleanup_preview(view)

      -- This should not call vim.ui.select because there's no stale data
      if #preview.deleted_branches > 0 then
        vim.ui.select({ "Yes", "No" }, {
          prompt = "Clean up?",
        }, function(choice) end)
      end

      -- Restore
      vim.ui.select = original_ui_select

      -- vim.ui.select should NOT have been called
      eq(false, ui_select_called)

      -- File should still exist
      eq(true, file_exists(repo_dir .. "/main.json"))
    end)

    it("handles preview error gracefully without active view", function()
      -- This test verifies that when git commands fail, the command handles it gracefully
      -- Use the same repo_id as other tests so the store override works correctly
      local fail_repo_id = repo_id  -- Use "cmdnoview123" from parent scope

      -- Create adapter that returns nil for get_all_branches
      local failing_adapter = {
        ctx = { toplevel = "/mock/fail/repo/" .. fail_repo_id },
        exec_sync = function(self, args)
          if args[1] == "rev-list" then
            return { fail_repo_id .. "0000000000000000000000000000" }, 0
          end
          return {}, 1
        end,
        get_all_branches = function()
          return nil  -- Simulates failure
        end,
      }

      -- Set up the repo dir
      uv.fs_mkdir(test_cache_dir .. "/" .. fail_repo_id, tonumber("0755", 8))
      write_file(test_cache_dir .. "/" .. fail_repo_id .. "/main.json", vim.json.encode({
        version = 1,
        files = { ["file.lua"] = { blob_hash = "abc", reviewed_at = os.time() } },
      }))

      -- Override diffview.get_adapter to return our failing mock
      local diffview_module = require("diffview")
      original_get_adapter = diffview_module.get_adapter
      diffview_module.get_adapter = function()
        return failing_adapter
      end

      -- Create the view object
      local view = { adapter = failing_adapter }
      local preview = review.get_cleanup_preview(view)

      -- Preview should have an error due to failing get_all_branches
      neq(nil, preview.error)
      eq("Could not get git branches", preview.error)

      -- In the command, this would trigger a warning message and return early
      -- The key point is it doesn't crash
    end)
  end)
end)
