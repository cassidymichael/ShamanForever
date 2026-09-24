-- Timers: one way to show a duration everywhere (design: workspace design/timers.md).
--
-- A timer has three parts, each on or off: countdown text, swipe and time bar. There are two kinds:
-- "cooldown" (a spell not ready yet) and "uptime" (a totem, shield or imbue running, "Time left"
-- in the UI). General holds a style for each kind (db.timers); an element, or the totem bar, can
-- have its own (elementOpts(key).timers[kind], db.totemBar.timers[kind]) or follow General.
--
-- Every timer is fed a duration object, so nothing here reads a time: Cooldown and StatusBar take
-- the object, and the bar's "run out" alpha comes from a curve (secret values go straight to
-- SetAlpha). Plain times (the imbue) become a duration object through C_DurationUtil.

local _, ns = ...

local T = {}
ns.Timer = T

T.KINDS = { "cooldown", "uptime" }
T.DEFAULTS = {
	cooldown = {
		text = true, textSize = 16, textColor = { 1, 1, 1, 1 }, textPos = "center", abbrev = 0,
		swipe = true, swipeAlpha = 0.65, swipeReverse = false,
		bar = false, barHeight = 8, barElement = true, barColor = { 0.9, 0.8, 0.3, 1 }, barEdge = "top",
	},
	uptime = {
		text = true, textSize = 12, textColor = { 0.5, 1, 0.4, 1 }, textPos = "auto", abbrev = 0,
		swipe = false, swipeAlpha = 0.6, swipeReverse = true,
		bar = true, barHeight = 8, barElement = true, barColor = { 0.4, 0.9, 0.3, 1 }, barEdge = "bottom",
	},
}
-- Elements that look different from General until the player says otherwise: applied over
-- General's style, and they do not follow it by default.
T.ELEMENT_DEFAULTS = {
	shield = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	imbue = { uptime = { text = true, textSize = 16, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = false } },
	-- The cooldown's number is enough text on these; their time left shows as the bar alone.
	earthbind = { uptime = { text = false } },
	stoneclaw = { uptime = { text = false } },
}
-- Parts the game cannot do for an element, and why (shown on its page).
T.CANT = {
	shield = { bar = "The shield's timer is Blizzard's own; a time bar can't follow it." },
}

local WHITE = "Interface\\Buttons\\WHITE8x8"
local TIMER_REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local TIMER_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0

local function isColor(v) return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" end

-- A clean copy of t: every field of def, taken from t where it has the right type.
local function clean(t, def)
	local out = {}
	for k, v in pairs(def) do
		local x = type(t) == "table" and t[k]
		if type(v) == "table" then out[k] = isColor(x) and { x[1], x[2], x[3], x[4] or 1 } or CopyTable(v)
		elseif type(x) == type(v) then out[k] = x
		else out[k] = v end
	end
	return out
end
T.clean = clean

-- General's style for a kind.
function T.general(kind)
	local db = ns.getDB()
	if type(db.timers) ~= "table" then db.timers = {} end
	return clean(db.timers[kind], T.DEFAULTS[kind])
end

-- The stored style of an element (or "totembar") for a kind; nil if it has none.
function T.override(key, kind, create)
	local holder
	if key == "totembar" then holder = ns.TotemBar and ns.TotemBar.cfg()
	else holder = ns.elementOpts(key) end
	if not holder then return nil end
	if type(holder.timers) ~= "table" then
		if not create then return nil end
		holder.timers = {}
	end
	local o = holder.timers[kind]
	if type(o) ~= "table" then
		if not create then return nil end
		o = {}
		holder.timers[kind] = o
	end
	return o
end

-- Whether an element's timer follows General.
function T.follows(key, kind)
	local o = T.override(key, kind)
	if o and type(o.follow) == "boolean" then return o.follow end
	return not (T.ELEMENT_DEFAULTS[key] and T.ELEMENT_DEFAULTS[key][kind])
end

-- An element's own style before any change: General with the element's defaults on top.
local function base(key, kind)
	local s = T.general(kind)
	local d = T.ELEMENT_DEFAULTS[key] and T.ELEMENT_DEFAULTS[key][kind]
	if d then for k, v in pairs(d) do s[k] = type(v) == "table" and CopyTable(v) or v end end
	return s
