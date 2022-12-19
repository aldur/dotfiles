-- luacheck: globals hs
-- luacheck: globals globals
local logger = hs.logger.new('mic')
logger.level = 3

local module = {}
module.__menubar = nil

-- This is the single source of truth for this module.
-- If this is set to true, then all input devices MUST be muted.
module.isMuted = false

local function setAudioInput(isMuted)
    for _, d in pairs(hs.audiodevice.allInputDevices()) do
        local name = d:name()
        if name == nil then name = '<nil>' end

        if isMuted then
            logger.d('Muting input of ' .. name .. '.')
        else
            logger.d('Unmuting input of ' .. name .. '.')
        end

        if not d:setInputMuted(module.isMuted) then
            logger.d('Device ' .. name .. 'does not support muting.')
        end
    end
end

local function setAudioWatch()
    for _, d in pairs(hs.audiodevice.allInputDevices()) do
        if not d:watcherIsRunning() then
            assert(d:watcherCallback(module.localAudioWatchCallback))
            assert(d:watcherStart())
        end
    end
end

function module.localAudioWatchCallback(device_uid, event_name, event_scope, _)
    -- Some applications (I'm looking at you, Zoom US), override the mute-state.
    -- If that happens, we reset it to the truth of this module.
    if event_name == 'mute' and (event_scope == 'glob' or event_scope == 'inpt') then
        local d = hs.audiodevice.findDeviceByUID(device_uid)
        if d == nil then
            logger.w('Received an event for `nil` device with name "' ..
                         device_uid .. '".')
            return
        end

        local name = d:name()
        if name == nil then name = '<nil>' end

        if d:inputMuted() ~= module.isMuted then
            local m = 'false'
            if module.isMuted then m = 'true' end
            logger.i('Device named ' .. name ..
                         ' did not respect the module `isMuted` state (' .. m ..
                         '). Re-setting it.')
            assert(d:setInputMuted(module.isMuted))
        end
    end
end

-- Global audio device watcher. Triggered when a device gets added or removed.
function module.globalAudioWatchCallback(arg)
    logger.d('Received global event typed `' .. arg .. '`.')

    if arg == 'dev#' then
        -- A new device has been added or removed.
        logger.d('Resetting audio state for all devices.')
        setAudioInput(module.isMuted)
        logger.d('Resetting audio watcher for all devices.')
        setAudioWatch()
    end
end

function module.toggleAudioInput()
    module.isMuted = not module.isMuted
    setAudioInput(module.isMuted)
    module.toggleMutedMenubar()
end

function module.toggleMutedMenubar()
    if module.isMuted then
        if module.__menubar ~= nil then return end
        module.__menubar = hs.menubar.new():setIcon('icons/audio-mute-on.pdf')
                               :setTitle('muted')
                               :setTooltip('Audio Inputs Are Muted'):setMenu({
                {title = 'Audio Inputs Are Muted', disabled = true},
                {title = '-'},
                {title = 'Unmute Input Devices', fn = module.toggleAudioInput}
            })
    else
        if module.__menubar == nil then return end
        module.__menubar:delete()
        module.__menubar = nil
    end
end

hs.audiodevice.watcher.setCallback(module.globalAudioWatchCallback)
if not hs.audiodevice.watcher.isRunning() then hs.audiodevice.watcher.start() end

local function start()
    -- At startup, we use the `muted` state of the default device as truth.
    local device = hs.audiodevice.defaultInputDevice()
    if device == nil then return end
    local isMuted = device:inputMuted()
    if isMuted == nil then return end

    -- Start the watcher on all connected devices.
    setAudioWatch()

    -- We set the local state to the opposite of `isMuted`,
    -- then we toggle the audio input so that we initialize it
    -- on all devices and we keep things consistent.
    module.isMuted = not isMuted
    module.toggleAudioInput()
end
start()

return module
