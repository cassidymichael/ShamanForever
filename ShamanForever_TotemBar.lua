-- Totem bar
-- Every click is a secure button set up out of combat, so it works in combat: slot buttons
-- (destroytotem, multi-cast action), pickers opened by a secure header's snippets, and "multispell"
-- popout buttons (spell 0 is "No totem"). Layout, attributes and anything that shows, hides or
-- moves a secure button happen out of combat only; what the player sees sits on plain frames over
-- them.
-- Verbs: apply (settings changed), layout (out of combat), refresh (read the slots and show them),
-- draw (ten times a second).
-- In combat the totem in a slot is secret: its icon goes straight to SetTexture, timers use the
-- slot's duration object, warnings are a curve into SetAlpha. Which totem it is comes from our own
-- casts (ns.Totems), by spell ID.

local _, ns = ...

local TB = { name = "totem bar" }
ns.TotemBar = TB

local ELEMENTS = { "earth", "fire", "water", "air" }
local SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
local NAME = { earth = "Earth", fire = "Fire", water = "Water", air = "Air" }
TB.ELEMENTS, TB.NAME, TB.SLOT = ELEMENTS, NAME, SLOT

TB.DEFAULTS = {
	mode = "everything",   -- blizzard | active | everything
	point = "CENTER", x = -353, y = -182,
	scale = 1,
	alpha = 1,
	-- always | active (in combat or a totem down) | combat | target (in combat or with an enemy target)
	show = "always",
	fadeAfter = 0,   -- seconds it stays once combat ends (0: none)
	order = { "fire", "earth", "water", "air" },
	hidden = {},
	dir = "row",
	pop = "up",   -- up | down (row), right | left (column)
	spacing = 2,
	-- The Buttons settings apply only in Everything
	cast = true,
	arrows = true,
	arrowSize = 20,
	tips = "ooc",   -- always | ooc | never
	keys = false,
	keySize = 13,
	keyX = 0, keyY = 0,
	keyColor = { 0.85, 0.85, 0.85, 1 },
	call = true,
	recall = true,
	extras = "after",   -- ends | before | after the slots
	extrasScale = 0.8,
	sizeFollow = true,
	empty = "pick",   -- pick | frame | blank
	idleGrey = false,
	idleAlpha = 0.35,
	offPick = true,
	badgeSize = 0.45,
	badgeAlpha = 0.75,
	badgeSat = 0.5,
	badgeX = 0, badgeY = 0,
	warnGrey = false,
	warnRing = false,
	warnPulse = true,
	warnGlow = false,
	expiredPop = true,
	goneSound = "none",
	warn = 10,   -- seconds before the end (0: off)
	-- Totem -> seconds, instead of warn; keyed by the client's rank-less spell name. cfg() fills the
	-- defaults in the client's language
	warnOver = {},
	killed = true,
	killedPop = true,
	killedGlow = true,
	killedMark = true,
	range = true,
	rangeHeight = 5,
	rangeIn = { 0.2, 0.8, 0.25, 0 },
	rangeOut = { 0.9, 0.12, 0.08, 0.85 },
	pickHover = true,
	skin = "default",
	pixelTray = true,
	pixelEdge = 1,
	stonePlinth = "normal",   -- slim | normal | grand
	stoneExtrasScale = 1,
	barPlace = "in",   -- in | out
}

local isSecret = ns.isSecret

local RANGES = {
	scale = { 0.5, 3 }, alpha = { 0.1, 1 }, spacing = { -10, 20 }, size = { 24, 96 },
	arrowSize = { 8, 32 }, extrasScale = { 0.5, 1.5 }, idleAlpha = { 0.1, 1 },
	badgeSize = { 0.25, 0.8 }, badgeAlpha = { 0.1, 1 }, badgeSat = { 0, 1 }, warn = { 0, 30 }, rangeHeight = { 1, 12 },
	fadeAfter = { 0, 10 }, badgeX = { -30, 30 }, badgeY = { -30, 30 }, keySize = { 6, 30 }, keyX = { -20, 20 }, keyY = { -20, 20 }, pixelEdge = { 1, 4 }, stoneExtrasScale = { 0.5, 1.5 },
}
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, r) return math.min(math.max(v, r[1]), r[2]) end

local WARN_OVER = { earthbind = 5, stoneclaw = 5, manaTide = 3 }

function TB.warnOverDefaults()
	local out = {}
	for key, secs in pairs(WARN_OVER) do out[ns.Spells.name(key)] = secs end
	return out
end

function TB.warnOverChanged(over)
	local seen = {}
	for key, secs in pairs(WARN_OVER) do
		local name = ns.Spells.name(key)
		if over[name] == nil then name = ns.Spells.DEFS[key].en end
		if over[name] ~= secs then return true end
		seen[name] = true
	end
	for name in pairs(over) do
		if not seen[name] then return true end
	end
	return false
end

local cfgTable
local function cfg()
	local db = ns.getDB()
	if type(db.totemBar) ~= "table" then db.totemBar = {} end
	local t = db.totemBar
	if t ~= cfgTable then
		if t.mode == nil and (t.enabled == false or t.show == "never") then t.mode = "blizzard" end
		if t.follow == false then
			t.sizeFollow = false
			if type(t.border) == "table" then t.border.follow = false end
		elseif t.follow == true then t.size, t.border = nil, nil end
		t.enabled, t.hideTotemFrame, t.hideActionBar, t.killedPulse, t.follow = nil, nil, nil, nil, nil
		if t.mode ~= "blizzard" and t.mode ~= "active" and t.mode ~= "everything" then t.mode = nil end
		if t.show ~= "always" and t.show ~= "active" and t.show ~= "combat" and t.show ~= "target" then t.show = nil end
		if t.barPlace ~= "in" and t.barPlace ~= "out" then t.barPlace = nil end
		if t.stonePlinth ~= "slim" and t.stonePlinth ~= "normal" and t.stonePlinth ~= "grand" then t.stonePlinth = nil end
		if type(t.warnOver) ~= "table" then t.warnOver = TB.warnOverDefaults() end
		for k, v in pairs(TB.DEFAULTS) do
			if type(t[k]) ~= type(v) then t[k] = type(v) == "table" and CopyTable(v) or v end
		end
		for k, r in pairs(RANGES) do
			if type(t[k]) == "number" then
				if t[k] ~= t[k] then t[k] = TB.DEFAULTS[k] else t[k] = clamp(t[k], r) end
			end
		end
		if not finite(t.x) then t.x = TB.DEFAULTS.x end
		if not finite(t.y) then t.y = TB.DEFAULTS.y end
		if not ns.POINTS[t.point] then t.point, t.x, t.y = TB.DEFAULTS.point, TB.DEFAULTS.x, TB.DEFAULTS.y end
		local seen, order = {}, {}
		for _, el in ipairs(t.order) do
			if SLOT[el] and not seen[el] then seen[el] = true; table.insert(order, el) end
		end
		for _, el in ipairs(ELEMENTS) do if not seen[el] then table.insert(order, el) end end
		t.order = order
		for name, v in pairs(t.warnOver) do
			if type(name) ~= "string" or type(v) ~= "number" or v ~= v then t.warnOver[name] = nil
			else t.warnOver[name] = clamp(v, RANGES.warn) end
		end
		if type(t.size) ~= "number" then t.size = nil end
		for _, k in ipairs({ "rangeIn", "rangeOut", "keyColor" }) do
			if not ns.isColor(t[k]) then t[k] = CopyTable(TB.DEFAULTS[k]) end
		end
		cfgTable = t
	end
	return t
end
TB.cfg = cfg

-- Only the class gets the bar: other classes leave Blizzard's frames alone
local function barOn() return ns.isClass() and cfg().mode ~= "blizzard" end
local function feat(key) local c = cfg(); return barOn() and c.mode == "everything" and c[key] or false end
TB.barOn, TB.feat = barOn, feat
ns.Style.registerBar("totembar", { cfg = cfg, DEFAULTS = TB.DEFAULTS, label = "Totem bar", on = barOn,
	kinds = { "border", "uptime", "gcd", "text", "bar", "glow", "pop" },
	-- Its theme can draw its own border
	ownLabel = function(kind)
		if kind == "border" and TB.skin.owns("border") then return "Totem bar (its theme)" end
	end })

-- The player's settings, or the theme's where it owns one
local effective = setmetatable({}, { __index = function(_, k)
	local v = TB.skin.owned(k)
	if v ~= nil then return v end
	return cfg()[k]
end })
function TB.eff() return effective end

local function look()
	local c, db = cfg(), ns.getDB()
	local border = TB.skin.border() or ns.Style.get("totembar", "border")
	return (not c.sizeFollow and c.size) or db.iconSize, border, TB.skin.extrasBorder() or border
