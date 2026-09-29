local _, ns = ...
local L, C, DB, Data, Player, Status = ns.L, ns.C, ns.DB, ns.Data, ns.Player, ns.Status

-- Quest reward items, and searching them: which quests give a cloth chest
-- with Intellect, say. Which quests reward which items comes from QuestieDB,
-- except for quests the client has listed rewards for (Rewards.lua): WoW:
-- Forever changed some, so the client's list replaces the database's. What
-- an item is (slot, armor or weapon type, stats, level) comes from the game.

local Items = {}
ns.Items = Items

local _G = _G
local type, pairs, ipairs, min, max, sort, tremove, lower =
	type, pairs, ipairs, math.min, math.max, table.sort, table.remove, string.lower

Items.ready = false -- the database's rewards have been read
Items.scanning = false
Items.progress = 0

local fromDatabase = {} -- [questID] = { itemID, ... }
local byItem -- [itemID] = { questID, ... }, the database and the client together
local info = {} -- [itemID] = item details, once the client has them
local asked = {} -- [itemID] = true once requested
local queue = {}
local ticking = false

--------------------------------------------------------------------------------
-- Which quests reward what
--------------------------------------------------------------------------------

function Items.FromDatabase(questID)
	return fromDatabase[questID]
end

-- Rebuilds byItem: each quest's rewards as the client lists them if it has,
-- else as QuestieDB has them.
local function Combine()
	byItem = {}
	local function Add(itemID, questID)
		local list = byItem[itemID]
		if not list then
			list = {}
			byItem[itemID] = list
		end
		for _, other in ipairs(list) do
			if other == questID then
				return
			end
		end
		list[#list + 1] = questID
	end
	local learned = DB.learned
	for questID, entry in pairs(learned) do
		for _, kind in ipairs({ "fixed", "choice" }) do
			for _, item in ipairs(entry[kind] or {}) do
				Add(item[1], questID)
			end
		end
	end
	for questID, list in pairs(fromDatabase) do
		local entry = learned[questID]
		if not (entry and (entry.fixed or entry.choice)) then
			for _, itemID in ipairs(list) do
				Add(itemID, questID)
			end
		end
	end
	-- New Forever quests Forever Dungeon Journal lists rewards for, unless the
	-- client has listed theirs.
	for _, questID in ipairs(ns.NewQuests and ns.NewQuests.Ids() or {}) do
		local entry = learned[questID]
		if not (entry and (entry.fixed or entry.choice)) then
			local _, fixed, choice = Data.NewQuestRewards(questID)
			for _, list in ipairs({ fixed or {}, choice or {} }) do
				for _, item in ipairs(list) do
					Add(item[1], questID)
				end
			end
		end
	end
end

-- The quests that reward an item.
function Items.QuestsFor(itemID)
	if not byItem then
		Combine()
	end
	return byItem[itemID] or {}
end

-- Every item some quest rewards.
function Items.All()
	if not byItem then
		Combine()
	end
	return byItem
end

-- The client listed a quest's rewards (Rewards.lua).
function Items.Learn()
	byItem = nil
	ns.Send("items")
end

-- Reads which quests reward which items from QuestieDB, spread over frames.
function Items.Scan()
	if Items.ready or Items.scanning or not Data.ready then
		return
	end
	Items.scanning = true
	local rewards, rewardedBy = {}, {}
	C.Spread(function(pause)
		Data.ScanRewards(rewards, rewardedBy, function(progress)
			Items.progress = progress
			pause()
		end)
	end, function()
		fromDatabase = rewards
		byItem = nil
		Items.scanning = false
		Items.ready = true
		Items.progress = 1
		ns.Send("items")
	end)
end

-- At once (tests).
function Items.ScanNow()
	local rewards, rewardedBy = {}, {}
	Data.ScanRewards(rewards, rewardedBy)
	fromDatabase = rewards
	byItem = nil
	Items.ready = true
	Items.progress = 1
end

--------------------------------------------------------------------------------
-- What an item is
--------------------------------------------------------------------------------

local Announce = C.Debounce(0.3, function()
	ns.Send("items")
end)

local function Tick()
	local count = 0
	while count < 40 and #queue > 0 do
		local itemID = tremove(queue, 1)
		C.RequestItem(itemID)
		count = count + 1
	end
	if #queue > 0 then
		C.After(0.1, Tick)
	else
		ticking = false
	end
end

local function Ask(itemID)
	if asked[itemID] then
		return
	end
	asked[itemID] = GetTime()
	queue[#queue + 1] = itemID
	if not ticking then
		ticking = true
		C.After(0.05, Tick)
	end
end

-- Whether an item is still being fetched: an item the server has not sent
-- in 20 seconds is taken not to exist.
local function Fetching(itemID)
	local since = asked[itemID]
	return since ~= nil and GetTime() - since < 20
end

-- An item's details: { id, name, link, quality, level, minLevel, equipLoc,
-- icon, classID, subClassID, stats }, or nil while the client is fetching
-- it (it is asked for).
function Items.Info(itemID)
	local item = info[itemID]
	if item then
		return item
	end
	item = C.ItemInfo(itemID)
	if not item then
		Ask(itemID)
		return nil
	end
	item.id = itemID
	item.stats = C.ItemStats(item.link or ("item:" .. itemID))
	info[itemID] = item
	return item
end

-- What can be told without waiting: equipLoc, classID, subClassID, icon.
function Items.Basic(itemID)
	local equipLoc, icon, classID, subClassID = C.ItemInstant(itemID)
	if not classID then
		local item = Data.Item(itemID)
		if item then
			classID, subClassID = item.class, item.subClass
		end
	end
	return equipLoc or "", classID, subClassID, icon
end

function Items.Start()
	C.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
		if asked[itemID] and not info[itemID] then
			Announce()
		end
	end)
	C.On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
		if asked[itemID] and not info[itemID] then
			Announce()
		end
	end)
