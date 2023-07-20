local JSON = require("Lib/JSON")
local retry_common = require("Lib/retry_common")

local module = {}

module.get_urls = function(file, url, is_css, iri)
    local json = JSON:decode(get_body())
    -- If this error is sent, at a page with no more comments; this grab script will only encounterer it if the last valid page has >50 comments (relatively rare)
    if json["error"] and json["error"]["category"] == "system" and json["error"]["message"]:match"[OMGClient::selectQuery][(DBGateException) DBGateContext::decodeHeader, invalid response, opcode 200, recv opcode 0, body -100%\t#(MysqlException) mysql_real_query, 1064 You have an error in your SQL syntax; check the manual that corresponds to your MySQL server version for the right syntax to use near '-97' at line 1]" then
        return
    end

    for _, comment in pairs(json["comment"]) do
        if comment["comment_writer"] ~= nil then
            queue_request({url="https://api.egloos.com/v3/blog/" .. comment["comment_writer"] .. ".json"}, "api_user", true)
            process_url(comment["comment_writer_url"])
        end
        queue_request({url=comment["comment_writer_thumbnail"]}, "resources", true)
        process_html(comment["comment_content"])
    end

    -- Apparently comments are 100/page; this is the same logic as the independent grab
    if #json["comment"] > 50 then
        local newurl = current_options.url:gsub("(%d+)$", function(num) tostring(tonumber(num) + 1) end)
        local account, post, page = current_options.url:match('^https?://api%.egloos%.com/(.+)/post/(%d+)/comment%.json%?page=(%d+)$')
        local newpage = tostring(tonumber(page) + 1)
        newurl = "https://api.egloos.com/" .. account .. "/post/" .. post .. "/comment.json?page=" .. newpage
        queue_request({url=newurl}, current_handler, false)
    end
end

module.take_subsequent_actions = egloos_api_tsa

return module
