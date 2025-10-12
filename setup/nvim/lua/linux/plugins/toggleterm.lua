return {
    enabled = true,
    'akinsho/toggleterm.nvim',
    version = "*",
    opts = { --[[ things you want to change go here]] },
    config = function()
        require("toggleterm").setup({
            direction = 'float',
            open_mapping = [[<c-\>]],
        })

        -- goal: from teminal mode back to normal mode
        vim.keymap.set("t", "<C-a><esc>", [[<C-\><C-n>]], { silent = true })

        -- 當不只用 float 時, 這些快捷鍵可以讓你在 terminal 模式下切換視窗
        -- vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], {})
        -- vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], {})
        -- vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], {})
        -- vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], {})
        -- vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], {})
    end
}
