-- Suggest Markdown headers (using `tags` under the hood)
local pattern = require('cmp.utils.pattern')
local source = {}

local cmp = require('cmp')

function source:get_debug_name() return 'Markdown Headers' end

function source:is_available()
    -- Only enable this for `markdown`.
    local filetypes = vim.split(vim.bo.filetype, '.',
                                {plain = true, trimempty = true})
    return vim.tbl_contains(filetypes, 'markdown')
end

function source:get_keyword_pattern() return [=[\%(^#\+\s\+\)\zs\k\+]=] end

function source:complete(request, callback)
    local items = {}

    -- Strip leading header markers
    local _, end_ = pattern.offset([[^#\+\s]],
                                   request.context.cursor_before_line)

    local input = string.sub(request.context.cursor_before_line, end_)

    local success, tags = pcall(vim.fn.getcompletion, input, "tag")

    if not success then
        print("Error getting tags!")
        return callback(items)
    end

    if type(tags) ~= 'table' or #tags == 0 then return callback(items) end

    for _, value in pairs(tags) do
        local item = {
            word = value,
            label = value,
            kind = cmp.lsp.CompletionItemKind.Tag
        }
        items[#items + 1] = item
    end

    callback(items)
end

return source
