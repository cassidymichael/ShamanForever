-- Timers
-- Fed duration objects, so nothing here reads a time: secret values go straight to widgets and curves.

local _, ns = ...

local T = {}
ns.Timer = T

T.KINDS = { "cooldown", "uptime" }
-- Tenths: seconds below which the countdown shows tenths (0: never)
local function timeColors()
	return {
		timeColors = false, soon = 10, soonColor = { 1, 0.85, 0.1, 1 }, now = 3, nowColor = { 1, 0.25, 0.2, 1 },
		tenths = 0,
	}
end
T.DEFAULTS = {
	cooldown = {
		text = true, textSize = 18, textColor = { 1, 1, 1, 1 }, textPos = "center", abbrev = 0,
		swipe = true, swipeAlpha = 0.65, swipeReverse = false,
		bar = false, barHeight = 8, barElement = true, barColor = { 1, 0.9, 0.35, 1 }, barEdge = "top",
	},
	uptime = {
		text = true, textSize = 12, textColor = { 0.5, 1, 0.4, 1 }, textPos = "auto", abbrev = 0,
		swipe = false, swipeAlpha = 0.6, swipeReverse = true,
		bar = true, barHeight = 8, barElement = true, barColor = { 0.46, 1, 0.35, 1 }, barEdge = "bottom",
	},
}
for _, kind in ipairs(T.KINDS) do
	for k, v in pairs(timeColors()) do T.DEFAULTS[kind][k] = v end
end
-- Parts an element's timer can't have, and why (shown on its page); filled as elements register
T.CANT = {}
function T.cant(key, kind)
	local c, out = key and T.CANT[key], {}
	if not c then return out end
	for k, v in pairs(c) do if type(v) == "string" then out[k] = v end end
	if type(c[kind]) == "table" then for k, v in pairs(c[kind]) do out[k] = v end end
	return out
end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local TIMER_REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local TIMER_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
T.AURA_BAR = { interpolation = TIMER_IMMEDIATE, direction = TIMER_REMAINING }

-- abbrev: seconds under which minutes read 1:31 (0: never)
local RANGES = { textSize = { 6, 48, 1 }, abbrev = { 0, 3600, 60 }, swipeAlpha = { 0.1, 1, 0.05 },
	barHeight = { 1, 20, 1 }, soon = { 1, 60, 1 }, now = { 1, 60, 1 }, tenths = { 0, 10, 1 } }
local NAMES = { cooldown = { "Cooldown timer", "cooldown", 1 }, uptime = { "Time left timer", "time left", 2 } }
local S = ns.Style
for _, kind in ipairs(T.KINDS) do
	S.register(kind, { defaults = T.DEFAULTS[kind], ranges = RANGES, path = { "timers", kind }, elements = true,
		label = NAMES[kind][1], short = NAMES[kind][2], order = NAMES[kind][3] })
end

-- The countdown's formatter
-- A numeric rule formatter handed to the Cooldown colours by time left inside the engine, so it
-- follows secret durations. It replaces the Cooldown's own formatting: its rules repeat the Time
-- format. Everything rounds up.
local ROUND_UP = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1

local function secsIn(v, field)
	local r = RANGES[field]
	if type(v) ~= "number" or v ~= v then return r[1] end
	return math.min(math.max(v, r[1]), r[2])
end

local function formatRules(abbrev, tenths)
	local rules = {}
	if tenths > 0 then
		table.insert(rules, { threshold = 0, format = "%.1f", step = 0.1, rounding = ROUND_UP })
		table.insert(rules, { threshold = tenths, format = "%d", step = 1, rounding = ROUND_UP })
	else
		table.insert(rules, { threshold = 0, format = "%d", step = 1, rounding = ROUND_UP })
	end
	if abbrev > 60 then
		table.insert(rules, { threshold = 60, format = "%d:%02d", step = 1, rounding = ROUND_UP,
			components = { { div = 60 }, { mod = 60 } } })
	end
	table.insert(rules, { threshold = math.max(abbrev, 60), format = "%dm", rounding = ROUND_UP,
		components = { { div = 60, step = 1, rounding = ROUND_UP } } })
	table.insert(rules, { threshold = 3600, format = "%dh", rounding = ROUND_UP,
		components = { { div = 3600, step = 1, rounding = ROUND_UP } } })
	return rules
end

local function colorCode(c)
	local function byte(v) return math.floor(math.min(math.max(v, 0), 1) * 255 + 0.5) end
	return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

