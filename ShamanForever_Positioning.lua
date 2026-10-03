-- Positioning (unlock mode)

local _, ns = ...
local say = ns.say

local PO = {}
ns.Positioning = PO

local selectedGroup
local selectedMovable
local movables = {}
local SNAP = 8   -- UI units
local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
local function uiScale() return UIParent:GetEffectiveScale() end
local function db() return ns.getDB() end
local function acct() return ns.getAccount() end

-- Grid and snap guides
local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid:Hide()
grid.lines = {}

local function drawGrid()
	local w, h = UIParent:GetSize()
	local gs = acct().gridSize
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

-- Dragging, the wheel and clicks
local function snap(frame, x, y)
	local a = acct()
	local gx, gy
	if a.snap then
		local ui = uiScale()
		local w, h = UIParent:GetSize()
		local s = frame:GetEffectiveScale() / ui
		local tx, ty = { w / 2 }, { h / 2 }
		local function target(f)
			if f == frame or not f:IsShown() or not f:GetLeft() then return end
			local fs = f:GetEffectiveScale() / ui
			local l, r, b, t = f:GetLeft() * fs, f:GetRight() * fs, f:GetBottom() * fs, f:GetTop() * fs
			table.insert(tx, l); table.insert(tx, (l + r) / 2); table.insert(tx, r)
			table.insert(ty, b); table.insert(ty, (b + t) / 2); table.insert(ty, t)
		end
		for id, f in pairs(ns.groupFrames) do
			if ns.groupById(id) then target(f) end
		end
		for _, m in ipairs(movables) do target(m.frame) end
		local gs = a.grid and a.gridSize or nil
		x, gx = snapAxis(x, frame:GetWidth() * s / 2, tx, w / 2, gs)
		y, gy = snapAxis(y, frame:GetHeight() * s / 2, ty, h / 2, gs)
	end
	showGuides(gx, gy)
	return x, y
end

-- Dragged by hand rather than with StartMoving so they can snap while moving: moveTo(x, y) takes
-- the moved frame's new centre in UI units
local function dragUpdate(self)
	if InCombatLockdown() then self:SetScript("OnUpdate", nil); showGuides(); return end
	local ui = uiScale()
	local cx, cy = GetCursorPosition()
	self.moveTo(snap(self.moved, cx / ui + self.dragDX, cy / ui + self.dragDY))
end
local function startDrag(handle, moved, moveTo)
	local ui = uiScale()
	local s = moved:GetEffectiveScale() / ui
	local fx, fy = moved:GetCenter()
	local cx, cy = GetCursorPosition()
	handle.moved, handle.moveTo = moved, moveTo
	handle.dragDX, handle.dragDY = fx * s - cx / ui, fy * s - cy / ui
	handle:SetScript("OnUpdate", dragUpdate)
end
local function stopDrag(handle)
	handle:SetScript("OnUpdate", nil)
	showGuides()
end

-- The wheel: opacity (Ctrl), scale (Shift) or the size (size = { key, step, from(c): the value it
-- starts from, if not c[key] }), each kept in its range. Its steps are its own, apart from the sliders'
local function wheel(c, delta, ranges, size)
	local function step(key, by, from)
		local r = ranges[key]
		c[key] = clamp(round2((from or c[key]) + delta * by), r[1], r[2])
	end
	if IsControlKeyDown() then step("alpha", 0.05)
	elseif IsShiftKeyDown() then step("scale", 0.05)
	else step(size.key, size.step, size.from and size.from(c)) end
end

local GROUP_SIZE = { key = "size", step = 2, from = function(g)
	if g.sizeFollow then g.sizeFollow = false; return db().iconSize end
end }

