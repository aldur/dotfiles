-- luacheck: globals pandoc
-- luacheck: globals FORMAT
local list_text_map = {["XXX"] = "red", ["NOTE"] = "blue", ["INFO"] = "blue"}

local function replace(elem)
    for marker, color in pairs(list_text_map) do
        local match, punctuation = elem.text:match(
                                       "(" .. marker .. ")" .. "(%p?)")
        if match ~= nil then
            local t = pandoc.Span(pandoc.Strong(pandoc.Str(match)))
            t.attributes['style'] = 'color: ' .. color .. ';'
            local r = {t}

            if punctuation then
                table.insert(r, pandoc.Str(punctuation))
            end

            return r
        end
    end

    return elem
end

if FORMAT:match 'html' then
    return {{Str = replace}}
else
    return {}
end
