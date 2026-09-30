-- Swing timer: the time to your next main-hand swing, on a bar of its own that fills (or empties)
-- as the swing comes due. Like the totem bar, it sits outside the groups: its own place, size,
-- scale, opacity, Show and border, per profile in db.swingBar.
--
-- The engine sends PLAYER_SWING(swingDuration, swingType) with every auto attack, carrying the time
-- to the next one; Blizzard's own swing bar is timed from it too. The duration is plain in combat
-- and the gaps between swings match it within 0.04 s (tested 2026-09-28, open world), and it comes
-- with Blizzard's bar off too. So each swing sets the bar from the engine's own number, as a
-- duration object the StatusBar fills from: nothing is polled between swings.
--
-- Best effort, one swing at a time: nothing else is modelled, so a swing moved by a weapon swap or
-- an attack speed change (secret in combat, tested 2026-09-28) is right again from the next swing.
-- A cast-time spell restarts the swing, and the engine doesn't say when the next one lands, so the
-- bar is cleared when such a cast starts and shows again from the next swing. When the time runs
-- out and no swing came (out of range, facing away), the bar stays at its end: the swing is due.
-- Auto attack off clears it, and so does death.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule): afterGroups lays it out
-- with every layout of the HUD. Its events are registered only while it's on (not Hidden), so it
-- costs nothing while it's off.

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local SW = { name = "swing" }
ns.Swing = SW

local MAIN_HAND = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
SW.ICON = Spells.icon("attack") or 135274   -- Attack's icon, or a sword if the client can't say

-- The fill's colour by the main hand's imbue (ShamanForever_Imbue.lua), grey with none.
local IMBUE_SCHOOL = { rockbiter = "earth", flametongue = "fire", frostbrand = "water", windfury = "air" }
local NO_IMBUE = { 0.6, 0.6, 0.6 }

------------------------------------------------------------------------
-- Settings: per profile, in db.swingBar
------------------------------------------------------------------------
SW.DEFAULTS = {
	show = "combat",          -- combat | always | never (Hidden: off, nothing runs)
	-- Just under the first row (shield, shocks, Fire Nova) and above the totem bar, as wide as that
	-- row. x, y in UIParent units, so scaling keeps the centre.
	point = "CENTER", x = 0, y = -70,
	width = 144, height = 10,   -- in the bar's own units: Scale grows them, lines too
	scale = 1,
	alpha = 0.75,
	colorBy = "imbue", color = { 0.9, 0.7, 0.2, 1 },   -- imbue | custom
	fillFrom = "left",        -- left | right: the side the fill starts from
	deplete = false,          -- starts full and empties
	countdown = false, countdownSize = 12, countdownColor = { 1, 1, 1, 1 },
	countdownPos = "center",  -- left | center | right of the bar
	-- border: its own, if it has one (ShamanForever_Style.lua)
}
-- Number settings: the options sliders' ranges. Anything outside (a damaged or hand-made import) is
-- clamped, so the layout never gets a scale of 0 or a NaN.
local RANGES = { width = { 40, 400 }, height = { 4, 40 }, scale = { 0.5, 3 }, alpha = { 0.1, 1 },
	countdownSize = { 8, 40 } }
SW.RANGES = RANGES
-- Settings that are one of a few words: the first is kept where the value isn't one of them.
local CHOICES = { show = { "combat", "always", "never" }, colorBy = { "imbue", "custom" },
	fillFrom = { "left", "right" }, countdownPos = { "center", "left", "right" } }
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, r) return math.min(math.max(v, r[1]), r[2]) end

-- The profile's settings, with defaults filled and wrong types or values reset (imported profiles).
local cfgTable
local function cfg()
	local db = ns.getDB()
	if type(db.swingBar) ~= "table" then db.swingBar = {} end
	local t = db.swingBar
	if t ~= cfgTable then
		for k, v in pairs(SW.DEFAULTS) do
			if type(t[k]) ~= type(v) then t[k] = type(v) == "table" and CopyTable(v) or v end
		end
		for k, r in pairs(RANGES) do
			if t[k] ~= t[k] then t[k] = SW.DEFAULTS[k] else t[k] = clamp(t[k], r) end
		end
		for k, list in pairs(CHOICES) do
			if not tContains(list, t[k]) then t[k] = list[1] end
		end
		for _, k in ipairs({ "color", "countdownColor" }) do
			if not ns.isColor(t[k]) then t[k] = CopyTable(SW.DEFAULTS[k]) end
		end
		if not finite(t.x) then t.x = SW.DEFAULTS.x end
		if not finite(t.y) then t.y = SW.DEFAULTS.y end
		if not ns.POINTS[t.point] then t.point, t.x, t.y = SW.DEFAULTS.point, SW.DEFAULTS.x, SW.DEFAULTS.y end
		cfgTable = t
	end
	return t
end
SW.cfg = cfg

-- On at all: a shaman, and Show isn't Hidden.
function SW.isOn() return ns.isActive() and cfg().show ~= "never" end

