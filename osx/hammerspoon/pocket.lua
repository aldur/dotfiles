local logger = hs.logger.new('pocket')
local secrets = require('secrets')

local pocket_consumer_key = secrets.POCKET_CONSUMER_KEY
local pocket_access_token = secrets.POCKET_ACCESS_TOKEN

local function topocket(url)
    if not url then url = hs.pasteboard.getContents() end
    assert(url)

    if not (string.match(url, "www") or
        string.match(url, "http://") or
        string.match(url, "https://"))
        then logger.e("Invalid url: " .. url .. "."); return end

    hs.http.asyncPost(
        'https://getpocket.com/v3/add',
        hs.json.encode({
                url=hs.http.encodeForQuery(url),
                consumer_key=pocket_consumer_key,
                access_token=pocket_access_token
            }),
        {['Content-Type']="application/json; charset=UTF-8"},
        function(status, _, _)
            if not status or status ~= 200 then
                logger.e("Error (" .. status .. ") while adding url (" .. url .. ") to Pocket.")
            else
                hs.notify.new({title="Hammerspoon", informativeText=url .. " added to Pocket",
                    autoWithdraw=true}):send()
            end

            hs.window.frontmostWindow():focus()  -- Always focus frontmost window before returning
        end
    )
end

hs.urlevent.bind('pocket', function(_, _) topocket(nil) end)