end

--------------------------------------------------------------------------------
-- Who can use it
--------------------------------------------------------------------------------

local ARMOR, WEAPON = 4, 2

-- Armor types by class, and the level from which they can wear them.
local ARMOR_TYPES = {
	[2] = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, SHAMAN = 1, DRUID = 1 }, -- leather
	[3] = { WARRIOR = 1, PALADIN = 1, HUNTER = 40, SHAMAN = 40 }, -- mail
	[4] = { WARRIOR = 40, PALADIN = 40 }, -- plate
	[6] = { WARRIOR = 1, PALADIN = 1, SHAMAN = 1 }, -- shields
	[7] = { PALADIN = 1 }, -- librams
	[8] = { DRUID = 1 }, -- idols
	[9] = { SHAMAN = 1 }, -- totems
}

-- Weapon types each class can learn (item subclasses).
local WEAPON_TYPES = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 10, 13, 15 },
}
local weaponOK = {}
for class, list in pairs(WEAPON_TYPES) do
	weaponOK[class] = {}
	for _, subClass in ipairs(list) do
		weaponOK[class][subClass] = true
	end
end

-- Whether a class can use an item of this type by the level it needs, or
-- (for mail and plate) by the level the class learns to wear them.
function Items.Usable(classFile, classID, subClassID, level)
	if classID == ARMOR then
		local allowed = ARMOR_TYPES[subClassID]
		if not allowed then
			return true -- cloth, and rings, necks, trinkets and cloaks
		end
		local from = allowed[classFile]
		return from ~= nil and (level or 60) >= from
	elseif classID == WEAPON then
		local allowed = weaponOK[classFile]
		if not allowed or subClassID == 14 or subClassID == 20 then
			return true -- other classes, fishing poles and miscellaneous weapons
		end
		return allowed[subClassID] == true
	end
	return true
end

--------------------------------------------------------------------------------
-- The filters
--------------------------------------------------------------------------------

local function Slot(value, locs, fallback)
	return { value = value, text = _G[locs[1]] or fallback, locs = locs }
end

