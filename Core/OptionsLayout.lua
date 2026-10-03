-- Groups & Layout page: the group list and the chosen group
local _, ns = ...
local W = ns.Widgets
local G = ns.Groups
local E, P = ns.Elements, ns.Profiles

local LP = {}
ns.LayoutPage = LP

local Page, K = ns.Page, ns.Options.kit
local setTip = Page.setTip
local int, times, pct = Page.int, Page.times, Page.pct
local NAV_W, PAGE_TOP = Page.NAV_W, Page.PAGE_TOP
local relayout = K.relayout

local function db() return P.getDB() end

-- Chosen group
local chosen
local reveal = false

local function selected()
	local g = G.byId(chosen)
	if not g then
		g = db().groups[1]
		chosen = g and g.id
	end
	return g
end

function LP.choose(id)
	chosen = id
	reveal = true
end

local function askAbout(which, g)
	if g then StaticPopup_Show(which, g.name, nil, g.id) end
end
K.confirm(ns.POPUP .. "CENTER", "Move %s to the middle of the screen?\nIts current position is lost.", "Centre",
	function(id) G.center(id) end)
K.confirm(ns.POPUP .. "HIDEALL", "Hide every element in %s?\nEach one's Show setting becomes Hidden.", "Hide all",
	function(id) G.hide(id) end)
K.confirm(ns.POPUP .. "DELETE_GROUP", "Delete the group %s?\n%s", "Delete", function(id)
	local _, i = G.byId(id)
	if not (i and G.delete(id)) then return end
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
	StaticPopup_Show(ns.POPUP .. "DELETE_GROUP", g.name, what, g.id)
end

-- Element chips
local CHIP_STEP = 26
local drag = {}
local page, list, rows, loose, newButton
local view = {}

local function elementName(key) return ns.OptionsArt.elementName(key) end

local function chipText(key)
	local tags = {}
	if not E.isLearned(key) then table.insert(tags, E.notLearnedText(key):lower()) end
	local mode = E.showMode(key)
	if mode == "never" then table.insert(tags, "hidden")
	elseif mode == "combat" then table.insert(tags, "in combat") end
	if #tags == 0 then return elementName(key) end
	return elementName(key) .. "  |cff888888(" .. table.concat(tags, ", ") .. ")|r"
end

local function fillChip(chip, key)
	chip.key = key
	E.ALL[key].paint(chip.icon)
	local learned = E.isLearned(key)
	chip.icon:SetDesaturated(not learned)
	chip.text:SetText(chipText(key))
	chip:SetAlpha((learned and E.showMode(key) ~= "never") and 1 or 0.6)
end

local function dropIndex()
	return Page.dropPosition(view.inner.shown, function(chip) return chip.key == drag.key end)
end

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
	if not Page.placeDropLine(line, others, at) then
		line:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -inner.top + 1)
		line:SetPoint("TOPRIGHT", inner, "TOPRIGHT", 0, -inner.top + 1)
	end
	line:Show()
end

local function startDrag(chip)
	if InCombatLockdown() then ns.say("layout changes wait until combat ends"); return end
	drag.key = chip.key
	chip:SetAlpha(0.35)
	E.ALL[chip.key].paint(drag.ghost.icon)
	drag.ghost.text:SetText(elementName(chip.key))
	drag.ghost:Show()
end

local function endDrag(drop)
	local key = drag.key
	local kind, over
	if key and drop then kind, over = targetUnderCursor() end
	local at = kind == "box" and dropIndex()
	drag.key, drag.kind, drag.over = nil, nil, nil
	drag.ended = GetTime()
	drag.ghost:Hide()
	view.line:Hide()
	newButton:UnlockHighlight()
	if not key then return end
	if kind == "new" then
		local done, id = G.placeElement(key, "new")
		if done and id then ns.Options.openGroup(id) end
	elseif kind == "box" then
		local to = selected()
		if to then G.placeElement(key, to.id, at) end
	elseif kind == "row" then
		local to = G.byId(over.id)
		if to and to ~= G.of(key) then G.placeElement(key, to.id) end
	end
	ns.Options.refresh()
end
local function finishDrag() endDrag(true) end

