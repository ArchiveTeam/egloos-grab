local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())
    -- If this error is sent, at a page with no more comments
    if not (json["error"] and json["category"] == "system" and json["message"] == "[OMGClient::selectQuery][(DBGateException) DBGateContext::decodeHeader, invalid response, opcode 200, recv opcode 0, body -100%\t#(MysqlException) mysql_real_query, 1064 You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '-97' at line 1]") then
        for _, comment in pairs(json["comments"]) do
            queue_request({url="https://api.egloos.com/v3/blog/" .. comment["comment_writer"] .. ".json"}, "comment_user", true)
            queue_request({url=comment["comment_writer_thumbnail"]}, "resources", true)
            process_html(comment["comment_content"])
            process_url(comment["comment_writer_url"])
        end

        queue_request({url=current_options.url:gsub("page=(%d+)$", function(num) tostring(tonumber(num) + 1) end)}, current_handler, false)
    end
end

module.take_subsequent_actions = egloos_api_tsa

return module