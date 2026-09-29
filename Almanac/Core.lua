local ADDON, ns = ...
local L, C, DB, Data, Player, Status, Rewards, Catalog, Items =
	ns.L, ns.C, ns.DB, ns.Data, ns.Player, ns.Status, ns.Rewards, ns.Catalog, ns.Items

-- Startup, key bindings, the addon compartment and /almanac.

local _G = _G
local ipairs, pcall, tonumber, tostring, type, format, lower, concat =
	ipairs, pcall, tonumber, tostring, type, string.format, string.lower, table.concat

local function Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. L["Almanac"] .. "|r: " .. message)
end
ns.Print = Print

--------------------------------------------------------------------------------
-- Key bindings (Bindings.xml) and the addon compartment on the minimap
--------------------------------------------------------------------------------

_G.BINDING_HEADER_ALMANAC = L["Almanac"]
_G.BINDING_NAME_ALMANAC_TOGGLE = L["Open or close Almanac"]
_G.BINDING_NAME_ALMANAC_REWARDS = L["Find a quest reward"]

function _G.Almanac_Toggle()
	ns.Window.Toggle()
end

function _G.Almanac_Rewards()
	ns.Window.Open("rewards")
end

function _G.Almanac_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Window.Open("options")
	else
		ns.Window.Toggle()
	end
end

function _G.Almanac_OnAddonCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Almanac"], 1, 1, 1)
	GameTooltip:AddLine(L["Left-click: quests"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: options"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function _G.Almanac_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

C.On("ADDON_LOADED", function(_, name)
	if name == ADDON then
		DB.Load()
	end
end)

C.On("PLAYER_LOGIN", function()
	-- Each step on its own: one failing must not stop the others. A module
	-- can be missing too: the game only finds files added to the .toc after
	-- a restart, not a /reload.
	local call = _G.securecallfunction or pcall
	local function Step(module, name)
		if module and module[name] then
			call(module[name])
		end
	end
	Step(Player, "Start")
	Step(Rewards, "Start")
	Step(Items, "Start")
	Step(ns.Options, "Register")
	Step(ns.MinimapButton, "Create")
	if not Data.Init() then
		Print(Data.problem)
	elseif ns.NewQuests then
		-- Forever's new quests have no money or rewards listed: the game says.
		Rewards.Want(ns.NewQuests.Ids())
	end
	-- Once Questie is ready it says which quests it hides; the list is built
	-- again with that.
	local questie = _G.Questie
	if type(questie) == "table" and type(questie.API) == "table" and type(questie.API.RegisterOnReady) == "function" then
		pcall(questie.API.RegisterOnReady, function()
			if Catalog.ready or Catalog.building then
				Catalog.Build()
			end
		end)
	end
end)

--------------------------------------------------------------------------------
-- /almanac probe: what the database, the client and the saved data say about
-- a quest, for reporting problems.
--------------------------------------------------------------------------------

local function ItemList(list)
	local ids = {}
	for _, entry in ipairs(list or {}) do
		ids[#ids + 1] = tostring(entry[1]) .. (entry[2] and entry[2] > 1 and ("x" .. entry[2]) or "")
	end
	return #ids > 0 and concat(ids, ", ") or "-"
end

-- Where a quest QuestieDB does not have comes from.
local SOURCES = { almanac = " (new in Forever, from Almanac's list)", journal = " (from Forever Dungeon Journal)" }

local function Probe(id)
	if not Data.Init() then
		Print(Data.problem)
		return
	end
	Print(format("you: level %d %s %s (%s)", Player.level, C.RaceName(Player.raceID or 0) or tostring(Player.raceFile),
		C.ClassName(Player.classFile or ""), tostring(Player.faction)))
	local quest = Data.Basics(id)
	if quest then
		Print(format("%d \"%s\"%s: level %s, requires %d, zone %d (%s), races %d, classes %d, database XP %s",
			id, quest.name, SOURCES[Data.Source(id)] or "", tostring(quest.level),
			quest.reqLevel, quest.zone, Data.ZoneName(Data.ZoneKey(quest.zone)), quest.races, quest.classes,
			tostring((Data.BaseXP(id)))))
		local state, reasons = Status.Of(id)
		local why = {}
		for _, reason in ipairs(reasons or {}) do
			why[#why + 1] = Status.ReasonText(reason)
		end
		Print(format("  %s%s", state, #why > 0 and (": " .. concat(why, "; ")) or ""))
	else
		Print(format(L["Quest %d is not in QuestieDB."], id))
	end
	if C.HaveQuestData(id) then
		local listed = C.CachedRewards(id)
		Print(format("  client: \"%s\", XP %s, money %s, items %s, choices %s", tostring(C.QuestTitle(id)),
			tostring(listed.xp), tostring(listed.money), ItemList(listed.fixed), ItemList(listed.choice)))
	else
		C.RequestQuest(id)
		Print("  " .. L["The client does not have this quest yet; it was asked for. Try again in a moment."])
	end
	local learned = DB.learned[id]
	if learned then
		Print(format("  saved: turn-in XP %s, money %s; listed XP %s, money %s; items %s, choices %s",
			tostring(learned.xp), tostring(learned.money), tostring(learned.cxp), tostring(learned.cmoney),
			ItemList(learned.fixed), ItemList(learned.choice)))
	end
	local full, source = Rewards.FullXP(id)
	Print(format("  Almanac: full XP %s (%s), your XP %s, money %s", tostring(full), tostring(source),
		tostring(Rewards.XP(id)), tostring((Rewards.Money(id)))))
end

--------------------------------------------------------------------------------
-- /almanac
--------------------------------------------------------------------------------

_G.SLASH_ALMANAC1 = "/almanac"
_G.SlashCmdList.ALMANAC = function(message)
	-- The first word is the command; the rest keeps its case (names).
	local word, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local command = lower(word or "")
	rest = rest or ""
	if command == "" then
		ns.Window.Toggle()
	elseif command == "rewards" or command == "reward" or command == "items" then
		ns.Window.Open("rewards", rest)
	elseif command == "options" or command == "config" then
		ns.Window.Open("options")
	elseif command == "minimap" then
		DB.Set("minimapButton", not DB.settings.minimapButton)
		ns.Send("settings", "minimapButton")
		Print(DB.settings.minimapButton and L["The minimap button is shown."] or L["The minimap button is hidden."])
	elseif command == "probe" and tonumber(rest) then
		Probe(tonumber(rest))
	elseif command == "help" or command == "?" then
		Print(L["commands:"])
		Print("  /almanac - " .. L["open or close the window"])
		Print("  /almanac <name> - " .. L["find quests by name"])
		Print("  /almanac rewards [name] - " .. L["find quest rewards"])
		Print("  /almanac options - " .. L["options"])
		Print("  /almanac minimap - " .. L["show or hide the minimap button"])
		Print("  /almanac probe <quest ID> - " .. L["what Almanac knows about a quest"])
	else
		ns.Window.Open("quests", message:match("^%s*(.-)%s*$"))
	end
end
