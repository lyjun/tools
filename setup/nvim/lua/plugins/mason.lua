return {
    "williamboman/mason.nvim",
    dependencies = {
        {
            "williamboman/mason-lspconfig.nvim"
        }
    },
    config = function()
        require("mason").setup()
        require("mason-lspconfig").setup {
            ensure_installed = {
                -- [[ LSP ]]
                -- [ make ]
                "autotools_ls",
                -- [ bash ]
                "bashls",
                -- [ C & C++ ]
                -- "clangd",
                -- [ golang ]
                "gopls",
                -- [ lua ]
                "lua_ls",
                -- [ python ]
                "pylsp",
            },
        }
    end
}
