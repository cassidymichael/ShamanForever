-- The options window's Layout page: the groups listed on the left (name, element count and an icon
-- strip), the chosen group's elements and settings on the right. Drag an element onto a group's name
-- to move it there, between the chosen group's elements to change the order, or onto New group for
-- a group of its own; click one for a menu. The groups are ShamanForever.lua's (db.groups): every
-- change goes through its layout edits, which wait out combat.
local _, ns = ...

local LP = {}
ns.LayoutPage = LP

local Page, K = ns.Page, ns.Options.kit
local setTip = Page.setTip
local int, times, pct = Page.int, Page.times, Page.pct
local NAV_W, PAGE_TOP, LABEL_W = Page.NAV_W, Page.PAGE_TOP, Page.LABEL_W
local relayout = K.relayout

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end

------------------------------------------------------------------------
-- The chosen group
------------------------------------------------------------------------
local chosen   -- its id
local reveal = false   -- scroll the list to the chosen group on the next refresh

-- The chosen group, or the first when it is gone (or none was chosen).
local function selected()
	local g = ns.groupById(chosen)
	if not g then
		g = db().groups[1]
		chosen = g and g.id
	end
	return g
end
local function hasGroups() return #db().groups > 0 end

-- Shows the group with this id next time the page draws, scrolled into the list's view.
function LP.choose(id)
	chosen = id
	reveal = true
end

local function groupGet(key) return function() local g = selected(); return g and g[key] end end
local function groupSet(key) return function(v) local g = selected(); if g then g[key] = v; relayout() end end end

-- A confirmation about the chosen group: its name in the question, its id for the answer.
local function askAboutGroup(which)
	local g = selected()
	if g then StaticPopup_Show(which, g.name, nil, g.id) end
end
K.confirm("SHAMANFOREVER_CENTER", "Move %s to the middle of the screen?\nIts current position is lost.", "Centre",
	function(id) ns.centerGroup(id) end)
K.confirm("SHAMANFOREVER_SPLIT", "Split %s into one group per element?\nPutting them back together is done by hand.", "Split up",
	function(id) ns.splitGroup(id) end)
K.confirm("SHAMANFOREVER_HIDEALL", "Hide every element in %s?\nEach one's Show setting becomes Hidden.", "Hide all",
	function(id) ns.hideGroup(id) end)
-- The group after it in the list is chosen next, or the one before when it was last.
K.confirm("SHAMANFOREVER_DELETE_GROUP", "Delete the group %s?\n%s", "Delete", function(id)
	local _, i = ns.groupById(id)
	if not (i and ns.deleteGroup(id)) then return end
	local groups = db().groups
	local after = groups[i] or groups[i - 1]
	chosen = after and after.id
	ns.Options.refresh()
end)
local function askDelete()
	local g = selected()
	if not g then return end
	local n = #g.members
	local what = n == 0 and "It has no elements." or n == 1 and "Its element moves to Ungrouped."
		or string.format("Its %d elements move to Ungrouped.", n)
	StaticPopup_Show("SHAMANFOREVER_DELETE_GROUP", g.name, what, g.id)
end

------------------------------------------------------------------------
-- Elements (chips): an icon and a name, dimmed while hidden or not learned. Drag one to move it;
-- click one for a menu.
------------------------------------------------------------------------
local CHIP_STEP = 26   -- a chip is 2 shorter, leaving a gap
local drag = {}        -- key: the element being dragged; hover: the drop target under the cursor
local list, rows, loose, newButton, members   -- built with the page (LP.build)

local function elementName(key) return ns.Look.elementName(key) end

-- Its name, and what keeps it off screen or in combat only.
local function chipText(key)
	local tags = {}
	if not ns.isLearned(key) then table.insert(tags, "not learned") end
	local mode = ns.showMode(key)
	if mode == "never" then table.insert(tags, "hidden")
	elseif mode == "combat" then table.insert(tags, "in combat") end
	if #tags == 0 then return elementName(key) end
	return elementName(key) .. "  |cff888888(" .. table.concat(tags, ", ") .. ")|r"
