local source = {}

source.new = function()
    local self = setmetatable({}, {__index = source})
    return self
end

function source:is_available()
    -- Only enable this for `markdown`.
    local filetypes = vim.split(vim.bo.filetype, '.', true)
    return vim.tbl_contains(filetypes, 'markdown')
end

function source:get_debug_name()
    return 'NoteTags'
end

function source:get_trigger_characters(_)
  return { ":" }
end

function source:get_keyword_pattern(_)
    -- Don't ask what this mean.
    -- Taken from https://github.com/hrsh7th/cmp-emoji,
    -- Then addeed ^\s to only match after whitespace at beginning of line.
    -- Does not seem to work.
    return [=[^\s\%(\s\|^\)\zs:[[:alnum:]_\-\+]*:\?]=]
end

function source:complete(_, callback)
    local unique_tags = {}
    local function on_exit(_, _, _)
        local tags = {}
        for k,_ in pairs(unique_tags) do table.insert(tags, {label=k}) end
        callback(tags)
    end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            line = line:gsub("%s+", "")
            if line ~= "" then
                unique_tags[line] = true  -- Build a table with unique keys.
            end
        end, data)
    end

    -- TODO: Do this without `rg` in pure Lua or warn if `rg` not in PATH.
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
