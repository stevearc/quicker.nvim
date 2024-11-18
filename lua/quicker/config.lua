local default_config = {
  -- Local options to set for quickfix
  opts = {
    buflisted = false,
    number = false,
    relativenumber = false,
    signcolumn = "auto",
    winfixheight = true,
    wrap = false,
  },
  -- Set to false to disable the default options in `opts`
  use_default_opts = true,
  -- Keymaps to set for the quickfix buffer
  keys = {
    -- { ">", "<cmd>lua require('quicker').expand()<CR>", desc = "Expand quickfix content" },
  },
  -- Callback function to run any custom logic or keymaps for the quickfix buffer
  on_qf = function(bufnr) end,
  edit = {
    -- Enable editing the quickfix like a normal buffer
    enabled = true,
    -- Set to true to write buffers after applying edits.
    -- Set to "unmodified" to only write unmodified buffers.
    autosave = "unmodified",
  },
  -- Keep the cursor to the right of the filename and lnum columns
  constrain_cursor = true,
  highlight = {
    -- Use treesitter highlighting
    treesitter = true,
    -- Use LSP semantic token highlighting
    lsp = true,
    -- Load the referenced buffers to apply more accurate highlights (may be slow)
    load_buffers = true,
  },
  follow = {
    -- When quickfix window is open, scroll to closest item to the cursor
    enabled = false,
  },
  -- Map of quickfix item type to icon
  type_icons = {
    E = "󰅚 ",
    W = "󰀪 ",
    I = " ",
    N = " ",
    H = " ",
  },
  -- Border characters
  borders = {
    vert = "┃",
    -- Strong headers separate results from different files
    strong_header = "━",
    strong_cross = "╋",
    strong_end = "┫",
    -- Soft headers separate results within the same file
    soft_header = "╌",
    soft_cross = "╂",
    soft_end = "┨",
  },
  -- How to trim the leading whitespace from results. Can be 'all', 'common', or false
  trim_leading_whitespace = "common",
  -- Maximum width of the filename column
  max_filename_width = function()
    return math.floor(math.min(95, vim.o.columns / 2))
  end,
  -- How far the header should extend to the right
  header_length = function(type, start_col)
    return vim.o.columns - start_col
  end,
}

---@alias quicker.TrimEnum "all"|"common"|false

---@class quicker.Config
---@field on_qf fun(bufnr: number)
---@field opts table<string, any>
---@field keys quicker.Keymap[]
---@field use_default_opts boolean
---@field constrain_cursor boolean
---@field highlight quicker.HighlightConfig
---@field follow quicker.FollowConfig
---@field edit quicker.EditConfig
---@field type_icons table<string, string>
---@field borders quicker.Borders
---@field trim_leading_whitespace quicker.TrimEnum
---@field max_filename_width fun(): integer
---@field header_length fun(type: "hard"|"soft", start_col: integer): integer
local M = {}

---@class (exact) quicker.SetupOptions
---@field on_qf? fun(bufnr: number) Callback function to run any custom logic or keymaps for the quickfix buffer
---@field opts? table<string, any> Local options to set for quickfix
---@field keys? quicker.Keymap[] Keymaps to set for the quickfix buffer
---@field use_default_opts? boolean Set to false to disable the default options in `opts`
---@field constrain_cursor? boolean Keep the cursor to the right of the filename and lnum columns
---@field highlight? quicker.SetupHighlightConfig Configure syntax highlighting
---@field follow? quicker.SetupFollowConfig Configure cursor following
---@field edit? quicker.SetupEditConfig
---@field type_icons? table<string, string> Map of quickfix item type to icon
---@field borders? quicker.SetupBorders Characters used for drawing the borders
---@field trim_leading_whitespace? quicker.TrimEnum How to trim the leading whitespace from results
---@field max_filename_width? fun(): integer Maximum width of the filename column
---@field header_length? fun(type: "hard"|"soft", start_col: integer): integer How far the header should extend to the right

local has_setup = false
---@param opts? quicker.SetupOptions
M.setup = function(opts)
  opts = opts or {}
  local new_conf = vim.tbl_deep_extend("keep", opts, default_config)

  for k, v in pairs(new_conf) do
    M[k] = v
  end

  -- Shim for when this was only a boolean. 'true' meant 'common'
  if M.trim_leading_whitespace == true then
    M.trim_leading_whitespace = "common"
  end

  -- Remove the default opts values if use_default_opts is false
  if not new_conf.use_default_opts then
    M.opts = opts.opts or {}
  end
  has_setup = true
end

---@class (exact) quicker.Keymap
---@field [1] string Key sequence
---@field [2] any Command to run
---@field desc? string
---@field mode? string
---@field expr? boolean
---@field nowait? boolean
---@field remap? boolean
---@field replace_keycodes? boolean
---@field silent? boolean

---@class (exact) quicker.Borders
---@field vert string
---@field strong_header string
---@field strong_cross string
---@field strong_end string
---@field soft_header string
---@field soft_cross string
---@field soft_end string

---@class (exact) quicker.SetupBorders
---@field vert? string
---@field strong_header? string Strong headers separate results from different files
---@field strong_cross? string
---@field strong_end? string
---@field soft_header? string Soft headers separate results within the same file
---@field soft_cross? string
---@field soft_end? string

---@class (exact) quicker.HighlightConfig
---@field treesitter boolean
---@field lsp boolean
---@field load_buffers boolean

---@class (exact) quicker.SetupHighlightConfig
---@field treesitter? boolean Enable treesitter syntax highlighting
---@field lsp? boolean Use LSP semantic token highlighting
---@field load_buffers? boolean Load the referenced buffers to apply more accurate highlights (may be slow)

---@class (exact) quicker.FollowConfig
---@field enabled boolean

---@class (exact) quicker.SetupFollowConfig
---@field enabled? boolean

---@class (exact) quicker.EditConfig
---@field enabled boolean
---@field autosave boolean|"unmodified"

---@class (exact) quicker.SetupEditConfig
---@field enabled? boolean
---@field autosave? boolean|"unmodified"

return setmetatable(M, {
  -- If the user hasn't called setup() yet, make sure we correctly set up the config object so there
  -- aren't random crashes.
  __index = function(self, key)
    if not has_setup then
      M.setup()
    end
    return rawget(self, key)
  end,
})
