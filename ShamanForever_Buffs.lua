-- Buff elements: Water Walking and Water Breathing (our own ten-minute buffs), and Elemental Focus
-- (its Clearcasting proc). Each shows while its buff is up; while it isn't, it is idle, and at the
-- default Idle opacity of 0 it is hidden and keeps its place in its group.
--
-- What can be read, and when:
-- * Water Walking, Water Breathing: out of combat the aura is readable, so the time left is exact.
--   In combat, and all through a PvP match, auras are secret: the timer carries on from the last
--   read, and our own cast of the spell (readable in combat) restarts it when the target is us (a
--   guess: no friendly target but us). A buff dispelled or cancelled then, or a cast that went to
--   someone else, is seen when combat (or the match) ends.
-- * Water Breathing's underwater warning: the breath bar (a mirror timer, "BREATH") draining while
--   the buff isn't up. Readable in and out of combat (probed 2026-09-27): MIRROR_TIMER_START comes
--   with a negative scale while it drains under water, and again with a positive one while it
--   refills after surfacing; MIRROR_TIMER_STOP only once it's full.
-- * Elemental Focus: a proc can't be foreseen, so in combat only Blizzard's aura container
--   can show it (ns.makeAuraSlot, as for the shield). Its button draws the icon and time left
--   (swipe, countdown or bar). The container sits on the effects layer, which ignores the icon's
--   alpha: Idle fades only the icon under it (the look while no proc is up), never the proc
--   itself. Its glow and pop are its effect host's aura route (ns.Effects.host): the glow a clip
--   look lit exactly while the proc is up, the pop played by the button each time a proc arrives
--   (both tested in combat on Lightning Shield, 2026-10-01; not yet on the proc).

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells = ns.Spells

local B = { name = "buffs" }
ns.Buffs = B

local function setting(key, name) return ns.elementSetting(key, name) end

-- key, spellKey (ns.Spells), icon (fallback), school, blurb (the line under its name in the
-- options), reagent (item ID; counted only while the spell's tooltip names it: ns.Reagents.takes),
-- duration (seconds, until an aura read says), defaults (its own option defaults, over its parts':
-- PARTS below). Adding one is a line here, in the order the options list them.
local BUFFS = {
	{ key = "waterwalking", spellKey = "waterWalking", icon = 135863, school = "water", reagent = 17058, duration = 600,
		blurb = "Time left while it's up.",
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, pulse = false } }, experimental = "Water Walking" },
	{ key = "waterbreathing", spellKey = "waterBreathing", icon = 136148, school = "water", reagent = 17057, duration = 600,
		breath = true, blurb = "Time left while it's up. Warns under water without it.",
		defaults = { idleAlpha = 0, expire = { secs = 30, glow = true, pulse = false } }, experimental = "Water Breathing" },
	{ key = "elementalfocus", spellKey = "elementalFocus", buffKey = "clearcasting", icon = 136170, school = "spirit",
		blurb = "Shows while " .. Spells.name("clearcasting") .. " is up.",
		proc = true, defaults = { idleAlpha = 0 }, experimental = "Elemental Focus" },
}

------------------------------------------------------------------------
-- Elements
------------------------------------------------------------------------
-- Option defaults (ns.elementSetting) by part; a def's own defaults win over them.
local PARTS = {
	reagent = ns.Reagents.DEFAULTS,
	breath = { breathWarn = true, breathRing = true, breathPulse = true },   -- Under water
	proc = { primedPop = true, primedGlow = true },                          -- its proc's pop and glow
}

local function makeBuffIcon(def)
	-- Effects on a layer that ignores the icon's alpha (as the cooldown elements do), so an idle
	-- icon doesn't fade the expiring glow. Elemental Focus's aura container sits on that layer too;
	-- its frame level is its aura slot's (ns.makeAuraSlot), not f.stack's.
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if not def.proc then
		f.upTimer = ns.Timer.new(f, def.key, "uptime", { cd = f.cd, school = def.school })
	end
	f.stack()
	return f
end

for _, def in ipairs(BUFFS) do
	def.buff = true   -- for the options page and preview
	def.idleText = def.proc and ("Idle while " .. Spells.name("clearcasting") .. " isn't up")
		or "Idle while it isn't up"
	if def.reagent then def.idleExtra = ns.Reagents.IDLE_EXTRA end
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.buffKey or def.spellKey) or def.icon
	def.defaults = def.defaults or {}
	for part, defaults in pairs(PARTS) do
		if def[part] then ns.fillDefaults(def.defaults, defaults) end
	end
	def.frame = makeBuffIcon(def)
	def.frame.aboveProtected = def.proc   -- Elemental Focus: Blizzard's aura button sits under it
	ns.registerElement(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		-- Preview mode: the proc's border is on Blizzard's button, not its frame (ShamanForever_Preview.lua).
		standInBorder = def.proc,
		-- The water buffs never pop.
		effects = def.proc and { glow = { "up" }, pop = { "up" } } or { glow = { "expiring" }, pop = {} },
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental })
end