------------------------------------------------------------------------
-- The bar
------------------------------------------------------------------------
-- f: the bar's place, scale, opacity and visibility (its state driver). face, on it: what shows,
-- only while a swing is under way or positioning is unlocked: a dark strip, the fill over it (a
-- StatusBar fed each swing's duration object) with a spark on its edge, the countdown (the client's
-- own cooldown text, placed left, middle or right) and the border, drawn on the face so it hides
-- with it.

-- The bar's look, shared with its preview (ShamanForever_OptionsSwing.lua): the strip's colour, and
-- the fill filling parent with a spark on its edge (the StatusBar, its spark as .spark).
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
	local fromRight = cfg().fillFrom == "right"
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
	local c = cfg()
	local k = c.countdownColor
	font:SetFont(STANDARD_TEXT_FONT, c.countdownSize, "OUTLINE")
	font:SetTextColor(k[1], k[2], k[3], k[4] or 1)
end
function SW.placeCountdown(fs, anchor)
	local side = TEXT_SIDE[cfg().countdownPos]
	fs:ClearAllPoints()
	fs:SetPoint(side, anchor, side, side == "LEFT" and 3 or side == "RIGHT" and -3 or 0, 0)
	fs:SetJustifyH(side)
end

-- The border it wears: General's, or its own.
function SW.border() return ns.Style.get("swing", "border") end

local f = CreateFrame("Frame", nil, UIParent)
f:SetSize(SW.DEFAULTS.width, SW.DEFAULTS.height)
f:Hide()
SW.frame = f
local face = CreateFrame("Frame", nil, f)
face:SetAllPoints()
face:Hide()   -- shown from the first swing
face.bg = face:CreateTexture(nil, "BACKGROUND")
face.bg:SetAllPoints()
face.bg:SetColorTexture(unpack(SW.BACKGROUND))
local bar = SW.makeBar(face)
bar:SetFrameLevel(face:GetFrameLevel() + 1)
bar:Hide()
local cd = CreateFrame("Cooldown", nil, face, "CooldownFrameTemplate")
cd:SetAllPoints()
cd:SetFrameLevel(face:GetFrameLevel() + 2)
cd:SetDrawSwipe(false)
cd:SetDrawEdge(false)
cd:SetDrawBling(false)
cd:SetCountdownFont("ShamanForeverSwingFont")
local okText, cdFont = pcall(cd.GetCountdownFontString, cd)
local cdText = okText and cdFont or nil

------------------------------------------------------------------------
-- The swing
------------------------------------------------------------------------
-- endsAt: when the swing under way comes due (GetTime's clock), nil while none is known. swings and
-- secret count PLAYER_SWING for /sf debug.
local state = { endsAt = nil, swings = 0, secret = 0, casts = 0 }
local duration = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()

-- The fill's colour: the imbue's school, or the custom one.
local function fillColor()
	local c = cfg()
	if c.colorBy == "custom" then return c.color end
	local school = IMBUE_SCHOOL[ns.Imbue.mainHand() or ""]
	return school and ns.SCHOOL_COLOR[school] or NO_IMBUE
end
SW.fillColor = fillColor
local function paintFill()
	local c = fillColor()
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- The face shows with a swing under way, and while positioning is unlocked (the strip and border
-- then show where the bar goes).
local function drawFace() face:SetShown(bar:IsShown() or not ns.getAccount().locked) end

local function clearSwing()
	state.endsAt = nil
	bar:Hide()
	cd:Clear()
	drawFace()
end

-- The swing under way on the bar and the countdown: filling as it comes due, or emptying.
local function drawSwing()
	local direction = cfg().deplete and REMAINING or ELAPSED
	if not ns.try("swing bar", bar.SetTimerDuration, bar, duration, IMMEDIATE, direction) then
		clearSwing()
		return
	end
	ns.try("swing countdown", cd.SetCooldownFromDurationObject, cd, duration, true)
	bar:Show()
	drawFace()
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
-- Events: registered only while it's on
------------------------------------------------------------------------
local ev, listening = nil, false
local EVENTS = {
	{ "PLAYER_SWING" },
	{ "UNIT_SPELLCAST_START", "player" },
	{ "UNIT_INVENTORY_CHANGED", "player" },
	{ "PLAYER_LEAVE_COMBAT" },   -- auto attack off
	{ "PLAYER_DEAD" },
}

local function onEvent(_, event, a1, a2)
	if event == "PLAYER_SWING" then onSwing(a1, a2)
	elseif event == "UNIT_SPELLCAST_START" then onCastStart()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		paintFill()   -- an imbue put on or lost: the fill takes its colour now, and the options preview
		ns.Options.refresh()
	elseif event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_DEAD" then clearSwing()
	end
end

-- Registers the events while it's on; off, drops them and the swing under way.
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
-- Visibility: its state driver
------------------------------------------------------------------------
local mover
local function visibilityDriver()
	if not SW.isOn() then return "hide" end
	if not ns.getAccount().locked then return "show" end
	if cfg().show == "combat" then return "[petbattle] hide; [combat] show; hide" end
	return "[petbattle] hide; show"
end
local lastDriver
local function drive()
	local driver = visibilityDriver()
	if driver ~= lastDriver then
		lastDriver = driver
		RegisterStateDriver(f, "visibility", driver)
	end
end

------------------------------------------------------------------------
-- Layout (out of combat: its state driver can only change then)
------------------------------------------------------------------------
local function layout()
	if ns.deferInCombat("swing layout", layout) then return end
	local c = cfg()
	listen(SW.isOn())
	-- Scale and opacity first: the size and position are whole screen pixels at the scale
	-- (ns.placeOnPixels says why), and the border's lines are measured for it.
	f:SetScale(c.scale)
	f:SetAlpha(c.alpha)
	local px = ns.pixel(f)
	f:SetSize(math.max(ns.roundPx(c.width, px), px), math.max(ns.roundPx(c.height, px), px))
	ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
	-- "bar": only the parts of a border look that fit a bar, where looks have parts.
	ns.applyBorder(face, SW.border(), "bar")
	paintFill()
	SW.styleBar(bar)
	SW.styleCountdown()
	cd:SetCountdownFont("ShamanForeverSwingFont")
	cd:SetHideCountdownNumbers(not c.countdown)
	if cdText then SW.placeCountdown(cdText, face) end
	if state.endsAt then drawSwing() else drawFace() end
	drive()
	mover.update()
end

-- Settings changed (options page): laid out now, or when combat ends.
function SW.apply()
	cfgTable = nil
	layout()
end

------------------------------------------------------------------------
-- Positioning: a handle over the bar while positioning is unlocked. Dragged by hand, not with
-- StartMoving, so it snaps as groups do (ns.Positioning).
------------------------------------------------------------------------
mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
mover:SetFrameStrata("DIALOG")
mover:SetBackdrop(ns.BACKDROP)
mover:SetBackdropColor(0, 0, 0, 0.4)
mover:EnableMouse(true)
mover:EnableMouseWheel(true)
mover:RegisterForDrag("LeftButton")
mover:Hide()
mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mover.label:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 2)

