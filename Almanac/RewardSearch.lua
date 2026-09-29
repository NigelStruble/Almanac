local _, ns = ...
local L, C, DB, W, Data, Player, Status, Items, Tip =
	ns.L, ns.C, ns.DB, ns.W, ns.Data, ns.Player, ns.Status, ns.Items, ns.Tip

-- The Rewards page: every item a quest rewards, narrowed down by slot, armor
-- or weapon type, stat, level and quality, to the items the character can use
-- from the quests it can do now (or by a chain it can do now), or can still do
-- one day. Each item says which quest gives it, from what level; a click goes
-- to that quest.

local RewardSearch = {}
ns.RewardSearch = RewardSearch

local _G = _G
local ipairs, pairs, format, max, concat, tremove = ipairs, pairs, string.format, math.max, table.concat, table.remove

local ROW_HEIGHT = 38
local FILTER_WIDTH = 214

local QUALITIES = {
	{ value = 0, text = L["Any quality"] },
	{ value = 2, text = L["Uncommon or better"] },
	{ value = 3, text = L["Rare or better"] },
	{ value = 4, text = L["Epic"] },
}

local SORTS = {
	{ value = "level", text = L["Item level"] },
	{ value = "reqlevel", text = L["Level you can have it at"],
		tooltip = L["The level the item needs, or the level its quest needs if that is higher; the lowest first."] },
	{ value = "stat", text = L["Most of the chosen stat"] },
	{ value = "name", text = L["Name"] },
}

local function Get(key)
	return function()
		return DB.settings[key]
	end
end

local function Set(key)
	return function(value)
		DB.Set(key, value)
		ns.Send("filters")
	end
end

--------------------------------------------------------------------------------
-- Result rows
--------------------------------------------------------------------------------

