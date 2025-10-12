-- [ CONFIGS ]
local opt = vim.opt
-- General
opt.encoding = "utf-8"
opt.syntax = "on"
opt.filetype = "on"
opt.inccommand = "nosplit"                           -- Show live substitutions in the command line
opt.laststatus = 3                                   -- statusline mode
opt.splitbelow = true                                -- force all horizontal splits to go below current window
opt.splitright = true                                -- force all vertical splits to go to the right of current window
-- Appear
opt.number = true                                    -- Show line numbers
opt.relativenumber = true                            -- Show relative line numbers
opt.signcolumn = "yes"                               -- show sign column
opt.cursorline = true                                -- Highlight the current line
opt.cursorlineopt = "number"                         -- Highlight the number instead of current line
opt.termguicolors = true                             -- Enable true colors
opt.showmode = false                                 -- Disappear mode e.g. "-- INSERT --" on left corner
opt.signcolumn = "yes"                               -- Show the sign column
-- Enable auto completion menu after pressing TAB.
opt.wildmenu = true                                  -- completion for command-line mode
opt.wildmode = "list:longest"
opt.completeopt = { "menuone", "popup", "noinsert" } -- Options for completion menu
-- Make search case insensitive
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
-- Real programmers don't use TABs but spaces
opt.expandtab = true -- Use spaces instead of tabs
opt.tabstop = 4      -- Number of spaces for a tab
opt.softtabstop = 4
opt.shiftwidth = 4   -- Number of spaces to use for each step of (auto)indent.
opt.shiftround = true


-- [ VARIABLES ]
-- global variables
vim.g.mapleader = " " -- leader key
