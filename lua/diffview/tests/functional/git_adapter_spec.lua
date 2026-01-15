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
end)
