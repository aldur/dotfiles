-- luacheck: no self

local obj = {}
obj.__index = obj
obj.__name = 'seal_snippets'
obj.__icon = hs.image.imageFromAppBundle('com.apple.TextEdit')

local secrets = require("secrets")
obj.snippets = secrets.snippets

function obj:commands()
    return {snip={
            cmd='snip', fn=obj.choicesSnippets,
            name='Snippets',
            description="Choose a snippet",
            plugin=obj.__name, icon=obj.__icon,
    }}
end

function obj:bare() return nil end

function obj.choicesSnippets(query)
    query = query:lower()
    local choices = {}

    for _, snippet in pairs(obj.snippets) do
        if (string.match(snippet.name:lower(), query) or
                string.match(snippet.snippet:lower(), query)) then
            local choice = {}
            choice['text'] = snippet.name
            choice['subText'] = hs.fnutils.split(snippet.snippet, '\n', 1, true)[1]
            choice['snippet'] = snippet.snippet
            choice['plugin'] = obj.__name
            table.insert(choices, choice)
        end
    end
    table.sort(choices, function(a, b) return a['text'] < b['text'] end)

    return choices
end

function obj.completionCallback(row_info)
    if row_info then hs.pasteboard.setContents(row_info.snippet) end
    local lastFocused = hs.window.filter.defaultCurrentSpace:getWindows(hs.window.filter.sortByFocusedLast)
    if #lastFocused > 0 then lastFocused[1]:focus() end
end

return obj