Items.SLOTS = {
	{ value = "any", text = L["Any slot"] },
	Slot("head", { "INVTYPE_HEAD" }, L["Head"]),
	Slot("neck", { "INVTYPE_NECK" }, L["Neck"]),
	Slot("shoulder", { "INVTYPE_SHOULDER" }, L["Shoulder"]),
	Slot("back", { "INVTYPE_CLOAK" }, L["Back"]),
	Slot("chest", { "INVTYPE_CHEST", "INVTYPE_ROBE" }, L["Chest"]),
	Slot("wrist", { "INVTYPE_WRIST" }, L["Wrist"]),
	Slot("hands", { "INVTYPE_HAND" }, L["Hands"]),
	Slot("waist", { "INVTYPE_WAIST" }, L["Waist"]),
	Slot("legs", { "INVTYPE_LEGS" }, L["Legs"]),
	Slot("feet", { "INVTYPE_FEET" }, L["Feet"]),
	Slot("finger", { "INVTYPE_FINGER" }, L["Finger"]),
	Slot("trinket", { "INVTYPE_TRINKET" }, L["Trinket"]),
	Slot("onehand", { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" }, L["One-Hand"]),
	Slot("twohand", { "INVTYPE_2HWEAPON" }, L["Two-Hand"]),
	Slot("offhand", { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" }, L["Off Hand"]),
	Slot("ranged", { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" }, L["Ranged"]),
	Slot("bag", { "INVTYPE_BAG", "INVTYPE_QUIVER" }, L["Bag"]),
	{ value = "other", text = L["Not equipment"], none = true },
}

local function Type(value, classID, subClassID, fallback)
	return { value = value, classID = classID, subClassID = subClassID, fallback = fallback }
end

Items.TYPES = {
	{ value = "any", text = L["Any type"] },
	Type("cloth", ARMOR, 1, L["Cloth"]),
	Type("leather", ARMOR, 2, L["Leather"]),
	Type("mail", ARMOR, 3, L["Mail"]),
	Type("plate", ARMOR, 4, L["Plate"]),
	Type("shield", ARMOR, 6, L["Shields"]),
	Type("axe1", WEAPON, 0, L["One-Handed Axes"]),
	Type("axe2", WEAPON, 1, L["Two-Handed Axes"]),
	Type("mace1", WEAPON, 4, L["One-Handed Maces"]),
	Type("mace2", WEAPON, 5, L["Two-Handed Maces"]),
	Type("sword1", WEAPON, 7, L["One-Handed Swords"]),
	Type("sword2", WEAPON, 8, L["Two-Handed Swords"]),
	Type("dagger", WEAPON, 15, L["Daggers"]),
	Type("fist", WEAPON, 13, L["Fist Weapons"]),
	Type("polearm", WEAPON, 6, L["Polearms"]),
	Type("staff", WEAPON, 10, L["Staves"]),
	Type("bow", WEAPON, 2, L["Bows"]),
	Type("crossbow", WEAPON, 18, L["Crossbows"]),
	Type("gun", WEAPON, 3, L["Guns"]),
	Type("thrown", WEAPON, 16, L["Thrown"]),
	Type("wand", WEAPON, 19, L["Wands"]),
	Type("libram", ARMOR, 7, L["Librams"]),
	Type("idol", ARMOR, 8, L["Idols"]),
	Type("totem", ARMOR, 9, L["Totems"]),
}

-- The game's own names, once it is running.
function Items.TypeName(entry)
	if entry.text then
		return entry.text
	end
	return C.SubClassName(entry.classID, entry.subClassID) or entry.fallback
end

-- Stats in the order the dropdown lists them first; any other stat found on
-- the rewards follows, named as the game names it.
local STAT_ORDER = {
	"ITEM_MOD_STRENGTH_SHORT",
	"ITEM_MOD_AGILITY_SHORT",
	"ITEM_MOD_STAMINA_SHORT",
	"ITEM_MOD_INTELLECT_SHORT",
	"ITEM_MOD_SPIRIT_SHORT",
	"RESISTANCE0_NAME",
}

function Items.StatName(key)
	local name = _G[key]
	if type(name) == "string" and name ~= "" then
		return (name:gsub("%%s", ""):gsub("^%s*[%+%-]?%s*", ""))
	end
	return (key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower())
end

-- The stats dropdown: the main stats, then every other stat seen so far.
function Items.StatChoices()
	local choices = { { value = "any", text = L["Any stat"] } }
	local listed = {}
	for _, key in ipairs(STAT_ORDER) do
		choices[#choices + 1] = { value = key, text = Items.StatName(key) }
		listed[key] = true
	end
	local others = {}
	for _, item in pairs(info) do
		for key in pairs(item.stats or {}) do
			if not listed[key] then
				listed[key] = true
				others[#others + 1] = { value = key, text = Items.StatName(key) }
			end
		end
	end
	sort(others, function(a, b)
		return a.text < b.text
	end)
	for _, choice in ipairs(others) do
		choices[#choices + 1] = choice
	end
	return choices
end

local function Find(list, value)
	for _, entry in ipairs(list) do
		if entry.value == value then
			return entry
		end
	end
	return nil
end

local function SlotMatches(slot, equipLoc)
	if not slot or slot.value == "any" then
		return true
	end
	if slot.none then
		return equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" or equipLoc == "INVTYPE_NON_EQUIP"
	end
	for _, loc in ipairs(slot.locs) do
		if loc == equipLoc then
			return true
		end
	end
	return false
end

-- Which quests a reward can come from (the quests filter):
--   now    quests the character can do now, or by doing a chain it can do
--          now (Status.Reachable)
--   still  quests it can still do one day
--   all    any quest
Items.QUEST_MODES = {
	{ value = "now", text = L["Can do now, or by a chain"],
		tooltip = L["Quests you can take now or have taken, and quests that only wait for the quests before them in a chain you can do now."] },
	{ value = "still", text = L["Can still do"],
		tooltip = L["Every quest you have not done and can still take one day, at any level."] },
	{ value = "all", text = L["Any quest"], tooltip = L["Quests you have done, or can no longer take, too."] },
}

local function QuestCounts(questID, mode)
	if mode == "all" then
		return true
	end
	if not ns.Catalog.kept[questID] then
		return false
	end
	if mode == "now" then
		return Status.Reachable(questID)
	end
	return Status.Open(questID)
end

local function ReqLevel(questID)
	local quest = Data.Basics(questID)
	return quest and quest.reqLevel or 0
end

-- A result's quests: those the character can do now first, then by level.
local function QuestOrder(a, b)
	local ra, rb = Status.Reachable(a), Status.Reachable(b)
	if ra ~= rb then
		return ra
	end
	local la, lb = ReqLevel(a), ReqLevel(b)
	if la ~= lb then
		return la < lb
	end
	return a < b
end

-- The reward search. filters: slot, type, stat (values from the lists
-- above), usable, quests (a QUEST_MODES value), maxLevel, quality, text, sort.
-- Returns the matching items as { id, item (details), quests, level }, and how
-- many items may match but are still being fetched from the server. level is
-- the level the character can have the item at: the level it needs, or the
-- level its quest needs, whichever is higher.
function Items.Search(filters)
	local all = Items.All()
	local slot = Find(Items.SLOTS, filters.slot)
	local kind = Find(Items.TYPES, filters.type)
	local classFile = Player.classFile
	local maxLevel = filters.maxLevel or 0
	local text = filters.text and filters.text ~= "" and lower(filters.text) or nil
	local results, waiting = {}, 0

	for itemID, quests in pairs(all) do
		local equipLoc, classID, subClassID = Items.Basic(itemID)
		local keep = SlotMatches(slot, equipLoc)
			and (not kind or kind.value == "any" or (kind.classID == classID and kind.subClassID == subClassID))
		if keep and filters.usable then
			-- Worked out again below, with the level the item can be had at.
			keep = Items.Usable(classFile, classID, subClassID, 60)
		end
		local from
		if keep then
			from = {}
			for _, questID in ipairs(quests) do
				if QuestCounts(questID, filters.quests or "all") and (maxLevel == 0 or ReqLevel(questID) <= maxLevel) then
					from[#from + 1] = questID
				end
			end
			keep = #from > 0
		end
		if keep then
			local item = Items.Info(itemID)
			if not item then
				if Fetching(itemID) then
					waiting = waiting + 1
				end
			else
				local questLevel
				for _, questID in ipairs(from) do
					questLevel = questLevel and min(questLevel, ReqLevel(questID)) or ReqLevel(questID)
				end
				local level = max(item.minLevel or 0, questLevel or 0)
				keep = (not filters.usable or Items.Usable(classFile, classID, subClassID, max(Player.level, level)))
					and (maxLevel == 0 or level <= maxLevel)
					and (item.quality or 1) >= (filters.quality or 0)
					and (filters.stat == "any" or (item.stats[filters.stat] or 0) > 0)
					and (not text or lower(item.name):find(text, 1, true) ~= nil)
				if keep then
					sort(from, QuestOrder)
					results[#results + 1] = { id = itemID, item = item, quests = from, level = level }
				end
			end
		end
	end

	local order = filters.sort or "level"
	local stat = filters.stat
	sort(results, function(a, b)
		local ia, ib = a.item, b.item
		if order == "stat" and stat ~= "any" then
			local sa, sb = ia.stats[stat] or 0, ib.stats[stat] or 0
			if sa ~= sb then
				return sa > sb
			end
		elseif order == "name" then
			if ia.name ~= ib.name then
				return ia.name < ib.name
			end
		elseif order == "reqlevel" then
			-- The soonest first.
			if a.level ~= b.level then
				return a.level < b.level
			end
		end
		if ia.level ~= ib.level then
			return ia.level > ib.level
		end
		if ia.name ~= ib.name then
			return ia.name < ib.name
		end
		return a.id < b.id
	end)
	return results, waiting
end

-- How many reward items there are, for the page's note.
function Items.Count()
	local count = 0
	for _ in pairs(Items.All()) do
		count = count + 1
	end
	return count
end

-- For tests.
function Items.Reset()
	fromDatabase, byItem, info, asked, queue = {}, nil, {}, {}, {}
	Items.ready, Items.scanning, ticking = false, false, false
end
