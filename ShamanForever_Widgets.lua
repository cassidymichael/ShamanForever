-- Widgets

local ADDON, ns = ...

-- What shared code reads from the class (_Class) with no default; the first reader is _Looks
do
	local function has(path)
		local t = ns
		for key in path:gmatch("[^.]+") do
			if type(t) ~= "table" then return false end
			t = t[tonumber(key) or key]
		end
		return t ~= nil
	end
	local gaps = {}
	for _, path in ipairs({ "CLASS.token", "CLASS.plural", "CLASS.slash.1", "CLASS.icon", "CLASS.blurb",
		"CLASS.links.repo", "CLASS.links.curseforge", "CLASS.links.discord", "CLASS.links.kofi", "CLASS.credits",
		"CLASS.sharePrefix", "CLASS.help.uptime", "CLASS.help.pop", "CLASS.help.popColour", "CLASS.help.bars",
		"CLASS.help.glowColour", "CLASS.layout", "THEME.axis.name", "THEME.axis.lower", "THEME.axis.one" }) do
		if not has(path) then table.insert(gaps, "ns." .. path) end
	end
	if not (has("THEME.color") and has("THEME.sample") and ns.THEME.color[ns.THEME.sample]) then
		table.insert(gaps, "ns.THEME.color[ns.THEME.sample]")
	end
	if #gaps > 0 then error(ADDON .. ": the class doesn't supply " .. table.concat(gaps, ", ")) end
end

-- A class may give its own bar colours; else each colour a little brighter
if not ns.THEME.barColor then
	ns.THEME.barColor = {}
	for school, c in pairs(ns.THEME.color) do
		ns.THEME.barColor[school] = { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) }
	end
end

ns.BACKDROP = { bgFile = ns.WHITE, edgeFile = ns.WHITE, edgeSize = 1 }

-- A tooltip: title, then text in white (either may be a function); anchor: a GameTooltip one, or "above"
function ns.setTip(frame, title, text, anchor)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		if anchor == "above" then
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
		else GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT") end
		GameTooltip:SetText(type(title) == "function" and title() or title)
		GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A panel the player drags, kept on screen, hidden; border: its edge colour over a dark fill (none: no backdrop)
function ns.floatingPanel(name, width, height, border)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnHide", f.StopMovingOrSizing)   -- hidden mid-drag (combat), the drag ends
	if border then
		f:SetBackdrop(ns.BACKDROP)
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
		f:SetBackdropBorderColor(unpack(border))
	end
	f:Hide()
	return f
end

function ns.cropIcon(tex) tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
-- Drawn at the frame's exact rect: a snapped texture would show a sliver past a cooldown swipe.
function ns.cropIconExact(tex)
	ns.cropIcon(tex)
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
	end
end

ns.COUNT_JUSTIFY = { TOPLEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
	CENTER = "CENTER" }

ns.BASE_ICON_SIZE = 44
function ns.placeScaledText(fs, icon, size, point, x, y, relPoint)
	local px = math.max(math.floor(size * icon:GetWidth() / ns.BASE_ICON_SIZE + 0.5), 6)
	local sig = string.format("%d%s%s%s,%s%s", px, point, relPoint or point, x, y, ns.Media.textKey())
	if fs.placed == sig then return px end
	fs.placed = sig
	ns.Media.setFont(fs, nil, px)
	fs:ClearAllPoints()
	fs:SetPoint(point, icon, relPoint or point, x, y)
	return px
end

