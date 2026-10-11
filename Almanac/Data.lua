local _, ns = ...
local L, C = ns.L, ns.C

-- The quest database. Almanac reads QuestieDB, the database addon that comes
-- with Questie and is open to other addons through its LibQuestieDB global
-- (QuestieDB's src/api.lua): quests, with their levels, races, classes,
-- zones, prerequisites and follow-ups; which quests reward which items; and
-- its support tables of zones, dungeons and quest XP.
--
-- Quest fields are read once and kept in small records here, since every
-- read of a table field from QuestieDB decodes a fresh copy.

local Data = {}
ns.Data = Data

local _G = _G
local type, pairs, ipairs, pcall, next = type, pairs, ipairs, pcall, next
local floor = math.floor

-- The QuestieDB contract Almanac is written against (QuestieDB checks the range).
local CONTRACT = 2

local QuestDB, ItemDB, NpcDB, ObjectDB

--------------------------------------------------------------------------------
-- Zones, dungeons and categories
--------------------------------------------------------------------------------

-- Zones by continent (AreaTable IDs). Cities count as zones.
local EASTERN_KINGDOMS = {
	1, 3, 4, 8, 10, 11, 12, 25, 28, 33, 36, 38, 40, 41, 44, 45, 46, 47, 51, 85,
	130, 139, 267, 1497, 1519, 1537, 2257,
}
local KALIMDOR = {
	14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493,
	618, 1377, 1637, 1638, 1657,
}
local RAIDS = { 1977, 2159, 2677, 2717, 3428, 3429, 3456 }
local BATTLEGROUNDS = { 2597, 3277, 3358 }
-- In QuestieDB's dungeon list, but not dungeons.
local NOT_DUNGEONS = { 2257, 2917, 2918 }

local function Set(list)
	local set = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	return set
end

local continentOf = {}
for _, id in ipairs(EASTERN_KINGDOMS) do
	continentOf[id] = "ek"
end
for _, id in ipairs(KALIMDOR) do
	continentOf[id] = "kalimdor"
end
local isRaid, isBattleground, notDungeon = Set(RAIDS), Set(BATTLEGROUNDS), Set(NOT_DUNGEONS)

-- Quests filed under a category instead of a zone have a negative "zone" (a
-- QuestSort ID). group: where the category is listed; the second value is
-- its name, or for a class, the class.
local SORTS = {
	[-61] = { "class", "WARLOCK" },
	[-81] = { "class", "WARRIOR" },
	[-82] = { "class", "SHAMAN" },
	[-141] = { "class", "PALADIN" },
	[-161] = { "class", "MAGE" },
	[-162] = { "class", "ROGUE" },
	[-261] = { "class", "HUNTER" },
	[-262] = { "class", "PRIEST" },
	[-263] = { "class", "DRUID" },
	[-372] = { "class", "DEATHKNIGHT" },
	[-395] = { "class", "MONK" },
	[-24] = { "profession", L["Herbalism"] },
	[-101] = { "profession", L["Fishing"] },
	[-121] = { "profession", L["Blacksmithing"] },
	[-181] = { "profession", L["Alchemy"] },
	[-182] = { "profession", L["Leatherworking"] },
	[-201] = { "profession", L["Engineering"] },
	[-264] = { "profession", L["Tailoring"] },
	[-304] = { "profession", L["Cooking"] },
	[-324] = { "profession", L["First Aid"] },
	[-371] = { "profession", L["Inscription"] },
	[-373] = { "profession", L["Jewelcrafting"] },
	[-377] = { "profession", L["Archaeology"] },
	[-398] = { "profession", L["Riding"] },
	[-21] = { "event", L["Hallow's End"] },
	[-22] = { "event", L["Seasonal"] },
	[-41] = { "event", L["Day of the Dead"] },
	[-364] = { "event", L["Darkmoon Faire"] },
	[-366] = { "event", L["Lunar Festival"] },
	[-369] = { "event", L["Midsummer Fire Festival"] },
	[-370] = { "event", L["Brewfest"] },
	[-374] = { "event", L["Noblegarden"] },
	[-375] = { "event", L["Pilgrim's Bounty"] },
	[-376] = { "event", L["Love is in the Air"] },
	[-378] = { "event", L["Children's Week"] },
	[-402] = { "event", L["Harvest Festival"] },
	[-404] = { "event", L["Feast of Winter Veil"] },
	[-25] = { "pvp", L["Battlegrounds"] },
	[-1] = { "other", L["Epic"] },
	[-221] = { "other", L["Treasure Map"] },
	[-241] = { "other", L["Tournament"] },
	[-284] = { "other", L["Special"] },
	[-344] = { "other", L["Legendary"] },
	[-365] = { "other", L["Ahn'Qiraj War"] },
	[-367] = { "other", L["Reputation"] },
	[-368] = { "other", L["Invasion"] },
	[-660] = { "other", L["The High Order"] },
	[-666] = { "other", L["Camping"] },
	[-676] = { "other", L["Night Elf"] },
}

-- The groups of the zone list, in order.
Data.GROUPS = {
	{ key = "ek", name = L["Eastern Kingdoms"] },
	{ key = "kalimdor", name = L["Kalimdor"] },
	{ key = "dungeon", name = L["Dungeons"] },
	{ key = "raid", name = L["Raids"] },
	{ key = "pvp", name = L["Battlegrounds"] },
	{ key = "class", name = L["Class"] },
	{ key = "profession", name = L["Professions"] },
	{ key = "event", name = L["World Events"] },
	{ key = "other", name = L["Other"] },
}

-- Races by faction, for showing (or not) quests of other races of one's own
-- faction. raceID -> faction.
local RACE_FACTION = {
	[1] = "Alliance", [3] = "Alliance", [4] = "Alliance", [7] = "Alliance", [11] = "Alliance",
	[22] = "Alliance", [25] = "Alliance", [29] = "Alliance", [30] = "Alliance", [32] = "Alliance",
	[34] = "Alliance", [37] = "Alliance", [52] = "Alliance",
	[2] = "Horde", [5] = "Horde", [6] = "Horde", [8] = "Horde", [9] = "Horde", [10] = "Horde",
	[26] = "Horde", [27] = "Horde", [28] = "Horde", [31] = "Horde", [35] = "Horde", [36] = "Horde",
	[70] = "Horde",
	[95] = "Alliance", [96] = "Horde", -- High Order and Windshaper Skyborne
}

-- Races whose bit is not raceID - 1: Forever puts the Skyborne at bits 32/33.
local RACE_BITS = { [95] = 2 ^ 32, [96] = 2 ^ 33 }

-- The bit of a race or class ID in a quest's allowed races or classes.
function Data.Bit(id)
	return 2 ^ ((id or 1) - 1)
end

function Data.RaceBit(raceID)
	return RACE_BITS[raceID] or Data.Bit(raceID)
end

-- Whether bit is set in mask. A mask of 0 (or none) allows everyone.
function Data.HasBit(mask, bit)
	if not mask or mask == 0 then
		return true
	end
	return floor(mask / bit) % 2 == 1
end

-- All the race bits of a faction.
function Data.FactionMask(faction)
	local mask = 0
	for raceID, raceFaction in pairs(RACE_FACTION) do
		if raceFaction == faction then
			mask = mask + Data.RaceBit(raceID)
		end
	end
	return mask
end

function Data.RaceFaction(raceID)
	return RACE_FACTION[raceID]
end

--------------------------------------------------------------------------------
-- Loading
--------------------------------------------------------------------------------

-- Support tables are kept as Lua source ("return { ... }") until needed.
local function Parse(value)
	if type(value) == "table" then
		return value
	end
	if type(value) == "string" then
		local fn = _G.loadstring(value)
		if fn then
			local ok, result = pcall(fn)
			if ok and type(result) == "table" then
				return result
			end
		end
	end
	return {}
end

local function Merge(base, override)
	local merged = {}
	for key, value in pairs(base) do
		merged[key] = value
	end
	for key, value in pairs(override) do
		merged[key] = value
	end
	return merged
end

local function LoadSupport(lib)
	local support = lib.Support
	local get = support and support.Get
	local xp = type(get) == "function" and get("QuestXP")
	Data.xp = type(xp) == "table" and type(xp.db) == "table" and xp.db or {}

	local zones = type(get) == "function" and get("ZoneDB") or {}
	local private = type(zones.private) == "table" and zones.private or {}
	Data.dungeons = type(private.dungeons) == "table" and private.dungeons or {}
	Data.subZones = Merge(Parse(private.subZoneToParentZone), Parse(private.subZoneToParentZoneOverride))
	Data.uiMapToArea = Merge(Parse(private.uiMapIdToAreaId), Parse(private.uiMapIdToAreaIdOverride))
	Data.instanceToArea = Parse(zones.instanceIdToAreaId or private.instanceIdToAreaId)

	-- A dungeon's quests can be filed under one of its other areas (Zul'Farrak's
	-- under 978, Gnomeregan's under 133).
	Data.dungeonOf = {}
	for areaID, entry in pairs(Data.dungeons) do
		if type(entry) == "table" and not notDungeon[areaID] then
			Data.dungeonOf[areaID] = areaID
			for _, other in ipairs(type(entry[2]) == "table" and entry[2] or {}) do
				Data.dungeonOf[other] = areaID
			end
		end
	end
end

-- Connects to QuestieDB. Returns false (and sets Data.problem) if it is missing
-- or a version Almanac cannot read.
function Data.Init()
	if Data.ready then
		return true
	end
	local lib = _G.LibQuestieDB
	if type(lib) ~= "table" or type(lib.Quest) ~= "table" or type(lib.Item) ~= "table" then
		Data.problem = L["Almanac needs QuestieDB, the quest database that comes with Questie. Install or turn on Questie."]
		return false
	end
	if type(lib.RequireContract) == "function" then
		local ok, message = lib.RequireContract(CONTRACT)
		if not ok then
			Data.problem = message or L["This version of QuestieDB is not one Almanac can read."]
			return false
		end
	end
	QuestDB, ItemDB, NpcDB, ObjectDB = lib.Quest, lib.Item, lib.Npc, lib.Object
	Data.lib = lib
	LoadSupport(lib)
	-- Forever's quests QuestieDB does not have yet (NewQuests.lua), and the new
	-- dungeons they are in.
	local newQuests = ns.NewQuests
	if newQuests and newQuests.Load(Data.QuestExists) then
		for key in pairs(newQuests.Dungeons()) do
			Data.dungeonOf[key] = key
		end
	end
	Data.ready = true
	Data.problem = nil
	return true
end

--------------------------------------------------------------------------------
-- Reading fields
--------------------------------------------------------------------------------

local function Read(entity, id, key)
	if not entity then
		return nil
	end
	local ok, value = pcall(entity.Get, id, key)
	if ok then
		return value
	end
	return nil
end

-- A list field, or nil when empty.
local function List(entity, id, key)
	local value = Read(entity, id, key)
	if type(value) == "table" and next(value) then
		return value
	end
	return nil
end

-- A quest ID field, or nil for none (stored as 0).
local function Id(entity, id, key)
	local value = Read(entity, id, key)
	if type(value) == "number" and value ~= 0 then
		return value
	end
	return nil
end

-- Every quest: QuestieDB's, and Forever's it does not have.
function Data.QuestIds()
	if not QuestDB then
		return {}
	end
	local ok, ids = pcall(QuestDB.GetAllIds)
	ids = ok and type(ids) == "table" and ids or {}
	local extra = ns.NewQuests and ns.NewQuests.Ids() or {}
	if #extra == 0 then
		return ids
	end
	local all = {}
	for i = 1, #ids do
		all[i] = ids[i]
	end
	for _, id in ipairs(extra) do
		all[#all + 1] = id
	end
	return all
end

-- Whether QuestieDB has a quest.
function Data.QuestExists(id)
	return QuestDB and QuestDB.Exists and QuestDB.Exists(id) or false
end

-- The record of a Forever quest QuestieDB does not have (NewQuests.lua), or
-- nil.
local function NewQuest(id)
	local newQuests = ns.NewQuests
	if newQuests and not Data.QuestExists(id) then
		return newQuests.Quest(id)
	end
	return nil
end

-- Where a quest comes from: "questie", "almanac" (Almanac's list of Forever's
-- new quests) or "journal" (Forever Dungeon Journal).
function Data.Source(id)
	local quest = NewQuest(id)
	return quest and quest.origin or "questie"
end

local basics = {}

-- What the quest list is built from: { id, name, level, reqLevel, races,
-- classes, zone (as QuestieDB files it), repeatable }. Nil for an unknown quest.
function Data.Basics(id)
	local quest = basics[id]
	if quest ~= nil then
		return quest or nil
	end
	local name = Read(QuestDB, id, "name")
	if type(name) ~= "string" then
		quest = NewQuest(id) or false
		basics[id] = quest
		return quest or nil
	end
	local level = Read(QuestDB, id, "questLevel") or 0
	local reqLevel = Read(QuestDB, id, "requiredLevel") or 0
	local special = Read(QuestDB, id, "specialFlags") or 0
	local flags = Read(QuestDB, id, "questFlags") or 0
	quest = {
		id = id,
		name = name,
		-- Some event quests have no level: they are the character's level.
		level = level > 0 and level or nil,
		reqLevel = reqLevel,
		races = Read(QuestDB, id, "requiredRaces") or 0,
		classes = Read(QuestDB, id, "requiredClasses") or 0,
		zone = Read(QuestDB, id, "zoneOrSort") or 0,
		-- specialFlags 1: repeatable; questFlags 4096, 32768: daily, weekly.
		repeatable = special % 2 == 1 or floor(flags / 4096) % 2 == 1 or floor(flags / 32768) % 2 == 1,
	}
	basics[id] = quest
	return quest
end

local links = {}

-- What decides whether the character can take a quest, and how quests chain:
--   preSingle     any one of these must be done
--   preGroup      all of these must be done (a negative ID: exactly that one)
--   next          the quest that follows; once it is taken or done, this one
--                 no longer can be
--   exclusive     taking or finishing any of these rules this one out
--   parent        must be in the quest log
--   breadcrumbFor this quest leads to that one, and goes away once that one
--                 is taken or done
--   breadcrumbs   quests that lead to this one; while one is in the log, this
--                 one waits for it to be turned in
--   untilDone     goes away once that quest is done
--   startingWith  needs that quest taken or done
--   disabledBy    not while that quest is in the log
--   skill, minRep, maxRep: { id, value }; spell: a spell known (negative: not
--   known); spec: a profession specialization spell; maxLevel
function Data.Links(id)
	local quest = links[id]
	if quest then
		return quest
	end
	local new = NewQuest(id)
	if new then
		return new.links
	end
	quest = {
		preSingle = List(QuestDB, id, "preQuestSingle"),
		preGroup = List(QuestDB, id, "preQuestGroup"),
		next = Id(QuestDB, id, "nextQuestInChain"),
		exclusive = List(QuestDB, id, "exclusiveTo"),
		parent = Id(QuestDB, id, "parentQuest"),
		breadcrumbFor = Id(QuestDB, id, "breadcrumbForQuestId"),
		breadcrumbs = List(QuestDB, id, "breadcrumbs"),
		untilDone = Id(QuestDB, id, "availableUntilCompleted"),
		startingWith = Id(QuestDB, id, "availableStartingWith"),
		disabledBy = Id(QuestDB, id, "disabledByQuest"),
		skill = List(QuestDB, id, "requiredSkill"),
		minRep = List(QuestDB, id, "requiredMinRep"),
		maxRep = List(QuestDB, id, "requiredMaxRep"),
		spell = Id(QuestDB, id, "requiredSpell"),
		spec = Id(QuestDB, id, "requiredSpecialization"),
		maxLevel = Id(QuestDB, id, "requiredMaxLevel"),
	}
	links[id] = quest
	return quest
end

local details = {}

-- What only a quest's tooltip needs: who starts and ends it, its objectives,
-- reputation and the item that starts it. A new Forever quest says who starts
-- and ends it in words (startText, endText), and may say where (startSpot,
-- endSpot: { zone, x, y, label }; x, y and label when known).
function Data.Details(id)
	local quest = details[id]
	if quest then
		return quest
	end
	local new = NewQuest(id)
	if new then
		return new.details
	end
	quest = {
		startedBy = Read(QuestDB, id, "startedBy") or {},
		finishedBy = Read(QuestDB, id, "finishedBy") or {},
		objectives = List(QuestDB, id, "objectivesText"),
		reputation = List(QuestDB, id, "reputationReward"),
		sourceItem = Id(QuestDB, id, "sourceItemId"),
	}
	details[id] = quest
	return quest
end

-- The quest's name: from the database, or from the client for quests the
-- database does not know.
function Data.QuestName(id)
	local quest = Data.Basics(id)
	return quest and quest.name or C.QuestTitle(id) or (L["Quest"] .. " " .. id)
end

-- The database's XP for a quest at its own level, and where it comes from:
-- "database" (QuestieDB), or for a new Forever quest what it gives on
-- Forever: "reported" (Almanac's list) or "journal" (Forever Dungeon
-- Journal). Nil when none knows.
function Data.BaseXP(id)
	local entry = Data.xp and Data.xp[id]
	if type(entry) == "table" and type(entry[2]) == "number" and entry[2] > 0 then
		return entry[2], "database"
	end
	local new = NewQuest(id)
	if new and new.xp then
		return new.xp, new.origin == "journal" and "journal" or "reported"
	end
	return nil
end

-- The money and reward items a new Forever quest has listed with it (only
-- the journal's quests have them; the game says the others').
function Data.NewQuestRewards(id)
	local new = NewQuest(id)
	if new then
		return new.money, new.fixed, new.choice
	end
	return nil
end

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

-- Where a quest is listed: its dungeon, or its zone (not a subzone such as
-- Northshire Valley, which goes under Elwynn Forest), or its category.
function Data.ZoneKey(zone)
	if type(zone) ~= "number" or zone == 0 then
		return 0
	end
	if zone < 0 then
		return zone
	end
	local dungeons = Data.dungeonOf or {}
	if dungeons[zone] then
		return dungeons[zone]
	end
	local parent = Data.subZones and Data.subZones[zone]
	if type(parent) == "number" and parent > 0 then
		return dungeons[parent] or parent
	end
	return zone
end

-- Which group of the zone list a zone key goes in.
function Data.ZoneGroup(key)
	if key < 0 then
		local sort = SORTS[key]
		return sort and sort[1] or "other"
	end
	if isRaid[key] then
		return "raid"
	elseif isBattleground[key] then
		return "pvp"
	elseif Data.dungeonOf and Data.dungeonOf[key] == key then
		return "dungeon"
	end
	return continentOf[key] or "other"
end

-- The class a class category is for ("MAGE"), or nil.
function Data.SortClass(key)
	local sort = SORTS[key]
	if sort and sort[1] == "class" then
		return sort[2]
	end
	return nil
end

function Data.ZoneName(key)
	if key == 0 then
		return L["Unknown zone"]
	end
	if key < 0 then
		local sort = SORTS[key]
		if not sort then
			return L["Other"] .. " (" .. key .. ")"
		end
		if sort[1] == "class" then
			return C.ClassName(sort[2])
		end
		return sort[2]
	end
	local name = C.AreaName(key)
	if name then
		return name
	end
	local dungeon = Data.dungeons and Data.dungeons[key]
	if type(dungeon) == "table" and type(dungeon[1]) == "string" then
		return dungeon[1]
	end
	local new = ns.NewQuests and ns.NewQuests.DungeonName(key)
	if new then
		return new
	end
	return L["Zone"] .. " " .. key
end

-- A dungeon's zone key by its name ("The Hall of Thanes"), for dungeons
-- QuestieDB cannot place by their instance.
local function DungeonByName(name)
	local newQuests = ns.NewQuests
	if not newQuests or type(name) ~= "string" then
		return nil
	end
	local wanted = newQuests.Normal(name)
	for key, known in pairs(newQuests.Dungeons()) do
		if newQuests.Normal(known) == wanted then
			return key
		end
	end
	for areaID, entry in pairs(Data.dungeons or {}) do
		if type(entry) == "table" and newQuests.Normal(entry[1]) == wanted and Data.dungeonOf[areaID] then
			return Data.dungeonOf[areaID]
		end
	end
	return nil
end

-- The zone key for where the character is now: the dungeon when inside one,
-- else the zone of the map the game shows for the character.
function Data.PlayerZoneKey()
	local instanceID, _, instanceName = C.Instance()
	if instanceID and Data.instanceToArea then
		local area = Data.instanceToArea[instanceID]
		if type(area) == "number" and area > 0 then
			return Data.ZoneKey(area)
		end
		local key = DungeonByName(instanceName)
		if key then
			return key
		end
	end
	local uiMap = C.PlayerUiMap()
	local area = uiMap and Data.uiMapToArea and Data.uiMapToArea[uiMap]
	if type(area) == "number" and area > 0 then
		return Data.ZoneKey(area)
	end
	return nil
end

--------------------------------------------------------------------------------
-- NPCs, objects and items
--------------------------------------------------------------------------------

function Data.NpcName(id)
	return Read(NpcDB, id, "name")
end

function Data.ObjectName(id)
	return Read(ObjectDB, id, "name")
end

-- The zone and first spot an NPC or object is found at: zoneKey, x, y.
local function FirstSpawn(spawns, preferred)
	if type(spawns) ~= "table" then
		return nil
	end
	local zone = preferred and spawns[preferred] and preferred or next(spawns)
	local points = zone and spawns[zone]
	local point = type(points) == "table" and points[1]
	if type(point) == "table" then
		return zone, point[1], point[2]
	end
	return zone
end

function Data.NpcSpot(id)
	return FirstSpawn(Read(NpcDB, id, "spawns"), Read(NpcDB, id, "zoneID"))
end

function Data.ObjectSpot(id)
	return FirstSpawn(Read(ObjectDB, id, "spawns"), Read(ObjectDB, id, "zoneID"))
end

local items = {}

-- What the database knows about an item: { name, class, subClass, level,
-- reqLevel }, or nil.
function Data.Item(id)
	local item = items[id]
	if item ~= nil then
		return item or nil
	end
	local name = Read(ItemDB, id, "name")
	if type(name) ~= "string" then
		items[id] = false
		return nil
	end
	item = {
		name = name,
		class = Read(ItemDB, id, "class"),
		subClass = Read(ItemDB, id, "subClass"),
		level = Read(ItemDB, id, "itemLevel"),
		reqLevel = Read(ItemDB, id, "requiredLevel"),
	}
	items[id] = item
	return item
end

-- Walks every item in the database for the quests that reward it, filling
-- rewards[questID] = { itemID, ... } and rewardedBy[itemID] = { questID, ... }.
-- pause() is called now and then, so the work can be spread over frames.
function Data.ScanRewards(rewards, rewardedBy, pause)
	if not ItemDB then
		return
	end
	local ok, ids = pcall(ItemDB.GetAllIds)
	if not ok or type(ids) ~= "table" then
		return
	end
	for i = 1, #ids do
		local itemID = ids[i]
		local quests = List(ItemDB, itemID, "questRewards")
		if quests then
			rewardedBy[itemID] = quests
			for _, questID in ipairs(quests) do
				local list = rewards[questID]
				if not list then
					list = {}
					rewards[questID] = list
				end
				list[#list + 1] = itemID
			end
		end
		if pause and i % 200 == 0 then
			pause(i / #ids)
		end
	end
end

-- For tests: forget what has been read.
function Data.Reset()
	basics, links, details, items = {}, {}, {}, {}
	Data.ready = nil
end
