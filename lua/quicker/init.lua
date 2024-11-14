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

  -- If the quickfix/loclist is already open, refresh it so the quickfixtextfunc will take effect.
  -- This is required for lazy-loading to work properly.
  local list = vim.fn.getqflist({ all = 0 })
  if not vim.tbl_isempty(list.items) then
    vim.fn.setqflist({}, "r", list)
  end
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) then
      local llist = vim.fn.getloclist(winid, { all = 0 })
      if not vim.tbl_isempty(list.items) then
        vim.fn.setloclist(winid, {}, "r", llist)
      end
    end
  end
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
---@param opts? quicker.RefreshOpts
M.refresh = function(loclist_win, opts)
  return require("quicker.context").refresh(loclist_win, opts)
end

---@param loclist_win? integer Check if loclist is open for the given window. If nil, check quickfix.
M.is_open = function(loclist_win)
  if loclist_win then
    return vim.fn.getloclist(loclist_win or 0, { winid = 0 }).winid ~= 0
  else
    return vim.fn.getqflist({ winid = 0 }).winid ~= 0
  end
end

---@class quicker.OpenCmdMods: vim.api.keyset.parse_cmd.mods

---@class (exact) quicker.OpenOpts
---@field loclist? boolean Toggle the loclist instead of the quickfix list
---@field focus? boolean Focus the quickfix window after toggling (default false)
---@field height? integer Height of the quickfix window when opened. Defaults to number of items in the list.
---@field min_height? integer Minimum height of the quickfix window. Default 4.
---@field max_height? integer Maximum height of the quickfix window. Default 10.
---@field open_cmd_mods? quicker.OpenCmdMods A table of modifiers for the quickfix or loclist open commands.

---Toggle the quickfix or loclist window.
---@param opts? quicker.OpenOpts
M.toggle = function(opts)
  ---@type {loclist: boolean, focus: boolean, height?: integer, min_height: integer, max_height: integer, open_cmd_mods?: quicker.OpenCmdMods}
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    loclist = false,
    focus = false,
    min_height = 4,
    max_height = 10,
    open_cmd_mods = {},
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
  ---@type {loclist: boolean, focus: boolean, height?: integer, min_height: integer, max_height: integer, open_cmd_mods?: quicker.OpenCmdMods}
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    loclist = false,
    focus = false,
    min_height = 4,
    max_height = 10,
    open_cmd_mods = {},
  })
  local height
  if opts.loclist then
    local ok, err = pcall(vim.cmd.lopen, { mods = opts.open_cmd_mods })
    if not ok then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    height = #vim.fn.getloclist(0)
  else
    vim.cmd.copen({ mods = opts.open_cmd_mods })
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

---@class (exact) quicker.FindFileOpts
---@field keep_win? boolean Keep the cursor in the current window
---@field jump? boolean Jump to the quickfix item location after selecting a file
---@field last? boolean Jump to the last item of the file instead of the first

---Select and jump to a file in the quickfix or loclist.
---@param opts? quicker.FindFileOpts
---@note
--- This function exists because the filenames are rendered with virtual text, so you cannot find
--- them using `/` or similar. This uses vim.ui.select to find and jump to the first quickfix item
--- from a particular file.
M.find_file = function(opts)
  opts = opts or {}
  local display = require("quicker.display")
  local util = require("quicker.util")

  local start_win = vim.api.nvim_get_current_win()
  local list = vim.fn.getloclist(0, { winid = 0, items = 0 })
  if list.winid == 0 then
    list = vim.fn.getqflist({ winid = 0, items = 0 })
  end
  if list.winid == 0 then
    vim.notify("No quickfix or loclist window found", vim.log.levels.WARN)
    return
  end

  ---@type {[1]: integer, [2]: string}[]
  local filenames = {}
  local seen = {}
  for i, item in ipairs(list.items) do
    if item.bufnr ~= 0 then
      local filename = display.get_filename_from_item(item)
      if not seen[filename] then
        local pair = { i, filename }
        seen[filename] = pair
        table.insert(filenames, pair)
      elseif opts.last then
        seen[filename][1] = i
      end
    end
  end

  if #filenames == 0 then
    vim.notify("No files found in quickfix or loclist", vim.log.levels.WARN)
    return
  end

  vim.ui.select(filenames, {
    prompt = "quickfix file",
    kind = "quicker_file",
    format_item = function(item)
      return item[2]
    end,
  }, function(pair)
    if pair then
      if opts.jump then
        local type = util.get_win_type(list.winid)
        assert(type, "Quickfix window type is nil")
        vim.cmd({ cmd = type .. type, count = pair[1] })
      else
        vim.api.nvim_win_set_cursor(list.winid, { pair[1], 0 })
        vim.api.nvim_set_current_win(list.winid)
      end

      if opts.keep_win then
        vim.api.nvim_set_current_win(start_win)
      end
    end
  end)
end

return M
