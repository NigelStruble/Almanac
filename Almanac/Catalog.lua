local _, ns = ...
local C, DB, Data, Player, Status = ns.C, ns.DB, ns.Data, ns.Player, ns.Status

-- The quest list: every quest the character could care about, filed by zone,
-- and the chains the quests form. A chain is every quest joined to another by
-- a prerequisite, a follow-up or a breadcrumb, in the order they are done.
-- It is built from QuestieDB a few milliseconds a frame, the first time the
-- window opens, and again when a filter option changes.

local Catalog = {}
ns.Catalog = Catalog

local _G = _G
local type, pairs, ipairs, pcall, abs, floor, ceil, sort = type, pairs, ipairs, pcall, math.abs, math.floor, math.ceil, table.sort

Catalog.ready = false
Catalog.building = false
Catalog.progress = 0
Catalog.zones = {} -- [zone key] = zone (see BuildZones)
Catalog.groups = {} -- the zone list's groups, in order, with their zones
Catalog.chains = {}
Catalog.chainOf = {} -- [questID] = chain
Catalog.kept = {} -- [questID] = true for the quests listed
Catalog.all = {} -- the quests listed, by level

--------------------------------------------------------------------------------
-- Questie
--------------------------------------------------------------------------------

-- Questie keeps a list of quests it hides (duplicates, quests that are not in
-- the game, world event quests out of season) and knows which event quests
-- are in season. That is not part of Questie's public API, so it is only
-- used while it looks as expected, once Questie says it is ready.
local modules = {}

local function QuestieModule(name)
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

function Catalog.QuestieHidden()
	local corrections = QuestieModule("QuestieCorrections")
	local hidden = corrections and corrections.hiddenQuests
	return type(hidden) == "table" and hidden or nil
end

Status.IsEvent = function(id)
	local events = QuestieModule("QuestieEvent")
	if events and type(events.IsEventQuest) == "function" then
		local ok, isEvent = pcall(events.IsEventQuest, id)
		return ok and isEvent and true or false
	end
	return false
end

Status.EventActive = function(id)
	local events = QuestieModule("QuestieEvent")
	return events and type(events.activeQuests) == "table" and events.activeQuests[id] == true or false
end

--------------------------------------------------------------------------------
-- Which quests are listed
--------------------------------------------------------------------------------

-- A quest only other races of the character's faction can take is listed
-- with that option; any race's with the other faction's option.
local function RaceListed(races)
	if Data.HasBit(races, Player.raceBit) then
		return true
	end
	local settings = DB.settings
	if settings.otherFaction then
		return true
	end
	if settings.otherRaces then
		for bit = 0, 31 do
			local value = 2 ^ bit
			if Data.HasBit(Player.factionMask, value) and Data.HasBit(races, value) then
				return true
			end
		end
	end
	return false
end

local function Listed(quest, hidden)
	if hidden and hidden[quest.id] == true and not DB.settings.showHidden then
		return false
	end
	if not RaceListed(quest.races) then
		return false
	end
	return DB.settings.otherClasses or Data.HasBit(quest.classes, Player.classBit)
end

--------------------------------------------------------------------------------
-- Chains
--------------------------------------------------------------------------------

