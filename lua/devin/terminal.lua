local config = require("devin.config")

local M = {}

local term -- the snacks.nvim terminal Devin runs in, or a Native standing in for one
local cwd -- directory the running Devin was started in
local ready = false -- Devin has drawn its input box
local pending = {} -- text to paste once it has

local function notify(msg, level)
  vim.notify(msg, level, { title = "devin" })
end

-- Stand-in for the snacks.nvim terminal when that is not installed: a plain split with the methods used below.
local Native = {}
Native.__index = Native

function Native.open(cmd, opts)
  local self = setmetatable({ buf = vim.api.nvim_create_buf(false, false), opts = opts.win }, Native)
  self:show()
  vim.api.nvim_buf_call(self.buf, function()
    vim.fn.jobstart(cmd, { term = true, cwd = opts.cwd, env = opts.env })
  end)
  vim.api.nvim_create_autocmd("BufEnter", { buffer = self.buf, command = "startinsert" })
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = self.buf,
    callback = function()
      if vim.v.event.status == 0 then -- an error stays up to be read
        vim.schedule(function()
          self:close()
        end)
      end
    end,
  })
  return self
end

function Native:win_valid()
  return self.win ~= nil and vim.api.nvim_win_is_valid(self.win)
end

function Native:show()
  local win = self.opts
  self.win = vim.api.nvim_open_win(self.buf, win.enter == true, {
    split = win.position == "left" and "left" or "right",
    win = -1, -- beside every other window, not just the current one
    width = math.floor(win.width < 1 and vim.o.columns * win.width or win.width),
  })
  vim.wo[self.win].number = false
  vim.wo[self.win].relativenumber = false
  vim.wo[self.win].signcolumn = "no"
  vim.wo[self.win].winfixwidth = true
end

function Native:hide()
  if self:win_valid() then
    pcall(vim.api.nvim_win_close, self.win, true) -- fails on the last window, which then stays
  end
end

function Native:close()
  self:hide()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    vim.api.nvim_buf_delete(self.buf, { force = true })
  end
  self.buf = nil
end

local function running()
  return term ~= nil
    and term.buf ~= nil
    and vim.api.nvim_buf_is_valid(term.buf)
    and vim.fn.jobwait({ vim.bo[term.buf].channel }, 0)[1] == -1
end

local function showing()
  return term ~= nil and term:win_valid()
end

local function show(focus)
  if not showing() then
    term.opts.enter = focus
    term:show()
  end
  if focus then
    vim.api.nvim_set_current_win(term.win)
    vim.cmd.startinsert()
  end
end

local function close()
  if term then
    term:close()
  end
  term = nil
end

-- As a bracketed paste: typed, an "@" would open Devin's file picker and a newline would submit the prompt.
local function deliver()
  for _, text in ipairs(pending) do
    vim.fn.chansend(vim.bo[term.buf].channel, "\27[200~" .. text .. "\27[201~")
  end
  pending = {}
end

-- Wait for Devin's input box before pasting: earlier text could land in its trust or login screen.
-- After 10 seconds without one it is pasted anyway, in case the box no longer starts with `prompt`.
local function deliver_when_ready(buf, tries)
  if not (running() and term.buf == buf) then
    return -- that Devin is gone; one started since waits for itself
  end
  local drawn = vim.iter(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):any(function(line)
    return vim.startswith(line, config.options.prompt)
  end)
  if not drawn and tries < 100 then
    return vim.defer_fn(function()
      deliver_when_ready(buf, tries + 1)
    end, 100)
  end
  ready = true
  deliver()
end

local function start(args, focus)
  close()
  ready, pending = false, {}
  local opts = config.options
  local cmd = vim.list_extend(vim.deepcopy(opts.cmd), args or {})
  if vim.fn.executable(cmd[1]) == 0 then
    return notify(cmd[1] .. " is not on PATH: install the Devin CLI, or point `cmd` at it", vim.log.levels.ERROR)
  end
  cwd = vim.fn.getcwd()
  local has_snacks, snacks = pcall(require, "snacks")
  term = (has_snacks and snacks.terminal or Native).open(cmd, {
    cwd = cwd,
    env = next(opts.env) and opts.env or nil,
    -- Esc belongs to Devin (Esc Esc interrupts it), so snacks.nvim's "Esc Esc leaves terminal mode" is off
    win = vim.tbl_deep_extend("force", { enter = focus, keys = { term_normal = false } }, opts.win),
  })
  -- Devin writes its edits to disk itself; pick them up when the cursor leaves it
  vim.api.nvim_create_autocmd("TermLeave", { buffer = term.buf, command = "checktime" })
  show(focus)
  deliver_when_ready(term.buf, 0)
end

--- The directory Devin runs in, or would if it were started now.
function M.cwd()
  return running() and cwd or vim.fn.getcwd()
end

--- Hide Devin when it is showing (`smart`: only when the cursor is in it), otherwise show it, starting it when it
--- is not running. `args` are extra arguments for a start.
function M.toggle(args, smart)
  local has_args = args ~= nil and args[1] ~= nil
  if showing() and not running() then
    close() -- it exited with an error, which stayed up to be read
  elseif showing() and not has_args and not (smart and vim.api.nvim_get_current_win() ~= term.win) then
    term:hide()
  elseif not running() then
    start(args, true)
  else
    if has_args then
      notify(("Devin is already running, so %s was ignored"):format(table.concat(args, " ")), vim.log.levels.WARN)
    end
    show(true)
  end
end

--- Paste `text` into Devin's prompt without submitting it, starting Devin when it is not running.
function M.send(text)
  if running() then
    show(config.options.focus_after_send)
  else
    start(nil, config.options.focus_after_send)
  end
  pending[#pending + 1] = text
  if ready then
    deliver()
  end
end

return M
