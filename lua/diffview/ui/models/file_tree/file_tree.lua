local oop = require("diffview.oop")
local utils = require("diffview.utils")
local Node = require("diffview.ui.models.file_tree.node").Node
local Model = require("diffview.ui.model").Model

local pl = utils.path

local M = {}

---@class DirData
---@field name string
---@field path string
---@field kind vcs.FileKind
---@field collapsed boolean
---@field status string
---@field _node Node

---@class FileTree : Model
---@field root Node
local FileTree = oop.create_class("FileTree", Model)

---FileTree constructor
---@param files FileEntry[]?
function FileTree:init(files)
  self.root = Node("__ROOT__")

  for _, file in ipairs(files or {}) do
    self:add_file_entry(file)
  end
end

---@param file FileEntry
function FileTree:add_file_entry(file)
  local parts = pl:explode(file.path)
  local cur_node = self.root

  local path = parts[1]

  -- Create missing intermediate pathname components
  for i = 1, #parts - 1 do
    local name = parts[i]

    if i > 1 then
      path = pl:join(path, parts[i])
    end

    if not cur_node.children[name] then
      ---@type DirData
      local dir_data = {
        name = name,
        path = path,
        kind = file.kind,
        collapsed = false,
        status = " ", -- updated later in FileTree:update_statuses()
      }
      cur_node = cur_node:add_child(Node(name, dir_data))
    else
      cur_node = cur_node.children[name]
    end
  end

  cur_node:add_child(Node(parts[#parts], file))
end

---@param a string
---@param b string
---@return string
local function combine_statuses(a, b)
  if a == " " or a == "?" or a == "!" or a == b then
    return b
  end

  return "M"
end

function FileTree:update_statuses()
  ---@return string the node's status
  local function recurse(node)
    if not node:has_children() then
      return node.data.status
    end

    local parent_status = " "

    for _, child in ipairs(node.children) do
      local child_status = recurse(child)
      parent_status = combine_statuses(parent_status, child_status)
    end

    node.data.status = parent_status

    return parent_status
  end

  for _, node in ipairs(self.root.children) do
    recurse(node)
  end
end

---Create component schema for rendering the tree.
---@param data { flatten_dirs: boolean, file_filter?: fun(file: FileEntry): boolean }
---@return CompSchema
function FileTree:create_comp_schema(data)
  self.root:sort()
  ---@type CompSchema
  local schema = {}
  local file_filter = data.file_filter

  ---Check if a node or any of its descendants have visible files.
  ---@param node Node
  ---@return boolean
  local function has_visible_files(node)
    if not node:has_children() then
      -- Leaf node: check if file passes filter
      if file_filter then
        return file_filter(node.data)
      end
      return true
    end

    -- Directory node: check if any child has visible files
    for _, child in ipairs(node.children) do
      if has_visible_files(child) then
        return true
      end
    end
    return false
  end

  ---@param parent CompSchema
  ---@param node Node
  local function recurse(parent, node)
    if not node:has_children() then
      -- Leaf node (file): apply filter
      if file_filter and not file_filter(node.data) then
        return
      end
      parent[#parent + 1] = { name = "file", context = node.data }
      return
    end

    -- Directory node: skip if no visible files in subtree
    if file_filter and not has_visible_files(node) then
      return
    end

    ---@type DirData
    local dir_data = node.data

    if data.flatten_dirs then
      while #node.children == 1 and node.children[1]:has_children() do
        -- When flattening, also skip empty directories if filtering
        if file_filter and not has_visible_files(node.children[1]) then
          break
        end
        ---@type DirData
        local subdir_data = node.children[1].data
        dir_data = {
          name = pl:join(dir_data.name, subdir_data.name),
          path = subdir_data.path,
          kind = subdir_data.kind,
          collapsed = dir_data.collapsed and subdir_data.collapsed,
          status = dir_data.status,
          _node = node,
        }
        node = node.children[1]
      end
    end

    local items = { name = "items" }
    local struct = {
      name = "directory",
      context = dir_data,
      { name = "dir_name" },
      items,
    }
    parent[#parent + 1] = struct

    for _, child in ipairs(node.children) do
      recurse(items, child)
    end
  end

  for _, node in ipairs(self.root.children) do
    recurse(schema, node)
  end

  return schema
end

M.FileTree = FileTree

return M
