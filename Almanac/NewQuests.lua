local _, ns = ...
local L, Data = ns.L, ns.Data

-- Quests WoW: Forever has that QuestieDB does not have yet, so they can be
-- listed until it does: Almanac's own list (ForeverQuests.lua), and any more
-- that Forever Dungeon Journal (by Exehn) knows, when it is installed. The
-- journal is read while the game runs, through its ForeverDungeonJournal_NS
-- global: FDJ.DB (dungeons and their quests), QUEST_PREREQ_CHAINS and
-- QUEST_PREREQ_DETAILS (the quests before them), and its XP, money and quest
-- giver tables.
--
-- A quest QuestieDB has is always taken from QuestieDB, and one on Almanac's
-- list from the list, so each one here drops out by itself once QuestieDB
-- adds it.

local NewQuests = {}
ns.NewQuests = NewQuests

local _G = _G
local type, pairs, ipairs, tonumber, floor, sort, format =
	type, pairs, ipairs, tonumber, math.floor, table.sort, string.format

local FACTION_RACES = { Alliance = 77, Horde = 178 }
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
-- Dungeons only the journal knows get zone keys of their own, from here up.
local MADE_UP = 9000000
local madeUp = MADE_UP

-- [questID] = { id, name, level, reqLevel, races, classes, zone, repeatable,
-- origin ("almanac" or "journal"), links, details, xp, money, fixed, choice }
local quests = {}
local ids = {}
local dungeonNames = {} -- [zone key] = name, for dungeons QuestieDB does not know

-- "The Deadmines" and "Deadmines" are one dungeon.
local function Normal(name)
	return ((type(name) == "string" and name or ""):lower():gsub("^the ", ""))
end
NewQuests.Normal = Normal