function ns.makeKeyText(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	fs:SetPoint("TOPRIGHT", -2, -2)
	fs:SetTextColor(0.85, 0.85, 0.85)
	return fs
end
function ns.keyTextSize(size, base) return math.max(6, math.floor(base * size / ns.BASE_ICON_SIZE + 0.5)) end
-- A binding's key in the short form action bars use ("SWU", "C5").
local MODIFIERS = { ALT = "A", CTRL = "C", SHIFT = "S", META = "M" }
local SHORT_KEYS = {
	MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
	SPACE = "Sp", BACKSPACE = "BS", CAPSLOCK = "Cap", TAB = "Tab", ENTER = "Ent", ESCAPE = "Esc",
	INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End", PAGEUP = "PU", PAGEDOWN = "PD",
	UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
	NUMLOCK = "NL", SCROLLLOCK = "SL", PRINTSCREEN = "PS", PAUSE = "Pau",
	NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/",
	NUMPADDECIMAL = "N.", NUMPADEQUALS = "N=",
}
local keyLabels = {}
function ns.keyLabel(key)
	if not key then return "" end
	local label = keyLabels[key]
	if label then return label end
	local mods, rest = "", key
	while true do
		local m, after = rest:match("^(%u+)%-(.+)$")
		if not (m and MODIFIERS[m]) then break end
		mods, rest = mods .. MODIFIERS[m], after
	end
	local short = SHORT_KEYS[rest] or rest:match("^BUTTON(%d+)$") and "M" .. rest:match("^BUTTON(%d+)$")
		or rest:match("^NUMPAD(%d)$") and "N" .. rest:match("^NUMPAD(%d)$")
	if not short then
		short = #rest <= 3 and rest or GetBindingText(rest, 1)
		if type(short) ~= "string" or short == "" then short = rest end
	end
	label = mods .. short
	keyLabels[key] = label
	return label
end

-- A frame above Blizzard's protected aura button takes no alpha change in combat: its fade is
-- restated after combat.
local FADE_OUT, FADE_IN = 0.8, 0.15
local fading = {}
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
	local combat = InCombatLockdown()
	for f, target in pairs(fading) do
		if combat and f.aboveProtected then fading[f] = nil
		else
			local a = f:GetAlpha()
			if target < a then a = math.max(target, a - elapsed / FADE_OUT)
			else a = math.min(target, a + elapsed / FADE_IN) end
			f:SetAlpha(a)
			if a == target then fading[f] = nil end
		end
	end
	if next(fading) == nil then self:Hide() end
end)
function ns.fadeTo(f, alpha)
	if f.aboveProtected and InCombatLockdown() then return end
	if math.abs(f:GetAlpha() - alpha) < 0.005 then
		fading[f] = nil
		f:SetAlpha(alpha)
		return
	end
	fading[f] = alpha
	fader:Show()
end

-- Screen-pixel lines
function ns.pixel(frame)
	local _, physicalHeight = GetPhysicalScreenSize()
	return 768 / (physicalHeight or 768) / frame:GetEffectiveScale()
end
function ns.roundPx(v, px) return math.floor(v / px + 0.5) * px end

function ns.linePx(frame, n)
	local count = math.floor(n * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() + 0.5)
	if n > 0 and count < 1 then count = 1 end
	return count * ns.pixel(frame)
end

-- Anchors on a whole screen pixel so texture, border and swipe agree on edges.
function ns.placeOnPixels(frame, point, x, y)
	local px = ns.pixel(frame)
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local pw, ph = UIParent:GetSize()
	local w, h = frame:GetSize()
	local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
	local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
	local left = fx * pw * k + x - fx * w
	local top = fy * ph * k + y + (1 - fy) * h
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x + ns.roundPx(left, px) - left, y + ns.roundPx(top, px) - top)
end

-- Warning looks
local RING_PX = 3
local RING_COLOR = { 1, 0, 0, 0.9 }
local Ring = {}
Ring.__index = Ring
local rings = setmetatable({}, { __mode = "k" })
function ns.makeRing(parent, anchor)
	local r = setmetatable({ anchor = anchor, edges = {} }, Ring)
	rings[r] = true
	for i = 1, 4 do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, 6)
		t:Hide()
		r.edges[i] = t
	end
	r:color()
	return r
end
function Ring:color(red, g, b, a)
	local k = RING_COLOR
	for _, t in ipairs(self.edges) do t:SetColorTexture(red or k[1], g or k[2], b or k[3], a or k[4]) end
end
function Ring:fit()
	local w = ns.linePx(self.anchor, RING_PX)
	if w == self.width then return end
	self.width = w
	local a, top, bottom, left, right = self.anchor, self.edges[1], self.edges[2], self.edges[3], self.edges[4]
	for _, t in ipairs(self.edges) do t:ClearAllPoints() end
	top:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0); top:SetHeight(w)
	bottom:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(w)
	left:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -w); left:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, w); left:SetWidth(w)
	right:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, -w); right:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, w); right:SetWidth(w)
end
function Ring:show(on)
	if on then self:fit() end
	for _, t in ipairs(self.edges) do t:SetShown(on and true or false) end
end
function ns.refitRings()
	for r in pairs(rings) do
		if r.edges[1]:IsShown() then r:fit() end
	end
end

-- fade: the region breathes (missing); dim: a dark layer (expiring).
function ns.makePulse(region, kind)
	local g = region:CreateAnimationGroup()
	g:SetLooping("BOUNCE")
	local a = g:CreateAnimation("Alpha")
	if kind == "dim" then a:SetFromAlpha(0); a:SetToAlpha(0.55); a:SetDuration(0.6)
	else a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.8) end
	a:SetSmoothing("IN_OUT")
	return g
