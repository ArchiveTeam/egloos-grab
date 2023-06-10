local retry_common = {}
local socket = require "socket"
local urlparse = require("socket.url")

retry_common.retry_unless_hit_iters = function(max, give_up_instead_of_crashing)
	local new_options = deep_copy(current_options)
	local cur_try = new_options["try"] or 1
	if cur_try > max then
		if not give_up_instead_of_crashing then
			error("Crashing due to too many retries")
		else
			print("Giving up due to too many retries...")
			return
		end
	end
	new_options["try"] = cur_try + 1
	new_options["delay_until"] = socket.gettime() + 2^(cur_try + 1)
	queue_request(new_options, current_handler)
end

retry_common.only_retry_handler = function(max, allowed_status_codes, do_not_follow_redirects)
	local handler = {}
	local allowed_sc_lookup = {}
	for _, v in pairs(allowed_status_codes) do
		allowed_sc_lookup[v] = true
	end
	handler.take_subsequent_actions = function(url, http_stat)
		-- Might this redirect handling better be handled by a wrapper handler that follows if it redirects and passes to the underlying if it doesn't?
		-- Nice idea but use of current_handler everywhere could cause issues
		-- This is actually an instance of a post-response "dispatcher" that as of yet defies the "model" this framework tries to approximate
		if allowed_sc_lookup[http_stat["statcode"]] then
			if http_stat["statcode"] >= 300 and http_stat["statcode"] <= 399 and not do_not_follow_redirects then
				local new_table = shallow_copy(current_options)
				new_table["url"] = urlparse.absolute(current_options["url"], http_stat["newloc"])
				queue_request(new_table, current_handler)
			end
			return true
		else
			retry_common.retry_unless_hit_iters(max)
			return false
		end
		
	end
	return handler
end

return retry_common