local function breakpoints(s, abbrev, tenths)
	local rules = formatRules(abbrev, tenths)
	local soon, now = secsIn(s.soon, "soon"), secsIn(s.now, "now")
	local soonCode, nowCode = colorCode(s.soonColor), colorCode(s.nowColor)
	local cuts, list = {}, {}
	for _, r in ipairs(rules) do cuts[r.threshold] = true end
	if s.timeColors then cuts[soon], cuts[now] = true, true end
	for t in pairs(cuts) do table.insert(list, t) end
	table.sort(list)
	local out = {}
	for _, t in ipairs(list) do
		local rule
		for _, r in ipairs(rules) do if r.threshold <= t then rule = r end end
		local code = s.timeColors and (t < now and nowCode or t < soon and soonCode) or nil
		table.insert(out, {
			threshold = t, step = rule.step, rounding = rule.rounding, components = rule.components,
			format = code and (code .. rule.format .. "|r") or rule.format,
		})
	end
	return out
end

-- One formatter per look; a timer keeps its own, so dropping the cache never frees one in use
local formatters, cached = {}, 0
local function formatterFor(s)
	if not s.timeColors then return nil end
	local tenths = math.floor(secsIn(s.tenths, "tenths"))
	local abbrev = secsIn(s.abbrev, "abbrev")
	local key = string.format("%s|%d|%d|%s|%s|%s|%s", tostring(s.timeColors), abbrev, tenths,
		tostring(s.soon), tostring(s.now), colorCode(s.soonColor), colorCode(s.nowColor))
	local f = formatters[key]
	if f == nil then
		local ok, made = pcall(function()
			local fm = C_StringUtil.CreateNumericRuleFormatter()
			fm:SetBreakpoints(breakpoints(s, abbrev, tenths))
			return fm
		end)
		if not ok then ns.noteError("timer formatter", made) end
		if cached >= 32 then wipe(formatters); cached = 0 end
		f = ok and made or false
		formatters[key], cached = f, cached + 1
	end
	return f or nil
end

-- The widget
local Timer = {}
Timer.__index = Timer
local fonts = 0

-- opts: anchor, cd (an existing Cooldown), dual, school, aura (on Blizzard's aura button: it
-- drives the bar, so it is never fed a duration here), barInset
function T.new(parent, key, kind, opts)
	opts = opts or {}
	local t = setmetatable({ key = key, kind = kind, parent = parent, anchor = opts.anchor or parent, dual = opts.dual,
		school = opts.school, aura = opts.aura, barInset = opts.barInset }, Timer)
	local cd = opts.cd
	if not cd then
		cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
		cd:SetAllPoints(t.anchor)
	end
	cd:SetDrawEdge(false)
	cd:SetDrawBling(kind == "cooldown")
	cd:SetSwipeTexture(WHITE)
	t.cd = cd
	fonts = fonts + 1
	t.fontName = ns.NAME .. "TimerFont" .. fonts
	t.font = CreateFont(t.fontName)
	t.font:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	cd:SetCountdownFont(t.fontName)
	local ok, fs = pcall(cd.GetCountdownFontString, cd)
	if ok and fs then
		t.fs = fs
		pcall(fs.SetDrawLayer, fs, "OVERLAY", 7)
	end
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(WHITE)
	bar:SetFrameLevel(cd:GetFrameLevel() + 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	bar:Hide()
	t.bar = bar
	return t
end

local function schoolColor(t)
	local school = type(t.school) == "function" and t.school() or t.school
	local c = school and ns.THEME.barColor[school]
	return c or { 0.46, 1, 0.35 }
end

-- Safe any time for our own frames; the shield's Cooldown is restyled out of combat only by its caller
function Timer:apply()
	local s = S.get(self.key, self.kind)
	local cant = T.cant(self.key, self.kind)
	local cd = self.cd
	cd:SetDrawSwipe(s.swipe and not cant.swipe)
	cd:SetSwipeColor(0, 0, 0, s.swipeAlpha)
	cd:SetReverse(s.swipeReverse)
	cd:SetHideCountdownNumbers(not s.text or cant.text ~= nil)
	pcall(cd.SetCountdownAbbrevThreshold, cd, s.abbrev)
	local text = s.text and not cant.text
	local fm = text and formatterFor(s) or nil
	if fm ~= self.formatter then
		self.formatter = fm
		ns.try("timer formatter", cd.SetCountdownFormatter, cd, fm)
	end
	local ms = (text and not fm) and math.floor(secsIn(s.tenths, "tenths")) or 0
	if ms ~= (self.ms or 0) then
		self.ms = ms
		pcall(cd.SetCountdownMillisecondsThreshold, cd, ms)
	end
	local c = s.textColor
	ns.Media.setFontObject(self.font, self.key, s.textSize)
	self.font:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	cd:SetCountdownFont(self.fontName)
	self.barOn = self.bar ~= nil and s.bar and not cant.bar
	local bar = self.bar
	if bar then
		local a = self.anchor
		bar:ClearAllPoints()
		bar:SetHeight(s.barHeight)
		bar:SetStatusBarTexture(ns.Media.barTexture(self.key))
		if s.barEdge == "top" then
			bar:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0); bar:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
		else
			local y = self.barInset and self.barInset() or 0
			bar:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, y); bar:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, y)
		end
		local col = s.barElement and schoolColor(self) or s.barColor
		bar:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
		if self.aura then bar:SetShown(self.barOn)
		elseif not self.barOn then bar:Hide() end
	end
	if self.last then self:set(self.last) end
	if self.fs then
		T.placeText(self.fs, self.anchor, s, self.barOn, self.dual and self.kind == "uptime")
	end