local function chipMenu(chip)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	if drag.ended and GetTime() - drag.ended < 0.3 then return end
	local key = chip.key
	MenuUtil.CreateContextMenu(chip, function(_, root)
		root:CreateTitle(elementName(key))
		root:CreateButton("Element settings", function() ns.Options.openElement(key) end)
		root:CreateDivider()
		local g, i = G.of(key)
		if g and i > 1 then root:CreateButton("Move earlier", function() G.placeElement(key, g.id, i - 1) end) end
		if g and i < #g.members then root:CreateButton("Move later", function() G.placeElement(key, g.id, i + 1) end) end
		local to
		for _, o in ipairs(db().groups) do
			if o ~= g then
				to = to or root:CreateButton("Move to")
				to:CreateButton(o.name, function() G.placeElement(key, o.id) end)
			end
		end
		if not (g and #g.members == 1) then
			root:CreateButton("Move to a new group", function()
				local done, id = G.placeElement(key, "new")
				if done and id then ns.Options.openGroup(id) end
			end)
		end
		root:CreateDivider()
		root:CreateTitle("Show")
		for _, c in ipairs(K.SHOW_CHOICES) do
			root:CreateRadio(c[2], function() return E.showMode(key) == c[1] end, function() E.setShow(key, c[1]) end)
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
	W.cropIcon(chip.icon)
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

-- Group list
local LIST_W, LIST_W_WIDE, LIST_WIDE_AT = 196, 250, 1100
local ROWS_TOP = 42
local ROW_H, ROW_STEP = 42, 45
local ICON_STEP = 18

local rowMenu

local function newRow(parent)
	local r = CreateFrame("Button", nil, parent, "BackdropTemplate")
	r:SetBackdrop(W.BACKDROP)
	r:SetBackdropColor(0.09, 0.075, 0.06, 1)
	r:SetHeight(ROW_H)
	r.wash = r:CreateTexture(nil, "BACKGROUND", nil, 1)
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
			W.cropIcon(t)
			r.icons[i] = t
		end
		local key = g.members[i]
		E.ALL[key].paint(t)
		t:SetDesaturated(not E.isLearned(key))
		t:SetAlpha(E.showMode(key) == "never" and 0.45 or 1)
		t:Show()
	end
	for i = shown + 1, #r.icons do r.icons[i]:Hide() end
	r.more:ClearAllPoints()
	r.more:SetPoint("LEFT", r, "TOPLEFT", 8 + shown * ICON_STEP, -30)
	r.more:SetText(n == 0 and "Empty" or n > shown and ("+" .. (n - shown)) or "")
	rowBorder(r)
end

local function layoutRows()
	selected()
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

-- Ungrouped: elements whose group was deleted; not drawn, settings kept.
local LOOSE_TOP = 48

local function looseKeys()
	local keys = {}
	for _, key in ipairs(E.KEYS) do
		if not G.of(key) then table.insert(keys, key) end
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

local placedW
local function placeColumns()
	local w = page.win:GetWidth() >= LIST_WIDE_AT and LIST_W_WIDE or LIST_W
	if w == placedW then return end
	placedW = w
	list.scroll:SetWidth(w - 14)
	list.content:SetWidth(w - 14)
	page.scroll:SetPoint("TOPLEFT", page.win, "TOPLEFT", NAV_W + 18 + w + 12, PAGE_TOP)
end

local function buildList()
	list = Page.new(page.win, "layoutGroups")
	list.panels = false
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
		local done, id = G.add()
		if done and id then ns.Options.openGroup(id) end
	end)
	setTip(newButton, "New group", "An empty group. Drop an element here to give it a group of its own.")
	list:add(list:row(6), 6)
	rows = list:row(10)
	rows.pool = {}
	list:add(rows, function() return rows.height or 1 end, nil, layoutRows)
	buildLoose()
end

-- The chosen group
local BOX_PAD = 6
local BOX_TOP = 5
local CAPTION_H = 22

-- Rename works in combat: it only changes a saved name and our own frames.
local renaming

local function stopRename()
	renaming = nil
	view.head.box:ClearFocus()
	ns.Options.refresh()
end

local function acceptRename()
	if not renaming then return end
	G.rename(renaming, view.head.box:GetText())
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
	local function placeCaption(w)
		hint:ClearAllPoints()
		hint:SetWidth(0)
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
	local sel = selected
	local R, slider = P.GROUP_RANGES, K.rangeSlider
	local function get(key) return function() local g = sel(); return g and g[key] end end
	local function owns(key, reset) p:owns({ group = sel, name = key, after = relayout, reset = reset }) end
	local function set(key)
		owns(key)
		return function(v) local g = sel(); if g then g[key] = v; relayout() end end
	end
	local show = p:dropdown("Show", "When the group is on screen. Everything visible shows while positioning is unlocked.",
		K.COMBAT_SHOW, get("show"), set("show"), nil, 240)
	p:sub(show, function() local g = sel(); return g ~= nil and g.show ~= "always" end, function()
		slider(p, R.fadeAfter, "Stay after combat", K.STAY_TIP, K.staySecs, get("fadeAfter"), set("fadeAfter"))
	end)
	p:text("Elements have their own Show setting too. An element shows only when both allow it.")
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, get("orientation"), set("orientation"))
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, get("growth"), set("growth"))
	slider(p, R.spacing, "Spacing", "Gap between the group's elements. Below 0 they overlap.", int, get("spacing"),
		set("spacing"))
	owns("sizeFollow")
	local follow = K.globalRow(p, "Icon size same as Global", "Use the global icon size.",
		get("sizeFollow"),
		function(v)
			local g = sel()
			if not g then return end
			if not v then g.size = db().iconSize end
			g.sizeFollow = v
			relayout()
		end, "size")
	p:sub(follow, function() local g = sel(); return g ~= nil and not g.sizeFollow end, function()
		slider(p, R.size, "Icon size", nil, int, get("size"), set("size"))
	end)
	p:text("Icon size keeps borders and rings crisp. Scale grows everything, borders and rings included.")
	local function setScale(v)
		local g = sel()
		if not g then return end
		-- Offsets are in the group's units: rescaled so the centre stays put.
		if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
		g.scale = v
		relayout()
	end
	owns("scale", function(r) setScale(Page.refDefault(r)) end)
	slider(p, R.scale, "Scale", "Grows everything in the group, borders and rings too.", times, get("scale"), setScale)
	slider(p, R.alpha, "Opacity", "Transparency of the group.", pct, get("alpha"), set("alpha"))
	p:header("Group art frame")
	K.frameRows(p, sel, "groupframe", relayout, {
		note = "Doesn't fade with each element's Idle.",
		spacing = { get = get("spacing"), set = function(v) local g = sel(); if g then g.spacing = v; relayout() end end,
			min = R.spacing[1], max = R.spacing[2], size = function() return G.size(sel()) end } })
	p:text("Each element's border and art frame are on its own page.")
	p:buttons({
		{ "Centre on screen", function() askAbout(ns.POPUP .. "CENTER", sel()) end,
			"Moves the group to the middle of the screen.", 130 },
		{ "Hide all", function() askAbout(ns.POPUP .. "HIDEALL", sel()) end,
			"Sets every element in the group to Hidden. They keep their places; set one back to Always to bring it back.",
			90 },
	})
	p:buttons({
		{ "Delete group", function() askDelete(sel()) end,
			"Its elements move to Ungrouped: off screen, their settings kept.", 110,
			function() return renaming == nil end },
	})
	p:add(p:row(10), 10)
end

function rowMenu(r)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local g = G.byId(r.id)
	if not g then return end
	MenuUtil.CreateContextMenu(r, function(_, root)
		root:CreateTitle(g.name)
		root:CreateButton("Rename", function()
			ns.Options.openGroup(g.id)
			startRename()
		end)
		root:CreateButton("Hide all", function() askAbout(ns.POPUP .. "HIDEALL", g) end)
		root:CreateButton("Delete group", function() askDelete(g) end)
	end)
end

function LP.headerOf(id)
	local g = selected()
	if g and g.id == id then return view.head end
end

function LP.build(p)
	page = p
	p.panels = false
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
	-- Closed mid-drag the release may never come: drop nothing.
	local function left()
		if drag.key then endDrag(false) end
		if renaming then stopRename() end
	end
	p.win:HookScript("OnHide", left)
	p.scroll:HookScript("OnHide", left)
end

ns.Options.registerPage("layout", { title = "Groups & Layout", icon = "Interface\\Icons\\Spell_Nature_Invisibilty",
	order = 40, build = LP.build })
