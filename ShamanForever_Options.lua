-- Options window, opened with /sf. The entry under Escape > Options > AddOns only points here: the
-- Settings list is built once, so it cannot follow groups being added and removed.
local ADDON, ns = ...

local WIDTH, HEIGHT, NAV_W = 800, 660, 150       -- default size; the window is resizable
local MIN_W, MIN_H, MAX_W, MAX_H = 700, 420, 1600, 1200
local ROW_W = WIDTH - NAV_W - 64                  -- initial row width; rows then follow the window
local LABEL_W = 180
local SLIDER_MAX_W, SLIDER_VALUE_W = 360, 56   -- the value text sits right of the slider

local win
local pages, pageOrder, currentPage = {}, {}, nil
local selectedGroup = 1

local function db() return ns.getDB() end
local function relayout() ns.applyLayout() end
local function respell() ns.resolveSpells(); ns.refreshAll() end

local function setTip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Pages: a scrolling column of rows. Rows can hide themselves; refresh reflows the visible ones
-- and pulls every control's value from the saved settings.
------------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function newPage(key, title, indent)
	local scroll = CreateFrame("ScrollFrame", "ShamanForeverOptionsScroll_" .. key, win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 20, -44)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -34, 14)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, w)
		content:SetWidth(w)
		if ns.RefreshOptions then ns.RefreshOptions() end
	end)
	scroll:Hide()
	local p = setmetatable({ key = key, title = title, indent = indent, scroll = scroll, content = content, items = {} }, Page)
	pages[key] = p
	table.insert(pageOrder, p)
	return p
end

function Page:add(frame, height, shown, refresh)
	table.insert(self.items, { frame = frame, height = height, shown = shown, refresh = refresh })
	return frame
end

function Page:refresh()
	local y = 0
	for _, it in ipairs(self.items) do
		local show = not it.shown or it.shown()
		it.frame:SetShown(show)
		if show then
			if it.refresh then it.refresh() end
			it.frame:ClearAllPoints()
			it.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
			it.frame:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -y)
			y = y + (type(it.height) == "function" and it.height() or it.height)
		end
	end
	self.content:SetHeight(math.max(y, 1))
end

function Page:row(height)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetSize(ROW_W, height)
	return f
end

function Page:label(f, text, tip)
	f:EnableMouse(true)
	setTip(f, text, tip)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

function Page:header(text, shown, note)
	local f = self:row(36)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.text:SetPoint("BOTTOMLEFT", 0, 7)
	f.text:SetText(text)
	if note then
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 10, 1)
		f.note:SetText(note)
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.3)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
	return self:add(f, 36, shown)
end

-- Wraps to the page width; the row grows to fit. str may be a function, re-read on every refresh.
function Page:text(str, shown)
	local f = self:row(20)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetPoint("TOPLEFT", 4, -4)
	f.text:SetJustifyH("LEFT")
	f.text:SetSpacing(2)
	return self:add(f, function() return f.text:GetStringHeight() + 12 end, shown, function()
		f.text:SetWidth(self.content:GetWidth() - 8)
		f.text:SetText(type(str) == "function" and str() or str)
	end)
end

function Page:checkbox(label, tip, get, set, shown)
	local f = self:row(30)
	local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("LEFT", 0, 0)
	cb.Text:SetFontObject("GameFontHighlight")
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	setTip(cb, label, tip)
	return self:add(f, 30, shown, function() cb:SetChecked(get() and true or false) end)
end

function Page:slider(label, tip, minV, maxV, step, fmt, get, set, shown)
	local f = self:row(34)
	self:label(f, label, tip)
	local s = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	s:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	local updating = true
	s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5),
		{ [MinimalSliderWithSteppersMixin.Label.Right] = fmt })
	updating = false
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		v = math.floor(v / step + 0.5) * step
		if step < 1 then v = tonumber(string.format("%.2f", v)) end
		set(v)
	end, s)
	return self:add(f, 34, shown, function()
		-- Fit the page width so the value text never runs past the edge of a narrow window.
		s:SetWidth(math.max(math.min(self.content:GetWidth() - LABEL_W - SLIDER_VALUE_W, SLIDER_MAX_W), 80))
		updating = true
		s:SetValue(get() or minV)
		updating = false
	end)
end