end

-- The global cooldown's sweep
function ns.makeGCDSweep(parent)
	local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetSwipeTexture(ns.WHITE)
	cd:SetSwipeColor(0, 0, 0, 0.6)
	ns.Looks.followSwipe(parent, cd)
	return cd
end

-- Aura slot: Blizzard's aura container on an element icon, the one way to show an aura in combat.
-- Calls it refuses in combat or while auras are secret wait (ns.deferWhileAurasSecret).
-- Scripts under its button never run: it only plays animations handed to it.
local AuraSlot = {}
AuraSlot.__index = AuraSlot

-- Clicks and hover pass through a button of Blizzard's (each call may be refused)
function ns.noMouse(b)
	pcall(b.EnableMouse, b, false)
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
end

function ns.makeAuraSlot(frame, opts)
	return setmetatable({ frame = frame, opts = opts }, AuraSlot)
end

local function initAuraButton(slot, button)
	local o = slot.opts
	local size = ns.sizeOf(o.key)
	button:SetSize(size, size)
	slot.size = size
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	ns.noMouse(button)
	local host = o.host and o.host(slot, button) or button
	slot.host = host
	local tex = host:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	ns.cropIconExact(tex)
	if o.ownIcon then tex:SetTexture(o.ownIcon()) else button:SetIcon(tex) end
	slot.icon = tex
	ns.try(o.sites.style, ns.Looks.auraMask, host, tex, o.key)
	local cd = CreateFrame("Cooldown", nil, host, "CooldownFrameTemplate")
	cd:SetAllPoints()
	slot.cd = cd
	if o.noTimer then
		cd:SetHideCountdownNumbers(true)
		if o.onButton then o.onButton(slot, button, cd) end
		slot.button = button
		return
	end
	-- A client that refuses the time bar gets none rather than a still one.
	local e = ns.ELEMENTS[o.key]
	slot.timer = ns.Timer.new(host, o.key, "uptime", { cd = cd, anchor = host, aura = true,
		school = e and e.school, barInset = o.barInset })
	if not ns.try("aura time bar", button.SetDurationBar, button, slot.timer.bar, ns.Timer.AURA_BAR) then
		slot.timer.bar:Hide()
		slot.timer.bar = nil
	end
	slot.timer:apply()
	button:SetDurationCooldown(cd)
	if o.onButton then o.onButton(slot, button, cd) end
	slot.button = button
end

local function initExtraButton(slot, x, button)
	local size = ns.sizeOf(slot.opts.key)
	button:SetSize(size, size)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	ns.noMouse(button)
	slot.extras = slot.extras or {}
	slot.extras[x.key] = button
	x.init(slot, button)
end

local function candidates(o)
	if o.candidates then return o.candidates() end
	return { includeSpellIDs = o.ids() }
end

local function filterSig(filters)
	local parts = {}
	for k, v in pairs(filters) do
		if type(v) == "table" then
			local keys = {}
			for x, on in pairs(v) do if on then table.insert(keys, tostring(x)) end end
			table.sort(keys)
			table.insert(parts, k .. "=" .. table.concat(keys, ","))
		else table.insert(parts, k .. "=" .. tostring(v)) end
	end
	table.sort(parts)
	return table.concat(parts, ";")
end

