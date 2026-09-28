-- Swing timer: the time to your next main-hand swing, on a bar that fills as the swing comes due.
--
-- The engine sends PLAYER_SWING(swingDuration, swingType) with every auto attack, carrying the time
-- to the next one; Blizzard's own swing bar runs on it and nothing else. The duration is plain in
-- combat and the gaps between swings match it within 0.04 s (tested 2026-09-28, open world), and it
-- comes with Blizzard's bar off too. So each swing sets the bar from the engine's own number, as a
-- duration object the StatusBar fills from: nothing is polled between swings.
--
-- What moves a swing already under way isn't sent. Attack speed is secret in combat (UnitAttackSpeed,
-- tested 2026-09-28), so after an attack speed change (UNIT_ATTACK_SPEED) or a main-hand swap
-- mid-swing the bar can't know when the next swing comes: its fill fades ("unsure") until the next
-- PLAYER_SWING sets it right. When the time runs out and no swing came (out of range, facing away),
-- the bar stays full: the swing is due. Not auto attacking, it is idle.
--
-- Blizzard's own swing bar (the showSwingTimer CVar, off by default) is turned off while this one
-- shows, unless the player shows both; see "Blizzard's swing bar" below.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule). Its events are registered
-- only while the element is on (SW.afterGroups), so it costs nothing while it's off.

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

local SW = { name = "swing" }
ns.Swing = SW

local KEY = "swing"
local MAIN_HAND = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local MAIN_HAND_SLOT = 16   -- the main hand's inventory slot (INVSLOT_MAINHAND)
local ATTACK = Spells.DEFS.attack.ids[1]
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local ICON = Spells.icon("attack") or 135274   -- Attack's icon, or a sword if the client can't say

-- The fill's colour by the main hand's imbue (ShamanForever_Imbue.lua), grey with none.
local IMBUE_SCHOOL = { rockbiter = "earth", flametongue = "fire", frostbrand = "water", windfury = "air" }
local NO_IMBUE = { 0.6, 0.6, 0.6 }

-- Its option defaults (ns.elementSetting). Width and height at the default icon size: the bar grows
-- and shrinks with its group's icon size.
SW.DEFAULTS = {
	show = "combat", idleAlpha = 0,
	swingWidth = 144, swingHeight = 10,   -- the first row's width (three icons and their gaps)
	colorBy = "imbue", color = { 0.9, 0.7, 0.2, 1 },
	unsureAlpha = 0.35,
}
-- Its numbers' ranges: the page's sliders take theirs from here, and ShamanForever_Profiles.lua
-- clamps imported ones to them.
local RANGES = { swingWidth = { 40, 400 }, swingHeight = { 4, 40 }, unsureAlpha = { 0, 1 } }
SW.RANGES = RANGES
local function setting(name) return ns.elementSetting(KEY, name) end
local function number(name)
	local v, r = setting(name), RANGES[name]
	if type(v) ~= "number" or v ~= v then v = SW.DEFAULTS[name] end
	return math.min(math.max(v, r[1]), r[2])
end

