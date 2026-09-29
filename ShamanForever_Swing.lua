-- Swing timer: the time to your next main-hand swing, on a bar that fills (or empties) as the swing
-- comes due.
--
-- The engine sends PLAYER_SWING(swingDuration, swingType) with every auto attack, carrying the time
-- to the next one; Blizzard's own swing bar is timed from it too. The duration is plain in combat
-- and the gaps between swings match it within 0.04 s (tested 2026-09-28, open world), and it comes
-- with Blizzard's bar off too. So each swing sets the bar from the engine's own number, as a
-- duration object the StatusBar fills from: nothing is polled between swings.
--
-- Best effort, one swing at a time: nothing else is modelled, so a swing moved by a weapon swap or an
-- attack speed change (secret in combat, tested 2026-09-28) is right again from the next swing. A
-- cast-time spell restarts the swing, and the engine doesn't say when the next one lands, so the bar
-- is cleared when such a cast starts and shows again from the next swing. When the time runs out and
-- no swing came (out of range, facing away), the bar stays at its end: the swing is due. Auto attack
-- off clears it.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule). Its events are registered
-- only while the element is on (SW.afterGroups), so it costs nothing while it's off.

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local SW = { name = "swing" }
ns.Swing = SW

local KEY = "swing"
local MAIN_HAND = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local ICON = Spells.icon("attack") or 135274   -- Attack's icon, or a sword if the client can't say

-- The fill's colour by the main hand's imbue (ShamanForever_Imbue.lua), grey with none.
local IMBUE_SCHOOL = { rockbiter = "earth", flametongue = "fire", frostbrand = "water", windfury = "air" }
local NO_IMBUE = { 0.6, 0.6, 0.6 }

-- Its option defaults (ns.elementSetting). Width and height at the default icon size: the bar grows
-- and shrinks with its group's icon size. fillFrom: the side the fill starts from (left | right);
-- deplete: the bar starts full and empties. countdownPos: left | center | right of the bar.
SW.DEFAULTS = {
	show = "combat",
	swingWidth = 144, swingHeight = 10,   -- the first row's width (three icons and their gaps)
	colorBy = "imbue", color = { 0.9, 0.7, 0.2, 1 },
	fillFrom = "left", deplete = false,
	countdown = false, countdownSize = 12, countdownColor = { 1, 1, 1, 1 }, countdownPos = "center",
}
-- Its numbers' ranges: the page's sliders take theirs from here, and ShamanForever_Profiles.lua
-- clamps imported ones to them.
local RANGES = { swingWidth = { 40, 400 }, swingHeight = { 4, 40 }, countdownSize = { 8, 40 } }
SW.RANGES = RANGES
local function setting(name) return ns.elementSetting(KEY, name) end
local function number(name)
	local v, r = setting(name), RANGES[name]
	if type(v) ~= "number" or v ~= v then v = SW.DEFAULTS[name] end
	return math.min(math.max(v, r[1]), r[2])
end
-- A setting that is one of a few words.
local function choice(name, ...)
	local v = setting(name)
	for i = 1, select("#", ...) do if v == select(i, ...) then return v end end
	return SW.DEFAULTS[name]
end

------------------------------------------------------------------------
-- The element
------------------------------------------------------------------------
-- A dark bar, the fill over it (a StatusBar fed each swing's duration object), a spark on the fill's
-- edge, and the countdown: the client's own cooldown text, placed left, middle or right.

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
	b.spark = spark
	return b
end
-- The side it fills from, and the spark on the fill's free edge. The spark is a line: two screen
-- pixels wide at any size (ns.linePx).
function SW.styleBar(b)
	local fromRight = choice("fillFrom", "left", "right") == "right"
	b:SetReverseFill(fromRight)
	local fill, side = b:GetStatusBarTexture(), fromRight and "LEFT" or "RIGHT"
	b.spark:ClearAllPoints()
	b.spark:SetPoint("TOP" .. side, fill, "TOP" .. side, 0, 0)
	b.spark:SetPoint("BOTTOM" .. side, fill, "BOTTOM" .. side, 0, 0)
	b.spark:SetWidth(ns.linePx(b, 2))
end

-- The countdown's text style, one font object for the bar and its preview (a cooldown's text and a
-- plain font string both take it), and where it sits on the bar it's given.
local font = CreateFont("ShamanForeverSwingFont")
font:SetFont(STANDARD_TEXT_FONT, SW.DEFAULTS.countdownSize, "OUTLINE")
SW.font = font
local TEXT_SIDE = { left = "LEFT", center = "CENTER", right = "RIGHT" }
function SW.styleCountdown()
	local c = setting("countdownColor")
	if not ns.isColor(c) then c = SW.DEFAULTS.countdownColor end
	font:SetFont(STANDARD_TEXT_FONT, number("countdownSize"), "OUTLINE")
	font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end
function SW.placeCountdown(fs, anchor)
	local side = TEXT_SIDE[choice("countdownPos", "left", "center", "right")]
	fs:ClearAllPoints()
	fs:SetPoint(side, anchor, side, side == "LEFT" and 3 or side == "RIGHT" and -3 or 0, 0)
	fs:SetJustifyH(side)
end

