-- Cooldown elements: the cooldown kind, its parts and its engine
-- No secret is read: durations go to widgets, alphas from curves to SetAlpha.
-- Buff windows and primed states are inferred from our own casts (a primed buff is corrected from
-- its aura when readable).

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, Reagents, KD = ns.Spells, ns.Reagents, ns.Kinds

local CD = { name = "cooldowns" }
ns.Cooldowns = CD

local setting = ns.elementSetting

-- Elements: the class's rows (ns.CLASS.cooldowns). A row's fields: key, spellKey, icon, school,
-- blurb, experimental; its parts' flags (this file's parts: window (seconds from our cast), primed,
-- readyGlow, noReady; others' below); expireLooks (which looks Expiring offers; false: none), race
-- (race IDs; others see "Not your race"), cd and duration (preview only), defaults (over the
-- parts'), styles and timerCant (see ns.registerElement).
local COOLDOWNS = ns.CLASS.cooldowns or {}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Other files' parts join
-- it: the reagent's (_Reagents), Expiring's (_Timers), a class's own.
local IDLE_NEVER = { "never", "Never", "It always shows in full" }
local IDLE_OFFCD = { "offcd", "Ready", "Idle while it's ready%s" }
local IDLE_ONCD = { "oncd", "Cooling down", "Idle while it's cooling down%s",
	"Shown in full only while it's ready." }
CD.IDLE_CHOICES = { IDLE_NEVER, IDLE_OFFCD, IDLE_ONCD }
-- held: what keeps it shown ("not active")
local function heldChoices(held)
	return { IDLE_NEVER, { IDLE_OFFCD[1], "Ready, " .. held, IDLE_OFFCD[3] },
		{ IDLE_ONCD[1], "Cooling down, " .. held, IDLE_ONCD[3], IDLE_ONCD[4] } }
end

-- Time left: its page has a Time left block (a window, a primed state with a length, a part's)
local function hasUptime(def) return KD.words("cooldown", def, "uptime") ~= nil end

ns.registerPart("cooldown", {
	defaults = { idleAlpha = 0.3, idleWhen = "never" },
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
	pop = true,
})
ns.registerPart("readyGlow", { defaults = { ready = { glow = false } }, glow = true })
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
-- Primed by our cast until spent: { spends, duration, buffKey, text }; primedLooks false:
-- no pop or glow of its own
ns.registerPart("primed", {
	defaults = function(def)
		return def.primedLooks ~= false and { active = { pop = true, glow = true } } or nil
	end,
	glow = function(def) return def.primedLooks ~= false end,
	pop = function(def) return def.primedLooks ~= false end,
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
-- A part's runtime hooks (each optional; parts from other files bring their own):
--   refresh(def, inEvent, held)  draws its state on def.frame; returns held, or true where its
--                                state keeps the element shown (its Idle choices applied)
--   gate(def)                    the Ready pop and sound: "ready", "blocked" (the greyed pop, if
--                                chosen) or nil (neither)
--   readyGate(def)               the Ready glow's alpha (may be secret); nil: it can't show
--   debug(def)                   its words in /sf debug
-- The icon (def.frame) has upTimer in activeHolder when its page has a Time left block, warn when
-- it has a Warning block, and readyGlow in readyGate with the readyGlow part or a readyGate hook.
-- Icons are made as this file loads, so a part with hooks registers before it.
ns.registerKind("cooldown", {
	parts = { "cooldown", "ready", "readyGlow", "window", "primed" },
	slots = { "own", "warn", "cooldown", "gcd", "uptime", "ready", "active", "expire", "killed" },
	prepare = function(def) def.expires = hasUptime(def) and def.expireLooks ~= false end,
})

-- The first of def's parts with that runtime hook
local function hookOf(def, name)
	for _, p in ipairs(KD.partsOf("cooldown", def)) do
		local h = p.runtime and p.runtime[name]
		if h then return h end
	end
end

local function makeCooldownIcon(def)
	-- The effects layer ignores the icon's alpha, so an idle icon doesn't fade them
	local f = ns.newElementIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if hasUptime(def) then
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.readyGlow or hookOf(def, "readyGate") then
		-- Ready glow alpha: off cooldown; the gate's alpha multiplies it
		f.readyGate = CreateFrame("Frame", nil, f.effects)
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.Effects.glow(f.readyGate, f, def.key)
	end
	if KD.words("cooldown", def, "warn") then f.warn = ns.makeWarnOverlay(f) end
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

-- Pop when ready. gate(): "ready", "blocked" (a greyed pop, if chosen) or nil (none); no gate: ready
local function popWhenReady(f, key, gate)
	watchEnds(f)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not CD.readyNow(f) then return end
		if not (ns.isEnabled(key) and setting(key, "ready", "pop")) then return end
		if ns.cantAct() then return end
		local g = "ready"
		if gate then g = gate() end
		if g == "ready" then f:Pop()
		elseif g == "blocked" and setting(key, "ready", "blocked") == "grey" then f:Pop("blocked") end
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

-- def needs key, frame, spellID and refresh (the shock passes such a table too); held: something of
-- its own keeps it shown (a window or primed buff, low reagents, a part's state)
local function applyIdle(def, held, inEvent)
	local when = setting(def.key, "idleWhen")
	local running, certain = ownCooldownRunning(def, inEvent)
	local busy
	if when == "oncd" or when == "oncdany" then busy = not (running and certain) else busy = running end
	busy = busy or held or when == "never" or not ns.getAccount().locked
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
	for _, p in ipairs(KD.partsOf("cooldown", def)) do
		local r = p.runtime and p.runtime.refresh
		if r then held = r(def, inEvent, held) end
	end
	applyIdle(def, held, inEvent)
end

local function refreshCooldowns(inEvent)
	for _, def in ipairs(COOLDOWNS) do refreshCooldown(def, inEvent) end
end

-- Ready sound: at the pop's moment, only while the icon is on screen and not just after it comes
-- into view; gate as popWhenReady's
local function soundWhenReady(f, key, gate)
	f:HookScript("OnShow", function() f.shownAt = GetTime() end)
	f.ownCd:HookScript("OnCooldownDone", function()
		if not f:IsVisible() or GetTime() - (f.shownAt or 0) < JUST_SHOWN then return end
		if not CD.readyNow(f) then return end
		if gate and gate() ~= "ready" then return end
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
	local function gate()
		local g = hookOf(def, "gate")
		if g then return g(def) end
		return "ready"
	end
	popWhenReady(def.frame, def.key, gate)
	if not def.noReady then soundWhenReady(def.frame, def.key, gate) end
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
	local gate = hookOf(def, "readyGate")
	if gate then
		local a = gate(def)
		if not a then f.readyGate:SetAlpha(0) return end
		f.readyGate:SetAlpha(a)
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
					def.castAt = now
					startActive(def, now, def.primed.duration, def.activeUntil ~= nil)
				elseif def.activeUntil and def.spends[key] then
					def.spentAt = now
					endActive(def)
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
		local words = ""
		for _, p in ipairs(KD.partsOf("cooldown", def)) do
			local d = p.runtime and p.runtime.debug
			if d then words = words .. d(def) .. ", " end
		end
		local extra = ""
		if def.window or def.primed then
			extra = def.activeUntil and string.format(", %s for %s", def.primed and "primed" or "window",
				def.activeUntil == math.huge and "until spent"
					or string.format("%.1f s", def.activeUntil - GetTime())) or ", not active"
		end
		if def.reagent then
			extra = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", extra,
				describeArg(def.reagentRead), tostring(def.takesReagent), tostring(Reagents.perkKnown()))
		end
		say("%s: spell %s, %sidle %s%s", def.spell, tostring(def.spellID), words, tostring(def.idle), extra)
	end
end

ns.registerModule(CD)
