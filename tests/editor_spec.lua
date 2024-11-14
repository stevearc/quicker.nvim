local config = require("quicker.config")
local display = require("quicker.display")
local quicker = require("quicker")
local test_util = require("tests.test_util")

---@param lnum integer
---@param line string
local function replace_text(lnum, line)
  local prev_line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]
  local idx = prev_line:find(display.EM_QUAD, 1, true)
  vim.api.nvim_buf_set_text(0, lnum - 1, idx + display.EM_QUAD_LEN - 1, lnum - 1, -1, { line })
end

---@param lnum integer
local function del_line(lnum)
  vim.cmd.normal({ args = { string.format("%dggdd", lnum) }, bang = true })
end

local function wait_virt_text()
  vim.wait(10, function()
    return false
  end)
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
    wait_virt_text()
    replace_text(1, "new text")
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
    wait_virt_text()
    replace_text(2, "new text")
    replace_text(3, "some text")
    replace_text(7, "other text")
    replace_text(11, "final text")
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
    wait_virt_text()
    replace_text(1, "first")
    replace_text(2, "second")
    replace_text(3, "third")
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
    wait_virt_text()
    replace_text(1, "new text")
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
    test_util.assert_snapshot(0, "edit_fail_qf")
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
    wait_virt_text()
    replace_text(1, "first")
    replace_text(2, "second")
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_dupe")
    test_util.assert_snapshot(0, "edit_dupe_qf")

    -- If only one of them has a change, it should go through
    replace_text(1, "line 2")
    replace_text(2, "second")
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
    wait_virt_text()
    del_line(3)
    del_line(2)
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
    wait_virt_text()
    replace_text(1, "new text")
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
    wait_virt_text()
    replace_text(1, line .. " " .. config.borders.vert .. " more text")
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_delim")
  end)

  it("can edit lines with trimmed common whitespace", function()
    require("quicker.config").trim_leading_whitespace = "common"
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
    wait_virt_text()
    test_util.assert_snapshot(0, "edit_whitespace_qf")
    replace_text(1, "foo")
    replace_text(2, "bar")
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_whitespace")
  end)

  it("can edit lines with trimmed all whitespace", function()
    require("quicker.config").trim_leading_whitespace = "all"
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
    wait_virt_text()
    test_util.assert_snapshot(0, "edit_all_whitespace_qf")
    replace_text(1, "foo")
    replace_text(2, "bar")
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_all_whitespace")
  end)

  it("can edit lines with untrimmed whitespace", function()
    require("quicker.config").trim_leading_whitespace = false
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
    wait_virt_text()
    test_util.assert_snapshot(0, "edit_none_whitespace_qf")
    replace_text(1, "foo")
    replace_text(2, "bar")
    vim.cmd.write()
    test_util.assert_snapshot(bufnr, "edit_none_whitespace")
  end)
end)
