-- The options window's Groups & Layout page: the groups listed on the left (name, element count and
-- an icon strip), and beside the list every group as a panel of its own, in the list's order: its
-- name (Rename edits it in place), its elements right under it, then its settings. A panel folds
-- from its header, and folded it names its elements. Clicking a group in the list goes to its panel.
-- Drag an element onto a group in the list, onto a panel's elements (between two to set the order)
-- or its name, or onto New group for a group of its own; click one for a menu. The groups are
-- ShamanForever.lua's (db.groups): every change goes through its layout edits, which wait out
-- combat.
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
-- The chosen group: the one last gone to, marked gold in the list
------------------------------------------------------------------------
local chosen   -- its id
local reveal = false   -- scroll the list to the chosen group on the next refresh

-- Marks the group with this id, scrolled into the list's view next time the page draws.
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
K.confirm("SHAMANFOREVER_SPLIT", "Split %s into one group per element?\nPutting them back together is done by hand.", "Split up",
	function(id) ns.splitGroup(id) end)
K.confirm("SHAMANFOREVER_HIDEALL", "Hide every element in %s?\nEach one's Show setting becomes Hidden.", "Hide all",
	function(id) ns.hideGroup(id) end)
K.confirm("SHAMANFOREVER_DELETE_GROUP", "Delete the group %s?\n%s", "Delete", function(id)
	if ns.deleteGroup(id) then ns.Options.refresh() end
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
local slots = {}       -- the group panels, one per place in db.groups (buildSlot)

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

-- Where a drop on a panel's elements lands: its place among the others.
local function dropIndex(s)
	return Page.dropPosition(s.inner.shown, function(chip) return chip.key == drag.key end)
end

-- The drop target under the cursor: "new" (the New group button), "row" and a group's row in the
-- list, "box" and a panel (its elements), or "head" and a panel (its name). What's scrolled out of
-- view doesn't count.
local function targetUnderCursor()
	if list.scroll:IsMouseOver() then
		if newButton:IsVisible() and newButton:IsMouseOver() then return "new" end
		for _, r in ipairs(rows.pool) do
			if r:IsShown() and r:IsMouseOver() then return "row", r end
		end
		return
	end
	if not page.scroll:IsMouseOver() then return end
	for _, s in ipairs(slots) do
		if s.box:IsVisible() and s.box:IsMouseOver() then return "box", s end
		if s.head:IsVisible() and s.head:IsMouseOver() then return "head", s end
	end
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
	for _, s in ipairs(slots) do s.line:Hide() end
	if drag.kind ~= "box" then return end
	local s = drag.over
	local line, inner = s.line, s.inner
	local at, others = dropIndex(s)
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
	local at = kind == "box" and dropIndex(over)   -- while the dragged chip is still left out
	drag.key, drag.kind, drag.over = nil, nil, nil
	drag.ended = GetTime()
	drag.ghost:Hide()
	for _, s in ipairs(slots) do s.line:Hide() end
	newButton:UnlockHighlight()
	if not key then return end
	if kind == "new" then
		local done, id = ns.placeElement(key, "new")
		if done and id then ns.Options.openGroup(id) end
	elseif kind == "box" then
		local to = over.group()
		if to then ns.placeElement(key, to.id, at) end
	elseif kind == "row" or kind == "head" then
		local to = kind == "row" and ns.groupById(over.id) or over.group()
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
	r:SetScript("OnClick", function(self) ns.Options.openGroup(self.id) end)
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

local ensureSlots   -- below: a panel for every group

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
	-- The list shows and refreshes with the page, as a pinned header does (Page:pin), before the
	-- page lays out: the page's panels are made here as groups are added.
	page.fixed = s
	function s.refresh()
		placeColumns()
		ensureSlots()
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
-- A group's panel: its name, its elements, its settings. Each panel shows the group in its place in
-- db.groups, so deleting one moves the ones after it up a panel.
------------------------------------------------------------------------
-- Wide enough (a wide window), a panel's elements stand in a column left of its settings.
local WIDE_AT, MEMBERS_W, COLUMN_GAP = 680, 240, 18
local BOX_PAD = 6      -- the elements' box: its inset around the chips
local CAPTION_H = 22   -- the Elements caption above the chips
local function wide() return page.content:GetWidth() >= WIDE_AT end

-- The name being edited: { slot, id }, one at a time. Enter or Accept saves it; Escape or Cancel
-- leaves the name as it was. It belongs to the group it was started for: if that group leaves the
-- panel (deleted), the edit ends.
local renaming

local function stopRename()
	local r = renaming
	renaming = nil
	if r then r.slot.head.box:ClearFocus() end
	ns.Options.refresh()
end

local function acceptRename()
	local r = renaming
	if not r then return end
	ns.renameGroup(r.id, r.slot.head.box:GetText())
	stopRename()
end

local function startRename(s)
	local g = s.group()
	if not g then return end
	if renaming and renaming.slot ~= s then renaming.slot.head.box:ClearFocus() end
	renaming = { slot = s, id = g.id }
	local box = s.head.box
	box:SetText(g.name)
	box:Show()
	box:SetFocus()
	box:HighlightText()
	ns.Options.refresh()
end

-- The header's Rename button and, while renaming, the name box with Accept and Cancel beside it.
local function renameControls(s, head)
	local function button(text, width, onClick)
		local b = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		b:SetText(text)
		b:SetScript("OnClick", onClick)
		return b
	end
	head.rename = button("Rename", 76, function() startRename(s) end)
	head.rename:SetPoint("BOTTOMRIGHT", 0, 6)
	setTip(head.rename, "Rename", "A name another group has gets a number added.")
	-- A folded panel's element names end left of the button.
	head.says:ClearAllPoints()
	head.says:SetPoint("BOTTOMRIGHT", head.rename, "BOTTOMLEFT", -10, 3)
	head.saysRight = 86
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
local function paintHead(s)
	local g, head = s.group(), s.head
	local n = #g.members
	head.text:SetText(g.name)
	head.note:SetText(n == 1 and "1 element" or n .. " elements")
	if renaming and renaming.slot == s and renaming.id ~= g.id then renaming = nil end
	local editing = renaming ~= nil and renaming.slot == s
	if not editing and head.box:HasFocus() then head.box:ClearFocus() end
	head.text:SetShown(not editing)
	head.note:SetShown(not editing)
	head.rename:SetShown(not editing)
	head.box:SetShown(editing)
	head.accept:SetShown(editing)
	head.cancel:SetShown(editing)
	head.says:SetAlpha(editing and 0 or 1)
end

-- The elements: a box right under the name, the chips in their order.
local function buildBox(p, s)
	local box = p:row(10)
	local bg = CreateFrame("Frame", nil, box, "BackdropTemplate")
	bg:SetPoint("TOPLEFT")
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
	s.box, s.inner, s.line = box, inner, Page.dropLine(inner)
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
		local g = s.group()
		local keys = g and g.members or {}
		local h = placeChips(inner, keys, inner.top)
		empty:SetShown(#keys == 0)
		box.height = inner.top + math.max(h, CHIP_STEP) + 2 * BOX_PAD + 6
		box:SetHeight(box.height)
	end)
end

local function buildSettings(p, s)
	local G = s.group
	local function get(key) return function() local g = G(); return g and g[key] end end
	local function set(key) return function(v) local g = G(); if g then g[key] = v; relayout() end end end
	local show = p:dropdown("Show", "When the group is on screen. Everything visible shows while positioning is unlocked.",
		K.COMBAT_SHOW, get("show"), set("show"), nil, 226)
	p:sub(show, function() local g = G(); return g ~= nil and g.show ~= "always" end, function()
		p:slider("Stay after combat", K.STAY_TIP, 0, 10, 1, K.staySecs, get("fadeAfter"), set("fadeAfter"))
	end)
	p:text("Elements have their own Show setting too. An element shows only when both allow it.")
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, get("orientation"), set("orientation"))
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, get("growth"), set("growth"))
	p:slider("Spacing", "Gap between the group's elements.", 0, 40, 1, int, get("spacing"), set("spacing"))
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
		p:slider("Icon size", "Shift + mouse wheel over the group while unlocked does the same.", 24, 96, 1, int,
			get("size"), set("size"))
	end)
	p:text("Icon size keeps borders and rings crisp. Scale grows everything, borders and rings included.")
	p:slider("Scale", "Grows everything in the group, borders and rings too. Mouse wheel over the group while unlocked does the same.", 0.5, 3, 0.05, times,
		get("scale"), function(v)
			local g = G()
			if not g then return end
			-- Offsets are in the group's own units: rescale them so the centre stays put.
			if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
			g.scale = v
			relayout()
		end)
	p:slider("Opacity", "Transparency of the group. Ctrl + mouse wheel over the group while unlocked does the same.", 0.1, 1, 0.05, pct,
		get("alpha"), set("alpha"))
	K.borderRows(p, G, relayout, "Border same as General")
	p:buttons({
		-- Hard to undo, so each asks first.
		{ "Centre on screen", function() askAbout("SHAMANFOREVER_CENTER", G()) end, "Moves the group to the middle of the screen.", 130 },
		{ "Split up", function() askAbout("SHAMANFOREVER_SPLIT", G()) end, "Gives every element in the group a group of its own, left where it is.", 90 },
		{ "Hide all", function() askAbout("SHAMANFOREVER_HIDEALL", G()) end, "Sets every element in the group to Hidden. They keep their places; set one back to Always to bring it back.", 90 },
	})
	p:buttons({
		{ "Delete group", function() askDelete(G()) end, "Its elements move to Ungrouped: off screen, their settings kept.", 110 },
	})
