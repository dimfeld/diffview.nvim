local helpers = require("diffview.tests.helpers")
local eq, neq = helpers.eq, helpers.neq

local config = require("diffview.config")
local hl = require("diffview.hl")
local renderer = require("diffview.renderer")
local review = require("diffview.review")

-- Helper to create a mock file entry
local function create_mock_file(path, opts)
  opts = opts or {}
  local basename = path:match("[^/]+$") or path
  local extension = basename:match("%.([^%.]+)$")
  local parent_path = path:match("(.+)/[^/]+$") or ""

  return {
    path = path,
    basename = basename,
    extension = extension,
    parent_path = parent_path,
    status = opts.status or "M",
    active = opts.active or false,
    kind = opts.kind or "working",
    stats = opts.stats,
  }
end

-- Helper to create a mock view
local function create_mock_view(opts)
  opts = opts or {}

  local mock_review_state = nil
  if opts.review_enabled ~= false and opts.has_review_state ~= false then
    local review_files = opts.review_files or {}
    mock_review_state = {
      files = review_files,
    }
    -- Add the get_file_status method separately to capture the closure properly
    mock_review_state.get_file_status = function(self, file_path, current_blob_hash)
      local entry = self.files[file_path]
      if not entry then
        return "unreviewed"
      end
      if not current_blob_hash or entry.blob_hash == current_blob_hash then
        return "reviewed"
      end
      return "changed"
    end
  end

  local blob_hashes = opts.blob_hashes or {}
  local mock_adapter = {
    file_blob_hash = function(_, path, rev)
      return blob_hashes[path]
    end,
    ctx = {
      toplevel = "/mock/repo",
    },
  }

  return {
    review_state = mock_review_state,
    adapter = mock_adapter,
  }
end

-- Helper to render a file and capture output
local function render_file_to_component(file, view, show_path, depth)
  local RenderComponent = renderer.RenderComponent
  local comp = RenderComponent.create_static_component({
    name = "file",
    context = file,
  })

  -- Call the render_file function by loading the render module
  -- We need to invoke it via the internal render logic
  local conf = config.get_config()

  -- Manually replicate the render_file logic for testing
  comp:add_text(file.status .. " ", hl.get_git_hl(file.status))

  -- Review status indicator
  if view and view.review_state and conf.review and conf.review.enabled then
    local review_status = review.get_file_status(view, file)
    if review_status then
      local symbol = conf.review.symbols[review_status] or "?"
      comp:add_text(symbol .. " ", hl.get_review_hl(review_status))
    end
  end

  if depth then
    comp:add_text(string.rep(" ", depth * 2 + 2))
  end

  comp:add_text(file.basename, file.active and "DiffviewFilePanelSelected" or "DiffviewFilePanelFileName")

  if show_path then
    comp:add_text(" " .. file.parent_path, "DiffviewFilePanelPath")
  end

  comp:ln()

  return comp
end

