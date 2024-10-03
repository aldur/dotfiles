local logger = hs.logger.new('mic')
logger.level = 3

local module = {}

module.__isMutedMenubar = nil
module.__isForcingBuiltInInputMenubar = nil

-- This is the single source of truth for this module.
-- If this is set to true, then all input devices MUST be muted.
module.isMuted = false
module.isForcingBuiltInInput = false
module.previousBuiltInInput = nil

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

function module.forceBuiltInInput()
    -- FIXME: This won't work on a Mac (standalone, non MacBook)
    local builtInMicName = "MacBook Pro Microphone"
    local defaultMicName = hs.audiodevice.defaultInputDevice():name()
    if defaultMicName ~= builtInMicName then
        logger.d('Setting built-in mic as default input device.')
        module.previousBuiltInInput = defaultMicName
        local builtInMic = hs.audiodevice.findInputByName(builtInMicName)
        assert(builtInMic:setDefaultInputDevice())
    end
end

function module.restorePreviousInput()
    if not module.previousBuiltInInput then return end
    local mic = hs.audiodevice.findInputByName(module.previousBuiltInInput)
    assert(mic)
    assert(mic:setDefaultInputDevice())
end

-- Global audio device watcher. Triggered when a device gets added or removed.
function module.globalAudioWatchCallback(arg)
    logger.d('Received global event typed `' .. arg .. '`.')

    -- NOTE: The space after `dIn ` is not a typo
    if module.isForcingBuiltInInput and arg == "dIn " then
        module.forceBuiltInInput()
    end

    if arg == 'dev#' then
        -- A new device has been added or removed.
        logger.d('Resetting audio state for all devices.')
        setAudioInput(module.isMuted)
        logger.d('Resetting audio watcher for all devices.')
        setAudioWatch()
    end
end

function module.toggleInputMute()
    module.isMuted = not module.isMuted
    setAudioInput(module.isMuted)
    module.toggleMutedMenubar()
end

function module.toggleMutedMenubar()
    if module.isMuted then
        if module.__isMutedMenubar ~= nil then return end
        module.__isMutedMenubar = hs.menubar.new():setIcon(
                                      'icons/audio-mute-on.pdf')
                                      :setTitle('muted'):setTooltip(
                                          'Audio inputs are muted'):setMenu({
                {title = 'Audio inputs are muted', disabled = true},
                {title = '-'},
                {title = 'Unmute input devices', fn = module.toggleInputMute}
            })
    else
        if module.__isMutedMenubar == nil then return end
        module.__isMutedMenubar:delete()
        module.__isMutedMenubar = nil
    end
end

function module.toggleForceBuiltInInput()
    module.isForcingBuiltInInput = not module.isForcingBuiltInInput
    if module.isForcingBuiltInInput then
        module.forceBuiltInInput()
    else
        module.restorePreviousInput()
    end
    module.toggleForceBuiltInInputMenubar()
end

function module.toggleForceBuiltInInputMenubar()
    if module.isForcingBuiltInInput then
        if module.__isForcingBuiltInInputMenubar ~= nil then return end
        module.__isForcingBuiltInInputMenubar =
            hs.menubar.new():setIcon('icons/mic.pdf'):setTitle('built-in')
                :setTooltip('Forcing built-in audio input'):setMenu({
                    {title = 'Forcing built-in audio input', disabled = true},
                    {title = '-'},
                    {
                        title = 'Restore to default audio input',
                        fn = module.toggleForceBuiltInInput
                    }
                })
    else
        if module.__isForcingBuiltInInputMenubar == nil then return end
        module.__isForcingBuiltInInputMenubar:delete()
        module.__isForcingBuiltInInputMenubar = nil
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
    module.toggleInputMute()
end
start()

return module