-- The quests that come before a quest.
local function Before(id)
	local links = Data.Links(id)
	local list = {}
	for _, other in ipairs(links.preSingle or {}) do
		list[#list + 1] = other
	end
	for _, other in ipairs(links.preGroup or {}) do
		list[#list + 1] = abs(other)
	end
	if links.parent then
		list[#list + 1] = links.parent
	end
	if links.startingWith then
		list[#list + 1] = links.startingWith
	end
	return list
end

-- The quests that come right after a quest, by its own fields.
local function After(id)
	local links = Data.Links(id)
	local list = {}
	if links.next then
		list[#list + 1] = links.next
	end
	if links.breadcrumbFor then
		list[#list + 1] = links.breadcrumbFor
	end
	return list
end

local function BuildChains(ids, kept, pause)
	-- Quests joined by any link end up in one group (union-find).
	local root = {}
	local function Find(id)
		local parent = root[id]
		if not parent or parent == id then
			return id
		end
		local top = Find(parent)
		root[id] = top
		return top
	end
	local function Join(a, b)
		local ra, rb = Find(a), Find(b)
		if ra ~= rb then
			root[ra] = rb
		end
	end
	local before, after = {}, {}
	for i, id in ipairs(ids) do
		local list = {}
		for _, other in ipairs(Before(id)) do
			if kept[other] and other ~= id then
				list[#list + 1] = other
				Join(id, other)
			end
		end
		before[id] = list
		for _, other in ipairs(After(id)) do
			if kept[other] and other ~= id then
				after[#after + 1] = { id, other }
				Join(id, other)
			end
		end
		if pause and i % 200 == 0 then
			pause()
		end
	end
	-- "a leads to b" also puts a before b.
	for _, pair in ipairs(after) do
		local list = before[pair[2]]
		local seen = false
		for _, other in ipairs(list) do
			if other == pair[1] then
				seen = true
				break
			end
		end
		if not seen then
			list[#list + 1] = pair[1]
		end
	end

	local groups = {}
	for _, id in ipairs(ids) do
		local top = Find(id)
		local group = groups[top]
		if not group then
			group = {}
			groups[top] = group
		end
		group[#group + 1] = id
	end

	local chains, chainOf = {}, {}
	local depth = {}
	local visiting = {}
	-- How many quests come before a quest, at most. Loops in the data are cut.
	local function Depth(id)
		if depth[id] then
			return depth[id]
		end
		if visiting[id] then
			return 0
		end
		visiting[id] = true
		local deepest = 0
		for _, other in ipairs(before[id]) do
			local d = Depth(other) + 1
			if d > deepest then
				deepest = d
			end
		end
		visiting[id] = nil
		depth[id] = deepest
		return deepest
	end

	for _, group in pairs(groups) do
		if #group > 1 then
			for _, id in ipairs(group) do
				Depth(id)
			end
			sort(group, function(a, b)
				if depth[a] ~= depth[b] then
					return depth[a] < depth[b]
				end
				local la, lb = Data.Basics(a).level or 0, Data.Basics(b).level or 0
				if la ~= lb then
					return la < lb
				end
				return a < b
			end)
			-- Named after the name at least half of its quests share (a chain
			-- of "The Defias Brotherhood" parts), or else its first quest.
			local counts, name, best = {}, nil, 0
			for _, id in ipairs(group) do
				local questName = Data.Basics(id).name
				counts[questName] = (counts[questName] or 0) + 1
				if counts[questName] > best then
					name, best = questName, counts[questName]
				end
			end
			if best < 2 or best * 2 < #group then
				name = Data.Basics(group[1]).name
			end
			local chain = { id = group[1], name = name, quests = group, depth = {}, zones = {} }
			for _, id in ipairs(group) do
				chain.depth[id] = depth[id]
				chain.zones[Data.ZoneKey(Data.Basics(id).zone)] = true
				chainOf[id] = chain
			end
			chains[#chains + 1] = chain
		end
	end
	sort(chains, function(a, b)
		return a.id < b.id
	end)
	return chains, chainOf
end

-- Where in its chain a quest is: step, steps.
function Catalog.Step(id)
	local chain = Catalog.chainOf[id]
	if not chain then
		return nil
	end
	for index, other in ipairs(chain.quests) do
		if other == id then
			return index, #chain.quests
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

local function ByLevel(a, b)
	local qa, qb = Data.Basics(a), Data.Basics(b)
	local la, lb = qa.level or qa.reqLevel or 0, qb.level or qb.reqLevel or 0
	if la ~= lb then
		return la < lb
	end
	if qa.name ~= qb.name then
		return qa.name < qb.name
	end
	return a < b
end
Catalog.ByLevel = ByLevel

-- The levels most of a zone's quests are, leaving out the odd one far off.
local function LevelRange(ids)
	local levels = {}
	for _, id in ipairs(ids) do
		local quest = Data.Basics(id)
		if quest.level and not quest.repeatable then
			levels[#levels + 1] = quest.level
		end
	end
	if #levels == 0 then
		return nil
	end
	sort(levels)
	if #levels < 10 then
		return levels[1], levels[#levels]
	end
	return levels[floor(#levels * 0.1) + 1], levels[ceil(#levels * 0.9)]
end

local function BuildZones(ids)
	local zones = {}
	for _, id in ipairs(ids) do
		local key = Data.ZoneKey(Data.Basics(id).zone)
		local zone = zones[key]
		if not zone then
			zone = { key = key, group = Data.ZoneGroup(key), name = Data.ZoneName(key), quests = {} }
			zones[key] = zone
		end
		zone.quests[#zone.quests + 1] = id
	end
	for _, zone in pairs(zones) do
		sort(zone.quests, ByLevel)
		zone.low, zone.high = LevelRange(zone.quests)
	end

	local byGroup = {}
	for _, zone in pairs(zones) do
		local list = byGroup[zone.group]
		if not list then
			list = {}
			byGroup[zone.group] = list
		end
		list[#list + 1] = zone
	end
	local groups = {}
	for _, info in ipairs(Data.GROUPS) do
		local list = byGroup[info.key]
		if list then
			local ownClass = Player.classFile
			sort(list, function(a, b)
				-- The character's own class first.
				local ca, cb = Data.SortClass(a.key) == ownClass, Data.SortClass(b.key) == ownClass
				if ca ~= cb then
					return ca
				end
				if info.key ~= "other" and info.key ~= "event" and info.key ~= "profession" then
					local la, lb = a.low or 99, b.low or 99
					if la ~= lb then
						return la < lb
					end
				end
				return a.name < b.name
			end)
			groups[#groups + 1] = { key = info.key, name = info.name, zones = list }
		end
	end
	return zones, groups
end

--------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------

local function Run(pause)
	local hidden = Catalog.QuestieHidden()
	local ids = Data.QuestIds()
	local kept, list = {}, {}
	for i, id in ipairs(ids) do
		local quest = Data.Basics(id)
		if quest and Listed(quest, hidden) then
			kept[id] = true
			list[#list + 1] = id
			Data.Links(id)
		end
		if pause and i % 100 == 0 then
			Catalog.progress = i / #ids * 0.8
			pause()
		end
	end
	local chains, chainOf = BuildChains(list, kept, pause)
	Catalog.progress = 0.9
	local zones, groups = BuildZones(list)
	sort(list, ByLevel)

	Catalog.kept, Catalog.all = kept, list
	Catalog.chains, Catalog.chainOf = chains, chainOf
	Catalog.zones, Catalog.groups = zones, groups
	Catalog.progress = 1
end

local stop

local function Finished()
	stop = nil
	Catalog.building = false
	Catalog.ready = true
	Status.Reset()
	ns.Send("catalog")
end

-- (Re)builds the list, spread over frames; "catalog" is announced when done.
function Catalog.Build()
	if not Data.ready then
		return
	end
	if stop then
		stop()
	end
	Catalog.building = true
	Catalog.progress = 0
	stop = C.Spread(Run, Finished)
end

-- Builds the list at once (tests, and /almanac commands that need it now).
function Catalog.BuildNow()
	if not Data.ready then
		return
	end
	if stop then
		stop()
		stop = nil
	end
	Run(nil)
	Finished()
end

-- Quests whose name has text in it, by level.
function Catalog.Search(text)
	local found = {}
	text = text:lower()
	for _, id in ipairs(Catalog.all) do
		if Data.Basics(id).name:lower():find(text, 1, true) then
			found[#found + 1] = id
		end
	end
	return found
end
