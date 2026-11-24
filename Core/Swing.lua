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
	show = "swinging",   -- swinging | combat | always | never
	idle = "empty",   -- empty | full: the bar between swings, where it stays up
	point = "CENTER", x = 0, y = -251,
	width = 220, height = 7,
	scale = 1,
	alpha = 0.75,
	colorBy = COLOR_BY[1], color = { 1, 0.8, 0.25, 1 },
	fillFrom = "left",
	deplete = false,
	spark = true,
	countdown = false, countdownSize = 12, countdownColor = { 1, 1, 1, 1 },
	countdownPos = "center",
	markPos = "top",   -- top | bottom (inside the bar) | above | below (outside it)
	markSize = 0.33,   -- of the bar's height
	markColorBy = "element", markColor = { 1, 1, 1, 1 },
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
	countdownSize = { 8, 40, 1 }, markSize = { 0.1, 1, 0.01 } }
SW.RANGES = RANGES
local CHOICES = { show = { "swinging", "combat", "always", "never" }, idle = { "empty", "full" }, colorBy = COLOR_BY,
	fillFrom = { "left", "right" }, countdownPos = { "center", "left", "right" },
	markPos = { "top", "bottom", "above", "below" }, markColorBy = { "element", "custom" } }

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
-- Whether Show keeps the bar up between swings at all (In combat, Always)
local SHOWS_IDLE = { combat = true, always = true }
function SW.showsIdle() return SHOWS_IDLE[cfg().show] == true end

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
	b.spark:SetShown(c.spark)
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
-- A mark's colour: its element's, or the custom one
function SW.markColor(spec)
	local c = cfg()
	return c.markColorBy == "custom" and c.markColor or spec.color()
end
-- The pips' edge, the anchor's edge it sits on, and its gap in pixels
local MARK_AT = { top = { "TOP", "TOP", 0 }, bottom = { "BOTTOM", "BOTTOM", 0 }, above = { "BOTTOM", "TOP", 1 },
	below = { "TOP", "BOTTOM", -1 } }
-- max pips along anchor; ref: the frame its pixels are read from (else anchor), never one under
-- Blizzard's aura button
function SW.stylePips(b, anchor, max, color, ref)
	local c = cfg()
	ref = ref or anchor
	local px = W.pixel(ref)
	local at = MARK_AT[c.markPos] or MARK_AT.top
	b:ClearAllPoints()
	b:SetPoint(at[1] .. "LEFT", anchor, at[2] .. "LEFT", 0, at[3] * px)
	b:SetPoint(at[1] .. "RIGHT", anchor, at[2] .. "RIGHT", 0, at[3] * px)
	b:SetHeight(math.max(W.roundPx(c.height * c.markSize, px), 2 * px))
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
-- Between swings: the bar full, where it stays up that way
local rest = SW.makeBar(face)
rest:SetFrameLevel(face:GetFrameLevel() + 1)
rest:SetValue(1)
rest.spark:Hide()
rest:Hide()
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

local state = { endsAt = nil, attacking = false, swings = 0, secret = 0 }
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
	rest:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- Marks: each on its own aura slot over f, no picture, only the pips its button fills
local marks = {}
local function markOn(key)
	local e = E.ALL[key]
	return cfg().marks[key] == true and e.learned ~= nil and e.learned() and SW.isOn()
end
-- What a mark's pips are drawn for: the bar's size and direction, their own place and size
local function markShape()
	local c = cfg()
	return c.width .. "x" .. c.height .. c.fillFrom .. c.markPos .. c.markSize
end
-- Our frame over Blizzard's button: its opacity is ours to set in combat too. Hidden while its pips
-- wait to be drawn for the bar as it is (a restyle waits while auras are secret). A site each: a retry
-- after combat is kept by site
local function markAlpha(m) m.slot:fade(m.alphaSite, m.alpha) end
-- Made once, while it's on
local function makeMark(m)
	local slot = m.slot
	if slot.container or slot.err or not markOn(m.key) then return end
	if ns.deferWhileAurasSecret(slot.opts.sites.container, function() makeMark(m) end) then return end
	slot:setup()
	if not slot.container or slot.err then return end
	slot:styleNow()
	markAlpha(m)
end
for _, key in ipairs(MARKS) do
	local m = { key = key, alphaSite = "swing mark alpha " .. key }
	marks[key] = m
	m.alpha = function()
		return (markOn(key) and not pv.mode and face:IsShown() and m.shape == markShape()) and 1 or 0
	end
	local site, spec = "swing mark " .. key, E.ALL[key].swingMark
	m.slot = W.makeAuraSlot(f, {
		key = key, slot = "swing-" .. key, layer = f, noIcon = true, noTimer = true, noLayoutWait = true,
		size = function() return f:GetSize() end,
		levelFrom = function() return face:GetFrameLevel() end, level = 3,
		ids = spec.ids,
		sites = { container = site, style = "swing mark style " .. key, filter = "swing mark filter " .. key },
		onButton = function(_, button)
			local pips = SW.makePips(button)
			local ok = ns.try(site, button.SetApplicationBar, button, pips,
				{ minApplications = 0, maxApplications = spec.max })
			if ok then m.pips = pips else pips:Hide() end
		end,
		onStyle = function(slot)
			if m.pips then
				SW.stylePips(m.pips, slot.button, spec.max, SW.markColor(spec), f)
				m.shape = markShape()
			end
			markAlpha(m)
		end,
		onError = function(err) ns.noteError(site, err) end,
	})
