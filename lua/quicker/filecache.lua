---Provides a fast way to access lines from quickfix items
---@class quicker.FileCache
---@field private count_per_buf table<number, number>
---@field private max_line_per_buf table<number, number>
---@field private cache table<number, string[]>
local FileCache = {}

---@param items QuickFixItem[]
---@return quicker.FileCache
function FileCache.new(items)
  local obj = {
    count_per_buf = {},
    max_line_per_buf = {},
    cache = {},
  }

  for _, item in ipairs(items) do
    if item.bufnr ~= 0 and item.lnum ~= 0 then
      if not obj.count_per_buf[item.bufnr] then
        obj.count_per_buf[item.bufnr] = 0
        obj.max_line_per_buf[item.bufnr] = 1
      end
      obj.count_per_buf[item.bufnr] = obj.count_per_buf[item.bufnr] + 1
      if item.lnum > obj.max_line_per_buf[item.bufnr] then
        obj.max_line_per_buf[item.bufnr] = item.lnum
      end
    end
  end

  setmetatable(obj, { __index = FileCache })
  return obj
end

---@param bufnr integer
---@param lnum integer
---@return string|nil
function FileCache:get_line(bufnr, lnum)
  if bufnr == 0 or lnum == 0 then
    return nil
  end
  if vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  end

  if not self.cache[bufnr] then
    -- Reading files with readfile() is much faster than loading the buffer
    local max_line = self.max_line_per_buf[bufnr] or error("FileCache: unknown bufnr " .. bufnr)
    local lines = vim.fn.readfile(vim.api.nvim_buf_get_name(bufnr), "", max_line)
    self.cache[bufnr] = lines
  end

  local line = self.cache[bufnr][lnum]

  self.count_per_buf[bufnr] = self.count_per_buf[bufnr] - 1
  if self.count_per_buf[bufnr] == 0 then
    -- If we have retrieved all needed lines from this buffer, free the cache
    self.cache[bufnr] = nil
  elseif self.count_per_buf[bufnr] < 0 then
    error("FileCache: more quickfix items for bufnr than expected " .. bufnr)
  end

  return line
end

return FileCache
