local _, ns = ...

-- Thin wrappers around the WoW API. Almanac is written for WoW: Forever, which
-- is Classic content on the Retail client, so the Retail API is used first;
-- where an older spelling of a function exists it is the fallback. Anything
-- the client may not have, or may refuse, is guarded, so one missing function
-- never stops the window from opening.

local C = {}
ns.C = C

local _G = _G
local type, pcall, select, pairs, ipairs, tonumber, tostring = type, pcall, select, pairs, ipairs, tonumber, tostring
local floor, format = math.floor, string.format

--------------------------------------------------------------------------------
-- Game version
--------------------------------------------------------------------------------

C.toc = select(4, GetBuildInfo()) or 0
-- Forever reports a 1.6x interface number (16001); nothing else at runtime
-- tells it apart from Retail.
C.isForever = C.toc >= 16000 and C.toc < 20000

--------------------------------------------------------------------------------
-- Secret values
--------------------------------------------------------------------------------

-- Some API results are "secret" in combat on Retail and Forever: addon code
-- may not compare, format or join them. Anything that could be secret goes
-- through Clean first, which turns a secret into nil.
local issecretvalue = _G.issecretvalue

function C.Clean(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

local Clean = C.Clean

local function Pass(ok, ...)
	if ok then
		return ...
	end
	return nil
end

-- Calls fn, returning nothing if it errors or does not exist.
local function Try(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	return Pass(pcall(fn, ...))
end
C.Try = Try

--------------------------------------------------------------------------------
-- Events and timers
--------------------------------------------------------------------------------

-- Newer clients throw an error when asked for an event they do not have, so
-- every registration is guarded. Returns false if the event does not exist.
function C.RegisterEvent(frame, event)
	return (pcall(frame.RegisterEvent, frame, event))
end

-- One event frame for the whole addon; any number of handlers per event.
-- securecallfunction reports a failing handler without stopping the others.
local eventFrame = CreateFrame("Frame")
local handlers = {}
local call = _G.securecallfunction or function(func, ...)
	return func(...)
end

function C.On(event, handler)
	local list = handlers[event]
	if not list then
		if not C.RegisterEvent(eventFrame, event) then
			return false
		end
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = handler
	return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	for i = 1, #list do
		call(list[i], event, ...)
	end
end)

function C.After(delay, fn)
	C_Timer.After(delay, fn)
end

-- Returns a function that runs fn once, delay seconds after the first of any
-- number of calls. Folds bursts of events into one update.
function C.Debounce(delay, fn)
	local pending = false
	local function Run()
		pending = false
		fn()
	end
	return function()
		if not pending then
			pending = true
			C_Timer.After(delay, Run)
		end
	end
end

-- Milliseconds, for keeping long jobs to a few milliseconds a frame.
function C.Clock()
	if _G.debugprofilestop then
		return _G.debugprofilestop()
	end
	return GetTime() * 1000
end

-- Runs fn(pause) a few milliseconds a frame, so a long job does not freeze
-- the game: fn calls pause(progress) now and then, which waits for the next
-- frame once this frame's share is used up. done() runs at the end. Returns
-- a function that stops the job.
function C.Spread(fn, done, budget)
	budget = budget or 8
	local job = coroutine.create(fn)
	local frame = CreateFrame("Frame")
	local started = 0
	local function Pause()
		if C.Clock() - started > budget then
			coroutine.yield()
		end
	end
	local function Stop()
		frame:SetScript("OnUpdate", nil)
	end
	frame:SetScript("OnUpdate", function()
		started = C.Clock()
		local ok, err = coroutine.resume(job, Pause)
		if not ok then
			Stop()
			_G.geterrorhandler()(err)
		elseif coroutine.status(job) == "dead" then
			Stop()
			if done then
				done()
			end
		end
	end)
	return Stop
end

--------------------------------------------------------------------------------
-- Quests
--------------------------------------------------------------------------------

local QuestLog = _G.C_QuestLog

-- Every quest the character has turned in, as a set of quest IDs.
function C.CompletedQuests()
	local done = {}
	local ids = QuestLog and Try(QuestLog.GetAllCompletedQuestIDs)
	if type(ids) == "table" then
		for _, id in ipairs(ids) do
			done[id] = true
		end
		return done
	end
	local old = Try(_G.GetQuestsCompleted)
	if type(old) == "table" then
		for id in pairs(old) do
			done[id] = true
		end
	end
	return done
end

function C.IsQuestCompleted(questID)
	if QuestLog and QuestLog.IsQuestFlaggedCompleted then
		return Try(QuestLog.IsQuestFlaggedCompleted, questID) == true
	end
	return Try(_G.IsQuestFlaggedCompleted, questID) == true
end

-- The quests in the log: { [questID] = { complete = true/false } }. Only the
-- quest log's own "complete" counts: on Forever a quest can report being
-- ready to turn in before its objectives are done.
function C.QuestLog()
	local log = {}
	if QuestLog and QuestLog.GetInfo then
		for index = 1, 200 do
			local info = Try(QuestLog.GetInfo, index)
			if type(info) ~= "table" then
				break
			end
			local id = Clean(info.questID)
			if not info.isHeader and type(id) == "number" and id > 0 then
				log[id] = { complete = Try(QuestLog.IsComplete, id) == true }
			end
		end
		return log
	end
	local count = Try(_G.GetNumQuestLogEntries) or 0
	for index = 1, count do
		local title, _, _, isHeader, _, isComplete, _, id = Try(_G.GetQuestLogTitle, index)
		if title and not isHeader and type(id) == "number" then
			log[id] = { complete = isComplete == 1 or isComplete == true }
		end
	end
	return log
end

-- Asks the server for a quest's details (title, rewards) if the client does
-- not have them yet. QUEST_DATA_LOAD_RESULT(questID, success) answers.
function C.RequestQuest(questID)
	if QuestLog and QuestLog.RequestLoadQuestByID then
		return (pcall(QuestLog.RequestLoadQuestByID, questID))
	end
	return false
end

function C.CanRequestQuests()
	return QuestLog and QuestLog.RequestLoadQuestByID ~= nil
end

-- Whether the client already has a quest's details, so reading them needs no
-- request.
function C.HaveQuestData(questID)
	return Try(_G.HaveQuestData, questID) == true
end

function C.QuestTitle(questID)
	if not QuestLog then
		return nil
	end
	local title = Try(QuestLog.GetTitleForQuestID or QuestLog.GetQuestInfo, questID)
	title = Clean(title)
	if type(title) == "string" and title ~= "" then
		return title
	end
	return nil
end

-- A quest link for chat: the game's own where it has one (for a quest in the
-- quest log), else "[Name (ID)]" as text, which Questie turns into a link for
-- those who have it.
function C.QuestLink(questID, name)
	local link = Clean(Try(_G.GetQuestLink, questID))
	if type(link) == "string" and link ~= "" then
		return link
	end
	if type(name) == "string" and name ~= "" then
		return format("[%s (%d)]", name, questID)
	end
	return nil
