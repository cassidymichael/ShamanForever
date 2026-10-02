-- Swing timer

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local SW = { name = "swing" }
ns.Swing = SW

local MAIN_HAND = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
SW.ICON = Spells.icon("attack") or 135274

local IMBUE_SCHOOL = { rockbiter = "earth", flametongue = "fire", frostbrand = "water", windfury = "air" }
local NO_IMBUE = { 0.7, 0.7, 0.7 }

-- Settings
SW.DEFAULTS = {
	show = "combat",   -- combat | always | never
	point = "CENTER", x = 0, y = -251,
	width = 220, height = 7,
	scale = 1,
	alpha = 0.75,
	colorBy = "imbue", color = { 1, 0.8, 0.25, 1 },
	fillFrom = "left",
	deplete = false,
	countdown = false, countdownSize = 12, countdownColor = { 1, 1, 1, 1 },
	countdownPos = "center",
}
local RANGES = { width = { 40, 400 }, height = { 4, 40 }, scale = { 0.5, 3 }, alpha = { 0.1, 1 },
	countdownSize = { 8, 40 } }
SW.RANGES = RANGES
local CHOICES = { show = { "combat", "always", "never" }, colorBy = { "imbue", "custom" },
	fillFrom = { "left", "right" }, countdownPos = { "center", "left", "right" } }
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, r) return math.min(math.max(v, r[1]), r[2]) end

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

function SW.isOn() return ns.isActive() and cfg().show ~= "never" end
ns.Style.registerBar("swing", { cfg = cfg, DEFAULTS = SW.DEFAULTS, label = "Swing timer", on = SW.isOn,
	kinds = { "border", "text", "bar" } })


