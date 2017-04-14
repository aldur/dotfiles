local logger = hs.logger.new('instapaper')
local secrets = require('secrets')

local instapaper_auth = hs.base64.encode(
    secrets.INSTAPAPER_USERNAME .. ":" .. secrets.INSTAPAPER_PASSWORD
)

local function toInstapaper(url)
    if not url then url = hs.pasteboard.getContents() end
    assert(url)

    if not (string.match(url, "www") or
        string.match(url, "http://") or
        string.match(url, "https://"))
        then logger.e("Invalid url: " .. url .. "."); return end

    hs.http.asyncPost(
        'https://www.instapaper.com/api/add',
        "url=" .. url, {Authorization="Basic " .. instapaper_auth},
        function(status, _, _)
            if not status or status ~= 201 then
                logger.e("Error (" .. status .. ") while adding url (" .. url .. ") to Instapaper.")
            else
                hs.notify.new({title="Hammerspoon", informativeText=url .. " added to Instapaper",
                    autoWithdraw=true}):send()
            end
            hs.window.frontmostWindow():focus()  -- Always focus frontmost window before returning
        end
    )
end

hs.urlevent.bind('instapaper', function(_, _) toInstapaper(nil) end)
