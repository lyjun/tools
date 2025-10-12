return {
    --[[
      code completion / suggestion plugin
    --]]
    enabled = true,
    "github/copilot.vim",
    config = function()
        -- vim.g.copilot_settings = { selectedCompletionModel = 'gpt-4o-copilot' }
    end,
}
