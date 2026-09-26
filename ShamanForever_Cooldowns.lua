-- Shocks and the cooldown elements (Earthbind, Stoneclaw, Fire Nova): a spell's cooldown, the pop and
-- the "use me" glow when it's ready, and for a totem its time left, its end, and an idle look.
--
-- Nothing here reads a secret value:
-- * The spell cooldown and a totem's time are duration objects that Blizzard widgets draw (cooldown
--   swipe, countdown numbers, timer bar).
-- * Fire Nova's "no fire totem" warning: the fire slot's duration object evaluates its remaining time
--   through a curve (0s -> 1, anything more -> 0) and the result, secret or not, goes straight to
--   SetAlpha, which accepts secrets. An empty slot returns no duration object at all (seen
--   2026-09-23), which is plainly "no totem"; an expired one evaluates to 0s remaining.
--   (IsZero doesn't work: an expired totem's duration is not a zero time span.)
--   The addon never branches on it.
-- * Earthbind / Stoneclaw must tell their totem from any other earth totem: the totem in the slot is
--   the last one we cast into it (ShamanForever_Totems.lua), and the timer's holder is shown only
--   when that is this element's totem. The slot's duration object still drives the timer, and an
--   empty slot has none. When the owner is unknown (a /reload with a totem already out), out of
--   combat the slot says which totem it is (its spell ID, else its icon), and that is kept as the
--   owner. In combat the slot is secret, so the timer stays hidden until combat ends or the totem is
--   recast: a /reload in combat isn't worth guessing for.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, Totems = ns.Spells, ns.Totems

local CD = { name = "cooldowns" }
ns.Cooldowns = CD

local function db() return ns.getDB() end
local setting = ns.elementSetting

