-- Modeline {{{
-- vim: set foldmarker={{{,}}} foldlevel=0 foldmethod=marker
-- luacheck: globals hs utf8 globals
-- }}}

-- Require {{{

local spaces = require('hs._asm.undocumented.spaces')
local secrets = require('secrets')

-- }}}

-- Constants / Definitions {{{

-- Change this line to enable verbose logging.
hs.logger.defaultLogLevel = 'info'
local logger = hs.logger.new('init')

-- Use hs.canvas drawing wrapper.
hs.canvas.drawingWrapper(true)

local animationDuration = 0
local shadows = false

local wf = hs.window.filter

globals = {}
globals['WiFi'] = {}
globals['watcher'] = {}
globals['watchable_watcher'] = {}
globals['watchable'] = hs.watchable.new('globals')
globals['windows'] = {}
globals['geeklets'] = {}
globals['timers'] = {}
globals['wfilters'] = {}

local cardinals = { h='west', l='east', k='north', j='south', }
local snapped = {
    west=hs.geometry(0,0,0.5,1), east=hs.geometry(0.5,0,0.5,1),
    north=hs.geometry(0,0,1,0.5), south=hs.geometry(0,0.5,1,0.5),
}

local hyper = {'cmd', 'alt', 'ctrl'}
local hyper_shift = {'cmd', 'alt', 'ctrl', 'shift'}

-- Source http://www.color-hex.com/color-palette/5452
local red = hs.drawing.color.asRGB({red=217/255, green=83/255, blue=79/255})
local green = hs.drawing.color.asRGB({red=92/255, green=184/255, blue=92/255})

-- }}}

-- Settings {{{

hs.window.animationDuration = animationDuration  -- Disable window animation
hs.window.setShadows(shadows)  -- No windows shadow
wf.setLogLevel('error')  -- Only log WF errors
hs.hotkey.setLogLevel('warning')  -- Less verbose hotkey logging
hs.application.enableSpotlightForNameSearches(true)  -- Enable alternate application names

-- }}}

-- Helpers {{{

local function cleanup()
    -- Cleanup here.
    hs.fnutils.each(globals.watcher, function(w) w:stop() end)
    -- hs.fnutils.each(globals.watchable_watcher, function(w) w:release() end)
    hs.fnutils.each(globals.timers, function(t) t:stop() end)
    hs.fnutils.each(globals.geeklets, function(g) g:delete() end)
    hs.fnutils.each(globals.wfilters, function(f) f:unsubscribeAll() end)

    if globals.pushbullet then globals.pushbullet:close() end

    for key in pairs(globals) do globals[key] = nil end
    globals = nil
end

-- }}}

