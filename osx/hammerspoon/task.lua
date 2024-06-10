-- Experimental, poor man's background tasks based on `hs.timer.delayer`.
-- NOTE that tasks are supposed to be long-lived, so doing this repeatedly
-- will leak memory.
local module = {}

-- TODO: Figure out how NOT to leak this.
function module.spawn(f) hs.timer.delayed.new(0, f):start() end

return module
