-- Swing timer

local _, ns = ...
local W = ns.Widgets
local E, MOD, Bars, P = ns.Elements, ns.Modules, ns.Bars, ns.Profiles
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
for _, key in ipairs(E.KEYS) do
	if E.ALL[key].barColor then table.insert(COLOR_BY, key) end
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
-- Marks: elements offering their aura's charges as pips (an element's swingMark, main), each with a
-- switch in marks, off by default
local MARKS = {}
SW.DEFAULTS.marks = {}
for _, key in ipairs(E.KEYS) do
	if E.ALL[key].swingMark then
		table.insert(MARKS, key)
		SW.DEFAULTS.marks[key] = false
	end
end
SW.MARKS = MARKS
local RANGES = { width = { 40, 400, 4 }, height = { 4, 40, 1 }, scale = { 0.5, 3, 0.05 }, alpha = { 0.1, 1, 0.05 },
	countdownSize = { 8, 40, 1 } }
SW.RANGES = RANGES
local CHOICES = { show = { "combat", "always", "never" }, colorBy = COLOR_BY,
	fillFrom = { "left", "right" }, countdownPos = { "center", "left", "right" } }

-- What the profile's cleaning can't declare, once per saved table
local cfgTable
local function cfg()
	local t = P.getDB().swingBar
	if t ~= cfgTable then
		P.fillParts(t, SW.DEFAULTS)
		if not ns.POINTS[t.point] then t.point, t.x, t.y = SW.DEFAULTS.point, SW.DEFAULTS.x, SW.DEFAULTS.y end
		cfgTable = t
	end
	return t
end
SW.cfg = cfg

function SW.isOn() return E.isActive() and cfg().show ~= "never" end

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
	b.spark:SetWidth(W.linePx(b, 2))
end

-- Pips: a strip filled one pip a charge, a dark tick between
function SW.makePips(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(0, 0, 0, 0.5)
	b.ticks = {}
	return b
end
-- max pips along anchor's top; ref: the frame its pixels are read from (else anchor), never one under
-- Blizzard's aura button
function SW.stylePips(b, anchor, max, color, ref)
	local c = cfg()
	ref = ref or anchor
	local px = W.pixel(ref)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
	b:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
	b:SetHeight(math.max(W.roundPx(c.height / 3, px), 2 * px))
	b:SetStatusBarTexture(ns.Media.barTexture("swing"))
	b:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	b:SetReverseFill(c.fillFrom == "right")
	for i = 1, max - 1 do
		local t = b.ticks[i] or b:CreateTexture(nil, "OVERLAY")
		b.ticks[i] = t
		t:SetColorTexture(0, 0, 0, 1)
		t:ClearAllPoints()
		t:SetPoint("TOP", b, "TOPLEFT", W.roundPx(c.width * i / max, px), 0)
		t:SetPoint("BOTTOM", b, "BOTTOMLEFT", W.roundPx(c.width * i / max, px), 0)
		t:SetWidth(W.linePx(ref, 1))
		t:Show()
	end
	for i = max, #b.ticks do b.ticks[i]:Hide() end
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

function SW.border() return E.borderFor("swing") end

local f = CreateFrame("Frame", nil, Bars.parent())
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
	local e = E.ALL[c.colorBy]
	return e and e.barColor and e.barColor.color() or c.color
end
SW.fillColor = fillColor
local function paintFill()
	local c = fillColor()
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- Marks: each on its own aura container under f (shown by its state driver, never by Show in combat)
local marks = {}
local function markOn(key)
	local e = E.ALL[key]
	return cfg().marks[key] == true and e.learned ~= nil and e.learned() and SW.isOn()
end
-- What a mark's pips are drawn for: the bar's size and direction
local function markShape()
	local c = cfg()
	return c.width .. "x" .. c.height .. c.fillFrom
end
-- Our frame over Blizzard's button: its opacity is ours to set in combat too. Hidden while its pips
-- wait to be drawn for the bar as it is (a restyle waits while auras are secret)
local function markAlpha(m)
	if not m.host then return end
	local a = (markOn(m.key) and not pv.mode and face:IsShown() and m.shape == markShape()) and 1 or 0
	if not ns.try("swing mark alpha", m.host.SetAlpha, m.host, a) then
		ns.retryAfterCombat("swing mark alpha", function() markAlpha(m) end)
	end
end
-- Out of combat, auras readable
local function styleMark(m)
	if not m.container or m.err then return end
	local site = "swing mark style " .. m.key
	if ns.deferWhileAurasSecret(site, function() styleMark(m) end) then return end
	local ok = ns.try(site, function()
		local spec = E.ALL[m.key].swingMark
		m.container:SetFrameStrata(f:GetFrameStrata())
		m.container:SetFrameLevel(face:GetFrameLevel() + 3)
		if not m.button then return end
		m.button:SetSize(f:GetSize())
		if m.pips then
			SW.stylePips(m.pips, m.button, spec.max, spec.color(), f)
			m.shape = markShape()
		end
	end)
	if not ok then ns.retryAfterCombat(site, function() styleMark(m) end) end
	markAlpha(m)
end
-- Blizzard's button: no picture of its own, only the pips it fills
local function initMark(m, button)
	W.noMouse(button)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	m.button = button
	local pips = SW.makePips(button)
	if ns.try("swing mark " .. m.key, button.SetApplicationBar, button, pips,
		{ minApplications = 0, maxApplications = E.ALL[m.key].swingMark.max }) then m.pips = pips
	else pips:Hide() end
	styleMark(m)
end
-- Made once, while it's on
local function makeMark(m)
	if m.container or m.err or not markOn(m.key) then return end
	local site = "swing mark " .. m.key
	if ns.deferWhileAurasSecret(site, function() makeMark(m) end) then return end
	local ok, err = pcall(function()
		m.host = CreateFrame("Frame", nil, f)
		m.host:SetAllPoints(f)
		local c = CreateFrame("AuraContainer", nil, m.host, "CustomAuraContainerTemplate")
		m.container = c
		c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)
		c:AddAuraSlot("swing-" .. m.key, "HELPFUL", {
			candidateFilters = { includeSpellIDs = E.ALL[m.key].swingMark.ids() },
			initializeFrame = function(button) ns.try(site .. " button", initMark, m, button) end })
	end)
	if not ok then
		m.err = tostring(err)
		if m.container then m.container:Hide() end
		ns.noteError(site, m.err)
		return
	end
	styleMark(m)
	markAlpha(m)
