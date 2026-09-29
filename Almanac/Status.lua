local _, ns = ...
local L, C, Data, Player = ns.L, ns.C, ns.Data, ns.Player

-- Whether the character can take a quest now, and if not, why. A quest is:
--   done       turned in (a repeatable one is available again instead)
--   ready      in the quest log and complete
--   active     in the quest log
--   available  can be taken now
--   later      not yet: too low a level, a quest to do first, reputation, ...
--   blocked    not any more: it was ruled out by another quest, or the
--              character has outgrown it
--   event      a world event quest, out of season
--   other      for another race or class
-- The window files them under Available, Unavailable and Completed by chain
-- (Status.Section): a chain under way is listed whole under Available, but
-- for the quests that need more than the earlier quests of the chain.

local Status = {}
ns.Status = Status

local ipairs, type, format, concat = ipairs, type, string.format, table.concat

Status.CATEGORY = {
	done = "completed",
	ready = "available",
	active = "available",
	available = "available",
	later = "unavailable",
	blocked = "unavailable",
	event = "unavailable",
	other = "unavailable",
}

-- Whether a quest belongs to a world event, and whether that is in season.
-- Questie knows (Catalog.lua sets these); without it, the quests filed under
-- an event count as event quests, always out of season.
Status.IsEvent = function(_)
	return false
end
Status.EventActive = function(_)
	return false
end

--------------------------------------------------------------------------------
-- Working it out
--------------------------------------------------------------------------------

local function Taken(id)
	return Player.HasTaken(id)
end