end

local function fillChip(chip, key)
	chip.key = key
	ns.ELEMENTS[key].paint(chip.icon)
	local learned = ns.isLearned(key)
	chip.icon:SetDesaturated(not learned)
	chip.text:SetText(chipText(key))
	chip:SetAlpha((learned and ns.showMode(key) ~= "never") and 1 or 0.6)
end

-- Where a drop on the chosen group's elements lands: its place among the others.
local function dropIndex()
	return Page.dropPosition(members.shown, function(chip) return chip.key == drag.key end)
end

-- The drop target under the cursor: "new" (the New group button), a group's row, or "members" (the
-- chosen group's elements). Rows scrolled out of the list's view don't count.
local function targetUnderCursor()
	if newButton:IsVisible() and newButton:IsMouseOver() then return "new" end
	if list.scroll:IsMouseOver() then
		for _, r in ipairs(rows.pool) do
			if r:IsShown() and r:IsMouseOver() then return r end
		end
	end
	if members:IsVisible() and members.page.scroll:IsMouseOver() and members:IsMouseOver() then return "members" end
end

-- Gold marks the chosen group, as it marks the current page in the nav; white is drop feedback.
local function rowBorder(r)
	if drag.key and drag.hover == r then r:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
	elseif r.id == chosen then r:SetBackdropBorderColor(0.88, 0.66, 0.29, 1)
	else r:SetBackdropBorderColor(0.23, 0.17, 0.10, 1) end
	r.wash:SetShown(r.id == chosen)
end

local function updateDragFeedback()
	drag.hover = targetUnderCursor()
	for _, r in ipairs(rows.pool) do rowBorder(r) end
	if drag.hover == "new" then newButton:LockHighlight() else newButton:UnlockHighlight() end
	local line = drag.line
	line:Hide()
	if drag.hover ~= "members" then return end
	local at, others = dropIndex()
	if not Page.placeDropLine(line, others, at) then   -- no other elements: under the caption
		line:SetPoint("TOPLEFT", members, "TOPLEFT", 0, -members.top + 1)
		line:SetPoint("TOPRIGHT", members, "TOPRIGHT", 0, -members.top + 1)
	end
	line:Show()
end

local function startDrag(chip)
	if InCombatLockdown() then ns.say("layout changes wait until combat ends"); return end
	drag.key = chip.key
	chip:SetAlpha(0.35)
	ns.ELEMENTS[chip.key].paint(drag.ghost.icon)
	drag.ghost.text:SetText(elementName(chip.key))
	drag.ghost:Show()
end

-- Ends a drag; drop: whether to place the element where the cursor is.
local function endDrag(drop)
	local key = drag.key
	local target = key and drop and targetUnderCursor()
	local at = target == "members" and dropIndex()   -- while the dragged chip is still left out
	drag.key, drag.hover = nil, nil
	drag.ended = GetTime()
	drag.ghost:Hide()
	drag.line:Hide()
	newButton:UnlockHighlight()
	if not key then return end
	if target == "new" then
		local done, id = ns.placeElement(key, "new")
		if done and id then chosen = id end
	elseif target == "members" then
		local g = selected()
		if g then ns.placeElement(key, g.id, at) end
	elseif type(target) == "table" then
		local g = ns.groupOf(key)
		if not (g and g.id == target.id) then ns.placeElement(key, target.id) end
	end
	ns.Options.refresh()   -- also restores the dimmed chip when nothing moved
end
local function finishDrag() endDrag(true) end