------------------------------------------------------------------------
-- Water Walking, Water Breathing: the buff's time
------------------------------------------------------------------------
-- def.upUntil: when the buff ends (GetTime's clock), nil while it isn't up.
local function setUp(def, start, length)
	def.upUntil = start + length
	def.frame.upTimer:setTime(start, length)
end
local function setDown(def)
	def.upUntil = nil
	def.frame.upTimer:clear()
end

-- While auras are readable: the aura, by the client's name for the spell (every rank shares it).
local function readAura(def)
	if InCombatLockdown() or ns.aurasSecret() or not C_UnitAuras then return end
	local ok, a = safe(C_UnitAuras.GetAuraDataBySpellName, "player", def.spell, "HELPFUL")
	if not ok then return end
	if type(a) ~= "table" then setDown(def) return end
	local exp, dur = a.expirationTime, a.duration
	if isSecret(exp) or isSecret(dur) or type(exp) ~= "number" or type(dur) ~= "number" or exp <= 0 or dur <= 0 then return end
	def.duration = dur
	if not def.upUntil or math.abs(def.upUntil - exp) > 0.2 then setUp(def, exp - dur, dur) end
end

-- Whether our cast just now was on ourselves: no friendly target but us means a self-cast. Anything
-- unreadable counts as ourselves (the buff then shows until an aura read says otherwise).
local function castOnSelf()
	local ok, exists = safe(UnitExists, "target")
	if not ok or isSecret(exists) or not exists then return true end
	local sok, me = safe(UnitIsUnit, "target", "player")
	if sok and not isSecret(me) and me then return true end
	local fok, friend = safe(UnitIsFriend, "player", "target")
	if not fok or isSecret(friend) then return true end
	return not friend
end

------------------------------------------------------------------------
-- Water Breathing: under water without it
------------------------------------------------------------------------
local breathing = false   -- the breath bar is draining (under water)
local function breathWarn(def)
	return def.breath and breathing and not def.upUntil and setting(def.key, "breathWarn") and not ns.cantAct()
end

------------------------------------------------------------------------
-- Elemental Focus: Blizzard's aura container (see the file's header, and ns.makeAuraSlot)
------------------------------------------------------------------------
-- Every ID of the proc's buff (seeds, and any learned since); made again at each spellbook scan.
local function procIDMap(def)
	if not def.procIDs then
		def.procIDs = {}
		for id in pairs(Spells.ids(def.buffKey)) do def.procIDs[id] = true end
	end
	return def.procIDs
end

-- Levels over the element's icon (its container's is the text's + 5, ns.makeAuraSlot): the glow
-- over the proc's button, the pop's light over that. Set from our own levels, never read from
-- Blizzard's button.
local GLOW_LEVEL, POP_LEVEL = 11, 13

-- The pop's rig on Blizzard's button, once it is made, with the group's border on the rig's body
-- so the two move together: the border shows exactly with the proc (the element's own frame, and
-- its border, sit at its Idle opacity). Styled out of combat only (styleProc).
local function buildProc(def, slot, button)
	local body = def.fx:bind(button, slot.icon, def.frame.textFrame:GetFrameLevel() + POP_LEVEL)
	def.edge = CreateFrame("Frame", nil, body)
	def.edge:SetAllPoints(body)
	def.edge.owner = def.key   -- its school colour (ns.Looks)
end

-- Our parts again, for the current size and settings (after the aura slot's own restyle).
local function styleProc(def, size)
	ns.try("proc border " .. def.key, ns.applyBorder, def.edge, ns.borderFor(def.key))
	ns.try("proc pop " .. def.key, def.fx.stylePop, def.fx, size)
end

-- The glow's sensor for the current size, look and levels (out of combat; it waits for that).
local function styleGlow(def)
	if InCombatLockdown() then return end
	def.fx:setLevel(def.frame.textFrame:GetFrameLevel() + GLOW_LEVEL)
	def.fx:style()
end

-- The proc's aura slot, on the effects layer (made while auras are readable; once made, it stays),
-- and its effect host: the glow on the effects layer beside it, the pop on its button.
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
		popOn = function() return setting(def.key, "primedPop") end,
		sites = { container = "proc glow sensor " .. def.key, style = "proc glow style " .. def.key,
			filter = "proc glow filter " .. def.key },
	} })