end

local function ReadItemList(countFunc, infoFunc, questID)
	local list = {}
	local count = Clean(Try(countFunc, questID))
	if type(count) ~= "number" then
		return list
	end
	for index = 1, count do
		local _, _, amount, _, _, itemID = Try(infoFunc, index, questID)
		itemID = Clean(itemID)
		if type(itemID) == "number" and itemID > 0 then
			list[#list + 1] = { itemID, Clean(amount) or 1 }
		end
	end
	return list
end

-- What the client knows about a quest's rewards from its quest cache, for any
-- quest (not only those in the log) once its data has loaded:
-- { xp, money, fixed = { {itemID, count}, ... }, choice = { ... } }.
-- xp is what the client says this character would get.
function C.CachedRewards(questID)
	local xp = Clean(Try(_G.GetQuestLogRewardXP, questID))
	local money = Clean(Try(_G.GetQuestLogRewardMoney, questID))
	return {
		xp = type(xp) == "number" and xp or nil,
		money = type(money) == "number" and money or nil,
		fixed = ReadItemList(_G.GetNumQuestLogRewards, _G.GetQuestLogRewardInfo, questID),
		choice = ReadItemList(_G.GetNumQuestLogChoices, _G.GetQuestLogChoiceInfo, questID),
	}
end

local function DialogItems(kind, count)
	local list = {}
	for index = 1, count or 0 do
		local _, _, amount, _, _, itemID = Try(_G.GetQuestItemInfo, kind, index)
		itemID = Clean(itemID)
		if type(itemID) ~= "number" then
			local link = Clean(Try(_G.GetQuestItemLink, kind, index))
			itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
		end
		if itemID and itemID > 0 then
			list[#list + 1] = { itemID, Clean(amount) or 1 }
		end
	end
	return list
end

-- The rewards shown in the quest dialog that is open (a quest being offered,
-- or being turned in): { questID, xp, money, fixed, choice }.
function C.DialogRewards()
	local questID = Clean(Try(_G.GetQuestID))
	if type(questID) ~= "number" or questID <= 0 then
		return nil
	end
	return {
		questID = questID,
		xp = Clean(Try(_G.GetRewardXP)),
		money = Clean(Try(_G.GetRewardMoney)),
		fixed = DialogItems("reward", Clean(Try(_G.GetNumQuestRewards))),
		choice = DialogItems("choice", Clean(Try(_G.GetNumQuestChoices))),
	}
end

--------------------------------------------------------------------------------
-- The character
--------------------------------------------------------------------------------

function C.PlayerLevel()
	return Clean(UnitLevel("player")) or 1
end

function C.MaxLevel()
	local level = Try(_G.GetMaxPlayerLevel) or Try(_G.GetMaxLevelForPlayerExpansion) or _G.MAX_PLAYER_LEVEL
	if type(level) ~= "number" or level < 1 then
		return 60
	end
	return level
end

-- raceID, raceFile ("Human", "Scourge", ...)
function C.PlayerRace()
	local _, file, id = UnitRace("player")
	return id, file
end

-- classID, classFile ("MAGE", ...)
function C.PlayerClass()
	local _, file, id = UnitClass("player")
	return id, file
end

function C.PlayerFaction()
	return (UnitFactionGroup("player"))
end

-- The character's reputation with a faction, as the game counts it (0 is
-- the start of Neutral, 3000 of Friendly), or nil if it has never met them.
function C.Reputation(factionID)
	local reputation = _G.C_Reputation
	if reputation and reputation.GetFactionDataByID then
		local data = Try(reputation.GetFactionDataByID, factionID)
		if type(data) == "table" and data.name then
			return Clean(data.currentStanding)
		end
		return nil
	end
	local name, _, _, _, _, value = Try(_G.GetFactionInfoByID, factionID)
	if name then
		return Clean(value)
	end
	return nil
end

function C.FactionName(factionID)
	local reputation = _G.C_Reputation
	if reputation and reputation.GetFactionDataByID then
		local data = Try(reputation.GetFactionDataByID, factionID)
		return type(data) == "table" and Clean(data.name) or nil
	end
	return Clean((Try(_G.GetFactionInfoByID, factionID)))
end

-- "Friendly", "Honored", ... for a reputation value.
local STANDINGS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }

