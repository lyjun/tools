return {
    --[[
    don't forget to execute "TSUpdate" or install launquage with "TSInstall ${lang}"
    --]]
    "nvim-treesitter/nvim-treesitter",
    build = ':TSUpdate',
    config = function()
        require("nvim-treesitter.configs").setup({
            -- A list of parser names, or "all" (the five listed parsers should always be installed)
            ensure_installed = {
                "bash",
                "c", "cmake", "comment", "cpp",
                "gitignore", "go", "gomod",
                "helm", "html",
                "json",
                "kconfig",
                "lua",
                "make", "markdown", "markdown_inline",
                "objdump",
                "proto", "python",
                "regex",
                "tmux", "toml",
                "udev",
                "vim", "vimdoc",
                "xml",
                "yaml",
            },

            -- Install parsers synchronously (only applied to `ensure_installed`)
            sync_install = false,
            -- Automatically install missing parsers when entering buffer
            -- Recommendation: set to false if you don't have `tree-sitter` CLI installed locally
            auto_install = false,
            -- List of parsers to ignore installing (or "all")
            ignore_install = {},
            ---- If you need to change the installation directory of the parsers (see -> Advanced Setup)
            -- parser_install_dir = "/some/path/to/store/parsers", -- Remember to run vim.opt.runtimepath:append("/some/path/to/store/parsers")!
            highlight = {
                enable = true,
                additional_vim_regex_highlighting = false
            },
        })
    end,
}
