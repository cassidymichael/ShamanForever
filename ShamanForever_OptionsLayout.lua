-- The options window's Groups & Layout page: the groups listed on the left (name, element count
-- and an icon strip; right-click one for a menu), and beside the list the chosen group: its name
-- (Rename edits it in place), its elements right under it, then its settings. Clicking a group in
-- the list chooses it. Drag an element onto a group in the list, between the chosen group's
-- elements to set the order, or onto New group for a group of its own; click one for a menu. The
-- groups are ShamanForever.lua's (db.groups): every change goes through its layout edits, which
-- wait out combat.
local _, ns = ...

local LP = {}
ns.LayoutPage = LP

local Page, K = ns.Page, ns.Options.kit
local setTip = Page.setTip
local int, times, pct = Page.int, Page.times, Page.pct
local NAV_W, PAGE_TOP = Page.NAV_W, Page.PAGE_TOP
local relayout = K.relayout

local function db() return ns.getDB() end

------------------------------------------------------------------------
-- The chosen group: the one the page shows, marked gold in the list
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

-- Shows the group with this id next time the page draws, scrolled into the list's view.
function LP.choose(id)
	chosen = id
	reveal = true
end

-- A confirmation about a group: its name in the question, its id for the answer.
local function askAbout(which, g)
	if g then StaticPopup_Show(which, g.name, nil, g.id) end
end
K.confirm("SHAMANFOREVER_CENTER", "Move %s to the middle of the screen?\nIts current position is lost.", "Centre",
	function(id) ns.centerGroup(id) end)
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
local function askDelete(g)
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
local drag = {}        -- key: the element dragged; kind and over: the drop target under the cursor
local page, list, rows, loose, newButton   -- built with the page (LP.build)
local view = {}        -- the chosen group's header (head) and elements (box, inner, line): LP.build

local function elementName(key) return ns.Look.elementName(key) end

-- Its name, and what keeps it off screen or in combat only.
local function chipText(key)
	local tags = {}
	if not ns.isLearned(key) then table.insert(tags, ns.notLearnedText(key):lower()) end
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
	return Page.dropPosition(view.inner.shown, function(chip) return chip.key == drag.key end)
end

-- The drop target under the cursor: "new" (the New group button), "row" and a group's row in the
-- list, or "box" (the chosen group's elements). What's scrolled out of view doesn't count.
local function targetUnderCursor()
	if list.scroll:IsMouseOver() then
		if newButton:IsVisible() and newButton:IsMouseOver() then return "new" end
		for _, r in ipairs(rows.pool) do
			if r:IsShown() and r:IsMouseOver() then return "row", r end
		end
		return
	end
	if page.scroll:IsMouseOver() and view.box:IsVisible() and view.box:IsMouseOver() then return "box" end
end

-- Gold marks the chosen group, as it marks the current page in the nav; white is drop feedback.
local function rowBorder(r)
	if drag.key and drag.kind == "row" and drag.over == r then r:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
	elseif r.id == chosen then r:SetBackdropBorderColor(0.88, 0.66, 0.29, 1)
	else r:SetBackdropBorderColor(0.23, 0.17, 0.10, 1) end
	r.wash:SetShown(r.id == chosen)
end

local function updateDragFeedback()
	drag.kind, drag.over = targetUnderCursor()
	for _, r in ipairs(rows.pool) do rowBorder(r) end
	if drag.kind == "new" then newButton:LockHighlight() else newButton:UnlockHighlight() end
	view.line:Hide()
	if drag.kind ~= "box" then return end
	local line, inner = view.line, view.inner
	local at, others = dropIndex()
	if not Page.placeDropLine(line, others, at) then   -- no other elements: under the caption
		line:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -inner.top + 1)
		line:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, -inner.top + 1)
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
	local kind, over
	if key and drop then kind, over = targetUnderCursor() end
	local at = kind == "box" and dropIndex()   -- while the dragged chip is still left out
	drag.key, drag.kind, drag.over = nil, nil, nil
	drag.ended = GetTime()
	drag.ghost:Hide()
	view.line:Hide()
	newButton:UnlockHighlight()
	if not key then return end
	if kind == "new" then
		local done, id = ns.placeElement(key, "new")
		if done and id then ns.Options.openGroup(id) end
	elseif kind == "box" then
		local to = selected()
		if to then ns.placeElement(key, to.id, at) end
	elseif kind == "row" then
		local to = ns.groupById(over.id)
		if to and to ~= ns.groupOf(key) then ns.placeElement(key, to.id) end
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
		root:CreateButton("Element settings", function() ns.Options.openElement(key) end)
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
				if done and id then ns.Options.openGroup(id) end
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
-- The list's column, its scroll bar included; wider in a wide window.
local LIST_W, LIST_W_WIDE, LIST_WIDE_AT = 196, 250, 1100
local ROWS_TOP = 42    -- the rows' offset in the list, under its header
local ROW_H, ROW_STEP = 42, 45
local ICON_STEP = 18   -- 16 px icons in the strip

