local config = require("quicker.config")

local M = {}

---@param bufnr integer
function M.set_keymaps(bufnr)
  for _, defn in ipairs(config.keys) do
    vim.keymap.set(defn.mode or "n", defn[1], defn[2], {
      buffer = bufnr,
      desc = defn.desc,
      expr = defn.expr,
      nowait = defn.nowait,
      remap = defn.remap,
      replace_keycodes = defn.replace_keycodes,
      silent = defn.silent,
    })
  end
end

return M