------------------------------------------------------------------------
-- Elements
------------------------------------------------------------------------
-- Shock choice -> spell key; SHOCKS holds the display names (the client's, set by CD.resolve).
local SHOCK_SPELL = { earth = "earthShock", flame = "flameShock", frost = "frostShock" }
local SHOCKS = {}
for key, spell in pairs(SHOCK_SPELL) do SHOCKS[key] = Spells.name(spell) end
local SHOCK_ORDER = { "earth", "flame", "frost" }
CD.SHOCKS, CD.SHOCK_ORDER = SHOCKS, SHOCK_ORDER

local shock = ns.newElementIcon("shock")
shock.cdTimer = ns.Timer.new(shock, "shock", "cooldown", { cd = shock.cd, school = "spirit" })
local shockIcon = 136026
ns.registerElement("shock", { frame = shock, label = "Shocks", paint = function(t) t:SetTexture(shockIcon) end })

-- Cooldown elements: a spell's cooldown, plus for a totem the active time of ours in its slot, or for
-- Fire Nova whether the fire totem it needs is out. Totem slots: 1 fire, 2 earth, 3 water, 4 air.
-- Adding one starts with a line here and its key in ShamanForever.lua's ELEMENT_KEYS (its look and
-- page go in the Options files); spellKey is its spell in ns.Spells, icon the fallback until the
-- spellbook has it, duration the totem's lifetime in seconds (for the options previews). spell is
-- the display name (the client's).
local COOLDOWNS = {
	{ key = "earthbind", spellKey = "earthbind", icon = 136102, totemSlot = 2, duration = 45, school = "earth" },
	{ key = "stoneclaw", spellKey = "stoneclaw", icon = 136097, totemSlot = 2, duration = 15, school = "earth" },
	{ key = "firenova",  spellKey = "fireNova",  icon = 135824, needsTotem = 1, school = "fire" },
}
CD.COOLDOWNS = COOLDOWNS

local function makeCooldownIcon(def)
	local f = ns.newElementIcon(def.key)
	f.tex:SetTexture(def.icon)
	-- Effects (the glows, the pops' light, the end flashes) on a layer that ignores the icon's alpha,
	-- so an idle icon (applyIdle) doesn't fade them. It takes its group's opacity instead (layoutGroup).
	f.effects = CreateFrame("Frame", nil, f)
	f.effects:SetAllPoints()
	f.effects:SetIgnoreParentAlpha(true)
	f.glowF:SetParent(f.effects)
	if def.totemSlot or def.needsTotem then
		-- A totem's time left (its own, or for Fire Nova whichever fire totem is out): a timer of the
		-- "uptime" kind beside the spell's cooldown. Its parts sit in a holder so one alpha can hide
		-- them all (Earthbind and Stoneclaw show it only while the earth totem out is theirs).
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.needsTotem then
		-- Ready glow (updateReadyGlow): the gate's alpha is "a fire totem is down", the glow's is "off
		-- cooldown"; nested, the two multiply.
		f.readyGate = CreateFrame("Frame", nil, f.effects)
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.makeGlow(f.readyGate, f, def.key)
		-- "No totem" warning layer: a grey copy of the icon and a red ring, above the icon and below the
		-- cooldown swipe. Its alpha is set from a possibly-secret boolean (see refreshFireNova), so it
		-- always pulses and is simply invisible while a totem is out.
		f.warn = CreateFrame("Frame", nil, f)
		f.warn:SetAllPoints()
		f.warn.grey = f.warn:CreateTexture(nil, "ARTWORK")
		f.warn.grey:SetAllPoints(f.tex)
		ns.cropIcon(f.warn.grey)
		f.warn.grey:SetDesaturated(true)
		f.warn.ring = ns.makeRing(f.warn, f.tex)
		f.warn.pulse = ns.makePulse(f.warn.grey, "fade")
		f.warn:SetAlpha(0)
		-- Hiding a frame (a combat-only group out of combat) stops its animations.
		f.warn:SetScript("OnShow", function(w) if w.pulseOn and not w.pulse:IsPlaying() then w.pulse:Play() end end)
	end
	-- Layers, bottom up: icon, Fire Nova's warning layer and the expiring warning, the swipe, the timer
	-- bar, text. Restated after regrouping (layoutGroup), since reparenting moves frame levels.
	function f.stack()
		local base = f:GetFrameLevel()
		f.effects:SetFrameLevel(base)
		f.glowF:SetFrameLevel(base + 1)
		if f.warn then f.warn:SetFrameLevel(base + 1) end
		f.cd:SetFrameLevel(base + 2)
		if f.cdTimer.bar then f.cdTimer.bar:SetFrameLevel(base + 3) end
		f.textFrame:SetFrameLevel(base + 4)
		if f.upTimer then f.upTimer:restack() end
	end
	f.stack()
	return f
end

for _, def in ipairs(COOLDOWNS) do
	def.spell = Spells.name(def.spellKey)
	def.frame = makeCooldownIcon(def)
	ns.registerElement(def.key, { frame = def.frame, label = def.spell, cooldown = def, stack = def.frame.stack,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end })
end

------------------------------------------------------------------------
-- The global cooldown and a spell's own cooldown
------------------------------------------------------------------------
-- The global cooldown: while it runs, every spell reads as on cooldown, so the swipe, the ready pop
-- and the ready glows would react to each cast. isOnGCD says so, when it's readable (if it's secret
-- in combat, this falls back to treating it as a real cooldown). Blizzard only vouches for it inside
-- SPELL_UPDATE_COOLDOWN (inEvent below); the timers keep the GCD sweep, so they still read it
-- (tested 2026-09-25).
function CD.onGCD(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) then return false end
	return info.isOnGCD == true
end
-- The spell's own cooldown without the GCD (ignoreGCD, on Forever since 12.0.5): true when none is
-- running, false when one is, nil when that can't be told (secret, or an older client).
local function ownCooldownOver(spellID)
	local ok, d = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if not ok then return nil end
	if not d then return true end
	local zok, z = pcall(d.IsZero, d)
	if zok and not isSecret(z) and type(z) == "boolean" then return z end
end
-- Before a cooldown timer takes a new duration: a global-cooldown sweep gets no bling, and the
-- ready pop that fires when it ends is skipped (f.gcdUntil), unless the spell's own cooldown is
-- running under the GCD: then its end is a real "ready".
local function noteGCD(f, spellID)
	local g = CD.onGCD(spellID)
	if g and ownCooldownOver(spellID) ~= false then f.gcdUntil = GetTime() + 1.6 end
	f.cd:SetDrawBling(not g)
end
-- A cooldown timer's duration, by the element's Global cooldown style: on, with the GCD (every cast
-- sweeps it, as on action bars); off, its own cooldown only (ignoreGCD), which its own cast starts,
-- so other spells don't sweep it. nil when none can be read.
local function cooldownFor(f, key, spellID)
	if ns.Style.value(key, "gcd", "show") then
		local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID)
		if not (ok and dur) then return nil end
		noteGCD(f, spellID)
		return dur
	end
	f.gcdUntil = nil
	f.cd:SetDrawBling(true)
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	-- None running: clear what an earlier read (a GCD sweep from before the style changed) left.
	if ok and not dur then f.cdTimer:clear() end
	return ok and dur or nil
