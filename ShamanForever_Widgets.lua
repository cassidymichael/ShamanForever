-- Widgets shared by the HUD, the totem bar and the options previews: text on icons, pixel
-- placement, warning rings and pulses, the aura slot, the clip look and the element icon (its glow
-- and pop are ns.Effects'). Looks come from ns.Style; nothing here reads settings of its own.

local _, ns = ...

-- The five element schools' colours (spirit covers anything mixed): the totem bar's slots, the
-- options' art.
ns.SCHOOL_COLOR = {
	earth  = { 0.75, 0.54, 0.24 },
	fire   = { 0.89, 0.38, 0.18 },
	water  = { 0.25, 0.69, 0.77 },
	air    = { 0.56, 0.76, 0.92 },
	spirit = { 0.73, 0.64, 0.90 },
}
-- The same, a little brighter, for bars: a textured fill (the default Blizzard one) darkens its
-- colour.
ns.SCHOOL_BAR_COLOR = {}
for school, c in pairs(ns.SCHOOL_COLOR) do
	ns.SCHOOL_BAR_COLOR[school] = { math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15) }
end

-- A flat backdrop: a solid fill and a 1 px edge, coloured by the caller.
ns.BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

-- A spell icon without Blizzard's built-in border.
function ns.cropIcon(tex) tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
-- The same, drawn at its frame's exact rect: for an element's icon and the copies laid over it,
-- which a cooldown swipe covers. A texture snaps to the pixel grid, and a cropped one's edge can
-- round to a different pixel than the swipe's, which doesn't snap: at some positions and scales a
-- 1 px sliver of icon shows past the swipe's edge. Unsnapped, it fills the rect the swipe fills;
-- at a half-pixel edge no two layers agree, so the HUD also sits icons on whole pixels
-- (ns.placeOnPixels).
function ns.cropIconExact(tex)
	ns.cropIcon(tex)
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
		tex:SetTexelSnappingBias(0)
	end
end

-- The places a number on an icon can sit (the shield's charges, a reagent count), and how its text
-- is justified at each.
ns.COUNT_JUSTIFY = { TOPLEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
	CENTER = "CENTER" }

-- The icon size text sizes are given at (the default): text on an icon scales with it from here.
ns.BASE_ICON_SIZE = 44
-- A font string on an icon: size at the base icon size (it grows and shrinks with the icon), placed
-- at a point of the icon (a corner, CENTER, or TOP / BOTTOM for text above or below it) with an
-- offset, in General's text style. Restated only when something changed; returns the font size
-- used.
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

-- The key bound to a totem bar button, in its top-right corner: a light grey label whose font the
-- caller sets, at keyTextSize.
function ns.makeKeyText(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	fs:SetPoint("TOPRIGHT", -2, -2)
	fs:SetTextColor(0.85, 0.85, 0.85)
	return fs
end
-- Its font size on an icon size pixels wide, for a size set at the base icon size: it scales with
-- the icon.
function ns.keyTextSize(size, base) return math.max(6, math.floor(base * size / ns.BASE_ICON_SIZE + 0.5)) end
-- A binding's key in the compact form action bar addons use (Bartender's and Dominos' LibKeyBound,
-- ElvUI): a letter per modifier, then the key, short: "SWU" for Shift + Mouse Wheel Up, "C5" for
-- Ctrl-5, "AM4" for Alt + Mouse Button 4, "N7" for Num Pad 7. A key without a short name here
-- takes the client's own short text for it (GetBindingText's abbreviated form). "" for none.
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
local keyLabels = {}   -- binding key -> its label
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

-- An element icon easing to a new opacity: slowly into idle, quickly back (each rate covers 0 to 1).
-- A frame above Blizzard's protected aura button (frame.aboveProtected) takes no alpha change in
-- combat, so its fade is dropped then and restated after combat by its owner's refresh.
local FADE_OUT, FADE_IN = 0.8, 0.15
local fading = {}   -- frame -> target alpha
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

