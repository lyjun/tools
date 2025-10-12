return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        -- optional, but recommended
        "nvim-tree/nvim-web-devicons",
    },
    -- neo-tree will lazily load itself
    lazy = false,
    config = function()
        vim.keymap.set("n", "<leader>e", "<Cmd>Neotree<CR>")

        require("neo-tree").setup({
            window = {
                mappings = {
                    ["X"] = "expand_all_subnodes",
                    ["x"] = "close_all_subnodes",
                    ["z"] = ""
                }
            },
            filesystem = {
                window = {
                    mappings = {
                        -- use 'A' instead of 'H' and clean 'H'
                        ["A"] = "toggle_hidden",
                        ["H"] = "",
                    },
                },
            },
        })
    end,
}
