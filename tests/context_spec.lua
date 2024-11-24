local quicker = require("quicker")
local test_util = require("tests.test_util")

describe("context", function()
  after_each(function()
    test_util.reset_editor()
  end)

  it("expand results", function()
    local first = test_util.make_tmp_file("expand_1.txt", 10)
    local second = test_util.make_tmp_file("expand_2.txt", 10)
    local first_buf = vim.fn.bufadd(first)
    local second_buf = vim.fn.bufadd(second)
    vim.fn.setqflist({
      {
        bufnr = first_buf,
        text = "line 2",
        lnum = 2,
        valid = 1,
      },
      {
        bufnr = first_buf,
        text = "line 8",
        lnum = 8,
        valid = 1,
      },
      {
        bufnr = second_buf,
        text = "line 4",
        lnum = 4,
        valid = 1,
      },
    })
    vim.cmd.copen()
    test_util.assert_snapshot(0, "expand_1")

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    quicker.expand()
    test_util.assert_snapshot(0, "expand_2")
    -- Cursor stays on the same item
    assert.equals(12, vim.api.nvim_win_get_cursor(0)[1])
    vim.api.nvim_win_set_cursor(0, { 14, 0 })

    -- Expanding again will produce the same result
    quicker.expand()
    test_util.assert_snapshot(0, "expand_2")
    assert.equals(14, vim.api.nvim_win_get_cursor(0)[1])

    -- Expanding again will produce the same result
    quicker.expand({ add_to_existing = true })
    test_util.assert_snapshot(0, "expand_3")

    -- Collapsing will return to the original state
    quicker.collapse()
    test_util.assert_snapshot(0, "expand_1")
    assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("expand loclist results", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("expand_loclist.txt", 10))
    vim.fn.setloclist(0, {
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        valid = 1,
      },
    })
    vim.cmd.lopen()
    quicker.expand()
    test_util.assert_snapshot(0, "expand_loclist")
  end)

  it("expand when items missing bufnr", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("expand_missing.txt", 10))
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        valid = 1,
      },
      {
        text = "Valid line with no bufnr",
        lnum = 4,
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "Invalid line with a bufnr",
        lnum = 5,
        valid = 0,
      },
      {
        text = "Invalid line with no bufnr",
        lnum = 6,
        valid = 0,
      },
    })
    vim.cmd.copen()
    quicker.expand()
    -- The last three lines should be stripped after expansion
    test_util.assert_snapshot(0, "expand_missing")
  end)

  it("expand removes duplicate line entries", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("expand_dupe.txt", 10))
    vim.fn.setqflist({
      {
        bufnr = bufnr,
        text = "line 2",
        lnum = 2,
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "line 3",
        lnum = 3,
        valid = 1,
      },
      {
        bufnr = bufnr,
        text = "line 3",
        lnum = 3,
        valid = 1,
      },
    })
    vim.cmd.copen()
    test_util.assert_snapshot(0, "expand_dupe_1")

    quicker.expand()
    test_util.assert_snapshot(0, "expand_dupe_2")
  end)
end)