function C.StandingName(value)
	local standing = 1
	for index, threshold in ipairs(STANDINGS) do
		if value >= threshold then
			standing = index
		end
	end
	return _G["FACTION_STANDING_LABEL" .. standing] or tostring(value)
end

function C.SpellName(spellID)
	local spells = _G.C_Spell
	if spells and spells.GetSpellName then
		return Clean(Try(spells.GetSpellName, spellID))
	end
	return Clean((Try(_G.GetSpellInfo, spellID)))
end

-- Professions and secondary skills: { [skillLineID] = rank }.
function C.Professions()
	local skills = {}
	if _G.GetProfessions and _G.GetProfessionInfo then
		local list = { Try(_G.GetProfessions) }
		for i = 1, 5 do
			local index = list[i]
			if index then
				local _, _, rank, _, _, _, skillLine = Try(_G.GetProfessionInfo, index)
				if type(skillLine) == "number" then
					skills[skillLine] = rank or 0
				end
			end
		end
	end
	return skills
end

function C.KnowsSpell(spellID)
	if _G.IsPlayerSpell and Try(_G.IsPlayerSpell, spellID) then
		return true
	end
	local book = _G.C_SpellBook
	if book and book.IsSpellKnown then
		return Try(book.IsSpellKnown, spellID) == true
	end
	return Try(_G.IsSpellKnown, spellID) == true