local rowMenu   -- below: a group's menu, from its row

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
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r:SetScript("OnClick", function(self, button)
		if button == "RightButton" then rowMenu(self) else ns.Options.openGroup(self.id) end
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
		if not ns.groupOf(key) then table.insert(keys, key) end
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

-- The list's column and the page's beside it, for the window's width.
local placedW
local function placeColumns()
	local w = page.win:GetWidth() >= LIST_WIDE_AT and LIST_W_WIDE or LIST_W
	if w == placedW then return end
	placedW = w
	list.scroll:SetWidth(w - 14)
	list.content:SetWidth(w - 14)   -- at once, so the rows fit their column on the first draw
	page.scroll:SetPoint("TOPLEFT", page.win, "TOPLEFT", NAV_W + 18 + w + 12, PAGE_TOP)
end

local function buildList()
	list = Page.new(page.win, "layoutGroups")
	list.panels = false   -- a column of groups, not blocks of settings
	local s = list.scroll
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", page.win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	s:SetPoint("BOTTOMLEFT", page.win, "BOTTOMLEFT", NAV_W + 18, 12)
	if s.ScrollBar then
		s.ScrollBar:ClearAllPoints()
		s.ScrollBar:SetPoint("TOPLEFT", s, "TOPRIGHT", 4, 0)
		s.ScrollBar:SetPoint("BOTTOMLEFT", s, "BOTTOMRIGHT", 4, 0)
	end
	placeColumns()
	-- The list shows and refreshes with the page, as a pinned header does (Page:pin).
	page.fixed = s
	function s.refresh()
		placeColumns()
		list:refresh()
	end
	list.afterRefresh = revealChosen

	local head = list:header("Groups")
	newButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
	newButton:SetSize(92, 20)
	newButton:SetPoint("BOTTOMRIGHT", 0, 7)
	newButton:SetText("New group")
	newButton:SetScript("OnClick", function()
		local done, id = ns.addGroup()
		if done and id then ns.Options.openGroup(id) end
	end)
	setTip(newButton, "New group", "An empty group. Drop an element here to give it a group of its own.")
	list:add(list:row(6), 6)
	rows = list:row(10)
	rows.pool = {}
	list:add(rows, function() return rows.height or 1 end, nil, layoutRows)
	buildLoose()
end

------------------------------------------------------------------------
-- The chosen group: its name, its elements right under it, then its settings
------------------------------------------------------------------------
local BOX_PAD = 6      -- the elements' box: its inset around the chips
local BOX_TOP = 5      -- and its gap under the group's name
local CAPTION_H = 22   -- the Elements caption above the chips

-- The id of the group whose name is being edited. Enter or Accept saves it; Escape or Cancel leaves
-- it as it was. Choosing another group (or the group going) ends the edit. Renaming works in combat:
-- it only changes a saved name and our own frames, and the HUD's labels wait for the layout.
local renaming

local function stopRename()
	renaming = nil
	view.head.box:ClearFocus()
	ns.Options.refresh()
end

local function acceptRename()
	if not renaming then return end
	ns.renameGroup(renaming, view.head.box:GetText())
	stopRename()
end

local function startRename()
	local g = selected()
	if not g then return end
	renaming = g.id
	local box = view.head.box
	box:SetText(g.name)
	box:Show()
	box:SetFocus()
	box:HighlightText()
	ns.Options.refresh()
end

-- The header's Rename button and, while renaming, the name box with Accept and Cancel beside it.
local function renameControls(head)
	local function button(text, width, onClick)
		local b = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		b:SetText(text)
		b:SetScript("OnClick", onClick)
		return b
	end
	head.rename = button("Rename", 76, startRename)
	head.rename:SetPoint("BOTTOMRIGHT", 0, 6)
	setTip(head.rename, "Rename", "A name another group has gets a number added.")
	local box = CreateFrame("EditBox", nil, head, "InputBoxTemplate")
	box:SetSize(200, 20)
	box:SetPoint("BOTTOMLEFT", head.textX + 6, 6)
	box:SetAutoFocus(false)
	box:SetMaxLetters(ns.MAX_GROUP_NAME)
	box:SetFontObject("GameFontHighlight")
	box:SetScript("OnEnterPressed", acceptRename)
	box:SetScript("OnEscapePressed", stopRename)
	box:Hide()
	head.box = box
	head.accept = button("Accept", 70, acceptRename)
	head.accept:SetPoint("LEFT", box, "RIGHT", 8, 0)
	head.cancel = button("Cancel", 70, stopRename)
	head.cancel:SetPoint("LEFT", head.accept, "RIGHT", 4, 0)
end

-- The header: the group's name and count, or the name being edited.
local function paintHead()
	local g, head = selected(), view.head
	local n = #g.members
	head.text:SetText(g.name)
	head.note:SetText(n == 1 and "1 element" or n .. " elements")
	if renaming and renaming ~= g.id then renaming = nil end
	local editing = renaming ~= nil
	if not editing and head.box:HasFocus() then head.box:ClearFocus() end
	head.text:SetShown(not editing)
	head.note:SetShown(not editing)
	head.rename:SetShown(not editing)
	head.box:SetShown(editing)
	head.accept:SetShown(editing)
	head.cancel:SetShown(editing)
end

-- The elements: a box right under the name, the chips in their order.
local function buildBox(p)
	local box = p:row(10)
	local bg = CreateFrame("Frame", nil, box, "BackdropTemplate")
	bg:SetPoint("TOPLEFT", 0, -BOX_TOP)
	bg:SetPoint("BOTTOMRIGHT", 0, 6)
	Page.panelBackdrop(bg)
	local inner = CreateFrame("Frame", nil, bg)
	inner:SetPoint("TOPLEFT", BOX_PAD, -BOX_PAD)
	inner:SetPoint("BOTTOMRIGHT", -BOX_PAD, BOX_PAD)
	inner.pool, inner.top = {}, CAPTION_H
	local caption = inner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	caption:SetPoint("TOPLEFT", 2, -3)
	caption:SetText("Elements")
	local hint = inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetJustifyH("LEFT")
	hint:SetText("Drag to reorder, or onto a group to move it.")
	local empty = inner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetText("Empty. Drop an element here.")
	view.box, view.inner, view.line = box, inner, Page.dropLine(inner)
	-- The hint beside the caption, or under it in a narrow column; the chips start below both.
	local function placeCaption(w)
		hint:ClearAllPoints()
		hint:SetWidth(0)   -- unbounded, so it measures its whole line
		if caption:GetStringWidth() + 10 + hint:GetStringWidth() <= w - 4 then
			hint:SetPoint("LEFT", caption, "RIGHT", 10, 0)
			inner.top = CAPTION_H
		else
			hint:SetWidth(w - 4)
			hint:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -4)
			inner.top = math.ceil(3 + caption:GetStringHeight() + 4 + hint:GetStringHeight() + 6)
		end
		empty:SetPoint("TOPLEFT", 2, -inner.top - 5)
	end
	p:add(box, function() return box.height or 1 end, nil, function()
		placeCaption(p:width() - 2 * BOX_PAD)
		local g = selected()
		local keys = g and g.members or {}
		local h = placeChips(inner, keys, inner.top)
		empty:SetShown(#keys == 0)
		box.height = BOX_TOP + inner.top + math.max(h, CHIP_STEP) + 2 * BOX_PAD + 6
		box:SetHeight(box.height)
	end)
end

local function buildSettings(p)
	local G = selected
	local function get(key) return function() local g = G(); return g and g[key] end end
	-- The page owns what the chosen group's rows write (it has no blocks), for a reset of the group.
	local function owns(key, reset) p:owns({ group = G, name = key, after = relayout, reset = reset }) end
	local function set(key)
		owns(key)
		return function(v) local g = G(); if g then g[key] = v; relayout() end end
	end
	local show = p:dropdown("Show", "When the group is on screen. Everything visible shows while positioning is unlocked.",
		K.COMBAT_SHOW, get("show"), set("show"), nil, 240)
	p:sub(show, function() local g = G(); return g ~= nil and g.show ~= "always" end, function()
		p:slider("Stay after combat", K.STAY_TIP, 0, 10, 1, K.staySecs, get("fadeAfter"), set("fadeAfter"))
	end)
	p:text("Elements have their own Show setting too. An element shows only when both allow it.")
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, get("orientation"), set("orientation"))
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, get("growth"), set("growth"))
	p:slider("Spacing", "Gap between the group's elements. Below 0 they overlap.", -20, 40, 1, int, get("spacing"), set("spacing"))
	owns("sizeFollow")
	local follow = K.generalRow(p, "Icon size same as General", "Use the icon size on the General page.",
		get("sizeFollow"),
		function(v)
			local g = G()
			if not g then return end
			if not v then g.size = db().iconSize end   -- its own starts from General's, so nothing jumps
			g.sizeFollow = v
			relayout()
		end, "size")
	p:sub(follow, function() local g = G(); return g ~= nil and not g.sizeFollow end, function()
		p:slider("Icon size", nil, 24, 96, 1, int, get("size"), set("size"))
	end)
	p:text("Icon size keeps borders and rings crisp. Scale grows everything, borders and rings included.")
	local function setScale(v)
		local g = G()
		if not g then return end
		-- Offsets are in the group's own units: rescale them so the centre stays put.
		if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
		g.scale = v
		relayout()
	end
	owns("scale", function() setScale(ns.GROUP_DEFAULTS.scale) end)
	p:slider("Scale", "Grows everything in the group, borders and rings too.", 0.5, 3, 0.05, times,
		get("scale"), setScale)
	p:slider("Opacity", "Transparency of the group.", 0.1, 1, 0.05, pct, get("alpha"), set("alpha"))
	K.borderRows(p, G, relayout, "Border same as General")
	p:buttons({
		-- Hard to undo, so each asks first.
		{ "Centre on screen", function() askAbout("SHAMANFOREVER_CENTER", G()) end, "Moves the group to the middle of the screen.", 130 },
		{ "Hide all", function() askAbout("SHAMANFOREVER_HIDEALL", G()) end, "Sets every element in the group to Hidden. They keep their places; set one back to Always to bring it back.", 90 },
	})
	-- Not while its name is being edited: the edit belongs to the group.
	p:buttons({
		{ "Delete group", function() askDelete(G()) end, "Its elements move to Ungrouped: off screen, their settings kept.", 110,
			function() return renaming == nil end },
	})
	p:add(p:row(10), 10)
