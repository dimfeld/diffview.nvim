local helpers = require("diffview.tests.helpers")
local eq = helpers.eq

local GroupedFileDict = require("diffview.grouped_file_dict").GroupedFileDict

local function make_file(path, kind, status)
  return {
    path = path,
    kind = kind or "working",
    status = status or "M",
  }
end

describe("diffview.grouped_file_dict", function()
  it("stores groups and returns group metadata", function()
    local dict = GroupedFileDict("My Review")
    local files = {
      make_file("src/foo.lua"),
      make_file("src/bar.lua"),
    }

    local group = dict:add_group("Group A", files)

    eq("Group A", group.name)
    eq(files, group.files)
    eq("My Review", dict.title)
    eq(true, dict:is_grouped())
    eq(1, #group.tree.root.children)
  end)

  it("indexes files across groups", function()
    local dict = GroupedFileDict()
    local group_a = {
      make_file("src/foo.lua"),
      make_file("src/bar.lua"),
    }
    local group_b = {
      make_file("doc/readme.md"),
    }

    dict:add_group("Group A", group_a)
    dict:add_group("Group B", group_b)

    eq("src/foo.lua", dict[1].path)
    eq("src/bar.lua", dict[2].path)
    eq("doc/readme.md", dict[3].path)
  end)

  it("returns nil for out-of-bounds indices", function()
    local dict = GroupedFileDict()
    dict:add_group("Group A", {
      make_file("src/foo.lua"),
    })

    eq(nil, dict[0])
    eq(nil, dict[-1])
    eq(nil, dict[dict:len() + 1])
  end)

  it("returns total length and iterates in order", function()
    local dict = GroupedFileDict()
    dict:add_group("Group A", {
      make_file("src/foo.lua"),
    })
    dict:add_group("Group B", {
      make_file("src/bar.lua"),
      make_file("src/baz.lua"),
    })

    eq(3, dict:len())

    local paths = {}
    for _, file in dict:iter() do
      table.insert(paths, file.path)
    end

    eq({ "src/foo.lua", "src/bar.lua", "src/baz.lua" }, paths)
  end)

  it("skips empty groups when indexing and iterating", function()
    local dict = GroupedFileDict()
    dict:add_group("Empty A", {})
    dict:add_group("Group B", {
      make_file("src/foo.lua"),
    })
    dict:add_group("Empty C", {})
    dict:add_group("Group D", {
      make_file("src/bar.lua"),
      make_file("src/baz.lua"),
    })

    eq(3, dict:len())
    eq("src/foo.lua", dict[1].path)
    eq("src/bar.lua", dict[2].path)
    eq("src/baz.lua", dict[3].path)

    local paths = {}
    for _, file in dict:iter() do
      table.insert(paths, file.path)
    end

    eq({ "src/foo.lua", "src/bar.lua", "src/baz.lua" }, paths)
  end)

  it("rebuilds file trees on update", function()
    local dict = GroupedFileDict()
    local group = dict:add_group("Group A", {
      make_file("src/foo.lua"),
    })

    eq(true, group.tree.root.children["src"] ~= nil)

    group.files = {
      make_file("lib/qux.lua"),
      make_file("lib/quux.lua"),
    }

    dict:update_file_trees()

    eq(nil, group.tree.root.children["src"])
    eq(true, group.tree.root.children["lib"] ~= nil)
    eq(1, #group.tree.root.children)
  end)
end)
