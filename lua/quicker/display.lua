local config = require("quicker.config")
local fs = require("quicker.fs")
local highlight = require("quicker.highlight")

local M = {}

---@class (exact) QuickFixUserData
---@field header? "hard"|"soft"
---@field lnum? integer

---@class (exact) QuickFixItem
---@field text string
---@field type string
---@field lnum integer line number in the buffer (first line is 1)
---@field end_lnum integer end of line number if the item is multiline
---@field col integer column number (first column is 1)
---@field end_col integer end of column number if the item has range
---@field vcol 0|1 if true "col" is visual column. If false "col" is byte index
---@field nr integer error number
---@field pattern string search pattern used to locate the error
---@field bufnr integer number of buffer that has the file name
---@field module string
---@field valid 0|1
---@field user_data? any

---@param item QuickFixItem
---@return QuickFixUserData
local function get_user_data(item)
  if type(item.user_data) == "table" then
    return item.user_data
  else
    return {}
  end
end

---@param type string
---@return string
local function get_icon(type)
  return config.type_icons[type:upper()] or "U"
end

local sign_highlight_map = {
  E = "DiagnosticSignError",
  W = "DiagnosticSignWarn",
  I = "DiagnosticSignInfo",
  H = "DiagnosticSignHint",
  N = "DiagnosticSignHint",
}

---@param item QuickFixItem
local function get_filename_from_item(item)
  if item.valid == 1 then
    if item.module and item.module ~= "" then
      return item.module
    elseif item.bufnr > 0 then
      local bufname = vim.api.nvim_buf_get_name(item.bufnr)
      local path = fs.shorten_path(bufname)
      local max_len = config.max_filename_width()
      if path:len() > max_len then
        path = "…" .. path:sub(path:len() - max_len - 1)
      end
      return path
    else
      return ""
    end
  else
    return ""
  end
end