end

-- The panel for the i-th group: made the first time there is one, then shown while there is.
local function buildSlot(p, i)
	local s = {}
	function s.group() return db().groups[i] end
	p.gate = function() return s.group() ~= nil end
	s.head = p:header(" ", nil, " ")
	s.block = p.block
	-- Folded, it names its elements.
	function s.block.summary()
		local g, names = s.group(), {}
		for _, key in ipairs(g and g.members or {}) do table.insert(names, elementName(key)) end
		return table.concat(names, ", ")
	end
	renameControls(s, s.head)
	p.items[#p.items].refresh = function() paintHead(s) end
	p.float = wide
	p.inset = function() return 0, wide() and p.content:GetWidth() - MEMBERS_W or 0 end
	buildBox(p, s)
	p.float = nil
	p.inset = function() return wide() and MEMBERS_W + COLUMN_GAP or 0, 0 end
	buildSettings(p, s)
	p.inset, p.gate = nil, nil
	slots[i] = s
end

-- A panel for every group, and each panel's fold kept by its group's id, so a folded group stays
-- folded when the ones before it are deleted.
function ensureSlots()
	local groups = db().groups
	for i = #slots + 1, #groups do buildSlot(page, i) end
	for i, s in ipairs(slots) do
		if groups[i] then s.block.key = "layout:group" .. groups[i].id end
	end
end

-- The header of the panel for the group with this id, once the page has drawn it.
function LP.headerOf(id)
	for i, g in ipairs(db().groups) do
		if g.id == id then return slots[i] and slots[i].head end
	end
end

-- The page: the group list on its left, every group's panel beside it.
function LP.build(p)
	page = p
	buildList()
	drag.ghost = Page.dragGhost(updateDragFeedback)
	p:text("No groups. New group makes one.", function() return #db().groups == 0 end)
	-- Closed or left mid-drag (Escape, the key binding), the release may never come: drop nothing.
	-- A name being edited is left as it was.
	local function left()
		if drag.key then endDrag(false) end
		if renaming then stopRename() end
	end
	p.win:HookScript("OnHide", left)
	p.scroll:HookScript("OnHide", left)
end
