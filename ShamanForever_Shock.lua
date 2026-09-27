-- Shocks: the tracked shock's cooldown, whether the target is in its range and whether there's mana
-- for it (or for another shock, the Mana check), the pop when it's ready and the "use me" glow.
--
-- Nothing here reads a secret value: the cooldown is a duration object that Blizzard's widgets draw,
-- range and mana are read with the answer checked for a secret first, and the ready glow's alpha is
-- the cooldown's remaining time through a curve (ShamanForever_Cooldowns.lua, which this file
-- shares the cooldown reads with).

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
ns.registerElement("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end })

local shockSpellID, manaSpellID
local shockIDs = {}
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

local function refreshCooldown()
	if not shockSpellID or not ns.isEnabled("shock") then return end
	local dur = CD.cooldownFor(shock, "shock", shockSpellID)
	if dur then shock.cdTimer:set(dur) end
end

local function refreshRange()
	if not shockSpellID or not ns.isEnabled("shock") then return end
	-- The event also fires for other spells' checks; the 4 Hz ticker covers ours either way.
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	drawTint()
end

local function refreshMana()
	if not ns.isEnabled("shock") then return end
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
	shock.glowF:SetAlpha(CD.readyAlpha(shockSpellID))
end
local glowTicker = CD.readyTicker(refreshGlow)
-- Runs only while the glow is turned on (checked on every layout, i.e. every settings change).
local function syncGlowTicker()
	local want = ns.isActive() and ns.isEnabled("shock") and setting("shock", "readyGlow")
	glowTicker:SetShown(want and true or false)
	if not want then refreshGlow() end   -- one last pass turns the glow off
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After a spellbook scan: the shocks' names, the tracked one's highest rank and icon, the Mana
-- check's spell, and the range check. Returns a signature of what it found.
function SK.resolve()
	local d = db()
	shockIDs = {}
	for key, spell in pairs(SHOCK_SPELL) do
		SHOCKS[key] = Spells.name(spell)
		local id = Spells.known(spell)
		if id then shockIDs[key] = id end
	end
	local id, ic = Spells.known(SHOCK_SPELL[d.shock] or SHOCK_SPELL.earth)
	shockSpellID = id
	shockIcon = ic or 136026
	shock.tex:SetTexture(shockIcon)
	manaSpellID = (d.manaSpell ~= "tracked" and shockIDs[d.manaSpell]) or shockSpellID
	if rangeCheckID ~= shockSpellID and C_Spell.EnableSpellRangeCheck then
		if rangeCheckID then safe(C_Spell.EnableSpellRangeCheck, rangeCheckID, false) end
		if shockSpellID then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
		rangeCheckID = shockSpellID
	end
	return tostring(shockSpellID) .. "," .. tostring(manaSpellID)
end

function SK.applyTimers() shock.cdTimer:apply() end

-- After a layout (settings may have changed): the looks, then the mana read again.
function SK.applyLayout()
	drawn = nil   -- the looks may have changed
	drawTint()
	refreshMana()
	syncGlowTicker()
end

function SK.refresh()
	refreshCooldown()
	refreshRange()
	refreshMana()
end

SK.onCooldowns = refreshCooldown

-- Once a second: a cooldown's end fires no event.
function SK.tick() ns.try("shock refresh", refreshCooldown) end

-- A shaman logged in: the shock's own events, and its range four times a second.
function SK.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "SPELL_UPDATE_USABLE")
	ns.registerEvent(ev, "UNIT_POWER_UPDATE", "player")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "SPELL_RANGE_CHECK_UPDATE")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then refreshMana()
		else refreshRange() end
	end)
	C_Timer.NewTicker(0.25, function() ns.try("range refresh", refreshRange) end)
end

-- /sf debug
function SK.debug()
	say("shock spell %s (%s), mana spell %s", tostring(shockSpellID), db().shock, tostring(manaSpellID))
	for key, id in pairs(shockIDs) do
		local _, usable, noPower = safe(C_Spell.IsSpellUsable, id)
		local _, inRange = safe(C_Spell.IsSpellInRange, id, "target")
		local e = Spells.bookEntry(SHOCK_SPELL[key])
		say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
			e and e.rank or "?", describeArg(usable), describeArg(noPower), describeArg(inRange))
	end
end

ns.registerModule(SK)
