local ADDON, ns = ...
local L, C, DB, W, Data, Player, Status, Catalog, Skin =
	ns.L, ns.C, ns.DB, ns.W, ns.Data, ns.Player, ns.Status, ns.Catalog, ns.Skin

-- The window: a header with Quests, Rewards and Options and a search box; on
-- the left the zone list (or, on the Rewards page, its filters); on the right
-- the page.

local Window = {}
ns.Window = Window

local ipairs, pairs, type, format, max, floor, lower, tremove =
	ipairs, pairs, type, string.format, math.max, math.floor, string.lower, table.remove

local SIDEBAR_WIDTH = 236
local BODY_TOP = -66
local GROUP_HEIGHT = 22
local ZONE_HEIGHT = 18
local MIN_WIDTH, MIN_HEIGHT = 820, 480

local frame

--------------------------------------------------------------------------------
-- The zone list
--------------------------------------------------------------------------------

local function Group_OnClick(self)
	DB.collapsed[self.key] = not DB.collapsed[self.key] or nil
	C.PlaySound("U_CHAT_SCROLL_BUTTON", 1115)
	Window.RefreshZones()
end

local function Zone_OnClick(self)
	C.PlaySound("U_CHAT_SCROLL_BUTTON", 1115)
	Window.SelectZone(self.key)
end

local function Zone_OnEnter(self)
	local zone = Catalog.zones[self.key]
	if not zone then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(zone.name, 1, 1, 1)
	if zone.low then
		GameTooltip:AddLine(zone.low == zone.high and format(L["Level %d"], zone.low)
			or format(L["Levels %d-%d"], zone.low, zone.high), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine(format(L["%d quests, %d you can take now"], #zone.quests, self.available or 0), 1, 0.82, 0)
	GameTooltip:Show()
end

local function CreateGroupRow(list)
	local row = CreateFrame("Button", nil, list.content)
	row:SetHeight(GROUP_HEIGHT)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)
	row.arrow = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.arrow:SetPoint("LEFT", 4, 0)
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.name:SetPoint("LEFT", 18, 0)
	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.count:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnClick", Group_OnClick)
	return row
end

local function CreateZoneRow(list)
	local row = CreateFrame("Button", nil, list.content)
	row:SetHeight(ZONE_HEIGHT)
	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	W.Paint(row.selected, W.COLORS.selected)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)
	row.here = row:CreateTexture(nil, "ARTWORK")
	row.here:SetSize(10, 10)
	row.here:SetPoint("LEFT", 5, 0)
	C.SetIcon(row.here, "Waypoint-MapPin-ChatIcon", "Interface\\Minimap\\Tracking\\None")
	row.levels = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.levels:SetPoint("RIGHT", -6, 0)
	row.levels:SetJustifyH("RIGHT")
	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	row.count:SetPoint("RIGHT", -44, 0)
	row.count:SetJustifyH("RIGHT")
	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 18, 0)
	row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row:SetScript("OnClick", Zone_OnClick)
	row:SetScript("OnEnter", Zone_OnEnter)
	row:SetScript("OnLeave", W.HideTooltip)
	return row
end

