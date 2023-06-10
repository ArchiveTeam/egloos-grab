local nothing = require("handlers/nothing")
local module = {}

module.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	queue_request({url=urlpos["url"]["url"]}, nothing)
end

return module
