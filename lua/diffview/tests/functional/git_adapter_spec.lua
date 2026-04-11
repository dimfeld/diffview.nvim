local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq
local RevType = require("diffview.vcs.rev").RevType

describe("diffview.vcs.adapters.git", function()
  -- Load the actual GitAdapter class to test its methods
  local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter

  describe("GitAdapter:get_current_branch()", function()
    -- Helper to create a mock adapter that has exec_sync mocked
    -- but uses the real get_current_branch implementation
    local function create_mock_adapter(options)
      options = options or {}

      -- Create a table that will serve as our mock adapter instance
      local mock = {
        ctx = {
          toplevel = options.toplevel or "/mock/repo",
        },
        exec_sync = function(self, args, opts)
          -- Handle git rev-parse --abbrev-ref HEAD
          if args[1] == "rev-parse" and args[2] == "--abbrev-ref" and args[3] == "HEAD" then
            if options.abbrev_ref_fails then return {}, options.abbrev_ref_exit_code or 128 end
            return { options.abbrev_ref_result or "main" }, 0
          end

          -- Handle git rev-parse --short HEAD
          if args[1] == "rev-parse" and args[2] == "--short" and args[3] == "HEAD" then
            if options.short_fails then return {}, options.short_exit_code or 128 end
            return { options.short_result or "abc1234" }, 0
          end

          return {}, 1
        end,
      }

      -- Set the metatable to inherit from GitAdapter for the get_current_branch method
      -- This ensures we're testing the actual implementation, not a copy
      setmetatable(mock, { __index = GitAdapter })

      return mock
    end

    it("returns branch name when on a normal branch", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "main",
      })

      local branch = adapter:get_current_branch()
      eq("main", branch)
    end)

    it("returns branch name for feature branches with slashes", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "feature/add-login",
      })

      local branch = adapter:get_current_branch()
      eq("feature/add-login", branch)
    end)

    it("returns detached-<sha> when in detached HEAD state", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "HEAD", -- Git returns "HEAD" when detached
        short_result = "abc1234",
      })

      local branch = adapter:get_current_branch()
      eq("detached-abc1234", branch)
    end)

    it("handles whitespace in git output", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "  develop  \n",
      })

      local branch = adapter:get_current_branch()
      eq("develop", branch)
    end)

    it("returns detached-unknown when detached and short rev-parse fails", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "HEAD", -- Detached state
        short_fails = true,
      })

      local branch = adapter:get_current_branch()
      eq("detached-unknown", branch)
    end)

    it("returns unknown when all git commands fail", function()
      local adapter = create_mock_adapter({
        abbrev_ref_fails = true,
        short_fails = true,
      })

      local branch = adapter:get_current_branch()
      eq("unknown", branch)
    end)

    it("falls back to detached-<sha> when abbrev-ref fails but short succeeds", function()
      local adapter = create_mock_adapter({
        abbrev_ref_fails = true,
        short_result = "def5678",
      })

      local branch = adapter:get_current_branch()
      eq("detached-def5678", branch)
    end)

    it("handles short SHA with whitespace in detached state", function()
      local adapter = create_mock_adapter({
        abbrev_ref_result = "HEAD",
        short_result = "  xyz9999  \n",
      })

      local branch = adapter:get_current_branch()
      eq("detached-xyz9999", branch)
    end)

    it("returns unknown when abbrev-ref fails and short returns empty", function()
      local adapter = create_mock_adapter({
        abbrev_ref_fails = true,
      })
      -- Override exec_sync for this specific case
      adapter.exec_sync = function(self, args, opts)
        if args[1] == "rev-parse" and args[2] == "--abbrev-ref" then return {}, 128 end
        if args[1] == "rev-parse" and args[2] == "--short" then
          return {}, 0 -- Success but empty array
        end
        return {}, 1
      end

      local branch = adapter:get_current_branch()
      eq("unknown", branch)
    end)
  end)

  describe("GitAdapter:get_all_branches()", function()
    -- Helper to create a mock adapter for get_all_branches tests
    -- Now supports separate outputs for local and remote branches
    local function create_mock_adapter(options)
      options = options or {}

      local mock = {
        ctx = {
          toplevel = options.toplevel or "/mock/repo",
        },
        exec_sync = function(self, args, opts)
          -- Handle git for-each-ref command for local branches
          if
            args[1] == "for-each-ref"
            and args[2] == "--format=%(refname:short)"
            and args[3] == "refs/heads/"
          then
            if options.local_fails then return {}, options.local_exit_code or 128 end
            return options.local_output or {}, 0
          end

          -- Handle git for-each-ref command for remote branches
          if
            args[1] == "for-each-ref"
            and args[2] == "--format=%(refname:short)"
            and args[3] == "refs/remotes/"
          then
            if options.remote_fails then return {}, options.remote_exit_code or 128 end
            return options.remote_output or {}, 0
          end

          return {}, 1
        end,
      }

      setmetatable(mock, { __index = GitAdapter })
      return mock
    end

    it("returns branch names for local branches", function()
      local adapter = create_mock_adapter({
        local_output = { "main", "develop", "feature/login" },
        remote_output = {},
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      eq(true, vim.tbl_contains(branches, "main"))
      eq(true, vim.tbl_contains(branches, "develop"))
      eq(true, vim.tbl_contains(branches, "feature/login"))
    end)

    it("filters out empty lines in output", function()
      local adapter = create_mock_adapter({
        local_output = { "main", "", "develop", "", "" },
        remote_output = {},
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      -- Should only contain non-empty branches
      eq(2, #branches)
      eq(true, vim.tbl_contains(branches, "main"))
      eq(true, vim.tbl_contains(branches, "develop"))
    end)

    it("returns nil when local branch command fails", function()
      local adapter = create_mock_adapter({
        local_fails = true,
        local_exit_code = 128,
      })

      local branches = adapter:get_all_branches()
      eq(nil, branches)
    end)

    it("returns nil when remote branch command fails", function()
      local adapter = create_mock_adapter({
        local_output = { "main" },
        remote_fails = true,
        remote_exit_code = 128,
      })

      local branches = adapter:get_all_branches()
      eq(nil, branches)
    end)

    it("extracts short forms from remote branches", function()
      local adapter = create_mock_adapter({
        local_output = { "main" },
        remote_output = { "origin/main", "origin/feature/test" },
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      -- Should contain both full remote names and short forms
      eq(true, vim.tbl_contains(branches, "origin/main"))
      eq(true, vim.tbl_contains(branches, "main"))
      eq(true, vim.tbl_contains(branches, "origin/feature/test"))
      eq(true, vim.tbl_contains(branches, "feature/test"))
    end)

    it("does NOT extract short forms from local branches with slashes", function()
      local adapter = create_mock_adapter({
        local_output = { "feature/foo", "bugfix/bar/baz" },
        remote_output = {},
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      -- Local branches should appear as-is
      eq(true, vim.tbl_contains(branches, "feature/foo"))
      eq(true, vim.tbl_contains(branches, "bugfix/bar/baz"))
      -- But their short forms should NOT be extracted
      eq(false, vim.tbl_contains(branches, "foo"))
      eq(false, vim.tbl_contains(branches, "bar/baz"))
    end)

    it("only extracts short forms from remote branches, not local", function()
      -- This is the key test for the bug fix
      local adapter = create_mock_adapter({
        local_output = { "feature/foo" }, -- Local branch with slash
        remote_output = { "origin/feature/bar" }, -- Remote branch with slash
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      -- Local branch should NOT have short form extracted
      eq(true, vim.tbl_contains(branches, "feature/foo"))
      eq(false, vim.tbl_contains(branches, "foo"))
      -- Remote branch SHOULD have short form extracted
      eq(true, vim.tbl_contains(branches, "origin/feature/bar"))
      eq(true, vim.tbl_contains(branches, "feature/bar"))
    end)

    it("deduplicates branches that appear both locally and remotely", function()
      local adapter = create_mock_adapter({
        local_output = { "main" },
        remote_output = { "origin/main" },
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      -- "main" should only appear once even though it's both local and extracted from origin/main
      local main_count = 0
      for _, branch in ipairs(branches) do
        if branch == "main" then main_count = main_count + 1 end
      end
      eq(1, main_count)
    end)

    it("handles empty output gracefully", function()
      local adapter = create_mock_adapter({
        local_output = {},
        remote_output = {},
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      eq(0, #branches)
    end)

    it("handles nil output gracefully", function()
      local adapter = create_mock_adapter({})
      -- Override to return nil explicitly
      adapter.exec_sync = function(self, args, opts)
        if args[1] == "for-each-ref" then return nil, 0 end
        return {}, 1
      end

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      eq(0, #branches)
    end)

    it("handles multiple remote origins", function()
      local adapter = create_mock_adapter({
        local_output = { "main" },
        remote_output = { "origin/main", "upstream/main", "origin/feature/x" },
      })

      local branches = adapter:get_all_branches()
      neq(nil, branches)
      eq(true, vim.tbl_contains(branches, "origin/main"))
      eq(true, vim.tbl_contains(branches, "upstream/main"))
      eq(true, vim.tbl_contains(branches, "main"))
      eq(true, vim.tbl_contains(branches, "feature/x"))
    end)
  end)

  describe("GitAdapter:get_current_branch() with JJ support", function()
    local utils = require("diffview.utils")
    local original_job
    local original_is_dir

    before_each(function()
      original_job = utils.job
      original_is_dir = utils.path.is_dir
    end)

    after_each(function()
      utils.job = original_job
      utils.path.is_dir = original_is_dir
    end)

    -- Helper to create a mock adapter for JJ tests
    local function create_jj_mock_adapter(options)
      options = options or {}

      local mock = {
        ctx = {
          toplevel = options.toplevel or "/mock/repo",
        },
        exec_sync = function(self, args, opts)
          -- Handle git rev-parse --abbrev-ref HEAD
          if args[1] == "rev-parse" and args[2] == "--abbrev-ref" and args[3] == "HEAD" then
            if options.abbrev_ref_fails then return {}, options.abbrev_ref_exit_code or 128 end
            return { options.abbrev_ref_result or "main" }, 0
          end

          -- Handle git rev-parse --short HEAD
          if args[1] == "rev-parse" and args[2] == "--short" and args[3] == "HEAD" then
            if options.short_fails then return {}, options.short_exit_code or 128 end
            return { options.short_result or "abc1234" }, 0
          end

          return {}, 1
        end,
      }

      setmetatable(mock, { __index = GitAdapter })
      return mock
    end

    it("uses JJ command when .jj directory exists", function()
      -- Mock is_dir to return true for .jj
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      -- Mock utils.job to return JJ output
      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then return { "feature-branch" }, 0, {} end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "git-branch", -- This should NOT be used
      })

      local branch = adapter:get_current_branch()
      eq("feature-branch", branch)
    end)

    it("removes asterisks from JJ bookmark output", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "my-bookmark*" }, 0, {} -- JJ marks current with asterisk
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter()

      local branch = adapter:get_current_branch()
      eq("my-bookmark", branch)
    end)

    it("handles whitespace in JJ output", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then return { "  spaced-branch*  \n" }, 0, {} end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter()

      local branch = adapter:get_current_branch()
      eq("spaced-branch", branch)
    end)

    it("falls back to Git when JJ command fails", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return {}, 1, { "jj: command not found" } -- JJ not installed
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "git-fallback-branch",
      })

      local branch = adapter:get_current_branch()
      eq("git-fallback-branch", branch)
    end)

    it("falls back to Git when JJ returns empty output", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return {}, 0, {} -- Success but empty (no bookmarks)
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "git-no-bookmark-branch",
      })

      local branch = adapter:get_current_branch()
      eq("git-no-bookmark-branch", branch)
    end)

    it("falls back to Git when JJ output is only whitespace/asterisks", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "  *  " }, 0, {} -- Only whitespace and asterisks
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "git-empty-jj-branch",
      })

      local branch = adapter:get_current_branch()
      eq("git-empty-jj-branch", branch)
    end)

    it("uses Git behavior when .jj directory does not exist", function()
      utils.path.is_dir = function(self, path)
        return false -- No .jj directory
      end

      -- JJ should NOT be called
      local jj_called = false
      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then jj_called = true end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "regular-git-branch",
      })

      local branch = adapter:get_current_branch()
      eq("regular-git-branch", branch)
      eq(false, jj_called)
    end)
  end)

  describe("JJ revision parsing", function()
    local utils = require("diffview.utils")
    local original_job
    local original_is_dir

    before_each(function()
      original_job = utils.job
      original_is_dir = utils.path.is_dir
    end)

    after_each(function()
      utils.job = original_job
      utils.path.is_dir = original_is_dir
    end)

    local function create_rev_mock_adapter(options)
      options = options or {}

      local mock = {
        ctx = {
          toplevel = options.toplevel or "/mock/repo",
        },
        exec_sync = function(self, args, opts)
          if args[1] == "rev-parse" and args[2] == "HEAD" and args[3] == "--" then
            return { options.head_result or "head-hash" }, 0
          end

          if args[1] == "rev-parse" and args[2] == "--revs-only" then
            local result = options.rev_parse_results and options.rev_parse_results[args[3]]
            if result then return result, 0, {} end
            return {}, 128, { "bad revision" }
          end

          if args[1] == "merge-base" then
            return { options.merge_base_result or "merge-base-hash" }, 0, {}
          end

          return {}, 1, {}
        end,
      }

      setmetatable(mock, { __index = GitAdapter })
      return mock
    end

    it("verifies single JJ revisions when git rev-parse fails", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-1" then
          return { "jj-commit-hash" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_rev_mock_adapter()
      local ok, out = adapter:verify_rev_arg("bookmark-1")

      eq(true, ok)
      eq("jj-commit-hash", out[1])
    end)

    it("parses single JJ revisions into commit revs", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-2" then
          return { "jj-single-hash" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_rev_mock_adapter()
      local left, right = adapter:parse_revs("bookmark-2", {})

      eq("jj-single-hash", left.commit)
      eq(RevType.LOCAL, right.type)
    end)

    it("converts a git revision into a single-commit diff range", function()
      local adapter = create_rev_mock_adapter({
        rev_parse_results = {
          ["git-commit"] = { "git-commit-hash" },
        },
      })

      local range_arg = adapter:show_single_commit_rev_arg("git-commit")

      eq("git-commit-hash^!", range_arg)
    end)

    it("converts a JJ revision into a single-commit diff range", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-show" then
          return { "jj-show-hash" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_rev_mock_adapter()
      local range_arg = adapter:show_single_commit_rev_arg("bookmark-show")

      eq("jj-show-hash^!", range_arg)
    end)

    it("parses rev ranges with JJ revisions on either endpoint", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-3" then
          return { "jj-range-hash" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_rev_mock_adapter({
        rev_parse_results = {
          ["git-base"] = { "git-base-hash" },
          ["git-base-hash..jj-range-hash"] = { "jj-range-hash", "^git-base-hash" },
        },
      })

      local left, right = adapter:parse_revs("git-base..bookmark-3", {})

      eq("git-base-hash", left.commit)
      eq("jj-range-hash", right.commit)
    end)

    it("resolves JJ revisions before computing symmetric diffs", function()
      utils.path.is_dir = function(self, path) return path:match("%.jj$") ~= nil end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-left" then
          return { "jj-left-hash" }, 0, {}
        end
        if cmd[1] == "jj" and cmd[2] == "show" and cmd[3] == "bookmark-right" then
          return { "jj-right-hash" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local merge_base_args
      local adapter = create_rev_mock_adapter({
        merge_base_result = "merge-base-hash",
      })

      adapter.exec_sync = function(self, args, opts)
        if args[1] == "rev-parse" and args[2] == "HEAD" and args[3] == "--" then
          return { "head-hash" }, 0
        end

        if args[1] == "rev-parse" and args[2] == "--revs-only" then
          return {}, 128, { "bad revision" }
        end

        if args[1] == "merge-base" then
          merge_base_args = { args[2], args[3] }
          return { "merge-base-hash" }, 0, {}
        end

        return {}, 1, {}
      end

      local left, right = adapter:parse_revs("bookmark-left...bookmark-right", {})

      eq("jj-left-hash", merge_base_args[1])
      eq("jj-right-hash", merge_base_args[2])
      eq("merge-base-hash", left.commit)
      eq("jj-right-hash", right.commit)
    end)
  end)

  describe("GitAdapter:file_blob_hashes_batch()", function()
    local utils = require("diffview.utils")

    -- Helper to create a mock adapter for batch blob hash tests
    local function create_mock_adapter(options)
      options = options or {}

      local mock = {
        ctx = {
          toplevel = options.toplevel or "/mock/repo",
        },
        exec_sync = function(self, args, opts)
          -- Handle git ls-tree command
          if args[1] == "ls-tree" then
            if options.ls_tree_fails then return {}, options.ls_tree_exit_code or 128 end
            -- Return mock ls-tree output
            -- Format: "<mode> <type> <hash>\t<path>\0"
            return options.ls_tree_output or {}, 0
          end

          return {}, 1
        end,
      }

      setmetatable(mock, { __index = GitAdapter })
      return mock
    end

    it("returns empty table for empty paths", function()
      local adapter = create_mock_adapter()
      local result = adapter:file_blob_hashes_batch({}, "HEAD")
      eq({}, result)
    end)

    it("returns empty table for nil paths", function()
      local adapter = create_mock_adapter()
      local result = adapter:file_blob_hashes_batch(nil, "HEAD")
      eq({}, result)
    end)

    it("returns blob hashes for valid paths", function()
      -- Output uses NUL character (\000 in Lua) as separator
      local adapter = create_mock_adapter({
        ls_tree_output = {
          "100644 blob abc123def456\tsrc/foo.lua\000100644 blob def789abc012\tsrc/bar.lua",
        },
      })

      local result = adapter:file_blob_hashes_batch({ "src/foo.lua", "src/bar.lua" }, "HEAD")
      eq("abc123def456", result["src/foo.lua"])
      eq("def789abc012", result["src/bar.lua"])
    end)

    it("returns nil for missing paths", function()
      -- Only one file in output - missing.lua is not returned by ls-tree
      local adapter = create_mock_adapter({
        ls_tree_output = {
          "100644 blob abc123def456\tsrc/exists.lua",
        },
      })

      local result = adapter:file_blob_hashes_batch({ "src/exists.lua", "src/missing.lua" }, "HEAD")
      eq("abc123def456", result["src/exists.lua"])
      eq(nil, result["src/missing.lua"])
    end)

    it("handles paths with special characters", function()
      -- Output uses NUL character (\000 in Lua) as separator
      local adapter = create_mock_adapter({
        ls_tree_output = {
          "100644 blob abc123456789\tpath with spaces/file.lua\000100644 blob def456789012\tpath-with-dash.lua",
        },
      })

      local result = adapter:file_blob_hashes_batch({
        "path with spaces/file.lua",
        "path-with-dash.lua",
      }, "HEAD")
      eq("abc123456789", result["path with spaces/file.lua"])
      eq("def456789012", result["path-with-dash.lua"])
    end)

    it("initializes all paths to nil before processing", function()
      local adapter = create_mock_adapter({
        ls_tree_output = {}, -- No output - all paths fail
      })

      local paths = { "a.lua", "b.lua", "c.lua" }
      local result = adapter:file_blob_hashes_batch(paths, "HEAD")

      -- All paths should be present in result, but nil
      for _, path in ipairs(paths) do
        eq(true, result[path] == nil, "Expected nil for " .. path)
      end
    end)

    it("uses default rev_arg of HEAD when not specified", function()
      local exec_calls = {}
      local mock = {
        ctx = { toplevel = "/mock/repo" },
        exec_sync = function(self, args, opts)
          table.insert(exec_calls, args)
          return {}, 0
        end,
      }
      setmetatable(mock, { __index = GitAdapter })

      mock:file_blob_hashes_batch({ "test.lua" })

      -- Should have called ls-tree with HEAD
      eq(true, #exec_calls > 0)
      local found_head = false
      for _, call in ipairs(exec_calls) do
        for _, arg in ipairs(call) do
          if arg == "HEAD" then
            found_head = true
            break
          end
        end
      end
      eq(true, found_head, "Expected HEAD in ls-tree call")
    end)

    it("handles ls-tree failure gracefully", function()
      local adapter = create_mock_adapter({
        ls_tree_fails = true,
        ls_tree_exit_code = 128,
      })

      local result = adapter:file_blob_hashes_batch({ "src/foo.lua" }, "HEAD")
      -- Should return table with nil values, not error
      eq(nil, result["src/foo.lua"])
    end)
  end)
end)
