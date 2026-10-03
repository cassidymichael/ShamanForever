-- Buff elements
-- A buff with a timer: auras are secret in combat, so the timer runs on from the last read.
-- A proc: only Blizzard's aura container can show one in combat, on the player or another unit.

local _, ns = ...
local P = ns.Profiles
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, KD, CS = ns.Spells, ns.Kinds, ns.CastStates

local B = { name = "buffs" }
ns.Buffs = B

local setting = E.setting

-- Elements: the class's rows (ns.CLASS.buffs), all built here; BUFFS are those this file runs. Rows
-- from other files join the list before this file loads.
local ROWS = ns.CLASS.buffs or {}
local BUFFS = {}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Other files' rows and
-- parts join it: the reagent's (_Reagents), Expiring's (_Timers), a class's own.
local function procName(def) return def.buffKey and Spells.name(def.buffKey) end
ns.registerPart("buff", {
	idle = { text = function(def)
		local name = def.proc and procName(def)
		return name and ("Idle while " .. name .. " isn't up") or "Idle while it isn't up"
	end },
	page = {
		uptime = function(def) return not def.noTimer and "Time left" or nil end,
		expire = {},
		active = function(def)
			local tips = { pop = def.popTip or "The moment it procs.",
				glow = def.glowTip or "While it's up." }
			return { title = def.procHeader or procName(def), tips = tips }
		end,
	},
	preview = {
		uptime = true,
		labels = { low = "Not up, few left", out = "Not up, none left" },
		states = function(def)
			local states = { { "up", def.proc and (def.upLabel or procName(def)) or "Up", 10 } }
			if not def.proc then table.insert(states, { "expiring", "Expiring", 20 }) end
			table.insert(states, { "idle", def.idleLabel or "Not up", 40 })
			return states
		end,
		render = function(ic, st, def, kit)
			local key = def.key
			kit.reset(ic, def.icon)
			if st == "up" then
				if def.proc then
					if not def.noTimer then kit.frozen(ic.upT, 0.3, 15) end
					ic:SetGlowShown(setting(key, "active", "glow"))
				else kit.frozen(ic.upT, 0.3, 600) end
			elseif st == "expiring" and not def.engineExpire then kit.expiring(ic, key, 600)
			elseif st == "idle" then
				if setting(key, "idleWhen") ~= "never" then kit.idle(ic, key) end
			end
		end,
		rest = function(ic, def, kit, keep) if not keep then kit.idle(ic, def.key) end end,
	},
})
-- breath: warns under water without it
ns.registerPart("breath", {
	defaults = { warn = { on = true, ring = true, fade = true, glow = false } },
	page = { warn = { title = "Under water",
		on = { "Warn without it", "While your breath bar drains and it isn't up." } } },
	preview = {
		warning = "underwater",
		states = { { "underwater", "Under water", 80 } },
		render = function(ic, st, def, kit)
			if st ~= "underwater" then return end
			if setting(def.key, "warn", "on") then ic:SetWarnParts(W.warnParts(def.key, "warn"))
			else kit.idle(ic, def.key) end
		end,
	},
})
-- proc: shown by Blizzard's aura container while the aura is up (noPop, noGlow: without its own)
ns.registerPart("proc", {
	has = function(def) return def.proc and not (def.noPop and def.noGlow) end,
	defaults = { active = { pop = true, glow = true } },
	glow = function(def) return not def.noGlow end,
	pop = function(def) return not def.noPop end,
	preview = {
		pop = function(ic, st, def)
			if st == "up" and setting(def.key, "active", "pop") then ic:Pop("ready") end
		end,
	},
})
-- Rows with proc are shown by Blizzard's aura container. The builder reads their fields: filter
-- (else "HELPFUL"), candidates(def) (candidate filters, else the aura's IDs), auraKey or buffKey
-- (the aura's spell, any rank), ownIcon (the row's icon, not the aura's), noTimer (no time left),
-- noGlow and noPop (without its own glow or pop; with neither, no effect host).
-- A part's runtime hooks for them (each optional; parts from other files bring their own):
--   make(def)                  at load, after the icon, before the aura slot: frames of its own;
--                              returns { looks, extras }: aura looks set up, refiltered and checked
--                              with the slot, and more slots on its container (makeAuraSlot); it
--                              may set def.borderHost (registerElement's: the frame its border is on)
--   aura(def)                  where the aura is read, else on the player: { unit, slot, parent,
--                              site, glow = { unit, needUnit, parent } }
--   button(def, slot, button)  Blizzard's button was made, after its pop and border
--   style(def, size, slot)     the button restyles, before its border and pop
--   engine                     true: its own module runs the element; this file builds it
-- make, button and style run for every part, in parts order; the others come from the first part
-- that gives one.
local EXPIRE_RANGE = { 0, 120, 5 }
ns.registerKind("buff", {
	parts = { "buff", "breath", "proc" },
	slots = { "own", "warn", "cast", "active", "expire", "uptime" },
	prepare = function(def)
		def.expires = not def.proc
		def.expireRange = EXPIRE_RANGE
	end,
})

local NONE = {}

local function makeBuffIcon(def)
	local f = E.newIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if not def.proc then
		f.upTimer = ns.Timer.new(f, def.key, "uptime", { cd = f.cd, school = def.school })
	end
	f.stack()
	return f
end

-- The aura's IDs: any rank of its spell
local function auraIDs(def)
	if not def.ids then
		def.ids = {}
		local key = def.auraKey or def.buffKey
		if key then for id in pairs(Spells.ids(key)) do def.ids[id] = true end end
	end
	return def.ids
end
B.auraIDs = auraIDs

-- An aura element's button: its pop, its border (the button draws the border's art), then parts'
local function buildButton(def, slot, button, site)
	if def.fx then def.fx:bind(button, slot.icon) end
	def.edge = def.fx and def.fx:makeEdge(button)
		or ns.Frames.edge(button, button, def.key, { overlay = false })
	-- Dressed now too: its styling may wait for the fight to end
	ns.try(site .. " border " .. def.key, ns.Frames.dress, def.edge, def.key)
	KD.eachHook("buff", def, "button", slot, button)
end

local function styleButton(def, size, slot, site)
	KD.eachHook("buff", def, "style", size, slot)
	if def.edge then ns.try(site .. " border " .. def.key, ns.Frames.dress, def.edge, def.key) end
	if def.fx then ns.try(site .. " pop " .. def.key, def.fx.stylePop, def.fx, size) end
end

-- Its slot and, unless it has neither glow nor pop, its effect host (glow and pop on the button)
local function buildAura(def)
	local key, f = def.key, def.frame
	def.looks, def.extras = {}, {}
	for _, p in ipairs(KD.partsOf("buff", def)) do
		local made = p.runtime and p.runtime.make and p.runtime.make(def) or NONE
		for _, look in ipairs(made.looks or NONE) do table.insert(def.looks, look) end
		for _, x in ipairs(made.extras or NONE) do table.insert(def.extras, x) end
	end
	local where = KD.hook("buff", def, "aura")
	where = where and where(def) or { slot = "proc", parent = f.effects, site = "proc",
		glow = { parent = f.effects } }
	local site = where.site
	local ids = function() return auraIDs(def) end
	local candidates = def.candidates and function() return def.candidates(def) end
	def.aura = W.makeAuraSlot(f, {
		key = key, slot = where.slot, unit = where.unit, filter = def.filter, parent = where.parent,
		ids = ids, candidates = candidates,
		ownIcon = def.ownIcon and function() return def.icon end, noTimer = def.noTimer,
		extras = #def.extras > 0 and def.extras or nil,
		sites = { container = site .. " container " .. key, style = site .. " style " .. key,
			filter = site .. " filter " .. key },
		onButton = function(slot, button) buildButton(def, slot, button, site) end,
		onStyle = function(slot, size) styleButton(def, size, slot, site) end,
		onError = function(err) ns.noteError(site .. " container " .. key, err) end,
	})
	if def.noGlow and def.noPop then return end
	local g = where.glow
	def.fx = ns.Effects.host(f, key, { aura = {
		slot = def.aura, parent = g.parent, unit = g.unit, needUnit = g.needUnit, filter = def.filter,
		ids = ids, candidates = candidates,
		popOn = function() return not def.noPop and setting(key, "active", "pop") end,
		sites = { container = site .. " glow sensor " .. key, style = site .. " glow style " .. key,
			filter = site .. " glow filter " .. key },
	} })
end

-- A cast state's paint over the button, while the aura is up: sensed as its glow is, faded with the
-- button
local function auraCover(def)
	local where = KD.hook("buff", def, "aura")
	local g = where and where(def).glow or { parent = def.frame.effects }
	return { parent = def.idle or g.parent, sensorParent = g.parent, unit = g.unit, needUnit = g.needUnit,
		filter = def.filter, ids = function() return auraIDs(def) end,
		candidates = def.candidates and function() return def.candidates(def) end, slot = def.aura,
		note = def.castNote, tips = def.castTips,
		-- Refiltered and pointed with the row's own looks while attached
		attach = function(look) table.insert(def.looks, look) end,
		detach = function(look)
			for i = #def.looks, 1, -1 do if def.looks[i] == look then table.remove(def.looks, i) end end
		end }
end

for _, def in ipairs(ROWS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.buffKey or def.spellKey) or def.icon
	def.frame = makeBuffIcon(def)
	def.frame.aboveProtected = def.proc   -- Blizzard's aura button sits under it
	if def.proc then buildAura(def) end
	E.register(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults or {}, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		standInBorder = def.proc, borderHost = def.borderHost,
		ranges = def.ranges,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, styles = def.styles })
	if not KD.hook("buff", def, "engine") then table.insert(BUFFS, def) end
	if def.power or def.range then CS.watchRow(def, def.proc and auraCover(def) or nil) end
end

-- An aura element's steps, for whichever module runs it
-- Its slot, looks and host made (out of combat, auras readable: they wait otherwise)
function B.setupAura(def)
	def.aura:setup()
	for _, look in ipairs(def.looks) do look:setup() end
	if def.fx then def.fx:setup() end
end
-- After a spellbook scan: a new rank's ID refilters each look
function B.resolveAura(def)
	local before = def.ids
	def.ids = nil
	if before and def.aura.container then
		for id in pairs(auraIDs(def)) do
			if not before[id] then
				def.aura:refilter()
				for _, look in ipairs(def.looks) do look:refilter() end
				if def.fx then def.fx:refilter() end
				break
			end
		end
	end
	for _, look in ipairs(def.looks) do look:checkIDs() end
	if def.fx then def.fx:checkIDs() end
end
-- Its glow's level and look (out of combat: the host restyles its sensor)
function B.styleGlow(def)
	if not def.fx or InCombatLockdown() then return end
	def.fx:levelGlow()
	def.fx:style()
end
local styleGlow = B.styleGlow

-- A timed buff's time
local function setUp(def, start, length)
	def.upUntil = start + length
	def.frame.upTimer:setTime(start, length)
end
local function setDown(def)
	def.upUntil = nil
	def.frame.upTimer:clear()
end

local function readAura(def)
	if not ns.aurasReadable() or not C_UnitAuras then return end
	local ok, a = safe(C_UnitAuras.GetAuraDataBySpellName, "player", def.spell, "HELPFUL")
	if not ok then return end
	if type(a) ~= "table" then setDown(def) return end
	local exp, dur = a.expirationTime, a.duration
	if isSecret(exp) or isSecret(dur) or type(exp) ~= "number" or type(dur) ~= "number" or exp <= 0 or dur <= 0 then
		return
	end
	def.duration = dur
	if not def.upUntil or math.abs(def.upUntil - exp) > 0.2 then setUp(def, exp - dur, dur) end
end

local function castOnSelf()
	local ok, exists = safe(UnitExists, "target")
	if not ok or isSecret(exists) or not exists then return true end
	if ns.plain(safe(UnitIsUnit, "target", "player")) then return true end
	local fok, friend = safe(UnitIsFriend, "player", "target")
	if not fok or isSecret(friend) then return true end
	return not friend
end

-- Under water without the breath buff
local breathing = false
local function underWaterWarns(def)
	return def.breath and breathing and not def.upUntil and setting(def.key, "warn", "on") and not ns.cantAct()
end

local previewing = false

local function refreshBuff(def)
	local f, key = def.frame, def.key
	if def.proc then f.tex:SetAlpha(previewing and 0 or 1) end
	if not E.isEnabled(key) then
		if def.fx then def.fx:glow(false) end
		return
	end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		if def.glowing then f:SetGlowShown(false); def.glowing = false end
		f.count:Hide()
		W.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	if def.proc then
		-- Frame is an ancestor of Blizzard's button: its alpha changes out of combat only
		if def.fx then def.fx:glow(setting(key, "active", "glow") and not previewing) end
		W.fadeTo(f, P.getAccount().locked and E.idleAlpha(key) or 1)
		return
	end
	if def.upUntil and GetTime() >= def.upUntil then setDown(def) end
	-- Set each look once: re-setting a pulse restarts it
	local held, ring, pulse, glow = false, false, false, false
	if def.reagent then held, ring, pulse = ns.Reagents.refresh(def) end
	if underWaterWarns(def) then
		ring, pulse, held = setting(key, "warn", "ring"), setting(key, "warn", "fade"), true
		glow = setting(key, "warn", "glow")
	end
	f:SetRingShown(ring)
	f:SetPulsing(pulse)
	if def.breath and glow ~= (def.glowing or false) then
		def.glowing = glow and true or false
		f:SetGlowShown(def.glowing)
	end
	local busy = not P.getAccount().locked or def.upUntil ~= nil or held
	W.fadeTo(f, busy and 1 or E.idleAlpha(key))
end

local function refreshAll()
	for _, def in ipairs(BUFFS) do refreshBuff(def) end
end

function B.resolve()
	ns.Reagents.readPerk()
	local sig = {}
	for _, def in ipairs(BUFFS) do
		def.spell = Spells.name(def.spellKey)
		E.ALL[def.key].label = def.spell
		local known, icon = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end
		def.spellID = known
		if def.proc then B.resolveAura(def) end
		if not def.proc then def.iconID = icon end
		table.insert(sig, tostring(known))
	end
	return table.concat(sig, ",")
end

function B.applyTimers()
	for _, def in ipairs(BUFFS) do
		local t = def.frame.upTimer
		if t then
			t:apply()
			t:setExpire(E.event(def.key, "expire"), def.iconID or def.icon)
		end
	end
	for _, def in ipairs(BUFFS) do
		if def.proc then
			def.aura:style()
			styleGlow(def)
		end
	end
end

function B.applyLayout()
	for _, def in ipairs(BUFFS) do
		if def.proc and def.spellID and E.isEnabled(def.key) then B.setupAura(def) end
		if def.proc then
			def.aura:style()
			styleGlow(def)
		end
	end
	refreshAll()
end
function B.afterGroups()
	for _, def in ipairs(BUFFS) do
		if def.proc then
			def.aura:style()
			styleGlow(def)
		end
	end
end

local function readBreath()
	breathing = false
	for i = 1, 3 do
		local ok, name, _, _, scale = safe(GetMirrorTimerInfo, i)
		if ok and not isSecret(name) and name == "BREATH" and type(scale) == "number" and not isSecret(scale)
			and scale < 0 then
			breathing = true
		end
	end
end

function B.refresh()
	readBreath()
	for _, def in ipairs(BUFFS) do
		if not def.proc then readAura(def) end
	end
	refreshAll()
end

B.tick = refreshAll

function B.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not key or ns.aurasReadable() then return end
	for _, def in ipairs(BUFFS) do
		if not def.proc and key == def.spellKey and def.spellID and castOnSelf() then
			setUp(def, GetTime(), def.duration)
			refreshBuff(def)
		end
	end
end

function B.start()
	readBreath()
	ns.onCanActChange(refreshAll)
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "MIRROR_TIMER_START")
	ns.registerEvent(ev, "MIRROR_TIMER_STOP")
	ev:SetScript("OnEvent", function(_, event, timer, _, _, scale)
		if event == "UNIT_AURA" then
			if not InCombatLockdown() then B.refresh() end   -- secret in combat
			return
		end
		if isSecret(timer) or timer ~= "BREATH" then return end
		breathing = event == "MIRROR_TIMER_START" and type(scale) == "number" and not isSecret(scale) and scale < 0
		if breathing then for _, def in ipairs(BUFFS) do if def.breath then setDown(def) end end end
		refreshAll()
	end)
end

function B.onPreview(shown)
	previewing = shown
	refreshAll()
end

-- /sf debug
function B.debug()
	for _, def in ipairs(BUFFS) do
		local state
		if def.proc then
			local a = def.aura
			state = string.format("container %s%s; %s", a.container and "made" or "not made",
				a.err and (", error: " .. a.err) or "", def.fx and def.fx:describe() or "no glow or pop")
		else
			state = def.upUntil and string.format("up, %.0f s left", def.upUntil - GetTime()) or "not up"
			if def.reagent then state = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", state,
				describeArg(def.reagentRead), tostring(def.takesReagent), tostring(ns.Reagents.perkKnown())) end
			if def.breath then state = state .. ", breath bar " .. tostring(breathing) end
		end
		say("%s: spell %s, %s", def.spell, tostring(def.spellID), state)
	end
end

MOD.register(B)