end

-- A group's menu, from a right-click on its row: the header's and the buttons' actions. Rename
-- chooses the group first.
function rowMenu(r)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local g = ns.groupById(r.id)
	if not g then return end
	MenuUtil.CreateContextMenu(r, function(_, root)
		root:CreateTitle(g.name)
		root:CreateButton("Rename", function()
			ns.Options.openGroup(g.id)
			startRename()
		end)
		root:CreateButton("Hide all", function() askAbout("SHAMANFOREVER_HIDEALL", g) end)
		root:CreateButton("Delete group", function() askDelete(g) end)
	end)
end

-- The header of the chosen group, when it is the group with this id (the page shows it).
function LP.headerOf(id)
	local g = selected()
	if g and g.id == id then return view.head end
end

-- The page: the group list on its left, the chosen group beside it.
function LP.build(p)
	page = p
	p.panels = false   -- one group's settings, under its name: no blocks to fold
	-- Folds this page saved when it showed every group at once are gone with them.
	local folded = ns.getAccount().foldedBlocks
	for key in pairs(folded) do
		if key:find("^layout:") then folded[key] = nil end
	end
	buildList()
	drag.ghost = Page.dragGhost(updateDragFeedback)
	p:text("No groups. New group makes one.", function() return #db().groups == 0 end)
	p.gate = function() return #db().groups > 0 end
	view.head = p:header(" ", nil, " ")
	renameControls(view.head)
	p.items[#p.items].refresh = paintHead
	buildBox(p)
	buildSettings(p)
	p.gate = nil
	-- Closed or left mid-drag (Escape, the key binding), the release may never come: drop nothing.
	-- A name being edited is left as it was.
	local function left()
		if drag.key then endDrag(false) end
		if renaming then stopRename() end
	end
	p.win:HookScript("OnHide", left)
	p.scroll:HookScript("OnHide", left)
end
