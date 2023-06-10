local retry_common = require("Lib/retry_common")

local module = {}


module.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	queue_request({url=urlpos["url"]["url"]}, retry_common.only_retry_handler(5, {200, 404, 301, 302}))
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
