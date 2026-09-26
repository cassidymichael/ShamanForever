-- Timers: one way to show a duration everywhere (design: workspace design/timers.md).
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

local _, ns = ...

local T = {}
ns.Timer = T

T.KINDS = { "cooldown", "uptime" }
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
-- Elements that look different from General until the player says otherwise: applied over
-- General's style, and they do not follow it by default.
T.ELEMENT_DEFAULTS = {
	shield = { uptime = { text = false, swipe = false, swipeAlpha = 0.5, swipeReverse = false, bar = false } },
	imbue = { uptime = { text = true, textSize = 16, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false, bar = false } },
	-- Their time left as a bar only (whatever General says): the countdown shows the cooldown.
	earthbind = { uptime = { text = false, bar = true } },
	stoneclaw = { uptime = { text = false, bar = true } },
}
-- Parts an element's timer can't have, and why (shown on its page): for every kind, or under a
-- kind's name for that kind only.
local ONE_SWIPE = "The cooldown has the swipe; time left shows as text or a bar."
T.CANT = {
	shield = { bar = "The shield's timer is Blizzard's own; a time bar can't follow it." },
	-- One icon, two timers: only the cooldown sweeps.
	earthbind = { uptime = { swipe = ONE_SWIPE } },
	stoneclaw = { uptime = { swipe = ONE_SWIPE } },
	firenova = { uptime = { swipe = ONE_SWIPE } },
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
-- The widget
------------------------------------------------------------------------
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
	local t = setmetatable({ key = key, kind = kind, parent = parent, anchor = opts.anchor or parent, dual = opts.dual, school = opts.school }, Timer)
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
	local s = S.get(self.key, self.kind)
	local cant = T.cant(self.key, self.kind)
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
T.EXPIRE_ELEMENT = {}   -- elements that start differently: key -> fields

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
		x.grey:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		x.grey:SetDesaturated(true)
		x.ring = ns.makeRing(x, x)
		x.dim = x:CreateTexture(nil, "OVERLAY")
		x.dim:SetAllPoints()
		x.dim:SetColorTexture(0, 0, 0, 1)
		x.dim:SetAlpha(0)
		x.pulse = ns.makePulse(x.dim, "dim")
		-- A hidden ancestor (combat-only visibility, Alt-Z) stops the pulse; start it again on show.
		x:SetScript("OnShow", function(s) if s.pulseOn then s.pulse:Play() end end)
		x.glow = ns.makeGlow(x, self.anchor, self.key)   -- ShamanForever.lua; made on first use, after it has loaded
		self.exp = x
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
		if ok then x:SetAlpha(a) else x:SetAlpha(0) end   -- a may be secret: never tested, only handed on
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