function PO.attach(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop(ns.BACKDROP)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	local function moveTo(x, y)
		local g = ns.groupById(f.groupId)
		if not g then return end
		local ui = uiScale()
		ns.setGroupCenter(g, x * ui, y * ui)
		ns.placeOnPixels(f, "CENTER", g.x, g.y)
	end
	f:SetScript("OnDragStart", function(self)
		if acct().locked or InCombatLockdown() then return end
		PO.select(self.groupId)
		startDrag(self, self, moveTo)
	end)
	f:SetScript("OnDragStop", function(self)
		stopDrag(self)
		if not InCombatLockdown() then ns.layoutElements() end
	end)
	f:SetScript("OnMouseWheel", function(self, delta)
		local g = ns.groupById(self.groupId)
		if acct().locked or InCombatLockdown() or not g then return end
		local sx, sy = ns.screenCenter(self)
		wheel(g, delta, ns.Profiles.GROUP_RANGES, GROUP_SIZE)
		if sx then ns.setGroupCenter(g, sx, sy) end
		ns.layoutElements()
		self.label:SetText(string.format("%s: size %d, scale %.2f, opacity %.0f%%", g.name,
			ns.groupSize(g), g.scale, g.alpha * 100))
	end)
	f:SetScript("OnMouseUp", function(self, button)
		local locked = acct().locked
		if button == "LeftButton" and not locked and not InCombatLockdown() then PO.select(self.groupId) return end
		if button ~= "RightButton" or locked then return end
		local g = ns.groupById(self.groupId)
		if IsShiftKeyDown() and g then
			for _, key in ipairs(g.members) do
				local e = ns.ELEMENTS[key].frame
				if e:IsShown() and e:IsMouseOver() then ns.Options.openElement(key) return end
			end
		end
		ns.Options.openGroup(self.groupId)
	end)
end

-- The border of a mover: gold when selected, blue otherwise
local function paintBorder(f, chosen, unlocked)
	if chosen then f:SetBackdropBorderColor(1, 0.82, 0, 1)
	else f:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0) end
end

function PO.decorate(gf, g)
	local unlocked = not acct().locked
	local chosen = unlocked and selectedGroup == g.id
	gf:EnableMouse(unlocked)
	gf:EnableMouseWheel(unlocked)
	gf:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	paintBorder(gf, chosen, unlocked)
	gf.label:SetText(g.name)
	gf.label:SetShown(unlocked)
end

-- Nudging: the arrow keys move the selected group by 1 (Shift: 10). Keyboard capture is restricted
-- in combat, and a frame left swallowing keys when combat starts would block every key for the
-- fight: only the arrows and Escape are kept, for the key press itself, and the frame hides itself
-- at combat start (always allowed for our own frame).
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local nudger = CreateFrame("Frame", ns.NAME .. "Nudge", UIParent)
nudger:Hide()

local function nudge(key)
	local d = NUDGE_KEYS[key]
	local step = IsShiftKeyDown() and 10 or 1
	if selectedMovable then
		if d then selectedMovable.nudge(d[1] * step, d[2] * step) end
		return
	end
	local g = ns.groupById(selectedGroup)
	local f = selectedGroup and ns.groupFrames[selectedGroup]
	if not (g and d and f) then return end
	g.x = g.x + d[1] * step / g.scale
	g.y = g.y + d[2] * step / g.scale
	ns.placeOnPixels(f, g.point, g.x, g.y)
end

local function syncNudger()
	local on = (selectedGroup ~= nil or selectedMovable ~= nil) and not acct().locked and not InCombatLockdown()
	if on and not nudger.keys then
		-- Out of combat only (restricted in combat), so not at file load: a /reload in combat would lose them
		nudger:EnableKeyboard(true)
		nudger:SetPropagateKeyboardInput(true)
		nudger.keys = true
	end
	if on then nudger:Show() else nudger:Hide() end
end

function PO.select(id)
	if selectedGroup == id and not selectedMovable then return end
	selectedGroup, selectedMovable = id, nil
	syncNudger()
	ns.layoutElements()
end

-- A frame that moves on its own (a bar). m: frame, nudge(dx, dy), lock()
-- (combat started while unlocked)
-- bar: the key it registered under
function PO.addMovable(m, bar)
	m.bar = bar
	table.insert(movables, m)
end
local function selectMovable(m)
	if selectedMovable == m then return end
	selectedGroup, selectedMovable = nil, m
	syncNudger()
	ns.layoutElements()
end

