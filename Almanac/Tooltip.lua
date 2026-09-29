local _, ns = ...
local L, C, DB, Data, Player, Status, Rewards, Catalog = ns.L, ns.C, ns.DB, ns.Data, ns.Player, ns.Status, ns.Rewards, ns.Catalog

-- The tooltips of quests, chains and reward items.

local Tip = {}
ns.Tip = Tip

local _G = _G
local ipairs, type, format, floor = ipairs, type, string.format, math.floor

local GREY = { 0.6, 0.6, 0.6 }
local WHITE = { 1, 1, 1 }
local GOLD = { 1, 0.82, 0 }
local RED = { 1, 0.35, 0.35 }
local GREEN = { 0.3, 1, 0.3 }

local STATE_COLORS = {
	done = GREY,
	ready = GREEN,
	active = GOLD,
	available = GOLD,
	later = RED,
	blocked = RED,
	event = RED,
	other = RED,
}
Tip.STATE_COLORS = STATE_COLORS

local function Line(tooltip, text, color, wrap)
	color = color or WHITE
	tooltip:AddLine(text, color[1], color[2], color[3], wrap)
end

local function Pair(tooltip, left, right, leftColor, rightColor)
	leftColor, rightColor = leftColor or GREY, rightColor or WHITE
	tooltip:AddDoubleLine(left, right, leftColor[1], leftColor[2], leftColor[3], rightColor[1], rightColor[2], rightColor[3])
end

-- "Westfall (56.3, 47.5)" for where an NPC or object stands.
local function Place(zone, x, y)
	if not zone then
		return nil
	end
	local name = Data.ZoneName(Data.ZoneKey(zone))
	if x and y and x >= 0 and y >= 0 then
		return format("%s (%.1f, %.1f)", name, x, y)
	end
	return name
end

