-- luacheck: no self

local obj = {}
obj.__index = obj
obj.__name = 'seal_hammerspoon'
obj.__icon = hs.image.imageFromAppBundle('org.hammerspoon.Hammerspoon')
obj.__logger = hs.logger.new(obj.__name)
obj.__caffeine = nil

function obj.clipboardToPocket()
    local success, _, _ = hs.applescript([[do shell script "open hammerspoon://pocket"]])
    if not success then obj.__logger.e('Got an error while opening Hammerspoon/Pocket url handler.') end
end

function obj.clipboardToTermBin()
    local success, output, _ = hs.applescript([[do shell script "pbpaste | nc termbin.com 9999"]])
    if not success then obj.__logger.e('Got an error while sending clipboard to TermBin.'); return end

    success, _, _ = hs.applescript(string.format([[do shell script "open '%s'"]], output))
    if not success then obj.__logger.e('Got an error while opening TermBin url.'); return end
end

function obj.clipboardToFile()
    local success, _, _ = hs.applescript(
        [[do shell script "open 'hammerspoon://clipboard?clipboard=/tmp/clipboard.json&archive=/tmp/archive.json'"]])
    if not success then obj.__logger.e('Got an error while opening Hammerspoon/Clipboard url handler.') end
end

function obj.clearClipboard()
    local success, _, _ = hs.applescript(
        [[do shell script "open 'hammerspoon://clipboard?clear_all=True'"]])
    if not success then obj.__logger.e('Got an error while opening Hammerspoon/Clipboard url handler.') end
end

function obj.archiveClipboard()
    local success, _, _ = hs.applescript(
        [[do shell script "open 'hammerspoon://clipboard?archive_all=True'"]])
    if not success then obj.__logger.e('Got an error while opening Hammerspoon/Clipboard url handler.') end
end

function obj.showCaffeineMenubar(isEnabled)
    if isEnabled == nil then isEnabled = hs.caffeinate.get('displayIdle') end
    if isEnabled then
        if obj.__caffeine ~= nil then return end
        obj.__caffeine = hs.menubar.new():setIcon('icons/caffeine-on.pdf'):setTooltip(
            'Caffine is active'):setMenu({{title='Caffine is active', disabled=true},
            {title='-'}, {title='Disable Caffeine', fn=obj.toggleCaffeine}})
    else
        if obj.__caffeine == nil then return end
        obj.__caffeine:delete()
        obj.__caffeine = nil
    end
end

function obj.toggleCaffeine()
    obj.showCaffeineMenubar(hs.caffeinate.toggle('displayIdle'))
end

obj.cmds = {
    {text='Clipboard to Pocket', type='clipboardToPocket'},
    {text='Clipboard to TermBin', type='clipboardToTermBin'},
    {text='Save Clipboard to File', type='clipboardToFile'},
    {text='Clear Clipboard', type='clearClipboard'},
    {text='Archive Clipboard', type='archiveClipboard'},
    {text='Toggle Caffeine', type='toggleCaffeine'},
    {text='Create Meeting Note', type='meetingNote'},
}

function obj:commands()
    return {hs={
            cmd='hs', fn=obj.choicesMacOS,
            name='Hammerspoon command',
            description="Send a command to Hammerspoon",
            plugin=obj.__name, icon=obj.__icon,
    }}
end

function obj:bare() return nil end

function obj.choicesMacOS(query)
    query = query:lower()
    local choices = {}

    for _, command in pairs(obj.cmds) do
        if (string.match(command.text:lower(), query) or
                string.match((command.subText or ''):lower(), query)) then
            command['plugin'] = obj.__name
            command['image'] = obj.__icon
            table.insert(choices, command)
        end
    end
    table.sort(choices, function(a, b) return a['text'] < b['text'] end)

    return choices
end

function obj.completionCallback(row_info)
    if not row_info then return end
    obj[row_info.type]()
end

obj.showCaffeineMenubar()
return obj