function AuraSlot:setup()
	if self.container or self.err then return end
	local o, f = self.opts, self.frame
	if ns.deferWhileAurasSecret(o.sites.container, function() self:setup() end) then return end
	local filters = candidates(o)
	local ok, err = pcall(function()
		local size = ns.sizeOf(o.key)
		local c = CreateFrame("AuraContainer", o.name, o.parent or f, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		c:SetSize(size, size)
		c:SetFrameStrata(f:GetFrameStrata())
		c:SetFrameLevel(f.textFrame:GetFrameLevel() + 5 + (o.level or 0))
		c:SetUnit(o.unit or "player")
		pcall(c.EnableMouse, c, false)   -- unlocked drags start on the group frame underneath
		self.container = c
		f.auraButton = true   -- the layout waits while it can't restyle the button (layoutElements)
		c:AddAuraSlot(o.slot, o.filter or "HELPFUL", {
			candidateFilters = filters,
			initializeFrame = function(button) initAuraButton(self, button) end,
		})
		for _, x in ipairs(o.extras or {}) do
			c:AddAuraSlot(o.slot .. "-" .. x.key, o.filter or "HELPFUL", {
				candidateFilters = filters,
				initializeFrame = function(button) initExtraButton(self, x, button) end,
			})
		end
	end)
	if not ok then
		self.err = tostring(err)
		if self.container then self.container:Hide() end
		o.onError(self.err)
	else
		self.filtered, self.applied = filters.includeSpellIDs, filterSig(filters)
		self:style()   -- a layout queued before it (a /reload in combat) found no button to style
	end
end

-- Out of combat, auras readable; a refused call is tried again after combat. Once a frame at most:
-- one layout asks several times, and a dragged slider restyles every frame.
function AuraSlot:style()
	if not self.button or self.styleSoon then return end
	self.styleSoon = true
	C_Timer.After(0, function()
		self.styleSoon = false
		self:styleNow()
	end)
end
function AuraSlot:styleNow()
	if not self.button then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.style, function() self:styleNow() end) then return end
	local ok = ns.try(o.sites.style, function()
		local size, f, c = ns.sizeOf(o.key), self.frame, self.container
		c:SetSize(size, size)
		c:SetFrameStrata(f:GetFrameStrata())
		c:SetFrameLevel(f.textFrame:GetFrameLevel() + 5 + (o.level or 0))
		self.button:SetSize(size, size)
		self.size = size
		for i, x in ipairs(o.extras or {}) do
			local b = self.extras and self.extras[x.key]
			if b then
				b:SetSize(size, size)
				b:SetFrameLevel(f.textFrame:GetFrameLevel() + 5 + 2 * i + 2)
			end
		end
		-- Own try: a look the button refuses mustn't stop the timer and the caller's parts.
		ns.try(o.sites.style .. ": look", ns.Looks.auraStyle, self, size)
		if self.timer then self.timer:apply() end
		if o.onStyle then o.onStyle(self, size) end
	end)
	if not ok then ns.retryAfterCombat(o.sites.style, function() self:styleNow() end) end
end

-- Only when the filters changed (callers ask on every spellbook change)
function AuraSlot:refilter()
	if not self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.filter, function() self:refilter() end) then return end
	local filters = candidates(o)
	local sig = filterSig(filters)
	if sig == self.applied then return end
	self.applied = nil
	local ok = ns.try(o.sites.filter, self.container.SetAuraSlotCandidateFilters, self.container, o.slot, filters)
	-- Last to first: a part covering another comes after it, so a refilter stopping part way leaves
	-- nothing uncovered.
	local extras = o.extras or {}
	for i = #extras, 1, -1 do
		if ok then
			ok = ns.try(o.sites.filter, self.container.SetAuraSlotCandidateFilters, self.container,
				o.slot .. "-" .. extras[i].key, filters)
		end
	end
	if ok then self.filtered, self.applied = filters.includeSpellIDs, sig
	else ns.retryAfterCombat(o.sites.filter, function() self:refilter() end) end
end

-- Counts on an aura button: Blizzard writes the number and fills the bar; nothing here reads them
local Count = {}
ns.Count = Count

local COUNT_NUDGE = { CENTER = { 0, 0 }, TOPLEFT = { -2, 2 }, TOPRIGHT = { 2, 2 }, BOTTOMLEFT = { -2, -2 },
	BOTTOMRIGHT = { 2, -2 } }

-- lift: how far a number at a bottom point sits up (over a bar)
function Count.place(fs, anchor, pos, lift)
	local nudge = COUNT_NUDGE[pos]
	local y = nudge[2] + ((lift and pos:find("BOTTOM")) and lift or 0)
	fs:ClearAllPoints()
	fs:SetPoint(pos, anchor, pos, nudge[1], y)
	fs:SetJustifyH(ns.COUNT_JUSTIFY[pos])
end

-- The number's font string on parent, handed to the button; place(fs) sets its font first, since
-- Blizzard writes the count at once
function Count.text(slot, button, parent, place, site)
	local fs = parent:CreateFontString(nil, "OVERLAY", nil, 7)
	place(fs)
	slot.fs, slot.countFormatter = fs, false
	ns.try(site, button.SetApplicationCount, button, fs)
	return fs
end

