local _, ns = ...
local L, C, DB, W, Data, Player, Status, Rewards, Catalog, Tip =
	ns.L, ns.C, ns.DB, ns.W, ns.Data, ns.Player, ns.Status, ns.Rewards, ns.Catalog, ns.Tip

-- The quest pages of the window: a zone (or dungeon, or category) with its
-- quests under Available, Unavailable and Completed, each chain together; a
-- whole chain from its first quest to its last; and search results.
--
-- A chain under way (one the character has started, or can start) is listed
-- whole under Available: its done quests, the quests it can take, and those
-- only waiting for earlier quests of the chain. Its quests in other zones are
-- there too, greyed, with their zone; a long run of them is one line. What
-- needs more than the chain (a level, reputation, a profession) is under
-- Unavailable.

local QuestList = {}
ns.QuestList = QuestList

local _G = _G
local ipairs, pairs, type, format, max, min, sort, concat, tremove =
	ipairs, pairs, type, string.format, math.max, math.min, table.sort, table.concat, table.remove

local HEADER_HEIGHT = 88
local QUEST_HEIGHT = 20
local SECTION_HEIGHT = 26
local CHAIN_HEIGHT = 20
local TEXT_HEIGHT = 20
local INDENT = 14
local REWARD_ICONS = 4
local XP_WIDTH = 96
local MONEY_WIDTH = 84
local SEARCH_LIMIT = 300
-- A chain's quests from other zones are listed one by one up to this many in
-- a row; more become one line.
local LONG_RUN = 6

local GREY = "ff999999"
local DIM = "ff707070"

local SECTIONS = {
	{ key = "available", title = L["Available"], color = { 1, 0.82, 0 } },
	{ key = "unavailable", title = L["Unavailable"], color = { 1, 0.4, 0.4 } },
	{ key = "completed", title = L["Completed"], color = { 0.6, 0.6, 0.6 } },
}

-- Folded sections, for the session. Completed starts folded unless the
-- options say otherwise (see QuestList.Create).
QuestList.folded = {}

-- Within a section: quests that can be taken first, then those waiting for
-- something, done ones, and those out of reach last.
local RANK = { ready = 0, active = 0, available = 0, later = 1, done = 2, event = 3, blocked = 4, other = 5 }

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function Colored(hex, text)
	return "|c" .. hex .. text .. "|r"
end

-- "1,350" or, reduced for the character, "675 (1,350)".
local function XPText(id)
	local full, source = Rewards.FullXP(id)
	if not full then
		return Colored(DIM, "? XP")
	end
	local prefix = source == "estimate" and "~" or ""
	local yours = Rewards.XP(id) or full
	if yours < full then
		return prefix .. Colored("ffff8080", C.Number(yours)) .. Colored(GREY, " (" .. C.Number(full) .. ")")
	end
	return prefix .. C.Number(full) .. Colored(GREY, " XP")
end

local function MoneyText(id)
	local money = Rewards.Money(id)
	if not money then
		return Colored(DIM, "?")
	end
	if money == 0 then
		return Colored(DIM, "-")
	end
	return C.Money(money)
end

-- "8,450 XP (6,200 for you) · 1g 20s" for a sum of rewards.
local function TotalText(total, short)
	if total.count == 0 then
		return ""
	end
	local parts = {}
	local xp = C.Number(total.fullXP) .. " XP"
	if total.estimated then
		xp = "~" .. xp
	end
	if total.xp < total.fullXP then
		xp = xp .. Colored(GREY, format(short and " (%s)" or L[" (%s for you)"], C.Number(total.xp)))
	end
	if total.noXP > 0 and not short then
		xp = xp .. Colored(DIM, " +?")
	end
	parts[1] = xp
	-- Money: "?" while none of it is known, nothing when it is known to be none.
	if total.money > 0 then
		parts[2] = C.Money(total.money) .. (total.noMoney > 0 and Colored(DIM, " +?") or "")
	elseif total.noMoney > 0 then
		parts[2] = Colored(DIM, "?")
	end
	return concat(parts, Colored(GREY, "  ·  "))
end
QuestList.TotalText = TotalText