end

-- The class name as the game shows it ("Mage").
function C.ClassName(classFile)
	local names = _G.LOCALIZED_CLASS_NAMES_MALE
	return names and names[classFile] or classFile
end

function C.ClassNameByID(classID)
	local name = Clean((Try(_G.GetClassInfo, classID)))
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

-- "Night Elf", for a race ID.
function C.RaceName(raceID)
	local creatures = _G.C_CreatureInfo
	local info = creatures and Try(creatures.GetRaceInfo, raceID)
	local name = type(info) == "table" and Clean(info.raceName)
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

local Item = _G.C_Item

-- equipLoc, icon, classID, subClassID, from the client's own item data,
-- without waiting for the server.
function C.ItemInstant(itemID)
	local fn = (Item and Item.GetItemInfoInstant) or _G.GetItemInfoInstant
	local _, _, _, equipLoc, icon, classID, subClassID = Try(fn, itemID)
	return equipLoc, icon, classID, subClassID
end

-- Everything about an item, or nil until the client has it (see RequestItem).
function C.ItemInfo(itemID)
	local fn = (Item and Item.GetItemInfo) or _G.GetItemInfo
	local name, link, quality, level, minLevel, _, _, _, equipLoc, icon, sellPrice, classID, subClassID = Try(fn, itemID)
	if not name then
		return nil
	end
	return {
		name = name,
		link = link,
		quality = quality or 1,
		level = level or 0,
		minLevel = minLevel or 0,
		equipLoc = equipLoc or "",
		icon = icon,
		sellPrice = sellPrice or 0,
		classID = classID,
		subClassID = subClassID,
	}
end

-- Stat keys (ITEM_MOD_INTELLECT_SHORT, ...) to amounts.
function C.ItemStats(link)
	local fn = (Item and Item.GetItemStats) or _G.GetItemStats
	local stats = Try(fn, link)
	if type(stats) == "table" then
		return stats
	end
	return {}
end

-- Asks for an item's data; GET_ITEM_INFO_RECEIVED or ITEM_DATA_LOAD_RESULT
-- follow.
function C.RequestItem(itemID)
	if Item and Item.RequestLoadItemDataByID then
		pcall(Item.RequestLoadItemDataByID, itemID)
	else
		Try(_G.GetItemInfo, itemID)
	end
end

-- "Cloth", "One-Handed Swords", ... as the game names them.
function C.SubClassName(classID, subClassID)
	local name = Clean(Try(Item and Item.GetItemSubClassInfo or _G.GetItemSubClassInfo, classID, subClassID))
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

function C.ItemIcon(itemID)
	local _, icon = C.ItemInstant(itemID)
	return icon or 134400 -- the question mark
end

-- r, g, b, and the hex code, of an item quality.
function C.QualityColor(quality)
	local r, g, b, hex = Try(Item and Item.GetItemQualityColor or _G.GetItemQualityColor, quality or 1)
	if r then
		return r, g, b, hex
	end
	return 1, 1, 1, "ffffffff"
end

--------------------------------------------------------------------------------
-- Maps
--------------------------------------------------------------------------------

-- A zone's name from the game (in the game's language).
function C.AreaName(areaID)
	local map = _G.C_Map
	local name = map and Clean(Try(map.GetAreaInfo, areaID))
	if type(name) == "string" and name ~= "" then
		return name
	end
	return nil
end

function C.PlayerUiMap()
	local map = _G.C_Map
	return map and Clean(Try(map.GetBestMapForUnit, "player"))
end

