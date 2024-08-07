local M = {}

---@param opts? quicker.SetupOptions
local function setup(opts)
  local config = require("quicker.config")
  config.setup(opts)

  local aug = vim.api.nvim_create_augroup("quicker", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    group = aug,
    desc = "quicker.nvim set up quickfix mappings",
    callback = function(args)
      require("quicker.highlight").set_highlight_groups()
      require("quicker.opts").set_opts(args.buf)
      require("quicker.keys").set_keymaps(args.buf)
      vim.api.nvim_buf_create_user_command(args.buf, "Refresh", function()
        require("quicker.context").refresh()
      end, {
        desc = "Update the quickfix list with the current buffer text for each item",
      })

      if config.constrain_cursor then
        require("quicker.cursor").constrain_cursor(args.buf)
      end

      config.on_qf(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    pattern = "*",
    group = aug,
    desc = "quicker.nvim set up quickfix highlight groups",
    callback = function()
      require("quicker.highlight").set_highlight_groups()
    end,
  })
  if config.edit.enabled then
    vim.api.nvim_create_autocmd("BufReadPost", {
      pattern = "quickfix",
      group = aug,
      desc = "quicker.nvim set up quickfix editing",
      callback = function(args)
        require("quicker.editor").setup_editor(args.buf)
      end,
    })
  end

  vim.o.quickfixtextfunc = "v:lua.require'quicker.display'.quickfixtextfunc"
end

M.setup = setup

---Expand the context around the quickfix results.
---@param opts? quicker.ExpandOpts
---@note
--- If there are multiple quickfix items for the same line of a file, only the first
--- one will remain after calling expand().
M.expand = function(opts)
  return require("quicker.context").expand(opts)
end

---Collapse the context around quickfix results, leaving only the `valid` items.
M.collapse = function()
  return require("quicker.context").collapse()
end

---Update the quickfix list with the current buffer text for each item.
---@param loclist_win? integer
M.refresh = function(loclist_win)
  return require("quicker.context").refresh(loclist_win)
end

---@param loclist_win? integer Check if loclist is open for the given window. If nil, check quickfix.
M.is_open = function(loclist_win)
  if loclist_win then
    return vim.fn.getloclist(loclist_win, { winid = 0 }).winid ~= 0
  else
    return vim.fn.getqflist({ winid = 0 }).winid ~= 0
  end
end

---@class (exact) quicker.OpenOpts
---@field loclist? boolean Toggle the loclist instead of the quickfix list
---@field focus? boolean Focus the quickfix window after toggling (default false)
---@field height? integer Height of the quickfix window when opened. Defaults to number of items in the list.
---@field min_height? integer Minimum height of the quickfix window. Default 4.
---@field max_height? integer Maximum height of the quickfix window. Default 10.

---Toggle the quickfix or loclist window.
---@param opts? quicker.OpenOpts
M.toggle = function(opts)
  ---@type {loclist: boolean, focus: boolean, height?: integer, min_height: integer, max_height: integer}
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    loclist = false,
    focus = false,
    min_height = 4,
    max_height = 10,
  })
  local loclist_win = opts.loclist and 0 or nil
  if M.is_open(loclist_win) then
    M.close({ loclist = opts.loclist })
  else
    M.open(opts)
  end
end

---Open the quickfix or loclist window.
---@param opts? quicker.OpenOpts
M.open = function(opts)
  ---@type {loclist: boolean, focus: boolean, height?: integer, min_height: integer, max_height: integer}
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    loclist = false,
    focus = false,
    min_height = 4,
    max_height = 10,
  })
  local height
  if opts.loclist then
    local ok, err = pcall(vim.cmd.lopen)
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    height = #vim.fn.getloclist(0)
  else
    vim.cmd.copen()
    height = #vim.fn.getqflist()
  end

  height = math.min(opts.max_height, math.max(opts.min_height, height))
  vim.api.nvim_win_set_height(0, height)

  if not opts.focus then
    vim.cmd.wincmd({ args = { "p" } })
  end
end

---@class (exact) quicker.CloseOpts
---@field loclist? boolean Close the loclist instead of the quickfix list

---Close the quickfix or loclist window.
---@param opts? quicker.CloseOpts
M.close = function(opts)
  if opts and opts.loclist then
    vim.cmd.lclose()
  else
    vim.cmd.cclose()
  end
end

return M