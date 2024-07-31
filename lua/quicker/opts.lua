local config = require("quicker.config")
local util = require("quicker.util")

local M = {}

---@param bufnr integer
local function set_buf_opts(bufnr)
  for k, v in pairs(config.opts) do
    local opt_info = vim.api.nvim_get_option_info2(k, {})
    if opt_info.scope == "buf" then
      local ok, err = pcall(vim.api.nvim_set_option_value, k, v, { buf = bufnr })
      if not ok then
        vim.notify(
          string.format("Error setting quickfix option %s = %s: %s", k, vim.inspect(v), err),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

---@param winid integer
local function set_win_opts(winid)
  for k, v in pairs(config.opts) do
    local opt_info = vim.api.nvim_get_option_info2(k, {})
    if opt_info.scope == "win" then
      local ok, err = pcall(vim.api.nvim_set_option_value, k, v, { scope = "local", win = winid })
      if not ok then
        vim.notify(
          string.format("Error setting quickfix window option %s = %s: %s", k, vim.inspect(v), err),
          vim.log.levels.ERROR
        )
      end
    end
  end
end

---@param bufnr integer
function M.set_opts(bufnr)
  set_buf_opts(bufnr)
  local winid = util.buf_find_win(bufnr)
  if winid then
    set_win_opts(winid)
  else
    local aug = vim.api.nvim_create_augroup("quicker", { clear = false })
    vim.api.nvim_create_autocmd("BufWinEnter", {
      desc = "Set quickfix window options",
      buffer = bufnr,
      group = aug,
      callback = function()
        winid = util.buf_find_win(bufnr)
        if winid then
          set_win_opts(winid)
        end
        return winid ~= nil
      end,
    })
  end
end

return M
