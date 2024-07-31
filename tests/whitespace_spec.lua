local quicker = require("quicker")
local test_util = require("tests.test_util")

describe("whitespace", function()
  before_each(function()
    require("quicker.config").trim_leading_whitespace = true
  end)
  after_each(function()
    test_util.reset_editor()
  end)

  it("removes leading whitespace from valid results", function()
    local bufnr = vim.fn.bufadd(test_util.make_tmp_file("whitespace.txt", {
      "    line 1",
      "  line 2",
      "    line 3",
      "",
      "      line 4",
    }))
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
    test_util.assert_snapshot(0, "trim_whitespace")
    quicker.expand()
    test_util.assert_snapshot(0, "trim_whitespace_expanded")
  end)
end)
