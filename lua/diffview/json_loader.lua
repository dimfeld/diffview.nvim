local utils = require("diffview.utils")
local uv = vim.loop

local M = {}

---@class JsonFileSpec
---@field path string

---@class JsonGroup
---@field name string
---@field description? string
---@field files JsonFileSpec[]

---@class JsonData
---@field title? string
---@field groups JsonGroup[]

local MAX_JSON_SIZE = 10 * 1024 * 1024

local function read_file(file_path)
  local fd
  local function close_fd()
    if not fd then return true end

    local close_ok, close_err = pcall(uv.fs_close, fd)
    fd = nil
    return close_ok, close_err
  end

  local ok, result = pcall(function()
    fd = assert(uv.fs_open(file_path, "r", 438))
    local fstat = assert(uv.fs_fstat(fd))
    if fstat.size > MAX_JSON_SIZE then
      error(
        ("JSON file is too large (%d bytes). Max allowed is %d bytes."):format(
          fstat.size,
          MAX_JSON_SIZE
        )
      )
    end
    return assert(uv.fs_read(fd, fstat.size, 0))
  end)

  local close_ok, close_err = close_fd()

  if not ok then return nil, result end

  if not close_ok then return nil, close_err end

  return result
end

---@param data table
---@return boolean valid
---@return string|nil error
function M.validate_schema(data)
  if type(data) ~= "table" then return false, "JSON root must be an object" end

  if data.title ~= nil and type(data.title) ~= "string" then
    return false, "title must be a string"
  end

  if type(data.groups) ~= "table" or not utils.islist(data.groups) then
    return false, "groups must be an array"
  end

  if #data.groups == 0 then return false, "groups must not be empty" end

  for i, group in ipairs(data.groups) do
    if type(group) ~= "table" then return false, ("group %d must be an object"):format(i) end

    if type(group.name) ~= "string" or group.name == "" then
      return false, ("group %d name must be a non-empty string"):format(i)
    end

    if group.description ~= nil and type(group.description) ~= "string" then
      return false, ("group %d description must be a string"):format(i)
    end

    if type(group.files) ~= "table" or not utils.islist(group.files) then
      return false, ("group %d files must be an array"):format(i)
    end

    for j, file_spec in ipairs(group.files) do
      if type(file_spec) ~= "table" then
        return false, ("group %d file %d must be an object"):format(i, j)
      end

      if type(file_spec.path) ~= "string" or file_spec.path == "" then
        return false, ("group %d file %d path must be a non-empty string"):format(i, j)
      end
    end
  end

  return true
end

---@param file_path string
---@return JsonData|nil data
---@return string|nil error
function M.load_json(file_path)
  local content, read_err = read_file(file_path)
  if not content then
    return nil, ("Failed to read JSON file: %s"):format(read_err or "unknown error")
  end

  local decode_ok, data = pcall(vim.json.decode, content)
  if not decode_ok or not data then return nil, "Failed to parse JSON" end

  local valid, err = M.validate_schema(data)
  if not valid then return nil, err end

  return data
end

return M
