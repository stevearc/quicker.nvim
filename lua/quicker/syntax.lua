local config = require("quicker.config")

local M = {}

function M.set_syntax()
  local v = config.borders.vert
  local cmd = string.format(
    [[
syn match QuickFixFilename /^[^%s]*/ nextgroup=qfSeparatorLeft
syn match qfSeparatorLeft /%s/ contained nextgroup=QuickFixLineNr
syn match QuickFixLineNr /[^%s]*/ contained nextgroup=qfSeparatorRight
syn match qfSeparatorRight '%s' contained

hi def link qfSeparatorLeft Delimiter
hi def link qfSeparatorRight Delimiter
]],
    v,
    v,
    v,
    v
  )
  vim.cmd(cmd)
end

return M
