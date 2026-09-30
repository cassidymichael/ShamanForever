-- The cooldown elements (the totems, Fire Nova, and spells like Nature's Swiftness or
-- Reincarnation): a spell's cooldown, the pop and the "use me" glow when it's ready, for a totem its
-- time left and its end, primed states and buff windows, reagents (ShamanForever_Reagents.lua), and
-- an idle look. The global cooldown and ready reads here are shared with the shock
-- (ShamanForever_Shock.lua) and the shield.
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
-- * A totem element must tell its totem from any other in its slot: the totem in the slot is
--   the last one we cast into it (ShamanForever_Totems.lua), and the timer's holder is shown only
--   when that is this element's totem. The slot's duration object still drives the timer, and an
--   empty slot has none. When the owner is unknown (a /reload with a totem already out), out of
--   combat the slot says which totem it is (its spell ID, else its icon), and that is kept as the
--   owner. In combat, and all through a PvP match, the slot is secret, so the timer stays hidden
--   until that ends or the totem is recast: a /reload then isn't worth guessing for.
-- * Buff windows and primed states come from our own casts, which are readable in combat: Rage of the
--   Farseer's window runs a fixed time from its cast; Nature's Swiftness and Stormstrike are primed
--   from their cast until our casts of the spells that spend them (or its time runs out). That is an
--   inference; Nature's Swiftness is corrected from its buff whenever auras are
--   readable (out of combat, and not in a PvP match). Death ends it, and Rage of the Farseer's window.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, Totems, Reagents = ns.Spells, ns.Totems, ns.Reagents

local CD = { name = "cooldowns" }
ns.Cooldowns = CD

local setting = ns.elementSetting