end
for _, def in ipairs(BUFFS) do
	if def.proc then makeProcSlot(def) end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local previewing = false   -- preview mode's stand-ins show (B.preview, below)

local function refreshBuff(def)
	local f, key = def.frame, def.key
	if def.proc then f.tex:SetAlpha(previewing and 0 or 1) end
	if not ns.isEnabled(key) then
		if def.proc then def.fx:glow(false) end
		return
	end
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		-- Not learned yet (seen only while the preview shows such elements): a plain grey icon.
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.count:Hide()
		ns.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	if def.proc then
		-- The button says whether it's up, and the glow's sensor; the icon under it is the idle
		-- look. The frame is an ancestor of Blizzard's button, so its alpha only changes out of
		-- combat (ns.fadeTo).
		def.fx:glow(setting(key, "primedGlow") and not previewing)
		ns.fadeTo(f, ns.getAccount().locked and ns.idleAlpha(key) or 1)
		return
	end
	if def.upUntil and GetTime() >= def.upUntil then setDown(def) end
	-- Each look decided first, then set once: setting a pulse off and on again restarts it.
	local held, ring, pulse = false, false, false
	if def.reagent then held, ring, pulse = ns.Reagents.refresh(def) end
	if breathWarn(def) then
		-- Under water without it: the missing look.
		ring, pulse, held = setting(key, "breathRing"), setting(key, "breathPulse"), true
	end
	f:SetRingShown(ring)
	f:SetPulsing(pulse)
	local busy = not ns.getAccount().locked or def.upUntil ~= nil or held
	ns.fadeTo(f, busy and 1 or ns.idleAlpha(key))
end

local function refreshAll()
	for _, def in ipairs(BUFFS) do refreshBuff(def) end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
function B.resolve()
	ns.Reagents.readPerk()   -- the spellbook changed: the perk may have come
	local sig = {}
	for _, def in ipairs(BUFFS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		local known, icon = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end   -- a new rank: read its tooltip again
		def.spellID = known
		local before = def.procIDs
		def.procIDs = nil
		-- A proc ID learned since: the slot and the glow's sensor take it together.
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
		-- A passive talent (Elemental Focus) has no icon of its own worth showing: keep the buff's.
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
			t:setExpire(ns.Timer.expireOpts(def.key), def.iconID or def.icon)
		end
	end
	for _, def in ipairs(BUFFS) do
		if def.proc then
			def.aura:style()
			styleGlow(def)   -- a glow style change (the options call this)
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
			styleGlow(def)   -- a new size or scale
		end
	end
end

-- Whether the breath bar is draining now (a /reload under water, or after a loading screen that
-- missed its events): negative scale means draining.
local function readBreath()
	breathing = false
	for i = 1, 3 do   -- the client's three mirror timers (EXHAUSTION, BREATH, DEATH, FEIGNDEATH)
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

-- Our own cast of Water Walking or Water Breathing on ourselves, while auras can't be read: up for
-- its duration. While they can, the buff's own UNIT_AURA says exactly (B.refresh), and a guess from
-- the target would count a cast on someone else (mouseover, party frames, a macro) as ours.
function B.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not key or not (InCombatLockdown() or ns.aurasSecret()) then return end
	for _, def in ipairs(BUFFS) do
		if not def.proc and key == def.spellKey and def.spellID and castOnSelf() then
			setUp(def, GetTime(), def.duration)
			refreshBuff(def)
		end
	end
end

function B.start()
	readBreath()   -- already under water (a /reload)
	ns.onCanActChange(refreshAll)   -- no breath warning while dead or a ghost
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "MIRROR_TIMER_START")
	ns.registerEvent(ev, "MIRROR_TIMER_STOP")
	ev:SetScript("OnEvent", function(_, event, timer, _, _, scale)
		if event == "UNIT_AURA" then
			if not InCombatLockdown() then B.refresh() end   -- auras are secret in combat: nothing to read
			return
		end
		if isSecret(timer) or timer ~= "BREATH" then return end
		-- Draining (negative scale) is under water; refilling after surfacing is not.
		breathing = event == "MIRROR_TIMER_START" and type(scale) == "number" and not isSecret(scale) and scale < 0
		-- The breath bar only runs without Water Breathing: a dispel or cancel in combat shows here.
		if breathing then for _, def in ipairs(BUFFS) do if def.breath then setDown(def) end end end
		refreshAll()
	end)
end

-- Preview mode (ShamanForever_Preview.lua): Elemental Focus is never parked, as Blizzard's button
-- hangs from it, so the preview's stand-in sits over it. Meanwhile its own icon under the stand-in is
-- clear, so its not-learned grey or its full look can't show through the stand-in's idle look. Only
-- our own texture changes, which is allowed at any time. shown: whether the preview shows.
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
