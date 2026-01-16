local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

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
            if options.abbrev_ref_fails then
              return {}, options.abbrev_ref_exit_code or 128
            end
            return { options.abbrev_ref_result or "main" }, 0
          end

          -- Handle git rev-parse --short HEAD
          if args[1] == "rev-parse" and args[2] == "--short" and args[3] == "HEAD" then
            if options.short_fails then
              return {}, options.short_exit_code or 128
            end
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
        abbrev_ref_result = "HEAD",  -- Git returns "HEAD" when detached
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
        abbrev_ref_result = "HEAD",  -- Detached state
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
        if args[1] == "rev-parse" and args[2] == "--abbrev-ref" then
          return {}, 128
        end
        if args[1] == "rev-parse" and args[2] == "--short" then
          return {}, 0  -- Success but empty array
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
          if args[1] == "for-each-ref" and args[2] == "--format=%(refname:short)" and args[3] == "refs/heads/" then
            if options.local_fails then
              return {}, options.local_exit_code or 128
            end
            return options.local_output or {}, 0
          end

          -- Handle git for-each-ref command for remote branches
          if args[1] == "for-each-ref" and args[2] == "--format=%(refname:short)" and args[3] == "refs/remotes/" then
            if options.remote_fails then
              return {}, options.remote_exit_code or 128
            end
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
        local_output = { "feature/foo" },  -- Local branch with slash
        remote_output = { "origin/feature/bar" },  -- Remote branch with slash
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
        if branch == "main" then
          main_count = main_count + 1
        end
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
        if args[1] == "for-each-ref" then
          return nil, 0
        end
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
            if options.abbrev_ref_fails then
              return {}, options.abbrev_ref_exit_code or 128
            end
            return { options.abbrev_ref_result or "main" }, 0
          end

          -- Handle git rev-parse --short HEAD
          if args[1] == "rev-parse" and args[2] == "--short" and args[3] == "HEAD" then
            if options.short_fails then
              return {}, options.short_exit_code or 128
            end
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
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      -- Mock utils.job to return JJ output
      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "feature-branch" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter({
        abbrev_ref_result = "git-branch",  -- This should NOT be used
      })

      local branch = adapter:get_current_branch()
      eq("feature-branch", branch)
    end)

    it("removes asterisks from JJ bookmark output", function()
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "my-bookmark*" }, 0, {}  -- JJ marks current with asterisk
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter()

      local branch = adapter:get_current_branch()
      eq("my-bookmark", branch)
    end)

    it("handles whitespace in JJ output", function()
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "  spaced-branch*  \n" }, 0, {}
        end
        return original_job(cmd, opts)
      end

      local adapter = create_jj_mock_adapter()

      local branch = adapter:get_current_branch()
      eq("spaced-branch", branch)
    end)

    it("falls back to Git when JJ command fails", function()
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return {}, 1, { "jj: command not found" }  -- JJ not installed
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
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return {}, 0, {}  -- Success but empty (no bookmarks)
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
      utils.path.is_dir = function(self, path)
        return path:match("%.jj$") ~= nil
      end

      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          return { "  *  " }, 0, {}  -- Only whitespace and asterisks
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
        return false  -- No .jj directory
      end

      -- JJ should NOT be called
      local jj_called = false
      utils.job = function(cmd, opts)
        if cmd[1] == "jj" then
          jj_called = true
        end
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
end)
