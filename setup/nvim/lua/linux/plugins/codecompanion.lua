return {
    --[[
    -- Code Companion is a Neovim plugin that provides AI-powered code assistance.
    -- It supports various AI models and offers features like inline code suggestions, chat-based interactions,
    -- and command-based actions to enhance your coding experience.
    --
    -- reference:
    -- 1. configuration: https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua
    --]]
    "olimorris/codecompanion.nvim",
    opts = {},
    dependencies = {
        {
            "nvim-lua/plenary.nvim",
            branch = "master",
        },
        "nvim-treesitter/nvim-treesitter",
        "ravitemer/mcphub.nvim",
        -- event notify
        "j-hui/fidget.nvim",
    },
    init = function()
        require("linux.plugins.codecompanion.fidget-spinner"):init()
    end,
    config = function()
        local aiProvider = "copilot" -- gemini|copilot

        require("codecompanion").setup({
            opts = {
                language = "English",
            },
            strategies = {
                chat = {
                    adapter = {
                        name = aiProvider,
                        -- must set model, if not, it will not work.
                        model = "gpt-4.1",
                    },
                    opts = {
                        completion_provider = "cmp", -- blink|cmp|coc|default
                    },
                    roles = {
                        -- XXX: You find emojis here (https://emojipedia.org/)
                        ---The header name for the LLM's messages
                        ---@type string|fun(adapter: CodeCompanion.Adapter): string
                        llm = function(adapter)
                            return "🚑 Assistant (" .. adapter.formatted_name .. ")"
                        end,

                        ---The header name for your messages
                        ---@type string
                        user = "👀 You",
                    }
                },
                inline = {
                    adapter = {
                        name = aiProvider,
                        -- must set model, if not, it will not work.
                        model = "gpt-4.1",
                    },
                },
                cmd = {
                    adapter = aiProvider,
                }
            },
            display = {
                chat = {
                    -- if show_settings is set, we can't dynaymically change ai model.
                    -- show_settings = false,
                    show_token_count = true,
                    show_tools_processing = true,
                    window = {
                        layout = "vertical", -- float|vertical|horizontal|buffer
                        position = "right",  -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
                        width = 0.3,
                    },
                },
            },
            adapters = {
                acp = {
                    -- claude_code = function()
                    --     -- TODO: setup claude code adapter via acp
                    --     -- refer https://codecompanion.olimorris.dev/configuration/adapters.html#setup-claude-code-via-acp
                    --     return require("codecompanion.adapters").extend("claude_code", {
                    --         env = {
                    --             CLAUDE_CODE_OAUTH_TOKEN = "my-oauth-token",
                    --         },
                    --     })
                    -- end,
                    -- gemini_cli = function()
                    --     return require("codecompanion.adapters").extend("gemini_cli", {
                    --         env = {
                    --             api_key = "todo",
                    --         },
                    --     })
                    -- end,
                },
                http = {
                    gemini = function()
                        return require("codecompanion.adapters").extend("gemini", {
                            --[[
                        schema = {
                            model = {
                                default = "gemini-2.5-flash",
                            },
                        },
                        --]]
                            env = {
                                api_key = "TODO",
                            },
                        })
                    end,
                },
            },
            extensions = {
                mcphub = {
                    callback = "mcphub.extensions.codecompanion",
                    opts = {
                        make_vars = true,
                        make_slash_commands = true,
                        show_result_in_chat = true
                    }
                }
            },
        })

        vim.keymap.set({ "n", "v" }, "<leader>aa", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
        vim.keymap.set({ "n", "v" }, "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>",
            { noremap = true, silent = true })
        vim.keymap.set("v", "<leader>ap", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })
    end
}
