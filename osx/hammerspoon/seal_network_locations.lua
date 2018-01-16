-- luacheck: no self

local obj = {}
obj.__index = obj
obj.__name = 'seal_network_locations'
obj.__icon = hs.image.imageFromPath('icons/internet.ico')

function obj:commands()
    return {network={
            cmd='net', fn=obj.choicesNetworkLocation,
            name='Network Location',
            description="Set a network location",
            plugin=obj.__name, icon=obj.__icon,
    }}
end

function obj:bare() return nil end

function obj.getNetworkLocations()
    return hs.network.configuration.open():locations()
end

function obj.selectNetworkLocation(uuid)
    return hs.network.configuration.open():setLocation(uuid)
end

function obj.choicesNetworkLocation(query)
    local choices = {}
    local locations = obj.getNetworkLocations()

    for _, location in pairs(locations) do
        if string.match(location:lower(), query:lower()) then
            local choice = {}
            choice['text'] = location
            choice['plugin'] = obj.__name
            table.insert(choices, choice)
        end
    end
    table.sort(choices, function(a, b) return a['text'] < b['text'] end)

    return choices
end

function obj.completionCallback(row_info)
    obj.selectNetworkLocation(row_info['text'])
end

return obj
