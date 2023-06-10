require "Lib/utils"
local JSON = require 'Lib/JSON'
local url = require("socket.url")

local queue_item_utils = {}
-- This function has two functions:
--  - As its name implies, take a possibly incompletely-specified request options list and fill in the defaults, in order that queueing it multiple places, in different formats, will only make it happen once
--  - Fill out those defaults in such a way as to bypass Wget's own duplicate-request checking, so that this framework can do it itself
-- This function is idempotent.
--
-- This doesn't do the same for headers, though; it sets some defaults under particular circumstances, but if you have, say, a specified UA header that's the same as specified on the command line, that queue item will be seen as different from the one without, even though the requests they produce are (minus timing etc.) identical
queue_item_utils.fill_in_defaults = function(options)
	local options = deep_copy(options)
	
	assert(options.url ~= nil, "Options must have an URL")
	assert(options.post_data == nil, "Use method=\"POST\" and body_data instead of post_data")
	
	local function default_option_to(k, v)
		options[k] = options[k] or v
	end
	
	
	default_option_to("method", "GET")
	default_option_to("headers", {})
	default_option_to("link_expect_html", 1)
	default_option_to("link_expect_css", 0)
	default_option_to("prior_delay", 0)
	
	-- Wget will not do its own duplicate checking if you have body data
	-- So if the user hasn't specified any, set it to an empty string, then remove the headers that normally come alongside it
	if options.body_data == nil then
		options.body_data = ""
		-- Setting headers here, not raw options
		options.headers["Content-Type"] = options.headers["Content-Type"] or ""
		options.headers["Content-Length"] = options.headers["Content-Length"] or ""
	end
	
	return options
end


-- Does the inverse of fill_in_defaults, or possibly more if the user specified fields to the defaults themselves, or possibly less if headers are filled in.
-- In any case to reinflate use run through fill_in_defaults.
-- Idempotent
queue_item_utils.remove_defaults_for_space_saving = function(options)
	local options = deep_copy(options)
	
	local function remove_if_equiv(k, v)
		if deep_compare(options[k], v) then
			options[k] = nil
		end
	end
	
	remove_if_equiv("method", "GET")
	remove_if_equiv("link_expect_html", 1)
	remove_if_equiv("link_expect_css", 0)
	remove_if_equiv("prior_delay", 0)
	
	-- Absence of all 3 of these is equiv to these defaults
	if options.body_data == "" and options.headers and options.headers["Content-Length"] == "" and options.headers["Content-Type"] == "" then
		options.body_data = nil
		options.headers["Content-Length"] = nil
		options.headers["Content-Type"] = nil
	end
	
	remove_if_equiv("headers", {})
	return options
end


-- Returns a canonicalized string representation of the given request options.
queue_item_utils.serialize_request_options = function(options)
	-- The JSON library currently in use alphabetizes and orders keys before encoding
	-- So that makes it fine to use as a dedup key
	return url.escape(JSON:encode(queue_item_utils.remove_defaults_for_space_saving(queue_item_utils.fill_in_defaults(options))))
end

-- Inverse of serialize_request_options.
queue_item_utils.deserialize_request_options = function(serialized)
	return queue_item_utils.fill_in_defaults(JSON:decode(url.unescape(serialized)))
end

return queue_item_utils
