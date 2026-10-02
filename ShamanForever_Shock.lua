-- Shocks

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, CD = ns.Spells, ns.Cooldowns

local SK = { name = "shock" }
ns.Shock = SK

ns.Profiles.addRanges({ manaRing = { 0.1, 1 }, manaIntensity = { 0.1, 1 }, manaTint = { 0.1, 1 },
	rangeIntensity = { 0.1, 1 }, rangeTint = { 0.1, 1 } })

local function db() return ns.getDB() end
local setting = ns.elementSetting

local SHOCK_SPELL = { earth = "earthShock", flame = "flameShock", frost = "frostShock" }
local SHOCKS = {}
for key, spell in pairs(SHOCK_SPELL) do SHOCKS[key] = Spells.name(spell) end
local SHOCK_ORDER = { "earth", "flame", "frost" }
SK.SHOCKS, SK.ORDER = SHOCKS, SHOCK_ORDER

local shock = ns.newElementIcon("shock", { effects = true })
shock.cdTimer = ns.Timer.new(shock, "shock", "cooldown", { cd = shock.cd, school = "spirit" })
shock.stack()
local shockIcon = 136026
local shockIDs = {}
local usedShock, shockSpellID, manaSpellID
local defaults = CopyTable(CD.READY_DEFAULTS)
defaults.idleWhen, defaults.idleAlpha = "never", 0.3
ns.registerElement("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end,
	learned = function() return next(shockIDs) ~= nil end,
	defaults = defaults,
	def = { key = "shock", idleChoices = CD.IDLE_CHOICES },
	effects = { glow = { "ready" }, pop = { "ready" } },
	kind = "shock", icon = 136026, school = "spirit", blurb = "Cooldown, range and mana." })

local idleDef = { key = "shock", frame = shock }

local shockState = { outOfRange = false, noMana = false }
local rangeCheckID

-- Out of range: red body; no mana: blue body and ring; both: red body, blue ring
local drawn
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

local function refreshCooldown(inEvent)
	if not shockSpellID or not ns.isEnabled("shock") then
		idleDef.cdRunning, idleDef.idle, idleDef.idleAt = nil, nil, nil
		ns.fadeTo(shock, 1)
		return CD.resetReady(shock)
	end
	local dur = CD.cooldownFor(shock, "shock", shockSpellID, inEvent)
	if dur then shock.cdTimer:set(dur) end
	idleDef.spellID = shockSpellID
	CD.applyIdle(idleDef, false, inEvent)
end
idleDef.refresh = function() refreshCooldown() end
-- A cooldown's end fires no event
shock.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, refreshCooldown) end)

local function refreshRange()
	if not shockSpellID or not ns.isEnabled("shock") then
		shockState.outOfRange = false
		drawTint()
		return
	end
	-- Fires for other spells' checks too: the ticker covers ours
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
CD.soundWhenReady(shock, "shock")

-- Ready glow
local function refreshGlow()
	local on = shockSpellID and ns.isEnabled("shock") and setting("shock", "readyGlow") and ns.CURVE_OVER
	shock.glowF:SetShown(on and true or false)
	if not on then return end
	shock.glowF:fit(shock:GetWidth())
	shock.glowF:SetAlpha(CD.readyAlpha(shockSpellID, ns.cantAct()))
end
local glowTicker = CD.readyTicker(refreshGlow)
local function syncGlowTicker()
	local want = ns.isActive() and ns.isEnabled("shock") and setting("shock", "readyGlow")
	glowTicker:SetShown(want and true or false)
	if not want then refreshGlow() end
end

function SK.resolve()
	local d = db()
	shockIDs = {}
	local icons = {}
	for key, spell in pairs(SHOCK_SPELL) do
		SHOCKS[key] = Spells.name(spell)
		local id, ic = Spells.known(spell)
		if id then shockIDs[key], icons[key] = id, ic end
	end
	usedShock = SHOCK_SPELL[d.shock] and d.shock or "earth"
	if not shockIDs[usedShock] then
		for _, key in ipairs(SHOCK_ORDER) do
			if shockIDs[key] then usedShock = key break end
		end
	end
	shockSpellID = shockIDs[usedShock]
	idleDef.cdRunning = nil
	shockIcon = icons[usedShock] or Spells.icon(SHOCK_SPELL[usedShock]) or 136026
	shock.tex:SetTexture(shockIcon)
	shock.tex:SetDesaturated(next(shockIDs) == nil)
	manaSpellID = (d.manaSpell ~= "tracked" and shockIDs[d.manaSpell]) or shockSpellID
	if rangeCheckID ~= shockSpellID and C_Spell.EnableSpellRangeCheck then
		if rangeCheckID then safe(C_Spell.EnableSpellRangeCheck, rangeCheckID, false) end
		if shockSpellID then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
		rangeCheckID = shockSpellID
	end
	local sig = { tostring(shockSpellID), tostring(manaSpellID) }
	for _, key in ipairs(SHOCK_ORDER) do table.insert(sig, tostring(shockIDs[key])) end
	return table.concat(sig, ",")
end

function SK.applyTimers() shock.cdTimer:apply() end

-- Full mana out of combat fires no event
function SK.afterGroups()
	refreshMana()
	refreshRange()
end

function SK.applyLayout()
	drawn = nil
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

local SHOCK_KEY = {}
for _, spell in pairs(SHOCK_SPELL) do SHOCK_KEY[spell] = true end
function SK.onCast(spellID)
	if shockSpellID and ns.isEnabled("shock") and SHOCK_KEY[Spells.keyOf(spellID)] then CD.noteCast(shock, shockSpellID) end
end

function SK.tick() ns.try("shock refresh", refreshCooldown) end

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
end

ns.registerModule(SK)