local function chipMenu(chip)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	if drag.ended and GetTime() - drag.ended < 0.3 then return end   -- the release that ended a drag
	local key = chip.key
	MenuUtil.CreateContextMenu(chip, function(_, root)
		root:CreateTitle(elementName(key))
		root:CreateButton("Open settings", function() ns.Options.openElement(key) end)
		root:CreateDivider()
		local g, i = ns.groupOf(key)
		if g and i > 1 then root:CreateButton("Move earlier", function() ns.placeElement(key, g.id, i - 1) end) end
		if g and i < #g.members then root:CreateButton("Move later", function() ns.placeElement(key, g.id, i + 1) end) end
		local to
		for _, o in ipairs(db().groups) do
			if o ~= g then
				to = to or root:CreateButton("Move to")
				to:CreateButton(o.name, function() ns.placeElement(key, o.id) end)
			end
		end
		if not (g and #g.members == 1) then
			root:CreateButton("Move to a new group", function()
				local done, id = ns.placeElement(key, "new")
				if done and id then chosen = id end
				ns.Options.refresh()
			end)
		end
		root:CreateDivider()
		root:CreateTitle("Show")
		for _, c in ipairs(K.SHOW_CHOICES) do
			root:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
		end
	end)
end

local function newChip(parent)
	local chip = CreateFrame("Button", nil, parent)
	chip:SetHeight(CHIP_STEP - 2)
	local bg = chip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.06)
	local hl = chip:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(20, 20)
	chip.icon:SetPoint("LEFT", 2, 0)
	ns.cropIcon(chip.icon)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
	chip.text:SetPoint("RIGHT", -4, 0)
	chip.text:SetJustifyH("LEFT")
	chip.text:SetWordWrap(false)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:RegisterForDrag("LeftButton")
	chip:SetScript("OnClick", chipMenu)
	chip:SetScript("OnDragStart", startDrag)
	chip:SetScript("OnDragStop", finishDrag)
	setTip(chip, "Move element", "Drag onto a group or New group, or between elements to set the order. Click for a menu.")
	return chip
end

-- Lays out keys as chips in a block from top, reusing its pool. Returns the height used.
local function placeChips(block, keys, top)
	block.shown = block.shown or {}
	wipe(block.shown)
	for i, key in ipairs(keys) do
		local chip = block.pool[i]
		if not chip then
			chip = newChip(block)
			block.pool[i] = chip
		end
		fillChip(chip, key)
		chip:ClearAllPoints()
		chip:SetPoint("TOPLEFT", block, "TOPLEFT", 0, -top - (i - 1) * CHIP_STEP)
		chip:SetPoint("RIGHT", block, "RIGHT", 0, 0)
		chip:Show()
		block.shown[i] = chip
	end
	for i = #keys + 1, #block.pool do block.pool[i]:Hide() end
	return #keys * CHIP_STEP
end

------------------------------------------------------------------------
-- The group list: one row per group (its name, how many elements, their icons), New group above.
------------------------------------------------------------------------
local LIST_W = 196     -- the list's column, its scroll bar included
local ROWS_TOP = 42    -- the rows' offset in the list, under its header
local ROW_H, ROW_STEP = 42, 45
local ICON_STEP = 18   -- 16 px icons in the strip

local function newRow(parent)
	local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
	r:SetBackdrop(ns.BACKDROP)
	r:SetBackdropColor(0.09, 0.075, 0.06, 1)
	r:SetHeight(ROW_H)
	r.wash = r:CreateTexture(nil, "BACKGROUND", nil, 1)   -- the chosen group's gold
	r.wash:SetPoint("TOPLEFT", 1, -1)
	r.wash:SetPoint("BOTTOMRIGHT", -1, 1)
	r.wash:SetColorTexture(1, 1, 1, 1)
	pcall(r.wash.SetGradient, r.wash, "VERTICAL", CreateColor(0.88, 0.66, 0.29, 0.04), CreateColor(0.88, 0.66, 0.29, 0.13))
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetColorTexture(1, 1, 1, 0.05)
	r.count = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r.count:SetPoint("TOPRIGHT", -6, -7)
	r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.name:SetPoint("TOPLEFT", 6, -6)
	r.name:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
	r.name:SetJustifyH("LEFT")
	r.name:SetWordWrap(false)
	r.icons = {}
	r.more = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	r:SetScript("OnClick", function(self)
		chosen = self.id
		ns.Options.refresh()
	end)
	return r
