local _, ns = ...

-- Everything is saved account-wide in AlmanacDB:
--   settings   options and the reward search's filters; only changed values
--              are saved (see DEFAULTS)
--   positions  where the window was left, and its size
--   learned    what quests really gave when turned in, and the rewards quest
--              dialogs showed, by quest ID (see Rewards.lua)
--   collapsed  the zone list's groups that are folded up

local DB = {}
ns.DB = DB

local _G = _G
local ipairs, type, rawset = ipairs, type, rawset

DB.DEFAULTS = {
	scale = 1,
	width = 980,
	height = 640,
	otherFaction = false, -- the other faction's quests
	otherClasses = false, -- other classes' quests
	otherRaces = false, -- quests only other races of your faction can take
	showBlocked = true, -- quests you can no longer take, under Unavailable
	showHidden = false, -- quests Questie hides (not in the game, or out of season)
	repeatableTotals = false, -- repeatable quests count toward the totals
	completedOpen = false, -- the Completed section starts open
	questIDs = false, -- quest IDs in tooltips
	minimapButton = true, -- the button on the minimap
	minimapAngle = 225, -- where it is around the minimap, in degrees
	-- The reward search
	rewardSlot = "any",
	rewardType = "any",
	rewardStat = "any",
	rewardUsable = true, -- only items the character can use (at the level it can have them)
	rewardQuests = "now", -- which quests: "now", "still" or "all" (see Items.QUEST_MODES)
	rewardMaxLevel = 0, -- highest level the item or its quest needs; 0 for any
	rewardQuality = 0, -- lowest quality
	rewardSort = "level",
}

local VERSION = 1

-- Until AlmanacDB loads, everything reads empty tables and the defaults.
DB.settings = setmetatable({}, { __index = DB.DEFAULTS })
DB.positions, DB.learned, DB.collapsed = {}, {}, {}

function DB.Load()
	local saved = _G.AlmanacDB
	if type(saved) ~= "table" then
		saved = {}
		_G.AlmanacDB = saved
	end
	saved.version = saved.version or VERSION
	for _, key in ipairs({ "settings", "positions", "learned", "collapsed" }) do
		if type(saved[key]) ~= "table" then
			saved[key] = {}
		end
	end
	-- Replaced by rewardQuests before the first release.
	saved.settings.rewardObtainable = nil
	DB.settings = setmetatable(saved.settings, { __index = DB.DEFAULTS })
	DB.positions = saved.positions
	DB.learned = saved.learned
	DB.collapsed = saved.collapsed
end

function DB.Set(key, value)
	if value == DB.DEFAULTS[key] then
		value = nil -- keep the saved file to what differs from the defaults
	end
	rawset(DB.settings, key, value)
end

--------------------------------------------------------------------------------
-- Change notifications
--------------------------------------------------------------------------------

-- Modules announce what changed and the window brings itself up to date:
--   "catalog"   the quest list was (re)built
--   "player"    level, completed quests, the quest log, reputation, skills
--   "rewards"   quest rewards arrived from the server or were learned
--   "items"     item details arrived from the server
--   "settings"  an option changed
local listeners = {}

function ns.Listen(what, callback)
	local list = listeners[what]
	if not list then
		list = {}
		listeners[what] = list
	end
	list[#list + 1] = callback
end

function ns.Send(what, ...)
	local list = listeners[what]
	if list then
		for i = 1, #list do
			list[i](...)
		end
	end
end