end

-- The countdown's place on anchor for timer style s, clear of a bar; dual: an uptime sharing its
-- icon with a cooldown
function T.placeText(fs, anchor, s, barOn, dual)
	local pos = s.textPos
	if pos == "auto" then pos = dual and "topleft" or "center" end
	fs:ClearAllPoints()
	if pos == "topleft" then
		local y = (barOn and s.barEdge == "top") and -(s.barHeight + 1) or -1
		fs:SetPoint("TOPLEFT", anchor, "TOPLEFT", 1, y); fs:SetJustifyH("LEFT")
	elseif pos == "bottom" then
		local y = (barOn and s.barEdge == "bottom") and (s.barHeight + 1) or 1
		fs:SetPoint("BOTTOM", anchor, "BOTTOM", 0, y); fs:SetJustifyH("CENTER")
	else
		fs:SetPoint("CENTER", anchor, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
	end
end

function Timer:barRGB()
	local s = S.get(self.key, self.kind)
	return s.barElement and schoolColor(self) or s.barColor
end

function Timer:set(d)
	if not d then return self:clear() end
	self.last, self.held = d, nil
	ns.try("timer cooldown", self.cd.SetCooldownFromDurationObject, self.cd, d, true)
	local bar = self.bar
	if bar and self.barOn then
		ns.try("timer bar", bar.SetTimerDuration, bar, d, TIMER_IMMEDIATE, TIMER_REMAINING)
		-- 0 once run out: an expired duration object can linger on the bar
		if ns.CURVE_LIVE then
			local ok, a = ns.try("timer bar alpha", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
			if ok then bar:SetAlpha(a) else bar:SetAlpha(1) end
		end
		bar:Show()
	elseif bar then bar:Hide() end
end

function Timer:setTime(start, length)
	self.held = nil
	if C_DurationUtil and C_DurationUtil.CreateDuration then
		self.own = self.own or C_DurationUtil.CreateDuration()
		local ok = ns.try("timer time", self.own.SetTimeFromStart, self.own, start, length)
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
	self.last, self.held = nil, nil
	if self.exp then self.exp:SetAlpha(0) end
	self.cd:Clear()
	if self.bar then self.bar:Hide() end
end

-- Frozen frac of the way through; a setExpire after it lights the warning if the time held is in it
function Timer:static(frac, length)
	length = length or 30
	self.last, self.held = nil, (1 - frac) * length
	self.cd:SetCooldown(GetTime() - frac * length, length)
	pcall(self.cd.Pause, self.cd)
	if self.bar then
		self.bar:SetMinMaxValues(0, 1)
		self.bar:SetValue(1 - frac)
		self.bar:SetAlpha(1)
		self.bar:SetShown(self.barOn)
	end
end

-- Expiring: a warning over the icon in a timer's last seconds. Its alpha is the time left through
-- a curve, evaluated ten times a second, so it works in combat.
local warning = {}
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", ns.throttled(0.1, function()
	for t in pairs(warning) do
		local d = t.last
		if d then
			-- pcall, not ns.try: ten times a second, must not allocate
			local ok, a = pcall(d.EvaluateRemainingDuration, d, t.expCurve)
			if ok then t.exp:SetAlpha(a) else t.exp:SetAlpha(0); ns.noteError("timer expiring", a) end
		elseif not t.held then t.exp:SetAlpha(0) end
	end
end))