local movable = { frame = f }
-- The arrow keys: moved by dx, dy (UIParent units).
function movable.nudge(dx, dy)
	local c = cfg()
	c.x, c.y = c.x + dx, c.y + dy
	ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
end
-- Combat started while unlocked: the handle goes, and the strip with it (plain frames).
function movable.lock()
	mover:SetScript("OnUpdate", nil)
	mover:Hide()
	ns.Positioning.endSnap()
	drawFace()
end
ns.Positioning.addMovable(movable)

-- f's centre, from the cursor while dragging (UIParent units from its bottom left), snapped.
local function dragUpdate(self)
	if InCombatLockdown() then movable.lock() return end
	local ui = UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = ns.Positioning.snap(f, cx / ui + self.dragDX, cy / ui + self.dragDY)
	local c = cfg()
	local ux, uy = UIParent:GetCenter()
	c.point, c.x, c.y = "CENTER", x - ux, y - uy
	ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
end
mover:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
	ns.Positioning.selectMovable(movable)
	local ui = UIParent:GetEffectiveScale()
	local s = f:GetEffectiveScale() / ui
	local fx, fy = f:GetCenter()
	local cx, cy = GetCursorPosition()
	self.dragDX, self.dragDY = fx * s - cx / ui, fy * s - cy / ui
	self:SetScript("OnUpdate", dragUpdate)
end)
mover:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
	ns.Positioning.endSnap()
	if not InCombatLockdown() then layout() end
end)
mover:SetScript("OnMouseUp", function(_, button)
	if InCombatLockdown() then return end
	if button == "LeftButton" then ns.Positioning.selectMovable(movable)
	elseif button == "RightButton" then ns.Options.open("swing") end
end)
local function describe()
	local c = cfg()
	return string.format("Swing timer: %d x %d, scale %.2f, opacity %.0f%%", c.width, c.height, c.scale, c.alpha * 100)
end
-- As for groups and the totem bar: mouse wheel, width (lines stay crisp); Shift + wheel, scale
-- (everything grows, lines too); Ctrl + wheel, opacity. Each grows about the bar's centre.
mover:SetScript("OnMouseWheel", function(self, delta)
	if InCombatLockdown() then return end
	local c = cfg()
	local function step(key) c[key] = clamp(math.floor((c[key] + delta * 0.05) * 100 + 0.5) / 100, RANGES[key]) end
	if IsControlKeyDown() then step("alpha")
	elseif IsShiftKeyDown() then step("scale")
	else c.width = clamp(c.width + delta * 4, RANGES.width)
	end
	layout()
	self.label:SetText(describe())
	ns.Options.refresh()
end)
function mover.update()
	local on = SW.isOn() and not ns.getAccount().locked and not InCombatLockdown()
	if on then
		mover:ClearAllPoints()
		mover:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
		mover:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
		local chosen = ns.Positioning.isSelected(movable)
		if chosen then mover:SetBackdropBorderColor(1, 0.82, 0, 1)
		else mover:SetBackdropBorderColor(0.2, 0.6, 1, 0.9) end
		mover.label:SetText(chosen and "Swing timer (arrow keys move it)" or "Swing timer")
	end
	mover:SetShown(on)
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- Its own layout, with every layout of the HUD (settings, the lock, a profile loaded).
SW.afterGroups = layout

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
