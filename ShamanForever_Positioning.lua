-- Positioning (unlock mode): drag a group to move it (snapping to the grid and to other groups), the
-- mouse wheel for its size, scale and opacity, the arrow keys to nudge it, right-click for its
-- settings, and a small bar with the controls. Group membership is edited in the options window.
--
-- ShamanForever.lua owns the groups and lays them out; it hands each group frame here once
-- (PO.attach), and calls PO.decorate on every layout and PO.update after it.

local _, ns = ...
local say = ns.say

local PO = {}
ns.Positioning = PO

local selectedGroup       -- the group the arrow keys move (see Nudging)
local SNAP = 8   -- UI units: how close an edge must come to another group's edge or centre to snap
local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
local function uiScale() return UIParent:GetEffectiveScale() end
local function db() return ns.getDB() end
local function acct() return ns.getAccount() end

------------------------------------------------------------------------
-- Grid and snap guides
------------------------------------------------------------------------
-- Grid over the whole screen while unlocked, measured from the screen centre in UIParent units.
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

------------------------------------------------------------------------
-- Dragging, the mouse wheel and clicks on a group
------------------------------------------------------------------------
-- Groups are dragged by hand rather than with StartMoving so they can snap while moving.
local function dragUpdate(self)
	if InCombatLockdown() then self:SetScript("OnUpdate", nil); showGuides(); return end
	local a = acct()
	local ui = uiScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx / ui + self.dragDX, cy / ui + self.dragDY
	local gx, gy
	if a.snap then
		local w, h = UIParent:GetSize()
		local s = self:GetEffectiveScale() / ui
		local tx, ty = { w / 2 }, { h / 2 }
		for gi, f in ipairs(ns.groupFrames) do
			if gi ~= self.index and gi <= #db().groups and f:IsShown() and f:GetLeft() then
				local fs = f:GetEffectiveScale() / ui
				local l, r, b, t = f:GetLeft() * fs, f:GetRight() * fs, f:GetBottom() * fs, f:GetTop() * fs
				table.insert(tx, l); table.insert(tx, (l + r) / 2); table.insert(tx, r)
				table.insert(ty, b); table.insert(ty, (b + t) / 2); table.insert(ty, t)
			end
		end
		local gs = a.grid and a.gridSize or nil
		x, gx = snapAxis(x, self:GetWidth() * s / 2, tx, w / 2, gs)
		y, gy = snapAxis(y, self:GetHeight() * s / 2, ty, h / 2, gs)
	end
	showGuides(gx, gy)
	local g = db().groups[self.index]
	ns.setGroupCenter(g, x * ui, y * ui)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", g.x, g.y)
end

-- A new group frame: its outline, label and the unlock-mode handlers.
function PO.attach(f)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop(ns.BACKDROP)
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f:SetScript("OnDragStart", function(self)
		if acct().locked or InCombatLockdown() then return end
		PO.select(self.index)
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
		if not InCombatLockdown() then ns.layoutElements() end
	end)
	-- Wheel: icon size (lines stay crisp); Ctrl: scale (everything grows, lines too); Shift: opacity.
	f:SetScript("OnMouseWheel", function(self, delta)
		if acct().locked or InCombatLockdown() then return end
		local g = db().groups[self.index]
		local sx, sy = ns.screenCenter(self)
		if IsShiftKeyDown() then g.alpha = clamp(round2(g.alpha + delta * 0.05), 0.1, 1)
		elseif IsControlKeyDown() then g.scale = clamp(round2(g.scale + delta * 0.05), 0.5, 3)
		else
			if g.sizeFollow then g.sizeFollow, g.size = false, db().iconSize end   -- its own from here on
			g.size = clamp(g.size + delta * 2, 24, 96)
		end
		if sx then ns.setGroupCenter(g, sx, sy) end   -- grow about the centre, not the anchor
		ns.layoutElements()
		self.label:SetText(string.format("Group %d: size %d, scale %.2f, opacity %.0f%%", self.index,
			ns.groupSize(g), g.scale, g.alpha * 100))
	end)
	-- Right-click: the group's settings. Shift-right-click: the settings of the element under the cursor.
	f:SetScript("OnMouseUp", function(self, button)
		local locked = acct().locked
		if button == "LeftButton" and not locked and not InCombatLockdown() then PO.select(self.index) return end
		if button ~= "RightButton" or locked then return end
		if IsShiftKeyDown() then
			for _, key in ipairs(db().groups[self.index].members) do
				local e = ns.ELEMENTS[key].frame
				if e:IsShown() and e:IsMouseOver() then ns.Options.openElement(key) return end
			end
		end
		ns.Options.open("layout", self.index)
	end)
