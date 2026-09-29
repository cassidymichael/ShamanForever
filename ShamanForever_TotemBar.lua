-- Totem bar: one bar that can replace both of Blizzard's totem frames, the totems under the player
-- frame (timers, right-click dismiss) and the Totem Action Bar (a pick per element, arrow popouts).
--
-- Every click is a secure button set up out of combat, so it works in combat too:
-- * slot button: right-click "destroytotem" (totem-slot), left-click "action" on the element's
--   multi-cast action slot, so it casts whatever the element's pick is, and follows it.
-- * pickers: a secure header's snippets open and close the popouts (secure snippets work on Forever
--   since build 70009). The arrow tab toggles its popout, Alt+click on a slot opens it, and a click
--   outside it (the catch button) closes it. With "Open pickers on hover", entering a slot or its tab
--   opens it, and leaving the slot and the strip from it to the picker's far end closes it.
-- * popout: "multispell" buttons (spell 0 is "No totem") that change the pick, then close it.
-- Layout, attributes and anything that shows, hides or moves a secure button change only out of
-- combat; changes asked for in combat wait for it to end. Every layout, and the end of combat,
-- closes any open picker. What the player sees sits on plain frames over the secure buttons, so it
-- can change any time. Verbs, as in the modules: apply (settings changed), layout (out of combat),
-- refresh (read the slots and show them), draw (show what is known, ten times a second).
-- In combat, which totem is in a slot is secret: its icon is drawn by handing the secret icon to
-- SetTexture, timers come from the slot's duration object, and warnings are the remaining time
-- through a curve into SetAlpha. Which totem it is (per-totem warning times, "not your pick") comes
-- from our own casts (ns.Totems), by spell ID.

local _, ns = ...

local TB = {}
ns.TotemBar = TB

local ELEMENTS = { "earth", "fire", "water", "air" }
local SLOT = { fire = 1, earth = 2, water = 3, air = 4 }   -- Blizzard's totem slots
local NAME = { earth = "Earth", fire = "Fire", water = "Water", air = "Air" }
TB.ELEMENTS, TB.NAME, TB.SLOT = ELEMENTS, NAME, SLOT

-- Per profile, in db.totemBar.
TB.DEFAULTS = {
	mode = "everything",      -- the Totems cards: blizzard (our bar off) | active (totems and timers) | everything
	point = "CENTER", x = 0, y = -100,   -- x, y in UIParent units, so scaling keeps the centre
	scale = 1,
	alpha = 1,
	-- always | active (in combat or a totem down) | combat | target (in combat or with an enemy target)
	show = "always",
	fadeAfter = 0,            -- seconds it stays once combat ends, then fades out (0: none)
	order = { "earth", "fire", "water", "air" },
	hidden = {},              -- element -> true to leave its slot out
	dir = "row",              -- row | column
	pop = "up",               -- where pickers open: up | down (row), right | left (column)
	spacing = 6,
	-- The Buttons settings (cast, arrows, call, recall) only apply in Everything.
	cast = true,              -- left-click casts the element's pick
	arrows = true,            -- arrow tab opens the element's picker
	arrowSize = 18,
	tips = "always",          -- always | ooc | never
	keys = false,             -- each button's key, in its corner
	call = true,              -- Call of the Elements button, once learned
	recall = true,            -- Totemic Recall button: right-click dismisses all; left-click casts it once learned
	extras = "ends",          -- where they sit: ends (Call first, Recall last, as Blizzard's) | before | after the slots
	extrasScale = 0.8,        -- their size, as a share of the slots' (centred on the slots' line)
	sizeFollow = true,        -- icon size from General; off: size (set from General's the first time)
	-- border, glow, pop, timers: the bar's own styles, if it has them (ShamanForever_Style.lua)
	empty = "pick",           -- a totem not down: pick (the element's pick) | frame (element colour) | blank
	idleGrey = false,         -- the pick, greyed (off: in colour)
	idleAlpha = 0.4,          -- the pick's opacity
	offPick = true,           -- a totem down that isn't the pick: show the pick small beside the slot
	badgeSize = 0.45,         -- that badge, as a share of the slot's size
	badgeAlpha = 0.75,        -- its opacity
	badgeSat = 0.5,           -- its colour (0 grey, 1 full colour)
	warnGrey = false,
	warnRing = false,
	warnPulse = true,
	warnGlow = false,         -- a pulsing glow inside the slot (the bar's glow style)
	expiredPop = true,        -- the totem pops and fades the moment it runs out
	goneSound = "none",       -- a sound when a totem runs out or is killed (ShamanForever_Sounds.lua)
	warn = 10,                -- seconds before the end (0 = off)
	-- Totem -> seconds, instead of warn (short-lived ones). Keyed by the client's rank-less spell
	-- name; the defaults (Earthbind and Stoneclaw, 5 s; Mana Tide, 3 s, as on its element: its
	-- 5-minute cooldown allows no recast) are filled by cfg(), in the client's language.
	warnOver = {},
	killed = true,            -- flash when a totem dies with time left, made of:
	killedPop = true,         --   the slot bursts bigger for a moment
	killedGlow = true,        --   a red glow around the slot
	killedMark = true,        --   a red cross over the slot until it is recast, up to 5 s
	range = true,             -- a strip along the top: are you in range of your own totem's buff (ShamanForever_TotemRange.lua)
	rangeHeight = 4,          --   its height in screen pixels (ns.linePx)
	rangeIn = { 0.2, 0.8, 0.25, 0 },       --   with the buff (0: nothing shows in range)
	rangeOut = { 0.9, 0.12, 0.08, 0.85 },  --   without it
	pickHover = false,        -- hovering a slot or its tab opens its picker (Everything)
	pulse = "off",            -- time to a pulsing totem's next pulse: off | bar | text (ShamanForever_TotemPulse.lua)
}

local isSecret = ns.isSecret

-- Number settings: the options sliders' ranges. Anything outside (a damaged or hand-made import)
-- is clamped, so layout() never gets a scale of 0 or a NaN.
local RANGES = {
	scale = { 0.5, 3 }, alpha = { 0.1, 1 }, spacing = { -20, 20 }, size = { 24, 96 },
	arrowSize = { 8, 32 }, extrasScale = { 0.5, 1.5 }, idleAlpha = { 0.1, 1 },
	badgeSize = { 0.25, 0.8 }, badgeAlpha = { 0.1, 1 }, badgeSat = { 0, 1 }, warn = { 0, 30 }, rangeHeight = { 1, 12 },
	fadeAfter = { 0, 10 },
}
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, r) return math.min(math.max(v, r[1]), r[2]) end

-- The profile's bar settings, with defaults filled and wrong types or values reset (imported profiles).
local cfgTable
local function cfg()
	local db = ns.getDB()
	if type(db.totemBar) ~= "table" then db.totemBar = {} end
	local t = db.totemBar
	if t ~= cfgTable then
		-- Saves from before the Totems cards: "enabled" and Show "never" meant our bar off.
		if t.mode == nil and (t.enabled == false or t.show == "never") then t.mode = "blizzard" end
		-- Before styles (0.6.1 and earlier) one switch covered size and border: keep an own look as own.
		if t.follow == false then
			t.sizeFollow = false
			if type(t.border) == "table" then t.border.follow = false end
		elseif t.follow == true then t.size, t.border = nil, nil end
		t.enabled, t.hideTotemFrame, t.hideActionBar, t.killedPulse, t.follow = nil, nil, nil, nil, nil
		if t.mode ~= "blizzard" and t.mode ~= "active" and t.mode ~= "everything" then t.mode = nil end
		if t.show ~= "always" and t.show ~= "active" and t.show ~= "combat" and t.show ~= "target" then t.show = nil end
		-- The default per-totem times, by the client's names (English until they have loaded; the
		-- lookup in warnSecs also takes the English name, so either works).
		if type(t.warnOver) ~= "table" then
			t.warnOver = { [ns.Spells.name("earthbind")] = 5, [ns.Spells.name("stoneclaw")] = 5,
				[ns.Spells.name("manaTide")] = 3 }
		end
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
		for _, k in ipairs({ "rangeIn", "rangeOut" }) do
			if not ns.isColor(t[k]) then t[k] = CopyTable(TB.DEFAULTS[k]) end
		end
		cfgTable = t
	end
	return t
end
TB.cfg = cfg

-- What the mode allows: our bar at all (active or everything), and the Buttons settings (everything).
-- Only shamans get the bar: for any other class it stays hidden and Blizzard's frames are left alone.
local playerClass   -- cached once known: it never changes
local function isShaman()
	if not playerClass then playerClass = select(2, UnitClass("player")) end
	return playerClass == "SHAMAN"
end
local function barOn() return isShaman() and cfg().mode ~= "blizzard" end
TB.isShaman = isShaman
local function feat(key) local c = cfg(); return barOn() and c.mode == "everything" and c[key] or false end
TB.barOn, TB.feat = barOn, feat

-- The slots' size and border: each General's, or the bar's own.
local function look()
	local c, db = cfg(), ns.getDB()
	return (not c.sizeFollow and c.size) or db.iconSize, ns.Style.get("totembar", "border")
end
-- Own icon size from General's current one, the first time; later its own is kept.
function TB.setSizeFollow(follow)
	local c = cfg()
	if not follow and not c.size then c.size = ns.getDB().iconSize end
	c.sizeFollow = follow
end

-- An element's multi-cast action slot (Call of the Elements' page, the first set).
local function multiAction(slot)
	local ok, bar = ns.try("totem bar: multi-cast page", C_ActionBar.GetMultiCastBarIndex)
	if not ok or type(bar) ~= "number" or isSecret(bar) then bar = 12 end
	return (bar - 1) * 12 + slot