end

-- Pop when ready: Blizzard's cooldown widget says when its swipe finishes (OnCooldownDone), a
-- moment with no secret in it, so the icon can pop right then, in combat too.
local function popWhenReady(f, key)
	f.cd:HookScript("OnCooldownDone", function()
		if f.gcdUntil and GetTime() <= f.gcdUntil then return end   -- a global cooldown ended
		if ns.isEnabled(key) and setting(key, "readyPop") then f:Pop() end
	end)
end

------------------------------------------------------------------------
-- Shock
------------------------------------------------------------------------
local shockSpellID, manaSpellID
local shockIDs = {}
local shockState = { outOfRange = false, noMana = false }
local rangeCheckID   -- the spell whose range check is on

-- Shock looks, fixed rule: out of range paints the body red; not enough mana paints the body blue
-- and adds a blue ring; when both apply the body is red (range) and the ring blue (mana).
local shockPainted   -- what updateShockTint last drew; repainted only on a change
local function updateShockTint()
	local now = (shockState.outOfRange and "r" or "") .. (shockState.noMana and "m" or "")
	if now == shockPainted then return end
	shockPainted = now
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

local function refreshShockCooldown()
	if not shockSpellID or not ns.isEnabled("shock") then return end
	local dur = cooldownFor(shock, "shock", shockSpellID)
	if dur then shock.cdTimer:set(dur) end
end

local function refreshShockRange()
	if not shockSpellID or not ns.isEnabled("shock") then return end
	-- The event also fires for other spells' checks; the 4 Hz ticker covers ours either way.
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	updateShockTint()
end

local function refreshShockMana()
	if not ns.isEnabled("shock") then return end
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ok and not isSecret(noPower) and noPower == true
	updateShockTint()
end

popWhenReady(shock, "shock")

