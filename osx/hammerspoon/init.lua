-- Modeline {{{
-- vim: set foldmarker={{{,}}} foldlevel=0 foldmethod=marker
-- }}}

-- luacheck: globals hs
-- luacheck: globals globals
-- luacheck: no self

-- Require {{{

local secrets = require('secrets')

-- }}}

-- Constants / Definitions {{{

-- Change this line to enable verbose logging.
hs.logger.defaultLogLevel = 'debug'
local logger = hs.logger.new('init')

local animationDuration = 0
local shadows = false

local wf = hs.window.filter

globals = {}
globals.WiFi = {}
globals.watcher = {}
globals.windows = {}
globals.wfilters = {}
globals.modals = {}

local cardinals = { h='west', l='east', k='north', j='south', }
local snapped = {
    west=hs.geometry(0,0,0.5,1), east=hs.geometry(0.5,0,0.5,1),
    north=hs.geometry(0,0,1,0.5), south=hs.geometry(0,0.5,1,0.5),
}

local hyper = {'cmd', 'alt', 'ctrl'}
local hyper_shift = {'cmd', 'alt', 'ctrl', 'shift'}

-- }}}

-- Settings {{{

hs.window.animationDuration = animationDuration  -- Disable window animation
hs.window.setShadows(shadows)  -- No windows shadow
wf.setLogLevel('error')  -- Only log WF errors
hs.hotkey.setLogLevel('warning')  -- Less verbose hotkey logging
hs.application.enableSpotlightForNameSearches(true)  -- Enable alternate application names
hs.grid.setGrid('11x7')  -- Grid size
local margin = hs.geometry('5x5')
hs.grid.setMargins(margin)

-- }}}

