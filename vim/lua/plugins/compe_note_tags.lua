local Source = {}

function Source.get_metadata(_)
    return {
        priority = 450,
        dup = 0,
        menu = '[NoteTag]',
        filetypes = {'wiki', 'markdown.wiki'}
    }
end

function Source.determine(_, context)
    local start = context.before_line:find(':$')
    if start ~= nil then
        return {
            keyword_pattern_offset = start,
            trigger_character_offset = start
        }
    end
    return {}
end

function Source.complete(_, args)
    local tags = {}
    local function on_exit(_, _, _) args.callback {items = tags} end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            line = line:gsub("%s+", "")
            if line ~= "" then table.insert(tags, line) end
        end, data)
    end

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

return Source
