local oop = require("diffview.oop")
local FileTree = require("diffview.ui.models.file_tree.file_tree").FileTree

local M = {}

---@class GroupedFileDict : diffview.Object
---@field [integer] FileEntry
---@field groups { name: string, files: FileEntry[], tree: FileTree }[]
---@field title string|nil
local GroupedFileDict = oop.create_class("GroupedFileDict")

---@param title? string
function GroupedFileDict:init(title)
  self.title = title
  self.groups = {}
end

function GroupedFileDict:__index(k)
  if type(k) == "number" then
    local offset = 0

    for _, group in ipairs(self.groups) do
      local files = group.files
      local idx = k - offset
      if idx >= 1 and idx <= #files then
        return files[idx]
      end

      offset = offset + #files
    end
  else
    return GroupedFileDict[k]
  end
end

---@param name string
---@param files FileEntry[]
---@return { name: string, files: FileEntry[], tree: FileTree }
function GroupedFileDict:add_group(name, files)
  local group = {
    name = name,
    files = files or {},
    tree = FileTree(files or {}),
  }
  table.insert(self.groups, group)
  return group
end

function GroupedFileDict:len()
  local total = 0
  for _, group in ipairs(self.groups) do
    total = total + #group.files
  end
  return total
end

function GroupedFileDict:iter()
  local i = 0
  local group_idx = 1
  local file_idx = 0
  local groups = self.groups

  ---@return integer?, FileEntry?
  return function()
    while group_idx <= #groups do
      local files = groups[group_idx].files

      if file_idx < #files then
        file_idx = file_idx + 1
        i = i + 1
        return i, files[file_idx]
      end

      group_idx = group_idx + 1
      file_idx = 0
    end
  end
end

function GroupedFileDict:update_file_trees()
  for _, group in ipairs(self.groups) do
    group.tree = FileTree(group.files)
  end
end

function GroupedFileDict:is_grouped()
  return true
end

M.GroupedFileDict = GroupedFileDict
return M
