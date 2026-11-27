if vim.g.loaded_devin then
  return
end
vim.g.loaded_devin = true

local command = vim.api.nvim_create_user_command

command("Devin", function(cmd)
  require("devin").toggle(cmd.fargs)
end, { nargs = "*", desc = "Show or hide Devin (arguments go to devin when it starts)" })

command("DevinFocus", function(cmd)
  require("devin").focus(cmd.fargs)
end, { nargs = "*", desc = "Jump into Devin, or hide it from inside" })

command("DevinAdd", function(cmd)
  require("devin").add(cmd.args)
end, { nargs = "?", complete = "file", desc = "Mention a file in Devin's prompt (default: this buffer)" })

command("DevinSend", function(cmd)
  require("devin").send(cmd.line1, cmd.line2)
end, { range = true, desc = "Point Devin at the selected lines" })