------------------------------------------------------------------------
-- Lines (borders, warning rings, the range strip) are measured in screen pixels, so they stay crisp:
-- n pixels at scale 1. A Scale between the screen and the frame (a group's, the totem bar's, a
-- preview's) grows them with everything else, rounded to whole pixels. Icon Size doesn't.
------------------------------------------------------------------------
-- One screen pixel, in a frame's own units.
function ns.pixel(frame)
	local _, physicalHeight = GetPhysicalScreenSize()
	return 768 / (physicalHeight or 768) / frame:GetEffectiveScale()
end
-- v rounded to whole screen pixels; px is ns.pixel of the frame v is measured in.
function ns.roundPx(v, px) return math.floor(v / px + 0.5) * px end

-- The length, in the frame's own units, of n screen pixels grown by the frame's Scale.
function ns.linePx(frame, n)
	local count = math.floor(n * frame:GetEffectiveScale() / UIParent:GetEffectiveScale() + 0.5)
	if n > 0 and count < 1 then count = 1 end
	return count * ns.pixel(frame)
end

-- Anchors a frame at point on UIParent, x and y in the frame's own units as SetPoint takes them,
-- moved by under a pixel so its top left sits on a whole screen pixel; with a size in whole pixels,
-- so do its other edges. The HUD's icons are laid out on whole pixels from there: at a half-pixel
-- edge an icon's texture and its border, which snap to the pixel grid, and its cooldown swipe,
-- which doesn't, each draw that edge differently, and a sliver of one shows past another.
function ns.placeOnPixels(frame, point, x, y)
	local px = ns.pixel(frame)
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()   -- UIParent's units to the frame's
	local pw, ph = UIParent:GetSize()
	local w, h = frame:GetSize()
	local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
	local fy = point:find("BOTTOM") and 0 or point:find("TOP") and 1 or 0.5
	local left = fx * pw * k + x - fx * w
	local top = fy * ph * k + y + (1 - fy) * h
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, point, x + ns.roundPx(left, px) - left, y + ns.roundPx(top, px) - top)
end

------------------------------------------------------------------------
-- Warning looks shared by the HUD, the totem bar and the options previews
------------------------------------------------------------------------
-- A ring just inside an icon's edge: four textures, the side ones between the top and bottom ones
-- (no doubled corners). Its thickness is a line's (ns.linePx): crisp, the same at any icon size.
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
-- A colour other than the warning red (the shock's blue "no mana" ring); no arguments: the red.
function Ring:color(red, g, b, a)
	local k = RING_COLOR
	for _, t in ipairs(self.edges) do t:SetColorTexture(red or k[1], g or k[2], b or k[3], a or k[4]) end
end
-- Sizes the edges for the anchor's current scale; re-anchors only when that changed.
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
-- After a layout (a group's or the bar's Scale may have changed): every ring on screen re-measures.
function ns.refitRings()
	for r in pairs(rings) do
		if r.edges[1]:IsShown() then r:fit() end
	end
end

-- A looping pulse on a region. "fade": the region itself breathes, 100% to 35% over 0.8 s (missing
-- looks). "dim": a dark layer from 0 to 55% over 0.6 s (expiring; it dims the icon, never the text
-- above it). Returns the animation group.
function ns.makePulse(region, kind)
	local g = region:CreateAnimationGroup()
	g:SetLooping("BOUNCE")
	local a = g:CreateAnimation("Alpha")
	if kind == "dim" then a:SetFromAlpha(0); a:SetToAlpha(0.55); a:SetDuration(0.6)
	else a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.8) end
	a:SetSmoothing("IN_OUT")
	return g
end

-- The global cooldown's sweep, as on action bars: its own Cooldown over an icon, a dark swipe with no
-- edge, bling or numbers. The caller sets its frame level.
function ns.makeGCDSweep(parent)
	local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
	cd:SetSwipeColor(0, 0, 0, 0.6)
	ns.Looks.followSwipe(parent, cd)   -- a rounded or cut-corner icon's shape
	return cd
end