-- The status icons.
local ICON_AVAILABLE = { "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon" }
local ICON_REPEATABLE = { "QuestDaily", "Interface\\GossipFrame\\DailyQuestIcon" }
local ICON_TURNIN = { "QuestTurnin", "Interface\\GossipFrame\\ActiveQuestIcon" }
local ICON_ACTIVE = { nil, "Interface\\GossipFrame\\IncompleteQuestIcon" }
local ICON_DONE = { nil, "Interface\\RAIDFRAME\\ReadyCheck-Ready" }
local ICON_NO = { nil, "Interface\\RAIDFRAME\\ReadyCheck-NotReady" }

local function SetStateIcon(texture, state, repeatable)
	local icon, grey = ICON_AVAILABLE, false
	if state == "ready" then
		icon = ICON_TURNIN
	elseif state == "active" then
		icon = ICON_ACTIVE
	elseif state == "done" then
		icon = ICON_DONE
	elseif state == "blocked" or state == "other" then
		icon = ICON_NO
	elseif state == "later" or state == "event" then
		grey = true
	elseif repeatable then
		icon = ICON_REPEATABLE
	end
	C.SetIcon(texture, icon[1], icon[2])
	texture:SetDesaturated(grey)
	texture:SetAlpha(grey and 0.6 or 1)
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

local function Highlight(row)
	-- The highlight layer draws over the text, so it only tints.
	local texture = row:CreateTexture(nil, "HIGHLIGHT")
	texture:SetAllPoints()
	texture:SetColorTexture(1, 1, 1, 0.07)
	return texture
end

local function Text(parent, template, justify)
	local text = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

local function RewardIcon_OnEnter(self)
	if self.itemID then
		Tip.Item(self, self.itemID)
	end
end

local function RewardIcon_OnClick(self)
	if self.itemID and IsShiftKeyDown() then
		local item = ns.Items.Info(self.itemID)
		Tip.LinkInChat(item and item.link)
	end
end

