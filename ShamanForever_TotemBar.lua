-- Totem bar: one bar that can replace both of Blizzard's totem frames, the totems under the player
-- frame (timers, right-click dismiss) and the Totem Action Bar (a pick per element, arrow popouts).
-- Design: workspace design/totem-bar.md; what was tested in game: design/totem-research.md.
--
-- Every click is a secure button set up out of combat, so it works in combat too:
-- * slot button: right-click "destroytotem" (totem-slot), left-click "action" on the element's
--   multi-cast action slot, so it casts whatever the element's pick is, and follows it.
-- * pickers: a secure header's snippets open and close the popouts (secure snippets work on Forever
--   since build 70009). The arrow tab toggles its popout, Alt+click on a slot opens it, and a click
--   outside it (the catch button) closes it.
-- * popout: "multispell" buttons (spell 0 is "No totem") that change the pick, then close it.
-- Layout, attributes and anything that shows, hides or moves a secure button change only out of
-- combat; changes asked for in combat wait for it to end. Every layout, and the end of combat,
-- closes any open picker. Drawing sits on plain frames over the secure buttons, so it can change
-- any time.
-- In combat, which totem is in a slot is secret: its icon is drawn by handing the secret icon to
-- SetTexture, timers come from the slot's duration object, and warnings are the remaining time
-- through a curve into SetAlpha. Which totem it is (per-totem warning times, "not your pick") comes
-- from our own casts (ns.totemSpellInSlot), by spell ID.

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
	mode = "everything",      -- the Totems cards: blizzard (our bar off) | active (totems and timers) | everything
	point = "CENTER", x = 0, y = -100,   -- x, y in UIParent units, so scaling keeps the centre
	scale = 1,
	alpha = 1,
	show = "always",          -- always | active (in combat or a totem down) | combat
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
	warn = 10,                -- seconds before the end (0 = off)
	-- Totem -> seconds, instead of warn (short-lived ones). Keyed by the client's rank-less spell
	-- name; the defaults (Earthbind and Stoneclaw, 5 s) are filled by cfg(), in the client's language.
	warnOver = {},
	killed = true,            -- flash when a totem dies with time left, made of:
	killedPop = true,         --   the slot bursts bigger for a moment
	killedGlow = true,        --   a red glow around the slot
	killedMark = true,        --   a red cross over the slot until it is recast, up to 5 s
	range = true,             -- a strip along the top: are you in range of your own totem's buff (ShamanForever_TotemRange.lua)
	rangeHeight = 4,          --   its height in physical pixels
	rangeIn = { 0.2, 0.8, 0.25, 0 },       --   with the buff (0: nothing shows in range)
	rangeOut = { 0.9, 0.12, 0.08, 0.85 },  --   without it
}

local isSecret = ns.isSecret

-- Number settings: the options sliders' ranges. Anything outside (a damaged or hand-made import)
-- is clamped, so layout() never gets a scale of 0 or a NaN.
local RANGES = {
	scale = { 0.5, 3 }, alpha = { 0.1, 1 }, spacing = { 0, 20 }, size = { 24, 96 },
	arrowSize = { 8, 32 }, extrasScale = { 0.5, 1.5 }, idleAlpha = { 0.1, 1 },
	badgeSize = { 0.25, 0.8 }, badgeAlpha = { 0.1, 1 }, badgeSat = { 0, 1 }, warn = { 0, 30 }, rangeHeight = { 1, 12 },
}
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
	TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function clamp(v, r) return math.min(math.max(v, r[1]), r[2]) end