------------------------------------------------------------------------
-- An aura slot: Blizzard's aura container on an element icon, with one aura slot whose button
-- Blizzard (untainted) shows while an aura it matches is up and draws that aura's icon, time left
-- and charges, exact in combat too. It is the one way to show an aura in combat: addon reads of
-- auras then throw (by index or instance) or come back empty (by spell). Used by the shield and
-- Elemental Focus.
-- What it takes:
-- * The container and its button refuse addon calls in combat and while auras are secret, which
--   can also happen out of combat (PvP matches, encounters). So the container is made, and it and
--   the button restyled, only outside both; anything asked for meanwhile waits for them to end
--   (ns.deferWhileAurasSecret), and a refused call is noted for /sf debug and tried again then.
-- * An intrinsic frame doesn't inherit placement: the container takes the icon's strata (HIGH
--   would float over other addons' dialogs) and a frame level above the icon's text, so it sits
--   over the icon and its rings. Regrouping reparents the icon, which can drop the container back
--   under them, so each restyle restates both.
-- * The slot's button is placed by us (at the container's corner), not by the container's flow.
-- * Mouse input goes off before Blizzard locks the button down: no tooltip, clicks pass through.
-- * Script handlers on anything under the button never run (OnShow and OnHide on a child fired
--   zero times, tested 2026-09-23), so nothing tells addon code when it shows or hides; the button
--   only plays animations handed to it (Blizzard_CustomAuraButton.lua).
------------------------------------------------------------------------
local AuraSlot = {}
AuraSlot.__index = AuraSlot

-- frame: the element icon it covers. opts:
--   key          the element: its icon size (ns.sizeOf) and its timer's style
--   slot, ids()  the aura slot's name, and the spell ID map it matches (read when it is made)
--   parent       what the container hangs from (default frame); name: a global name, or nil
--   level        frame levels above the usual (optional): a slot drawn over another's parts
--   sites        { container = , style = , filter = }: names for its waiting work and caught errors
--   iconAlpha()  the aura icon's alpha as the button is made (optional)
--   ownIcon()    a texture to show on the button in place of the aura's icon (optional): set once,
--                as the button is made, and never handed to Blizzard as its icon, so the aura's
--                icon never shows and Blizzard never writes to ours (a pop's animation may still
--                move it)
--   noTimer      no time left: the button is handed no cooldown or bar, and the slot has no timer
--   host(slot, button)  a frame of the caller's under the button, covering it, that the icon, its
--                border look and the timer go on in place of the button itself (optional; made as
--                Blizzard makes the button, before them): parts that show only within a clip there
--                (the icon can't be clipped from the button's own parent chain). slot.host is it
--                (the button itself when there is none)
--   extras       { { key, init(slot, button) }, ... }: more slots in the same container, taking the
--                same aura (its candidate filters), each a bare button of its own (no icon) laid
--                over the first, frame levels above it in order, for parts the one button can't
--                hold (it drives one bar and one text); init makes its parts, as Blizzard makes it.
--                slot.extras[key] is its button.
--   barInset()   how far above the bottom edge its time bar sits there (optional; ns.Timer.new)
--   onButton(slot, button, cd)  the caller's own parts, once Blizzard has made the button
--   onStyle(slot, size)         the caller's own restyle, after the shared one
--   onError(err)                the container couldn't be made on this client
-- Nothing is made until slot:setup(). The slot then holds container, button, icon (the aura's
-- texture), cd and timer (swipe, countdown and time bar), or err; size, the size its button was last
-- given; and after slot:refilter(), filtered (the spell IDs it last gave the slot).
function ns.makeAuraSlot(frame, opts)
	return setmetatable({ frame = frame, opts = opts }, AuraSlot)
end

-- Called by Blizzard (untainted) once, right after it makes the slot's button.
local function initAuraButton(slot, button)
	local o = slot.opts
	local size = ns.sizeOf(o.key)
	button:SetSize(size, size)
	slot.size = size
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	local host = o.host and o.host(slot, button) or button
	slot.host = host
	local tex = host:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	ns.cropIconExact(tex)
	if o.iconAlpha then tex:SetAlpha(o.iconAlpha()) end
	if o.ownIcon then tex:SetTexture(o.ownIcon()) else button:SetIcon(tex) end
	slot.icon = tex
	-- A frame look's mask and art: only now, as the button is made (ns.Looks.auraMask).
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
	-- Its timer: swipe and countdown on the Cooldown, and a time bar the button drives from the
	-- aura's own time (SetDurationBar; a bar of ours followed it in combat, tested 2026-09-27). We
	-- only style and show the bar. A client that refuses it gets no bar rather than a still one.
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

-- An extra slot's button (opts.extras), called by Blizzard as it makes it: placed over the first,
-- no mouse, and its parts.
local function initExtraButton(slot, x, button)
	local size = ns.sizeOf(slot.opts.key)
	button:SetSize(size, size)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	slot.extras = slot.extras or {}
	slot.extras[x.key] = button
	x.init(slot, button)
end

-- The slot's candidate filters: opts.candidates() if given, else its spell IDs.
local function candidates(o)
	if o.candidates then return o.candidates() end
	return { includeSpellIDs = o.ids() }