end

-- A row's icon strip: as many as fit, the last place saying how many more.
local function fillRow(r, g, w)
	r.id = g.id
	r.name:SetText(g.name)
	local n = #g.members
	r.count:SetText(n > 0 and n or "")
	local fit = math.max(math.floor((w - 12 + 2) / ICON_STEP), 1)
	local shown = n > fit and fit - 1 or n
	for i = 1, shown do
		local t = r.icons[i]
		if not t then
			t = r:CreateTexture(nil, "ARTWORK")
			t:SetSize(16, 16)
			t:SetPoint("TOPLEFT", 6 + (i - 1) * ICON_STEP, -22)
			ns.cropIcon(t)
			r.icons[i] = t
		end
		local key = g.members[i]
		ns.ELEMENTS[key].paint(t)
		t:SetDesaturated(not ns.isLearned(key))
		t:SetAlpha(ns.showMode(key) == "never" and 0.45 or 1)
		t:Show()
	end
	for i = shown + 1, #r.icons do r.icons[i]:Hide() end
	r.more:ClearAllPoints()
	r.more:SetPoint("LEFT", r, "TOPLEFT", 8 + shown * ICON_STEP, -30)
	r.more:SetText(n == 0 and "Empty" or n > shown and ("+" .. (n - shown)) or "")
	rowBorder(r)
end

local function layoutRows()
	selected()   -- a chosen group that's gone falls back to the first
	local w = list.content:GetWidth()
	for i, g in ipairs(db().groups) do
		local r = rows.pool[i]
		if not r then
			r = newRow(rows)
			rows.pool[i] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", rows, "TOPLEFT", 0, -(i - 1) * ROW_STEP)
		r:SetPoint("RIGHT", rows, "RIGHT", 0, 0)
		fillRow(r, g, w)
		r:Show()
		if reveal and g.id == chosen then rows.revealAt = (i - 1) * ROW_STEP end
	end
	for i = #db().groups + 1, #rows.pool do rows.pool[i]:Hide() end
	rows.height = math.max(#db().groups * ROW_STEP, 1)
	rows:SetHeight(rows.height)
end

-- After the list lays out: the chosen group scrolled into view, if it was chosen from elsewhere
-- (next frame, once the list's scroll range takes its new height).
local function revealChosen()
	local at = rows.revealAt
	rows.revealAt, reveal = nil, false
	if not at then return end
	C_Timer.After(0, function()
		local s = list.scroll
		local y, h, v = ROWS_TOP + at, s:GetHeight(), s:GetVerticalScroll()
		if y < v then v = y elseif y + ROW_H > v + h then v = y + ROW_H - h end
		s:SetVerticalScroll(math.max(0, math.min(v, s:GetVerticalScrollRange())))
	end)
end

-- Ungrouped: elements in no group (their group was deleted), under the groups while there are any.
-- They aren't drawn and keep their settings; drag one onto a group to place it.
local LOOSE_TOP = 48   -- the heading and its line above the chips

local function looseKeys()
	local keys = {}
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if ns.available(key) and not ns.groupOf(key) then table.insert(keys, key) end
	end
	return keys
end

local function buildLoose()
	loose = list:row(10)
	loose.pool = {}
	local title = loose:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 4, -12)
	title:SetText("Ungrouped")
	title:SetTextColor(0.62, 0.6, 0.57)
	local line = loose:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.23, 0.17, 0.10, 1)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 0, -28)
	line:SetPoint("TOPRIGHT", 0, -28)
	local note = loose:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 4, -33)
	note:SetText("Not on screen. Drag onto a group.")
	list:add(loose, function() return loose.height or 1 end, function() return #looseKeys() > 0 end, function()
		loose.height = LOOSE_TOP + placeChips(loose, looseKeys(), LOOSE_TOP)
		loose:SetHeight(loose.height)
	end)
