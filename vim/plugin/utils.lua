function _G.search_before_closest_open_braket_in_line()
    -- txn = transaction.PaymentTxn(faucet.address, params, receiver.address, amount)
    -- Should return the column just before (
    local line = vim.api.nvim_get_current_line()
    local current_column = vim.api.nvim_eval('getpos(".")')[3]

    line = line:sub(1, current_column)
    local reversed = line:reverse()
    local match = reversed:find("(", 1, true)
    if match == nil then return -1 end

    return current_column - match
end

-- function _G.dump(...)
--     -- https://github.com/nanotee/nvim-lua-guide
--     local objects = vim.tbl_map(vim.inspect, {...})
--     print(unpack(objects))
--     return ...
-- end

function _G.info_message(msg) vim.notify(msg, vim.log.levels.INFO) end

function _G.warning_message(msg) vim.notify(msg, vim.log.levels.WARN) end
