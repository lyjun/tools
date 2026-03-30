return {
    --[[
    don't forget to execute "TSUpdate" or install launquage with "TSInstall ${lang}"
    --]]
    -- enabled = false,
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ':TSUpdate',
    config = function()
        require("nvim-treesitter").setup({
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
            sync_install = false,
            auto_install = true,
            ignore_install = {},
        })
    end,
}
