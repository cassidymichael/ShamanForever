-- ShamanForever: Lightning Shield charges + shock cooldown/range/mana HUD for the WoW: Forever beta.
--
-- Addon code cannot read player auras in combat on this client, so the shield is drawn by Blizzard's
-- secure CustomAuraContainer: we hand it widgets, its untainted code fills them. Everything else here
-- is plain UI. Rule for this client: never do Lua math or comparisons on a possibly-secret value.

local ADDON, ns = ...
local PREFIX = "|cff3399ffShamanForever|r: "
local function say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

local SHIELD_NAME = "Lightning Shield"
local VANILLA_SHIELD_IDS = { 324, 325, 905, 945, 8134, 10431, 10432 }
local SHOCKS = { earth = "Earth Shock", flame = "Flame Shock", frost = "Frost Shock" }
local SHOCK_ORDER = { "earth", "flame", "frost" }
local CD_FONT = "ShamanForeverCDFont"

-- Every element belongs to exactly one group, which owns its position, scale, opacity and flow;
-- whether the element is drawn (always, in combat, never) is its own setting in db.elementOpts.
-- Positions are offsets in the group's own (scaled) units.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.65,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	spacing = 10,
	combatOnly = false,          -- hide the group out of combat (always shown while unlocked)
}

local DEFAULTS = {
	locked = true,
	testMode = false,       -- register placeholder elements for trying out layouts
	snap = false,           -- unlocked drags snap to other groups, the screen centre and the grid
	grid = false,           -- grid over the screen while unlocked
	gridSize = 32,
	iconSize = 40,          -- base element size; each group scales it
	groups = { { point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.65, orientation = "horizontal",
		growth = "forward", spacing = 10, members = { "shield", "shock" } } },
	known = {},             -- element keys placed at least once; new ones join the first group
	elementOpts = {},       -- per-element settings by key, e.g. { shock = { show = "combat" } }
	-- shield
	countPos = "center",    -- corner | center
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	showCount = true,       -- charge number (Blizzard prints it for two or more)
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	underlayUp = 0.25,      -- underlay strength while the shield is believed up (0 = none)
	shieldSwipe = 0.5,      -- darkness of the duration swipe over the shield icon (0 = no swipe)
	shieldIconAlpha = 1,    -- manual multiplier on the compensated shield icon alpha
	-- shock
	shock = "earth",        -- which shock the icon tracks
	manaSpell = "tracked",  -- tracked | earth | flame | frost
	cdText = true,
	cdTextSize = 22,
	manaRing = 0.6,         -- not enough mana: blue ring inside the icon edge, this opaque
	manaStyle = "both",     -- not enough mana (alone): overlay | tint | both on the icon body
	manaIntensity = 0.25,
	manaTint = 0.8,
	rangeStyle = "tint",    -- out of range: overlay | tint | both, painted on the icon body
	rangeIntensity = 0.45,
	rangeTint = 0.7,
}
-- Pre-groups layout keys, folded into a single group on first load.
local LEGACY_KEYS = { "point", "x", "y", "alpha", "scale", "size", "spacing", "orientation", "growth", "order", "enabled" }
-- Saved settings format. Bump it and add a step on ADDON_LOADED when a stored value must change.
local SETTINGS_VERSION = 3
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function safe(fn, ...) if not fn then return false end return pcall(fn, ...) end
local function describeArg(v) if isSecret(v) then return "<secret>" end return tostring(v) end

------------------------------------------------------------------------
-- Spellbook: highest known rank of each spell, by name
------------------------------------------------------------------------
local book = {}

local function rankOf(item)
	local sub = item.subName
	if (not sub or sub == "") and C_Spell.GetSpellSubtext then
		local ok, s = safe(C_Spell.GetSpellSubtext, item.spellID)
		if ok then sub = s end
	end
	return tonumber((sub or ""):match("(%d+)")) or 0
end

