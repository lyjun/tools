return {
    --[[
    formatter plugin (it is not integrated with mason)

    1. All formmatters can be installed via mason plugin.
    2. Check formatter with conform via executing ":ConformInfo"
    --]]
    'stevearc/conform.nvim',
    opts = {},
    config = function()
        require("conform").setup({
            formatters_by_ft = {
                --[[
                  If you want to specify formatters for the language, revise these settings.
                  Otherwise, it will pick one automatically.

                  -- Example: set formatters for each language
                  formatters_by_ft = {
                      go = { "goimports", "gofmt" },
                      java = { "google-java-format" },
                      lua = { "stylua" },
                  }
                --]]
            },
            -- format code style after save.
            format_on_save = {
                -- These options will be passed to conform.format()
                timeout_ms = 500,
                lsp_format = "fallback",
            },
        })
    end
}
