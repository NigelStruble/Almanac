-- Runs Almanac against the mock client in tests/mock_wow.lua, with a small
-- made-up QuestieDB, and then, if it is installed, against the real QuestieDB.
-- Usage, from the repository root:  lua5.1 tests/run_tests.lua

package.path = "tests/?.lua;" .. package.path
local Mock = require("mock_wow")
local RealQuestieDB = require("questiedb")

local ADDON_DIR = "Almanac"
local ADDON = "Almanac"
local passed, failed = 0, 0
local current

local function check(condition, message, ...)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print(("    FAIL [%s] " .. message):format(current, ...))
	end
	return condition
end

local function equal(actual, expected, what)
	return check(actual == expected, "%s: expected %s, got %s", what, tostring(expected), tostring(actual))
end

local function test(name, func)
	current = name
	local before = failed
	local ok, err = xpcall(func, debug.traceback)
	if not ok then
		failed = failed + 1
		print("    ERROR " .. tostring(err))
	end
	print(((ok and failed == before) and "ok     " or "FAILED ") .. name)
end

--------------------------------------------------------------------------------
-- A small world
--------------------------------------------------------------------------------

local ALLIANCE, HORDE = 77, 178

-- Quests as QuestieDB has them (only the fields that matter here).
local function Quest(name, zone, level, reqLevel, extra)
	local quest = { name = name, zoneOrSort = zone, questLevel = level, requiredLevel = reqLevel, requiredRaces = ALLIANCE }
	for key, value in pairs(extra or {}) do
		quest[key] = value
	end
	return quest
end

local function World()
	local quests = {
		-- Northshire Valley (9), a subzone of Elwynn Forest (12)
		[783] = Quest("A Threat Within", 9, 1, 1, { nextQuestInChain = 7 }),
		[7] = Quest("Kobold Camp Cleanup", 9, 2, 1, { preQuestSingle = { 783 } }),
		-- Elwynn Forest
		[11] = Quest("Riverpaw Gnoll Bounty", 12, 10, 6),
		[60] = Quest("Kobold Candles", 12, 7, 5),
		[1007] = Quest("Only for Beginners", 12, 5, 1, { requiredMaxLevel = 10 }),
		-- Westfall (40): the Defias Brotherhood, into the Deadmines (1581)
		[1002] = Quest("Report to Gryan Stoutmantle", 40, 14, 10, { breadcrumbForQuestId = 65 }),
		[65] = Quest("The Defias Brotherhood", 40, 18, 14, { nextQuestInChain = 132, startedBy = { { 234 } }, finishedBy = { { 234 } } }),
		[132] = Quest("The Defias Brotherhood", 40, 18, 14, { preQuestSingle = { 65 }, nextQuestInChain = 135 }),
		[135] = Quest("The Defias Brotherhood", 40, 18, 14, { preQuestSingle = { 132 }, nextQuestInChain = 141 }),
		[141] = Quest("The Defias Brotherhood", 40, 18, 14, { preQuestSingle = { 135 }, nextQuestInChain = 142 }),
		[142] = Quest("The Defias Brotherhood", 40, 18, 14, { preQuestSingle = { 141 }, nextQuestInChain = 155 }),
		[155] = Quest("The Defias Brotherhood", 40, 18, 14, { preQuestSingle = { 142 }, nextQuestInChain = 166 }),
		[166] = Quest("The Defias Brotherhood", 1581, 22, 16, { preQuestSingle = { 155 } }),
		[214] = Quest("Red Silk Bandanas", 1581, 17, 14, { preQuestSingle = { 155 } }),
		[167] = Quest("Oh Brother. . .", 1581, 20, 15),
		[168] = Quest("Collecting Memories", 10029, 18, 15), -- filed under another Deadmines area
		[36] = Quest("Westfall Stew", 40, 14, 9),
		[22] = Quest("Goretusk Liver Pie", 40, 12, 9),
		[1000] = Quest("The Farmer's Choice", 40, 15, 10, { exclusiveTo = { 1001 } }),
		[1001] = Quest("The Other Choice", 40, 15, 10, { exclusiveTo = { 1000 } }),
		[1003] = Quest("For Humans Only", 40, 10, 5, { requiredRaces = 1 }),
		[1004] = Quest("For Dwarves Only", 40, 10, 5, { requiredRaces = 4 }),
		[1005] = Quest("A Horde Errand", 40, 15, 10, { requiredRaces = HORDE }),
		[1006] = Quest("Friends of Stormwind", 40, 15, 10, { requiredMinRep = { 72, 3000 } }),
		[1008] = Quest("Harvest Again", 40, 15, 10, { specialFlags = 1 }),
		-- A long chain in Elwynn Forest that ends in Stormwind City (1519)
		[3001] = Quest("The Long Road", 12, 5, 1),
		[3002] = Quest("The Long Road", 12, 5, 1, { preQuestSingle = { 3001 } }),
		[3003] = Quest("The Long Road", 12, 6, 1, { preQuestSingle = { 3002 } }),
		[3004] = Quest("The Long Road", 12, 6, 1, { preQuestSingle = { 3003 } }),
		[3005] = Quest("The Long Road", 12, 7, 1, { preQuestSingle = { 3004 } }),
		[3006] = Quest("The Long Road", 12, 7, 1, { preQuestSingle = { 3005 } }),
		[3007] = Quest("The Long Road", 12, 8, 1, { preQuestSingle = { 3006 } }),
		[3008] = Quest("The Long Road", 12, 9, 1, { preQuestSingle = { 3007 } }),
		[3009] = Quest("The Long Road", 1519, 10, 5, { preQuestSingle = { 3008 } }),
		-- Wailing Caverns (718), and a Horde quest there
		[1486] = Quest("Deviate Hides", 718, 17, 13, { requiredRaces = 0 }),
		[914] = Quest("Leaders of the Fang", 718, 22, 11, { requiredRaces = HORDE }),
		-- Categories: mage and warrior quests, tailoring, the Darkmoon Faire
		[1860] = Quest("Speak with Jennea", -161, 10, 10, { requiredClasses = 128 }),
		[1638] = Quest("A Warrior's Training", -81, 10, 10, { requiredClasses = 1 }),
		[5000] = Quest("Bolts of Cloth", -264, 20, 15, { requiredSkill = { 197, 75 } }),
		[7905] = Quest("Darkmoon Faire Games", -364, 1, 1, { requiredRaces = 0, specialFlags = 1 }),
	}
	return {
		quests = quests,
		xp = {
			[783] = { 1, 40 }, [7] = { 2, 170 }, [11] = { 10, 840 }, [60] = { 7, 420 }, [65] = { 18, 1350 },
			[132] = { 18, 680 }, [135] = { 18, 680 }, [141] = { 18, 340 }, [142] = { 18, 1350 }, [155] = { 18, 1700 },
			[166] = { 22, 2600 }, [214] = { 17, 1250 }, [167] = { 20, 1550 }, [168] = { 18, 1350 }, [36] = { 14, 1050 },
			[22] = { 12, 910 }, [1486] = { 17, 1600 }, [1860] = { 10, 100 }, [1002] = { 14, 210 },
		},
		dungeons = {
			[1581] = { "The Deadmines", { 10029 }, 40, { { 40, 42.5, 71.7 } } },
			[718] = { "Wailing Caverns", nil, 17, { { 17, 46, 36.5 } } },
			[2257] = { "Deeprun Tram", nil, 1519, {} },
		},
		subZonesSource = "{ [9] = 12 }",
		uiMapsSource = "{ [1429] = 12, [1436] = 40, [1426] = 1 }",
		instances = { [36] = 1581 },
		dbItems = {
			[2000] = { name = "Robe of Intellect", questRewards = { 166 }, class = 4, subClass = 1, itemLevel = 22, requiredLevel = 18 },
			[2001] = { name = "Chainmail Vest", questRewards = { 214 }, class = 4, subClass = 3, itemLevel = 20, requiredLevel = 17 },
			[2002] = { name = "Gnarled Staff", questRewards = { 1486 }, class = 2, subClass = 10, itemLevel = 18, requiredLevel = 12 },
			[2003] = { name = "Plate Helm", questRewards = { 1486 }, class = 4, subClass = 4, itemLevel = 50, requiredLevel = 45 },
			[2004] = { name = "Cloth Hood", questRewards = { 36 }, class = 4, subClass = 1, itemLevel = 14, requiredLevel = 10 },
			[2006] = { name = "Apprentice Gloves", questRewards = { 166 }, class = 4, subClass = 1, itemLevel = 12, requiredLevel = 5 },
		},
		npcs = {
			[234] = { name = "Gryan Stoutmantle", spawns = { [40] = { { 56.3, 47.5 } } }, zoneID = 40 },
		},
	}
end

local AREA_NAMES = {
	[12] = "Elwynn Forest", [9] = "Northshire Valley", [40] = "Westfall", [1581] = "The Deadmines",
	[718] = "Wailing Caverns", [17] = "The Barrens", [1519] = "Stormwind City", [1] = "Dun Morogh",
	[16919] = "The Hall of Thanes", [1537] = "Ironforge", [1497] = "Undercity",
}