local formatters = ns.cache(8, function(code, markAt, max, site)
	local ok, new = ns.try(site, function()
		local x = C_StringUtil.CreateNumericRuleFormatter()
		local rules = { { threshold = 0, format = "%d" } }
		if code ~= "" then
			table.insert(rules, { threshold = markAt, format = code .. "%d|r" })
			if markAt < max then table.insert(rules, { threshold = markAt + 1, format = "%d" }) end
		end
		x:SetBreakpoints(rules)
		for n = 0, max do
			local text = x:FormatNumber(n)
			local coloured = code ~= "" and n == markAt
			if type(text) ~= "string" or ns.isSecret(text) or (coloured and not text:lower():find(code, 1, true)) then
				error(string.format("formatted %d as %s", n, tostring(text)))
			end
		end
		return x
	end)
	return ok and new or false
end)
-- Prints every count from 0 (without one Blizzard prints from 2), markAt in markColor (nil: none).
-- Tried on 0 to max first: an error would stop Blizzard's aura update. nil if the client can't.
function Count.formatter(markColor, markAt, max, site)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local code = markColor and ns.colorCode(markColor) or ""
	return formatters(code .. ":" .. tostring(markAt) .. ":" .. max, code, markAt, max, site) or nil
end

-- Hands the button a formatter (nil: Blizzard's own count), once per change
function Count.setFormat(slot, fm, site)
	fm = fm or false
	if fm == slot.countFormatter then return end
	if ns.try(site, slot.button.SetApplicationCount, slot.button, slot.fs, fm and { formatter = fm } or nil) then
		slot.countFormatter = fm
	end
end

-- A bar along anchor's bottom, on a dark back, with a tick between segments (Count.styleBar).
-- The ticks are the bar's child, so they sit over it.
function Count.bar(slot, parent, anchor)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
	bar:SetStatusBarTexture(ns.Media.barTexture())
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	local ticks = CreateFrame("Frame", nil, bar)
	ticks:SetAllPoints(bar)
	slot.bar, slot.tickFrame, slot.ticks = bar, ticks, {}
	return bar
end

-- max segments on an icon size wide; shown: the bar and ticks at alpha 1, else 0
function Count.styleBar(slot, size, max, height, color, shown)
	local bar, ticks = slot.bar, slot.ticks
	bar:SetHeight(height)
	bar:SetStatusBarTexture(ns.Media.barTexture())   -- before the colour
	bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	for i = 1, max - 1 do
		local t = ticks[i]
		if not t then
			t = slot.tickFrame:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(0, 0, 0, 0.9)
			t:SetWidth(1)
			ticks[i] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOP", slot.tickFrame, "TOPLEFT", size * i / max, 0)
		t:SetPoint("BOTTOM", slot.tickFrame, "BOTTOMLEFT", size * i / max, 0)
		t:Show()
	end
	for i = max, #ticks do ticks[i]:Hide() end
	bar:SetAlpha(shown and 1 or 0)
	slot.tickFrame:SetAlpha(shown and 1 or 0)
end

-- The warning look: grey, tint, ring, fade, glow. The same five go to the icon itself
-- (f:SetWarnParts), to a warn overlay and to a clip look (setParts). ns.warnParts reads them from an
-- element's state table (warn, expire): a look it doesn't declare is off.
function ns.warnParts(key, name)
	local function part(field)
		if ns.elementDefault(key, name, field) == nil then return false end
		return ns.elementSetting(key, name, field) and true or false
	end
	return part("grey"), part("tint"), part("ring"), part("fade"), part("glow")
end

-- A warning look over an icon, its alpha set by its owner (a curve in combat): grey, ring and fade
-- only, all an element drawn this way declares
function ns.makeWarnOverlay(f)
	local w = CreateFrame("Frame", nil, f)
	w:SetAllPoints()
	w.grey = w:CreateTexture(nil, "ARTWORK")
	w.grey:SetAllPoints(f.tex)
	ns.cropIconExact(w.grey)
	w.grey:SetDesaturated(true)
	w.ring = ns.makeRing(w, f.tex)
	w.pulse = ns.makePulse(w.grey, "fade")
	w:SetAlpha(0)
	-- Hiding a frame stops its animations
	w:SetScript("OnShow", function(self)
		if self.pulseOn and not self.pulse:IsPlaying() then self.pulse:Play() end
	end)
	function w:setIcon(icon) self.grey:SetTexture(icon) end
	function w:setParts(grey, _, ring, fade)
		self.grey:SetShown(grey and true or false)
		self.ring:show(ring)
		self.pulseOn = fade and true or false
		if not self.pulseOn then self.pulse:Stop()
		elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	end
	return w
end

-- Clip look: shown exactly while an aura is gone (inverted: while it is up), in combat too, nothing
-- read. A sensor container sizes to its aura button; a clip frame of ours shows the look only
-- within that. A change waiting for combat's end is a miss, never a false warning.
local ClipLook = {}
ClipLook.__index = ClipLook
-- The sensor's button is this much wider than the cell: the clip empty, not 1 px.
local CLIP_SLACK = 2
-- The look's reach in icon widths: 1.7 covers the widest (the Proc glow's burst, 150/45); a wider
-- look needs it raised.
local CLIP_REACH = 1.7