-- choices: list of { value, text }, or a function returning one
function Page:dropdown(label, tip, choices, get, set, shown, width)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dd:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	dd:SetWidth(width or 200)
	dd:SetupMenu(function(_, rootDescription)
		for _, c in ipairs(type(choices) == "function" and choices() or choices) do
			rootDescription:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
		end
	end)
	return self:add(f, 34, shown, function() dd:GenerateMenu() end)
end

-- A button whose text follows the settings, e.g. Unlock / Lock.
function Page:button(textFn, onClick, tip, width, shown)
	local f = self:row(32)
	local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btn:SetSize(width or 160, 22)
	btn:SetPoint("LEFT", 0, 0)
	btn:SetScript("OnClick", onClick)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(textFn())
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return self:add(f, 32, shown, function() btn:SetText(textFn()) end)
end

-- list: { { text, onClick, tip, width }, ... }
function Page:buttons(list, shown)
	local f = self:row(32)
	local x = 0
	for _, b in ipairs(list) do
		local w = b[4] or 140
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(w, 22)
		btn:SetPoint("LEFT", x, 0)
		btn:SetText(b[1])
		btn:SetScript("OnClick", b[2])
		setTip(btn, b[1], b[3])
		x = x + w + 6
	end
	return self:add(f, 32, shown)
end

------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
local function pct(v) return string.format("%.0f%%", v * 100) end
local function times(v) return string.format("%.2fx", v) end
local function int(v) return string.format("%d", v) end

local function get(key) return function() return db()[key] end end
local function set(key, after) return function(v) db()[key] = v; (after or relayout)() end end

local function groupCount() return #db().groups end
local function hasGroups() return groupCount() > 0 end
local function selected()
	local n = groupCount()
	if selectedGroup > n then selectedGroup = n end
	if selectedGroup < 1 then selectedGroup = 1 end
	return db().groups[selectedGroup]
end
local function groupGet(key) return function() local g = selected(); return g and g[key] end end
local function groupSet(key) return function(v) local g = selected(); if g then g[key] = v; relayout() end end end

------------------------------------------------------------------------
-- Page contents
------------------------------------------------------------------------
local function buildGeneral(p)
	p:header("Display")
	p:button(function() return db().locked and "Unlock layout" or "Lock layout" end,
		function() db().locked = not db().locked; relayout() end,
		"Unlocked, groups can be dragged on screen (they snap to the grid and to each other), scaled with the mouse wheel and faded with shift + wheel. Lock when done so clicks pass through.")
	p:slider("Global icon size", "Base size of every element, in pixels before scaling. Size is shared by all elements; each group's scale then multiplies it.", 24, 96, 1, int,
		get("iconSize"), set("iconSize"))

	p:header("Cooldown numbers")
	p:checkbox("Show countdown", "Countdown numbers on every cooldown (Shock and the cooldown elements).", get("cdText"), set("cdText"))
	p:slider("Countdown text size", "Font size of the countdown numbers. A totem's active time uses a smaller size of the same font.",
		8, 48, 1, int, get("cdTextSize"), set("cdTextSize"))

	p:header("Beta: Issue Reporter", function() return ns.hasIssueReporter and ns.hasIssueReporter() end)
	p:text("Blizzard's Issue Reporter button forgets where you put it on this beta. Shaman Forever remembers it: drag it once and it stays there.",
		function() return ns.hasIssueReporter and ns.hasIssueReporter() end)
	p:checkbox("Hide the Issue Reporter", "Hides Blizzard's beta Issue Reporter button. Turn this off to bring it back; /ptr still works while it is hidden.",
		get("hideIssueReporter"), function(v) db().hideIssueReporter = v; ns.applyIssueReporter() end,
		function() return ns.hasIssueReporter and ns.hasIssueReporter() end)

	p:header("Testing")
	p:checkbox("Test elements", "Adds five coloured placeholder elements (A to E, including a wide and a tall one) in their own group, for trying out layouts. Turning this off removes them.",
		get("testMode"), function(v) ns.setTestMode(v) end)

	p:header("Reset")
	p:buttons({ { "Reset everything", function() StaticPopup_Show("SHAMANFOREVER_RESET") end,
		"Restores every option and the default layout.", 160 } })
end

------------------------------------------------------------------------
-- Group board (Layout page): one card per group plus "New group". Drag an element's chip onto a card
-- to move it there, at the position the blue line shows; click a chip for a menu. Hidden elements
-- stay in their group, dimmed.
------------------------------------------------------------------------
local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" }, { "never", "Never" } }
local SHOW_TIP = "When the element is drawn. Never keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups can also be set to show only in combat on the Layout page; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked."