end

-- On every layout: the outline, label and mouse while unlocked, nothing while locked.
function PO.decorate(gf, gi)
	local unlocked = not acct().locked
	gf:EnableMouse(unlocked)
	gf:EnableMouseWheel(unlocked)
	gf:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	if unlocked and selectedGroup == gi then gf:SetBackdropBorderColor(1, 0.82, 0, 1)
	else gf:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0) end
	gf.label:SetText(unlocked and selectedGroup == gi and ("Group " .. gi .. " (arrow keys move it)") or ("Group " .. gi))
	gf.label:SetShown(unlocked)
end

------------------------------------------------------------------------
-- Nudging: while unlocked, the arrow keys move the selected group by 1 (Shift: 10), repeating while
-- held; Escape deselects. Out of combat only, like dragging. Keyboard capture is restricted in combat
-- (EnableKeyboard is protected, SetPropagateKeyboardInput restricted), and a frame left swallowing
-- keys when combat starts would block every key for the fight. So: only the arrows (and Escape) are
-- kept, and only for the key press itself (propagation goes back on the next frame); the frame is
-- shown only while a group is selected out of combat; and it hides itself when combat starts, which
-- is always allowed for our own frame and stops all capture.
------------------------------------------------------------------------
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local nudger = CreateFrame("Frame", "ShamanForeverNudge", UIParent)
nudger:Hide()

local function nudge(key)
	local g, d = selectedGroup and db().groups[selectedGroup], NUDGE_KEYS[key]
	local f = selectedGroup and ns.groupFrames[selectedGroup]
	if not (g and d and f) then return end
	local step = IsShiftKeyDown() and 10 or 1
	g.x = g.x + d[1] * step / g.scale   -- offsets are in the group's scaled units
	g.y = g.y + d[2] * step / g.scale
	f:ClearAllPoints()
	f:SetPoint(g.point, UIParent, g.point, g.x, g.y)
end

local function syncNudger()
	local on = selectedGroup ~= nil and not acct().locked and not InCombatLockdown()
	if on and not nudger.keys then
		-- Out of combat only (both are restricted in combat), so not at file load: a /reload in
		-- combat would lose them for the session.
		nudger:EnableKeyboard(true)
		nudger:SetPropagateKeyboardInput(true)
		nudger.keys = true
	end
	if on then nudger:Show() else nudger:Hide() end
end

function PO.select(gi)
	if selectedGroup == gi then return end
	selectedGroup = gi
	syncNudger()
	ns.layoutElements()
end

-- The groups were renumbered (layout edits): the selection, an index, would jump to another group.
function PO.clearSelection()
	selectedGroup = nil
	syncNudger()
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
-- Hidden frames still get events: hide at the start of combat, come back after it.
nudger:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		self:Hide()
		if ns.isActive() and not acct().locked then PO.lockInCombat(); say("positioning locked for combat") end
	else syncNudger() end
end)
ns.registerEvent(nudger, "PLAYER_REGEN_DISABLED")
ns.registerEvent(nudger, "PLAYER_REGEN_ENABLED")

