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
  -- Wait for the virtual text extmarks to be set
  if vim.bo[bufnr].filetype == "qf" then
    vim.wait(10, function()
      return false
    end)
  end
  local util = require("quicker.util")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Add virtual text to lines
  local headers = {}
  local header_ns = vim.api.nvim_create_namespace("quicker_headers")
  for i, v in ipairs(lines) do
    local extmarks = util.get_lnum_extmarks(bufnr, i, v:len())
    assert(#extmarks <= 1, "Expected at most one extmark per line")
    local mark = extmarks[1]
    if mark then
      local start_col = mark[3]
      local data = mark[4]
      local virt_text = table.concat(
        vim.tbl_map(function(vt)
          return vt[1]
        end, data.virt_text),
        ""
      )
      lines[i] = v:sub(0, start_col) .. virt_text .. v:sub(start_col + 1)

      extmarks = util.get_lnum_extmarks(bufnr, i, v:len(), header_ns)
      assert(#extmarks <= 1, "Expected at most one extmark per line")
      mark = extmarks[1]
      if mark and mark[4].virt_lines then
        table.insert(headers, { i, mark[4].virt_lines[1][1][1] })
      end
    end
  end

  for i = #headers, 1, -1 do
    local lnum, header = unpack(headers[i])
    table.insert(lines, lnum, header)
  end

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