-- WiFi management {{{

-- secrets.SSIDS is a table of the form:
-- secrets.SSIDS = {
--     ['SSID']='Network location name',
-- }

-- secrets.SSID_CALLBACKS is a table of the form:
-- secrets.SSID_CALLBACKS = {
--     ['Network location name']={
--         function() assert(hs.audiodevice.findDeviceByName("Built-in Output"):setMuted(true)) end,  -- IN callback
--         function() assert(hs.audiodevice.findDeviceByName("Built-in Output"):setMuted(false)) end,  -- OUT callback
--     },
-- }

globals.WiFi.lastSSID = hs.wifi.currentNetwork()
local function ssidChangedCallback()
    local newSSID = hs.wifi.currentNetwork()

    if newSSID == nil and hs.wifi.interfaceDetails('en0').power then
        hs.notify.new({
            title="Hammerspoon",
            informativeText="Wireless disconnected",
            contentImage=hs.image.imageFromPath('icons/internet.ico'),
            autoWithdraw=true
        }):send()
        return
    end

    local networkLocation = secrets.SSIDS[newSSID] or 'Automatic'
    local networkConfiguration = hs.network.configuration.open()
    local networkLocations = networkConfiguration:locations()

    if ((globals.WiFi.lastSSID == newSSID
                and networkLocations[networkConfiguration:location()] == networkLocation) or
            not hs.wifi.interfaceDetails('en0').power) then
        return
    end

    if networkConfiguration:setLocation(networkLocation) then
        if not hs.wifi.interfaceDetails('en0').power then hs.wifi.setPower(true, 'en0') end
        hs.notify.new({
                title="Hammerspoon",
                contentImage=hs.image.imageFromPath("icons/internet.ico"),
                informativeText="Selecting '" .. networkLocation .. "' network location.",
                autoWithdraw=true
            }):send()
    else
        hs.notify.new({
                title="Hammerspoon",
                informativeText="An error occurred while managing network locations.",
                autoWithdraw=true
            }):send()
    end

    -- Execute IN callback for new network location.
    local callback = secrets.SSID_CALLBACKS[networkLocation]
    if callback then assert(#callback == 2); callback[1]() end

    -- Execute OUT callback for last network location.
    local lastSSID = globals.WiFi.lastSSID
    local lastNetworkLocation = secrets.SSIDS[lastSSID] or 'Automatic'
    callback = secrets.SSID_CALLBACKS[lastNetworkLocation]
    if callback then assert(#callback == 2); callback[2]() end

    globals.WiFi.lastSSID = newSSID
end
globals.watcher.WiFi = hs.wifi.watcher.new(ssidChangedCallback):start()

-- }}}

-- USB management {{{

-- local function usbDeviceCallback(data)
--     if data["productID"] == 49944 and data["vendorID"] == 1133 then
--         if (data["eventType"] == "added") then
--             hs.keycodes.setLayout('Keyboard Illuminated IT')
--         elseif (data["eventType"] == "removed") then
--             hs.keycodes.setLayout('Italian')
--         end
--     end
-- end
-- globals["watcher"]["usb"] = hs.usb.watcher.new(usbDeviceCallback):start()

-- }}}

-- Spaces {{{

local function adjacentSpace(left)
    local layout = spaces.layout()[spaces.mainScreenUUID()]

    local current = hs.fnutils.indexOf(layout, spaces.activeSpace())
    assert(current ~= nil)

    local adjacent
    if not left then
        adjacent = current % #layout + 1
    else
        adjacent = current ~= 1 and current - 1 or #layout
    end

    return layout[adjacent], adjacent
end

local function moveToNextSpace(window, left)
    local newSpaceID = adjacentSpace(left)
    window:spacesMoveTo(newSpaceID)
    hs.window.frontmostWindow():focus()
end

-- }}}

-- Windows {{{

local function focusLastFocused()
    local lastFocused = wf.defaultCurrentSpace:getWindows(wf.sortByFocusedLast)
    if #lastFocused > 0 then lastFocused[1]:focus() end
end

local function focusSecondToLastFocused()
    local lastFocused = wf.default:getWindows(wf.sortByFocusedLast)
    if #lastFocused > 1 then lastFocused[2]:focus() end
end

globals.windows.savedFrames = {}
local function saveFrame(window)
    assert(window)
    local savedFrame = globals.windows.savedFrames[window:id()]
    if savedFrame == nil then
        globals.windows.savedFrames[window:id()] = window:frame()
    end
end

local function setFrame(window, frame)
    assert(window)
    local windowID = window:id()
    assert(windowID)

    -- Check if window was snapped on one of the borders.
    local cardinal = hs.fnutils.indexOf(globals["windows"], windowID)
    if cardinal then globals.windows[cardinal] = nil end

    local savedFrame = globals.windows.savedFrames[windowID]
    if frame == nil and savedFrame == nil then return end  -- Nothing to do

    if frame == nil then
        assert(savedFrame)
        window:setFrame(savedFrame)  -- Restore the original frame
        globals.windows.savedFrames[windowID] = nil
        return
    end

    saveFrame(window)  -- Save the current frame.

    if frame and frame.x <= 1 and frame.y <= 1
        and frame.w <= 1 and frame.h <= 1 then
        window:moveToUnit(frame)
    else
        window:move(frame)
    end

    -- Store that window is snapped to one of the borders.
    cardinal = hs.fnutils.indexOf(snapped, frame)
    if cardinal then globals.windows[cardinal] = windowID end
end

local function resize(window, enlarge)
    if not window then return end

    local frame = window:frame()
    assert(frame)

    if enlarge then
        frame.x = frame.x - (frame.w * 1 / 20)
        frame.y = frame.y - (frame.h * 1 / 20)

        frame.w = frame.w * 11 / 10
        frame.h = frame.h * 11 / 10

        if frame.x < 0 then frame.x = 0 end
        if frame.y < 0 then frame.y = 0 end

        local screen = window:screen():frame()
        if frame.w > screen.w then frame.w = screen.w end
        if frame.h > screen.h then frame.h = screen.h end
    else
        frame.x = frame.x + (frame.w * 1 / 20)
        frame.y = frame.y + (frame.h * 1 / 20)

        frame.w = frame.w * 9 / 10
        frame.h = frame.h * 9 / 10
    end

    setFrame(window, frame)
end

-- }}}

-- Grid {{{

hs.grid.setGrid('11x7')

-- }}}

-- Window filters {{{

globals.wfilters.finder = wf.copy(
    wf.defaultCurrentSpace):setDefaultFilter(false):setAppFilter('Finder')
globals.wfilters.finder:subscribe(wf.windowDestroyed, function(_, _, _)
    -- Focus last focused window as soon as a window is destroyed.
    focusLastFocused()
end)

-- }}}

-- Emojis {{{

globals.emojis = hs.loadSpoon('Emojis')

-- }}}

-- Bindings {{{

-- Configuration reload
hs.hotkey.bind(hyper_shift, "r", function()
    cleanup()
    hs.reload()
    hs.notify.new({title="Hammerspoon", informativeText="Configuration reloaded",
        autoWithdraw=true}):send()
end)

-- Toggle console
hs.hotkey.bind(hyper_shift, "c", function()
    hs.toggleConsole()
    hs.window.frontmostWindow():focus()
end)

-- Clipboard manager
globals.clipboard = require('clipboard')
hs.hotkey.bind(hyper, "c", function()
    local clipboard = globals.clipboard.chooser
    if clipboard:isVisible() then clipboard:hide() else clipboard:show() end
    hs.window.frontmostWindow():focus()
end)

-- Force pasting where forbidden
hs.hotkey.bind(hyper, "v", function()
    hs.eventtap.keyStrokes(hs.pasteboard.getContents())
end)

-- Move through the grid
hs.fnutils.each({
    {"up", "Up"}, {"down", "Down"}, {"left", "Left"}, {"right", "Right"},
}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        saveFrame(hs.window.focusedWindow());
        hs.grid["pushWindow" .. k[2]]()
    end)
end)

-- Shrink/enlarge within the grid
hs.fnutils.each({
    {"up", "Shorter"}, {"down", "Taller"}, {"left", "Thinner"}, {"right", "Wider"},
}, function(k)
    hs.hotkey.bind(hyper_shift, k[1], function()
        saveFrame(hs.window.focusedWindow());
        hs.grid["resizeWindow" .. k[2]]()
    end)
end)

-- Quick open Downloads/Desktop
hs.fnutils.each({{"d", "Downloads"}, {"s", "Desktop"}}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        hs.applescript('tell application "Finder"\n'
        .. 'open folder "' .. k[2] .. '" of home\nactivate\nend tell')
    end)
end)

-- Move window to space on left/right
hs.fnutils.each({{"right", false}, {"left", true}}, function(k)
    hs.hotkey.bind({"ctrl", "shift"}, k[1], function()
        local focused = hs.window.focusedWindow()
        if focused then moveToNextSpace(focused, k[2]) end
    end)
end)

-- Fullscreen / revert to original
hs.fnutils.each({{"delete", nil}, {"return", hs.geometry(0,0,1,1)}}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        local focused = hs.window.focusedWindow()
        if focused then setFrame(focused, k[2]) end
    end)
end)

-- Snap west, south, north, east
hs.fnutils.each({"h", "j", "k", "l"}, function(k)
    hs.hotkey.bind(hyper_shift, k, function()
        local focused = hs.window.focusedWindow()
        if focused then setFrame(focused, snapped[cardinals[k]]) end
    end)
end)

-- Focus window on west, south, north, east
hs.fnutils.each({"h", "j", "k", "l"}, function(k)
    hs.hotkey.bind(hyper, k, function()
        local snappedID = globals["windows"][cardinals[k]]
        if snappedID and hs.window.get(snappedID) then
            hs.window.get(snappedID):focus()
            return
        end

        local f = "focusWindow" .. cardinals[k]:gsub("^%l", string.upper)
        wf.defaultCurrentSpace[f](wf.defaultCurrentSpace,
            nil, false, false
        )
    end)
end)

-- Focus second-last focused window
hs.hotkey.bind(hyper, ',', function()
    focusSecondToLastFocused()
end)

-- Center on screen
hs.hotkey.bind(hyper, ".", function()
    local focused = hs.window.focusedWindow()
    saveFrame(focused)
    if focused then focused:centerOnScreen() end
end)

-- Enlarge / shrink window
hs.fnutils.each({{"-", false}, {"=", true}}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        resize(hs.window.focusedWindow(), k[2])
    end)
end)

-- Focus/launch most commonly used applications.
hs.fnutils.each({
    {'M', 'com.deezer.Deezer'}, {'B', 'com.google.Chrome'},
    {'O', 'com.omnigroup.OmniFocus2'}, {'W', 'com.kapeli.dashdoc'}
}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        local window = hs.window.focusedWindow()
        if window and window:application():bundleID() == k[2] then
            focusSecondToLastFocused()
        else
            assert(hs.application.launchOrFocusByBundleID(k[2]))
        end
    end)
end)