------------------------------------------------------------------------
-- Cooldown elements: idle
------------------------------------------------------------------------
-- Idle (Earthbind, Stoneclaw, Fire Nova): off cooldown, with nothing of its own going on. Both halves
-- are plain values in combat (probed 2026-09-26): the spell's own cooldown from GetSpellCooldown's
-- isActive and isOnGCD (a global cooldown shows as active and on the GCD; the duration object is
-- secret), and a totem from its slot having a duration at all (nil the moment it's gone) plus our
-- own casts. An idle icon takes its "Opacity when idle" and keeps its place in the group; it is
-- always full while positioning is unlocked. The end of a cooldown fires no event: OnCooldownDone
-- (below) and the 1 s ticker catch it. isOnGCD is only vouched for inside SPELL_UPDATE_COOLDOWN
-- (inEvent), so its answer is kept (def.cdRunning) and only re-read there; isActive false needs no
-- such care. Going idle waits IDLE_DELAY at full opacity first, so a ready or run-out pop plays at full.
local IDLE_DELAY = 1.5
local refreshCooldown           -- below
local function ownCooldownRunning(def, inEvent)
	local ok, info = safe(C_Spell.GetSpellCooldown, def.spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then return true end   -- can't tell: not idle
	if info.isActive == false then def.cdRunning = false return false end
	if inEvent or def.cdRunning == nil then
		if isSecret(info.isOnGCD) then return true end
		def.cdRunning = info.isOnGCD ~= true
	end
	return def.cdRunning
end
local function idleAlpha(key)
	local v = setting(key, "idleAlpha")
	if type(v) ~= "number" or v ~= v then return 1 end
	return math.min(math.max(v, 0), 1)
end
-- The icon eases to its new opacity: slowly into idle, quickly back (each rate covers 0 to 1).
local FADE_OUT, FADE_IN = 0.8, 0.15
local fading = {}   -- def -> target alpha
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
	for def, target in pairs(fading) do
		local a = def.frame:GetAlpha()
		if target < a then a = math.max(target, a - elapsed / FADE_OUT)
		else a = math.min(target, a + elapsed / FADE_IN) end
		def.frame:SetAlpha(a)
		if a == target then fading[def] = nil end
	end
	if next(fading) == nil then self:Hide() end
end)
local function fadeTo(def, alpha)
	if math.abs(def.frame:GetAlpha() - alpha) < 0.005 then
		fading[def] = nil
		def.frame:SetAlpha(alpha)
		return
	end
	fading[def] = alpha
	fader:Show()
end

-- totemBusy: our totem is down (Earthbind, Stoneclaw), or any fire totem is (Fire Nova).
local function applyIdle(def, totemBusy, inEvent)
	local when = def.needsTotem and setting(def.key, "idleWhen")   -- Fire Nova: never | nototem | offcd
	local cdRunning = ownCooldownRunning(def, inEvent)   -- always, so its kept answer stays current
	local busy = not ns.getAccount().locked or when == "never" or cdRunning
	if not busy and totemBusy then busy = when ~= "offcd" end
	if busy then def.idleAt = nil
	elseif def.idle == false then
		-- Just went idle: full for a moment, then refresh to fade.
		def.idleAt = GetTime() + IDLE_DELAY
		C_Timer.After(IDLE_DELAY + 0.05, function() refreshCooldown(def) end)
	end
	local waiting = def.idleAt and GetTime() < def.idleAt
	fadeTo(def, (busy or waiting) and 1 or idleAlpha(def.key))
	def.idle = not busy
end

------------------------------------------------------------------------
-- Cooldown elements: refresh
------------------------------------------------------------------------
-- Remaining seconds -> alpha: fully shown at 0s, hidden from 0.05s up.
local noTimeLeftCurve = ns.CURVE_OVER

-- Fire Nova: the slot's duration object drives everything, secret or not. An empty slot has none and
-- an expired one evaluates to 0 s, so the timer widgets draw nothing and the warning layer shows.
-- def.read (for /sf debug) is kept as parts and only formatted there.
local function refreshFireNova(def, inEvent)
	local f = def.frame
	local tok, tdur = safe(GetTotemDuration, def.needsTotem)
	applyIdle(def, tok and tdur ~= nil, inEvent)
	f.activeHolder:SetAlpha(1)   -- any fire totem counts, so its timer always shows
	if tok and tdur == nil then
		-- Nothing in the slot: no duration object to evaluate.
		f.warn:SetAlpha(1)
		def.read = "no fire totem (no duration)"
	else
		local aok, alpha = false, nil
		if tok and tdur and noTimeLeftCurve then
			aok, alpha = ns.try("fire nova warning", tdur.EvaluateRemainingDuration, tdur, noTimeLeftCurve)
		end
		if aok and alpha ~= nil then
			f.warn:SetAlpha(alpha)
			def.read = alpha   -- possibly secret; described by /sf debug
		else
			f.warn:SetAlpha(0)
			def.read = tok and "fire slot duration unreadable" or "fire slot duration error"
		end
	end
	f.upTimer:set(tok and tdur or nil)
end

-- Whether the totem in def's slot is def's own (1) or not (0), and how that was told. Not known from
-- our casts (a /reload with the totem already down): out of combat the slot's spell, else its icon
-- (every rank shares it), kept as the owner so it holds into combat. In combat: unknown, hidden.
local function slotMatch(def, slot)
	local owner = Totems.ownerOf(slot)
	if owner then return owner == def.spellKey and 1 or 0, "cast" end
	local have, spellID, icon = Totems.read(slot)
	local mine, how
	if have and spellID then mine, how = Spells.keyOf(spellID) == def.spellKey, "slot spell"
	elseif have and icon then mine, how = icon == def.iconID or icon == def.icon, "slot icon" end
	if mine == nil then return 0, "unknown" end
	if mine then Totems.setOwner(slot, def.spellKey, spellID) end
	return mine and 1 or 0, how
end

-- Earthbind / Stoneclaw: the slot's timer, shown only while this totem is the one in the slot.
local function refreshEarthTotem(def, inEvent)
	local f = def.frame
	local tok, tdur = safe(GetTotemDuration, def.totemSlot)
	if tok and tdur then
		local match, how = slotMatch(def, def.totemSlot)
		f.activeHolder:SetAlpha(match)
		f.upTimer:set(tdur)
		def.read, def.readHow = match, how
		applyIdle(def, match == 1, inEvent)
	else
		f.activeHolder:SetAlpha(0)
		f.upTimer:clear()
		def.read, def.readHow = "no earth totem", nil
		applyIdle(def, false, inEvent)
	end
end

function refreshCooldown(def, inEvent)
	if not ns.isEnabled(def.key) then def.cdRunning = nil return end   -- read afresh when it's back
	local f = def.frame
	if f.killed and not (setting(def.key, "killed") and setting(def.key, "killedMark")) then f.killed.mark:Hide() end
	if not def.spellID then
		-- Not learned yet: a plain grey icon.
		fadeTo(def, 1)
		def.idle = nil
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.cdTimer:clear()
		if f.upTimer then f.upTimer:clear() end
		if f.warn then f.warn:SetAlpha(0) end
		return
	end
	local dur = cooldownFor(f, def.key, def.spellID)
	if dur then f.cdTimer:set(dur) end
	f.tex:SetDesaturated(false)
	if def.needsTotem then refreshFireNova(def, inEvent)
	elseif def.totemSlot then refreshEarthTotem(def, inEvent) end
end

local function refreshCooldowns(inEvent)
	for _, def in ipairs(COOLDOWNS) do refreshCooldown(def, inEvent) end
end

for _, def in ipairs(COOLDOWNS) do
	popWhenReady(def.frame, def.key)
	-- A cooldown ending can make it idle (see applyIdle); read on the next frame.
	def.frame.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, function() refreshCooldown(def) end) end)
