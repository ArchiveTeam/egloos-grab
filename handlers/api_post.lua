local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())["post"]
    if json["comment_count"] ~= "0" then
        local domain, post_num = current_options.url:match('^https://api%.egloos%.com/(.+)/post/(%d+)%.json')
        -- TODO should we figure out comments/page and never get that last, erroring request? Or always get the first page regardless of # listed here?
        queue_request({url="https://api.egloos.com/" .. domain .. "/post/" .. post_num .. "/comment.json?page=1"}, "api_comments", true)
    end
    process_html(json["post_content"])
end

module.take_subsequent_actions = egloos_api_tsa

return module