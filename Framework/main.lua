local Deque = require 'Lib/deque'
local JSON = require 'Lib/JSON'
local ansicolors = require 'Lib/ansicolors'
local urlparse = require("socket.url") -- In the system
local queue_item_utils = require "Framework/queue_item"
local backfeed_l = require "Framework/backfeed"
local socket = require "socket"
require "Lib/strict"
require "Lib/table_show"
require "Lib/utils"

io.stdout:setvbuf("no") -- So prints are not buffered - http://lua.2524044.n2.nabble.com/print-stdout-and-flush-td6406981.html

-- Should it fail if URLs that come out of the queue are not exactly the same as URLs that went into the queue? Due to wget's normalization, this is only useful under testing or other strict conditions.
STRICT_URL_CHECK = false
-- Should it normalize the URLs slightly (see inside urls_are_equivalent_under_possible_effective_normalization) under certain conditions and then check?
APPROXIMATE_URL_CHECK = true

-- Dummy URL for the first "request"
START_URL = "http://archiveteam.invalid/start"
-- Default URL to have at the end of the list so that it can queue extra stuff
END_URL = "http://archiveteam.invalid/end"
-- Prefixes integers when it goes past the end due to not being able to queue everything
ADDITIONAL_END_URL_BASE = "http://archiveteam.invalid/end_additional/"

-- Whether to skip on backfeed
do_debug = false

-- -- Functions in the project script:
-- Global begin/end stuff, also lookup_host (maybe pass it the item name as well?)
-- callbacks for:
-- write_to_warc
-- dcp
-- httploop_result
-- get_urls

local DEBUG = {level=-1}
local INFO = {level=0}
local WARNING = {level=1}
local ERROR = {level=2}

LOG_LEVEL = WARNING

local print_cbsd = function(s, level)
	if not level then
		level = DEBUG
	end
	if level.level >= LOG_LEVEL.level then
		local color_string = nil
		if level == DEBUG then
			color_string = "dim"
		elseif level == INFO then
			color_string = "blue"
		elseif level == WARNING then
			color_string = "yellow"
		elseif level == ERROR then
			color_string = "red"
		end
		print(ansicolors("%{" .. color_string .. "}" .. s))
	end
end

-- This contains entries in the form {url=url, callbacks={callbacks}}. Should mirror wget's queue. The current request is dequeued from the left, and new ones are added to the right.
local expected_urls = Deque:new()
expected_urls:push_right({url=START_URL, handler={}})

local url_count = 0

local finished_and_expect_no_more_urls = false

-- Global so that project can access it
current_handler = nil
current_options = nil

local queued_requests = {}

local current_file_name = nil
local current_loaded_body = nil


local new_request_called_since_last_httploop_result = false

local queued_requests_not_yet_queued_to_wget = {}

local additional_end_url_cur_count = 0

-- Records the output of take_subsequent_actions for each request
-- See that function for details
local do_take_subsequent_actions = nil



-- Looks up a handler by a string name.
local find_handler_by_name = function(name)
	-- Disabled as it doesn't like a cycle of references
	--[[if general_project_script.find_handler ~= nil then
		local v = general_project_script.find_handler(name)
		if v ~= nil then
			return v
		end
	end]]
	-- Either the general script's finder didn't exist, or it retuned nil
	-- So now go find it on the disk - this will crash if one does not exist
	return (require("handlers/" .. name))
end


-- "Inner" so that I can keep referring directly to it even if project code wraps queue_request in something
local queue_request_inner = function(options_table, handler, backfeed)
	print_cbsd("Trying to queue the following: " .. table.show(options_table), DEBUG)
	options_table = queue_item_utils.fill_in_defaults(options_table)
	assert(not options_table.post_data, "Use method=\"POST\" and the body_data option instead of post_data")
	assert(handler, "If you want a handler that does nothing, use an empty table instead of nil")
	
	assert(string.match(options_table["url"], "^https?://.+/"))
	
	local no_fragment = string.match(options_table["url"], "^[^#]+")
	assert(no_fragment)
	if no_fragment ~= options_table["url"] then
		print_cbsd("Eliminating fragment as to replace " .. options_table["url"] .. " with " .. no_fragment, INFO)
		options_table["url"] = no_fragment
	end
	
	local escaped = minimal_escape(options_table["url"])
	if options_table["url"] ~= escaped then
		print_cbsd("Escaping URL as to replace " .. options_table["url"] .. " with " .. escaped, INFO)
		options_table["url"] = escaped
	end
	
	-- Putting dedup here so that there are not needless dummy-URL cycles
	local canocialized = queue_item_utils.serialize_request_options(options_table)
	if queued_requests[canocialized] then
		print_cbsd("Dropping " .. canocialized .. " because it has already been seen")
	else
		if not backfeed then
			if type(handler) == "string" then
				handler = find_handler_by_name(handler)
			end
			table.insert(queued_requests_not_yet_queued_to_wget, {handler=handler, options=options_table})
		else
			assert(type(handler) == "string", "For backfeed handler must be a handler name, not the table")
			backfeed_l.queue_request_for_upload(handler, canocialized)
		end
		queued_requests[canocialized] = true
	end