end
function TB.setSizeFollow(follow)
	local c = cfg()
	if not follow and not c.size then c.size = ns.getDB().iconSize end
	c.sizeFollow = follow
end

local function multiAction(slot)
	local ok, bar = ns.try("totem bar: multi-cast page", C_ActionBar.GetMultiCastBarIndex)
	if not ok or type(bar) ~= "number" or isSecret(bar) then bar = 12 end
	return (bar - 1) * 12 + slot
end

-- Geometry, shared with the options' preview of the bar
local POP_STEP = 3
TB.POP_FILL = { 0, 0, 0, 0.72 }
TB.BADGE_GAP = 0
local EXTRA_GAP = 6

function TB.along(n, size, px)
	local c = TB.eff()
	local before, after = TB.extraSides()
	local function round(v) return px and ns.roundPx(v, px) or math.floor(v + 0.5) end
	local esz, gap, extraGap = round(size * c.extrasScale), c.spacing, c.spacing + EXTRA_GAP
	local own, ownExtra = TB.skin.spacing(size)
	if own then gap, extraGap = own, ownExtra end
	if px then gap, extraGap = round(gap), round(extraGap) end
	local list, long = {}, 0
	local function put(key, space, sz, extra)
		if #list > 0 then long = long + space end
		table.insert(list, { key = key, offset = long, size = sz, extra = extra })
		long = long + sz
	end
	for _, k in ipairs(before) do put(k, gap, esz, true) end
	for i = 1, n do put(i, i == 1 and extraGap or gap, size) end
	for i, k in ipairs(after) do put(k, i == 1 and extraGap or gap, esz, true) end
	-- Negative spacing overlaps buttons: the bar spans them all
	local lo, hi = 0, 0
	for _, it in ipairs(list) do
		lo = math.min(lo, it.offset)
		hi = math.max(hi, it.offset + it.size)
	end
	if lo < 0 then for _, it in ipairs(list) do it.offset = it.offset - lo end end
	local line = (#before + #after > 0) and math.max(size, esz) or size
	return list, math.max(hi - lo, size), line
end

function TB.popButtonSize(size) return math.floor(size * 0.8 + 0.5) end
local function popDims(psz)
	local first, last, gap, thick = TB.skin.popMetrics(psz)
	if first then return first, last, gap, thick end
	return POP_STEP, POP_STEP, POP_STEP, psz + 2 * POP_STEP
end
function TB.popLength(n, psz)
	local first, last, gap = popDims(psz)
	return first + last + n * psz + (n - 1) * gap
end
function TB.placePopout(pop, anchor, n, psz)
	local c = TB.eff()
	local len, tab = TB.popLength(n, psz), c.arrowSize
	local thick = select(4, popDims(psz))
	pop:ClearAllPoints()
	if c.pop == "up" then pop:SetSize(thick, len); pop:SetPoint("BOTTOM", anchor, "TOP", 0, tab + 4)
	elseif c.pop == "down" then pop:SetSize(thick, len); pop:SetPoint("TOP", anchor, "BOTTOM", 0, -tab - 4)
	elseif c.pop == "right" then pop:SetSize(len, thick); pop:SetPoint("LEFT", anchor, "RIGHT", tab + 4, 0)
	else pop:SetSize(len, thick); pop:SetPoint("RIGHT", anchor, "LEFT", -tab - 4, 0) end
end
function TB.placePopButton(b, pop, i, psz)
	local c = TB.eff()
	b:SetSize(psz, psz)
	b:ClearAllPoints()
	local first, _, gap = popDims(psz)
	local off = first + (i - 1) * (psz + gap)
	if c.pop == "up" then b:SetPoint("BOTTOM", pop, "BOTTOM", 0, off)
	elseif c.pop == "down" then b:SetPoint("TOP", pop, "TOP", 0, -off)
	elseif c.pop == "right" then b:SetPoint("LEFT", pop, "LEFT", off, 0)
	else b:SetPoint("RIGHT", pop, "RIGHT", -off, 0) end
end

function TB.makeArrowLook(parent)
	local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	t:SetBackdrop(ns.BACKDROP)
	t.glyph = t:CreateTexture(nil, "OVERLAY")
	t.glyph:SetPoint("CENTER")
	TB.plainArrow(t)
	return t
end
function TB.plainArrow(t)
	t:SetBackdropColor(0.06, 0.05, 0.03, 0.92)
	t:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
	t.glyph:SetTexture("Interface\\Buttons\\UI-TotemBar")
	t.glyph:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	t.glyph:SetBlendMode("ADD")
	t.glyph:SetVertexColor(1, 1, 1, 1)
end
local GLYPH_TURN = { up = 0, down = math.pi, right = -math.pi / 2, left = math.pi / 2 }
TB.GLYPH_TURN = GLYPH_TURN
function TB.placeArrow(tab, anchor, glyph)
	local c = TB.eff()
	local deep = c.arrowSize
	tab:ClearAllPoints()
	if c.pop == "up" then tab:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 1, 1); tab:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -1, 1); tab:SetHeight(deep)
	elseif c.pop == "down" then tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 1, -1); tab:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -1, -1); tab:SetHeight(deep)
	elseif c.pop == "right" then tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, -1); tab:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 1, 1); tab:SetWidth(deep)
	else tab:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -1, -1); tab:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -1, 1); tab:SetWidth(deep) end
	glyph:SetSize(math.max(deep * 1.1, 10), math.max(deep * 0.6, 6))
	glyph:SetRotation(GLYPH_TURN[c.pop])
end

function TB.saturate(tex, sat)
	if not pcall(tex.SetDesaturation, tex, 1 - sat) then tex:SetDesaturated(sat < 0.5) end
end

function TB.badgeSize(size) return math.max(math.floor(size * cfg().badgeSize + 0.5), 8) end
function TB.layoutBadge(bd, anchor, size, border)
	local c = TB.eff()
	local usesColor = border and border.show and ns.Looks.uses(ns.Style.look("border", border.look), "color")
	local color = usesColor and border.color or { 0, 0, 0, 1 }
	local inset = ns.Looks.fit(bd, border and border.show and { show = true, size = 1, color = color } or border,
		TB.badgeSize(size))
	bd:SetAlpha(c.badgeAlpha)
	TB.saturate(bd.icon, c.badgeSat)
	bd:ClearAllPoints()
	local gap = TB.BADGE_GAP + inset + TB.skin.badgeGap(size)
	local x, y = c.badgeX, c.badgeY
	if c.pop == "up" then bd:SetPoint("TOP", anchor, "BOTTOM", x, y - gap)
	elseif c.pop == "down" then bd:SetPoint("BOTTOM", anchor, "TOP", x, y + gap)
	elseif c.pop == "right" then bd:SetPoint("RIGHT", anchor, "LEFT", x - gap, y)
	else bd:SetPoint("LEFT", anchor, "RIGHT", x + gap, y) end
end

function TB.fitLook(v, b, border, size)
	local o = ns.Looks.inset(v, border, size)
	v:ClearAllPoints()
	v:SetPoint("TOPLEFT", b, "TOPLEFT", o, -o)
	v:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -o, o)
	ns.applyBorder(v, border)
	return o
end

-- Frames: created at file load, allowed even during a /reload in combat
local bar = CreateFrame("Frame", "ShamanForeverTotemBar", UIParent)
bar:SetSize(1, 1)
bar:SetPoint("CENTER", 0, -120)
bar:SetFrameStrata("MEDIUM")
bar:Hide()