------------------------------------------------------------------------
-- The bar while unlocked: what the mouse does, snapping and grid toggles, Lock and Options.
------------------------------------------------------------------------
local wasUnlocked, optionsSteppedAside = false, false   -- see stepOptionsAside
local tray = CreateFrame("Frame", "ShamanForeverTray", UIParent, "BackdropTemplate")
tray:SetSize(560, 120)
tray:SetFrameStrata("DIALOG")
tray:SetPoint("TOP", UIParent, "TOP", 0, -120)
tray:SetMovable(true)
tray:SetClampedToScreen(true)
tray:EnableMouse(true)
tray:RegisterForDrag("LeftButton")
tray:SetScript("OnDragStart", tray.StartMoving)
tray:SetScript("OnDragStop", tray.StopMovingOrSizing)
tray:SetBackdrop(ns.BACKDROP)
tray:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
tray:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
tray:Hide()
do
	local title = tray:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("ShamanForever: positioning unlocked")
	tray.hint = tray:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tray.hint:SetPoint("TOPLEFT", 10, -30)
	tray.hint:SetWidth(540)
	tray.hint:SetJustifyH("LEFT")
	tray.hint:SetSpacing(2)
	tray.hint:SetText("Drag a group to move it, or click it and use the arrow keys (Shift: 10x).\n" ..
		"Mouse wheel over a group: icon size (borders stay crisp).\n" ..
		"Ctrl + wheel: scale (everything grows, borders too). Shift + wheel: opacity.\n" ..
		"Right-click a group: its settings.\n" ..
		"Shift-right-click an element: its own settings.\n" ..
		"Options: choose which elements each group holds.")
	-- Controls sit on a row under the hint, so a longer hint pushes them down instead of overlapping.
	local row = CreateFrame("Frame", nil, tray)
	row:SetPoint("TOPLEFT", tray.hint, "BOTTOMLEFT", 0, -10)
	row:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row:SetHeight(26)
	tray.row = row
	local function check(label, key, tip, parent, after)
		local cb = CreateFrame("CheckButton", nil, parent or row, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb.Text:SetFontObject("GameFontHighlightSmall")
		cb.Text:SetText(label)
		cb:SetScript("OnClick", function(self)
			local on = self:GetChecked() and true or false
			acct()[key] = on
			if after then after(on) end
			ns.layoutElements()
		end)
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
	-- Grid size: - value +, in steps of 4.
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
	lock:SetSize(90, 22)
	lock:SetPoint("RIGHT", 0, 0)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() ns.setLocked(true) end)
	local options = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	options:SetSize(90, 22)
	options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	options:SetText("Options")
	options:SetScript("OnClick", function() ns.Options.open("layout") end)
	local row2 = CreateFrame("Frame", nil, tray)
	row2:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
	row2:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row2:SetHeight(24)
	-- Takes effect at once: ticking brings the window back, unticking puts it away until locking.
	tray.keepOptions = check("Keep options open", "keepOptionsOpen",
		"Unticked, the options window closes while you move groups and comes back when you lock.", row2,
		function(keep)
			if keep then
				optionsSteppedAside = false
				ns.Options.open()
			elseif ns.Options.hide() then
				optionsSteppedAside = true
			end
		end)
	tray.keepOptions:SetPoint("LEFT", -4, 0)
end

-- Unlocking closes the options window (unless the player keeps it open) and locking brings it back.
local function stepOptionsAside(unlocked)
	if unlocked == wasUnlocked then return end
	wasUnlocked = unlocked
	if unlocked then
		optionsSteppedAside = not acct().keepOptionsOpen and ns.Options.hide() or false
	elseif optionsSteppedAside then
		optionsSteppedAside = false
		ns.Options.open()
	end
end

-- After every layout: the bar, grid, guides and nudging follow the lock.
function PO.update()
	local a = acct()
	local unlocked = ns.isActive() and not a.locked
	if not unlocked then selectedGroup = nil end
	if selectedGroup and not db().groups[selectedGroup] then selectedGroup = nil end
	syncNudger()
	tray:SetShown(unlocked)
	tray:SetHeight(30 + tray.hint:GetStringHeight() + 10 + 26 + 2 + 24 + 8)
	tray.snap:SetChecked(a.snap)
	tray.keepOptions:SetChecked(a.keepOptionsOpen)
	stepOptionsAside(unlocked)
	tray.grid:SetChecked(a.grid)
	tray.gridValue:SetText(a.gridSize)
	grid:SetShown(unlocked and a.grid)
	if unlocked and a.grid then drawGrid() end
	if not unlocked then showGuides() end
end

-- Combat locks positioning, and it cannot be unlocked until combat ends (ns.setLocked). Showing,
-- moving and mouse changes on group frames are dropped in combat (the shield's group holds
-- Blizzard's protected aura button), so only the looks change now: bar, grid, guides, outlines,
-- labels and the selection. The full layout runs when combat ends. Called from
-- PLAYER_REGEN_DISABLED, which comes before lockdown: then the groups also stop taking the mouse, or
-- they would eat clicks, camera drags and wheel zoom for the whole fight.
function PO.lockInCombat()
	acct().locked = true
	optionsSteppedAside = false   -- no options window popping up mid-fight
	selectedGroup = nil
	local free = not InCombatLockdown()
	for _, gf in ipairs(ns.groupFrames) do
		if free then gf:EnableMouse(false); gf:EnableMouseWheel(false) end
		gf:SetScript("OnUpdate", nil)
		gf:SetBackdropColor(0, 0, 0, 0)
		gf:SetBackdropBorderColor(0, 0, 0, 0)
		gf.label:Hide()
	end
	showGuides()
	PO.update()
	ns.retryAfterCombat("layout", ns.layoutElements)
	ns.TotemBar.lockInCombat()
	ns.Options.refresh()
end
