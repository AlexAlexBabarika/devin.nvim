# devin.nvim

Neovim plugin (Lua, Neovim >= 0.11) that runs the Devin CLI in a side terminal and pastes file mentions and line
references into its prompt. No build step and no dependencies; the terminal is a snacks.nvim terminal when that is
installed, a plain split otherwise.

There is no editor protocol behind it: the Devin CLI only talks to editors over ACP (`devin acp`), which replaces its
terminal UI. Everything here goes through the terminal, so Devin cannot be asked about its state, and its edits are
reviewed in its own window rather than as Neovim diffs.

## Layout

- `lua/devin/terminal.lua` - the one Devin terminal: start, show, hide, and pasting once its prompt is up
- `lua/devin/init.lua` - public API: `toggle`, `focus`, `add` (file mention), `send` (line range)
- `lua/devin/config.lua` - options
- `plugin/devin.lua` - `:Devin`, `:DevinFocus`, `:DevinAdd`, `:DevinSend`

## Tests

Headless and offline, against a stand-in `devin` script, so no session is started; a failing check exits non-zero.
Run both terminals:

```sh
nvim --headless -u NONE -l tests/devin.lua
SNACKS=~/.local/share/nvim/lazy/snacks.nvim nvim --headless -u NONE -l tests/devin.lua
```

`nvim -l` keeps the screen at 80 columns whatever `columns` is set to, so Devin's window is 24 wide there.

What depends on the real CLI is checked by hand: text is pasted as a bracketed paste because a typed `@` opens
Devin's file picker, and pasting waits for a line starting with `❭` (the `prompt` option) because that is how its
input box is drawn.

## Style

2-space indent, 120 columns (stylua defaults of the user's Neovim config), double quotes.
