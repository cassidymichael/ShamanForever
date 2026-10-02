-- Cooldown elements
-- No secret is read: durations go to widgets, Fire Nova's warning is a curve into SetAlpha.
-- A totem timer shows only when the slot's totem is ours; in combat the slot is secret, so an
-- unknown one stays hidden.
-- Buff windows and primed states are inferred from our own casts (Nature's Swiftness is corrected
-- from its aura when readable).

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, Totems, Reagents = ns.Spells, ns.Totems, ns.Reagents

local CD = { name = "cooldowns" }
ns.Cooldowns = CD

local setting = ns.elementSetting

-- Elements
-- Slots: 1 fire, 2 earth, 3 water, 4 air.
-- Parts (below): totemSlot, needsTotem (a totem slot it needs), grounded and ranOut (a totem's end),
-- window (seconds from our cast), primed, reagent (item ID), readyGlow, noReady; expireLooks (which
-- looks Expiring offers; false: none), race (race IDs; others see "Not your race"), cd and duration
-- (preview only), defaults (over the parts'), styles and timerCant (see ns.registerElement).
-- With a cooldown and time left: the cooldown has the swipe; time left as a bar
local ONE_SWIPE = { uptime = { swipe = "The cooldown has the swipe; time left shows as text or a bar." } }
local function barTimer() return { uptime = { text = false, bar = true } } end
local COOLDOWNS = {
	{ key = "earthbind", spellKey = "earthbind", icon = 136102, totemSlot = 2, duration = 45, cd = 15,
		school = "earth",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE, defaults = {} },
	{ key = "stoneclaw", spellKey = "stoneclaw", icon = 136097, totemSlot = 2, duration = 15, cd = 15,
		school = "earth",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE, defaults = {} },
	{ key = "firenova",  spellKey = "fireNova",  icon = 135824, needsTotem = 1, school = "fire",
		blurb = "Cooldown. Needs a fire totem.", timerCant = ONE_SWIPE, cd = 6, duration = 55,
		defaults = { idleWhen = "never" } },
	-- Emergency cooldowns
	{ key = "naturesswiftness", spellKey = "naturesSwiftness", icon = 136076, school = "water",
		blurb = "Cooldown, and a glow while your next Nature spell is instant.",
		primed = { spends = { "healingWave", "lesserHealingWave", "chainHeal", "lightningBolt", "chainLightning",
			"ghostWolf", "farSight" },
			buffKey = "naturesSwiftness",
			text = "From your cast until your next Nature spell with a cast time." },
		cd = 180, defaults = { idleWhen = "never" }, experimental = "Nature's Swiftness" },
	{ key = "manatide", spellKey = "manaTide", icon = 135861, totemSlot = 3, duration = 12, school = "water",
		blurb = "Cooldown, and time left while it's down.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		ranOut = true, cd = 300,
		defaults = { idleWhen = "never", expire = { secs = 3, glow = true, fade = false } }, experimental = "Mana Tide Totem" },
	{ key = "grounding", spellKey = "grounding", icon = 136039, totemSlot = 4, duration = 45, school = "air",
		blurb = "Cooldown, time left, and a flash when it takes a spell.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		grounded = true, ranOut = true, cd = 15, defaults = {}, experimental = "Grounding Totem" },
	-- Rotation
	-- Stormstrike: timed from the cast, spent by our own casts only (auras are secret in combat).
	{ key = "stormstrike", spellKey = "stormstrike", icon = 135963, school = "air",
		blurb = "Cooldown, and a bar while your target takes more Nature damage.",
		styles = barTimer(), timerCant = ONE_SWIPE,
		primed = { spends = { "lightningBolt", "chainLightning", "earthShock" }, duration = 12,
			text = "From your cast for 12 s, or until your next Lightning Bolt, Chain Lightning or Earth Shock. " ..
				"Other Nature damage on the target can also use it up, which can't be seen." },
		primedLooks = false, expireLooks = false, readyGlow = true, cd = 8,
		defaults = { idleWhen = "never" }, experimental = "Stormstrike" },
	{ key = "riptide", spellKey = "riptide", icon = 252995, school = "water", blurb = "Cooldown.",
		readyGlow = true, cd = 6, defaults = { idleWhen = "never" }, experimental = "Riptide" },
	-- Short cooldowns: no Ready pop by default
	{ key = "lavaburst", spellKey = "lavaBurst", icon = 237582, school = "fire", blurb = "Cooldown.",
		readyGlow = true, cd = 10, defaults = { idleWhen = "never", ready = { pop = false } }, experimental = "Lava Burst" },
	{ key = "chainlightning", spellKey = "chainLightning", icon = 136015, school = "air", blurb = "Cooldown.",
		readyGlow = true, cd = 6, defaults = { idleWhen = "never", ready = { pop = false } }, experimental = "Chain Lightning" },
	{ key = "farseer", spellKey = "rageOfTheFarseer", icon = 136048, window = 25, school = "air",
		blurb = "Cooldown, and time left while it's on.",
		timerCant = ONE_SWIPE,
		readyGlow = true, expireLooks = { "grey", "fade" }, cd = 180,
		defaults = { idleWhen = "never", expire = { secs = 0, fade = true } }, experimental = "Rage of the Farseer" },
	{ key = "projection", spellKey = "totemicProjection", icon = 136099, school = "spirit", blurb = "Cooldown.",
		cd = 60, experimental = "Totemic Projection" },
	{ key = "reincarnation", spellKey = "reincarnation", icon = 136080, school = "spirit",
		blurb = "Cooldown, and your Ankhs when they run low.",
		styles = { gcd = { show = false } },   -- never needs the sweep
		reagent = 17030, noReady = true, cd = 3600,
		defaults = { idleAlpha = 0 }, experimental = "Reincarnation" },
	-- Racials (race IDs: Orc 2, Dwarf 3, Tauren 6, Troll 8, Windshaper Skyborne 96)
	{ key = "bloodfury", spellKey = "bloodFury", icon = 135726, race = { 2 }, window = 15,
		school = "fire",
		blurb = "Cooldown, and time left while it's on.", readyGlow = true, timerCant = ONE_SWIPE,
		expireLooks = { "grey", "fade" }, cd = 120,
		defaults = { idleWhen = "never", expire = { secs = 0, fade = true } }, experimental = "Blood Fury" },
	{ key = "shattercurse", spellKey = "shatterCurse", icon = 136082, race = { 2 }, window = 8,
		school = "spirit",
		blurb = "Cooldown, and time left while it's on.", readyGlow = true, timerCant = ONE_SWIPE,
		expireLooks = { "grey", "fade" }, cd = 180,
		defaults = { idleWhen = "never", expire = { secs = 0, fade = true } }, experimental = "Shatter Curse" },
	{ key = "berserking", spellKey = "berserking", icon = 135727, race = { 8 }, window = 10,
		school = "fire",
		blurb = "Cooldown, and time left while it's on.", readyGlow = true, timerCant = ONE_SWIPE,
		expireLooks = { "grey", "fade" }, cd = 180,
		defaults = { idleWhen = "never", expire = { secs = 0, fade = true } }, experimental = "Berserking" },
	{ key = "rapidregeneration", spellKey = "rapidRegeneration", icon = 1850550, race = { 8 },
		school = "water",
		blurb = "Cooldown.", readyGlow = true, cd = 180,
		defaults = { idleWhen = "never" }, experimental = "Rapid Regeneration" },
	{ key = "warstomp", spellKey = "warStomp", icon = 132368, race = { 6 }, school = "earth",
		blurb = "Cooldown.", readyGlow = true, cd = 120,
		defaults = { idleWhen = "never" }, experimental = "War Stomp" },
	{ key = "stoneform", spellKey = "stoneform", icon = 136225, race = { 3 }, window = 8,
		school = "earth",
		blurb = "Cooldown, and time left while it's on.", readyGlow = true, timerCant = ONE_SWIPE,
		expireLooks = { "grey", "fade" }, cd = 180,
		defaults = { idleWhen = "never", expire = { secs = 0, fade = true } }, experimental = "Stoneform" },
	-- Walk on Air: cooldown only, its real length is unseen
	{ key = "walkonair", spellKey = "walkOnAir", icon = 132845, race = { 96 }, school = "air",
		blurb = "Cooldown.", readyGlow = true, cd = 120,
		defaults = { idleWhen = "never" }, experimental = "Walk on Air" },
	{ key = "skysight", spellKey = "skysight", icon = 1029587, race = { 96 }, school = "air",
		blurb = "Cooldown.", readyGlow = true, cd = 120,
		defaults = { idleWhen = "never" }, experimental = "Skysight" },
}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Other files' parts join
-- it: the totems' (_Totems), the reagent's (_Reagents), Expiring's (_Timers).
local IDLE_NEVER = { "never", "Never", "It always shows in full" }
local IDLE_OFFCD = { "offcd", "Ready", "Idle while it's ready%s" }
local IDLE_ONCD = { "oncd", "Cooling down", "Idle while it's cooling down%s",
	"Shown in full only while it's ready." }
CD.IDLE_CHOICES = { IDLE_NEVER, IDLE_OFFCD, IDLE_ONCD }
-- held: what keeps it shown ("no totem out")
local function heldChoices(held)
	return { IDLE_NEVER, { IDLE_OFFCD[1], "Ready, " .. held, IDLE_OFFCD[3] },
		{ IDLE_ONCD[1], "Cooling down, " .. held, IDLE_ONCD[3], IDLE_ONCD[4] } }
end

-- Expiring: a totem's, or a window's or primed state's with a length, unless expireLooks is false
local function expires(def)
	local timed = def.window or (def.primed and def.primed.duration)
	return (def.needsTotem or def.totemSlot or timed) and def.expireLooks ~= false and true or false
end

ns.registerPart("cooldown", {
	defaults = { idleAlpha = 0.3, idleWhen = "offcd" },
	idle = { choices = function(def)
		return def.idleHeld and heldChoices(def.idleHeld) or CD.IDLE_CHOICES
	end },
	page = { cooldown = "Cooldown", gcd = true, ready = {}, expire = {} },
	preview = {
		cooldown = true, typical = "cd",
		states = { { "ready", "Ready", 10 }, { "cd", "Cooldown", 50 } },
		render = function(ic, st, def, P)
			P.reset(ic, def.iconID or def.icon)
			if st == "ready" then ic:SetGlowShown(setting(def.key, "ready", "glow"))
			elseif st == "cd" then P.frozen(ic.cdT, 0.4, def.cd or 60) end
		end,
		rest = function(ic, def, P) P.frozen(ic.cdT, 0.4, def.cd or 60) end,
		pop = function(ic, st, def)
			if st == "ready" and setting(def.key, "ready", "pop") then ic:Pop("ready") end
		end,
		idles = function(st, _, when)
			if when == "oncd" or when == "oncdany" then return st == "cd" end
			return st == "ready"
		end,
	},
})
ns.registerPart("ready", {
	has = function(def) return not def.noReady end,
	defaults = { ready = { pop = true, sound = "none" } },
	pop = { "ready" },
})
ns.registerPart("readyGlow", { defaults = { ready = { glow = false } }, glow = { "ready" } })
-- A buff window from our own cast (window: its seconds)
ns.registerPart("window", {
	idle = { held = "not active", also = " and it isn't active" },
	page = { uptime = "Time left" },
	preview = {
		uptime = true,
		states = { { "active", "Active", 61 }, { "expiring", "Expiring", 62 } },
		render = function(ic, st, def, P)
			if st == "active" then P.frozen(ic.upT, 0.3, def.window)
			elseif st == "expiring" then P.expiring(ic, def.key, def.window) end
		end,
	},
})
-- Primed by our cast until spent: { spends, charges, duration, buffKey, text }; primedLooks false:
-- no pop or glow of its own
ns.registerPart("primed", {
	defaults = function(def)
		return def.primedLooks ~= false and { active = { pop = true, glow = true } } or nil
	end,
	glow = function(def) return def.primedLooks ~= false and { "active" } or nil end,
	pop = function(def) return def.primedLooks ~= false and { "active" } or nil end,
	idle = { held = "not primed", also = " and it isn't primed" },
	page = {
		uptime = function(def) return def.primed.duration and "Primed time left" or nil end,
		active = function(def)
			return { title = "Primed", text = def.primed.text,
				tips = { pop = "The moment it's primed.", glow = "While it's primed." } }
		end,
	},
	preview = {
		uptime = function(def) return def.primed.duration ~= nil end,
		states = { { "primed", "Primed", 60 } },
		render = function(ic, st, def, P)
			if st ~= "primed" then return end
			ic:SetGlowShown(setting(def.key, "active", "glow"))
			if def.primed.duration then P.frozen(ic.upT, 0.3, def.primed.duration) end
		end,
		pop = function(ic, st, def)
			if st == "primed" and setting(def.key, "active", "pop") then ic:Pop("ready") end
		end,
	},
})
ns.registerKind("cooldown", {
	parts = { "cooldown", "ready", "readyGlow", "window", "primed" },
	slots = { "own", "warn", "cooldown", "gcd", "uptime", "ready", "active", "expire", "killed" },
	prepare = function(def) def.expires = expires(def) end,
})

local function makeCooldownIcon(def)
	-- The effects layer ignores the icon's alpha, so an idle icon doesn't fade them
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if def.totemSlot or def.needsTotem or def.window or (def.primed and def.primed.duration) then
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.needsTotem or def.readyGlow then
		-- Ready glow alpha: off cooldown; Fire Nova's gate: a fire totem is down; the two multiply
		f.readyGate = CreateFrame("Frame", nil, f.effects)
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.Effects.glow(f.readyGate, f, def.key)
	end
	-- Fire Nova's warning: its alpha from a possibly-secret boolean
	if def.needsTotem then f.warn = ns.makeWarnOverlay(f) end
	-- Layers, bottom up: icon, warning, swipe, timer bar, text
	f.stack()
	return f
end

for _, def in ipairs(COOLDOWNS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.spellKey) or def.icon
	def.frame = makeCooldownIcon(def)
	ns.registerElement(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults or {}, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end, ranges = def.ranges,
		kind = "cooldown", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, race = def.race, styles = def.styles, timerCant = def.timerCant })
end

-- GCD and own cooldown
-- isOnGCD is only vouched for inside SPELL_UPDATE_COOLDOWN (inEvent)
function CD.onGCD(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) then return false end
	return info.isOnGCD == true
end
-- State: "ready", "gcd", "own"; nil when a field is secret. gcd and own count only in the event.
local function plainCooldown(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then return nil end
	if info.isActive == false then return "ready" end
	if isSecret(info.isOnGCD) then return nil end
	return info.isOnGCD == true and "gcd" or "own"
end
-- Arms the next ready only when our own cast starts the cooldown, never on a guess: a missed
-- ready beats a false one.
local READY_GRACE, ARM_AFTER_CAST = 0.5, 1.5
local function noteReady(f, st, inEvent)
	local r = f.ready
	if st == "ready" then
		if r.armed and not r.by then r.by = GetTime() + READY_GRACE end
	elseif st == "own" and inEvent and r.castAt and GetTime() - r.castAt <= ARM_AFTER_CAST then
		r.armed, r.by, r.castAt = true, nil, nil
	end
end
-- Ready tracker: a Cooldown fed the spell's own cooldown (ignoreGCD). An end just after the icon
-- comes into view is never a ready (a hidden Cooldown's end can come late).
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
	t.noCooldownCount = true
	f.ownCd = t
	t:HookScript("OnShow", function() r.shownAt = GetTime() end)
	t:HookScript("OnCooldownDone", function()
		local now = GetTime()
		local late = r.shownAt and now - r.shownAt < JUST_SHOWN
		r.at = (r.armed and not late and (not r.by or now <= r.by)) and now or nil
		r.armed, r.by = nil, nil
	end)
end
function CD.noteCast(f, spellID)
	watchEnds(f)
	local r = f.ready
	r.castAt = GetTime()
	if plainCooldown(spellID) == "own" then r.armed, r.by, r.castAt = true, nil, nil end
end
-- Forgets a pending ready: a cast we didn't see can't leave one armed
function CD.resetReady(f)
	local r = f.ready
	if not r then return end
	r.armed, r.by, r.castAt = nil, nil, nil
	f.ownCd:Clear()
end
function CD.readyNow(f) return f.ready ~= nil and f.ready.at == GetTime() end
-- Timer duration by the Global cooldown style; nil when unreadable. Duration objects only go to
-- widgets (secret in combat).
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
	if ok and not own then f.cdTimer:clear() end
	return ok and own or nil
end
CD.cooldownFor = cooldownFor

-- Pop when ready. totemSlot: needs a totem in that slot (Fire Nova): a greyed pop, or none
local function popWhenReady(f, key, totemSlot)
	watchEnds(f)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not CD.readyNow(f) then return end
		if not (ns.isEnabled(key) and setting(key, "ready", "pop")) then return end
		if ns.cantAct() then return end
		if totemSlot then
			local ok, d = safe(GetTotemDuration, totemSlot)
			if not ok then return end
			if not d then
				if setting(key, "ready", "blocked") == "grey" then f:Pop("blocked") end
				return
			end
		end
		f:Pop()
	end)
end
CD.popWhenReady = popWhenReady

-- Idle
-- Off cooldown with nothing of its own going on. isOnGCD is only vouched for inside the event,
-- so its answer is kept (cdRunning). Going idle waits IDLE_DELAY so a ready or run-out pop plays at full.
local IDLE_DELAY = ns.IDLE_DELAY
local refreshCooldown
-- An unreadable answer reports running but uncertain
local function ownCooldownRunning(def, inEvent)
	local ok, info = safe(C_Spell.GetSpellCooldown, def.spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then
		def.cdRunning = nil
		return true, false
	end
	if info.isActive == false then def.cdRunning = false return false, true end
	if inEvent or def.cdRunning == nil then
		if isSecret(info.isOnGCD) then return true, false end
		def.cdRunning = info.isOnGCD ~= true
	end
	return def.cdRunning, true
end
local function fadeTo(def, alpha) ns.fadeTo(def.frame, alpha) end

-- def needs key, frame, spellID and refresh (the shock passes such a table too)
local function applyIdle(def, totemBusy, inEvent)
	local when = setting(def.key, "idleWhen")
	local running, certain = ownCooldownRunning(def, inEvent)
	local busy
	if when == "oncd" or when == "oncdany" then busy = not (running and certain) else busy = running end
	busy = busy or when == "never" or not ns.getAccount().locked
	-- A held state (totem down, primed buff, low reagents) is never idle
	if not busy and totemBusy then busy = not (def.needsTotem and (when == "offcd" or when == "oncdany")) end
	if busy then def.idleAt = nil
	elseif def.idle == false then
		def.idleAt = GetTime() + IDLE_DELAY
		C_Timer.After(IDLE_DELAY + 0.05, function() def.refresh(def) end)
	end
	local waiting = def.idleAt and GetTime() < def.idleAt
	fadeTo(def, (busy or waiting) and 1 or ns.idleAlpha(def.key))
	def.idle = not busy
end
CD.applyIdle = applyIdle

-- Refresh
-- Remaining seconds -> alpha
local noTimeLeftCurve = ns.CURVE_OVER

-- Fire Nova: the slot's duration object drives everything, secret or not
local function refreshFireNova(def, inEvent)
	local f = def.frame
	local tok, tdur = safe(GetTotemDuration, def.needsTotem)
	applyIdle(def, tok and tdur ~= nil, inEvent)
	f.activeHolder:SetAlpha(1)
	if tok and tdur == nil then
		f.warn:SetAlpha(1)
		def.read = "no fire totem (no duration)"
	else
		local aok, alpha = false, nil
		if tok and tdur and noTimeLeftCurve then
			aok, alpha = ns.try("fire nova warning", tdur.EvaluateRemainingDuration, tdur, noTimeLeftCurve)
		end
		if aok and alpha ~= nil then
			f.warn:SetAlpha(alpha)
			def.read = alpha
		else
			f.warn:SetAlpha(0)
			def.read = tok and "fire slot duration unreadable" or "fire slot duration error"
		end
	end
	f.upTimer:set(tok and tdur or nil)
	-- Only ever turned off here (cooldownFor sets it each pass)
	if not (tok and tdur) then f.cd:SetDrawBling(false) end
end

-- Whether the slot's totem is def's own (1) or not (0); unknown: hidden
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

-- Buff windows and primed buffs
local function showPrimed(def, on, pop)
	local f, key = def.frame, def.key
	f:SetGlowShown(on and setting(key, "active", "glow"))
	if on and pop and setting(key, "active", "pop") then f:Pop("ready") end
end

local function endActive(def)
	if not def.activeUntil then return end
	def.activeUntil, def.activeToken = nil, nil
	local f = def.frame
	if f.upTimer then f.upTimer:clear(); f.activeHolder:SetAlpha(0) end
	if def.primed then showPrimed(def, false) end
end

-- quiet: already known (an aura read confirming it), so no pop
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

-- A missing buff within a moment of our cast doesn't end it (the aura can arrive after the cast event)
local CAST_GRACE = 1.5
local function readPrimedBuff(def, fromAura)
	local buffKey = def.primed and def.primed.buffKey
	if not buffKey or not ns.aurasReadable() or not C_UnitAuras then return end
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
	-- Just spent: an aura event can still carry the buff; don't bring it back
	if not def.activeUntil and def.spentAt and GetTime() - def.spentAt < CAST_GRACE then return end
	local exp, dur = found.expirationTime, found.duration
	local was = def.activeUntil ~= nil
	if type(exp) == "number" and type(dur) == "number" and exp > 0 and dur > 0 then
		if not was or math.abs(def.activeUntil - exp) > 0.2 then startActive(def, exp - dur, dur, was or not fromAura) end
	elseif not was then startActive(def, GetTime(), nil, not fromAura) end
end

function refreshCooldown(def, inEvent)
	if not ns.isEnabled(def.key) then
		-- Casts aren't followed while off: a window could be spent unseen, so it ends here
		def.cdRunning = nil
		endActive(def)
		CD.resetReady(def.frame)
		return
	end
	local f = def.frame
	if f.killed and not (setting(def.key, "killed", "flash") and setting(def.key, "killed", "mark")) then
		f.killed.mark:Hide()
	end
	if not def.spellID then
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
	if def.primed then showPrimed(def, held) end
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

-- Ready sound: at the pop's moment, only while the icon is on screen and not just after it comes
-- into view
local function soundWhenReady(f, key, totemSlot)
	f:HookScript("OnShow", function() f.shownAt = GetTime() end)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not f:IsVisible() or GetTime() - (f.shownAt or 0) < JUST_SHOWN then return end
		if not CD.readyNow(f) then return end
		if totemSlot then
			local ok, d = safe(GetTotemDuration, totemSlot)
			if not (ok and d) then return end
		end
		ns.Sounds.element(key, "ready")
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
	def.frame.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, function() refreshCooldown(def) end) end)
end

local function styleCooldown(def)
	local f = def.frame
	f.tex:SetTexture(def.iconID or def.icon)
	local w = f.warn
	if not w then return end
	w:setIcon(def.iconID or def.icon)
	w:setParts(ns.warnParts(def.key, "warn"))
end

-- Totem ends: killed early (Grounded for Grounding) or ran out, gated on the time left
Totems.subscribe(function(event, slot, arg)
	for _, def in ipairs(COOLDOWNS) do
		if def.totemSlot == slot then
			local f, key = def.frame, def.key
			if event == "cast" and arg == def.spellKey and f.killed then
				f.killed.mark:Hide()
			elseif event == "gone" and Totems.ownerOf(slot) == def.spellKey and ns.isEnabled(key) then
				local dur = arg
				if f:IsVisible() then ns.Sounds.element(key, "ended", true) end
				if def.ranOut then
					if setting(key, "ended", "flash") then
						if not f.expired then f.expired = ns.Effects.endFlash(f.effects, f, key) end
						f.expired:setIcon(def.iconID or def.icon)
						f.expired:play(dur, { expired = true, ranOut = ns.THEME.color[def.school],
							pop = setting(key, "ended", "pop"), glow = setting(key, "ended", "glow") })
					end
				elseif setting(key, "ended", "pop") then
					if not f.expired then f.expired = ns.Effects.endFlash(f.effects, f, key) end
					f.expired:setIcon(def.iconID or def.icon)
					f.expired:play(dur, { expired = true, pop = true })
				end
				if setting(key, "killed", "flash") then
					if not f.killed then f.killed = ns.Effects.endFlash(f.effects, f, key) end
					f.killed:setIcon(def.iconID or def.icon)
					if def.grounded then
						f.killed:play(dur, { grounded = true, pop = setting(key, "killed", "pop"),
							glow = setting(key, "killed", "glow") })
					else
						f.killed:play(dur, { pop = setting(key, "killed", "pop"), glow = setting(key, "killed", "glow"),
							mark = setting(key, "killed", "mark") })
					end
				end
			end
		end
	end
end)

-- Ready glows ("use me"), all off by default; re-read ten times a second while on
local hasTimeLeftCurve = ns.CURVE_LIVE
-- 1 while off cooldown (maybe secret: only given to SetAlpha); 0 while the player can't act. Not
-- IsSpellUsable: mana would remove it.
local function readyAlpha(spellID, cantAct)
	if cantAct then return 0 end
	-- A failed read is noted once per place (ns.try)
	local ok, dur = ns.try("ready glow cooldown", C_Spell.GetSpellCooldownDuration, spellID, true)
	if not ok then return 0 end
	if not dur then return 1 end
	local rok, r = ns.try("ready glow", dur.EvaluateRemainingDuration, dur, ns.CURVE_OVER)
	if rok then return r end
	return 0
end
CD.readyAlpha = readyAlpha
-- Calls update ten times a second while shown
function CD.readyTicker(update)
	local ticker = CreateFrame("Frame")
	ticker:Hide()
	ticker:SetScript("OnUpdate", ns.throttled(0.1, update))
	return ticker
end
local function refreshReadyGlow(def, cantAct)
	local f = def.frame
	local on = def.spellID and ns.isEnabled(def.key) and setting(def.key, "ready", "glow") and hasTimeLeftCurve
		and noTimeLeftCurve
	f.readyGlow:SetShown(on and true or false)
	if not on then return end
	f.readyGlow:fit(f:GetWidth())
	if def.needsTotem then
		local tok, tdur = safe(GetTotemDuration, def.needsTotem)
		if not (tok and tdur) then f.readyGate:SetAlpha(0) return end
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
local function syncReadyTicker()
	local want = false
	if ns.isActive() then
		for _, def in ipairs(COOLDOWNS) do
			if def.frame.readyGate and ns.isEnabled(def.key) and setting(def.key, "ready", "glow") then want = true end
		end
	end
	readyTicker:SetShown(want and true or false)
	if not want then refreshReadyGlows() end
end

function CD.resolve()
	Reagents.readPerk()
	local sig = {}
	for _, def in ipairs(COOLDOWNS) do
		def.spell = Spells.name(def.spellKey)
		ns.ELEMENTS[def.key].label = def.spell
		local known, knownIcon
		if not Spells.otherRace(def.race) then
			known, knownIcon = Spells.known(def.spellKey)
		end
		if known ~= def.spellID then def.takesReagent = nil end
		def.spellID, def.iconID = known, knownIcon
		table.insert(sig, tostring(def.spellID)); table.insert(sig, tostring(def.iconID))
	end
	return table.concat(sig, ",")
end

function CD.applyTimers()
	for _, def in ipairs(COOLDOWNS) do
		local f = def.frame
		f.cdTimer:apply()
		if f.upTimer then
			f.upTimer:apply()
			f.upTimer:setExpire(ns.elementEvent(def.key, "expire"), def.iconID or def.icon)
		end
	end
end

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
					startActive(def, now, def.primed.duration, def.activeUntil ~= nil)
				elseif def.activeUntil and def.spends[key] then
					def.charges = (def.charges or 1) - 1
					if def.charges <= 0 then def.spentAt = now; endActive(def) end
				end
			end
		end
	end
end

-- inEvent: from SPELL_UPDATE_COOLDOWN
function CD.onCooldowns(inEvent)
	refreshCooldowns(inEvent)
end

-- A cooldown's end fires no event
function CD.tick()
	ns.try("cooldown refresh", refreshCooldowns)
end

function CD.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "BAG_UPDATE_DELAYED")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ev:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" then
			for _, def in ipairs(COOLDOWNS) do if def.reagent then refreshCooldown(def) end end
		elseif event == "UNIT_AURA" then
			if InCombatLockdown() then return end   -- secret in combat
			local perkUnknown = Reagents.auraChanged()
			for _, def in ipairs(COOLDOWNS) do
				if def.spellID and def.primed and def.primed.buffKey and ns.isEnabled(def.key) then
					readPrimedBuff(def, true); refreshCooldown(def)
				elseif def.reagent and perkUnknown then refreshCooldown(def) end
			end
		end
	end)
	-- Death ends our buffs, also where auras can't be read afterwards
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