local function scanSpellbook()
	book = {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local ok, item = safe(C_SpellBook.GetSpellBookItemInfo, i, bank)
				if ok and item and item.spellID and item.name and not item.isPassive then
					local rank = rankOf(item)
					local cur = book[item.name]
					if not cur or rank > cur.rank then
						book[item.name] = { id = item.spellID, icon = item.iconID, rank = rank }
					end
				end
			end
		end
	end
end

local function knownSpell(name)
	local e = book[name]
	if e then return e.id, e.icon end
	local ok, info = safe(C_Spell.GetSpellInfo, name)
	if ok and type(info) == "table" and info.spellID then return info.spellID, info.iconID end
	return nil
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local cdFont = CreateFont(CD_FONT)

-- root spans the screen and takes no input: the parent of every group (each anchored to UIParent),
-- hidden as a whole for other classes. Not the old
-- ShamanForeverFrame name: that frame was dragged, so the client's layout cache would re-anchor it.
local root = CreateFrame("Frame", "ShamanForeverRoot", UIParent)
root:SetAllPoints(UIParent)

local function makeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.manaOverlay = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.manaOverlay:SetAllPoints(f.tex)
	f.manaOverlay:SetColorTexture(0.2, 0.45, 1, 0.55)
	f.manaOverlay:Hide()
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	-- Text sits on its own frame above the cooldown so the swipe never dims it.
	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints()
	f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.count = f.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	f.count:SetFont(STANDARD_TEXT_FONT, math.floor(size * 0.45), "OUTLINE")
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	f.count:SetJustifyH("RIGHT")
	local okFS, cdText = pcall(f.cd.GetCountdownFontString, f.cd)
	if okFS and cdText then pcall(cdText.SetDrawLayer, cdText, "OVERLAY", 7) end
	-- Red ring just inside the icon edge, so an exact-size frame on top covers it completely.
	f.ring = {}
	local function edge(p1, p2, w, h)
		local t = f.textFrame:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetColorTexture(1, 0, 0, 0.9)
		t:SetPoint(p1, f.tex, p1, 0, 0)
		t:SetPoint(p2, f.tex, p2, 0, 0)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		t:Hide()
		table.insert(f.ring, t)
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 3)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
	edge("TOPLEFT", "BOTTOMLEFT", 3, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
	f.SetRingShown = function(self, shown, r, g, b, a)
		for _, t in ipairs(self.ring) do
			if shown then t:SetColorTexture(r or 1, g or 0, b or 0, a or 0.9); t:Show() else t:Hide() end
		end
	end
	return f
end

local shield = makeIcon(root, DEFAULTS.iconSize)
shield.count:Hide()

local shock = makeIcon(root, DEFAULTS.iconSize)
shock.count:Hide()

-- Placeholder elements for trying out layouts, available only in test mode. Sizes are multiples of
-- the icon size, with one wide and one tall shape to exercise non-square layout.
local PLACEHOLDERS = {
	{ key = "testA", letter = "A", color = { 0.85, 0.25, 0.25 }, w = 1, h = 1 },
	{ key = "testB", letter = "B", color = { 0.25, 0.7, 0.3 }, w = 1, h = 1 },
	{ key = "testC", letter = "C", color = { 0.3, 0.45, 0.9 }, w = 1, h = 1 },
	{ key = "testD", letter = "D", color = { 0.85, 0.7, 0.2 }, w = 2.5, h = 0.5 },
	{ key = "testE", letter = "E", color = { 0.65, 0.3, 0.8 }, w = 0.5, h = 1.5 },
}

local function makePlaceholder(p)
	local f = CreateFrame("Frame", nil, root)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetColorTexture(p.color[1], p.color[2], p.color[3], 0.9)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.text:SetPoint("CENTER")
	f.text:SetText(p.letter)
	f:Hide()
	return f
end

local shieldIcon, shockIcon = 136051, 136026

-- Element registry. db.groups decides where each one shows. Each entry owns its size, so elements
-- need not be square, and paints a texture that stands in for it in the unlock tray and while dragging.
local function iconSize() return db.iconSize, db.iconSize end
local ELEMENTS = {
	shield = { frame = shield, label = "Lightning Shield", getSize = iconSize, paint = function(t) t:SetTexture(shieldIcon) end },
	shock  = { frame = shock,  label = "Shock",            getSize = iconSize, paint = function(t) t:SetTexture(shockIcon) end },
}
local ELEMENT_KEYS = { "shield", "shock" }   -- registration order
for _, p in ipairs(PLACEHOLDERS) do
	local c = p.color
	ELEMENTS[p.key] = { frame = makePlaceholder(p), label = "Test " .. p.letter, placeholder = true,
		getSize = function() return db.iconSize * p.w, db.iconSize * p.h end,
		paint = function(t) t:SetColorTexture(c[1], c[2], c[3], 0.9) end }
	table.insert(ELEMENT_KEYS, p.key)
end

------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------
local function available(key)
	local e = ELEMENTS[key]
	return e ~= nil and (not e.placeholder or db.testMode)
end

-- Group index and position of an element. Every available element sits in a group; whether it is
-- drawn is its own "show" setting, so hiding one keeps its place.
local function findElement(key)
	for gi, g in ipairs(db.groups) do
		for i, k in ipairs(g.members) do if k == key then return gi, i end end
	end
end

local function elementOpts(key)
	local o = db.elementOpts[key]
	if not o then o = {}; db.elementOpts[key] = o end
	return o
end

-- always | combat | never
local function showMode(key) return elementOpts(key).show or "always" end

local function isEnabled(key) return findElement(key) ~= nil and showMode(key) ~= "never" end

local function removeElement(key)
	local gi, i = findElement(key)
	if gi then table.remove(db.groups[gi].members, i) end
end

local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do g[k] = template and template[k] or v end
	g.members = {}
	table.insert(db.groups, g)
	return g
end

local function pruneGroups()
	for gi = #db.groups, 1, -1 do
		if #db.groups[gi].members == 0 then table.remove(db.groups, gi) end
	end
end

-- Makes db.groups consistent: fills missing group fields, drops unknown, unavailable and duplicate
-- members, and places every element that is in no group. Elements never seen before (new in an
-- update, or test ones) show; ones seen before were hidden under the old rule, so they come back
-- into the first group set to never show.
local function sanitize()
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		local kept = {}
		for _, key in ipairs(type(g.members) == "table" and g.members or {}) do
			if available(key) and not seen[key] then
				table.insert(kept, key)
				seen[key], db.known[key] = true, true
			end
		end
		g.members = kept
	end
	pruneGroups()
	local fresh, freshTest = {}, {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if available(key) and not seen[key] then
			if not db.known[key] then
				table.insert(ELEMENTS[key].placeholder and freshTest or fresh, key)
				db.known[key] = true
			else
				elementOpts(key).show = "never"
				table.insert(fresh, key)
			end
		end
	end
	if #fresh > 0 then
		local g = db.groups[1] or newGroup()
		for _, key in ipairs(fresh) do table.insert(g.members, key) end
	end
	if #freshTest > 0 then
		local g = newGroup(db.groups[1])
		g.point, g.x, g.y = "CENTER", 0, -40
		g.members = freshTest
	end
end

-- Test elements are forgotten when switched off, so switching back on puts them in a fresh group.
local function setTestMode(on)
	db.testMode = on
	if not on then
		for _, p in ipairs(PLACEHOLDERS) do db.known[p.key] = nil end
	end
	sanitize()
end

-- Places a group so its centre sits at screen coordinates (the units GetCursorPosition returns).
local function setGroupCenter(g, sx, sy)
	local ui = UIParent:GetEffectiveScale()
	local w, h = UIParent:GetSize()
	g.point = "CENTER"
	g.x = (sx / ui - w / 2) / g.scale
	g.y = (sy / ui - h / 2) / g.scale
end

local function screenCenter(f)
	local x, y = f:GetCenter()
	if not x then return nil end
	local s = f:GetEffectiveScale()
	return x * s, y * s
end

local groupFrames = {}
local groupFrameScripts   -- unlock-mode handlers, assigned below

local function groupFrame(gi)
	local f = groupFrames[gi]
	if f then return f end
	f = CreateFrame("Frame", nil, root, "BackdropTemplate")
	f:SetSize(1, 1)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.index = gi
	groupFrameScripts(f)
	groupFrames[gi] = f
	return f
end

-- Combat-only visibility uses Blizzard's secure state driver, the standard technique for this. The
-- shield's group and element frames are ancestors of Blizzard's protected aura button, so an addon
-- Show/Hide/SetAlpha on them is silently dropped in combat (tested: alpha 0 out of combat never came
-- back). The driver's manager shows and hides from untainted code instead; its visibility path
-- needs only SecureCmdOptionParse, not a compiled snippet, so it survives this build's missing
-- loadstring_untainted. Groups and elements are driven separately, so an element shows only when
-- both allow it. The manager re-applies its state every 0.2s and does not show a frame it lets go
-- of, so a driven frame is never shown or hidden by hand. Only called out of combat.
local driven = {}
local function setDriven(frame, want)
	if want == (driven[frame] or false) then return end
	if want then
		local ok, err = pcall(RegisterStateDriver, frame, "visibility", "[combat] show; hide")
		if not ok then say("state driver failed: %s", tostring(err)); return end
		driven[frame] = true
	else
		pcall(UnregisterStateDriver, frame, "visibility")
		driven[frame] = nil
	end
end

-- Shows a frame, or hands it to the driver when it should only show in combat.
local function showFrame(frame, combatOnly)
	setDriven(frame, combatOnly)
	if not combatOnly then frame:Show() end
end

local function hideFrame(frame)
	setDriven(frame, false)
	frame:Hide()
end

-- Sizes and anchors a group's members in one pass, centred on the cross axis; the group frame
-- shrinks to fit so dragging feels right.
local function layoutGroup(gi)
	local g, gf = db.groups[gi], groupFrame(gi)
	local gap = g.spacing
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local prev, n, along, across = nil, 0, 0, 0
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		if showMode(key) == "never" then
			hideFrame(f)
		else
			local w, h = e.getSize()
			f:SetSize(w, h)
			f:ClearAllPoints()
			if horizontal then
				if not prev then
					local edge = forward and "LEFT" or "RIGHT"
					f:SetPoint(edge, gf, edge, 0, 0)
				elseif forward then f:SetPoint("LEFT", prev, "RIGHT", gap, 0)
				else f:SetPoint("RIGHT", prev, "LEFT", -gap, 0) end
				along, across = along + w, math.max(across, h)
			else
				if not prev then
					local edge = forward and "TOP" or "BOTTOM"
					f:SetPoint(edge, gf, edge, 0, 0)
				elseif forward then f:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
				else f:SetPoint("BOTTOM", prev, "TOP", 0, gap) end
				along, across = along + h, math.max(across, w)
			end
			showFrame(f, db.locked and showMode(key) == "combat")
			prev, n = f, n + 1
		end
	end
	along = math.max(along + math.max(n - 1, 0) * gap, 1)
	across = math.max(across, 1)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetScale(g.scale)
	gf:SetAlpha(g.alpha)
	gf:ClearAllPoints()
	gf:SetPoint(g.point, UIParent, g.point, g.x, g.y)
	local unlocked = not db.locked
	gf:EnableMouse(unlocked)
	gf:EnableMouseWheel(unlocked)
	gf:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	gf:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0)
	gf.label:SetText("Group " .. gi)
	gf.label:SetShown(unlocked)
	if n > 0 then showFrame(gf, db.locked and g.combatOnly or false) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected aura button, so
-- showing, hiding, moving or reparenting it in combat is silently dropped.
local styleNative, updateTray   -- defined further down
local layoutPending = false
local function layoutElements()
	if InCombatLockdown() then layoutPending = true return end
	layoutPending = false
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	for gi in ipairs(db.groups) do layoutGroup(gi) end
	for gi = #db.groups + 1, #groupFrames do hideFrame(groupFrames[gi]) end
	styleNative()   -- the shield's alpha compensation follows its group's opacity
	updateTray()
	if ns.RefreshOptions then ns.RefreshOptions() end
end

------------------------------------------------------------------------
-- Unlock mode: drag a group to move it (snapping to the grid and to other groups), wheel for scale
-- and opacity, right-click for its settings. Group membership is edited in the options window.
------------------------------------------------------------------------
local isShaman = false
local SNAP = 8   -- UI units: how close an edge must come to another group's edge or centre to snap
local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
local function uiScale() return UIParent:GetEffectiveScale() end

-- Grid over the whole screen while unlocked, measured from the screen centre in UIParent units.
local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid:Hide()
grid.lines = {}

local function drawGrid()
	local w, h = UIParent:GetSize()
	local gs = db.gridSize
	local n = 0
	local function line(vertical, offset)
		n = n + 1
		local t = grid.lines[n]
		if not t then t = grid:CreateTexture(nil, "BACKGROUND"); grid.lines[n] = t end
		t:ClearAllPoints()
		if offset == 0 then t:SetColorTexture(0.2, 0.6, 1, 0.5) else t:SetColorTexture(1, 1, 1, 0.1) end
		if vertical then
			t:SetPoint("TOP", grid, "TOP", offset, 0)
			t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			t:SetWidth(1)
		else
			t:SetPoint("LEFT", grid, "LEFT", 0, offset)
			t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			t:SetHeight(1)
		end
		t:Show()
	end
	for k = 0, math.floor(w / 2 / gs) do
		line(true, k * gs)
		if k > 0 then line(true, -k * gs) end
	end
	for k = 0, math.floor(h / 2 / gs) do
		line(false, k * gs)
		if k > 0 then line(false, -k * gs) end
	end
	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

-- Gold lines showing what a dragged group has snapped to.
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("BACKGROUND")
guides:SetFrameLevel(grid:GetFrameLevel() + 5)
guides.x = guides:CreateTexture(nil, "ARTWORK")
guides.x:SetColorTexture(1, 0.82, 0, 0.8)
guides.x:SetWidth(1)
guides.y = guides:CreateTexture(nil, "ARTWORK")
guides.y:SetColorTexture(1, 0.82, 0, 0.8)
guides.y:SetHeight(1)

local function showGuides(gx, gy)
	guides.x:SetShown(gx ~= nil)
	guides.y:SetShown(gy ~= nil)
	if gx then
		guides.x:ClearAllPoints()
		guides.x:SetPoint("TOP", guides, "TOPLEFT", gx, 0)
		guides.x:SetPoint("BOTTOM", guides, "BOTTOMLEFT", gx, 0)
	end
	if gy then
		guides.y:ClearAllPoints()
		guides.y:SetPoint("LEFT", guides, "BOTTOMLEFT", 0, gy)
		guides.y:SetPoint("RIGHT", guides, "BOTTOMRIGHT", 0, gy)
	end
end

-- Snaps one axis. pos is the group's centre, half its half-extent, targets the edges and centres of
-- other groups (and the screen centre). A group target within SNAP wins and returns a guide line;
-- otherwise, with a grid, the nearest of the group's two edges and centre lands on a grid line.
local function snapAxis(pos, half, targets, origin, gs)
	local bestAbs, shift, guide = SNAP, nil, nil
	for _, t in ipairs(targets) do
		for _, e in ipairs({ -half, 0, half }) do
			local d = t - (pos + e)
			if math.abs(d) <= bestAbs then bestAbs, shift, guide = math.abs(d), d, t end
		end
	end
	if shift then return pos + shift, guide end
	if gs then
		for _, e in ipairs({ -half, 0, half }) do
			local p = pos + e
			local d = origin + math.floor((p - origin) / gs + 0.5) * gs - p
			if not shift or math.abs(d) < math.abs(shift) then shift = d end
		end
		return pos + shift
	end
	return pos
end

-- Groups are dragged by hand rather than with StartMoving so they can snap while moving.
local function dragUpdate(self)
	if InCombatLockdown() then self:SetScript("OnUpdate", nil); showGuides(); return end
	local ui = uiScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx / ui + self.dragDX, cy / ui + self.dragDY
	local gx, gy
	if db.snap then
		local w, h = UIParent:GetSize()
		local s = self:GetEffectiveScale() / ui
		local tx, ty = { w / 2 }, { h / 2 }
		for gi = 1, #db.groups do
			local f = groupFrames[gi]
			if gi ~= self.index and f and f:IsShown() and f:GetLeft() then
				local fs = f:GetEffectiveScale() / ui
				local l, r, b, t = f:GetLeft() * fs, f:GetRight() * fs, f:GetBottom() * fs, f:GetTop() * fs
				table.insert(tx, l); table.insert(tx, (l + r) / 2); table.insert(tx, r)
				table.insert(ty, b); table.insert(ty, (b + t) / 2); table.insert(ty, t)
			end
		end
		local gs = db.grid and db.gridSize or nil
		x, gx = snapAxis(x, self:GetWidth() * s / 2, tx, w / 2, gs)
		y, gy = snapAxis(y, self:GetHeight() * s / 2, ty, h / 2, gs)
	end
	showGuides(gx, gy)
	local g = db.groups[self.index]
	setGroupCenter(g, x * ui, y * ui)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", g.x, g.y)
end

groupFrameScripts = function(f)
	f:SetScript("OnDragStart", function(self)
		if db.locked or InCombatLockdown() then return end
		local ui = uiScale()
		local s = self:GetEffectiveScale() / ui
		local fx, fy = self:GetCenter()
		local cx, cy = GetCursorPosition()
		self.dragDX, self.dragDY = fx * s - cx / ui, fy * s - cy / ui
		self:SetScript("OnUpdate", dragUpdate)
	end)
	f:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		showGuides()
		if not InCombatLockdown() then layoutElements() end
	end)
	f:SetScript("OnMouseWheel", function(self, delta)
		if db.locked or InCombatLockdown() then return end
		local g = db.groups[self.index]
		local sx, sy = screenCenter(self)
		if IsShiftKeyDown() then g.alpha = clamp(round2(g.alpha + delta * 0.05), 0.1, 1)
		else g.scale = clamp(round2(g.scale + delta * 0.05), 0.5, 3) end
		if sx then setGroupCenter(g, sx, sy) end   -- scale about the centre, not the anchor
		layoutElements()
		self.label:SetText(string.format("Group %d: scale %.2f, opacity %.0f%%", self.index, g.scale, g.alpha * 100))
	end)
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and not db.locked and ns.OpenOptions then ns.OpenOptions("layout", self.index) end
	end)