local f = CreateFrame("Frame", nil, UIParent)
f:SetSize(SW.DEFAULTS.swingWidth, SW.DEFAULTS.swingHeight)
f:Hide()
f.bg = f:CreateTexture(nil, "BACKGROUND")
f.bg:SetAllPoints()
f.bg:SetColorTexture(unpack(SW.BACKGROUND))
local bar = SW.makeBar(f)
bar:Hide()   -- shown from the first swing
local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
cd:SetAllPoints()
cd:SetDrawSwipe(false)
cd:SetDrawEdge(false)
cd:SetDrawBling(false)
cd:SetCountdownFont("ShamanForeverSwingFont")
local okText, cdFont = pcall(cd.GetCountdownFontString, cd)
local cdText = okText and cdFont or nil
-- Frame levels bottom up: the bar, the countdown (layoutGroup calls this after regrouping).
function f.stack()
	local base = f:GetFrameLevel()
	bar:SetFrameLevel(base + 1)
	cd:SetFrameLevel(base + 2)
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

-- Its place in the default layout: a group of its own just under the first row (shield, shocks,
-- Fire Nova) and above the totem bar, as wide as that row. name: the group's name where groups
-- have one.
table.insert(ns.DEFAULTS.groups, { name = "Swing", point = "CENTER", x = 0, y = -70, scale = 1, alpha = 0.75,
	orientation = "horizontal", growth = "forward", spacing = 6, members = { KEY } })

------------------------------------------------------------------------
-- The swing
------------------------------------------------------------------------
-- endsAt: when the swing under way comes due (GetTime's clock), nil while none is known. swings and
-- secret count PLAYER_SWING for /sf debug.
local state = { endsAt = nil, swings = 0, secret = 0, casts = 0 }
local duration = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()

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

-- The dark strip behind the bar shows with it, and while positioning is unlocked.
local function drawStrip() f.bg:SetShown(bar:IsShown() or not ns.getAccount().locked) end

local function clearSwing()
	state.endsAt = nil
	bar:Hide()
	cd:Clear()
	drawStrip()
end

-- The swing under way on the bar and the countdown: filling as it comes due, or emptying.
local function drawSwing()
	local direction = setting("deplete") == true and REMAINING or ELAPSED
	if not ns.try("swing bar", bar.SetTimerDuration, bar, duration, IMMEDIATE, direction) then
		clearSwing()
		return
	end
	ns.try("swing countdown", cd.SetCooldownFromDurationObject, cd, duration, true)
	bar:Show()
	drawStrip()
end

-- A swing of swingDuration seconds starts now (a plain number).
local function startSwing(swingDuration)
	local now = GetTime()
	if not ns.try("swing duration", duration.SetTimeFromStart, duration, now, swingDuration) then
		clearSwing()
		return
	end
	state.endsAt = now + swingDuration
	drawSwing()
end

local function onSwing(swingDuration, swingType)
	if isSecret(swingType) or swingType ~= MAIN_HAND then return end
	state.swings = state.swings + 1
	if isSecret(swingDuration) or type(swingDuration) ~= "number" or swingDuration <= 0 or not duration then
		-- A secret duration can't time a bar (a duration object takes plain numbers only): the bar
		-- empties until a plain one comes.
		if isSecret(swingDuration) then state.secret = state.secret + 1 end
		clearSwing()
		return
	end
	startSwing(swingDuration)
end

-- A cast that takes time began (UNIT_SPELLCAST_START is not sent for instant spells): it restarts
-- the swing, so the one on the bar is no longer true.
local function onCastStart()
	state.casts = state.casts + 1
	if state.endsAt then clearSwing() end
end

------------------------------------------------------------------------
-- Events: registered only while the element is on
------------------------------------------------------------------------
local ev, listening = nil, false
local EVENTS = {
	{ "PLAYER_SWING" },
	{ "UNIT_SPELLCAST_START", "player" },
	{ "UNIT_INVENTORY_CHANGED", "player" },
	{ "PLAYER_LEAVE_COMBAT" },   -- auto attack off
}

local function onEvent(_, event, a1, a2)
	if event == "PLAYER_SWING" then onSwing(a1, a2)
	elseif event == "UNIT_SPELLCAST_START" then onCastStart()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		paintFill()   -- an imbue put on or lost: the fill takes its colour now, and the options preview
		ns.Options.refresh()
	elseif event == "PLAYER_LEAVE_COMBAT" then clearSwing()
	end
end

-- Registers the events while the element is on; off, drops them and the swing under way.
local function listen(on)
	if not ev or on == listening then return end
	listening = on
	if on then
		for _, e in ipairs(EVENTS) do ns.registerEvent(ev, e[1], e[2]) end
	else
		ev:UnregisterAllEvents()
		clearSwing()
	end
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- The look again after a layout (settings may have changed): the fill's colour, direction and
-- countdown, and the swing under way in its new direction.
function SW.applyLayout()
	if not listening then return end
	paintFill()
	SW.styleBar(bar)
	SW.styleCountdown()
	cd:SetCountdownFont("ShamanForeverSwingFont")
	cd:SetHideCountdownNumbers(setting("countdown") ~= true)
	if cdText then SW.placeCountdown(cdText, f) end
	if state.endsAt then drawSwing() else drawStrip() end
end
-- After the groups' scales are set: lines are measured in screen pixels. Also where ours has just
-- been shown or hidden (every layout comes through here): its events follow.
function SW.afterGroups()
	local on = ns.isEnabled(KEY)
	if on and not listening then
		listen(true)
		SW.applyLayout()
	elseif not on then
		listen(false)
	end
	SW.styleBar(bar)
end

function SW.start()
	ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
end

-- /sf debug
function SW.debug()
	local left = state.endsAt and state.endsAt - GetTime()
	say("swing: %s; %d swings seen, %d with a secret duration, %d cast starts; %s",
		listening and "on" or "off", state.swings, state.secret, state.casts,
		left and (left > 0 and string.format("next in %.1f s", left) or "due") or "no swing under way")
end

ns.registerModule(SW)
