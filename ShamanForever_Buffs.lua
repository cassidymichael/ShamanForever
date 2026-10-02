-- Buff elements
-- Water buffs in combat: auras are secret, so the timer runs on from the last read.
-- Elemental Focus: only Blizzard's aura container can show a proc in combat.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells = ns.Spells

local B = { name = "buffs" }
ns.Buffs = B

local setting = ns.elementSetting

local TEXT_TIMER = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 }, textPos = "center",
	swipe = false, bar = true } }
local BUFFS = {
	{ key = "waterwalking", spellKey = "waterWalking", icon = 135863, school = "water", reagent = 17058, duration = 600,
		blurb = "Time left while it's up.", styles = TEXT_TIMER,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, fade = false } }, experimental = "Water Walking" },
	{ key = "waterbreathing", spellKey = "waterBreathing", icon = 136148, school = "water", reagent = 17057, duration = 600,
		breath = true, blurb = "Time left while it's up. Warns under water without it.", styles = TEXT_TIMER,
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, fade = false } }, experimental = "Water Breathing" },
	{ key = "elementalfocus", spellKey = "elementalFocus", buffKey = "clearcasting", icon = 136170, school = "spirit",
		blurb = "Shows while " .. Spells.name("clearcasting") .. " is up.",
		proc = true, defaults = { idleAlpha = 0 },
		styles = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	},
}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Target's rows are of this
-- kind too, with parts of their own (_Target); the reagent's is _Reagents', Expiring's _Timers'.
local function procName(def) return def.buffKey and Spells.name(def.buffKey) end
ns.registerPart("buff", {
	idle = { text = function(def)
		return def.proc and procName(def) and ("Idle while " .. procName(def) .. " isn't up") or "Idle while it isn't up"
	end },
	page = {
		uptime = function(def) return not def.noTimer and "Time left" or nil end,
		expire = {},
		active = function(def)
			return { title = def.procHeader or procName(def),
				tips = { pop = def.popTip or "The moment it procs.", glow = def.glowTip or "While it's up." } }
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
		render = function(ic, st, def, P)
			local key = def.key
			P.reset(ic, def.icon)
			if st == "up" then
				if def.proc then
					if not def.noTimer then P.frozen(ic.upT, 0.3, 15) end
					ic:SetGlowShown(setting(key, "active", "glow"))
				else P.frozen(ic.upT, 0.3, 600) end
			elseif st == "expiring" and not def.engineExpire then P.expiring(ic, key, 600)
			elseif st == "idle" then
				if setting(key, "idleWhen") ~= "never" then P.idle(ic, key) end
			end
			if (st == "up" or st == "expiring") and setting(key, "idleWhen") == "target" then P.idle(ic, key) end
		end,
		rest = function(ic, def, P, keep) if not keep then P.idle(ic, def.key) end end,
	},
})
-- breath: warns under water without it
ns.registerPart("breath", {
	defaults = { warn = { on = true, ring = true, fade = true } },
	page = { warn = { title = "Under water", on = { "Warn without it", "While your breath bar drains and it isn't up." } } },
	preview = {
		warning = "underwater",
		states = { { "underwater", "Under water", 80 } },
		render = function(ic, st, def, P)
			if st ~= "underwater" then return end
			if setting(def.key, "warn", "on") then
				ic:SetRingShown(setting(def.key, "warn", "ring"))
				ic:SetPulsing(setting(def.key, "warn", "fade"))
			else P.idle(ic, def.key) end
		end,
	},
})
-- proc: shown by Blizzard's aura container while the aura is up (noPop, noGlow: without its own)
ns.registerPart("proc", {
	has = function(def) return def.proc and not (def.noPop and def.noGlow) end,
	defaults = { active = { pop = true, glow = true } },
	glow = function(def) return not def.noGlow and { "active" } or nil end,
	pop = function(def) return not def.noPop and { "active" } or nil end,
	preview = {
		pop = function(ic, st, def)
			if st == "up" and setting(def.key, "active", "pop") then ic:Pop("ready") end
		end,
	},
})
local EXPIRE_RANGE = { 0, 120, 5 }
ns.registerKind("buff", {
	parts = { "buff", "breath", "skipLong", "reagent", "missing", "engineExpire", "proc", "expire" },
	slots = { "own", "warn", "uptime", "expire", "active" },
	prepare = function(def)
		def.expires = not def.proc
		def.expireRange = EXPIRE_RANGE
	end,
})

local function makeBuffIcon(def)
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if not def.proc then
		f.upTimer = ns.Timer.new(f, def.key, "uptime", { cd = f.cd, school = def.school })
	end
	f.stack()
	return f
end

for _, def in ipairs(BUFFS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.buffKey or def.spellKey) or def.icon
	def.frame = makeBuffIcon(def)
	def.frame.aboveProtected = def.proc   -- Blizzard's aura button sits under it
	ns.registerElement(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults or {}, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		standInBorder = def.proc,
		ranges = def.ranges,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, styles = def.styles })
end

-- Water buff time
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
	if isSecret(exp) or isSecret(dur) or type(exp) ~= "number" or type(dur) ~= "number" or exp <= 0 or dur <= 0 then return end
	def.duration = dur
	if not def.upUntil or math.abs(def.upUntil - exp) > 0.2 then setUp(def, exp - dur, dur) end