local _col_width_cache = {}
---@param id integer
---@param items QuickFixItem[]
---@return integer
local function get_cached_qf_col_width(id, items)
  local cached = _col_width_cache[id]
  if not cached or cached[2] ~= #items then
    local max_len = 0
    for _, item in ipairs(items) do
      max_len = math.max(max_len, vim.api.nvim_strwidth(get_filename_from_item(item)))
    end

    cached = { max_len + 1, #items }
    _col_width_cache[id] = cached
  end
  return cached[1]
end

---@param items QuickFixItem[]
---@return table<integer, string>
local function calc_whitespace_prefix(items)
  local prefixes = {}
  if not config.trim_leading_whitespace then
    return prefixes
  end

  for _, item in ipairs(items) do
    if item.bufnr ~= 0 and not item.text:match("^%s*$") then
      local prefix = prefixes[item.bufnr]
      if not prefix or not vim.startswith(item.text, prefix) then
        prefixes[item.bufnr] = item.text:match("^%s*")
      end
    end
  end
  return prefixes
end

-- Highlighting can be slow because it requires loading buffers and parsing them with treesitter, so
-- we pipeline it and break it up with defers to keep the editor responsive.
local add_qf_highlights
-- We have two queues, one to apply "fast" highlights, and one that will load the buffer (slow)
-- and then apply more correct highlights. The second queue is always processed after the first.
local _pending_fast_highlights = {}
local _pending_bufload_highlights = {}
local _running = false
local function do_next_highlight()
  if _running then
    return
  end
  _running = true

  local next_info = table.remove(_pending_fast_highlights, 1)
  if not next_info then
    next_info = table.remove(_pending_bufload_highlights, 1)
  end

  if next_info then
    local ok, err = xpcall(add_qf_highlights, debug.traceback, next_info)
    if not ok then
      vim.api.nvim_err_writeln(err)
    end
  else
    _running = false
    return
  end

  vim.defer_fn(function()
    _running = false
    do_next_highlight()
  end, 20)
end

---@param queue QuickFixTextFuncInfo[]
---@param info QuickFixTextFuncInfo
local function add_info_to_queue(queue, info)
  for _, i in ipairs(queue) do
    -- If we're already processing a highlight for this quickfix, just expand the range
    if i.id == info.id and i.winid == info.winid and i.quickfix == info.quickfix then
      i.start_idx = math.min(i.start_idx, info.start_idx)
      i.end_idx = math.max(i.end_idx, info.end_idx)
      return
    end
  end
  table.insert(queue, info)
end

---@param info QuickFixTextFuncInfo
local function schedule_highlights(info)
  -- If this info already has force_bufload, then we don't want to add it to the first queue.
  if not info.force_bufload then
    add_info_to_queue(_pending_fast_highlights, info)
  end

  if config.highlight.load_buffers then
    local info2 = vim.deepcopy(info)
    info2.force_bufload = true
    add_info_to_queue(_pending_bufload_highlights, info2)
  end

  vim.schedule(do_next_highlight)
end

---@param qfbufnr integer
---@param item QuickFixItem
---@param line string
---@param lnum integer
local function add_item_highlights_from_buf(qfbufnr, item, line, lnum)
  local b = config.borders
  local prefixes = vim.b[qfbufnr].qf_prefixes or {}
  local ns = vim.api.nvim_create_namespace("quicker_highlights")
  -- TODO re-apply highlights when a buffer is loaded or a LSP receives semantic tokens
  local src_line = vim.api.nvim_buf_get_lines(item.bufnr, item.lnum - 1, item.lnum, false)[1]
  if not src_line then
    return
  end

  -- If the lines differ only in leading whitespace, we should add highlights anyway and adjust
  -- the offset.
  local item_space = item.text:match("^%s*"):len()
  local src_space = src_line:match("^%s*"):len()

  -- Only add highlights if the text in the quickfix matches the source line
  if item.text:sub(item_space + 1) == src_line:sub(src_space + 1) then
    local offset = line:find(b.vert, 1, true)
    offset = line:find(b.vert, (offset or 0) + b.vert:len(), true) + b.vert:len() - 1
    offset = offset - (prefixes[item.bufnr] or ""):len()
    offset = offset - src_space + item_space

    -- Add treesitter highlights
    if config.highlight.treesitter then
      for _, hl in ipairs(highlight.buf_get_ts_highlights(item.bufnr, item.lnum)) do
        local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
        vim.api.nvim_buf_set_extmark(qfbufnr, ns, lnum - 1, start_col + offset, {
          hl_group = hl_group,
          end_col = end_col + offset,
          priority = 100,
          strict = false,
        })
      end
    end

    -- Add LSP semantic token highlights
    if config.highlight.lsp then
      for _, hl in ipairs(highlight.buf_get_lsp_highlights(item.bufnr, item.lnum)) do
        local start_col, end_col, hl_group, priority = hl[1], hl[2], hl[3], hl[4]
        vim.api.nvim_buf_set_extmark(qfbufnr, ns, lnum - 1, start_col + offset, {
          hl_group = hl_group,
          end_col = end_col + offset,
          priority = vim.highlight.priorities.semantic_tokens + priority,
          strict = false,
        })
      end
    end
  end
end

---@param info QuickFixTextFuncInfo
add_qf_highlights = function(info)
  local qf_list
  if info.quickfix == 1 then
    qf_list = vim.fn.getqflist({ id = info.id, items = 0, qfbufnr = 0 })
  else
    qf_list = vim.fn.getloclist(info.winid, { id = info.id, items = 0, qfbufnr = 0 })
  end
  if not qf_list.qfbufnr or qf_list.qfbufnr == 0 then
    return
  elseif info.end_idx < info.start_idx then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(qf_list.qfbufnr, 0, -1, false)
  local ns = vim.api.nvim_create_namespace("quicker_highlights")

  -- Only clear the error namespace during the first pass of "fast" highlighting
  if not info.force_bufload then
    local err_ns = vim.api.nvim_create_namespace("quicker_err")
    vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, err_ns, 0, -1)
  end

  local start = vim.uv.hrtime() / 1e6
  for i = info.start_idx, info.end_idx do
    vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, ns, i - 1, i)
    ---@type nil|QuickFixItem
    local item = qf_list.items[i]
    -- If the quickfix list has changed length since the async highlight job has started,
    -- we should abort and let the next async highlight task pick it up.
    if not item then
      return
    end

    local line = lines[i]
    if item.bufnr ~= 0 and line then
      local loaded = vim.api.nvim_buf_is_loaded(item.bufnr)
      if not loaded and info.force_bufload then
        vim.fn.bufload(item.bufnr)
        loaded = true
      end

      if loaded then
        add_item_highlights_from_buf(qf_list.qfbufnr, item, line, i)
      elseif config.highlight.treesitter then
        for _, hl in ipairs(highlight.get_heuristic_ts_highlights(item, line)) do
          local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
          vim.api.nvim_buf_set_extmark(qf_list.qfbufnr, ns, i - 1, start_col, {
            hl_group = hl_group,
            end_col = end_col,
            priority = 100,
            strict = false,
          })
        end
      end
    end

    -- Set sign if item has a type
    if item.type and item.type ~= "" then
      vim.api.nvim_buf_set_extmark(qf_list.qfbufnr, ns, i - 1, 0, {
        sign_text = get_icon(item.type),
        sign_hl_group = sign_highlight_map[item.type:upper()],
        invalidate = true,
      })
    end

    local user_data = get_user_data(item)
    if user_data.header == "hard" then
      vim.api.nvim_buf_add_highlight(qf_list.qfbufnr, ns, "QuickFixHeaderHard", i - 1, 0, -1)
    elseif user_data.header == "soft" then
      vim.api.nvim_buf_add_highlight(qf_list.qfbufnr, ns, "QuickFixHeaderSoft", i - 1, 0, -1)
    end

    -- If we've been processing for too long, defer to preserve editor responsiveness
    local delta = vim.uv.hrtime() / 1e6 - start
    if delta > 50 then
      info.start_idx = i + 1
      schedule_highlights(info)
      return
    end
  end

  vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, ns, info.end_idx, -1)