end
for _, key in ipairs(MARKS) do marks[key] = { key = key } end
-- /sf preview: our own pips in place of the button's while a mark is on: full, or in Busy one spent
-- a swing. A mark not learned too, with Show not learned
local pvPips = {}
local function previewMarks()
	for _, key in ipairs(MARKS) do
		local e = E.ALL[key]
		local learned = e.learned ~= nil and e.learned()
		local shown = pv.mode ~= nil and cfg().marks[key] == true and SW.isOn()
			and (learned or ns.Preview.showsUnlearned())
		local b = pvPips[key]
		if shown and not b then
			b = SW.makePips(face)
			b:SetFrameLevel(face:GetFrameLevel() + 3)
			pvPips[key] = b
		end
		if shown then
			local spec = E.ALL[key].swingMark
			SW.stylePips(b, face, spec.max, spec.color())
			b:SetMinMaxValues(0, spec.max)
			b:SetValue(pv.mode == "busy" and math.min(math.max(spec.max + 1 - pv.count, 1), spec.max) or spec.max)
		end
		if b then b:SetShown(shown) end
	end
end

local function drawFace()
	face:SetShown(bar:IsShown() or not P.getAccount().locked)
	for _, m in pairs(marks) do markAlpha(m) end
end

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
	if not P.getAccount().locked then return "show" end
	return Bars.SHOW_WHEN[cfg().show] or "show"
end
local function drive() ns.setVisibilityDriver(f, visibilityDriver(), "swing timer driver") end

-- Layout (out of combat)
local function layout()
	if ns.deferInCombat("swing layout", layout) then return end
	local c = cfg()
	listen(SW.isOn())
	f:SetScale(c.scale)
	f:SetAlpha(c.alpha)
	local px = W.pixel(f)
	f:SetSize(math.max(W.roundPx(c.width, px), px), math.max(W.roundPx(c.height, px), px))
	W.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
	ns.StyleArt.applyBorder(face, SW.border(), "bar")
	SW.styleBar(bar)
	paintFill()
	SW.styleCountdown()
	cd:SetCountdownFont(ns.NAME .. "SwingFont")
	cd:SetHideCountdownNumbers(not c.countdown)
	if cdText then SW.placeCountdown(cdText, face) end
	if state.endsAt then drawSwing() else drawFace() end
	for _, m in pairs(marks) do
		makeMark(m)
		styleMark(m)
		markAlpha(m)
	end
	previewMarks()
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
	previewMarks()
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
	lock = drawFace,
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
	for _, key in ipairs(MARKS) do
		local m = marks[key]
		say("swing mark %s: %s, container %s%s", key, cfg().marks[key] and "on" or "off",
			m.container and "made" or "not made", m.err and (", error: " .. m.err) or "")
	end
end

Bars.register("swing", { label = "Swing timer", cfg = cfg, saved = "swingBar", defaults = SW.DEFAULTS,
	ranges = RANGES, choices = CHOICES, on = SW.isOn, parts = { "border", "text", "bar" }, movable = movable,
	hud = { show = showPreview } })
MOD.register(SW)