end

-- A small bar while unlocked: what the mouse does, snapping and grid toggles, Lock and Options.
local tray = CreateFrame("Frame", "ShamanForeverTray", UIParent, "BackdropTemplate")
tray:SetSize(500, 120)
tray:SetFrameStrata("DIALOG")
tray:SetPoint("TOP", UIParent, "TOP", 0, -120)
tray:SetMovable(true)
tray:SetClampedToScreen(true)
tray:EnableMouse(true)
tray:RegisterForDrag("LeftButton")
tray:SetScript("OnDragStart", tray.StartMoving)
tray:SetScript("OnDragStop", tray.StopMovingOrSizing)
tray:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
tray:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
tray:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
tray:Hide()
do
	local title = tray:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("ShamanForever: layout unlocked")
	tray.hint = tray:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tray.hint:SetPoint("TOPLEFT", 10, -30)
	tray.hint:SetWidth(480)
	tray.hint:SetJustifyH("LEFT")
	tray.hint:SetSpacing(2)
	tray.hint:SetText("Drag a group to move it. Mouse wheel over a group: scale. Shift + wheel: opacity.\n" ..
		"Right-click a group, or press Options, to change which elements it holds.")
	-- Controls sit on a row under the hint, so a longer hint pushes them down instead of overlapping.
	local row = CreateFrame("Frame", nil, tray)
	row:SetPoint("TOPLEFT", tray.hint, "BOTTOMLEFT", 0, -10)
	row:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row:SetHeight(26)
	tray.row = row
	local function check(label, key, tip)
		local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb.Text:SetFontObject("GameFontHighlightSmall")
		cb.Text:SetText(label)
		cb:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; layoutElements() end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return cb
	end
	tray.snap = check("Snapping", "snap", "While dragging, groups snap to other groups' edges and centres, the screen centre, and the grid when it is shown.")
	tray.snap:SetPoint("LEFT", -4, 0)
	tray.grid = check("Show grid", "grid", "A grid over the whole screen while unlocked. With snapping on, groups snap to it.")
	tray.grid:SetPoint("LEFT", tray.snap.Text, "RIGHT", 16, 0)
	local lock = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	lock:SetSize(90, 22)
	lock:SetPoint("RIGHT", 0, 0)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() db.locked = true; ns.applyLayout() end)
	local options = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	options:SetSize(90, 22)
	options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	options:SetText("Options")
	options:SetScript("OnClick", function() if ns.OpenOptions then ns.OpenOptions("layout") end end)