end

local function buildList(p)
	list = Page.new(p.win, "layoutGroups")
	local s = list.scroll
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", p.win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	s:SetPoint("BOTTOMLEFT", p.win, "BOTTOMLEFT", NAV_W + 18, 12)
	s:SetWidth(LIST_W - 14)
	if s.ScrollBar then
		s.ScrollBar:ClearAllPoints()
		s.ScrollBar:SetPoint("TOPLEFT", s, "TOPRIGHT", 4, 0)
		s.ScrollBar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 4, 0)
	end
	-- The list shows and refreshes with the page, as a pinned header does (Page:pin).
	p.fixed = s
	function s.refresh() list:refresh() end
	list.afterRefresh = revealChosen

	local head = list:header("Groups")
	newButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
	newButton:SetSize(92, 20)
	newButton:SetPoint("BOTTOMRIGHT", 0, 7)
	newButton:SetText("New group")
	newButton:SetScript("OnClick", function()
		local done, id = ns.addGroup()
		if done and id then LP.choose(id) end
		ns.Options.refresh()
	end)
	setTip(newButton, "New group", "An empty group. Drop an element here to give it a group of its own.")
	list:add(list:row(6), 6)
	rows = list:row(10)
	rows.pool = {}
	list:add(rows, function() return rows.height or 1 end, nil, layoutRows)
	buildLoose()
	list:add(list:row(6), 6)
	list:checkbox("Test elements", nil,
		function() return acct().testMode end, function(v) ns.setTestMode(v); ns.Options.refresh() end)
	list:text("Placeholder elements, and ones you haven't learned yet.")
end

------------------------------------------------------------------------
-- The chosen group: its name, its elements, its settings
------------------------------------------------------------------------
local CAPTION_H = 28   -- the Elements caption above the chips