SW.BACKGROUND = { 0, 0, 0, 0.6 }
function SW.makeBar(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetAllPoints()
	b:SetStatusBarTexture(ns.Media.barTexture("swing"))
	b:SetMinMaxValues(0, 1)
	b:SetValue(0)
	local spark = b:CreateTexture(nil, "OVERLAY")
	spark:SetColorTexture(1, 1, 1, 0.9)
	b.spark = spark
	return b
end
function SW.styleBar(b)
	b:SetStatusBarTexture(ns.Media.barTexture("swing"))   -- global or its own; before the fill colour
	local c = cfg()
	local fromRight = (c.fillFrom == "right") ~= c.deplete
	b:SetReverseFill(fromRight)
	local fill, side = b:GetStatusBarTexture(), fromRight and "LEFT" or "RIGHT"
	b.spark:ClearAllPoints()
	b.spark:SetPoint("TOP" .. side, fill, "TOP" .. side, 0, 0)
	b.spark:SetPoint("BOTTOM" .. side, fill, "BOTTOM" .. side, 0, 0)
	b.spark:SetWidth(ns.linePx(b, 2))
end

local font = CreateFont(ns.NAME .. "SwingFont")
font:SetFont(STANDARD_TEXT_FONT, SW.DEFAULTS.countdownSize, "OUTLINE")
SW.font = font
local TEXT_SIDE = { left = "LEFT", center = "CENTER", right = "RIGHT" }
function SW.styleCountdown()
	local c = cfg()
	local k = c.countdownColor
	ns.Media.setFontObject(font, "swing", c.countdownSize)
	font:SetTextColor(k[1], k[2], k[3], k[4] or 1)
end
function SW.placeCountdown(fs, anchor)
	local side = TEXT_SIDE[cfg().countdownPos]
	fs:ClearAllPoints()
	fs:SetPoint(side, anchor, side, side == "LEFT" and 3 or side == "RIGHT" and -3 or 0, 0)
	fs:SetJustifyH(side)
end

function SW.border() return ns.Style.get("swing", "border") end

local f = CreateFrame("Frame", nil, UIParent)
f:SetSize(SW.DEFAULTS.width, SW.DEFAULTS.height)
f:Hide()
SW.frame = f
local face = CreateFrame("Frame", nil, f)
face:SetAllPoints()
face:Hide()
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
cd:SetCountdownFont(ns.NAME .. "SwingFont")
pcall(cd.SetCountdownMillisecondsThreshold, cd, 60)
local okText, cdFont = pcall(cd.GetCountdownFontString, cd)
local cdText = okText and cdFont or nil

local state = { endsAt = nil, swings = 0, secret = 0, casts = 0 }
local duration = C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()
local pv = { mode = nil, action = "swing", count = 0, nextAt = 0 }

local function fillColor()
	local c = cfg()
	if c.colorBy == "custom" then return c.color end
	local school = IMBUE_SCHOOL[ns.Imbue.mainHand() or ""]
	return school and ns.SCHOOL_BAR_COLOR[school] or NO_IMBUE
end
SW.fillColor = fillColor
local function paintFill()
	local c = fillColor()
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

local function drawFace() face:SetShown(bar:IsShown() or not ns.getAccount().locked) end

local function clearSwing()
	state.endsAt = nil
	bar:Hide()
	cd:Clear()
	drawFace()
end

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
		-- Secret: a duration object takes plain numbers only
		if isSecret(swingDuration) then state.secret = state.secret + 1 end
		clearSwing()
		return
	end
	startSwing(swingDuration)
end

-- A cast-time spell restarts the swing: clear the bar
local function onCastStart()
	state.casts = state.casts + 1
	if state.endsAt and not pv.mode then clearSwing() end
end

-- Events
local ev, listening = nil, false
local EVENTS = {
	{ "PLAYER_SWING" },
	{ "UNIT_SPELLCAST_START", "player" },
	{ "UNIT_INVENTORY_CHANGED", "player" },
	{ "PLAYER_LEAVE_COMBAT" },
	{ "PLAYER_DEAD" },
}

local function onEvent(_, event, a1, a2)
	if event == "PLAYER_SWING" then onSwing(a1, a2)
	elseif event == "UNIT_SPELLCAST_START" then onCastStart()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		paintFill()
		ns.Options.refresh()
	elseif event == "PLAYER_LEAVE_COMBAT" or event == "PLAYER_DEAD" then clearSwing()
	end
end

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

-- Visibility
local mover
local function visibilityDriver()
	if not SW.isOn() then return "hide" end
	if pv.mode then return "show" end
	if not ns.getAccount().locked then return "show" end
	if cfg().show == "combat" then return "[petbattle] hide; [combat] show; hide" end
	return "[petbattle] hide; show"
end
local lastDriver
local function drive()
	local driver = visibilityDriver()
	if driver ~= lastDriver and ns.setVisibilityDriver(f, driver, "swing timer driver") then
		lastDriver = driver
	end
end

-- Layout (out of combat)
local function layout()
	if ns.deferInCombat("swing layout", layout) then return end
	local c = cfg()
	listen(SW.isOn())
	f:SetScale(c.scale)
	f:SetAlpha(c.alpha)
	local px = ns.pixel(f)
	f:SetSize(math.max(ns.roundPx(c.width, px), px), math.max(ns.roundPx(c.height, px), px))
	ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
	ns.applyBorder(face, SW.border(), "bar")
	SW.styleBar(bar)
	paintFill()
	SW.styleCountdown()
	cd:SetCountdownFont(ns.NAME .. "SwingFont")
	cd:SetHideCountdownNumbers(not c.countdown)
	if cdText then SW.placeCountdown(cdText, face) end
	if state.endsAt then drawSwing() else drawFace() end
	drive()
	mover.update()
end

function SW.apply()
	cfgTable = nil
	layout()
end

-- Preview
local PREVIEW_SWINGS = {
	preview = { speed = 2.6 },
	warnings = { speed = 2.6 },
	busy = { speed = 1.6, swings = 2, cutAt = 0.6, gap = 1 },
}
local pvFrame = CreateFrame("Frame")
pvFrame:Hide()
pvFrame:SetScript("OnUpdate", function()
	local now = GetTime()
	if now < pv.nextAt then return end
	if not (SW.isOn() and duration) then
		pv.action, pv.count, pv.nextAt = "swing", 0, 0
		return
	end
	local p = PREVIEW_SWINGS[pv.mode]
	if pv.action == "cast" then
		clearSwing()
		pv.action, pv.count, pv.nextAt = "swing", 0, now + p.gap
		return
	end
	startSwing(p.speed)
	pv.count = pv.count + 1
	if p.swings and pv.count > p.swings then
		pv.action, pv.nextAt = "cast", now + p.speed * p.cutAt
	else
		pv.nextAt = now + p.speed
	end
end)

function SW.preview(mode)
	if mode and not PREVIEW_SWINGS[mode] then mode = nil end
	local was = pv.mode
	pv.mode, pv.action, pv.count, pv.nextAt = mode, "swing", 0, 0
	pvFrame:SetShown(mode ~= nil)
	if not mode then clearSwing() end
	if (mode ~= nil) ~= (was ~= nil) then layout() end
end

-- Positioning
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
function movable.nudge(dx, dy)
	local c = cfg()
	c.x, c.y = c.x + dx, c.y + dy
	ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
end
function movable.lock()
	mover:SetScript("OnUpdate", nil)
	mover:Hide()
	ns.Positioning.endSnap()
	drawFace()
end
ns.Positioning.addMovable(movable)

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
		mover.label:SetText("Swing timer")
	end
	mover:SetShown(on)
end

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
