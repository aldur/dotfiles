-- Override compe_tags to only autocomplete markdown headers
-- (which are theirselves tags)
local tags = require("compe_tags")
local Source = {}

function Source.get_metadata(_)
    return {
        priority = 500,
        menu = '[Header]',
        dup = 0,
        filetypes = {'wiki', 'markdown.wiki'}
    }
end

function Source.determine(_, context)
    local start = context.before_line:find('# ', 1, true)
    if start ~= nil then
        return {
            keyword_pattern_offset = start + 2,
            trigger_character_offset = start + 2
        }
    end
end

function Source.complete(x, context)
    return tags.complete(x, context)
end

function Source.documentation(x, context)
    return tags.documentation(x, context)
end

return Source
