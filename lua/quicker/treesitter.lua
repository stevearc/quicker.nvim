---@alias quicker.LangRegions table<string, Range4[][]>

local M = {}

local cache = {} ---@type table<number, table<string,{parser: vim.treesitter.LanguageTree, highlighter:vim.treesitter.highlighter, enabled:boolean}>>
local ns = vim.api.nvim_create_namespace("quicker.treesitter")

local TSHighlighter = vim.treesitter.highlighter

local function wrap(name)
  return function(_, win, buf, ...)
    if not cache[buf] then
      return false
    end
    for _, hl in pairs(cache[buf] or {}) do
      if hl.enabled then
        TSHighlighter.active[buf] = hl.highlighter
        TSHighlighter[name](_, win, buf, ...)
      end
    end
    TSHighlighter.active[buf] = nil
  end
end

M.did_setup = false
function M.setup()
  if M.did_setup then
    return
  end
  M.did_setup = true

  vim.api.nvim_set_decoration_provider(ns, {
    on_win = wrap("_on_win"),
    on_line = wrap("_on_line"),
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("quicker.treesitter.hl", { clear = true }),
    callback = function(ev)
      cache[ev.buf] = nil
    end,
  })
end

---@param buf number
---@param regions quicker.LangRegions
function M.attach(buf, regions)
  M.setup()
  cache[buf] = cache[buf] or {}
  for lang in pairs(cache[buf]) do
    cache[buf][lang].enabled = regions[lang] ~= nil
  end

  for lang in pairs(regions) do
    M._attach_lang(buf, lang, regions[lang])
  end
end

---@param buf number
---@param lang? string
---@param regions quicker.LangRegions
function M._attach_lang(buf, lang, regions)
  lang = lang or "markdown"
  lang = lang == "markdown" and "markdown_inline" or lang

  cache[buf] = cache[buf] or {}

  if not cache[buf][lang] then
    local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
    if not ok then
      return
    end
    parser:set_included_regions(vim.deepcopy(regions))
    cache[buf][lang] = {
      parser = parser,
      highlighter = TSHighlighter.new(parser),
    }
  end
  cache[buf][lang].enabled = true
  local parser = cache[buf][lang].parser

  parser:set_included_regions(vim.deepcopy(regions))
  -- Run a full parse for all included regions. There are two reasons:
  -- 1. When we call `vim.treesitter.get_parser`, we have not set any
  --    injection ranges.
  -- 2. If this is not called, the highlighter will do incremental parsing,
  --    which means it only parses visible areas (the on_win and on_line callback),
  --    so if we modify the buffer, unvisited area's state get unsynced.
  pcall(parser.parse, parser, true)
end

return M
