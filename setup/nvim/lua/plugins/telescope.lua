return {
    --[[
    telescope.nvim is a highly extendable fuzzy finder over lists
    --]]
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
        'nvim-lua/plenary.nvim',
    },
    config = function()
        local builtin = require('telescope.builtin')

        -- file pickers
        vim.keymap.set('n', '<leader>ff', builtin.find_files,
            { desc = "Lists files in your current working directory", })
        vim.keymap.set('n', '<leader>fg', builtin.live_grep,
            { desc = "Search for a string in your current working directory and get results live as you type" })

        -- vim pickers
        vim.keymap.set('n', '<leader>vc', builtin.commands,
            { desc = "Lists available plugin/user commands and runs them on <cr>" })
        vim.keymap.set('n', '<leader>vm', builtin.man_pages,
            { desc = "Lists manpage entries, opens them in a help window on <cr>" })
        vim.keymap.set('n', '<leader>vq', builtin.quickfix, { desc = "Lists items in the quickfix list" })

        -- lsp pickers
        vim.keymap.set('n', '<leader>lr', builtin.lsp_references,
            { desc = "Lists LSP references for word under the cursor" })
        vim.keymap.set('n', '<leader>ld', builtin.diagnostics,
            { desc = "Lists Diagnostics for all open buffers or a specific buffer" })

        -- git pickers
        vim.keymap.set('n', '<leader>gb', builtin.git_branches,
            { desc = "Lists all branches with log preview, checkout action <cr>..." })
    end
}
