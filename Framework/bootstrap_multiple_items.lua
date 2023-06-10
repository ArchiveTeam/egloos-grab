-- Constructs item names for basic, unadorned GET requests, good for loading into the tracker after outside discovery.
-- First arg - item name
-- On stdin: URLs
-- On stdout: item names
-- Does not dedup
local qiu = require "Framework/queue_item"
while true do
	local line = io.read()
	if not line then
		break
	end
	print(arg[1] .. ":" .. qiu.serialize_request_options({url=line}))
end
