return {
    --[[
    telescope.nvim is a highly extendable fuzzy finder over lists
    --]]
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
        'nvim-lua/plenary.nvim',
        "BurntSushi/ripgrep"
    },
    config = function()
        local builtin = require('telescope.builtin')

        -- file pickers
        vim.keymap.set('n', '<leader>ff', builtin.find_files,
            { desc = "Lists files in your current working directory", })
        vim.keymap.set('n', '<leader>fg', builtin.live_grep,
            { desc = "Search for a string in your current working directory and get results live as you type" })

        -- vim pickers
        --- commands
        vim.keymap.set('n', '<leader>vmd', builtin.commands,
            { desc = "Lists available plugin/user commands and runs them on <cr>" })
        vim.keymap.set('n', '<leader>vch', builtin.command_history,
            { desc = "Lists commands that were executed recently, and reruns them on <cr>" })

        -- lsp pickers
        vim.keymap.set('n', '<leader>li', builtin.lsp_implementations,
            {
                desc =
                "Goto the implementation of the word under the cursor if there's only one, otherwise show all options in Telescope"
            })
        vim.keymap.set('n', '<leader>ld', builtin.diagnostics,
            {
                desc =
                "Lists Diagnostics for all open buffers or a specific buffer. Use option bufnr=0 for current buffer."
            })
    end
}