end

------------------------------------------------------------------------
-- Geometry, shared with the options' preview of the bar (ShamanForever_OptionsLook.lua), so both
-- place everything the same way. Each reads the bar's settings (cfg) at the call.
------------------------------------------------------------------------
local POP_STEP = 3    -- a picker's padding, and the gap between its buttons
TB.BADGE_GAP = 3      -- between a slot and its "not your pick" badge
local EXTRA_GAP = 6   -- added to the spacing between the extras and the slots

-- Where everything sits along the bar, from its left or top end: Call and Recall before the slots
-- (TB.extraSides, below), n slots of the given size, then Call and Recall after. Returns a list of
-- { key, offset, size, extra } (key: an extra's key, or the slot's place among the n), the bar's
-- length and its thickness (its largest button: every button is centred on its line).
function TB.along(n, size, px)
	local c = cfg()
	local before, after = TB.extraSides()
	-- px (one screen pixel in the bar's units): sizes and gaps in whole pixels, as on the bar.
	local function round(v) return px and ns.roundPx(v, px) or math.floor(v + 0.5) end
	local esz, gap, extraGap = round(size * c.extrasScale), c.spacing, c.spacing + EXTRA_GAP
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
	-- Negative spacing overlaps buttons: one shorter than the overlap can start before the first or
	-- end before the last, so the bar spans them all.
	local lo, hi = 0, 0
	for _, it in ipairs(list) do
		lo = math.min(lo, it.offset)
		hi = math.max(hi, it.offset + it.size)
	end
	if lo < 0 then for _, it in ipairs(list) do it.offset = it.offset - lo end end
	local line = (#before + #after > 0) and math.max(size, esz) or size
	return list, math.max(hi - lo, size), line
end

-- A picker's button size, for slots of this size, and its length for n buttons of that size.
function TB.popButtonSize(size) return math.floor(size * 0.8 + 0.5) end
function TB.popLength(n, psz) return POP_STEP + n * (psz + POP_STEP) end
-- A picker of n buttons (psz) beside anchor, a slot, on the side pickers open, past the arrow tab.
function TB.placePopout(pop, anchor, n, psz)
	local c = cfg()
	local len, thick, tab = TB.popLength(n, psz), psz + 2 * POP_STEP, c.arrowSize
	pop:ClearAllPoints()
	if c.pop == "up" then pop:SetSize(thick, len); pop:SetPoint("BOTTOM", anchor, "TOP", 0, tab + 4)
	elseif c.pop == "down" then pop:SetSize(thick, len); pop:SetPoint("TOP", anchor, "BOTTOM", 0, -tab - 4)
	elseif c.pop == "right" then pop:SetSize(len, thick); pop:SetPoint("LEFT", anchor, "RIGHT", tab + 4, 0)
	else pop:SetSize(len, thick); pop:SetPoint("RIGHT", anchor, "LEFT", -tab - 4, 0) end
end
-- A picker's i-th button (psz), counted from the slot's end.
function TB.placePopButton(b, pop, i, psz)
	local c = cfg()
	b:SetSize(psz, psz)
	b:ClearAllPoints()
	local off = POP_STEP + (i - 1) * (psz + POP_STEP)
	if c.pop == "up" then b:SetPoint("BOTTOM", pop, "BOTTOM", 0, off)
	elseif c.pop == "down" then b:SetPoint("TOP", pop, "TOP", 0, -off)
	elseif c.pop == "right" then b:SetPoint("LEFT", pop, "LEFT", off, 0)
	else b:SetPoint("RIGHT", pop, "RIGHT", -off, 0) end
end

-- The arrow tab's look: dark, gold-edged, with the arrow from Blizzard's own totem bar art (its
-- flyout button highlight), turned by TB.placeArrow to point the way the picker opens.
function TB.makeArrowLook(parent)
	local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	t:SetBackdrop(ns.BACKDROP)
	t:SetBackdropColor(0.06, 0.05, 0.03, 0.92)
	t:SetBackdropBorderColor(0.85, 0.71, 0.42, 0.9)
	t.glyph = t:CreateTexture(nil, "OVERLAY")
	t.glyph:SetTexture("Interface\\Buttons\\UI-TotemBar")
	t.glyph:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	t.glyph:SetBlendMode("ADD")
	t.glyph:SetPoint("CENTER")
	return t
end
-- The arrow tab along anchor's picker side, arrowSize deep, and its glyph sized and turned.
local GLYPH_TURN = { up = 0, down = math.pi, right = -math.pi / 2, left = math.pi / 2 }
function TB.placeArrow(tab, anchor, glyph)
	local c = cfg()
	local deep = c.arrowSize
	tab:ClearAllPoints()
	if c.pop == "up" then tab:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 1, 1); tab:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -1, 1); tab:SetHeight(deep)
	elseif c.pop == "down" then tab:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 1, -1); tab:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -1, -1); tab:SetHeight(deep)
	elseif c.pop == "right" then tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 1, -1); tab:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 1, 1); tab:SetWidth(deep)
	else tab:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -1, -1); tab:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -1, 1); tab:SetWidth(deep) end
	glyph:SetSize(math.max(deep * 1.1, 10), math.max(deep * 0.6, 6))
	glyph:SetRotation(GLYPH_TURN[c.pop])
end

-- A texture's colour, from grey (0) to full (1); all or nothing where partial desaturation is missing.
function TB.saturate(tex, sat)
	if not pcall(tex.SetDesaturation, tex, 1 - sat) then tex:SetDesaturated(sat < 0.5) end
end

