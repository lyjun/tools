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
    "williamboman/mason.nvim",
    dependencies = {
        {
            "williamboman/mason-lspconfig.nvim"
        }
    },
    config = function()
        require("mason").setup()

        -- common LSP servers
        lspLangs = {
            -- [[ LSP ]]
            "autotools_ls",
            "cmake",
            -- [ bash language ]
            "bashls",
            -- [ C & C++ language ]
            "clangd",
            -- [ docker language ]
            "docker_compose_language_service",
            -- [ golang language ]
            "gopls",
            -- [ lua language ]
            "lua_ls",
            -- [ json language ]
            "jsonls",
            -- [ python language ]
            "pylsp",
            -- [ markdown language ]
            "marksman",
            -- [ toml language ]
            "harper_ls",
            -- [ YAML language]
            "yamlls",
        }

        osType = vim.loop.os_uname().sysname
        if (osType == "Darwin") then
            -- for macos
            --table.insert(lspLangs, "")
        elseif (osType == "Linux") then
            -- for linux
            -- table.insert(lspLangs, "")
        end

        require("mason-lspconfig").setup {
            ensure_installed = lspLangs,
        }
    end
}
