return {
    --[[
    This plugin adds image support to Neovim using Kitty's Graphics Protocol or ueberzugpp.
    It works great with Kitty and Tmux, and it handles all the rendering complexity for you.

    dependencies packages:
    1. kitty
    curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin

    2. imageMagick
    for ubuntu, execute "apt install imagemagick"
    --]]
    "3rd/image.nvim",
    enabled = false,
    build = false, -- so that it doesn't build the rock https://github.com/3rd/image.nvim/issues/91#issuecomment-2453430239
    opts = {}
}
