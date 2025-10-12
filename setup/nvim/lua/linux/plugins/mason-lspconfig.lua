return {
    --[[
    Portable package manager for Neovim that runs everywhere Neovim runs.
    Easily install and manage LSP servers, DAP servers, linters, and formatters.

    The following plugins are recommended:

      LSP: lspconfig & mason-lspconfig.nvim
      DAP: nvim-dap & nvim-dap-ui
      Linters: null-ls.nvim or nvim-lint
      Formatters: null-ls.nvim or formatter.nvim
    --]]
    "mason-org/mason-lspconfig.nvim",
    opts = {},
    dependencies = {
        {
            "mason-org/mason.nvim",
            opts = {},
        },
        "neovim/nvim-lspconfig",
    },
    config = function()
        -- common LSP servers
        -- XXX: remember to revise nvim-cmp for auto-completion
        custom_lsp_lang = {
            -- [[ LSP ]]
            "autotools_ls",
            "cmake",
            -- [ bash language ]
            -- extra - lint: shellcheck, format: shfmt
            "bashls",
            -- [ C & C++ language ]
            "clangd",
            -- [ docker language ]
            "dockerls",
            "docker_compose_language_service",
            -- [ golang language ]
            -- extra - lint: golangci-lint, format: goimports
            "gopls",
            -- [ lua language ]
            "lua_ls",
            -- [ json language ]
            "jsonls",
            -- [ markdown language ]
            "marksman",
            -- [ python language ]
            -- extra - lint: ruff , format:
            "pyright",
            -- [TOML language]
            "taplo",
            -- [ YAML language]
            "yamlls",
        }

        require("mason-lspconfig").setup {
            ensure_installed = custom_lsp_lang,
            -- avoid duplicate lsp client. the neovim/nvim-lspconfig will auto start lsp client
            automatic_enable = false,
        }
    end
}
