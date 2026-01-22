local helpers = require("diffview.tests.helpers")
local eq = helpers.eq

local stub = require("luassert.stub")
local uv = vim.loop

local json_loader = require("diffview.json_loader")

local function rm_rf(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end

  if stat.type == "directory" then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        rm_rf(path .. "/" .. name)
      end
    end
    uv.fs_rmdir(path)
  else
    uv.fs_unlink(path)
  end
end

local function write_file(path, content)
  local fd = assert(uv.fs_open(path, "w", 438))
  assert(uv.fs_write(fd, content, 0))
  assert(uv.fs_close(fd))
end

describe("diffview.json_loader", function()
  local test_dir

  before_each(function()
    test_dir = vim.fn.tempname() .. "_diffview_json_loader"
    rm_rf(test_dir)
    assert(uv.fs_mkdir(test_dir, tonumber("0755", 8)))
  end)

  after_each(function()
    rm_rf(test_dir)
  end)

  describe("validate_schema", function()
    it("accepts valid JSON data", function()
      local valid, err = json_loader.validate_schema({
        title = "Example",
        groups = {
          {
            name = "Group A",
            files = {
              { path = "src/foo.lua" },
              { path = "src/bar.lua" },
            },
          },
          {
            name = "Group B",
            files = {
              { path = "README.md" },
            },
          },
        },
      })

      eq(true, valid)
      eq(nil, err)
    end)

    it("rejects non-object roots", function()
      local valid, err = json_loader.validate_schema("not a table")
      eq(false, valid)
      eq("JSON root must be an object", err)
    end)

    it("rejects non-string titles", function()
      local valid, err = json_loader.validate_schema({
        title = 123,
        groups = {
          { name = "Group", files = { { path = "foo" } } },
        },
      })
      eq(false, valid)
      eq("title must be a string", err)
    end)

    it("rejects missing or empty groups", function()
      local valid, err = json_loader.validate_schema({})
      eq(false, valid)
      eq("groups must be an array", err)

      valid, err = json_loader.validate_schema({ groups = {} })
      eq(false, valid)
      eq("groups must not be empty", err)
    end)

    it("rejects invalid group entries", function()
      local valid, err = json_loader.validate_schema({ groups = { "bad" } })
      eq(false, valid)
      eq("group 1 must be an object", err)

      valid, err = json_loader.validate_schema({
        groups = {
          { name = "", files = {} },
        },
      })
      eq(false, valid)
      eq("group 1 name must be a non-empty string", err)

      valid, err = json_loader.validate_schema({
        groups = {
          { name = "Group", files = "bad" },
        },
      })
      eq(false, valid)
      eq("group 1 files must be an array", err)
    end)

    it("accepts groups with empty file lists", function()
      local valid, err = json_loader.validate_schema({
        groups = {
          { name = "Empty Group", files = {} },
        },
      })
      eq(true, valid)
      eq(nil, err)
    end)

    it("rejects invalid file specs", function()
      local valid, err = json_loader.validate_schema({
        groups = {
          {
            name = "Group",
            files = { "bad" },
          },
        },
      })
      eq(false, valid)
      eq("group 1 file 1 must be an object", err)

      valid, err = json_loader.validate_schema({
        groups = {
          {
            name = "Group",
            files = { { path = "" } },
          },
        },
      })
      eq(false, valid)
      eq("group 1 file 1 path must be a non-empty string", err)
    end)
  end)

  describe("load_json", function()
    it("returns an error when file is missing", function()
      local data, err = json_loader.load_json(test_dir .. "/missing.json")
      eq(nil, data)
      assert(err:match("Failed to read JSON file"), "Expected read error")
    end)

    it("returns an error for malformed JSON", function()
      local path = test_dir .. "/invalid.json"
      write_file(path, "{ bad json ")

      local data, err = json_loader.load_json(path)
      eq(nil, data)
      eq("Failed to parse JSON", err)
    end)

    it("returns an error for empty JSON files", function()
      local path = test_dir .. "/empty.json"
      write_file(path, "")

      local data, err = json_loader.load_json(path)
      eq(nil, data)
      eq("Failed to parse JSON", err)
    end)

    it("returns an error when the JSON file exceeds the size limit", function()
      local max_size = 10 * 1024 * 1024
      local open_stub = stub(uv, "fs_open", function()
        return 1
      end)
      local fstat_stub = stub(uv, "fs_fstat", function()
        return { size = max_size + 1 }
      end)
      local close_stub = stub(uv, "fs_close", function()
        return true
      end)

      local data, err = json_loader.load_json(test_dir .. "/too_large.json")
      eq(nil, data)
      assert(err:match("JSON file is too large"), "Expected size limit error")

      open_stub:revert()
      fstat_stub:revert()
      close_stub:revert()
    end)

    it("returns schema errors for invalid JSON content", function()
      local path = test_dir .. "/schema.json"
      write_file(path, vim.json.encode({ groups = {} }))

      local data, err = json_loader.load_json(path)
      eq(nil, data)
      eq("groups must not be empty", err)
    end)

    it("loads valid JSON content", function()
      local payload = {
        title = "Test",
        groups = {
          { name = "Group A", files = { { path = "src/foo.lua" } } },
        },
      }
      local path = test_dir .. "/valid.json"
      write_file(path, vim.json.encode(payload))

      local data, err = json_loader.load_json(path)
      eq(nil, err)
      eq("Test", data.title)
      eq(1, #data.groups)
      eq("Group A", data.groups[1].name)
      eq("src/foo.lua", data.groups[1].files[1].path)
    end)

    it("loads valid JSON content without title", function()
      local payload = {
        groups = {
          { name = "Group A", files = { { path = "src/foo.lua" } } },
        },
      }
      local path = test_dir .. "/valid_without_title.json"
      write_file(path, vim.json.encode(payload))

      local data, err = json_loader.load_json(path)
      eq(nil, err)
      eq(nil, data.title)
      eq(1, #data.groups)
      eq("Group A", data.groups[1].name)
      eq("src/foo.lua", data.groups[1].files[1].path)
    end)
  end)
end)