-- The "not your pick" badge's size, for slots of this size.
function TB.badgeSize(size) return math.max(math.floor(size * cfg().badgeSize + 0.5), 8) end
-- The badge (bd, with its icon) beside anchor, a slot, opposite the picker: below a row whose
-- pickers open up, and so on. Its look: size, opacity, colour, and a plain 1 px line, whatever look
-- the slots use (a small pick badge stays a plain line, not the slots' bevel or caps).
function TB.layoutBadge(bd, anchor, size, border)
	local c = cfg()
	-- Only draw the setting's colour when the slots' own look actually uses it; other looks (Gold
	-- hairline, Bronze bevel) hide that setting, and the badge shouldn't keep a colour
	-- the player can no longer see or change.
	local usesColor = border and border.show and ns.Looks.uses(ns.Style.look("border", border.look), "color")
	local color = usesColor and border.color or { 0, 0, 0, 1 }
	-- Its line inside its size, as the slots' borders are.
	local inset = ns.Looks.fit(bd, border and border.show and { show = true, size = 1, color = color } or border,
		TB.badgeSize(size))
	bd:SetAlpha(c.badgeAlpha)
	TB.saturate(bd.icon, c.badgeSat)
	bd:ClearAllPoints()
	local gap = TB.BADGE_GAP + inset
	if c.pop == "up" then bd:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
	elseif c.pop == "down" then bd:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
	elseif c.pop == "right" then bd:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
	else bd:SetPoint("LEFT", anchor, "RIGHT", gap, 0) end
end

-- A button's look v over its button b (size wide), set in by its border's reach so that the
-- border, drawn round v, stays inside the button (ns.Looks.inset). Returns that inset.
function TB.fitLook(v, b, border, size)
	local o = ns.Looks.inset(v, border, size)
	v:ClearAllPoints()
	v:SetPoint("TOPLEFT", b, "TOPLEFT", o, -o)
	v:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -o, o)
	ns.applyBorder(v, border)
	return o
end

------------------------------------------------------------------------
-- Frames. Created when the file loads, which is allowed even during a /reload in combat.
------------------------------------------------------------------------
local bar = CreateFrame("Frame", "ShamanForeverTotemBar", UIParent)
bar:SetSize(1, 1)
bar:SetPoint("CENTER", 0, -120)
bar:SetFrameStrata("MEDIUM")
bar:Hide()

-- The pickers' header. Each popout is a protected frame it holds a reference to ("pop1".."pop4", by
-- the element's index in ELEMENTS); each button that opens or closes one carries that index
-- ("sf-pick") and, from its click, runs one of these snippets: open shows that popout and hides the
-- others (open 0 hides them all), close hides it.
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
-- Snippets run round each button's own click (SecureHandlerWrapScript). Returning false skips the
-- button's own action; a second return value runs the post-snippet with it, after the action.
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
-- Alt+left-click on a slot opens its picker instead of casting (when "sf-altpick" is on). Slots act
-- on the press (press-and-hold), so the press is skipped too; the picker opens on the release.
local SLOT_CLICK = [[
	if button == "LeftButton" and IsAltKeyDown() and self:GetAttribute("sf-altpick") then
		if not down then owner:RunAttribute("sf-open", self:GetAttribute("sf-pick")) end
		return false
	end
]]
local PICK_CLICK, PICK_AFTER = [[ return nil, self:GetAttribute("sf-pick") ]], [[ owner:RunAttribute("sf-close", message) ]]
-- Hover mode: the mouse entering a slot or its tab opens that picker (wrapped round OnEnter, below).
local HOVER_ENTER = [[
	if owner:GetAttribute("sf-hovermode") then owner:RunAttribute("sf-open", self:GetAttribute("sf-pick")) end
]]
-- Hover mode: the mouse leaving a slot, its tab, its strip or a picker button closes the picker
-- unless it is still over the slot or the strip (IsUnderMouse is the cursor against each frame's
-- rect). A leave runs only on a frame whose enter is wrapped too (Blizzard's SecureHandlers).
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


local slots = {}    -- element -> slot record
local bySlot = {}   -- Blizzard's totem slot -> slot record
TB.slots, TB.frame = slots, bar

-- Frame levels over a slot's button, bottom to top: the look (+2: icon), the expiring warning
-- (+3 to +4: Timer:setExpire, ShamanForever_Timers.lua), the timer's time-left bar (+8, kept under
-- the range strip so it never hides the range mark), the range strip (+9 to +12: ours, Blizzard's
-- aura button and our colour on it; ShamanForever_TotemRange.lua), then everything drawn over the
-- whole icon: the GCD sweep, the timer's Cooldown (swipe, countdown text), the key, the end
-- flashes. The strip's in-range part is opaque (the buff's icon under its colour), so what sits
-- under it is hidden.
TB.RANGE_LEVEL = 9
local OVER_RANGE = TB.RANGE_LEVEL + 4
local LOOK_LEVEL = 2   -- the look's level over the button (v:SetFrameLevel(b:GetFrameLevel() + LOOK_LEVEL))
local LOOK_OVER_RANGE = OVER_RANGE - LOOK_LEVEL   -- the same, over the look's level

-- Over a button's look (above its timer, and inside the look so it fades with it): the key bound to
-- it, in the top corner, and its highlight while Blizzard's Quick Keybind Mode is open.
local KEY_HIGHLIGHT = "UI-HUD-ActionBar-IconFrame-Mouseover"
local function keyLayer(v)
	local f = CreateFrame("Frame", nil, v)
	f:SetAllPoints()
	f:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE + 3)
	f.text = f:CreateFontString(nil, "OVERLAY")
	f.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	f.text:SetPoint("TOPRIGHT", -2, -2)
	f.text:SetTextColor(0.85, 0.85, 0.85)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetAllPoints()
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(KEY_HIGHLIGHT) then f.glow:SetAtlas(KEY_HIGHLIGHT)
	else f.glow:SetColorTexture(1, 0.82, 0, 0.3) end
	f.glow:Hide()
	return f
end

-- The global cooldown's sweep over the icon (the expiring warning and the range strip too), below
-- the button's timer, so the time left stays readable.
local function gcdSweep(v)
	local cd = ns.makeGCDSweep(v)
	cd:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE)
	return cd
end


