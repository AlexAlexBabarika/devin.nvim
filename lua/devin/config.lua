local M = {}

M.defaults = {
  cmd = { "devin" }, -- what every launch starts with, e.g. { "devin", "--permission-mode", "accept-edits" }
  env = {}, -- extra environment variables for Devin
  prompt = "❭", -- what Devin's input box starts with; text sent to a starting Devin waits until this shows
  focus_after_send = false, -- move into Devin's window after :DevinAdd and :DevinSend
  win = { -- with snacks.nvim any snacks.win option; without it only these two
    position = "right", -- or "left"
    width = 0.3, -- share of the editor's width, or a number of columns
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