-- The group's name: Enter renames it; Escape, or leaving the box any other way, keeps the old one.
local function nameRow(p, shown)
	local f = p:row(34)
	p:label(f, "Name", "A name another group has gets a number added.")
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(200, 20)
	box:SetPoint("LEFT", f, "LEFT", LABEL_W + 6, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(32)
	box:SetFontObject("GameFontHighlight")
	local function current() local g = selected(); return g and g.name or "" end
	box:SetScript("OnEditFocusGained", function(b) b:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(b)
		b:HighlightText(0, 0)
		b:SetText(current())
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", function(b)
		local g = selected()
		if g then ns.renameGroup(g.id, b:GetText()) end
		b:ClearFocus()
		ns.Options.refresh()
	end)
	return p:add(f, 34, shown, function() if not box:HasFocus() then box:SetText(current()) end end)
end

local function buildMembers(p)
	members = p:row(10)
	members.page, members.pool, members.top = p, {}, CAPTION_H
	local caption = members:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	caption:SetPoint("TOPLEFT", 4, -9)
	caption:SetText("Elements")
	local hint = members:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", caption, "RIGHT", 10, 0)
	hint:SetText("Drag to reorder, or onto a group to move it.")
	members.empty = members:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	members.empty:SetPoint("TOPLEFT", 4, -CAPTION_H - 5)
	members.empty:SetText("Empty. Drop an element here.")
	drag.line = Page.dropLine(members)
	p:add(members, function() return members.height or 1 end, nil, function()
		local g = selected()
		local keys = g and g.members or {}
		local h = placeChips(members, keys, CAPTION_H)
		members.empty:SetShown(#keys == 0)
		members.height = CAPTION_H + math.max(h, CHIP_STEP) + 8
		members:SetHeight(members.height)
	end)
end

local function buildSettings(p)
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, groupGet("orientation"), groupSet("orientation"))
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, groupGet("growth"), groupSet("growth"))
	p:slider("Spacing", "Gap between the group's elements.", 0, 40, 1, int, groupGet("spacing"), groupSet("spacing"))
	K.generalRow(p, "Icon size same as General", "Use the icon size on the General page.",
		function() local g = selected(); return g and g.sizeFollow end,
		function(v)
			local g = selected()
			if not g then return end
			if not v then g.size = db().iconSize end   -- its own starts from General's, so nothing jumps
			g.sizeFollow = v
			relayout()
		end, "size")
	p:slider("Icon size", "Mouse wheel over the group while unlocked does the same.", 24, 96, 1, int,
		groupGet("size"), groupSet("size"), function() local g = selected(); return g and not g.sizeFollow end)
	p:text("Icon size keeps borders and rings crisp. Scale grows everything, borders and rings included.")
	p:slider("Scale", "Grows everything in the group, borders and rings too. Ctrl + mouse wheel over the group while unlocked does the same.", 0.5, 3, 0.05, times,
		groupGet("scale"), function(v)
			local g = selected()
			if not g then return end
			-- Offsets are in the group's own units: rescale them so the centre stays put.
			if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
			g.scale = v
			relayout()
		end)
	p:slider("Opacity", "Transparency of the group. Shift + mouse wheel over the group while unlocked does the same.", 0.1, 1, 0.05, pct,
		groupGet("alpha"), groupSet("alpha"))
	K.borderRows(p, selected, relayout, "Border same as General")
	p:dropdown("Show", "When the group is on screen. Everything visible shows while positioning is unlocked.",
		K.COMBAT_SHOW, groupGet("show"), groupSet("show"), nil, 240)
	p:slider("Stay after combat", K.STAY_TIP, 0, 10, 1, K.staySecs, groupGet("fadeAfter"), groupSet("fadeAfter"),
		function() local g = selected(); return g and g.show ~= "always" end)
	p:text("Elements have their own Show setting too. An element shows only when both allow it.")
	p:buttons({
		-- Hard to undo, so each asks first.
		{ "Centre on screen", function() askAboutGroup("SHAMANFOREVER_CENTER") end, "Moves the group to the middle of the screen.", 130 },
		{ "Split up", function() askAboutGroup("SHAMANFOREVER_SPLIT") end, "Gives every element in the group a group of its own, left where it is.", 90 },
		{ "Hide all", function() askAboutGroup("SHAMANFOREVER_HIDEALL") end, "Sets every element in the group to Hidden. They keep their places; set one back to Always to bring it back.", 90 },
	})
	p:buttons({
		{ "Delete group", askDelete, "Its elements move to Ungrouped: off screen, their settings kept.", 110 },
	})
	p:add(p:row(10), 10)
end

-- The page: the group list on its left, the chosen group's elements and settings beside it.
function LP.build(p)
	buildList(p)
	p.scroll:SetPoint("TOPLEFT", p.win, "TOPLEFT", NAV_W + 18 + LIST_W + 12, PAGE_TOP)
	drag.ghost = Page.dragGhost(updateDragFeedback)

	p:text("No groups. New group makes one.", function() return not hasGroups() end)
	p.gate = hasGroups
	local head = p:header(" ", nil, " ")
	p.items[#p.items].refresh = function()
		local g = selected()
		local n = #g.members
		head.text:SetText(g.name)
		head.note:SetText(n == 1 and "1 element" or n .. " elements")
	end
	nameRow(p)
	buildMembers(p)
	buildSettings(p)
	p.gate = nil
	-- Closed or left mid-drag (Escape, the key binding), the release may never come: drop nothing.
	p.win:HookScript("OnHide", function() if drag.key then endDrag(false) end end)
	p.scroll:HookScript("OnHide", function() if drag.key then endDrag(false) end end)
end
