-- Totem bar: one bar that can replace both of Blizzard's totem frames, the totems under the player
-- frame (timers, right-click dismiss) and the Totem Action Bar (a pick per element, arrow popouts).
-- Design: workspace design/totem-bar.md; what was tested in game: design/totem-research.md.
--
-- Every click goes through Blizzard's own secure actions, set up out of combat; nothing here runs a
-- secure snippet (they are broken on Forever):
-- * slot button: right-click "destroytotem" (totem-slot), left-click "action" on the element's
--   multi-cast action slot, so it casts whatever the element's pick is, and follows it.
-- * arrow tab: a press-and-hold button. Press sets SecureStateDriverManager's "setframe" to the
--   element's popout, release clicks a helper that sets "setstate" to "state-visibility show".
--   This opens the popout in combat too. Right-click on the tab closes it the same way.
-- * popout: "multispell" buttons (spell 0 is "No totem") that change the pick; on release they
--   click the helper that hides the popout.
-- Layout, attributes and anything that shows, hides or moves a secure button change only out of
-- combat; changes asked for in combat wait for it to end. Drawing sits on plain frames over the
-- secure buttons, so it can change any time.
-- In combat, which totem is in a slot is secret: its icon is drawn by handing the secret icon to
-- SetTexture, timers come from the slot's duration object, and warnings are the remaining time
-- through a curve into SetAlpha. The totem's name (for per-totem warning times) comes from our own
-- casts (ns.totemNameInSlot).

local _, ns = ...

local TB = {}
ns.TotemBar = TB

local ELEMENTS = { "earth", "fire", "water", "air" }
local SLOT = { fire = 1, earth = 2, water = 3, air = 4 }   -- Blizzard's totem slots
local NAME = { earth = "Earth", fire = "Fire", water = "Water", air = "Air" }
local COLOR = { earth = { 0.75, 0.54, 0.24 }, fire = { 0.89, 0.38, 0.18 }, water = { 0.25, 0.69, 0.77 }, air = { 0.56, 0.76, 0.92 } }
TB.ELEMENTS, TB.NAME, TB.SLOT = ELEMENTS, NAME, SLOT

-- Per profile, in db.totemBar.
TB.DEFAULTS = {
	enabled = false,
	point = "CENTER", x = 0, y = -120,   -- x, y in UIParent units, so scaling keeps the centre
	scale = 1,
	alpha = 1,
	show = "always",          -- always | active (in combat or a totem down) | combat | never
	order = { "earth", "fire", "water", "air" },
	hidden = {},              -- element -> true to leave its slot out
	dir = "row",              -- row | column
	pop = "up",               -- where pickers open: up | down (row), right | left (column)
	spacing = 4,
	cast = true,              -- left-click casts the element's pick
	arrows = true,            -- arrow tab opens the element's picker
	arrowSize = 18,
	tips = "always",          -- always | ooc | never
	hideTotemFrame = true,    -- Blizzard's totems under the player frame
	hideActionBar = true,     -- Blizzard's Totem Action Bar
	follow = true,            -- icon size, border and countdown size from General
	size = 40,
	border = { show = true, size = 1, color = { 0, 0, 0, 1 } },
	cdSize = 22,
	empty = "pick",           -- pick (greyed) | frame (element colour) | blank
	timer = "swipe",          -- swipe | bar | both | num
	warnGrey = false,
	warnRing = false,
	warnPulse = true,
	warn = 5,                 -- seconds before the end (0 = off)
	warnOver = {},            -- totem name -> seconds, instead of warn
}

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-- The profile's bar settings, with defaults filled and wrong types reset (imported profiles).
local cfgTable
local function cfg()
	local db = ns.getDB()
	if type(db.totemBar) ~= "table" then db.totemBar = {} end
	local t = db.totemBar
	if t ~= cfgTable then
		for k, v in pairs(TB.DEFAULTS) do
			if type(t[k]) ~= type(v) then t[k] = type(v) == "table" and CopyTable(v) or v end
		end
		local seen, order = {}, {}
		for _, el in ipairs(t.order) do
			if SLOT[el] and not seen[el] then seen[el] = true; table.insert(order, el) end
		end
		for _, el in ipairs(ELEMENTS) do if not seen[el] then table.insert(order, el) end end
		t.order = order
		for name, v in pairs(t.warnOver) do
			if type(name) ~= "string" or type(v) ~= "number" then t.warnOver[name] = nil end
		end
		local b = t.border
		if type(b.show) ~= "boolean" or type(b.size) ~= "number" or type(b.color) ~= "table" then t.border = CopyTable(TB.DEFAULTS.border) end
		cfgTable = t
	end
	return t
