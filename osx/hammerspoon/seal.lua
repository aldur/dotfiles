local obj = {}
obj.__index = obj
obj.__logger = hs.logger.new('seal')

obj.chooser = nil
obj.hotkeyShow = nil
obj.lastFocused = nil
obj.plugins = {}
obj.commands = {}

function obj:init(plugins)
    obj.__logger.v("Initialising Seal...")
    self.chooser = hs.chooser.new(self.completionCallback)
    self.chooser:choices(self.choicesCallback)
    self.chooser:queryChangedCallback(self.queryChangedCallback)

    for _, plugin_name in pairs(plugins) do
        obj.__logger.v("Loading Seal plugin: '" .. plugin_name .. "'.")
        local plugin = require("seal_" .. plugin_name)
        table.insert(obj.plugins, plugin)
        for cmd, cmd_info in pairs(plugin:commands()) do
            obj.__logger.v("Adding command: '" .. cmd .. "'.")
            obj.commands[cmd] = cmd_info
        end
    end
    return self
end

function obj:start(modifiers, hotkey)
    obj.__logger.v("Starting Seal.")
    if hotkey then
        self.hotkeyShow = hs.hotkey.bind(modifiers, hotkey, function() obj:toggle() end)
    end
    return self
end

function obj:stop()
    obj.__logger.v("Stopping Seal.")
    self.chooser:hide()
    if self.hotkeyShow then self.hotkeyShow:disable() end
    return self
end

function obj:show()
    self.lastFocused = hs.window.focusedWindow()
    self.chooser:show()
    return self
end

function obj:toggle()
    if self.chooser:isVisible() then
        self.chooser:hide()
        if self.lastFocused then self.lastFocused:focus() end
        return self
    end

    return self:show()
end

function obj.completionCallback(row_info)
    if row_info == nil then
        if obj.lastFocused then obj.lastFocused:focus() end
        return
    end

    if row_info["type"] == "plugin_cmd" then
        obj.chooser:query(row_info["cmd"])
        return
    end

    for _, plugin in pairs(obj.plugins) do
        if plugin.__name == row_info["plugin"] then
            plugin.completionCallback(row_info)
            if obj.lastFocused then obj.lastFocused:focus() end
            break
        end
    end
end

function obj.choicesCallback()
    -- TODO: Sort each of these clusters of choices, alphabetically
    local choices = {}
    local query = obj.chooser:query()
    local cmd = nil
    local query_words = {}

    for word in string.gmatch(query, "%S+") do
        if cmd == nil then
            cmd = word
        else
            table.insert(query_words, word)
        end
    end
    query_words = table.concat(query_words, " ")

    if cmd then
        -- First get any direct command matches
        for command, cmd_info in pairs(obj.commands) do
            local cmd_fn = cmd_info["fn"]
            if cmd:lower() == command:lower() then
                if (query_words or "") == "" then query_words = ".*" end

                local fn_choices = cmd_fn(query_words)
                if fn_choices ~= nil then
                    for _, choice in pairs(fn_choices) do
                        table.insert(choices, choice)
                    end
                end
            end
        end
    end

    -- Now get any bare matches
    for _, plugin in pairs(obj.plugins) do
        local bare = plugin:bare()
        if bare then
            for _, choice in pairs(bare(query)) do
                table.insert(choices, choice)
            end
        end
    end

    -- Now add in any matching commands
    for command, cmd_info in pairs(obj.commands) do
        if string.match(command, query) and #query_words == 0 then
            local choice = {
                text=cmd_info['name'],
                subText=cmd_info['description'],
                type='plugin_cmd',
                image=cmd_info['icon']
            }
            table.insert(choices, choice)
        end
    end

    return choices
end

function obj.queryChangedCallback(_)
    obj.chooser:refreshChoicesCallback()
end

return obj