-- The pickers' header: popouts are protected frames it references; buttons carry their index
-- ("sf-pick") and run its open and close snippets. Blizzard's secure hover driver alone can't close
-- a hover picker: it never counts down if the mouse was gone at its first update.
local picker = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
picker:SetAttribute("sf-open", [[
	local open = ...
	for i = 1, 4 do
		local pop = self:GetFrameRef("pop" .. i)
		if i == open then pop:Show() else pop:Hide() end
	end
	-- Hover mode ("sf-hovermode"): HOVER_LEAVE closes the picker as the mouse leaves its slot and
	-- strip. Blizzard's secure hover driver is a second way: it hides the picker once the mouse has
	-- been off both for a moment (registering again restarts it). It never counts down if the mouse
	-- was already gone at its first update (a fast flick), so it can't be the only way.
	if open > 0 and self:GetAttribute("sf-hovermode") then
		local pop = self:GetFrameRef("pop" .. open)
		pop:RegisterAutoHide(0.3)
		pop:AddToAutoHide(self:GetFrameRef("slot" .. open))
		pop:AddToAutoHide(self:GetFrameRef("strip" .. open))
	end
]])
picker:SetAttribute("sf-close", [[ self:GetFrameRef("pop" .. (...)):Hide() ]])
-- Snippets run round each click (SecureHandlerWrapScript): returning false skips the button's action
local ARROW_CLICK = [[
	local i = self:GetAttribute("sf-pick")
	if button == "RightButton" then owner:RunAttribute("sf-open", 0)   -- closes any open picker
	elseif owner:GetFrameRef("pop" .. i):IsShown() then owner:RunAttribute("sf-close", i)
	else owner:RunAttribute("sf-open", i) end
	return false
]]
local CATCH_CLICK = [[
	owner:RunAttribute("sf-close", self:GetAttribute("sf-pick"))
	return false
]]
-- Alt+click opens the picker: slots act on the press, so the press is skipped and it opens on the release
local SLOT_CLICK = [[
	if button == "LeftButton" and IsAltKeyDown() and self:GetAttribute("sf-altpick") then
		if not down then owner:RunAttribute("sf-open", self:GetAttribute("sf-pick")) end
		return false
	end
]]
local PICK_CLICK, PICK_AFTER = [[ return nil, self:GetAttribute("sf-pick") ]], [[ owner:RunAttribute("sf-close", message) ]]
local HOVER_ENTER = [[
	if owner:GetAttribute("sf-hovermode") then owner:RunAttribute("sf-open", self:GetAttribute("sf-pick")) end
]]
-- Hover leave closes the picker unless still over the slot or strip. A leave runs only on a frame
-- whose enter is wrapped too
local HOVER_LEAVE = [[
	local i = self:GetAttribute("sf-pick")
	if not owner:GetAttribute("sf-hovermode") then return end
	local pop = owner:GetFrameRef("pop" .. i)
	if pop:IsShown() and not owner:GetFrameRef("slot" .. i):IsUnderMouse()
			and not owner:GetFrameRef("strip" .. i):IsUnderMouse() then
		pop:Hide()
	end
]]
local HOVER_NONE = [[ return ]]
local function wrapHover(b, enter)
	SecureHandlerWrapScript(b, "OnEnter", picker, enter or HOVER_NONE)
	SecureHandlerWrapScript(b, "OnLeave", picker, HOVER_LEAVE)
end
local function wrapClick(b, pre, post) SecureHandlerWrapScript(b, "OnClick", picker, pre, post) end


local slots = {}
local bySlot = {}
TB.slots, TB.frame = slots, bar

-- Frame levels over a slot's button, bottom to top: look +2, range strip +9 to +12, expiring
-- warning +13 to +15, time bar +16, then everything over the icon (GCD sweep, timer Cooldown, key,
-- end flashes). The strip's in-range part is opaque, so the warning sits over it; a bar along the
-- top edge hides the strip under it (a missed mark, never a false one).
TB.RANGE_LEVEL = 9
local WARN_LEVEL = TB.RANGE_LEVEL + 4
local TIME_BAR_LEVEL = TB.RANGE_LEVEL + 7
local OVER_RANGE = TB.RANGE_LEVEL + 8
local LOOK_LEVEL = 2
local LOOK_OVER_RANGE = OVER_RANGE - LOOK_LEVEL

local KEY_HIGHLIGHT = "UI-HUD-ActionBar-IconFrame-Mouseover"
local function keyLayer(v)
	local f = CreateFrame("Frame", nil, v)
	f:SetAllPoints()
	f:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE + 3)
	f.text = ns.makeKeyText(f)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetAllPoints()
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(KEY_HIGHLIGHT) then f.glow:SetAtlas(KEY_HIGHLIGHT)
	else f.glow:SetColorTexture(1, 0.82, 0, 0.3) end
	f.glow:Hide()
	return f
end

local function gcdSweep(v)
	local cd = ns.makeGCDSweep(v)
	cd:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE)
	return cd
end


