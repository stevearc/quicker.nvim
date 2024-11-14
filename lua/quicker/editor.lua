local config = require("quicker.config")
local display = require("quicker.display")
local util = require("quicker.util")
local M = {}

---@class (exact) quicker.ParsedLine
---@field filename? string
---@field lnum? integer
---@field text? string

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

---Replace the text in a quickfix line, preserving the lineno virt text
---@param bufnr integer
---@param lnum integer
---@param new_text string
local function replace_qf_line(bufnr, lnum, new_text)
  local old_line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1]

  local old_idx = old_line:find(display.EM_QUAD, 1, true)
  local new_idx = new_text:find(display.EM_QUAD, 1, true)

  -- If we're missing the em quad delimiter in either the old or new text, the best we can do is
  -- replace the whole line
  if not old_idx or not new_idx then
    vim.api.nvim_buf_set_text(bufnr, lnum - 1, 0, lnum - 1, -1, { new_text })
    return
  end

  -- Replace first the text after the em quad, then the filename before.
  -- This keeps the line number virtual text in the same location.
  vim.api.nvim_buf_set_text(
    bufnr,
    lnum - 1,
    old_idx + display.EM_QUAD_LEN - 1,
    lnum - 1,
    -1,
    { new_text:sub(new_idx + display.EM_QUAD_LEN) }
  )
  vim.api.nvim_buf_set_text(bufnr, lnum - 1, 0, lnum - 1, old_idx, { new_text:sub(1, new_idx) })
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

---@param item QuickFixItem
---@param needle string
---@param src_line nil|string
---@return nil|table text_change
---@return nil|string error
local function get_text_edit(item, needle, src_line)
  if not src_line then
    return nil
  elseif item.text == needle then
    return nil
  elseif src_line ~= item.text then
    if item.text:gsub("^%s*", "") == src_line:gsub("^%s*", "") then
      -- If they only disagree in their leading whitespace, just take the changes after the
      -- whitespace and assume that the whitespace hasn't changed.
      -- This can happen if the setqflist caller doesn't use the same whitespace as the source file,
      -- for example overseer.nvim Grep will convert tabs to spaces because the embedded terminal
      -- will convert tabs to spaces.
      needle = src_line:match("^%s*") .. needle:gsub("^%s*", "")
    else
      return nil, "buffer text does not match source text"
    end
  end

  return {
    newText = needle,
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

---Deserialize qf_prefixes from the buffer, converting vim.NIL to nil
---@param bufnr integer
---@return table<integer, string>
local function load_qf_prefixes(bufnr)
  local prefixes = vim.b[bufnr].qf_prefixes or {}
  for k, v in pairs(prefixes) do
    if v == vim.NIL then
      prefixes[k] = nil
    end
  end
  return prefixes
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
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local errors = {}
  local exit_early = false
  local prefixes = load_qf_prefixes(bufnr)
  local ext_id_to_item_idx = vim.b[bufnr].qf_ext_id_to_item_idx
  for i, line in ipairs(lines) do
    (function()
      local extmarks = util.get_lnum_extmarks(bufnr, i, line:len())
      assert(#extmarks <= 1, string.format("Found more than one extmark on line %d", i))
      local found_idx
      if extmarks[1] then
        found_idx = ext_id_to_item_idx[extmarks[1][1]]
      end

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

      -- Trim the filename off of the line
      local idx = string.find(line, display.EM_QUAD, 1, true)
      if not idx then
        add_qf_error(
          bufnr,
          i,
          "The delimiter between filename and text has been deleted. Undo, delete line, or :Refresh.",
          "DiagnosticError"
        )
        if winid then
          vim.api.nvim_win_set_cursor(winid, { i, 0 })
        end
        exit_early = true
        return
      end
      local text = line:sub(idx + display.EM_QUAD_LEN)

      local item = qf_list.items[found_idx]
      if item.bufnr ~= 0 and item.lnum ~= 0 then
        if not vim.api.nvim_buf_is_loaded(item.bufnr) then
          vim.fn.bufload(item.bufnr)
        end
        local src_line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]

        -- add the whitespace prefix back to the parsed line text
        if config.trim_leading_whitespace == "common" then
          text = (prefixes[item.bufnr] or "") .. text
        elseif config.trim_leading_whitespace == "all" and src_line then
          text = src_line:match("^%s*") .. text
        end

        if src_line and text ~= src_line then
          if text:gsub("^%s*", "") == src_line:gsub("^%s*", "") then
            -- If they only disagree in their leading whitespace, just take the changes after the
            -- whitespace and assume that the whitespace hasn't changed
            text = src_line:match("^%s*") .. text:gsub("^%s*", "")
          end
        end

        local text_edit, err = get_text_edit(item, text, src_line)
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
          errors[#new_items] = line
          return
        end
      end

      -- add item to future qflist
      item.text = text
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
        replace_qf_line(bufnr, lnum, new_text)
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
