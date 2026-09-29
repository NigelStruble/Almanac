local _, ns = ...
local L, C, DB, W, Catalog = ns.L, ns.C, ns.DB, ns.W, ns.Catalog

-- The Options page of the window, and a page in the game's AddOns options
-- that opens it.

local Options = {}
ns.Options = Options

local _G = _G
local pairs, format, max = pairs, string.format, math.max

local WIDTH = 420

local function Get(key)
	return function()
		return DB.settings[key]
	end
end

-- Options that change which quests are listed rebuild the list.
local function Set(key, rebuild)
	return function(value)
		DB.Set(key, value)
		if rebuild then
			Catalog.Build()
		end
		ns.Send("settings", key)
	end
end

-- Stacks widgets top to bottom.
local function NewColumn(parent, x, y)
	local column = { parent = parent, x = x, y = y }
	function column:Add(widget, height)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x, self.y)
		widget:Show()
		if not height then
			if widget.GetStringHeight then
				height = max(12, widget:GetStringHeight())
			else
				height = widget:GetHeight()
			end
		end
		self.y = self.y - height - 6
		return widget
	end
	function column:Skip(height)
		self.y = self.y - height
	end
	return column
end

-- What the saved data holds, for the page's last note.
local function Learned()
	local count = 0
	for _ in pairs(DB.learned) do
		count = count + 1
	end
	return count
end

function Options.Create(parent)
	local page = CreateFrame("Frame", nil, parent)
	-- It scrolls when the window is too short for it.
	local scroll, body = W.ScrollFrame(page)
	scroll:SetAllPoints()
	local column = NewColumn(body, 12, -8)

	column:Add(W.Header(body, L["Which quests are listed"], WIDTH))
	column:Add(W.Checkbox(body, L["The other faction's quests"], Get("otherFaction"), Set("otherFaction", true),
		L["Lists quests only the other faction can take, under Unavailable."]))
	column:Add(W.Checkbox(body, L["Other races' quests"], Get("otherRaces"), Set("otherRaces", true),
		L["Lists quests only other races of your faction can take, under Unavailable."]))
	column:Add(W.Checkbox(body, L["Other classes' quests"], Get("otherClasses"), Set("otherClasses", true),
		L["Lists other classes' quests, under Unavailable, and their class categories."]))
	column:Add(W.Checkbox(body, L["Quests you can no longer take"], Get("showBlocked"), Set("showBlocked"),
		L["Quests ruled out by another quest you took, breadcrumbs to quests you already have, and quests for lower levels only. They go at the end of Unavailable."]))
	local hidden = column:Add(W.Checkbox(body, L["Quests Questie hides"], Get("showHidden"), Set("showHidden", true),
		L["Questie hides quests that are not in the game, duplicates, and world event quests out of season. Almanac hides them too while Questie is running."]))
	hidden:SetActive(Catalog.QuestieHidden() ~= nil)
	page.hidden = hidden

	column:Skip(8)
	column:Add(W.Header(body, L["Totals, tooltips and buttons"], WIDTH))
	column:Add(W.Checkbox(body, L["Count repeatable quests in the totals"], Get("repeatableTotals"), Set("repeatableTotals"),
		L["Repeatable quests can be done again and again, so they are left out of the XP and money totals unless this is on."]))
	column:Add(W.Checkbox(body, L["Open the Completed section"], Get("completedOpen"), function(value)
		DB.Set("completedOpen", value)
		ns.QuestList.folded.completed = not value
		ns.Send("settings", "completedOpen")
	end, L["Otherwise it starts folded up."]))
	column:Add(W.Checkbox(body, L["Quest IDs in tooltips"], Get("questIDs"), Set("questIDs")))
	column:Add(W.Checkbox(body, L["Minimap button"], Get("minimapButton"), Set("minimapButton"),
		L["A button on the minimap that opens Almanac. Drag it to move it around the minimap."]))
	column:Add(W.Slider(body, L["Window scale"], 0.6, 1.6, 0.05, Get("scale"), Set("scale"), {
		width = 260,
		format = function(value)
			return format("%.2f", value)
		end,
	}))

	column:Skip(8)
	column:Add(W.Header(body, L["What quests give"], WIDTH))
	page.about = column:Add(W.Note(body, "", WIDTH), 60)
	column:Add(W.Button(body, L["Forget what was learned"], 200, 22, function()
		W.Confirm(L["Forget the XP, money and rewards Almanac has seen quests give? It learns them again as you play."], function()
			for key in pairs(DB.learned) do
				DB.learned[key] = nil
			end
			ns.Rewards.Forget()
			ns.Items.Learn()
			ns.Send("rewards")
			page:Refresh()
		end)
	end))
	scroll:SetContentHeight(8 - column.y)

	function page:Refresh()
		W.RefreshAll()
		self.hidden:SetActive(Catalog.QuestieHidden() ~= nil)
		local version = C.AddOnMetadata("QuestieDB", "Version") or "?"
		self.about:SetText(format(L["Quests come from QuestieDB %s. XP is what the database lists until one of your characters turns the quest in; money is what the game lists. Almanac remembers what %d quests gave or list."],
			version, Learned()))
	end
	return page
end

-- A page in the game's own AddOns options that opens the window's Options.
function Options.Register()
	local panel = CreateFrame("Frame")
	panel.name = L["Almanac"]
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L["Almanac"])
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetWidth(520)
	text:SetJustifyH("LEFT")
	text:SetText(L["The options are in Almanac's window. You can also open it by typing /almanac options."])
	local open = W.Button(panel, L["Open Almanac's options"], 220, 26, function()
		if _G.SettingsPanel and _G.SettingsPanel:IsShown() and not InCombatLockdown() then
			_G.HideUIPanel(_G.SettingsPanel)
		end
		ns.Window.Open("options")
	end)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	C.RegisterOptionsPanel(panel, L["Almanac"])
end
