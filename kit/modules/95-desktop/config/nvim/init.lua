-- Neovim config from work-kit 95-desktop (marker: work-kit). LazyVim-style keys, offline.
-- Plugins: only mini.nvim, shipped in ~/.local/share/nvim/site/pack/work-kit/start/mini.nvim.
-- Works without network. Needs network (not shipped): language servers, extra treesitter
-- parsers (Neovim 0.12 bundles c, lua, markdown, query, vim, vimdoc), the full LazyVim distro.
-- Full LazyVim when network is allowed: move this folder away, then
--   git clone https://github.com/LazyVim/starter ~/.config/nvim

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local o = vim.opt
o.number = true
o.relativenumber = false
o.mouse = "a"
o.clipboard = "unnamedplus"
o.ignorecase = true
o.smartcase = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false
o.signcolumn = "yes"
o.termguicolors = true
o.undofile = true
o.splitright = true
o.splitbelow = true
o.scrolloff = 4
o.cursorline = true
o.laststatus = 3
o.updatetime = 200
o.timeoutlen = 300
o.confirm = true

local ok = pcall(require, "mini.basics")
if not ok then
  vim.notify("mini.nvim missing: run 95-desktop/install.sh again", vim.log.levels.WARN)
  return
end

-- Colours from `kit-desk theme` (lua/work-kit/palette.lua), else a built-in scheme
local has_palette, palette = pcall(require, "work-kit.palette")
if has_palette then
  vim.o.background = palette.mode == "light" and "light" or "dark"
  local colors = {}
  for k, v in pairs(palette) do
    if k:match("^base0") then colors[k] = v end
  end
  require("mini.base16").setup({ palette = colors, use_cterm = true })
  vim.g.colors_name = "work-kit-" .. palette.name
else
  vim.cmd.colorscheme("habamax")
end

require("mini.basics").setup({ options = { extra_ui = true }, mappings = { windows = true } })
require("mini.icons").setup()
require("mini.statusline").setup()
require("mini.tabline").setup()
require("mini.pairs").setup()
require("mini.surround").setup()
require("mini.ai").setup()
require("mini.diff").setup()
require("mini.git").setup()
require("mini.files").setup()
require("mini.pick").setup()
require("mini.extra").setup()
require("mini.notify").setup()
require("mini.cursorword").setup()
require("mini.indentscope").setup({ draw = { animation = require("mini.indentscope").gen_animation.none() } })
require("mini.completion").setup()
require("mini.starter").setup()

local clue = require("mini.clue")
clue.setup({
  triggers = {
    { mode = "n", keys = "<Leader>" }, { mode = "x", keys = "<Leader>" },
    { mode = "n", keys = "g" }, { mode = "n", keys = "]" }, { mode = "n", keys = "[" },
    { mode = "n", keys = "<C-w>" }, { mode = "n", keys = "z" }, { mode = "n", keys = "'" },
  },
  clues = {
    clue.gen_clues.builtin_completion(), clue.gen_clues.g(), clue.gen_clues.marks(),
    clue.gen_clues.registers(), clue.gen_clues.windows(), clue.gen_clues.z(),
    { mode = "n", keys = "<Leader>f", desc = "+find" }, { mode = "n", keys = "<Leader>g", desc = "+git" },
    { mode = "n", keys = "<Leader>b", desc = "+buffer" }, { mode = "n", keys = "<Leader>c", desc = "+code" },
  },
})

-- LazyVim-like keys
local map = function(lhs, rhs, desc, mode) vim.keymap.set(mode or "n", lhs, rhs, { desc = desc }) end
local pick = require("mini.pick").builtin
local extra = require("mini.extra").pickers
map("<Leader><Space>", pick.files, "Find files")
map("<Leader>ff", pick.files, "Find files")
map("<Leader>fr", extra.oldfiles, "Recent files")
map("<Leader>fb", pick.buffers, "Buffers")
map("<Leader>,", pick.buffers, "Buffers")
map("<Leader>/", pick.grep_live, "Grep (uses rg when installed)")
map("<Leader>sg", pick.grep_live, "Grep")
map("<Leader>sh", pick.help, "Help")
map("<Leader>fk", extra.keymaps, "Keymaps")
map("<Leader>e", function() require("mini.files").open(vim.api.nvim_buf_get_name(0)) end, "File explorer")
map("<Leader>E", function() require("mini.files").open() end, "File explorer (cwd)")
map("<Leader>gg", function()
  if vim.fn.executable("lazygit") == 1 then
    vim.cmd("tab terminal lazygit")
    vim.cmd("startinsert")
  else
    vim.notify("lazygit not installed", vim.log.levels.WARN)
  end
end, "Lazygit")
map("<Leader>gd", function() require("mini.diff").toggle_overlay(0) end, "Diff overlay")
map("<Leader>bd", function() require("mini.bufremove").delete() end, "Delete buffer")
map("<S-h>", "<Cmd>bprevious<CR>", "Previous buffer")
map("<S-l>", "<Cmd>bnext<CR>", "Next buffer")
map("<Leader>qq", "<Cmd>qa<CR>", "Quit all")
map("<Leader>cd", vim.diagnostic.open_float, "Line diagnostics")
map("<Leader>cf", function() vim.lsp.buf.format() end, "Format (needs an LSP)")
map("<Esc>", "<Cmd>nohlsearch<CR><Esc>", "Clear search")
map("<C-s>", "<Cmd>write<CR><Esc>", "Save", { "n", "i", "x" })
require("mini.bufremove").setup()
