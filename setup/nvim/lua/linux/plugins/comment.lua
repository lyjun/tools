return {
    "numToStr/Comment.nvim",
    config = function()
        require('Comment').setup({
            --- LHS of toggle mappings in NORMAL mode
            toggler = {
                ---Line-comment toggle keymap
                line = 'gcc',
                ---Block-comment toggle keymap
                block = 'gbc',
            },
        })
    end
}
