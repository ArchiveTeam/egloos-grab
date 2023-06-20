local retry_common = require("Lib/retry_common")

local module = {}


module.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	queue_request({url=urlpos["url"]["url"]}, "resources", true)
end



module.take_subsequent_actions = function(url, http_stat)
	if http_stat["statcode"] == 200 or http_stat["statcode"] == 404 then
		return true
	else
		retry_common.retry_unless_hit_iters(4)
		return false
	end
	
end

return module
