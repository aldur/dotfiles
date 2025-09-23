-- Modeline {{{
-- vim: set foldmarker={{{,}}} foldlevel=0 foldmethod=marker:
-- }}}
-- luacheck: no self
-- Require {{{
local secrets = require("secrets")

-- }}}

-- Constants / Definitions {{{

-- Change this line to enable verbose logging.
hs.logger.defaultLogLevel = "debug"
local logger = hs.logger.new("init")

local animationDuration = 0
local shadows = false

local wf = hs.window.filter

Globals = {}
Globals.WiFi = {}
Globals.watcher = {}
Globals.windows = {}
Globals.wfilters = {}

local hyper = { "cmd", "alt", "ctrl" }
local hyper_shift = { "cmd", "alt", "ctrl", "shift" }

-- }}}

-- Settings {{{

hs.window.animationDuration = animationDuration -- Disable window animation
hs.window.setShadows(shadows) -- No windows shadow
wf.setLogLevel("error") -- Only log WF errors
hs.hotkey.setLogLevel("warning") -- Less verbose hotkey logging
hs.application.enableSpotlightForNameSearches(true) -- Enable alternate application names

-- }}}

-- Helpers {{{

local function cleanup()
	-- Cleanup here.
	hs.fnutils.each(Globals.watcher, function(w)
		w:stop()
	end)
	-- hs.fnutils.each(globals.watchable_watcher, function(w) w:release() end)
	hs.fnutils.each(Globals.wfilters, function(f)
		f:unsubscribeAll()
	end)

	for key in pairs(Globals) do
		Globals[key] = nil
	end
	Globals = nil
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

Globals.WiFi.lastSSID = hs.wifi.currentNetwork()
local function ssidChangedCallback()
	local newSSID = hs.wifi.currentNetwork()

	if newSSID == nil and hs.wifi.interfaceDetails("en0").power then
		hs.notify
			.new({
				title = "Hammerspoon",
				informativeText = "Wireless disconnected",
				contentImage = hs.image.imageFromPath("icons/internet.ico"),
				autoWithdraw = true,
				hasActionButton = false,
			})
			:send()
		return
	end

	local networkLocation = secrets.SSIDS[newSSID] or "Automatic"
	local networkConfiguration = hs.network.configuration.open()
	local networkLocations = networkConfiguration:locations()

	if
		(Globals.WiFi.lastSSID == newSSID and networkLocations[networkConfiguration:location()] == networkLocation)
		or not hs.wifi.interfaceDetails("en0").power
	then
		return
	end

	if networkConfiguration:setLocation(networkLocation) then
		if not hs.wifi.interfaceDetails("en0").power then
			hs.wifi.setPower(true, "en0")
		end
		hs.notify
			.new({
				title = "Hammerspoon",
				contentImage = hs.image.imageFromPath("icons/internet.ico"),
				informativeText = "Selecting '" .. networkLocation .. "' network location.",
				autoWithdraw = true,
				hasActionButton = false,
			})
			:send()
	else
		hs.notify
			.new({
				title = "Hammerspoon",
				informativeText = "An error occurred while managing network locations.",
				autoWithdraw = true,
				hasActionButton = false,
			})
			:send()
		logger.e("[Network Locations] Error setting " .. networkLocation .. ".")
	end

	if secrets["SSID_CALLBACKS"] then
		-- Execute IN callback for new network location.
		local callback = secrets.SSID_CALLBACKS[networkLocation]
		if callback then
			assert(#callback == 2)
			callback[1]()
		end

		-- Execute OUT callback for last network location.
		local lastSSID = Globals.WiFi.lastSSID
		local lastNetworkLocation = secrets.SSIDS[lastSSID] or "Automatic"
		callback = secrets.SSID_CALLBACKS[lastNetworkLocation]
		if callback then
			assert(#callback == 2)
			callback[2]()
		end
	end

	Globals.WiFi.lastSSID = newSSID
end
Globals.watcher.WiFi = hs.wifi.watcher.new(ssidChangedCallback):start()

-- }}}

-- Windows {{{

local function focusLastFocused()
	local lastFocused = wf.defaultCurrentSpace:getWindows(wf.sortByFocusedLast)
	if #lastFocused > 0 then
		lastFocused[1]:focus()
	end
end

local function focusSecondToLastFocused()
	local lastFocused = wf.default:getWindows(wf.sortByFocusedLast)
	if #lastFocused > 1 then
		lastFocused[2]:focus()
	end
end

-- }}}

-- Window filters {{{

-- hs.window.filter._showCandidates()
local w_to_ignores = {
	"WindowManager",
	"Control Centre",
	"Wallpaper",
	"talagent",
	"Notification Centre",
	"Dock Extra",
	"Stats",
	"TextInputMenuAgent",
	"SecretAgent",
	"Adobe Content Synchronizer Finder Extension",
	"Shortcuts Events",
	"Karabiner-NotificationWindow",
	"Universal Control",
	"Mail Networking",
	"Mail Graphics and Media",
	"universalAccessAuthWarn",
	"UserNotificationCenter",
	"com.apple.hiservices-xpcservice",
	"MobileDeviceUpdater",
	"AutoFillPanelService",
	"Mail (Finder) Networking",
	"Adobe Content Synchronizer Finder Extension",
	"Google Chrome Helper (Plugin)",
	"Safari Graphics and Media",
	"AXVisualSupportAgent",
	"CoreLocationAgent",
	"SoftwareUpdateNotificationManager",
	"Single Sign-On",
	"coreautha",
	"TextInputSwitcher",
	"DockHelper",
	"OSDUIHelper",
	"Safari Service Worker (skiff.com)",
	"Tailscale",
	"AccessibilityVisualsAgent",
	"Safari Web Content (Prewarmed)",
	"Dash Networking",
	"Dash Web Content",
	"Dash Graphics and Media",
	"Safari Web Content (Cached)",
	"com.apple.WebKit.WebContent",
	"Safari Web Content",
}

for _, name in pairs(w_to_ignores) do
	hs.window.filter.ignoreAlways[name] = true
end

-- Focus last window when closing Finder.
Globals.wfilters.finder = wf.copy(wf.defaultCurrentSpace)
	:setDefaultFilter(false)
	:setAppFilter("Finder")
	:subscribe(wf.windowDestroyed, function(_, _, _)
		-- Finder always keeps a background window open.
		local f = hs.application("com.apple.finder")
		if f and #f:allWindows() == 1 then
			focusLastFocused()
		end
	end)

Globals.watcher.mail = hs.application.watcher
	.new(function(_, event, application)
		if event ~= hs.application.watcher.activated then
			return
		end
		if application:bundleID() ~= "com.apple.mail" then
			return
		end
		if #application:allWindows() > 0 then
			return
		end
		hs.eventtap.keyStroke({ "cmd" }, "0")
	end)
	:start()
-- }}}

-- Emojis {{{

-- Globals.emojis = hs.loadSpoon("Emojis")
-- Globals.emojis:bindHotkeys({ toggle = { hyper, "e" } })

-- }}}

-- Seal {{{

Globals.seal = hs.loadSpoon("Seal")
Globals.seal:loadPlugins({ "snippets", "macos", "hammerspoon", "shortcuts" })
Globals.seal:bindHotkeys({ toggle = { hyper, "space" } })
Globals.seal:start()

-- }}}

-- Bindings {{{

-- Configuration reload
hs.hotkey.bind(hyper_shift, "r", function()
	logger.i("Starting reload...") -- Useful for timings
	cleanup()
	hs.reload()
end)

-- Toggle console
hs.hotkey.bind(hyper_shift, "c", function()
	hs.toggleConsole()
	hs.window.frontmostWindow():focus()
end)

-- Clipboard manager
-- Globals.clipboard = require("clipboard")
-- hs.hotkey.bind(hyper, "c", Globals.clipboard.toggle)

-- Force pasting where forbidden
hs.hotkey.bind(hyper_shift, "v", function()
	hs.eventtap.keyStrokes(hs.pasteboard.getContents())
end)

hs.hotkey.bind(hyper_shift, "d", function()
	hs.eventtap.keyStrokes(os.date("%Y-%m-%d"))
end)

-- Quick open Downloads/Desktop
local home = os.getenv("HOME")
hs.fnutils.each({ { "d", "Downloads" }, { "s", "Desktop" } }, function(k)
	hs.hotkey.bind(hyper, k[1], function()
		-- os.execute('open ~/' .. k[2])
		local url = "file://" .. home .. "/" .. k[2]
		if not hs.urlevent.openURL(url) then
			logger.e("Error opening URL:" .. url)
		end
	end)
end)

local function launchFocusOrSwitchBack(bundleID)
	if bundleID == nil then
		return
	end
	local window = hs.window.focusedWindow()
	if window and window:application():bundleID() == bundleID then
		focusSecondToLastFocused()
	else
		assert(hs.application.launchOrFocusByBundleID(bundleID))
	end
end

-- Focus/launch most commonly used applications.
hs.fnutils.each({
	{ "B", "com.apple.Safari" },
	{ "W", "org.zealdocs.zeal" },
	{ "G", "com.culturedcode.ThingsMac" }, -- {'X', 'com.tinyspeck.slackmacgap'},
	{ "X", "com.apple.Safari.WebApp.48BE0633-CEC2-4ACA-AE9C-7C9BA07EEBF7" },
	{ "I", "com.apple.MobileSMS" },
	{ "F", "com.apple.finder" },
}, function(k)
	hs.hotkey.bind(hyper, k[1], function()
		launchFocusOrSwitchBack(k[2])
	end)
end)

hs.hotkey.bind("cmd", [[\]], function()
	launchFocusOrSwitchBack("com.bitwarden.desktop")
end)

local function getMeetingClients()
	local clients = {
		"com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan", -- Google Meet?
		"com.apple.FaceTime",
		"com.google.Chrome.app.fdbibeljcgcjkpedilpdafnjdmbjjjep", -- Zoom
		-- 'com.cisco.webexmeetingsapp', 'com.webex.meetingmanager',
		-- 'com.microsoft.teams'
	}

	-- This is a Google Chrome app and the bundleID changes
	-- We first check if we can find it, then extract the bundle ID

	-- TODO: This only works if the application is running,
	-- but this function gets called once when HS in init.
	local zoom = hs.application.get("Zoom")
	if zoom ~= nil then
		table.insert(clients, 1, zoom:bundleID())
	end

	-- Give preference to Google Meet
	local googleMeet = hs.application.get("Google Meet")
	if googleMeet ~= nil then
		table.insert(clients, 1, googleMeet:bundleID())
	end

	return clients
end

-- Focus/launch most commonly used applications across multiple options.
hs.fnutils.each({
	{ "M", { "com.apple.Music", "tv.plex.plexamp" } },
	{ "T", { "com.neovide.neovide", "com.qvacua.VimR" } },
	{
		"P",
		{ "com.jetbrains.pycharm", "com.microsoft.VSCode", "com.apple.dt.Xcode" },
	},
	{ "Z", getMeetingClients() },
}, function(k)
	hs.hotkey.bind(hyper, k[1], function()
		for _, bundleID in pairs(k[2]) do
			if hs.application.get(bundleID) ~= nil then
				launchFocusOrSwitchBack(bundleID)
				return
			end
		end

		-- Fallback to open and focus the first one.
		launchFocusOrSwitchBack(k[2][1])
	end)
end)

-- Get network latency
-- Source: https://medium.com/@robhowlett/hammerspoon-the-best-mac-software-youve-never-heard-of-40c2df6db0f8
local function pingResult(object, message, _, _)
	if message == "didFinish" then
		local avg = tonumber(string.match(object:summary(), "/(%d+.%d+)/"))
		if avg == 0.0 then
			hs.alert.show("No network")
		elseif avg < 200.0 then
			hs.alert.show("Network: good (" .. avg .. "ms)")
		elseif avg < 500.0 then
			hs.alert.show("Network: poor (" .. avg .. "ms)")
		else
			hs.alert.show("Network: bad (" .. avg .. "ms)")
		end
	end
end

hs.hotkey.bind(hyper_shift, "p", function()
	hs.network.ping.ping("8.8.8.8", 1, 0.01, 0.5, "any", pingResult)
end)

-- }}}

-- iTerm2 {{{

-- Launch iTerm2 by pressing alt-space
-- Showing/hiding the window is managed within iTerm itself
-- local function launchOrFocusITerm()
-- 	local iTermBudleID = "com.googlecode.iterm2"
-- 	local iTerms = hs.application.applicationsForBundleID(iTermBudleID)
-- 	assert(#iTerms <= 1)
--
-- 	if #iTerms == 0 then
-- 		hs.application.open("com.googlecode.iterm2")
-- 	else
-- 		-- Bufgix for Safari 17.0
-- 		local focusedWindow = hs.window.focusedWindow()
-- 		if focusedWindow then
-- 			local focusedApp = focusedWindow:application()
-- 			if focusedApp and focusedApp:bundleID() == "com.apple.Safari" then
-- 				launchFocusOrSwitchBack(iTermBudleID)
-- 				return
-- 			end
-- 		end
--
-- 		-- Pass the hotkey through.
-- 		Globals.iTermHotkey:disable()
-- 		hs.eventtap.keyStroke({ "alt" }, "space")
-- 		Globals.iTermHotkey:enable()
-- 	end
-- end
-- Globals.iTermHotkey = hs.hotkey.new({ "alt" }, "space", launchOrFocusITerm):enable()

-- }}}

-- Audio input/output {{{

Globals.audio = require("audio")
hs.hotkey.bind(hyper, "a", Globals.audio.toggleInputMute)

-- }}}

-- Local Configuration {{{

if hs.fs.attributes("local.lua") then
	require("local")
end

-- }}}

-- Ending {{{

hs.notify
	.new({
		title = "Hammerspoon",
		informativeText = "Hammerspoon is ready",
		autoWithdraw = true,
		hasActionButton = false,
	})
	:send()

-- }}}
