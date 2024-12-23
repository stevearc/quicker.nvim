require("plenary.async").tests.add_to_env()
local config = require("quicker.config")
local test_util = require("tests.test_util")

local sleep = require("plenary.async.util").sleep

a.describe("display", function()
  after_each(function()
    test_util.reset_editor()
  end)

  it("renders quickfix items", function()
    vim.fn.setqflist({
      {
        bufnr = vim.fn.bufadd("README.md"),
        text = "text",
        lnum = 5,
        valid = 1,
      },
      {
        filename = "README.md",
        text = "text",
        lnum = 10,
        col = 0,
        end_col = 4,
        nr = 3,
        type = "E",
        valid = 1,
      },
      {
        module = "mod",
        bufnr = vim.fn.bufadd("README.md"),
        text = "text",
        valid = 1,
      },
      {
        bufnr = vim.fn.bufadd("README.md"),
        text = "text",
        valid = 0,
      },
      {
        bufnr = vim.fn.bufadd("README.md"),
        lnum = 1,
        text = "",
        valid = 0,
      },
    })
    vim.cmd.copen()
    test_util.assert_snapshot(0, "display_1")
  end)

  a.it("truncates long filenames", function()
    config.max_filename_width = function()
      return 10
    end
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file(string.rep("f", 10) .. ".txt", 10))
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "text",
        lnum = 5,
        valid = 1,
      },
    })
    vim.cmd.copen()
    -- Wait for highlights to be applied
    sleep(50)
    test_util.assert_snapshot(0, "display_long_1")
  end)

  a.it("renders minimal line when no filenames in results", function()
    vim.fn.setqflist({
      {
        text = "text",
      },
    })
    vim.cmd.copen()
    -- Wait for highlights to be applied
    sleep(50)
    test_util.assert_snapshot(0, "display_minimal_1")
  end)

  a.it("sets signs for diagnostics", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("sign_test.txt", 10))
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "text",
        lnum = 1,
        type = "E",
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "text",
        lnum = 2,
        type = "W",
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "text",
        lnum = 3,
        type = "I",
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "text",
        lnum = 4,
        type = "H",
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "text",
        lnum = 5,
        type = "N",
        valid = 1,
      },
    })
    vim.cmd.copen()

    -- Wait for highlights to be applied
    sleep(50)
    local ns = vim.api.nvim_create_namespace("quicker_highlights")
    local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { type = "sign" })
    assert.equals(5, #marks)
    local expected = {
      { "DiagnosticSignError", config.type_icons.E },
      { "DiagnosticSignWarn", config.type_icons.W },
      { "DiagnosticSignInfo", config.type_icons.I },
      { "DiagnosticSignHint", config.type_icons.H },
      { "DiagnosticSignHint", config.type_icons.N },
    }
    for i, mark_data in ipairs(marks) do
      local extmark_id, row = mark_data[1], mark_data[2]
      local mark = vim.api.nvim_buf_get_extmark_by_id(0, ns, extmark_id, { details = true })
      local hl_group, icon = unpack(expected[i])
      assert.equals(i - 1, row)
      assert.equals(hl_group, mark[3].sign_hl_group)
      assert.equals(icon, mark[3].sign_text)
    end
  end)
end)
