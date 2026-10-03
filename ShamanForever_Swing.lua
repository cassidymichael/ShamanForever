-- Swing timer

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local SW = { name = "swing" }
ns.Swing = SW

local MAIN_HAND = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local ELAPSED = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING, IMMEDIATE = ns.Timer.AURA_BAR.direction, ns.Timer.AURA_BAR.interpolation
SW.ICON = Spells.icon("attack") or 135274

-- Colour: custom, or an element's that offers one to a bar (its barColor), the first by default:
-- only elements whose files load before this one (TOC order)
local COLOR_BY = {}
for _, key in ipairs(ns.ELEMENT_KEYS) do
	if ns.ELEMENTS[key].barColor then table.insert(COLOR_BY, key) end
end
table.insert(COLOR_BY, "custom")
SW.COLOR_BY = COLOR_BY

-- Settings
SW.DEFAULTS = {
	show = "combat",   -- combat | always | never
	point = "CENTER", x = 0, y = -251,
	width = 220, height = 7,
	scale = 1,
	alpha = 0.75,
	colorBy = COLOR_BY[1], color = { 1, 0.8, 0.25, 1 },
	fillFrom = "left",
	deplete = false,
	countdown = false, countdownSize = 12, countdownColor = { 1, 1, 1, 1 },
	countdownPos = "center",
}
local RANGES = { width = { 40, 400, 4 }, height = { 4, 40, 1 }, scale = { 0.5, 3, 0.05 }, alpha = { 0.1, 1, 0.05 },
	countdownSize = { 8, 40, 1 } }
SW.RANGES = RANGES
local CHOICES = { show = { "combat", "always", "never" }, colorBy = COLOR_BY,
	fillFrom = { "left", "right" }, countdownPos = { "center", "left", "right" } }

-- What the profile's cleaning can't declare, once per saved table
local cfgTable
local function cfg()
	local t = ns.getDB().swingBar
	if t ~= cfgTable then
		ns.fillDefaults(t, SW.DEFAULTS)
		if not ns.POINTS[t.point] then t.point, t.x, t.y = SW.DEFAULTS.point, SW.DEFAULTS.x, SW.DEFAULTS.y end
		cfgTable = t
	end
	return t
end
SW.cfg = cfg

function SW.isOn() return ns.isActive() and cfg().show ~= "never" end

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
	ns.Media.setFont(font, "swing", c.countdownSize)
	font:SetTextColor(k[1], k[2], k[3], k[4] or 1)
end
function SW.placeCountdown(fs, anchor)
	local side = TEXT_SIDE[cfg().countdownPos]
	fs:ClearAllPoints()
	fs:SetPoint(side, anchor, side, side == "LEFT" and 3 or side == "RIGHT" and -3 or 0, 0)
	fs:SetJustifyH(side)
end

function SW.border() return ns.borderFor("swing") end

local f = CreateFrame("Frame", nil, UIParent)
f:SetSize(SW.DEFAULTS.width, SW.DEFAULTS.height)
f:Hide()
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
	local e = ns.ELEMENTS[c.colorBy]
	return e and e.barColor and e.barColor.color() or c.color
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
		ns.changed()
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
local movable
local function visibilityDriver()
	if not SW.isOn() then return "hide" end
	if pv.mode then return "show" end
	if not ns.getAccount().locked then return "show" end
	return ns.Bars.SHOW_WHEN[cfg().show] or "show"
end
local function drive() ns.setVisibilityDriver(f, visibilityDriver(), "swing timer driver") end

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
	ns.Looks.applyBorder(face, SW.border(), "bar")
	SW.styleBar(bar)
	paintFill()
	SW.styleCountdown()
	cd:SetCountdownFont(ns.NAME .. "SwingFont")
	cd:SetHideCountdownNumbers(not c.countdown)
	if cdText then SW.placeCountdown(cdText, face) end
	if state.endsAt then drawSwing() else drawFace() end
	drive()
	movable.update()
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

-- opts: the preview's (its mode); nil as it ends
local function showPreview(opts)
	local mode = opts and opts.mode
	if mode and not PREVIEW_SWINGS[mode] then mode = nil end
	local was = pv.mode
	pv.mode, pv.action, pv.count, pv.nextAt = mode, "swing", 0, 0
	pvFrame:SetShown(mode ~= nil)
	if not mode then clearSwing() end
	if (mode ~= nil) ~= (was ~= nil) then layout() end
end

-- Positioning
movable = ns.Positioning.mover({ frame = f, label = "Swing timer", cfg = cfg, ranges = RANGES,
	size = { key = "width", step = 4 }, shown = SW.isOn, place = layout,
	open = function() ns.Options.open("swing") end, lock = drawFace,
	describe = function()
		local c = cfg()
		return string.format("Swing timer: %d x %d, scale %.2f, opacity %.0f%%", c.width, c.height, c.scale,
			c.alpha * 100)
	end })

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

ns.registerBar("swing", { label = "Swing timer", cfg = cfg, saved = "swingBar", defaults = SW.DEFAULTS,
	ranges = RANGES, choices = CHOICES, on = SW.isOn, kinds = { "border", "text", "bar" }, movable = movable,
	hud = { show = showPreview } })
ns.registerModule(SW)
