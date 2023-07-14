--require "strict"
local backfeed = require "Framework/backfeed"

local module = {}

local queue_request_prev = queue_request
queue_request = function(options_table, handler, backfeed)
    if options_table["url"] ~= "http://md.egloos.net/skin/img/common/ico_paging_prev.gif"
            and options_table["url"] ~= "http://md.egloos.net/skin/img/common/ico_paging_next.gif"
            and handler ~= "most" then
        queue_request_prev(options_table, handler, backfeed)

        -- Extract the underlying images from thumbnails
        local thumb_orig = options_table["url"]:match("^https?://thumbnail%.egloos%.net/[^/]+/(https?://.+)")
        if thumb_orig then
            queue_request({url=thumb_orig}, "resources", true)
        end
    end
end


process_url = function(url)
    local domain = url:match("^https?://([a-zA-Z0-9%-_]+)%.egloos%.com")
    if domain == "thumbnail"
            or url:match("^https?://thumbnail%.egloos%.net") -- .net instead of .com
            or domain == "profile"
            or domain == "rss"
            or (domain and domain:match("^pds%d+$")) then -- Resources
        queue_request({url=url}, "resources", true)
    elseif domain then -- Other page on site
        if domain ~= "statweb"
                and domain ~= "help"
                and domain ~= "sec"
                and domain ~= "valley"
                and domain ~= "www" then
            queue_request({url="https://api.egloos.com/v3/blog/" .. domain .. ".json"}, "api_user", true)
        end
    else
        backfeed.queue_external_url_for_upload(url)
    end
end

-- Copy+paste of arkiver's regular get_urls stuff (specifically from banciyuan)
-- decode_codepoint calls removed
local extract_links_from_html = function(html, current_url, callback)
	local urlparse = require("socket.url")
	local url = current_url


    local function check(newurl)
        --newurl = fix_case(newurl)
        local origurl = url
        if string.len(url) == 0 then
            return nil
        end
        local url = string.match(newurl, "^([^#]+)")
        local url_ = string.match(url, "^(.-)[%.\\]*$")
        while string.find(url_, "&amp;") do
            url_ = string.gsub(url_, "&amp;", "&")
        end
        callback(url_)
    end

    local function checknewurl(newurl)
        if string.match(newurl, "['\"><]") then
            return nil
        end
        if string.match(newurl, "^https?:////") then
            check(string.gsub(newurl, ":////", "://"))
        elseif string.match(newurl, "^https?://") then
            check(newurl)
        elseif string.match(newurl, "^https?:\\/\\?/") then
            check(string.gsub(newurl, "\\", ""))
        elseif string.match(newurl, "^\\/\\/") then
            checknewurl(string.gsub(newurl, "\\", ""))
        elseif string.match(newurl, "^//") then
            check(urlparse.absolute(url, newurl))
        elseif string.match(newurl, "^\\/") then
            checknewurl(string.gsub(newurl, "\\", ""))
        elseif string.match(newurl, "^/") then
            check(urlparse.absolute(url, newurl))
        elseif string.match(newurl, "^%.%./") then
            if string.match(url, "^https?://[^/]+/[^/]+/") then
                check(urlparse.absolute(url, newurl))
            else
                checknewurl(string.match(newurl, "^%.%.(/.+)$"))
            end
        elseif string.match(newurl, "^%./") then
            check(urlparse.absolute(url, newurl))
        end
    end

    local function checknewshorturl(newurl)
        if string.match(newurl, "^%?") then
            check(urlparse.absolute(url, newurl))
        elseif not (
                string.match(newurl, "^https?:\\?/\\?//?/?")
                        or string.match(newurl, "^[/\\]")
                        or string.match(newurl, "^%./")
                        or string.match(newurl, "^[jJ]ava[sS]cript:")
                        or string.match(newurl, "^[mM]ail[tT]o:")
                        or string.match(newurl, "^vine:")
                        or string.match(newurl, "^android%-app:")
                        or string.match(newurl, "^ios%-app:")
                        or string.match(newurl, "^data:")
                        or string.match(newurl, "^irc:")
                        or string.match(newurl, "^%${")
        ) then
            check(urlparse.absolute(url, newurl))
        end
    end

    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
        checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
        checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
        checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
        checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
        checknewurl(newurl)
    end
    html = string.gsub(html, "&gt;", ">")
    html = string.gsub(html, "&lt;", "<")
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
        checknewurl(newurl)
    end
end

-- Look through a string of HTML, extract the links it contains, send them where they need to go.
process_html = function(html)
    extract_links_from_html(html, current_options.url, process_url)
end

return module
