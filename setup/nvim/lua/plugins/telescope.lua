return {
    --[[
    don't forget to install "ripgrep"
    --]]
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
        'nvim-lua/plenary.nvim',
    },
    config = function()
        local builtin = require('telescope.builtin')

        -- file pickers
        vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
        vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})

        -- vim pickers
        vim.keymap.set('n', '<leader>vm', builtin.man_pages, {})
        vim.keymap.set('n', '<leader>vc', builtin.commands, {})
    end
}
