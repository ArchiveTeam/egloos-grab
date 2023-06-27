
local module = {}

module.get_urls = function(file, url, is_css, iri)
	-- Thumbnails
	for url in get_body():gmatch("[\"'](https?://thumbnail%.egloos%.net.-pds.-)[\"']") do
		queue_request({url=url}, "resources", true)
	end
	
	for url in get_body():gmatch("[\"'](https?://pds%d+%.egloos%.com.-)[\"']") do
		queue_request({url=url}, "resources", true)
	end
end

module.take_subsequent_actions = function(url, http_stat)
	if http_stat["statcode"] == 200 then
		return true
	else
		retry_common.retry_unless_hit_iters(4)
		return false
	end
	
end

return module
 
