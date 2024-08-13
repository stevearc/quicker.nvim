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

return M
