return {
    'MeanderingProgrammer/render-markdown.nvim',
    -- if you use the mini.nvim suite
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' },

    -- if you use standalone mini plugins
    -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' },

    -- if you prefer nvim-web-devicons
    dependencies = {
        'nvim-treesitter/nvim-treesitter',
        'nvim-tree/nvim-web-devicons',
    },
    ---@module 'render-markdown'
    ---@type render.md.UserConfig
    opts = {},
    ft = {
        "markdown",
        -- umcomment if codecompanion is installed
        "codecompanion"
    },
}