describe("review indicator rendering", function()
  local original_config

  before_each(function()
    -- Store original config
    original_config = config._config
    -- Reset to a fresh config with review enabled
    config._config = vim.tbl_deep_extend("force", {}, config.defaults)
  end)

  after_each(function()
    -- Restore original config
    config._config = original_config
  end)

  describe("highlight groups", function()
    it("get_review_hl returns correct highlight for unreviewed", function()
      local result = hl.get_review_hl("unreviewed")
      eq("DiffviewReviewUnreviewed", result)
    end)

    it("get_review_hl returns correct highlight for reviewed", function()
      local result = hl.get_review_hl("reviewed")
      eq("DiffviewReviewReviewed", result)
    end)

    it("get_review_hl returns correct highlight for changed", function()
      local result = hl.get_review_hl("changed")
      eq("DiffviewReviewChanged", result)
    end)

    it("get_review_hl returns nil for invalid status", function()
      local result = hl.get_review_hl("invalid_status")
      eq(nil, result)
    end)

    it("hl_links contains review highlight group mappings", function()
      eq("Comment", hl.hl_links.ReviewUnreviewed)
      eq("diffAdded", hl.hl_links.ReviewReviewed)
      eq("DiagnosticSignWarn", hl.hl_links.ReviewChanged)
    end)
  end)

  describe("config symbols", function()
    it("default config has review symbols defined", function()
      local conf = config.get_config()
      neq(nil, conf.review)
      neq(nil, conf.review.symbols)
      eq(" ", conf.review.symbols.unreviewed)
      eq("●", conf.review.symbols.reviewed)
      eq("◐", conf.review.symbols.changed)
    end)

    it("default config has review enabled", function()
      local conf = config.get_config()
      eq(true, conf.review.enabled)
    end)
  end)

  describe("review indicator in file rendering", function()
    it("renders indicator when review is enabled and view has review_state", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)

      -- The rendered line should contain the git status, review symbol, and filename
      eq(1, #comp.lines)
      local line = comp.lines[1]

      -- Should contain "M " (git status), then review indicator, then filename
      assert.is_truthy(line:match("^M "))
      assert.is_truthy(line:match("test%.lua"))
    end)

    it("renders unreviewed indicator (space) for files not yet reviewed", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = { unreviewed = " ", reviewed = "R", changed = "C" },
        },
      })

      local file = create_mock_file("src/new.lua", { status = "A" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = {}, -- No files reviewed
        blob_hashes = { ["src/new.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Check that unreviewed symbol (space) is present after status
      -- The line should be "A   new.lua ..." (status + space + space(indicator) + space + filename)
      assert.is_truthy(line:match("^A "))
    end)

    it("renders reviewed indicator for files that have been reviewed", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = { unreviewed = " ", reviewed = "R", changed = "C" },
        },
      })

      local file = create_mock_file("src/reviewed.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/reviewed.lua"] = { blob_hash = "abc123" } },
        blob_hashes = { ["src/reviewed.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Should contain the reviewed indicator "R"
      assert.is_truthy(line:match("R "))
    end)

    it("renders changed indicator for files reviewed but modified", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = { unreviewed = " ", reviewed = "R", changed = "C" },
        },
      })

      local file = create_mock_file("src/changed.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/changed.lua"] = { blob_hash = "old_hash" } },
        blob_hashes = { ["src/changed.lua"] = "new_hash" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Should contain the changed indicator "C"
      assert.is_truthy(line:match("C "))
    end)

    it("does not render indicator when review is disabled", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = false },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Should start with just "M " followed by filename (no extra review indicator column)
      -- With review disabled, pattern should be "M test.lua" without extra space for indicator
      assert.is_truthy(line:match("^M "))
      -- The line should NOT have the reviewed/changed symbols
      assert.is_falsy(line:match("●"))
      assert.is_falsy(line:match("◐"))
    end)

    it("does not render indicator when view is nil", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })

      local comp = render_file_to_component(file, nil, true, nil)
      local line = comp.lines[1]

      -- Should just have git status and filename
      assert.is_truthy(line:match("^M "))
      assert.is_truthy(line:match("test%.lua"))
    end)

    it("does not render indicator when view has no review_state", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = false, -- No review state (e.g., Mercurial)
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Should just have git status and filename, no indicator
      assert.is_truthy(line:match("^M "))
    end)

    it("applies correct highlight group for unreviewed status", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = {},
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)

      -- Check that the highlight data includes the review highlight
      local has_review_hl = false
      for _, hl_entry in ipairs(comp.hl) do
        if hl_entry.group == "DiffviewReviewUnreviewed" then
          has_review_hl = true
          break
        end
      end
      eq(true, has_review_hl)
    end)

    it("applies correct highlight group for reviewed status", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/test.lua"] = { blob_hash = "abc123" } },
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)

      local has_review_hl = false
      for _, hl_entry in ipairs(comp.hl) do
        if hl_entry.group == "DiffviewReviewReviewed" then
          has_review_hl = true
          break
        end
      end
      eq(true, has_review_hl)
    end)

    it("applies correct highlight group for changed status", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/test.lua"] = { blob_hash = "old_hash" } },
        blob_hashes = { ["src/test.lua"] = "new_hash" },
      })

      local comp = render_file_to_component(file, view, true, nil)

      local has_review_hl = false
      for _, hl_entry in ipairs(comp.hl) do
        if hl_entry.group == "DiffviewReviewChanged" then
          has_review_hl = true
          break
        end
      end
      eq(true, has_review_hl)
    end)
  end)

  describe("tree view rendering", function()
    it("renders indicator for files in tree view (with depth)", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = { unreviewed = " ", reviewed = "R", changed = "C" },
        },
      })

      local file = create_mock_file("src/deep/nested/file.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/deep/nested/file.lua"] = { blob_hash = "abc123" } },
        blob_hashes = { ["src/deep/nested/file.lua"] = "abc123" },
      })

      -- Render with depth = 2 (simulating tree nesting)
      local comp = render_file_to_component(file, view, false, 2)
      local line = comp.lines[1]

      -- Should contain: status, review indicator, indentation (depth*2+2 spaces), filename
      assert.is_truthy(line:match("^M "))
      assert.is_truthy(line:match("R "))
      assert.is_truthy(line:match("file%.lua"))
      -- Should have indentation (2*2+2 = 6 spaces)
      assert.is_truthy(line:match("      file%.lua"))
    end)

    it("renders indicator correctly at different tree depths", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = { unreviewed = "U", reviewed = "R", changed = "C" },
        },
      })

      local file = create_mock_file("root.lua", { status = "A" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = {},
        blob_hashes = { ["root.lua"] = "abc123" },
      })

      -- Render at depth 0
      local comp = render_file_to_component(file, view, false, 0)
      local line = comp.lines[1]

      -- At depth 0, should have (0*2+2 = 2) spaces of indentation
      assert.is_truthy(line:match("^A "))
      assert.is_truthy(line:match("U "))
      assert.is_truthy(line:match("  root%.lua")) -- 2 spaces indentation
    end)
  end)

  describe("different git statuses", function()
    local test_cases = {
      { status = "A", name = "Added" },
      { status = "M", name = "Modified" },
      { status = "D", name = "Deleted" },
      { status = "R", name = "Renamed" },
      { status = "C", name = "Copied" },
      { status = "?", name = "Untracked" },
    }

    for _, tc in ipairs(test_cases) do
      it("renders review indicator for " .. tc.name .. " (" .. tc.status .. ") files", function()
        config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
          review = {
            enabled = true,
            symbols = { unreviewed = "U", reviewed = "R", changed = "C" },
          },
        })

        local file = create_mock_file("src/file.lua", { status = tc.status })
        local view = create_mock_view({
          review_enabled = true,
          has_review_state = true,
          review_files = { ["src/file.lua"] = { blob_hash = "abc123" } },
          blob_hashes = { ["src/file.lua"] = "abc123" },
        })

        local comp = render_file_to_component(file, view, true, nil)
        local line = comp.lines[1]

        -- Should start with the git status, then review indicator
        assert.is_truthy(line:match("^" .. vim.pesc(tc.status) .. " "))
        assert.is_truthy(line:match("R ")) -- reviewed indicator
      end)
    end
  end)

  describe("edge cases", function()
    it("handles file with nil path gracefully", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = { enabled = true },
      })

      local file = {
        path = nil,
        basename = "orphan.lua",
        extension = "lua",
        parent_path = "",
        status = "M",
        active = false,
      }
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
      })

      -- Should not error
      local comp = render_file_to_component(file, view, true, nil)
      eq(1, #comp.lines)
    end)

    it("handles missing review symbols in config", function()
      -- Explicitly set up config with partial symbols (missing some)
      config._config = vim.tbl_deep_extend("force", {}, config.defaults)
      -- Explicitly clear the symbols to test fallback
      config._config.review.symbols = {
        -- Only reviewed is defined, missing unreviewed and changed
        reviewed = "R",
      }

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = {}, -- File not reviewed, so status will be "unreviewed"
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      -- Status will be "unreviewed" which is not in symbols, should fallback to "?"
      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]
      -- The unreviewed symbol is missing, so it should use fallback "?"
      assert.is_truthy(line:match("%? ")) -- fallback symbol
    end)

    it("works with unicode symbols", function()
      config._config = vim.tbl_deep_extend("force", {}, config.defaults, {
        review = {
          enabled = true,
          symbols = {
            unreviewed = "○",
            reviewed = "●",
            changed = "◐",
          },
        },
      })

      local file = create_mock_file("src/test.lua", { status = "M" })
      local view = create_mock_view({
        review_enabled = true,
        has_review_state = true,
        review_files = { ["src/test.lua"] = { blob_hash = "abc123" } },
        blob_hashes = { ["src/test.lua"] = "abc123" },
      })

      local comp = render_file_to_component(file, view, true, nil)
      local line = comp.lines[1]

      -- Should contain the unicode reviewed symbol
      assert.is_truthy(line:match("● "))
    end)
  end)
