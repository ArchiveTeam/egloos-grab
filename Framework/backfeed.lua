local http = require("socket.http")

local module = {}

local queue = {}
local external_urls_queue = {}

local send_binary = function(to_send, key)
  local tries = 0
  while tries < 10 do
    local body, code, headers, status = http.request(
            "https://legacy-api.arpa.li/backfeed/legacy/" .. key,
            to_send
    )
    if code == 200 or code == 409 then
      break
    end
    print("Failed to submit discovered URLs." .. tostring(code) .. " " .. tostring(body)) -- From arkiver https://github.com/ArchiveTeam/vlive-grab/blob/master/vlive.lua
    os.execute("sleep " .. math.floor(math.pow(2, tries)))
    tries = tries + 1
  end
  if tries == 10 then
    abortgrab = true
  end
end

-- Taken verbatim from previous projects I've done'
local queue_list_to = function(list, key)
  if do_debug then
    for item, _ in pairs(list) do
      print("Would have sent discovered item " .. item)
    end
  else
    local to_send = nil
    for item, _ in pairs(list) do
      assert(string.match(item, ":")) -- Message from EggplantN, #binnedtray (search "colon"?)
      if to_send == nil then
        to_send = item
      else
        to_send = to_send .. "\0" .. item
      end
      print("Queued " .. item)

      if #to_send > 1500 then
        send_binary(to_send .. "\0", key)
        to_send = ""
      end
    end

    if to_send ~= nil and #to_send > 0 then
      send_binary(to_send .. "\0", key)
    end
  end
end

module.upload = function()
  queue_list_to(queue, "wysp-qzjkrxpuzjub4dmm")
  queue_list_to(external_urls_queue, "urls-op991cap2s2amz92")
  queue = {}
  external_urls_queue = {}
end

module.queue_request_for_upload = function(handler, params_serialized)
  assert(type(handler) == "string")
  assert(type("params_serialized" == "string"))
  queue[handler .. ":" .. params_serialized] = true
end

module.queue_external_url_for_upload = function(url)
  if url:match(":") then
    external_urls_queue[url] = true
  end
end

return module
