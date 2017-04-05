-- Original credits: https://github.com/VFS/.hammerspoon/blob/master/tools/clipboard.lua

local frequency = 5.0
local chooser_max_size = 1000
local last_application = nil
local consider_ignore = false
local ignore = {'1Password 6', '1Password mini'}

if consider_ignore then
    hs.window.filter.new(true):subscribe(
        {hs.window.filter.windowFocused, hs.window.filter.windowVisible},
        function(_, name, _) last_application = name end)
end

-- Don't change anything bellow this line
local pasteboard_name = 'com.aldur.clipboard'
local last_change = hs.pasteboard.changeCount()

-- Array to store the clipboard history/the chooser choices.
local clipboard_history = hs.settings.get(pasteboard_name) or {}

-- -- Clears the clipboard and history
-- local function clearAll()
--     pasteboard.clearContents()
--     clipboard_history = {}
--     settings.set(pasteboard_name,clipboard_history)
--     pasteboard.changeCount()
-- end

-- Clears the last added to the history
local function clearLastItem()
    table.remove(clipboard_history, #clipboard_history)
    hs.settings.set(pasteboard_name, clipboard_history)
    hs.pasteboard.changeCount()
end

local function toClipboard(item)
    -- Loop to enforce limit on qty of elements in history. Removes the oldest items
    -- while (#clipboard_history >= hist_size) do
    --     table.remove(clipboard_history, 1)
    -- end

    for i, v in pairs(clipboard_history) do
        if v['text'] == item then table.remove(clipboard_history, i) end
    end

    table.insert(clipboard_history, 1, {text=item, date=os.date()})
    hs.settings.set(pasteboard_name, clipboard_history)
end

local chooser = hs.chooser.new(function(row_info)
    if row_info then hs.pasteboard.setContents(row_info['text']) end
    local lastFocused = hs.window.filter.defaultCurrentSpace:getWindows(hs.window.filter.sortByFocusedLast)
    if #lastFocused > 0 then lastFocused[1]:focus() end
end)
chooser:choices(clipboard_history)

local function storeCopy()
    if last_application and ignore[last_application] then return end
    local now = hs.pasteboard.changeCount()
    if (now > last_change) then
        local current_clipboard = hs.pasteboard.getContents()
        if not current_clipboard then clearLastItem() else toClipboard(current_clipboard) end
        last_change = now

        chooser:choices(clipboard_history)
    end
end

-- hs.timer.new(frequency, storeCopy):start()
hs.eventtap.new({hs.eventtap.event.types.keyUp, }, function(event)
    if not event then return end
    if not event:getFlags()['cmd'] then return end
    if event:getCharacters() ~= 'c' then return end
    storeCopy()
end):start()

return chooser