-- Emoji chooser
globals.emojis:bindHotkeys({toggle={hyper, 'e'}})

-- }}}

-- iTerm2 {{{

-- Launch iTerm2 by pressing alt-space
hs.hotkey.new({"alt"}, "space", function()
    local iTerms = hs.application.applicationsForBundleID("com.googlecode.iterm2")

    if #iTerms == 0 then
        hs.application.open("com.googlecode.iterm2")
        return
    end

    local iTerm2 = iTerms[1]
    local w = iTerm2:mainWindow()
    if not w then
        hs.osascript.applescript('tell application "iTerm2" \n'
            .. 'create window with default profile\n' ..
            'end tell')
        return
    elseif w == hs.window.focusedWindow() then
        iTerm2:hide()
    else
        w:focus()
    end
end):enable()

-- }}}

-- Pushbullet {{{

local pb_api_key = secrets.PUSHBULLET_API_KEY

hs.notify.register('pb', function()
    hs.http.asyncGet('https://api.pushbullet.com/v2/pushes?limit=1',
    {["Access-Token"]=pb_api_key},
    function(status, body, _)
        if not status or status > 200 then
            logger.e('[Pushbullet] - Error (' .. status .. ") while getting pushes.")
            return
        end

        local pushes = hs.json.decode(body)
        local push = pushes.pushes[1]
        if not push.dismissed then
            assert(push.iden)
            hs.http.asyncPost(
                'https://api.pushbullet.com/v2/pushes/' .. push.iden,
                hs.json.encode({dismissed=true}),
                {["Access-Token"]=pb_api_key, ["Content-Type"]='application/json'},
                function(postStatus, _, _)
                    if not postStatus or postStatus > 200 then
                        logger.e('[Pushbhullet] - Error (' .. postStatus .. ") while marking push as read")
                    end
                end
            )
        end
    end)
end)

local function pushbullet()
    return hs.http.websocket(
        'wss://stream.pushbullet.com/websocket/' .. pb_api_key,
        function(ws_body)
            local alert = hs.json.decode(ws_body)
            if alert['type'] == 'nop' then return end
            hs.http.asyncGet('https://api.pushbullet.com/v2/pushes?limit=1',
            {["Access-Token"]=pb_api_key},
            function(status, body, _)
                if not status or status > 200 then
                    logger.e("[Pushbullet] - Error (" .. status .. ") while getting pushes.")
                    return
                end

                local pushes = hs.json.decode(body)
                local push = pushes.pushes[1]
                if not push or push.dismissed or not push.body then return end

                hs.pasteboard.setContents(push.body)
                hs.notify.new('pb', {
                    title=push.title or "Pushbullet",
                    informativeText=push.body, autoWithdraw=true,
                    contentImage=hs.image.imageFromPath('icons/pushbullet.ico')
                }):send()
            end)
        end)
end

-- The callback will start Pushbullet as soon as Internet connectivity is found.
globals.watchable_watcher.reachability_pb = hs.watchable.watch('globals', 'reachability',
    function(_, _, _, _, _)
        if not globals.watchable.reachability then
            if globals.pushbullet then logger.v('[Pushbullet] - Closing PB.'); globals.pushbullet:close() end
        else
            logger.v('[Pushbullet] - Creating new PB instance.'); globals.pushbullet = pushbullet()
        end
    end)

-- }}}

