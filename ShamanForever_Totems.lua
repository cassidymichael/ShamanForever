-- Totems

local _, ns = ...
local say, isSecret, describeArg = ns.say, ns.isSecret, ns.describeArg
local Spells = ns.Spells

local T = { name = "totems" }
ns.Totems = T

-- Slots: 1 fire, 2 earth, 3 water, 4 air
local owner = {}   -- slot -> spell key, or "other"
local spells = {}
local slotByID, slotByName = {}, {}
local listeners = {}

-- fn(event, slot, ...): "cast" (slot, spell key), "gone" (slot, last duration object)
function T.subscribe(fn) table.insert(listeners, fn) end
local function notify(...) for _, fn in ipairs(listeners) do fn(...) end end

-- Dismissals all go through DestroyTotem
local dismissedAt = {}
if DestroyTotem then hooksecurefunc("DestroyTotem", function(slot) dismissedAt[slot] = GetTime() end) end

-- A totem is out only when it has a name (an empty slot can report haveTotem)
function T.read(slot)
	if not GetTotemInfo then return nil end
	local ok, have, name, _, _, icon, _, spellID = ns.try("totems: info", GetTotemInfo, slot)
	if not ok or isSecret(have) or isSecret(name) then return nil end
	if not have or type(name) ~= "string" or name == "" then return false end
	if isSecret(spellID) or type(spellID) ~= "number" then spellID = nil end
	if isSecret(icon) or type(icon) ~= "number" then icon = nil end
	return true, spellID, icon
end

local function multiCast(slot) return { GetMultiCastTotemSpells(slot) } end

function T.knownTotems(slot)
	if not GetMultiCastTotemSpells then return {} end
	local ok, ids = ns.try("totems: known", multiCast, slot)
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

function T.ownerOf(slot) return owner[slot] end
function T.spellInSlot(slot) return spells[slot] end
function T.setOwner(slot, spellKey, spellID)
	owner[slot] = spellKey
	if spellID then spells[slot] = spellID end
end

-- Never the slot's name: right after a cast it can still be the previous totem's
function T.downSpell(slot)
	local id = spells[slot]
	if id then return id end
	if InCombatLockdown() then return nil end
	local ok, _, _, _, _, _, _, sid = ns.try("totem bar: totem info", GetTotemInfo, slot)
	if ok and not isSecret(sid) and type(sid) == "number" and sid > 0 then return sid end
end

-- Returns the spell key ("other" if untracked) and how it was told: "cast", "slot spell", or nil, "slot icon", icon
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

function T.resolve()
	if not GetMultiCastTotemSpells then return end
	local byID, byName = {}, {}
	for slot = 1, 4 do
		local ok, ids = ns.try("totems: known", multiCast, slot)
		if not ok then return end
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

-- dur: the gone totem's last duration object (killed early vs ran out)
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

function T.forget(slot)
	owner[slot], spells[slot] = nil, nil
end

function T.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "PLAYER_TOTEM_UPDATE")
	ev:SetScript("OnEvent", function() ns.refreshCooldownsSoon() end)
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