-- Forever Dungeon Journal's data, as its ForeverDungeonJournal_NS global has
-- it: quests QuestieDB lacks (a new dungeon, a new Deadmines quest and the
-- chain before it), and one it has (Red Silk Bandanas), which is left alone.
local function Journal(env)
	local bullet = " \226\128\162 "
	env.ForeverDungeonJournal_NS = {
		DB = {
			["Hall of Thanes"] = {
				quests = {
					{ id = 96395, liveXPFallback = 3570, name = "An Ancient Grudge", level = 15, requires = 10, faction = "Both",
						pickup = "Ghostly Attendant, inside Hall of Thanes", turnin = "Ghostly Attendant, inside the dungeon",
						objective = "Put the spirit of Faldrim Anvilmar to rest.", rewardChoice = true,
						rewardItems = { { 279899, "Catacomb Cloak", 3 }, { 279900, "Deepgrave Trousers", 3 } },
						rewardSummary = "3,570 XP" },
					{ id = 96394, liveXPFallback = 3570, name = "The Restless Dead", level = 15, requires = 10, faction = "Alliance",
						rewardItems = {}, rewardSummary = "3,570 XP" .. bullet .. "7s" .. bullet .. "Ironforge +100" },
					{ id = 96393, liveXPFallback = 4930, name = "Old Ironforge Incursion", level = 16, requires = 9,
						faction = "Alliance", rewardItems = {}, rewardSummary = "4,930 XP" .. bullet .. "8s" },
				},
			},
			["The Deadmines"] = {
				quests = {
					{ id = 214, liveXPFallback = 4688, name = "Red Silk Bandanas", level = 17, requires = 14, faction = "Alliance",
						rewardItems = {} },
					{ id = 92753, liveXPFallback = 4050, name = "Destruction in Deadmines", level = 18, requires = 9,
						faction = "Alliance", rewardItems = {}, rewardSummary = "Stormwind +50" },
				},
			},
			["Ruins of Lordaeron"] = {
				quests = {
					{ id = 97288, liveXPFallback = 5300, name = "Unending Torment", level = 21, requires = 16, faction = "Horde",
						rewardItems = {} },
				},
			},
		},
		QUEST_PREREQ_CHAINS = {
			[96393] = { { id = 96391, name = "Underground Map" } },
			[92753] = {
				{ id = 92742, name = "Testing the Wells" },
				{ id = 92748, name = "Explosive Consultation" },
				{ id = 92749, name = "A Dynamite Plan" },
				{ id = 92753, name = "Destruction in Deadmines" },
				{ id = 92819, name = "Destruction in Deadmines" },
			},
			[214] = { { id = 65, name = "The Defias Brotherhood" }, { id = 155, name = "The Defias Brotherhood" } },
		},
		QUEST_PREREQ_DETAILS = {
			[96391] = { level = 15, requires = 9, pickup = "Dark Iron Map", map = { mapID = 1426, x = 0.77, y = 0.6 } },
			[92742] = { level = 12, requires = 9, pickup = "Alba Fairmoon, Sentinel Hill inn, Westfall",
				turnin = "Alba Fairmoon, Sentinel Hill inn, Westfall", map = { mapID = 1436, x = 0.53, y = 0.533 } },
			[92748] = { level = 16, requires = 9, map = { mapID = 1436, x = 0.53, y = 0.533 } },
			[92749] = { level = 16, requires = 9, pickup = "Sprite Jumpsprocket, Dwarven District, Stormwind" },
			[92819] = { level = 18, requires = 9, map = { mapID = 1436, x = 0.53, y = 0.533 } },
		},
		FOREVER_QUEST_XP_FALLBACK = { [96391] = 1050, [92742] = 460, [92749] = 580, [92819] = 680 },
		PREREQ_REWARD_MONEY_FALLBACK = { [96391] = 700, [92742] = 250 },
		QUEST_START_MAPS = {
			[96395] = { mapID = 1426, x = 0.305, y = 0.42, label = "Ghostly Attendant" },
			[214] = { mapID = 1436, x = 0.5667, y = 0.4735, label = "Scout Riell" },
		},
	}
end

-- The client's items.
local ITEMS = {
	[2000] = { name = "Robe of Intellect", classID = 4, subClassID = 1, equipLoc = "INVTYPE_ROBE", level = 22, minLevel = 18,
		stats = { ITEM_MOD_INTELLECT_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3, RESISTANCE0_NAME = 40 } },
	[2001] = { name = "Chainmail Vest", classID = 4, subClassID = 3, equipLoc = "INVTYPE_CHEST", level = 20, minLevel = 17,
		stats = { ITEM_MOD_STRENGTH_SHORT = 4 } },
	[2002] = { name = "Gnarled Staff", classID = 2, subClassID = 10, equipLoc = "INVTYPE_2HWEAPON", level = 18, minLevel = 12,
		stats = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 2 } },
	[2003] = { name = "Plate Helm", classID = 4, subClassID = 4, equipLoc = "INVTYPE_HEAD", level = 50, minLevel = 45, stats = {} },
	[2004] = { name = "Cloth Hood", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HEAD", level = 14, minLevel = 10,
		stats = { ITEM_MOD_INTELLECT_SHORT = 2 } },
	[2005] = { name = "Forever Hammer", classID = 2, subClassID = 4, equipLoc = "INVTYPE_WEAPON", level = 19, minLevel = 13,
		stats = { ITEM_MOD_STRENGTH_SHORT = 3 } },
	-- Needs level 5, but its quest (166) needs 16.
	[2006] = { name = "Apprentice Gloves", classID = 4, subClassID = 1, equipLoc = "INVTYPE_HAND", level = 12, minLevel = 5,
		stats = { ITEM_MOD_INTELLECT_SHORT = 1 } },
	-- Rewards of a Forever quest QuestieDB does not have.
	[279899] = { name = "Catacomb Cloak", classID = 4, subClassID = 1, equipLoc = "INVTYPE_CLOAK", level = 18, minLevel = 10,
		stats = { ITEM_MOD_INTELLECT_SHORT = 3 } },
	[279900] = { name = "Deepgrave Trousers", classID = 4, subClassID = 2, equipLoc = "INVTYPE_LEGS", level = 18, minLevel = 10,
		stats = { ITEM_MOD_AGILITY_SHORT = 3 } },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- options.forever keeps Almanac's list of Forever's new quests
-- (ForeverQuests.lua); the other tests leave it out of their small world.
local function Start(setup, options)
	local env, state = Mock.New(options)
	state.areaNames = AREA_NAMES
	for id, item in pairs(ITEMS) do
		state.items[id] = item
	end
	env.LibQuestieDB = Mock.QuestieDB(World())
	if setup then
		setup(env, state)
	end
	env.AlmanacDB = state.saved
	local ns = Mock.LoadAddon(env, state, ADDON_DIR, ADDON)
	if not (options and options.forever) then
		ns.ForeverQuests.quests = {}
	end
	Mock.Fire(state, "ADDON_LOADED", ADDON)
	Mock.Fire(state, "PLAYER_LOGIN")
	Mock.Fire(state, "PLAYER_ENTERING_WORLD", true, false)
	Mock.Advance(state, 1)
	return { env = env, state = state, ns = ns }
end