end

-- A string that is the same for two candidate filter tables exactly when they match the same
-- auras: what an aura slot and a clip look last took, compared (ns.makeClipLook's agrees).
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

-- Makes the container and its slot, once (out of combat, auras readable; else when that ends).
-- Once made it stays; a client that refuses it gets err and onError. Beside the opts above, it
-- takes unit (default "player"), filter (default "HELPFUL") and candidates() (the slot's
-- candidate filters, in place of includeSpellIDs = ids()). slot.applied: the filters it last took
-- (filterSig), nil while not known.
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
		self.applied = filterSig(filters)
		self:style()   -- a layout queued before it (a /reload in combat) found no button to style
	end
end

-- The container's size and placement, the button's size and its timer's style, then the caller's
-- own parts (onStyle). Out of combat only, and not while auras are secret: waits for that, and
-- one refused call (the whole restyle is one pcall) is noted and tried again when combat ends.
-- Once a frame at most, on the next: one layout asks several times (afterGroups, applyTimers,
-- applyLayout), and the options lay out every frame while a slider is dragged.
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
		-- Extra slots' buttons over the first and its parts, in order, two levels apart (their own
		-- parts take the level between); set from our own levels, never read back from the buttons.
		for i, x in ipairs(o.extras or {}) do
			local b = self.extras and self.extras[x.key]
			if b then
				b:SetSize(size, size)
				b:SetFrameLevel(f.textFrame:GetFrameLevel() + 5 + 2 * i + 2)
			end
		end
		-- Its own try: a look the button refuses mustn't stop the timer and the caller's parts.
		ns.try(o.sites.style .. ": look", ns.Looks.auraStyle, self, size)
		if self.timer then self.timer:apply() end
		if o.onStyle then o.onStyle(self, size) end
	end)
	if not ok then ns.retryAfterCombat(o.sites.style, function() self:styleNow() end) end
end