end

function updateTray()
	local unlocked = isShaman and not db.locked
	tray:SetShown(unlocked)
	tray:SetHeight(30 + tray.hint:GetStringHeight() + 10 + 26 + 10)
	tray.snap:SetChecked(db.snap)
	tray.grid:SetChecked(db.grid)
	grid:SetShown(unlocked and db.grid)
	if unlocked and db.grid then drawGrid() end
	if not unlocked then showGuides() end
end

------------------------------------------------------------------------
-- Lightning Shield: underlay (our "no shield" look) + Blizzard's secure aura button on top
------------------------------------------------------------------------
local shieldSpellID, shieldAuraSpellID
local believedUp = false      -- last known shield state (exact out of combat, from events in combat)
local native = { container = nil, button = nil, icon = nil, fs = nil, cd = nil, bar = nil, ticks = nil, overlay = nil,
	err = nil, ids = {} }

-- The underlay is meant to show only when Blizzard's button is hidden, i.e. when the shield is down,
-- so grey and tint apply unconditionally. Frame alpha is applied per texture, so while the shield is
-- up the translucent button stacks on the underlay and reads darker than the shock icon. The engine
-- does not tell us about the hide in combat, so the ring and the underlay strength follow our belief:
-- faded while believed up, full when believed down. Blizzard's icon alpha then compensates for the
-- remaining bleed-through (see nativeIconAlpha) so the stack sums to the display opacity exactly.
local function applyEmptyLook()
	shield.tex:SetDesaturated(db.emptyGrey)
	if db.emptyTint then shield.tex:SetVertexColor(1, 0.35, 0.35) else shield.tex:SetVertexColor(1, 1, 1) end
	shield.tex:SetAlpha(believedUp and db.underlayUp or 1)
	shield:SetRingShown(not believedUp and db.emptyRing)
