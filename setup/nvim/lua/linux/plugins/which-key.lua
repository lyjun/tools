return {
    --[[
    WhichKey helps you remember your Neovim keymaps, by showing available keybindings in a popup as you type.

    Limitation:
    1. It is not working with vs code
       floating windows, https://github.com/folke/which-key.nvim/discussions/592
    --]]
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
        -- your configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
    },
    keys = {
        {
            "<leader>?",
            function()
                require("which-key").show({ global = false })
            end,
            desc = "Buffer Local Keymaps (which-key)",
        },
    },
}
