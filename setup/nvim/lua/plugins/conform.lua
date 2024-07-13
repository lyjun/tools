return {
    --[[
    1. set your filetypes with spefific formmatters above. Otherwise, it will pick one automatically.
    2. All formmatters can be installed via mason plugin.
    3. Check formatter with conform via executing ":ConformInfo"
    ]] --
    'stevearc/conform.nvim',
    opts = {},
    config = function()
        require("conform").setup({
            formatters_by_ft = {
                -- go = { "goimports", "gofmt" },
                -- java = { "google-java-format" },
                -- lua = { "stylua" },
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
