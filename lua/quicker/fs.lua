local M = {}

---@type boolean
M.is_windows = vim.uv.os_uname().version:match("Windows")

M.is_mac = vim.uv.os_uname().sysname == "Darwin"

M.is_linux = not M.is_windows and not M.is_mac

---@type string
M.sep = M.is_windows and "\\" or "/"

---@param ... string
M.join = function(...)
  return table.concat({ ... }, M.sep)
end

---Check if OS path is absolute
---@param dir string
---@return boolean
M.is_absolute = function(dir)
  if M.is_windows then
    return dir:match("^%a:\\")
  else
    return vim.startswith(dir, "/")
  end
end

M.abspath = function(path)
  if not M.is_absolute(path) then
    path = vim.fn.fnamemodify(path, ":p")
  end
  return path
end

local home_dir = assert(vim.uv.os_homedir())

---@param path string
---@param relative_to? string Shorten relative to this path (default cwd)
---@return string
M.shorten_path = function(path, relative_to)
  if not relative_to then
    relative_to = vim.fn.getcwd()
  end
  local relpath
  if M.is_subpath(relative_to, path) then
    local idx = relative_to:len() + 1
    -- Trim the dividing slash if it's not included in relative_to
    if not vim.endswith(relative_to, "/") and not vim.endswith(relative_to, "\\") then
      idx = idx + 1
    end
    relpath = path:sub(idx)
    if relpath == "" then
      relpath = "."
    end
  end
  if M.is_subpath(home_dir, path) then
    local homepath = "~" .. path:sub(home_dir:len() + 1)
    if not relpath or homepath:len() < relpath:len() then
      return homepath
    end
  end
  return relpath or path
end

--- Returns true if candidate is a subpath of root, or if they are the same path.
---@param root string
---@param candidate string
---@return boolean
M.is_subpath = function(root, candidate)
  if candidate == "" then
    return false
  end
  root = vim.fs.normalize(M.abspath(root))
  -- Trim trailing "/" from the root
  if root:find("/", -1) then
    root = root:sub(1, -2)
  end
  candidate = vim.fs.normalize(M.abspath(candidate))
  if M.is_windows then
    root = root:lower()
    candidate = candidate:lower()
  end
  if root == candidate then
    return true
  end
  local prefix = candidate:sub(1, root:len())
  if prefix ~= root then
    return false
  end

  local candidate_starts_with_sep = candidate:find("/", root:len() + 1, true) == root:len() + 1
  local root_ends_with_sep = root:find("/", root:len(), true) == root:len()

  return candidate_starts_with_sep or root_ends_with_sep
end

return M
