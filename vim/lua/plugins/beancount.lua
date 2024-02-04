local M = {}

local cmp = require "cmp"

function M.reload_beancount_completions()
    for _, s in pairs(cmp.core.sources) do
        if s.name == "beancount" then
            s.source.items = nil
            print("Beacnount completions will reload...")
        end
    end
end

return M