end



queue_request = function(options_table, handler, backfeed)
	queue_request_inner(options_table, handler, backfeed)
end
local general_project_script = require 'example_project'



-- Ultimately this comes down to "if (url->port != scheme_port)" in url.c, url_string(). Removed port numbers on redirects when they are the default ports for the scheme.
local urls_are_equivalent_under_possible_effective_normalization = function(a, b)
	local normalize = function(url)
		local p = urlparse.parse(url)
		local portless_authority = p.authority:gsub("(:[0-9]+)", "")
		return p.scheme .. "://" .. portless_authority .. "/" .. p.path .. (p.params or "") .. ";".. (p.query or "") .. "#" .. (p.fragment or "") -- Leaving out the other fields even though wget dropping them is not yet a problem
	end
	return normalize(a) == normalize(b)
end


-- I have found that I frequently end up either copying and pasting "is a good response?" code between
--  write_to_warc and httploop_result, or saving the result to a variable per handler.
-- This makes this cleaner by having one function that decides whether the handler's write_to_warc,
--  httploop_result, get_urls, and download_child_ps run at all.
-- If the output of the handler's version of this is true, they run (but it doesn't override negative results, so
--  e.g. WTW is still able to return a false).
-- If the output of the user is false, they do not run at all, the response is not written to WARC, and download_child_p will always
--  return false for that request. As in previous versions of this framework, you still need to manually queue retries
--  with queue_request.
local take_subsequent_actions = function(url, http_stat)
	if current_handler.take_subsequent_actions ~= nil then
		do_take_subsequent_actions = current_handler.take_subsequent_actions(url, http_stat)
		assert(do_take_subsequent_actions == true or do_take_subsequent_actions == false)
	else
		do_take_subsequent_actions = true
	end
end


-- This function is called as early as possible, every time a new request begins to be made/the script is informed of it.
-- It is run from write_to_warc, but that isn't called in some cases (e.g. where DNS resolution fails) so httploop_result may call it as well, checking that it hasn't run already with the value of new_request_called_since_last_httploop_result.
-- url is an url structure, not the actual url

local prev_url = nil
local consecutive_retry_count = 0
local new_request = function(url, http_stat)
	print_cbsd("Doing new request on " .. url["url"], DEBUG)
	local this_url = url["url"]
	
	-- Bypass the use of this framework for requests with identical URLs
	-- This is because the targeted for this project is repeatedly giving HTTP errors of an undetermined nature, which caues WGET to retry the request, and messes up the queue since
	-- So try to detect this case and allow it - look for repeats of URLs where they should not be repeating
	-- This will still fail occasionally when an URL is retried, while it is also the next in the
	--  queue (i.e. you have a sandwhich of framework request, wget retry, framework request)
	if this_url == prev_url and (expected_urls:is_empty() or expected_urls:peek_left().url ~= this_url) then
		new_request_called_since_last_httploop_result = true
		consecutive_retry_count = consecutive_retry_count + 1
		if consecutive_retry_count > 15 then
			error("Too many retries")
		end
		return
	else
		prev_url = this_url
		consecutive_retry_count = 0
	end
	
	-- Putting this here
	if collectgarbage("count") > 1024 * 100 then
		print("Warning: the Lua VM is using " .. tostring(collectgarbage("count")) .. "KB of memory")
	end
	
	assert (not finished_and_expect_no_more_urls)
	
	current_loaded_body = nil
	
	if expected_urls:is_empty() then
		-- Check we are where we expect
		if additional_end_url_cur_count == 0 then
			assert(this_url == END_URL)
		else
			assert(this_url == ADDITIONAL_END_URL_BASE .. tostring(additional_end_url_cur_count))
		end
		assert(http_stat["statcode"] == 0)
	
		-- Any more URLs to queue? Then start another cycle with a new end; else prepare to exit
		if next(queued_requests_not_yet_queued_to_wget) ~= nil then
			-- This relies on the fact that wget calls get_urls on URLs that don't resolve
			-- So it assumes that the queued will be queued this dummy URL; and all it does is add on another dummy URL to the end so that this process can repeat if so necessary
			additional_end_url_cur_count = additional_end_url_cur_count + 1
			queue_request_inner({url=ADDITIONAL_END_URL_BASE .. tostring(additional_end_url_cur_count)}, {}) -- Empty list as handler will resolve to nil on each of the functions
		else
			print_cbsd("Finished, expect no more URLs", INFO)
			finished_and_expect_no_more_urls = true
			backfeed_l.upload()
		end
		
		-- If it's a normal end URL, need to tell it to use an empty handler; as addition end URLs are added within the script rather than from the wget args, this does not need to be done for them
		if this_url == END_URL then
			current_handler = {}
		end
	else
		-- Normal new URL, no new item
		local this_req = expected_urls:pop_left()
		print_cbsd("From WTW pop left " .. this_req.url, DEBUG)
		if STRICT_URL_CHECK then
			assert (this_req.url == url["url"], this_req.url .. " != " .. url["url"]) -- This may be triggered if you do not pass -e robots.off
		end
		if APPROXIMATE_URL_CHECK then
			assert (urls_are_equivalent_under_possible_effective_normalization(this_req.url, url["url"]), this_req.url .. " != " .. url["url"]) -- If this is triggered see the comment on the previous block
		end
		current_handler = this_req.handler
		current_options = this_req.options
		
		take_subsequent_actions(url, http_stat)
	end
	new_request_called_since_last_httploop_result = true
