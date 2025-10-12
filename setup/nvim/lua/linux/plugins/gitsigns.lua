return {
    -- Deep buffer integration for Git
    "lewis6991/gitsigns.nvim",
    config = function()
        require('gitsigns').setup({
            on_attach = function(bufnr)
                local gitsigns = require('gitsigns')

                local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                end

                -- Actions
                map('n', '<leader>gp', gitsigns.preview_hunk, { desc = "Preview git hunk" })
                map('n', '<leader>gi', gitsigns.preview_hunk_inline, { desc = "Preview git hunk inline" })

                map('n', '<leader>gb', function() gitsigns.blame_line({ full = true }) end,
                    { desc = "Show full git blame info" })

                map('n', '<leader>gd', gitsigns.diffthis, { desc = "View git diff for current file" })
                map('n', '<leader>gD', function() gitsigns.diffthis('~') end,
                    { desc = "View git diff for current file against last commit" })
            end
        })
    end
}
