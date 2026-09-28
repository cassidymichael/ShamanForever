-- Totems: which of our totems is in each slot. In combat everything GetTotemInfo returns is secret
-- (tested 2026-09-23), but our own UNIT_SPELLCAST_SUCCEEDED is not: it gives the spell, in combat too,
-- in the same frame as the PLAYER_TOTEM_UPDATE that fills the slot (tested 2026-09-24). So the totem
-- in each slot is the last totem we cast into it. Call of the Elements fires one cast per totem it
-- drops, after its own (tested 2026-09-25), so its totems are bound like any other.
--
-- Used by the totem elements and the totem bar. The bar reports a slot that emptied
-- (T.slotEmptied); unless we dismissed that totem or a new one took its place, the elements and the
-- bar hear it's gone (T.subscribe).

local _, ns = ...
local say, isSecret, describeArg = ns.say, ns.isSecret, ns.describeArg
local Spells = ns.Spells

local T = { name = "totems" }
ns.Totems = T

-- Totem slots: 1 fire, 2 earth, 3 water, 4 air.
local owner = {}    -- slot -> the spell key (ns.Spells) of the totem we last cast into it, or "other"
local spells = {}   -- slot -> its spell ID
-- Which slot a totem spell fills: from the multi-cast bar's lists, by ID, and for a rank not listed
-- there by the client's name (ranks share it).
local slotByID, slotByName = {}, {}
local listeners = {}

