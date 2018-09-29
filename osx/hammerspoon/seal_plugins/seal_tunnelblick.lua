-- luacheck: no self

local obj = {}
obj.__index = obj
obj.__name = 'seal_tunnelblick'
obj.__icon = hs.image.imageFromAppBundle('net.tunnelblick.tunnelblick')
obj.__logger = hs.logger.new(obj.__name)

-- Disconnect all other VPNs before connecting.
local disconnect_before = true

function obj:commands()
    return {vpn={
            cmd="vpn", fn=obj.choicesVPNCommand,
            name="Tunnelblick",
            description="Manage Tunnelblick connections",
            plugin=obj.__name, icon=obj.__icon,
    }}
end

function obj:bare() return nil end

function obj.getVPNConnections()
    local names_code, names, _ = hs.osascript.applescript([[
        tell application "Tunnelblick" to get name of configurations
    ]])
    if not names_code then hs.logger.e('Could not get Tunnelblick configuration names.'); return {} end

    local states_code, states, _ = hs.osascript.applescript([[
        tell application "Tunnelblick" to get state of configurations
    ]])
    if not states_code then obj.__logger('Could not get Tunnelblick configuration states.'); return {} end

    local connections = {}
    for idx, value in ipairs(names) do
        connections[value] = states[idx]
    end

    return connections
end

function obj.disconnectVPN(name)
    -- TODO: Add checks.
    local code, _, _ = hs.osascript.applescript(string.format([[
        tell application "Tunnelblick" to disconnect "%s"
    ]], name))

    if not code then
        obj.__logger(string.format(
            'An error occurred while disconnecting Tunnelblick from "%s".'), name)
    end
end

function obj.disconnectAll()
    local code, _, _ = hs.osascript.applescript([[
        tell application "Tunnelblick" to disconnect all
    ]])

    if not code then
        obj.__logger('An error occurred while disconnecting Tunnelblick from all.')
    end
end

function obj.connectVPN(name)
    if disconnect_before then obj.disconnectAll() end

    -- TODO: Add checks.
    local code, _, _ = hs.osascript.applescript(string.format([[
        tell application "Tunnelblick" to connect "%s"
    ]], name))

    if not code then
        obj.__logger(string.format(
            'An error occurred while connecting Tunnelblick to "%s".'), name)
        end
end

function obj.choicesVPNCommand(query)
    local choices = {}
    local connections = obj.getVPNConnections()
    local img_connected = hs.image.imageFromPath("icons/locked.png")
    local img_disconnected = hs.image.imageFromPath("icons/unlocked.png")

    for name, state in pairs(connections) do
        if string.match(name:lower(), query:lower()) then
            local choice = {}
            choice['text'] = name
            choice['subText'] = state

            if state == 'CONNECTED' then
                choice['image'] = img_connected
            else
                choice['image'] = img_disconnected
            end

            choice['name'] = name
            choice['state'] = state
            choice['plugin'] = obj.__name
            choice['type'] = 'toggle'
            table.insert(choices, choice)
        end
    end

    table.sort(choices, function(a, b)
            if (a.state == b.state) then return a.name < b.name else return a.state < b.state end end)

    local choice = {text='Disconnect all', plugin=obj.__name, type='disconnect'}
    table.insert(choices, 1, choice)

    return choices
end

function obj.completionCallback(rowInfo)
    if rowInfo["type"] == "toggle" then
        if rowInfo["state"] == "CONNECTED" then
            obj.disconnectVPN(rowInfo["name"])
        else
            obj.connectVPN(rowInfo["name"])
        end
    elseif rowInfo['type'] == 'disconnect' then
        obj.disconnectAll()
    end
end

return obj
