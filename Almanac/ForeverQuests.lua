local _, ns = ...

-- Quests WoW: Forever added that QuestieDB does not have yet: those of its
-- new dungeons (The Hall of Thanes, Ruins of Lordaeron), a new Deadmines
-- quest, and the quests that lead to them or follow them. Almanac lists them
-- until QuestieDB has them; a quest QuestieDB has is taken from QuestieDB, so
-- each one here drops out by itself (NewQuests.lua).
--
-- Facts about the game, checked on 2026-09-28 against:
--   Wowhead's Forever database: levels, sides, series, objectives, who
--     starts and ends a quest (www.wowhead.com/forever)
--   wowforevertalents.com: read from the Forever beta client's quest cache
--   foreverchanges.pro and quissy.tv: the XP the beta really gives
-- Money and reward items are not here: Almanac asks the game for them.
--
-- quests[quest ID] = {
--   name,
--   zone   where it is listed: its dungeon, or its zone (an area ID)
--   level  its level; req: the level it can be taken from
--   side   "Alliance" or "Horde"; none for both
--   after  the quest that must be done first
--   xp     the XP it gives on Forever. Forever tunes dungeon quests up: they
--          give 3 to 4 times what the game lists for them.
--   from, to  who starts and who ends it, and where: { name, area ID }, or
--          { name, area ID, item = true } for an item that starts it
-- }

local HALL_OF_THANES, RUINS_OF_LORDAERON, DEADMINES = 16919, 16611, 1581
local DUN_MOROGH, IRONFORGE, WESTFALL, STORMWIND = 1, 1537, 40, 1519
local TIRISFAL, SILVERPINE, UNDERCITY, DUSKWOOD = 85, 130, 1497, 10

local ALBA = { "Alba Fairmoon", WESTFALL }
local SPRITE = { "Sprite Jumpsprocket", STORMWIND }
local MAGNI = { "King Magni Bronzebeard", IRONFORGE }
local FARANELL = { "Master Apothecary Faranell", UNDERCITY }