-- fn(event, slot, ...): "cast" (slot, spell key) after our own cast into a slot; "gone" (slot, the
-- totem's last duration object) when a slot emptied without our dismissing or replacing it.
-- Listeners are called in the order they subscribed.
function T.subscribe(fn) table.insert(listeners, fn) end
local function notify(...) for _, fn in ipairs(listeners) do fn(...) end end

-- Our own dismissals: every one goes through DestroyTotem (right-click, keys, dismiss all,
-- Blizzard's frame), and Totemic Recall is our own cast (T.onCast).
local dismissedAt = {}   -- slot -> GetTime() of our last dismissal
if DestroyTotem then hooksecurefunc("DestroyTotem", function(slot) dismissedAt[slot] = GetTime() end) end

-- Whether a totem is out in a slot, its spell ID and icon (each nil if not given); nil when the slot
-- cannot be read. haveTotem alone is not enough: on Forever an empty slot reports haveTotem true with a
-- blank name, and a slot can also return nothing at all (both seen 2026-09-23). So a totem is out
-- only when it has a name. The name itself is never used to tell totems apart (it is in the
-- client's language and carries the rank, "Stoneclaw Totem II").
function T.read(slot)
	if not GetTotemInfo then return nil end
	local ok, have, name, _, _, icon, _, spellID = pcall(GetTotemInfo, slot)
	if not ok or isSecret(have) or isSecret(name) then return nil end
	if not have or type(name) ~= "string" or name == "" then return false end
	if isSecret(spellID) or type(spellID) ~= "number" then spellID = nil end
	if isSecret(icon) or type(icon) ~= "number" then icon = nil end
	return true, spellID, icon
end

-- The totems known for a slot, by spell ID, in Blizzard's order; a totem known at several ranks
-- (one name in the client's language) is listed once, at its highest.
function T.knownTotems(slot)
	if not GetMultiCastTotemSpells then return {} end
	local ok, ids = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
	if not ok then return {} end
	local out, at = {}, {}
	for _, id in ipairs(ids) do
		local name = Spells.nameOf(id)
		if name then
			local i = at[name]
			if not i then table.insert(out, id); at[name] = #out
			elseif Spells.rank(id) > Spells.rank(out[i]) then out[i] = id end
		end
	end
	return out
end

-- The spell key of the totem in a slot (our last cast into it), "other", or nil while unknown.
function T.ownerOf(slot) return owner[slot] end
-- The spell ID of our last cast into a slot, nil while unknown.
function T.spellInSlot(slot) return spells[slot] end
-- Learned some other way (from the slot itself while it's readable: see T.identify).
function T.setOwner(slot, spellKey, spellID)
	owner[slot] = spellKey
	if spellID then spells[slot] = spellID end
end

-- The totem down in a slot, by spell ID: our own last cast into it (exact, in combat too), else,
-- while the slot is readable (out of combat, not in a PvP match), the slot's own spell ID (after a
-- /reload, before we have cast). Never the slot's name: right after a cast it can still be the
-- previous totem's. nil when unknown.
function T.downSpell(slot)
	local id = spells[slot]
	if id then return id end
	if InCombatLockdown() then return nil end
	local ok, _, _, _, _, _, _, sid = ns.try("totem bar: totem info", GetTotemInfo, slot)
	if ok and not isSecret(sid) and type(sid) == "number" and sid > 0 then return sid end
end

-- Which of our totems is in a slot: our last cast into it, else, when the slot is readable (out of
-- combat and not in a PvP match; a /reload with a totem already down), the slot's own spell, kept
-- as the owner so it holds into combat. Returns its spell key ("other" for one we don't track) and
-- how it was told ("cast", "slot spell"); when only the slot's icon can be read, nil, "slot icon"
-- and the icon (every rank shares it), for the caller to match; nil, "unknown" otherwise.
function T.identify(slot)
	if owner[slot] then return owner[slot], "cast" end
	local have, spellID, icon = T.read(slot)
	if have and spellID then
		local key = Spells.keyOf(spellID) or "other"
		T.setOwner(slot, key, spellID)
		return key, "slot spell"
	elseif have and icon then return nil, "slot icon", icon end
	return nil, "unknown"
end

-- After a spellbook scan (ns.resolveSpells): which slot each totem spell fills.
function T.resolve()
	if not GetMultiCastTotemSpells then return end
	local byID, byName = {}, {}
	for slot = 1, 4 do
		local ok, ids = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
		if not ok then return end   -- keep the last good map
		for _, id in ipairs(ids) do
			if type(id) == "number" and not isSecret(id) then
				byID[id] = slot
				local name = Spells.nameOf(id)
				if name then byName[name] = slot end
			end
		end
	end
	slotByID, slotByName = byID, byName
end

-- Our own cast: Totemic Recall dismisses every totem; a totem cast is remembered in its slot.
function T.onCast(spellID)
	if Spells.keyOf(spellID) == "recall" then
		for s = 1, 4 do dismissedAt[s] = GetTime() end
	end
	local slot = slotByID[spellID]
	if not slot then
		local name = Spells.nameOf(spellID)
		slot = name and slotByName[name]
		if not slot then return end
		slotByID[spellID] = slot
	end
	local key = Spells.keyOf(spellID) or "other"
	owner[slot], spells[slot] = key, spellID
	notify("cast", slot, key)
end

-- The totem bar saw a slot that had a totem empty: dur is the gone totem's last duration object
-- (how much time it had left says killed early or ran out; ns.makeEndFlash). A moment later, unless
-- we dismissed it or a new totem filled the slot, the listeners hear it's "gone". A slot that stayed
-- empty forgets its totem: one that fills it next without a cast we can place (a totem not on the
-- multi-cast bar's lists) is then unknown, never taken for the last one.
function T.slotEmptied(slot, dur)
	C_Timer.After(0.1, function()
		local mine = dismissedAt[slot] and GetTime() - dismissedAt[slot] < 1.5
		local ok, d = ns.try("totem bar: duration", GetTotemDuration, slot)
		local refilled = ok and d ~= nil
		if refilled then return end
		if not mine then notify("gone", slot, dur) end
		if ok then owner[slot], spells[slot] = nil, nil end
	end)
end

-- /sf debug
function T.debug()
	for slot = 1, 4 do
		local ok, have, name, start, duration, icon, _, spellID = pcall(GetTotemInfo, slot)
		say("totem slot %d: %s", slot, ok and string.format("have=%s name=%s start=%s duration=%s icon=%s spellID=%s",
			describeArg(have), describeArg(name), describeArg(start), describeArg(duration), describeArg(icon), describeArg(spellID))
			or ("error " .. tostring(have)))
		local dok, d = pcall(GetTotemDuration, slot)
		if dok and d then
			local rok, rem = pcall(d.GetRemainingDuration, d)
			local tok, total = pcall(d.GetTotalDuration, d)
			say("  duration object: remaining=%s total=%s", rok and describeArg(rem) or "error", tok and describeArg(total) or "error")
		end
	end
	if C_Secrets and C_Secrets.ShouldTotemSlotBeSecret then
		local t = {}
		for slot = 1, 4 do
			local ok, v = pcall(C_Secrets.ShouldTotemSlotBeSecret, slot)
			t[slot] = ok and describeArg(v) or "error"
		end
		say("totem slots secret now: %s", table.concat(t, ", "))
	end
end

ns.registerModule(T)
