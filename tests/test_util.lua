require("plenary.async").tests.add_to_env()
local M = {}

local tmp_files = {}
M.reset_editor = function()
  vim.cmd.tabonly({ mods = { silent = true } })
  for i, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if i > 1 then
      vim.api.nvim_win_close(winid, true)
    end
  end
  vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  vim.fn.setqflist({})
  vim.fn.setloclist(0, {})
  for _, filename in ipairs(tmp_files) do
    vim.uv.fs_unlink(filename)
  end
  tmp_files = {}

  require("quicker").setup({
    header_length = function()
      -- Make this deterministic so the snapshots are stable
      return 8
    end,
  })
end

---@param basename string
---@param lines integer|string[]
---@return string
M.make_tmp_file = function(basename, lines)
  vim.fn.mkdir("tests/tmp", "p")
  local filename = "tests/tmp/" .. basename
  table.insert(tmp_files, filename)
  local f = assert(io.open(filename, "w"))
  if type(lines) == "table" then
    for _, line in ipairs(lines) do
      f:write(line .. "\n")
    end
  else
    for i = 1, lines do
      f:write("line " .. i .. "\n")
    end
  end
  f:close()
  return filename
end

---@param name string
---@return string[]
local function load_snapshot(name)
  local path = "tests/snapshots/" .. name
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local f = assert(io.open(path, "r"))
  local lines = {}
  for line in f:lines() do
    table.insert(lines, line)
  end
  f:close()
  return lines
end

---@param name string
---@param lines string[]
local function save_snapshot(name, lines)
  vim.fn.mkdir("tests/snapshots", "p")
  local path = "tests/snapshots/" .. name
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n"))
  f:close()
  return lines
end

---@param bufnr integer
---@param name string
M.assert_snapshot = function(bufnr, name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if os.getenv("UPDATE_SNAPSHOTS") then
    save_snapshot(name, lines)
  else
    local expected = load_snapshot(name)
    assert.are.same(expected, lines)
  end
end

---@param context fun(): fun()
---@param fn fun()
M.with = function(context, fn)
  local cleanup = context()
  local ok, err = pcall(fn)
  cleanup()
  if not ok then
    error(err)
  end
end

return M