for index, el in ipairs(ELEMENTS) do
	local slot = SLOT[el]
	local s = { el = el, slot = slot, index = index }
	slots[el], bySlot[slot] = s, s

	-- The click area: right-click dismisses, left-click casts the pick, Alt+click opens the
	-- element's picker (SLOT_CLICK; layout() turns it off outside Everything). Casts and dismissals
	-- happen on the press (press-and-hold).
	local b = CreateFrame("Button", "ShamanForeverTotem" .. NAME[el], bar, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("pressAndHoldAction", true)
	-- "*" matches any modifier (a plain "type2" is only used with none held).
	b:SetAttribute("*type2", "destroytotem")
	b:SetAttribute("totem-slot", slot)
	b:SetAttribute("sf-pick", index)
	wrapClick(b, SLOT_CLICK)
	s.button = b

	-- What the player sees, on a plain frame over the button.
	local v = CreateFrame("Frame", nil, bar)
	v:SetAllPoints(b)
	v:SetFrameLevel(b:GetFrameLevel() + LOOK_LEVEL)
	v:EnableMouse(false)
	s.vis = v
	v.school = el   -- the school its looks take (ns.Looks)
	-- "Not your pick": the element's pick, small, on the side away from the picker (a plain frame).
	local badge = CreateFrame("Frame", nil, bar)
	badge:SetFrameLevel(b:GetFrameLevel() + 6)
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.icon:SetAllPoints()
	ns.cropIcon(badge.icon)
	badge:Hide()
	s.badge = badge
	-- Killed early and ran out (ns.makeEndFlash): on their own frames, since the slot's look can be
	-- invisible (Active totems). Two frames: each has its own secret gate.
	local kf = ns.makeEndFlash(bar, b, "totembar", v)
	s.expired = ns.makeEndFlash(bar, b, "totembar", v)
	s.killed = kf
	kf:SetFrameLevel(b:GetFrameLevel() + OVER_RANGE + 4)
	s.expired:SetFrameLevel(b:GetFrameLevel() + OVER_RANGE + 4)
	-- Over the picture, inside the slot's border (TB.fitLook sets it in from the button).
	for _, flash in ipairs({ kf, s.expired }) do flash:ClearAllPoints(); flash:SetAllPoints(v) end
	v.bg = v:CreateTexture(nil, "BACKGROUND")
	v.bg:SetAllPoints()
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	ns.cropIconExact(v.icon)
	-- Time left: a timer (text, swipe, bar), above the warning layer so it stays readable.
	s.timer = ns.Timer.new(v, "totembar", "uptime", { anchor = v, school = el })
	s.timer.cd:SetFrameLevel(v:GetFrameLevel() + LOOK_OVER_RANGE + 1)
	s.timer.bar:SetFrameLevel(b:GetFrameLevel() + TB.RANGE_LEVEL - 1)
	v.cd = s.timer.cd
	s.keys = keyLayer(v)
	s.gcd = gcdSweep(v)
	s.command = "CLICK ShamanForeverKeyCast" .. NAME[el] .. ":LeftButton"   -- its key (Key bindings, below)
	-- The expiring warning is the timer's (Timer:setExpire, as on the HUD): a grey copy of the icon, a
	-- red ring, a dark pulsing layer and a glow, above the icon and below the cooldown, in the slot's
	-- last seconds. refreshSlot gives it the totem's own warning time and icon.

	-- Arrow tab (secure, no action of its own: ARROW_CLICK toggles the popout; right-click closes any)
	-- and its look (plain, shown while the mouse is over the slot or the tab).
	local ar = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
	-- Above every open picker's catch button (layoutArrow sets the level), so another slot's arrow
	-- opens its picker in one click and its own arrow closes it.
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

	-- Popout: protected, so the header's snippets can show and hide it in combat.
	local pop = CreateFrame("Frame", "ShamanForeverTotemPopout" .. NAME[el], bar, "SecureFrameTemplate")
	pop:Hide()
	pop:SetSize(1, 1)
	pop.bg = pop:CreateTexture(nil, "BACKGROUND")
	pop.bg:SetAllPoints()
	pop.bg:SetColorTexture(0, 0, 0, 0.72)
	pop:SetFrameStrata("HIGH")
	pop.buttons = {}
	s.popout = pop
	SecureHandlerSetFrameRef(picker, "pop" .. index, pop)
	-- While the popout is open, a click anywhere else (left or right; not the arrow tabs, which sit
	-- above it) lands on this invisible, screen-wide button under the pickers, and closes it.
	local catch = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
	catch:SetAllPoints(UIParent)
	catch:SetFrameLevel(pop:GetFrameLevel() + 1)
	catch:RegisterForClicks("AnyUp")
	catch:SetAttribute("sf-pick", index)
	wrapClick(catch, CATCH_CLICK)
	pop.catch = catch
	-- Hover mode's strip: from the slot's edge to the picker's far end, over the tab and the gaps, so
	-- the mouse can cross from the slot to the picker. It takes the mouse (below the tab and the
	-- picker's buttons), so leaving it through a gap closes the picker too. Shown only in hover mode.
	local strip = CreateFrame("Frame", nil, pop, "SecureFrameTemplate")
	strip:SetFrameLevel(pop:GetFrameLevel() + 1)
	strip:EnableMouse(true)
	strip:SetAttribute("sf-pick", index)
	strip:Hide()
	pop.strip = strip
	SecureHandlerSetFrameRef(picker, "strip" .. index, strip)
	SecureHandlerSetFrameRef(picker, "slot" .. index, b)
end

-- Close every picker (out of combat only). A picker hidden only through the bar would come back
-- open, with its screen-wide catch button, the next time the bar shows.
local function closePopouts()
	if InCombatLockdown() then return end
	for _, el in ipairs(ELEMENTS) do slots[el].popout:Hide() end
end

------------------------------------------------------------------------
-- Key bindings (Bindings.xml; Key Bindings > ShamanForever). Each is a CLICK binding to its own
-- invisible secure button, so keys work whatever the bar's settings, and even with the bar off:
-- cast an element's pick ("action" on its multi-cast slot), dismiss one slot ("destroytotem"),
-- Call of the Elements and Totemic Recall ("spell"), and dismiss all. A secure button does one
-- action per click, so "dismiss all" runs a macro that /clicks four dismiss helpers; /click sends a
-- release, so those act on release. That dismisses without a spell: no global cooldown, no mana back.
------------------------------------------------------------------------
local CALL, RECALL = ns.Spells.DEFS.call.ids[1], ns.Spells.DEFS.recall.ids[1]
_G.BINDING_HEADER_SHAMANFOREVER_TOTEMS = "Totems"
_G["BINDING_NAME_CLICK ShamanForeverKeyDismissAll:LeftButton"] = "Dismiss all totems"
-- In the client's language; again at login, as names can come late on a cold start.
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
local castKeys = {}   -- element -> its "cast your pick" key button
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

------------------------------------------------------------------------
-- Call of the Elements and Totemic Recall on the bar. Call shows once learned. Recall always shows,
-- greyed until learned: right-click runs the "dismiss all" macro above, left-click casts Recall
-- once it is learned. Where they sit is c.extras; layout() places them with the slots.
------------------------------------------------------------------------
local function knows(spell)
	local ok, v = pcall(C_SpellBook.IsSpellKnown, spell)
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

-- Each button's key, in its corner (any time: plain frames).
local function refreshKeys()
	local on = cfg().keys
	local function draw(layer, command)
		local key = on and GetBindingKey(command)
		layer.text:SetText(key and GetBindingText(key, 1) or "")
	end
	for _, el in ipairs(ELEMENTS) do draw(slots[el].keys, slots[el].command) end
	for _, e in pairs(extras) do draw(e.keys, e.command) end
end

-- The global cooldown on each button that casts, when the bar's Global cooldown style is on: the
-- slots (their pick, by the multi-cast action) and Call and Recall once learned. Only while the
-- button's own cooldown is the GCD (isOnGCD, readable in combat; Blizzard vouches for it inside
-- SPELL_UPDATE_COOLDOWN, where this runs), so a totem's own longer cooldown isn't shown. A duration
-- object, so fine in combat.
local function gcdOf(getInfo, getDuration, id)
	local ok, info = pcall(getInfo, id)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) or info.isOnGCD ~= true then return nil end
	local dok, d = ns.try("totem bar: GCD", getDuration, id)
	return dok and d or nil
end
local function refreshGCD()
	-- Not gated on the bar being shown: the cast that brings it up (in combat, a first totem) sweeps too.
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

local keyTexts = {}   -- button -> its key label, for layout()
for _, el in ipairs(ELEMENTS) do keyTexts[slots[el].button] = slots[el].keys.text end
for _, e in pairs(extras) do keyTexts[e.button] = e.keys.text end

-- Which extras show, and where: the keys before the slots and the keys after them.
local function extraSides()
	local c = cfg()
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

-- Hover: the arrow tab's look shows while the mouse is over the slot, the tab or the open popout.
-- arrows: feat("arrows"), when the caller already has it.
local function hover(s, arrows)
	if arrows == nil then arrows = feat("arrows") end
	local over = s.button:IsMouseOver() or s.arrow:IsMouseOver() or (s.popout:IsShown() and s.popout:IsMouseOver())
	s.arrowVis:SetAlpha((over or s.popout:IsShown()) and arrows and 1 or 0)
end