end

-- With display opacity a and underlay strength u, an icon alpha b gives a stacked result of
-- a*b + (1 - a*b)*a*u; solving that for a yields b = (1 - u) / (1 - a*u). The display opacity is
-- that of the shield's group.
local function nativeIconAlpha()
	local gi = findElement("shield")
	local a, u = gi and db.groups[gi].alpha or 1, db.underlayUp
	local b = u > 0 and (1 - u) / (1 - a * u) or 1
	return math.min(math.max(b * db.shieldIconAlpha, 0.05), 1)
end

local function styleSwipe(cd)
	cd:SetDrawSwipe(db.shieldSwipe > 0)
	cd:SetSwipeColor(0, 0, 0, db.shieldSwipe)
end

local function setBelievedUp(up)
	believedUp = up
	applyEmptyLook()
end

local function shieldIDMap()
	local map = {}
	for _, id in ipairs(VANILLA_SHIELD_IDS) do map[id] = true end
	for id in pairs(native.ids) do map[id] = true end
	if shieldSpellID then map[shieldSpellID] = true end
	if shieldAuraSpellID then map[shieldAuraSpellID] = true end
	return map
end

local function learnShieldID(id)
	if not id or isSecret(id) or native.ids[id] then return end
	native.ids[id] = true
	if native.container and not native.err and not InCombatLockdown() then
		pcall(native.container.SetAuraSlotCandidateFilters, native.container, "shield", { includeSpellIDs = shieldIDMap() })
	end
end

