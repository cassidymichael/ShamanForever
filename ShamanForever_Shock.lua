-- Shocks: the tracked shock's cooldown, whether the target is in its range and whether there's mana
-- for it (or for another shock, the Mana check), the pop when it's ready, the "use me" glow and the
-- interrupt cue.
--
-- Nothing here reads a secret value: the cooldown is a duration object that Blizzard's widgets draw,
-- range and mana are read with the answer checked for a secret first, and the ready glow's alpha is
-- the cooldown's remaining time through a curve (ShamanForever_Cooldowns.lua, which this file
-- shares the cooldown reads with).
--
-- The interrupt cue (experimental: not yet tested on a target in combat): a glow while your
-- attackable target casts something you can interrupt and Earth Shock is ready. An enemy's cast is
-- secret in and out of combat, spell ID included. UnitCastingInfo and UnitChannelInfo still return
-- values only while the unit casts or channels, and how many they return is plain; that is "casting
-- now". Whether the cast can be interrupted may be a secret boolean: it goes straight to
-- SetAlphaFromBoolean on a frame of its own; a plain one lights the glow only when it is false (nil
-- is not known). Earth Shock being off cooldown is its cooldown's time left through a curve into the
-- glow's own alpha (as the ready glow). The three alphas multiply, so the glow shows only when all
-- three hold. Read ten times a second while the option is on and the target can be attacked; no
-- cast event is needed.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, CD = ns.Spells, ns.Cooldowns

local SK = { name = "shock" }
ns.Shock = SK

local function db() return ns.getDB() end
local setting = ns.elementSetting

-- Shock choice -> spell key; SHOCKS holds the display names (the client's, set by SK.resolve).
local SHOCK_SPELL = { earth = "earthShock", flame = "flameShock", frost = "frostShock" }
local SHOCKS = {}
for key, spell in pairs(SHOCK_SPELL) do SHOCKS[key] = Spells.name(spell) end
local SHOCK_ORDER = { "earth", "flame", "frost" }
SK.SHOCKS, SK.ORDER = SHOCKS, SHOCK_ORDER

local shock = ns.newElementIcon("shock")
shock.cdTimer = ns.Timer.new(shock, "shock", "cooldown", { cd = shock.cd, school = "spirit" })
local shockIcon = 136026
-- By SK.resolve: the known shocks' spell IDs by choice, the shock the icon tracks (usedShock) and
-- its spell ID, and the Mana check's spell ID.
local shockIDs = {}
local usedShock, shockSpellID, manaSpellID
local defaults = CopyTable(CD.READY_DEFAULTS)
defaults.castGlow, defaults.castColor = false, { 1, 0.35, 0.85, 1 }   -- the interrupt cue
ns.registerElement("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end,
	learned = function() return next(shockIDs) ~= nil end,   -- any shock
	defaults = defaults,
	kind = "shock", icon = 136026, school = "spirit", blurb = "Cooldown, range and mana." })

local shockState = { outOfRange = false, noMana = false }
local rangeCheckID   -- the spell whose range check is on

-- Shock looks, fixed rule: out of range paints the body red; not enough mana paints the body blue
-- and adds a blue ring; when both apply the body is red (range) and the ring blue (mana).
local drawn   -- what drawTint last drew; drawn again only on a change
local function drawTint()
	local now = (shockState.outOfRange and "r" or "") .. (shockState.noMana and "m" or "")
	if now == drawn then return end
	drawn = now
	local d = db()
	shock.manaOverlay:Hide()
	shock.tex:SetVertexColor(1, 1, 1)
	if shockState.outOfRange then
		shock:SetBodyPaint(d.rangeStyle, 1, 0.25, 0.25, d.rangeIntensity, d.rangeTint)
	elseif shockState.noMana then
		shock:SetBodyPaint(d.manaStyle, 0.2, 0.45, 1, d.manaIntensity, d.manaTint)
	end
	shock:SetRingShown(shockState.noMana, 0.2, 0.45, 1, d.manaRing)
end

-- inEvent: from SPELL_UPDATE_COOLDOWN (onCooldowns).
local function refreshCooldown(inEvent)
	if not shockSpellID or not ns.isEnabled("shock") then return CD.resetReady(shock) end
	local dur = CD.cooldownFor(shock, "shock", shockSpellID, inEvent)
	if dur then shock.cdTimer:set(dur) end
end

-- While the element is off (hidden, or no shock known) nothing is read and its looks are cleared,
-- so none comes back stale when it shows again.
local function refreshRange()
	if not shockSpellID or not ns.isEnabled("shock") then
		shockState.outOfRange = false
		drawTint()
		return
	end
	-- The event also fires for other spells' checks; the 4 Hz ticker covers ours either way.
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	drawTint()
end