-- The profile's bar settings, with defaults filled and wrong types or values reset (imported profiles).
local cfgTable
local function cfg()
	local db = ns.getDB()
	if type(db.totemBar) ~= "table" then db.totemBar = {} end
	local t = db.totemBar
	if t ~= cfgTable then
		-- Before the Totems cards (2026-09-25): "enabled" and Show "never" meant our bar off.
		if t.mode == nil and (t.enabled == false or t.show == "never") then t.mode = "blizzard" end
		-- Before styles (0.6.1 and earlier) one switch covered size and border: keep an own look as own.
		if t.follow == false then
			t.sizeFollow = false
			if type(t.border) == "table" then t.border.follow = false end
		elseif t.follow == true then t.size, t.border = nil, nil end
		t.enabled, t.hideTotemFrame, t.hideActionBar, t.killedPulse, t.follow = nil, nil, nil, nil, nil
		if t.mode ~= "blizzard" and t.mode ~= "active" and t.mode ~= "everything" then t.mode = nil end
		if t.show ~= "always" and t.show ~= "active" and t.show ~= "combat" then t.show = nil end
		-- The default per-totem times, by the client's names (English until they have loaded; the
		-- lookup in warnSecs also takes the English name, so either works).
		if type(t.warnOver) ~= "table" then
			t.warnOver = { [ns.Spells.name("earthbind")] = 5, [ns.Spells.name("stoneclaw")] = 5 }
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
		if not POINTS[t.point] then t.point, t.x, t.y = TB.DEFAULTS.point, TB.DEFAULTS.x, TB.DEFAULTS.y end
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
			local v = t[k]
			local ok = type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number"
				and (v[4] == nil or type(v[4]) == "number")
			if not ok then t[k] = CopyTable(TB.DEFAULTS[k]) end
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

