local GroupedFileDict = require("diffview.grouped_file_dict").GroupedFileDict

local M = {}

local doc_extensions =
  { md = true, markdown = true, rst = true, adoc = true, org = true, txt = true }
local test_extensions = { snap = true, feature = true }
local doc_names = {
  readme = true,
  changelog = true,
  changes = true,
  contributing = true,
  license = true,
  licence = true,
  authors = true,
  code_of_conduct = true,
}

---@param path string
---@return "Implementation"|"Documentation"|"Tests"
function M.classify(path)
  local lower = path:lower()
  local name = lower:match("([^/]+)$") or lower
  local stem, extension = name:match("^(.*)%.([^%.]+)$")
  stem = stem or name

  if
    lower:match("^tests?/")
    or lower:match("/tests?/")
    or lower:match("^specs?/")
    or lower:match("/specs?/")
    or lower:match("^__tests__/")
    or lower:match("/__tests__/")
    or stem:match("^test[_%-]")
    or stem:match("^spec[_%-]")
    or stem:match("[_%.%-]tests?$")
    or stem:match("[_%.%-]spec$")
    or (extension and test_extensions[extension])
  then
    return "Tests"
  end

  if
    lower:match("^docs?/")
    or lower:match("/docs?/")
    or lower:match("^documentation/")
    or lower:match("/documentation/")
    or doc_names[stem]
    or (extension and doc_extensions[extension])
  then
    return "Documentation"
  end

  return "Implementation"
end

---@param files FileDict
---@return GroupedFileDict
function M.group(files)
  local groups = { Implementation = {}, Documentation = {}, Tests = {} }
  for _, file in files:iter() do
    local group = groups[M.classify(file.path)]
    group[#group + 1] = file
  end

  local result = GroupedFileDict()
  for _, name in ipairs({ "Implementation", "Documentation", "Tests" }) do
    result:add_group(name, groups[name])
  end
  return result
end

return M
