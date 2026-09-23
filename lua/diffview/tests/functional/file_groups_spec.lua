local helpers = require("diffview.tests.helpers")
local eq = helpers.eq
local FileDict = require("diffview.vcs.file_dict").FileDict
local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
local file_groups = require("diffview.scene.views.diff.file_groups")
local renderer = require("diffview.renderer")

local function file(path, kind) return { path = path, kind = kind or "working", status = "M" } end

describe("diffview file groups", function()
  it("classifies common paths and gives test paths priority", function()
    eq("Implementation", file_groups.classify("lua/diffview/init.lua"))
    eq("Documentation", file_groups.classify("README.md"))
    eq("Documentation", file_groups.classify("docs/setup.rst"))
    eq("Documentation", file_groups.classify("LICENSE"))
    eq("Tests", file_groups.classify("tests/helpers.lua"))
    eq("Tests", file_groups.classify("src/widget.test.ts"))
    eq("Tests", file_groups.classify("src/__tests__/README.md"))
    eq("Tests", file_groups.classify("fixtures/result.snap"))
  end)

  it("shows each file once and restores regular order when grouping is off", function()
    local files = FileDict()
    local conflict = file("src/conflict.lua", "conflicting")
    local test = file("tests/widget_spec.lua")
    local docs = file("README.md", "staged")
    files:set_conflicting({ conflict })
    files:set_working({ test })
    files:set_staged({ docs })
    files:update_file_trees()

    local panel = {
      files = files,
      grouped = true,
      listing_style = "list",
      render_data = renderer.RenderData("file_groups_test"),
      should_show_file = FilePanel.should_show_file,
      update_components = FilePanel.update_components,
      ordered_file_list = FilePanel.ordered_file_list,
    }

    panel:update_components()
    eq(
      { "Implementation", "Documentation", "Tests" },
      vim.tbl_map(function(group) return group.name end, panel.display_files.groups)
    )
    eq({ conflict, docs, test }, panel:ordered_file_list())

    panel.grouped = false
    panel:update_components()
    eq(files, panel.display_files)
    eq({ conflict, test, docs }, panel:ordered_file_list())
  end)
end)
