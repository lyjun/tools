return {
    --[[
    MCP Hub: A Neovim plugin for managing model context protocols (MCPs) and their associated files.

    Recommended plugin:
    1. context7: allow LLM to use latest package documentation and generate useful code examples

    --]]
    "ravitemer/mcphub.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    build = "bundled_build.lua", -- Bundles `mcp-hub` binary along with the neovim plugin
    config = function()
        require("mcphub").setup({
            use_bundled_binary = true, -- Use local `mcp-hub` binary
        })
    end,
}