end


-- Before a request starts being sent Currently just applies the delay, if there is one, for the next one.
local before_request = function()
	local next_req = expected_urls:peek_left()
	if not next_req then
		return
	end
	
	local max = function(a, b)
		if a > b then
			return a
		else
			return b
		end
	end
	
	local delay = 0
	if next_req.options.delay_until then
		delay = max(delay, next_req.options.delay_until - socket.gettime())
	end
	if next_req.options.prior_delay then
		delay = max(delay, next_req.options.prior_delay)
	end
	
	if delay > 0 then
		print_cbsd("Delaying " .. tostring(delay), WARNING)
		os.execute("sleep " .. delay)
	end
end




wget.callbacks.write_to_warc = function(url, http_stat)
	new_request(url, http_stat)
	if do_take_subsequent_actions == false then
		return false
	elseif current_handler.write_to_warc ~= nil then
		return current_handler.write_to_warc(url, http_stat)
	else
		return true
	end
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
	assert(finished_and_expect_no_more_urls)
	assert(expected_urls:is_empty())
	if general_project_script.finish then
		general_project_script.finish(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
	end
	
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
	if general_project_script.before_exit then
		return general_project_script.before_exit(exit_status, exit_status_string)
	else
		return exit_status
	end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
	local ret = nil
	-- Either return a handler object (queue) or false/nil (don't, though you may call queue_request within the handler if you want)
	print_cbsd("DCP on " .. urlpos["url"]["url"] .. " from " .. parent["url"], DEBUG)
	if current_handler.download_child_p ~= nil and do_take_subsequent_actions then
		ret = current_handler.download_child_p(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
		assert (ret == nil, "You should use queue_request() instead of returning from download_child_p()")
	end
	return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
	if current_handler.get_urls ~= nil and do_take_subsequent_actions then
		current_file_name = file
		local res = current_handler.get_urls(file, url, is_css, iri)
		current_file_name = nil
		assert (res == nil, "You should use queue_request() instead of returning from get_urls()")
	end
	local to_queue = {}
	for i = #queued_requests_not_yet_queued_to_wget, 1, -1 do
		local inserting = queued_requests_not_yet_queued_to_wget[i]
		assert(inserting)
		
		expected_urls:push_right({url=inserting.options["url"], handler=inserting.handler, options=inserting.options})
		print_cbsd("Inserting " .. inserting.options["url"], DEBUG)
		table.insert(to_queue, 1, inserting.options) -- Insert at the beginning, as the first item in the returned list from this function, is the one that gets run last
	end
	queued_requests_not_yet_queued_to_wget = {}
	before_request() -- Before the next one
	return to_queue
end



wget.callbacks.httploop_result = function(url, err, http_stat)
	
	-- On urls that give status_code 0 (e.g. nonresolving domain), write_to_warc doesn't get called
	-- So put this here as well
	if not new_request_called_since_last_httploop_result then
		new_request(url, http_stat)
	end
	new_request_called_since_last_httploop_result = false
	
	local status_code = http_stat["statcode"]

	url_count = url_count + 1
	io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
	io.stdout:flush()


	-- TODO is do_take_subsequent_actions really necessary here? Should see in practice. Normally HLS doesn't really... do much, since the framework gets rid of the normal retry mechanism
	if current_handler.httploop_result ~= nil and do_take_subsequent_actions then
		local ret = current_handler.httploop_result(url, err, http_stat)
		assert (ret == nil, "You should use queue_request() instead of returning from download_child_p()")
	end

	-- If you return EXIT uniformly DCP will never be called
	-- TODO see about the additional weirdness with this - like is get_urls called on redirects?
	if (status_code >= 300 and status_code <= 399) or status_code == 0 then
		return wget.actions.EXIT
	else
		return wget.actions.NOTHING
	end
end


wget.callbacks.lookup_host = function(host)
	if general_project_script.lookup_host then
		return general_project_script.lookup_host(host)
	else
		return nil
	end
end


-------


get_body = function()
	assert(current_file_name, "get_body should only be called from a get_urls handler")
	if current_loaded_body == nil then
		-- Taken from read_file() in the copypasta framework
		local f = assert(io.open(current_file_name))
		current_loaded_body = f:read("*all")
		f:close()
	end
	return current_loaded_body
end



local queue_initial_reqs = function()
	for _, v in pairs(JSON:decode(os.getenv("initial_requests"))) do
		-- TODO have a project-specific function that can scrutinize these and e.g. change them if it wants to increase their version?
		queue_request(queue_item_utils.deserialize_request_options(v[2]), v[1])
	end
end


queue_initial_reqs()