-- Blizzard's button and its parts are off limits to addon code in combat; defer until it ends.
local nativeStylePending = false
function styleNative()
	if not native.button then return end
	if InCombatLockdown() then nativeStylePending = true return end
	nativeStylePending = false
	pcall(function()
		local size = db.iconSize
		native.container:SetSize(size, size)
		-- Moving the shield to another group reparents it, which can drop the container back under
		-- the underlay and its ring; restate the placement from setupNative.
		native.container:SetFrameStrata(shield:GetFrameStrata())
		native.container:SetFrameLevel(shield.textFrame:GetFrameLevel() + 5)
		native.button:SetSize(size, size)
		for i, t in ipairs(native.tickTextures or {}) do
			t:ClearAllPoints()
			t:SetPoint("TOP", native.ticks, "TOPLEFT", size * i / native.maxCharges, 0)
			t:SetPoint("BOTTOM", native.ticks, "BOTTOMLEFT", size * i / native.maxCharges, 0)
		end
		native.icon:SetAlpha(nativeIconAlpha())
		native.bar:SetAlpha(db.showBar and 1 or 0)
		native.ticks:SetAlpha(db.showBar and 1 or 0)
		native.fs:SetAlpha(db.showCount and 1 or 0)
		native.fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
		native.fs:ClearAllPoints()
		if db.countPos == "center" then
			native.fs:SetPoint("CENTER", native.button, "CENTER", 0, 0); native.fs:SetJustifyH("CENTER")
		else
			native.fs:SetPoint("BOTTOMRIGHT", native.button, "BOTTOMRIGHT", 2, -2); native.fs:SetJustifyH("RIGHT")
		end
		native.cd:SetCountdownFont(CD_FONT)
		native.cd:SetHideCountdownNumbers(true)
		styleSwipe(native.cd)
	end)
end

-- Called by Blizzard (untainted) once, right after it creates the slot button.
local function initNativeButton(button)
	local size = db.iconSize
	button:SetSize(size, size)
	-- Slot frames are positioned by the caller, not by the container's flow layout.
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	-- No tooltip and click-through: disable mouse input before Blizzard locks the button down.
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)

	local tex = button:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tex:SetAlpha(nativeIconAlpha())
	button:SetIcon(tex)
	native.icon = tex

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetCountdownFont(CD_FONT)
	cd:SetHideCountdownNumbers(true)
	styleSwipe(cd)
	button:SetDurationCooldown(cd)
	native.cd = cd

	-- Our parts live on an overlay frame above the cooldown so nothing Blizzard hides takes them along.
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
	native.overlay = overlay

	-- Blizzard writes the count immediately on registration, so the font must already be set.
	local fs = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
	fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
	if db.countPos == "center" then
		fs:SetPoint("CENTER", button, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
	else
		fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2); fs:SetJustifyH("RIGHT")
	end
	button:SetApplicationCount(fs)
	native.fs = fs

	-- Charge bar along the bottom edge: min 0 so one charge is one third, not empty.
	local bar = CreateFrame("StatusBar", nil, overlay)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(7)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetStatusBarColor(0.35, 0.75, 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	local maxCharges = 3
	button:SetApplicationBar(bar, { minApplications = 0, maxApplications = maxCharges })
	native.bar = bar
	local ticks = CreateFrame("Frame", nil, overlay)
	ticks:SetAllPoints(bar)
	ticks:SetFrameLevel(bar:GetFrameLevel() + 1)
	native.tickTextures, native.maxCharges = {}, maxCharges
	for i = 1, maxCharges - 1 do
		local t = ticks:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.9)
		t:SetWidth(1)
		t:SetPoint("TOP", ticks, "TOPLEFT", size * i / maxCharges, 0)
		t:SetPoint("BOTTOM", ticks, "BOTTOMLEFT", size * i / maxCharges, 0)
		table.insert(native.tickTextures, t)
	end
	native.ticks = ticks

	-- Note: script handlers on anything under Blizzard's button never run (tested: OnShow/OnHide on a
	-- child frame fired zero times), so there is no way to learn when the button hides.

	bar:SetAlpha(db.showBar and 1 or 0)
	ticks:SetAlpha(db.showBar and 1 or 0)
	fs:SetAlpha(db.showCount and 1 or 0)
	native.button = button
end

local function setupNative()
	if native.container or native.err or InCombatLockdown() then return end
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", "ShamanForeverAuraContainer", shield, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", shield, "TOPLEFT", 0, 0)
		c:SetSize(db.iconSize, db.iconSize)
		-- Intrinsic frames do not inherit placement; match the HUD's strata (HIGH would float over other
		-- addons' dialogs) and use frame level alone to sit above the underlay and its ring.
		c:SetFrameStrata(shield:GetFrameStrata())
		c:SetFrameLevel(shield.textFrame:GetFrameLevel() + 5)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)   -- unlocked drags start on the group frame underneath
		native.container = c
		c:AddAuraSlot("shield", "HELPFUL", {
			candidateFilters = { includeSpellIDs = shieldIDMap() },
			initializeFrame = initNativeButton,
		})
	end)
	if not ok then
		native.err = tostring(err)
		if native.container then native.container:Hide() end
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", native.err)
	end
end

-- Out of combat the aura is readable: sync our belief and learn the live spell ID.
local function refreshShield()
	if not shieldSpellID or InCombatLockdown() then return end
	local ok, aura = safe(C_UnitAuras.GetAuraDataBySpellName, "player", SHIELD_NAME, "HELPFUL")
	if not ok then return end
	setBelievedUp(aura ~= nil)
	if aura then
		if not isSecret(aura.spellId) then shieldAuraSpellID = aura.spellId; learnShieldID(aura.spellId) end
	end
end

------------------------------------------------------------------------
-- Shock
------------------------------------------------------------------------
local shockSpellID, manaSpellID
local shockIDs = {}
local shockState = { outOfRange = false, noMana = false }

-- Shock looks, fixed rule: out of range paints the body red; not enough mana paints the body blue
-- and adds a blue ring; when both apply the body is red (range) and the ring blue (mana).
local function paintBody(style, r, g, b, overlayAlpha, tintStrength)
	if style == "overlay" or style == "both" then
		shock.manaOverlay:SetColorTexture(r, g, b, overlayAlpha)
		shock.manaOverlay:Show()
	end
	if style == "tint" or style == "both" then
		local k = 1 - tintStrength
		shock.tex:SetVertexColor(r == 1 and 1 or k, g == 1 and 1 or k, b == 1 and 1 or k)
	end
