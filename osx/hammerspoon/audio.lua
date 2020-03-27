-- luacheck: globals hs
-- luacheck: globals globals

local logger = hs.logger.new('mic')

local module = {}
module.is_muted = false
module.__menubar = nil

function module.audiowatch(arg)
    -- TODO: if a new input device gets added, we might need to mute it as well.
    logger.df("Audiowatch arg: %s", arg)
end

function module.toggleAudioInput()
    module.is_muted = not module.is_muted
    for _, d in pairs(hs.audiodevice.allInputDevices()) do
        local name = d:name()
        if name == nil then name = '<nil>' end
        if module.is_muted then
            logger.d('Muting device ' .. name .. ' input.')
        else
            logger.d('Unmuting device ' .. name .. ' input.')
        end
        d:setInputMuted(module.is_muted)
    end
    module.toggleMutedMenubar()
end

function module.toggleMutedMenubar()
    if module.is_muted then
        if module.__menubar ~= nil then return end
        module.__menubar = hs.menubar.new():setIcon('icons/audio-mute-on.pdf'):setTitle('muted'):setTooltip(
            'Audio Inputs Are Muted'):setMenu({{title='Audio Inputs Are Muted', disabled=true},
            {title='-'}, {title='Unmute Input Devices', fn=module.toggleAudioInput}})
    else
        if module.__menubar == nil then return end
        module.__menubar:delete()
        module.__menubar = nil
    end
end

hs.audiodevice.watcher.setCallback(module.audiowatch)
hs.audiodevice.watcher.start()

local function start()
    local device = hs.audiodevice.defaultInputDevice()
    if device == nil then return end
    local is_muted = device:inputMuted()
    if is_muted == nil then return end

    -- We set the local state to the opposite of `is_muted`,
    -- then we toggle the audio input so that we initialize it
    -- on all devices and we keep things consistent.
    module.is_muted = not is_muted
    module.toggleAudioInput()
end
start()

return module
