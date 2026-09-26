-- Totems: which of our totems is in each slot. In combat everything GetTotemInfo returns is secret
-- (tested 2026-09-23), but our own UNIT_SPELLCAST_SUCCEEDED is not: it gives the spell, in combat too,
-- in the same frame as the PLAYER_TOTEM_UPDATE that fills the slot (tested 2026-09-24). So the totem
-- in each slot is the last totem we cast into it. Call of the Elements fires one cast per totem it
-- drops, after its own (tested 2026-09-25), so its totems are bound like any other.
--
-- Used by the cooldown elements (Earthbind, Stoneclaw) and the totem bar; the bar reports a slot
-- that emptied without our dismissing it (T.slotEmptied), and the elements hear of it (T.subscribe).

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
function T.subscribe(fn) table.insert(listeners, fn) end
local function notify(...) for _, fn in ipairs(listeners) do fn(...) end end

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

-- The spell key of the totem in a slot (our last cast into it), "other", or nil while unknown.
function T.ownerOf(slot) return owner[slot] end
-- The spell ID of our last cast into a slot, nil while unknown.
function T.spellInSlot(slot) return spells[slot] end
-- Learned some other way (out of combat, from the slot itself: see the cooldown elements).
function T.setOwner(slot, spellKey, spellID)
	owner[slot] = spellKey
	if spellID then spells[slot] = spellID end
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

-- Our own cast: if it put a totem in a slot, remember which.
function T.onCast(spellID)
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

-- The totem bar saw a slot empty that we didn't dismiss or refill: dur is the gone totem's last
-- duration object (how much time it had left says killed early or ran out; ns.makeEndFlash).
function T.slotEmptied(slot, dur) notify("gone", slot, dur) end

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
