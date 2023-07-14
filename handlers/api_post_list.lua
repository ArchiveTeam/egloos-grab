local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())
    -- Nil signifies end of posts for a blog
    if json["post"] ~= nil then
        local domain = current_options.url:match("^https://api%.egloos%.com/(.+)/post%.json%?page=%d+$")
        for _, post in pairs(json["post"]) do
            queue_request({url="https://api.egloos.com/" .. domain .. "/post/" .. post["post_no"] .. ".json"}, "api_post", true)
            if post["post_thumb"] and post["post_thumb"] ~= "" then
                queue_request({url=post["post_thumb"]}, "resources", true)
            end
        end
    end
end

-- TODO take_subsequent_actions need info on the rate limiting mechanism - also on other API handlers
-- Also need to have real 404s saved, but get_urls cancelled out
module.take_subsequent_actions = retry_common.status_code_subsequent_actions(5, {200})

return module