local function shapeTextures(frame, f, over)
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("Texture") and not r:IsObjectType("MaskTexture") then
			ns.Looks.maskOver(f, r, over)
		end
	end
	for _, c in ipairs({ frame:GetChildren() }) do shapeTextures(c, f, over) end
end

function ns.makeClipLook(frame, opts)
	local h = setmetatable({ frame = frame, opts = opts }, ClipLook)
	h.hold = CreateFrame("Frame", nil, opts.parent)
	h.hold:SetAllPoints(frame)
	h.hold:SetAlpha(0)
	h.hold:SetScript("OnShow", function()
		h:wait()
		if h.fadeOn then h.pulse:Play() end
	end)
	h.tick = function(f)
		h.waiting = h.waiting - 1
		if h.waiting > 0 then return end
		h.waiting = nil
		f:SetScript("OnUpdate", nil)
		h:update()
	end
	h.cell = CreateFrame("Frame", nil, opts.sensorParent)
	h.cell:SetPoint("CENTER", frame, "CENTER", 0, 0)
	h.cell:SetSize(1, 1)
	h.clip = CreateFrame("Frame", nil, h.hold, "DisableUntrustedLayoutScriptsTemplate")
	h.clip:SetClipsChildren(true)
	h.clip:SetPoint("TOPLEFT", h.cell, "TOPRIGHT", 0, 0)
	h.clip:SetPoint("BOTTOMRIGHT", h.cell, "BOTTOMRIGHT", 0, 0)
	h.look = CreateFrame("Frame", nil, h.clip, "DisableUntrustedLayoutScriptsTemplate")
	h.look:SetAllPoints(h.cell)
	h.art = CreateFrame("Frame", nil, h.look)
	h.art:SetAllPoints(frame)
	h.tex = h.art:CreateTexture(nil, "ARTWORK")
	ns.cropIconExact(h.tex)
	h.tex:SetAllPoints(frame.tex)
	h.ring = ns.makeRing(h.art, h.tex)
	h.pulse = ns.makePulse(h.tex, "fade")
	if opts.glowOnly then h.art:Hide() end
	h.glow = ns.Effects.glow(h.look, frame, opts.owner)
	h.glow.onLayout = function(_, parts, look)
		if not look.inside then return end
		for _, r in ipairs(parts.roots or {}) do shapeTextures(r, frame, h.tex) end
	end
	for key, parts in pairs(h.glow.parts) do
		if parts then h.glow.onLayout(h.glow, parts, ns.Style.look("glow", key)) end
	end
	return h
end

-- Wide enough for the art frame on a look that carries the border
local function cellWidth(size, frame, o)
	local half = CLIP_REACH * (size + 2 * ns.Looks.outerEdge(frame))
	if not o.glowOnly then
		local r, box = ns.Frames.reach(o.key), ns.boxOf(o.key)
		half = math.max(half, box * (0.5 + math.max(r.left, r.right, r.top, r.bottom)) + 1)
	end
	return math.ceil(2 * half)
end

-- Hold at 0 now, back on its second OnUpdate: Blizzard's container updates on its next OnUpdate
-- after a change.
function ClipLook:wait()
	self.waiting = 2
	self.hold:SetAlpha(0)
	self.hold:SetScript("OnUpdate", self.tick)
end

function ClipLook:ready()
	local o = self.opts
	return self.container ~= nil and not self.err and self.idsOK == true and not self.waiting
		and self.size == ns.sizeOf(o.key) and (o.needUnit == nil or self.unit == o.needUnit)
		and (o.agrees == nil or o.agrees() == true)
end

function ClipLook:update()
	self.hold:SetAlpha((self.wanted and self:ready()) and 1 or 0)
end

function ClipLook:want(on)
	self.wanted = on and true or false
	self:update()
end

function ClipLook:setParts(grey, tint, ring, fade, glow)
	local t = self.tex
	t:SetDesaturated(grey and true or false)
	if tint then t:SetVertexColor(1, 0.35, 0.35) else t:SetVertexColor(1, 1, 1) end
	self.ring:show(ring)
	self.fadeOn = fade and true or false
	if not self.fadeOn then self.pulse:Stop()
	elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	glow = glow and true or false
	if glow ~= self.glowOn then
		self.glowOn = glow
		self.glow:SetShown(glow)
	end