for index, el in ipairs(ELEMENTS) do
	local slot = SLOT[el]
	local s = { el = el, slot = slot, index = index }
	slots[el], bySlot[slot] = s, s

	-- The click area: right-click dismisses, left-click casts the pick, Alt+click opens the picker; all on the press
	local b = CreateFrame("Button", "ShamanForeverTotem" .. NAME[el], bar, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("pressAndHoldAction", true)
	-- "*" matches any modifier (a plain "type2" only works with none held)
	b:SetAttribute("*type2", "destroytotem")
	b:SetAttribute("totem-slot", slot)
	b:SetAttribute("sf-pick", index)
	wrapClick(b, SLOT_CLICK)
	s.button = b

	local v = CreateFrame("Frame", nil, bar)
	v:SetAllPoints(b)
	v:SetFrameLevel(b:GetFrameLevel() + LOOK_LEVEL)
	v:EnableMouse(false)
	s.vis = v
	v.school = el
	local badge = CreateFrame("Frame", nil, bar)
	badge:SetFrameLevel(b:GetFrameLevel() + 6)
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.icon:SetAllPoints()
	ns.cropIcon(badge.icon)
	badge:Hide()
	s.badge = badge
	-- End flashes on their own frames (the slot's look can be invisible); each has its own secret gate
	local kf = ns.Effects.endFlash(bar, b, "totembar", v)
	s.expired = ns.Effects.endFlash(bar, b, "totembar", v)
	s.killed = kf
	kf:SetFrameLevel(b:GetFrameLevel() + OVER_RANGE + 4)
	s.expired:SetFrameLevel(b:GetFrameLevel() + OVER_RANGE + 4)
	for _, flash in ipairs({ kf, s.expired }) do flash:ClearAllPoints(); flash:SetAllPoints(v) end
	v.bg = v:CreateTexture(nil, "BACKGROUND")
	v.bg:SetAllPoints()
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	ns.cropIconExact(v.icon)
	s.timer = ns.Timer.new(v, "totembar", "uptime", { anchor = v, school = el })
	s.timer.cd:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE + 1)
	s.timer.bar:SetFrameLevel(b:GetFrameLevel() + TIME_BAR_LEVEL)
	v.cd = s.timer.cd
	s.keys = keyLayer(v)
	s.gcd = gcdSweep(v)
	s.command = "CLICK ShamanForeverKeyCast" .. NAME[el] .. ":LeftButton"

	local ar = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
	-- Above every open picker's catch button, so another slot's arrow opens in one click
	ar:SetFrameStrata("HIGH")
	ar:RegisterForClicks("AnyUp")
	ar:SetAttribute("sf-pick", index)
	wrapClick(ar, ARROW_CLICK)
	s.arrow = ar
	local av = TB.makeArrowLook(bar)
	av:SetAllPoints(ar)
	av:SetFrameLevel(ar:GetFrameLevel() + 2)
	av:EnableMouse(false)
	av:SetAlpha(0)
	s.arrowVis = av

	-- Popout: protected, so the snippets can show and hide it in combat
	local pop = CreateFrame("Frame", "ShamanForeverTotemPopout" .. NAME[el], bar, "SecureFrameTemplate")
	pop:Hide()
	pop:SetSize(1, 1)
	pop.bg = pop:CreateTexture(nil, "BACKGROUND")
	pop.bg:SetAllPoints()
	pop.bg:SetColorTexture(TB.POP_FILL[1], TB.POP_FILL[2], TB.POP_FILL[3], TB.POP_FILL[4])
	pop:SetFrameStrata("HIGH")
	pop.buttons = {}
	s.popout = pop
	SecureHandlerSetFrameRef(picker, "pop" .. index, pop)
	-- Catch button: screen-wide, under the pickers, closes an open one
	local catch = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
	catch:SetAllPoints(UIParent)
	catch:SetFrameLevel(pop:GetFrameLevel() + 1)
	catch:RegisterForClicks("AnyUp")
	catch:SetAttribute("sf-pick", index)
	wrapClick(catch, CATCH_CLICK)
	pop.catch = catch
	-- Hover strip: from the slot to the picker's far end so the mouse can cross; hover mode only
	local strip = CreateFrame("Frame", nil, pop, "SecureFrameTemplate")
	strip:SetFrameLevel(pop:GetFrameLevel() + 1)
	strip:EnableMouse(true)
	strip:SetAttribute("sf-pick", index)
	strip:Hide()
	pop.strip = strip
	SecureHandlerSetFrameRef(picker, "strip" .. index, strip)
	SecureHandlerSetFrameRef(picker, "slot" .. index, b)
end

-- Close every picker (out of combat): one hidden through the bar would come back open
local function closePopouts()
	if InCombatLockdown() then return end
	for _, el in ipairs(ELEMENTS) do slots[el].popout:Hide() end
end

-- Key bindings: each a CLICK binding to its own invisible secure button, so keys work with the bar
-- off. "Dismiss all" runs a macro that /clicks four dismiss helpers (a click sends a release, so
-- those act on release): no spell, so no global cooldown and no mana back.
local CALL, RECALL = ns.Spells.DEFS.call.ids[1], ns.Spells.DEFS.recall.ids[1]
_G.BINDING_HEADER_SHAMANFOREVER_TOTEMS = "Totems"
_G["BINDING_NAME_CLICK ShamanForeverKeyDismissAll:LeftButton"] = "Dismiss all totems"
local function nameBindings()
	_G["BINDING_NAME_CLICK ShamanForeverKeyCall:LeftButton"] = ns.Spells.name("call")
	_G["BINDING_NAME_CLICK ShamanForeverKeyRecall:LeftButton"] = ns.Spells.name("recall")
end
nameBindings()

local function keyButton(name, kind)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetAttribute("type", kind)
	return b
end
local castKeys = {}
local dismissAll = {}
for _, el in ipairs(ELEMENTS) do
	local slot = SLOT[el]
	castKeys[el] = keyButton("ShamanForeverKeyCast" .. NAME[el], "action")
	castKeys[el]:SetAttribute("action", multiAction(slot))
	_G["BINDING_NAME_CLICK ShamanForeverKeyCast" .. NAME[el] .. ":LeftButton"] = "Cast " .. NAME[el] .. " totem"
	keyButton("ShamanForeverKeyDismiss" .. NAME[el], "destroytotem"):SetAttribute("totem-slot", slot)
	_G["BINDING_NAME_CLICK ShamanForeverKeyDismiss" .. NAME[el] .. ":LeftButton"] = "Dismiss " .. NAME[el] .. " totem"
	local h = keyButton("ShamanForeverKeyDismissAll" .. slot, "destroytotem")
	h:SetAttribute("useOnKeyDown", false)
	h:SetAttribute("totem-slot", slot)
	table.insert(dismissAll, "/click ShamanForeverKeyDismissAll" .. slot)
end
keyButton("ShamanForeverKeyCall", "spell"):SetAttribute("spell", CALL)
keyButton("ShamanForeverKeyRecall", "spell"):SetAttribute("spell", RECALL)
local DISMISS_ALL = table.concat(dismissAll, "\n")
keyButton("ShamanForeverKeyDismissAll", "macro"):SetAttribute("macrotext", DISMISS_ALL)

-- Call of the Elements and Totemic Recall: Recall always shows, greyed until learned
local function knows(spell)
	local ok, v = ns.try("totem bar: spell known", C_SpellBook.IsSpellKnown, spell)
	return ok and v == true
end
local extras = {}
for _, e in ipairs({ { "Call", CALL }, { "Recall", RECALL } }) do
	local key, spell = e[1], e[2]
	local b = CreateFrame("Button", "ShamanForeverTotem" .. key, bar, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("spell", spell)
	local v = CreateFrame("Frame", nil, bar)
	v:SetAllPoints(b)
	v:SetFrameLevel(b:GetFrameLevel() + LOOK_LEVEL)
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	ns.cropIconExact(v.icon)
	extras[key] = { key = key, spell = spell, button = b, vis = v, keys = keyLayer(v), gcd = gcdSweep(v),
		command = "CLICK ShamanForeverKey" .. key .. ":LeftButton" }
end
extras.Recall.button:SetAttribute("*type2", "macro")
extras.Recall.button:SetAttribute("macrotext", DISMISS_ALL)

local function refreshKeys()
	local on = cfg().keys
	local function draw(layer, command)
		local key = on and GetBindingKey(command)
		layer.text:SetText(ns.keyLabel(key))
	end
	for _, el in ipairs(ELEMENTS) do draw(slots[el].keys, slots[el].command) end
	for _, e in pairs(extras) do draw(e.keys, e.command) end
end

-- The GCD on each casting button when the bar's Global cooldown style is on; only while the
-- button's own cooldown is the GCD (isOnGCD, vouched for inside SPELL_UPDATE_COOLDOWN)
local function gcdOf(getInfo, getDuration, id)
	local ok, info = ns.try("totem bar: cooldown", getInfo, id)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) or info.isOnGCD ~= true then return nil end
	local dok, d = ns.try("totem bar: GCD", getDuration, id)
	return dok and d or nil
end
local function refreshGCD()
	local on = ns.Style.value("totembar", "gcd", "show")
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		local action = multiAction(s.slot)
		local d = on and feat("cast") and C_ActionBar.HasAction(action)
			and gcdOf(C_ActionBar.GetActionCooldown, C_ActionBar.GetActionCooldownDuration, action)
		if d then s.gcd:SetCooldownFromDurationObject(d) else s.gcd:Clear() end
	end
	for _, e in pairs(extras) do
		local d = on and e.button:IsShown() and knows(e.spell)
			and gcdOf(C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration, e.spell)
		if d then e.gcd:SetCooldownFromDurationObject(d) else e.gcd:Clear() end
	end
end
TB.refreshGCD = refreshGCD

local keyTexts = {}
for _, el in ipairs(ELEMENTS) do keyTexts[slots[el].button] = slots[el].keys.text end
for _, e in pairs(extras) do keyTexts[e.button] = e.keys.text end

local function extraSides()
	local c = TB.eff()
	local list = {}
	if feat("call") and knows(CALL) then table.insert(list, "Call") end
	if feat("recall") then table.insert(list, "Recall") end
	if c.extras == "before" then return list, {} end
	if c.extras == "after" then return {}, list end
	local before, after = {}, {}
	for _, k in ipairs(list) do table.insert(k == "Call" and before or after, k) end
	return before, after
end
TB.extraSides = extraSides
function TB.extraTexture(key) return C_Spell.GetSpellTexture(key == "Call" and CALL or RECALL) end
function TB.extraLearned(key) return knows(key == "Call" and CALL or RECALL) end

local function hover(s, arrows)
	if arrows == nil then arrows = feat("arrows") end
	local over = s.button:IsMouseOver() or s.arrow:IsMouseOver() or (s.popout:IsShown() and s.popout:IsMouseOver())
	s.arrowVis:SetAlpha((over or s.popout:IsShown()) and arrows and 1 or 0)
end

-- Refreshing the slots (any time, combat included)
local function pickSpell(slot)
	local ok, kind, id = ns.try("totem bar: pick", GetActionInfo, multiAction(slot))
	if not ok or isSecret(kind) or isSecret(id) or kind ~= "spell" or type(id) ~= "number" then return nil end
	return id
end

-- warnOver is keyed by the client's rank-less spell name; the English name counts too (older profiles)
local function warnSecs(c, id)
	if not id then return c.warn end
	local name = ns.Spells.nameOf(id)
	local v = name and c.warnOver[name]
	if v == nil then
		local key = ns.Spells.keyOf(id)
		local def = key and ns.Spells.DEFS[key]
		v = def and c.warnOver[def.en]
	end
	return v or c.warn
end

local anyDown = false
local kbOpen = false
local preview

-- Values from the duration object may be secret: only ever straight to SetAlpha
function TB.drawTimeLeft(s)
	local d = s.dur
	if not d then return end
	local tbar = s.timer.bar
	if ns.CURVE_LIVE and tbar:IsShown() then
		local ok, a = ns.try("totem bar: time bar", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		if ok then tbar:SetAlpha(a) end
	end
	TB.range.drawTimeLeft(s)
end

-- The slot's expiring warning over the range strip, once: see the frame levels above
local function liftWarning(s)
	local x = s.timer.exp
	if not x or x.sfLifted then return end
	local lv = s.button:GetFrameLevel() + WARN_LEVEL
	x:SetFrameLevel(lv)
	local g = x.glow
	g:SetFrameLevel(lv + 1)
	if g.inner then g.inner:SetFrameLevel(lv + 2) end
	for _, parts in pairs(g.parts or {}) do
		if parts then ns.Looks.levelParts(parts) end
	end
	x.sfLifted = true
end

local function refreshSlot(s)
	local c, v = cfg(), s.vis
	local was = s.dur
	local ok, d = ns.try("totem bar: duration", GetTotemDuration, s.slot)
	if ok and d then
		local iok, _, _, _, _, icon = ns.try("totem bar: totem info", GetTotemInfo, s.slot)
		if iok and (isSecret(icon) or icon) then
			ns.try("totem bar: icon", v.icon.SetTexture, v.icon, icon)
			s.killed:setIcon(icon)
			s.expired:setIcon(icon)
		end
		s.killed.mark:Hide()
		v:SetAlpha(1)
		v.icon:SetDesaturated(false)
		v.icon:SetAlpha(1)
		v.bg:SetColorTexture(0, 0, 0, 1)
		s.timer:set(d)
		local down = ns.Totems.downSpell(s.slot)
		local pick = down and c.offPick and c.mode == "everything" and pickSpell(s.slot)
		if pick and not ns.Spells.same(down, pick) then
			ns.try("totem bar: badge", s.badge.icon.SetTexture, s.badge.icon, C_ActionBar.GetActionTexture(multiAction(s.slot)))
			s.badge:Show()
		else s.badge:Hide() end
		s.dur = d
		s.timer:setExpire({ secs = warnSecs(c, down), grey = c.warnGrey, ring = c.warnRing, pulse = c.warnPulse, glow = c.warnGlow })
		liftWarning(s)
		if iok and (isSecret(icon) or icon) then s.timer:setExpireIcon(icon) end
		TB.drawTimeLeft(s)
		return true
	end
	s.dur = nil
	if was then ns.Totems.slotEmptied(s.slot, was) end
	s.badge:Hide()
	s.timer:clear()
	-- Active totems: the slot keeps its place (secure buttons can't move in combat); a plain frame's
	-- alpha, so it works in combat
	v:SetAlpha((c.mode == "everything" or kbOpen) and 1 or 0)
	local tex = c.empty == "pick" and C_ActionBar.GetActionTexture(multiAction(s.slot))
	if isSecret(tex) or tex then
		ns.try("totem bar: pick icon", v.icon.SetTexture, v.icon, tex)
		v.icon:SetDesaturated(c.idleGrey)
		v.icon:SetAlpha(c.idleAlpha)
		v.bg:SetColorTexture(0, 0, 0, 0.6 * c.idleAlpha)
	elseif c.empty ~= "blank" then
		local col = ns.SCHOOL_COLOR[s.el]
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 0.8)
	else
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(0, 0, 0, 0)
	end
	return false
end

local function refreshSlots()
	if preview then return end
	local down = false
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		s.down = refreshSlot(s)
		if s.down then down = true end
		TB.range.refresh(s)
	end
	anyDown = down
end

local layout
local function refresh()
	local wasDown = anyDown
	refreshSlots()
	if anyDown ~= wasDown and cfg().show == "active" then layout() end
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", ns.throttled(0.1, function()
	if not bar:IsShown() then return end
	local arrows = feat("arrows")
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		hover(s, arrows)
		if s.down and not preview then TB.drawTimeLeft(s) end
	end
end))

