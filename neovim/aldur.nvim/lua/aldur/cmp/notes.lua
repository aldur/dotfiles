local source = {}

source.new = function()
    local self = setmetatable({}, {__index = source})
    return self
end

function source:is_available()
    -- Only enable this for `markdown`.
    local filetypes = vim.split(vim.bo.filetype, '.',
                                {plain = true, trimempty = true})
    return vim.tbl_contains(filetypes, 'markdown')
end

function source:get_debug_name() return 'Note' end

-- NOTE: This works for [ but not for ](
-- Maybe this should return single characters rather than strings.
function source:get_trigger_characters(_) return {"[", "]("} end

function source:get_keyword_pattern(_)
    local note_pattern = "[[:alnum:][:blank:]]*"

    -- [[ and ]] are Lua string delimiters
    -- \%(\s\|^\) matches at beginnnig of line or after whitespace
    -- \%(\) makes sure what's inside does not count as a sub expression.
    -- \[ matches the literal [
    -- \zs means set the start of the match here, i.e. after the [
    -- \ze means set the end of the match here, i.e. before the ]
    -- Within the square brackets we match :alnum: and :blank:
    -- \]\? makes the closing ] optional.
    local square_brakets = [[\%(\s\|^\)\[\zs]] .. note_pattern .. [[\ze\]\?]]

    -- Here we do something similar,
    -- but we only match after a literal sequence of ](
    local round_brackets = [[\%(](\)\zs]] .. note_pattern .. [[\ze)\?]]

    -- Note that the order matter.
    return round_brackets .. [[\|]] .. square_brakets
end

local cmp = require 'cmp'

function source:complete(_, callback)
    local notes = {}
    local function on_exit(_, _, _) callback(notes) end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            if line:match('.md$') then line = line:sub(1, -4) end
            local label = line
            -- if label:len() > 20 then
            --     label = label:sub(0, 20) .. '...'
            -- end
            if line ~= "" then
                table.insert(notes, {
                    label = label,
                    word = line,
                    kind = cmp.lsp.CompletionItemKind.File
                })
            end
        end, data)
    end

    -- TODO: Do this without `fd` in pure Lua or warn if `fd` not in PATH.
    vim.fn.jobstart("fd -t f --base-directory " ..
                        vim.api.nvim_get_var('wiki_root'), {
        on_stdout = process_stdout,
        on_stderr = process_stdout,
        on_exit = on_exit,
        stdout_buffered = true,
        stderr_buffered = true
    })
end

return source
