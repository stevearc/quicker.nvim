local config = require("quicker.config")
local quicker = require("quicker")
local test_util = require("tests.test_util")

---@param start_idx integer
---@param end_idx integer
---@param lines string[]
local function replace_text(start_idx, end_idx, lines)
  local buflines = vim.api.nvim_buf_get_lines(0, start_idx, end_idx, false)
  for i, line in ipairs(buflines) do
    local pieces = vim.split(line, config.borders.vert)
    pieces[3] = lines[i]
    pieces[4] = nil -- just in case there was a delimiter in the text
    buflines[i] = table.concat(pieces, config.borders.vert)
  end
  vim.api.nvim_buf_set_lines(0, start_idx, end_idx, false, buflines)
end

describe("editor", function()
  after_each(function()
    test_util.reset_editor()
  end)

  it("can edit one line in file", function()
    vim.cmd.edit({ args = { test_util.make_tmp_file("edit_1.txt", 10) } })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
      },
    })
    vim.cmd.copen()
    replace_text(0, -1, { "new text" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_1")
  end)

  it("can edit across multiple files", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("edit_multiple_1.txt", 10))
    vim.fn.bufload(bufnr)
    local buf2 = vim.fn.bufadd(test_util.make_tmp_file("edit_multiple_2.txt", 10))
    vim.fn.bufload(buf2)
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
      },
      {
        bufnr = bufnr,
        text = "line 9",
        lnum = 9,
      },
      {
        bufnr = buf2,
        text = "line 5",
        lnum = 5,
      },
    })
    vim.cmd.copen()
    quicker.expand()
    replace_text(1, 3, { "new text", "some text" })
    replace_text(7, 8, { "other text" })
    replace_text(12, 13, { "final text" })
    local last_line = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { last_line, 0 })
    vim.cmd.write()
    test_util.assert_snapshot(0, "edit_multiple_qf")
    test_util.assert_snapshot(bufnr, "edit_multiple_1")
    test_util.assert_snapshot(buf2, "edit_multiple_2")
    -- We should keep the cursor position
    assert.equals(last_line, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("can expand then edit expanded line", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("edit_expanded.txt", 10))
    vim.fn.bufload(bufnr)
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
      },
    })
    vim.cmd.copen()
    quicker.expand()
    replace_text(0, 3, { "first", "second", "third" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_expanded")
    test_util.assert_snapshot(0, "edit_expanded_qf")
  end)

  it("fails when source text is different", function()
    vim.cmd.edit({ args = { test_util.make_tmp_file("edit_fail.txt", 10) } })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "buzz buzz",
        lnum = 2,
      },
    })
    vim.cmd.copen()
    replace_text(0, -1, { "new text" })
    test_util.with(function()
      local notify = vim.notify
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function() end
      return function()
        vim.notify = notify
      end
    end, function()
      vim.cmd.write()
    end)
    test_util.assert_snapshot(bufnr, "edit_fail")
  end)

  it("can handle multiple qf items on same lnum", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("edit_dupe.txt", 10))
    vim.fn.bufload(bufnr)
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        col = 0,
      },
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        col = 3,
      },
    })
    vim.cmd.copen()
    replace_text(0, -1, { "first", "second" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_dupe")
    test_util.assert_snapshot(0, "edit_dupe_qf")

    -- If only one of them has a change, it should go through
    replace_text(0, -1, { "line 2", "second" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_dupe_2")
    test_util.assert_snapshot(0, "edit_dupe_qf_2")
  end)

  it("handles deleting lines (shrinks quickfix)", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("edit_delete.txt", 10))
    vim.fn.bufload(bufnr)
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
      },
      {
        bufnr = bufnr,
        text = "line 3",
        lnum = 3,
      },
      {
        bufnr = bufnr,
        text = "line 6",
        lnum = 6,
      },
    })
    vim.cmd.copen()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.api.nvim_buf_get_lines(0, 0, 1, false))
    vim.cmd.write()
    assert.are.same({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        col = 0,
        end_col = 0,
        vcol = 0,
        end_lnum = 0,
        module = "",
        nr = 0,
        pattern = "",
        type = "",
        valid = 1,
      },
    }, vim.fn.getqflist())
  end)

  it("handles loclist", function()
    vim.cmd.edit({ args = { test_util.make_tmp_file("edit_ll.txt", 10) } })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.fn.setloclist(0, {
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
      },
    })
    vim.cmd.lopen()
    replace_text(0, -1, { "new text" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_ll")
  end)

  it("handles text that contains the delimiter", function()
    vim.cmd.edit({ args = { test_util.make_tmp_file("edit_delim.txt", 10) } })
    local bufnr = vim.api.nvim_get_current_buf()
    local line = "line 2 " .. config.borders.vert .. " text"
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { line })
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = line,
        lnum = 2,
      },
    })
    vim.cmd.copen()
    replace_text(0, -1, { line .. " " .. config.borders.vert .. " more text" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_delim")
  end)

  it("can edit lines with trimmed whitespace", function()
    require("quicker.config").trim_leading_whitespace = true
    vim.cmd.edit({
      args = {
        test_util.make_tmp_file("edit_whitespace.txt", {
          "    line 1",
          "  line 2",
          "    line 3",
          "      line 4",
        }),
      },
    })
    local bufnr = vim.api.nvim_get_current_buf()
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "  line 2",
        lnum = 2,
      },
      {
        bufnr = bufnr,
        text = "    line 3",
        lnum = 3,
      },
    })
    vim.cmd.copen()
    replace_text(0, -1, { "foo", "bar" })
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_whitespace")
  end)
end)