-- Blizzard's totem frames
-- The totems under the player frame: made invisible and click-through rather than hidden, since
-- hiding it would re-lay out PlayerFrame and PetFrame from addon code. Blizzard's layout sets its
-- alpha back to 1 when it shows its frames, so a hidden TotemFrame hides again whenever alpha is set.
local function totemFrameOurs()
	if not ns.getDB() or not TotemFrame then return false end
	local roots = { PlayerFrame or false, _G.PlayerBottomManagedFrameContainer or false }
	local p = TotemFrame:GetParent()
	while p do
		for _, r in ipairs(roots) do if r and p == r then return true end end
		p = p:GetParent()
	end
	return false
end
local totemFrameHidden, settingAlpha = false, false
local function setTotemFrameHidden(hide)
	totemFrameHidden = hide
	settingAlpha = true
	TotemFrame:SetAlpha(hide and 0 or 1)
	settingAlpha = false
	for _, child in ipairs({ TotemFrame:GetChildren() }) do
		if child.EnableMouse and not (child.IsProtected and child:IsProtected()) then child:EnableMouse(not hide) end
	end
end
if TotemFrame then
	hooksecurefunc(TotemFrame, "SetAlpha", function(self, a)
		if totemFrameHidden and not settingAlpha and (isSecret(a) or a ~= 0) and totemFrameOurs() then
			settingAlpha = true
			self:SetAlpha(0)
			settingAlpha = false
		end
	end)