ns.ForeverQuests = {
	-- The new dungeons, by area ID (Wowhead's zone IDs).
	dungeons = {
		[HALL_OF_THANES] = "The Hall of Thanes",
		[RUINS_OF_LORDAERON] = "Ruins of Lordaeron",
	},

	quests = {
		-- The Hall of Thanes, beneath Ironforge
		[96395] = { name = "An Ancient Grudge", zone = HALL_OF_THANES, level = 15, req = 10, xp = 3570,
			from = { "Ghostly Attendant", HALL_OF_THANES } },
		-- Wowhead lists it for the Alliance; the others say both factions.
		[96403] = { name = "Important Heirlooms", zone = HALL_OF_THANES, level = 15, req = 10, xp = 4590,
			from = { "Thom Filch", IRONFORGE }, to = { "Thom Filch", IRONFORGE } },
		[96394] = { name = "The Restless Dead", zone = HALL_OF_THANES, level = 15, req = 10, side = "Alliance", xp = 3570,
			from = { "Afadra Dunwall", IRONFORGE } },
		[96391] = { name = "Underground Map", zone = DUN_MOROGH, level = 15, req = 9, side = "Alliance", xp = 1050,
			from = { "Dark Iron Map", DUN_MOROGH, item = true }, to = { "Earthseer Farsen", DUN_MOROGH } },
		[96393] = { name = "Old Ironforge Incursion", zone = HALL_OF_THANES, level = 16, req = 9, side = "Alliance",
			after = 96391, xp = 4930, from = { "Earthseer Farsen", DUN_MOROGH }, to = MAGNI },
		[98423] = { name = "The Treaty of Understanding", zone = HALL_OF_THANES, level = 16, req = 9, side = "Alliance",
			xp = 3900, from = { "Treaty of Understanding", HALL_OF_THANES, item = true }, to = MAGNI },

		-- Ruins of Lordaeron, above the Undercity
		[95250] = { name = "Abominable Creatures", zone = RUINS_OF_LORDAERON, level = 21, req = 16, side = "Alliance",
			xp = 6188, from = { "Captain Truman", RUINS_OF_LORDAERON }, to = { "Captain Truman", RUINS_OF_LORDAERON } },
		[95195] = { name = "Bloodied Insignia", zone = RUINS_OF_LORDAERON, level = 22, req = 16, side = "Alliance",
			xp = 9750, from = { "Bloodied Insignia", RUINS_OF_LORDAERON, item = true },
			to = { "General Marcus Jonathan", STORMWIND } },
		[92415] = { name = "Remember That I Love You", zone = RUINS_OF_LORDAERON, level = 22, req = 15, side = "Alliance",
			xp = 9750, from = { "Blood-Stained Letter", RUINS_OF_LORDAERON, item = true },
			to = { "Orphan Matron Nightingale", STORMWIND } },
		[95161] = { name = "Remember That I Love You", zone = STORMWIND, level = 22, req = 15, side = "Alliance",
			after = 92415, xp = 180, from = { "Orphan Matron Nightingale", STORMWIND },
			to = { "Avette Fellwood", DUSKWOOD } },
		[95189] = { name = "Crest of Lordaeron", zone = RUINS_OF_LORDAERON, level = 22, req = 16, side = "Alliance",
			xp = 9750, from = { "Crest of Lordaeron", RUINS_OF_LORDAERON, item = true },
			to = { "Lady Dena Kennedy", STORMWIND } },
		-- It gives no XP on the beta.
		[92422] = { name = "The Wrath of Rath'mael", zone = RUINS_OF_LORDAERON, level = 22, req = 15, side = "Horde",
			xp = 0, from = { "Deathguard Kristof", TIRISFAL }, to = { "Deathguard Kristof", TIRISFAL } },
		[92421] = { name = "Light's Justice", zone = RUINS_OF_LORDAERON, level = 22, req = 15, side = "Horde",
			xp = 7040, from = { "Morbin Lightbane", UNDERCITY }, to = { "Morbin Lightbane", UNDERCITY } },
		[92401] = { name = "A Frightened Request", zone = RUINS_OF_LORDAERON, level = 22, req = 15, side = "Horde",
			xp = 7040, from = { "Tabitha Heartweaver", SILVERPINE } },
		[95216] = { name = "The New Plague", zone = RUINS_OF_LORDAERON, level = 22, req = 16, side = "Horde",
			xp = 8320, from = { "Theodore Griffs", UNDERCITY }, to = { "Theodore Griffs", UNDERCITY } },
		[95204] = { name = "Crest of Lordaeron", zone = RUINS_OF_LORDAERON, level = 22, req = 16, side = "Horde",
			xp = 8320, from = { "Crest of Lordaeron", RUINS_OF_LORDAERON, item = true },
			to = { "Oran Snakewrithe", UNDERCITY } },
		-- Five parts; only the first is tuned up.
		[97288] = { name = "Unending Torment", zone = RUINS_OF_LORDAERON, level = 21, req = 16, side = "Horde",
			xp = 5280, from = { "Abominable Head", RUINS_OF_LORDAERON, item = true }, to = FARANELL },
		[97289] = { name = "Unending Torment", zone = RUINS_OF_LORDAERON, level = 21, req = 16, side = "Horde",
			after = 97288, xp = 1650 },
		[97290] = { name = "Unending Torment", zone = UNDERCITY, level = 21, req = 16, side = "Horde",
			after = 97289, xp = 1650, from = { "Unfinished Abomination", UNDERCITY }, to = FARANELL },
		[97291] = { name = "Unending Torment", zone = RUINS_OF_LORDAERON, level = 21, req = 16, side = "Horde",
			after = 97290, xp = 1650 },
		[97292] = { name = "Unending Torment", zone = RUINS_OF_LORDAERON, level = 21, req = 16, side = "Horde",
			after = 97291, xp = 1650 },

		-- The Deadmines, and Toxic Soil, the Westfall story that leads there
		[92742] = { name = "Testing the Wells", zone = WESTFALL, level = 12, req = 9, side = "Alliance", xp = 455,
			from = ALBA, to = ALBA },
		[92744] = { name = "Murloc Gills", zone = WESTFALL, level = 12, req = 9, side = "Alliance", after = 92742,
			xp = 455, from = ALBA, to = ALBA },
		[92745] = { name = "The State of the Mines", zone = WESTFALL, level = 14, req = 9, side = "Alliance", after = 92744,
			xp = 490, from = ALBA, to = ALBA },
		[92747] = { name = "Moonbrook Espionage", zone = WESTFALL, level = 16, req = 9, side = "Alliance", after = 92745,
			xp = 580, from = ALBA, to = ALBA },
		[92748] = { name = "Explosive Consultation", zone = WESTFALL, level = 16, req = 9, side = "Alliance", after = 92747,
			xp = 580, to = SPRITE },
		[92749] = { name = "A Dynamite Plan", zone = WESTFALL, level = 16, req = 9, side = "Alliance", after = 92748,
			xp = 580, to = SPRITE },
		[92750] = { name = "Detonation at a Distance", zone = WESTFALL, level = 16, req = 9, side = "Alliance",
			after = 92749, xp = 580, to = { "Stormwind Intelligence", STORMWIND } },
		[92751] = { name = "Detonation at a Distance", zone = WESTFALL, level = 16, req = 9, side = "Alliance",
			after = 92750, xp = 580, to = SPRITE },
		[92752] = { name = "Explosive Consultation", zone = WESTFALL, level = 16, req = 9, side = "Alliance",
			after = 92751, xp = 580, to = ALBA },
		[92753] = { name = "Destruction in Deadmines", zone = DEADMINES, level = 18, req = 9, side = "Alliance",
			after = 92752, xp = 4050, from = ALBA, to = ALBA },
		[92819] = { name = "Destruction in Deadmines", zone = WESTFALL, level = 18, req = 9, side = "Alliance",
			after = 92753, xp = 680 },
	},
}