end

function ClipLook:reshape()
	if self.opts.glowOnly then self.glow:restyle() return end
	local f = self.frame
	ns.Looks.overlay(self.art, ns.borderFor(self.opts.key))
	ns.Looks.maskOver(f, self.tex)
	for _, e in ipairs(self.ring.edges) do ns.Looks.maskOver(f, e, self.tex) end
	self.glow:restyle()
end

local function clipTo(self, c)
	self.clip:ClearAllPoints()
	if self.opts.invert then
		self.clip:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
		self.clip:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -CLIP_SLACK, 0)
	else
		self.clip:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
		self.clip:SetPoint("BOTTOMRIGHT", self.cell, "BOTTOMRIGHT", 0, 0)
	end
end

function ClipLook:setup()
	if self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.container, function() self:setup() end) then return end
	local size = ns.sizeOf(o.key)
	local w = cellWidth(size, self.frame, o)
	local filters = candidates(o)
	local unit = type(o.unit) == "function" and o.unit() or o.unit or "player"
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", nil, o.sensorParent, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", self.cell, "TOPLEFT", 0, 0)
		c:SetFrameStrata(self.frame:GetFrameStrata())
		c:SetUnit(unit)
		pcall(c.EnableMouse, c, false)
		pcall(c.SetFlowLayoutPadding, c, 0, 0, 0, 0)   -- empty is 1 px wide (its layout's least)
		self.container = c
		self.unit = unit
		self.cell:SetSize(w, w)
		c:AddAuraGroup(o.key, o.filter or "HELPFUL", {
			candidateFilters = filters, maxFrameCount = 1,
			layout = { elementWidth = w + CLIP_SLACK, elementHeight = w },
			initializeFrame = function(b)
				b:SetSize(1, 1)
				ns.noMouse(b)
			end,
		})
		clipTo(self, c)
	end)
	if not ok then
		self.err = tostring(err)
		if self.container then self.container:Hide() end
		ns.noteError(o.sites.container, self.err)
		self:update()
		return
	end
	self.width = w
	self:took(size, filters)
	self:wait()
end

function ClipLook:took(size, filters)
	if size then
		self.size = size
		self.glow:fit(size)
	end
	if filters then
		self.applied = filterSig(filters)
		self.filtered = {}
		for id in pairs(filters.includeSpellIDs or {}) do self.filtered[id] = true end
	end
	self:checkIDs()
end

-- Every ID of ids() must be in it: a sensor missing one would stay empty over that aura, a false
-- warning.
function ClipLook:checkIDs()
	local o, ok = self.opts, false
	if o.candidates then ok = self.applied ~= nil and self.applied == filterSig(o.candidates())
	elseif self.filtered then
		ok = true
		for id in pairs(o.ids()) do
			if not self.filtered[id] then ok = false break end
		end
	end
	self.idsOK = ok
	self:update()
end

-- Waits for combat's end; the hold stays at 0 meanwhile.
function ClipLook:style()
	self:update()
	if not self.container or self.err or self.styleSoon then return end
	self.styleSoon = true
	C_Timer.After(0, function()
		self.styleSoon = false
		self:styleNow()
	end)
end
function ClipLook:styleNow()
	local o = self.opts
	local size = ns.sizeOf(o.key)
	local w = cellWidth(size, self.frame, o)
	if w == self.width then
		self:took(size)
		return
	end
	if ns.deferWhileAurasSecret(o.sites.style, function() self:styleNow() end) then return end
	self:wait()
	local ok = ns.try(o.sites.style, function()
		self.container:SetFrameStrata(self.frame:GetFrameStrata())
		self.container:SetAuraGroupLayout(o.key,
			{ elementWidth = w + CLIP_SLACK, elementHeight = w })
		self.cell:SetSize(w, w)
	end)
	if ok then
		self.width = w
		self:took(size)
	else
		ns.retryAfterCombat(o.sites.style, function() self:styleNow() end)
	end
end

-- Only when the filters changed: a refilter holds the look off for two frames
function ClipLook:refilter()
	if not self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.filter, function() self:refilter() end) then return end
	local filters = candidates(o)
	if filterSig(filters) == self.applied then return end
	self:wait()
	if ns.try(o.sites.filter, self.container.SetAuraGroupCandidateFilters, self.container, o.key, filters) then
		self:took(nil, filters)
	else
		ns.retryAfterCombat(o.sites.filter, function() self:refilter() end)
	end
