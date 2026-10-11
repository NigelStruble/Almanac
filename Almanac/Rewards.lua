local _, ns = ...
local C, DB, Data, Player = ns.C, ns.DB, ns.Data, ns.Player

-- What quests give: XP, money and items.
--
-- There are three sources, best first:
--   * what a quest really gave when one of your characters turned it in
--     (QUEST_TURNED_IN), saved in DB.learned. WoW: Forever gives much more XP
--     than listed for many dungeon quests, and only this shows it;
--   * what the game client lists: its quest cache, asked for with
--     C_QuestLog.RequestLoadQuestByID for the quests on screen, and the quest
--     dialogs (offered and turned in). Saved too, so totals and the reward
--     search know them next time;
--   * QuestieDB: XP (Classic's values) and the items each quest rewards. It
--     has no money, so money is only known once the client has listed it.
--
-- XP is "full" XP, what the quest gives a character up to five levels above
-- it; XP() is what the character gets: what the game lists for it when it
-- has, else the full XP reduced by Forever's rule (Reduce).

local Rewards = {}
ns.Rewards = Rewards

local _G = _G
local type, pairs, ipairs, floor, min, sort, tremove =
	type, pairs, ipairs, math.floor, math.min, table.sort, table.remove

local client = {} -- [questID] = what the client listed this session, and at what level
local requested = {} -- [questID] = time asked, until the client answers
local failed = {} -- [questID] = time the client said it has no such quest
local queue, queued = {}, {}
local ticking = false

local PER_TICK = 10 -- quests asked for every tick
local TICK = 0.1
local RETRY = 30 -- seconds before asking again for a quest that did not answer

local function Now()
	return GetTime()
end

--------------------------------------------------------------------------------
-- XP
--------------------------------------------------------------------------------

-- XP for a character playerLevel of a quest questLevel that gives xp in full,
-- by WoW: Forever's rule: all of it up to five levels above the quest, 80% at
-- six levels above, 60% at seven, and half from eight on. (Classic went on
-- down to 10%.)
local SHARE_ABOVE = { [6] = 0.8, [7] = 0.6 }
local SHARE_FAR_ABOVE = 0.5

function Rewards.Reduce(xp, questLevel, playerLevel)
	local above = playerLevel - questLevel
	if above <= 5 then
		return xp
	end
	return floor(xp * (SHARE_ABOVE[above] or SHARE_FAR_ABOVE) + 0.5)
end

local function QuestLevel(id)
	local quest = Data.Basics(id)
	return quest and quest.level or Player.level
end

-- Whether a character of this level gets a quest's full XP.
local function FullAt(id, level)
	return level <= QuestLevel(id) + 5 and level < Player.maxLevel
end

-- XP sources that are what a quest gives on Forever already: Almanac's list of
-- Forever's new quests, and Forever Dungeon Journal.
local ON_FOREVER = { reported = true, journal = true }

-- What the client or QuestieDB lists as the quest's full XP. For a new Forever
-- quest, what it gives on Forever comes first: the client lists Forever's new
-- dungeon quests at their untuned XP.
local function Listed(id)
	local xp, source = Data.BaseXP(id)
	if ON_FOREVER[source] then
		return xp, source
	end
	local learned = DB.learned[id]
	if learned and learned.cxp then
		return learned.cxp, "client"
	end
	if xp then
		return xp, source
	end
	return nil
end

-- How much more (or less) XP the quests of a dungeon or raid gave when turned
-- in than they list, by zone key: WoW: Forever tunes dungeon quests up. The
-- middle value of all the quests turned in there.
local ratios

local function Ratios()
	if ratios then
		return ratios
	end
	local samples = {}
	for id, learned in pairs(DB.learned) do
		local quest = learned.xp and Data.Basics(id)
		local listed, source = nil, nil
		if quest then
			listed, source = Listed(id)
		end
		-- XP that is what quests give on Forever already says nothing about
		-- how the database's differs.
		if listed and listed > 0 and not ON_FOREVER[source] then
			local key = Data.ZoneKey(quest.zone)
			local group = Data.ZoneGroup(key)
			if group == "dungeon" or group == "raid" then
				local list = samples[key] or {}
				list[#list + 1] = learned.xp / listed
				samples[key] = list
			end
		end
	end
	ratios = {}
	for key, list in pairs(samples) do
		sort(list)
		local middle = list[floor((#list + 1) / 2)]
		if middle > 1.05 or middle < 0.95 then
			ratios[key] = middle
		end
	end
	return ratios
end

-- The quest's full XP, and where it comes from: "turnin" (what it gave),
-- "estimate" (listed XP times what the zone's other quests gave over theirs),
-- "reported" or "journal" (what a new Forever quest gives, from Almanac's list
-- or Forever Dungeon Journal), "client" or "database". Nil when nothing knows.
function Rewards.FullXP(id)
	local learned = DB.learned[id]
	if learned and learned.xp then
		return learned.xp, "turnin"
	end
	local listed, source = Listed(id)
	if not listed then
		return nil
	end
	local quest = Data.Basics(id)
	local ratio = quest and not ON_FOREVER[source] and Ratios()[Data.ZoneKey(quest.zone)]
	if ratio then
		return floor(listed * ratio + 0.5), "estimate", ratio
	end
	return listed, source
end

-- The share of its full XP the game lists a quest at for the character now,
-- when it is above the quest: the game's number over the quest's untuned full
-- XP (as the game listed it at a lower level, or as QuestieDB has it). Nil
-- when the game has not listed it at this level, or nothing to compare with.
local function ListedShare(id)
	local listed = client[id]
	if not (listed and listed.level == Player.level and (listed.xp or 0) > 0) or FullAt(id, Player.level) then
		return nil
	end
	local learned = DB.learned[id]
	local base = learned and learned.cxp
	if not base then
		local xp, source = Data.BaseXP(id)
		base = source == "database" and xp or nil
	end
	if not base or base <= 0 then
		return nil
	end
	return min(1, listed.xp / base)
end

-- The XP the character (or a character of level) gets for the quest: 0 at
-- the highest level, nil when not known. For the character itself, what the
-- game lists comes first: it is exact, whatever the game's rule. A quest
-- Forever tunes up gets the same share of its tuned XP.
function Rewards.XP(id, level)
	level = level or Player.level
	if level >= Player.maxLevel then
		return 0
	end
	local full = Rewards.FullXP(id)
	if not full then
		return nil
	end
	local share = level == Player.level and ListedShare(id)
	if share then
		return floor(full * share + 0.5)
	end
	return Rewards.Reduce(full, QuestLevel(id), level)
end

--------------------------------------------------------------------------------
-- Money and items
--------------------------------------------------------------------------------

-- Copper, and "turnin", "client" or "journal"; nil when not known yet.
function Rewards.Money(id)
	local learned = DB.learned[id]
	if learned then
		if learned.money then
			return learned.money, "turnin"
		elseif learned.cmoney then
			return learned.cmoney, "client"
		end
	end
	local money = Data.NewQuestRewards(id)
	if money then
		return money, "journal"
	end
	return nil
end

-- fixed, choice, source: lists of { itemID, count }. From the client and
-- Forever Dungeon Journal ("journal") they are the items the quest gives and
-- those to choose one of; from QuestieDB ("database") every item comes in
-- fixed, as it does not say which is which.
function Rewards.Items(id)
	local learned = DB.learned[id]
	if learned and (learned.fixed or learned.choice) then
		return learned.fixed or {}, learned.choice or {}, "client"
	end
	local _, fixed, choice = Data.NewQuestRewards(id)
	if fixed and (#fixed > 0 or #choice > 0) then
		return fixed, choice, "journal"
	end
	local items = ns.Items and ns.Items.FromDatabase(id)
	if items and #items > 0 then
		local list = {}
		for i, itemID in ipairs(items) do
			list[i] = { itemID, 1 }
		end
		return list, {}, "database"
	end
	return {}, {}, nil
end

-- Every item a quest can reward, as a list of item IDs.
function Rewards.ItemIDs(id)
	local fixed, choice = Rewards.Items(id)
	local ids = {}
	for _, entry in ipairs(fixed) do
		ids[#ids + 1] = entry[1]
	end
	for _, entry in ipairs(choice) do
		ids[#ids + 1] = entry[1]
	end
	return ids
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

local Announce = C.Debounce(0.25, function()
	ns.Send("rewards")
end)

local function Learned(id)
	local learned = DB.learned[id]
	if not learned then
		learned = {}
		DB.learned[id] = learned
	end
	return learned
end

local function SameItems(a, b)
	if a == nil or b == nil then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for i, entry in ipairs(a) do
		if entry[1] ~= b[i][1] or entry[2] ~= b[i][2] then
			return false
		end
	end
	return true
end

-- Keeps what the client lists for a quest (from its quest cache, or a quest
-- dialog). Returns true if anything new was learned. The quest cache answers
-- for quests not in the log too (seen in game): a quest it lists with XP or
-- items but no money gives no money.
local function Remember(id, listed)
	local fixed, choice = listed.fixed or {}, listed.choice or {}
	-- A quest the client has no details for lists nothing at all; that is not
	-- the same as a quest with no rewards, so it is not kept.
	if not ((listed.xp or 0) > 0 or (listed.money or 0) > 0 or #fixed > 0 or #choice > 0) then
		return false
	end
	local learned = Learned(id)
	local changed = false
	-- The client lists XP for this character: the full XP only if it is not
	-- above the quest's level range.
	if (listed.xp or 0) > 0 and FullAt(id, Player.level) and learned.cxp ~= listed.xp then
		learned.cxp = listed.xp
		changed = true
		ratios = nil
	end
	if listed.money and learned.cmoney ~= listed.money then
		learned.cmoney = listed.money
		changed = true
	end
	local newFixed = #fixed > 0 and fixed or nil
	local newChoice = #choice > 0 and choice or nil
	if (newFixed or newChoice) and not (SameItems(newFixed, learned.fixed) and SameItems(newChoice, learned.choice)) then
		learned.fixed, learned.choice = newFixed, newChoice
		changed = true
		if ns.Items then
			ns.Items.Learn()
		end
	end
	if changed then
		learned.t = _G.time and _G.time() or 0
	end
	return changed
end
Rewards.Remember = Remember

local function ReadClient(id)
	local listed = C.CachedRewards(id)
	-- Its XP is for the character at this level.
	listed.level = Player.level
	client[id] = listed
	if Remember(id, listed) then
		Announce()
	end
end

-- The quest dialog: a quest offered, or being turned in.
local function ReadDialog()
	local listed = C.DialogRewards()
	if listed and Remember(listed.questID, listed) then
		Announce()
	end
end

-- What a quest really gave: its full XP (when the character was not above its
-- level range, or at the highest level, where quests give money instead of
-- XP) and its money.
function Rewards.TurnedIn(id, xp, money)
	local quest = Data.Basics(id)
	if not quest and not DB.learned[id] then
		return
	end
	local learned = Learned(id)
	local level = Player.level
	if type(xp) == "number" and xp > 0 and FullAt(id, level) then
		learned.xp = xp
		ratios = nil
	end
	if type(money) == "number" and level < Player.maxLevel then
		learned.money = money
	end
	learned.t = _G.time and _G.time() or 0
	Announce()
end

--------------------------------------------------------------------------------
-- Asking the client
--------------------------------------------------------------------------------

-- Whether the client has listed a quest at the character's level this session.
local function ListedNow(id)
	local listed = client[id]
	return listed ~= nil and listed.level == Player.level
end

local function Tick()
	local count = 0
	while count < PER_TICK and #queue > 0 do
		local id = tremove(queue, 1)
		queued[id] = nil
		if not ListedNow(id) then
			-- Marked first: if the client already has the quest, it answers
			-- before RequestLoadQuestByID returns.
			requested[id] = Now()
			C.RequestQuest(id)
			count = count + 1
		end
	end
	if #queue > 0 then
		C.After(TICK, Tick)
	else
		ticking = false
	end
end

-- Asks the client for the rewards of these quests, a few at a time. Quests
-- it already has are read at once.
function Rewards.Want(ids)
	if not C.CanRequestQuests() then
		return
	end
	local now = Now()
	for _, id in ipairs(ids) do
		local asked = requested[id] or failed[id]
		if not ListedNow(id) and not queued[id] and (not asked or now - asked > RETRY) then
			if C.HaveQuestData(id) then
				ReadClient(id)
			else
				queued[id] = true
				queue[#queue + 1] = id
			end
		end
	end
	if #queue > 0 and not ticking then
		ticking = true
		C.After(TICK, Tick)
	end
end

-- How many quests are still being asked for.
function Rewards.Pending()
	local count, now = #queue, Now()
	for _, asked in pairs(requested) do
		if now - asked < RETRY then
			count = count + 1
		end
	end
	return count
end

-- What the client listed this session (for /almanac probe).
function Rewards.Client(id)
	return client[id]
end

function Rewards.Start()
	C.On("QUEST_DATA_LOAD_RESULT", function(_, id, success)
		if not requested[id] then
			return -- asked for by someone else
		end
		requested[id] = nil
		if success then
			ReadClient(id)
		else
			failed[id] = Now() -- not again for a while
		end
	end)
	C.On("QUEST_DETAIL", ReadDialog)
	C.On("QUEST_COMPLETE", ReadDialog)
	C.On("QUEST_TURNED_IN", function(_, id, xp, money)
		Rewards.TurnedIn(id, xp, money)
	end)
end

--------------------------------------------------------------------------------
-- Totals
--------------------------------------------------------------------------------

-- Sums the rewards of a list of quests: { count, xp (for the character),
-- fullXP, money, noXP (quests whose XP is not known), noMoney (quests whose
-- money is not known yet), estimated (some XP is an estimate) }. Repeatable
-- quests are left out unless the options count them.
function Rewards.Sum(ids)
	local total = { count = 0, xp = 0, fullXP = 0, money = 0, noXP = 0, noMoney = 0, estimated = false }
	local repeatables = DB.settings.repeatableTotals
	for _, id in ipairs(ids) do
		local quest = Data.Basics(id)
		if quest and (repeatables or not quest.repeatable) then
			total.count = total.count + 1
			local full, source = Rewards.FullXP(id)
			if full then
				total.fullXP = total.fullXP + full
				total.xp = total.xp + (Rewards.XP(id) or 0)
				if source == "estimate" then
					total.estimated = true
				end
			else
				total.noXP = total.noXP + 1
			end
			local money = Rewards.Money(id)
			if money then
				total.money = total.money + money
			else
				total.noMoney = total.noMoney + 1
			end
		end
	end
	return total
end

-- For tests.
function Rewards.Reset()
	client, requested, failed, queue, queued = {}, {}, {}, {}, {}
	ticking = false
	ratios = nil
end

-- Called when the saved data is replaced (and by tests).
function Rewards.Forget()
	ratios = nil
end