local CARD_GAP, CHIP_H, CARD_HEAD = 8, 26, 28
local board = { cards = {}, chips = {} }

local function cardUnderCursor()
	for _, c in ipairs(board.cards) do
		if c:IsShown() and c:IsMouseOver() then return c end
	end
end

-- Position among the card's other chips that the cursor points at (chips run top to bottom).
local function dropIndex(c, key)
	local _, cy = GetCursorPosition()
	local at, n, others = 1, 0, {}
	for _, chip in ipairs(c.chips) do
		if chip.key ~= key then
			n = n + 1
			others[n] = chip
			local _, y = chip:GetCenter()
			if y and y * chip:GetEffectiveScale() > cy then at = n + 1 end
		end
	end
	return at, others
end

local function cardBorder(c)
	if board.dragKey and c == board.hover then c:SetBackdropBorderColor(1, 0.82, 0, 1)
	elseif type(c.target) == "number" and c.target == selectedGroup then c:SetBackdropBorderColor(0.2, 0.6, 1, 1)
	else c:SetBackdropBorderColor(0.35, 0.35, 0.4, 1) end
end

local function updateDragFeedback()
	board.hover = cardUnderCursor()
	for _, c in ipairs(board.cards) do cardBorder(c) end
	local ind, c = board.indicator, board.hover
	ind:Hide()
	if not (c and type(c.target) == "number") then return end
	local at, others = dropIndex(c, board.dragKey)
	ind:ClearAllPoints()
	if #others == 0 then
		ind:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -CARD_HEAD + 1)
		ind:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -CARD_HEAD + 1)
	elseif at <= #others then
		ind:SetPoint("BOTTOMLEFT", others[at], "TOPLEFT", 0, 0)
		ind:SetPoint("BOTTOMRIGHT", others[at], "TOPRIGHT", 0, 0)
	else
		ind:SetPoint("TOPLEFT", others[#others], "BOTTOMLEFT", 0, 0)
		ind:SetPoint("TOPRIGHT", others[#others], "BOTTOMRIGHT", 0, 0)
	end
	ind:Show()
end

local function startDrag(chip)
	if InCombatLockdown() then ns.say("layout changes wait until combat ends"); return end
	board.dragKey = chip.key
	chip:SetAlpha(0.35)
	local e = ns.ELEMENTS[chip.key]
	e.paint(board.ghost.icon)
	board.ghost.text:SetText(e.label)
	board.ghost:Show()
end

local function finishDrag()
	local key = board.dragKey
	board.dragKey = nil
	board.dragEnded = GetTime()
	board.ghost:Hide()
	board.indicator:Hide()
	if not key then return end
	local c = cardUnderCursor()
	if c then
		if type(c.target) == "number" then ns.placeElement(key, c.target, (dropIndex(c, key)))
		else ns.placeElement(key, c.target) end
	end
	ns.RefreshOptions()   -- also restores the dimmed chip when nothing moved
end

local function chipMenu(chip)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	if board.dragEnded and GetTime() - board.dragEnded < 0.3 then return end   -- the release that ended a drag
	local key = chip.key
	MenuUtil.CreateContextMenu(chip, function(_, root)
		root:CreateTitle(ns.ELEMENTS[key].label)
		root:CreateButton("Open settings", function() ns.OpenElementOptions(key) end)
		root:CreateDivider()
		local gi, i = ns.findElement(key)
		if gi and i > 1 then root:CreateButton("Move earlier", function() ns.placeElement(key, gi, i - 1) end) end
		if gi and i < #db().groups[gi].members then root:CreateButton("Move later", function() ns.placeElement(key, gi, i + 1) end) end
		for g = 1, groupCount() do
			if g ~= gi then root:CreateButton("Move to group " .. g, function() ns.placeElement(key, g) end) end
		end
		if not (gi and #db().groups[gi].members == 1) then
			root:CreateButton("Move to a new group", function() ns.placeElement(key, "new") end)
		end
		root:CreateDivider()
		root:CreateTitle("Show")
		for _, c in ipairs(SHOW_CHOICES) do
			root:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
		end
	end)
end

local function getCard(i)
	local c = board.cards[i]
	if c then return c end
	c = CreateFrame("Button", nil, board.frame, "BackdropTemplate")
	c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	c:SetBackdropColor(0.1, 0.1, 0.13, 0.9)
	c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.title:SetPoint("TOPLEFT", 8, -8)
	c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.sub:SetPoint("TOPRIGHT", -8, -9)
	c.empty = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.empty:SetPoint("TOPLEFT", 10, -CARD_HEAD - 4)
	c.empty:SetPoint("RIGHT", -10, 0)
	c.empty:SetJustifyH("LEFT")
	c:SetScript("OnClick", function(self)
		if type(self.target) == "number" then selectedGroup = self.target; ns.RefreshOptions() end
	end)
	c.chips = {}
	board.cards[i] = c
	return c
end

local function getChip(i)
	local chip = board.chips[i]
	if chip then return chip end
	chip = CreateFrame("Button", nil, board.frame)
	chip:SetHeight(CHIP_H - 2)
	chip:SetFrameLevel(board.frame:GetFrameLevel() + 10)
	local bg = chip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.06)
	local hl = chip:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(20, 20)
	chip.icon:SetPoint("LEFT", 2, 0)
	chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:RegisterForDrag("LeftButton")
	chip:SetScript("OnClick", chipMenu)
	chip:SetScript("OnDragStart", startDrag)
	chip:SetScript("OnDragStop", finishDrag)
	setTip(chip, "Move element", "Drag onto another group or New group. Drop between elements to set the order. Click for a menu, including when it shows.")
	board.chips[i] = chip
	return chip
end

local function layoutBoard()
	local groups = db().groups
	local colW = (board.page.content:GetWidth() - CARD_GAP) / 2
	local nCard, nChip = 0, 0
	local function fill(target, keys, title, sub, emptyText)
		nCard = nCard + 1
		local c = getCard(nCard)
		c.target = target
		c.title:SetText(title)
		c.sub:SetText(sub or "")
		c.empty:SetText(emptyText or "")
		c.empty:SetShown(#keys == 0)
		wipe(c.chips)
		for i, key in ipairs(keys) do
			nChip = nChip + 1
			local chip = getChip(nChip)
			chip.key = key
			ns.ELEMENTS[key].paint(chip.icon)
			local mode = ns.showMode(key)
			chip.text:SetText(ns.ELEMENTS[key].label .. (mode == "never" and "  |cff888888(hidden)|r"
				or mode == "combat" and "  |cff888888(in combat)|r" or ""))
			chip:SetAlpha(mode == "never" and 0.5 or 1)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -CARD_HEAD - (i - 1) * CHIP_H)
			chip:SetPoint("RIGHT", c, "RIGHT", -6, 0)
			chip:Show()
			c.chips[i] = chip
		end
		local h = CARD_HEAD + math.max(#keys, 1) * CHIP_H + 8
		if #keys == 0 and emptyText then h = h + 12 end
		c:SetSize(colW, h)
		cardBorder(c)
		c:Show()
		return c, h
	end
	local function place(c, x, y)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", board.frame, "TOPLEFT", x, -y)
	end
	-- Groups fill two columns, each card going into the shorter one.
	local colY = { 0, 0 }
	for gi, g in ipairs(groups) do
		local c, h = fill(gi, g.members, "Group " .. gi, g.orientation == "vertical" and "Column" or "Row")
		local col = colY[1] <= colY[2] and 1 or 2
		place(c, (col - 1) * (colW + CARD_GAP), colY[col])
		colY[col] = colY[col] + h + CARD_GAP
	end
	local y = math.max(colY[1], colY[2])
	local newCard, h = fill("new", {}, "New group", nil, "Drop an element here to give it a group of its own.")
	place(newCard, 0, y)
	for i = nCard + 1, #board.cards do board.cards[i]:Hide() end
	for i = nChip + 1, #board.chips do board.chips[i]:Hide() end
	board.height = y + h
	board.frame:SetHeight(board.height)
end

local function buildBoard(p)
	board.page = p
	board.frame = p:row(10)
	board.indicator = board.frame:CreateTexture(nil, "OVERLAY")
	board.indicator:SetColorTexture(0.2, 0.6, 1, 1)
	board.indicator:SetHeight(2)
	board.indicator:SetDrawLayer("OVERLAY", 7)
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(180, 24)
	ghost:SetAlpha(0.9)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local s = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s)
		updateDragFeedback()
	end)
	board.ghost = ghost
	p:add(board.frame, function() return board.height or 10 end, nil, layoutBoard)
end

local function buildLayout(p)
	p:text("Drag elements between groups, or click one for a menu. Click a group's title to edit it below. " ..
		"To place groups on screen, unlock: drag a group to move it, mouse wheel to scale, shift + wheel for opacity.")
	p:button(function() return db().locked and "Unlock layout" or "Lock layout" end,
		function() db().locked = not db().locked; relayout() end,
		"Unlocked, groups can be dragged on screen (they snap to the grid and to each other), scaled with the mouse wheel and faded with shift + wheel. Lock when done so clicks pass through.")
	p:checkbox("Snapping", "While dragging, groups snap to other groups' edges and centres, the screen centre, and the grid when it is shown.",
		get("snap"), set("snap"))
	p:checkbox("Show grid while unlocked", "A grid over the whole screen while the layout is unlocked. With snapping on, groups snap to it.",
		get("grid"), set("grid"))
	p:slider("Grid size", "Distance between grid lines.", 8, 128, 4, int, get("gridSize"), set("gridSize"))
	p:header("Groups")
	buildBoard(p)

	local settingsHeader = p:header("Group settings", hasGroups, "Click a group title above to edit settings for that group.")
	p.items[#p.items].refresh = function()
		selected()
		settingsHeader.text:SetText(string.format("Group %d settings", selectedGroup))
	end
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, groupGet("orientation"), groupSet("orientation"), hasGroups)
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, groupGet("growth"), groupSet("growth"), hasGroups)
	p:slider("Spacing", "Gap between the group's elements.", 0, 40, 1, int, groupGet("spacing"), groupSet("spacing"), hasGroups)
	p:slider("Scale", "Size of the whole group. Mouse wheel over the group while unlocked does the same.", 0.5, 3, 0.05, times,
		groupGet("scale"), function(v)
			local g = selected()
			if not g then return end
			-- Offsets are in the group's own units: rescale them so the centre stays put.
			if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
			g.scale = v
			relayout()
		end, hasGroups)
	p:slider("Opacity", "Transparency of the group. Shift + mouse wheel over the group while unlocked does the same.", 0.1, 1, 0.05, pct,
		groupGet("alpha"), groupSet("alpha"), hasGroups)
	p:checkbox("Only show in combat", "Hide this group out of combat. Each element also has its own Show setting (Always, In combat, Never) under Elements; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked.",
		groupGet("combatOnly"), groupSet("combatOnly"), hasGroups)
	p:buttons({
		{ "Centre on screen", function() ns.centerGroup(selectedGroup) end, "Moves the group to the middle of the screen.", 130 },
		{ "Split up", function() ns.splitGroup(selectedGroup) end, "Gives every element in the group a group of its own, left where it is.", 100 },
		{ "Hide all", function() ns.hideGroup(selectedGroup) end, "Sets every element in the group to never show. They keep their places; set one back to Always to bring it back.", 100 },
	}, hasGroups)
end

------------------------------------------------------------------------
-- Elements: an overview of every element, and one page per real element under it in the nav.
------------------------------------------------------------------------
local ELEMENT_PAGES = {}   -- key -> page key, filled as element pages are built

local function groupText(key)
	local gi = ns.findElement(key)
	return gi and ("Group " .. gi) or "No group"
end

local function buildElements(p)
	p:text("Every element the addon can show, which group it sits in and when it shows. The Layout page arranges groups on screen; each element's own look is on its page below Elements.")
	p:header("Elements")
	local GROUP_X, SHOW_X = 150, 260   -- sized to fit beside the Settings button at the minimum width
	do
		local f = p:row(20)
		local function col(text, x)
			local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetPoint("LEFT", x, 0)
			fs:SetText(text)
		end
		col("Element", 32)
		col("Group", GROUP_X + 4)
		col("Show", SHOW_X + 4)
		p:add(f, 20)
	end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		local f = p:row(34)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", 4, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", 32, 0)
		name:SetText(e.label)
		local group = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		group:SetPoint("LEFT", GROUP_X, 0)
		group:SetWidth(100)
		group:SetupMenu(function(_, rootDescription)
			for gi = 1, groupCount() do
				rootDescription:CreateRadio("Group " .. gi, function() return ns.findElement(key) == gi end,
					function() ns.placeElement(key, gi) end)
			end
			rootDescription:CreateRadio("New group", function() return false end, function() ns.placeElement(key, "new") end)
		end)
		local show = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		show:SetPoint("LEFT", SHOW_X, 0)
		show:SetWidth(110)
		show:SetupMenu(function(_, rootDescription)
			for _, c in ipairs(SHOW_CHOICES) do
				rootDescription:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
			end
		end)
		show:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Show")
			GameTooltip:AddLine(SHOW_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		open:SetSize(90, 22)
		open:SetPoint("RIGHT", -4, 0)
		open:SetText("Settings")
		open:SetScript("OnClick", function() if ELEMENT_PAGES[key] then ns.OpenOptions(ELEMENT_PAGES[key]) end end)
		p:add(f, 34, function() return ns.available(key) end, function()
			e.paint(icon)
			group:GenerateMenu()
			show:GenerateMenu()
			open:SetShown(ELEMENT_PAGES[key] ~= nil)
		end)
	end
end

-- The block every element page starts with.
local function elementDisplay(p, key)
	ELEMENT_PAGES[key] = p.key
	p:header("Display")
	p:text(function() return "In " .. groupText(key) .. ". Change groups on the Layout page." end)
	p:dropdown("Show", SHOW_TIP, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
end

local function buildShield(p)
	elementDisplay(p, "shield")
	p:header("Charges")
	p:dropdown("Charge number position", "Where the charge count sits on the shield icon.",
		{ { "corner", "Bottom right corner" }, { "center", "Centred" } }, get("countPos"), set("countPos"))
	p:slider("Charge number size", "Font size of the charge count.", 8, 64, 1, int, get("countSize"), set("countSize"))
	p:checkbox("Show charge bar", "A bar along the bottom of the icon, one segment per charge.", get("showBar"), set("showBar"))
	p:checkbox("Show charge number", "The charge count text (Blizzard only prints it for two or more).", get("showCount"), set("showCount"))

	p:header("No shield")
	p:checkbox("Red ring", "Red ring inside the icon edge when the shield is down.", get("emptyRing"), set("emptyRing"))
	p:checkbox("Grey icon", "Desaturate the icon when the shield is down.", get("emptyGrey"), set("emptyGrey"))
	p:checkbox("Red tint", "Red tint on the icon when the shield is down.", get("emptyTint"), set("emptyTint"))
	p:checkbox("Pulse", "Fade the icon in and out when the shield is down. In combat this starts once the addon knows the shield is gone (when combat ends), like the red ring.",
		get("emptyPulse"), set("emptyPulse"))
	p:slider("Combat fallback", "How much of the no-shield look stays underneath while the shield is up. Blizzard's icon compensates so the overall opacity matches the group's. If the shield drops mid-fight before you recast, this is how strongly the no-shield look shows until combat ends.",
		0, 1, 0.05, pct, get("underlayUp"), set("underlayUp"))

	p:header("Shielded")
	p:slider("Duration swipe", "Darkness of the swipe Blizzard draws over the shield icon for the buff's remaining duration. Zero turns the swipe off.",
		0, 1, 0.05, pct, get("shieldSwipe"), set("shieldSwipe"))
	p:slider("Icon opacity", "Manual multiplier on the shield icon's opacity, applied after the underlay compensation. Cannot brighten past the group's opacity.",
		0.5, 1, 0.05, pct, get("shieldIconAlpha"), set("shieldIconAlpha"))
end

local function buildShock(p)
	elementDisplay(p, "shock")
	p:header("Spell")
	local shockChoices = {}
	for _, key in ipairs(ns.SHOCK_ORDER) do table.insert(shockChoices, { key, ns.SHOCKS[key] }) end
	p:dropdown("Tracked shock", "Which shock the icon shows, with its cooldown and range.", shockChoices, get("shock"), set("shock", respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, c in ipairs(shockChoices) do table.insert(manaChoices, c) end
	p:dropdown("Mana check uses", "Which spell's cost decides when the icon turns blue. Always the highest rank you know.",
		manaChoices, get("manaSpell"), set("manaSpell", respell))

	local looks = { { "tint", "Tint" }, { "overlay", "Coloured overlay" }, { "both", "Overlay and tint" } }
	p:header("Not enough mana")
	p:dropdown("Look", "Blue on the icon itself when you cannot afford the mana-check spell. If you are also out of range, the icon goes red instead and only the blue ring remains.",
		looks, get("manaStyle"), set("manaStyle"))
	p:slider("Overlay strength", "Opacity of the blue overlay.", 0.1, 1, 0.05, pct, get("manaIntensity"), set("manaIntensity"))
	p:slider("Tint strength", "How strongly the blue tint removes the other colours.", 0.1, 1, 0.05, pct, get("manaTint"), set("manaTint"))
	p:slider("Ring", "A blue ring inside the icon edge whenever you cannot afford the mana-check spell. This is its opacity.",
		0.1, 1, 0.05, pct, get("manaRing"), set("manaRing"))

	p:header("Out of range")
	p:dropdown("Look", "Red on the icon itself when your target is out of range. Takes the icon body over the mana look.",
		looks, get("rangeStyle"), set("rangeStyle"))
	p:slider("Overlay strength", "Opacity of the red overlay.", 0.1, 1, 0.05, pct, get("rangeIntensity"), set("rangeIntensity"))
	p:slider("Tint strength", "How strongly the red tint removes the other colours.", 0.1, 1, 0.05, pct, get("rangeTint"), set("rangeTint"))
end

local function buildImbue(p)
	elementDisplay(p, "imbue")
	p:text("Tracks the Rockbiter, Flametongue, Frostbrand or Windfury imbue on your main-hand weapon.")

	p:header("No imbue on")
	local iconChoices = { { "last", "Last one used" } }
	for _, key in ipairs(ns.IMBUE_ORDER) do table.insert(iconChoices, { key, ns.IMBUES[key].name }) end
	p:dropdown("Icon", "Which imbue's icon stands in while none is on.", iconChoices, get("imbuePreferred"), set("imbuePreferred"))
	p:checkbox("Red ring", "Red ring inside the icon edge while no imbue is on.", get("imbueMissingRing"), set("imbueMissingRing"))
	p:checkbox("Grey icon", "Desaturate the icon while no imbue is on.", get("imbueMissingGrey"), set("imbueMissingGrey"))
	p:checkbox("Pulse", "Fade the icon in and out while no imbue is on.", get("imbuePulse"), set("imbuePulse"))

	p:header("Imbue on")
	p:slider("Show time left under", "Show the minutes (then seconds) left once the imbue has less than this. Zero never shows it.",
		0, 30, 1, function(v) return v == 0 and "Never" or string.format("%d min", v) end, get("imbueWarnMins"), set("imbueWarnMins"))
	p:slider("Time text size", "Font size of the time left.", 8, 48, 1, int, get("imbueTextSize"), set("imbueTextSize"))
	p:checkbox("Hide until it runs low", "While an imbue is on, keep the icon invisible until its time left shows. It keeps its place in the group.",
		get("imbueHideActive"), set("imbueHideActive"))
end

-- One page per cooldown element; the options depend on what the element tracks.
local function buildCooldown(p, def)
	local key = def.key
	elementDisplay(p, key)
	local function optGet(name, default) return function()
		local v = ns.elementOpts(key)[name]
		if v == nil then return default end
		return v
	end end
	local function optSet(name) return function(v) ns.elementOpts(key)[name] = v; relayout() end end
	p:text("Shows " .. def.spell .. "'s cooldown. Countdown number settings are on the General page.")
	if def.totemSlot then
		p:header("Totem active")
		p:checkbox("Time bar", "A bar along the bottom that drains while your " .. def.spell .. " is down.",
			optGet("activeBar", true), optSet("activeBar"))
		p:checkbox("Time left", "Small numbers in the top-left corner counting down while your " .. def.spell .. " is down.",
			optGet("activeText", true), optSet("activeText"))
	end
	if def.needsTotem then
		p:header("No fire totem")
		p:text(def.spell .. " only works while one of your fire totems is out.")
		p:checkbox("Grey icon", "Desaturate the icon while no fire totem is out.", optGet("blockedGrey", true), optSet("blockedGrey"))
		p:checkbox("Red ring", "Red ring inside the icon edge while no fire totem is out.", optGet("blockedRing", true), optSet("blockedRing"))
		p:checkbox("Pulse", "Fade the icon in and out while no fire totem is out.", optGet("blockedPulse", false), optSet("blockedPulse"))
		p:header("Fire totem out")
		p:checkbox("Time bar", "A bar along the bottom that drains while a fire totem is out, so you know how long " .. def.spell .. " can still be cast.",
			optGet("activeBar", true), optSet("activeBar"))
		p:checkbox("Time left", "Small numbers in the top-left corner counting down the fire totem's time.",
			optGet("activeText", true), optSet("activeText"))
	end
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function showPage(key)
	currentPage = key
	for _, p in ipairs(pageOrder) do
		local on = p.key == key
		p.scroll:SetShown(on)
		p.nav.bg:SetShown(on)
	end
	pages[key]:refresh()
end

local function buildWindow()
	win = CreateFrame("Frame", "ShamanForeverOptionsFrame", UIParent, "BackdropTemplate")
	local saved = db().optionsSize
	win:SetSize(saved and saved.w or WIDTH, saved and saved.h or HEIGHT)
	win:SetPoint("CENTER")
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(win:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	-- Sized by hand rather than with StartSizing: the size always follows the cursor's distance from
	-- where the grip was grabbed, so dragging past a limit and back only grows the window once the
	-- cursor returns past that limit (StartSizing grows as soon as the direction reverses).
	local function sizeToCursor()
		local s = win:GetEffectiveScale()
		local x, y = GetCursorPosition()
		win:SetSize(math.min(math.max(grip.startW + (x - grip.startX) / s, MIN_W), MAX_W),
			math.min(math.max(grip.startH + (grip.startY - y) / s, MIN_H), MAX_H))
	end
	grip:SetScript("OnMouseDown", function(self)
		-- Pin the top-left corner so the window grows right and down.
		local left, top = win:GetLeft(), win:GetTop()
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		self.startX, self.startY = GetCursorPosition()
		self.startW, self.startH = win:GetSize()
		self:SetScript("OnUpdate", sizeToCursor)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		db().optionsSize = { w = math.floor(win:GetWidth()), h = math.floor(win:GetHeight()) }
	end)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	win:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
	win:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
	table.insert(UISpecialFrames, win:GetName())   -- Escape closes it

	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Shaman Forever")
	local version = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("LEFT", title, "RIGHT", 8, -1)
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	version:SetText(getMeta and getMeta(ADDON, "Version") or "")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local divider = win:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.1)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", NAV_W + 8, -40)
	divider:SetPoint("BOTTOMLEFT", NAV_W + 8, 12)

	buildGeneral(newPage("general", "General"))
	buildLayout(newPage("layout", "Layout"))
	buildElements(newPage("elements", "Elements"))
	buildShield(newPage("shield", "Lightning Shield", true))
	buildShock(newPage("shock", "Shock", true))
	buildImbue(newPage("imbue", "Weapon Imbue", true))
	for _, def in ipairs(ns.COOLDOWNS) do buildCooldown(newPage(def.key, def.spell, true), def) end

	for i, p in ipairs(pageOrder) do
		local indent = p.indent and 14 or 0
		local b = CreateFrame("Button", nil, win)
		b:SetSize(NAV_W - 12 - indent, p.indent and 22 or 26)
		b:SetPoint("TOPLEFT", 10 + indent, -44 - (i - 1) * 28)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(0.2, 0.6, 1, 0.25)
		b.bg:Hide()
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		local fs = b:CreateFontString(nil, "OVERLAY", p.indent and "GameFontHighlightSmall" or "GameFontNormal")
		fs:SetPoint("LEFT", 8, 0)
		fs:SetText(p.title)
		b:SetScript("OnClick", function() showPage(p.key) end)
		p.nav = b
	end
	win:Hide()
end

StaticPopupDialogs["SHAMANFOREVER_RESET"] = {
	text = "Reset every Shaman Forever option and the layout to defaults?",
	button1 = YES, button2 = NO,
	OnAccept = function() ns.resetAll(); ns.say("reset to defaults") end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Several changes in one frame (a slider drag, a drop) refresh the visible page once.
local refreshQueued = false
function ns.RefreshOptions()
	if not (win and win:IsShown()) or refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if win:IsShown() and currentPage then pages[currentPage]:refresh() end
	end)
end

function ns.OpenOptions(page, groupIndex)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
	if groupIndex then selectedGroup = groupIndex end
	win:Show()
	showPage(page or currentPage or "general")
end

-- An element's own page, or the Elements overview for one without a page (test elements).
function ns.OpenElementOptions(key)
	if not win then buildWindow() end
	ns.OpenOptions(ELEMENT_PAGES[key] or "elements")
end

function ns.ToggleOptions()
	if win and win:IsShown() then win:Hide() else ns.OpenOptions() end
end

-- Escape > Options > AddOns > Shaman Forever: a pointer to the window above.
local category
function ns.BuildOptions()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Shaman Forever")
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText("Shaman Forever has its own options window. You can also open it by typing /sf.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	button:SetText("Open options")
	button:SetScript("OnClick", function() ns.OpenOptions() end)
	category = Settings.RegisterCanvasLayoutCategory(panel, "Shaman Forever")
	Settings.RegisterAddOnCategory(category)
end