local function Evaluate(id)
	local quest = Data.Basics(id)
	if not quest then
		return "blocked", { { kind = "unknown" } }
	end
	if Player.IsDone(id) and not quest.repeatable then
		return "done"
	end
	local entry = Player.log[id]
	if entry then
		return entry.complete and "ready" or "active"
	end

	local reasons = {}
	local function Add(reason)
		reasons[#reasons + 1] = reason
	end

	if not Data.HasBit(quest.races, Player.raceBit) then
		Add({ kind = "race", races = quest.races })
	end
	if not Data.HasBit(quest.classes, Player.classBit) then
		Add({ kind = "class", classes = quest.classes })
	end
	if #reasons > 0 then
		return "other", reasons
	end

	local links = Data.Links(id)

	-- Ruled out for good.
	for _, other in ipairs(links.exclusive or {}) do
		if Taken(other) then
			Add({ kind = "exclusive", id = other })
			break
		end
	end
	if links.next and Taken(links.next) then
		Add({ kind = "skipped", id = links.next })
	end
	if links.breadcrumbFor and Taken(links.breadcrumbFor) then
		Add({ kind = "breadcrumb", id = links.breadcrumbFor })
	end
	if links.untilDone and Player.IsDone(links.untilDone) then
		Add({ kind = "ended", id = links.untilDone })
	end
	if links.maxLevel and Player.level > links.maxLevel then
		Add({ kind = "toohigh", level = links.maxLevel })
	end
	if links.maxRep then
		local value = Player.Reputation(links.maxRep[1])
		if value and value >= links.maxRep[2] then
			Add({ kind = "maxrep", faction = links.maxRep[1], value = links.maxRep[2] })
		end
	end
	if links.spell and links.spell < 0 and Player.KnowsSpell(-links.spell) then
		Add({ kind = "nospell", spell = -links.spell })
	end
	if #reasons > 0 then
		return "blocked", reasons
	end

	-- Not yet.
	if quest.reqLevel > Player.level then
		Add({ kind = "level", level = quest.reqLevel })
	end
	if links.preSingle then
		local any = false
		for _, other in ipairs(links.preSingle) do
			if Player.IsDone(other) then
				any = true
				break
			end
		end
		if not any then
			Add({ kind = "after", ids = links.preSingle, any = #links.preSingle > 1 })
		end
	elseif links.preGroup then
		local missing = {}
		for _, other in ipairs(links.preGroup) do
			if other < 0 then
				if not Player.IsDone(-other) then
					missing[#missing + 1] = -other
				end
			elseif not Player.IsDone(other) then
				-- Doing one of its alternatives counts too.
				local instead = false
				for _, alternative in ipairs(Data.Links(other).exclusive or {}) do
					if Player.IsDone(alternative) then
						instead = true
						break
					end
				end
				if not instead then
					missing[#missing + 1] = other
				end
			end
		end
		if #missing > 0 then
			Add({ kind = "after", ids = missing })
		end
	end
	if links.parent and not Player.InLog(links.parent) then
		Add({ kind = "parent", id = links.parent })
	end
	if links.startingWith and not Taken(links.startingWith) then
		Add({ kind = "after", ids = { links.startingWith } })
	end
	for _, breadcrumb in ipairs(links.breadcrumbs or {}) do
		if Player.InLog(breadcrumb) then
			Add({ kind = "turnin", id = breadcrumb })
			break
		end
	end
	if links.disabledBy and Player.InLog(links.disabledBy) then
		Add({ kind = "disabled", id = links.disabledBy })
	end
	if links.minRep then
		local value = Player.Reputation(links.minRep[1])
		if not value or value < links.minRep[2] then
			Add({ kind = "rep", faction = links.minRep[1], value = links.minRep[2] })
		end
	end
	if links.skill then
		local rank = Player.Skill(links.skill[1])
		if not rank or rank < (links.skill[2] or 0) then
			Add({ kind = "skill", skill = links.skill[1], value = links.skill[2] or 0, missing = not rank })
		end
	end
	if links.spell and links.spell > 0 and not Player.KnowsSpell(links.spell) then
		Add({ kind = "spell", spell = links.spell })
	end
	if links.spec and links.spec > 0 and not Player.KnowsSpell(links.spec) then
		Add({ kind = "spell", spell = links.spec })
	end
	if (Data.ZoneGroup(Data.ZoneKey(quest.zone)) == "event" or Status.IsEvent(id)) and not Status.EventActive(id) then
		Add({ kind = "event" })
	end
	if #reasons > 0 then
		-- Out of season is its own kind: nothing the character does changes it.
		if #reasons == 1 and reasons[1].kind == "event" then
			return "event", reasons
		end
		return "later", reasons
	end
	return "available"
end

local cache = {}

-- state, reasons (a list; nil for done, in the log, or available).
function Status.Of(id)
	local entry = cache[id]
	if entry and entry.version == Player.version then
		return entry.state, entry.reasons
	end
	local state, reasons = Evaluate(id)
	cache[id] = { version = Player.version, state = state, reasons = reasons }
	return state, reasons
end

function Status.Category(id)
	return Status.CATEGORY[(Status.Of(id))]
end

-- Whether the character could still do the quest one day.
function Status.Open(id)
	local state = Status.Of(id)
	return state ~= "done" and state ~= "blocked" and state ~= "other"
end

--------------------------------------------------------------------------------
-- Chains
--------------------------------------------------------------------------------

-- Reasons that only mean "an earlier quest of the chain comes first".
local CHAIN_REASONS = { after = true, parent = true, turnin = true }

local reachable, going = {}, {}
local chainVersion = -1

local function Fresh()
	if chainVersion ~= Player.version then
		reachable, going = {}, {}
		chainVersion = Player.version
	end
end

local function InChain(id, chain)
	return ns.Catalog.chainOf[id] == chain
end

local function WorkOutReachable(id)
	local state, reasons = Status.Of(id)
	if state == "available" or state == "active" or state == "ready" then
		return true
	end
	if state ~= "later" then
		return false
	end
	local chain = ns.Catalog.chainOf[id]
	if not chain then
		return false
	end
	for _, reason in ipairs(reasons or {}) do
		if not CHAIN_REASONS[reason.kind] then
			return false -- a level, reputation, profession, ...
		end
		if reason.kind == "after" then
			-- One of them (any), or all of them.
			local ok = not reason.any
			for _, other in ipairs(reason.ids) do
				local fine = InChain(other, chain) and Status.Reachable(other)
				if reason.any and fine then
					ok = true
					break
				elseif not reason.any and not fine then
					ok = false
					break
				end
			end
			if not ok then
				return false
			end
		elseif not (InChain(reason.id, chain) and Status.Reachable(reason.id)) then
			return false
		end
	end
	return true
end

-- Whether the character can get to a quest by doing its chain in order: it
-- can take it now (or has it), or all it waits for is earlier quests of its
-- chain that the character can get to. Anything else it needs (a level,
-- reputation, a profession) keeps it out of reach.
function Status.Reachable(id)
	Fresh()
	local known = reachable[id]
	if known ~= nil then
		return known
	end
	reachable[id] = false -- a loop in the data counts as out of reach
	local value = WorkOutReachable(id)
	reachable[id] = value
	return value
end

-- Whether a chain is under way: the character has a quest of it left that it
-- can get to.
function Status.ChainGoing(chain)
	Fresh()
	local known = going[chain]
	if known ~= nil then
		return known
	end
	local value = false
	for _, id in ipairs(chain.quests) do
		if Status.Of(id) ~= "done" and Status.Reachable(id) then
			value = true
			break
		end
	end
	going[chain] = value
	return value
end

-- Where the window lists a quest: "available" if the character can take it
-- now or once the quests before it in its chain are done, and for the done
-- quests of a chain still under way, so a chain shows whole; "completed" for
-- other done quests; else "unavailable".
function Status.Section(id)
	local state = Status.Of(id)
	if state == "done" then
		local chain = ns.Catalog.chainOf[id]
		return (chain and Status.ChainGoing(chain)) and "available" or "completed"
	end
	return Status.Reachable(id) and "available" or "unavailable"
end

function Status.Reset()
	cache = {}
	chainVersion = -1
end

--------------------------------------------------------------------------------
-- Saying why
--------------------------------------------------------------------------------

local SKILLS = {
	[129] = L["First Aid"],
	[164] = L["Blacksmithing"],
	[165] = L["Leatherworking"],
	[171] = L["Alchemy"],
	[182] = L["Herbalism"],
	[185] = L["Cooking"],
	[186] = L["Mining"],
	[197] = L["Tailoring"],
	[202] = L["Engineering"],
	[333] = L["Enchanting"],
	[356] = L["Fishing"],
	[393] = L["Skinning"],
	[755] = L["Jewelcrafting"],
	[762] = L["Riding"],
	[773] = L["Inscription"],
}

local function QuestNames(ids, joiner)
	local names = {}
	for i, id in ipairs(ids) do
		if i > 3 then
			names[#names + 1] = format(L["%d more"], #ids - 3)
			break
		end
		names[#names + 1] = Data.QuestName(id)
	end
	return concat(names, joiner)
end

local function FactionName(id)
	return C.FactionName(id) or (L["Faction"] .. " " .. id)
end

-- One line of text for a reason.
function Status.ReasonText(reason)
	local kind = reason.kind
	if kind == "level" then
		return format(L["Requires level %d"], reason.level)
	elseif kind == "after" then
		if reason.any then
			return format(L["After one of: %s"], QuestNames(reason.ids, L[" or "]))
		end
		return format(L["After %s"], QuestNames(reason.ids, ", "))
	elseif kind == "parent" then
		return format(L["While %s is in your quest log"], Data.QuestName(reason.id))
	elseif kind == "turnin" then
		return format(L["Turn in %s first"], Data.QuestName(reason.id))
	elseif kind == "disabled" then
		return format(L["Not while %s is in your quest log"], Data.QuestName(reason.id))
	elseif kind == "rep" then
		return format(L["Requires %s with %s"], C.StandingName(reason.value), FactionName(reason.faction))
	elseif kind == "maxrep" then
		return format(L["Only below %s with %s"], C.StandingName(reason.value), FactionName(reason.faction))
	elseif kind == "skill" then
		local name = SKILLS[reason.skill] or (L["Skill"] .. " " .. reason.skill)
		if reason.value > 0 then
			return format(L["Requires %s (%d)"], name, reason.value)
		end
		return format(L["Requires %s"], name)
	elseif kind == "spell" then
		return format(L["Requires %s"], C.SpellName(reason.spell) or (L["spell"] .. " " .. reason.spell))
	elseif kind == "nospell" then
		return format(L["Not once you know %s"], C.SpellName(reason.spell) or (L["spell"] .. " " .. reason.spell))
	elseif kind == "exclusive" then
		return format(L["Ruled out by %s"], Data.QuestName(reason.id))
	elseif kind == "skipped" then
		return format(L["Skipped: you went on to %s"], Data.QuestName(reason.id))
	elseif kind == "breadcrumb" then
		return format(L["Leads to %s, which you have already taken"], Data.QuestName(reason.id))
	elseif kind == "ended" then
		return format(L["No longer offered after %s"], Data.QuestName(reason.id))
	elseif kind == "toohigh" then
		return format(L["Only up to level %d"], reason.level)
	elseif kind == "event" then
		return L["World event, out of season"]
	elseif kind == "race" then
		return Status.RacesText(reason.races)
	elseif kind == "class" then
		return Status.ClassesText(reason.classes)
	end
	return L["Not available"]
end

-- "Alliance only", "Horde only", or the races: "Night Elf, Gnome only".
function Status.RacesText(mask)
	local names, faction, count = {}, nil, 0
	for raceID = 1, 32 do
		if mask and mask > 0 and Data.HasBit(mask, Data.Bit(raceID)) then
			count = count + 1
			names[#names + 1] = C.RaceName(raceID) or (L["race"] .. " " .. raceID)
			local raceFaction = Data.RaceFaction(raceID) or "?"
			faction = (faction == nil or faction == raceFaction) and raceFaction or "mixed"
		end
	end
	if count >= 4 and faction == "Alliance" then
		return L["Alliance only"]
	elseif count >= 4 and faction == "Horde" then
		return L["Horde only"]
	elseif count == 0 then
		return L["For other races"]
	end
	return format(L["%s only"], concat(names, ", "))
end

-- "Warrior, Paladin only".
function Status.ClassesText(mask)
	local names = {}
	for classID = 1, 16 do
		if mask and mask > 0 and Data.HasBit(mask, Data.Bit(classID)) then
			names[#names + 1] = C.ClassNameByID(classID) or (L["class"] .. " " .. classID)
		end
	end
	if #names == 0 then
		return L["For other classes"]
	end
	return format(L["%s only"], concat(names, ", "))
end

-- The first reason, for a quest's row.
function Status.Summary(id)
	local state, reasons = Status.Of(id)
	if type(reasons) == "table" and reasons[1] then
		return Status.ReasonText(reasons[1]), state
	end
	return nil, state
end

local STATE_TEXT = {
	done = L["Completed"],
	ready = L["Ready to turn in"],
	active = L["In your quest log"],
	available = L["Available"],
	later = L["Not yet available"],
	blocked = L["No longer available"],
	event = L["Out of season"],
	other = L["Not for your character"],
}

function Status.StateText(state)
	return STATE_TEXT[state] or state
end
