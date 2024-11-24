local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- [ modules ]
require("lazy").setup({
    spec = {
        { import = "colorschemes" },
        { import = "plugins" },
    },
})

-- [ settings ]
require("options.nvim")


--[[
  After installed nvim configuration, do these

  [ install extra binary ]
  1. install lsp via mason
  :MasonInstall
  or run this command and use manage UI to install/uninstall
  :Mason

  2. install treesitter
  :TSUpdate or :TSInstall

  3. install extra binary "ripgrep" for telescope

  [ revise plugin setting ]
  1. mason.lau
  to add/remove built-in lsp if you need

  2. nvim-cmp.lua
  revise auto completion for your language server(lsp) if you need

  TODO:
  1. integrate lint with mason
  2. formatters install via mason or manully from mason UI
  3. (?)use other git plugin instead of net-git
--]]