end

local function updateShockTint()
	shock.manaOverlay:Hide()
	shock.tex:SetVertexColor(1, 1, 1)
	if shockState.outOfRange then
		paintBody(db.rangeStyle, 1, 0.25, 0.25, db.rangeIntensity, db.rangeTint)
	elseif shockState.noMana then
		paintBody(db.manaStyle, 0.2, 0.45, 1, db.manaIntensity, db.manaTint)
	end
	shock:SetRingShown(shockState.noMana, 0.2, 0.45, 1, db.manaRing)
end

local function refreshShockCooldown()
	if not shockSpellID or not isEnabled("shock") then return end
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, shockSpellID)
	if ok and dur then pcall(shock.cd.SetCooldownFromDurationObject, shock.cd, dur) end
end

local function refreshShockRange()
	if not shockSpellID or not isEnabled("shock") then return end
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	updateShockTint()
end

local function refreshShockMana()
	if not isEnabled("shock") then return end
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ok and not isSecret(noPower) and noPower == true
	updateShockTint()
end

------------------------------------------------------------------------
-- Spell resolution and layout
------------------------------------------------------------------------
local function resolveSpells()
	scanSpellbook()
	local icon
	shieldSpellID, icon = knownSpell(SHIELD_NAME)
	shieldIcon = icon or 136051
	shield.tex:SetTexture(shieldIcon)
	shockIDs = {}
	for key, name in pairs(SHOCKS) do
		local id = knownSpell(name)
		if id then shockIDs[key] = id end
	end
	local id, ic = knownSpell(SHOCKS[db.shock] or SHOCKS.earth)
	shockSpellID = id
	shockIcon = ic or 136026
	shock.tex:SetTexture(shockIcon)
	manaSpellID = (db.manaSpell ~= "tracked" and shockIDs[db.manaSpell]) or shockSpellID
	if shockSpellID and C_Spell.EnableSpellRangeCheck then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
	if shieldSpellID then learnShieldID(shieldSpellID) end
end

local function applyLayout()
	layoutElements()
	cdFont:SetFont(STANDARD_TEXT_FONT, db.cdTextSize, "OUTLINE")
	shock.cd:SetCountdownFont(CD_FONT)
	shock.cd:SetHideCountdownNumbers(not db.cdText)
	refreshShockMana()
	if not native.container then setupNative() end
	styleNative()
	applyEmptyLook()
end

local function refreshAll()
	refreshShield()
	refreshShockCooldown()
	refreshShockRange()
	refreshShockMana()
end

-- Layout edits used by the options window. Each leaves db.groups consistent and relays out.
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return end
		fn(...)
		pruneGroups()
		layoutElements()
	end
end