------------------------------------------------------------------------
-- Elements
------------------------------------------------------------------------
-- Cooldown elements: a spell's cooldown, plus for a totem the active time of ours in its slot, or for
-- Fire Nova whether the fire totem it needs is out. Totem slots: 1 fire, 2 earth, 3 water, 4 air.
-- Adding one is a line here, in the order the options list them: its options page and preview
-- follow from the parts it has (ShamanForever_OptionsElements.lua, _OptionsLook.lua). spellKey is
-- its spell in ns.Spells, icon the fallback until the client has it, school its colour and art,
-- blurb the line under its name in the options, duration the totem's lifetime in seconds (for the
-- options previews). spell is the display name (the client's).
-- Optional parts:
--   grounded = true     its early end is a success (Grounding): a Grounded flash, not Killed early
--   window = seconds    a buff window timed from our cast (Rage of the Farseer), shown as time left
--   primed = { spends = { spell keys }, charges = n (1), duration = seconds or nil (until spent),
--              buffKey = spell key of a buff on us, read when auras are readable, text = what
--              starts and spends it, for its options page }: an effect that waits to be spent
--              (Nature's Swiftness, Stormstrike); see the file's header
--   reagent = item ID   the spell's reagent (Reincarnation's Ankh): a count, low and out looks
--   readyGlow = true    offers the "use me" glow while off cooldown (off by default)
--   noReady = true      no ready pop (Reincarnation: nothing to do the moment it's back)
--   ranOut = true       its totem running out is shown as a flash in its colour with an hourglass
--                       (Mana Tide, Grounding), not the pop
--   expireLooks = { ... } the Expiring looks it offers, when not all of them (Rage of the Farseer:
--                       nothing to recast as it ends, so no glow or ring); false for no Expiring
--   primedLooks = false no Primed pop or glow, only its time left (Stormstrike)
--   cd = seconds        its cooldown's length, for the options preview only
--   defaults = { ... }  its own option defaults (ns.elementSetting), over its parts' (PARTS)
--   experimental        a feature name: not tested in game (the level cap is 20)
local COOLDOWNS = {
	{ key = "earthbind", spellKey = "earthbind", icon = 136102, totemSlot = 2, duration = 45, school = "earth",
		blurb = "Cooldown, and time left while it's down.", defaults = {} },
	{ key = "stoneclaw", spellKey = "stoneclaw", icon = 136097, totemSlot = 2, duration = 15, school = "earth",
		blurb = "Cooldown, and time left while it's down.", defaults = {} },
	{ key = "firenova",  spellKey = "fireNova",  icon = 135824, needsTotem = 1, school = "fire",
		blurb = "Cooldown. Needs a fire totem.", defaults = { idleWhen = "never" } },
	-- Emergency cooldowns: plainly visible while ready.
	{ key = "naturesswiftness", spellKey = "naturesSwiftness", icon = 136076, school = "water",
		blurb = "Cooldown, and a glow while your next Nature spell is instant.",
		primed = { spends = { "healingWave", "lesserHealingWave", "chainHeal", "lightningBolt", "chainLightning",
			"ghostWolf", "farSight" },
			buffKey = "naturesSwiftness",
			text = "From your cast until your next Nature spell with a cast time." },
		cd = 180, defaults = { idleWhen = "never" }, experimental = "Nature's Swiftness" },
	{ key = "manatide", spellKey = "manaTide", icon = 135861, totemSlot = 3, duration = 12, school = "water",
		blurb = "Cooldown, and time left while it's down.",
		ranOut = true, cd = 300,
		defaults = { idleWhen = "never", expire = { secs = 3, glow = true, pulse = false } }, experimental = "Mana Tide Totem" },
	{ key = "grounding", spellKey = "grounding", icon = 136039, totemSlot = 4, duration = 45, school = "air",
		blurb = "Cooldown, time left, and a flash when it takes a spell.",
		grounded = true, ranOut = true, cd = 15, defaults = {}, experimental = "Grounding Totem" },
	-- Rotation: full while ready, like the shocks.
	-- On Forever, Stormstrike leaves a 12 s debuff with one charge on the target: the shaman's next
	-- Lightning Bolt, Chain Lightning or Earth Shock on it hits 20% harder. Auras can't be read in
	-- combat, so it's timed from the cast and spent by our own casts only. Its text names only those
	-- spells; whether other Nature damage (Lightning Shield, other shamans) can spend it is untested.
	{ key = "stormstrike", spellKey = "stormstrike", icon = 135963, school = "air",
		blurb = "Cooldown, and a bar while your target takes more Nature damage.",
		primed = { spends = { "lightningBolt", "chainLightning", "earthShock" }, duration = 12,
			text = "From your cast for 12 s, or until your next Lightning Bolt, Chain Lightning or Earth Shock. " ..
				"Other Nature damage on the target can also use it up, which can't be seen." },
		primedLooks = false, expireLooks = false, readyGlow = true, cd = 8,
		defaults = { idleWhen = "never", primedPop = false, primedGlow = false, expire = { secs = 0 } }, experimental = "Stormstrike" },
	{ key = "riptide", spellKey = "riptide", icon = 252995, school = "water", blurb = "Cooldown.",
		readyGlow = true, cd = 6, defaults = { idleWhen = "never" }, experimental = "Riptide" },
	-- Short cooldowns, back many times a fight: no Ready pop unless the player asks for it.
	{ key = "lavaburst", spellKey = "lavaBurst", icon = 237582, school = "fire", blurb = "Cooldown.",
		readyGlow = true, cd = 10, defaults = { idleWhen = "never", readyPop = false }, experimental = "Lava Burst" },
	{ key = "chainlightning", spellKey = "chainLightning", icon = 136015, school = "air", blurb = "Cooldown.",
		readyGlow = true, cd = 6, defaults = { idleWhen = "never", readyPop = false }, experimental = "Chain Lightning" },
	{ key = "farseer", spellKey = "rageOfTheFarseer", icon = 136048, window = 25, school = "air",
		blurb = "Cooldown, and time left while it's on.",
		readyGlow = true, expireLooks = { "grey", "pulse" }, cd = 180,
		-- Expiring off: nothing to recast as it ends. Turned on, it fades in and out.
		defaults = { idleWhen = "never", expire = { secs = 0, pulse = true } }, experimental = "Rage of the Farseer" },
	{ key = "projection", spellKey = "totemicProjection", icon = 136099, school = "spirit", blurb = "Cooldown.",
		cd = 60, experimental = "Totemic Projection" },
	-- Out of sight while ready: seen on cooldown, or when Ankhs run low.
	{ key = "reincarnation", spellKey = "reincarnation", icon = 136080, school = "spirit",
		blurb = "Cooldown, and your Ankhs when they run low.",
		reagent = 17030, noReady = true, cd = 3600,
		defaults = { idleAlpha = 0, readyPop = false }, experimental = "Reincarnation" },
}

-- Option defaults (ns.elementSetting) by part: every cooldown element has Ready and Idle, the rest
-- come with what it has. A def's own defaults win over them.
local PARTS = {
	ready = { readyPop = true, readyGlow = false },
	-- idleWhen: never | offcd | oncd (Fire Nova also nototem); see applyIdle.
	idle = { idleAlpha = 0.3, idleWhen = "offcd" },
	-- Fire Nova: the no-fire-totem look.
	-- readyNoTotem: its cooldown ending with no fire totem down plays a greyed pop (grey) or nothing (none).
	needsTotem = { blockedGrey = true, blockedRing = false, blockedPulse = false, readyNoTotem = "grey" },
	-- A totem's end: ran out (the pop) or killed early (Killed early's flash and cross).
	totemSlot = { expiredPop = true, killed = true, killedPop = true, killedGlow = true, killedMark = true },
	ranOut = { ranOutFlash = true, ranOutPop = false, ranOutGlow = false },   -- ran out, as a flash
	grounded = { grounded = true, groundedPop = true, groundedGlow = true },  -- Grounding's early end
	primed = { primedPop = true, primedGlow = true },
	reagent = Reagents.DEFAULTS,
}
CD.READY_DEFAULTS = PARTS.ready   -- the shock's too
-- The Idle block's choices (see idleBlock in ShamanForever_OptionsElements.lua).
local IDLE_NEVER = { "never", "Never", "It always shows in full" }
local IDLE_OFFCD = { "offcd", "Off cooldown", "Idle is when it's off cooldown%s" }
local IDLE_ONCD = { "oncd", "On cooldown", "Idle is when it's on cooldown%s",
	"Shown in full only while it's ready." }
local FIRE_NOVA_CHOICES = {
	IDLE_NEVER,
	{ "nototem", "Off cooldown, no fire totem", "Idle is when it's off cooldown and no fire totem is down",
		"It can't be cast." },
	{ "offcd", "Off cooldown", "Idle is when it's off cooldown", "Whether a fire totem is down or not." },
	{ "oncd", "On cooldown", "Idle is when it's on cooldown and no fire totem is down",
		IDLE_ONCD[4] },
}
CD.IDLE_CHOICES = { IDLE_NEVER, IDLE_OFFCD, IDLE_ONCD }
local function withParts(def)
	def.idleChoices = def.needsTotem and FIRE_NOVA_CHOICES or CD.IDLE_CHOICES
	def.idleAlso = def.totemSlot and " and its totem isn't down" or def.primed and " and not primed"
		or def.window and " and not active" or nil
	if def.reagent then def.idleExtra = Reagents.IDLE_EXTRA end
	def.defaults = def.defaults or {}
	local fill = ns.fillDefaults
	fill(def.defaults, PARTS.ready)
	fill(def.defaults, PARTS.idle)
	for _, part in ipairs({ "needsTotem", "totemSlot", "ranOut", "grounded", "primed", "reagent" }) do
		if def[part] then fill(def.defaults, PARTS[part]) end
	end
end

local function makeCooldownIcon(def)
	-- Effects (the glows, the pops' light, the end flashes) on a layer that ignores the icon's alpha,
	-- so an idle icon (applyIdle) doesn't fade them.
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if def.totemSlot or def.needsTotem or def.window or (def.primed and def.primed.duration) then
		-- A totem's time left (its own, or for Fire Nova whichever fire totem is out), a buff window's
		-- or a primed buff's: a timer of the "uptime" kind beside the spell's cooldown. Its parts sit
		-- in a holder so one alpha can hide them all (Earthbind and Stoneclaw show it only while the
		-- earth totem out is theirs).
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.needsTotem or def.readyGlow then
		-- Ready glow (refreshReadyGlow): the glow's alpha is "off cooldown"; for Fire Nova the gate's is
		-- "a fire totem is down", and nested, the two multiply. Others leave the gate at 1.
		f.readyGate = CreateFrame("Frame", nil, f.effects)
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.makeGlow(f.readyGate, f, def.key)
	end
	if def.needsTotem then
		-- "No totem" warning layer: a grey copy of the icon and a red ring, above the icon and below the
		-- cooldown swipe. Its alpha is set from a possibly-secret boolean (see refreshFireNova), so it
		-- always pulses and is simply invisible while a totem is out.
		f.warn = CreateFrame("Frame", nil, f)
		f.warn:SetAllPoints()
		f.warn.grey = f.warn:CreateTexture(nil, "ARTWORK")
		f.warn.grey:SetAllPoints(f.tex)
		ns.cropIconExact(f.warn.grey)
		f.warn.grey:SetDesaturated(true)
		f.warn.ring = ns.makeRing(f.warn, f.tex)
		f.warn.pulse = ns.makePulse(f.warn.grey, "fade")
		f.warn:SetAlpha(0)
		-- Hiding a frame (a combat-only group out of combat) stops its animations.
		f.warn:SetScript("OnShow", function(w) if w.pulseOn and not w.pulse:IsPlaying() then w.pulse:Play() end end)
	end
	-- Layers, bottom up: icon, Fire Nova's warning layer and the expiring warning, the swipe, the timer
	-- bar, text (ns.newElementIcon).
	f.stack()
	return f
end

for _, def in ipairs(COOLDOWNS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.spellKey) or def.icon
	withParts(def)
	def.frame = makeCooldownIcon(def)
	ns.registerElement(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end,
		kind = "cooldown", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental })
end

------------------------------------------------------------------------
-- The global cooldown and a spell's own cooldown
------------------------------------------------------------------------
-- The global cooldown: while it runs, every spell reads as on cooldown, so the swipe and the ready
-- pop would react to each cast. isOnGCD says so (false when it's secret). Blizzard only vouches
-- for it inside SPELL_UPDATE_COOLDOWN; the shield's GCD sweep and a sweep's bling read it at other
-- times too (tested 2026-09-25).
function CD.onGCD(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) then return false end
	return info.isOnGCD == true
end
-- Ready: the end of the spell's own cooldown (the ready tracker's OnCooldownDone, watchEnds) is a
-- "ready" only when our cast was seen starting it. GetSpellCooldown's isActive and isOnGCD
-- are plain in combat (probed 2026-09-26); the duration objects aren't, so nothing here asks them.
-- A spell's state: "ready" (isActive false), "gcd" (the global cooldown, alone or outlasting its
-- own), "own" (its own cooldown); nil when a field is secret. isOnGCD is only vouched for inside
-- SPELL_UPDATE_COOLDOWN, so "gcd" and "own" count only there (inEvent).
local function plainCooldown(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then return nil end
	if info.isActive == false then return "ready" end
	if isSecret(info.isOnGCD) then return nil end
	return info.isOnGCD == true and "gcd" or "own"
end
-- Arms the next end (f.ready.armed) when our own cast starts its own cooldown: an "own" read in
-- SPELL_UPDATE_COOLDOWN within ARM_AFTER_CAST of the cast (CD.noteCast), or at the cast itself when
-- that event came first. Only our cast: as a global cooldown ends, isActive can still read true
-- with isOnGCD false for a moment (tested 2026-09-29), and that must not arm the sweep's end. A
-- cooldown not started by our cast is missed, never a false ready. The end is the ready tracker's
-- (watchEnds), which runs the spell's own cooldown only, so one that ends inside a GCD ends at its
-- own time. Once isActive reads false while armed, the end must come within READY_GRACE: out of
-- combat it can read false just before the tracker ends. A secret read arms nothing.
local READY_GRACE, ARM_AFTER_CAST = 0.5, 1.5
local function noteReady(f, st, inEvent)
	local r = f.ready
	if st == "ready" then
		if r.armed and not r.by then r.by = GetTime() + READY_GRACE end
	elseif st == "own" and inEvent and r.castAt and GetTime() - r.castAt <= ARM_AFTER_CAST then
		r.armed, r.by, r.castAt = true, nil, nil
	end
end
-- The ready tracker (f.ownCd): a Cooldown that draws nothing, fed the spell's own cooldown
-- (ignoreGCD) whatever the visible timer shows, so a ready is its own end, not a global cooldown's
-- that outlasts it. A child of f, so it is shown while the icon is: a hidden Cooldown's end can
-- come late, when it is shown again, so an end within JUST_SHOWN of coming into view is never a
-- ready (a missed pop, never a stale one). Its OnCooldownDone decides once whether this end is a
-- ready; the pop hooks it after (and the sound, which gates on CD.readyNow too).
local JUST_SHOWN = 0.2
local function watchEnds(f)
	if f.ready then return end
	local r = {}
	f.ready = r
	local t = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	t:SetAllPoints()
	t:SetDrawSwipe(false)
	t:SetDrawEdge(false)
	t:SetDrawBling(false)
	t:SetHideCountdownNumbers(true)
	t.noCooldownCount = true   -- countdown text addons (OmniCC and the like) leave it alone
	f.ownCd = t
	t:HookScript("OnShow", function() r.shownAt = GetTime() end)
	t:HookScript("OnCooldownDone", function()
		local now = GetTime()
		local late = r.shownAt and now - r.shownAt < JUST_SHOWN
		r.at = (r.armed and not late and (not r.by or now <= r.by)) and now or nil
		r.armed, r.by = nil, nil
	end)
end
-- Our own successful cast of f's spell (spellID: the one its timer reads).
function CD.noteCast(f, spellID)
	watchEnds(f)
	local r = f.ready
	r.castAt = GetTime()
	if plainCooldown(spellID) == "own" then r.armed, r.by, r.castAt = true, nil, nil end
end
-- Forgets a pending ready (the element is off, or its spell not known): a cast it didn't see can't
-- leave one armed for later. The tracker stops too.
function CD.resetReady(f)
	local r = f.ready
	if not r then return end
	r.armed, r.by, r.castAt = nil, nil, nil
	f.ownCd:Clear()
end
-- True inside the tracker's OnCooldownDone when that end is a ready (hooks on f.ownCd after it).
function CD.readyNow(f) return f.ready ~= nil and f.ready.at == GetTime() end
-- A cooldown timer's duration, by the element's Global cooldown style: on, with the GCD (every cast
-- sweeps it, as on action bars; a GCD sweep gets no bling); off, its own cooldown only
-- (ignoreGCD), which its own cast starts, so other spells don't sweep it. nil when none can be
-- read. inEvent: from SPELL_UPDATE_COOLDOWN.
-- Either way the ready tracker (watchEnds) takes the own cooldown, only while it reads "own": while
-- a global cooldown outlasts it the tracker keeps its last one, which ends on time. Off cooldown,
-- with no ready pending, it is cleared (a cooldown that came back early leaves no end behind). The
-- duration objects can be secret in combat: they are only handed to the widgets.
local function cooldownFor(f, key, spellID, inEvent)
	watchEnds(f)
	local st = plainCooldown(spellID)
	noteReady(f, st, inEvent)
	local ok, own = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if st == "own" and ok and own then
		ns.try("ready tracker", f.ownCd.SetCooldownFromDurationObject, f.ownCd, own, true)
	elseif st == "ready" and not f.ready.armed then f.ownCd:Clear() end
	if ns.Style.value(key, "gcd", "show") then
		local gok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID)
		if not (gok and dur) then return nil end
		f.cd:SetDrawBling(st ~= "gcd")
		return dur
	end
	f.cd:SetDrawBling(true)
	-- None running: clear what an earlier read (a GCD sweep from before the style changed) left.
	if ok and not own then f.cdTimer:clear() end
	return ok and own or nil
