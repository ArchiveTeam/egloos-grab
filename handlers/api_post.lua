local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())["post"]
    if json["comment_count"] ~= "0" then
        -- TODO should we figure out comments/page and never get that last, erroring request? Or always get the first page regardless of # listed here?
        queue_request("https://api%.egloos%.com/" .. domain .. "/post/" .. post_num .. "/comment.json?page=1", "api_comments", true)
    end
    process_html(json["post_content"])
end

-- TODO take_subsequent_actions need info on the rate limiting mechanism - also on other API handlers
-- Also need to have real 404s saved, but get_urls cancelled out
module.take_subsequent_actions = retry_common.status_code_subsequent_actions(5, {200})

return module