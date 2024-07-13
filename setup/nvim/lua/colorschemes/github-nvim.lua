return {
    'projekt0n/github-nvim-theme',
    config = function()
        require('github-theme').setup({
            palettes = {
                github_dark_colorblind = {
                    -- let hidden file more visible on neo-tree
                    blue = {
                        base = "#f4f9fd",
                        bright = "#fbfdfe",
                    },
                },
            },
        })
    end
}