local function refreshMana()
	if not manaSpellID or not ns.isEnabled("shock") then
		shockState.noMana = false
		drawTint()
		return
	end
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ok and not isSecret(noPower) and noPower == true
	drawTint()
end

CD.popWhenReady(shock, "shock")

------------------------------------------------------------------------
-- Ready glow ("use me"), off by default: while the shock is off cooldown (ShamanForever_Cooldowns.lua
-- has the rule), re-read ten times a second while it's on.
------------------------------------------------------------------------
local function refreshGlow()
	local on = shockSpellID and ns.isEnabled("shock") and setting("shock", "readyGlow") and ns.CURVE_OVER
	shock.glowF:SetShown(on and true or false)
	if not on then return end
	shock.glowF:fit(shock:GetWidth())
	shock.glowF:SetAlpha(CD.readyAlpha(shockSpellID, ns.cantAct()))
end
local glowTicker = CD.readyTicker(refreshGlow)
-- Runs only while the glow is turned on (checked on every layout, i.e. every settings change).
local function syncGlowTicker()
	local want = ns.isActive() and ns.isEnabled("shock") and setting("shock", "readyGlow")
	glowTicker:SetShown(want and true or false)
	if not want then refreshGlow() end   -- one last pass turns the glow off
end

------------------------------------------------------------------------
-- Interrupt cue, off by default (see the file's header)
------------------------------------------------------------------------
-- Nested, bottom up: casting (plain), interruptible (maybe secret), then the glow, whose own alpha is
-- Earth Shock's ready state and whose inner frame does the pulsing.
local castGate = CreateFrame("Frame", nil, shock)
castGate:SetAllPoints()
local kickGate = CreateFrame("Frame", nil, castGate)
kickGate:SetAllPoints()
local castGlow = ns.makeGlow(kickGate, shock, "shock")
castGlow:Hide()
-- For /sf debug: passes read, casts seen, and each cast's notInterruptible by kind.
local cast = { reads = 0, casting = 0, kickSecret = 0, kickTrue = 0, kickFalse = 0, kickNil = 0 }

-- Whether the target casts or channels now, and its notInterruptible (plain or secret).
local function castInfo(at, ok, ...)
	if not ok or select("#", ...) == 0 then return false end
	local first = ...
	if not isSecret(first) and first == nil then return false end
	return true, (select(at, ...))
end
local function readCast()
	local casting, noKick = castInfo(8, safe(UnitCastingInfo, "target"))
	if not casting then casting, noKick = castInfo(7, safe(UnitChannelInfo, "target")) end
	return casting, noKick
end

-- Earth Shock (its highest known rank) is the shock that interrupts.
local function castWanted()
	return shockIDs.earth and ns.isActive() and ns.isEnabled("shock") and setting("shock", "castGlow") and ns.CURVE_OVER
end

local castTicker
local function refreshCast()
	local watch = castWanted() and ns.Target.hostile()
	local casting, noKick = false, nil
	if watch then casting, noKick = readCast() end
	castGate:SetAlpha(casting and 1 or 0)
	castGlow:SetShown(casting)   -- its pulse runs only during a cast
	-- A target that died or turned friendly stops the polling until the next target change.
	if not watch then castTicker:Hide() return end
	cast.reads = cast.reads + 1
	if not casting then return end
	cast.casting = cast.casting + 1
	castGlow:fit(shock:GetWidth())
	if isSecret(noKick) then
		cast.kickSecret = cast.kickSecret + 1
		if not ns.try("interrupt cue", kickGate.SetAlphaFromBoolean, kickGate, noKick, 0, 1) then kickGate:SetAlpha(0) end
	else
		if noKick == nil then cast.kickNil = cast.kickNil + 1
		elseif noKick then cast.kickTrue = cast.kickTrue + 1
		else cast.kickFalse = cast.kickFalse + 1 end
		kickGate:SetAlpha(noKick == false and 1 or 0)
	end
	castGlow:SetAlpha(CD.readyAlpha(shockIDs.earth, ns.cantAct()))
end
castTicker = CD.readyTicker(refreshCast)

-- Polled only while the cue is on and the target can be attacked (a target change, a layout);
-- one pass either way, which also clears the glow when it stops.
local function syncCast()
	castTicker:SetShown((castWanted() and ns.Target.hostile()) and true or false)
	refreshCast()
end

local function applyCast()
	-- Over the icon's art like its ready glow; regrouping can move frame levels, so restated here.
	local level = shock.glowF:GetFrameLevel()
	castGate:SetFrameLevel(level)
	kickGate:SetFrameLevel(level)
	castGlow:SetFrameLevel(level)
	local c = setting("shock", "castColor")
	if type(c) == "table" then castGlow:color(c[1], c[2], c[3]) end
	syncCast()
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After a spellbook scan: the shocks' names and highest known ranks, the one the icon tracks and
-- its icon, the Mana check's spell, and the range check. Returns a signature of what it found.
function SK.resolve()
	local d = db()
	shockIDs = {}
	local icons = {}
	for key, spell in pairs(SHOCK_SPELL) do
		SHOCKS[key] = Spells.name(spell)
		local id, ic = Spells.known(spell)
		if id then shockIDs[key], icons[key] = id, ic end
	end
	-- The chosen shock, or until it is learned the first one known: the shocks share one cooldown,
	-- so the cooldown and ready state are the chosen one's too. Range and mana follow the shock used.
	usedShock = SHOCK_SPELL[d.shock] and d.shock or "earth"
	if not shockIDs[usedShock] then
		for _, key in ipairs(SHOCK_ORDER) do
			if shockIDs[key] then usedShock = key break end
		end
	end
	shockSpellID = shockIDs[usedShock]
	shockIcon = icons[usedShock] or Spells.icon(SHOCK_SPELL[usedShock]) or 136026
	shock.tex:SetTexture(shockIcon)
	-- Not learned yet (seen only in test mode): a plain grey icon.
	shock.tex:SetDesaturated(next(shockIDs) == nil)
	manaSpellID = (d.manaSpell ~= "tracked" and shockIDs[d.manaSpell]) or shockSpellID
	if rangeCheckID ~= shockSpellID and C_Spell.EnableSpellRangeCheck then
		if rangeCheckID then safe(C_Spell.EnableSpellRangeCheck, rangeCheckID, false) end
		if shockSpellID then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
		rangeCheckID = shockSpellID
	end
	-- Every known shock, so learning one lays the HUD out again (the element's learned()).
	local sig = { tostring(shockSpellID), tostring(manaSpellID) }
	for _, key in ipairs(SHOCK_ORDER) do table.insert(sig, tostring(shockIDs[key])) end
	return table.concat(sig, ",")
end

function SK.applyTimers() shock.cdTimer:apply() end

-- The groups were laid out: the element may have just been shown or hidden, with nothing else to
-- say that range or mana changed (full mana out of combat fires no event).
function SK.afterGroups()
	refreshMana()
	refreshRange()
	applyCast()
end

-- After a layout (settings may have changed): the looks, then the mana read again.
function SK.applyLayout()
	drawn = nil   -- the looks may have changed
	drawTint()
	refreshMana()
	syncGlowTicker()
	applyCast()
end

function SK.refresh()
	refreshCooldown()
	refreshRange()
	refreshMana()
end

SK.onCooldowns = refreshCooldown

-- Our own cast of any shock arms the next ready: the shocks share one cooldown.
local SHOCK_KEY = {}
for _, spell in pairs(SHOCK_SPELL) do SHOCK_KEY[spell] = true end
function SK.onCast(spellID)
	if shockSpellID and ns.isEnabled("shock") and SHOCK_KEY[Spells.keyOf(spellID)] then CD.noteCast(shock, shockSpellID) end
end

-- Once a second: a cooldown's end fires no event.
function SK.tick() ns.try("shock refresh", refreshCooldown) end

-- A shaman logged in: the shock's own events, and its range four times a second.
function SK.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "SPELL_UPDATE_USABLE")
	ns.registerEvent(ev, "UNIT_POWER_UPDATE", "player")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "UNIT_FACTION", "target")   -- a target that turns hostile or friendly
	ns.registerEvent(ev, "SPELL_RANGE_CHECK_UPDATE")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then refreshMana()
		elseif event == "SPELL_RANGE_CHECK_UPDATE" then refreshRange()
		else
			refreshRange()
			syncCast()
		end
	end)
	C_Timer.NewTicker(0.25, function() ns.try("range refresh", refreshRange) end)
end

-- /sf debug
function SK.debug()
	local chosen = db().shock
	say("shock spell %s (%s%s), mana spell %s", tostring(shockSpellID), tostring(usedShock),
		usedShock ~= chosen and (", chosen " .. tostring(chosen) .. " not learned") or "", tostring(manaSpellID))
	for key, id in pairs(shockIDs) do
		local _, usable, noPower = safe(C_Spell.IsSpellUsable, id)
		local _, inRange = safe(C_Spell.IsSpellInRange, id, "target")
		local e = Spells.bookEntry(SHOCK_SPELL[key])
		say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
			e and e.rank or "?", describeArg(usable), describeArg(noPower), describeArg(inRange))
	end
	say("interrupt cue: %s, polling %s; reads %d, casting %d; can't be interrupted: secret %d, true %d, false %d, nil %d",
		castWanted() and "on" or "off", tostring(castTicker:IsShown()), cast.reads, cast.casting, cast.kickSecret,
		cast.kickTrue, cast.kickFalse, cast.kickNil)
end

ns.registerModule(SK)
