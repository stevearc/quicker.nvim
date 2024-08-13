local config = require("quicker.config")
local util = require("quicker.util")
local M = {}

---@class (exact) quicker.ParsedLine
---@field filename? string
---@field lnum? integer
---@field text? string

---@param line string
---@return quicker.ParsedLine
local function parse_line(line)
  local pieces = vim.split(line, config.borders.vert)
  if #pieces < 3 then
    return { text = line }
  end
  -- If the buffer text contains the delimiter, we need to reassemble the text
  local filename = vim.trim(pieces[1])
  local lnum = tonumber(pieces[2])
  local text = pieces[3]
  if #pieces > 3 then
    table.remove(pieces, 1)
    table.remove(pieces, 1)
    text = table.concat(pieces, config.borders.vert)
  end
  return {
    filename = filename,
    lnum = lnum,
    text = text,
  }
end

---@param item QuickFixItem
---@param filename? string
---@return boolean
local function filename_match(item, filename)
  if not filename or item.bufnr == 0 then
    return false
  else
    local bufname = vim.api.nvim_buf_get_name(item.bufnr)
    -- Trim off the leading "~" if this was a shortened path in the home dir
    if vim.startswith(filename, "~") then
      filename = filename:sub(2)
    end
    -- Trim off the leading "…" if this was a truncated path
    if vim.startswith(filename, "…") then
      filename = filename:sub(1 + string.len("…"))
    end
    return vim.endswith(bufname, filename)
  end
end

---@param n integer
---@param base string
---@param pluralized? string
---@return string
local function plural(n, base, pluralized)
  if n == 1 then
    return base
  elseif pluralized then
    return pluralized
  else
    return base .. "s"
  end
end

---@param item QuickFixItem
---@return QuickFixUserData
local function get_user_data(item)
  if type(item.user_data) == "table" then
    return item.user_data
  else
    return {}
  end
end

---@param bufnr integer
---@param lnum integer
---@param text string
---@param text_hl? string
local function add_qf_error(bufnr, lnum, text, text_hl)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]
  local col = line:find(config.borders.vert, 1, true)
  if col then
    col = line:find(config.borders.vert, col + config.borders.vert:len(), true)
      + config.borders.vert:len()
      - 1
  else
    col = 0
  end
  local offset = vim.api.nvim_strwidth(line:sub(1, col))
  local ns = vim.api.nvim_create_namespace("quicker_err")
  vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, col, {
    virt_text = { { config.type_icons.E, "DiagnosticSignError" } },
    virt_text_pos = "inline",
    virt_lines = {
      {
        { string.rep(" ", offset), "Normal" },
        { "↳ ", "DiagnosticError" },
        { text, text_hl or "Normal" },
      },
    },
  })
end

---@param bufnr integer
---@param lnum integer
---@param text string
local function replace_text(bufnr, lnum, text)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  local pieces = vim.split(line, config.borders.vert)
  pieces[3] = text
  pieces[4] = nil -- just in case there was a delimiter in the text
  local new_line = table.concat(pieces, config.borders.vert)
  vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, false, { new_line })
end

---@param items QuickFixItem[]
---@param start integer
---@param needle quicker.ParsedLine
---@param prefixes table<integer, string>
---@return integer? next_start
local function find_next(items, start, needle, prefixes)
  -- If the line we're looking for has no filename, search for matching text
  if not needle.filename then
    -- Check if we're looking for a header
    local header_types = {}
    if vim.startswith(needle.text, config.borders.strong_header) then
      table.insert(header_types, "hard")
    elseif vim.startswith(needle.text, config.borders.soft_header) then
      table.insert(header_types, "soft")
    end
    if not vim.tbl_isempty(header_types) then
      for i = start, #items do
        local item = items[i]
        local user_data = get_user_data(item)
        if vim.tbl_contains(header_types, user_data.header) then
          return i
        end
      end
      return
    end

    for i = start, #items do
      local item = items[i]
      if item.bufnr == 0 and item.text == needle.text then
        return i
      end
    end
    return
  end

  -- If we're looking for a line with a filename and no lnum check for filename + text
  if needle.filename and not needle.lnum then
    for i = start, #items do
      local item = items[i]
      if filename_match(item, needle.filename) then
        local full_text = (prefixes[item.bufnr] or "") .. needle.text
        if item.text == full_text then
          return i
        end
      end
    end
    return
  end

  -- Search for filename and lnum match
  for i = start, #items do
    local item = items[i]
    local lnum = item.lnum
    if not lnum or lnum == 0 then
      lnum = get_user_data(item).lnum
    end
    if filename_match(item, needle.filename) and lnum == needle.lnum then
      return i
    end
  end
