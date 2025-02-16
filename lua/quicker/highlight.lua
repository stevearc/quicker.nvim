local M = {}

---@class quicker.TSHighlight
---@field [1] integer start_col
---@field [2] integer end_col
---@field [3] string highlight group

local _cached_queries = {}
---@param lang string
---@return vim.treesitter.Query?
local function get_highlight_query(lang)
  local query = _cached_queries[lang]
  if query == nil then
    query = vim.treesitter.query.get(lang, "highlights") or false
    _cached_queries[lang] = query
  end
  if query then
    return query
  end
end

---@class quicker.LSPHighlight
---@field [1] integer start_col
---@field [2] integer end_col
---@field [3] string highlight group
---@field [4] integer priority modifier

-- We're accessing private APIs here. This could break in the future.
local STHighlighter = vim.lsp.semantic_tokens.__STHighlighter

--- Copied from Neovim semantic_tokens.lua
--- Do a binary search of the tokens in the half-open range [lo, hi).
---
--- Return the index i in range such that tokens[j].line < line for all j < i, and
--- tokens[j].line >= line for all j >= i, or return hi if no such index is found.
---
---@private
local function lower_bound(tokens, line, lo, hi)
  while lo < hi do
    local mid = bit.rshift(lo + hi, 1) -- Equivalent to floor((lo + hi) / 2).
    if tokens[mid].line < line then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

---@param bufnr integer
---@param lnum integer
---@return quicker.LSPHighlight[]
function M.buf_get_lsp_highlights(bufnr, lnum)
  local highlighter = STHighlighter.active[bufnr]
  if not highlighter then
    return {}
  end
  local ft = vim.bo[bufnr].filetype

  local lsp_highlights = {}
  for _, client in pairs(highlighter.client_state) do
    local highlights = client.current_result.highlights
    if highlights then
      local idx = lower_bound(highlights, lnum - 1, 1, #highlights + 1)
      for i = idx, #highlights do
        local token = highlights[i]

        if token.line >= lnum then
          break
        end

        table.insert(
          lsp_highlights,
          { token.start_col, token.end_col, string.format("@lsp.type.%s.%s", token.type, ft), 0 }
        )
        for modifier, _ in pairs(token.modifiers) do
          table.insert(
            lsp_highlights,
            { token.start_col, token.end_col, string.format("@lsp.mod.%s.%s", modifier, ft), 1 }
          )
          table.insert(lsp_highlights, {
            token.start_col,
            token.end_col,
            string.format("@lsp.typemod.%s.%s.%s", token.type, modifier, ft),
            2,
          })
        end
      end
    end
  end

  return lsp_highlights
end

function M.set_highlight_groups()
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "QuickFixHeaderHard" })) then
    vim.api.nvim_set_hl(0, "QuickFixHeaderHard", { link = "Delimiter", default = true })
  end
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "QuickFixHeaderSoft" })) then
    vim.api.nvim_set_hl(0, "QuickFixHeaderSoft", { link = "Comment", default = true })
  end
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "QuickFixFilename" })) then
    vim.api.nvim_set_hl(0, "QuickFixFilename", { link = "Directory", default = true })
  end
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "QuickFixFilenameInvalid" })) then
    vim.api.nvim_set_hl(0, "QuickFixFilenameInvalid", { link = "Comment", default = true })
  end
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "QuickFixLineNr" })) then
    vim.api.nvim_set_hl(0, "QuickFixLineNr", { link = "LineNr", default = true })
  end
end

return M