end
TB.cfg = cfg

-- The look: the bar's own, or General's.
local function look()
	local c, db = cfg(), ns.getDB()
	if c.follow then return db.iconSize, db.border, db.cdText and db.cdTextSize or nil end
	return c.size, c.border, c.cdSize
end

-- An element's multi-cast action slot (Call of the Elements' page, the first set).
local function multiAction(slot)
	local ok, bar = pcall(C_ActionBar.GetMultiCastBarIndex)
	if not ok or type(bar) ~= "number" or isSecret(bar) then bar = 12 end
	return (bar - 1) * 12 + slot
end

-- The totems known for an element, by spell ID (Blizzard's lists for its popouts).
local function knownTotems(slot)
	if not GetMultiCastTotemSpells then return {} end
	local ok, ids = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
	return ok and ids or {}
end

------------------------------------------------------------------------
-- Frames. Created when the file loads, which is allowed even during a /reload in combat.
------------------------------------------------------------------------
local bar = CreateFrame("Frame", "ShamanForeverTotemBar", UIParent)
bar:SetSize(1, 1)
bar:SetPoint("CENTER", 0, -120)
bar:SetFrameStrata("MEDIUM")
bar:Hide()

-- Helpers the arrow tabs and pickers click to show or hide the popout named in setframe.
local function stateHelper(value)
	local h = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
	h:SetAttribute("useOnKeyDown", false)
	h:SetAttribute("type", "attribute")
	h:SetAttribute("attribute-frame", SecureStateDriverManager)
	h:SetAttribute("attribute-name", "setstate")
	h:SetAttribute("attribute-value", "state-visibility " .. value)
	return h
end
local showHelper, hideHelper = stateHelper("show"), stateHelper("hide")

local FONT = "ShamanForeverTotemBarFont"
local font = CreateFont(FONT)

local slots = {}   -- element -> slot record

local function edgeRing(parent, anchor)
	local ring = {}
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
			{ "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetColorTexture(0.88, 0.2, 0.17, 1)
		t:SetPoint(e[1], anchor, e[1])
		t:SetPoint(e[2], anchor, e[2])
		if e[3] then t:SetWidth(e[3]) end
		if e[4] then t:SetHeight(e[4]) end
		table.insert(ring, t)
	end
	return ring
end

for _, el in ipairs(ELEMENTS) do
	local slot = SLOT[el]
	local s = { el = el, slot = slot }
	slots[el] = s

	-- The click area: right-click dismisses, left-click casts the pick, Alt+click opens the
	-- element's picker. Press-and-hold gives the one click two actions, which Alt+click needs (the
	-- press names the popout, the release shows it), so casts and dismissals happen on the press.
	local b = CreateFrame("Button", "ShamanForeverTotem" .. NAME[el], bar, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("pressAndHoldAction", true)
	-- "*" matches any modifier (a plain "type2" is only used with none held); Alt+left-click's own
	-- "alt-type1" is more specific, so it still wins.
	b:SetAttribute("*type2", "destroytotem")
	b:SetAttribute("totem-slot", slot)
	b:SetAttribute("alt-type1", "attribute")
	b:SetAttribute("alt-attribute-frame1", SecureStateDriverManager)
	b:SetAttribute("alt-attribute-name1", "setframe")
	b:SetAttribute("alt-typerelease1", "click")
	b:SetAttribute("alt-clickbutton1", showHelper)
	s.button = b

	-- What the player sees, on a plain frame over the button.
	local v = CreateFrame("Frame", nil, bar)
	v:SetAllPoints(b)
	v:SetFrameLevel(b:GetFrameLevel() + 2)
	v:EnableMouse(false)
	s.vis = v
	v.bg = v:CreateTexture(nil, "BACKGROUND")
	v.bg:SetAllPoints()
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	v.cd = CreateFrame("Cooldown", nil, v, "CooldownFrameTemplate")
	v.cd:SetAllPoints()
	v.cd:SetFrameLevel(v:GetFrameLevel() + 3)
	v.cd:SetDrawEdge(false)
	v.cd:SetDrawBling(false)
	v.cd:SetCountdownFont(FONT)
	v.timer = CreateFrame("StatusBar", nil, v)
	v.timer:SetPoint("BOTTOMLEFT")
	v.timer:SetPoint("BOTTOMRIGHT")
	v.timer:SetHeight(5)
	v.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	v.timer:SetStatusBarColor(COLOR[el][1], COLOR[el][2], COLOR[el][3])
	v.timer.bg = v.timer:CreateTexture(nil, "BACKGROUND")
	v.timer.bg:SetAllPoints()
	v.timer.bg:SetColorTexture(0, 0, 0, 0.6)
	v.timer:SetFrameLevel(v.cd:GetFrameLevel() + 1)
	v.timer:Hide()
	-- The expiring warning: its alpha is the remaining time through a curve, so it can appear and
	-- disappear in combat. A grey copy of the icon, a red ring, and a dark layer that pulses; it sits
	-- above the icon and below the cooldown, so the swipe and countdown stay readable.
	v.warn = CreateFrame("Frame", nil, v)
	v.warn:SetAllPoints()
	v.warn:SetFrameLevel(v:GetFrameLevel() + 1)
	v.warn:SetAlpha(0)
	v.warn.grey = v.warn:CreateTexture(nil, "ARTWORK")
	v.warn.grey:SetAllPoints()
	v.warn.grey:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	v.warn.grey:SetDesaturated(true)
	v.warn.ring = edgeRing(v.warn, v)
	v.warn.dim = v.warn:CreateTexture(nil, "OVERLAY")
	v.warn.dim:SetAllPoints()
	v.warn.dim:SetColorTexture(0, 0, 0, 1)
	v.warn.dim:SetAlpha(0)
	local pulse = v.warn.dim:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local a = pulse:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(0.55)
	a:SetDuration(0.6)
	a:SetSmoothing("IN_OUT")
	v.warn.pulse = pulse

	-- Arrow tab (secure) and its look (plain, shown while the mouse is over the slot or the tab).
	local ar = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
	ar:RegisterForClicks("AnyUp", "AnyDown")
	ar:SetAttribute("pressAndHoldAction", true)
	ar:SetAttribute("type", "attribute")
	ar:SetAttribute("attribute-frame", SecureStateDriverManager)
	ar:SetAttribute("attribute-name", "setframe")
	ar:SetAttribute("*typerelease1", "click")
	ar:SetAttribute("*clickbutton1", showHelper)
	ar:SetAttribute("*typerelease2", "click")
	ar:SetAttribute("*clickbutton2", hideHelper)
	s.arrow = ar
	local av = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	av:SetAllPoints(ar)
	av:SetFrameLevel(ar:GetFrameLevel() + 2)
	av:EnableMouse(false)
	av:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	av:SetBackdropColor(0.06, 0.05, 0.03, 0.92)
	av:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
	-- The arrow from Blizzard's own totem bar art (its flyout button highlight), turned to point
	-- the way the picker opens.
	av.glyph = av:CreateTexture(nil, "OVERLAY")
	av.glyph:SetTexture("Interface\\Buttons\\UI-TotemBar")
	av.glyph:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	av.glyph:SetBlendMode("ADD")
	av.glyph:SetPoint("CENTER")
	av:SetAlpha(0)
	s.arrowVis = av

	-- Popout: its visibility belongs to the state driver, driven by the arrow tab and the pickers.
	local pop = CreateFrame("Frame", "ShamanForeverTotemPopout" .. NAME[el], bar)
	pop:SetSize(1, 1)
	pop.bg = pop:CreateTexture(nil, "BACKGROUND")
	pop.bg:SetAllPoints()
	pop.bg:SetColorTexture(0, 0, 0, 0.72)
	pop:SetFrameStrata("HIGH")
	pop.buttons = {}
	s.popout = pop
	b:SetAttribute("alt-attribute-value1", pop)
	-- While the popout is open, a click anywhere else (left or right, the arrow tab included) lands
	-- on this invisible, screen-wide button under the pickers, and closes it the same way.
	local catch = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
	catch:SetAllPoints(UIParent)
	catch:SetFrameLevel(pop:GetFrameLevel() + 1)
	catch:RegisterForClicks("AnyUp", "AnyDown")
	catch:SetAttribute("pressAndHoldAction", true)
	catch:SetAttribute("type", "attribute")
	catch:SetAttribute("attribute-frame", SecureStateDriverManager)
	catch:SetAttribute("attribute-name", "setframe")
	catch:SetAttribute("attribute-value", pop)
	catch:SetAttribute("typerelease", "click")
	catch:SetAttribute("clickbutton", hideHelper)
	pop.catch = catch
	RegisterStateDriver(pop, "visibility", "hide")
	ar:SetAttribute("attribute-value", pop)
end

-- Hover: the arrow tab's look shows while the mouse is over the slot, the tab or the open popout.
local function hover(s)
	local over = s.button:IsMouseOver() or s.arrow:IsMouseOver() or (s.popout:IsShown() and s.popout:IsMouseOver())
	s.arrowVis:SetAlpha((over or s.popout:IsShown()) and cfg().arrows and 1 or 0)
end

------------------------------------------------------------------------
-- Drawing (any time, combat included)
------------------------------------------------------------------------
-- Remaining time -> 1 inside the last `secs` seconds, else 0. One curve per value.
local warnCurves = {}
local function warnCurve(secs)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) or secs <= 0 then return nil end
	local c = warnCurves[secs]
	if not c then
		c = C_CurveUtil.CreateCurve()
		if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
		c:AddPoint(0, 1)
		c:AddPoint(secs, 1)
		c:AddPoint(secs + 0.05, 0)
		warnCurves[secs] = c
	end
	return c
end
-- Remaining time -> 0 once it has run out (an expired duration object may linger).
local liveCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
	liveCurve = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then liveCurve:SetType(Enum.LuaCurveType.Linear) end
	liveCurve:AddPoint(0, 0)
	liveCurve:AddPoint(0.05, 1)
end
local TIMER_REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local TIMER_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0

-- The totem's name, if known: our own cast, or out of combat the slot itself.
local function totemName(slot)
	local ok, _, n = pcall(GetTotemInfo, slot)
	if ok and not isSecret(n) and type(n) == "string" and n ~= "" then return n end
	return ns.totemNameInSlot and ns.totemNameInSlot(slot)
end

local anyDown = false

-- The parts that follow the remaining time: the warning, and the time bar once it has run out.
-- Values from the duration object may be secret, so they only ever go straight to SetAlpha.
function TB.alphas(s)
	local d, v = s.dur, s.vis
	if not d then return end
	if s.curve then
		local ok, a = pcall(d.EvaluateRemainingDuration, d, s.curve)
		if ok then v.warn:SetAlpha(a) else v.warn:SetAlpha(0) end
	else v.warn:SetAlpha(0) end
	if liveCurve and v.timer:IsShown() then
		local ok, a = pcall(d.EvaluateRemainingDuration, d, liveCurve)
		if ok then v.timer:SetAlpha(a) end
	end
end

local function drawSlot(s)
	local c, v = cfg(), s.vis
	local ok, d = pcall(GetTotemDuration, s.slot)
	if ok and d then
		-- A totem is down.
		local iok, _, _, _, _, icon = pcall(GetTotemInfo, s.slot)
		if iok and (isSecret(icon) or icon) then pcall(v.icon.SetTexture, v.icon, icon); pcall(v.warn.grey.SetTexture, v.warn.grey, icon) end
		v.icon:SetDesaturated(false)
		v.icon:SetAlpha(1)
		v.bg:SetColorTexture(0, 0, 0, 1)
		local swipe = c.timer == "swipe" or c.timer == "both"
		v.cd:SetDrawSwipe(swipe)
		pcall(v.cd.SetCooldownFromDurationObject, v.cd, d, true)
		if c.timer == "bar" or c.timer == "both" then
			pcall(v.timer.SetTimerDuration, v.timer, d, TIMER_IMMEDIATE, TIMER_REMAINING)
			v.timer:Show()
		else v.timer:Hide() end
		s.dur = d
		s.curve = warnCurve(c.warnOver[totemName(s.slot) or ""] or c.warn)
		TB.alphas(s)
		return true
	end
	s.dur, s.curve = nil, nil
	-- Empty: the element's pick, greyed, or its colour, or nothing.
	v.cd:Clear()
	v.timer:Hide()
	v.warn:SetAlpha(0)
	local tex = c.empty == "pick" and GetActionTexture and GetActionTexture(multiAction(s.slot))
	if isSecret(tex) or tex then
		pcall(v.icon.SetTexture, v.icon, tex)
		v.icon:SetDesaturated(true)
		v.icon:SetAlpha(0.45)
		v.bg:SetColorTexture(0, 0, 0, 0.6)
	elseif c.empty ~= "blank" then
		local col = COLOR[s.el]
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35, 0.8)
	else
		v.icon:SetTexture(nil)
		v.bg:SetColorTexture(0, 0, 0, 0)
	end
	return false
