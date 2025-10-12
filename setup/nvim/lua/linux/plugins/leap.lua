return {
    --[[
      Leap's default motions allow you to jump to any position in the visible editor area by entering a 2-character search pattern, and then potentially a label character to pick your target from multiple matches, similar to Sneak.
    --]]
    "ggandor/leap.nvim",
    config = function()
        vim.keymap.set({ 'n', 'x', 'o' }, '<leader>s', '<Plug>(leap)')
        vim.keymap.set('n', '<leader>S', '<Plug>(leap-from-window)')
    end
}