end

-- The style an element's timer uses now.
function T.style(key, kind)
	if T.follows(key, kind) then return T.general(kind) end
	return clean(T.override(key, kind), base(key, kind))
end

-- Stop following General: the element keeps the look it has now, as its own. Follow again: its
-- own values are kept for later.
function T.setFollow(key, kind, follow)
	local start = base(key, kind)   -- General's, with the element's own defaults on top
	local o = T.override(key, kind, true)
	if not follow then for k, v in pairs(start) do if o[k] == nil then o[k] = type(v) == "table" and CopyTable(v) or v end end end
	o.follow = follow
end

-- Change one part of a style: General's (key nil) or an element's own.
function T.set(key, kind, field, value)
	if not key then
		local db = ns.getDB()
		if type(db.timers) ~= "table" then db.timers = {} end
		db.timers[kind] = clean(db.timers[kind], T.DEFAULTS[kind])
		db.timers[kind][field] = value
		return
	end
	T.setFollow(key, kind, false)
	T.override(key, kind, true)[field] = value
end

------------------------------------------------------------------------
-- The widget
------------------------------------------------------------------------
-- Remaining time -> 0 once run out: an expired duration object can linger on the bar.
local liveCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
	liveCurve = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then liveCurve:SetType(Enum.LuaCurveType.Linear) end
	liveCurve:AddPoint(0, 0)
	liveCurve:AddPoint(0.05, 1)
end

local Timer = {}
Timer.__index = Timer
local fonts = 0