end

local function drawAll()
	local down = false
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		s.down = drawSlot(s)
		if s.down then down = true end
	end
	anyDown = down
end
TB.draw = drawAll

-- The warnings follow the remaining time, so they are re-evaluated a few times a second.
local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	if not bar:IsShown() then return end
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		hover(s)
		if s.down then TB.alphas(s) end
	end
end)

------------------------------------------------------------------------
-- Blizzard's totem frames
------------------------------------------------------------------------
-- The totems under the player frame: made invisible and click-through rather than hidden, so
-- nothing moves in Blizzard's player-frame layout (hiding it from here would re-lay that out,
-- PetFrame included, from addon code). Left alone when another addon has taken it over.
local function totemFrameOurs()
	if not ns.getDB() then return false end
	local p = TotemFrame and TotemFrame:GetParent()
	local name = p and p:GetName() or ""
	return name == "PlayerFrame" or name:find("^PlayerFrame") ~= nil or name:find("ManagedFrame") ~= nil
end
local totemFrameHidden = false
local function applyTotemFrame()
	if not TotemFrame or not totemFrameOurs() then return end
	local hide = cfg().enabled and cfg().hideTotemFrame
	if not hide and not totemFrameHidden then return end
	totemFrameHidden = hide
	TotemFrame:SetAlpha(hide and 0 or 1)
	for _, child in ipairs({ TotemFrame:GetChildren() }) do
		if child.EnableMouse and not (child.IsProtected and child:IsProtected()) then child:EnableMouse(not hide) end
	end
