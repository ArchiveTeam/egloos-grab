local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

-- URLs like https://api.egloos.com/v3/blog/areaz.json

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())
    assert(not json["blog_cover"]) -- Not sure what these are
    if json["logo"] then
        queue_request({url=json["logo"]}, "resources", true)
    end
    -- Start listing posts
    local domain = current_options.url:match("^https://api%.egloos%.com/v3/blog/(.+)%.json$")
    queue_request({url="https://api.egloos.com/" .. domain .. "/post.json?page=1"}, "api_post_list", false)
end

-- TODO take_subsequent_actions need info on the rate limiting mechanism - also on other API handlers
-- Also need to have real 404s saved, but get_urls cancelled
module.take_subsequent_actions = retry_common.status_code_subsequent_actions(5, {200})

return module