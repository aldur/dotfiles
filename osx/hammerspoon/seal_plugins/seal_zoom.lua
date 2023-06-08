-- luacheck: no self

local obj = {}
obj.__index = obj
obj.__name = 'seal_zoom'
obj.__icon = hs.image.imageFromAppBundle('us.zoom.xos')
obj.__logger = hs.logger.new(obj.__name)

local secrets = require("secrets")
obj.zoom_rooms = secrets.zoom_rooms


function obj:commands()
    return {zoom={
            cmd='zoom', fn=obj.choicesZoom,
            name='Zoom',
            description="Join a Zoom room",
            plugin=obj.__name, icon=obj.__icon,
    }}
end

function obj:bare() return nil end

function obj.choicesZoom(query)
    query = query:lower()
    local choices = {}

    for _, room in pairs(obj.zoom_rooms) do
        if string.match(room.name:lower(), query) then
            local choice = {}
            choice['text'] = room.name
            choice['subText'] = room.number
            choice['room_number'] = room.number
            choice['plugin'] = obj.__name
            choice['image'] = obj.__icon
            table.insert(choices, choice)
        end
    end
    table.sort(choices, function(a, b) return a['text'] < b['text'] end)

    return choices
end

function obj.completionCallback(row_info)
    if not row_info then return end
    if not hs.urlevent.openURL('zoommtg://zoom.us/join?confno=' .. row_info.room_number) then
        obj.__logger.e('Error while opening Zoom URL')
    end
end

return obj