end

-- Looks that change only with the spellbook and settings: the icon, and Fire Nova's warning layer.
local function styleCooldown(def)
	local f = def.frame
	f.tex:SetTexture(def.iconID or def.icon)
	local w = f.warn
	if not w then return end
	w.grey:SetTexture(def.iconID or def.icon)
	w.grey:SetShown(setting(def.key, "blockedGrey"))
	w.ring:show(setting(def.key, "blockedRing"))
	w.pulseOn = setting(def.key, "blockedPulse")   -- OnShow restarts it after the group was hidden
	if w.pulseOn then
		if not w.pulse:IsPlaying() then w.pulse:Play() end
	else w.pulse:Stop() end
end

-- Our totems (ShamanForever_Totems.lua): a recast takes away the element's killed-early cross; the
-- end of an Earthbind / Stoneclaw totem plays its ends, each gated on the time the totem had left
-- (ns.makeEndFlash): killed early, or ran out.
Totems.subscribe(function(event, slot, arg)
	for _, def in ipairs(COOLDOWNS) do
		if def.totemSlot == slot then
			local f, key = def.frame, def.key
			if event == "cast" and arg == def.spellKey and f.killed then
				f.killed.mark:Hide()
			elseif event == "gone" and Totems.ownerOf(slot) == def.spellKey and ns.isEnabled(key) then
				local dur = arg
				if setting(key, "expiredPop") then
					if not f.expired then f.expired = ns.makeEndFlash(f.effects, f, key) end
					f.expired:setIcon(def.iconID or def.icon)
					f.expired:play(dur, { expired = true, pop = true })
				end
				if setting(key, "killed") then
					if not f.killed then f.killed = ns.makeEndFlash(f.effects, f, key) end
					f.killed:setIcon(def.iconID or def.icon)
					f.killed:play(dur, { pop = setting(key, "killedPop"), glow = setting(key, "killedGlow"),
						mark = setting(key, "killedMark") })
				end
			end
		end
	end
end)

