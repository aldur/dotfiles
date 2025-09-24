--- @module 'blink.cmp'
--- @class blink.cmp.RipgrepEmojiSource
local source = {}

-- `opts` table comes from `sources.providers.ripgrep_emoji.opts`
function source.new(opts)
    local self = setmetatable({}, {__index = source})
    self.opts = {}
    return self
end

function source:enabled() return vim.bo.filetype == 'markdown.wiki' end

-- Trigger when typing ':'
function source:get_trigger_characters() return {':'} end

-- Execute ripgrep to find emoji-like patterns
function source:get_completions(ctx, callback)
    local line = ctx.line
    local line_number = ctx.bounds.line_number - 1

    if not line or line_number > 10 then
        -- Tags are only at the top of the file
        callback({
            items = {},
            is_incomplete_forward = false,
            is_incomplete_backward = false
        })
        return
    end

    -- [=[ and ]=] are Lua string delimiters
    -- The rest is a Lua pattern.
    local pattern = line:match([=[^%s+(%:%w*)%:?$]=])

    if not pattern then
        callback({
            items = {},
            is_incomplete_forward = false,
            is_incomplete_backward = false
        })
        return
    end

    -- Remove the leading colon for the search
    local search_term = pattern:sub(1)

    -- Prepare ripgrep command
    local command = string.format(
                        [[rg --no-heading --no-line-number --no-filename --replace '$1' '^\s+(%s.*:)$' %s | sort -u]],
                        search_term, vim.api.nvim_get_var('wiki_root'))

    -- Keep track of job
    local job_id
    local cancel_request = false
    local items = {}

    local function on_stdout(_, data, _)
        if cancel_request then return end

        for _, match in ipairs(data) do
            if match and match ~= "" then
                table.insert(items, {
                    label = match,
                    kind = require('blink.cmp.types').CompletionItemKind.Text,
                    textEdit = {
                        newText = match,
                        range = {
                            -- 0-indexed line_number and character
                            start = {
                                line = line_number,
                                character = #line - #pattern
                            },
                            ['end'] = {
                                line = line_number,
                                character = #line - #pattern + #match
                            }
                        }
                    }
                })
            end
        end
    end

    local function on_exit(_, _, _)
        if cancel_request then return end

        callback({
            items = items,
            is_incomplete_forward = false,
            is_incomplete_backward = false
        })
    end

    -- Execute the ripgrep command
    job_id = vim.fn.jobstart(command, {
        on_stdout = on_stdout,
        on_stderr = on_stdout,
        on_exit = on_exit,
        stdout_buffered = true,
        stderr_buffered = true
    })

    -- Return a function to cancel the request
    return function()
        cancel_request = true
        if job_id and job_id > 0 then vim.fn.jobstop(job_id) end
    end
end

-- Add documentation for each matched emoji
function source:resolve(item, callback) callback(item) end

-- No special execution needed
function source:execute(ctx, item, callback) callback() end

return source