-- The slot's filters again, from opts.ids() (the IDs that count can grow) or opts.candidates(),
-- once the container is made. Out of combat only, and not while auras are secret: waits for that,
-- and a refused call is noted and tried again when combat ends.
function AuraSlot:refilter()
	if not self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.filter, function() self:refilter() end) then return end
	local filters = candidates(o)
	self.applied = nil   -- until every slot has taken them
	local ok = ns.try(o.sites.filter, self.container.SetAuraSlotCandidateFilters, self.container, o.slot, filters)
	-- The extras last to first: a part that covers another (Flame Shock's Expiring cover) comes after
	-- what it covers, so a refilter that stops part way leaves no uncovered part taking a new aura.
	local extras = o.extras or {}
	for i = #extras, 1, -1 do
		if ok then
			ok = ns.try(o.sites.filter, self.container.SetAuraSlotCandidateFilters, self.container,
				o.slot .. "-" .. extras[i].key, filters)
		end
	end
	if ok then self.filtered, self.applied = filters.includeSpellIDs, filterSig(filters)
	else ns.retryAfterCombat(o.sites.filter, function() self:refilter() end) end
end

------------------------------------------------------------------------
-- A clip look: a missing look (the icon's picture, grey or tinted, a red ring, a fade in and out,
-- and a pulsing glow that may reach past the icon's edge), shown exactly while an aura is gone, in
-- combat too, with nothing read (tested in combat 2026-09-30). Inverted (opts.invert), the same
-- glow shown exactly while the aura is up (tested in combat 2026-10-01).
-- * The sensor: a container of its own with one aura group of one invisible button, as big as the
--   look's reach (the cell) and CLIP_SLACK wider. Blizzard sizes a group's container to its
--   buttons: to the button while the aura is up, to 1 px once it's gone. Its width is secret;
--   nothing of ours reads it.
-- * A clip frame of ours runs from the container's right edge to the cell's right edge: nothing
--   while the aura is up (the button is a little wider than the cell), the whole cell once it's
--   gone. Inverted, it runs from the container's left edge to CLIP_SLACK inside its right edge:
--   the cell while the aura is up, nothing once it's gone (with the clip on the right edge itself,
--   about 1 px of the look showed with the aura down; 2 px inside, none). The look inside it is
--   drawn only there, by the engine. So nothing of it lies under the aura's own icon, and that
--   icon can take its group's opacity like any other.
-- * Frames anchored to a container with an aura group must inherit
--   DisableUntrustedLayoutScriptsTemplate as they are made (Blizzard's note in AddAuraGroup): the
--   clip and the look's holder do.
-- * The chain: hold (its alpha ours, allowed in combat) > clip > look > the picture and ring (art),
--   and the glow over them. The sensor hangs apart, so it keeps up with the aura while the
--   chain is hidden.
-- * The sensor is made, restyled and refiltered only out of combat with auras readable, as an aura
--   slot is. The hold stays at 0 while the sensor can't be trusted: not made, a size or filters it
--   hasn't taken yet, not on the unit asked for, and for two frames after it's made, restyled,
--   pointed at a unit or shown (Blizzard's container catches up on its next frame). A change
--   waiting for combat's end is a miss, never a false warning.
-- * Inverted, beside the aura slot that shows the aura: the sensor must match exactly what the slot
--   matches (opts.agrees), or the glow could show with no aura shown, a false state.
------------------------------------------------------------------------
local ClipLook = {}
ClipLook.__index = ClipLook
-- The sensor's button is this much wider than the cell: the clip empty, not 1 px.
local CLIP_SLACK = 2
-- How far the look reaches from the icon's centre, in widths of the icon with its frame: the Proc
-- glow's opening burst, the widest look, reaches 150/45 of the icon with its frame (its flipbook is
-- 150 wide for a 45 icon; Heartbeat's ring reaches 1.22), so 1.7 has 0.07 to spare. A look that
-- reaches further is clipped: raise this with it.
local CLIP_REACH = 1.7

-- Every texture under frame (but masks: they take none) in icon frame f's look's shape, over the
-- rect of over (Looks.maskOver: re-placed on each call and look change).
local function shapeTextures(frame, f, over)
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("Texture") and not r:IsObjectType("MaskTexture") then
			ns.Looks.maskOver(f, r, over)
		end
	end
	for _, c in ipairs({ frame:GetChildren() }) do shapeTextures(c, f, over) end
end

-- frame: the element icon the look is drawn on (its picture, frame.tex, and round it). opts:
--   key            the element: its icon size (ns.sizeOf); also the aura group's name
--   parent         what the chain hangs from; sensorParent, what the sensor hangs from (shown
--                  whenever the chain may be)
--   unit, filter   the sensor's unit as it's made (default "player"; a function: its answer then)
--                  and filter (default "HELPFUL")
--   ids()          the spell IDs it matches; or candidates(), its candidate filters (an aura
--                  slot's: ns.makeAuraSlot)
--   needUnit       the unit it must be on for the look to show (a sensor that follows the target)
--   owner          the glow's style owner (nil: General's), its look, colour and the rest
--   invert         lit while the aura is up, not while it's gone
--   glowOnly       the glow alone: no picture, no ring
--   agrees()       whether the aura slot showing the aura took the filters the sensor did
--                  (h.applied), for an inverted look (optional)
--   sites          { container = , style = , filter = }: names for waiting work and caught errors
-- Its parts: h.tex (the icon's picture; the caller sets its texture), h.ring, h.pulse (the
-- picture's fade) and h.glow (ns.Effects.glow). The glow looks drawn within the icon (`inside`,
-- ns.Looks) take the icon's rounded or cut-corner shape over the picture; the looks that reach past
-- it take none. h:want(on) shows the look or not, h:setParts which of its parts show; nothing is
-- made until h:setup(). h.filtered: the spell IDs its sensor last took; h.applied: its filters.
function ns.makeClipLook(frame, opts)
	local h = setmetatable({ frame = frame, opts = opts }, ClipLook)
	h.hold = CreateFrame("Frame", nil, opts.parent)
	h.hold:SetAllPoints(frame)
	h.hold:SetAlpha(0)
	h.hold:SetScript("OnShow", function()
		h:wait()
		if h.fadeOn then h.pulse:Play() end   -- a hidden frame's animations stop
	end)
	h.tick = function(f)   -- the wait's OnUpdate (wait)
		h.waiting = h.waiting - 1
		if h.waiting > 0 then return end
		h.waiting = nil
		f:SetScript("OnUpdate", nil)
		h:update()
	end
	-- The cell: the look's reach, centred on the icon, sized only as the sensor is (style).
	h.cell = CreateFrame("Frame", nil, opts.sensorParent)
	h.cell:SetPoint("CENTER", frame, "CENTER", 0, 0)
	h.cell:SetSize(1, 1)
	h.clip = CreateFrame("Frame", nil, h.hold, "DisableUntrustedLayoutScriptsTemplate")
	h.clip:SetClipsChildren(true)
	-- Empty until the sensor is made (setup): from the cell's right edge to itself.
	h.clip:SetPoint("TOPLEFT", h.cell, "TOPRIGHT", 0, 0)
	h.clip:SetPoint("BOTTOMRIGHT", h.cell, "BOTTOMRIGHT", 0, 0)
	h.look = CreateFrame("Frame", nil, h.clip, "DisableUntrustedLayoutScriptsTemplate")
	h.look:SetAllPoints(h.cell)
	-- The picture over the icon's own, with its ring just inside its edge, under the glow.
	h.art = CreateFrame("Frame", nil, h.look)
	h.art:SetAllPoints(frame)
	h.tex = h.art:CreateTexture(nil, "ARTWORK")
	ns.cropIconExact(h.tex)
	h.tex:SetAllPoints(frame.tex)
	h.ring = ns.makeRing(h.art, h.tex)
	h.pulse = ns.makePulse(h.tex, "fade")
	if opts.glowOnly then h.art:Hide() end
	h.glow = ns.Effects.glow(h.look, frame, opts.owner)
	-- As a look's parts are made and each time they're fitted (a look changed with the options
	-- open, in combat too).
	h.glow.onLayout = function(_, parts, look)
		if not look.inside then return end
		for _, r in ipairs(parts.roots or {}) do shapeTextures(r, frame, h.tex) end
	end
	for key, parts in pairs(h.glow.parts) do
		if parts then h.glow.onLayout(h.glow, parts, ns.Style.look("glow", key)) end
	end
	return h
end

-- The cell's width for an icon of size: the look's reach both ways, with the icon's frame.
local function cellWidth(size, frame)
	return math.ceil(2 * CLIP_REACH * (size + 2 * ns.Looks.outerEdge(frame)))
end

-- The hold at 0 now, and back on its second OnUpdate from here. Blizzard's container updates in its
-- own next OnUpdate after a change (or after it shows), in this frame's pass or the next one's; the
-- hold comes back a pass after that, so before the frame drawn after that update, never the one
-- before. Our own frame: allowed in combat.
function ClipLook:wait()
	self.waiting = 2
	self.hold:SetAlpha(0)
	self.hold:SetScript("OnUpdate", self.tick)
end

-- Whether the sensor can be trusted now (see above).
function ClipLook:ready()
	local o = self.opts
	return self.container ~= nil and not self.err and self.idsOK == true and not self.waiting
		and self.size == ns.sizeOf(o.key) and (o.needUnit == nil or self.unit == o.needUnit)
		and (o.agrees == nil or o.agrees() == true)
end

-- The hold's alpha: 1 while the caller wants the look and the sensor can be trusted, else 0. Our
-- own frame: allowed in combat.
function ClipLook:update()
	self.hold:SetAlpha((self.wanted and self:ready()) and 1 or 0)
end

-- The caller's condition for the look (whatever its own warning waits for).
function ClipLook:want(on)
	self.wanted = on and true or false
	self:update()
end

-- Which parts of the look show: the picture grey, tinted red, the ring, the picture's fade in and
-- out, the glow. Our own frames and textures: allowed in combat.
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

-- The picture and ring in the icon's look's shape now, the border look's inner art over them (the
-- look's own border part: it shows exactly while the aura is gone, where the aura button's copy
-- of it isn't), and the glow in its look now (after a layout, a size or a look change).
function ClipLook:reshape()
	if self.opts.glowOnly then self.glow:restyle() return end
	local f = self.frame
	ns.Looks.overlay(self.art, ns.borderFor(self.opts.key))
	ns.Looks.maskOver(f, self.tex)
	for _, e in ipairs(self.ring.edges) do ns.Looks.maskOver(f, e, self.tex) end
	self.glow:restyle()
end

-- The sensor's candidate filters now: opts.candidates(), else its spell IDs.
local function sensorFilters(o)
	if o.candidates then return o.candidates() end
	return { includeSpellIDs = o.ids() }
end

-- The clip over the made sensor c: from its right edge to the cell's (lit while the aura is gone),
-- or inverted from its left edge to CLIP_SLACK inside its right edge (lit while it's up).
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

-- Makes the sensor, once (out of combat, auras readable; else when that ends). Once made it stays;
-- a client that refuses it gets err, and the look never shows.
function ClipLook:setup()
	if self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.container, function() self:setup() end) then return end
	local size = ns.sizeOf(o.key)
	local w = cellWidth(size, self.frame)
	local filters = sensorFilters(o)
	local unit = type(o.unit) == "function" and o.unit() or o.unit or "player"
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", nil, o.sensorParent, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", self.cell, "TOPLEFT", 0, 0)
		-- An intrinsic frame doesn't inherit placement (see the aura slot, above).
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
				pcall(b.EnableMouse, b, false)
				pcall(b.SetMouseClickEnabled, b, false)
				pcall(b.SetMouseMotionEnabled, b, false)
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

-- Records the size and filters the sensor now has, and fits the glow to that size.
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

-- Whether the sensor matches what it should now. By spell IDs: every one ids() gives (a sensor
-- missing one would stay empty over that aura, a false warning); call it whenever those may have
-- grown. By candidate filters: exactly those candidates() gives.
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

-- The sensor and the look for the icon's size now: at once while nothing changed, else the sensor
-- waits for combat's end and auras readable, and the hold stays at 0 meanwhile (ready). Once a
-- frame at most, on the next.
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
	local w = cellWidth(size, self.frame)
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

-- The sensor's filters again, from ids() or candidates() (out of combat, auras readable; else
-- when that ends).
function ClipLook:refilter()
	if not self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.filter, function() self:refilter() end) then return end
	local filters = sensorFilters(o)
	self:wait()
	if ns.try(o.sites.filter, self.container.SetAuraGroupCandidateFilters, self.container, o.key, filters) then
		self:took(nil, filters)
	else
		ns.retryAfterCombat(o.sites.filter, function() self:refilter() end)
	end