-- Reachability {{{

local function testPing()
    logger.v('[Ping] - Testing ping.')
    local pingReceived = false
    hs.network.ping.ping('8.8.8.8', 2, 0.1, 2.0, 'IPv4', function(_, message, _, _)
        if message == 'didFail' or message == 'sendPacketFailed' or (
                message == 'didFinish' and not pingReceived) then
            logger.v('[Ping] - Ping did fail.')
            globals.watchable.reachability = false
        elseif message == 'receivedPacket' then
            logger.v('[Ping] - Ping did succeed.')
            pingReceived = true
        elseif message == 'didFinish' and pingReceived then
            logger.v('[Ping] - Ping did finish.')
            globals.watchable.reachability = true
        end
    end)
end
globals.timers.ping = hs.timer.doEvery(10, function() testPing() end)

local function reachabilityCallback(_, flags)
    if flags == hs.network.reachability.flags.reachable then
        -- A default route exists, so an active internet connection may be present
        logger.v('[Reachability] - Active route found.')
        testPing()
    else
        -- No default route exists, so no active internet connection is present
        logger.v('[Reachability] - No active Internet connection.')
        globals.watchable.reachability = false
    end
end

globals.watcher.internet = hs.network.reachability.internet():setCallback(reachabilityCallback):start()
reachabilityCallback(nil, globals.watcher.internet:status())

-- }}}