end
if TotemFrame and TotemFrame.Update then hooksecurefunc(TotemFrame, "Update", applyTotemFrame) end

-- The Totem Action Bar: moved under a hidden frame out of combat, and back when wanted.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()
local actionBarParent
local function applyActionBar()
	local f = MultiCastActionBarFrame
	if not f or InCombatLockdown() then return end
	local hide = cfg().enabled and cfg().hideActionBar
	if hide and f:GetParent() ~= hiddenParent then
		actionBarParent = f:GetParent()
		f:SetParent(hiddenParent)
	elseif not hide and f:GetParent() == hiddenParent then
		f:SetParent(actionBarParent or UIParent)
	end
end

------------------------------------------------------------------------
-- Layout (out of combat only)
------------------------------------------------------------------------
local pending = false
local mover

local POP_STEP = 3
local function layoutPopout(s, size)
	local c, pop = cfg(), s.popout
	local slot = s.slot
	local ids = knownTotems(slot)
	table.insert(ids, 1, 0)   -- "No totem" first, nearest the slot (as Blizzard's)
	local psz = math.floor(size * 0.8 + 0.5)
	local action = multiAction(slot)
	for i, id in ipairs(ids) do
		local p = pop.buttons[i]
		if not p then
			p = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
			p:RegisterForClicks("AnyUp", "AnyDown")
			p:SetAttribute("pressAndHoldAction", true)
			p:SetAttribute("*type1", "multispell")   -- right-click has no press action: it only closes
			p:SetAttribute("typerelease", "click")
			p:SetAttribute("clickbutton", hideHelper)
			p:SetFrameLevel(pop:GetFrameLevel() + 5)
			p.icon = p:CreateTexture(nil, "ARTWORK")
			p.icon:SetAllPoints()
			p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
			pop.buttons[i] = p
		end
		p.spellID = id
		p:SetAttribute("action", action)
		p:SetAttribute("spell", id)
		p:SetSize(psz, psz)
		p:ClearAllPoints()
		local off = POP_STEP + (i - 1) * (psz + POP_STEP)
		if c.pop == "up" then p:SetPoint("BOTTOM", pop, "BOTTOM", 0, off)
		elseif c.pop == "down" then p:SetPoint("TOP", pop, "TOP", 0, -off)
		elseif c.pop == "right" then p:SetPoint("LEFT", pop, "LEFT", off, 0)
		else p:SetPoint("RIGHT", pop, "RIGHT", -off, 0) end
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
	local len = POP_STEP + #ids * (psz + POP_STEP)
	local tab = c.arrowSize
	pop:ClearAllPoints()
	if c.pop == "up" then pop:SetSize(psz + 2 * POP_STEP, len); pop:SetPoint("BOTTOM", s.button, "TOP", 0, tab + 4)
	elseif c.pop == "down" then pop:SetSize(psz + 2 * POP_STEP, len); pop:SetPoint("TOP", s.button, "BOTTOM", 0, -tab - 4)
	elseif c.pop == "right" then pop:SetSize(len, psz + 2 * POP_STEP); pop:SetPoint("LEFT", s.button, "RIGHT", tab + 4, 0)
	else pop:SetSize(len, psz + 2 * POP_STEP); pop:SetPoint("RIGHT", s.button, "LEFT", -tab - 4, 0) end
	if not c.arrows then RegisterStateDriver(pop, "visibility", "hide") end
end

local function layoutArrow(s)
	local c, ar, b = cfg(), s.arrow, s.button
	local tab = c.arrowSize
	ar:ClearAllPoints()
	if c.pop == "up" then ar:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 1, 1); ar:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -1, 1); ar:SetHeight(tab)
	elseif c.pop == "down" then ar:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 1, -1); ar:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -1, -1); ar:SetHeight(tab)
	elseif c.pop == "right" then ar:SetPoint("TOPLEFT", b, "TOPRIGHT", 1, -1); ar:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, 1); ar:SetWidth(tab)
	else ar:SetPoint("TOPRIGHT", b, "TOPLEFT", -1, -1); ar:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -1, 1); ar:SetWidth(tab) end
	ar:SetShown(c.arrows)
	local g = s.arrowVis.glyph
	g:SetSize(math.max(tab * 1.1, 10), math.max(tab * 0.6, 6))
	g:SetRotation(({ up = 0, down = math.pi, right = -math.pi / 2, left = math.pi / 2 })[c.pop])
	s.arrowVis:SetShown(c.arrows)
