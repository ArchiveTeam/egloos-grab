local retry_common = require("Lib/retry_common")
local backfeed = require "Framework/backfeed"
local urlparse = require("socket.url")

local module = {}

-- To prevent infinite calendars
local date_exists_and_is_too_extreme = function(url)
	local year = url:match("^https?://[^/%.].egloos%.com/archives/(%d%d%d%d)/%d+/%d+")
	if not year then
		return false
	else
		local year_int = tonumber(year)
		return year > 2026 or year < 1996 -- Some posts appear to slightly post-date reality, hence the safety margin
	end
end

local process_url = function(url)
	local domain = url:match("^https?://([a-zA-Z0-9%-_]+)%.egloos%.com")
	if domain == current_options["domain"] then
		if not url:match("/sns_share_frame%.php")
			and not date_exists_and_is_too_extreme(url) then
			queue_request({url=url, domain=domain}, "most")
		end
	elseif domain == "thumbnail"
		or url:match("^https?://thumbnail%.egloos%.net") -- .net instead of .com
		or domain == "profile"
		or domain == "rss"
		or (domain and domain:match("^pds%d+$")) then -- Resources
		queue_request({url=url}, retry_common.only_retry_handler(5, {200, 404, 301, 302}))
	elseif domain then -- Other page on site
		if domain ~= "statweb"
		and domain ~= "help"
		and domain ~= "seq"
		and domain ~= "valley"
		and domain ~= "www" then
			queue_request({url="http://" .. domain .. ".egloos.com/", domain=domain}, "most", true)
		end
	else
		backfeed.queue_external_url_for_upload(url)
	end
end

module.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	process_url(urlpos["url"]["url"])
end

module.get_urls = function(file, url, is_css, iri)
	-- Just do these once per domain
	queue_request({url="http://" .. current_options["domain"] .. ".egloos.com/photo/photo.xml"}, "photo_xml")
	queue_request({url="http://" .. current_options["domain"] .. ".egloos.com/archives"}, "photo_xml")
	
	-- Full images (thumbnails are successfully captured)
	for full_img in get_body():gmatch("Control%.Modal%.openDialog%(this, event, '(http:[^%s']+)'") do
		queue_request({url=full_img}, retry_common.only_retry_handler(5, {200, 404}))
	end
end

-- Retry on 429s, interpret everything else as final
module.take_subsequent_actions = function(url, http_stat)
	if http_stat["statcode"] >= 300 and http_stat["statcode"] <= 399 then
		process_url(urlparse.absolute(url["url"], http_stat["newloc"]))
	end
	
	if http_stat["statcode"] ~= 429 then
		return true
	else
		retry_common.retry_unless_hit_iters(4)
		return false
	end
	
end

return module