-- Drawing {{{

local geekletsTextStyle = {
    font={name='Futura', size=22},
    strokeColor=hs.drawing.color.asRGB({red=0, green=0, blue=0, alpha=1}),
    color=hs.drawing.color.asRGB({red=1, green=1, blue=1, alpha=1}),
    strokeWidth=-1.0,
    paragraphStyle={alignment='center', lineBreak='truncateMiddle'}
}

local function drawTimeGeeklet(r)
    local geeklets = globals.geeklets
    local timeString = hs.styledtext.new(os.date("%H:%M"), geekletsTextStyle)
    local time = geeklets['time']
    if time == nil then
        time = hs.drawing.text(r, timeString)
        geeklets['time'] = time
        assert(geeklets['time'])
        time:show()
    else
        time:setStyledText(timeString)
    end
end

local function drawMusicGeeklet(r)
    local geeklets = globals.geeklets
    local empty = hs.styledtext.new("", geekletsTextStyle)

    local music = geeklets['music']
    if music == nil then
        music = hs.drawing.text(hs.geometry.rect(r), empty)
        geeklets['music'] = music
        music:show()
    end
    assert(music)

    local musicApp
    if hs.deezer.isRunning() then
        musicApp = hs.deezer
    elseif hs.spotify.isRunning() then
        musicApp = hs.spotify
    else
        music:setStyledText(empty)
        return
    end

    assert(musicApp)
    local track = musicApp.getCurrentTrack()
    local album = musicApp.getCurrentAlbum()
    local artist = musicApp.getCurrentArtist()

    if not track or not album or not artist then return end

    music:setStyledText(hs.styledtext.new(
        track .. " | " .. album .. " | " .. artist, geekletsTextStyle
    ))
end

local function drawBatteryGeeklet(r)
    local geeklets = globals.geeklets

    local prefix = ''
    if hs.battery.isCharging() then prefix = '+' end
    local batteryPercentage = hs.styledtext.new(prefix .. math.floor(hs.battery.percentage()) .. "%", geekletsTextStyle)

    local battery = geeklets['battery']
    if battery == nil then
        battery = hs.drawing.text(r, batteryPercentage)
        geeklets['battery'] = battery
        battery:show()
    else
        battery:setStyledText(batteryPercentage)
    end
end

local function drawInternetGeeklet(r)
    local geeklets = globals.geeklets

    local color = red
    if globals.watchable.reachability then
        color = green
    end

    local internet = geeklets['internet']
    if internet == nil then
        internet = hs.drawing.circle(r)
        internet:setFillColor(color)
        internet:setStroke(false)
        geeklets['internet'] = internet
        assert(geeklets['internet'])
        internet:show()
    else
        internet:setFillColor(color)
    end
end

local function drawVPNGeeklet(r)
    local geeklets = globals.geeklets

    local color = red
    -- if hs.application.find('net.tunnelblick.tunnelblick') then
    if true then
        local states_code, states, _ = hs.osascript.applescript([[
            tell application "Tunnelblick" to get state of configurations
        ]])

        if not states_code then
            logger.e('[Geeklets] - Could not get Tunnelblick configuration states.')
            states = {}
        end

        for _, state in ipairs(states) do
            if state == 'CONNECTED' then color = green; break end
        end
    end

    local vpn = geeklets['vpn']
    if vpn == nil then
        vpn = hs.drawing.circle(r)
        vpn:setStroke(false)
        vpn:setFillColor(color)
        geeklets['vpn'] = vpn
        assert(geeklets['vpn'])
        vpn:show()
    else
        vpn:setFillColor(color)
    end
end

local function drawBackground(height, y)
    local frame = hs.screen.primaryScreen():frame()

    local background = hs.drawing.rectangle(hs.geometry.rect(0, y, frame.w, height))
    background:setStroke(false)
    background:setFillColor(hs.drawing.color.asRGB({red=0, green=0, blue=0, alpha=0.4}))
    background:setLevel(hs.drawing.windowLevels['desktop'])
    background:setBehaviorByLabels({'stationary', 'canJoinAllSpaces'})

    return background
end

local function drawTopGeeklets()
    local geeklets = globals.geeklets
    local height = 50
    local textVOffset = (height - geekletsTextStyle['font']['size'] * 1.33)
    local frame = hs.screen.primaryScreen():frame()

    local top_background = drawBackground(height, 10)
    geeklets['top_bg'] = top_background
    top_background:show()

    local timeRect = hs.geometry.rect(0, textVOffset, frame.w / 4, height / 3 * 2)
    drawTimeGeeklet(timeRect)
    local musicRect = hs.geometry.rect(frame.w / 5, textVOffset, frame.w / 5 * 3, height / 3 * 2)
    drawMusicGeeklet(musicRect)
    local batteryRect = hs.geometry.rect(frame.w * 3 / 4, textVOffset, frame.w / 4, height / 3 * 2)
    drawBatteryGeeklet(batteryRect)

    for _, geeklet in pairs(geeklets) do
        geeklet:setLevel(hs.drawing.windowLevels['desktop'])
        geeklet:setBehaviorByLabels({'stationary', 'canJoinAllSpaces'})
    end

    local timers = globals.timers
    timers['g_time'] = hs.timer.doEvery(10, function() drawTimeGeeklet(timeRect) end)
    timers['g_music'] = hs.timer.doEvery(10, function() drawMusicGeeklet(musicRect) end)
    timers['g_battery'] = hs.timer.doEvery(60, function() drawBatteryGeeklet(batteryRect) end)

    globals.watcher.g_battery = hs.battery.watcher.new(function() drawBatteryGeeklet(batteryRect) end)
end

local function drawBottomGeeklets()
    local geeklets = globals.geeklets
    local frame = hs.screen.primaryScreen():frame()

    local internetRect = hs.geometry.rect(10, frame.h - 20, 10, 10)
    drawInternetGeeklet(internetRect)

    local vpnRect = hs.geometry.rect(10 + 10 / 3 * 2, frame.h - 20, 10, 10)
    drawVPNGeeklet(vpnRect)

    for _, geeklet in pairs(geeklets) do
        geeklet:setLevel(hs.drawing.windowLevels['desktop'])
        geeklet:setBehaviorByLabels({'stationary', 'canJoinAllSpaces'})
    end

    globals.watchable_watcher.reachability_drawing = hs.watchable.watch('globals', 'reachability',
        function(_, _, _, _, _) drawInternetGeeklet(internetRect) end)

    local timers = globals.timers
    timers['g_vpn'] = hs.timer.doEvery(10, function() drawVPNGeeklet(vpnRect) end)
end

local function setupScreenlets()
    local geeklets = globals.geeklets
    local timers = globals.timers

    for _, geeklet in pairs(geeklets) do geeklet:hide() end
    globals.geeklets = {}

    for name, timer in pairs(timers) do
        -- Only remove timers that start with 'g_'.
        if string.sub(name, 1, string.len('g_')) == 'g_' then
            timer:stop()
            timers[name] = nil
        end
    end

    if globals.watcher['g_battery'] then
        globals.watcher.g_battery:stop()
        globals.watcher['g_battery'] = nil
    end

    drawTopGeeklets()
    drawBottomGeeklets()
end
setupScreenlets()

globals.watcher.screen = hs.screen.watcher.new(function() setupScreenlets() end)
globals.watcher.screen:start()

-- }}}

-- Instapaper {{{

require('instapaper')

-- }}}

-- Seal {{{

local seal = require('seal')
seal:init({'tunnelblick', 'network_locations', 'snippets', 'macos', 'hammerspoon'})
seal:start(hyper, 'space')

-- }}}