------------------------------------------------------------------------
-- Refreshing the slots (any time, combat included)
------------------------------------------------------------------------
-- The element's pick, by spell ID (nil for "No totem").
local function pickSpell(slot)
	local ok, kind, id = ns.try("totem bar: pick", GetActionInfo, multiAction(slot))
	if not ok or isSecret(kind) or isSecret(id) or kind ~= "spell" or type(id) ~= "number" then return nil end
	return id
end

-- A totem's own warning time (warnOver), else the bar's. warnOver is keyed by the client's rank-less
-- spell name; for the spells the addon tracks, the English name counts too (older profiles, and
-- defaults filled before the client's names had loaded).
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
local kbOpen = false   -- Blizzard's Quick Keybind Mode is open (Quick Keybind Mode, below)
local preview          -- what preview mode draws on the slots while it shows (Preview mode, below)

-- The parts that follow the remaining time: the time bar once it has run out, and the range strip.
-- (The expiring warning follows it in Timers' own ticker.)
-- Values from the duration object may be secret, so they only ever go straight to SetAlpha.
function TB.drawTimeLeft(s)
	local d = s.dur
	if not d then return end
	local tbar = s.timer.bar
	if ns.CURVE_LIVE and tbar:IsShown() then
		local ok, a = ns.try("totem bar: time bar", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		if ok then tbar:SetAlpha(a) end
	end
	if TB.range then TB.range.drawTimeLeft(s) end
end

local function refreshSlot(s)
	local c, v = cfg(), s.vis
	local was = s.dur   -- a slot that had a totem and now has none ended it (Killed early, below)
	local ok, d = ns.try("totem bar: duration", GetTotemDuration, s.slot)
	if ok and d then
		-- A totem is down.
		local iok, _, _, _, _, icon = ns.try("totem bar: totem info", GetTotemInfo, s.slot)
		if iok and (isSecret(icon) or icon) then
			ns.try("totem bar: icon", v.icon.SetTexture, v.icon, icon)
			s.killed:setIcon(icon)
			s.expired:setIcon(icon)
		end
		s.killed.mark:Hide()   -- recast: the cross goes
		v:SetAlpha(1)
		v.icon:SetDesaturated(false)
		v.icon:SetAlpha(1)
		v.bg:SetColorTexture(0, 0, 0, 1)
		s.timer:set(d)
		-- Not the element's pick? Only when both are known: the totem down (ns.Totems.downSpell)
		-- and a pick (not "No totem"); any rank of the pick counts as the pick.
		local down = ns.Totems.downSpell(s.slot)
		local pick = down and c.offPick and c.mode == "everything" and pickSpell(s.slot)
		if pick and not ns.Spells.same(down, pick) then
			ns.try("totem bar: badge", s.badge.icon.SetTexture, s.badge.icon, C_ActionBar.GetActionTexture(multiAction(s.slot)))
			s.badge:Show()
		else s.badge:Hide() end
		s.dur = d
		s.timer:setExpire({ secs = warnSecs(c, down), grey = c.warnGrey, ring = c.warnRing, pulse = c.warnPulse, glow = c.warnGlow })
		if iok and (isSecret(icon) or icon) then s.timer:setExpireIcon(icon) end
		TB.drawTimeLeft(s)
		return true
	end
	s.dur = nil
	if was then ns.Totems.slotEmptied(s.slot, was) end
	s.badge:Hide()
	-- Not down: the element's pick (greyed or in colour, at its opacity), or its colour, or nothing.
	-- With nothing picked, "pick" falls back to the element colour.
	s.timer:clear()
	-- Active totems: only totems that are down show (the slot keeps its place; secure buttons can't
	-- move in combat). A plain frame's alpha, so this works in combat too. In Quick Keybind Mode they
	-- show, to be bound.
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
	if preview then return end   -- it draws the slots itself; the next layout after it reads them
	local down = false
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		s.down = refreshSlot(s)
		if s.down then down = true end
		if TB.range then TB.range.refresh(s) end
	end
	anyDown = down
end

-- Refresh (any time), and when the first totem goes down or the last one goes, the bar's driver
-- for "In combat or a totem down" (out of combat only).
local layout   -- Layout, below
local function refresh()
	local wasDown = anyDown
	refreshSlots()
	if anyDown ~= wasDown and cfg().show == "active" then layout() end
end

-- Ten times a second: the time bar's run-out alpha, the range strip, and the arrow tabs' hover.
local ticker = CreateFrame("Frame")
ticker.t = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	if not bar:IsShown() then return end
	local arrows = feat("arrows")
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		hover(s, arrows)
		if s.down and not preview then TB.drawTimeLeft(s) end
	end
end)

------------------------------------------------------------------------
-- Blizzard's totem frames
------------------------------------------------------------------------
-- The totems under the player frame: made invisible and click-through rather than hidden, so
-- nothing moves in Blizzard's player-frame layout (hiding it from here would re-lay that out,
-- PetFrame included, from addon code). Left alone when another addon has taken it over.
-- Blizzard's managed-frame layout moves it between PlayerFrame and its layout containers (one has
-- no name), so "still Blizzard's" means anywhere under PlayerFrame or that container system; and
-- the same layout sets its alpha back to 1 when it shows its frames, so a hidden TotemFrame hides
-- again whenever its alpha is set.
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
		-- Another addon taking it over (and setting its alpha) gets it back visible (applyTotemFrame).
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
		-- Another addon took it over after we had hidden it (EllesmereUI's totem bar switched on
		-- mid-session): give it back visible. TotemFrame isn't protected, so this is fine in combat.
		if totemFrameHidden then setTotemFrameHidden(false) end
		return
	end
	local hide = barOn()
	if not hide and not totemFrameHidden then return end
	setTotemFrameHidden(hide)
end
if TotemFrame and TotemFrame.Update then hooksecurefunc(TotemFrame, "Update", applyTotemFrame) end

-- The Totem Action Bar: moved under a hidden frame out of combat, and back when wanted.
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

------------------------------------------------------------------------
-- Layout (out of combat only)
------------------------------------------------------------------------
local mover
local saidWait = false   -- "changes wait until combat ends" said this combat
local classDone = false  -- not a shaman: laid out hidden once, nothing more to do
local hasTotems = false  -- a totem of any element is known (layout): until then the bar hides
local paintPreview   -- Preview mode, below

