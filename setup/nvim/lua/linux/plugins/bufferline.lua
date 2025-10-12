return {
    --[[
    tabline plugin. It add status, file type for each tab.
    --]]
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
                numbers = function(opts)
                    return string.format('%s', opts.lower(opts.id))
                end,
            },
        }
    end
}
