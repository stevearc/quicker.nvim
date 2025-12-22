local util = require("quicker.util")
local M = {}

M.seek_to_position = function()
  if util.is_open(0) then
    local qf_list = vim.fn.getloclist(0, { winid = 0, items = 0 })
    local new_pos = M.calculate_pos(qf_list.items)
    if new_pos then
      M.set_pos(qf_list.winid, new_pos)
    end
  end

  if util.is_open() then
    local qf_list = vim.fn.getqflist({ winid = 0, items = 0 })
    local new_pos = M.calculate_pos(qf_list.items)
    if new_pos then
      M.set_pos(qf_list.winid, new_pos)
    end
  end
end

---Calculate the current buffer/cursor location in the quickfix list
---@param list QuickFixItem[]
---@return nil|integer
M.calculate_pos = function(list)
  if vim.bo.buftype ~= "" then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum, col = cursor[1], cursor[2] + 1
  -- If the quickfix list is sorted, we return the closest item that lies before or exactly at the
  -- cursor. If not sorted, we just find the closest by distance and tiebreak the previous one.
  local closest_idx, sorted_closest_idx, prev_lnum, prev_col
  local qf_is_sorted = true
  for i, entry in ipairs(list) do
    if entry.bufnr == bufnr then
      -- If the previous buffer was different, but we have found any results already,
      -- then the results for this buffer are split up and the list is not sorted.
      if i > 1 and entry.bufnr ~= list[i - 1].bufnr and closest_idx then
        qf_is_sorted = false
      end

      if qf_is_sorted then
        local closest = sorted_closest_idx and list[sorted_closest_idx]
        if
          prev_lnum
          and prev_col
          and (entry.lnum < prev_lnum or (entry.lnum == prev_lnum and entry.col <= prev_col))
        then
          qf_is_sorted = false
        elseif not closest or lnum > entry.lnum or (lnum == entry.lnum and col >= entry.col) then
          sorted_closest_idx = i
        end
        prev_lnum = entry.lnum
        prev_col = entry.col
      end

      local closest = closest_idx and list[closest_idx]
      if
        not closest
        -- take the one closest by number of lines
        or math.abs(entry.lnum - lnum) < math.abs(closest.lnum - lnum)
        -- they're the same number of lines apart but not the same line,
        -- take the one that comes before the cursor
        or (entry.lnum < lnum and lnum - entry.lnum < lnum - closest.lnum)
      then
        closest_idx = i
      elseif entry.lnum == closest.lnum then
        -- same line as cursor
        if entry.lnum == lnum then
          local closest_before = closest.col <= col
          local cur_before = entry.col <= col
          if
            -- take the closest col without going past the cursor
            (cur_before and not closest_before)
            or ( -- If they are both before/after the cursor
              cur_before == closest_before
              -- tiebreak with the closest col
              and math.abs(entry.col - col) < math.abs(closest.col - col)
            )
          then
            closest_idx = i
          end
        elseif
          -- if they're in a line before the cursor, take the largest col
          (entry.lnum < lnum and entry.col > closest.col)
          -- if they're in a line after the cursor, take the smallest col
          or (entry.lnum > lnum and entry.col < closest.col)
        then
          closest_idx = i
        end
      end
    end
  end

  if qf_is_sorted then
    return sorted_closest_idx
  else
    return closest_idx
  end
end

local timers = {}
---@param winid integer
---@param pos integer
M.set_pos = function(winid, pos)
  local timer = timers[winid]
  if timer then
    timer:close()
  end
  timer = assert(vim.uv.new_timer())
  timers[winid] = timer
  timer:start(10, 0, function()
    timer:close()
    timers[winid] = nil
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(winid) then
        pcall(vim.api.nvim_win_set_cursor, winid, { pos, 0 })
      end
    end)
  end)
end

return M
