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
local type, pairs, ipairs, pcall, next, tonumber = type, pairs, ipairs, pcall, next, tonumber
local floor, sort = math.floor, table.sort

-- The QuestieDB contract Almanac is written against (QuestieDB checks the range).
local CONTRACT = 2

local QuestDB, ItemDB, NpcDB, ObjectDB

-- Worked out from the database once it is read; Data.Init starts them afresh.
local basics = {} -- [questID] = the quest's record (Data.Basics), or false
local unplaced = {} -- [area ID] = where an area none of the zone lists know goes
local dungeonByName -- [normalized name] = a dungeon's zone key

--------------------------------------------------------------------------------
-- Zones, dungeons and categories
--------------------------------------------------------------------------------

-- Zones by continent (AreaTable IDs). Cities count as zones. Zones not here
-- go where Questie's quest journal puts them (QuestieGroup below), so zones
-- QuestieDB adds find their place without an update to Almanac.
local EASTERN_KINGDOMS = {
	1, 3, 4, 8, 10, 11, 12, 25, 28, 33, 36, 38, 40, 41, 44, 45, 46, 47, 51, 85,
	130, 139, 267, 1497, 1519, 1537, 2257,
	16591, -- Riverglades (WoW: Forever)
}
local KALIMDOR = {
	14, 15, 16, 17, 141, 148, 215, 331, 357, 361, 400, 405, 406, 440, 490, 493,
	618, 1377, 1637, 1638, 1657,
	616, 16651, -- Mount Hyjal and Shen'dralas (WoW: Forever)
}
local RAIDS = { 1977, 2159, 2677, 2717, 3428, 3429, 3456 }
local BATTLEGROUNDS = {
	2597, 3277, 3358,
	16606, -- Darkspear Islands (WoW: Forever)
}
-- In QuestieDB's dungeon list, but not dungeons.
local NOT_DUNGEONS = { 2257, 2917, 2918 }

local function Set(list)
	local set = {}
	for _, id in ipairs(list) do
		set[id] = true
	end
	return set
end