-- known: the element's known totems (ns.Totems.knownTotems), from layout().
local function layoutPopout(s, size, known)
	local pop = s.popout
	local slot = s.slot
	local ids = { 0 }   -- "No totem" first, nearest the slot (as Blizzard's)
	for _, id in ipairs(known) do table.insert(ids, id) end
	local psz = TB.popButtonSize(size)
	local action = multiAction(slot)
	for i, id in ipairs(ids) do
		local p = pop.buttons[i]
		if not p then
			p = CreateFrame("Button", nil, pop, "SecureActionButtonTemplate")
			-- On the release, whatever the "cast on key down" setting: it is the only click registered.
			p:RegisterForClicks("AnyUp")
			p:SetAttribute("useOnKeyDown", false)
			p:SetAttribute("*type1", "multispell")   -- right-click has no action: it only closes
			p:SetAttribute("sf-pick", s.index)
			wrapClick(p, PICK_CLICK, PICK_AFTER)   -- then the popout closes
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
	-- Hover mode's strip: as wide as the slot or the picker, whichever is wider.
	local strip, dir, b = pop.strip, cfg().pop, s.button
	local across = math.max(size, psz + 2 * POP_STEP)
	strip:ClearAllPoints()
	if dir == "up" then strip:SetPoint("BOTTOM", b, "TOP"); strip:SetPoint("TOP", pop, "TOP"); strip:SetWidth(across)
	elseif dir == "down" then strip:SetPoint("TOP", b, "BOTTOM"); strip:SetPoint("BOTTOM", pop, "BOTTOM"); strip:SetWidth(across)
	elseif dir == "right" then strip:SetPoint("LEFT", b, "RIGHT"); strip:SetPoint("RIGHT", pop, "RIGHT"); strip:SetHeight(across)
	else strip:SetPoint("RIGHT", b, "LEFT"); strip:SetPoint("LEFT", pop, "LEFT"); strip:SetHeight(across) end
end

local function layoutArrow(s)
	local ar = s.arrow
	TB.placeArrow(ar, s.button, s.arrowVis.glyph)
	ar:SetShown(feat("arrows"))
	-- Above every open picker's catch button (same strata), below the picker's own buttons.
	ar:SetFrameLevel(s.popout.catch:GetFrameLevel() + 2)
	s.arrowVis:SetShown(feat("arrows"))
end

-- The bar's own driver, and the one it has now: a plain "show" while it stays after combat
-- (ns.AfterCombat, made with the layout below).
local function ownDriver()
	local c = cfg()
	-- While preview mode draws the slots, the bar shows as in combat.
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
	if driver ~= lastDriver then
		lastDriver = driver
		RegisterStateDriver(bar, "visibility", driver)
	end
end

function layout()
	if ns.deferInCombat("totem bar layout", layout) then return end
	if classDone then return end
	-- Any open picker closes first: a layout can hide the bar or a slot under it (it would come back
	-- open later).
	closePopouts()
	local c = cfg()
	local size, border = look()
	-- Scale and opacity first: borders below are lines, sized for the bar's scale, and sizes, gaps
	-- and the position are whole screen pixels at it (ns.placeOnPixels says why). Out of combat
	-- only, like everything on a frame holding secure buttons.
	bar:SetScale(c.scale)
	bar:SetAlpha(c.alpha)
	local px = ns.pixel(bar)
	size = ns.roundPx(size, px)
	-- A slot shows for an element with a totem known (every element's where the client can't list
	-- them). With no totem known at all (a new character's first levels) the bar has nothing to show
	-- and hides, Call and Recall with it, in positioning mode too: like a group whose elements aren't
	-- learned, it can be placed once there is something in it.
	local shown, known = {}, {}
	local had = hasTotems
	hasTotems = not GetMultiCastTotemSpells
	for _, el in ipairs(ELEMENTS) do
		known[el] = ns.Totems.knownTotems(SLOT[el])
		if #known[el] > 0 then hasTotems = true end
	end
	if hasTotems ~= had then ns.Options.refresh() end   -- its page says "Not learned" until then
	for _, el in ipairs(c.order) do
		local s = slots[el]
		local on = barOn() and not c.hidden[el] and (#known[el] > 0 or not GetMultiCastTotemSpells or (preview and preview.all))
		s.button:SetShown(on)
		s.vis:SetShown(on)
		if not on then s.killed.mark:Hide() end   -- a slot taken off the bar takes its cross along
		if on then table.insert(shown, s) else s.arrow:Hide(); s.arrowVis:Hide() end
	end
	local row = c.dir == "row"
	if row and c.pop ~= "up" and c.pop ~= "down" then c.pop = "up" end
	if not row and c.pop ~= "right" and c.pop ~= "left" then c.pop = "right" end
	-- Everything along the bar, in order: extras before, slots, extras after (TB.along), each
	-- centred on the bar's line to the nearest whole pixel, whatever its size. Nothing while no
	-- totem is known.
	local seq, long, across = {}, size, size
	if hasTotems or (preview and preview.all) then seq, long, across = TB.along(#shown, size, px) end
	local on = {}   -- the extras that show -> their size
	for _, it in ipairs(seq) do
		local b, sz = it.extra and extras[it.key].button or shown[it.key].button, it.size
		if it.extra then on[it.key] = sz end
		b:SetSize(sz, sz)
		-- Its key label scales with the icon.
		if keyTexts[b] then keyTexts[b]:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(sz * 0.3 + 0.5)), "OUTLINE") end
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
			TB.fitLook(e.vis, e.button, border, on[key])
		end
	end
	-- Hover mode (not while binding keys): the picker closes as the mouse leaves its slot and strip,
	-- so there is no catch button. Every slot, shown or not, so none keeps the other mode's parts.
	local hoverMode = feat("pickHover") and not kbOpen
	picker:SetAttribute("sf-hovermode", hoverMode)
	for _, el in ipairs(ELEMENTS) do
		slots[el].popout.catch:SetShown(not hoverMode)
		slots[el].popout.strip:SetShown(hoverMode)
	end
	for _, s in ipairs(shown) do
		local b = s.button
		b:SetAttribute("*type1", feat("cast") and "action" or nil)
		-- Alt+click picks only in Everything (in Active totems an empty slot is invisible); off, it
		-- casts like a plain click.
		b:SetAttribute("sf-altpick", barOn() and cfg().mode == "everything")
		b:SetAttribute("action", multiAction(s.slot))
		castKeys[s.el]:SetAttribute("action", multiAction(s.slot))
		s.inset = TB.fitLook(s.vis, b, border, size)   -- the range strip sits in by it too
		s.killed.fitSize, s.expired.fitSize = size - 2 * s.inset, size - 2 * s.inset   -- over the picture
		s.timer:apply()
		if TB.pulse then TB.pulse.place(s) end   -- the pulse timer loads after this file
		layoutArrow(s)
		TB.layoutBadge(s.badge, s.button, size, border)
		layoutPopout(s, size, known[s.el])
	end
	if row then bar:SetSize(long, across) else bar:SetSize(across, long) end
	ns.placeOnPixels(bar, c.point, c.x / c.scale, c.y / c.scale)
	if TB.range then TB.range.layout(size) end   -- after the scale: its height is a line's
	refreshSlots()
	refreshKeys()
	refreshGCD()
	ns.refitRings()
	drive()
	applyTotemFrame()
	applyActionBar()
	if mover then mover.update() end
	if preview then paintPreview() end
	-- Not a shaman: the bar is laid out hidden; nothing else will change that.
	if playerClass and not isShaman() then classDone = true end
end
TB.layout = layout

-- Stay after combat, then fade out (ns.AfterCombat).
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

-- The slots' timers take their current style (General's or the bar's own). Plain frames, so any time.
function TB.applyTimers()
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		s.timer:apply()
		if TB.pulse then TB.pulse.place(s) end   -- the pulse bar sits above the time bar
	end
end

-- Settings changed (options page): relayout now, or when combat ends.
function TB.applySettings()
	cfgTable = nil
	-- Crosses go at once when switched off (plain frames: fine in combat, unlike the layout).
	local c = cfg()
	if not (c.killed and c.killedMark) then
		for _, el in ipairs(ELEMENTS) do slots[el].killed.mark:Hide() end
	end
	if InCombatLockdown() then
		-- Once per combat: sliders call this on every step.
		if not saidWait then
			saidWait = true
			ns.say("totem bar changes wait until combat ends")
		end
	end
	layout()
end

------------------------------------------------------------------------
-- Positioning: a handle over the bar while positioning is unlocked
------------------------------------------------------------------------
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
	if button == "RightButton" and ns.Options.open then ns.Options.open("totembar") end
end)
-- As for groups: mouse wheel, scale (everything grows, lines too); Shift + wheel, icon size (lines
-- stay crisp); Ctrl + wheel, opacity.
mover:SetScript("OnMouseWheel", function(self, delta)
	if InCombatLockdown() then return end
	local c = cfg()
	local function step(key) c[key] = clamp(math.floor((c[key] + delta * 0.05) * 100 + 0.5) / 100, RANGES[key]) end
	if IsControlKeyDown() then step("alpha")
	elseif IsShiftKeyDown() then
		local from = look()   -- the size it has now, General's or its own
		c.sizeFollow = false
		c.size = clamp(from + delta * 2, RANGES.size)
	else step("scale")
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
	end
	if on then mover.label:SetText("Totem bar") end
	mover:SetShown(on)
end

-- Combat started while unlocked: the handle goes at once (it is a plain frame).
function TB.lockInCombat()
	mover:Hide()
	ns.retryAfterCombat("totem bar layout", layout)
end

------------------------------------------------------------------------
-- Quick Keybind Mode (Blizzard's, from Options > Keybindings; EllesmereUI's /kb opens it). While it is
-- open, the bar shows, empty slots included, and hovering a button and pressing a key binds that key
-- to the button's own binding (the slots: cast the pick; Call; Recall).
-- The keys are caught on our own plain frame parked over the hovered button, and bound with
-- SetBinding, not through Blizzard's QuickKeybindButtonTemplateMixin: calling that from addon code
-- taints Blizzard's key handling (EllesmereUI saw keys it passes on, such as the screenshot key,
-- blocked afterwards). As Blizzard's: the key replaces the first key and keeps the second, Escape clears the
-- first, and OK saves (SaveBindings) or Cancel undoes (LoadBindings) our changes along with its own.
-- Controller buttons bind the same way.
------------------------------------------------------------------------
local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetFrameStrata("FULLSCREEN_DIALOG")
catcher:EnableMouse(true)   -- also stops clicks casting while binding
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

-- Hovering a bar button: true when Quick Keybind Mode took the hover (no normal tooltip then).
local function kbEnter(button, command, layer)
	if not kbOpen or InCombatLockdown() then return false end
	if not catcher.pad then
		-- Out of combat, the first time: controller buttons as well as keys.
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
		-- The screenshot key stays the screenshot key; lone modifiers wait for the key they go with.
		if GetBindingFromClick and GetBindingFromClick(input) == "SCREENSHOT" then return end
		local key = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
		if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(key) then return end
		key = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
		local was = GetBindingAction(key)   -- what the key did before, if anything: now unbound
		if key1 then SetBinding(key1, nil, ctx) end
		if key2 then SetBinding(key2, nil, ctx) end
		if SetBinding(key, command, ctx) then
			if key2 and key2 ~= key then SetBinding(key2, command, ctx) end
			-- Warn only when the key's old action is left with no key at all.
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
	-- The screenshot key takes a screenshot, as in Blizzard's own mode: passing the key on wouldn't,
	-- since Blizzard's keybind frame underneath takes every key.
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
	refreshSlots()  -- the empty slots' look, at once (also in combat, where the layout waits)
	layout()   -- shows the bar and its empty slots, or puts them back (after combat, if in it)
end

-- QuickKeybindFrame can load after PLAYER_LOGIN: hooked once it exists.
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
for _, e in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "PLAYER_REGEN_DISABLED" }) do ns.registerEvent(kbEvents, e) end
kbEvents:SetScript("OnEvent", function(self, event, name)
	if event == "PLAYER_REGEN_DISABLED" then
		kbLeave()   -- never left over the bar in combat, taking the keyboard
	elseif event == "PLAYER_LOGIN" or name == "Blizzard_QuickKeybind" then
		hookQuickKeybind()
		if kbHooked then self:UnregisterEvent("PLAYER_LOGIN"); self:UnregisterEvent("ADDON_LOADED") end
	end
end)

