return {
    'akinsho/bufferline.nvim',
    version = "*",
    dependencies = {
        'nvim-tree/nvim-web-devicons',
    },
    config = function()
        vim.opt.termguicolors = true
        require("bufferline").setup {
            options = {
                mode = "tabs", -- set to "tabs" to only show tabpages instead
                diagnostics = "nvim_lsp",
            }
        }
    end
}
