return {
    "akinsho/toggleterm.nvim",
    config = function()
        require("toggleterm").setup()

        vim.keymap.set("n", "<C-\\>", ":ToggleTerm<CR>", { silent = true })
        vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], { silent = true })
    end
}