local function NoErrors(client)
	for _, err in ipairs(client.state.errors) do
		print("    Lua error: " .. err)
	end
	check(#client.state.errors == 0, "%d Lua error(s)", #client.state.errors)
	client.state.errors = {}
end

-- Opens the window and waits for the quest list to be built.
local function Open(client, what)
	client.env.SlashCmdList.ALMANAC(what or "")
	Mock.Advance(client.state, 1)
	return client.ns.Window.Frame()
end

local function Contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function Ids(list)
	local out = {}
	for i, id in ipairs(list) do
		out[i] = tostring(id)
	end
	return table.concat(out, ",")
end

-- The rows a quest page shows, as text: "section Available  (2)",
-- "chain X", "quest 65", "text None".
local function PageRows(page)
	local rows = {}
	for kind, pool in pairs(page.pools) do
		for _, row in ipairs(pool.used) do
			local _, _, _, _, y = row:GetPoint(1)
			local text
			if kind == "quest" then
				text = "quest " .. row.questID
			elseif kind == "section" then
				text = "section " .. Mock.Plain(row.title:GetText())
			elseif kind == "chain" then
				text = "chain " .. row.chain.name
			elseif kind == "context" then
				text = "context " .. row.text:GetText()
			else
				text = "text " .. (row.text:GetText() or "")
			end
			rows[#rows + 1] = { y = -y, text = text, row = row }
		end
	end
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	return rows
end

local function RowText(page)
	local out = {}
	for i, row in ipairs(PageRows(page)) do
		out[i] = row.text
	end
	return table.concat(out, " | ")
end

local function FindRow(page, text)
	for _, row in ipairs(PageRows(page)) do
		if row.text == text then
			return row.row
		end
	end
end

--------------------------------------------------------------------------------
-- The quest list
--------------------------------------------------------------------------------

test("loads, opens and builds the quest list without errors", function()
	local client = Start()
	NoErrors(client)
	local frame = Open(client)
	NoErrors(client)
	local Catalog = client.ns.Catalog
	check(frame and frame:IsShown(), "the window is open")
	check(Catalog.ready, "the quest list is built")
	equal(client.state.chat[1], nil, "nothing printed at login")
end)

test("zones: continents, subzones, dungeons and categories", function()
	local client = Start()
	Open(client)
	local Catalog = client.ns.Catalog
	local elwynn = Catalog.zones[12]
	check(elwynn and Contains(elwynn.quests, 783) and Contains(elwynn.quests, 7), "Northshire's quests are listed under Elwynn Forest")
	equal(elwynn and elwynn.group, "ek", "Elwynn Forest is in the Eastern Kingdoms")
	equal(elwynn and elwynn.name, "Elwynn Forest", "zone name from the client")
	local deadmines = Catalog.zones[1581]
	equal(deadmines and deadmines.group, "dungeon", "the Deadmines are a dungeon")
	check(deadmines and Contains(deadmines.quests, 168), "a quest filed under another Deadmines area is listed there")
	equal(deadmines and #deadmines.quests, 4, "the Deadmines' quests")
	local wc = Catalog.zones[718]
	equal(wc and Ids(wc.quests), "1486", "the Horde's Wailing Caverns quest is left out")
	check(Catalog.zones[-161] and not Catalog.zones[-81], "the mage's class quests are listed, the warrior's not")
	equal(Catalog.zones[-161] and Catalog.zones[-161].name, "Mage", "class category name")
	equal(Catalog.zones[-364] and Catalog.zones[-364].group, "event", "the Darkmoon Faire is a world event")
	local westfall = Catalog.zones[40]
	check(Contains(westfall.quests, 1003), "a Human's own race quest is listed")
	check(not Contains(westfall.quests, 1004), "a Dwarf quest is left out")
	check(not Contains(westfall.quests, 1005), "a Horde quest is left out")
	local order = {}
	for _, group in ipairs(Catalog.groups) do
		order[#order + 1] = group.key
	end
	equal(table.concat(order, ","), "ek,dungeon,class,profession,event", "groups, in order")
	equal(Catalog.groups[1].zones[1].key, 12, "zones by level: Elwynn before Westfall")
	NoErrors(client)
end)

test("chains: the Defias Brotherhood from the breadcrumb to the Deadmines", function()
	local client = Start()
	Open(client)
	local Catalog = client.ns.Catalog
	local chain = Catalog.chainOf[65]
	check(chain ~= nil, "65 is in a chain")
	check(chain == Catalog.chainOf[166] and chain == Catalog.chainOf[214] and chain == Catalog.chainOf[1002],
		"the chain reaches into the Deadmines and back to the breadcrumb")
	equal(chain and Ids(chain.quests), "1002,65,132,135,141,142,155,214,166", "steps in order, level breaking ties")
	equal(chain and chain.name, "The Defias Brotherhood", "named after the name most steps share")
	check(chain and chain.zones[40] and chain.zones[1581], "the chain is in Westfall and the Deadmines")
	equal(chain and chain.depth[166], 7, "166 is seven steps in")
	check(Catalog.chainOf[783] == Catalog.chainOf[7] and Catalog.chainOf[7] ~= nil, "Northshire's two quests chain")
	check(Catalog.chainOf[36] == nil, "a quest on its own is in no chain")
	local step, steps = Catalog.Step(166)
	equal(step .. "/" .. steps, "9/9", "the last step")
end)

--------------------------------------------------------------------------------
-- What the character can take
--------------------------------------------------------------------------------

test("status: done, in the log, not yet, no longer", function()
	local client = Start(function(env, state)
		state.completed[65] = true
		state.completed[1000] = true
		state.log = { { id = 132, complete = false }, { id = 36, complete = true } }
	end)
	Open(client)
	local Status = client.ns.Status
	equal((Status.Of(65)), "done", "turned in")
	equal((Status.Of(132)), "active", "in the log")
	equal((Status.Of(36)), "ready", "in the log and complete")
	local state, reasons = Status.Of(135)
	equal(state, "later", "the next step waits for the one before")
	equal(reasons and reasons[1].kind, "after", "why")
	equal(Status.ReasonText(reasons[1]), "After The Defias Brotherhood", "reason text")
	equal((Status.Of(1002)), "blocked", "a breadcrumb to a quest already done is gone")
	equal((Status.Of(1001)), "blocked", "the other choice is ruled out")
	equal(select(2, Status.Of(1001))[1].kind, "exclusive", "ruled out by the choice made")
	equal((Status.Of(1007)), "blocked", "too high a level for it")
	equal((Status.Of(166)), "later", "not before level 16 and the chain")
	equal((Status.Of(22)), "available", "can be taken")
	equal((Status.Of(7905)), "event", "out of season without Questie")
	equal(Status.Category(7905), "unavailable", "event quests are unavailable")
	equal((Status.Of(1008)), "available", "repeatable")
	NoErrors(client)
end)

test("status: level, reputation and profession requirements", function()
	local client = Start(nil, { player = { level = 12, race = 1, class = "MAGE", classID = 8, faction = "Alliance" } })
	Open(client)
	local ns, state = client.ns, client.state
	local status, reasons = ns.Status.Of(65)
	equal(status, "later", "level 12 is too low for 65")
	equal(ns.Status.ReasonText(reasons[1]), "Requires level 14", "says the level")
	status, reasons = ns.Status.Of(1006)
	equal(status, "later", "not friendly with Stormwind yet")
	equal(ns.Status.ReasonText(reasons[1]), "Requires Friendly with Faction 72", "says the reputation")
	status, reasons = ns.Status.Of(5000)
	equal(ns.Status.ReasonText(reasons[#reasons]), "Requires Tailoring (75)", "says the profession")
	state.reps[72] = 3500
	state.professions[1] = { name = "Tailoring", rank = 80, skillLine = 197 }
	state.player.level = 16
	client.env.SlashCmdList.ALMANAC("")
	client.env.SlashCmdList.ALMANAC("")
	Mock.Advance(state, 1)
	equal((ns.Status.Of(1006)), "available", "friendly now")
	equal((ns.Status.Of(5000)), "available", "tailoring 80 now")
	equal((ns.Status.Of(65)), "available", "level 16 now")
	NoErrors(client)
end)

test("status: turning a quest in moves the chain along", function()
	local client = Start()
	Open(client)
	local ns, state = client.ns, client.state
	equal((ns.Status.Of(65)), "available", "the first step")
	state.completed[65] = true
	Mock.Fire(state, "QUEST_TURNED_IN", 65, 1350, 0)
	Mock.Advance(state, 1)
	equal((ns.Status.Of(65)), "done", "done")
	equal((ns.Status.Of(132)), "available", "the next step opens")
	equal((ns.Status.Of(1002)), "blocked", "the breadcrumb goes")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- XP and money
--------------------------------------------------------------------------------

test("XP: full up to five levels above the quest, then less", function()
	local client = Start()
	local Rewards = client.ns.Rewards
	equal(Rewards.Reduce(1350, 18, 20), 1350, "two levels above")
	equal(Rewards.Reduce(1350, 18, 23), 1350, "five levels above")
	equal(Rewards.Reduce(1350, 18, 24), 1080, "six: 80%")
	equal(Rewards.Reduce(1350, 18, 25), 810, "seven: 60%")
	equal(Rewards.Reduce(1350, 18, 26), 540, "eight: 40%")
	equal(Rewards.Reduce(1350, 18, 27), 270, "nine: 20%")
	equal(Rewards.Reduce(1350, 18, 28), 135, "ten: 10%")
	equal(Rewards.Reduce(1350, 18, 45), 135, "far above: 10%")
	equal(Rewards.Reduce(1350, 18, 5), 1350, "below the quest: all of it")
	equal((Rewards.FullXP(65)), 1350, "the database's XP")
	equal(select(2, Rewards.FullXP(65)), "database", "from the database")
	client.state.player.level = 25
	client.ns.Player.Read()
	equal(Rewards.XP(65), 810, "a level 25 gets 60%")
	client.state.player.level = 60
	client.ns.Player.Read()
	equal(Rewards.XP(65), 0, "no XP at the highest level")
	NoErrors(client)
end)

test("rewards: what the client lists, and what quests really gave", function()
	local client = Start(function(env, state)
		state.quests[36] = { title = "Westfall Stew", xp = 1050, money = 600 }
		state.quests[65] = { title = "The Defias Brotherhood", xp = 1350, money = 0 }
		state.quests[1486] = { title = "Deviate Hides", xp = 1600, money = 1100, choice = { 2002, 2005 } }
	end)
	local ns, state = client.ns, client.state
	local Rewards = ns.Rewards
	equal(Rewards.Money(36), nil, "money is not known before the client lists it")
	Rewards.Want({ 36, 65, 1486, 99999 })
	Mock.Advance(state, 2)
	equal(Rewards.Money(36), 600, "the client's money")
	equal(select(2, Rewards.FullXP(36)), "database", "a level 20 is too high for the client's XP of a level 14 quest to be its full XP")
	equal(select(2, Rewards.FullXP(65)), "client", "the client's XP of a level 18 quest is")
	equal(Rewards.Money(65), 0, "a quest the client lists with XP but no money gives none")
	equal(Rewards.Money(99999), nil, "a quest the client does not know stays unknown")
	local _, choice, source = Rewards.Items(1486)
	equal(source, "client", "the client's reward list")
	equal(#choice, 2, "two to choose from")
	equal(choice[2] and choice[2][1], 2005, "an item only the client knows")
	check(not Contains(ns.Items.QuestsFor(2003), 1486), "the client's list replaces the database's")
	check(Contains(ns.Items.QuestsFor(2005), 1486), "and adds the new item")
	equal(Rewards.Pending(), 0, "nothing left to ask")

	-- The quest dialog is sure about money, even none.
	state.dialog = { questID = 65, xp = 1350, money = 0 }
	Mock.Fire(state, "QUEST_DETAIL")
	Mock.Advance(state, 1)
	equal(Rewards.Money(65), 0, "the dialog says it gives no money")

	-- Turned in: what it really gave, and what that says about the dungeon.
	Mock.Fire(state, "QUEST_TURNED_IN", 166, 9750, 4500)
	Mock.Advance(state, 1)
	equal((Rewards.FullXP(166)), 9750, "what it gave")
	equal(select(2, Rewards.FullXP(166)), "turnin", "seen at turn-in")
	equal(Rewards.Money(166), 4500, "and its money")
	local xp, estimated, ratio = Rewards.FullXP(214)
	equal(xp, 4688, "another Deadmines quest: 3.75 times its listed XP")
	equal(estimated, "estimate", "an estimate")
	equal(ratio, 3.75, "the ratio")
	equal((Rewards.FullXP(167)), 5813, "and another")
	equal((Rewards.FullXP(65)), 1350, "Westfall's quests are not changed")
	check(client.env.AlmanacDB.learned[166].xp == 9750, "saved")

	-- Too high a level to tell the full XP from what it gave.
	state.player.level = 30
	ns.Player.Read()
	Mock.Fire(state, "QUEST_TURNED_IN", 11, 84, 300)
	Mock.Advance(state, 1)
	equal((Rewards.FullXP(11)), 840, "a reduced turn-in is not taken as the full XP")
	equal(Rewards.Money(11), 300, "its money is")
	NoErrors(client)
end)

test("totals: a zone's XP and money", function()
	local client = Start(function(env, state)
		state.quests[36] = { xp = 1050, money = 600 }
		state.quests[22] = { xp = 910, money = 450 }
		state.questCached[36], state.questCached[22] = true, true
	end)
	Open(client)
	local Rewards = client.ns.Rewards
	Rewards.Want({ 36, 22 })
	local total = Rewards.Sum({ 36, 22, 1008 })
	equal(total.count, 2, "the repeatable quest is left out")
	equal(total.fullXP, 1960, "full XP")
	equal(total.money, 1050, "money")
	equal(total.noMoney, 0, "all money known")
	client.state.player.level = 19
	client.ns.Player.Read()
	total = Rewards.Sum({ 36, 22 })
	equal(total.xp, 910 * 0.6 + 1050, "at 19 the level 12 quest gives 60%")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Reward search
--------------------------------------------------------------------------------

local function Search(ns, filters)
	local base = { slot = "any", type = "any", stat = "any", usable = true, quests = "still", maxLevel = 0, quality = 0, sort = "level" }
	for key, value in pairs(filters) do
		base[key] = value
	end
	local results = ns.Items.Search(base)
	local ids = {}
	for i, result in ipairs(results) do
		ids[i] = result.id
	end
	return Ids(ids), results
end

-- Asks the client for every reward item and waits for them.
local function LoadItems(client)
	client.ns.Items.ScanNow()
	local _, waiting = client.ns.Items.Search({ slot = "any", type = "any", stat = "any", usable = false, quests = "all", maxLevel = 0, quality = 0 })
	Mock.Advance(client.state, 1)
	return waiting
end

test("reward search: a cloth chest with Intellect", function()
	local client = Start()
	Open(client)
	local ns, state = client.ns, client.state
	check(LoadItems(client) > 0, "items are fetched from the server first")
	local ids, results = Search(ns, { slot = "chest", type = "cloth", stat = "ITEM_MOD_INTELLECT_SHORT" })
	equal(ids, "2000", "the robe")
	equal(results[1] and results[1].quests[1], 166, "from The Defias Brotherhood")
	equal(results[1] and results[1].level, 18, "which needs level 18")
	equal((Search(ns, { slot = "chest" })), "2000", "a mage cannot wear the mail vest")
	equal((Search(ns, { slot = "chest", usable = false })), "2000,2001", "unless all are shown")
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT" })), "2000,2002,2004,2006", "everything with Intellect, by item level")
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", sort = "stat" })), "2000,2002,2004,2006", "most Intellect first")
	equal((Search(ns, { text = "staff" })), "2002", "by name")
	-- Once Westfall Stew is done, its hood is out of reach.
	state.completed[36] = true
	ns.Player.Read()
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT" })), "2000,2002,2006", "only quests that can still be done")
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", quests = "all" })), "2000,2002,2004,2006", "or any quest")
	NoErrors(client)
end)

test("reward search: the level the quest needs counts too", function()
	local client = Start()
	Open(client)
	local ns = client.ns
	LoadItems(client)
	-- The staff needs level 12, but its quest (Deviate Hides) 13; the gloves
	-- need 5, but their quest (The Defias Brotherhood) 16.
	equal((Search(ns, { maxLevel = 12 })), "2004", "up to level 12, only the hood")
	equal((Search(ns, { maxLevel = 13 })), "2002,2004", "up to 13, the staff too")
	local _, results = Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", sort = "reqlevel" })
	local levels = {}
	for i, result in ipairs(results) do
		levels[i] = result.id .. "@" .. result.level
	end
	equal(table.concat(levels, ","), "2004@10,2002@13,2006@16,2000@18", "the level each can be had at, lowest first")
	NoErrors(client)
end)

test("reward search: quests and chains you can do now", function()
	local client = Start(nil, { player = { level = 14, race = 1, class = "MAGE", classID = 8, faction = "Alliance" } })
	Open(client)
	local ns, state = client.ns, client.state
	LoadItems(client)
	-- At 14, The Defias Brotherhood's last step needs 16: its robe and gloves
	-- are for later.
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", quests = "now" })), "2002,2004", "at 14")
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", quests = "still" })), "2000,2002,2004,2006", "one day")
	state.player.level = 16
	ns.Player.Read()
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", quests = "now" })), "2000,2002,2004,2006",
		"at 16 the whole chain can be done, to its last step")
	-- A chain that cannot be started (its first step needs a level) is not one
	-- you can do now.
	state.player.level = 12
	ns.Player.Read()
	equal((Search(ns, { stat = "ITEM_MOD_INTELLECT_SHORT", quests = "now" })), "2004", "at 12")
	NoErrors(client)
end)

test("reward search: mail and plate from level 40", function()
	local client = Start(nil, { player = { level = 20, race = 1, class = "WARRIOR", classID = 1, faction = "Alliance" } })
	Open(client)
	local ns = client.ns
	LoadItems(client)
	check(ns.Items.Usable("WARRIOR", 4, 3, 20), "warriors wear mail from the start")
	check(not ns.Items.Usable("HUNTER", 4, 3, 20), "hunters not before 40")
	check(ns.Items.Usable("HUNTER", 4, 3, 40), "hunters from 40")
	check(not ns.Items.Usable("MAGE", 2, 8, 60), "mages cannot use two-handed swords")
	check(ns.Items.Usable("MAGE", 2, 10, 1), "mages can use staves")
	equal((Search(ns, { slot = "head" })), "2003,2004", "the plate helm needs level 45, when a warrior wears plate")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

test("window: a zone's sections, chains, and the chain page", function()
	local client = Start(function(env, state)
		state.completed[65] = true
		state.uiMap = 1436 -- Westfall
	end)
	local frame = Open(client)
	local page = frame.quests
	equal(page.kind, "zone", "a zone page")
	equal(page.zoneKey, 40, "opens on the character's zone")
	local rows = RowText(page)
	-- The chain is under way, so all of it is under Available: the step done,
	-- the next, those waiting for it, and its Deadmines quests, which count
	-- there too. The skipped breadcrumb is under Unavailable, and nothing is
	-- left for Completed.
	equal(rows, "section Available  (13)  2 in other zones | quest 1003 | quest 22 | quest 36 | quest 1000 | quest 1001"
		.. " | quest 1008 | chain The Defias Brotherhood | quest 65 | quest 132 | quest 135 | quest 141 | quest 142"
		.. " | quest 155 | quest 214 | quest 166 | section Unavailable  (2) | quest 1006 | chain The Defias Brotherhood"
		.. " | quest 1002 | section Completed  (0)", "Westfall's rows")
	check(page.title:GetText() == "Westfall", "title")
	check(Mock.Plain(page.counts:GetText()):find("Available 11     Unavailable 2     Completed 1", 1, true),
		"the header counts Westfall's quests, the done step as completed: %s", Mock.Plain(page.counts:GetText()))
	local more = Mock.Plain(page.more:GetText())
	check(more:find("With the chains' 2 quests in other zones: ", 1, true), "the header's line for the chains elsewhere: %s", more)
	-- Westfall's quests under Available give 6,710 XP; Red Silk Bandanas and
	-- The Defias Brotherhood in the Deadmines 3,850 more.
	local section = FindRow(page, "section Available  (13)  2 in other zones")
	local withDeadmines = Mock.Plain(section.total:GetText())
	check(withDeadmines:find("10,560 XP", 1, true), "the Available total counts the Deadmines quests: %s", withDeadmines)
	local deadmines = FindRow(page, "quest 166")
	equal(select(1, deadmines.name:GetTextColor()), 0.55, "a quest in another zone is greyed")
	check(Mock.Plain(deadmines.note:GetText()):find("The Deadmines", 1, true), "with its zone")
	local waiting = FindRow(page, "quest 135")
	check(Mock.Plain(waiting.note:GetText()):find("After The Defias Brotherhood", 1, true), "a waiting step says for what")

	-- Hovering a quest shows its tooltip.
	local row = FindRow(page, "quest 132")
	Mock.Enter(row)
	local tip = client.env.GameTooltip:Text()
	check(tip:find("The Defias Brotherhood", 1, true) and tip:find("XP | 680", 1, true), "quest tooltip: %s", tip)
	check(tip:find("Part 3 of 9", 1, true), "the step it is")

	-- The chain heading opens the whole chain; Back returns.
	Mock.Click(FindRow(page, "chain The Defias Brotherhood"))
	equal(page.kind, "chain", "the chain page")
	rows = RowText(page)
	check(rows:find("quest 166", 1, true) and rows:find("quest 65", 1, true), "every step: %s", rows)
	Mock.Click(page.back)
	equal(page.kind, "zone", "back to the zone")

	-- Unfolding Completed.
	Mock.Click(FindRow(page, "section Completed  (0)"))
	check(RowText(page):find("section Completed  (0) | text None", 1, true), "Completed unfolds: nothing there")
	NoErrors(client)
end)

test("chains: a dungeon's page leads back to the quests before it", function()
	local client = Start(function(env, state)
		state.completed[65] = true
	end)
	local frame = Open(client)
	frame.quests:ShowZone(1581)
	-- What can be taken now first, then the chain, whose Deadmines quests wait
	-- for its Westfall ones.
	equal(RowText(frame.quests), "section Available  (9)  5 in other zones | quest 168 | quest 167"
		.. " | chain The Defias Brotherhood | quest 65 | quest 132 | quest 135 | quest 141 | quest 142 | quest 155"
		.. " | quest 214 | quest 166 | section Unavailable  (0) | text None | section Completed  (0)", "the Deadmines' rows")
	local row = FindRow(frame.quests, "quest 132")
	check(Mock.Plain(row.note:GetText()):find("Westfall", 1, true), "Westfall's steps say where they are")
	NoErrors(client)
end)

test("chains: a step that needs a level goes under Unavailable", function()
	local client = Start(function(env, state)
		state.uiMap = 1436 -- Westfall
	end, { player = { level = 12, race = 1, class = "MAGE", classID = 8, faction = "Alliance" } })
	local frame = Open(client)
	local rows = RowText(frame.quests)
	check(rows:find("quest 36 | chain The Defias Brotherhood | quest 1002 | quest 1000", 1, true),
		"the breadcrumb can be taken: %s", rows)
	check(rows:find("section Unavailable  (9)  2 in other zones | quest 1006 | chain The Defias Brotherhood | quest 65"
		.. " | quest 132 | quest 135 | quest 141 | quest 142 | quest 155 | quest 214 | quest 166", 1, true),
		"the rest needs level 14: %s", rows)
	local row = FindRow(frame.quests, "quest 65")
	check(Mock.Plain(row.note:GetText()):find("Requires level 14", 1, true), "and says so")
	local Status = client.ns.Status
	check(Status.Reachable(1002) and not Status.Reachable(65) and not Status.Reachable(132), "reachable")
	equal(Status.Section(132), "unavailable", "132's section")
	NoErrors(client)
end)

test("chains: a long run of steps elsewhere is one line", function()
	local client = Start(function(env, state)
		state.completed[3001], state.completed[3002] = true, true
	end)
	local frame = Open(client)
	frame.quests:ShowZone(1519)
	equal(RowText(frame.quests), "section Available  (7)  6 in other zones | chain The Long Road"
		.. " | context 8 quests in Elwynn Forest, 2 done | quest 3009 | section Unavailable  (0) | text None"
		.. " | section Completed  (0)", "Stormwind's rows")
	Mock.Click(FindRow(frame.quests, "context 8 quests in Elwynn Forest, 2 done"))
	equal(frame.quests.kind, "chain", "a click shows the whole chain")
	-- Once all of it is done, it is all under Completed.
	for id = 3003, 3009 do
		client.state.completed[id] = true
	end
	client.ns.Player.Read()
	frame.quests:ShowZone(1519)
	equal(client.ns.Status.Section(3001), "completed", "a finished chain is completed")
	check(RowText(frame.quests):find("section Completed  (9)  8 in other zones", 1, true), "Stormwind's quest is completed")
	NoErrors(client)
end)

test("minimap button: opens the window, moves, and can be hidden", function()
	local client = Start()
	local env, state = client.env, client.state
	local button = env.AlmanacMinimapButton
	check(button ~= nil, "there is a minimap button")
	equal(button and button:GetParent(), env.Minimap, "on the minimap")
	check(button:IsShown(), "shown")
	Mock.Click(button, "LeftButton")
	Mock.Advance(state, 1)
	local frame = client.ns.Window.Frame()
	check(frame and frame:IsShown(), "a click opens the window")
	Mock.Click(button, "LeftButton")
	check(not frame:IsShown(), "and closes it")
	Mock.Click(button, "RightButton")
	equal(frame.mode, "options", "a right-click opens the options")
	-- Dragged to the top right of the minimap (its middle is at 170, 830).
	state.cursor = { 170 + 50, 830 + 50 }
	Mock.CallScript(button, "OnDragStart")
	Mock.Advance(state, 0.2)
	Mock.CallScript(button, "OnDragStop")
	equal(math.floor(env.AlmanacDB.settings.minimapAngle + 0.5), 45, "the angle is saved")
	local _, _, _, x, y = button:GetPoint(1)
	check(x > 0 and y > 0 and math.abs(x - y) < 0.01, "placed up and right: %s, %s", tostring(x), tostring(y))
	env.SlashCmdList.ALMANAC("minimap")
	check(not button:IsShown(), "/almanac minimap hides it")
	env.SlashCmdList.ALMANAC("minimap")
	check(button:IsShown(), "and shows it again")
	NoErrors(client)
end)

test("minimap button: shows the icon the .toc sets", function()
	local client = Start()
	local icon
	for line in io.lines(ADDON_DIR .. "/" .. ADDON .. ".toc") do
		icon = icon or line:match("^## IconTexture:%s*(.-)%s*$")
	end
	check(icon ~= nil, "the .toc sets an icon")
	equal(client.env.AlmanacMinimapButton.icon:GetTexture(), icon, "the button's icon")
	NoErrors(client)
end)

test("EllesmereUI's skin: the window has one close X", function()
	local skinned = {}
	local client = Start(function(env)
		env.EllesmereUI = {
			RegisterSkin = function(_, callback)
				callback({
					Shell = function(frame)
						skinned.shell = frame
					end,
					CloseButton = function(button)
						skinned.close = button
					end,
					EditBox = function() end,
					Button = function() end,
				})
			end,
		}
	end)
	local frame = Open(client)
	equal(skinned.shell, frame, "the window is skinned")
	equal(skinned.close, frame.close, "its close button too")
	equal(frame.close.text:GetText(), "", "which then shows only EllesmereUI's X")
	NoErrors(client)
end)

test("reasons: other factions, races and classes are named", function()
	local client = Start()
	client.ns.DB.Set("otherFaction", true)
	client.ns.DB.Set("otherClasses", true)
	Open(client)
	local Status = client.ns.Status
	equal(Status.Summary(1005), "Horde only", "a Horde quest")
	equal(Status.Summary(1004), "Dwarf only", "a Dwarf quest")
	equal(Status.Summary(1638), "Warrior only", "a warrior quest")
	NoErrors(client)
end)

test("window: the zone list and searching", function()
	local client = Start()
	local frame = Open(client)
	local list = frame.zoneList
	local names = {}
	for _, row in ipairs(list.zones.used) do
		names[#names + 1] = row.name:GetText()
	end
	check(table.concat(names, ","):find("Westfall", 1, true), "Westfall is listed")
	-- Picking a zone.
	for _, row in ipairs(list.zones.used) do
		if row.key == 1581 then
			Mock.Click(row)
		end
	end
	equal(frame.quests.zoneKey, 1581, "the Deadmines' page")
	check(RowText(frame.quests):find("quest 167", 1, true), "its quests")
	-- Typing searches quest names everywhere.
	Mock.Type(frame.search, "defias")
	Mock.Advance(client.state, 1)
	equal(frame.quests.kind, "search", "search results")
	local rows = RowText(frame.quests)
	check(rows:find("quest 65", 1, true) and rows:find("quest 166", 1, true), "found in two zones: %s", rows)
	-- Clicking a result goes to its zone, marked.
	Mock.Click(FindRow(frame.quests, "quest 166"))
	equal(frame.quests.kind, "zone", "a zone page")
	equal(frame.quests.zoneKey, 1581, "the quest's zone")
	equal(frame.quests.marked, 166, "the quest marked")
	NoErrors(client)
end)

test("window: the Rewards page", function()
	local client = Start()
	local frame = Open(client)
	Mock.Click(frame.tabs.rewards)
	Mock.Advance(client.state, 2)
	equal(frame.mode, "rewards", "the Rewards page")
	local page = frame.rewards
	check(#page.used > 0, "results are listed")
	-- A click on a result goes to its quest.
	local robe
	for _, row in ipairs(page.used) do
		if row.result.id == 2000 then
			robe = row
		end
	end
	check(robe ~= nil, "the robe is listed")
	if robe then
		Mock.Enter(robe)
		check(client.env.GameTooltip:Text():find("Rewarded by", 1, true), "its tooltip names the quest")
		Mock.Click(robe)
		equal(frame.mode, "quests", "back to the quests")
		equal(frame.quests.zoneKey, 1581, "the Deadmines")
		equal(frame.quests.marked, 166, "The Defias Brotherhood marked")
	end
	NoErrors(client)
end)

test("window: clearing the search, and a chain's step", function()
	local client = Start(function(env, state)
		state.uiMap = 1436 -- Westfall
	end)
	local frame = Open(client)
	Mock.Type(frame.search, "stew")
	Mock.Advance(client.state, 1)
	equal(frame.quests.kind, "search", "searching")
	Mock.CallScript(frame.search, "OnEscapePressed")
	equal(frame.quests.kind, "zone", "Escape goes back to the zone")
	equal(frame.quests.zoneKey, 40, "Westfall")
	equal(frame.search:GetText(), "", "and empties the box")
	-- On a chain's page, a step in another zone goes there.
	frame.quests:ShowChain(client.ns.Catalog.chainOf[65])
	Mock.Click(FindRow(frame.quests, "quest 214"))
	equal(frame.quests.kind, "zone", "a zone page")
	equal(frame.quests.zoneKey, 1581, "the Deadmines")
	equal(frame.quests.marked, 214, "the step marked")
	Mock.Click(frame.quests.back)
	equal(frame.quests.kind, "chain", "back to the chain")
	NoErrors(client)
end)

test("window: shift-click puts a quest or its reward in the chat box", function()
	local client = Start(function(env, state)
		state.log = { { id = 132, complete = false } }
		state.completed[65] = true
		state.uiMap = 1436 -- Westfall
	end)
	local frame = Open(client)
	local state = client.state
	LoadItems(client)
	frame.quests:ShowZone(40)
	state.shift = true
	-- No chat box open: nothing to put it in, and it says so.
	Mock.Click(FindRow(frame.quests, "quest 36"))
	equal(#state.linked, 0, "nothing linked without a chat box")
	check(table.concat(state.chat, "\n"):find("Open the chat box first", 1, true), "it says to open one")
	equal(frame.quests.kind, "zone", "and does not go anywhere")
	-- A quest the game will not link (not in the log) goes as its name and ID,
	-- which Questie turns into a link; one in the log as the game's link.
	state.chatOpen = true
	Mock.Click(FindRow(frame.quests, "quest 36"))
	equal(state.linked[1], "[Westfall Stew (36)]", "a quest not in the log")
	Mock.Click(FindRow(frame.quests, "quest 132"))
	equal(state.linked[2], "|cffffff00|Hquest:132:20|h[Quest 132]|h|r", "a quest in the log")
	-- Its reward.
	local row = FindRow(frame.quests, "quest 36")
	equal(row.rewards[1].itemID, 2004, "Westfall Stew's reward icon")
	Mock.Click(row.rewards[1])
	check(tostring(state.linked[3]):find("|Hitem:2004:", 1, true), "the reward's item link: %s", tostring(state.linked[3]))
	-- The game's new chat functions are enough, without the old name.
	client.env.ChatEdit_InsertLink = nil
	Mock.Click(FindRow(frame.quests, "quest 22"))
	equal(state.linked[4], "[Goretusk Liver Pie (22)]", "ChatFrameUtil.InsertLink alone")
	state.shift = false
	NoErrors(client)
end)

test("window: reopens on the character's new zone, else where it was left", function()
	local client = Start(function(env, state)
		state.uiMap = 1436 -- Westfall
	end)
	local frame = Open(client)
	equal(frame.quests.zoneKey, 40, "Westfall")
	frame.quests:ShowZone(1581)
	frame:Hide()
	Open(client)
	equal(frame.quests.zoneKey, 1581, "still in Westfall: where it was left")
	frame:Hide()
	client.state.uiMap = 1429 -- Elwynn Forest
	Open(client)
	equal(frame.quests.zoneKey, 12, "moved on: the new zone")
	frame:Hide()
	Open(client, "options")
	equal(frame.mode, "options", "/almanac options opens the options")
	NoErrors(client)
end)

test("Questie: the quests it hides, and world events in season", function()
	local client = Start(function(env)
		local modules = {
			QuestieCorrections = { hiddenQuests = { [22] = true, [36] = "HIDE_ON_MAP" } },
			QuestieEvent = {
				IsEventQuest = function(id)
					return id == 7905 or id == 1008
				end,
				activeQuests = { [7905] = true },
			},
		}
		env.QuestieLoader = {
			ImportModule = function(_, name)
				return modules[name]
			end,
		}
		env.Questie = {
			API = {
				isReady = true,
				RegisterOnReady = function(callback)
					callback()
				end,
			},
		}
	end)
	Open(client)
	local ns = client.ns
	local westfall = ns.Catalog.zones[40]
	check(not Contains(westfall.quests, 22), "a quest Questie hides is left out")
	check(Contains(westfall.quests, 36), "a quest Questie only keeps off the map is listed")
	equal((ns.Status.Of(7905)), "available", "the Darkmoon Faire is in town")
	equal((ns.Status.Of(1008)), "event", "an event quest out of season, filed under a zone")
	ns.DB.Set("showHidden", true)
	ns.Catalog.BuildNow()
	check(Contains(ns.Catalog.zones[40].quests, 22), "shown with the option")
	NoErrors(client)
end)

test("options: other factions' quests", function()
	local client = Start()
	local frame = Open(client, "options")
	equal(frame.mode, "options", "the Options page")
	client.ns.DB.Set("otherFaction", true)
	client.ns.Catalog.Build()
	Mock.Advance(client.state, 1)
	local westfall = client.ns.Catalog.zones[40]
	check(Contains(westfall.quests, 1005), "the Horde quest is listed")
	equal((client.ns.Status.Of(1005)), "other", "as not for this character")
	equal(rawget(client.env.AlmanacDB.settings, "otherFaction"), true, "saved")
	client.ns.DB.Set("otherFaction", false)
	equal(rawget(client.env.AlmanacDB.settings, "otherFaction"), nil, "a default is not saved")
	NoErrors(client)
end)

test("/almanac probe says what is known about a quest", function()
	local client = Start()
	client.env.SlashCmdList.ALMANAC("probe 65")
	local text = table.concat(client.state.chat, "\n")
	check(text:find("The Defias Brotherhood", 1, true), "names it: %s", text)
	check(text:find("asked for", 1, true), "asks the client for it")
	client.env.SlashCmdList.ALMANAC("help")
	check(table.concat(client.state.chat, "\n"):find("/almanac rewards", 1, true), "help lists the commands")
	NoErrors(client)
end)

test("without QuestieDB it says what is missing", function()
	local client = Start(function(env)
		env.LibQuestieDB = nil
	end)
	local text = table.concat(client.state.chat, "\n")
	check(text:find("QuestieDB", 1, true), "says QuestieDB is needed: %s", text)
	local frame = Open(client)
	check(frame.problem:IsShown(), "the window says so")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Forever Dungeon Journal
--------------------------------------------------------------------------------

local function Count(list, value)
	local n = 0
	for _, v in ipairs(list or {}) do
		if v == value then
			n = n + 1
		end
	end
	return n
end

test("Forever Dungeon Journal: money in its reward lines", function()
	local client = Start()
	local NewQuests = client.ns.NewQuests
	local bullet = " \226\128\162 "
	equal(NewQuests.ParseMoney("4,590 XP" .. bullet .. "7s" .. bullet .. "Gadgetzan +100"), 700, "7 silver")
	equal(NewQuests.ParseMoney("1g 5s 20c"), 10520, "gold, silver and copper")
	equal(NewQuests.ParseMoney("3,570 XP"), nil, "no money")
	equal(NewQuests.ParseMoney("Stormwind +50"), nil, "reputation is not money")
	equal(NewQuests.ParseMoney(nil), nil, "no line")
	equal(#NewQuests.Ids(), 0, "without the journal or Almanac's list, no new quests")
	NoErrors(client)
end)

test("Forever Dungeon Journal: the quests QuestieDB does not have yet", function()
	local client = Start(Journal)
	Open(client)
	local ns = client.ns
	local Catalog, Data, Status, Rewards = ns.Catalog, ns.Data, ns.Status, ns.Rewards
	local thanes = Catalog.zones[16919]
	equal(thanes and thanes.group, "dungeon", "Hall of Thanes is a dungeon")
	equal(thanes and thanes.name, "The Hall of Thanes", "by the client's name for it")
	equal(thanes and #thanes.quests, 3, "its quests")
	check(Contains(thanes and thanes.quests, 96395), "one for both factions")
	local deadmines = Catalog.zones[1581]
	check(Contains(deadmines.quests, 92753), "a new quest of an old dungeon is listed with the others")
	equal(#deadmines.quests, 5, "the Deadmines' quests")
	for _, id in ipairs({ 92742, 92748, 92749, 92819 }) do
		check(Contains(Catalog.zones[40].quests, id), "%d is in Westfall, where it starts or the one before it does", id)
	end
	check(Contains(Catalog.zones[1] and Catalog.zones[1].quests, 96391), "Underground Map is in Dun Morogh")
	check(Catalog.zones[16611] == nil, "the Horde's new dungeon is left out")
	equal(Count(Catalog.all, 214), 1, "a quest both have is listed once")
	equal(Data.Source(214), "questie", "from QuestieDB")
	equal((Rewards.FullXP(214)), 1250, "with QuestieDB's XP")
	equal(Data.Source(96395), "journal", "a quest only the journal has")

	-- Chains, through the journal's lists of the quests before a dungeon's.
	local chain = Catalog.chainOf[92753]
	equal(chain and Ids(chain.quests), "92742,92748,92749,92753,92819", "the chain into the Deadmines, in order")
	equal(chain and chain.name, "Testing the Wells", "named after its first quest, as no name is half of it")
	check(chain and chain.zones[40] and chain.zones[1581], "in Westfall and the Deadmines")
	check(Catalog.chainOf[96393] and Catalog.chainOf[96393] == Catalog.chainOf[96391],
		"a list that does not name its quest still leads to it")
	equal((Status.Of(92742)), "available", "the chain's first step")
	local state, reasons = Status.Of(92748)
	equal(state, "later", "the next waits")
	equal(reasons and Status.ReasonText(reasons[1]), "After Testing the Wells", "for the one before")
	equal(Status.Section(92753), "available", "a chain that can be started is all under Available")
	equal((Status.Of(96395)), "available", "Hall of Thanes' quest")

	-- XP, money and items.
	equal((Rewards.FullXP(96395)), 3570, "the XP the journal has seen it give")
	equal(select(2, Rewards.FullXP(96395)), "journal", "from the journal")
	equal((Rewards.FullXP(92749)), 580, "a quest before a dungeon's, from the journal's XP table")
	equal(Rewards.FullXP(92748), nil, "the journal does not know every quest's XP")
	equal(Rewards.Money(96394), 700, "7 silver")
	equal(Rewards.Money(96391), 700, "from the journal's money table")
	equal(Rewards.Money(96395), nil, "no money listed: not known yet")
	local fixed, choice, source = Rewards.Items(96395)
	equal(#fixed .. "/" .. #choice .. " " .. tostring(source), "0/2 journal", "two to choose from")
	equal(choice[1] and choice[1][1], 279899, "the cloak")

	-- Turned in, 166 gave 3.75 times its listed XP, and the Deadmines' other
	-- quests are estimated at that; the journal's quest says what it gives.
	Mock.Fire(client.state, "QUEST_TURNED_IN", 166, 9750, 4500)
	Mock.Advance(client.state, 1)
	equal(select(2, Rewards.FullXP(214)), "estimate", "QuestieDB's quest is estimated")
	equal((Rewards.FullXP(92753)), 4050, "the journal's is not")
	Mock.Fire(client.state, "QUEST_TURNED_IN", 92753, 4100, 0)
	Mock.Advance(client.state, 1)
	equal((Rewards.FullXP(92753)), 4100, "what it gave")
	equal((Rewards.FullXP(214)), 4688, "which does not change the estimate")
	NoErrors(client)
end)

test("Forever Dungeon Journal: factions, and a dungeon only it knows", function()
	local client = Start(function(env)
		Journal(env)
		env.ForeverDungeonJournal_NS.DB["Stonetalon Hideaway"] = {
			quests = { { id = 99001, name = "Into the Hideaway", level = 24, requires = 18, faction = "Both", rewardItems = {} } },
		}
	end, { player = { level = 20, race = 2, class = "WARRIOR", classID = 1, faction = "Horde" } })
	Open(client)
	local Catalog, Data = client.ns.Catalog, client.ns.Data
	local ruins = Catalog.zones[16611]
	equal(ruins and Ids(ruins.quests), "97288", "the Horde's new dungeon")
	equal(ruins and ruins.name, "Ruins of Lordaeron", "by the journal's name when the client has none")
	equal(Catalog.zones[16919] and Ids(Catalog.zones[16919].quests), "96395", "Hall of Thanes' quest for both factions")
	check(not Contains(Catalog.zones[1] and Catalog.zones[1].quests, 96391), "the map to an Alliance quest is the Alliance's")
	local hideaway = Catalog.zones[9000001]
	equal(hideaway and hideaway.name, "Stonetalon Hideaway", "a dungeon with no known area")
	equal(hideaway and hideaway.group, "dungeon", "is a dungeon")
	-- Inside a dungeon QuestieDB cannot place, it is found by its name.
	client.state.instance, client.state.instanceName = 2999, "Hall of Thanes"
	equal(Data.PlayerZoneKey(), 16919, "Hall of Thanes")
	client.state.instanceName = "Stonetalon Hideaway"
	equal(Data.PlayerZoneKey(), 9000001, "the dungeon only the journal knows")
	client.state.instanceName = "The Deadmines"
	equal(Data.PlayerZoneKey(), 1581, "and one QuestieDB knows")
	client.ns.DB.Set("otherFaction", true)
	client.ns.Catalog.BuildNow()
	check(Contains(Catalog.zones[16919].quests, 96394), "other factions' quests with the option")
	equal((client.ns.Status.Of(96394)), "other", "not for this character")
	NoErrors(client)
end)

test("Forever Dungeon Journal: its rewards, tooltips and /almanac probe", function()
	local client = Start(Journal)
	local frame = Open(client)
	local ns = client.ns
	LoadItems(client)
	local ids, results = Search(ns, { slot = "back" })
	equal(ids, "279899", "the cloak a mage can wear")
	equal(results[1] and results[1].quests[1], 96395, "from An Ancient Grudge")
	equal((Search(ns, { slot = "legs", usable = false })), "279900", "and the trousers")

	frame.quests:ShowZone(16919)
	Mock.Enter(FindRow(frame.quests, "quest 96395"))
	local tip = Mock.Plain(client.env.GameTooltip:Text())
	check(tip:find("Starts | Ghostly Attendant, inside Hall of Thanes, Dun Morogh (30.5, 42.0)", 1, true),
		"who starts it, and where: %s", tip)
	check(tip:find("Ends | Ghostly Attendant, inside the dungeon", 1, true), "who ends it")
	check(tip:find("3,570 (as Forever Dungeon Journal has it)", 1, true), "its XP")
	check(tip:find("Choose one of", 1, true), "its rewards")
	check(tip:find("Put the spirit of Faldrim Anvilmar to rest.", 1, true), "its objective")
	check(tip:find("QuestieDB does not have this quest yet", 1, true), "where it is from")

	client.env.SlashCmdList.ALMANAC("probe 96395")
	check(table.concat(client.state.chat, "\n"):find("(from Forever Dungeon Journal)", 1, true), "/almanac probe says so")
	NoErrors(client)
end)

test("Forever Dungeon Journal: only what Almanac's list lacks", function()
	local client = Start(function(env)
		Journal(env)
		local fdj = env.ForeverDungeonJournal_NS
		fdj.DB["Hall of Thanes"].quests[1].liveXPFallback = 3600
		fdj.DB["Stonetalon Hideaway"] = {
			quests = { { id = 99001, name = "Into the Hideaway", level = 24, requires = 18, faction = "Both", rewardItems = {} } },
		}
	end, { forever = true })
	Open(client)
	local ns = client.ns
	local Data = ns.Data
	equal(Data.Source(96395), "almanac", "Almanac's list comes first")
	equal((ns.Rewards.FullXP(96395)), 3570, "with its XP")
	equal(Data.Links(92748).preSingle[1], 92747, "and its chains")
	local journal = {}
	for _, id in ipairs(ns.NewQuests.Ids()) do
		if Data.Source(id) == "journal" then
			journal[#journal + 1] = id
		end
	end
	equal(Ids(journal), "99001", "the journal adds the quest the list lacks")
	local hideaway = ns.Catalog.zones[9000001]
	equal(hideaway and hideaway.name, "Stonetalon Hideaway", "in a dungeon only the journal knows")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- Almanac's own list of Forever's new quests
--------------------------------------------------------------------------------

-- What the game lists for two of them.
local function ForeverClient(_, state)
	state.quests[96394] = { title = "The Restless Dead", xp = 1050, money = 700 }
	state.quests[96395] = { title = "An Ancient Grudge", xp = 1050, choice = { 279899, 279900 } }
end

test("Forever's new quests: listed without Forever Dungeon Journal", function()
	local client = Start(ForeverClient, { forever = true })
	Open(client)
	local ns = client.ns
	local Catalog, Data, Status, Rewards = ns.Catalog, ns.Data, ns.Status, ns.Rewards
	local thanes = Catalog.zones[16919]
	equal(thanes and thanes.group, "dungeon", "The Hall of Thanes is a dungeon")
	equal(thanes and #thanes.quests, 5, "with five quests for the Alliance")
	local ruins = Catalog.zones[16611]
	equal(ruins and ruins.name, "Ruins of Lordaeron", "named by the list when the game has no name")
	equal(ruins and #ruins.quests, 4, "the Alliance's four in Ruins of Lordaeron")
	check(Contains(Catalog.zones[1581].quests, 92753), "the new Deadmines quest")
	for _, id in ipairs({ 92742, 92744, 92745, 92747, 92748, 92749, 92750, 92751, 92752, 92819 }) do
		check(Contains(Catalog.zones[40].quests, id), "%d is in Westfall", id)
	end
	check(Contains(Catalog.zones[1] and Catalog.zones[1].quests, 96391), "Underground Map is in Dun Morogh")
	check(Contains(Catalog.zones[1519].quests, 95161), "the letter's second part is in Stormwind")
	check(Catalog.zones[1497] == nil, "the Horde's step in the Undercity is left out")
	equal(Data.Source(96395), "almanac", "from Almanac's list")

	-- Chains
	local chain = Catalog.chainOf[92753]
	equal(chain and Ids(chain.quests), "92742,92744,92745,92747,92748,92749,92750,92751,92752,92753,92819",
		"Toxic Soil, into the Deadmines")
	equal(chain and chain.name, "Testing the Wells", "named after its first quest")
	check(Catalog.chainOf[96393] and Catalog.chainOf[96393] == Catalog.chainOf[96391], "the map leads to Old Ironforge Incursion")
	check(Catalog.chainOf[95161] and Catalog.chainOf[95161] == Catalog.chainOf[92415], "the letter's two parts")
	equal((Status.Of(92742)), "available", "the first step")
	local state, reasons = Status.Of(92744)
	equal(state, "later", "the next waits")
	equal(reasons and Status.ReasonText(reasons[1]), "After Testing the Wells", "for the one before")
	equal(Status.Section(92753), "available", "a chain that can be started is all under Available")

	-- XP from the list; money and rewards from the game.
	equal((Rewards.FullXP(96395)), 3570, "Forever's tuned XP")
	equal(select(2, Rewards.FullXP(96395)), "reported", "from the list")
	equal((Rewards.FullXP(96394)), 3570, "not the 1,050 the game lists")
	equal((Rewards.FullXP(92742)), 455, "a quest outside a dungeon")
	equal((Rewards.FullXP(92422)), 0, "The Wrath of Rath'mael gives none")
	equal(Rewards.Money(96394), 700, "money from the game")
	local fixed, choice, source = Rewards.Items(96395)
	equal(#fixed .. "/" .. #choice .. " " .. tostring(source), "0/2 client", "rewards from the game")

	-- Turned in, 166 gave 3.75 times its listed XP, and the Deadmines' other
	-- QuestieDB quests are estimated at that; the new one says what it gives.
	Mock.Fire(client.state, "QUEST_TURNED_IN", 166, 9750, 4500)
	Mock.Advance(client.state, 1)
	equal(select(2, Rewards.FullXP(214)), "estimate", "QuestieDB's quest is estimated")
	equal((Rewards.FullXP(92753)), 4050, "the new one is not")
	NoErrors(client)
end)

test("Forever's new quests: tooltips, rewards and where you are", function()
	local client = Start(ForeverClient, { forever = true })
	local frame = Open(client)
	local ns = client.ns
	frame.quests:ShowZone(16919)
	Mock.Enter(FindRow(frame.quests, "quest 96393"))
	local tip = Mock.Plain(client.env.GameTooltip:Text())
	check(tip:find("Starts | Earthseer Farsen, Dun Morogh", 1, true), "who starts it, and where: %s", tip)
	check(tip:find("Ends | King Magni Bronzebeard, Ironforge", 1, true), "who ends it")
	check(tip:find("4,930 (as reported for Forever)", 1, true), "its XP")
	check(tip:find("New in WoW: Forever", 1, true), "where it is from")
	Mock.Enter(FindRow(frame.quests, "quest 98423"))
	tip = Mock.Plain(client.env.GameTooltip:Text())
	check(tip:find("Starts | Treaty of Understanding (an item), The Hall of Thanes", 1, true), "an item starts it: %s", tip)

	LoadItems(client)
	local ids, results = Search(ns, { slot = "back" })
	equal(ids, "279899", "the cloak the game lists for An Ancient Grudge")
	equal(results[1] and results[1].quests[1], 96395, "from it")

	client.state.instance, client.state.instanceName = 2999, "The Hall of Thanes"
	equal(ns.Data.PlayerZoneKey(), 16919, "inside The Hall of Thanes")
	client.env.SlashCmdList.ALMANAC("probe 96395")
	check(table.concat(client.state.chat, "\n"):find("(new in Forever, from Almanac's list)", 1, true), "/almanac probe says so")
	NoErrors(client)
end)

test("Forever's new quests: each drops out once QuestieDB has it", function()
	local client = Start(function(env)
		local world = World()
		world.quests[92742] = Quest("Testing the Wells", 40, 12, 9)
		world.xp[92742] = { 12, 455 }
		env.LibQuestieDB = Mock.QuestieDB(world)
	end, { forever = true })
	Open(client)
	local ns = client.ns
	equal(ns.Data.Source(92742), "questie", "QuestieDB's now")
	equal(select(2, ns.Rewards.FullXP(92742)), "database", "with QuestieDB's XP")
	equal(Count(ns.Catalog.all, 92742), 1, "listed once")
	equal(ns.Data.Source(92744), "almanac", "the next one is still Almanac's")
	check(ns.Catalog.chainOf[92744] and ns.Catalog.chainOf[92744] == ns.Catalog.chainOf[92742], "and follows it")
	NoErrors(client)
end)

--------------------------------------------------------------------------------
-- The real QuestieDB
--------------------------------------------------------------------------------

-- Forever Dungeon Journal's data files, as the game loads them, if it is
-- installed.
local function LoadJournal(env)
	local dir = RealQuestieDB.Folder() .. "/ForeverDungeonJournal/"
	local toc = io.open(dir .. "ForeverDungeonJournal.toc")
	if not toc then
		return nil, "no Forever Dungeon Journal at " .. dir
	end
	local files = {}
	for line in toc:lines() do
		local file = line:match("^%s*(Core[\\/]Bootstrap%.lua)%s*$") or line:match("^%s*(Data[\\/][^%s]+%.lua)%s*$")
		if file then
			files[#files + 1] = file:gsub("\\", "/")
		end
	end
	toc:close()
	local ns = {}
	for _, file in ipairs(files) do
		local chunk, err = loadfile(dir .. file)
		if not chunk then
			return nil, err
		end
		setfenv(chunk, env)
		local ok, loadErr = pcall(chunk, "ForeverDungeonJournal", ns)
		if not ok then
			return nil, file .. ": " .. tostring(loadErr)
		end
	end
	return env.ForeverDungeonJournal_NS ~= nil or nil, "Forever Dungeon Journal did not publish its data"
end

local function RealStart(player, setup)
	local env, state = Mock.New({ player = player })
	local ok, why = RealQuestieDB.Load(env)
	if not ok then
		return nil, why
	end
	if setup then
		ok, why = setup(env)
		if not ok then
			return nil, why
		end
	end
	local ns = Mock.LoadAddon(env, state, ADDON_DIR, ADDON)
	Mock.Fire(state, "ADDON_LOADED", ADDON)
	Mock.Fire(state, "PLAYER_LOGIN")
	return { env = env, state = state, ns = ns }
end

local real, skipped = RealStart()
if not real then
	print("skipped the real QuestieDB tests (" .. tostring(skipped) .. ")")
else
	test("real QuestieDB: a Human Mage's quest list", function()
		local client = real
		local started = os.clock()
		client.ns.Catalog.BuildNow()
		local seconds = os.clock() - started
		print(("    built in %.2f s (plain Lua; the client decodes natively)"):format(seconds))
		local Catalog = client.ns.Catalog
		check(#Catalog.all > 1500, "quests listed: %d", #Catalog.all)
		local westfall = Catalog.zones[40]
		check(westfall and #westfall.quests > 20, "Westfall has quests")
		local chain = Catalog.chainOf[65]
		check(chain and Contains(chain.quests, 166), "the Defias chain reaches 166")
		local deadmines = Catalog.zones[1581]
		equal(deadmines and deadmines.group, "dungeon", "the Deadmines are a dungeon")
		check(deadmines and Contains(deadmines.quests, 214) and Contains(deadmines.quests, 166), "with their quests")
		local gnomeregan = Catalog.zones[721]
		check(gnomeregan and #gnomeregan.quests > 0, "Gnomeregan's quests (filed under 133) are there")
		check(Catalog.zones[12] and Contains(Catalog.zones[12].quests, 783), "Northshire's quests are in Elwynn Forest")
		check(Catalog.zones[-161], "the Mage category")
		check(not Catalog.zones[-81], "no Warrior category")
		local groups = {}
		for _, group in ipairs(Catalog.groups) do
			groups[#groups + 1] = group.key .. ":" .. #group.zones
		end
		print("    groups: " .. table.concat(groups, " "))
		for _, group in ipairs(Catalog.groups) do
			if group.key ~= "ek" and group.key ~= "kalimdor" then
				local names = {}
				for _, zone in ipairs(group.zones) do
					names[#names + 1] = zone.name .. "(" .. zone.key .. "):" .. #zone.quests
				end
				print("    " .. group.key .. ": " .. table.concat(names, ", "))
			end
		end
		for _, id in ipairs(Catalog.all) do
			client.ns.Status.Of(id)
		end
		equal((client.ns.Status.Of(65)), "available", "a level 20 can take 65")
		equal((client.ns.Rewards.FullXP(65)), 1350, "its XP")
		NoErrors(client)
	end)

	test("real QuestieDB: reward items", function()
		local client = real
		local started = os.clock()
		client.ns.Items.ScanNow()
		print(("    reward index in %.2f s"):format(os.clock() - started))
		check(client.ns.Items.Count() > 1500, "reward items: %d", client.ns.Items.Count())
		NoErrors(client)
	end)

	test("real QuestieDB: every zone page draws", function()
		local client = real
		local frame = Open(client)
		for key in pairs(client.ns.Catalog.zones) do
			frame.quests:ShowZone(key)
		end
		frame.quests:ShowSearch("the")
		NoErrors(client)
	end)

	test("real QuestieDB: Forever's new quests it does not have yet", function()
		local ns = real.ns
		local Data, Catalog = ns.Data, ns.Catalog
		local listed, inQuestie, byZone, keys = 0, 0, {}, {}
		for id in pairs(ns.ForeverQuests.quests) do
			if Data.QuestExists(id) then
				inQuestie = inQuestie + 1
			else
				listed = listed + 1
				local quest = Data.Basics(id)
				local key = quest and Data.ZoneKey(quest.zone)
				check(quest and key and key ~= 0 and Data.Source(id) == "almanac", "%d is listed from Almanac's list", id)
				if key then
					if not byZone[key] then
						byZone[key] = 0
						keys[#keys + 1] = key
					end
					byZone[key] = byZone[key] + 1
				end
				local links = Data.Links(id)
				for _, before in ipairs(links.preSingle or {}) do
					check(Data.Basics(before), "%d comes after a quest Almanac knows (%d)", id, before)
				end
			end
		end
		table.sort(keys)
		local zones = {}
		for i, key in ipairs(keys) do
			zones[i] = ("%s %d"):format(Data.ZoneName(key), byZone[key])
		end
		print(("    %d listed from Almanac's list, %d in QuestieDB now: %s"):format(listed, inQuestie, table.concat(zones, ", ")))
		equal(Catalog.zones[16919] and Catalog.zones[16919].group, "dungeon", "The Hall of Thanes is a dungeon")
		if not Data.QuestExists(92753) and not Data.QuestExists(92742) then
			local chain = Catalog.chainOf[92753]
			check(chain and Contains(chain.quests, 92742), "Toxic Soil leads to Destruction in Deadmines")
		end
		NoErrors(real)
	end)

	real = nil
	local journal, noJournal = RealStart(nil, LoadJournal)
	if not journal then
		print("skipped the real Forever Dungeon Journal test (" .. tostring(noJournal) .. ")")
	else
		test("real Forever Dungeon Journal: what it adds to Almanac's list", function()
			local client = journal
			local ns = client.ns
			local Data, Catalog = ns.Data, ns.Catalog
			Catalog.BuildNow()
			-- Every quest of the journal's is in QuestieDB, on Almanac's list,
			-- or added from the journal.
			local fdj = client.env.ForeverDungeonJournal_NS
			local added, keys = {}, {}
			for _, dungeon in pairs(fdj.DB) do
				for _, q in ipairs(type(dungeon) == "table" and dungeon.quests or {}) do
					local source = Data.QuestExists(q.id) and "questie" or Data.Source(q.id)
					check(source == "questie" or Data.Basics(q.id), "%d is listed", q.id)
					if source == "journal" and not added[q.id] then
						added[q.id] = true
						keys[#keys + 1] = q.id .. " " .. q.name
					end
				end
			end
			for _, id in ipairs(ns.NewQuests.Ids()) do
				if Data.Source(id) == "journal" and not added[id] then
					added[id] = true
					keys[#keys + 1] = id .. " " .. Data.Basics(id).name
				end
				ns.Status.Of(id)
			end
			table.sort(keys)
			print(("    the journal adds %d quests Almanac's list lacks%s"):format(#keys,
				#keys > 0 and (": " .. table.concat(keys, ", ")) or ""))
			local frame = Open(client)
			for key in pairs(Catalog.zones) do
				frame.quests:ShowZone(key)
			end
			NoErrors(client)
		end)
	end
end

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
