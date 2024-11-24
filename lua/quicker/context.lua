local util = require("quicker.util")

local M = {}

---@class (exact) quicker.QFContext
---@field num_before integer
---@field num_after integer

---@class (exact) quicker.ExpandOpts
---@field before? integer Number of lines of context to show before the line (default 2)
---@field after? integer Number of lines of context to show after the line (default 2)
---@field add_to_existing? boolean
---@field loclist_win? integer

---@param item QuickFixItem
---@param new_text string
local function update_item_text_keep_diagnostics(item, new_text)
  -- If this is an "error" item, replace the text with the source line and store that text
  -- in the user data so we can add it as virtual text later
  if item.type ~= "" and not vim.endswith(new_text, item.text) then
    local user_data = util.get_user_data(item)
    if not user_data.error_text then
      user_data.error_text = item.text
      item.user_data = user_data
    end
  end
  item.text = new_text
end

---@param opts? quicker.ExpandOpts
function M.expand(opts)
  opts = opts or {}
  if not opts.loclist_win and util.get_win_type(0) == "l" then
    opts.loclist_win = vim.api.nvim_get_current_win()
  end
  local qf_list
  if opts.loclist_win then
    qf_list = vim.fn.getloclist(opts.loclist_win, { all = 0 })
  else
    qf_list = vim.fn.getqflist({ all = 0 })
  end
  local winid = qf_list.winid
  if not winid then
    vim.notify("Cannot find quickfix window", vim.log.levels.ERROR)
    return
  end
  local ctx = qf_list.context or {}
  if type(ctx) ~= "table" then
    -- If the quickfix had a non-table context, we're going to have to overwrite it
    ctx = {}
  end
  ---@type quicker.QFContext
  local quicker_ctx = ctx.quicker
  if not quicker_ctx then
    quicker_ctx = { num_before = 0, num_after = 0 }
    ctx.quicker = quicker_ctx
  end
  local curpos = vim.api.nvim_win_get_cursor(winid)[1]
  local cur_item = qf_list.items[curpos]
  local newpos

  -- calculate the number of lines to show before and after the current line
  local num_before = opts.before or 2
  if opts.add_to_existing then
    num_before = num_before + quicker_ctx.num_before
  end
  num_before = math.max(0, num_before)
  quicker_ctx.num_before = num_before
  local num_after = opts.after or 2
  if opts.add_to_existing then
    num_after = num_after + quicker_ctx.num_after
  end
  num_after = math.max(0, num_after)
  quicker_ctx.num_after = num_after

  local items = {}
  ---@type nil|QuickFixItem
  local prev_item
  ---@param i integer
  ---@return nil|QuickFixItem
  local function get_next_item(i)
    local item = qf_list.items[i]
    for j = i + 1, #qf_list.items do
      local next_item = qf_list.items[j]
      -- Next valid item that is on a different line (since we dedupe same-line items)
      if
        next_item.valid == 1 and (item.bufnr ~= next_item.bufnr or item.lnum ~= next_item.lnum)
      then
        return next_item
      end
    end
  end

  for i, item in ipairs(qf_list.items) do
    (function()
      ---@cast item QuickFixItem
      if item.valid == 0 or item.bufnr == 0 then
        return
      end

      if not vim.api.nvim_buf_is_loaded(item.bufnr) then
        vim.fn.bufload(item.bufnr)
      end

      local overlaps_previous = false
      local header_type = "hard"
      local low = math.max(0, item.lnum - 1 - num_before)
      if prev_item then
        if prev_item.bufnr == item.bufnr then
          -- If this is the second match on the same line, skip this item
          if prev_item.lnum == item.lnum then
            return
          end
          header_type = "soft"
          if prev_item.lnum + num_after >= low then
            low = math.min(item.lnum - 1, prev_item.lnum + num_after)
            overlaps_previous = true
          end
        end
      end

      local high = item.lnum + num_after
      local next_item = get_next_item(i)
      if next_item then
        if next_item.bufnr == item.bufnr and next_item.lnum <= high then
          high = next_item.lnum - 1
        end
      end

      local item_start_idx = #items
      local lines = vim.api.nvim_buf_get_lines(item.bufnr, low, high, false)
      for j, line in ipairs(lines) do
        if j + low == item.lnum then
          update_item_text_keep_diagnostics(item, line)
          table.insert(items, item)
        else
          table.insert(items, {
            bufnr = item.bufnr,
            lnum = low + j,
            text = line,
            valid = 0,
            user_data = { lnum = low + j },
          })
        end
        if cur_item.bufnr == item.bufnr and cur_item.lnum == low + j then
          newpos = #items
        end
      end

      -- Add the header to the first item in this sequence, if one is needed
      if prev_item and not overlaps_previous then
        local first_item = items[item_start_idx + 1]
        if first_item then
          first_item.user_data = first_item.user_data or {}
          first_item.user_data.header = header_type
        end
      end

      prev_item = item
    end)()

    if i == curpos and not newpos then
      newpos = #items
    end
  end

  if opts.loclist_win then
    vim.fn.setloclist(
      opts.loclist_win,
      {},
      "r",
      { items = items, title = qf_list.title, context = ctx }
    )
  else
    vim.fn.setqflist({}, "r", { items = items, title = qf_list.title, context = ctx })
  end

  pcall(vim.api.nvim_win_set_cursor, qf_list.winid, { newpos, 0 })