end

-- Allowed in combat: Blizzard restricts the aura button, not the container.
function ClipLook:follow(unit)
	local c = self.container
	if not c or self.err then return true end
	local ok = true
	if self.unit ~= unit then ok = ns.try(self.opts.sites.container .. " unit", c.SetUnit, c, unit)
	elseif unit ~= "none" then
		ok = ns.try(self.opts.sites.container .. " refresh", c.UpdateAllAuras, c)
	end
	self.unit = ok and unit or nil
	self:wait()
	return ok
end

-- up: the glow's level over the look (2 over a look whose edge carries an art frame)
function ClipLook:setLevel(lv, up)
	for _, f in ipairs({ self.hold, self.clip, self.look, self.art }) do
		f:SetFrameLevel(lv)
	end
	self.glow:SetFrameLevel(lv + (up or 1))
	self.glow.inner:SetFrameLevel(lv + (up or 1))
end

function ClipLook:describe()
	return string.format(
		"%ssensor %s%s, size %s (icon %s), filters %s, unit %s, wanted %s, waiting %s, drawn %s",
		self.opts.invert and "while up: " or "",
		self.container and "made" or "not made", self.err and (" (error: " .. self.err .. ")") or "",
		tostring(self.size), tostring(ns.sizeOf(self.opts.key)),
		not self.idsOK and "behind" or (self.opts.agrees and not self.opts.agrees()) and "not the slot's"
			or "matched",
		tostring(self.unit), tostring(self.wanted), tostring(self.waiting ~= nil),
		self.glow.look and self.glow.look.key or "none")
end

function ns.makeIcon(parent, size, owner)
	local f = CreateFrame("Frame", nil, parent)
	f.owner = owner
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	ns.cropIconExact(f.tex)
	f.manaOverlay = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.manaOverlay:SetAllPoints(f.tex)
	f.manaOverlay:SetColorTexture(0.2, 0.45, 1, 0.55)
	f.manaOverlay:Hide()
	f.SetBodyPaint = function(self, style, r, g, b, overlayAlpha, tintStrength)
		if style == "overlay" or style == "both" then
			self.manaOverlay:SetColorTexture(r, g, b, overlayAlpha)
			self.manaOverlay:Show()
		end
		if style == "tint" or style == "both" then
			local k = 1 - tintStrength
			self.tex:SetVertexColor(r == 1 and 1 or k, g == 1 and 1 or k, b == 1 and 1 or k)
		end
	end
	-- Levels over the icon: its art frame (ns.Frames.LEVEL.over), glow, swipe, text
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetFrameLevel(f:GetFrameLevel() + 3)
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	-- Text above the cooldown so the swipe never dims it.
	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints()
	f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.count = f.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	ns.Media.setFont(f.count, owner, math.floor(size * 0.45))
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	f.count:SetJustifyH("RIGHT")
	local okFS, cdText = pcall(f.cd.GetCountdownFontString, f.cd)
	if okFS and cdText then pcall(cdText.SetDrawLayer, cdText, "OVERLAY", 7) end
	f.ring = ns.makeRing(f.textFrame, f.tex)
	f.pulse = ns.makePulse(f.tex, "fade")
	f.SetPulsing = function(self, on)
		if not on then self.pulse:Stop()
		elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	end
	f.SetRingShown = function(self, shown, r, g, b, a)
		if shown then self.ring:color(r, g, b, a) end
		self.ring:show(shown)
	end
	f.fx = ns.Effects.host(f, owner)
	f.glowF = f.fx.glowF
	f.glowF:SetFrameLevel(f:GetFrameLevel() + 2)
	f.SetGlowShown = function(self, shown, r, g, b) self.fx:glow(shown, r, g, b) end
	f.SetWarnParts = function(self, grey, tint, ring, fade, glow)
		self.tex:SetDesaturated(grey and true or false)
		-- The colour is set only when the tint changes (other looks colour this icon too); whoever
		-- sets the colour itself clears warnTint
		tint = tint and true or false
		if tint ~= (self.warnTint or false) then
			self.warnTint = tint
			if tint then self.tex:SetVertexColor(1, 0.35, 0.35)
			else self.tex:SetVertexColor(1, 1, 1) end
		end
		self:SetRingShown(ring)
		self:SetPulsing(fade)
		self:SetGlowShown(glow)
	end
	f.Pop = function(self, kind) self.fx:pop(kind) end
	return f
end