-- The totems known for an element, by spell ID, in Blizzard's order; a totem known at several
-- ranks (one name in the client's language) is listed once, at its highest.
local function knownTotems(slot)
	if not GetMultiCastTotemSpells then return {} end
	local ok, ids = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
	if not ok then return {} end
	local out, at = {}, {}
	for _, id in ipairs(ids) do
		local name = ns.Spells.nameOf(id)
		if name then
			local i = at[name]
			if not i then table.insert(out, id); at[name] = #out
			elseif ns.Spells.rank(id) > ns.Spells.rank(out[i]) then out[i] = id end
		end
	end
	return out
end
TB.knownTotems = knownTotems

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
local function wrapClick(b, pre, post) SecureHandlerWrapScript(b, "OnClick", picker, pre, post) end


local slots = {}   -- element -> slot record
TB.slots, TB.frame = slots, bar

-- Over a button's look (above its timer, and inside the look so it fades with it): the key bound to
-- it, in the top corner, and its highlight while Blizzard's Quick Keybind Mode is open.
local KEY_HIGHLIGHT = "UI-HUD-ActionBar-IconFrame-Mouseover"
local function keyLayer(v)
	local f = CreateFrame("Frame", nil, v)
	f:SetAllPoints()
	f:SetFrameLevel(v:GetFrameLevel() + 6)
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

-- The global cooldown's sweep, as on action bars: on its own Cooldown over the icon (and the expiring
-- warning), below the button's timer, so the time left stays readable.
local function gcdSweep(v)
	local cd = CreateFrame("Cooldown", nil, v, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetFrameLevel(v:GetFrameLevel() + 2)
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
	cd:SetSwipeColor(0, 0, 0, 0.6)
	return cd
end


for index, el in ipairs(ELEMENTS) do
	local slot = SLOT[el]
	local s = { el = el, slot = slot, index = index }
	slots[el] = s

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
	v:SetFrameLevel(b:GetFrameLevel() + 2)
	v:EnableMouse(false)
	s.vis = v
	-- "Not your pick": the element's pick, small, on the side away from the picker (a plain frame).
	local badge = CreateFrame("Frame", nil, bar)
	badge:SetFrameLevel(b:GetFrameLevel() + 6)
	badge.icon = badge:CreateTexture(nil, "ARTWORK")
	badge.icon:SetAllPoints()
	badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	badge:Hide()
	s.badge = badge
	-- Killed early and ran out (ns.makeEndFlash): on their own frames, since the slot's look can be
	-- invisible (Active totems). Two frames: each has its own secret gate.
	local kf = ns.makeEndFlash(bar, b, "totembar")
	s.expired = ns.makeEndFlash(bar, b, "totembar")
	s.killed = kf
	v.bg = v:CreateTexture(nil, "BACKGROUND")
	v.bg:SetAllPoints()
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Time left: a timer (text, swipe, bar), above the warning layer so it stays readable.
	s.timer = ns.Timer.new(v, "totembar", "uptime", { anchor = v, school = el })
	s.timer.cd:SetFrameLevel(v:GetFrameLevel() + 3)
	s.timer.bar:SetFrameLevel(v:GetFrameLevel() + 4)
	v.cd = s.timer.cd
	s.keys = keyLayer(v)
	s.gcd = gcdSweep(v)
	s.command = "CLICK ShamanForeverKeyCast" .. NAME[el] .. ":LeftButton"   -- its key (Key bindings, below)
	-- The expiring warning is the timer's (Timer:setExpire, as on the HUD): a grey copy of the icon, a
	-- red ring, a dark pulsing layer and a glow, above the icon and below the cooldown, in the slot's
	-- last seconds. drawSlot gives it the totem's own warning time and icon.

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
	local ok, v = pcall(IsPlayerSpell, spell)
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
	v:SetFrameLevel(b:GetFrameLevel() + 2)
	v.icon = v:CreateTexture(nil, "ARTWORK")
	v.icon:SetAllPoints()
	v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	extras[key] = { key = key, spell = spell, button = b, vis = v, keys = keyLayer(v), gcd = gcdSweep(v),
		command = "CLICK ShamanForeverKey" .. key .. ":LeftButton" }
end
extras.Recall.button:SetAttribute("*type2", "macro")
extras.Recall.button:SetAttribute("macrotext", DISMISS_ALL)

-- Each button's key, in its corner (any time: plain frames).
local function drawKeys()
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
local function drawGCD()
	-- Not gated on the bar being shown: the cast that brings it up (in combat, a first totem) sweeps too.
	local on = ns.Style.get("totembar", "gcd").show
	for _, el in ipairs(ELEMENTS) do
		local s = slots[el]
		local action = multiAction(s.slot)
		local d = on and feat("cast") and HasAction(action)
			and gcdOf(C_ActionBar.GetActionCooldown, C_ActionBar.GetActionCooldownDuration, action)
		if d then s.gcd:SetCooldownFromDurationObject(d) else s.gcd:Clear() end
	end
	for _, e in pairs(extras) do
		local d = on and e.button:IsShown() and knows(e.spell)
			and gcdOf(C_Spell.GetSpellCooldown, C_Spell.GetSpellCooldownDuration, e.spell)
		if d then e.gcd:SetCooldownFromDurationObject(d) else e.gcd:Clear() end
	end
end
TB.drawGCD = drawGCD

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
TB.EXTRA_GAP = 6   -- added to the spacing between the extras and the slots
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
-- Drawing (any time, combat included)
------------------------------------------------------------------------
-- The element's pick, by spell ID (nil for "No totem").
local function pickSpell(slot)
	local ok, kind, id = ns.try("totem bar: pick", GetActionInfo, multiAction(slot))
	if not ok or isSecret(kind) or isSecret(id) or kind ~= "spell" or type(id) ~= "number" then return nil end
	return id
end

-- The totem down in a slot, by spell ID: our own last cast into it (exact, in combat too), else, out
-- of combat, the slot's own spell ID (after a /reload, before we have cast). Never the slot's name:
-- right after a cast it can still be the previous totem's. nil when unknown.
local function downSpell(slot)
	local id = ns.totemSpellInSlot and ns.totemSpellInSlot(slot)
	if id then return id end
	if InCombatLockdown() then return nil end
	local ok, _, _, _, _, _, _, sid = ns.try("totem bar: totem info", GetTotemInfo, slot)
	if ok and not isSecret(sid) and type(sid) == "number" and sid > 0 then return sid end
end
TB.downSpell = downSpell

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

-- The parts that follow the remaining time: the time bar once it has run out, and the range strip.
-- (The expiring warning follows it in Timers' own ticker.)
-- Values from the duration object may be secret, so they only ever go straight to SetAlpha.
function TB.alphas(s)
	local d = s.dur
	if not d then return end
	local tbar = s.timer.bar
	if ns.CURVE_LIVE and tbar:IsShown() then
		local ok, a = ns.try("totem bar: time bar", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		if ok then tbar:SetAlpha(a) end
	end
	if TB.range then TB.range.alphas(s) end
end

local slotEmptied   -- Killed early, below

local function drawSlot(s)
	local c, v = cfg(), s.vis
	local was = s.dur   -- a slot that had a totem and now has none ended it: see slotEmptied
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
		-- Not the element's pick? Only when both are known: the totem down (see downSpell) and a pick
		-- (not "No totem"); any rank of the pick counts as the pick.
		local down = downSpell(s.slot)
		local pick = down and c.offPick and c.mode == "everything" and pickSpell(s.slot)
		if pick and not ns.Spells.same(down, pick) then
			ns.try("totem bar: badge", s.badge.icon.SetTexture, s.badge.icon, GetActionTexture(multiAction(s.slot)))
			s.badge:Show()
		else s.badge:Hide() end
		s.dur = d
		s.timer:setExpire({ secs = warnSecs(c, down), grey = c.warnGrey, ring = c.warnRing, pulse = c.warnPulse, glow = c.warnGlow })
		if iok and (isSecret(icon) or icon) then s.timer:setExpireIcon(icon) end
		TB.alphas(s)
		return true
	end
	s.dur = nil
	if was then slotEmptied(s, was) end
	s.badge:Hide()
	-- Not down: the element's pick (greyed or in colour, at its opacity), or its colour, or nothing.
	-- With nothing picked, "pick" falls back to the element colour.
	s.timer:clear()
	-- Active totems: only totems that are down show (the slot keeps its place; secure buttons can't
	-- move in combat). A plain frame's alpha, so this works in combat too. In Quick Keybind Mode they
	-- show, to be bound.
	v:SetAlpha((c.mode == "everything" or kbOpen) and 1 or 0)
	local tex = c.empty == "pick" and GetActionTexture and GetActionTexture(multiAction(s.slot))
	if isSecret(tex) or tex then
		ns.try("totem bar: pick icon", v.icon.SetTexture, v.icon, tex)
		v.icon:SetDesaturated(c.idleGrey)
		v.icon:SetAlpha(c.idleAlpha)
		v.bg:SetColorTexture(0, 0, 0, 0.6 * c.idleAlpha)
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
		if TB.range then TB.range.draw(s) end
	end
	anyDown = down
end
TB.draw = drawAll

-- Redraw (any time), and when the first totem goes down or the last one goes, the bar's driver
-- for "In combat or a totem down" (out of combat only).
local layout   -- Layout, below
local function redraw()
	local wasDown = anyDown
	drawAll()
	if anyDown ~= wasDown and cfg().show == "active" then layout() end
end

-- The warnings follow the remaining time, so they are re-evaluated a few times a second.
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
local function setTotemFrameHidden(hide)
	totemFrameHidden = hide
	TotemFrame:SetAlpha(hide and 0 or 1)
	for _, child in ipairs({ TotemFrame:GetChildren() }) do
		if child.EnableMouse and not (child.IsProtected and child:IsProtected()) then child:EnableMouse(not hide) end
	end
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

local POP_STEP = 3
-- known: the element's knownTotems, from layout().
local function layoutPopout(s, size, known)
	local c, pop = cfg(), s.popout
	local slot = s.slot
	local ids = { 0 }   -- "No totem" first, nearest the slot (as Blizzard's)
	for _, id in ipairs(known) do table.insert(ids, id) end
	local psz = math.floor(size * 0.8 + 0.5)
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
end

-- The badge sits opposite the picker: below a row whose pickers open up, and so on.
-- A texture's colour, from grey (0) to full (1); all or nothing where partial desaturation is missing.
function TB.saturate(tex, sat)
	if not pcall(tex.SetDesaturation, tex, 1 - sat) then tex:SetDesaturated(sat < 0.5) end
end

local function layoutBadge(s, size, border)
	local c, bd, b = cfg(), s.badge, s.button
	local bs = math.max(math.floor(size * c.badgeSize + 0.5), 8)
	bd:SetSize(bs, bs)
	bd:SetAlpha(c.badgeAlpha)
	TB.saturate(bd.icon, c.badgeSat)
	bd:ClearAllPoints()
	local gap = 3
	if c.pop == "up" then bd:SetPoint("TOP", b, "BOTTOM", 0, -gap)
	elseif c.pop == "down" then bd:SetPoint("BOTTOM", b, "TOP", 0, gap)
	elseif c.pop == "right" then bd:SetPoint("RIGHT", b, "LEFT", -gap, 0)
	else bd:SetPoint("LEFT", b, "RIGHT", gap, 0) end
	if ns.applyBorder then ns.applyBorder(bd, border and border.show and { show = true, size = 1, color = border.color } or border) end
end

local function layoutArrow(s)
	local c, ar, b = cfg(), s.arrow, s.button
	local tab = c.arrowSize
	ar:ClearAllPoints()
	if c.pop == "up" then ar:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 1, 1); ar:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", -1, 1); ar:SetHeight(tab)
	elseif c.pop == "down" then ar:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 1, -1); ar:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -1, -1); ar:SetHeight(tab)
	elseif c.pop == "right" then ar:SetPoint("TOPLEFT", b, "TOPRIGHT", 1, -1); ar:SetPoint("BOTTOMLEFT", b, "BOTTOMRIGHT", 1, 1); ar:SetWidth(tab)
	else ar:SetPoint("TOPRIGHT", b, "TOPLEFT", -1, -1); ar:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -1, 1); ar:SetWidth(tab) end
	ar:SetShown(feat("arrows"))
	-- Above every open picker's catch button (same strata), below the picker's own buttons.
	ar:SetFrameLevel(s.popout.catch:GetFrameLevel() + 2)
	local g = s.arrowVis.glyph
	g:SetSize(math.max(tab * 1.1, 10), math.max(tab * 0.6, 6))
	g:SetRotation(({ up = 0, down = math.pi, right = -math.pi / 2, left = math.pi / 2 })[c.pop])
	s.arrowVis:SetShown(feat("arrows"))