end

local function castOnSelf()
	local ok, exists = safe(UnitExists, "target")
	if not ok or isSecret(exists) or not exists then return true end
	local sok, me = safe(UnitIsUnit, "target", "player")
	if sok and not isSecret(me) and me then return true end
	local fok, friend = safe(UnitIsFriend, "player", "target")
	if not fok or isSecret(friend) then return true end
	return not friend
end

-- Under water without Water Breathing
local breathing = false
local function underWaterWarns(def)
	return def.breath and breathing and not def.upUntil and setting(def.key, "warn", "on") and not ns.cantAct()
end

-- Elemental Focus
local function procIDMap(def)
	if not def.procIDs then
		def.procIDs = {}
		for id in pairs(Spells.ids(def.buffKey)) do def.procIDs[id] = true end
	end
	return def.procIDs
end

local function buildProc(def, slot, button)
	def.fx:bind(button, slot.icon)
	def.edge = def.fx:makeEdge(button)
end

local function styleProc(def, size)
	ns.try("proc border " .. def.key, ns.Frames.dress, def.edge, def.key)
	ns.try("proc pop " .. def.key, def.fx.stylePop, def.fx, size)
end

local function styleGlow(def)
	if InCombatLockdown() then return end
	def.fx:levelGlow()
	def.fx:style()
end

local function makeProcSlot(def)
	local ids = function() return procIDMap(def) end
	def.aura = ns.makeAuraSlot(def.frame, {
		key = def.key, slot = "proc", ids = ids, parent = def.frame.effects,
		sites = { container = "proc container " .. def.key, style = "proc style " .. def.key,
			filter = "proc filter " .. def.key },
		onButton = function(slot, button) buildProc(def, slot, button) end,
		onStyle = function(_, size) styleProc(def, size) end,
		onError = function(err) ns.noteError("proc container " .. def.key, err) end,
	})
	def.fx = ns.Effects.host(def.frame, def.key, { aura = {
		slot = def.aura, parent = def.frame.effects, ids = ids,
		popOn = function() return setting(def.key, "active", "pop") end,
		sites = { container = "proc glow sensor " .. def.key, style = "proc glow style " .. def.key,
			filter = "proc glow filter " .. def.key },
	} })
end
for _, def in ipairs(BUFFS) do
	if def.proc then makeProcSlot(def) end
end

local previewing = false

local function refreshBuff(def)
	local f, key = def.frame, def.key
	if def.proc then f.tex:SetAlpha(previewing and 0 or 1) end
	if not ns.isEnabled(key) then
		if def.proc then def.fx:glow(false) end
		return
	end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.count:Hide()
		ns.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	if def.proc then
		-- Frame is an ancestor of Blizzard's button: its alpha changes out of combat only
		def.fx:glow(setting(key, "active", "glow") and not previewing)
		ns.fadeTo(f, ns.getAccount().locked and ns.idleAlpha(key) or 1)
		return
	end
	if def.upUntil and GetTime() >= def.upUntil then setDown(def) end
	-- Set each look once: re-setting a pulse restarts it
	local held, ring, pulse = false, false, false
	if def.reagent then held, ring, pulse = ns.Reagents.refresh(def) end
	if underWaterWarns(def) then
		ring, pulse, held = setting(key, "warn", "ring"), setting(key, "warn", "fade"), true
	end
	f:SetRingShown(ring)
	f:SetPulsing(pulse)
	local busy = not ns.getAccount().locked or def.upUntil ~= nil or held
	ns.fadeTo(f, busy and 1 or ns.idleAlpha(key))
end

local function refreshAll()
	for _, def in ipairs(BUFFS) do refreshBuff(def) end
end

function B.resolve()
	ns.Reagents.readPerk()
	local sig = {}
	for _, def in ipairs(BUFFS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		local known, icon = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end
		def.spellID = known
		local before = def.procIDs
		def.procIDs = nil
		if def.proc and before and def.aura.container then
			for id in pairs(procIDMap(def)) do
				if not before[id] then
					def.aura:refilter()
					def.fx:refilter()
					break
				end
			end
		end
		if def.proc then def.fx:checkIDs() end
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
			t:setExpire(ns.elementEvent(def.key, "expire"), def.iconID or def.icon)
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
		if def.proc and def.spellID and ns.isEnabled(def.key) then
			def.aura:setup()
			def.fx:setup()
		end
		if def.proc then
			def.aura:style()
			styleGlow(def)
		end
	end
	refreshAll()
end
B.afterGroups = function()
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
		if ok and not isSecret(name) and name == "BREATH" and type(scale) == "number" and not isSecret(scale) and scale < 0 then
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

function B.preview(shown)
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
				a.err and (", error: " .. a.err) or "", def.fx:describe())
		else
			state = def.upUntil and string.format("up, %.0f s left", def.upUntil - GetTime()) or "not up"
			if def.reagent then state = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", state,
				describeArg(def.reagentRead), tostring(def.takesReagent), tostring(ns.Reagents.perkKnown())) end
			if def.breath then state = state .. ", breath bar " .. tostring(breathing) end
		end
		say("%s: spell %s, %s", def.spell, tostring(def.spellID), state)
	end
end

ns.registerModule(B)
