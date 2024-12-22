-- [ configs ]
-- set colorscheme
vim.cmd.colorscheme "github_dark_colorblind"

-- general
vim.o.encoding = "utf-8"
vim.o.number = true
vim.o.syntax = "on"
vim.o.filetype = "on"
-- appear
vim.opt.laststatus = 3 -- views can only be fully collapsed with the global statusline
-- Enable auto completion menu after pressing TAB.
vim.o.wildmenu = true
vim.o.wildmode = "list:longest"
-- Make search case insensitive
vim.o.hlsearch = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true
-- Real programmers don't use TABs but spaces
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4 -- Number of spaces to use for each step of (auto)indent.
vim.o.shiftround = true
vim.o.expandtab = true