------------------------------------------------------------------------
-- Ready glows ("use me"), both off by default. Fire Nova: while it is off cooldown and a fire totem
-- is down, the moment it can be cast; both are secret in combat, so each goes through a curve into
-- one of two nested frames' alphas. Shocks: while the shock is off cooldown. Re-read ten times a
-- second while any is on, so they follow a cooldown ending or a totem running out without waiting for
-- an event.
------------------------------------------------------------------------
local hasTimeLeftCurve = ns.CURVE_LIVE
-- 1 while the spell is off cooldown (possibly secret: only ever handed to SetAlpha). Its own
-- cooldown, without the GCD (ignoreGCD), so the glow doesn't blink with every cast.
local function readyAlpha(spellID)
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if not (ok and dur) then return 1 end   -- no cooldown running
	local rok, r = ns.try("ready glow", dur.EvaluateRemainingDuration, dur, ns.CURVE_OVER)
	if rok then return r end
	return 0
end
local function updateShockGlow()
	local on = shockSpellID and ns.isEnabled("shock") and setting("shock", "readyGlow") and noTimeLeftCurve
	shock.glowF:SetShown(on and true or false)
	if not on then return end
	shock.glowF:fit(shock:GetWidth())
	shock.glowF:SetAlpha(readyAlpha(shockSpellID))
end
local function updateReadyGlow(def)
	local f = def.frame
	local on = def.spellID and ns.isEnabled(def.key) and setting(def.key, "readyGlow") and hasTimeLeftCurve and noTimeLeftCurve
	f.readyGlow:SetShown(on and true or false)
	if not on then return end
	f.readyGlow:fit(f:GetWidth())
	local tok, tdur = safe(GetTotemDuration, def.needsTotem)
	if not (tok and tdur) then f.readyGate:SetAlpha(0) return end   -- no fire totem
	local gok, g = ns.try("ready gate", tdur.EvaluateRemainingDuration, tdur, hasTimeLeftCurve)
	if gok then f.readyGate:SetAlpha(g) else f.readyGate:SetAlpha(0) end
	f.readyGlow:SetAlpha(readyAlpha(def.spellID))
end
local function updateReadyGlows()
	for _, def in ipairs(COOLDOWNS) do
		if def.needsTotem then updateReadyGlow(def) end
	end
	updateShockGlow()
