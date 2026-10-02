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

-- Cooldown parts (ns.registerPart)
local setting = ns.elementSetting

-- totemSlot: a totem of its own in that slot; its end runs out (ranOut: a flash, not the pop) or is
-- killed early (grounded: it took a spell)
local function ended(def)
	local e = { pop = not def.ranOut, sound = "none" }
	if def.ranOut then e.flash, e.glow = true, false end
	return e
end
local function endFlash(ic, def, P, st, opts, secs)
	if opts then
		if not ic.endFlash then ic.endFlash = ns.Effects.endFlash(ic, ic, def.key) end
		ic.endFlash:setIcon(def.iconID or def.icon)
		ic.endFlash:play(nil, opts)
	end
	local token = {}
	ic.momentToken, ic.momentDone = token, false
	C_Timer.After(opts and secs or 0, function()
		if ic.momentToken ~= token or P.current(def.key) ~= st then return end
		ic.momentDone = true
		P.frozen(ic.cdT, 0.05, def.cd or 15)
	end)
end
ns.registerPart("totemSlot", {
	kind = "cooldown", after = "needsTotem",
	defaults = function(def)
		local killed = def.grounded and { flash = true, pop = true, glow = true }
			or { flash = true, pop = true, glow = true, mark = true }
		return { ended = ended(def), killed = killed }
	end,
	glow = true, pop = true,
	idle = { held = "no totem out", also = " and its totem isn't out" },
	page = {
		uptime = "Time left",
		expire = { tips = { endPop = "The totem pops and fades the moment it runs out.",
			endSound = "When it runs out or is killed. Not when you dismiss it." } },
		killed = function(def)
			if def.grounded then
				return { title = "Grounded", tips = { glow = "In blue." }, flash = { "Flash when it takes a spell",
					"The totem flashes blue over its icon when it ends early: it took a spell, or was destroyed." } }
			end
			return { flash = { "Flash when it dies early",
				"The dead totem flashes red over its icon. Not when you dismiss it or it runs out." } }
		end,
	},
	preview = {
		uptime = true, typical = "active",
		states = function(def)
			return { { "active", "Totem down", 20 }, { "expiring", "Expiring", 22 }, { "ranout", "Ran out", 23 },
				{ "killed", def.grounded and "Grounded" or "Killed early", 60 } }
		end,
		render = function(ic, st, def, P)
			local e = ic.endFlash
			if e and st ~= ic.flashState then
				e:stop()
				ic.momentDone = false
			end
			ic.flashState = st
			local life = def.duration or 45
			if st == "expiring" then P.expiring(ic, def.key, life)
			elseif st == "active" then P.frozen(ic.upT, 0.45, life)
			elseif (st == "ranout" and def.ranOut) or st == "killed" then
				if ic.momentDone then P.frozen(ic.cdT, 0.05, def.cd or 15) end
			end
		end,
		pop = function(ic, st, def, P)
			local key = def.key
			local function on(name, field) return setting(key, name, field) end
			if st == "ranout" and def.ranOut then
				endFlash(ic, def, P, st, on("ended", "flash") and { expired = true, ranOut = ns.THEME.color[def.school],
					pop = on("ended", "pop"), glow = on("ended", "glow") }, 1.4)
			elseif st == "ranout" and on("ended", "pop") then ic:Pop("expired")
			elseif st == "killed" and def.grounded then
				endFlash(ic, def, P, st, on("killed", "flash") and { grounded = true, pop = on("killed", "pop"),
					glow = on("killed", "glow") }, 2.1)
			elseif st == "killed" then
				endFlash(ic, def, P, st, on("killed", "flash") and { pop = on("killed", "pop"), glow = on("killed", "glow"),
					mark = on("killed", "mark") }, 2.1)
			end
		end,
	},
})

-- needsTotem: castable only with a totem in that slot (Fire Nova: a fire totem)
local FIRE_NOVA_CHOICES = {
	{ "never", "Never", "It always shows in full" },
	{ "nototem", "No fire totem", "Idle while it's ready and no fire totem is out",
		"Idle only while it can't be cast." },
	{ "offcd", "Ready", "Idle while it's ready, with or without a fire totem out",
		"With or without a fire totem out." },
	{ "oncdany", "Cooling down", "Idle while it's cooling down, with or without a fire totem out",
		"With or without a fire totem out." },
	{ "oncd", "Cooling down, no fire totem", "Idle while it's cooling down and no fire totem is out",
		"Shown in full only while it's ready." },
}
ns.registerPart("needsTotem", {
	kind = "cooldown", after = "readyGlow",
	defaults = { warn = { grey = true, ring = false, fade = false }, ready = { glow = false, blocked = "grey" } },
	glow = true,
	idle = { choices = FIRE_NOVA_CHOICES },
	page = {
		warn = { title = "No fire totem" },
		uptime = "Fire totem's time left",
		ready = { glowTip = "While it's off cooldown and a fire totem is down.",
			blocked = { "Without a fire totem", "The pop when the cooldown ends with no fire totem down." } },
	},
	preview = {
		uptime = true, typical = "out", warning = "nototem",
		states = { { "nototem", "No fire totem", 20 }, { "out", "Fire totem out", 21 }, { "expiring", "Totem expiring", 22 } },
		render = function(ic, st, def, P)
			local key = def.key
			local life = def.duration or 45
			if st == "ready" then ic:SetGlowShown(false)
			elseif st == "expiring" then P.expiring(ic, key, life)
			elseif st == "nototem" then ic:SetWarnParts(ns.warnParts(key, "warn"))
			elseif st == "out" then
				P.frozen(ic.upT, 0.2, life)
				ic:SetGlowShown(setting(key, "ready", "glow"))
			end
		end,
		idles = function(st, _, when)
			if when == "oncd" or when == "oncdany" then return nil end
			if when == "offcd" then return st ~= "cd" end
			return st == "nototem" or st == "ready"
		end,
	},
})

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