end

local function visibilityDriver()
	local c = cfg()
	if not barOn() then return "hide" end
	if kbOpen or not ns.getAccount().locked then return "show" end
	if c.show == "combat" then return "[petbattle] hide; [combat] show; hide" end
	if c.show == "active" then return "[petbattle] hide; [combat] show; " .. (anyDown and "show" or "hide") end
	return "[petbattle] hide; show"
end
local lastDriver

function layout()
	if ns.deferInCombat("totem bar layout", layout) then return end
	if classDone then return end
	-- Any open picker closes first: a layout can hide the bar or a slot under it (it would come back
	-- open later).
	closePopouts()
	local c = cfg()
	local size, border = look()
	-- Scale and opacity first: borders below are lines, sized for the bar's scale. Out of combat
	-- only, like everything on a frame holding secure buttons.
	bar:SetScale(c.scale)
	bar:SetAlpha(c.alpha)
	local shown, known = {}, {}
	for _, el in ipairs(c.order) do
		local s = slots[el]
		known[el] = knownTotems(s.slot)
		local on = barOn() and not c.hidden[el] and (#known[el] > 0 or not GetMultiCastTotemSpells)
		s.button:SetShown(on)
		s.vis:SetShown(on)
		if not on then s.killed.mark:Hide() end   -- a slot taken off the bar takes its cross along
		if on then table.insert(shown, s) else s.arrow:Hide(); s.arrowVis:Hide() end
	end
	local row = c.dir == "row"
	if row and c.pop ~= "up" and c.pop ~= "down" then c.pop = "up" end
	if not row and c.pop ~= "right" and c.pop ~= "left" then c.pop = "right" end
	-- Everything along the bar, in order: extras before, slots, extras after, each with its gap.
	local before, after = extraSides()
	local esz = math.floor(size * c.extrasScale + 0.5)
	local seq = {}   -- { button, gap before it, its size }
	local function put(b, gap, sz) table.insert(seq, { b, #seq > 0 and gap or 0, sz }) end
	for _, k in ipairs(before) do put(extras[k].button, c.spacing, esz) end
	for i, s in ipairs(shown) do put(s.button, i == 1 and c.spacing + TB.EXTRA_GAP or c.spacing, size) end
	for i, k in ipairs(after) do put(extras[k].button, i == 1 and c.spacing + TB.EXTRA_GAP or c.spacing, esz) end
	-- LEFT / TOP anchors keep every button centred on the bar's line, whatever its size.
	local long = 0
	for _, item in ipairs(seq) do
		local b, sz = item[1], item[3]
		long = long + item[2]
		b:SetSize(sz, sz)
		-- Its key label scales with the icon.
		if keyTexts[b] then keyTexts[b]:SetFont(STANDARD_TEXT_FONT, math.max(8, math.floor(sz * 0.3 + 0.5)), "OUTLINE") end
		b:ClearAllPoints()
		if row then b:SetPoint("LEFT", bar, "LEFT", long, 0) else b:SetPoint("TOP", bar, "TOP", 0, -long) end
		long = long + sz
	end
	local on = {}
	for _, k in ipairs(before) do on[k] = true end
	for _, k in ipairs(after) do on[k] = true end
	for key, e in pairs(extras) do
		local show = on[key] or false
		e.button:SetShown(show)
		e.vis:SetShown(show)
		if show then
			local learned = knows(e.spell)
			e.button:SetAttribute("*type1", learned and "spell" or nil)
			e.vis.icon:SetTexture(C_Spell.GetSpellTexture(e.spell))
			e.vis.icon:SetDesaturated(not learned)
			e.vis.icon:SetAlpha(learned and 1 or 0.6)
			if ns.applyBorder then ns.applyBorder(e.vis, border) end
		end
	end
	for _, s in ipairs(shown) do
		local b = s.button
		b:SetAttribute("*type1", feat("cast") and "action" or nil)
		-- Alt+click picks only in Everything (in Active totems an empty slot is invisible); off, it
		-- casts like a plain click.
		b:SetAttribute("sf-altpick", barOn() and cfg().mode == "everything")
		b:SetAttribute("action", multiAction(s.slot))
		castKeys[s.el]:SetAttribute("action", multiAction(s.slot))
		if ns.applyBorder then ns.applyBorder(s.vis, border) end
		s.timer:apply()
		layoutArrow(s)
		layoutBadge(s, size, border)
		layoutPopout(s, size, known[s.el])
	end
	long = math.max(long, size)
	local across = (#before + #after > 0) and math.max(size, esz) or size
	if row then bar:SetSize(long, across) else bar:SetSize(across, long) end
	bar:ClearAllPoints()
	bar:SetPoint(c.point, UIParent, c.point, c.x / c.scale, c.y / c.scale)
	if TB.range then TB.range.layout(size) end   -- after the scale: its height is a line's
	drawAll()
	drawKeys()
	drawGCD()
	ns.refitRings()
	local driver = visibilityDriver()
	if driver ~= lastDriver then
		lastDriver = driver
		RegisterStateDriver(bar, "visibility", driver)
	end
	applyTotemFrame()
	applyActionBar()
	if mover then mover.update() end
	-- Not a shaman: the bar is laid out hidden; nothing else will change that.
	if playerClass and not isShaman() then classDone = true end
end
TB.layout = layout

-- Settings changed (options page): relayout now, or when combat ends.
-- The slots' timers take their current style (General's or the bar's own). Plain frames, so any time.
function TB.applyTimers()
	for _, el in ipairs(ELEMENTS) do slots[el].timer:apply() end
end

function TB.apply()
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
-- As for groups: mouse wheel, icon size (lines stay crisp); Ctrl + wheel, scale (everything grows,
-- lines too); Shift + wheel, opacity.
mover:SetScript("OnMouseWheel", function(self, delta)
	if InCombatLockdown() then return end
	local c = cfg()
	local function step(key) c[key] = clamp(math.floor((c[key] + delta * 0.05) * 100 + 0.5) / 100, RANGES[key]) end
	if IsShiftKeyDown() then step("alpha")
	elseif IsControlKeyDown() then step("scale")
	else
		local from = look()   -- the size it has now, General's or its own
		c.sizeFollow = false
		c.size = clamp(from + delta * 2, RANGES.size)
	end
	layout()
	self.label:SetText(string.format("Totem bar: size %d, scale %.2f, opacity %.0f%%", (look()), c.scale, c.alpha * 100))
	if ns.RefreshOptions then ns.RefreshOptions() end
end)
function mover.update()
	local on = barOn() and not ns.getAccount().locked and not InCombatLockdown()
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
-- taints Blizzard's key handling (EllesmereUI found keys it passes on, like the screenshot key, then
-- blocked). As Blizzard's: the key replaces the first key and keeps the second, Escape clears the
-- first, and OK saves (SaveBindings) or Cancel undoes (LoadBindings) our changes along with its own.
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
	drawKeys()
	kbTooltip()
end

catcher:SetScript("OnLeave", kbLeave)
catcher:SetScript("OnKeyDown", function(_, key) kbBind(key) end)
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
	drawAll()  -- the empty slots' look, at once (also in combat, where the layout waits)
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
kbEvents:RegisterEvent("PLAYER_LOGIN")
kbEvents:RegisterEvent("ADDON_LOADED")
kbEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
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
			if HasAction and HasAction(action) then pcall(GameTooltip.SetAction, GameTooltip, action)
			else GameTooltip:SetText(NAME[el] .. ": no totem picked") end
		end
		GameTooltip:Show()
	end)
	s.button:SetScript("OnLeave", function() GameTooltip:Hide(); hover(s) end)
	s.arrow:SetScript("OnEnter", function() hover(s) end)
	s.arrow:SetScript("OnLeave", function() hover(s) end)
end

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
-- Events
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Killed early. When a slot empties, its last duration object still says how much time the totem
-- had left (tested 2026-09-25); ns.makeEndFlash turns that into the flash's alpha through a curve,
-- so a totem that simply ran out stays invisible. Our own dismissals don't flash: every one goes through
-- DestroyTotem (right-click, keys, dismiss all, Blizzard's frame), and Totemic Recall is our own
-- cast. A slot that fills again at once (a new totem cast over it) doesn't flash either. The cross
-- (killedMark) sits under the same gate and goes on a recast or after 5 s.
------------------------------------------------------------------------
local dismissedAt = {}   -- slot -> GetTime() of our last dismissal
if DestroyTotem then hooksecurefunc("DestroyTotem", function(slot) dismissedAt[slot] = GetTime() end) end
local function recalled() for slot = 1, 4 do dismissedAt[slot] = GetTime() end end

function slotEmptied(s, was)
	C_Timer.After(0.1, function()
		local mine = dismissedAt[s.slot] and GetTime() - dismissedAt[s.slot] < 1.5
		local ok, d = ns.try("totem bar: duration", GetTotemDuration, s.slot)
		local refilled = ok and d ~= nil
		if mine or refilled then return end
		if ns.onTotemGone then ns.onTotemGone(s.slot, was) end   -- Earthbind / Stoneclaw elements
		local c = cfg()
		if not s.button:IsShown() then return end
		if c.expiredPop then s.expired:play(was, { expired = true, pop = true }) end
		if c.killed then s.killed:play(was, { pop = c.killedPop, glow = c.killedGlow, mark = c.killedMark }) end
	end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_ENABLED",
		"SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MULTI_CAST_ACTIONBAR", "UPDATE_BINDINGS", "SPELL_UPDATE_COOLDOWN" }) do
	pcall(ev.RegisterEvent, ev, e)
end
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
-- After one of our casts: redraw once the main file has recorded which totem went into which slot
-- (ns.totemSpellInSlot; its handler may run after ours), so the order of this event and
-- PLAYER_TOTEM_UPDATE no longer matters. Plain frames only, so fine in combat.
local casts, redrawQueued = {}, false   -- spell IDs cast since the last check
local function redrawAfterCast(spell)
	casts[spell] = true
	if redrawQueued then return end
	redrawQueued = true
	C_Timer.After(0, function()
		redrawQueued = false
		local totem = not ns.totemSpellInSlot   -- can't tell: redraw anyway
		for slot = 1, 4 do
			local id = not totem and ns.totemSpellInSlot(slot)
			if id and casts[id] then totem = true end
		end
		wipe(casts)
		if totem then redraw() end
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
		redraw()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local _, spell = ...   -- unit, castGUID, spellID
		if isSecret(spell) or type(spell) ~= "number" then return end
		if ns.Spells.keyOf(spell) == "recall" then recalled() end
		redrawAfterCast(spell)
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		-- The element's multi-cast slots, or 0 (every slot).
		local base = multiAction(1) - 1
		if not isSecret(arg1) and type(arg1) == "number" and (arg1 == 0 or (arg1 > base and arg1 <= base + 12)) then redraw() end
	elseif event == "UPDATE_BINDINGS" then
		drawKeys()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		drawGCD()
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
function TB.pickTexture(el) return GetActionTexture(multiAction(SLOT[el])) end
function TB.known(el)
	-- The real picker's list when it is built (it matches the bar exactly), else Blizzard's.
	local ids = {}
	for _, p in ipairs(slots[el].popout.buttons) do
		if p:IsShown() and p.spellID and p.spellID ~= 0 then table.insert(ids, p.spellID) end
	end
	if #ids > 0 then return ids end
	return knownTotems(SLOT[el])
end
TB.look = look

-- For /sf debug.
function TB.debug()
	local c = cfg()
	local mc = MultiCastActionBarFrame
	-- The GCD sweep's test: is the first slot's isOnGCD readable (in combat too)?
	local gok, ginfo = pcall(C_ActionBar.GetActionCooldown, multiAction(SLOT.earth))
	local g = not gok and "error" or type(ginfo) ~= "table" and "none"
		or isSecret(ginfo.isOnGCD) and "secret" or tostring(ginfo.isOnGCD)
	return string.format("totem bar mode %s, show %s, driver %s, shown %s, earth isOnGCD %s; TotemFrame parent %s alpha %s; Totem Action Bar parent %s",
		c.mode, c.show, tostring(lastDriver), tostring(bar:IsShown()), g,
		TotemFrame and TotemFrame:GetParent() and (TotemFrame:GetParent():GetName() or "?") or "none",
		TotemFrame and string.format("%.2f", TotemFrame:GetAlpha()) or "-",
		mc and (mc:GetParent() == hiddenParent and "hidden" or (mc:GetParent() and mc:GetParent():GetName() or "?")) or "none")
end