end

local function visibilityDriver()
	local c = cfg()
	if not c.enabled or c.show == "never" then return "hide" end
	if not ns.getAccount().locked then return "show" end
	if c.show == "combat" then return "[petbattle] hide; [combat] show; hide" end
	if c.show == "active" then return "[petbattle] hide; [combat] show; " .. (anyDown and "show" or "hide") end
	return "[petbattle] hide; show"
end
local lastDriver

local function layout()
	if InCombatLockdown() then pending = true return end
	pending = false
	local c = cfg()
	local size, border, cdSize = look()
	font:SetFont(STANDARD_TEXT_FONT, cdSize or 12, "OUTLINE")
	local shown = {}
	for _, el in ipairs(c.order) do
		local s = slots[el]
		local known = #knownTotems(s.slot) > 0 or not GetMultiCastTotemSpells
		local on = c.enabled and not c.hidden[el] and known
		s.button:SetShown(on)
		s.vis:SetShown(on)
		if on then table.insert(shown, s) else s.arrow:Hide(); s.arrowVis:Hide(); RegisterStateDriver(s.popout, "visibility", "hide") end
	end
	local row = c.dir == "row"
	if row and c.pop ~= "up" and c.pop ~= "down" then c.pop = "up" end
	if not row and c.pop ~= "right" and c.pop ~= "left" then c.pop = "right" end
	for i, s in ipairs(shown) do
		local b = s.button
		b:SetSize(size, size)
		b:ClearAllPoints()
		local off = (i - 1) * (size + c.spacing)
		if row then b:SetPoint("LEFT", bar, "LEFT", off, 0) else b:SetPoint("TOP", bar, "TOP", 0, -off) end
		b:SetAttribute("*type1", c.cast and "action" or nil)
		b:SetAttribute("action", multiAction(s.slot))
		if ns.applyBorder then ns.applyBorder(s.vis, border) end
		s.cdShown = cdSize ~= nil
		s.vis.cd:SetHideCountdownNumbers(cdSize == nil)
		s.vis.warn.grey:SetShown(c.warnGrey)
		for _, t in ipairs(s.vis.warn.ring) do t:SetShown(c.warnRing) end
		if c.warnPulse then s.vis.warn.pulse:Play() else s.vis.warn.pulse:Stop(); s.vis.warn.dim:SetAlpha(0) end
		layoutArrow(s)
		layoutPopout(s, size)
	end
	local n = math.max(#shown, 1)
	local long = n * size + (n - 1) * c.spacing
	if row then bar:SetSize(long, size) else bar:SetSize(size, long) end
	-- Scale and opacity: out of combat only, like everything on a frame holding secure buttons.
	bar:SetScale(c.scale)
	bar:SetAlpha(c.alpha)
	bar:ClearAllPoints()
	bar:SetPoint(c.point, UIParent, c.point, c.x / c.scale, c.y / c.scale)
	drawAll()
	local driver = visibilityDriver()
	if driver ~= lastDriver then
		lastDriver = driver
		RegisterStateDriver(bar, "visibility", driver)
	end
	applyTotemFrame()
	applyActionBar()
	if mover then mover.update() end
end
TB.layout = layout

-- Settings changed (options page): relayout now, or when combat ends.
function TB.apply()
	cfgTable = nil
	if InCombatLockdown() then
		pending = true
		ns.say("totem bar changes wait until combat ends")
	end
	layout()
end

------------------------------------------------------------------------
-- Positioning: a handle over the bar while positioning is unlocked
------------------------------------------------------------------------
mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
mover:SetFrameStrata("DIALOG")
mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
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
mover:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
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
	if button == "RightButton" and ns.OpenOptions then ns.OpenOptions("totembar") end
end)
-- Mouse wheel: scale. Shift + wheel: opacity. As for groups.
mover:SetScript("OnMouseWheel", function(self, delta)
	if InCombatLockdown() then return end
	local c = cfg()
	local function clamp(v, lo, hi) return math.min(math.max(math.floor(v * 100 + 0.5) / 100, lo), hi) end
	if IsShiftKeyDown() then c.alpha = clamp(c.alpha + delta * 0.05, 0.1, 1)
	else c.scale = clamp(c.scale + delta * 0.05, 0.5, 3) end
	layout()
	self.label:SetText(string.format("Totem bar: scale %.2f, opacity %.0f%%", c.scale, c.alpha * 100))
	if ns.RefreshOptions then ns.RefreshOptions() end
end)
function mover.update()
	local on = cfg().enabled and not ns.getAccount().locked and not InCombatLockdown()
	if on then
		mover:ClearAllPoints()
		mover:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
		mover:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)
	end
	if on then mover.label:SetText("Totem bar") end
	mover:SetShown(on)