end

-- Points the sensor at unit ("none" for no unit), or refreshes it on the same one (a new target
-- that is the same kind of unit). Allowed in combat: Blizzard restricts the aura button, not the
-- container. Returns false when the client refused; the hold stays at 0 until a call works.
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

-- Frame levels: the chain and the picture at lv; the glow and its breathing layer a level above
-- (its look's parts take that level as it shows, Looks.levelParts).
function ClipLook:setLevel(lv)
	for _, f in ipairs({ self.hold, self.clip, self.look, self.art }) do
		f:SetFrameLevel(lv)
	end
	self.glow:SetFrameLevel(lv + 1)
	self.glow.inner:SetFrameLevel(lv + 1)
end

-- For /sf debug: one line of its state.
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

-- owner: whose glow and pop style it uses (an element key, "totembar", or nil for General's).
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
	-- The shock's body colour (out of range, no mana): an overlay over the art, a tint of the art, or
	-- both. style: overlay | tint | both; the caller clears it first.
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
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	-- Text sits on its own frame above the cooldown so the swipe never dims it.
	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints()
	f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.count = f.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	ns.Media.setFont(f.count, owner, math.floor(size * 0.45))
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	f.count:SetJustifyH("RIGHT")
	local okFS, cdText = pcall(f.cd.GetCountdownFontString, f.cd)
	if okFS and cdText then pcall(cdText.SetDrawLayer, cdText, "OVERLAY", 7) end
	-- Red ring just inside the icon edge (ns.makeRing), so an exact-size frame on top covers it completely.
	f.ring = ns.makeRing(f.textFrame, f.tex)
	-- Pulse: the icon fades in and out, used for "missing" warnings.
	f.pulse = ns.makePulse(f.tex, "fade")
	f.SetPulsing = function(self, on)
		if not on then self.pulse:Stop()
		elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	end
	-- r, g, b, a: a colour other than the warning red (the shock's blue "no mana" ring).
	f.SetRingShown = function(self, shown, r, g, b, a)
		if shown then self.ring:color(r, g, b, a) end
		self.ring:show(shown)
	end
	-- Glow (gold by default) and pop, for warnings and moments worth catching the eye: its effect
	-- host's (ns.Effects).
	f.fx = ns.Effects.host(f, owner)
	f.glowF = f.fx.glowF
	f.SetGlowShown = function(self, shown, r, g, b) self.fx:glow(shown, r, g, b) end
	f.Pop = function(self, kind) self.fx:pop(kind) end
	return f
end