-- A bar's mover: a box over it while unlocked that drags (snapping), wheels, nudges and locks it.
-- spec: frame (the bar), label, cfg() (point, x, y, scale, alpha), ranges, size (the plain wheel,
-- as wheel() takes it), shown() (it can be placed now), place() (lay it out again), describe() (the
-- label after a wheel step), lock() (combat started). A right-click opens the bar's page.
-- Returns the movable for ns.registerBar, with update() for the bar's layout.
function PO.mover(spec)
	local f = spec.frame
	local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	m:SetFrameStrata("DIALOG")
	-- Stays on screen when its bar isn't, so a drag from it can bring the bar back
	m:SetClampedToScreen(true)
	m:SetBackdrop(ns.BACKDROP)
	m:SetBackdropColor(0, 0, 0, 0.4)
	m:EnableMouse(true)
	m:EnableMouseWheel(true)
	m:RegisterForDrag("LeftButton")
	m:Hide()
	m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	m.label:SetPoint("BOTTOMLEFT", m, "TOPLEFT", 0, 2)
	local movable = { frame = f }
	local function place()
		local c = spec.cfg()
		ns.placeOnPixels(f, c.point, c.x / c.scale, c.y / c.scale)
	end
	local function moveTo(x, y)
		local c = spec.cfg()
		local ux, uy = UIParent:GetCenter()
		c.point, c.x, c.y = "CENTER", x - ux, y - uy
		place()
	end
	function movable.nudge(dx, dy)
		local c = spec.cfg()
		c.x, c.y = c.x + dx, c.y + dy
		place()
	end
	function movable.lock()
		stopDrag(m)
		m:Hide()
		spec.lock()
	end
	function movable.update()
		local on = spec.shown() and not acct().locked and not InCombatLockdown()
		if on then
			m:ClearAllPoints()
			m:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
			m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
			paintBorder(m, selectedMovable == movable, true)
			m.label:SetText(spec.label)
		end
		m:SetShown(on)
	end
	m:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		selectMovable(movable)
		startDrag(self, f, moveTo)
	end)
	m:SetScript("OnDragStop", function(self)
		stopDrag(self)
		if not InCombatLockdown() then spec.place() end
	end)
	m:SetScript("OnMouseUp", function(_, button)
		if InCombatLockdown() then return end
		if button == "LeftButton" then selectMovable(movable)
		elseif button == "RightButton" then ns.Options.open(movable.bar) end
	end)
	m:SetScript("OnMouseWheel", function(self, delta)
		if InCombatLockdown() then return end
		wheel(spec.cfg(), delta, spec.ranges, spec.size)
		spec.place()
		self.label:SetText(spec.describe())
		ns.changed()
	end)
	return movable
end

nudger:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then self:Hide() return end
	if NUDGE_KEYS[key] or key == "ESCAPE" then
		self:SetPropagateKeyboardInput(false)
		C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
		if key == "ESCAPE" then PO.select(nil) return end
		nudge(key)
		self.held, self.wait = key, 0.4
	end
end)
nudger:SetScript("OnKeyUp", function(self, key)
	if key == self.held then self.held = nil end
end)
nudger:SetScript("OnUpdate", function(self, elapsed)
	if not self.held then return end
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		nudge(self.held)
		self.wait = 0.04
	end
end)
nudger:SetScript("OnHide", function(self) self.held = nil end)
-- Hidden at the start of combat, back after
ns.onCombatStart(function()
	nudger:Hide()
	if ns.isActive() and not acct().locked then
		PO.lockInCombat()
		say("positioning locked for combat")
	end
end)
ns.onCombatEnd(syncNudger)