------------------------------------------------------------------------
-- Tooltips and hover on the slot buttons
------------------------------------------------------------------------
for _, el in ipairs(ELEMENTS) do
	local s = slots[el]
	s.button:SetScript("OnEnter", function(self)
		hover(s)
		if kbEnter(self, s.command, s.keys) then return end
		local c = cfg()
		if c.tips == "never" or (c.tips == "ooc" and InCombatLockdown()) then return end
		local ok, d = pcall(GetTotemDuration, s.slot)
		if not (ok and d) and c.mode ~= "everything" then return end   -- Active totems: an empty slot is invisible
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if ok and d then
			pcall(GameTooltip.SetTotem, GameTooltip, s.slot)
		else
			local action = multiAction(s.slot)
			if C_ActionBar.HasAction(action) then pcall(GameTooltip.SetAction, GameTooltip, action)
			else GameTooltip:SetText(NAME[el] .. ": no totem picked") end
		end
		GameTooltip:Show()
	end)
	s.button:SetScript("OnLeave", function() GameTooltip:Hide(); hover(s) end)
	s.arrow:SetScript("OnEnter", function() hover(s) end)
	s.arrow:SetScript("OnLeave", function() hover(s) end)
end
-- Hover mode: wrapped after the scripts above are set (setting a script later would drop the wrap).
for _, el in ipairs(ELEMENTS) do
	wrapHover(slots[el].button, HOVER_ENTER)
	wrapHover(slots[el].arrow, HOVER_ENTER)
	wrapHover(slots[el].popout.strip)
end
-- Hover mode: a picker the bar took along when it hid (Alt+Z hides the whole UI, in combat too) has
-- lost the hover driver, which drops hidden frames. It closes when the bar shows again, seen by an
-- explicitly protected child that stays shown (a wrapped script runs only on such a frame, and the
-- bar is a plain frame).
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
		if not pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell) then GameTooltip:SetText(C_Spell.GetSpellName(e.spell) or e.key) end
		if e.key == "Recall" then
			if not knows(e.spell) then GameTooltip:AddLine("Not learned yet", 0.6, 0.6, 0.6) end
			GameTooltip:AddLine("Right-click: dismiss all totems (no GCD, but no mana returned)", 1, 0.82, 0, true)
		end
		GameTooltip:Show()
	end)
	e.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Killed early. When a slot empties, its last duration object still says how much time the totem
-- had left (tested 2026-09-25); ns.makeEndFlash turns that into the flash's alpha through a curve,
-- so for a totem that simply ran out the flash stays invisible (its run-out pop plays instead).
-- Our own dismissals and a slot that fills again at once (a new totem cast over it) don't flash:
-- ns.Totems only calls a totem gone without either. The cross (killedMark) sits under the same gate
-- and goes on a recast or after 5 s.
------------------------------------------------------------------------
-- Subscribed after the totem elements (ShamanForever_Cooldowns.lua loads first): they hear first.
ns.Totems.subscribe(function(event, slot, was)
	if event ~= "gone" or preview then return end
	local s = bySlot[slot]
	local c = cfg()
	if not s.button:IsShown() then return end
	if s.button:IsVisible() then ns.Sounds.play(c.goneSound, "totembar", nil, true) end
	if c.expiredPop then s.expired:play(was, { expired = true, pop = true }) end
	if c.killed then s.killed:play(was, { pop = c.killedPop, glow = c.killedGlow, mark = c.killedMark }) end
end)

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_ENABLED",
		"SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MULTI_CAST_ACTIONBAR", "UPDATE_BINDINGS", "SPELL_UPDATE_COOLDOWN" }) do
	ns.registerEvent(ev, e)
