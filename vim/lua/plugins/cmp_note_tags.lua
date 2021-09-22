local source = {}

-- TODO: File-type specific availability.

source.new = function()
    local self = setmetatable({}, {__index = source})
    return self
end

source.get_trigger_characters = function() return {':'} end

source.get_keyword_pattern = function()
    return [=[\%(\s\|^\)\zs:[[:alnum:]_\-\+]*:\?]=]
end

source.complete = function(self, request, callback)
    -- Avoid unexpected completion.
    -- if not vim.regex(self.get_keyword_pattern() .. '$'):match_str(
    --     request.context.cursor_before_line) then return callback() end

    -- if not self.items then self.items = require('cmp_emoji.items') end

    -- callback(self.items)

    local tags = {}
    local function on_exit(_, _, _)
        -- TODO: Ignore duplicates.
        callback(tags)
    end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            line = line:gsub("%s+", "")
            if line ~= "" then table.insert(tags, {label = line}) end
        end, data)
    end

    -- TODO: We should be able to do this without `rg` in pure Lua.
    vim.fn.jobstart(
        "rg --no-filename --no-heading --no-line-number --color=never '^\\s*:\\w*:$' " ..
            vim.api.nvim_get_var('wiki_root'), {
            on_stdout = process_stdout,
            on_stderr = process_stdout,
            on_exit = on_exit,
            stdout_buffered = true,
            stderr_buffered = true
        })
end

return source