-- Helpers {{{

local function cleanup()
    -- Cleanup here.
    hs.fnutils.each(globals.watcher, function(w) w:stop() end)
    -- hs.fnutils.each(globals.watchable_watcher, function(w) w:release() end)
    hs.fnutils.each(globals.wfilters, function(f) f:unsubscribeAll() end)

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
            autoWithdraw=true,
            hasActionButton=false,
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
                autoWithdraw=true,
                hasActionButton=false,
            }):send()
    else
        hs.notify.new({
                title="Hammerspoon",
                informativeText="An error occurred while managing network locations.",
                autoWithdraw=true,
                hasActionButton=false,
            }):send()
        logger.e('[Network Locations] Error setting ' .. networkLocation .. '.')
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

-- require('usb')

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
    if window == nil then return end
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

    if frame == 'full' then
        hs.grid.maximizeWindow(window)
    elseif frame and frame.x <= 1 and frame.y <= 1
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

-- Window filters {{{

-- Focus last window when closing Finder.
globals.wfilters.finder = wf.copy(wf.defaultCurrentSpace):
    setDefaultFilter(false):setAppFilter('Finder'):
    subscribe(wf.windowDestroyed, focusLastFocused)

-- }}}

-- Emojis {{{

globals.emojis = hs.loadSpoon('Emojis')

-- }}}

-- Seal {{{

globals.seal = hs.loadSpoon('Seal')
globals.seal:loadPlugins({'tunnelblick', 'network_locations', 'snippets', 'macos', 'hammerspoon', 'zoom'})
globals.seal:bindHotkeys({toggle={hyper, 'space'}})
globals.seal:start()

-- }}}

-- Bindings {{{

-- Configuration reload
hs.hotkey.bind(hyper_shift, "r", function()
    cleanup()
    hs.reload()
end)

-- Toggle console
hs.hotkey.bind(hyper_shift, "c", function()
    hs.toggleConsole()
    hs.window.frontmostWindow():focus()
end)

-- Clipboard manager
globals.clipboard = require('clipboard')
hs.hotkey.bind(hyper, "c", globals.clipboard.toggle)

-- Force pasting where forbidden
hs.hotkey.bind(hyper_shift, "v", function()
    hs.eventtap.keyStrokes(hs.pasteboard.getContents())
end)

-- Grid Snapping Mode {{{

local h = hs.hotkey.modal.new(hyper, 'q')
globals.modals.grid_snapping_hotkey = h
function h:entered()
    hs.alert('Entered grid snapping mode')
end
function h:exited()
    hs.alert('Exited grid snapping mode')
end
h:bind('', 'escape', function() h:exit() end)

-- Move through the grid
hs.fnutils.each({
    {"k", "Up"}, {"j", "Down"}, {"h", "Left"}, {"l", "Right"},
}, function(k)
    h:bind('', k[1], nil, function()
        saveFrame(hs.window.focusedWindow());
        hs.grid["pushWindow" .. k[2]]()
    end)
end)

-- Shrink/enlarge within the grid
hs.fnutils.each({
    {"k", "Shorter"}, {"j", "Taller"}, {"h", "Thinner"}, {"l", "Wider"},
}, function(k)
    h:bind('shift', k[1], nil, function()
        saveFrame(hs.window.focusedWindow());
        hs.grid["resizeWindow" .. k[2]]()
    end)
end)

-- }}}

-- Quick open Downloads/Desktop
local home = os.getenv("HOME")
hs.fnutils.each({{"d", "Downloads"}, {"s", "Desktop"}}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        -- os.execute('open ~/' .. k[2])
        local url = 'file://' .. home .. '/' .. k[2]
        if not hs.urlevent.openURL(url) then
            logger.e('Error opening URL:' .. url)
        end
    end)
end)

-- Fullscreen / revert to original
hs.fnutils.each({{"delete", nil}, {"return", 'full'}}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        local focused = hs.window.focusedWindow()
        if not focused then return end
        setFrame(focused, k[2])
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
        wf.defaultCurrentSpace[f](wf.defaultCurrentSpace, nil, false, false)
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

local function focusOrSwitch(bundleID)
    if bundleID == nil then return end
    local window = hs.window.focusedWindow()
    if window and window:application():bundleID() == bundleID then
        focusSecondToLastFocused()
    else
        assert(hs.application.launchOrFocusByBundleID(bundleID))
    end
end

-- Focus/launch most commonly used applications.
hs.fnutils.each({
    {'M', 'com.spotify.client'}, {'B', 'com.apple.Safari'},
    {'W', 'com.kapeli.dashdoc'}, {'T', 'com.qvacua.VimR'},
    {'G', 'com.culturedcode.ThingsMac'}, {'X', 'com.tinyspeck.slackmacgap'},
}, function(k)
    hs.hotkey.bind(hyper, k[1], function() focusOrSwitch(k[2]) end)
end)

-- Focus/launch most commonly used applications across multiple options.
hs.fnutils.each({
    {'P', {'com.jetbrains.pycharm', 'com.microsoft.VSCode', 'com.apple.dt.Xcode'}},
    {'Z', {'us.zoom.xos', 'com.cisco.webexmeetingsapp', 'com.microsoft.teams'}}
}, function(k)
    hs.hotkey.bind(hyper, k[1], function()
        for _, bundleID in pairs(k[2]) do
            if hs.application.get(bundleID) ~= nil then
                focusOrSwitch(bundleID)
                return
            end
        end

        -- Fallback to open and focus the first one.
        focusOrSwitch(k[2][1])
    end)
end)

-- Get network latency
-- Source: https://medium.com/@robhowlett/hammerspoon-the-best-mac-software-youve-never-heard-of-40c2df6db0f8
local function pingResult(object, message, _, _)
    if message == "didFinish" then
        local avg = tonumber(string.match(object:summary(), '/(%d+.%d+)/'))
        if avg == 0.0 then
            hs.alert.show("No network")
        elseif avg < 200.0 then
            hs.alert.show("Network: good (" .. avg .. "ms)")
        elseif avg < 500.0 then
            hs.alert.show("Network: poor(" .. avg .. "ms)")
        else
            hs.alert.show("Network: bad(" .. avg .. "ms)")
        end
    end
end

hs.hotkey.bind(hyper_shift, "p", function()
    hs.network.ping.ping("8.8.8.8", 1, 0.01, 0.5, "any", pingResult)
end)

-- Emoji chooser

globals.emojis:bindHotkeys({toggle={hyper, 'e'}})

-- }}}

-- iTerm2 {{{

-- Launch iTerm2 by pressing alt-space
-- Showing/hiding the window is managed within iTerm itself
local function launchOrFocusITerm()
    local iTerms = hs.application.applicationsForBundleID('com.googlecode.iterm2')
    assert(#iTerms <= 1)

    if #iTerms == 0 then
        hs.application.open('com.googlecode.iterm2')
    else
        -- Pass the hotkey through.
        globals.iTermHotkey:disable()
        hs.eventtap.keyStroke({'alt'}, 'space')
        globals.iTermHotkey:enable()
    end
end
globals.iTermHotkey = hs.hotkey.new({'alt'}, 'space', launchOrFocusITerm):enable()

-- }}}

-- Pocket {{{

require('pocket')

-- }}}

-- Audio input/output {{{

globals.audio = require('audio')
hs.hotkey.bind(hyper, "a", globals.audio.toggleAudioInput)

-- }}}

-- Local Configuration {{{

if hs.fs.attributes('local.lua') then
    require('local')
end

-- }}}

-- Ending {{{

hs.notify.new({
    title="Hammerspoon",
    informativeText="Hammerspoon is ready",
    autoWithdraw=true,
    hasActionButton=false,
}):send()

-- }}}
