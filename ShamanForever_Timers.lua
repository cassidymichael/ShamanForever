-- Timers: one way to show a duration everywhere.
--
-- A timer has three parts, each on or off: countdown text, swipe and time bar. There are two kinds:
-- "cooldown" (a spell not ready yet) and "uptime" (a totem, shield or imbue running, "Time left"
-- in the UI). Each kind is a style (ShamanForever_Style.lua): General holds one (db.timers); an
-- element, or the totem bar, can have its own (elementOpts(key).timers[kind],
-- db.totemBar.timers[kind]) or follow General.
--
-- Every timer is fed a duration object, so nothing here reads a time: Cooldown and StatusBar take
-- the object, and the bar's "run out" alpha comes from a curve (secret values go straight to
-- SetAlpha). Plain times (the imbue) become a duration object through C_DurationUtil.
-- The countdown's colour by time left is a numeric formatter the Cooldown draws with (see "The
-- countdown's formatter" below), so it needs no reading of the time either.

local _, ns = ...

local T = {}
ns.Timer = T

T.KINDS = { "cooldown", "uptime" }
-- Colour by time left: off, or two steps (Soon, then Now) below which the countdown takes a colour.
-- Tenths: seconds below which the countdown shows tenths (0: never).
local function timeColors()
	return {
		timeColors = false, soon = 10, soonColor = { 1, 0.85, 0.1, 1 }, now = 3, nowColor = { 1, 0.25, 0.2, 1 },
		tenths = 0,
	}
end
T.DEFAULTS = {
	cooldown = {
		text = true, textSize = 20, textColor = { 1, 1, 1, 1 }, textPos = "center", abbrev = 0,
		swipe = true, swipeAlpha = 0.65, swipeReverse = false,
		bar = false, barHeight = 8, barElement = true, barColor = { 0.9, 0.8, 0.3, 1 }, barEdge = "top",
	},
	uptime = {
		text = true, textSize = 12, textColor = { 0.5, 1, 0.4, 1 }, textPos = "auto", abbrev = 0,
		swipe = false, swipeAlpha = 0.6, swipeReverse = true,
		bar = true, barHeight = 8, barElement = true, barColor = { 0.4, 0.9, 0.3, 1 }, barEdge = "bottom",
	},
}
for _, kind in ipairs(T.KINDS) do
	for k, v in pairs(timeColors()) do T.DEFAULTS[kind][k] = v end
