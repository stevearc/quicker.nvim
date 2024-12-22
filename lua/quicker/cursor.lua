local M = {}

local function constrain_cursor()
  local display = require("quicker.display")
  local cur = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(0, cur[1] - 1, cur[1], true)[1]
  local idx = line:find(display.EM_QUAD, 1, true)
  if not idx then
    return
  end
  local min_col = idx + display.EM_QUAD_LEN - 1
  if cur[2] < min_col then
    vim.api.nvim_win_set_cursor(0, { cur[1], min_col })
  end
end

---@param bufnr number
function M.constrain_cursor(bufnr)
  -- HACK: we have to defer this call because sometimes the autocmds don't take effect.
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local aug = vim.api.nvim_create_augroup("quicker", { clear = false })
    vim.api.nvim_create_autocmd("InsertEnter", {
      desc = "Constrain quickfix cursor position",
      group = aug,
      nested = true,
      buffer = bufnr,
      -- For some reason the cursor bounces back to its original position,
      -- so we have to defer the call
      callback = vim.schedule_wrap(constrain_cursor),
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "ModeChanged" }, {
      desc = "Constrain quickfix cursor position",
      nested = true,
      group = aug,
      buffer = bufnr,
      callback = constrain_cursor,
    })
  end)
end

return M
