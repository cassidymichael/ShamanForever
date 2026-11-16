-- Totem sets: each Call drops its own four picks, a page of the multi-cast bar. The totem bar uses
-- one set at a time (its switch header's sf-set), switched in combat too by the header's snippet;
-- the character's choice is saved. Out of combat the options choose a set and write its picks.

local ADDON, ns = ...
local P = ns.Profiles

local TS = {}
ns.TotemSets = TS

-- By set: its Call's spell key and ID, and the level it's learned at
local CALL_KEYS = { "call", "callAncestors", "callSpirits" }
local CALLS = {}
for i, key in ipairs(CALL_KEYS) do
	CALLS[i] = ns.Spells.DEFS[key].ids[1]
end
TS.CALLS, TS.CALL_KEYS = CALLS, CALL_KEYS
TS.LEVELS = { 20, 30, 40 }

local state = { active = 1, count = 1, known = { true } }
for set = 2, #CALLS do state.known[set] = false end
function TS.active() return state.active end
function TS.count() return state.count end
function TS.known(set) return state.known[set] == true end

-- Switch to a set (0: the next known one): every button that follows the set takes that set's
-- action or spell, kept on it as sf-action<set> and sf-spell<set>; sf-set is written last
local SWITCH = string.format([[
	local want = ...
	local set = self:GetAttribute("sf-set") or 1
	if want == 0 then
		want = set
		for _ = 1, %d do
			want = want %% %d + 1
			if self:GetAttribute("sf-known" .. want) then break end
		end
	end
	if want == set or not self:GetAttribute("sf-known" .. want) then return end
	for i = 1, self:GetAttribute("sf-follows") or 0 do
		local b = self:GetFrameRef("follow" .. i)
		local v = b:GetAttribute("sf-action" .. want)
		if v then b:SetAttribute("action", v) end
		v = b:GetAttribute("sf-spell" .. want)
		if v then b:SetAttribute("spell", v) end
	end
	self:SetAttribute("sf-set", want)
]], #CALLS - 1, #CALLS)

-- The switch's snippet and attributes on a secure header, at load
function TS.prime(header)
	header:SetAttribute("sf-switch", SWITCH)
	header:SetAttribute("sf-set", 1)
	header:SetAttribute("sf-known1", true)
end

-- The plain side's set; chosen: the player's choice, saved for the character
function TS.setActive(set, chosen)
	state.active = set
	if not chosen then return end
	state.wanted = set
	local t = P.char()
	if t then t.totemSet = set end
end

-- The sets known (on the header too: out of combat), and the one to use: the character's choice
-- once its Call is known
function TS.update(header, knows)
	local count = 1
	for set = 2, #CALLS do
		state.known[set] = knows(CALLS[set])
		if state.known[set] then count = count + 1 end
		header:SetAttribute("sf-known" .. set, state.known[set])
	end
	state.count = count
	if not state.wanted then
		local t = P.char()
		local v = t and t.totemSet
		if type(v) == "number" and CALLS[v] then state.wanted = v
		elseif t then state.wanted = 1 end
	end
	local set = state.wanted or 1
	return state.known[set] and set or 1
end

-- Out of combat (the options' Use on the bar): the bar laid out again on the chosen set
function TS.switch(set)
	if not (CALLS[set] and TS.known(set)) or ns.inCombat() then return false end
	TS.setActive(set, true)
	ns.TotemBar.layout()
	ns.changed()
	return true
end

-- A set's pick out of combat (spell 0: none), by SetMultiCastSpell on its action; false where
-- refused before the call. The game refuses one by ADDON_ACTION_FORBIDDEN or _BLOCKED naming the
-- function, not a Lua error: then none is tried again this session, so its dialog shows once.
local refused = false
function TS.picksRefused() return refused end
local watch = CreateFrame("Frame")
watch:SetScript("OnEvent", function(_, _, addon, fn)
	if refused or ns.isSecret(addon) or ns.isSecret(fn) or addon ~= ADDON or type(fn) ~= "string"
		or not fn:find("SetMultiCastSpell", 1, true) then
		return
	end
	refused = true
	ns.changed()
end)
ns.registerEvent(watch, "ADDON_ACTION_FORBIDDEN")
ns.registerEvent(watch, "ADDON_ACTION_BLOCKED")

function TS.setPick(set, slot, spell)
	if refused or not (TS.known(set) and type(slot) == "number" and slot >= 1 and slot <= 4) then return false end
	if spell ~= 0 then
		local fits = false
		for _, id in ipairs(ns.Totems.knownTotems(slot)) do if id == spell then fits = true end end
		if not fits then return false end
	end
	if not SetMultiCastSpell or InCombatLockdown() then return false end
	ns.try("totem sets: pick", SetMultiCastSpell, ns.TotemBar.actionFor(slot, set), spell)
	return not refused
end