-- The expire part (ns.registerPart): Expiring's settings for a kind that sets def.expires,
-- def.expireLooks (the looks it offers; default all) and def.expireRange (Warn in the last)
local EXPIRE = { secs = 5, grey = false, ring = false, fade = true, glow = false }
local EXPIRE_LOOKS = { "grey", "ring", "fade", "glow" }
ns.registerPart("expire", {
	kinds = { cooldown = {}, buff = {} },
	has = function(def) return def.expires end,
	defaults = function(def)
		local e = { secs = EXPIRE.secs }
		for _, look in ipairs(def.expireLooks or EXPIRE_LOOKS) do e[look] = EXPIRE[look] end
		return { expire = e }
	end,
	ranges = function(def) return { expire = { secs = def.expireRange or { 0, 30, 1 } } } end,
	glow = function(def) return def.defaults.expire.glow ~= nil end,
})

-- e: { secs, grey, ring, fade, glow } (secs 0: off), an element's or the totem bar's expire
function Timer:setExpire(e, icon)
	if not e or (e.secs or 0) <= 0 or not ns.lastSeconds(e.secs) then
		warning[self] = nil
		if next(warning) == nil then ticker:Hide() end
		local x = self.exp
		if x then
			x:SetAlpha(0)
			x.pulseOn = false
			x.pulse:Stop(); x.dim:SetAlpha(0)
			x.glow:Hide()
		end
		return
	end
	local x = self.exp
	if not x then
		x = CreateFrame("Frame", nil, self.parent)
		x:SetAllPoints(self.anchor)
		x:SetFrameLevel(self.anchor:GetFrameLevel() + (self.over or 1))
		x:SetAlpha(0)
		x.grey = x:CreateTexture(nil, "ARTWORK")
		x.grey:SetAllPoints()
		ns.cropIconExact(x.grey)
		x.grey:SetDesaturated(true)
		x.ring = ns.makeRing(x, x)
		x.dim = x:CreateTexture(nil, "OVERLAY")
		x.dim:SetAllPoints()
		x.dim:SetColorTexture(0, 0, 0, 1)
		x.dim:SetAlpha(0)
		x.pulse = ns.makePulse(x.dim, "dim")
		-- A hidden ancestor stops the pulse: start it again on show
		x:SetScript("OnShow", function(s) if s.pulseOn then s.pulse:Play() end end)
		x.glow = ns.Effects.glow(x, self.anchor, self.key)
		self.exp = x
		ns.Looks.followMask(self.anchor, x.grey, x.dim)
	end
	x.glow:fit(self.anchor:GetWidth())
	-- A look the owner doesn't declare is nil: off
	x.glow:SetShown(e.glow and true or false)
	if icon then x.grey:SetTexture(icon) end
	x.grey:SetShown(e.grey and true or false)
	x.ring:show(e.ring and true or false)
	x.pulseOn = e.fade and true or false
	-- Callers repeat this: a running pulse isn't restarted
	if not e.fade then x.pulse:Stop(); x.dim:SetAlpha(0)
	elseif not x.pulse:IsPlaying() then x.pulse:Play() end
	self.expCurve = ns.lastSeconds(e.secs)
	warning[self] = true
	ticker:Show()
	local d = self.last
	if d then
		local ok, a = pcall(d.EvaluateRemainingDuration, d, self.expCurve)
		if ok then x:SetAlpha(a) else x:SetAlpha(0) end   -- a may be secret: never compared
	elseif self.held then
		-- As the curve: lit from just above 0 to just past secs
		x:SetAlpha((self.held > 0 and self.held < e.secs + 0.05) and 1 or 0)
	end
end

function Timer:setExpireIcon(icon)
	if self.exp then ns.try("timer expiring icon", self.exp.grey.SetTexture, self.exp.grey, icon) end
end

-- over: the expiring warning's level over its anchor (an element icon's: over its art frame)
function Timer:restack(over)
	if over then self.over = over end
	local x = self.exp
	if x then
		x:SetFrameLevel(self.anchor:GetFrameLevel() + (self.over or 1))
		x.glow:SetFrameLevel(x:GetFrameLevel() + 1)
	end
	if self.bar then self.bar:SetFrameLevel(self.cd:GetFrameLevel() + 1) end
end