------------------------------------------------------------------------
-- The element
------------------------------------------------------------------------
-- A dark bar, the fill over it (a StatusBar fed each swing's duration object), a spark on the fill's
-- edge, and the countdown: a timer of the cooldown kind (ShamanForever_Timers.lua), text only.

-- The bar's look, shared with its preview (ShamanForever_OptionsLook.lua): the background colour
-- under it, and the fill filling parent with a spark on its edge (the StatusBar, its spark as .spark).
SW.BACKGROUND = { 0, 0, 0, 0.6 }
function SW.makeBar(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetAllPoints()
	b:SetStatusBarTexture(WHITE)
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	local spark = b:CreateTexture(nil, "OVERLAY")
	spark:SetColorTexture(1, 1, 1, 0.9)
	local fill = b:GetStatusBarTexture()
	spark:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
	spark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
	spark:SetWidth(1)
	b.spark = spark
	return b
end
-- The spark is a line: two screen pixels wide at any size (ns.linePx).
function SW.sizeSpark(b) b.spark:SetWidth(ns.linePx(b, 2)) end

local f = CreateFrame("Frame", nil, UIParent)
f:SetSize(SW.DEFAULTS.swingWidth, SW.DEFAULTS.swingHeight)
f:Hide()
f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.bg:SetColorTexture(unpack(SW.BACKGROUND))
local bar = SW.makeBar(f)
bar:Hide()   -- shown from the first swing
f.cdTimer = ns.Timer.new(f, KEY, "cooldown", { noBar = true })
f.cdTimer.cd:SetDrawBling(false)   -- no flash at the end of every swing
-- Frame levels bottom up: the bar, the fill, the countdown (layoutGroup calls this after regrouping).
function f.stack()
	local base = f:GetFrameLevel()
	bar:SetFrameLevel(base + 1)
	f.cdTimer.cd:SetFrameLevel(base + 2)
end
f.stack()

local function getSize(size)
	local k = size / ns.BASE_ICON_SIZE
	return number("swingWidth") * k, number("swingHeight") * k
end
SW.getSize = getSize

ns.registerElement(KEY, { frame = f, label = "Swing timer", paint = function(t) t:SetTexture(ICON) end,
	getSize = getSize, defaults = SW.DEFAULTS, kind = "swing", def = SW, icon = ICON, school = "spirit",
	blurb = "Time to your next melee swing.", experimental = "Swing timer" })

------------------------------------------------------------------------
-- The swing
------------------------------------------------------------------------
-- endsAt: when the swing under way comes due (GetTime's clock), nil while none is known; unsure:
-- something may have moved it since; attacking: auto attack is on; speed: the main hand's speed as
-- last read plainly (a swing's duration is one). swings and secret count PLAYER_SWING for /sf debug.
local state = { endsAt = nil, unsure = false, attacking = false, speed = nil, swings = 0, secret = 0 }
local duration = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()

local function running() return state.endsAt ~= nil and GetTime() < state.endsAt end

-- The fill's colour: the imbue's school, or the custom one.
local function fillColor()
	if setting("colorBy") == "custom" then
		local c = setting("color")
		return ns.isColor(c) and c or SW.DEFAULTS.color
	end
	local school = IMBUE_SCHOOL[ns.Imbue.mainHand() or ""]
	return school and ns.SCHOOL_COLOR[school] or NO_IMBUE
end
SW.fillColor = fillColor
local function paintFill()
	local c = fillColor()
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- The fill and countdown at full, or faded while unsure.
local function drawUnsure()
	local a = state.unsure and number("unsureAlpha") or 1
	bar:SetAlpha(a)
	f.cdTimer.cd:SetAlpha(a)
end

-- Idle (not auto attacking) takes its Idle opacity; while positioning is unlocked it shows at full.
local function drawIdle()
	local idle = ns.getAccount().locked and not state.attacking
	ns.fadeTo(f, idle and ns.idleAlpha(KEY) or 1)
end

local function clearSwing()
	state.endsAt, state.unsure = nil, false
	bar:Hide()
	f.cdTimer:clear()
	drawUnsure()
end

local function markUnsure()
	if not running() or state.unsure then return end
	state.unsure = true
	drawUnsure()
end

local function onSwing(swingDuration, swingType)
	if isSecret(swingType) or swingType ~= MAIN_HAND then return end
	state.swings = state.swings + 1
	if not state.attacking then
		state.attacking = true
		drawIdle()
	end
	if isSecret(swingDuration) or type(swingDuration) ~= "number" or swingDuration <= 0 or not duration then
		-- A secret duration can't time a bar (a duration object takes plain numbers only): the bar
		-- empties until a plain one comes.
		if isSecret(swingDuration) then state.secret = state.secret + 1 end
		clearSwing()
		return
	end
	local now = GetTime()
	if not ns.try("swing duration", duration.SetTimeFromStart, duration, now, swingDuration) then
		clearSwing()
		return
	end
	state.endsAt, state.unsure, state.speed = now + swingDuration, false, swingDuration
	ns.try("swing bar", bar.SetTimerDuration, bar, duration, IMMEDIATE, ELAPSED)
	bar:Show()
	f.cdTimer:set(duration)
	drawUnsure()
end

-- The main hand's speed, when it reads plainly (out of combat).
local function readSpeed()
	local ok, main = safe(UnitAttackSpeed, "player")
	if ok and not isSecret(main) and type(main) == "number" and main > 0 then return main end
end

-- Attack speed changed: a plain read that shows no change leaves the bar alone; a changed or secret
-- one leaves the swing under way unknown.
local function onAttackSpeed()
	local new = readSpeed()
	local same = new ~= nil and state.speed ~= nil and math.abs(new - state.speed) < 0.001
	if new then state.speed = new end
	if not same then markUnsure() end
end

local function readAttacking()
	local ok, v = safe(C_Spell.IsCurrentSpell, ATTACK)
	if ok and not isSecret(v) and type(v) == "boolean" then state.attacking = v end
end

------------------------------------------------------------------------
-- Blizzard's swing bar
------------------------------------------------------------------------
-- The showSwingTimer CVar (Options > Advanced Options > Swing Timer; off by default, seen
-- 2026-09-28). While ours shows, Blizzard's is turned off, out of combat, and the character's entry
-- in acct.swingBlizzardOff remembers that we did, so hiding ours turns it back on. Never against the
-- player: turning Blizzard's on while ours shows (CVAR_UPDATE, or found on at a later check after
-- we turned it off) sets Show both (acct.swingShowBlizzard), and it's left alone from then on.
local CVAR = "showSwingTimer"
local ourChange = false   -- our own SetCVar is under way (its CVAR_UPDATE comes at once)

local function blizzardOn()
	local ok, v = safe(C_CVar and C_CVar.GetCVar, CVAR)
	if not ok or isSecret(v) or type(v) ~= "string" then return nil end
	return v ~= "0"
end

local function setBlizzard(on)
	ourChange = true
	local ok, err = pcall(C_CVar.SetCVar, CVAR, on and "1" or "0")
	ourChange = false
	if not ok then ns.noteError("swing: Blizzard's bar", err) end
	return ok
end

-- The character's entry: whether we turned Blizzard's bar off (nil until the game knows who it is).
local function turnedOff(set)
	local acct, key = ns.getAccount(), ns.Profiles.charKey()
	if not key then return false end
	if type(acct.swingBlizzardOff) ~= "table" then acct.swingBlizzardOff = {} end
	if set ~= nil then acct.swingBlizzardOff[key] = set or nil end
	return acct.swingBlizzardOff[key] == true
end

local function syncBlizzard()
	if ns.deferInCombat("swing: Blizzard's bar", syncBlizzard) then return end
	local acct = ns.getAccount()
	local on = blizzardOn()
	if on == nil or not ns.isActive() then return end
	local wantOff = ns.isEnabled(KEY) and not acct.swingShowBlizzard
	if wantOff and on then
		if turnedOff() then
			-- We turned it off and it's on again: the player turned it back on.
			acct.swingShowBlizzard = true
			turnedOff(false)
		elseif setBlizzard(false) then
			turnedOff(true)
		end
	elseif not wantOff and turnedOff() then
		turnedOff(false)
		if not on then setBlizzard(true) end
	end
end

-- CVAR_UPDATE: the player turned Blizzard's bar on (its own option, or /console) while ours shows.
local function onCVar(name)
	if ourChange or isSecret(name) or type(name) ~= "string" or name:lower() ~= CVAR:lower() then return end
	local acct = ns.getAccount()
	if blizzardOn() and ns.isEnabled(KEY) and not acct.swingShowBlizzard then
		acct.swingShowBlizzard = true
		turnedOff(false)
		ns.Options.refresh()
	end
end

------------------------------------------------------------------------
-- Events: registered only while the element is on
------------------------------------------------------------------------
local ev, listening = nil, false
local EVENTS = {
	{ "PLAYER_SWING" }, { "UNIT_ATTACK_SPEED", "player" }, { "PLAYER_EQUIPMENT_CHANGED" },
	{ "UNIT_INVENTORY_CHANGED", "player" },
	{ "PLAYER_ENTER_COMBAT" },   -- auto attack on
	{ "PLAYER_LEAVE_COMBAT" },   -- auto attack off
	{ "CVAR_UPDATE" },
}

local function onEvent(_, event, a1, a2)
	if event == "PLAYER_SWING" then onSwing(a1, a2)
	elseif event == "UNIT_ATTACK_SPEED" then onAttackSpeed()
	elseif event == "PLAYER_EQUIPMENT_CHANGED" then
		-- A main-hand swap mid-swing: the next swing's time is the new weapon's, unknown in combat.
		if not isSecret(a1) and a1 == MAIN_HAND_SLOT then markUnsure() end
	elseif event == "UNIT_INVENTORY_CHANGED" then
		paintFill()   -- an imbue put on or lost: the fill takes its colour now
	elseif event == "PLAYER_ENTER_COMBAT" then
		state.attacking = true
		drawIdle()
	elseif event == "PLAYER_LEAVE_COMBAT" then
		-- Auto attack off: a swing started again later starts from an empty bar.
		state.attacking = false
		clearSwing()
		drawIdle()
	elseif event == "CVAR_UPDATE" then onCVar(a1)
	end
end

-- Registers the events while the element is on; off, drops them and the swing under way.
local function listen(on)
	if not ev or on == listening then return end
	listening = on
	if on then
		for _, e in ipairs(EVENTS) do ns.registerEvent(ev, e[1], e[2]) end
		state.speed = readSpeed()
	else
		ev:UnregisterAllEvents()
		state.attacking = false
		clearSwing()
	end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
function SW.refresh()
	if not listening then return end
	readAttacking()
	if not state.speed then state.speed = readSpeed() end
	drawIdle()
	drawUnsure()
end

-- The look again after a layout (settings may have changed): the fill's colour, idle and unsure.
function SW.applyLayout()
	if not listening then return end
	paintFill()
	SW.refresh()
end
function SW.applyTimers() f.cdTimer:apply() end
-- After the groups' scales are set: lines are measured in screen pixels. Also where ours has just
-- been shown or hidden (every layout comes through here): its events follow, and Blizzard's bar.
function SW.afterGroups()
	local on = ns.isEnabled(KEY)
	if on and not listening then
		listen(true)
		paintFill()
		SW.refresh()
	elseif not on then
		listen(false)
	end
	SW.sizeSpark(bar)
	syncBlizzard()
end

function SW.start()
	ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
end

-- /sf debug
function SW.debug()
	local left = state.endsAt and state.endsAt - GetTime()
	say("swing: %s; %d swings seen, %d with a secret duration; auto attack %s; %s%s; Blizzard's bar %s (turned off by us %s, show both %s)",
		listening and "on" or "off", state.swings, state.secret, tostring(state.attacking),
		left and (left > 0 and string.format("next in %.1f s", left) or "due") or "no swing under way",
		state.unsure and ", unsure" or "", tostring(blizzardOn()), tostring(turnedOff()),
		tostring(ns.getAccount().swingShowBlizzard or false))
end

ns.registerModule(SW)