end
ns.registerEvent(ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
-- After one of our casts: refresh once ShamanForever_Totems.lua has recorded which totem went into
-- which slot (ns.Totems; its handler may run after ours), so the order of this event and
-- PLAYER_TOTEM_UPDATE doesn't matter. Plain frames only, so fine in combat.
local casts, refreshQueued = {}, false   -- spell IDs cast since the last check
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

ev:SetScript("OnEvent", function(_, event, arg1, ...)
	if not ns.getDB() then return end
	if not isShaman() and playerClass then
		-- Only shamans get the bar: lay it out hidden once, then stop listening.
		layout()
		if classDone then
			ev:UnregisterAllEvents()
			ticker:SetScript("OnUpdate", nil)
		end
		return
	end
	if event == "PLAYER_TOTEM_UPDATE" then
		refresh()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, spell = ...   -- unit, castGUID, spellID
		if isSecret(spell) or type(spell) ~= "number" then return end
		refreshAfterCast(spell)
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		-- The element's multi-cast slots, or 0 (every slot).
		local base = multiAction(1) - 1
		if not isSecret(arg1) and type(arg1) == "number" and (arg1 == 0 or (arg1 > base and arg1 <= base + 12)) then refresh() end
	elseif event == "UPDATE_BINDINGS" then
		refreshKeys()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		refreshGCD()
	elseif event == "PLAYER_REGEN_ENABLED" then
		saidWait = false
		-- A queued layout has run already (ns.deferInCombat). A picker opened in combat and left open
		-- closes now.
		closePopouts()
		if mover then mover.update() end
	else
		if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then nameBindings() end
		layout()
	end
end)

-- The Totems cards. Choosing Everything turns every button back on; Active totems and
-- Blizzard's leave them as they are (they don't apply there).
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
-- For the options preview: an element's pick as a texture, its known totems, and the look.
function TB.pickTexture(el) return C_ActionBar.GetActionTexture(multiAction(SLOT[el])) end
function TB.known(el)
	-- The real picker's list when it is built (it matches the bar exactly), else Blizzard's.
	local ids = {}
	for _, p in ipairs(slots[el].popout.buttons) do
		if p:IsShown() and p.spellID and p.spellID ~= 0 then table.insert(ids, p.spellID) end
	end
	if #ids > 0 then return ids end
	return ns.Totems.knownTotems(SLOT[el])
end
TB.look = look
-- Whether a totem is known, as of the last layout (the options mark the bar "Not learned" until then).
function TB.hasTotems() return hasTotems end

------------------------------------------------------------------------
-- Preview mode (ShamanForever_Preview.lua): the slots drawn in the states it asks for, on their
-- own looks, while the bar's reads, time bars and end flashes wait. The bar shows as in combat; with
-- Show not learned every element's slot shows, even while none of its totems is known. Only plain
-- frames are drawn on; showing slots and the bar happens in layout(), out of combat. When it ends,
-- the next layout reads the slots again.
------------------------------------------------------------------------
-- The states a slot can be drawn in, in the order the preview's Busy mode plays them.
TB.PREVIEW_STATES = { "down", "expiring", "killed", "ranout", "empty" }

-- A slot in a preview state (down | expiring | killed | ranout | empty) since rec.at, its timer
-- running; rec.range: its range strip shows. Returns when its timer runs out.
local function paintSlot(s, rec)
	local c, v, st = cfg(), s.vis, rec.st
	local shown = s.button:IsShown()   -- the strip is a frame of its own
	local pick = GetActionTexture and GetActionTexture(multiAction(s.slot))
	if isSecret(pick) then pick = nil end   -- plain out of combat, where the preview runs
	local icon = pick or ns.Look.TOTEM_ICON[s.el]
	s.badge:Hide()
	s.killed:setIcon(icon)
	s.expired:setIcon(icon)
	-- The real strip: our red here, Blizzard's green in the range layout (ShamanForever_TotemRange.lua).
	if s.rangeGate then s.rangeGate:SetAlpha(0) end
	local size = s.button:GetWidth()   -- the slot's own: layout rounds it to whole pixels
	local strip = s.previewRange
	if rec.range and c.range and shown then
		if not strip then
			strip = CreateFrame("Frame", nil, bar)
			strip.bg = strip:CreateTexture(nil, "ARTWORK")
			strip.bg:SetAllPoints()
			s.previewRange = strip
		end
		-- Over Blizzard's part and its colour (+10 to +12, ShamanForever_TotemRange.lua).
		strip:SetFrameLevel(s.button:GetFrameLevel() + 14)
		strip:ClearAllPoints()
		strip:SetPoint("TOPLEFT", s.button, "TOPLEFT", 0, 0)
		strip:SetSize(size, ns.linePx(strip, c.rangeHeight))
		local k = c.rangeOut
		strip.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
		strip:Show()
	elseif strip then strip:Hide() end
	v.icon:SetTexture(icon)
	if st == "down" or st == "expiring" then
		s.killed.mark:Hide()   -- recast
		v:SetAlpha(1)
		v.icon:SetDesaturated(false)
		v.icon:SetAlpha(1)
		v.bg:SetColorTexture(0, 0, 0, 1)
		local left, life = ns.Look.PREVIEW_LEFT[s.el][1], ns.Look.PREVIEW_LEFT[s.el][2]
		if st == "expiring" then left = 5 end
		s.timer:setExpire({ secs = c.warn, grey = c.warnGrey, ring = c.warnRing, pulse = c.warnPulse, glow = c.warnGlow }, icon)
		s.timer:setTime(rec.at - (life - left), life)
		return rec.at + left
	end
	-- Not down (killed early and ran out leave the slot empty): as refreshSlot draws it.
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

-- After every layout while it shows: every slot's state again.
function paintPreview()
	for _, el in ipairs(ELEMENTS) do
		local rec = preview.states[el]
		if rec then paintSlot(slots[el], rec) end
	end
end

-- p: { all = every element's slot }, or nil when it ends. The caller lays the HUD out next
-- (ns.applyLayout or ns.layoutElements), which lays out the bar.
function TB.preview(p)
	if p then
		preview = { all = p.all, states = preview and preview.states or {} }
		if TB.range then TB.range.preview(true) end
	elseif preview then
		preview = nil
		if TB.range then TB.range.preview(false) end
		for _, el in ipairs(ELEMENTS) do
			local s = slots[el]
			s.killed:stop()
			s.expired:stop()
			if s.previewRange then s.previewRange:Hide() end
			-- A totem that went meanwhile isn't news: no end flash for it when the slot is read, and
			-- ns.Totems forgets it quietly.
			if s.dur then
				local ok, d = ns.try("totem bar: duration", GetTotemDuration, s.slot)
				if ok and d == nil then ns.Totems.forget(s.slot) end
			end
			s.dur = nil
		end
		lastDriver = nil
	end
end

-- A slot's state from `at` (GetTime): see paintSlot; moment: its end flash plays too. Returns when
-- its timer runs out, if it has one.
function TB.previewSlot(el, st, at, range, moment)
	if not preview then return end
	local rec = { st = st, at = at, range = range }
	preview.states[el] = rec
	local s, c = slots[el], cfg()
	-- The other state's flash and cross go: a slot that ran out wasn't killed early.
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

-- For /sf debug.
function TB.debug()
	local c = cfg()
	local mc = MultiCastActionBarFrame
	-- The GCD sweep's test: is the first slot's isOnGCD readable (in combat too)?
	local gok, ginfo = pcall(C_ActionBar.GetActionCooldown, multiAction(SLOT.earth))
	local g = not gok and "error" or type(ginfo) ~= "table" and "none"
		or isSecret(ginfo.isOnGCD) and "secret" or tostring(ginfo.isOnGCD)
	return string.format("totem bar mode %s, show %s, driver %s, shown %s, totems known %s, earth isOnGCD %s; TotemFrame parent %s alpha %s; Totem Action Bar parent %s",
		c.mode, c.show, tostring(lastDriver), tostring(bar:IsShown()), tostring(hasTotems), g,
		TotemFrame and TotemFrame:GetParent() and (TotemFrame:GetParent():GetName() or "?") or "none",
		TotemFrame and string.format("%.2f", TotemFrame:GetAlpha()) or "-",
		mc and (mc:GetParent() == hiddenParent and "hidden" or (mc:GetParent() and mc:GetParent():GetName() or "?")) or "none")
end

-- Untested features on the totem bar, for About's Experimental list: { name, where }.
TB.EXPERIMENTAL = {}
