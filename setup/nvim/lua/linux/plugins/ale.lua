return {
    --[[
    ALE (Asynchronous Lint Engine) is a plugin providing linting (syntax checking and semantic errors)
    in NeoVim 0.6.0+ and Vim 8.0+ while you edit your text files, and acts as a Vim Language Server Protocol client.

    Tip:
    1. Run the following to see what is currently configured:
        :ALEInfo
    2. you can install Language Server Protocol linters via Mason with linter tab.

    --]]
    enabled = true,
    "dense-analysis/ale",
    config = function()
        --[[
        -- example for configuring ale

        -- Configuration goes here.
        local g = vim.g

        g.ale_ruby_rubocop_auto_correct_all = 1

        g.ale_linters = {
            ruby = {'rubocop', 'ruby'},
            lua = {'lua_language_server'}
        }
        --]]
    end
}