end

---@class (exact) quicker.CollapseArgs
---@field loclist_win? integer
---
function M.collapse(opts)
  opts = opts or {}
  if not opts.loclist_win and util.get_win_type(0) == "l" then
    opts.loclist_win = vim.api.nvim_get_current_win()
  end
  local curpos = vim.api.nvim_win_get_cursor(0)[1]
  local qf_list
  if opts.loclist_win then
    qf_list = vim.fn.getloclist(opts.loclist_win, { all = 0 })
  else
    qf_list = vim.fn.getqflist({ all = 0 })
  end
  local items = {}
  local last_item
  for i, item in ipairs(qf_list.items) do
    if item.valid == 1 then
      if item.user_data then
        -- Clear the header, if present
        item.user_data.header = nil
      end
      table.insert(items, item)
      if i <= curpos then
        last_item = #items
      end
    end
  end

  vim.tbl_filter(function(item)
    return item.valid == 1
  end, qf_list.items)

  local ctx = qf_list.context or {}
  if type(ctx) == "table" then
    local quicker_ctx = ctx.quicker
    if quicker_ctx then
      quicker_ctx = { num_before = 0, num_after = 0 }
      ctx.quicker = quicker_ctx
    end
  end

  if opts.loclist_win then
    vim.fn.setloclist(
      opts.loclist_win,
      {},
      "r",
      { items = items, title = qf_list.title, context = qf_list.context }
    )
  else
    vim.fn.setqflist({}, "r", { items = items, title = qf_list.title, context = qf_list.context })
  end
  if qf_list.winid then
    if last_item then
      vim.api.nvim_win_set_cursor(qf_list.winid, { last_item, 0 })
    end
  end
end

---@param opts? quicker.ExpandOpts
function M.toggle(opts)
  opts = opts or {}
  local ctx
  if opts.loclist_win then
    ctx = vim.fn.getloclist(opts.loclist_win, { context = 0 }).context
  else
    ctx = vim.fn.getqflist({ context = 0 }).context
  end

  if
    type(ctx) == "table"
    and ctx.quicker
    and (ctx.quicker.num_before > 0 or ctx.quicker.num_after > 0)
  then
    M.collapse()
  else
    M.expand(opts)
  end
end

---@class (exact) quicker.RefreshOpts
---@field keep_diagnostics? boolean If a line has a diagnostic type, keep the original text and display it as virtual text after refreshing from source.

---@param loclist_win? integer
---@param opts? quicker.RefreshOpts
function M.refresh(loclist_win, opts)
  opts = vim.tbl_extend("keep", opts or {}, { keep_diagnostics = true })
  if not loclist_win then
    local ok, qf = pcall(vim.fn.getloclist, 0, { filewinid = 0 })
    if ok and qf.filewinid and qf.filewinid ~= 0 then
      loclist_win = qf.filewinid
    end
  end

  local qf_list
  if loclist_win then
    qf_list = vim.fn.getloclist(loclist_win, { all = 0 })
  else
    qf_list = vim.fn.getqflist({ all = 0 })
  end

  local items = {}
  for _, item in ipairs(qf_list.items) do
    if item.bufnr ~= 0 and item.lnum ~= 0 then
      if not vim.api.nvim_buf_is_loaded(item.bufnr) then
        vim.fn.bufload(item.bufnr)
      end
      local line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]
      if line then
        if opts.keep_diagnostics then
          update_item_text_keep_diagnostics(item, line)
        else
          item.text = line
        end
        table.insert(items, item)
      end
    else
      table.insert(items, item)
    end
  end

  if loclist_win then
    vim.fn.setloclist(
      loclist_win,
      {},
      "r",
      { items = items, title = qf_list.title, context = qf_list.context }
    )
  else
    vim.fn.setqflist({}, "r", { items = items, title = qf_list.title, context = qf_list.context })
  end
end

return M
