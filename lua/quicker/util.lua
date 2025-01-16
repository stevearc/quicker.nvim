local M = {}

---@param bufnr integer
---@return nil|integer
function M.buf_find_win(bufnr)
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      return winid
    end
  end
end

---@param loclist_win? integer Check if loclist is open for the given window. If nil, check quickfix.
M.is_open = function(loclist_win)
  if loclist_win then
    return vim.fn.getloclist(loclist_win or 0, { winid = 0 }).winid ~= 0
  else
    return vim.fn.getqflist({ winid = 0 }).winid ~= 0
  end
end

---@param winid nil|integer
---@return nil|"c"|"l"
M.get_win_type = function(winid)
  if not winid or winid == 0 then
    winid = vim.api.nvim_get_current_win()
  end
  local info = vim.fn.getwininfo(winid)[1]
  if info.quickfix == 0 then
    return nil
  elseif info.loclist == 0 then
    return "c"
  else
    return "l"
  end
end

---@param item QuickFixItem
---@return QuickFixUserData
M.get_user_data = function(item)
  if type(item.user_data) == "table" then
    return item.user_data
  else
    return {}
  end
end

---Get valid location extmarks for a line in the quickfix
---@param bufnr integer
---@param lnum integer
---@param line_len? integer how long this particular line is
---@param ns? integer namespace of extmarks
---@return table[] extmarks
M.get_lnum_extmarks = function(bufnr, lnum, line_len, ns)
  if not ns then
    ns = vim.api.nvim_create_namespace("quicker_locations")
  end
  if not line_len then
    local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
    line_len = line:len()
  end
  local extmarks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    ns,
    { lnum - 1, 0 },
    { lnum - 1, line_len },
    { details = true }
  )
  return vim.tbl_filter(function(mark)
    return not mark[4].invalid
  end, extmarks)
end

---Return true if the window is a full-height leaf window
---@param winid? integer
---@return boolean
M.is_full_height_vsplit = function(winid)
  if not winid or winid == 0 then
    winid = vim.api.nvim_get_current_win()
  end
  local layout = vim.fn.winlayout()
  -- If the top layout is not vsplit, then it's not a vertical leaf
  if layout[1] ~= "row" then
    return false
  end
  for _, v in ipairs(layout[2]) do
    if v[1] == "leaf" and v[2] == winid then
      return true
    end
  end

  return false
end

return M