-- Puts key into target (a group index or "new"). index is its position among the target's other
-- members; nil appends.
local placeElement = edit(function(key, target, index)
	local gi = findElement(key)
	local src = gi and db.groups[gi]
	if target == "new" then
		if src and #src.members == 1 then return end
		removeElement(key)
		local g = newGroup(src or db.groups[1])
		g.members = { key }
		-- Screen centre, stepping down past any group already parked there.
		g.point, g.x, g.y = "CENTER", 0, 0
		local taken = true
		while taken do
			taken = false
			for _, o in ipairs(db.groups) do
				if o ~= g and o.point == "CENTER" and o.x == g.x and o.y == g.y then taken = true end
			end
			if taken then g.y = g.y - 60 end
		end
	elseif db.groups[target] then
		local g = db.groups[target]
		local list = {}
		for _, k in ipairs(g.members) do if k ~= key then table.insert(list, k) end end
		index = math.min(math.max(index or #list + 1, 1), #list + 1)
		table.insert(list, index, key)
		removeElement(key)
		g.members = list
	end
end)

-- Splits a group into single-element groups, each left exactly where it is on screen.
local splitGroup = edit(function(gi)
	local g = db.groups[gi]
	if not g or #g.members < 2 then return end
	for i = #g.members, 2, -1 do
		local key = g.members[i]
		local sx, sy = screenCenter(ELEMENTS[key].frame)
		table.remove(g.members, i)
		local ng = newGroup(g)
		ng.members = { key }
		if sx then setGroupCenter(ng, sx, sy) end
	end
	local sx, sy = screenCenter(ELEMENTS[g.members[1]].frame)
	if sx then setGroupCenter(g, sx, sy) end
end)

local setShow = edit(function(key, mode) elementOpts(key).show = mode ~= "always" and mode or nil end)

-- Hides every element in the group; the group keeps them, so showing one brings it back in place.
local hideGroup = edit(function(gi)
	for _, key in ipairs(db.groups[gi] and db.groups[gi].members or {}) do elementOpts(key).show = "never" end
end)
local centerGroup = edit(function(gi)
	local g = db.groups[gi]
	if g then g.point, g.x, g.y = "CENTER", 0, 0 end
end)

local function resetAll()
	for k, v in pairs(DEFAULTS) do db[k] = type(v) == "table" and CopyTable(v) or v end
	sanitize()
	resolveSpells(); applyLayout(); refreshAll()
end

-- Shared with ShamanForever_Options.lua
ns.DEFAULTS, ns.GROUP_DEFAULTS, ns.SHOCKS, ns.SHOCK_ORDER = DEFAULTS, GROUP_DEFAULTS, SHOCKS, SHOCK_ORDER
ns.ELEMENTS, ns.ELEMENT_KEYS, ns.available, ns.findElement = ELEMENTS, ELEMENT_KEYS, available, findElement
ns.getDB = function() return db end
ns.applyLayout, ns.resolveSpells, ns.refreshAll, ns.elementOpts = applyLayout, resolveSpells, refreshAll, elementOpts
ns.placeElement, ns.splitGroup, ns.hideGroup, ns.centerGroup = placeElement, splitGroup, hideGroup, centerGroup
ns.setShow, ns.showMode = setShow, showMode
ns.setTestMode = function(on) edit(setTestMode)(on) end
ns.resetAll = resetAll
ns.say = say

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(event, unit)
	local ok = pcall(function()
		if unit then ev:RegisterUnitEvent(event, unit) else ev:RegisterEvent(event) end
	end)
	if not ok then say("event %s not available on this client", event) end
end

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		ShamanForeverDB = ShamanForeverDB or {}
		db = ShamanForeverDB
		-- Pre-groups saves: one row or column, with hidden elements in db.enabled.
		if db.groups == nil and (db.order or db.point) then
			local g = {}
			for k, v in pairs(GROUP_DEFAULTS) do if db[k] ~= nil then g[k] = db[k] else g[k] = v end end
			g.members, db.known = {}, {}
			for _, key in ipairs(db.order or { "shield", "shock" }) do
				db.known[key] = true
				if not (db.enabled and db.enabled[key] == false) then table.insert(g.members, key) end
			end
			db.groups = { g }
		end
		for _, k in ipairs(LEGACY_KEYS) do db[k] = nil end
		-- 1: snapping and the grid briefly defaulted to on during 0.2.0 development; start them off
		-- once, after which the saved choice is kept.
		if (db.settingsVersion or 0) < 1 then db.snap, db.grid = false, false end
		-- 2: "only show in combat" moved from the whole display to each group (and element).
		if (db.settingsVersion or 0) < 2 then
			if db.combatOnly and type(db.groups) == "table" then
				for _, g in ipairs(db.groups) do g.combatOnly = true end
			end
			db.combatOnly = nil
		end
		-- 3: per-element "only in combat" became the element's show mode (always | combat | never).
		-- Elements hidden by being in no group are placed by sanitize below, set to never.
		if (db.settingsVersion or 0) < 3 and type(db.elementOpts) == "table" then
			for _, o in pairs(db.elementOpts) do
				if o.combatOnly then o.show = "combat" end
				o.combatOnly = nil
			end
		end
		db.settingsVersion = SETTINGS_VERSION
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
		end
		sanitize()
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "PLAYER_LOGIN" then
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then root:Hide(); return end
		isShaman = true
		reg("UNIT_AURA", "player")
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("SPELL_UPDATE_USABLE")
		reg("UNIT_POWER_UPDATE", "player")
		reg("PLAYER_TARGET_CHANGED")
		reg("SPELLS_CHANGED")
		reg("PLAYER_REGEN_ENABLED")
		reg("SPELL_RANGE_CHECK_UPDATE")
		resolveSpells()
		applyLayout()
		refreshAll()
		C_Timer.NewTicker(0.25, refreshShockRange)
		root:Show()
	elseif event == "UNIT_AURA" then
		refreshShield()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3   -- args: unit, castGUID, spellID
		if not isSecret(spellID) and (spellID == shieldSpellID or spellID == shieldAuraSpellID) then
			setBelievedUp(true)  -- our own cast events stay readable in combat
		end
		refreshShockCooldown()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		refreshShockCooldown()
	elseif event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then
		refreshShockMana()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "SPELL_RANGE_CHECK_UPDATE" then
		refreshShockRange()
	elseif event == "SPELLS_CHANGED" then
		resolveSpells()
		applyLayout()
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if layoutPending then layoutElements() end
		if nativeStylePending then styleNative() end
		refreshAll()
	end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_SHAMANFOREVER1 = "/sf"
SLASH_SHAMANFOREVER2 = "/shf"
SlashCmdList.SHAMANFOREVER = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		if ns.ToggleOptions then ns.ToggleOptions() else say("options window unavailable") end
	elseif cmd == "lock" then db.locked = true; applyLayout(); say("locked")
	elseif cmd == "unlock" then db.locked = false; applyLayout(); say("unlocked: drag groups to move them")
	elseif cmd == "test" then
		ns.setTestMode(not db.testMode)
		say("test elements %s", db.testMode and "on" or "off")
	elseif cmd == "debug" then
		say("shield spell %s (aura spell %s), shock spell %s (%s), mana spell %s, believed up %s, in combat %s",
			tostring(shieldSpellID), tostring(shieldAuraSpellID), tostring(shockSpellID), db.shock,
			tostring(manaSpellID), tostring(believedUp), tostring(InCombatLockdown()))
		local e = book[SHIELD_NAME]
		say("spellbook: %s rank %s", SHIELD_NAME, e and e.rank or "?")
		say("aura container %s%s", native.container and "created" or "not created",
			native.err and (", error: " .. native.err) or "")
		local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
		say("tracked spell IDs: %s", table.concat(t, ","))
		for key, id in pairs(shockIDs) do
			local ok, usable, noPower = safe(C_Spell.IsSpellUsable, id)
			local _, r = safe(C_Spell.IsSpellInRange, id, "target")
			say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
				book[SHOCKS[key]] and book[SHOCKS[key]].rank or "?", describeArg(usable), describeArg(noPower), describeArg(r))
		end
		for gi, g in ipairs(db.groups) do
			local names = {}
			for _, key in ipairs(g.members) do
				local mode = showMode(key)
				table.insert(names, mode == "always" and key or (key .. " (" .. mode .. ")"))
			end
			say("group %d: %s, %s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", gi, table.concat(names, ","),
				g.orientation, g.scale, g.alpha, g.point, g.x, g.y, g.combatOnly and ", combat only" or "")
		end
	else
		say("/sf opens the options. Also: /sf lock, /sf unlock, /sf test (placeholder elements), /sf debug")
	end
end
