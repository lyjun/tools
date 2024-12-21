return {
    --[[
    A completion engine plugin for neovim written in Lua. Completion sources are installed from external repositories and "sourced".
    If you choose a snip, you also update "dependencies package", snippet config and sources.
    --]]
    "hrsh7th/nvim-cmp",
    dependencies = {
        'neovim/nvim-lspconfig',
        'hrsh7th/cmp-nvim-lsp',
        'hrsh7th/cmp-buffer',
        'hrsh7th/cmp-path',
        'hrsh7th/cmp-cmdline',
        -- XXX: Set your snip package
        --[[
        -- For ultisnips users
        'SirVer/ultisnips',
        'quangnguyen30192/cmp-nvim-ultisnips',
        --]]
        -- For luasnip users
        'L3MON4D3/LuaSnip',
        'saadparwaiz1/cmp_luasnip',
    },
    config = function()
        -- Set up nvim-cmp.
        local cmp = require('cmp')

        cmp.setup {
            snippet = {
                -- XXX: Set your snip package
                -- REQUIRED - you must specify a snippet engine
                expand = function(args)
                    -- vim.fn["UltiSnips#Anon"](args.body) -- For `ultisnips` users.
                    require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
                end,
            },
            window = {
                completion = cmp.config.window.bordered(),
                documentation = cmp.config.window.bordered(),
            },
            mapping = cmp.mapping.preset.insert({
                -- Control tips windows of snip
                ['<C-b>'] = cmp.mapping.scroll_docs(-4),
                ['<C-f>'] = cmp.mapping.scroll_docs(4),
                ['<C-Space>'] = cmp.mapping.complete(),
                ['<C-e>'] = cmp.mapping.abort(),
                ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
            }),
            sources = cmp.config.sources({
                { name = 'nvim_lsp' },
                -- XXX: Set your snip package
                -- { name = 'ultisnips' }, -- For ultisnips users.
                { name = 'luasnip' }, -- For luasnip users.
            }, {
                { name = 'buffer' },
            }),
        }

        -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
        cmp.setup.cmdline({ '/', '?' }, {
            mapping = cmp.mapping.preset.cmdline(),
            sources = {
                { name = 'buffer' }
            }
        })

        -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
        cmp.setup.cmdline(':', {
            mapping = cmp.mapping.preset.cmdline(),
            sources = cmp.config.sources({
                { name = 'path' }
            }, {
                { name = 'cmdline' }
            }),
            matching = { disallow_symbol_nonprefix_matching = false }
        })

        -- Set up lspconfig.
        local capabilities = require('cmp_nvim_lsp').default_capabilities()

        -- Replace <YOUR_LSP_SERVER> with each lsp server you've enabled.
        require('lspconfig')['autotools_ls'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['cmake'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['bashls'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['clangd'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['docker_compose_language_service'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['gopls'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['lua_ls'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['jsonls'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['pylsp'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['marksman'].setup {
            capabilities = capabilities,
        }

        require('lspconfig')['yamlls'].setup {
            capabilities = capabilities,
        }
    end
}