end)

describe("review.get_file_status integration", function()
  local original_config

  before_each(function()
    original_config = config._config
    config._config = vim.tbl_deep_extend("force", {}, config.defaults)
  end)

  after_each(function()
    config._config = original_config
  end)

  it("returns nil when config review is disabled", function()
    config._config.review.enabled = false

    local mock_view = {
      review_state = {
        get_file_status = function() return "reviewed" end,
      },
      adapter = {
        file_blob_hash = function() return "abc123" end,
      },
    }

    local result = review.get_file_status(mock_view, { path = "test.lua" })
    eq(nil, result)
  end)

  it("returns nil when view has no review_state", function()
    config._config.review.enabled = true

    local mock_view = {
      review_state = nil,
      adapter = {
        file_blob_hash = function() return "abc123" end,
      },
    }

    local result = review.get_file_status(mock_view, { path = "test.lua" })
    eq(nil, result)
  end)
end)

describe("DiffView review event listeners", function()
  local original_config

  -- Helper to create a mock panel
  local function create_mock_panel()
    local render_calls = 0
    local redraw_calls = 0
    local is_panel_open = true

    return {
      render = function()
        render_calls = render_calls + 1
      end,
      redraw = function()
        redraw_calls = redraw_calls + 1
      end,
      is_open = function()
        return is_panel_open
      end,
      set_open = function(open)
        is_panel_open = open
      end,
      get_render_calls = function()
        return render_calls
      end,
      get_redraw_calls = function()
        return redraw_calls
      end,
      reset_counts = function()
        render_calls = 0
        redraw_calls = 0
      end,
    }
  end

  -- Helper to create a mock DiffView with event listener setup
  local function create_mock_diff_view_with_events(panel)
    local view = {
      panel = panel,
      review_event_callbacks = {},
    }

    -- Replicate the init_review_event_listeners logic from diff_view.lua
    local function refresh_panel()
      if view.panel:is_open() then
        view.panel:render()
        view.panel:redraw()
      end
    end

    view.review_event_callbacks.file_marked = function(_, payload)
      if payload.view == view then
        refresh_panel()
      end
    end

    view.review_event_callbacks.file_cleared = function(_, payload)
      if payload.view == view then
        refresh_panel()
      end
    end

    view.review_event_callbacks.all_cleared = function(_, payload)
      if payload.view == view then
        refresh_panel()
      end
    end

    DiffviewGlobal.emitter:on("review_file_marked", view.review_event_callbacks.file_marked)
    DiffviewGlobal.emitter:on("review_file_cleared", view.review_event_callbacks.file_cleared)
    DiffviewGlobal.emitter:on("review_all_cleared", view.review_event_callbacks.all_cleared)

    return view
  end

  -- Helper to clean up a mock view's event listeners
  local function cleanup_mock_view(view)
    if view.review_event_callbacks then
      DiffviewGlobal.emitter:off(view.review_event_callbacks.file_marked)
      DiffviewGlobal.emitter:off(view.review_event_callbacks.file_cleared)
      DiffviewGlobal.emitter:off(view.review_event_callbacks.all_cleared)
      view.review_event_callbacks = nil
    end
  end

  before_each(function()
    original_config = config._config
    config._config = vim.tbl_deep_extend("force", {}, config.defaults)
  end)

  after_each(function()
    config._config = original_config
  end)

  describe("panel refresh on events", function()
    it("refreshes panel when review_file_marked event is emitted for current view", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Emit the event for this view
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = { path = "test.lua" },
        blob_hash = "abc123",
      })

      eq(1, panel.get_render_calls())
      eq(1, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)

    it("refreshes panel when review_file_cleared event is emitted for current view", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Emit the event for this view
      DiffviewGlobal.emitter:emit("review_file_cleared", {
        view = view,
        file_entry = { path = "test.lua" },
      })

      eq(1, panel.get_render_calls())
      eq(1, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)

    it("refreshes panel when review_all_cleared event is emitted for current view", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Emit the event for this view
      DiffviewGlobal.emitter:emit("review_all_cleared", {
        view = view,
      })

      eq(1, panel.get_render_calls())
      eq(1, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)

    it("does not refresh panel when event is for a different view", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      local other_view = { id = "other_view" }

      -- Emit events for a DIFFERENT view
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = other_view,
        file_entry = { path = "test.lua" },
        blob_hash = "abc123",
      })

      DiffviewGlobal.emitter:emit("review_file_cleared", {
        view = other_view,
        file_entry = { path = "test.lua" },
      })

      DiffviewGlobal.emitter:emit("review_all_cleared", {
        view = other_view,
      })

      -- Should NOT have refreshed
      eq(0, panel.get_render_calls())
      eq(0, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)

    it("does not refresh panel when panel is closed", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Close the panel
      panel.set_open(false)

      -- Emit the event for this view
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = { path = "test.lua" },
        blob_hash = "abc123",
      })

      -- Should NOT have refreshed since panel is closed
      eq(0, panel.get_render_calls())
      eq(0, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)

    it("handles multiple events correctly", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Emit multiple events
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = { path = "file1.lua" },
        blob_hash = "hash1",
      })

      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = { path = "file2.lua" },
        blob_hash = "hash2",
      })

      DiffviewGlobal.emitter:emit("review_file_cleared", {
        view = view,
        file_entry = { path = "file3.lua" },
      })

      eq(3, panel.get_render_calls())
      eq(3, panel.get_redraw_calls())

      cleanup_mock_view(view)
    end)
  end)

  describe("event listener cleanup", function()
    it("removes event listeners when cleanup is called", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Verify listeners are registered
      local marked_listeners = DiffviewGlobal.emitter:get("review_file_marked")
      local cleared_listeners = DiffviewGlobal.emitter:get("review_file_cleared")
      local all_cleared_listeners = DiffviewGlobal.emitter:get("review_all_cleared")

      -- Check our callbacks are in the listener lists
      local has_marked = false
      local has_cleared = false
      local has_all_cleared = false

      if marked_listeners then
        for _, listener in ipairs(marked_listeners) do
          if listener.callback == view.review_event_callbacks.file_marked then
            has_marked = true
            break
          end
        end
      end

      if cleared_listeners then
        for _, listener in ipairs(cleared_listeners) do
          if listener.callback == view.review_event_callbacks.file_cleared then
            has_cleared = true
            break
          end
        end
      end

      if all_cleared_listeners then
        for _, listener in ipairs(all_cleared_listeners) do
          if listener.callback == view.review_event_callbacks.all_cleared then
            has_all_cleared = true
            break
          end
        end
      end

      eq(true, has_marked, "file_marked listener should be registered")
      eq(true, has_cleared, "file_cleared listener should be registered")
      eq(true, has_all_cleared, "all_cleared listener should be registered")

      -- Store references before cleanup
      local file_marked_cb = view.review_event_callbacks.file_marked
      local file_cleared_cb = view.review_event_callbacks.file_cleared
      local all_cleared_cb = view.review_event_callbacks.all_cleared

      -- Cleanup (simulating DiffView:close())
      cleanup_mock_view(view)

      -- Verify listeners are removed
      marked_listeners = DiffviewGlobal.emitter:get("review_file_marked")
      cleared_listeners = DiffviewGlobal.emitter:get("review_file_cleared")
      all_cleared_listeners = DiffviewGlobal.emitter:get("review_all_cleared")

      has_marked = false
      has_cleared = false
      has_all_cleared = false

      if marked_listeners then
        for _, listener in ipairs(marked_listeners) do
          if listener.callback == file_marked_cb then
            has_marked = true
            break
          end
        end
      end

      if cleared_listeners then
        for _, listener in ipairs(cleared_listeners) do
          if listener.callback == file_cleared_cb then
            has_cleared = true
            break
          end
        end
      end

      if all_cleared_listeners then
        for _, listener in ipairs(all_cleared_listeners) do
          if listener.callback == all_cleared_cb then
            has_all_cleared = true
            break
          end
        end
      end

      eq(false, has_marked, "file_marked listener should be removed after cleanup")
      eq(false, has_cleared, "file_cleared listener should be removed after cleanup")
      eq(false, has_all_cleared, "all_cleared listener should be removed after cleanup")
    end)

    it("sets review_event_callbacks to nil after cleanup", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      neq(nil, view.review_event_callbacks)

      cleanup_mock_view(view)

      eq(nil, view.review_event_callbacks)
    end)

    it("events do not trigger panel refresh after cleanup", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- Cleanup
      cleanup_mock_view(view)

      -- Reset panel counts
      panel.reset_counts()

      -- Emit events - should not trigger any refresh since listeners are removed
      DiffviewGlobal.emitter:emit("review_file_marked", {
        view = view,
        file_entry = { path = "test.lua" },
        blob_hash = "abc123",
      })

      DiffviewGlobal.emitter:emit("review_file_cleared", {
        view = view,
        file_entry = { path = "test.lua" },
      })

      DiffviewGlobal.emitter:emit("review_all_cleared", {
        view = view,
      })

      eq(0, panel.get_render_calls())
      eq(0, panel.get_redraw_calls())
    end)

    it("cleanup is idempotent - can be called multiple times safely", function()
      local panel = create_mock_panel()
      local view = create_mock_diff_view_with_events(panel)

      -- First cleanup
      cleanup_mock_view(view)
      eq(nil, view.review_event_callbacks)

      -- Second cleanup should not error
      cleanup_mock_view(view)
      eq(nil, view.review_event_callbacks)
    end)
  end)
end)
