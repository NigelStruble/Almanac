-- A mock of the World of Warcraft API, enough to load Almanac and drive it
-- from tests: frames, events, timers (and OnUpdate), the quest log and quest
-- cache, items, and a small QuestieDB (LibQuestieDB) of made-up quests shaped
-- like the real ones.
--
-- Frames accept the methods Almanac calls; the static check with the WoW API
-- annotations catches misspelled methods instead. What matters for the tests
-- is modelled: visibility and OnShow/OnHide, scripts, events, timers,
-- tooltips, text, and the quest and item data the client answers with.

local Mock = {}

local format = string.format

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local Methods = {}

local function CallScript(frame, script, ...)
	local state = rawget(frame, "__state")
	local handler = frame.__scripts[script]
	if handler then
		state.CallProtected(handler, frame, ...)
	end
	for _, hook in ipairs(frame.__hooks[script] or {}) do
		state.CallProtected(hook, frame, ...)
	end
end
Mock.CallScript = CallScript

function Methods:GetName()
	return self.__name
end

function Methods:GetObjectType()
	return self.__type
end

function Methods:SetParent(parent)
	rawset(self, "__parent", parent)
end

function Methods:GetParent()
	return self.__parent
end

function Methods:Show()
	if not self.__shown then
		rawset(self, "__shown", true)
		CallScript(self, "OnShow")
	end
end

function Methods:Hide()
	if self.__shown then
		rawset(self, "__shown", false)
		CallScript(self, "OnHide")
	end
end

function Methods:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end

function Methods:IsShown()
	return self.__shown
end

function Methods:IsVisible()
	local frame = self
	while frame do
		if not frame.__shown then
			return false
		end
		frame = frame.__parent
	end
	return true
end

function Methods:SetScript(script, handler)
	self.__scripts[script] = handler
end

function Methods:GetScript(script)
	return self.__scripts[script]
end