end
local readyTicker = CreateFrame("Frame")
readyTicker:Hide()
readyTicker.t = 0
readyTicker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	updateReadyGlows()
end)
-- Runs only while a ready glow is turned on (checked on every layout, i.e. every settings change).
local function syncReadyTicker()
	local want = false
	if ns.isActive() then
		want = ns.isEnabled("shock") and setting("shock", "readyGlow")
		for _, def in ipairs(COOLDOWNS) do
			if def.needsTotem and ns.isEnabled(def.key) and setting(def.key, "readyGlow") then want = true end
		end
	end
	readyTicker:SetShown(want and true or false)
	if not want then updateReadyGlows() end   -- one last pass turns the glows off
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After a spellbook scan: the shocks' and the elements' names, highest ranks and icons, and the
-- shock's range check. Returns a signature of what it found.
function CD.resolve()
	local d = db()
	local sig = {}
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
	table.insert(sig, tostring(shockSpellID)); table.insert(sig, tostring(manaSpellID))
	for _, def in ipairs(COOLDOWNS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		def.spellID, def.iconID = Spells.known(def.spellKey)
		table.insert(sig, tostring(def.spellID)); table.insert(sig, tostring(def.iconID))
	end
	return table.concat(sig, ",")
end

-- Every timer takes its current style.
function CD.applyTimers()
	shock.cdTimer:apply()
	for _, def in ipairs(COOLDOWNS) do
		local f = def.frame
		f.cdTimer:apply()
		if f.upTimer then
			f.upTimer:apply()
			f.upTimer:setExpire(ns.Timer.expireOpts(def.key), def.iconID or def.icon)
		end
	end
end

-- After a layout (settings may have changed): the looks, then everything read again.
function CD.applyLayout()
	for _, def in ipairs(COOLDOWNS) do styleCooldown(def) end
	shockPainted = nil   -- the looks may have changed
	updateShockTint()
	refreshShockMana()
	refreshCooldowns()
	syncReadyTicker()
end

function CD.refresh()
	refreshShockCooldown()
	refreshShockRange()
	refreshShockMana()
	refreshCooldowns()
end

-- A cooldown or totem changed; inEvent: from SPELL_UPDATE_COOLDOWN (see the global cooldown above).
function CD.onCooldowns(inEvent)
	refreshShockCooldown()
	refreshCooldowns(inEvent)
end

-- Once a second: a cooldown's end fires no event.
function CD.tick()
	ns.try("cooldown refresh", refreshCooldowns)
	ns.try("shock refresh", refreshShockCooldown)
end

-- A shaman logged in: the shock's own events, and its range four times a second.
function CD.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "SPELL_UPDATE_USABLE")
	ns.registerEvent(ev, "UNIT_POWER_UPDATE", "player")
	ns.registerEvent(ev, "PLAYER_TARGET_CHANGED")
	ns.registerEvent(ev, "SPELL_RANGE_CHECK_UPDATE")
	ev:SetScript("OnEvent", function(_, event)
		if event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then refreshShockMana()
		else refreshShockRange() end
	end)
	C_Timer.NewTicker(0.25, function() ns.try("range refresh", refreshShockRange) end)
end

-- /sf debug
function CD.debug()
	say("shock spell %s (%s), mana spell %s", tostring(shockSpellID), db().shock, tostring(manaSpellID))
	for key, id in pairs(shockIDs) do
		local _, usable, noPower = safe(C_Spell.IsSpellUsable, id)
		local _, inRange = safe(C_Spell.IsSpellInRange, id, "target")
		local e = Spells.bookEntry(SHOCK_SPELL[key])
		say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
			e and e.rank or "?", describeArg(usable), describeArg(noPower), describeArg(inRange))
	end
	for _, def in ipairs(COOLDOWNS) do
		local secret = "?"
		if def.spellID and C_Secrets and C_Secrets.ShouldTotemSpellBeSecret then
			local ok, v = pcall(C_Secrets.ShouldTotemSpellBeSecret, def.spellID)
			secret = ok and describeArg(v) or "error"
		end
		local read = def.read == nil and "not checked" or describeArg(def.read)
		if def.readHow then read = string.format("earth slot timer, by %s, match %s", def.readHow, read)
		elseif def.needsTotem and type(def.read) ~= "string" and def.read ~= nil then read = "warning alpha " .. read end
		say("%s: spell %s, totem spell secret=%s, %s, idle %s", def.spell, tostring(def.spellID), secret, read, tostring(def.idle))
	end
end

ns.registerModule(CD)
