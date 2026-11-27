local terminal = require("devin.terminal")

local M = {}

function M.setup(opts)
  require("devin.config").setup(opts)
end

--- Show or hide Devin, starting it when it is not running. `args` are extra `devin` arguments for a start,
--- e.g. { "--resume" }.
function M.toggle(args)
  terminal.toggle(args)
end

--- Jump into Devin, or hide it when the cursor is already there.
function M.focus(args)
  terminal.toggle(args, true)
end

-- "@path" as Devin's own file picker writes it: relative to Devin's directory, a directory ending in "/"
local function mention(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return "@" .. (vim.fs.relpath(terminal.cwd(), path) or path) .. (vim.fn.isdirectory(path) == 1 and "/" or "")
end

--- Mention a file or directory in Devin's prompt: `path`, else the node under the cursor in neo-tree, else the
--- current buffer's file.
function M.add(path)
  if not path or path == "" then
    if vim.bo.filetype == "neo-tree" then
      local state = require("neo-tree.sources.manager").get_state(vim.b.neo_tree_source)
      local node = state.tree and state.tree:get_node()
      path = node and node.path
    else
      path = vim.api.nvim_buf_get_name(0)
    end
  end
  if not path or not vim.uv.fs_stat(path) then
    return vim.notify("No file here to add", vim.log.levels.WARN, { title = "devin" })
  end
  terminal.send(mention(path) .. " ")
end

--- Point Devin at lines of the current buffer (default: the cursor line). Lines that are not on disk as shown,
--- because the buffer has unsaved changes or no file, are pasted instead.
function M.send(line1, line2)
  line1 = line1 or vim.fn.line(".")
  line2 = line2 or line1
  local path = vim.api.nvim_buf_get_name(0)
  local is_file = vim.bo.buftype == "" and path ~= ""
  local range = line1 == line2 and ("line " .. line1) or ("lines %d-%d"):format(line1, line2)
  if is_file and not vim.bo.modified and vim.uv.fs_stat(path) then
    return terminal.send(("%s %s "):format(mention(path), range))
  end
  local header = is_file and ("%s %s, not saved yet:\n"):format(mention(path), range) or ""
  local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  terminal.send(("%s```%s\n%s\n```\n"):format(header, vim.bo.filetype, table.concat(lines, "\n")))
end

return M
