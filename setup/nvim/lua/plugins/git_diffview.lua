return {
    "sindrets/diffview.nvim",
    keys = {
        "<leader>gd",
        ":DiffviewOpen<CR>",
        desc = "Buffer Local Keymaps (which-key)",
    },

    config = function()
        require("diffview").setup()
        vim.keymap.set("n", "<leader>gd", ":DiffviewOpen<CR>",
            { silent = true, desc = "opens a new Diffview that compares against the current index" })
    end
}