function Methods:HookScript(script, handler)
	local hooks = self.__hooks[script] or {}
	hooks[#hooks + 1] = handler
	self.__hooks[script] = hooks
end

function Methods:RegisterEvent(event)
	if not self.__state.events[event] then
		error(format("Attempt to register unknown event \"%s\"", tostring(event)), 2)
	end
	self.__events[event] = true
end

function Methods:UnregisterEvent(event)
	self.__events[event] = nil
end

function Methods:SetSize(width, height)
	rawset(self, "__width", width)
	rawset(self, "__height", height)
	CallScript(self, "OnSizeChanged", width, height)
end

function Methods:SetWidth(width)
	rawset(self, "__width", width)
end

function Methods:SetHeight(height)
	rawset(self, "__height", height)
end

-- Frames anchored on two sides take their parent's size, which is what the
-- window's lists need to lay out rows.
function Methods:GetWidth()
	if self.__width then
		return self.__width
	end
	if (self.__allPoints or #self.__points >= 2) and self.__parent then
		return self.__parent:GetWidth()
	end
	return 0
end

function Methods:GetHeight()
	if self.__height then
		return self.__height
	end
	if (self.__allPoints or #self.__points >= 2) and self.__parent then
		return self.__parent:GetHeight()
	end
	return 0
end

function Methods:GetSize()
	return self:GetWidth(), self:GetHeight()
end

function Methods:SetPoint(point, relativeTo, relativePoint, x, y)
	local points = self.__points
	if type(relativeTo) == "number" then
		relativeTo, relativePoint, x, y = self.__parent, point, relativeTo, relativePoint
	end
	points[#points + 1] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
end

function Methods:ClearAllPoints()
	rawset(self, "__points", {})
	rawset(self, "__allPoints", nil)
end

function Methods:SetAllPoints(relativeTo)
	self:ClearAllPoints()
	self.__points[1] = { "ALL", relativeTo or self.__parent }
	rawset(self, "__allPoints", relativeTo or self.__parent or true)
end

function Methods:GetPoint(index)
	local p = self.__points[index or 1]
	if p then
		return p[1], p[2], p[3], p[4], p[5]
	end
end

function Methods:GetNumPoints()
	return #self.__points
end

-- Positions are not laid out; these numbers only have to be plausible.
function Methods:GetLeft()
	return 100
end

function Methods:GetRight()
	return 100 + self:GetWidth()
end

function Methods:GetTop()
	return 900
end

function Methods:GetBottom()
	return 900 - self:GetHeight()
end

function Methods:GetCenter()
	return self:GetLeft() + self:GetWidth() / 2, self:GetBottom() + self:GetHeight() / 2
end

function Methods:SetScale(scale)
	rawset(self, "__scale", scale)
end

function Methods:GetScale()
	return self.__scale or 1
end

function Methods:GetEffectiveScale()
	return self:GetScale()
end

function Methods:SetAlpha(alpha)
	rawset(self, "__alpha", alpha)
end

function Methods:GetAlpha()
	return self.__alpha or 1
end

function Methods:EnableMouse(enable)
	rawset(self, "__mouse", enable and true or false)
end

function Methods:CreateTexture(name)
	return Mock.NewFrame(self.__state, "Texture", name, self)
end

function Methods:CreateFontString(name)
	return Mock.NewFrame(self.__state, "FontString", name, self)
end

-- Text. An edit box's OnTextChanged has userInput false when code sets it.
function Methods:SetText(text)
	rawset(self, "__text", text ~= nil and tostring(text) or nil)
	if self.__scripts.OnTextChanged then
		CallScript(self, "OnTextChanged", false)
	end
end

function Methods:GetText()
	return self.__text
end

local function Plain(text)
	return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "W"))
end
Mock.Plain = Plain

function Methods:GetStringWidth()
	return #Plain(self.__text) * 6
end

function Methods:GetStringHeight()
	return 12
end

function Methods:SetTextColor(r, g, b)
	rawset(self, "__textColor", { r, g, b })
end

function Methods:GetTextColor()
	local c = self.__textColor or { 1, 1, 1 }
	return c[1], c[2], c[3], 1
end

function Methods:SetTexture(texture)
	rawset(self, "__texture", texture)
end

function Methods:GetTexture()
	return self.__texture
end

function Methods:SetAtlas(atlas)
	rawset(self, "__atlas", atlas)
	return true
end

function Methods:SetColorTexture(r, g, b, a)
	rawset(self, "__color", { r, g, b, a })
end

function Methods:SetVertexColor(r, g, b)
	rawset(self, "__vertex", { r, g, b })
end

function Methods:SetDesaturated(desaturated)
	rawset(self, "__desaturated", desaturated and true or false)
end

function Methods:IsDesaturated()
	return self.__desaturated or false
end

-- Scroll frames, sliders, edit boxes
function Methods:SetScrollChild(child)
	rawset(self, "__scrollChild", child)
end

function Methods:SetVerticalScroll(value)
	rawset(self, "__scroll", value)
end

function Methods:GetVerticalScroll()
	return self.__scroll or 0
end

function Methods:SetMinMaxValues(low, high)
	rawset(self, "__min", low)
	rawset(self, "__max", high)
	if self.__value then
		if self.__value > high then
			self:SetValue(high)
		elseif self.__value < low then
			self:SetValue(low)
		end
	end
end

function Methods:GetMinMaxValues()
	return self.__min or 0, self.__max or 0
end

function Methods:SetValue(value)
	if self.__min and value < self.__min then
		value = self.__min
	elseif self.__max and value > self.__max then
		value = self.__max
	end
	rawset(self, "__value", value)
	CallScript(self, "OnValueChanged", value)
end

function Methods:GetValue()
	return self.__value or 0
end

function Methods:SetEnabled(enabled)
	rawset(self, "__enabled", enabled and true or false)
	CallScript(self, enabled and "OnEnable" or "OnDisable")
end

function Methods:Enable()
	self:SetEnabled(true)
end

function Methods:Disable()
	self:SetEnabled(false)
end

function Methods:IsEnabled()
	return self.__enabled ~= false
end

function Methods:SetFocus()
	if not self.__focus then
		rawset(self, "__focus", true)
		CallScript(self, "OnEditFocusGained")
	end
end

function Methods:ClearFocus()
	if self.__focus then
		rawset(self, "__focus", false)
		CallScript(self, "OnEditFocusLost")
	end
end

function Methods:HasFocus()
	return self.__focus or false
end

function Methods:SetResizable(resizable)
	rawset(self, "__resizable", resizable)
end

function Methods:SetResizeBounds(minWidth, minHeight)
	rawset(self, "__minSize", { minWidth, minHeight })
end

local function Noop() end

-- Methods Almanac calls that change nothing the tests look at. Anything not
-- here or in Methods is nil, as it would be on a real frame, so a misspelled
-- method still fails.
local NOOPS = {}
for _, name in ipairs({
	"SetMovable", "SetClampedToScreen", "SetToplevel", "SetFrameStrata", "RegisterForDrag", "RegisterForClicks",
	"SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject", "SetTextInsets", "SetAutoFocus", "SetMaxLetters",
	"SetCursorPosition", "SetTexCoord", "SetOrientation", "SetValueStep", "SetObeyStepOnDrag", "SetThumbTexture",
	"EnableMouseWheel", "Raise", "Lower", "SetFont", "UnregisterAllEvents", "SetHighlightTexture",
	"SetNormalTexture", "SetPushedTexture", "StartMoving", "StopMovingOrSizing", "StartSizing", "SetFrameLevel",
}) do
	NOOPS[name] = Noop
end

local methodIndex = setmetatable({}, {
	__index = function(_, key)
		return Methods[key] or NOOPS[key]
	end,
})

local frameMeta = { __index = methodIndex }

function Mock.NewFrame(state, frameType, name, parent, template)
	local frame = {
		__state = state,
		__type = frameType,
		__name = name,
		__parent = parent,
		__scripts = {},
		__hooks = {},
		__events = {},
		__points = {},
		__shown = true,
		__template = template,
	}
	setmetatable(frame, frameMeta)
	state.frames[#state.frames + 1] = frame
	if name then
		state.env[name] = frame
	end
	return frame
end

--------------------------------------------------------------------------------
-- The tooltip
--------------------------------------------------------------------------------

local function NewTooltip(state, name)
	local tip = Mock.NewFrame(state, "GameTooltip", name)
	rawset(tip, "__shown", false)
	tip.lines = {}

	function tip:SetOwner(owner)
		self:Hide()
		self.owner = owner
		self.item = nil
		self.lines = {}
	end

	function tip:IsOwned(frame)
		return self.owner == frame
	end

	function tip:NumLines()
		return #self.lines
	end

	function tip:SetText(text)
		self.lines = { { left = tostring(text) } }
	end

	function tip:AddLine(text)
		assert(type(text) == "string" or type(text) == "number", "AddLine: text must be a string")
		self.lines[#self.lines + 1] = { left = tostring(text) }
	end

	function tip:AddDoubleLine(left, right)
		assert(type(left) == "string" or type(left) == "number", "AddDoubleLine: left text")
		assert(type(right) == "string" or type(right) == "number", "AddDoubleLine: right text")
		self.lines[#self.lines + 1] = { left = tostring(left), right = tostring(right) }
	end

	function tip:SetItemByID(itemID)
		self.item = itemID
		local item = state.items[itemID]
		self.lines = { { left = item and item.name or "?" } }
	end

	function tip:SetHyperlink(link)
		self:SetItemByID(tonumber(link:match("item:(%d+)")))
	end

	function tip:Show()
		rawset(self, "__shown", true)
	end

	function tip:Hide()
		rawset(self, "__shown", false)
	end

	-- The tooltip as text, one line per row: "left | right", without colors.
	function tip:Text()
		local rows = {}
		for i, line in ipairs(self.lines) do
			rows[i] = Plain(line.right and (line.left .. " | " .. line.right) or line.left)
		end
		return table.concat(rows, "\n")
	end

	return tip
end

--------------------------------------------------------------------------------
-- QuestieDB
--------------------------------------------------------------------------------

local QUEST_KEYS = {
	"name", "startedBy", "finishedBy", "requiredLevel", "questLevel", "requiredRaces", "requiredClasses",
	"objectivesText", "triggerEnd", "objectives", "sourceItemId", "preQuestGroup", "preQuestSingle", "childQuests",
	"inGroupWith", "exclusiveTo", "zoneOrSort", "requiredSkill", "requiredMinRep", "requiredMaxRep",
	"requiredSourceItems", "nextQuestInChain", "questFlags", "specialFlags", "parentQuest", "reputationReward",
	"breadcrumbForQuestId", "breadcrumbs", "extraObjectives", "requiredSpell", "requiredSpecialization",
	"requiredMaxLevel", "availableUntilCompleted", "availableStartingWith", "requiredRanks", "disabledByQuest",
}

-- An entity (Quest, Item, Npc, Object) over rows of named fields, answering
-- as QuestieDB does: numbers default to 0 for a known entity, tables are
-- copies, an unknown ID reads nil.
local function Entity(rows, keys, defaults)
	local known = {}
	for _, key in ipairs(keys) do
		known[key] = true
	end
	local entity = {}
	local function Copy(value)
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for k, v in pairs(value) do
			out[k] = Copy(v)
		end
		return out
	end
	function entity.Get(id, key)
		assert(known[key], "QuestieDB has no field " .. tostring(key))
		local row = rows[id]
		if not row then
			return nil
		end
		local value = row[key]
		if value == nil then
			return defaults and defaults[key]
		end
		return Copy(value)
	end
	function entity.GetAllIds()
		local ids = {}
		for id in pairs(rows) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		return ids
	end
	function entity.Exists(id)
		return rows[id] ~= nil
	end
	return entity
end

local QUEST_DEFAULTS = {
	requiredLevel = 0, questLevel = 0, requiredRaces = 0, requiredClasses = 0, zoneOrSort = 0,
	nextQuestInChain = 0, questFlags = 0, specialFlags = 0, parentQuest = 0, breadcrumbForQuestId = 0,
	requiredSpell = 0, requiredSpecialization = 0, requiredMaxLevel = 0, availableUntilCompleted = 0,
	availableStartingWith = 0, disabledByQuest = 0, sourceItemId = 0, startedBy = {}, finishedBy = {},
}

function Mock.QuestieDB(world)
	local support = {
		QuestXP = { db = world.xp or {} },
		ZoneDB = {
			instanceIdToAreaId = world.instances or {},
			private = {
				dungeons = world.dungeons or {},
				subZoneToParentZone = "return " .. (world.subZonesSource or "{}"),
				subZoneToParentZoneOverride = "return {}",
				uiMapIdToAreaId = "return " .. (world.uiMapsSource or "{}"),
				uiMapIdToAreaIdOverride = "return {}",
			},
		},
	}
	return {
		Quest = Entity(world.quests, QUEST_KEYS, QUEST_DEFAULTS),
		Item = Entity(world.dbItems or {}, {
			"name", "npcDrops", "objectDrops", "itemDrops", "startQuest", "questRewards", "flags", "foodType",
			"itemLevel", "requiredLevel", "ammoType", "class", "subClass", "vendors", "relatedQuests", "teachesSpell",
		}),
		Npc = Entity(world.npcs or {}, {
			"name", "minLevelHealth", "maxLevelHealth", "minLevel", "maxLevel", "rank", "spawns", "waypoints",
			"zoneID", "questStarts", "questEnds", "factionID", "friendlyToFaction", "subName", "npcFlags",
		}),
		Object = Entity(world.objects or {}, { "name", "questStarts", "questEnds", "spawns", "zoneID", "factionID", "waypoints" }),
		Support = {
			Get = function(name)
				return support[name]
			end,
		},
		RequireContract = function(required)
			return required >= 1 and required <= 2, "contract"
		end,
		contractVersion = 2,
	}
end

--------------------------------------------------------------------------------
-- The client
--------------------------------------------------------------------------------

local KNOWN_EVENTS = {
	"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN",
	"QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UPDATE_FACTION", "SKILL_LINES_CHANGED",
	"LEARNED_SPELL_IN_SKILL_LINE", "QUEST_DATA_LOAD_RESULT", "QUEST_DETAIL", "QUEST_COMPLETE",
	"GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT",
}

local ITEM_CLASSES = { [2] = "Weapon", [4] = "Armor" }
local SUBCLASS_NAMES = {
	[4] = { [0] = "Miscellaneous", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields" },
	[2] = { [0] = "One-Handed Axes", [7] = "One-Handed Swords", [10] = "Staves", [15] = "Daggers", [19] = "Wands" },
}

-- options.player: { level, race (ID), class (file), classID, faction }.
function Mock.New(options)
	options = options or {}
	local player = options.player or { level = 20, race = 1, raceFile = "Human", class = "MAGE", classID = 8, faction = "Alliance" }
	local state = {
		time = 1000,
		epoch = 1790000000,
		errors = {},
		frames = {},
		timers = {},
		events = {},
		chat = {},
		player = player,
		completed = {},
		log = {}, -- ordered list of { id, complete }
		reps = {},
		professions = {},
		spells = {},
		quests = {}, -- the client's quest cache: [id] = { title, xp, money, fixed, choice }
		questCached = {}, -- [id] = true once the client has it
		questRequests = {},
		items = {}, -- [id] = { name, quality, level, minLevel, equipLoc, classID, subClassID, icon, stats }
		itemCached = {},
		itemRequests = {},
		dialog = nil, -- the quest dialog open: { questID, xp, money, fixed, choice }
		shift = false,
		chatOpen = false, -- a chat box is being typed in
		linked = {}, -- what was put in it
		uiMap = nil,
		instance = nil,
	}
	for _, event in ipairs(KNOWN_EVENTS) do
		state.events[event] = true
	end

	function state.CallProtected(func, ...)
		local ok, err = pcall(func, ...)
		if not ok then
			state.errors[#state.errors + 1] = tostring(err)
		end
	end

	local env = setmetatable({}, { __index = _G })
	env._G = env
	state.env = env

	-- Lua extras the client has
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.tinsert = table.insert
	env.securecallfunction = function(func, ...)
		return func(...)
	end
	env.geterrorhandler = function()
		return function(err)
			state.errors[#state.errors + 1] = tostring(err)
		end
	end
	env.loadstring = loadstring

	-- Time
	env.GetTime = function()
		return state.time
	end
	env.time = function()
		return state.epoch + math.floor(state.time)
	end
	env.debugprofilestop = function()
		return state.time * 1000
	end
	env.C_Timer = {
		After = function(delay, func)
			state.timers[#state.timers + 1] = { at = state.time + delay, func = func }
		end,
	}

	-- Client
	env.GetBuildInfo = function()
		return "1.60.1", "69893", "Sep 1 2026", 16001
	end
	env.InCombatLockdown = function()
		return false
	end
	env.IsShiftKeyDown = function()
		return state.shift
	end
	env.CreateFrame = function(frameType, name, parent, template)
		return Mock.NewFrame(state, frameType, name, parent, template)
	end
	env.UIParent = Mock.NewFrame(state, "Frame", "UIParent")
	env.UIParent:SetSize(1920, 1080)
	env.Minimap = Mock.NewFrame(state, "Minimap", "Minimap", env.UIParent)
	env.Minimap:SetSize(140, 140)
	state.cursor = { 0, 0 }
	env.GetCursorPosition = function()
		return state.cursor[1], state.cursor[2]
	end
	env.GameTooltip = NewTooltip(state, "GameTooltip")
	env.UISpecialFrames = {}
	env.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, message)
			state.chat[#state.chat + 1] = Plain(message)
		end,
	}
	env.SlashCmdList = {}
	env.GameFontNormal, env.GameFontHighlightSmall = {}, {}
	env.SOUNDKIT = {}
	env.PlaySound = function() end
	-- As in the game: a link goes only into a chat box already open.
	env.ChatFrameUtil = {
		InsertLink = function(link)
			if not (link and state.chatOpen) then
				return false
			end
			state.linked[#state.linked + 1] = link
			return true
		end,
	}
	env.ChatEdit_InsertLink = env.ChatFrameUtil.InsertLink -- deprecated name
	env.Settings = {
		RegisterCanvasLayoutCategory = function(panel, name)
			return { panel = panel, name = name }
		end,
		RegisterAddOnCategory = function() end,
	}
	-- An addon's .toc fields, from its file (see Mock.LoadAddon).
	state.metadata = {}
	env.C_AddOns = {
		IsAddOnLoaded = function()
			return false
		end,
		GetAddOnMetadata = function(addon, field)
			local fields = state.metadata[addon]
			if fields and fields[field] then
				return fields[field]
			end
			if field == "Version" and addon == "QuestieDB" then
				return "1.0.4"
			end
		end,
	}
	env.LOCALIZED_CLASS_NAMES_MALE = {
		WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
		SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
	}
	env.FACTION_STANDING_LABEL4 = "Neutral"
	env.FACTION_STANDING_LABEL5 = "Friendly"
	env.FACTION_STANDING_LABEL6 = "Honored"
	env.INVTYPE_CHEST = "Chest"
	env.INVTYPE_ROBE = "Chest"
	env.INVTYPE_HEAD = "Head"
	env.INVTYPE_2HWEAPON = "Two-Hand"
	env.ITEM_MOD_INTELLECT_SHORT = "Intellect"
	env.ITEM_MOD_STAMINA_SHORT = "Stamina"
	env.ITEM_MOD_STRENGTH_SHORT = "Strength"
	env.ITEM_MOD_SPIRIT_SHORT = "Spirit"
	env.RESISTANCE0_NAME = "Armor"

	-- The character
	env.UnitLevel = function()
		return player.level
	end
	env.UnitRace = function()
		return player.raceFile or "Human", player.raceFile or "Human", player.race
	end
	env.UnitClass = function()
		return env.LOCALIZED_CLASS_NAMES_MALE[player.class], player.class, player.classID
	end
	env.UnitFactionGroup = function()
		return player.faction, player.faction
	end
	env.UnitName = function()
		return "Vedek", "Md"
	end
	env.GetMaxPlayerLevel = function()
		return 60
	end
	local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
	env.C_CreatureInfo = {
		GetRaceInfo = function(raceID)
			if RACES[raceID] then
				return { raceName = RACES[raceID], raceID = raceID }
			end
		end,
	}
	local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", nil, "Shaman", "Mage", "Warlock", nil, "Druid" }
	env.GetClassInfo = function(classID)
		return CLASSES[classID]
	end
	env.C_Reputation = {
		GetFactionDataByID = function(factionID)
			local value = state.reps[factionID]
			if value == nil then
				return nil
			end
			return { factionID = factionID, name = "Faction " .. factionID, currentStanding = value }
		end,
	}
	env.GetProfessions = function()
		return 1, 2
	end
	env.GetProfessionInfo = function(index)
		local prof = state.professions[index]
		if prof then
			return prof.name, 1, prof.rank, 300, 1, 1, prof.skillLine
		end
	end
	env.IsPlayerSpell = function(spellID)
		return state.spells[spellID] == true
	end

	-- Quests
	env.C_QuestLog = {
		GetAllCompletedQuestIDs = function()
			local ids = {}
			for id in pairs(state.completed) do
				ids[#ids + 1] = id
			end
			return ids
		end,
		IsQuestFlaggedCompleted = function(id)
			return state.completed[id] == true
		end,
		GetInfo = function(index)
			local entry = state.log[index]
			if entry then
				return { questID = entry.id, isHeader = false, title = "Quest " .. entry.id }
			end
		end,
		IsComplete = function(id)
			for _, entry in ipairs(state.log) do
				if entry.id == id then
					return entry.complete == true
				end
			end
			return false
		end,
		RequestLoadQuestByID = function(id)
			state.questRequests[#state.questRequests + 1] = id
			if state.questCached[id] then
				Mock.Fire(state, "QUEST_DATA_LOAD_RESULT", id, true)
			elseif state.quests[id] then
				env.C_Timer.After(0.3, function()
					state.questCached[id] = true
					Mock.Fire(state, "QUEST_DATA_LOAD_RESULT", id, true)
				end)
			else
				env.C_Timer.After(0.3, function()
					Mock.Fire(state, "QUEST_DATA_LOAD_RESULT", id, false)
				end)
			end
		end,
		GetTitleForQuestID = function(id)
			local quest = state.questCached[id] and state.quests[id]
			return quest and quest.title
		end,
	}
	env.HaveQuestData = function(id)
		return state.questCached[id] == true
	end
	local function Cached(id)
		return state.questCached[id] and state.quests[id]
	end
	env.GetQuestLogRewardXP = function(id)
		local quest = Cached(id)
		return quest and quest.xp or 0
	end
	env.GetQuestLogRewardMoney = function(id)
		local quest = Cached(id)
		return quest and quest.money or 0
	end
	env.GetNumQuestLogRewards = function(id)
		local quest = Cached(id)
		return quest and quest.fixed and #quest.fixed or 0
	end
	env.GetQuestLogRewardInfo = function(index, id)
		local quest = Cached(id)
		local itemID = quest and quest.fixed and quest.fixed[index]
		if itemID then
			return "Item " .. itemID, 134400, 1, 2, true, itemID
		end
	end
	env.GetNumQuestLogChoices = function(id)
		local quest = Cached(id)
		return quest and quest.choice and #quest.choice or 0
	end
	env.GetQuestLogChoiceInfo = function(index, id)
		local quest = Cached(id)
		local itemID = quest and quest.choice and quest.choice[index]
		if itemID then
			return "Item " .. itemID, 134400, 1, 2, true, itemID
		end
	end
	-- On Forever the game links only the quests in the log.
	env.GetQuestLink = function(id)
		for _, entry in ipairs(state.log) do
			if entry.id == id then
				return format("|cffffff00|Hquest:%d:20|h[Quest %d]|h|r", id, id)
			end
		end
		return nil
	end
	-- The quest dialog
	env.GetQuestID = function()
		return state.dialog and state.dialog.questID or 0
	end
	env.GetRewardXP = function()
		return state.dialog and state.dialog.xp or 0
	end
	env.GetRewardMoney = function()
		return state.dialog and state.dialog.money or 0
	end
	env.GetNumQuestRewards = function()
		return state.dialog and #(state.dialog.fixed or {}) or 0
	end
	env.GetNumQuestChoices = function()
		return state.dialog and #(state.dialog.choice or {}) or 0
	end
	env.GetQuestItemInfo = function(kind, index)
		local list = state.dialog and state.dialog[kind == "choice" and "choice" or "fixed"]
		local itemID = list and list[index]
		if itemID then
			return "Item " .. itemID, 134400, 1, 2, true, itemID
		end
	end

	-- Items
	local function ItemRecord(itemID)
		local item = state.items[itemID]
		if item and state.itemCached[itemID] then
			return item
		end
	end
	env.C_Item = {
		GetItemInfoInstant = function(itemID)
			local item = state.items[itemID]
			if item then
				return itemID, ITEM_CLASSES[item.classID] or "Misc", "", item.equipLoc or "", item.icon or 134400,
					item.classID, item.subClassID
			end
		end,
		GetItemInfo = function(itemID)
			local item = ItemRecord(itemID)
			if not item then
				return nil
			end
			return item.name, format("|cff1eff00|Hitem:%d::::::::20:::::|h[%s]|h|r", itemID, item.name), item.quality or 2,
				item.level or 20, item.minLevel or 0, "", "", 1, item.equipLoc or "", item.icon or 134400, item.sell or 100,
				item.classID, item.subClassID
		end,
		GetItemStats = function(link)
			local itemID = tonumber(link:match("item:(%d+)"))
			local item = itemID and ItemRecord(itemID)
			return item and item.stats or {}
		end,
		RequestLoadItemDataByID = function(itemID)
			state.itemRequests[#state.itemRequests + 1] = itemID
			if state.items[itemID] and not state.itemCached[itemID] then
				env.C_Timer.After(0.2, function()
					state.itemCached[itemID] = true
					Mock.Fire(state, "GET_ITEM_INFO_RECEIVED", itemID, true)
				end)
			end
		end,
		GetItemQualityColor = function(quality)
			if quality == 4 then
				return 0.64, 0.21, 0.93, "ffa335ee"
			elseif quality == 3 then
				return 0, 0.44, 0.87, "ff0070dd"
			elseif quality == 2 then
				return 0.12, 1, 0, "ff1eff00"
			end
			return 1, 1, 1, "ffffffff"
		end,
		GetItemSubClassInfo = function(classID, subClassID)
			local names = SUBCLASS_NAMES[classID]
			return names and names[subClassID]
		end,
	}

	-- Maps
	env.C_Map = {
		GetAreaInfo = function(areaID)
			return state.areaNames and state.areaNames[areaID]
		end,
		GetBestMapForUnit = function()
			return state.uiMap
		end,
	}
	-- state.instance: the instance ID the character is in (and
	-- state.instanceName its name), or nil for the open world.
	env.GetInstanceInfo = function()
		if state.instance then
			return state.instanceName or "Instance", "party", 1, "Normal", 5, 0, false, state.instance
		end
		return "World", "none", 0, "", 0, 0, false, 0
	end

	return env, state
end

--------------------------------------------------------------------------------
-- Driving the client
--------------------------------------------------------------------------------

-- Loads every file of the addon's .toc into env, the way the client does:
-- each chunk gets (addonName, namespace). The .toc's "## Field: value" lines
-- are what GetAddOnMetadata answers.
function Mock.LoadAddon(env, state, dir, name)
	local ns = {}
	local fields = {}
	state.metadata[name] = fields
	local toc = assert(io.open(dir .. "/" .. name .. ".toc", "r"))
	for line in toc:lines() do
		line = line:gsub("%s+$", "")
		local key, value = line:match("^##%s*([^:]+):%s*(.*)$")
		if key then
			fields[key] = value
		elseif line ~= "" and not line:match("^#") and line:match("%.lua$") then
			local path = dir .. "/" .. line:gsub("\\", "/")
			local chunk = assert(loadfile(path))
			setfenv(chunk, env)
			local ok, err = pcall(chunk, name, ns)
			if not ok then
				state.errors[#state.errors + 1] = path .. ": " .. tostring(err)
			end
		end
	end
	toc:close()
	return ns
end

function Mock.Fire(state, event, ...)
	for _, frame in ipairs(state.frames) do
		if frame.__events[event] then
			CallScript(frame, "OnEvent", event, ...)
		end
	end
end

-- Moves the clock forward a tenth of a second at a time, running timers that
-- come due and the OnUpdate scripts of visible frames.
function Mock.Advance(state, seconds)
	local stop = state.time + seconds
	while state.time < stop do
		local step = math.min(0.1, stop - state.time)
		local now = state.time + step
		while true do
			local nextTimer, index
			for i, timer in ipairs(state.timers) do
				if timer.at <= now and (not nextTimer or timer.at < nextTimer.at) then
					nextTimer, index = timer, i
				end
			end
			if not nextTimer then
				break
			end
			table.remove(state.timers, index)
			state.time = math.max(state.time, nextTimer.at)
			state.CallProtected(nextTimer.func)
		end
		state.time = now
		for _, frame in ipairs(state.frames) do
			if frame.__scripts.OnUpdate and frame:IsVisible() then
				CallScript(frame, "OnUpdate", step)
			end
		end
	end
end

function Mock.Enter(frame)
	CallScript(frame, "OnEnter")
end

function Mock.Click(frame, button)
	CallScript(frame, "OnClick", button or "LeftButton")
end

-- Types into an edit box, as a player does.
function Mock.Type(box, text)
	rawset(box, "__text", text)
	CallScript(box, "OnTextChanged", true)
end

return Mock