-- "Chest · Cloth · item level 25 · level 20 · +7 Intellect, +5 Stamina"
local function Describe(item, classID, subClassID)
	local parts = {}
	local slot = item.equipLoc ~= "" and _G[item.equipLoc]
	if slot then
		parts[#parts + 1] = slot
	end
	local kind = C.SubClassName(classID, subClassID)
	if kind and (classID == 2 or (classID == 4 and subClassID and subClassID > 0)) then
		parts[#parts + 1] = kind
	end
	if item.level and item.level > 0 then
		parts[#parts + 1] = format(L["item level %d"], item.level)
	end
	if item.minLevel and item.minLevel > 1 then
		parts[#parts + 1] = format(L["requires level %d"], item.minLevel)
	end
	local stats = {}
	for key, amount in pairs(item.stats or {}) do
		if key ~= "RESISTANCE0_NAME" and type(amount) == "number" then
			stats[#stats + 1] = format("%+d %s", amount, Items.StatName(key))
		end
	end
	table.sort(stats)
	if #stats > 0 then
		parts[#parts + 1] = concat(stats, ", ")
	end
	return concat(parts, "  ·  ")
end

local function Row_OnEnter(self)
	local result = self.result
	if not result then
		return
	end
	Tip.Item(self, result.id, "ANCHOR_RIGHT")
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Rewarded by"], 1, 0.82, 0)
	for _, questID in ipairs(result.quests) do
		local quest = Data.Basics(questID)
		local state = Status.Of(questID)
		local color = Tip.STATE_COLORS[state]
		local where = quest and Data.ZoneName(Data.ZoneKey(quest.zone)) or ""
		if quest and quest.reqLevel > 1 then
			where = where .. "  ·  " .. format(L["from level %d"], quest.reqLevel)
		end
		local name = quest and quest.level and format("[%d] %s", quest.level, quest.name) or Data.QuestName(questID)
		GameTooltip:AddDoubleLine(name, where, color[1], color[2], color[3], 0.6, 0.6, 0.6)
	end
	if result.level > Player.level then
		GameTooltip:AddLine(format(L["You can have it from level %d."], result.level), 1, 0.4, 0.4)
	end
	GameTooltip:AddLine(L["Click to go to the quest."], 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function Row_OnClick(self)
	local result = self.result
	if not result then
		return
	end
	if IsShiftKeyDown() then
		Tip.LinkInChat(result.item.link)
		return
	end
	local questID = result.quests[1]
	if questID and self.page.OnQuest then
		self.page.OnQuest(questID)
	end
end

local function CreateRow(page)
	local row = CreateFrame("Button", nil, page.content)
	row:SetHeight(ROW_HEIGHT)
	row.page = page
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(30, 30)
	row.icon:SetPoint("LEFT", 6, 0)
	row.quest = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.quest:SetPoint("TOPRIGHT", -6, -5)
	row.quest:SetJustifyH("RIGHT")
	row.quest:SetWordWrap(false)
	row.zone = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.zone:SetPoint("BOTTOMRIGHT", -6, 5)
	row.zone:SetJustifyH("RIGHT")
	row.zone:SetWordWrap(false)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
	row.name:SetPoint("RIGHT", row.quest, "LEFT", -10, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.info = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
	row.info:SetPoint("RIGHT", row.zone, "LEFT", -10, 0)
	row.info:SetJustifyH("LEFT")
	row.info:SetWordWrap(false)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Tip.Hide)
	row:SetScript("OnClick", Row_OnClick)
	return row
end

local function SetRow(row, result)
	row.result = result
	local item = result.item
	local _, classID, subClassID, icon = Items.Basic(result.id)
	row.icon:SetTexture(item.icon or icon or 134400)
	local r, g, b = C.QualityColor(item.quality)
	row.name:SetText(item.name)
	row.name:SetTextColor(r, g, b)
	row.info:SetText(Describe(item, classID, subClassID))
	-- The quest it comes from, its zone, the level the quest needs, and what
	-- it waits for.
	local questID = result.quests[1]
	local quest = questID and Data.Basics(questID)
	local text = questID and Data.QuestName(questID) or ""
	if quest and quest.level then
		text = format("[%d] %s", quest.level, text)
	end
	if #result.quests > 1 then
		text = text .. format(" |cff999999+%d|r", #result.quests - 1)
	end
	row.quest:SetText(text)
	local state = questID and Status.Of(questID)
	local color = state and Tip.STATE_COLORS[state] or { 1, 1, 1 }
	row.quest:SetTextColor(color[1], color[2], color[3])
	local parts = { quest and Data.ZoneName(Data.ZoneKey(quest.zone)) or "" }
	if quest and quest.reqLevel > 1 then
		parts[#parts + 1] = format(L["quest from level %d"], quest.reqLevel)
	end
	local reason = questID and Status.Summary(questID)
	if reason and not (quest and reason == format(L["Requires level %d"], quest.reqLevel)) then
		parts[#parts + 1] = reason
	end
	row.zone:SetText(concat(parts, "  ·  "))
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local prototype = {}

function prototype:Filters()
	local settings = DB.settings
	return {
		slot = settings.rewardSlot,
		type = settings.rewardType,
		stat = settings.rewardStat,
		usable = settings.rewardUsable,
		quests = settings.rewardQuests,
		maxLevel = settings.rewardMaxLevel,
		quality = settings.rewardQuality,
		sort = settings.rewardSort,
		text = self.text,
	}
end

function prototype:SetText(text)
	self.text = text
	self:Refresh(true)
end

function prototype:Refresh(toTop)
	for _, row in ipairs(self.used) do
		row:Hide()
		self.free[#self.free + 1] = row
	end
	self.used = {}
	if not Items.ready then
		Items.Scan()
		self.note:SetText(format(L["Reading which quests reward which items... %d%%"], Items.progress * 100))
		self.scroll:SetContentHeight(1)
		return
	end
	local results, waiting = Items.Search(self:Filters())
	local shown = math.min(#results, 400)
	local note = format(L["%d items"], #results)
	if #results > shown then
		note = format(L["%d items, the first %d shown"], #results, shown)
	end
	if waiting > 0 then
		note = note .. "  ·  " .. format(L["getting %d more from the server"], waiting)
	end
	self.note:SetText(note)
	local width = max(300, self.scroll:GetWidth() - 12)
	for i = 1, shown do
		local row = tremove(self.free) or CreateRow(self)
		self.used[#self.used + 1] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		row:SetWidth(width)
		SetRow(row, results[i])
		row:Show()
	end
	self.empty:SetShown(shown == 0 and waiting == 0)
	self.scroll:SetContentHeight(shown * ROW_HEIGHT + 8)
	if toTop then
		self.scroll.bar:SetValue(0)
	end
end

-- The filters go in the window's left column (sidebar); the results in the
-- page.
function RewardSearch.Create(parent, sidebar)
	local page = CreateFrame("Frame", nil, parent)
	for key, fn in pairs(prototype) do
		page[key] = fn
	end
	page.used, page.free = {}, {}

	page.title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	page.title:SetPoint("TOPLEFT", 8, -6)
	page.title:SetText(L["Quest rewards"])
	page.note = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	page.note:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
	page.note:SetPoint("RIGHT", -8, 0)
	page.note:SetJustifyH("LEFT")
	page.note:SetTextColor(0.7, 0.7, 0.7)
	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 0, -44)
	line:SetPoint("TOPRIGHT", 0, -44)
	line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.1)
	local scroll, content = W.ScrollFrame(page)
	scroll:SetPoint("TOPLEFT", 0, -46)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	page.scroll, page.content = scroll, content
	page.empty = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	page.empty:SetPoint("TOP", scroll, "TOP", 0, -30)
	page.empty:SetText(L["No quest reward matches."])
	page.empty:Hide()

	-- The filters.
	local filters = CreateFrame("Frame", nil, sidebar)
	filters:SetAllPoints()
	page.filters = filters
	local y = -4
	local function Add(widget, height)
		widget:SetPoint("TOPLEFT", filters, "TOPLEFT", 6, y)
		y = y - (height or widget:GetHeight()) - 8
		return widget
	end
	Add(W.Header(filters, L["Find a reward"], FILTER_WIDTH))
	Add(W.Dropdown(filters, L["Slot"], FILTER_WIDTH, Items.SLOTS, Get("rewardSlot"), Set("rewardSlot")))
	Add(W.Dropdown(filters, L["Armor or weapon type"], FILTER_WIDTH, function()
		local list = {}
		for i, entry in ipairs(Items.TYPES) do
			list[i] = { value = entry.value, text = Items.TypeName(entry) }
		end
		return list
	end, Get("rewardType"), Set("rewardType")))
	Add(W.Dropdown(filters, L["Has the stat"], FILTER_WIDTH, Items.StatChoices, Get("rewardStat"), Set("rewardStat")))
	Add(W.Dropdown(filters, L["Quality"], FILTER_WIDTH, QUALITIES, Get("rewardQuality"), Set("rewardQuality")))
	Add(W.Dropdown(filters, L["From quests you"], FILTER_WIDTH, Items.QUEST_MODES, Get("rewardQuests"), Set("rewardQuests"), {
		tooltip = L["Which quests the rewards may come from. \"Can do now, or by a chain\" is the quests you can take now, and those at the end of a chain you can do now."],
	}))
	Add(W.Slider(filters, L["Up to level (0: any)"], 0, 60, 1, Get("rewardMaxLevel"), Set("rewardMaxLevel"), {
		width = FILTER_WIDTH,
		tooltip = L["Leaves out items that need a higher level, and items whose quest needs a higher level."],
	}))
	page.usable = Add(W.Checkbox(filters, format(L["Only what a %s can use"], C.ClassName(Player.classFile or "")),
		Get("rewardUsable"), Set("rewardUsable"),
		L["Leaves out armor and weapons your class cannot use, counting mail and plate from level 40 for the classes that learn them then, at the level you can have the item."]))
	Add(W.Dropdown(filters, L["Sort by"], FILTER_WIDTH, SORTS, Get("rewardSort"), Set("rewardSort")))
	local hint = W.Note(filters, L["Type in the search box at the top to look for part of an item's name."], FILTER_WIDTH)
	Add(hint, hint:GetStringHeight())
	return page
end