end

-- Combat started while unlocked: the handle goes at once (it is a plain frame).
function TB.lockInCombat()
	mover:Hide()
	pending = true
end

------------------------------------------------------------------------
-- Tooltips and hover on the slot buttons
------------------------------------------------------------------------
for _, el in ipairs(ELEMENTS) do
	local s = slots[el]
	s.button:SetScript("OnEnter", function(self)
		hover(s)
		local c = cfg()
		if c.tips == "never" or (c.tips == "ooc" and InCombatLockdown()) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok, d = pcall(GetTotemDuration, s.slot)
		if ok and d then
			pcall(GameTooltip.SetTotem, GameTooltip, s.slot)
		else
			local action = multiAction(s.slot)
			if HasAction and HasAction(action) then pcall(GameTooltip.SetAction, GameTooltip, action)
			else GameTooltip:SetText(NAME[el] .. ": no totem picked") end
		end
		GameTooltip:Show()
	end)
	s.button:SetScript("OnLeave", function() GameTooltip:Hide(); hover(s) end)
	s.arrow:SetScript("OnEnter", function() hover(s) end)
	s.arrow:SetScript("OnLeave", function() hover(s) end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_ENABLED",
		"SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MULTI_CAST_ACTIONBAR" }) do
	pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
	if not ns.getDB() then return end
	if event == "PLAYER_TOTEM_UPDATE" then
		local wasDown = anyDown
		for _, el in ipairs(ELEMENTS) do slots[el].down = drawSlot(slots[el]) end
		local down = false
		for _, el in ipairs(ELEMENTS) do if slots[el].down then down = true end end
		anyDown = down
		-- "In combat or a totem down": the driver changes out of combat only.
		if down ~= wasDown and cfg().show == "active" then
			if InCombatLockdown() then pending = true else layout() end
		end
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		local base = multiAction(1) - 1
		if not isSecret(arg1) and type(arg1) == "number" and arg1 > base and arg1 <= base + 12 then drawAll() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pending then layout() elseif mover then mover.update() end
	else
		layout()
	end