end
-- Elements that look different from General until the player says otherwise: applied over
-- General's style, and they do not follow it by default.
T.ELEMENT_DEFAULTS = {
	-- The shield's time bar, when on, along the top: its charge bar is along the bottom.
	shield = { uptime = { text = false, swipe = false, swipeAlpha = 0.5, swipeReverse = false, bar = false, barEdge = "top" } },
	imbue = { uptime = { text = true, textSize = 16, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = false } },
	-- Aura-button elements: their own timer, no bar under Blizzard's button.
	-- Flame Shock's time left: the countdown and a bar along the bottom, Blizzard's button drives both.
	flameshock = { uptime = { text = true, bar = true, barEdge = "bottom" } },
	-- Their time left as a bar only (whatever General says): the countdown shows the cooldown.
	earthbind = { uptime = { text = false, bar = true } },
	stoneclaw = { uptime = { text = false, bar = true } },
	manatide = { uptime = { text = false, bar = true } },
	grounding = { uptime = { text = false, bar = true } },
	-- Stormstrike's time left is how long its empowered spell waits: a bar only.
	stormstrike = { uptime = { text = false, bar = true } },
	-- Ten-minute buffs: minutes in the middle, and a bar.
	waterwalking = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = true } },
	waterbreathing = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = true } },
	elementalfocus = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	-- Maelstrom Weapon's time left is Blizzard's own button swipe: no text, no bar.
	maelstrom = { uptime = { text = false, swipe = true, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	-- Tremor Totem's five minutes while it's down: minutes in the middle and a time bar.
	tremor = { uptime = { text = true, textSize = 14, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = true } },
}
-- Parts an element's timer can't have, and why (shown on its page): for every kind, or under a
-- kind's name for that kind only.
local ONE_SWIPE = "The cooldown has the swipe; time left shows as text or a bar."
T.CANT = {
	-- One icon, two timers: only the cooldown sweeps.
	earthbind = { uptime = { swipe = ONE_SWIPE } },
	stoneclaw = { uptime = { swipe = ONE_SWIPE } },
	firenova = { uptime = { swipe = ONE_SWIPE } },
	manatide = { uptime = { swipe = ONE_SWIPE } },
	grounding = { uptime = { swipe = ONE_SWIPE } },
	-- Not one of the above: Blizzard's own timer, like the shield's and Elemental Focus's.
	maelstrom = { bar = "Its timer is Blizzard's own; a time bar can't follow it." },
	farseer = { uptime = { swipe = ONE_SWIPE } },
	stormstrike = { uptime = { swipe = ONE_SWIPE } },
}
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
-- How Blizzard's aura button drives an aura timer's bar (its SetDurationBar options): as ours do.
T.AURA_BAR = { interpolation = TIMER_IMMEDIATE, direction = TIMER_REMAINING }

-- Both kinds are styles (ShamanForever_Style.lua): General's in db.timers[kind], an element's or the
-- totem bar's own in its timers[kind].
local S = ns.Style
for _, kind in ipairs(T.KINDS) do
	local own = {}
	for key, d in pairs(T.ELEMENT_DEFAULTS) do own[key] = d[kind] end
	S.register(kind, {
		defaults = T.DEFAULTS[kind], path = { "timers", kind }, ownerDefaults = own,
	})
end

------------------------------------------------------------------------
-- The countdown's formatter: colour by time left (and tenths with it). A numeric rule formatter
-- (C_StringUtil.CreateNumericRuleFormatter) handed to the Cooldown (SetCountdownFormatter) turns
-- the time left into the countdown's text inside the engine, with a colour code wrapped into each
-- rule's format, so it follows secret durations in combat with no polling. It replaces the
-- Cooldown's own formatting, so its rules repeat the Time format setting: seconds, "2m" above a
-- minute (or "1:31" below the Time format's threshold) and "1h". Everything rounds up, as the
-- Cooldown's own numbers do. Only Colour by time left needs it: tenths alone are the Cooldown's
-- own (SetCountdownMillisecondsThreshold), and a timer with neither keeps the Cooldown's own text.
------------------------------------------------------------------------
local ROUND_UP = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up or 1

local function secsIn(v, lo, hi)
	if type(v) ~= "number" or v ~= v then return lo end
	return math.min(math.max(v, lo), hi)
end

-- The Cooldown's own formats, lowest threshold first (a rule applies from its threshold up).
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

-- The formatter's breakpoints: a cut at every format rule's threshold and at each colour step,
-- each carrying the format that applies there, in the colour of its step (none above Soon: the
-- text keeps its own colour).
local function breakpoints(s, abbrev, tenths)
	local rules = formatRules(abbrev, tenths)
	local soon, now = secsIn(s.soon, 0, 3600), secsIn(s.now, 0, 3600)
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

-- One formatter per look, shared by every timer with it; a timer also keeps its own, so dropping
-- the cache (while the options are being dragged through many looks) never frees one in use.
local formatters, cached = {}, 0
local function formatterFor(s)
	if not s.timeColors then return nil end
	local tenths = math.floor(secsIn(s.tenths, 0, 10))
	local abbrev = secsIn(s.abbrev, 0, 3600)
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

------------------------------------------------------------------------
-- The widget
------------------------------------------------------------------------
local Timer = {}
Timer.__index = Timer
local fonts = 0

-- parent: frame the parts go on; opts:
--   anchor = the icon the parts cover (default parent)
--   cd     = an existing Cooldown to use (its frame level is kept)
--   dual   = the icon also shows the other kind of timer ("auto" text then goes top-left)
--   school = colour for "element colour" bars (a key of ns.SCHOOL_COLOR), or a function returning one
--   aura   = the timer is on Blizzard's aura button (ns.makeAuraSlot), which draws the time: the
--            button drives the bar (T.AURA_BAR), so it is shown whenever the style has one and is
--            never fed a duration here; its looks change only out of combat (the slot's restyle)
--   barInset = function returning how far above the bottom edge a bottom bar sits (the shield's
--            charge bar is along that edge, drawn over it)
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
	cd:SetDrawBling(kind == "cooldown")   -- the ready flash, for cooldowns only
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
	local c = school and ns.SCHOOL_COLOR[school]
	return c or { 0.4, 0.9, 0.3 }
end

-- Takes the current style. Safe any time for our own frames; the shield's Cooldown is restyled
-- only out of combat by its caller.
function Timer:apply()
	local s = S.get(self.key, self.kind)
	local cant = T.cant(self.key, self.kind)
	local cd = self.cd
	cd:SetDrawSwipe(s.swipe and not cant.swipe)
	cd:SetSwipeColor(0, 0, 0, s.swipeAlpha)
	cd:SetReverse(s.swipeReverse)
	cd:SetHideCountdownNumbers(not s.text or cant.text ~= nil)
	-- Minutes read "2m"; under abbrev seconds they read "1:31" (0: never). Under a minute the client
	-- always shows plain seconds.
	pcall(cd.SetCountdownAbbrevThreshold, cd, s.abbrev)
	-- Colour by time left (a formatter, which then does the above and the tenths too), or tenths
	-- alone (the Cooldown's own). A timer that never had either is left alone.
	local text = s.text and not cant.text
	local fm = text and formatterFor(s) or nil
	if fm ~= self.formatter then
		self.formatter = fm
		ns.try("timer formatter", cd.SetCountdownFormatter, cd, fm)
	end
	local ms = (text and not fm) and math.floor(secsIn(s.tenths, 0, 10)) or 0
	if ms ~= (self.ms or 0) then
		self.ms = ms
		pcall(cd.SetCountdownMillisecondsThreshold, cd, ms)
	end
	local c = s.textColor
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
			local y = self.barInset and self.barInset() or 0
			bar:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, y); bar:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, y)
		end
		local col = s.barElement and schoolColor(self) or s.barColor
		bar:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
		if self.aura then bar:SetShown(self.barOn)
		elseif not self.barOn then bar:Hide() end
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

-- The colour its time bar takes (its element's school, or the style's colour).
function Timer:barRGB()
	local s = S.get(self.key, self.kind)
	return s.barElement and schoolColor(self) or s.barColor
end

-- Show a duration object, or clear with nil.
function Timer:set(d)
	if not d then return self:clear() end
	self.last = d
	ns.try("timer cooldown", self.cd.SetCooldownFromDurationObject, self.cd, d, true)
	local bar = self.bar
	if bar and self.barOn then
		ns.try("timer bar", bar.SetTimerDuration, bar, d, TIMER_IMMEDIATE, TIMER_REMAINING)
		-- 0 once run out: an expired duration object can linger on the bar.
		if ns.CURVE_LIVE then
			local ok, a = ns.try("timer bar alpha", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
			if ok then bar:SetAlpha(a) else bar:SetAlpha(1) end
		end
		bar:Show()
	elseif bar then bar:Hide() end
end

-- Show a plain time span (start and length in seconds, GetTime's clock).
function Timer:setTime(start, length)
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
	self.last = nil
	if self.exp then self.exp:SetAlpha(0) end
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

------------------------------------------------------------------------
-- Expiring: a warning over the icon in a timer's last seconds (grey icon, red ring, fade in and
-- out, pulsing glow, any mix). Its alpha is the remaining time through a curve (1 inside the last
-- `secs`, else 0: ns.lastSeconds), so it works in combat; evaluated ten times a second for every
-- timer that has one. It sits just above the icon, below the cooldowns and their countdowns, so
-- those stay readable (the totem bar does the same).
------------------------------------------------------------------------
local warning = {}   -- timers with an expiry warning
local ticker = CreateFrame("Frame")   -- shown only while some timer has a warning
ticker.t = 0
ticker:Hide()
ticker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	for t in pairs(warning) do
		local d = t.last
		if d then
			-- pcall, not ns.try: this runs ten times a second and must not allocate.
			local ok, a = pcall(d.EvaluateRemainingDuration, d, t.expCurve)
			if ok then t.exp:SetAlpha(a) else t.exp:SetAlpha(0); ns.noteError("timer expiring", a) end
		else t.exp:SetAlpha(0) end
	end
end)

T.EXPIRE_DEFAULTS = { secs = 5, grey = false, ring = false, pulse = true, glow = false }

-- An element's expiring warning (its time left's last seconds): its own settings over its own
-- defaults (ns.elementDefault's "expire") over everyone's.
function T.expireOpts(key)
	local o = ns.elementOpts(key).expire
	local own = ns.elementDefault(key, "expire")
	local out = {}
	for k, v in pairs(T.EXPIRE_DEFAULTS) do
		if type(own) == "table" and type(own[k]) == type(v) then v = own[k] end
		if type(o) == "table" and type(o[k]) == type(v) then out[k] = o[k] else out[k] = v end   -- a saved false counts
	end
	return out
end

-- e: { secs, grey, ring, pulse, glow } (secs 0 turns it off); icon: the texture the grey copy shows.
function Timer:setExpire(e, icon)
	if not e or e.secs <= 0 or not ns.lastSeconds(e.secs) then
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
		-- On the timer's parent (so an owner's alpha still gates it), but at the icon's level + 1:
		-- below the cooldowns, which the caller keeps above it.
		x = CreateFrame("Frame", nil, self.parent)
		x:SetAllPoints(self.anchor)
		x:SetFrameLevel(self.anchor:GetFrameLevel() + 1)
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
		-- A hidden ancestor (combat-only visibility, Alt-Z) stops the pulse; start it again on show.
		x:SetScript("OnShow", function(s) if s.pulseOn then s.pulse:Play() end end)
		x.glow = ns.makeGlow(x, self.anchor, self.key)   -- made on first use
		self.exp = x
		ns.Looks.followMask(self.anchor, x.grey, x.dim)   -- a rounded or cut-corner icon's shape
	end
	x.glow:fit(self.anchor:GetWidth())
	x.glow:SetShown(e.glow)
	if icon then x.grey:SetTexture(icon) end
	x.grey:SetShown(e.grey)
	x.ring:show(e.ring)
	x.pulseOn = e.pulse and true or false
	-- Callers repeat this (the totem bar on every totem change): a running pulse isn't restarted.
	if not e.pulse then x.pulse:Stop(); x.dim:SetAlpha(0)
	elseif not x.pulse:IsPlaying() then x.pulse:Play() end
	self.expCurve = ns.lastSeconds(e.secs)
	warning[self] = true
	ticker:Show()
	-- At once, not on the next tick (a totem recast in its last seconds drops the old warning now).
	local d = self.last
	if d then
		local ok, a = pcall(d.EvaluateRemainingDuration, d, self.expCurve)
		if ok then x:SetAlpha(a) else x:SetAlpha(0) end   -- a may be secret: never compared, only handed on
	end
end

-- The grey copy's icon, when it changes with what is shown (the totem bar's totem; a secret icon
-- in combat is fine, SetTexture takes it).
function Timer:setExpireIcon(icon)
	if self.exp then ns.try("timer expiring icon", self.exp.grey.SetTexture, self.exp.grey, icon) end
end

-- Frame levels again, after the caller moved the icon (regrouping): the warning just above the
-- anchor, the bar just above the timer's Cooldown.
function Timer:restack()
	local x = self.exp
	if x then
		x:SetFrameLevel(self.anchor:GetFrameLevel() + 1)
		x.glow:SetFrameLevel(x:GetFrameLevel() + 1)
	end
	if self.bar then self.bar:SetFrameLevel(self.cd:GetFrameLevel() + 1) end
end