local function CreateZoneList(parent)
	local scroll, content = W.ScrollFrame(parent)
	scroll:SetAllPoints()
	local list = { scroll = scroll, content = content, groups = { free = {}, used = {} }, zones = { free = {}, used = {} } }

	local function Acquire(pool, create)
		local row = tremove(pool.free) or create(list)
		pool.used[#pool.used + 1] = row
		row:ClearAllPoints()
		row:Show()
		return row
	end

	-- How many of a zone's quests the character can take now.
	local function Available(zone)
		local count = 0
		for _, id in ipairs(zone.quests) do
			local state = Status.Of(id)
			if state == "available" then
				count = count + 1
			end
		end
		return count
	end

	function list:Refresh(filter)
		for _, pool in pairs({ self.groups, self.zones }) do
			for _, row in ipairs(pool.used) do
				row:Hide()
				pool.free[#pool.free + 1] = row
			end
			pool.used = {}
		end
		local y = 0
		local width = max(100, scroll:GetWidth() - 12)
		local here = Window.here
		local selected = frame.quests.kind == "zone" and frame.quests.zoneKey
		filter = filter and filter ~= "" and lower(filter) or nil
		for _, group in ipairs(Catalog.groups) do
			local zones = {}
			for _, zone in ipairs(group.zones) do
				if not filter or lower(zone.name):find(filter, 1, true) then
					zones[#zones + 1] = zone
				end
			end
			if #zones > 0 then
				local folded = DB.collapsed[group.key] and not filter
				local row = Acquire(self.groups, CreateGroupRow)
				row.key = group.key
				row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
				row:SetWidth(width)
				row.arrow:SetText(folded and "+" or "-")
				row.name:SetText(group.name)
				row.count:SetText(#zones)
				y = y + GROUP_HEIGHT
				if not folded then
					for _, zone in ipairs(zones) do
						local zoneRow = Acquire(self.zones, CreateZoneRow)
						zoneRow.key = zone.key
						zoneRow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
						zoneRow:SetWidth(width)
						zoneRow.name:SetText(zone.name)
						zoneRow.here:SetShown(zone.key == here)
						zoneRow.selected:SetShown(zone.key == selected)
						local available = Available(zone)
						zoneRow.available = available
						zoneRow.count:SetText(available > 0 and available or "")
						if zone.low then
							zoneRow.levels:SetText(zone.low == zone.high and zone.low or (zone.low .. "-" .. zone.high))
							local r, g, b = C.LevelColor(zone.high, Player.level)
							zoneRow.levels:SetTextColor(r, g, b)
						else
							zoneRow.levels:SetText("")
						end
						y = y + ZONE_HEIGHT
					end
				end
			end
		end
		scroll:SetContentHeight(y + 4)
	end

	return list
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

local SEARCH_ICON = "Interface\\Common\\UI-Searchbox-Icon"

local function SearchBox(parent)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetSize(230, 20)
	box:SetAutoFocus(false)
	box:SetFontObject(GameFontHighlightSmall)
	box.bg = W.Background(box, W.COLORS.control)
	W.Border(box)
	box.icon = box:CreateTexture(nil, "OVERLAY")
	C.SetIcon(box.icon, "common-search-magnifyingglass", SEARCH_ICON)
	box.icon:SetSize(11, 11)
	box.icon:SetPoint("LEFT", 5, 0)
	box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.placeholder:SetPoint("LEFT", 18, 0)
	box:SetTextInsets(18, 20, 0, 0)

	-- The x at the end empties the box and lets go of the keyboard.
	local clear = CreateFrame("Button", nil, box)
	clear:SetSize(16, 16)
	clear:SetPoint("RIGHT", -2, 0)
	clear.icon = clear:CreateTexture(nil, "ARTWORK")
	C.SetIcon(clear.icon, "common-search-clearbutton", "Interface\\FriendsFrame\\ClearBroadcastIcon")
	clear.icon:SetSize(10, 10)
	clear.icon:SetPoint("CENTER")
	clear.icon:SetAlpha(0.6)
	clear:SetScript("OnEnter", function(self)
		self.icon:SetAlpha(1)
	end)
	clear:SetScript("OnLeave", function(self)
		self.icon:SetAlpha(0.6)
	end)
	clear:SetScript("OnClick", function()
		box:SetText("")
		box:ClearFocus()
		Window.Search("")
	end)
	clear:Hide()
	box.clear = clear
	local function UpdateClear(self)
		self.clear:SetShown(self:GetText() ~= "" or self:HasFocus())
	end

	-- Typing searches; text set by code (a page's own search, when switching
	-- pages) does not.
	local Search = C.Debounce(0.25, function()
		Window.Search(box:GetText())
	end)
	box:SetScript("OnTextChanged", function(self, userInput)
		self.placeholder:SetShown(self:GetText() == "")
		UpdateClear(self)
		if userInput ~= false then
			Search()
		end
	end)
	box:SetScript("OnEditFocusGained", UpdateClear)
	box:SetScript("OnEditFocusLost", UpdateClear)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		Window.Search("")
	end)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	return box
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local MODES = { "quests", "rewards", "options" }

local function ShowMode(mode)
	frame.mode = mode
	for _, key in ipairs(MODES) do
		frame.tabs[key]:SetSelected(key == mode)
	end
	frame.quests:SetShown(mode == "quests")
	frame.rewards:SetShown(mode == "rewards")
	frame.options:SetShown(mode == "options")
	frame.zoneList.scroll:SetShown(mode ~= "rewards")
	frame.rewards.filters:SetShown(mode == "rewards")
	frame.search.placeholder:SetText(mode == "rewards" and L["Search reward names"] or L["Search zones and quests"])
	W.CloseMenu()
end

function Window.SelectZone(key)
	if not frame then
		return
	end
	if frame.search:GetText() ~= "" then
		frame.search:SetText("")
		frame.searchText = ""
	end
	if frame.mode ~= "quests" then
		ShowMode("quests")
	end
	frame.quests:ShowZone(key)
	Window.RefreshZones()
end

-- The search box: on the quest pages it narrows the zone list and lists the
-- quests with the text in their name; on the Rewards page it looks for
-- reward names.
function Window.Search(text)
	if not frame then
		return
	end
	if frame.mode == "rewards" then
		frame.rewards:SetText(text)
		return
	end
	frame.searchText = text
	if frame.mode == "options" then
		ShowMode("quests")
	end
	if text ~= "" and #text >= 2 then
		frame.quests:ShowSearch(text)
	elseif frame.quests.kind == "search" then
		frame.quests:Back()
	end
	Window.RefreshZones()
end

function Window.RefreshZones()
	if frame and Catalog.ready then
		frame.zoneList:Refresh(frame.searchText)
	end
end

-- Everything brought up to date.
function Window.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	if not Data.ready then
		frame.problem:SetText(Data.problem or "")
		frame.problem:Show()
		return
	end
	if not Catalog.ready and frame.mode == "quests" then
		frame.problem:SetText(L["Reading the quest database..."])
		frame.problem:Show()
		return
	end
	frame.problem:Hide()
	Window.here = Data.PlayerZoneKey()
	Window.RefreshZones()
	if frame.mode == "quests" then
		frame.quests:Refresh()
	elseif frame.mode == "rewards" then
		frame.rewards:Refresh()
	else
		frame.options:Refresh()
	end
end

local QueueRefresh = C.Debounce(0.15, Window.Refresh)

-- The zone the window starts on: where the character is, else the last one
-- looked at, else the first.
local function StartingZone()
	local here = Data.PlayerZoneKey()
	if here and Catalog.zones[here] then
		return here
	end
	local last = frame.quests.zoneKey
	if last and Catalog.zones[last] then
		return last
	end
	local first = Catalog.groups[1]
	return first and first.zones[1] and first.zones[1].key
end

--------------------------------------------------------------------------------
-- Position and size
--------------------------------------------------------------------------------

local function SavePosition()
	local x, y = frame:GetLeft() or 0, (frame:GetTop() or 0) - UIParent:GetHeight() / frame:GetScale()
	DB.positions.main = { "TOPLEFT", x, y }
end

local function RestorePosition()
	local saved = DB.positions.main
	frame:ClearAllPoints()
	if type(saved) == "table" and saved[1] then
		frame:SetPoint(saved[1], UIParent, saved[1], saved[2] or 0, saved[3] or 0)
	else
		frame:SetPoint("CENTER")
	end
end

local function ApplyScale()
	frame:SetScale(DB.settings.scale)
	RestorePosition()
end

local function MakeResizable()
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 2000, 1400)
	elseif frame.SetMinResize then
		frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
	end
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		DB.Set("width", floor(frame:GetWidth() + 0.5))
		DB.Set("height", floor(frame:GetHeight() + 0.5))
		SavePosition()
		QueueRefresh()
	end)
	frame:SetScript("OnSizeChanged", function()
		QueueRefresh()
	end)
end

--------------------------------------------------------------------------------
-- Creating it
--------------------------------------------------------------------------------

local function Create()
	local version = C.AddOnMetadata(ADDON, "Version")
	local width = max(MIN_WIDTH, DB.settings.width)
	local height = max(MIN_HEIGHT, DB.settings.height)
	frame = W.Window("AlmanacFrame", L["Almanac"] .. (version and ("  |cff808080" .. version .. "|r") or ""), width, height)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	MakeResizable()

	-- Header: the pages, the search box, and the character's own zone.
	frame.tabs = {}
	local x = 10
	for _, info in ipairs({ { "quests", L["Quests"] }, { "rewards", L["Rewards"] }, { "options", L["Options"] } }) do
		local tab = W.Button(frame, info[2], 90, 24, function()
			ShowMode(info[1])
			-- Each page keeps its own search.
			if info[1] == "rewards" then
				frame.search:SetText(frame.rewards.text or "")
			else
				frame.search:SetText(frame.searchText or "")
			end
			Window.Refresh()
		end)
		tab:SetPoint("TOPLEFT", x, -36)
		frame.tabs[info[1]] = tab
		x = x + 94
	end
	frame.hereButton = W.Button(frame, L["Your zone"], 90, 24, function()
		local here = Data.PlayerZoneKey()
		if here and Catalog.zones[here] then
			Window.SelectZone(here)
		else
			ns.Print(L["Almanac has no quests for where you are."])
		end
	end, L["Shows the zone or dungeon you are in."])
	frame.hereButton:SetPoint("TOPRIGHT", -10, -36)
	frame.search = SearchBox(frame)
	frame.search:SetPoint("RIGHT", frame.hereButton, "LEFT", -8, 0)
	frame.searchText = ""

	-- Body.
	local sidebar = CreateFrame("Frame", nil, frame)
	sidebar:SetPoint("TOPLEFT", 8, BODY_TOP)
	sidebar:SetPoint("BOTTOMLEFT", 8, 8)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	W.Background(sidebar, W.COLORS.panel)
	frame.sidebar = sidebar
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
	content:SetPoint("BOTTOMRIGHT", -8, 22)
	frame.content = content

	frame.zoneList = CreateZoneList(sidebar)
	frame.quests = ns.QuestList.Create(content)
	frame.quests:SetAllPoints()
	frame.quests.OnNavigate = function()
		Window.RefreshZones()
	end
	frame.rewards = ns.RewardSearch.Create(content, sidebar)
	frame.rewards:SetAllPoints()
	frame.rewards.OnQuest = function(questID)
		local quest = Data.Basics(questID)
		if quest and Catalog.kept[questID] then
			ShowMode("quests")
			frame.search:SetText("")
			frame.searchText = ""
			frame.quests:ShowZone(Data.ZoneKey(quest.zone), questID)
			Window.RefreshZones()
		end
	end
	frame.options = ns.Options.Create(content)
	frame.options:SetAllPoints()

	frame.problem = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.problem:SetPoint("TOPLEFT", content, "TOPLEFT", 20, -40)
	frame.problem:SetPoint("RIGHT", content, "RIGHT", -20, 0)
	frame.problem:SetJustifyH("LEFT")
	frame.problem:Hide()

	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, -16)
	frame.hint:SetPoint("RIGHT", content, "RIGHT", -20, 0)
	frame.hint:SetJustifyH("LEFT")
	frame.hint:SetText(L["XP in red is what you get at your level; the quest's full XP is in brackets. ? means the game has not said yet."])

	-- The window opens on the zone the character is in when that has changed
	-- since it was last opened, and else where it was left.
	frame:SetScript("OnShow", function()
		Player.Read()
		local here = Data.ready and Data.PlayerZoneKey()
		if here and here ~= Window.lastHere and Catalog.ready and Catalog.zones[here] then
			Window.lastHere = here
			frame.quests:ShowZone(here)
		end
		Window.Refresh()
	end)
	frame:SetScript("OnHide", function()
		W.CloseMenu()
	end)

	ns.Listen("catalog", function()
		if frame.quests.kind == nil or (frame.quests.kind == "zone" and not Catalog.zones[frame.quests.zoneKey]) then
			local start = StartingZone()
			if start then
				frame.quests.kind, frame.quests.zoneKey = "zone", start
			end
			Window.lastHere = Data.PlayerZoneKey()
		end
		ns.Items.Scan()
		QueueRefresh()
	end)
	for _, what in ipairs({ "player", "rewards", "items", "looks" }) do
		ns.Listen(what, QueueRefresh)
	end
	ns.Listen("filters", function()
		if frame:IsShown() and frame.mode == "rewards" then
			frame.rewards:Refresh(true)
		end
	end)
	ns.Listen("settings", function(key)
		if key == "scale" then
			ApplyScale()
		end
		QueueRefresh()
	end)

	Skin.Apply(function(S)
		if S.Shell then
			S.Shell(frame)
		end
		if S.CloseButton then
			S.CloseButton(frame.close)
			-- EllesmereUI draws its own X over the button; the button's is
			-- text, which its skin leaves, so it would show two.
			frame.close.text:SetText("")
		end
		if S.EditBox then
			S.EditBox(frame.search)
		end
		if S.Button then
			for _, tab in pairs(frame.tabs) do
				S.Button(tab)
			end
			S.Button(frame.hereButton)
		end
	end)

	ShowMode("quests")
	ApplyScale()
end

--------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------

-- what: "quests", "rewards" or "options"; text: for the search box.
function Window.Open(what, text)
	if not frame then
		Create()
	end
	if Data.Init() and not Catalog.ready and not Catalog.building then
		Catalog.Build()
	end
	if what then
		ShowMode(what)
	end
	frame:Show()
	frame:Raise()
	if text and text ~= "" then
		frame.search:SetText(text)
		Window.Search(text)
	end
	Window.Refresh()
end

function Window.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Window.Open()
	end
end

function Window.Frame()
	return frame
end
