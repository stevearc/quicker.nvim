local quicker = require("quicker")
local test_util = require("tests.test_util")

describe("opts", function()
  after_each(function()
    test_util.reset_editor()
  end)

  it("sets buffer opts", function()
    quicker.setup({
      opts = {
        buflisted = true,
        bufhidden = "wipe",
        cindent = true,
      },
    })
    vim.fn.setqflist({
      {
        bufnr = vim.fn.bufadd("README.md"),
        text = "text",
        lnum = 5,
        valid = 1,
      },
    })
    vim.cmd.copen()
    assert.truthy(vim.bo.buflisted)
    assert.equals("wipe", vim.bo.bufhidden)
    assert.truthy(vim.bo.cindent)
  end)

  it("sets window opts", function()
    quicker.setup({
      opts = {
        wrap = false,
        number = true,
        list = true,
      },
    })
    vim.fn.setqflist({
      {
        bufnr = vim.fn.bufadd("README.md"),
        text = "text",
        lnum = 5,
        valid = 1,
      },
    })
    vim.cmd.copen()
    assert.falsy(vim.wo.wrap)
    assert.truthy(vim.wo.number)
    assert.truthy(vim.wo.list)
  end)
end)
