return {
    --[[
    A blazing fast and easy to configure Neovim statusline written in Lua.

    --]]
    "nvim-lualine/lualine.nvim",
    dependencies = {
        'nvim-tree/nvim-web-devicons',
    },
    config = function()
        require('lualine').setup({
            options = {
                theme = "powerline_dark",
            },
            extensions = {
                "lazy",
                "mason",
                "neo-tree",
                --"toggleterm",
            },
        })
    end
}