local function Add(id, quest)
	if quests[id] then
		return quests[id]
	end
	quests[id] = quest
	ids[#ids + 1] = id
	return quest
end

--------------------------------------------------------------------------------
-- Almanac's own list
--------------------------------------------------------------------------------

-- { name, area ID[, item = true] } -> "Name" (or "Name (an item)") and
-- { zone = area ID }.
local function Who(entry)
	if type(entry) ~= "table" or type(entry[1]) ~= "string" then
		return nil
	end
	local text = entry.item and format(L["%s (an item)"], entry[1]) or entry[1]
	return text, type(entry[2]) == "number" and { zone = entry[2] } or nil
end

local function LoadOwn(list, exists)
	for id, q in pairs(type(list.quests) == "table" and list.quests or {}) do
		if type(id) == "number" and type(q) == "table" and type(q.name) == "string" and not exists(id) then
			local startText, startSpot = Who(q.from)
			local endText, endSpot = Who(q.to)
			Add(id, {
				id = id,
				name = q.name,
				level = q.level,
				reqLevel = q.req or 0,
				races = FACTION_RACES[q.side] or 0,
				classes = 0,
				zone = q.zone or 0,
				repeatable = false,
				origin = "almanac",
				links = { preSingle = q.after and { q.after } or nil },
				details = {
					startedBy = {},
					finishedBy = {},
					startText = startText,
					startSpot = startSpot,
					endText = endText,
					endSpot = endSpot,
				},
				xp = q.xp,
				fixed = {},
				choice = {},
			})
		end
	end
	for key, name in pairs(type(list.dungeons) == "table" and list.dungeons or {}) do
		if not (Data.dungeons and Data.dungeons[key]) then
			dungeonNames[key] = name
		end
	end
end

--------------------------------------------------------------------------------
-- Forever Dungeon Journal
--------------------------------------------------------------------------------

-- "4,590 XP  •  7s  •  Gadgetzan +100" -> 700 (copper), or nil when it
-- lists no money.
function NewQuests.ParseMoney(summary)
	if type(summary) ~= "string" then
		return nil
	end
	for part in (summary .. "\226\128\162"):gmatch("(.-)\226\128\162") do
		part = part:gsub("^%s+", ""):gsub("%s+$", "")
		if part:match("^[%d%s,gsc]+$") and part:match("%d%s*[gsc]") then
			local copper = 0
			for amount, unit in part:gsub(",", ""):gmatch("(%d+)%s*([gsc])") do
				amount = tonumber(amount)
				copper = copper + (unit == "g" and amount * 10000 or unit == "s" and amount * 100 or amount)
			end
			return copper
		end
	end
	return nil
end

-- A spot on a map ({ mapID, x, y, label }, x and y from 0 to 1) as
-- { zone, x, y, label }, x and y in percent.
local function Spot(map)
	if type(map) ~= "table" or type(map.mapID) ~= "number" then
		return nil
	end
	local area = Data.uiMapToArea and Data.uiMapToArea[map.mapID]
	if type(area) ~= "number" or area <= 0 then
		return nil
	end
	return {
		zone = Data.ZoneKey(area),
		x = type(map.x) == "number" and floor(map.x * 1000 + 0.5) / 10 or nil,
		y = type(map.y) == "number" and floor(map.y * 1000 + 0.5) / 10 or nil,
		label = type(map.label) == "string" and map.label or nil,
	}
end

local function Items(list)
	local out = {}
	for _, entry in ipairs(type(list) == "table" and list or {}) do
		if type(entry) == "table" and type(entry[1]) == "number" then
			out[#out + 1] = { entry[1], 1 }
		end
	end
	return out
end

-- A quest of one of the journal's dungeons.
local function JournalQuest(fdj, q, zone)
	local classes = q.classOnly and CLASS_IDS[q.classOnly]
	local items = Items(q.rewardItems)
	local xp = type(q.liveXPFallback) == "number" and q.liveXPFallback or fdj.FOREVER_QUEST_XP_FALLBACK and fdj.FOREVER_QUEST_XP_FALLBACK[q.id]
	return Add(q.id, {
		id = q.id,
		name = q.name,
		level = type(q.level) == "number" and q.level or nil,
		reqLevel = type(q.requires) == "number" and q.requires or 0,
		races = FACTION_RACES[q.faction] or 0,
		classes = classes and Data.Bit(classes) or 0,
		zone = zone,
		repeatable = false,
		origin = "journal",
		links = {},
		details = {
			startedBy = {},
			finishedBy = {},
			objectives = type(q.objective) == "string" and { q.objective } or nil,
			startText = q.pickup,
			endText = q.turnin,
			startSpot = Spot(fdj.QUEST_START_MAPS and fdj.QUEST_START_MAPS[q.id]),
		},
		xp = type(xp) == "number" and xp or nil,
		money = NewQuests.ParseMoney(q.rewardSummary) or (fdj.PREREQ_REWARD_MONEY_FALLBACK and fdj.PREREQ_REWARD_MONEY_FALLBACK[q.id]),
		fixed = q.rewardChoice and {} or items,
		choice = q.rewardChoice and items or {},
	})
end

-- The zone key a dungeon of the journal goes under: the one QuestieDB or
-- Almanac's list has for it, else a made-up one.
local function DungeonKey(name, byName)
	local normal = Normal(name)
	local key = byName[normal]
	if not key then
		madeUp = madeUp + 1
		key = madeUp
		byName[normal] = key
		dungeonNames[key] = name
	end
	return key
end

local function LoadJournal(exists)
	local fdj = _G.ForeverDungeonJournal_NS
	if type(fdj) ~= "table" or type(fdj.DB) ~= "table" then
		return
	end
	local function Known(id)
		return quests[id] or exists(id)
	end
	local byName = {}
	for areaID, entry in pairs(Data.dungeons or {}) do
		if type(entry) == "table" and type(entry[1]) == "string" then
			byName[Normal(entry[1])] = byName[Normal(entry[1])] or areaID
		end
	end
	for key, name in pairs(dungeonNames) do
		byName[Normal(name)] = byName[Normal(name)] or key
	end

	-- The dungeons' quests.
	for name, dungeon in pairs(fdj.DB) do
		if type(dungeon) == "table" and type(dungeon.quests) == "table" then
			local key
			for _, q in ipairs(dungeon.quests) do
				if type(q) == "table" and type(q.id) == "number" and type(q.name) == "string" and not Known(q.id) then
					key = key or DungeonKey(name, byName)
					JournalQuest(fdj, q, key)
				end
			end
		end
	end

	-- The quests before them. The journal lists every quest needed, in order;
	-- a new one waits for the one before it, and is where its giver is (else
	-- where the quest before it is), for the same faction as the quest it
	-- leads to. Quests on Almanac's list keep their own links.
	local chains = type(fdj.QUEST_PREREQ_CHAINS) == "table" and fdj.QUEST_PREREQ_CHAINS or {}
	local details = type(fdj.QUEST_PREREQ_DETAILS) == "table" and fdj.QUEST_PREREQ_DETAILS or {}
	for target, steps in pairs(chains) do
		if type(steps) == "table" then
			local goal = quests[target]
			local previous, zone
			local listed = false
			for _, step in ipairs(steps) do
				local id = type(step) == "table" and step.id
				if type(id) == "number" and id ~= previous then
					listed = listed or id == target
					local quest = quests[id]
					if not quest and not exists(id) then
						local info = type(details[id]) == "table" and details[id] or {}
						local spot = Spot(info.map)
						quest = Add(id, {
							id = id,
							name = type(step.name) == "string" and step.name or (L["Quest"] .. " " .. id),
							level = type(info.level) == "number" and info.level or nil,
							reqLevel = type(info.requires) == "number" and info.requires or 0,
							races = goal and goal.races or 0,
							classes = goal and goal.classes or 0,
							zone = spot and spot.zone or zone or (goal and goal.zone) or 0,
							repeatable = false,
							origin = "journal",
							links = {},
							details = {
								startedBy = {},
								finishedBy = {},
								objectives = type(info.objective) == "string" and { info.objective } or nil,
								startText = info.pickup,
								endText = info.turnin,
								startSpot = spot,
							},
							xp = fdj.FOREVER_QUEST_XP_FALLBACK and fdj.FOREVER_QUEST_XP_FALLBACK[id],
							money = fdj.PREREQ_REWARD_MONEY_FALLBACK and fdj.PREREQ_REWARD_MONEY_FALLBACK[id],
							fixed = {},
							choice = {},
						})
					end
					if quest then
						if quest.origin == "journal" and previous and not quest.links.preSingle then
							quest.links.preSingle = { previous }
						end
						zone = quest.zone
					elseif exists(id) then
						zone = (Data.Basics(id) or {}).zone
					end
					previous = id
				end
			end
			-- A list that leads up to its quest without naming it.
			if goal and goal.origin == "journal" and previous and not listed and not goal.links.preSingle then
				goal.links.preSingle = { previous }
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Loading and reading
--------------------------------------------------------------------------------

-- Reads Almanac's list, then the journal. exists(questID) says whether
-- QuestieDB has a quest. Returns whether there are any.
function NewQuests.Load(exists)
	quests, ids, dungeonNames = {}, {}, {}
	madeUp = MADE_UP
	LoadOwn(type(ns.ForeverQuests) == "table" and ns.ForeverQuests or {}, exists)
	LoadJournal(exists)
	sort(ids)
	return #ids > 0
end

function NewQuests.Ids()
	return ids
end

function NewQuests.Quest(id)
	return quests[id]
end

-- The name of a dungeon QuestieDB does not know, by zone key.
function NewQuests.DungeonName(key)
	return dungeonNames[key]
end

function NewQuests.Dungeons()
	return dungeonNames
end
