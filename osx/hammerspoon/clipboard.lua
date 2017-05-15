-- Original credits: https://github.com/VFS/.hammerspoon/blob/master/tools/clipboard.lua
-- luacheck: ignore module

local pasteboard_name='com.aldur.clipboard'
local archive_name='com.aldur.clipboard.archive'
local logger = hs.logger.new('clipboard')

module = {
    frequency=2.0,
    chooser_max_size=1000,
    archive_max_size=10000,
    element_max_size=1000,
    consider_ignore=true,
    trim=true,
    ignore={'1Password 6', '1Password mini'},

    last_application=nil,
    last_change=hs.pasteboard.changeCount(),
    clipboard_history=hs.settings.get(pasteboard_name) or {},
    archive=hs.settings.get(archive_name) or {},
}

if module.consider_ignore then
    module.wf = hs.window.filter.new(true):subscribe(
        {hs.window.filter.windowFocused, hs.window.filter.windowVisible},
        function(_, name, _) module.last_application = name end)
end

-- Clears the clipboard and history
local function clearAll()
    module.clipboard_history = {}
    hs.settings.set(pasteboard_name, module.clipboard_history)
    hs.pasteboard.clearContents()
    hs.pasteboard.changeCount()
end

-- Archives/clears the clipboard and history
local function archiveAll()
    while (#module.clipboard_history > 0) do table.insert(module.archive, 1, table.remove(module.clipboard_history)) end
    hs.settings.set(archive_name, module.archive)
    hs.settings.set(pasteboard_name, module.clipboard_history)
    hs.pasteboard.clearContents()
    hs.pasteboard.changeCount()
end

-- Clears the last added to the history
local function clearLastItem()
    table.remove(module.clipboard_history, #module.clipboard_history)
    hs.settings.set(pasteboard_name, module.clipboard_history)
    hs.pasteboard.changeCount()
end

local function toClipboard(item)
    while (#module.clipboard_history >= module.chooser_max_size) do
        table.insert(module.archive, 1, table.remove(module.clipboard_history))
        hs.settings.set(archive_name, module.archive)
    end

    for i, v in pairs(module.clipboard_history) do
        if v.text == item then table.remove(module.clipboard_history, i) end
    end

    table.insert(module.clipboard_history, 1, {text=item, date=os.date()})
    hs.settings.set(pasteboard_name, module.clipboard_history)
end

module.chooser = hs.chooser.new(function(row_info)
    if row_info then hs.pasteboard.setContents(row_info['text']) end
    local lastFocused = hs.window.filter.defaultCurrentSpace:getWindows(hs.window.filter.sortByFocusedLast)
    if #lastFocused > 0 then lastFocused[1]:focus() end
end)
module.chooser:choices(module.clipboard_history)

local function storeCopy()
    if (module.last_application and
        module.ignore[module.last_application]) then return end
    local now = hs.pasteboard.changeCount()
    if (now > module.last_change) then
        module.last_change = now
        local current_clipboard = hs.pasteboard.getContents()

        if not current_clipboard
            then clearLastItem()
        elseif #current_clipboard > module.element_max_size then
            return
        else
            if module.trim then
                -- Strip leading/trailing whitespace
                current_clipboard = current_clipboard:gsub("^%s*(.-)%s*$", "%1")
            end
            toClipboard(current_clipboard)
        end

        module.chooser:choices(module.clipboard_history)
    end
end

module.timer = hs.timer.new(module.frequency, storeCopy):start()
module.eventtap = hs.eventtap.new({hs.eventtap.event.types.keyUp, }, function(event)
    if not event or not event:getFlags()['cmd'] or event:getCharacters() ~= 'c' then return end
    storeCopy()
end):start()

hs.urlevent.bind('clipboard', function(_, params)
    if params.clear_all then
        logger.i('Clearing the clipboard.')
        clearAll()
    elseif params.archive_all then
        logger.i('Archiving the clipboard.')
        archiveAll()
    else
        assert(params.clipboard)
        logger.i('Storing the clipboard.')

        local f = io.open(params.clipboard, 'w')
        f:write(hs.json.encode(module.clipboard_history, true))
        f:close()

        if params.archive then
            logger.i('Storing the archive.')
            f = io.open(params.archive, 'w')
            f:write(hs.json.encode(module.archive, true))
            f:close()
        end

    end

    hs.window.frontmostWindow():focus()  -- Always focus frontmost window before returning
end)

return module
