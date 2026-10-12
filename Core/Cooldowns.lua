-- Cooldown elements: the cooldown kind, its parts and its engine
-- No secret is read: durations go to widgets, alphas from curves to SetAlpha.

local _, ns = ...
local P = ns.Profiles
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, R, KD, CS = ns.Spells, ns.Reagents, ns.Kinds, ns.CastStates

local CD = { name = "cooldowns" }
ns.Cooldowns = CD

local setting = E.setting

-- Elements: the class's rows (ns.CLASS.cooldowns). A row's fields: key, spellKey, icon, school,
-- blurb, experimental; its parts' flags (this file's parts: readyGlow, lowMana, noReadyPop,
-- reset; others' below, auraState in _Buffs); expireLooks (which looks Expiring offers; false:
-- none), race (race IDs; others see "Not your race"), cd and duration (preview only),
-- defaults (over the parts'), choices, styles and timerCant (see E.register).
local COOLDOWNS = ns.CLASS.cooldowns or {}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Other files' parts join
-- it: the reagent's (_Reagents), Expiring's (_Timers), a class's own.
local IDLE_NEVER = { "never", "Never", "It always shows in full" }
local IDLE_OFFCD = { "offcd", "Ready", "Idle while it's ready%s" }
local IDLE_ONCD = { "oncd", "Cooling down", "Idle while it's cooling down%s",
	"Shown in full only while it's ready." }
CD.IDLE_CHOICES = { IDLE_NEVER, IDLE_OFFCD, IDLE_ONCD }
-- held: what keeps it shown (a totem's "no totem out")
local function heldChoices(held)
	return { IDLE_NEVER, { IDLE_OFFCD[1], "Ready, " .. held, IDLE_OFFCD[3] },
		{ IDLE_ONCD[1], "Cooling down, " .. held, IDLE_ONCD[3], "Shown in full while it's ready and while its totem "
			.. "is out." } }
end

-- A row with a buff of its own (auraState, _Buffs): its button shows it in full while the buff is up
local function buffChoices(def)
	local s = def.auraState
	if not s then return CD.IDLE_CHOICES end
	if s.active then
		return { IDLE_NEVER, IDLE_OFFCD, { IDLE_ONCD[1], IDLE_ONCD[2], IDLE_ONCD[3], string.format(
			"Shown in full while it's ready, and while it's %s when %s is on.", s.active.title:lower(), s.active.title) } }
	end
	local name = s.key and Spells.name(s.key) or def.spell
	if not name then return CD.IDLE_CHOICES end
	return { IDLE_NEVER, IDLE_OFFCD, { IDLE_ONCD[1], IDLE_ONCD[2],
		string.format("Idle while it's cooling down, except while %s is on you%%s", name),
		string.format("Shown in full while it's ready and while %s is on you.", name) } }
end

-- Time left: its page has a Time left block (a part's)
local function hasUptime(def) return KD.words("cooldown", def, "uptime") ~= nil end

ns.registerPart("cooldown", {
	defaults = { idleAlpha = 0.3, idleWhen = "never" },
	idle = { choices = function(def)
		return def.idleHeld and heldChoices(def.idleHeld) or buffChoices(def)
	end },
	page = { cooldown = "Cooldown", gcd = true, ready = {}, expire = {} },
	preview = {
		cooldown = true, typical = "cd",
		states = { { "ready", "Ready", 10 }, { "cd", "Cooldown", 50 } },
		render = function(ic, st, def, kit)
			kit.reset(ic, def.iconID or def.icon)
			if st == "ready" then ic:SetGlowShown(setting(def.key, "ready", "glow"))
			elseif st == "cd" then kit.frozen(ic.cdT, 0.4, def.cd or 60) end
		end,
		rest = function(ic, def, kit) kit.frozen(ic.cdT, 0.4, def.cd or 60) end,
		pop = function(ic, st, def)
			if st == "ready" and setting(def.key, "ready", "pop") then ic:Pop("ready") end
		end,
		idles = function(st, def, when)
			if KD.idleMode(def, when) == "oncd" then return st == "cd" end
			return st == "ready"
		end,
	},
})
-- Every cooldown has its ready sound; noReadyPop: without the pop
ns.registerPart("ready", {
	has = function() return true end,
	defaults = function(def) return { ready = { pop = not def.noReadyPop or nil, sound = "none" } } end,
	pop = function(def) return not def.noReadyPop end,
})
-- The Ready glow, kept in full over an idle element when the player says so (idleKeep.ready)
local GLOW_ONLY = "Only while its glow is on."
ns.registerPart("readyGlow", { defaults = { ready = { glow = false }, idleKeep = { ready = false } }, glow = true,
	idle = { keep = { "ready", "Ready glow", GLOW_ONLY } }, preview = { keeps = { ready = "ready" } } })
-- reset = { talent }: a Reset event (the cooldown ends early, by that talent), and its ready then.
-- Its pop and sound take the place of Ready's when it plays; the pop has a style of its own, which an
-- element ships different from its Pop style (resetpop); its text is the player's words by the icon for a
-- set time (the word's look: W.WORD's settings); experimental
local RESET_POP = { colorBy = "event", flash = "plain", burst = "star", motion = "bounce", size = 1.6, speed = 1,
	reach = 1 }
local RESET_WORDS, RESET_WORDS_MAX, WORD_FADE = "Reset!", 24, 0.2
CD.RESET_WORDS, CD.RESET_WORDS_MAX = RESET_WORDS, RESET_WORDS_MAX
local function resetWords(key)
	local words = setting(key, "reset", "words")
	words = type(words) == "string" and words:gsub("^%s+", ""):gsub("%s+$", "") or ""
	return words ~= "" and ns.utf8Cut(words, RESET_WORDS_MAX) or RESET_WORDS
end
-- The words on the icon for secs, then fading out; a new show restarts them
local function showWord(f, key, secs)
	local host, token = f.resetHost, {}
	f.resetToken = token
	f.resetWord:SetText(resetWords(key))
	W.styleWord(f.resetWord, f, E.settingsOf(key))
	W.fadeTo(host, 1)
	host:Show()
	C_Timer.After(secs, function()
		if f.resetToken ~= token then return end
		W.fadeTo(host, 0, WORD_FADE)
		C_Timer.After(WORD_FADE, function()
			if f.resetToken == token then host:Hide() end
		end)
	end)
	if f.holdAwake then f.holdAwake(secs + WORD_FADE) end
end
-- A preview icon's word: clipped to its panel, unless /sf preview's stand-in made one of its own
local function previewWord(ic)
	if not ic.resetWord then
		local clip = CreateFrame("Frame", nil, ic:GetParent())
		clip:SetAllPoints(ic:GetParent())
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(ic.textFrame:GetFrameLevel() + 1)
		ic.resetWord = clip:CreateFontString(nil, "OVERLAY")
		ns.Media.setFont(ic.resetWord, nil, 20)
	end
	ic.resetWord:Hide()
	return ic.resetWord
end
local function resetDefaults()
	local d = { reset = { pop = true, text = false, words = RESET_WORDS, secs = 1.5, sound = "none" } }
	for name, v in pairs(W.WORD.defaults) do d[name] = type(v) == "table" and CopyTable(v) or v end
	return d
end
ns.registerPart("reset", {
	kind = "cooldown", experiment = "Reset",
	defaults = resetDefaults,
	ranges = function()
		local r = { reset = { secs = { 0.5, 3, 0.1 } } }
		for name, v in pairs(W.WORD.ranges) do r[name] = v end
		return r
	end,
	choices = W.WORD.choices,
	styles = { resetpop = RESET_POP },
	page = { reset = {} },
	-- The state: Ready as it looks, the Reset's pop, and the words while the state is shown (the HUD's
	-- last a set time)
	preview = {
		states = { { "reset", "Reset", 12 } },
		render = function(ic, st, def)
			if st ~= "reset" then return end
			ic:SetGlowShown(setting(def.key, "ready", "glow"))
			local word = previewWord(ic)
			word:SetText(resetWords(def.key))
			W.styleWord(word, ic, E.settingsOf(def.key))
			word:SetShown(setting(def.key, "reset", "text") == true)
		end,
		pop = function(ic, st, def)
			if st ~= "reset" then return end
			if setting(def.key, "reset", "pop") then ic:Pop("reset")
			elseif setting(def.key, "ready", "pop") then ic:Pop() end
		end,
		idles = function(st, def, when)
			if st == "reset" then return KD.idleMode(def, when) == "offcd" and not setting(def.key, "reset", "text") end
		end,
		standIn = function(ic)
			ic.resetWord = ic.textFrame:CreateFontString(nil, "OVERLAY")
			ns.Media.setFont(ic.resetWord, nil, 16)
			ic.resetWord:Hide()
		end,
	},
	runtime = {
		make = function(def, f)
			f.resetHost = CreateFrame("Frame", nil, f.popLayer)
			f.resetHost:SetAllPoints(f)
			f.resetHost:Hide()
			f.resetWord = f.resetHost:CreateFontString(nil, "OVERLAY")
			ns.Media.setFont(f.resetWord, nil, 16)
		end,
		debug = function(def)
			return def.resetKnown and "reset known" or "reset (talent not learned)"
		end,
	},
})
-- Low mana: a pulsing glow while it's ready and your mana is under a percentage. Mana is secret even
-- out of combat: its percent goes through a curve straight into an alpha, and nothing else reads it
local MANA = Enum.PowerType and Enum.PowerType.Mana or 0
-- 1 under the percentage, 0 from it up
local lowCurves = ns.cache(32, function(under) return ns.curve({ 0, 1, under / 100, 0 }, "Step") or false end)
local function lowCurve(under) return lowCurves(under, under) or nil end
local function lowManaOn(def)
	return E.inUse(def.key) and setting(def.key, "lowMana", "glow") == true
end
ns.registerPart("lowMana", {
	defaults = { lowMana = { glow = false, under = 30 }, idleKeep = { lowMana = false } },
	ranges = { lowMana = { under = { 5, 90, 5 } } },
	glow = true,
	idle = { keep = { "lowMana", "Low mana glow", GLOW_ONLY } },
	page = { lowMana = {} },
	preview = {
		states = { { "lowMana", "Low mana", 15 } },
		render = function(ic, st, def)
			if st == "lowMana" then ic:SetGlowShown(setting(def.key, "lowMana", "glow")) end
		end,
		idles = function(st, def, when)
			if st == "lowMana" then return KD.idleMode(def, when) == "offcd" end
		end,
		keeps = { lowMana = "lowMana" },
	},
	runtime = {
		make = function(def, f)
			f.lowManaGate = CreateFrame("Frame", nil, f.keepHolder("lowMana"))
			f.lowManaGate:SetAllPoints()
			f.lowManaGlow = ns.Effects.glow(f.lowManaGate, f, def.key)
			f.lowManaGlow:Hide()
		end,
		ticks = lowManaOn,
		-- The gate's alpha follows mana, the glow's the cooldown; they multiply, and neither is read
		tick = function(def, cantAct)
			local f = def.frame
			local curve = lowCurve(setting(def.key, "lowMana", "under"))
			local on = lowManaOn(def) and curve ~= nil
			f.lowManaGlow:SetShown(on)
			if not on then f.lowManaGate:SetAlpha(0) return end
			f.lowManaGlow:fit(f:GetWidth())
			local ok, a = ns.try("low mana", UnitPowerPercent, "player", MANA, false, curve)
			if ok then f.lowManaGate:SetAlpha(a) else f.lowManaGate:SetAlpha(0) end
			f.lowManaGlow:SetAlpha(CD.readyAlpha(def.spellID, cantAct))
		end,
		debug = function(def)
			if setting(def.key, "lowMana", "glow") ~= true then return "low mana glow off" end
			local under = string.format("low mana glow under %d%%", setting(def.key, "lowMana", "under"))
			if not def.spellID then return under .. " (not learned)" end
			if not E.isEnabled(def.key) then return under .. " (not shown)" end
			return under
		end,
	},
})
-- A part's runtime hooks (each optional; parts from other files bring their own):
--   refresh(def, inEvent, held)  draws its state on def.frame; returns held, or true where its
--                                state keeps the element shown (its Idle choices applied)
--   gate(def)                    the Ready pop and sound: "ready", "blocked" (the greyed pop, if
--                                chosen) or nil (neither)
--   readyGate(def)               the Ready glow's alpha (may be secret); nil: it can't show
--   make(def, f)                 adds what it draws to the icon f as it's made
--   uptime(def)                  only its presence is read: the part draws its own Time left timer, on a
--                                frame of its own (the icon has none), and its own Expiring (no Expiring
--                                looks of _Timers' part)
--   ticks(def)                   whether tick is wanted now
--   tick(def, cantAct)           ten times a second while any part ticks: redraws a look with no
--                                event to follow (cantAct: the player can't act)
--   debug(def)                   its words in /sf debug
-- refresh, make, tick and debug run for every part, in parts order; gate and readyGate come from
-- the first part that gives one.
-- The icon (def.frame) has upTimer in activeHolder when its page has a Time left block, warn when
-- it has a Warning block, and readyGlow in readyGate with the readyGlow part or a readyGate hook.
-- Icons are made as this file loads, so a part that needs one of these registers before it;
-- prepare notes one that didn't. A part with an uptime hook registers after them on purpose.

local function checkFrames(def)
	local f, missing = def.frame, nil
	if hasUptime(def) and not f.upTimer and not KD.hook("cooldown", def, "uptime") then missing = "upTimer"
	elseif KD.words("cooldown", def, "warn") and not f.warn then missing = "warn"
	elseif KD.hook("cooldown", def, "readyGate") and not f.readyGate then missing = "readyGate" end
	if missing then
		ns.noteError("cooldowns: " .. def.key, "no " .. missing .. ": a part joined after its icon was made")
	end
end

ns.registerKind("cooldown", {
	parts = { "cooldown", "ready", "readyGlow", "lowMana" },
	slots = { "own", "warn", "cast", "ready", "reset", "lowMana", "active", "expire", "killed", "cooldown", "gcd",
		"uptime" },
	prepare = function(def)
		def.expires = hasUptime(def) and def.expireLooks ~= false and not KD.hook("cooldown", def, "uptime")
		checkFrames(def)
	end,
})

local function makeCooldownIcon(def)
	-- The effects layer ignores the icon's alpha; its idle layer and holders fade with an idle icon
	local f = E.newIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	if hasUptime(def) then
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.readyGlow or KD.hook("cooldown", def, "readyGate") then
		-- Ready glow alpha: off cooldown; the gate's alpha multiplies it
		f.readyGate = CreateFrame("Frame", nil, f.keepHolder("ready"))
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.Effects.glow(f.readyGate, f, def.key)
	end
	if KD.words("cooldown", def, "warn") then f.warn = W.makeWarnOverlay(f) end
	KD.eachHook("cooldown", def, "make", f)
	f.stack()
	return f
end

for _, def in ipairs(COOLDOWNS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.spellKey) or def.icon
	def.frame = makeCooldownIcon(def)
	E.register(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults or {}, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end, ranges = def.ranges, choices = def.choices,
		kind = "cooldown", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, race = def.race, styles = def.styles, timerCant = def.timerCant })
	if def.power or def.range then CS.watchRow(def) end
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
-- Arms the next ready only when our own cast starts the cooldown, or at the first look after a
-- login, never on a guess: a missed ready beats a false one.
local READY_GRACE, ARM_AFTER_CAST = 0.5, 1.5
local function arm(r) r.armed, r.by, r.castAt = true, nil, nil end
local function noteReady(f, st, inEvent)
	local r = f.ready
	if st == "ready" then
		-- Its own cooldown read over: the tracker's end within the grace is its ready, a later one isn't
		if r.armed and not r.by then r.by = GetTime() + READY_GRACE end
	elseif st == "own" and inEvent and r.castAt and GetTime() - r.castAt <= ARM_AFTER_CAST then
		arm(r)
	end
end
-- Reset: the event names the spell our cast armed, its tracker is still shown and the read isn't its own
-- cooldown running. Any read that fails or is secret is no Reset.
local function plainNumber(v) return type(v) == "number" and not isSecret(v) and v == v and v or nil end
local function namesSpell(def, id)
	return plainNumber(id) ~= nil and (id == def.spellID or Spells.keyOf(id) == def.spellKey)
end
local function checkReset(def, spellID, baseID)
	local f = def.frame
	local r = f.ready
	if not (r and r.armed and def.spellID and def.resetKnown) then return end
	if not (namesSpell(def, spellID) or namesSpell(def, baseID)) then return end
	if not f.ownCd:IsShown() or ns.zoning() or ns.cantAct() then return end
	local st = plainCooldown(def.spellID)
	if st == nil or st == "own" then return end
	r.armed, r.by, r.castAt = nil, nil, nil
	r.at = GetTime()
	r.reset = r.at
	for _, fn in ipairs(r.fns) do fn() end
end

local function quietCooldown(f)
	local t = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	t:SetAllPoints()
	t:SetDrawSwipe(false)
	t:SetDrawEdge(false)
	t:SetDrawBling(false)
	t:SetHideCountdownNumbers(true)
	t.noCooldownCount = true
	return t
end
-- Ready tracker: a Cooldown fed the spell's own cooldown (ignoreGCD). An end just after the icon
-- comes into view is never a ready (a hidden Cooldown's end can come late).
local JUST_SHOWN = 0.2
local function watchEnds(f)
	if f.ready then return end
	local r = { fns = {}, fresh = true }
	f.ready = r
	local t = quietCooldown(f)
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
	if plainCooldown(spellID) == "own" then arm(r) end
end
-- A cooldown already running at the first look after a login arms its ready, only out of combat, where
-- its start and length read plain; a GCD alone leaves the spell's own duration empty
local function armRunning(f, spellID, st, own)
	local r = f.ready
	if not r.fresh then return end
	r.fresh = nil
	if st ~= "own" or not own or ns.inCombat() or not f.ownCd:IsShown() then return end
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.startTime) or isSecret(info.duration) then return end
	if type(info.duration) ~= "number" or info.duration <= 0 then return end
	local zok, zero = safe(own.IsZero, own)
	if zok and not isSecret(zero) and zero == false then arm(r) end
end
-- Forgets a pending ready, and the login's first look: a cast we didn't see can't leave one armed.
-- off: the element went off, so its next look, once it's back, is a first look as at a login
function CD.resetReady(f, off)
	local r = f.ready
	if not r then return end
	r.armed, r.by, r.castAt, r.fresh = nil, nil, nil, off or nil
	f.ownCd:Clear()
end
function CD.readyNow(f) return f.ready ~= nil and f.ready.at == GetTime() end
-- readyNow, and it is a Reset
function CD.resetNow(f) return f.ready ~= nil and f.ready.reset == GetTime() and f.ready.at == GetTime() end
-- fn() at the tracker's end and at an early end; it checks CD.readyNow itself
local function onReady(f, fn)
	watchEnds(f)
	table.insert(f.ready.fns, fn)
	f.ownCd:HookScript("OnCooldownDone", fn)
end
-- Timer duration by the Global cooldown style, then the time bar's: the spell's own cooldown only,
-- never the GCD (false: none); nil when unreadable. Duration objects only go to widgets (secret in
-- combat).
local function cooldownFor(f, key, spellID, inEvent)
	watchEnds(f)
	local st = plainCooldown(spellID)
	noteReady(f, st, inEvent)
	local ok, own = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if st == "own" and ok and own then
		ns.try("ready tracker", f.ownCd.SetCooldownFromDurationObject, f.ownCd, own, true)
	elseif st == "ready" and not f.ready.armed then f.ownCd:Clear() end
	armRunning(f, spellID, st, ok and own)
	if ns.Style.value(key, "gcd", "show") then
		local gok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID)
		if not (gok and dur) then return nil end
		f.cd:SetDrawBling(st ~= "gcd")
		return dur, ok and own or false
	end
	f.cd:SetDrawBling(true)
	if ok and not own then f.cdTimer:clear() end
	return ok and own or nil
end
CD.cooldownFor = cooldownFor

-- Pop when ready. gate(): "ready", "blocked" (a greyed pop, if chosen) or nil (none); no gate: ready.
-- At a Reset, the Reset's pop takes the place of Ready's, which plays when the Reset's is off.
local function popWhenReady(f, key, gate)
	onReady(f, function()
		if not CD.readyNow(f) then return end
		if not E.isEnabled(key) then return end
		local reset = CD.resetNow(f) and setting(key, "reset", "pop") == true
		if not (reset or setting(key, "ready", "pop")) then return end
		if ns.cantAct() then return end
		local g = "ready"
		if gate then g = gate() end
		local grey = not reset and g == "blocked" and setting(key, "ready", "blocked") == "grey"
		if g ~= "ready" and not grey then return end
		-- Its refresh comes a frame later: a pop that wakes the element plays at the awake alpha
		E.fade(key, 1)
		if reset then f:Pop("reset") elseif grey then f:Pop("blocked") else f:Pop() end
	end)
end
CD.popWhenReady = popWhenReady

-- Idle
-- Off cooldown with nothing of its own going on. isOnGCD is only vouched for inside the event,
-- so its answer is kept (cdRunning).
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
local function fadeTo(def, alpha) E.fade(def.key, alpha) end

-- def needs key, frame, spellID and refresh (other engines pass such a table too); held: something
-- of its own keeps it shown (low reagents, a part's state)
local function applyIdle(def, held, inEvent)
	local when = E.idleWhen(def.key)
	local running, certain = ownCooldownRunning(def, inEvent)
	local busy
	if KD.idleMode(def, when) == "oncd" then busy = not (running and certain) else busy = running end
	busy = busy or held or when == "never" or not P.getAccount().locked
	fadeTo(def, busy and 1 or E.idleAlpha(def.key))
	def.idle = not busy
end
CD.applyIdle = applyIdle

-- Refresh
-- Remaining seconds -> alpha
local noTimeLeftCurve = ns.CURVE_OVER

function refreshCooldown(def, inEvent)
	if not E.isEnabled(def.key) then
		def.cdRunning = nil
		CD.resetReady(def.frame, true)
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
		if f.upTimer then f.upTimer:clear() end
		if f.warn then f.warn:SetAlpha(0) end
		return
	end
	local dur, bar = cooldownFor(f, def.key, def.spellID, inEvent)
	if dur then f.cdTimer:set(dur, bar) end
	f.tex:SetDesaturated(false)
	local held = false
	if def.reagent then
		local hold, ring, pulse = R.refresh(def)
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
	onReady(f, function()
		if not f:IsVisible() or GetTime() - (f.shownAt or 0) < JUST_SHOWN then return end
		if not CD.readyNow(f) then return end
		if gate and gate() ~= "ready" then return end
		local reset = CD.resetNow(f) and setting(key, "reset", "sound") ~= "none"
		ns.Sounds.element(key, reset and "reset" or "ready")
	end)
end
CD.soundWhenReady = soundWhenReady

-- Text at a Reset
local function textWhenReset(f, key)
	onReady(f, function()
		if not CD.resetNow(f) then return end
		if not (E.isEnabled(key) and setting(key, "reset", "text") == true) or ns.cantAct() then return end
		E.fade(key, 1)
		showWord(f, key, setting(key, "reset", "secs"))
	end)
end

for _, def in ipairs(COOLDOWNS) do
	def.refresh = refreshCooldown
	local function gate()
		local g = KD.hook("cooldown", def, "gate")
		if g then return g(def) end
		return "ready"
	end
	popWhenReady(def.frame, def.key, gate)
	soundWhenReady(def.frame, def.key, gate)
	if def.reset then textWhenReset(def.frame, def.key) end
	-- The swipe's end, and the spell's own (the time bar's), which can end inside a GCD
	for _, cd in ipairs({ def.frame.cd, def.frame.ownCd }) do
		cd:HookScript("OnCooldownDone", function() C_Timer.After(0, function() refreshCooldown(def) end) end)
	end
end

local function styleCooldown(def)
	local f = def.frame
	f.tex:SetTexture(def.iconID or def.icon)
	local w = f.warn
	if not w then return end
	w:setIcon(def.iconID or def.icon)
	w:setParts(W.warnParts(def.key, "warn"))
end

-- Ready glows ("use me"), all off by default; re-read ten times a second while on, with the parts'
-- ticks
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
local function refreshReadyGlow(def, cantAct)
	local f = def.frame
	local on = E.inUse(def.key) and setting(def.key, "ready", "glow") and hasTimeLeftCurve
		and noTimeLeftCurve
	f.readyGlow:SetShown(on and true or false)
	if not on then return end
	f.readyGlow:fit(f:GetWidth())
	local gate = KD.hook("cooldown", def, "readyGate")
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
		KD.eachHook("cooldown", def, "tick", cantAct)
	end
end
local function partTicks(def)
	for _, p in ipairs(KD.partsOf("cooldown", def)) do
		local t = p.runtime and p.runtime.ticks
		if t and t(def) then return true end
	end
	return false
end
local readyTicker = ns.ticker(0.1, refreshReadyGlows)
local function syncReadyTicker()
	local want = false
	if E.isActive() then
		for _, def in ipairs(COOLDOWNS) do
			if def.frame.readyGate and E.inUse(def.key) and setting(def.key, "ready", "glow") then want = true end
			if partTicks(def) then want = true end
		end
	end
	readyTicker:SetShown(want and true or false)
	if not want then refreshReadyGlows() end
end

function CD.resolve()
	R.readPerk()
	local sig = {}
	for _, def in ipairs(COOLDOWNS) do
		def.spell = Spells.name(def.spellKey)
		E.ALL[def.key].label = def.spell
		local known, knownIcon
		if not Spells.otherRace(def.race) then
			known, knownIcon = Spells.known(def.spellKey)
		end
		if known ~= def.spellID then def.takesReagent = nil end
		def.spellID, def.iconID = known, knownIcon
		def.resetKnown = def.reset ~= nil and Spells.known(def.reset.talent) ~= nil
		table.insert(sig, tostring(def.spellID)); table.insert(sig, tostring(def.iconID))
	end
	return table.concat(sig, ",")
end

-- Expiring ticks only for a row in use
function CD.applyTimers()
	for _, def in ipairs(COOLDOWNS) do
		local f = def.frame
		f.cdTimer:apply()
		if f.upTimer then
			f.upTimer:apply()
			f.upTimer:setExpire(E.inUse(def.key) and E.event(def.key, "expire") or nil, def.iconID or def.icon)
		end
	end
end

local events   -- set(on): the reagent rows' events, from start
function CD.applyLayout()
	local reagents = false
	for _, def in ipairs(COOLDOWNS) do
		styleCooldown(def)
		if def.reagent and E.inUse(def.key) then reagents = true end
	end
	if events then events(reagents) end
	refreshCooldowns()
	syncReadyTicker()
end

function CD.refresh() refreshCooldowns() end

function CD.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not key then return end
	for _, def in ipairs(COOLDOWNS) do
		if E.inUse(def.key) and key == def.spellKey then CD.noteCast(def.frame, def.spellID) end
	end
end

-- inEvent: from SPELL_UPDATE_COOLDOWN, with the spell it names
function CD.onCooldowns(inEvent, spellID, baseID)
	if inEvent then
		for _, def in ipairs(COOLDOWNS) do
			if def.reset and E.isEnabled(def.key) then checkReset(def, spellID, baseID) end
		end
	end
	refreshCooldowns(inEvent)
end

-- A cooldown's end fires no event
function CD.tick()
	ns.try("cooldown refresh", refreshCooldowns)
end

function CD.start()
	local ev = CreateFrame("Frame")
	events = ns.eventsWhile(ev, { "BAG_UPDATE_DELAYED", { "UNIT_AURA", "player" } })
	ev:SetScript("OnEvent", function(_, event)
		if event == "BAG_UPDATE_DELAYED" then
			for _, def in ipairs(COOLDOWNS) do if def.reagent then refreshCooldown(def) end end
		elseif event == "UNIT_AURA" then
			if not ns.aurasReadable() then return end
			local perkUnknown = R.auraChanged()
			for _, def in ipairs(COOLDOWNS) do
				if def.reagent and perkUnknown then refreshCooldown(def) end
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
		if def.reagent then
			extra = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", extra,
				describeArg(def.reagentRead), tostring(def.takesReagent), tostring(R.perkKnown()))
		end
		say("%s: spell %s, %sidle %s%s", def.spell, tostring(def.spellID), words, tostring(def.idle), extra)
	end
end

MOD.register(CD)