end
CD.cooldownFor = cooldownFor

-- Pop when ready: Blizzard's cooldown widget says when a cooldown finishes (OnCooldownDone), in
-- combat too (tested 2026-09-29), here the ready tracker's, and watchEnds says whether that end
-- is a ready. totemSlot: a spell that needs a totem down in that slot (Fire Nova), which isn't
-- ready without one: an empty slot has no duration object (see the file's header). Then the pop
-- is greyed, a nudge to drop one, or none (readyNoTotem).
local function popWhenReady(f, key, totemSlot)
	watchEnds(f)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not CD.readyNow(f) then return end   -- not armed by our cast, or stale
		if not (ns.isEnabled(key) and setting(key, "readyPop")) then return end
		if ns.cantAct() then return end   -- dead, a ghost or on a flight path: nothing to cast
		if totemSlot then
			local ok, d = safe(GetTotemDuration, totemSlot)
			if not ok then return end
			if not d then
				if setting(key, "readyNoTotem") == "grey" then f:Pop("blocked") end
				return
			end
		end
		f:Pop()
	end)
end
CD.popWhenReady = popWhenReady

------------------------------------------------------------------------
-- Cooldown elements: idle
------------------------------------------------------------------------
-- Idle (every cooldown element): off cooldown, with nothing of its own going on. Both halves
-- are plain values in combat (probed 2026-09-26): the spell's own cooldown from GetSpellCooldown's
-- isActive and isOnGCD (a global cooldown shows as active and on the GCD; the duration object is
-- secret), and a totem from its slot having a duration at all (nil the moment it's gone) plus our
-- own casts. An idle icon takes its "Opacity when idle" and keeps its place in the group; it is
-- always full while positioning is unlocked. The end of a cooldown fires no event: OnCooldownDone
-- (below) and the 1 s ticker catch it. isOnGCD is only vouched for inside SPELL_UPDATE_COOLDOWN
-- (inEvent), so its answer is kept (def.cdRunning) and only re-read there; isActive false needs no
-- such care. Going idle waits IDLE_DELAY at full opacity first, so a ready or run-out pop plays at full.
local IDLE_DELAY = 1.5
ns.IDLE_DELAY = IDLE_DELAY   -- the options preview and preview mode wait as long
local refreshCooldown           -- below (each cooldown def's refresh)
-- Whether the spell's own cooldown is running, and whether that is certain. An unreadable answer
-- reports running but uncertain: Off cooldown then treats it as busy, On cooldown as not idle.
local function ownCooldownRunning(def, inEvent)
	local ok, info = safe(C_Spell.GetSpellCooldown, def.spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then return true, false end
	if info.isActive == false then def.cdRunning = false return false, true end
	if inEvent or def.cdRunning == nil then
		if isSecret(info.isOnGCD) then return true, false end
		def.cdRunning = info.isOnGCD ~= true
	end
	return def.cdRunning, true
end
local function fadeTo(def, alpha) ns.fadeTo(def.frame, alpha) end

-- The "Idle when" choice (idleWhen): never | offcd (idle while off cooldown) | oncd (idle while
-- cooling down, so full only while ready); Fire Nova also nototem (off cooldown with no fire totem
-- down). totemBusy: our totem is down (Earthbind, Stoneclaw), or any fire totem is (Fire Nova).
-- def needs key, frame, spellID and a refresh function (the element's own, for the fade after the
-- pop's moment); the shock passes such a table too.
local function applyIdle(def, totemBusy, inEvent)
	local when = setting(def.key, "idleWhen")
	local running, certain = ownCooldownRunning(def, inEvent)   -- always, so its kept answer stays current
	local busy
	if when == "oncd" then busy = not (running and certain) else busy = running end
	busy = busy or when == "never" or not ns.getAccount().locked
	if not busy and totemBusy then busy = when ~= "offcd" end
	if busy then def.idleAt = nil
	elseif def.idle == false then
		-- Just went idle: full for a moment, then refresh to fade.
		def.idleAt = GetTime() + IDLE_DELAY
		C_Timer.After(IDLE_DELAY + 0.05, function() def.refresh(def) end)
	end
	local waiting = def.idleAt and GetTime() < def.idleAt
	fadeTo(def, (busy or waiting) and 1 or ns.idleAlpha(def.key))
	def.idle = not busy
end
CD.applyIdle = applyIdle

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
	-- No fire totem: its cooldown ending isn't "ready", so no bling either. Only ever turned off
	-- here: cooldownFor, which runs just before, sets it for the Global cooldown style each pass.
	if not (tok and tdur) then f.cd:SetDrawBling(false) end
end

-- Whether the totem in def's slot is def's own (1) or not (0), and how that was told. Not known from
-- our casts (a /reload with the totem already down): while the slot is readable its spell, else its
-- icon (every rank shares it), kept as the owner so it holds into combat. Else: unknown, hidden.
local function slotMatch(def, slot)
	local key, how, icon = Totems.identify(slot)
	if key then return key == def.spellKey and 1 or 0, how end
	if icon then
		local mine = icon == def.iconID or icon == def.icon
		if mine then Totems.setOwner(slot, def.spellKey) end
		return mine and 1 or 0, how
	end
	return 0, how
end

-- A totem element (Earthbind, Stoneclaw, Mana Tide, Grounding): the slot's timer, shown only while
-- this totem is the one in the slot. held: something else of its own keeps it from going idle.
local function refreshTotem(def, inEvent, held)
	local f = def.frame
	local tok, tdur = safe(GetTotemDuration, def.totemSlot)
	if tok and tdur then
		local match, how = slotMatch(def, def.totemSlot)
		f.activeHolder:SetAlpha(match)
		f.upTimer:set(tdur)
		def.read, def.readHow = match, how
		applyIdle(def, match == 1 or held, inEvent)
	else
		f.activeHolder:SetAlpha(0)
		f.upTimer:clear()
		def.read, def.readHow = "no totem in its slot", nil
		applyIdle(def, held, inEvent)
	end
end

------------------------------------------------------------------------
-- Buff windows and primed buffs (see the file's header)
------------------------------------------------------------------------
-- def.activeUntil: when the window or the primed buff ends (GetTime's clock; math.huge until it's
-- spent), nil while there is none. Only ever plain numbers from our own casts or readable auras.
local function showPrimed(def, on, pop)
	local f, key = def.frame, def.key
	f:SetGlowShown(on and setting(key, "primedGlow"))
	if on and pop and setting(key, "primedPop") then f:Pop("ready") end
end

local function endActive(def)
	if not def.activeUntil then return end
	def.activeUntil, def.activeToken = nil, nil
	local f = def.frame
	if f.upTimer then f.upTimer:clear(); f.activeHolder:SetAlpha(0) end
	if def.primed then showPrimed(def, false) end
end

-- start and length on GetTime's clock; length nil: until spent. quiet: already known (an aura read
-- confirming it), so no pop.
local function startActive(def, start, length, quiet)
	local f = def.frame
	def.activeUntil = length and start + length or math.huge
	local token = {}
	def.activeToken = token
	if f.upTimer then
		if length then f.upTimer:setTime(start, length); f.activeHolder:SetAlpha(1)
		else f.upTimer:clear(); f.activeHolder:SetAlpha(0) end
	end
	if def.primed then showPrimed(def, true, not quiet) end
	if length then
		C_Timer.After(math.max(start + length - GetTime(), 0) + 0.05, function()
			if def.activeToken == token then endActive(def); refreshCooldown(def) end
		end)
	end
end

local function isActive(def)
	if def.activeUntil and GetTime() >= def.activeUntil then endActive(def) end
	return def.activeUntil ~= nil
end

-- While auras are readable, the primed buff itself says whether it's up and for how long: by its
-- IDs, else by the client's name for it. Within a moment of our cast, a missing buff doesn't end it
-- (the aura can arrive after the cast event). fromAura: an aura change, which may pop; a read at
-- login or after combat finds what was already there, quietly.
local CAST_GRACE = 1.5
local function readPrimedBuff(def, fromAura)
	local buffKey = def.primed and def.primed.buffKey
	if not buffKey or InCombatLockdown() or ns.aurasSecret() or not C_UnitAuras then return end
	local found
	local function usable(ok, a)
		return ok and type(a) == "table" and not isSecret(a.expirationTime) and not isSecret(a.duration)
	end
	for id in pairs(Spells.ids(buffKey)) do
		local ok, a = safe(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if usable(ok, a) then found = a break end
	end
	if not found then
		local ok, a = safe(C_UnitAuras.GetAuraDataBySpellName, "player", Spells.name(buffKey), "HELPFUL")
		if usable(ok, a) then found = a end
	end
	if not found then
		if not (def.castAt and GetTime() - def.castAt < CAST_GRACE) then endActive(def) end
		return
	end
	-- Just spent: an aura event can still carry the buff for a moment; don't bring it back.
	if not def.activeUntil and def.spentAt and GetTime() - def.spentAt < CAST_GRACE then return end
	local exp, dur = found.expirationTime, found.duration
	local was = def.activeUntil ~= nil
	if type(exp) == "number" and type(dur) == "number" and exp > 0 and dur > 0 then
		if not was or math.abs(def.activeUntil - exp) > 0.2 then startActive(def, exp - dur, dur, was or not fromAura) end
	elseif not was then startActive(def, GetTime(), nil, not fromAura) end
end

function refreshCooldown(def, inEvent)
	if not ns.isEnabled(def.key) then
		-- Read afresh when it's back. Our casts aren't followed while it's off (CD.onCast), so a
		-- window or primed buff could be spent unseen: it ends here rather than come back stale.
		def.cdRunning = nil
		endActive(def)
		CD.resetReady(def.frame)
		return
	end
	local f = def.frame
	if f.killed and not (setting(def.key, "killed") and setting(def.key, "killedMark")) then f.killed.mark:Hide() end
	if not def.spellID then
		-- Not learned yet: a plain grey icon.
		CD.resetReady(f)
		fadeTo(def, 1)
		def.idle = nil
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.cdTimer:clear()
		f.count:Hide()
		endActive(def)
		if f.upTimer then f.upTimer:clear() end
		if f.warn then f.warn:SetAlpha(0) end
		return
	end
	local dur = cooldownFor(f, def.key, def.spellID, inEvent)
	if dur then f.cdTimer:set(dur) end
	f.tex:SetDesaturated(false)
	local held = isActive(def)
	if def.primed then showPrimed(def, held) end   -- a settings change shows at once
	if def.reagent then
		local hold, ring, pulse = Reagents.refresh(def)
		if hold then held = true end
		f:SetRingShown(ring)
		f:SetPulsing(pulse)
	end
	if def.needsTotem then refreshFireNova(def, inEvent)
	elseif def.totemSlot then refreshTotem(def, inEvent, held)
	else applyIdle(def, held, inEvent) end
end

local function refreshCooldowns(inEvent)
	for _, def in ipairs(COOLDOWNS) do refreshCooldown(def, inEvent) end
end

-- The ready sound (ShamanForever_Sounds.lua), at the ready pop's moment (popWhenReady, hooked
-- first): not when a global cooldown ends, nor for a spell that needs a totem while none is down.
-- Separate from the pop, which can be off while the sound is on. Only while the icon is on screen,
-- and not in the moment it comes into view: a hidden timer's end may reach it only then, late.
local function soundWhenReady(f, key, totemSlot)
	f:HookScript("OnShow", function() f.shownAt = GetTime() end)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not f:IsVisible() or GetTime() - (f.shownAt or 0) < JUST_SHOWN then return end
		if not CD.readyNow(f) then return end   -- not armed by our cast, or stale
		if totemSlot then
			local ok, d = safe(GetTotemDuration, totemSlot)
			if not (ok and d) then return end
		end
		ns.Sounds.element(key, "readySound")
	end)
end
CD.soundWhenReady = soundWhenReady

for _, def in ipairs(COOLDOWNS) do
	def.refresh = refreshCooldown
	if def.primed then
		def.spends = {}
		for _, k in ipairs(def.primed.spends) do def.spends[k] = true end
	end
	popWhenReady(def.frame, def.key, def.needsTotem)
	if not def.noReady then soundWhenReady(def.frame, def.key, def.needsTotem) end
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
-- end of a totem element's totem plays its ends, each gated on the time the totem had left
-- (ns.makeEndFlash): killed early (Grounded for Grounding), or ran out.
Totems.subscribe(function(event, slot, arg)
	for _, def in ipairs(COOLDOWNS) do
		if def.totemSlot == slot then
			local f, key = def.frame, def.key
			if event == "cast" and arg == def.spellKey and f.killed then
				f.killed.mark:Hide()
			elseif event == "gone" and Totems.ownerOf(slot) == def.spellKey and ns.isEnabled(key) then
				local dur = arg
				-- Ran out or killed: one sound, in combat too, while the icon is on screen.
				if f:IsVisible() then ns.Sounds.element(key, "goneSound", true) end
				if def.ranOut then
					-- Its colour with an hourglass, rather than the pop.
					if setting(key, "ranOutFlash") then
						if not f.expired then f.expired = ns.makeEndFlash(f.effects, f, key) end
						f.expired:setIcon(def.iconID or def.icon)
						f.expired:play(dur, { expired = true, ranOut = ns.SCHOOL_COLOR[def.school],
							pop = setting(key, "ranOutPop"), glow = setting(key, "ranOutGlow") })
					end
				elseif setting(key, "expiredPop") then
					if not f.expired then f.expired = ns.makeEndFlash(f.effects, f, key) end
					f.expired:setIcon(def.iconID or def.icon)
					f.expired:play(dur, { expired = true, pop = true })
				end
				if def.grounded then
					-- Grounding's early end: it took a spell (or was destroyed), shown as a success.
					if setting(key, "grounded") then
						if not f.killed then f.killed = ns.makeEndFlash(f.effects, f, key) end
						f.killed:setIcon(def.iconID or def.icon)
						f.killed:play(dur, { grounded = true, pop = setting(key, "groundedPop"), glow = setting(key, "groundedGlow") })
					end
				elseif setting(key, "killed") then
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
-- Ready glows ("use me"), all off by default. Fire Nova: while it is off cooldown and a fire totem
-- is down, the moment it can be cast; both are secret in combat, so each goes through a curve into
-- one of two nested frames' alphas. The shock (ShamanForever_Shock.lua) and the elements with
-- readyGlow (Stormstrike, Riptide, Rage of the Farseer): while the spell is off cooldown. Re-read
-- ten times a second while any is on, so they follow a cooldown ending or a totem running out
-- without waiting for an event.
------------------------------------------------------------------------
local hasTimeLeftCurve = ns.CURVE_LIVE
-- 1 while the spell is off cooldown (possibly secret: only ever handed to SetAlpha). Its own
-- cooldown, without the GCD (ignoreGCD), so the glow doesn't blink with every cast. 0 while the
-- player can't act (cantAct: ns.cantAct(), read once per pass by the caller): "use me" then asks
-- for a cast that can't be made. Not IsSpellUsable, which would also take the glow away when mana
-- runs short.
local function readyAlpha(spellID, cantAct)
	if cantAct then return 0 end
	-- A failed read (a client change) is noted for /sf debug and shows no glow; nothing back is no
	-- cooldown running. ns.try keeps one note per place, so ten reads a second don't flood it.
	local ok, dur = ns.try("ready glow cooldown", C_Spell.GetSpellCooldownDuration, spellID, true)
	if not ok then return 0 end
	if not dur then return 1 end
	local rok, r = ns.try("ready glow", dur.EvaluateRemainingDuration, dur, ns.CURVE_OVER)
	if rok then return r end
	return 0
end
CD.readyAlpha = readyAlpha
-- A frame that calls update ten times a second while shown; hidden, it costs nothing.
function CD.readyTicker(update)
	local ticker = CreateFrame("Frame")
	ticker:Hide()
	ticker.t = 0
	ticker:SetScript("OnUpdate", function(self, elapsed)
		self.t = self.t + elapsed
		if self.t < 0.1 then return end
		self.t = 0
		update()
	end)
	return ticker
end
local function refreshReadyGlow(def, cantAct)
	local f = def.frame
	local on = def.spellID and ns.isEnabled(def.key) and setting(def.key, "readyGlow") and hasTimeLeftCurve and noTimeLeftCurve
	f.readyGlow:SetShown(on and true or false)
	if not on then return end
	f.readyGlow:fit(f:GetWidth())
	if def.needsTotem then
		local tok, tdur = safe(GetTotemDuration, def.needsTotem)
		if not (tok and tdur) then f.readyGate:SetAlpha(0) return end   -- no fire totem
		local gok, g = ns.try("ready gate", tdur.EvaluateRemainingDuration, tdur, hasTimeLeftCurve)
		if gok then f.readyGate:SetAlpha(g) else f.readyGate:SetAlpha(0) end
	end
	f.readyGlow:SetAlpha(readyAlpha(def.spellID, cantAct))
end
local function refreshReadyGlows()
	local cantAct = ns.cantAct()
	for _, def in ipairs(COOLDOWNS) do
		if def.frame.readyGate then refreshReadyGlow(def, cantAct) end
	end
end
local readyTicker = CD.readyTicker(refreshReadyGlows)
-- Runs only while a ready glow is turned on (checked on every layout, i.e. every settings change).
local function syncReadyTicker()
	local want = false
	if ns.isActive() then
		for _, def in ipairs(COOLDOWNS) do
			if def.frame.readyGate and ns.isEnabled(def.key) and setting(def.key, "readyGlow") then want = true end
		end
	end
	readyTicker:SetShown(want and true or false)
	if not want then refreshReadyGlows() end   -- one last pass turns the glows off
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After a spellbook scan: the elements' names, highest ranks and icons. Returns a signature of what
-- it found.
function CD.resolve()
	Reagents.readPerk()   -- the spellbook changed: the perk may have come
	local sig = {}
	for _, def in ipairs(COOLDOWNS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		local known, knownIcon = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end   -- a new rank: read its tooltip again
		def.spellID, def.iconID = known, knownIcon
		table.insert(sig, tostring(def.spellID)); table.insert(sig, tostring(def.iconID))
	end
	return table.concat(sig, ",")
end

-- Every timer takes its current style.
function CD.applyTimers()
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
	refreshCooldowns()
	syncReadyTicker()
end

function CD.refresh()
	for _, def in ipairs(COOLDOWNS) do
		if def.spellID and def.primed then readPrimedBuff(def) end
	end
	refreshCooldowns()
end

-- Our own cast: its ready is armed, a buff window or a primed buff starts, or a spell spends one.
function CD.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not key then return end
	local now = GetTime()
	for _, def in ipairs(COOLDOWNS) do
		if def.spellID and ns.isEnabled(def.key) then
			if key == def.spellKey then CD.noteCast(def.frame, def.spellID) end
			if def.window and key == def.spellKey then
				startActive(def, now, def.window)
			elseif def.primed then
				if key == def.spellKey then
					def.charges = def.primed.charges or 1
					def.castAt = now
					-- Quiet if the buff was already read in (its aura can come before the cast event).
					startActive(def, now, def.primed.duration, def.activeUntil ~= nil)
				elseif def.activeUntil and def.spends[key] then
					def.charges = (def.charges or 1) - 1
					if def.charges <= 0 then def.spentAt = now; endActive(def) end
				end
			end
		end
	end
end

-- A cooldown or totem changed; inEvent: from SPELL_UPDATE_COOLDOWN (see the global cooldown above).
function CD.onCooldowns(inEvent)
	refreshCooldowns(inEvent)
end

-- Once a second: a cooldown's end fires no event.
function CD.tick()
	ns.try("cooldown refresh", refreshCooldowns)
end

-- A shaman logged in: reagent counts, the primed buffs whenever auras are readable, and death.
function CD.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "BAG_UPDATE_DELAYED")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ev:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" then
			for _, def in ipairs(COOLDOWNS) do if def.reagent then refreshCooldown(def) end end
		elseif event == "UNIT_AURA" then
			if InCombatLockdown() then return end   -- auras are secret: nothing to read
			-- Reagent Economy's aura may have come (the buff elements read it on their own refresh).
			local perkUnknown = Reagents.auraChanged()
			for _, def in ipairs(COOLDOWNS) do
				if def.spellID and def.primed and def.primed.buffKey and ns.isEnabled(def.key) then
					readPrimedBuff(def, true); refreshCooldown(def)
				elseif def.reagent and perkUnknown then refreshCooldown(def) end
			end
		end
	end)
	-- Death takes our buffs (Nature's Swiftness's, Rage of the Farseer's window): ended at once, also
	-- where auras can't be read afterwards (a PvP match). Stormstrike's effect is on the target.
	ns.onCanActChange(function(event)
		if event ~= "PLAYER_DEAD" then return end
		for _, def in ipairs(COOLDOWNS) do
			if def.window or (def.primed and def.primed.buffKey) then
				endActive(def)
				refreshCooldown(def)
			end
		end
	end)
end

-- /sf debug
function CD.debug()
	for _, def in ipairs(COOLDOWNS) do
		local secret = "?"
		if def.spellID and C_Secrets and C_Secrets.ShouldTotemSpellBeSecret then
			local ok, v = pcall(C_Secrets.ShouldTotemSpellBeSecret, def.spellID)
			secret = ok and describeArg(v) or "error"
		end
		local read = def.read == nil and "not checked" or describeArg(def.read)
		if def.readHow then read = string.format("slot %d timer, by %s, match %s", def.totemSlot, def.readHow, read)
		elseif def.needsTotem and type(def.read) ~= "string" and def.read ~= nil then read = "warning alpha " .. read end
		local extra = ""
		if def.window or def.primed then
			extra = def.activeUntil and string.format(", %s for %s", def.primed and "primed" or "window",
				def.activeUntil == math.huge and "until spent" or string.format("%.1f s", def.activeUntil - GetTime())) or ", not active"
		end
		if def.reagent then
			extra = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", extra, describeArg(def.reagentRead),
				tostring(def.takesReagent), tostring(Reagents.perkKnown()))
		end
		if def.totemSlot or def.needsTotem then
			say("%s: spell %s, totem spell secret=%s, %s, idle %s%s", def.spell, tostring(def.spellID), secret, read, tostring(def.idle), extra)
		else
			say("%s: spell %s, idle %s%s", def.spell, tostring(def.spellID), tostring(def.idle), extra)
		end
	end
end

ns.registerModule(CD)