end
local function applyTotemFrame()
	if not TotemFrame then return end
	if not totemFrameOurs() then
		-- Another addon took it over: give it back visible (TotemFrame isn't protected: fine in combat)
		if totemFrameHidden then setTotemFrameHidden(false) end
		return
	end
	local hide = barOn()
	if not hide and not totemFrameHidden then return end
	setTotemFrameHidden(hide)
end
if TotemFrame and TotemFrame.Update then hooksecurefunc(TotemFrame, "Update", applyTotemFrame) end

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local actionBarParent
local function applyActionBar()
	local f = MultiCastActionBarFrame
	if not f or InCombatLockdown() then return end
	local hide = barOn() and cfg().mode == "everything"
	if hide and f:GetParent() ~= hiddenParent then
		actionBarParent = f:GetParent()
		f:SetParent(hiddenParent)
	elseif not hide and f:GetParent() == hiddenParent then
		f:SetParent(actionBarParent or UIParent)
	end
end

-- Layout (out of combat only)
local mover
local saidWait = false
local classDone = false
local hasTotems = false
local paintPreview

local function layoutPopout(s, size, known)
	local pop = s.popout
	local slot = s.slot
	local ids = { 0 }
	for _, id in ipairs(known) do table.insert(ids, id) end
	local psz = TB.popButtonSize(size)
	local action = multiAction(slot)
	for i, id in ipairs(ids) do
		local p = pop.buttons[i]
		if not p then
			p = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
			-- On the release, whatever the cast-on-key-down setting
			p:RegisterForClicks("AnyUp")
			p:SetAttribute("useOnKeyDown", false)
			p:SetAttribute("*type1", "multispell")   -- right-click has no action: it only closes
			p:SetAttribute("sf-pick", s.index)
			wrapClick(p, PICK_CLICK, PICK_AFTER)
			p:SetFrameLevel(pop:GetFrameLevel() + 5)
			p.icon = p:CreateTexture(nil, "ARTWORK")
			p.icon:SetAllPoints()
			ns.cropIcon(p.icon)
			p.none = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
			p.none:SetPoint("CENTER")
			p.none:SetText("X")
			p:SetScript("OnEnter", function(self)
				if cfg().tips == "never" or (cfg().tips == "ooc" and InCombatLockdown()) then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if self.spellID and self.spellID > 0 then GameTooltip:SetSpellByID(self.spellID)
				else GameTooltip:SetText("No totem") end
				GameTooltip:Show()
			end)
			p:SetScript("OnLeave", function() GameTooltip:Hide() end)
			wrapHover(p)   -- after its scripts: setting a script later would drop the wrap
			pop.buttons[i] = p
		end
		p.spellID = id
		p:SetAttribute("action", action)
		p:SetAttribute("spell", id)
		TB.placePopButton(p, pop, i, psz)
		if id ~= 0 then
			p.icon:SetTexture(C_Spell.GetSpellTexture(id))
			p.none:Hide()
		else
			p.icon:SetColorTexture(0.1, 0.1, 0.1, 1)
			p.none:Show()
		end
		p:Show()
	end
	for i = #ids + 1, #pop.buttons do pop.buttons[i]:Hide() end
	TB.placePopout(pop, s.button, #ids, psz)
	TB.skin.stylePopout(pop, #ids, psz)
	local strip, dir, b = pop.strip, TB.eff().pop, s.button
	local across = math.max(size, select(4, popDims(psz)))
	strip:ClearAllPoints()
	if dir == "up" then strip:SetPoint("BOTTOM", b, "TOP"); strip:SetPoint("TOP", pop, "TOP"); strip:SetWidth(across)
	elseif dir == "down" then strip:SetPoint("TOP", b, "BOTTOM"); strip:SetPoint("BOTTOM", pop, "BOTTOM"); strip:SetWidth(across)
	elseif dir == "right" then strip:SetPoint("LEFT", b, "RIGHT"); strip:SetPoint("RIGHT", pop, "RIGHT"); strip:SetHeight(across)
	else strip:SetPoint("RIGHT", b, "LEFT"); strip:SetPoint("LEFT", pop, "LEFT"); strip:SetHeight(across) end
end

local function layoutArrow(s)
	local ar = s.arrow
	TB.placeArrow(ar, s.button, s.arrowVis.glyph)
	TB.skin.styleArrow(s.arrowVis)
	ar:SetShown(feat("arrows"))
	ar:SetFrameLevel(s.popout.catch:GetFrameLevel() + 2)
	s.arrowVis:SetShown(feat("arrows"))
end

local function ownDriver()
	local c = cfg()
	if preview then return barOn() and (hasTotems or preview.all) and "show" or "hide" end
	if not barOn() or not hasTotems then return "hide" end
	if kbOpen or not ns.getAccount().locked then return "show" end
	if c.show == "combat" then return "[petbattle] hide; [combat] show; hide" end
	if c.show == "target" then return "[petbattle] hide; [combat] show; [@target,exists,harm,nodead] show; hide" end
	if c.show == "active" then return "[petbattle] hide; [combat] show; " .. (anyDown and "show" or "hide") end
	return "[petbattle] hide; show"
end
local afterCombat
local function visibilityDriver()
	if ns.AfterCombat.held(afterCombat) and barOn() and ns.getAccount().locked and not kbOpen
		and cfg().show ~= "always" then
		return "[petbattle] hide; show"
	end
	return ownDriver()
end
local lastDriver
local function drive()
	local driver = visibilityDriver()
	if driver ~= lastDriver and ns.setVisibilityDriver(bar, driver, "totem bar driver") then
		lastDriver = driver
	end
end

function layout()
	if ns.deferInCombat("totem bar layout", layout) then return end
	if classDone then return end
	-- Any open picker closes first: it would come back open later
	closePopouts()
	local c = cfg()
	local size, border, extrasBorder = look()
	-- Scale and opacity first: sizes, gaps and position are whole screen pixels at it
	bar:SetScale(c.scale)
	bar:SetAlpha(c.alpha)
	local px = ns.pixel(bar)
	size = ns.roundPx(size, px)
	-- With no totem known the bar hides (Call and Recall too, in positioning mode as well)
	local shown, known = {}, {}
	local had = hasTotems
	hasTotems = not GetMultiCastTotemSpells
	for _, el in ipairs(ELEMENTS) do
		known[el] = ns.Totems.knownTotems(SLOT[el])
		if #known[el] > 0 then hasTotems = true end
	end
	if hasTotems ~= had then ns.Options.refresh() end
	for _, el in ipairs(c.order) do
		local s = slots[el]
		local on = barOn() and not c.hidden[el] and (#known[el] > 0 or not GetMultiCastTotemSpells or (preview and preview.all))
		s.button:SetShown(on)
		s.vis:SetShown(on)
		if not on then s.killed.mark:Hide() end
		if on then table.insert(shown, s) else s.arrow:Hide(); s.arrowVis:Hide() end
	end
	local row = c.dir == "row"
	if row and c.pop ~= "up" and c.pop ~= "down" then c.pop = "up" end
	if not row and c.pop ~= "right" and c.pop ~= "left" then c.pop = "right" end
	row = TB.eff().dir == "row"
	local places = shown
	if TB.skin.fixedSlots() and #shown > 0 then
		places = {}
		for _, el in ipairs(c.order) do table.insert(places, slots[el]) end
	end
	local seq, long, across = {}, size, size
	if hasTotems or (preview and preview.all) then seq, long, across = TB.along(#places, size, px) end
	local on = {}
	for _, it in ipairs(seq) do
		local b, sz = it.extra and extras[it.key].button or places[it.key].button, it.size
		if it.extra then on[it.key] = sz end
		b:SetSize(sz, sz)
		local kt = keyTexts[b]
		if kt then
			local k = c.keyColor
			ns.Media.setFont(kt, "totembar", ns.keyTextSize(sz, c.keySize))
			kt:ClearAllPoints()
			kt:SetPoint("TOPRIGHT", c.keyX, c.keyY)
			kt:SetTextColor(k[1], k[2], k[3], k[4] or 1)
		end
		b:ClearAllPoints()
		local side = ns.roundPx((across - sz) / 2, px)
		if row then b:SetPoint("TOPLEFT", bar, "TOPLEFT", it.offset, -side) else b:SetPoint("TOPLEFT", bar, "TOPLEFT", side, -it.offset) end
	end
	for key, e in pairs(extras) do
		local show = on[key] ~= nil
		e.button:SetShown(show)
		e.vis:SetShown(show)
		if show then
			local learned = knows(e.spell)
			e.button:SetAttribute("*type1", learned and "spell" or nil)
			e.vis.icon:SetTexture(C_Spell.GetSpellTexture(e.spell))
			e.vis.icon:SetDesaturated(not learned)
			e.vis.icon:SetAlpha(learned and 1 or 0.6)
			TB.fitLook(e.vis, e.button, extrasBorder, on[key])
		end
	end
	local hoverMode = feat("pickHover") and not kbOpen
	picker:SetAttribute("sf-hovermode", hoverMode)
	for _, el in ipairs(ELEMENTS) do
		slots[el].popout.catch:SetShown(not hoverMode)
		slots[el].popout.strip:SetShown(hoverMode)
	end
	for _, s in ipairs(shown) do
		local b = s.button
		b:SetAttribute("*type1", feat("cast") and "action" or nil)
		b:SetAttribute("sf-altpick", barOn() and cfg().mode == "everything")
		b:SetAttribute("action", multiAction(s.slot))
		castKeys[s.el]:SetAttribute("action", multiAction(s.slot))
		s.inset = TB.fitLook(s.vis, b, border, size)
		s.killed.fitSize, s.expired.fitSize = size - 2 * s.inset, size - 2 * s.inset
		s.timer:apply()
		TB.skin.styleTimer(s.timer, s.vis, size)
		layoutArrow(s)
		TB.layoutBadge(s.badge, s.button, size, border)
		layoutPopout(s, size, known[s.el])
	end
	if row then bar:SetSize(long, across) else bar:SetSize(across, long) end
	local boxes, sealed = {}, {}
	for i, s in ipairs(places) do
		boxes[i] = s.button
		if not s.button:IsShown() then sealed[s.button] = true end
	end
	TB.skin.layoutBar(bar, boxes, size, row, sealed)
	ns.placeOnPixels(bar, c.point, c.x / c.scale, c.y / c.scale)
	TB.range.layout(size)
	refreshSlots()
	refreshKeys()
	refreshGCD()
	ns.refitRings()
	drive()
	applyTotemFrame()
	applyActionBar()
	if mover then mover.update() end
	if preview then paintPreview() end
	if ns.otherClass() then classDone = true end
end
TB.layout = layout
TB.afterGroups = layout

afterCombat = ns.AfterCombat.new({
	secs = function()
		if not ns.getDB() or not barOn() or kbOpen or not ns.getAccount().locked then return 0 end
		local c = cfg()
		return c.show ~= "always" and c.fadeAfter or 0
	end,
	apply = function() if not InCombatLockdown() then drive() end end,
	shows = function() return SecureCmdOptionParse(ownDriver()) == "show" end,
	frames = function() return { bar } end,
})

function TB.applyTimers()
	local size = look()
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		s.timer:apply()
		TB.skin.styleTimer(s.timer, s.vis, size)
	end
end

function TB.applySettings()
	cfgTable = nil
	local c = cfg()
	if not (c.killed and c.killedMark) then
		for _, el in ipairs(ELEMENTS) do slots[el].killed.mark:Hide() end
	end
	if InCombatLockdown() then
		-- Once per combat: sliders call this on every step
		if not saidWait then
			saidWait = true
			ns.say("totem bar changes wait until combat ends")
		end
	end
	layout()
end

-- Positioning
mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
mover:SetFrameStrata("DIALOG")
mover:SetBackdrop(ns.BACKDROP)
mover:SetBackdropColor(0, 0, 0, 0.4)
mover:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
mover:EnableMouse(true)
mover:EnableMouseWheel(true)
mover:RegisterForDrag("LeftButton")
mover:SetMovable(true)
mover:SetClampedToScreen(true)
mover:Hide()
mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mover.label:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 2)
mover.label:SetText("Totem bar")
local movable = { frame = bar }
mover:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
	ns.Positioning.selectMovable(movable)
	self:StartMoving()
end)
mover:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	if InCombatLockdown() then return end
	local c = cfg()
	local x, y = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
	c.point, c.x, c.y = "CENTER", x * scale - ux, y * scale - uy
	layout()
end)
mover:SetScript("OnMouseUp", function(_, button)
	if InCombatLockdown() then return end
	if button == "LeftButton" then ns.Positioning.selectMovable(movable)
	elseif button == "RightButton" and ns.Options.open then ns.Options.open("totembar") end
end)
mover:SetScript("OnMouseWheel", function(self, delta)
	if InCombatLockdown() then return end
	local c = cfg()
	local function step(key) c[key] = clamp(math.floor((c[key] + delta * 0.05) * 100 + 0.5) / 100, RANGES[key]) end
	if IsControlKeyDown() then step("alpha")
	elseif IsShiftKeyDown() then step("scale")
	else
		local from = look()
		c.sizeFollow = false
		c.size = clamp(from + delta * 2, RANGES.size)
	end
	layout()
	self.label:SetText(string.format("Totem bar: size %d, scale %.2f, opacity %.0f%%", (look()), c.scale, c.alpha * 100))
	ns.Options.refresh()
end)
function mover.update()
	local on = barOn() and (hasTotems or (preview and preview.all)) and not ns.getAccount().locked and not InCombatLockdown()
	if on then
		mover:ClearAllPoints()
		mover:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
		mover:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
		if ns.Positioning.isSelected(movable) then mover:SetBackdropBorderColor(1, 0.82, 0, 1)
		else mover:SetBackdropBorderColor(0.2, 0.6, 1, 0.9) end
		mover.label:SetText("Totem bar")
	end
	mover:SetShown(on)
end

function movable.nudge(dx, dy)
	local c = cfg()
	c.x, c.y = c.x + dx, c.y + dy
	ns.placeOnPixels(bar, c.point, c.x / c.scale, c.y / c.scale)
end
function movable.lock()
	mover:Hide()
	ns.retryAfterCombat("totem bar layout", layout)
end
ns.Positioning.addMovable(movable)

-- Quick Keybind Mode (Blizzard's): the bar shows, empty slots included. Keys are caught on our own
-- plain frame and bound with SetBinding: calling Blizzard's QuickKeybindButtonTemplateMixin from
-- addon code taints its key handling. OK saves (SaveBindings), Cancel undoes (LoadBindings).
local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetFrameStrata("FULLSCREEN_DIALOG")
catcher:EnableMouse(true)
catcher:EnableKeyboard(true)
catcher:EnableMouseWheel(true)
catcher:Hide()

local function kbTooltip()
	local tip, command = QuickKeybindTooltip, catcher.command
	if not (tip and command) then return end
	tip:SetOwner(catcher, "ANCHOR_RIGHT")
	GameTooltip_AddHighlightLine(tip, GetBindingName(command))
	local key = GetBindingKey(command)
	if key then
		GameTooltip_AddInstructionLine(tip, GetBindingText(key))
		GameTooltip_AddNormalLine(tip, ESCAPE_TO_UNBIND)
	else
		GameTooltip_AddErrorLine(tip, NOT_BOUND)
		GameTooltip_AddNormalLine(tip, PRESS_KEY_TO_BIND)
	end
	tip:Show()
end

local function kbLeave()
	if catcher.layer then catcher.layer.glow:SetAlpha(0.5) end
	catcher.command, catcher.layer = nil, nil
	catcher:Hide()
	if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
end

local function kbEnter(button, command, layer)
	if not kbOpen or InCombatLockdown() then return false end
	if not catcher.pad then
		catcher.pad = true
		if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, true) end
	end
	catcher.command, catcher.layer = command, layer
	catcher:ClearAllPoints()
	catcher:SetAllPoints(button)
	catcher:Show()
	layer.glow:SetAlpha(1)
	kbTooltip()
	return true
end

local function kbSay(text)
	if QuickKeybindFrame and QuickKeybindFrame.SetOutputText then QuickKeybindFrame:SetOutputText(text) end
end

local function kbBind(input)
	local command = catcher.command
	if not command or InCombatLockdown() then return end
	local ctx = C_KeyBindings and C_KeyBindings.GetBindingContextForAction and C_KeyBindings.GetBindingContextForAction(command)
	local key1, key2 = GetBindingKey(command, nil, ctx)
	if input == "ESCAPE" then
		if not key1 then return end
		SetBinding(key1, nil, ctx)
		if key2 then SetBinding(key2, command, ctx) end
		kbSay(KEY_UNBOUND)
	else
		-- The screenshot key stays the screenshot key; lone modifiers wait for their key
		if GetBindingFromClick and GetBindingFromClick(input) == "SCREENSHOT" then return end
		local key = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
		if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) then return end
		key = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
		local was = GetBindingAction(key)
		if key1 then SetBinding(key1, nil, ctx) end
		if key2 then SetBinding(key2, nil, ctx) end
		if SetBinding(key, command, ctx) then
			if key2 and key2 ~= key then SetBinding(key2, command, ctx) end
			local lost = was and was ~= "" and was ~= command and not GetBindingKey(was, nil, ctx)
			if lost then kbSay(KEY_UNBOUND_ERROR:format(GetBindingName(was))) else kbSay(KEY_BOUND) end
		else
			if key1 then SetBinding(key1, command, ctx) end
			if key2 then SetBinding(key2, command, ctx) end
		end
	end
	refreshKeys()
	kbTooltip()
end

catcher:SetScript("OnLeave", kbLeave)
catcher:SetScript("OnKeyDown", function(_, key)
	-- The screenshot key takes a screenshot: Blizzard's keybind frame underneath takes every key
	if GetBindingFromClick and GetBindingFromClick(key) == "SCREENSHOT" then
		if Screenshot then Screenshot() end
		return
	end
	kbBind(key)
end)
catcher:SetScript("OnGamePadButtonDown", function(_, button) kbBind(button) end)
catcher:SetScript("OnMouseUp", function(_, button)
	if button ~= "LeftButton" and button ~= "RightButton" then kbBind(button) end
end)
catcher:SetScript("OnMouseWheel", function(_, delta) kbBind(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)

local function setKeybindMode(open)
	kbOpen = open
	if not open then kbLeave() end
	for _, el in ipairs(ELEMENTS) do
		slots[el].keys.glow:SetShown(open)
		slots[el].keys.glow:SetAlpha(0.5)
	end
	for _, e in pairs(extras) do
		e.keys.glow:SetShown(open)
		e.keys.glow:SetAlpha(0.5)
	end
	refreshSlots()
	layout()
end

local kbHooked = false
local function hookQuickKeybind()
	local f = QuickKeybindFrame
	if kbHooked or not f then return end
	kbHooked = true
	f:HookScript("OnShow", function() setKeybindMode(true) end)
	f:HookScript("OnHide", function() setKeybindMode(false) end)
	if f:IsShown() then setKeybindMode(true) end
end
local kbEvents = CreateFrame("Frame")
kbEvents:SetScript("OnEvent", function(self, _, name)
	if name ~= "Blizzard_QuickKeybind" then return end
	hookQuickKeybind()
	if kbHooked then self:UnregisterEvent("ADDON_LOADED") end
end)

-- Tooltips and hover on the slot buttons
for _, el in ipairs(ELEMENTS) do
	local s = slots[el]
	s.button:SetScript("OnEnter", function(self)
		hover(s)
		if kbEnter(self, s.command, s.keys) then return end
		local c = cfg()
		if c.tips == "never" or (c.tips == "ooc" and InCombatLockdown()) then return end
		local ok, d = ns.try("totem bar: tooltip", GetTotemDuration, s.slot)
		if not (ok and d) and c.mode ~= "everything" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if ok and d then
			ns.try("totem bar: tooltip", GameTooltip.SetTotem, GameTooltip, s.slot)
		else
			local action = multiAction(s.slot)
			if not C_ActionBar.HasAction(action) then GameTooltip:SetText(NAME[el] .. ": no totem picked")
			else ns.try("totem bar: tooltip", GameTooltip.SetAction, GameTooltip, action) end
		end
		GameTooltip:Show()
	end)
	s.button:SetScript("OnLeave", function() GameTooltip:Hide(); hover(s) end)
	s.arrow:SetScript("OnEnter", function() hover(s) end)
	s.arrow:SetScript("OnLeave", function() hover(s) end)
end
-- Hover mode: wrapped after the scripts above are set (setting a script later would drop the wrap)
for _, el in ipairs(ELEMENTS) do
	wrapHover(slots[el].button, HOVER_ENTER)
	wrapHover(slots[el].arrow, HOVER_ENTER)
	wrapHover(slots[el].popout.strip)
end
-- Alt+Z hides the whole UI, in combat too, and drops hidden frames from the hover driver: a picker
-- taken along must close when the bar shows again, via an explicitly protected child that stays
-- shown (a wrapped script runs only on such a frame)
local onShow = CreateFrame("Frame", nil, bar, "SecureFrameTemplate")
SecureHandlerWrapScript(onShow, "OnShow", picker, [[
	if owner:GetAttribute("sf-hovermode") then owner:RunAttribute("sf-open", 0) end
]])

for _, e in pairs(extras) do
	e.button:SetScript("OnEnter", function(self)
		if kbEnter(self, e.command, e.keys) then return end
		local c = cfg()
		if c.tips == "never" or (c.tips == "ooc" and InCombatLockdown()) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if not ns.try("totem bar: tooltip", GameTooltip.SetSpellByID, GameTooltip, e.spell) then
			GameTooltip:SetText(C_Spell.GetSpellName(e.spell) or e.key)
		end
		if e.key == "Recall" then
			if not knows(e.spell) then GameTooltip:AddLine("Not learned yet", 0.6, 0.6, 0.6) end
			GameTooltip:AddLine("Right-click: dismiss all totems (no GCD, but no mana returned)", 1, 0.82, 0, true)
		end
		GameTooltip:Show()
	end)
	e.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Killed early: a slot's last duration object says how much time the totem had left; endFlash
-- turns that into a curve, so a totem that ran out shows no flash. Our own dismissals and an
-- immediate recast don't flash.
ns.Totems.subscribe(function(event, slot, was)
	if event ~= "gone" or preview then return end
	local s = bySlot[slot]
	local c = cfg()
	if not s.button:IsShown() then return end
	if s.button:IsVisible() then ns.Sounds.play(c.goneSound, "totembar", nil, true) end
	if c.expiredPop then s.expired:play(was, { expired = true, pop = true }) end
	if c.killed then s.killed:play(was, { pop = c.killedPop, glow = c.killedGlow, mark = c.killedMark }) end
end)

-- Events
-- After one of our casts: refresh once ns.Totems has recorded the slot (its handler may run after ours)
local casts, refreshQueued = {}, false
local function refreshAfterCast(spell)
	casts[spell] = true
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		local totem = false
		for slot = 1, 4 do
			local id = not totem and ns.Totems.spellInSlot(slot)
			if id and casts[id] then totem = true end
		end
		wipe(casts)
		if totem then refresh() end
	end)
end

local function onEvent(_, event, arg1, ...)
	if event == "PLAYER_TOTEM_UPDATE" then
		refresh()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, spell = ...
		if isSecret(spell) or type(spell) ~= "number" then return end
		refreshAfterCast(spell)
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		local base = multiAction(1) - 1
		if not isSecret(arg1) and type(arg1) == "number" and (arg1 == 0 or (arg1 > base and arg1 <= base + 12)) then refresh() end
	elseif event == "UPDATE_BINDINGS" then
		refreshKeys()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		refreshGCD()
	else
		if event == "SPELLS_CHANGED" then nameBindings() end
		layout()
	end
end

-- The class's only: its first layout comes with the HUD's
function TB.start()
	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TOTEM_UPDATE", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED",
			"UPDATE_MULTI_CAST_ACTIONBAR", "UPDATE_BINDINGS", "SPELL_UPDATE_COOLDOWN" }) do
		ns.registerEvent(ev, e)
	end
	ns.registerEvent(ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
	ev:SetScript("OnEvent", onEvent)
	-- Never left over the bar in combat, taking the keyboard
	ns.onCombatStart(kbLeave)
	ns.onCombatEnd(function()
		saidWait = false
		closePopouts()
		mover.update()
	end)
	hookQuickKeybind()
	if not kbHooked then ns.registerEvent(kbEvents, "ADDON_LOADED") end
	nameBindings()
	ticker:Show()
	TB.range.start()
end

TB.MODES = { { "blizzard", "Blizzard's" }, { "active", "Active totems" }, { "everything", "Everything" } }
function TB.setMode(mode)
	local c = cfg()
	c.mode = mode
	if mode == "everything" then c.cast, c.arrows, c.call, c.recall = true, true, true, true end
end
function TB.modeName()
	for _, m in ipairs(TB.MODES) do if m[1] == cfg().mode then return m[2] end end
	return "?"
end
function TB.pickTexture(el) return C_ActionBar.GetActionTexture(multiAction(SLOT[el])) end
function TB.known(el)
	local ids = {}
	for _, p in ipairs(slots[el].popout.buttons) do
		if p:IsShown() and p.spellID and p.spellID ~= 0 then table.insert(ids, p.spellID) end
	end
	if #ids > 0 then return ids end
	return ns.Totems.knownTotems(SLOT[el])
end
TB.look = look
function TB.hasTotems() return hasTotems end

-- Preview mode: slots drawn in the requested states on plain frames; showing slots and the bar
-- happens in layout()
TB.PREVIEW_STATES = { "down", "expiring", "killed", "ranout", "empty" }

local function paintSlot(s, rec)
	local c, v, st = cfg(), s.vis, rec.st
	local shown = s.button:IsShown()
	local pick = GetActionTexture and GetActionTexture(multiAction(s.slot))
	if isSecret(pick) then pick = nil end
	local icon = pick or ns.Look.TOTEM_ICON[s.el]
	s.badge:Hide()
	s.killed:setIcon(icon)
	s.expired:setIcon(icon)
	if s.rangeGate then s.rangeGate:SetAlpha(0) end
	local size = s.button:GetWidth()
	local strip = s.previewRange
	if rec.range and c.range and shown then
		if not strip then
			strip = CreateFrame("Frame", nil, bar)
			strip.bg = strip:CreateTexture(nil, "ARTWORK")
			strip.bg:SetAllPoints()
			s.previewRange = strip
		end
		strip:SetFrameLevel(s.button:GetFrameLevel() + TB.RANGE_LEVEL + 3)
		strip:ClearAllPoints()
		local x, y, w, h = TB.skin.markRect(strip, size, s.inset or 0)
		if x then
			strip:SetPoint("TOPLEFT", s.button, "TOPLEFT", x, y)
			strip:SetSize(w, h)
		else
			strip:SetPoint("TOPLEFT", s.button, "TOPLEFT", 0, 0)
			strip:SetSize(size, ns.linePx(strip, c.rangeHeight))
		end
		if not TB.skin.paintMark(strip, w, h, s.vis) then
			local k = c.rangeOut
			strip.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
		end
		strip:Show()
	elseif strip then strip:Hide() end
	v.icon:SetTexture(icon)
	if st == "down" or st == "expiring" then
		s.killed.mark:Hide()
		v:SetAlpha(1)
		v.icon:SetDesaturated(false)
		v.icon:SetAlpha(1)
		v.bg:SetColorTexture(0, 0, 0, 1)
		local left, life = ns.Look.PREVIEW_LEFT[s.el][1], ns.Look.PREVIEW_LEFT[s.el][2]
		if st == "expiring" then left = 5 end
		s.timer:setExpire({ secs = c.warn, grey = c.warnGrey, ring = c.warnRing, pulse = c.warnPulse, glow = c.warnGlow }, icon)
		liftWarning(s)
		s.timer:setTime(rec.at - (life - left), life)
		return rec.at + left
	end
	s.timer:clear()
	v:SetAlpha(c.mode == "everything" and 1 or 0)
	if c.empty == "pick" and pick then
		v.icon:SetDesaturated(c.idleGrey)
		v.icon:SetAlpha(c.idleAlpha)
		v.bg:SetColorTexture(0, 0, 0, 0.6 * c.idleAlpha)
	elseif c.empty ~= "blank" then
		local col = ns.SCHOOL_COLOR[s.el]
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 0.8)
	else
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(0, 0, 0, 0)
	end
