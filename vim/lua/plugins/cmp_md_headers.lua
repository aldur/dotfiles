-- Override compe_tags to only autocomplete markdown headers
-- (which are theirselves tags)
local tags = require("cmp_nvim_tags")
local source = {}

source.new = function()
    local self = setmetatable({}, {__index = source})
    return self
end

function source:get_debug_name()
  return 'md_headers'
end

function source:is_available()
    -- Only enable this for `markdown`.
    local filetypes = vim.split(vim.bo.filetype, '.', true)
    return vim.tbl_contains(filetypes, 'markdown')
end

function source:complete(request, callback)
    local start = request.context.cursor_before_line:find('# ', 1, true)
    if start ~= nil then tags:complete(request, callback) end
end

return source
