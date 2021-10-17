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
    return 'Note'
end

function source:get_trigger_characters(_)
  return { "[", "](", }
end
-- function source:get_keyword_pattern(_)
--     return [=[^\s\%(\s\|^\)\zs[:[[:alnum:]_\-\+]*:\?]=]
-- end

function source:complete(_, callback)
    local notes = {}
    local function on_exit(_, _, _)
        callback(notes)
    end

    local function process_stdout(_, data, _)
        vim.tbl_map(function(line)
            if line:match('.md$') then line = line:sub(1, -4) end
            if line ~= "" then table.insert(notes, {label=line}) end
        end, data)
    end

    -- TODO: Do this without `fd` in pure Lua or warn if `fd` not in PATH.
    vim.fn.jobstart(
        "fd -t f --base-directory " .. vim.api.nvim_get_var('wiki_root'), {
            on_stdout = process_stdout,
            on_stderr = process_stdout,
            on_exit = on_exit,
            stdout_buffered = true,
            stderr_buffered = true
        })
end

return source
