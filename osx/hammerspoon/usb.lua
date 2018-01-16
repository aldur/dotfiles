-- USB related callbacks.

local function usbDeviceCallback(data)
    if data["productID"] == 49944 and data["vendorID"] == 1133 then
        if (data["eventType"] == "added") then
            hs.keycodes.setLayout('Keyboard Illuminated IT')
        elseif (data["eventType"] == "removed") then
            hs.keycodes.setLayout('Italian')
        end
    end
end
globals.watcher.usb = hs.usb.watcher.new(usbDeviceCallback):start()