-- Who starts or ends a quest: "Gryan Stoutmantle, Westfall (56.3, 47.5)".
local function Givers(entry)
	local names = {}
	if type(entry) ~= "table" then
		return names
	end
	for _, id in ipairs(type(entry[1]) == "table" and entry[1] or {}) do
		local name = Data.NpcName(id)
		if name then
			local place = Place(Data.NpcSpot(id))
			names[#names + 1] = place and (name .. ", " .. place) or name
		end
	end
	for _, id in ipairs(type(entry[2]) == "table" and entry[2] or {}) do
		local name = Data.ObjectName(id)
		if name then
			local place = Place(Data.ObjectSpot(id))
			names[#names + 1] = place and (name .. ", " .. place) or name
		end
	end
	for _, id in ipairs(type(entry[3]) == "table" and entry[3] or {}) do
		local item = C.ItemInfo(id) or Data.Item(id)
		if item then
			names[#names + 1] = format(L["%s (an item)"], item.name)
		end
	end
	return names
end

-- "|Ticon|t Name" in the item's quality color, and the count if more than one.
function Tip.ItemText(itemID, count)
	local icon = C.ItemIcon(itemID)
	local item = ns.Items.Info(itemID)
	local name, hex = nil, "ffffffff"
	if item then
		name = item.name
		local _, _, _, qualityHex = C.QualityColor(item.quality)
		hex = qualityHex or hex
	else
		local known = Data.Item(itemID)
		name = known and known.name or (L["Item"] .. " " .. itemID)
	end
	local text = format("|T%s:0|t |c%s%s|r", icon, hex, name)
	if count and count > 1 then
		text = text .. " x" .. count
	end
	return text
end

-- "1,350 XP" and what the character gets, with where the number comes from.
local function AddXP(tooltip, id)
	local full, source, ratio = Rewards.FullXP(id)
	if not full then
		Pair(tooltip, L["XP"], L["not known"])
		return
	end
	local text = C.Number(full)
	if source == "turnin" then
		text = text .. " |cff808080" .. L["(seen at turn-in)"] .. "|r"
	elseif source == "reported" then
		text = text .. " |cff808080" .. L["(as reported for Forever)"] .. "|r"
	elseif source == "journal" then
		text = text .. " |cff808080" .. L["(as Forever Dungeon Journal has it)"] .. "|r"
	elseif source == "estimate" then
		text = "~" .. text .. " |cff808080" .. format(L["(estimated: quests here gave %.1fx)"], ratio) .. "|r"
	end
	Pair(tooltip, L["XP"], text)
	local yours = Rewards.XP(id)
	if Player.level >= Player.maxLevel then
		Pair(tooltip, L["Your XP"], L["none at the highest level"], GREY, GREY)
	elseif yours and yours < full then
		Pair(tooltip, L["Your XP"], format(L["%s (%d%%, you are %d levels above it)"], C.Number(yours),
			floor(yours / full * 100 + 0.5), Player.level - (Data.Basics(id).level or Player.level)), GREY, RED)
	end
end

local function AddItems(tooltip, id)
	local fixed, choice, source = Rewards.Items(id)
	if #fixed == 0 and #choice == 0 then
		return
	end
	if source == "database" then
		Line(tooltip, L["Rewards"], GOLD)
	elseif #fixed > 0 then
		Line(tooltip, L["You receive"], GOLD)
	end
	for _, entry in ipairs(fixed) do
		Line(tooltip, "  " .. Tip.ItemText(entry[1], entry[2]))
	end
	if #choice > 0 then
		Line(tooltip, L["Choose one of"], GOLD)
		for _, entry in ipairs(choice) do
			Line(tooltip, "  " .. Tip.ItemText(entry[1], entry[2]))
		end
	end
end

-- Everything about a quest.
function Tip.Quest(owner, id, anchor)
	local tooltip = GameTooltip
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	local quest = Data.Basics(id)
	if not quest then
		tooltip:SetText(Data.QuestName(id), 1, 1, 1)
		tooltip:Show()
		return
	end
	local level = quest.level or Player.level
	local r, g, b = C.LevelColor(level, Player.level)
	tooltip:SetText(format("[%d] %s", level, quest.name), r, g, b)

	local key = Data.ZoneKey(quest.zone)
	Line(tooltip, Data.ZoneName(key), GREY)
	local state, reasons = Status.Of(id)
	Line(tooltip, Status.StateText(state), STATE_COLORS[state])
	for _, reason in ipairs(reasons or {}) do
		Line(tooltip, "  " .. Status.ReasonText(reason), RED, true)
	end
	if quest.repeatable then
		Line(tooltip, L["Repeatable"], { 0.4, 0.7, 1 })
	end

	local chain = Catalog.chainOf[id]
	if chain then
		local step, steps = Catalog.Step(id)
		Line(tooltip, format(L["Part %d of %d of %s"], step, steps, chain.name), { 0.5, 0.8, 1 }, true)
	end

	tooltip:AddLine(" ")
	if quest.reqLevel > 0 then
		Pair(tooltip, L["Requires level"], quest.reqLevel)
	end
	local details = Data.Details(id)
	local starts, ends = Givers(details.startedBy), Givers(details.finishedBy)
	-- New Forever quests say it in words, with where when they know it.
	local function Said(text, spot)
		text = type(text) == "string" and text or spot and spot.label
		local place = text and spot and Place(spot.zone, spot.x, spot.y)
		return place and (text .. ", " .. place) or text
	end
	if #starts == 0 then
		starts[1] = Said(details.startText, details.startSpot)
	end
	if #ends == 0 then
		ends[1] = Said(details.endText, details.endSpot)
	end
	for _, giver in ipairs(starts) do
		Pair(tooltip, L["Starts"], giver)
	end
	for _, giver in ipairs(ends) do
		Pair(tooltip, L["Ends"], giver)
	end
	AddXP(tooltip, id)
	local money = Rewards.Money(id)
	if money == 0 then
		Pair(tooltip, L["Money"], L["none"])
	else
		Pair(tooltip, L["Money"], money and C.Money(money) or L["not listed yet"])
	end
	for _, entry in ipairs(details.reputation or {}) do
		local name = C.FactionName(entry[1]) or (L["Faction"] .. " " .. entry[1])
		Pair(tooltip, L["Reputation"], format("%+d %s", entry[2], name))
	end
	AddItems(tooltip, id)

	local objectives = details.objectives
	if objectives and objectives[1] then
		tooltip:AddLine(" ")
		for i, text in ipairs(objectives) do
			if i > 3 then
				break
			end
			Line(tooltip, text, GREY, true)
		end
	end

	tooltip:AddLine(" ")
	local source = Data.Source(id)
	if source == "almanac" then
		Line(tooltip, L["New in WoW: Forever: QuestieDB does not have this quest yet."], GREY, true)
	elseif source == "journal" then
		Line(tooltip, L["From Forever Dungeon Journal: QuestieDB does not have this quest yet."], GREY, true)
	end
	if DB.settings.questIDs then
		Line(tooltip, L["Quest ID"] .. " " .. id, GREY)
	end
	Line(tooltip, L["Shift-click to link it in chat."], GREY)
	tooltip:Show()
end

-- A chain: its steps, and what is left of it.
function Tip.Chain(owner, chain, anchor)
	local tooltip = GameTooltip
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	tooltip:SetText(chain.name, 0.5, 0.8, 1)
	local done = 0
	local left = {}
	for _, id in ipairs(chain.quests) do
		if Status.Of(id) == "done" then
			done = done + 1
		elseif Status.Open(id) then
			left[#left + 1] = id
		end
	end
	Line(tooltip, format(L["%d quests, %d done"], #chain.quests, done), GREY)
	local total = Rewards.Sum(left)
	if total.count > 0 then
		Pair(tooltip, L["XP left"], C.Number(total.xp) .. (total.fullXP > total.xp and (" (" .. C.Number(total.fullXP) .. ")") or ""))
		if total.money > 0 then
			Pair(tooltip, L["Money left"], C.Money(total.money) .. (total.noMoney > 0 and " +?" or ""))
		elseif total.noMoney > 0 then
			Pair(tooltip, L["Money left"], L["not listed yet"])
		end
	end
	tooltip:AddLine(" ")
	local here
	for _, id in ipairs(chain.quests) do
		local quest = Data.Basics(id)
		local state = Status.Of(id)
		local zone = Data.ZoneKey(quest.zone)
		local text = format("%s[%d] %s", string.rep("  ", chain.depth[id] or 0), quest.level or Player.level, quest.name)
		if zone ~= here then
			text = text .. " |cff808080(" .. Data.ZoneName(zone) .. ")|r"
			here = zone
		end
		Line(tooltip, text, STATE_COLORS[state])
	end
	tooltip:Show()
end

function Tip.Item(owner, itemID, anchor)
	local tooltip = GameTooltip
	tooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	if tooltip.SetItemByID then
		tooltip:SetItemByID(itemID)
	else
		tooltip:SetHyperlink("item:" .. itemID)
	end
	tooltip:Show()
end

-- Shift-click: puts a link in the chat box being typed in, or says to open
-- one first.
function Tip.LinkInChat(link)
	if link and not C.InsertLink(link) then
		ns.Print(L["Open the chat box first (Enter), then shift-click to link it."])
	end
end

function Tip.Hide(owner)
	if GameTooltip:IsOwned(owner) then
		GameTooltip:Hide()
	end
end
