local retry_common = require("Lib/retry_common")

local module = {}


module.get_urls = function(file, url, is_css, iri)
	for photo in get_body():gmatch('<media:content url="(http:[^%s"]+)"') do
		queue_request({url=photo}, retry_common.only_retry_handler(5, {200, 404, 301, 302}))
	end
	for photo in get_body():gmatch('<media:thumbnail url="(http:[^%s"]+)"') do
		queue_request({url=photo}, retry_common.only_retry_handler(5, {200, 404, 301, 302}))
	end
end


module.take_subsequent_actions = function(url, http_stat)
	if http_stat["statcode"] == 200 then -- If this fails want to know, may require changing the way photos are found
		return true
	else
		retry_common.retry_unless_hit_iters(4)
		return false
	end
	
end

return module
