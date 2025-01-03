local config = require("quicker.config")
local fs = require("quicker.fs")
local highlight = require("quicker.highlight")
local util = require("quicker.util")

local M = {}

local EM_QUAD = " "
local EM_QUAD_LEN = EM_QUAD:len()
M.EM_QUAD = EM_QUAD
M.EM_QUAD_LEN = EM_QUAD_LEN

---@class (exact) QuickFixUserData
---@field header? "hard"|"soft" When present, this line is a header
---@field lnum? integer Encode the lnum separately for valid=0 items
---@field error_text? string Error text to be added as virtual text on the line

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
local virt_text_highlight_map = {
  E = "DiagnosticVirtualTextError",
  W = "DiagnosticVirtualTextWarn",
  I = "DiagnosticVirtualTextInfo",
  H = "DiagnosticVirtualTextHint",
  N = "DiagnosticVirtualTextHint",
}

---@param item QuickFixItem
M.get_filename_from_item = function(item)
  if item.module and item.module ~= "" then
    return item.module
  elseif item.bufnr > 0 then
    local bufname = vim.api.nvim_buf_get_name(item.bufnr)
    local path = fs.shorten_path(bufname)
    local max_len = config.max_filename_width()
    if max_len == 0 then
      return ""
    elseif path:len() > max_len then
      path = "…" .. path:sub(path:len() - max_len - 1)
    end
    return path
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
      max_len = math.max(max_len, vim.api.nvim_strwidth(M.get_filename_from_item(item)))
    end

    cached = { max_len, #items }
    _col_width_cache[id] = cached
  end
  return cached[1]
end

---@param items QuickFixItem[]
---@return table<integer, string>
local function calc_whitespace_prefix(items)
  local prefixes = {}
  if config.trim_leading_whitespace ~= "common" then
    return prefixes
  end

  for _, item in ipairs(items) do
    if item.bufnr ~= 0 and not item.text:match("^%s*$") then
      local prefix = prefixes[item.bufnr]
      if not prefix or not vim.startswith(item.text, prefix) then
        local new_prefix = item.text:match("^%s*")

        -- The new line should have strictly less whitespace as the previous line. If not, then
        -- there is some whitespace disagreement (e.g. tabs vs spaces) and we should not try to trim
        -- anything.
        if prefix and not vim.startswith(prefix, new_prefix) then
          new_prefix = ""
        end
        prefixes[item.bufnr] = new_prefix

        if new_prefix == "" then
          break
        end
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
    local offset = line:find(EM_QUAD, 1, true) + EM_QUAD_LEN - 1
    local prefix = prefixes[item.bufnr]
    if type(prefix) == "string" then
      -- Since prefixes get deserialized from vim.b, if there are holes in the map they get
      -- filled with `vim.NIL`, so we have to check that the retrieved value is a string.
      offset = offset - prefix:len()
    end
    offset = offset - src_space + item_space
    if config.trim_leading_whitespace == "all" then
      offset = offset - item_space
    end

    -- Add treesitter highlights
    if config.highlight.treesitter then
      for _, hl in ipairs(highlight.buf_get_ts_highlights(item.bufnr, item.lnum)) do
        local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
        if end_col == -1 then
          end_col = src_line:len()
        end
        -- If the highlight starts at the beginning of the source line, then it might be off the
        -- buffer in the quickfix because we've removed leading whitespace. If so, clamp the value
        -- to 0. Except, for some reason 0 gives incorrect results, but -1 works properly even
        -- though -1 should indicate the *end* of the line. Not sure why this work, but it does.
        local hl_start = math.max(-1, start_col + offset)
        vim.api.nvim_buf_set_extmark(qfbufnr, ns, lnum - 1, hl_start, {
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

---@param qfbufnr integer
---@param info QuickFixTextFuncInfo
local function highlight_buffer_when_entered(qfbufnr, info)
  if vim.b[qfbufnr].pending_highlight then
    return
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Highlight quickfix buffer when entered",
    buffer = qfbufnr,
    nested = true,
    once = true,
    callback = function()
      vim.b[qfbufnr].pending_highlight = nil
      info.start_idx = 1
      info.end_idx = vim.api.nvim_buf_line_count(qfbufnr)
      schedule_highlights(info)
    end,
  })
  vim.b[qfbufnr].pending_highlight = true
end

---@param info QuickFixTextFuncInfo
---@return {qfbufnr: integer, id: integer, context?: any}
---@overload fun(info: QuickFixTextFuncInfo, all: true): {qfbufnr: integer, id: integer, items: QuickFixItem[], context?: any}
local function load_qf(info, all)
  local query
  if all then
    query = { all = 0 }
  else
    query = { id = info.id, items = 0, qfbufnr = 0, context = 0 }
  end
  if info.quickfix == 1 then
    return vim.fn.getqflist(query)
  else
    return vim.fn.getloclist(info.winid, query)
  end
end

---@param info QuickFixTextFuncInfo
add_qf_highlights = function(info)
  local qf_list = load_qf(info, true)
  local qfbufnr = qf_list.qfbufnr
  if not qfbufnr or qfbufnr == 0 then
    return
  elseif info.end_idx < info.start_idx then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(qfbufnr, 0, -1, false)
  if #lines == 1 and lines[1] == "" then
    -- If the quickfix buffer is not visible, it is possible that quickfixtextfunc has run but the
    -- buffer has not been populated yet. If that is the case, we should exit early and ensure that
    -- the highlighting task runs again when the buffer is opened in a window.
    -- see https://github.com/stevearc/quicker.nvim/pull/8
    highlight_buffer_when_entered(qfbufnr, info)
    return
  end
  local ns = vim.api.nvim_create_namespace("quicker_highlights")

  -- Only clear the error namespace during the first pass of "fast" highlighting
  if not info.force_bufload then
    local err_ns = vim.api.nvim_create_namespace("quicker_err")
    vim.api.nvim_buf_clear_namespace(qfbufnr, err_ns, 0, -1)
  end

  local start = vim.uv.hrtime() / 1e6
  for i = info.start_idx, info.end_idx do
    vim.api.nvim_buf_clear_namespace(qfbufnr, ns, i - 1, i)
    ---@type nil|QuickFixItem
    local item = qf_list.items[i]
    -- If the quickfix list has changed length since the async highlight job has started,
    -- we should abort and let the next async highlight task pick it up.
    if not item then
      return
    end

    local line = lines[i]
    if not line then
      break
    end
    if item.bufnr ~= 0 then
      local loaded = vim.api.nvim_buf_is_loaded(item.bufnr)
      if not loaded and info.force_bufload then
        vim.fn.bufload(item.bufnr)
        loaded = true
      end

      if loaded then
        add_item_highlights_from_buf(qfbufnr, item, line, i)
      elseif config.highlight.treesitter then
        local filename = vim.split(line, EM_QUAD, { plain = true })[1]
        local offset = filename:len() + EM_QUAD_LEN
        local text = line:sub(offset + 1)
        for _, hl in ipairs(highlight.get_heuristic_ts_highlights(item, text)) do
          local start_col, end_col, hl_group = hl[1], hl[2], hl[3]
          start_col = start_col + offset
          end_col = end_col + offset
          vim.api.nvim_buf_set_extmark(qfbufnr, ns, i - 1, start_col, {
            hl_group = hl_group,
            end_col = end_col,
            priority = 100,
            strict = false,
          })
        end
      end
    end

    local user_data = util.get_user_data(item)
    -- Set sign if item has a type
    if item.type and item.type ~= "" then
      local mark = {
        sign_text = get_icon(item.type),
        sign_hl_group = sign_highlight_map[item.type:upper()],
        invalidate = true,
      }
      if user_data.error_text then
        mark.virt_text = {
          { user_data.error_text, virt_text_highlight_map[item.type:upper()] or "Normal" },
        }
      end
      vim.api.nvim_buf_set_extmark(qfbufnr, ns, i - 1, 0, mark)
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
  local ret
  if prefix and prefix ~= "" then
    ret = text:sub(prefix:len() + 1)
  else
    ret = text
  end

  return ret
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
---@return string[]
function M.quickfixtextfunc(info)
  local b = config.borders
  local qf_list = load_qf(info, true)
  local locations = {}
  local invalid_filenames = {}
  local headers = {}
  local ret = {}
  local items = qf_list.items
  local lnum_width = get_lnum_width(items)
  local col_width = get_cached_qf_col_width(info.id, items)
  local lnum_fmt = string.format("%%%ds", lnum_width)
  local prefixes = calc_whitespace_prefix(items)
  local no_filenames = col_width == 0

  local function get_virt_text(lnum)
    -- If none of the quickfix items have filenames, we don't need the lnum column and we only need
    -- to show a single delimiter. Technically we don't need any delimiter, but this maintains some
    -- of the original qf behavior while being a bit more visually appealing.
    if no_filenames then
      return { { b.vert, "Delimiter" } }
    else
      return {
        { b.vert, "Delimiter" },
        { lnum_fmt:format(lnum), "QuickFixLineNr" },
        { b.vert, "Delimiter" },
      }
    end
  end

  for i = info.start_idx, info.end_idx do
    local item = items[i]
    local user_data = util.get_user_data(item)

    -- First check if there's a header that we need to save to render as virtual text later
    if user_data.header == "hard" then
      -- Header when expanded QF list
      local pieces = {
        string.rep(b.strong_header, col_width + 1),
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
      table.insert(headers, { i, { { table.concat(pieces, ""), "QuickFixHeaderHard" } } })
    elseif user_data.header == "soft" then
      -- Soft header when expanded QF list
      local pieces = {
        string.rep(b.soft_header, col_width + 1),
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
      table.insert(headers, { i, { { table.concat(pieces, ""), "QuickFixHeaderSoft" } } })
    end

    -- Construct the lines and save the filename + lnum to render as virtual text later
    local trimmed_text
    if config.trim_leading_whitespace == "all" then
      trimmed_text = item.text:gsub("^%s*", "")
    elseif config.trim_leading_whitespace == "common" then
      trimmed_text = remove_prefix(item.text, prefixes[item.bufnr])
    else
      trimmed_text = item.text
    end
    if item.valid == 1 then
      -- Matching line
      local lnum = item.lnum == 0 and " " or item.lnum
      local filename = rpad(M.get_filename_from_item(item), col_width)
      table.insert(locations, get_virt_text(lnum))
      table.insert(ret, filename .. EM_QUAD .. trimmed_text)
    elseif user_data.lnum then
      -- Non-matching line from quicker.nvim context lines
      local filename = string.rep(" ", col_width)
      table.insert(locations, get_virt_text(user_data.lnum))
      table.insert(ret, filename .. EM_QUAD .. trimmed_text)
    else
      -- Other non-matching line
      local lnum = item.lnum == 0 and " " or item.lnum
      local filename = rpad(M.get_filename_from_item(item), col_width)
      table.insert(locations, get_virt_text(lnum))
      invalid_filenames[#locations] = true
      table.insert(ret, filename .. EM_QUAD .. trimmed_text)
    end
  end

  -- Render the filename+lnum and the headers as virtual text
  local start_idx = info.start_idx
  local set_virt_text
  set_virt_text = function()
    qf_list = load_qf(info)
    if qf_list.qfbufnr > 0 then
      -- Sometimes the buffer is not fully populated yet. If so, we should try again later.
      local num_lines = vim.api.nvim_buf_line_count(qf_list.qfbufnr)
      if num_lines < info.end_idx then
        vim.schedule(set_virt_text)
        return
      end

      local ns = vim.api.nvim_create_namespace("quicker_locations")
      vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, ns, start_idx - 1, -1)
      local header_ns = vim.api.nvim_create_namespace("quicker_headers")
      vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, header_ns, start_idx - 1, -1)
      local filename_ns = vim.api.nvim_create_namespace("quicker_filenames")
      vim.api.nvim_buf_clear_namespace(qf_list.qfbufnr, filename_ns, start_idx - 1, -1)

      local idmap = {}
      local lines = vim.api.nvim_buf_get_lines(qf_list.qfbufnr, start_idx - 1, -1, false)
      for i, loc in ipairs(locations) do
        local end_col = lines[i]:find(EM_QUAD, 1, true) or col_width
        local lnum = start_idx + i - 1
        local id =
          vim.api.nvim_buf_set_extmark(qf_list.qfbufnr, ns, lnum - 1, end_col + EM_QUAD_LEN - 1, {
            right_gravity = false,
            virt_text = loc,
            virt_text_pos = "inline",
            invalidate = true,
          })
        idmap[id] = lnum

        -- Highlight the filename
        vim.api.nvim_buf_set_extmark(qf_list.qfbufnr, filename_ns, lnum - 1, 0, {
          hl_group = invalid_filenames[i] and "QuickFixFilenameInvalid" or "QuickFixFilename",
          right_gravity = false,
          end_col = end_col,
          priority = 100,
          invalidate = true,
        })
      end
      vim.b[qf_list.qfbufnr].qf_ext_id_to_item_idx = idmap

      for _, pair in ipairs(headers) do
        local i, header = pair[1], pair[2]
        local lnum = start_idx + i - 1
        vim.api.nvim_buf_set_extmark(qf_list.qfbufnr, header_ns, lnum - 1, 0, {
          virt_lines = { header },
          virt_lines_above = true,
        })
      end
    end
  end
  vim.schedule(set_virt_text)

  -- If we just rendered the last item, add highlights
  if info.end_idx == #items then
    schedule_highlights(info)

    if qf_list.qfbufnr > 0 then
      vim.b[qf_list.qfbufnr].qf_prefixes = prefixes
    end
  end

  return ret
end

return M