end

function paintPreview()
	for _, el in ipairs(ELEMENTS) do
		local rec = preview.states[el]
		if rec then paintSlot(slots[el], rec) end
	end
end

function TB.preview(p)
	if p then
		preview = { all = p.all, states = preview and preview.states or {} }
		TB.range.preview(true)
	elseif preview then
		preview = nil
		TB.range.preview(false)
		for _, el in ipairs(ELEMENTS) do
			local s = slots[el]
			s.killed:stop()
			s.expired:stop()
			if s.previewRange then s.previewRange:Hide() end
			-- A totem that went meanwhile isn't news: no end flash; ns.Totems forgets it quietly
			if s.dur then
				local ok, d = ns.try("totem bar: duration", GetTotemDuration, s.slot)
				if ok and d == nil then ns.Totems.forget(s.slot) end
			end
			s.dur = nil
		end
		lastDriver = nil
	end
end

function TB.previewSlot(el, st, at, range, moment)
	if not preview then return end
	local rec = { st = st, at = at, range = range }
	preview.states[el] = rec
	local s, c = slots[el], cfg()
	if st ~= "killed" then s.killed:stop() end
	if st ~= "ranout" then s.expired:stop() end
	local ends = paintSlot(s, rec)
	moment = moment and s.button:IsShown()
	if moment and st == "killed" and c.killed then
		s.killed:play(nil, { pop = c.killedPop, glow = c.killedGlow, mark = c.killedMark })
	elseif moment and st == "ranout" and c.expiredPop then
		s.expired:play(nil, { expired = true, pop = true })
	end
	return ends
end

-- /sf debug
function TB.debug()
	local c = cfg()
	local mc = MultiCastActionBarFrame
	local gok, ginfo = pcall(C_ActionBar.GetActionCooldown, multiAction(SLOT.earth))
	local g = not gok and "error" or type(ginfo) ~= "table" and "none"
		or isSecret(ginfo.isOnGCD) and "secret" or tostring(ginfo.isOnGCD)
	ns.say("totem bar mode %s, show %s, driver %s, shown %s, totems known %s, earth isOnGCD %s; TotemFrame parent %s alpha %s; Totem Action Bar parent %s",
		c.mode, c.show, tostring(lastDriver), tostring(bar:IsShown()), tostring(hasTotems), g,
		TotemFrame and TotemFrame:GetParent() and (TotemFrame:GetParent():GetName() or "?") or "none",
		TotemFrame and string.format("%.2f", TotemFrame:GetAlpha()) or "-",
		mc and (mc:GetParent() == hiddenParent and "hidden" or (mc:GetParent() and mc:GetParent():GetName() or "?")) or "none")
end

ns.registerModule(TB)
