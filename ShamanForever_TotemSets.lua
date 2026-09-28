-- Totem bar: pick sets. The four picks (each element's totem on Call of the Elements' first page,
-- which the slots, the keys and Blizzard's Totem Action Bar all cast) saved under a name, and put
-- back by hand or on entering a kind of place: the open world, a dungeon, a raid, a battleground or
-- arena (IsInInstance). Picks are written with SetMultiCastSpell, the call Blizzard's own picker
-- makes, only out of combat: a set asked for in combat is put back when combat ends. Each pick is
-- read back afterwards, so a pick the game refused is reported rather than assumed.
--
-- A set keeps spell IDs. It puts back the highest rank you know of each totem (ranks share the
-- client's name), and leaves an element alone when you don't know its totem.

local _, ns = ...
local TB = ns.TotemBar
local S = {}
TB.sets = S
local isSecret = ns.isSecret

S.MAX = 10
-- The kinds of place with a rule, and the instance types that belong to each.
S.CONTENT = { { "world", "Open world" }, { "party", "Dungeon" }, { "raid", "Raid" }, { "pvp", "Battleground or arena" } }
local CONTENT_OF = { none = "world", party = "party", raid = "raid", pvp = "pvp", arena = "pvp" }

local function cfg() return TB.cfg() end

-- The saved sets, in order; anything malformed (a damaged import) is dropped.
function S.list()
	local c = cfg()
	local out, seen = {}, {}
	for _, set in ipairs(c.sets) do
		if type(set) == "table" and type(set.name) == "string" and set.name ~= "" and not seen[set.name]
				and type(set.picks) == "table" and #out < S.MAX then
			seen[set.name] = true
			table.insert(out, set)
		end
	end
	if #out ~= #c.sets then c.sets = out end
	return c.sets
end

function S.find(name)
	for _, set in ipairs(S.list()) do
		if set.name == name then return set end
	end
end

-- An element's pick now: its spell ID, 0 for No totem, nil when it can't be read.
local function pickNow(el)
	local action = TB.multiAction(TB.SLOT[el])
	local ok, has = pcall(C_ActionBar.HasAction, action)
	if not ok or isSecret(has) then return nil end
	if not has then return 0 end
	return TB.pickSpell(TB.SLOT[el])
end

-- The spell to pick for a saved one: 0 stays No totem; a totem, its highest known rank; nil when
-- the totem isn't known (or the saved value is not a spell ID).
local function pickFor(el, saved)
	if saved == 0 then return 0 end
	if type(saved) ~= "number" then return nil end
	for _, id in ipairs(ns.Totems.knownTotems(TB.SLOT[el])) do
		if ns.Spells.same(id, saved) then return id end
	end
end

-- Save the current picks under a name (replacing a set of that name). false when the list is full.
function S.save(name)
	local list = S.list()
	local set = S.find(name)
	if not set then
		if #list >= S.MAX then return false end
		set = { name = name }
		table.insert(list, set)
	end
	set.picks = {}
	for _, el in ipairs(TB.ELEMENTS) do set.picks[el] = pickNow(el) end
	return true
end

-- Delete a set, and any rule that named it.
function S.remove(name)
	local list = S.list()
	for i = #list, 1, -1 do
		if list[i].name == name then table.remove(list, i) end
	end
	local rules = cfg().setRules
	for k, v in pairs(rules) do
		if v == name then rules[k] = nil end
	end
end

-- Put a set's picks back (out of combat; in combat, once it ends). why: the place it was chosen
-- for (auto-switch), said in chat when a pick changes; nil for a set chosen by hand.
function S.apply(name, why)
	if not S.find(name) then return end
	if ns.deferInCombat("totem set", function() S.apply(name, why) end) then
		ns.say("totem set %s: after combat", name)
		return
	end
	local set = S.find(name)
	local wanted = {}
	for _, el in ipairs(TB.ELEMENTS) do
		local want = pickFor(el, set.picks[el])
		if want ~= nil and pickNow(el) ~= want then
			wanted[el] = want
			ns.try("totem set: pick", SetMultiCastSpell, TB.multiAction(TB.SLOT[el]), want)
		end
	end
	if not next(wanted) then return end
	if why then ns.say("%s: totem set %s", why, name) end
	-- Read back: a pick the game didn't take is said, never assumed.
	C_Timer.After(0.5, function()
		for el, want in pairs(wanted) do
			local now = pickNow(el)
			if now ~= nil and now ~= want then
				ns.say("totem set %s: the game didn't take the %s pick", name, TB.NAME[el]:lower())
				return
			end
		end
	end)
end

------------------------------------------------------------------------
-- Switching by place: on entering a kind of place other than the last one, its rule's set. A
-- /reload keeps the picks as they are (it isn't a new place); a login applies the rule for where
-- you are, a moment later, once the spellbook has loaded.
------------------------------------------------------------------------
local lastContent
local function contentNow()
	local ok, inInstance, kind = pcall(IsInInstance)
	if not ok or isSecret(inInstance) or isSecret(kind) then return nil end
	return CONTENT_OF[inInstance and kind or "none"]
end
function S.contentName(content)
	for _, c in ipairs(S.CONTENT) do if c[1] == content then return c[2] end end
end

local function check(apply)
	if not ns.getDB() or not TB.isShaman() then return end
	local content = contentNow()
	if not content or content == lastContent then return end
	lastContent = content
	local name = apply and cfg().setRules[content]
	if type(name) == "string" and S.find(name) then S.apply(name, S.contentName(content)) end
end

local ev = CreateFrame("Frame")
ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
ns.registerEvent(ev, "ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event, isLogin, isReload)
	if event == "PLAYER_ENTERING_WORLD" and isLogin then
		C_Timer.After(3, function() check(true) end)
	else
		check(not (event == "PLAYER_ENTERING_WORLD" and isReload and lastContent == nil))
	end
end)

table.insert(TB.EXPERIMENTAL, { "Totem sets", "Totem bar > Sets" })