-- The instance's map ID, type ("party", "raid", "pvp", ...) and name when
-- inside one, else nil.
function C.Instance()
	local name, instanceType, _, _, _, _, _, instanceID = Try(_G.GetInstanceInfo)
	if instanceType and instanceType ~= "none" then
		return instanceID, instanceType, Clean(name)
	end
	return nil
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

-- 12345 -> "12,345"
function C.Number(value)
	value = floor((value or 0) + 0.5)
	local text = Try(_G.BreakUpLargeNumbers, value)
	if type(text) == "string" then
		return text
	end
	text = tostring(value)
	local count
	repeat
		text, count = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text
end

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

-- Copper as gold, silver and copper with coin icons: "1[g] 20[s]".
function C.Money(copper)
	copper = floor(copper or 0)
	local gold = floor(copper / 10000)
	local silver = floor(copper / 100) % 100
	local rest = copper % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = C.Number(gold) .. GOLD
	end
	if silver > 0 then
		parts[#parts + 1] = silver .. SILVER
	end
	if rest > 0 or #parts == 0 then
		parts[#parts + 1] = rest .. COPPER
	end
	return table.concat(parts, " ")
end

-- The color a quest of this level has for the character: red, orange,
-- yellow, green or grey.
function C.LevelColor(level, playerLevel)
	playerLevel = playerLevel or C.PlayerLevel()
	local color = Try(_G.GetRelativeDifficultyColor, playerLevel, level)
	if type(color) == "table" and color.r then
		return color.r, color.g, color.b
	end
	local diff = level - playerLevel
	if diff >= 5 then
		return 1, 0.1, 0.1
	elseif diff >= 3 then
		return 1, 0.5, 0.25
	elseif diff >= -4 then
		return 1, 0.82, 0
	end
	local range = Try(_G.UnitQuestTrivialLevelRange, "player") or Try(_G.GetQuestGreenRange) or 8
	if -diff <= range then
		return 0.25, 0.75, 0.25
	end
	return 0.5, 0.5, 0.5
end

function C.Hex(r, g, b)
	return format("ff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Misc
--------------------------------------------------------------------------------

function C.AddOnMetadata(addon, field)
	local addOns = _G.C_AddOns
	if addOns and addOns.GetAddOnMetadata then
		return addOns.GetAddOnMetadata(addon, field)
	end
	return _G.GetAddOnMetadata and _G.GetAddOnMetadata(addon, field)
end

function C.AddOnLoaded(name)
	local addOns = _G.C_AddOns
	if addOns and addOns.IsAddOnLoaded then
		return addOns.IsAddOnLoaded(name) and true or false
	end
	return _G.IsAddOnLoaded and _G.IsAddOnLoaded(name) and true or false
end

-- Adds a page to the game's AddOns options.
function C.RegisterOptionsPanel(panel, name)
	local settings = _G.Settings
	if settings and settings.RegisterCanvasLayoutCategory and settings.RegisterAddOnCategory then
		local category = settings.RegisterCanvasLayoutCategory(panel, name)
		settings.RegisterAddOnCategory(category)
		return category
	end
	if _G.InterfaceOptions_AddCategory then
		panel.name = name
		_G.InterfaceOptions_AddCategory(panel)
		return panel
	end
	return nil
end

function C.PlaySound(kit, fallback)
	local sounds = _G.SOUNDKIT
	local id = (sounds and sounds[kit]) or fallback
	if id and _G.PlaySound then
		pcall(_G.PlaySound, id)
	end
end

-- Sets a texture to an atlas the client has, or else to a file.
function C.SetIcon(texture, atlas, file)
	local textures = _G.C_Texture
	if atlas and textures and textures.GetAtlasInfo and textures.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
	end
end

-- Puts a link in the chat box being typed in, like shift-clicking an item.
-- Returns false when no chat box is open. It does not open one: a chat box an
-- addon opens is tainted, which can block the commands typed in it.
function C.InsertLink(link)
	if not link then
		return false
	end
	local util = _G.ChatFrameUtil
	local insert = util and util.InsertLink or _G.ChatEdit_InsertLink
	return Try(insert, link) and true or false
end