end)

-- The two setups (design/totem-bar.md), and which one the settings match.
local SETUPS = {
	everything = { cast = true, arrows = true, hideActionBar = true, hideTotemFrame = true },
	active = { cast = false, arrows = false, hideActionBar = false, hideTotemFrame = true },
}
function TB.setup()
	local c = cfg()
	for name, set in pairs(SETUPS) do
		local match = true
		for k, v in pairs(set) do if c[k] ~= v then match = false end end
		if match then return name end
	end
	return "custom"
end
function TB.setupName() return ({ everything = "Everything", active = "Active totems only", custom = "Custom" })[TB.setup()] end
function TB.applySetup(name)
	for k, v in pairs(SETUPS[name] or {}) do cfg()[k] = v end
end
-- An element's pick, as a texture (the options preview).
function TB.pickTexture(el) return GetActionTexture(multiAction(SLOT[el])) end

-- For /sf debug.
function TB.debug()
	local c = cfg()
	local mc = MultiCastActionBarFrame
	return string.format("totem bar %s, show %s, driver %s, shown %s; TotemFrame parent %s alpha %s; Totem Action Bar parent %s",
		c.enabled and "on" or "off", c.show, tostring(lastDriver), tostring(bar:IsShown()),
		TotemFrame and TotemFrame:GetParent() and (TotemFrame:GetParent():GetName() or "?") or "none",
		TotemFrame and string.format("%.2f", TotemFrame:GetAlpha()) or "-",
		mc and (mc:GetParent() == hiddenParent and "hidden" or (mc:GetParent() and mc:GetParent():GetName() or "?")) or "none")
end