-- parent: frame the parts go on; opts:
--   anchor = the icon the parts cover (default parent)
--   cd     = an existing Cooldown to use (its frame level is kept)
--   dual   = the icon also shows the other kind of timer ("auto" text then goes top-left)
--   school = colour for "element colour" bars (a key of ns.Look.SCHOOL), or a function returning one
--   noBar  = never make a bar (Blizzard's shield button: no frames of ours created in its callback)
function T.new(parent, key, kind, opts)
	opts = opts or {}
	local t = setmetatable({ key = key, kind = kind, anchor = opts.anchor or parent, dual = opts.dual, school = opts.school }, Timer)
	local cd = opts.cd
	if not cd then
		cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
		cd:SetAllPoints(t.anchor)
	end
	cd:SetDrawEdge(false)
	cd:SetDrawBling(kind == "cooldown")   -- the ready flash, as cooldowns always had
	cd:SetSwipeTexture(WHITE)   -- square, so a cropped icon has no bright sliver at the edge
	t.cd = cd
	fonts = fonts + 1
	t.fontName = "ShamanForeverTimerFont" .. fonts
	t.font = CreateFont(t.fontName)
	t.font:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	cd:SetCountdownFont(t.fontName)
	local ok, fs = pcall(cd.GetCountdownFontString, cd)
	if ok and fs then
		t.fs = fs
		pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
	end
	if not opts.noBar then
		local bar = CreateFrame("StatusBar", nil, parent)
		bar:SetStatusBarTexture(WHITE)
		bar:SetFrameLevel(cd:GetFrameLevel() + 1)
		bar.bg = bar:CreateTexture(nil, "BACKGROUND")
		bar.bg:SetAllPoints()
		bar.bg:SetColorTexture(0, 0, 0, 0.6)
		bar:Hide()
		t.bar = bar
	end
	return t
end

local function schoolColor(t)
	local school = type(t.school) == "function" and t.school() or t.school
	local c = school and ns.Look and ns.Look.SCHOOL[school]
	return c or { 0.4, 0.9, 0.3 }
end

-- Takes the current style. Safe any time for our own frames; the shield's Cooldown is restyled
-- only out of combat by its caller.
function Timer:apply()
	local s = T.style(self.key, self.kind)
	local cant = T.CANT[self.key] or {}
	self.s = s
	local cd = self.cd
	cd:SetDrawSwipe(s.swipe and not cant.swipe)
	cd:SetSwipeColor(0, 0, 0, s.swipeAlpha)
	cd:SetReverse(s.swipeReverse)
	cd:SetHideCountdownNumbers(not s.text or cant.text ~= nil)
	-- Minutes read "2m"; under abbrev seconds they read "1:31" (0: never). Under a minute the client
	-- always shows plain seconds.
	pcall(cd.SetCountdownAbbrevThreshold, cd, s.abbrev)
	local c = self.tint or s.textColor
	self.font:SetFont(STANDARD_TEXT_FONT, s.textSize, "OUTLINE")
	self.font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	cd:SetCountdownFont(self.fontName)
	self.barOn = self.bar ~= nil and s.bar and not cant.bar
	local bar = self.bar
	if bar then
		local a = self.anchor
		bar:ClearAllPoints()
		bar:SetHeight(s.barHeight)
		if s.barEdge == "top" then
			bar:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
		else
			bar:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
		end
		local col = s.barElement and schoolColor(self) or s.barColor
		bar:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
		if not self.barOn then bar:Hide() end
	end
	if self.last then self:set(self.last) end   -- show a part just turned on, at once
	local fs = self.fs
	if fs then
		local pos = s.textPos
		if pos == "auto" then pos = (self.dual and self.kind == "uptime") and "topleft" or "center" end
		local a = self.anchor
		fs:ClearAllPoints()
		if pos == "topleft" then
			local y = (self.barOn and s.barEdge == "top") and -(s.barHeight + 1) or -1
			fs:SetPoint("TOPLEFT", a, "TOPLEFT", 1, y); fs:SetJustifyH("LEFT")
		elseif pos == "bottom" then
			local y = (self.barOn and s.barEdge == "bottom") and (s.barHeight + 1) or 1
			fs:SetPoint("BOTTOM", a, "BOTTOM", 0, y); fs:SetJustifyH("CENTER")
		else
			fs:SetPoint("CENTER", a, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
		end
	end
end

-- A text colour for now (the imbue's red last minute); nil goes back to the style's.
function Timer:setTint(r, g, b)
	self.tint = r and { r, g, b, 1 } or nil
	local c = self.tint or (self.s and self.s.textColor) or { 1, 1, 1, 1 }
	self.font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Show a duration object, or clear with nil.
function Timer:set(d)
	if not d then return self:clear() end
	self.last = d
	pcall(self.cd.SetCooldownFromDurationObject, self.cd, d, true)
	local bar = self.bar
	if bar and self.barOn then
		pcall(bar.SetTimerDuration, bar, d, TIMER_IMMEDIATE, TIMER_REMAINING)
		if liveCurve then
			local ok, a = pcall(d.EvaluateRemainingDuration, d, liveCurve)
			if ok then bar:SetAlpha(a) else bar:SetAlpha(1) end
		end
		bar:Show()
	elseif bar then bar:Hide() end
end

-- Show a plain time span (start and length in seconds, GetTime's clock).
function Timer:setTime(start, length)
	if C_DurationUtil and C_DurationUtil.CreateDuration then
		self.own = self.own or C_DurationUtil.CreateDuration()
		local ok = pcall(self.own.SetTimeFromStart, self.own, start, length)
		if ok then return self:set(self.own) end
	end
	self.cd:SetCooldown(start, length)
	if self.bar and self.barOn then
		self.bar:SetMinMaxValues(0, length)
		self.bar:SetValue(math.max(start + length - GetTime(), 0))
		self.bar:SetAlpha(1)
		self.bar:Show()
	end
end

function Timer:clear()
	self.last = nil
	self.cd:Clear()
	if self.bar then self.bar:Hide() end
end

-- A frozen picture for the options previews: frac of the time gone, of a span `length` long.
function Timer:static(frac, length)
	length = length or 30
	self.cd:SetCooldown(GetTime() - frac * length, length)
	pcall(self.cd.Pause, self.cd)
	if self.bar then
		self.bar:SetMinMaxValues(0, 1)
		self.bar:SetValue(1 - frac)
		self.bar:SetAlpha(1)
		self.bar:SetShown(self.barOn)
	end
end