local function QuestRow_OnEnter(self)
	if self.questID then
		Tip.Quest(self, self.questID)
		local hint = self.page:ClickHint(self.questID)
		if hint then
			GameTooltip:AddLine(hint, 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end
	end
end

local function QuestRow_OnLeave(self)
	Tip.Hide(self)
end

local function QuestRow_OnClick(self)
	local id = self.questID
	if not id then
		return
	end
	if IsShiftKeyDown() then
		Tip.LinkInChat(C.QuestLink(id, Data.QuestName(id)))
		return
	end
	self.page:QuestClicked(id)
end

local function CreateQuestRow(page)
	local row = CreateFrame("Button", nil, page.content)
	row:SetHeight(QUEST_HEIGHT)
	row:RegisterForClicks("LeftButtonUp")
	row.page = page
	row.mark = row:CreateTexture(nil, "BACKGROUND")
	row.mark:SetAllPoints()
	row.mark:SetColorTexture(1, 0.82, 0, 0.12)
	row.mark:Hide()
	Highlight(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.level = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.level:SetWidth(22)
	row.money = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.money:SetPoint("RIGHT", -4, 0)
	row.money:SetWidth(MONEY_WIDTH)
	row.xp = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.xp:SetPoint("RIGHT", row.money, "LEFT", -6, 0)
	row.xp:SetWidth(XP_WIDTH)
	row.rewards = {}
	for i = 1, REWARD_ICONS do
		local button = CreateFrame("Button", nil, row)
		button:SetSize(16, 16)
		if i == 1 then
			button:SetPoint("RIGHT", row.xp, "LEFT", -6, 0)
		else
			button:SetPoint("RIGHT", row.rewards[i - 1], "LEFT", -2, 0)
		end
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints()
		button:SetScript("OnEnter", RewardIcon_OnEnter)
		button:SetScript("OnLeave", Tip.Hide)
		button:SetScript("OnClick", RewardIcon_OnClick)
		row.rewards[i] = button
	end
	row.more = Text(row, "GameFontDisableSmall", "RIGHT")
	row.more:SetPoint("RIGHT", row.rewards[REWARD_ICONS], "LEFT", -2, 0)
	row.name = Text(row, "GameFontHighlightSmall")
	row.note = Text(row, "GameFontDisableSmall")
	row:SetScript("OnEnter", QuestRow_OnEnter)
	row:SetScript("OnLeave", QuestRow_OnLeave)
	row:SetScript("OnClick", QuestRow_OnClick)
	return row
end

-- opts.indent: steps in, opts.zone: say which zone it is in, opts.dim: grey
-- it out (a chain's quest from another part of the page).
local function SetQuestRow(row, id, opts)
	opts = opts or {}
	local quest = Data.Basics(id)
	local state, reasons = Status.Of(id)
	row.questID = id
	local x = 4 + (opts.indent or 0) * INDENT
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", x, 0)
	SetStateIcon(row.icon, state, quest.repeatable)
	row.level:ClearAllPoints()
	row.level:SetPoint("LEFT", row.icon, "RIGHT", 0, 0)
	local level = quest.level or Player.level
	row.level:SetText(level)
	row.level:SetTextColor(C.LevelColor(level, Player.level))

	-- Reward icons: the choices, then what is given anyway.
	local fixed, choice = Rewards.Items(id)
	local shown = 0
	local list = {}
	for _, entry in ipairs(choice) do
		list[#list + 1] = entry[1]
	end
	for _, entry in ipairs(fixed) do
		list[#list + 1] = entry[1]
	end
	for i, button in ipairs(row.rewards) do
		local itemID = list[i]
		button.itemID = itemID
		if itemID then
			button.icon:SetTexture(C.ItemIcon(itemID))
			button:Show()
			shown = i
		else
			button:Hide()
		end
	end
	if #list > REWARD_ICONS then
		row.more:SetText("+" .. (#list - REWARD_ICONS))
		row.more:Show()
	else
		row.more:Hide()
	end

	row.xp:SetText(XPText(id))
	row.money:SetText(MoneyText(id))

	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.level, "RIGHT", 6, 0)
	local nameColor = { 1, 1, 1 }
	if state == "done" or opts.dim then
		nameColor = { 0.55, 0.55, 0.55 }
	elseif state == "blocked" or state == "other" then
		nameColor = { 0.6, 0.45, 0.45 }
	elseif state == "later" or state == "event" then
		nameColor = { 0.8, 0.8, 0.8 }
	end
	row.name:SetText(quest.name)
	row.name:SetTextColor(nameColor[1], nameColor[2], nameColor[3])

	-- After the name: why it cannot be taken, and which zone it is in.
	local notes = {}
	if opts.zone then
		notes[#notes + 1] = Data.ZoneName(Data.ZoneKey(quest.zone))
	end
	if state == "ready" then
		notes[#notes + 1] = Colored("ff40ff40", L["ready to turn in"])
	elseif state == "active" then
		notes[#notes + 1] = Colored("ffffd100", L["in your quest log"])
	elseif reasons and reasons[1] then
		notes[#notes + 1] = Status.ReasonText(reasons[1])
	end
	if quest.repeatable then
		notes[#notes + 1] = Colored("ff66b3ff", L["repeatable"])
	end
	row.note:SetText(concat(notes, "  ·  "))
	row.note:ClearAllPoints()
	-- The name takes what it needs; the note what is left before the icons.
	local right = shown > 0 and row.rewards[shown] or row.xp
	if #list > REWARD_ICONS then
		right = row.more
	end
	local room = (row:GetWidth() or 400) - (x + 14 + 22 + 6) - (XP_WIDTH + MONEY_WIDTH + 16) - shown * 18 - 10
	row.name:SetWidth(0)
	local wanted = (row.name.GetUnboundedStringWidth and row.name:GetUnboundedStringWidth() or row.name:GetStringWidth()) + 2
	row.name:SetWidth(min(wanted, max(80, room)))
	row.note:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
	row.note:SetPoint("RIGHT", right, "LEFT", -6, 0)
	row.mark:SetShown(opts.marked == true)
end

local function Section_OnClick(self)
	local folded = QuestList.folded
	folded[self.key] = not folded[self.key]
	C.PlaySound("U_CHAT_SCROLL_BUTTON", 1115)
	self.page:Refresh()
end

local function CreateSectionRow(page)
	local row = CreateFrame("Button", nil, page.content)
	row:SetHeight(SECTION_HEIGHT)
	row.page = page
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetPoint("TOPLEFT", 0, -3)
	row.bg:SetPoint("BOTTOMRIGHT", 0, 1)
	row.bg:SetColorTexture(1, 1, 1, 0.05)
	Highlight(row)
	row.arrow = Text(row, "GameFontNormal")
	row.arrow:SetPoint("LEFT", 6, -1)
	row.title = Text(row, "GameFontNormal")
	row.title:SetPoint("LEFT", 22, -1)
	row.total = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.total:SetPoint("RIGHT", -6, -1)
	row:SetScript("OnClick", Section_OnClick)
	return row
end

-- elsewhere: how many of the count are a chain's quests in other zones.
local function SetSectionRow(row, section, count, total, elsewhere)
	row.key = section.key
	local folded = QuestList.folded[section.key]
	row.arrow:SetText(folded and "+" or "-")
	local title = format("%s  |cff999999(%d)|r", section.title, count)
	if elsewhere and elsewhere > 0 then
		title = title .. "  " .. Colored(DIM, format(L["%d in other zones"], elsewhere))
	end
	row.title:SetText(title)
	row.title:SetTextColor(section.color[1], section.color[2], section.color[3])
	row.total:SetText(TotalText(total, true))
end

local function Chain_OnEnter(self)
	if self.chain then
		Tip.Chain(self, self.chain)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Click to see the whole chain."], 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end
end

local function Chain_OnClick(self)
	if self.chain then
		self.page:ShowChain(self.chain)
	end
end

local function CreateChainRow(page)
	local row = CreateFrame("Button", nil, page.content)
	row:SetHeight(CHAIN_HEIGHT)
	row.page = page
	Highlight(row)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", 4, 0)
	C.SetIcon(row.icon, "Campaign-QuestLog-LoreBook", "Interface\\Icons\\Achievement_Quests_Completed_08")
	row.name = Text(row, "GameFontNormalSmall")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetTextColor(0.5, 0.8, 1)
	row.total = Text(row, "GameFontHighlightSmall", "RIGHT")
	row.total:SetPoint("RIGHT", -4, 0)
	row.note = Text(row, "GameFontDisableSmall")
	row.note:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
	row.note:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
	row:SetScript("OnEnter", Chain_OnEnter)
	row:SetScript("OnLeave", Tip.Hide)
	row:SetScript("OnClick", Chain_OnClick)
	return row
end

-- A chain's heading in a section: its name, how far along it is, where else
-- it goes, and what is left of all of it.
local function SetChainRow(row, chain, zoneKey)
	row.chain = chain
	local done, open = 0, {}
	for _, id in ipairs(chain.quests) do
		local state = Status.Of(id)
		if state == "done" then
			done = done + 1
		elseif Status.Open(id) then
			open[#open + 1] = id
		end
	end
	row.name:SetText(chain.name)
	local notes = { format(L["%d of %d done"], done, #chain.quests) }
	local elsewhere = {}
	for key in pairs(chain.zones) do
		if key ~= zoneKey then
			elsewhere[#elsewhere + 1] = Data.ZoneName(key)
		end
	end
	sort(elsewhere)
	if #elsewhere > 0 then
		notes[#notes + 1] = format(L["also %s"], concat(elsewhere, ", "))
	end
	row.note:SetText(concat(notes, "  ·  "))
	local total = Rewards.Sum(open)
	row.total:SetText(total.count > 0 and (Colored(GREY, L["chain left: "]) .. TotalText(total, true)) or "")
end

local function CreateTextRow(page)
	local row = CreateFrame("Frame", nil, page.content)
	row:SetHeight(TEXT_HEIGHT)
	row.text = Text(row, "GameFontDisableSmall")
	row.text:SetPoint("LEFT", 26, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	return row
end

-- A long run of a chain's quests in another zone, as one line: "8 quests in
-- Elwynn Forest, 2 done". A click shows the whole chain.
local function CreateContextRow(page)
	local row = CreateFrame("Button", nil, page.content)
	row:SetHeight(QUEST_HEIGHT)
	row.page = page
	Highlight(row)
	-- Lined up with the quests' names.
	row.text = Text(row, "GameFontDisableSmall")
	row.text:SetPoint("LEFT", 4 + INDENT + 14 + 22 + 6, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnEnter", Chain_OnEnter)
	row:SetScript("OnLeave", Tip.Hide)
	row:SetScript("OnClick", Chain_OnClick)
	return row
end

local function SetContextRow(row, line)
	row.chain = line.chain
	local zone = Data.ZoneName(line.zone)
	if line.done > 0 then
		row.text:SetText(format(L["%d quests in %s, %d done"], line.count, zone, line.done))
	else
		row.text:SetText(format(L["%d quests in %s"], line.count, zone))
	end
end

local KINDS = {
	quest = { create = CreateQuestRow, height = QUEST_HEIGHT },
	section = { create = CreateSectionRow, height = SECTION_HEIGHT },
	chain = { create = CreateChainRow, height = CHAIN_HEIGHT },
	context = { create = CreateContextRow, height = QUEST_HEIGHT },
	text = { create = CreateTextRow, height = TEXT_HEIGHT },
}

--------------------------------------------------------------------------------
-- What a page shows
--------------------------------------------------------------------------------

local function Level(id)
	local quest = Data.Basics(id)
	return quest.level or quest.reqLevel or 0
end

-- A section's quests, each chain's together under its name: a list of
-- { chain, quests } and { quest }, by level.
local function Entries(ids)
	local entries, byChain = {}, {}
	for _, id in ipairs(ids) do
		local chain = Catalog.chainOf[id]
		if chain then
			local entry = byChain[chain]
			if not entry then
				entry = { chain = chain, quests = {}, rank = 9, level = 999 }
				byChain[chain] = entry
				entries[#entries + 1] = entry
			end
			entry.quests[#entry.quests + 1] = id
		else
			entries[#entries + 1] = { quest = id, quests = { id }, rank = 9, level = 999 }
		end
	end
	for _, entry in ipairs(entries) do
		for _, id in ipairs(entry.quests) do
			entry.rank = min(entry.rank, RANK[(Status.Of(id))] or 5)
			entry.level = min(entry.level, Level(id))
		end
		if entry.chain then
			local order = {}
			for index, id in ipairs(entry.chain.quests) do
				order[id] = index
			end
			sort(entry.quests, function(a, b)
				return order[a] < order[b]
			end)
		end
	end
	sort(entries, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.quests[1] < b.quests[1]
	end)
	return entries
end

-- Quests the character can never take are left out unless the options show
-- them.
local function Shown(id)
	local state = Status.Of(id)
	return DB.settings.showBlocked or (state ~= "blocked" and state ~= "other")
end

-- Splits quests by section: by chain (Status.Section), or, in search
-- results, each on its own, where a done quest is always Completed.
local function Split(ids, byChain)
	local sections = { available = {}, unavailable = {}, completed = {} }
	for _, id in ipairs(ids) do
		if Shown(id) then
			local key
			if byChain then
				key = Status.Section(id)
			elseif Status.Of(id) == "done" then
				key = "completed"
			else
				key = Status.Reachable(id) and "available" or "unavailable"
			end
			local list = sections[key]
			list[#list + 1] = id
		end
	end
	return sections
end

-- A section's count and totals, for its quests here and its chains' quests
-- elsewhere that it lists: under Available the quests left to do (a chain's
-- done quests are only there to show it whole); under Unavailable every
-- quest listed, with the totals of those that can still be done one day;
-- under Completed all. Also returns how many of the count are elsewhere.
local function Tally(key, list, elsewhere)
	local count, others, sum = 0, 0, {}
	local function Add(id, other)
		local state = Status.Of(id)
		if key ~= "available" or state ~= "done" then
			count = count + 1
			if other then
				others = others + 1
			end
		end
		if (key == "completed" and state == "done") or (key ~= "completed" and Status.Open(id)) then
			sum[#sum + 1] = id
		end
	end
	for _, id in ipairs(list) do
		Add(id, false)
	end
	for _, id in ipairs(elsewhere or {}) do
		Add(id, true)
	end
	return count, Rewards.Sum(sum), others
end

-- Sums for a page's header: what is left to do, and what is done.
local function Totals(ids)
	local open, done = {}, {}
	for _, id in ipairs(ids) do
		if Status.Of(id) == "done" then
			done[#done + 1] = id
		elseif Status.Open(id) then
			open[#open + 1] = id
		end
	end
	return Rewards.Sum(open), Rewards.Sum(done)
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local prototype = {}

function prototype:Acquire(kind)
	local pool = self.pools[kind]
	local row = tremove(pool.free)
	if not row then
		row = KINDS[kind].create(self)
	end
	pool.used[#pool.used + 1] = row
	row:ClearAllPoints()
	row:Show()
	return row
end

function prototype:ReleaseAll()
	for _, pool in pairs(self.pools) do
		for _, row in ipairs(pool.used) do
			row:Hide()
			pool.free[#pool.free + 1] = row
		end
		pool.used = {}
	end
end

-- Lines are { kind, ... }; laid out top to bottom.
function prototype:Draw(lines)
	self:ReleaseAll()
	local y = 0
	local width = self.scroll:GetWidth() - 12
	for _, line in ipairs(lines) do
		local row = self:Acquire(line.kind)
		row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
		row:SetWidth(max(200, width))
		if line.kind == "quest" then
			SetQuestRow(row, line.id, line)
			if line.id == self.marked then
				self.markedY = y
			end
		elseif line.kind == "section" then
			SetSectionRow(row, line.section, line.count, line.total, line.elsewhere)
		elseif line.kind == "chain" then
			SetChainRow(row, line.chain, self.zoneKey)
		elseif line.kind == "context" then
			SetContextRow(row, line)
		else
			row.text:SetText(line.text)
		end
		y = y + KINDS[line.kind].height
	end
	self.scroll:SetContentHeight(y + 8)
end

-- A chain's quests in a section, in the chain's order: this page's, and its
-- quests elsewhere that go in the same section, greyed with their zone. More
-- than LONG_RUN in a row from one zone are one line. The quests elsewhere are
-- added to the list elsewhere.
function prototype:ChainLines(lines, entry, key, onPage, elsewhere)
	local here = {}
	for _, id in ipairs(entry.quests) do
		here[id] = true
	end
	local run = {}
	local function Flush()
		if #run > LONG_RUN then
			local done = 0
			for _, id in ipairs(run) do
				if Status.Of(id) == "done" then
					done = done + 1
				end
			end
			lines[#lines + 1] = { kind = "context", chain = entry.chain, zone = run.zone, count = #run, done = done }
		else
			for _, id in ipairs(run) do
				lines[#lines + 1] = { kind = "quest", id = id, indent = 1, zone = true, dim = true }
			end
		end
		run = {}
	end
	for _, id in ipairs(entry.chain.quests) do
		if here[id] then
			Flush()
			lines[#lines + 1] = { kind = "quest", id = id, indent = 1, marked = id == self.marked }
		elseif not onPage[id] and Shown(id) and Status.Section(id) == key then
			local zone = Data.ZoneKey(Data.Basics(id).zone)
			if run.zone ~= zone then
				Flush()
				run.zone = zone
			end
			run[#run + 1] = id
			elsewhere[#elsewhere + 1] = id
		end
	end
	Flush()
end

-- The three sections of a list of quests: a zone's, by chain; or search
-- results (opts.flat), each quest on its own with its zone. A zone's page
-- also keeps the chains' quests it lists from other zones in self.elsewhere.
function prototype:SectionLines(ids, opts)
	local lines = {}
	local sections = Split(ids, not opts.flat)
	local onPage = {}
	for _, id in ipairs(ids) do
		onPage[id] = true
	end
	self.elsewhere = {}
	for _, section in ipairs(SECTIONS) do
		local list = sections[section.key]
		-- Worked out even when folded: its count and totals need them.
		local body, elsewhere = {}, {}
		if #list == 0 then
			body[1] = { kind = "text", text = L["None"] }
		elseif opts.flat then
			sort(list, Catalog.ByLevel)
			for _, id in ipairs(list) do
				body[#body + 1] = { kind = "quest", id = id, zone = true, marked = id == self.marked }
			end
		else
			for _, entry in ipairs(Entries(list)) do
				if entry.chain then
					body[#body + 1] = { kind = "chain", chain = entry.chain }
					self:ChainLines(body, entry, section.key, onPage, elsewhere)
				else
					body[#body + 1] = { kind = "quest", id = entry.quest, marked = entry.quest == self.marked }
				end
			end
		end
		local count, total, others = Tally(section.key, list, elsewhere)
		lines[#lines + 1] = { kind = "section", section = section, count = count, total = total, elsewhere = others }
		if not QuestList.folded[section.key] then
			for _, line in ipairs(body) do
				lines[#lines + 1] = line
			end
		end
		for _, id in ipairs(elsewhere) do
			self.elsewhere[#self.elsewhere + 1] = id
		end
	end
	return lines
end

-- byChain: count the sections as a zone's page lists them. On a zone's page,
-- a last line gives what is left counting the chains' quests elsewhere that
-- the page lists (self.elsewhere, from SectionLines).
function prototype:SetHeader(title, sub, ids, byChain)
	self.title:SetText(title)
	self.sub:SetText(sub or "")
	self.more:SetText("")
	if not ids then
		self.counts:SetText("")
		self.totals:SetText("")
		return
	end
	local sections = Split(ids, byChain)
	local available = Tally("available", sections.available)
	local completed = 0
	for _, id in ipairs(ids) do
		if Status.Of(id) == "done" then
			completed = completed + 1
		end
	end
	self.counts:SetText(format("|cffffd100%s %d|r     |cffff6666%s %d|r     |cff999999%s %d|r",
		L["Available"], available, L["Unavailable"], #sections.unavailable, L["Completed"], completed))
	local left, done = Totals(ids)
	local parts = {}
	if left.count > 0 then
		parts[#parts + 1] = Colored(GREY, L["Left to do: "]) .. TotalText(left)
	end
	if done.count > 0 then
		parts[#parts + 1] = Colored(GREY, L["Done: "]) .. TotalText(done, true)
	end
	self.totals:SetText(concat(parts, "      "))

	if byChain and self.kind == "zone" and self.elsewhere then
		local open, others = {}, 0
		for _, id in ipairs(ids) do
			if Status.Open(id) then
				open[#open + 1] = id
			end
		end
		for _, id in ipairs(self.elsewhere) do
			if Status.Open(id) then
				open[#open + 1] = id
				others = others + 1
			end
		end
		if others > 0 then
			self.more:SetText(Colored(GREY, format(L["With the chains' %d quests in other zones: "], others))
				.. TotalText(Rewards.Sum(open)))
		end
	end
end

-- "Getting rewards from the server (12)" while quests are being asked for.
function prototype:UpdateLoading()
	local pending = Rewards.Pending()
	if pending > 0 then
		self.loading:SetText(format(L["Getting rewards from the server (%d)"], pending))
	else
		self.loading:SetText("")
	end
end

-- A zone, dungeon or category.
function prototype:ShowZone(key, marked)
	if self.kind and not (self.kind == "zone" and self.zoneKey == key) then
		self:Remember()
	end
	self.kind, self.zoneKey, self.chain, self.text = "zone", key, nil, nil
	self.marked = marked
	self.markedY = nil
	self:Refresh(true)
end

-- A whole chain, from its first quest to its last.
function prototype:ShowChain(chain)
	self:Remember()
	self.kind, self.chain, self.text, self.marked = "chain", chain, nil, nil
	self:Refresh(true)
end

-- Quests whose name has the text in it.
function prototype:ShowSearch(text)
	if self.kind ~= "search" then
		self:Remember()
	end
	self.kind, self.text, self.chain, self.marked = "search", text, nil, nil
	self:Refresh(true)
end

-- Where Back goes.
function prototype:Remember()
	if self.kind then
		local history = self.history
		history[#history + 1] = { kind = self.kind, zoneKey = self.zoneKey, chain = self.chain, text = self.text }
		if #history > 20 then
			tremove(history, 1)
		end
	end
end

function prototype:Back()
	local last = tremove(self.history)
	if not last then
		return
	end
	self.kind, self.zoneKey, self.chain, self.text, self.marked = last.kind, last.zoneKey, last.chain, last.text, nil
	if self.OnNavigate then
		self.OnNavigate(self)
	end
	self:Refresh(true)
end

-- What a click on a quest does, for its tooltip.
function prototype:ClickHint(id)
	if self.kind == "zone" then
		return Catalog.chainOf[id] and L["Click to see its whole chain."] or nil
	end
	return L["Click to go to its zone."]
end

function prototype:QuestClicked(id)
	if self.kind == "zone" then
		local chain = Catalog.chainOf[id]
		if chain then
			self:ShowChain(chain)
		end
		return
	end
	local quest = Data.Basics(id)
	if quest then
		self:ShowZone(Data.ZoneKey(quest.zone), id)
		if self.OnNavigate then
			self.OnNavigate(self)
		end
	end
end

function prototype:Refresh(toTop)
	if not self.kind then
		return
	end
	self.back:SetShown(#self.history > 0)
	if not Catalog.ready then
		self:SetHeader(L["Almanac"], L["Reading the quest database..."])
		self:Draw({})
		return
	end
	local lines, ids
	if self.kind == "zone" then
		local zone = Catalog.zones[self.zoneKey]
		ids = zone and zone.quests or {}
		local sub = {}
		for _, group in ipairs(Data.GROUPS) do
			if zone and group.key == zone.group then
				sub[#sub + 1] = group.name
			end
		end
		if zone and zone.low then
			sub[#sub + 1] = zone.low == zone.high and format(L["level %d"], zone.low) or format(L["levels %d-%d"], zone.low, zone.high)
		end
		sub[#sub + 1] = format(L["%d quests"], #ids)
		lines = self:SectionLines(ids, {})
		self:SetHeader(zone and zone.name or Data.ZoneName(self.zoneKey), concat(sub, "  ·  "), ids, true)
	elseif self.kind == "chain" then
		local chain = self.chain
		ids = chain.quests
		local zones = {}
		for key in pairs(chain.zones) do
			zones[#zones + 1] = Data.ZoneName(key)
		end
		sort(zones)
		self:SetHeader(chain.name, format(L["A chain of %d quests"], #ids) .. "  ·  " .. concat(zones, ", "), ids, true)
		lines = {}
		local here
		for _, id in ipairs(ids) do
			local zone = Data.ZoneKey(Data.Basics(id).zone)
			lines[#lines + 1] = { kind = "quest", id = id, indent = chain.depth[id] or 0, zone = zone ~= here }
			here = zone
		end
	else
		ids = Catalog.Search(self.text or "")
		local more = #ids > SEARCH_LIMIT
		while #ids > SEARCH_LIMIT do
			ids[#ids] = nil
		end
		self:SetHeader(format(L["Quests named \"%s\""], self.text or ""),
			more and format(L["The first %d found"], SEARCH_LIMIT) or format(L["%d found"], #ids), ids, false)
		lines = self:SectionLines(ids, { flat = true })
	end
	-- The rewards of everything on the page, a chain's quests elsewhere too.
	local wanted = {}
	for _, id in ipairs(ids) do
		wanted[#wanted + 1] = id
	end
	for _, line in ipairs(lines) do
		if line.kind == "quest" and line.dim then
			wanted[#wanted + 1] = line.id
		end
	end
	Rewards.Want(wanted)
	self:UpdateLoading()
	self:Draw(lines)
	if toTop then
		local target = 0
		if self.markedY then
			target = max(0, self.markedY - 60)
		end
		self.scroll.bar:SetValue(target)
	end
end

function QuestList.Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	for key, fn in pairs(prototype) do
		page[key] = fn
	end
	page.pools = {}
	for kind in pairs(KINDS) do
		page.pools[kind] = { free = {}, used = {} }
	end
	page.history = {}
	QuestList.folded.completed = not DB.settings.completedOpen

	page.title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	page.title:SetPoint("TOPLEFT", 8, -6)
	page.title:SetPoint("RIGHT", -150, 0)
	page.title:SetJustifyH("LEFT")
	page.title:SetWordWrap(false)
	page.sub = Text(page, "GameFontHighlightSmall")
	page.sub:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
	page.sub:SetPoint("RIGHT", -8, 0)
	page.sub:SetTextColor(0.7, 0.7, 0.7)
	page.counts = Text(page, "GameFontHighlightSmall")
	page.counts:SetPoint("TOPLEFT", page.sub, "BOTTOMLEFT", 0, -6)
	page.totals = Text(page, "GameFontHighlightSmall")
	page.totals:SetPoint("TOPLEFT", page.counts, "BOTTOMLEFT", 0, -5)
	page.totals:SetPoint("RIGHT", -8, 0)
	page.more = Text(page, "GameFontHighlightSmall")
	page.more:SetPoint("TOPLEFT", page.totals, "BOTTOMLEFT", 0, -5)
	page.more:SetPoint("RIGHT", -8, 0)
	page.loading = Text(page, "GameFontDisableSmall", "RIGHT")
	page.loading:SetPoint("TOPRIGHT", -8, -34)
	page.back = W.Button(page, L["< Back"], 70, 20, function()
		page:Back()
	end)
	page.back:SetPoint("TOPRIGHT", -6, -6)
	page.back:Hide()

	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT + 2)
	line:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT + 2)
	line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.1)

	local scroll, content = W.ScrollFrame(page)
	scroll:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	page.scroll, page.content = scroll, content
	return page
end
