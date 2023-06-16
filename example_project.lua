--require "strict"

local module = {}

local queue_request_prev = queue_request
queue_request = function(options_table, handler, backfeed)
	if options_table["url"] ~= "http://md.egloos.net/skin/img/common/ico_paging_prev.gif"
		and options_table["url"] ~= "http://md.egloos.net/skin/img/common/ico_paging_next.gif"
		and handler ~= "most" then
		queue_request_prev(options_table, handler, backfeed)
	end
end


return module