-- The bar while unlocked
local wasUnlocked = false
local tray = ns.floatingPanel(ns.NAME .. "Tray", 560, 120, { 0.2, 0.6, 1, 0.9 })
tray:SetPoint("TOP", UIParent, "TOP", 0, -120)
do
	local title = tray:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText(ns.NAME .. ": positioning unlocked")
	local HELP = {
		{ "Drag" },   -- what it moves: PO.update, once the bars have registered
		{ "Click, then arrow keys", "Nudge a group (Shift: 10x)" },
		{ "Mouse wheel", "Icon size: borders not scaled with it" },
		{ "Shift + wheel", "Scale: everything grows, borders too" },
		{ "Ctrl + wheel", "Opacity" },
		{ "Right-click", "The group's settings" },
		{ "Shift + right-click", "The settings of the element under the cursor" },
	}
	local LINE_H, KEY_W = 16, 150
	tray.hint = CreateFrame("Frame", nil, tray)
	tray.hint:SetPoint("TOPLEFT", 10, -30)
	tray.hint:SetSize(540, #HELP * LINE_H)
	for i, h in ipairs(HELP) do
		local key = tray.hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		key:SetPoint("TOPLEFT", 0, -(i - 1) * LINE_H)
		key:SetText(h[1])
		local what = tray.hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		what:SetPoint("TOPLEFT", KEY_W, -(i - 1) * LINE_H)
		what:SetText(h[2])
		if i == 1 then tray.drag = what end
	end
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
		cb:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			acct()[key] = on
			ns.layoutElements()
		end)
		ns.setTip(cb, label, tip, "ANCHOR_BOTTOM")
		return cb
	end
	tray.snap = check("Snapping", "snap", "While dragging, groups snap to other groups' edges and centres, the screen centre, and the grid when it is shown.")
	tray.snap:SetPoint("LEFT", -4, 0)
	tray.grid = check("Show grid", "grid", "A grid over the whole screen while unlocked. With snapping on, groups snap to it.")
	tray.grid:SetPoint("LEFT", tray.snap.Text, "RIGHT", 16, 0)
	local function stepper(text, delta)
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetSize(22, 20)
		b:SetText(text)
		b:SetScript("OnClick", function()
			local a = acct()
			a.gridSize = math.min(math.max(a.gridSize + delta, 8), 128)
			ns.layoutElements()
		end)
		return b
	end
	tray.gridLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tray.gridLabel:SetPoint("LEFT", tray.grid.Text, "RIGHT", 16, 0)
	tray.gridLabel:SetText("Grid size")
	tray.gridDown = stepper("-", -4)
	tray.gridDown:SetPoint("LEFT", tray.gridLabel, "RIGHT", 6, 0)
	tray.gridValue = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tray.gridValue:SetPoint("LEFT", tray.gridDown, "RIGHT", 4, 0)
	tray.gridValue:SetWidth(26)
	tray.gridUp = stepper("+", 4)
	tray.gridUp:SetPoint("LEFT", tray.gridValue, "RIGHT", 4, 0)
	local lock = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	lock:SetSize(70, 22)
	lock:SetPoint("RIGHT", 0, 0)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() ns.setLocked(true) end)
	tray.options = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	tray.options:SetSize(110, 22)
	tray.options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	tray.options:SetScript("OnClick", function() ns.Options.toggleAside("layout") end)
	ns.setTip(tray.options, function() return tray.options:GetText() end,
		"The options stay shown or hidden the next time you unlock.", "ANCHOR_BOTTOM")
end

function PO.optionsShown(shown)
	tray.options:SetText(shown and "Hide options" or "Show options")
end
PO.optionsShown(false)

local function stepOptionsAside(unlocked)
	if unlocked == wasUnlocked then return end
	wasUnlocked = unlocked
	if unlocked then ns.Options.stepAside("positioning") else ns.Options.comeBack("positioning") end
end

function PO.update()
	local a = acct()
	local unlocked = ns.isActive() and not a.locked
	if not unlocked then selectedGroup, selectedMovable = nil, nil end
	if selectedGroup and not ns.groupById(selectedGroup) then selectedGroup = nil end
	syncNudger()
	tray:SetShown(unlocked)
	if unlocked then tray.drag:SetText("Move " .. ns.Look.movingWords("a group", "or")) end
	tray:SetHeight(30 + tray.hint:GetHeight() + 10 + 26 + 8)
	tray.snap:SetChecked(a.snap)
	PO.optionsShown(ns.Options.isShown())
	stepOptionsAside(unlocked)
	tray.grid:SetChecked(a.grid)
	tray.gridValue:SetText(a.gridSize)
	grid:SetShown(unlocked and a.grid)
	if unlocked and a.grid then drawGrid() end
	if not unlocked then showGuides() end
end

-- Combat locks positioning. Showing, moving and mouse changes on group frames are dropped in combat
-- (a group can hold Blizzard's protected aura button), so only the looks change; the full
-- layout runs when combat ends. Groups stop taking the mouse, or they would eat clicks, camera
-- drags and wheel zoom for the whole fight.
function PO.lockInCombat()
	acct().locked = true
	ns.Options.comeBack("positioning", true)
	selectedGroup, selectedMovable = nil, nil
	local free = not InCombatLockdown()
	for _, gf in pairs(ns.groupFrames) do
		if free then gf:EnableMouse(false); gf:EnableMouseWheel(false) end
		gf:SetScript("OnUpdate", nil)
		gf:SetBackdropColor(0, 0, 0, 0)
		gf:SetBackdropBorderColor(0, 0, 0, 0)
		gf.label:Hide()
	end
	showGuides()
	PO.update()
	ns.retryAfterCombat("layout", ns.layoutElements)
	for _, m in ipairs(movables) do m.lock() end
	ns.changed()
end