end

---@param item QuickFixItem
---@param needle quicker.ParsedLine
---@return nil|table text_change
---@return nil|string error
local function get_text_edit(item, needle)
  local src_line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]
  if item.text == needle.text then
    return nil
  elseif src_line ~= item.text then
    if item.text:gsub("^%s*", "") == src_line:gsub("^%s*", "") then
      -- If they only disagree in their leading whitespace, just take the changes after the
      -- whitespace and assume that the whitespace hasn't changed.
      -- This can happen if the setqflist caller doesn't use the same whitespace as the source file,
      -- for example overseer.nvim Grep will convert tabs to spaces because the embedded terminal
      -- will convert tabs to spaces.
      needle.text = src_line:match("^%s*") .. needle.text:gsub("^%s*", "")
    else
      return nil, "buffer text does not match source text"
    end
  end

  return {
    newText = needle.text,
    range = {
      start = {
        line = item.lnum - 1,
        character = 0,
      },
      ["end"] = {
        line = item.lnum - 1,
        character = #src_line,
      },
    },
  }
end

---@param bufnr integer
---@param loclist_win? integer
local function save_changes(bufnr, loclist_win)
  if not vim.bo[bufnr].modified then
    return
  end
  local ns = vim.api.nvim_create_namespace("quicker_err")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local qf_list
  if loclist_win then
    qf_list = vim.fn.getloclist(loclist_win, { all = 0 })
  else
    qf_list = vim.fn.getqflist({ all = 0 })
  end

  -- We save the quickfix items in BufReadPost, because they are used to create the quickfix
  -- buffer text. However, if the source buffers are modified, the quickfix items will actually
  -- update their lnum automatically next time we call getqflist. This is useful, but makes it
  -- harder to match the buffer line to the quickfix item. So we use saved_items to match the line
  -- to the item, and then map to the current quickfix item when performing the mutation.
  ---@type QuickFixItem[]
  local saved_items = vim.b[bufnr].qf_items
  if not saved_items or #saved_items ~= #qf_list.items then
    vim.notify("quicker.nvim: saved quickfix items are out of sync", vim.log.levels.WARN)
    ---@type QuickFixItem[]
    saved_items = qf_list.items
  end

  local changes = {}
  local function add_change(buf, text_edit)
    if not changes[buf] then
      changes[buf] = {}
    end
    local last_edit = changes[buf][#changes[buf]]
    if last_edit and vim.deep_equal(last_edit.range, text_edit.range) then
      if last_edit.newText == text_edit.newText then
        return
      else
        return "conflicting changes on the same line"
      end
    end
    table.insert(changes[buf], text_edit)
  end

  -- Parse the buffer
  local winid = util.buf_find_win(bufnr)
  local new_items = {}
  local item_idx = 1
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local errors = {}
  local exit_early = false
  local prefixes = vim.b[bufnr].qf_prefixes or {}
  for i, line in ipairs(lines) do
    (function()
      local parsed = parse_line(line)
      local found_idx = find_next(saved_items, item_idx, parsed, prefixes)

      -- If we didn't find a match, the line was most likely added or reordered
      if not found_idx then
        add_qf_error(
          bufnr,
          i,
          "quicker.nvim does not support adding or reordering quickfix items",
          "DiagnosticError"
        )
        if winid then
          vim.api.nvim_win_set_cursor(winid, { i, 0 })
        end
        exit_early = true
        return
      end
      item_idx = found_idx + 1

      local item = qf_list.items[found_idx]
      if item.bufnr ~= 0 and item.lnum ~= 0 then
        if not vim.api.nvim_buf_is_loaded(item.bufnr) then
          vim.fn.bufload(item.bufnr)
        end
        -- add the whitespace prefix back to the parsed line text
        parsed.text = (prefixes[item.bufnr] or "") .. parsed.text

        local src_line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]
        if parsed.text ~= src_line then
          if parsed.text:gsub("^%s*", "") == src_line:gsub("^%s*", "") then
            -- If they only disagree in their leading whitespace, just take the changes after the
            -- whitespace and assume that the whitespace hasn't changed
            parsed.text = src_line:match("^%s*") .. parsed.text:gsub("^%s*", "")
          else
          end
        end

        local text_edit, err = get_text_edit(item, parsed)
        if text_edit then
          local chng_err = add_change(item.bufnr, text_edit)
          if chng_err then
            add_qf_error(bufnr, i, chng_err, "DiagnosticError")
            if winid then
              vim.api.nvim_win_set_cursor(winid, { i, 0 })
            end
            exit_early = true
            return
          end
        elseif err then
          table.insert(new_items, item)
          errors[#new_items] = parsed.text
          return
        end
      end

      -- add item to future qflist
      item.text = parsed.text
      table.insert(new_items, item)
    end)()
    if exit_early then
      vim.schedule(function()
        vim.bo[bufnr].modified = true
      end)
      return
    end
  end

  ---@type table<integer, boolean>
  local buf_was_modified = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    buf_was_modified[buf] = vim.bo[buf].modified
  end
  local autosave = config.edit.autosave
  local num_applied = 0
  local modified_bufs = {}
  for chg_buf, text_edits in pairs(changes) do
    modified_bufs[chg_buf] = true
    num_applied = num_applied + #text_edits
    vim.lsp.util.apply_text_edits(text_edits, chg_buf, "utf-8")
    local was_modified = buf_was_modified[chg_buf]
    local should_save = autosave == true or (autosave == "unmodified" and not was_modified)
    -- Autosave changed buffers if they were not modified before
    if should_save then
      vim.api.nvim_buf_call(chg_buf, function()
        vim.cmd.update({ mods = { emsg_silent = true, noautocmd = true } })
      end)
    end
  end
  if num_applied > 0 then
    local num_files = vim.tbl_count(modified_bufs)
    local num_errors = vim.tbl_count(errors)
    if num_errors > 0 then
      local total = num_errors + num_applied
      vim.notify(
        string.format(
          "Applied %d/%d %s in %d %s",
          num_applied,
          total,
          plural(total, "change"),
          num_files,
          plural(num_files, "file")
        ),
        vim.log.levels.WARN
      )
    else
      vim.notify(
        string.format(
          "Applied %d %s in %d %s",
          num_applied,
          plural(num_applied, "change"),
          num_files,
          plural(num_files, "file")
        ),
        vim.log.levels.INFO
      )
    end
  end

  local view
  if winid then
    view = vim.api.nvim_win_call(winid, function()
      return vim.fn.winsaveview()
    end)
  end
  if loclist_win then
    vim.fn.setloclist(
      loclist_win,
      {},
      "r",
      { items = new_items, title = qf_list.title, context = qf_list.context }
    )
  else
    vim.fn.setqflist(
      {},
      "r",
      { items = new_items, title = qf_list.title, context = qf_list.context }
    )
  end
  if winid and view then
    vim.api.nvim_win_call(winid, function()
      vim.fn.winrestview(view)
    end)
  end

  -- Schedule this so it runs after the save completes, and the buffer will be correctly marked as modified
  if not vim.tbl_isempty(errors) then
    vim.schedule(function()
      -- Mark the lines with changes that could not be applied
      for lnum, new_text in pairs(errors) do
        replace_text(bufnr, lnum, new_text)
        local item = new_items[lnum]
        local src_line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]
        add_qf_error(bufnr, lnum, src_line)
        if winid and vim.api.nvim_win_is_valid(winid) then
          vim.api.nvim_win_set_cursor(winid, { lnum, 0 })
        end
      end
    end)

    -- Notify user that some changes could not be applied
    local cnt = vim.tbl_count(errors)
    local change_text = cnt == 1 and "change" or "changes"
    vim.notify(
      string.format(
        "%d %s could not be applied due to conflicts in the source buffer. Please :Refresh and try again.",
        cnt,
        change_text
      ),
      vim.log.levels.ERROR
    )
  end
end

-- TODO add support for undo past last change

---@param bufnr integer
function M.setup_editor(bufnr)
  local aug = vim.api.nvim_create_augroup("quicker", { clear = false })
  local loclist_win
  vim.api.nvim_buf_call(bufnr, function()
    local ok, qf = pcall(vim.fn.getloclist, 0, { filewinid = 0 })
    if ok and qf.filewinid and qf.filewinid ~= 0 then
      loclist_win = qf.filewinid
    end
  end)

  -- save the items for later
  if loclist_win then
    vim.b[bufnr].qf_items = vim.fn.getloclist(loclist_win)
  else
    vim.b[bufnr].qf_items = vim.fn.getqflist()
  end

  -- Set a name for the buffer so we can save it
  local bufname = string.format("quickfix-%d", bufnr)
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    vim.api.nvim_buf_set_name(bufnr, bufname)
  end
  vim.bo[bufnr].modifiable = true

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    desc = "quicker.nvim apply changes on write",
    group = aug,
    buffer = bufnr,
    nested = true,
    callback = function(args)
      save_changes(args.buf, loclist_win)
      vim.bo[args.buf].modified = false
    end,
  })
end

return M
