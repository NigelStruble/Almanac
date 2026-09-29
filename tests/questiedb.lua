-- Loads an installed QuestieDB (the WoW: Forever build, baked into its TOC)
-- into a mock client's environment, so Almanac can be tested against the
-- real quest data. QuestieDB decodes its data with C_EncodingUtil (base64,
-- zlib, CBOR); here those are done in plain Lua, with the LibDeflate that
-- Questie ships for zlib.
--
-- Usage: require("questiedb").Load(env, addonsFolder) -> true, or nil and why

local QuestieDB = {}

local function ReadToc(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local meta, files = {}, {}
	for line in file:lines() do
		line = line:gsub("\r$", "")
		local key, value = line:match("^## ([^:]+):%s?(.*)$")
		if key then
			meta[key] = value
		elseif line ~= "" and not line:match("^#") then
			files[#files + 1] = line
		end
	end
	file:close()
	return meta, files
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INDEX = {}
for i = 1, #B64 do
	B64INDEX[B64:byte(i)] = i - 1
end

local function DecodeBase64(s)
	local out, n = {}, 0
	local bits, count = 0, 0
	for i = 1, #s do
		local v = B64INDEX[s:byte(i)]
		if v then
			bits = bits * 64 + v
			count = count + 6
			if count >= 8 then
				count = count - 8
				local byte = math.floor(bits / 2 ^ count)
				bits = bits - byte * 2 ^ count
				n = n + 1
				out[n] = string.char(byte)
			end
		end
	end
	return table.concat(out)
end

local function Float(bytes, expBits, fracBits)
	local total = 0
	for i = 1, #bytes do
		total = total * 256 + bytes:byte(i)
	end
	local sign = 1
	local signBit = 2 ^ (expBits + fracBits)
	if total >= signBit then
		sign = -1
		total = total - signBit
	end
	local exp = math.floor(total / 2 ^ fracBits)
	local frac = total - exp * 2 ^ fracBits
	local bias = 2 ^ (expBits - 1) - 1
	if exp == 0 then
		return sign * math.ldexp(frac, 1 - bias - fracBits)
	elseif exp == 2 ^ expBits - 1 then
		return frac == 0 and sign * math.huge or 0 / 0
	end
	return sign * math.ldexp(frac + 2 ^ fracBits, exp - bias - fracBits)
end

local function DeserializeCBOR(s)
	local pos = 1
	local function Byte()
		local b = s:byte(pos)
		pos = pos + 1
		return b
	end
	local function Uint(n)
		local v = 0
		for _ = 1, n do
			v = v * 256 + Byte()
		end
		return v
	end
	local function Argument(info)
		if info < 24 then
			return info
		elseif info == 24 then
			return Uint(1)
		elseif info == 25 then
			return Uint(2)
		elseif info == 26 then
			return Uint(4)
		elseif info == 27 then
			return Uint(8)
		elseif info == 31 then
			return nil
		end
		error("bad CBOR argument " .. info)
	end
	local Item
	function Item()
		local b = Byte()
		local major, info = math.floor(b / 32), b % 32
		if major == 0 then
			return Argument(info)
		elseif major == 1 then
			return -1 - Argument(info)
		elseif major == 2 or major == 3 then
			local len = Argument(info)
			if not len then
				local parts = {}
				while s:byte(pos) ~= 0xff do
					parts[#parts + 1] = Item()
				end
				pos = pos + 1
				return table.concat(parts)
			end
			local str = s:sub(pos, pos + len - 1)
			pos = pos + len
			return str
		elseif major == 4 or major == 5 then
			local len = Argument(info)
			local t = {}
			local i = 0
			while true do
				if len then
					if i >= len then
						break
					end
				elseif s:byte(pos) == 0xff then
					pos = pos + 1
					break
				end
				i = i + 1
				if major == 4 then
					t[i] = Item()
				else
					local k = Item()
					t[k] = Item()
				end
			end
			return t
		elseif major == 6 then
			Argument(info)
			return Item()
		end
		if info == 20 then
			return false
		elseif info == 21 then
			return true
		elseif info == 22 or info == 23 then
			return nil
		elseif info == 25 then
			pos = pos + 2
			return Float(s:sub(pos - 2, pos - 1), 5, 10)
		elseif info == 26 then
			pos = pos + 4
			return Float(s:sub(pos - 4, pos - 1), 8, 23)
		elseif info == 27 then
			pos = pos + 8
			return Float(s:sub(pos - 8, pos - 1), 11, 52)
		end
		return Argument(info)
	end
	return Item()
end

-- The WoW folder: from ALMANAC_WOW_ADDONS, else where it is on the author's
-- machine.
function QuestieDB.Folder()
	return os.getenv("ALMANAC_WOW_ADDONS") or "E:/World of Warcraft Windows/_classic_beta_/Interface/AddOns"
end

function QuestieDB.Load(env, addons)
	addons = addons or QuestieDB.Folder()
	local dir = addons .. "/QuestieDB"
	local meta, files = ReadToc(dir .. "/QuestieDB_Forever.toc")
	if not meta then
		return nil, "no QuestieDB at " .. dir
	end
	local deflateChunk = loadfile(addons .. "/Questie/Libs/LibDeflate/LibDeflate.lua")
	if not deflateChunk then
		return nil, "no Questie LibDeflate at " .. addons
	end
	local LibDeflate = deflateChunk()

	env.C_EncodingUtil = {
		DecodeBase64 = DecodeBase64,
		DecompressString = function(data, method)
			if method == 1 then
				return LibDeflate:DecompressZlib(data)
			end
			return LibDeflate:DecompressDeflate(data)
		end,
		DeserializeCBOR = DeserializeCBOR,
	}
	local addOns = env.C_AddOns
	local GetMetadata = addOns.GetAddOnMetadata
	addOns.GetAddOnMetadata = function(addon, key)
		if addon == "QuestieDB" then
			return meta[key]
		end
		return GetMetadata(addon, key)
	end
	env.GetLocale = env.GetLocale or function()
		return "enUS"
	end
	env.UnitClassBase = env.UnitClassBase or function()
		local _, file, id = env.UnitClass("player")
		return file, id
	end

	local ns = {}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(dir .. "/" .. file:gsub("\\", "/"))
		if not chunk then
			return nil, err
		end
		setfenv(chunk, env)
		local ok, loadErr = pcall(chunk, "QuestieDB", ns)
		if not ok then
			return nil, file .. ": " .. tostring(loadErr)
		end
	end
	if not env.LibQuestieDB then
		return nil, "QuestieDB did not publish LibQuestieDB"
	end
	return true
end

return QuestieDB
