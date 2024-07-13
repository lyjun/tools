return {
    "nvim-lualine/lualine.nvim",
    config = function()
        require('lualine').setup({
            options = {
                theme = "powerline",
            },
            extensions = {
                "lazy",
                "neo-tree",
                "mason",
                "toggleterm" ,"trouble",
            },
        })
    end
}