end

---@param str string
---@param len integer
---@return string
local function rpad(str, len)
  return str .. string.rep(" ", len - vim.api.nvim_strwidth(str))
end

---@param items QuickFixItem[]
---@return integer
local function get_lnum_width(items)
  local max_len = 2
  local max = 99
  for _, item in ipairs(items) do
    if item.lnum > max then
      max_len = tostring(item.lnum):len()
      max = item.lnum
    end
  end
  return max_len
end

---@param text string
---@param prefix? string
local function remove_prefix(text, prefix)
  if prefix and prefix ~= "" then
    return text:sub(prefix:len() + 1)
  else
    return text
  end
end

---@class QuickFixTextFuncInfo
---@field id integer
---@field start_idx integer
---@field end_idx integer
---@field winid integer
---@field quickfix 1|0
---@field force_bufload? boolean field injected by us to control if we're forcing a bufload for the syntax highlighting

-- TODO when appending to a qflist, the alignment can be thrown off
-- TODO when appending to a qflist, the prefix could mismatch earlier lines
---@param info QuickFixTextFuncInfo
function M.quickfixtextfunc(info)
  local b = config.borders
  local qf_list
  local ret = {}
  if info.quickfix == 1 then
    qf_list = vim.fn.getqflist({ id = info.id, items = 0, qfbufnr = 0 })
  else
    qf_list = vim.fn.getloclist(info.winid, { id = info.id, items = 0, qfbufnr = 0 })
  end
  ---@type QuickFixItem[]
  local items = qf_list.items
  local lnum_width = get_lnum_width(items)
  local col_width = get_cached_qf_col_width(info.id, items)
  local lnum_fmt = string.format("%%%ds", lnum_width)
  local prefixes = calc_whitespace_prefix(items)

  for i = info.start_idx, info.end_idx do
    local item = items[i]
    local user_data = get_user_data(item)
    if item.valid == 1 then
      -- Matching line
      local pieces = { rpad(get_filename_from_item(item), col_width) }
      if item.lnum ~= 0 then
        table.insert(pieces, lnum_fmt:format(item.lnum))
      else
        table.insert(pieces, string.rep(" ", lnum_width))
      end
      table.insert(pieces, remove_prefix(item.text, prefixes[item.bufnr]))
      table.insert(ret, table.concat(pieces, b.vert))
    elseif user_data.header == "hard" then
      -- Header when expanded QF list
      local pieces = {
        string.rep(b.strong_header, col_width),
        b.strong_cross,
        string.rep(b.strong_header, lnum_width),
      }
      local header_len = config.header_length("hard", col_width + lnum_width + 2)
      if header_len > 0 then
        table.insert(pieces, b.strong_cross)
        table.insert(pieces, string.rep(b.strong_header, header_len))
      else
        table.insert(pieces, b.strong_end)
      end
      table.insert(ret, table.concat(pieces, ""))
    elseif user_data.header == "soft" then
      -- Soft header when expanded QF list
      local pieces = {
        string.rep(b.soft_header, col_width),
        b.soft_cross,
        string.rep(b.soft_header, lnum_width),
      }
      local header_len = config.header_length("soft", col_width + lnum_width + 2)
      if header_len > 0 then
        table.insert(pieces, b.soft_cross)
        table.insert(pieces, string.rep(b.soft_header, header_len))
      else
        table.insert(pieces, b.soft_end)
      end
      table.insert(ret, table.concat(pieces, ""))
    else
      -- Non-matching line, either from context or normal QF results parsed with errorformat
      local lnum = user_data.lnum or " "
      local pieces = {
        string.rep(" ", col_width),
        lnum_fmt:format(lnum),
        remove_prefix(item.text, prefixes[item.bufnr]),
      }
      table.insert(ret, table.concat(pieces, b.vert))
    end
  end

  -- If we just rendered the last item, add highlights
  if info.end_idx == #items then
    schedule_highlights(info)

    -- If we have appended some items to the quickfix, we need to update qf_items (just the appended ones)
    if qf_list.qfbufnr > 0 then
      local stored_items = vim.b[qf_list.qfbufnr].qf_items or {}
      for i = info.start_idx, info.end_idx do
        stored_items[i] = items[i]
      end
      vim.b[qf_list.qfbufnr].qf_items = stored_items
      vim.b[qf_list.qfbufnr].qf_prefixes = prefixes
    end
  end
  return ret
end

return M
