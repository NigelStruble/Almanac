local _, ns = ...
local C, Data = ns.C, ns.Data

-- What the character is: level, race, class and faction, the quests it has
-- done, its quest log, its reputations, professions and spells. Everything
-- that decides whether it can take a quest. Player.version goes up with every
-- change, so what was worked out from the old state is known to be stale.

local Player = {}
ns.Player = Player

local pairs = pairs

Player.version = 0
Player.level = 1
Player.maxLevel = 60
Player.completed = {}
Player.log = {}
Player.skills = {}
Player.reps = {}

local function Changed()
	Player.version = Player.version + 1
	ns.Send("player")
end

-- Everything, read afresh.
function Player.Read()
	Player.level = C.PlayerLevel()
	Player.maxLevel = C.MaxLevel()
	Player.raceID, Player.raceFile = C.PlayerRace()
	Player.classID, Player.classFile = C.PlayerClass()
	Player.faction = C.PlayerFaction()
	Player.raceBit = Data.Bit(Player.raceID)
	Player.classBit = Data.Bit(Player.classID)
	-- The races of the character's faction; just its own race if the faction
	-- is not known (a new race, or a Pandaren who has not chosen yet).
	local mask = Player.faction and Data.FactionMask(Player.faction) or 0
	if mask == 0 or not Data.HasBit(mask, Player.raceBit) then
		mask = mask + Player.raceBit
	end
	Player.factionMask = mask
	Player.completed = C.CompletedQuests()
	Player.log = C.QuestLog()
	Player.skills = C.Professions()
	Player.reps = {}
	Changed()
end

function Player.IsDone(questID)
	return Player.completed[questID] == true
end

function Player.InLog(questID)
	return Player.log[questID] ~= nil
end

-- Done, or in the quest log.
function Player.HasTaken(questID)
	return Player.completed[questID] == true or Player.log[questID] ~= nil
end

-- The character's standing with a faction, or nil if it has none.
function Player.Reputation(factionID)
	local value = Player.reps[factionID]
	if value == nil then
		value = C.Reputation(factionID) or false
		Player.reps[factionID] = value
	end
	return value or nil
end

function Player.Skill(skillLine)
	return Player.skills[skillLine]
end

function Player.KnowsSpell(spellID)
	return C.KnowsSpell(spellID)
end

--------------------------------------------------------------------------------
-- Keeping up
--------------------------------------------------------------------------------

local function SameLog(a, b)
	for id, entry in pairs(a) do
		local other = b[id]
		if not other or other.complete ~= entry.complete then
			return false
		end
	end
	for id in pairs(b) do
		if not a[id] then
			return false
		end
	end
	return true
end

local ReadLog = C.Debounce(0.3, function()
	local log = C.QuestLog()
	if not SameLog(log, Player.log) then
		Player.log = log
		Changed()
	end
end)

local ReadSkills = C.Debounce(1, function()
	Player.skills = C.Professions()
	Changed()
end)

local SomethingChanged = C.Debounce(0.5, Changed)

function Player.Start()
	Player.Read()
	C.On("PLAYER_ENTERING_WORLD", function()
		Player.Read()
	end)
	C.On("PLAYER_LEVEL_UP", function(_, level)
		Player.level = level or C.PlayerLevel()
		Changed()
	end)
	C.On("QUEST_TURNED_IN", function(_, questID)
		if questID then
			Player.completed[questID] = true
			Player.log[questID] = nil
			Changed()
		end
		ReadLog()
	end)
	C.On("QUEST_ACCEPTED", ReadLog)
	C.On("QUEST_REMOVED", ReadLog)
	C.On("QUEST_LOG_UPDATE", ReadLog)
	C.On("UPDATE_FACTION", function()
		Player.reps = {}
		SomethingChanged()
	end)
	C.On("SKILL_LINES_CHANGED", ReadSkills)
	-- A few quests need a spell known (or not known). The event has two names.
	C.On("LEARNED_SPELL_IN_SKILL_LINE", SomethingChanged)
	C.On("LEARNED_SPELL_IN_TAB", SomethingChanged)
end
