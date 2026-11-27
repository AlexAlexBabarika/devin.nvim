-- Drives the commands against a stand-in `devin`: a script that draws a prompt and echoes what it is sent.
-- Runs in a plain split, or in a snacks.nvim terminal when SNACKS is the path of a snacks.nvim checkout.
local source = debug.getinfo(1, "S").source:sub(2)
vim.opt.rtp:prepend(vim.fn.fnamemodify(source, ":p:h:h"))
if vim.env.SNACKS then
  vim.opt.rtp:prepend(vim.env.SNACKS)
  require("snacks").setup({})
end
vim.cmd.runtime("plugin/devin.lua")

local checks = 0
local function eq(actual, expected, what)
  checks = checks + 1
  if not vim.deep_equal(actual, expected) then
    error(("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local dir = vim.uv.fs_realpath(vim.fn.tempname():match("^(.*)/"))
local project = dir .. "/project"
vim.fn.mkdir(project .. "/sub", "p")
vim.fn.writefile({ "one", "two", "three" }, project .. "/notes.txt")
vim.fn.writefile({ "return 1" }, project .. "/sub/mod.lua")
vim.fn.writefile({ "elsewhere" }, dir .. "/outside.txt")
local fake = dir .. "/devin"
vim.fn.writefile({
  "#!/bin/sh",
  '[ "$1" = "--slow" ] && { echo "Trust this folder?"; sleep 0.6; }',
  [[printf '❭ devin %s\n' "$*"]],
  '[ "$1" = "--fail" ] && exit 3',
  "exec cat",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.cmd.cd(project)
vim.cmd.edit("notes.txt")
local editor = vim.api.nvim_get_current_win()

local notes = {}
vim.notify = function(msg)
  notes[#notes + 1] = msg
end

local devin = require("devin")
devin.setup({ cmd = { fake } })

local function buf()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buftype == "terminal"
  end, vim.api.nvim_list_bufs())[1]
end

local function win()
  return buf() and vim.fn.bufwinid(buf()) ~= -1 and vim.fn.bufwinid(buf()) or nil
end

local function screen()
  return buf() and table.concat(vim.api.nvim_buf_get_lines(buf(), 0, -1, false), "\n") or ""
end

local function wait(what, cond)
  checks = checks + 1
  if not vim.wait(3000, cond, 20) then
    error(("%s\nscreen:\n%s"):format(what, screen()), 2)
  end
end

-- Devin's window is narrow, so what the stand-in echoes wraps: line breaks are left out of the comparison
local function shows(text)
  return function()
    return screen():gsub("\n", ""):find((text:gsub("\n", "")), 1, true) ~= nil
  end
end

local function exit_devin(keys)
  vim.fn.chansend(vim.bo[buf()].channel, keys)
  wait("Devin's buffer goes away when it exits cleanly", function()
    return buf() == nil
  end)
end

-- show, hide, focus
vim.cmd("Devin")
wait("it starts", shows("❭ devin \n"))
local first = buf()
eq(vim.api.nvim_get_current_win(), win(), "starting moves into Devin")
eq(vim.api.nvim_win_get_position(win())[2] > 0, true, "it opens to the right")
eq(vim.api.nvim_win_get_width(win()), 24, "it takes 30% of the 80 columns")
vim.cmd("Devin")
eq(win(), nil, "toggling hides it")
eq(buf(), first, "hidden, it keeps running")
eq(vim.api.nvim_get_current_win(), editor, "hiding goes back to the editor")
vim.cmd("Devin")
eq({ buf(), vim.api.nvim_get_current_win() }, { first, win() }, "toggling again shows the same Devin")
vim.api.nvim_set_current_win(editor)
vim.cmd("DevinFocus")
eq(vim.api.nvim_get_current_win(), win(), "focus from the editor jumps into Devin")
vim.cmd("DevinFocus")
eq(win(), nil, "focus from inside hides it")

-- mentions and selections
vim.cmd("DevinAdd")
wait("the buffer is mentioned, as a bracketed paste", shows("^[[200~@notes.txt ^[[201~"))
eq(win() ~= nil, true, "sending shows a hidden Devin")
eq(vim.api.nvim_get_current_win(), editor, "sending leaves the cursor in the editor")
eq(vim.api.nvim_get_mode().mode, "n", "and in normal mode")
vim.cmd("2,3DevinSend")
wait("saved lines are referred to", shows("@notes.txt lines 2-3 ^[[201~"))
vim.cmd("DevinAdd sub")
wait("a directory ends in a slash", shows("@sub/ ^[[201~"))
vim.cmd("DevinAdd " .. dir .. "/outside.txt")
wait("a file outside Devin's directory keeps its full path", shows("@" .. dir .. "/outside.txt ^[[201~"))
vim.cmd.edit("sub/mod.lua")
vim.cmd("DevinSend")
wait("paths are relative to Devin's directory", shows("@sub/mod.lua line 1 ^[[201~"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "return 2" })
vim.bo.filetype = "lua" -- -u NONE leaves filetype detection off
vim.cmd("DevinSend")
wait("unsaved lines are pasted", shows("@sub/mod.lua line 1, not saved yet:\n```lua\nreturn 2\n```\n^[[201~"))
vim.cmd("enew!")
vim.cmd("DevinAdd")
eq(notes[#notes], "No file here to add", "a buffer without a file cannot be mentioned")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scratch" })
vim.cmd("DevinSend")
wait("lines of a buffer without a file are pasted", shows("^[[200~```\nscratch\n```\n^[[201~"))

-- arguments, exiting
vim.cmd("Devin --resume")
eq(notes[#notes], "Devin is already running, so --resume was ignored", "arguments cannot reach a running Devin")
eq({ buf(), vim.api.nvim_get_current_win() }, { first, win() }, "which is shown instead")
exit_devin("\n\4")
vim.cmd("Devin --resume")
wait("arguments reach a starting Devin", shows("❭ devin --resume\n"))
exit_devin("\4")
vim.cmd("Devin --fail")
wait("it fails", shows("❭ devin --fail"))
vim.wait(300)
eq(win() ~= nil, true, "a Devin that exits with an error stays up")
vim.cmd("Devin")
eq(buf(), nil, "toggling dismisses it")
vim.cmd("Devin")
wait("the next toggle starts a new one", shows("❭ devin \n"))
exit_devin("\4")

-- text sent to a Devin that is still starting
vim.api.nvim_set_current_win(editor)
vim.cmd.edit({ "notes.txt", bang = true })
devin.setup({ cmd = { fake, "--slow" } })
vim.cmd("DevinAdd")
vim.cmd("DevinSend")
wait("it starts", shows("Trust this folder?"))
vim.wait(300)
eq(screen():find("@", 1, true), nil, "nothing is pasted before the prompt is up")
wait(
  "then everything is, in order",
  shows("❭ devin --slow\n^[[200~@notes.txt ^[[201~^[[200~@notes.txt line 1 ^[[201~")
)
exit_devin("\n\4")

devin.setup({ cmd = { "no-such-devin" } })
vim.cmd("Devin")
eq(notes[#notes]:find("no-such-devin is not on PATH", 1, true), 1, "a missing executable is reported")
eq(buf(), nil, "and nothing opens")
vim.api.nvim_set_current_win(editor)
local reported = #notes
vim.cmd("DevinAdd")
eq({ #notes - reported, buf() }, { 1, nil }, "also when something is sent")

print(("devin: %d checks passed (%s)\n"):format(checks, vim.env.SNACKS and "snacks.nvim" or "plain split"))
