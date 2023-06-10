-- Constructs an item name with a basic, unadorned GET request, good for being the root of a backfeed tree or for loading into the tracker.
-- First arg - item name
-- Second arg - URL
local qiu = require "Framework/queue_item"
print(arg[1] .. ":" .. qiu.serialize_request_options({url=arg[2], domain=arg[3]}))
