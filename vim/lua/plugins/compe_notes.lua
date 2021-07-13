local Source = {}

function Source.get_metadata(_)
    -- TODO: Add a warning if `fd` is not in $PATH.
    return {
        priority = 450,
        dup = 0,
        menu = '[Note]',
        filetypes = {'wiki', 'markdown.wiki'}
    }
end

function Source.determine(_, context)
    -- Ordering is important here.
    local start = context.before_line:find('](', 1, true)
    if start ~= nil then
        return {
            keyword_pattern_offset = start + 2,
            trigger_character_offset = start + 2
        }
    end

    start = context.before_line:find('[', 1, true)
    if start ~= nil then
        return {
            keyword_pattern_offset = start + 1,
            trigger_character_offset = start + 1
        }
    end

    return {}
end

function Source.complete(_, args)
    local notes = {}
    local function on_exit(_, _, _) args.callback {items = notes} end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            if line:match('.md$') then line = line:sub(1, -4) end
            if line ~= "" then table.insert(notes, line) end
        end, data)
    end

    -- We use `fd` because I am lazy, and we also can lookup asynchronously
    vim.fn.jobstart("fd -t f --base-directory " ..
                        vim.api.nvim_get_var('wiki_root'), {
        on_stdout = process_stdout,
        on_stderr = process_stdout,
        on_exit = on_exit,
        stdout_buffered = true,
        stderr_buffered = true
    })
end

return Source
