deep_copy = function(t)
	if type(t) ~= "table" then
		return t
	else
		local n = {}
		for k, v in pairs(t) do
			n[k] = deep_copy(v)
		end
		return n
	end
end

shallow_copy = function(t)
	if type(t) ~= "table" then
		return t
	else
		local n = {}
		for k, v in pairs(t) do
			n[k] = v
		end
		return n
	end
end

deep_compare = function(s, t)
	if type(s) ~= type(t) then
		return false
	end
	if type(s) == "table" then
		for k, v in pairs(s) do
			if t[k] == nil or not deep_compare(v, t[k]) then
				return false
			end
		end
		for k, v in pairs(t) do
			if s[k] == nil then
				return false
			end
		end
		return true
	else
		return s == t
	end
end


-- This is super-rudimentary
-- E.g. it doesn't check for improperly-escaped input URLs
-- Tries to duplicate what WGET does so that there aren't conflicts of the frameworks's queue and wget's
local allowed_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!*'();:@&=+$,/?#[]_.~-"
local char_is_allowed = {}
for i=1,#allowed_chars do
	char_is_allowed[allowed_chars:byte(i)] = true
end

local is_hex = function(c)
	return c ~= nil and string.match(string.char(c), "^[a-fA-F0-9]$")
end

-- Escaping with less URLs escaped
-- Not checked vs the standard
minimal_escape = function(s)
	local res = ""
	for index=1,#s do
		local b = s:byte(index)
		if char_is_allowed[b] then
			res = res .. string.char(b)
		elseif b == string.byte("%") and is_hex(s:byte(index + 1)) and is_hex(s:byte(index + 2)) then
			res = res .. "%"
		else
			res = res .. string.format("%%%02X", b)
		end
	end
	return res
end