end
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
			SW.stylePips(b, face, spec.max, SW.markColor(spec))
			b:SetMinMaxValues(0, spec.max)
			b:SetValue(pv.mode == "busy" and math.min(math.max(spec.max + 1 - pv.count, 1), spec.max) or spec.max)
		end
		if b then b:SetShown(shown) end
	end
end

-- Up with no swing under way
local function idleNow()
	local show = cfg().show
	return show == "always" or (show == "combat" and (ns.inCombat() or pv.mode ~= nil))
end
local function drawFace()
	local idle = idleNow()
	face:SetShown(bar:IsShown() or not P.getAccount().locked or idle)
	rest:SetShown(idle and not bar:IsShown() and cfg().idle == "full")
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

-- With auto attack off, the swing under way runs to its end, then clears
local function clearAtEnd()
	local endsAt = state.endsAt
	local left = endsAt and endsAt - GetTime()
	if not left or left <= 0 then
		clearSwing()
		return
	end
	C_Timer.After(left, function()
		if state.endsAt == endsAt and not state.attacking and not pv.mode then clearSwing() end
	end)
end

-- A weapon swap restarts the swing under way at the new weapon's speed
local function onWeaponSwap()
	if not state.endsAt or pv.mode then return end
	local speed = ns.plain(ns.safe(UnitAttackSpeed, "player"))
	if type(speed) == "number" and speed > 0 and GetTime() < state.endsAt then
		startSwing(speed)
		if not state.attacking then clearAtEnd() end
	else
		clearSwing()
	end
end

local function onAttackStop()
	state.attacking = false
	if not pv.mode then clearAtEnd() end
end

-- Events
local events, listening = nil, false   -- set(on), from start
local EVENTS = {
	{ "PLAYER_SWING" },
	{ "UNIT_INVENTORY_CHANGED", "player" },
	{ "WEAPON_SLOT_CHANGED" },
	{ "WEAPON_ENCHANT_CHANGED" },
	{ "PLAYER_ENTER_COMBAT" },
	{ "PLAYER_LEAVE_COMBAT" },
	{ "PLAYER_DEAD" },
}

local function onEvent(_, event, a1, a2)
	if event == "PLAYER_SWING" then onSwing(a1, a2)
	elseif event == "WEAPON_SLOT_CHANGED" then onWeaponSwap()
	elseif event == "UNIT_INVENTORY_CHANGED" or event == "WEAPON_ENCHANT_CHANGED" then
		paintFill()
		ns.changed()
	elseif event == "PLAYER_ENTER_COMBAT" then state.attacking = true
	elseif event == "PLAYER_LEAVE_COMBAT" then onAttackStop()
	elseif event == "PLAYER_DEAD" then clearSwing()
	end
end

local function listen(on)
	if not events or on == listening then return end
	listening = on
	events(on)
	if not on then clearSwing() end
end

-- Visibility
local movable
-- On: the frame always up, its face drawn by Show (drawFace). Off: no driver, hidden (out of combat: the layout's)
local function drive()
	local on = SW.isOn()
	ns.setVisibilityDriver(f, on and "show" or nil, "swing timer driver")
	if not on then f:Hide() end
end

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
	rest:SetStatusBarTexture(ns.Media.barTexture("swing"))
	paintFill()
	SW.styleCountdown()
	cd:SetCountdownFont(ns.NAME .. "SwingFont")
	cd:SetHideCountdownNumbers(not c.countdown)
	if cdText then SW.placeCountdown(cdText, face) end
	if state.endsAt then drawSwing() else drawFace() end
	-- A mark that's off is hidden, not only faded: a shown container still follows every aura change
	for _, m in pairs(marks) do
		makeMark(m)
		local on, slot = markOn(m.key), m.slot
		if on and m.refilterDue then
			m.refilterDue = false
			slot:refilter()
		end
		if slot.holder then slot.holder:SetShown(on) end
		slot:styleNow()
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

-- A mark that's off refilters as it's back (layout)
function SW.resolve()
	for _, m in pairs(marks) do
		m.refilterDue = not markOn(m.key)
		if not m.refilterDue then m.slot:refilter() end
	end
end

function SW.start()
	local ev = CreateFrame("Frame")
	ev:SetScript("OnEvent", onEvent)
	events = ns.eventsWhile(ev, EVENTS)
	ns.onCombatStart(drawFace)
	ns.onCombatEnd(drawFace)
end

-- /sf debug
function SW.debug()
	local left = state.endsAt and state.endsAt - GetTime()
	say("swing: %s; %d swings seen, %d with a secret duration; %s",
		listening and "on" or "off", state.swings, state.secret,
		left and (left > 0 and string.format("next in %.1f s", left) or "due") or "no swing under way")
	for _, key in ipairs(MARKS) do
		say("swing mark %s: %s, %s", key, cfg().marks[key] and "on" or "off", marks[key].slot:describe())
	end
end

Bars.register("swing", { label = "Swing timer", cfg = cfg, saved = "swingBar", defaults = SW.DEFAULTS,
	ranges = RANGES, choices = CHOICES, on = SW.isOn, parts = { "border", "text", "bar" }, movable = movable,
	hud = { show = showPreview } })
MOD.register(SW)