-- [area ID] = the group it is listed in: the continents, and WoW: Forever's
-- Zephras Isle, an island of its own (the Skyborne's first zone), and the
-- "Crafting" area its writ quests are filed under.
local groupOf = { [16593] = "zephras", [16941] = "profession" }
for _, id in ipairs(EASTERN_KINGDOMS) do
	groupOf[id] = "ek"
end
for _, id in ipairs(KALIMDOR) do
	groupOf[id] = "kalimdor"
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

-- The groups of the zone list, in order. A continent Questie has and Almanac
-- does not gets a group of its own, after these continents (Data.GroupName).
Data.GROUPS = {
	{ key = "ek", name = L["Eastern Kingdoms"] },
	{ key = "kalimdor", name = L["Kalimdor"] },
	{ key = "zephras", name = L["Zephras Isle"] },
	{ key = "dungeon", name = L["Dungeons"] },
	{ key = "raid", name = L["Raids"] },
	{ key = "pvp", name = L["Battlegrounds"] },
	{ key = "class", name = L["Class"] },
	{ key = "profession", name = L["Professions"] },
	{ key = "event", name = L["World Events"] },
	{ key = "other", name = L["Other"] },
}

-- Races and their factions: raceID -> faction. The classic races, and
-- WoW: Forever's High Order (95) and Windshaper (96) Skyborne. No later
-- races: their bits are not Forever's (race 34's would be the Windshaper's),
-- and one as high as race 70's is past what a number holds exactly, which
-- rounds the low bits, the classic races, out of a mask.
local RACE_FACTION = {
	[1] = "Alliance", [3] = "Alliance", [4] = "Alliance", [7] = "Alliance", [11] = "Alliance",
	[95] = "Alliance",
	[2] = "Horde", [5] = "Horde", [6] = "Horde", [8] = "Horde", [9] = "Horde", [10] = "Horde",
	[96] = "Horde",
}

local RACE_IDS = {} -- the races above, in order
for raceID in pairs(RACE_FACTION) do
	RACE_IDS[#RACE_IDS + 1] = raceID
end
table.sort(RACE_IDS)

-- Races whose bit is not raceID - 1: Forever puts the Skyborne at bits 32/33.
local RACE_BITS = { [95] = 2 ^ 32, [96] = 2 ^ 33 }

-- One of QuestieDB's published race tables (read-only by its contract), in
-- the encoding of the game it is built for: raceMaskById (race ID -> bit) or
-- factionRaceMasks (faction -> its races' bits). Nil from a QuestieDB that
-- does not publish it. QuestieDB is loaded before Almanac, so this works
-- before Data.Init.
local function QuestieRaces(name)
	local lib = _G.LibQuestieDB
	local enum = type(lib) == "table" and type(lib.Enum) == "table" and lib.Enum
	local value = enum and enum[name]
	return type(value) == "table" and value or nil
end

-- The bit of a race or class ID in a quest's allowed races or classes.
function Data.Bit(id)
	return 2 ^ ((id or 1) - 1)
end

-- The bit of a race in a quest's allowed races: QuestieDB's, else ours.
function Data.RaceBit(raceID)
	local byID = QuestieRaces("raceMaskById")
	local bit = byID and raceID and byID[raceID]
	if type(bit) == "number" and bit > 0 then
		return bit
	end
	return RACE_BITS[raceID] or Data.Bit(raceID)
end

-- Whether bit is set in mask. A mask of 0 (or none) allows everyone.
function Data.HasBit(mask, bit)
	if not mask or mask == 0 then
		return true
	end
	return floor(mask / bit) % 2 == 1
end

-- The single bits set in a mask, lowest first (none for 0).
function Data.Bits(mask)
	local bits = {}
	if type(mask) == "number" and mask > 0 then
		for i = 0, 52 do
			local value = 2 ^ i
			if value > mask then
				break
			end
			if floor(mask / value) % 2 == 1 then
				bits[#bits + 1] = value
			end
		end
	end
	return bits
end

-- All the race bits of a faction ("Alliance" or "Horde"; 0 for others):
-- QuestieDB's mask for it, else the sum of its races' bits.
function Data.FactionMask(faction)
	local masks = QuestieRaces("factionRaceMasks")
	local mask = masks and faction and masks[faction]
	if type(mask) == "number" then
		return mask
	end
	mask = 0
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

-- The race IDs Almanac knows, in order.
function Data.RaceIDs()
	return RACE_IDS
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
	-- Which map an area is drawn on (QuestieDB's Forever build has it).
	Data.areaToUiMap = Merge(Parse(private.areaIdToUiMapId), Parse(private.areaIdToUiMapIdOverride))
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
	-- dungeons they are in: dungeons too once QuestieDB has all their quests,
	-- if it does not list the dungeon.
	local newQuests = ns.NewQuests
	if newQuests then
		newQuests.Load(Data.QuestExists)
		for key in pairs(newQuests.Dungeons()) do
			Data.dungeonOf[key] = key
		end
	end
	-- Records read while the new quests were loading are read again, now
	-- that every dungeon is known.
	basics, unplaced, dungeonByName = {}, {}, nil
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

-- The zone QuestieDB files a quest under (its zoneOrSort), 0 for none.
function Data.FiledZone(id)
	local zone = Read(QuestDB, id, "zoneOrSort")
	return type(zone) == "number" and zone or 0
end

-- The area an NPC or object stands in, or nil.
local function Home(entity, id)
	local zone = Read(entity, id, "zoneID")
	if type(zone) == "number" and zone > 0 then
		return zone
	end
	local spawns = Read(entity, id, "spawns")
	zone = type(spawns) == "table" and next(spawns)
	return type(zone) == "number" and zone > 0 and zone or nil
end

-- Where a quest QuestieDB files under no zone is listed: the dungeon Almanac's
-- list or the journal puts it in (NewQuests.lua), else where its quest giver
-- stands, else where it is turned in. 0 when none of them says.
local function UnfiledZone(id)
	local newQuests = ns.NewQuests
	local zone = newQuests and newQuests.ZoneFor and newQuests.ZoneFor(id)
	if zone then
		return zone
	end
	for _, field in ipairs({ "startedBy", "finishedBy" }) do
		local who = Read(QuestDB, id, field)
		if type(who) == "table" then
			for _, npc in ipairs(type(who[1]) == "table" and who[1] or {}) do
				zone = Home(NpcDB, npc)
				if zone then
					return zone
				end
			end
			for _, object in ipairs(type(who[2]) == "table" and who[2] or {}) do
				zone = Home(ObjectDB, object)
				if zone then
					return zone
				end
			end
		end
	end
	return 0
end

-- What the quest list is built from: { id, name, level, reqLevel, races,
-- classes, zone, repeatable }. zone is where QuestieDB files the quest, or
-- for one it files under no zone, where Almanac lists it (UnfiledZone). Nil
-- for an unknown quest.
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
	local zone = Data.FiledZone(id)
	quest = {
		id = id,
		name = name,
		-- Some event quests have no level: they are the character's level.
		level = level > 0 and level or nil,
		reqLevel = reqLevel,
		races = Read(QuestDB, id, "requiredRaces") or 0,
		classes = Read(QuestDB, id, "requiredClasses") or 0,
		zone = zone ~= 0 and zone or UnfiledZone(id),
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
-- Questie
--------------------------------------------------------------------------------

-- Questie knows more than QuestieDB publishes: the quests it hides
-- (duplicates, quests that are not in the game, world event quests out of
-- season), which event quests are in season, and where its quest journal
-- files each zone. That is not part of Questie's public API, so it is only
-- used while it looks as expected, once Questie says it is ready.
local modules = {}

function Data.QuestieModule(name)
	if modules[name] then
		return modules[name]
	end
	local questie, loader = _G.Questie, _G.QuestieLoader
	if type(questie) ~= "table" or type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return nil
	end
	if type(questie.API) == "table" and not questie.API.isReady then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	if ok and type(module) == "table" then
		modules[name] = module
		return module
	end
	return nil
end

-- The categories of Questie's journal (its l10n.zoneCategoryLookup) as
-- Almanac's groups. Its Events are left out, as Almanac's World Events group
-- marks its quests out of season, and so are Class, Pet Battle and Scenarios.
-- Any other category is a continent Almanac has no group for, and gets one.
local QUESTIE_GROUPS = { [1] = "ek", [2] = "kalimdor", [8] = "zephras", [9] = "dungeon", [10] = "pvp", [12] = "profession" }
local QUESTIE_SKIPPED = { [11] = true, [13] = true, [14] = true, [15] = true }

local questieZones -- [area ID] = the category Questie's journal files it under

local function QuestieZones()
	if questieZones then
		return questieZones
	end
	local l10n = Data.QuestieModule("l10n")
	local lookup = l10n and l10n.zoneCategoryLookup
	if type(lookup) ~= "table" then
		return nil
	end
	-- In order, so an area in a continent and in Dungeons goes under Dungeons.
	local categories = {}
	for category, list in pairs(lookup) do
		if type(category) == "number" and type(list) == "table" and not QUESTIE_SKIPPED[category] then
			categories[#categories + 1] = category
		end
	end
	sort(categories)
	local zones = {}
	for _, category in ipairs(categories) do
		for area in pairs(lookup[category]) do
			if type(area) == "number" and area > 0 then
				zones[area] = category
			end
		end
	end
	questieZones = zones
	return zones
end

-- The group Questie's journal puts an area in, or nil.
local function QuestieGroup(area)
	local zones = QuestieZones()
	local category = zones and zones[area]
	return category and (QUESTIE_GROUPS[category] or ("questie" .. category)) or nil
end

-- A group's name: Almanac's, or for a continent only Questie has, Questie's.
function Data.GroupName(key)
	for _, group in ipairs(Data.GROUPS) do
		if group.key == key then
			return group.name
		end
	end
	local category = type(key) == "string" and tonumber(key:match("^questie(%d+)$"))
	local l10n = category and Data.QuestieModule("l10n")
	if not l10n then
		return L["Other"]
	end
	local name = type(l10n.continentLookup) == "table" and l10n.continentLookup[category]
	if type(name) ~= "string" then
		return L["Other"]
	end
	-- Questie translates its names by calling its l10n module.
	local ok, translated = pcall(function()
		return l10n(name)
	end)
	return ok and type(translated) == "string" and translated or name
end

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

-- Whether an area is in a group of Almanac's own lists, or of Questie's.
local function Placed(area)
	return isRaid[area] or isBattleground[area] or groupOf[area] or QuestieGroup(area) ~= nil
end

-- A dungeon's zone key by its name ("The Hall of Thanes", or the name the game
-- gives its instance): QuestieDB's dungeons, and the new ones (NewQuests.lua).
local function DungeonByName(name)
	local newQuests = ns.NewQuests
	if not (newQuests and Data.ready and type(name) == "string") then
		return nil
	end
	if not dungeonByName then
		dungeonByName = {}
		local function Add(text, key)
			local normal = newQuests.Normal(text)
			if normal ~= "" and not dungeonByName[normal] then
				dungeonByName[normal] = key
			end
		end
		for key, known in pairs(newQuests.Dungeons()) do
			Add(C.AreaName(key), key)
			Add(known, key)
		end
		-- The lowest area first: the dungeon, not a later copy of it
		-- (Scholomance 2057, not 6066).
		local areas = {}
		for areaID in pairs(Data.dungeons or {}) do
			if Data.dungeonOf[areaID] then
				areas[#areas + 1] = areaID
			end
		end
		sort(areas)
		for _, areaID in ipairs(areas) do
			local entry = Data.dungeons[areaID]
			Add(C.AreaName(areaID), Data.dungeonOf[areaID])
			Add(type(entry) == "table" and entry[1], Data.dungeonOf[areaID])
		end
	end
	return dungeonByName[newQuests.Normal(name)]
end

-- Where a quest is listed: its dungeon, or its zone (not a subzone such as
-- Northshire Valley, which goes under Elwynn Forest), or its category. An area
-- none of the lists know is a dungeon's when it has the dungeon's name (WoW:
-- Forever's second City of Dalaran area), else part of the zone whose map it
-- is drawn on (The Shaper's Terrace, on Un'Goro Crater's).
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
	local subZones = Data.subZones or {}
	local parent = subZones[zone]
	if type(parent) == "number" and parent > 0 then
		return dungeons[parent] or parent
	end
	if not Data.ready or Placed(zone) then
		return zone
	end
	local key = unplaced[zone]
	if not key then
		key = DungeonByName(C.AreaName(zone))
		if not key then
			key = zone
			local map = Data.areaToUiMap and Data.areaToUiMap[zone]
			local area = type(map) == "number" and map > 0 and Data.uiMapToArea and Data.uiMapToArea[map]
			if type(area) == "number" and area > 0 and area ~= zone then
				parent = subZones[area]
				key = dungeons[area] or (type(parent) == "number" and parent > 0 and (dungeons[parent] or parent)) or area
			end
		end
		unplaced[zone] = key
	end
	return key
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
	return groupOf[key] or QuestieGroup(key) or "other"
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

-- The zone key for where the character is now: the dungeon when inside one
-- (by its name for a dungeon QuestieDB cannot place by its instance), else
-- the zone of the map the game shows for the character.
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
