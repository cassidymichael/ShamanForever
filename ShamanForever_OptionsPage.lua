-- The options window's page kit: a page is a scrolling column of rows (headers, text, checkboxes,
-- sliders, dropdowns, colours, cards, buttons...). Rows can hide themselves; refresh reflows the
-- visible ones and pulls every control's value from the saved settings. Each header starts a block
-- that runs to the next header and sits on a faint panel; clicking the header folds the block. Rows
-- that only apply while another is on hang under it (Page:sub), indented, on a thin gold rule. Also
-- the drag and drop the pages' lists share. The pages themselves are built in
-- ShamanForever_Options.lua, Layout in ShamanForever_OptionsLayout.lua, and the elements' in
-- ShamanForever_OptionsElements.lua.

local _, ns = ...

local Page = {}
Page.__index = Page
ns.Page = Page

-- The window's geometry, shared with ShamanForever_Options.lua. The player may make it wider (the
-- nav keeps its width; the page takes the rest) and taller. Pages stay one column as wide as the
-- page: labels, sliders and dropdowns keep their widths, and text wraps at a readable width.
Page.WIDTH, Page.NAV_W = 864, 200   -- the least width; the nav: room for its element list's scroll bar
Page.PAGE_TOP = -38   -- pages start below the title bar
Page.LABEL_W = 150
local WIDTH, NAV_W, PAGE_TOP, LABEL_W = Page.WIDTH, Page.NAV_W, Page.PAGE_TOP, Page.LABEL_W
local ROW_W = WIDTH - NAV_W - 64                  -- initial row width; rows then follow the window
local SLIDER_SPAN_W = 400   -- a slider and its value box, at most
local TEXT_MAX_W = 600   -- text and boxed notices wrap here at the most (the page's width at 864)
-- A block's panel: its rows inset from its sides, room under its last row, a gap to the next block.
local PANEL_PAD, PANEL_PAD_B, BLOCK_GAP = 10, 6, 10
-- Folded blocks are saved with the account, by page and header text ("general:Border"), so they
-- stay folded across a /reload.
local function folded() return ns.getAccount().foldedBlocks end
local allPages = {}   -- every page made
-- A sub's rows: indented a level at a time, two at most, beside a rule down from under their parent.
local SUB_INDENT, SUB_MAX, RULE_X = 24, 2, 12

-- above: over the frame's top-left corner, for full-width rows, whose right edge is far from the
-- mouse on the label; otherwise to the right of the frame.
function Page.setTip(frame, title, text, above)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		if above then
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
		else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
-- A page of the options window (win), scrolling in the area right of the nav.
function Page.new(win, key, title, indent)
	-- Blizzard's modern scroll frame and slim bar; the old one if this client lacks it.
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", "ShamanForeverOptionsScroll_" .. key, win, "ScrollFrameTemplate")
	if not (ok and scroll and scroll.ScrollBar) then
		scroll = CreateFrame("ScrollFrame", "ShamanForeverOptionsScroll_" .. key .. "Old", win, "UIPanelScrollFrameTemplate")
	else
		if scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
		-- A clear gutter between the page and the slim bar.
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 14, 0)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 14, 0)
		-- A mouse wheel step: Blizzard's default is 30 px, about one row; two rows feels right.
		if scroll.SetPanExtent then scroll:SetPanExtent(64) end
	end
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	-- Update the scroll frame's child rect (its scroll range and the area where rows take clicks)
	-- after every resize and reflow, as Blizzard's pages do after a layout, so rows that a taller
	-- window or a longer page brings into view can be clicked. While the window is resized the page
	-- holds its place and is laid out once, at its end (Page.startResize).
	local page = setmetatable({ win = win, key = key, title = title, indent = indent, scroll = scroll,
		content = content, items = {}, blockList = {}, subs = {}, pageOwns = {}, ownIds = {} }, Page)
	scroll:SetScript("OnSizeChanged", function(self, w)
		if not Page.resizing then content:SetWidth(w) end
		self:UpdateScrollChildRect()
		page:keepScroll()
		if not Page.resizing then ns.Options.refresh() end
	end)
	content:SetScript("OnSizeChanged", function() scroll:UpdateScrollChildRect() end)
	-- Blizzard's handler, run first, sets the position again from its scroll bar's fraction of the
	-- range, and the range can come in a layout pass after ours: put the held place back after it.
	scroll:HookScript("OnScrollRangeChanged", function() if page.hold then page:keepScroll() end end)
	scroll:Hide()
	table.insert(allPages, page)
	return page
end

-- Resizing the window changes the scroll frame's size and range under the scroll bar, which keeps
-- the position as a fraction of the range and feeds back on itself (the range follows the frame,
-- the position follows the range), and that can send the page to the top. So from the grip's press
-- until two frames after its release the page holds its place and puts it back after every size
-- change, layout and range change, and it is not laid out while the grip is held: rows keep their
-- width, cut off or with room to spare, and one layout comes when the grip is let go. The row at
-- the top of the view stays there.
local resized   -- the page holding its place through a resize

function Page.startResize(page)
	if not page then return end
	Page.resizing, resized = true, page
	local offset = page.scroll:GetVerticalScroll()
	local hold = { offset = offset }
	-- The row at the top of the view, and how far into it the view starts.
	for _, it in ipairs(page.items) do
		if it.visible and it.y and it.y + it.h > offset then
			hold.row, hold.dy = it, offset - it.y
			break
		end
	end
	page.hold = hold
end

function Page.endResize()
	local page = resized
	Page.resizing, resized = nil, nil
	if not page then return end
	-- The widths the frozen size changes left alone, on every page; the page on show laid out now.
	for _, p in ipairs(allPages) do
		local w = p.scroll:GetWidth()
		if math.abs(p.content:GetWidth() - w) > 0.5 then
			p.content:SetWidth(w)
			p.scroll:UpdateScrollChildRect()
		end
	end
	if page.scroll:IsVisible() then page:refresh() end
	page:keepScroll()
	-- The layout the last size change queued, and the range changes it brings, come a frame later.
	local hold = page.hold
	C_Timer.After(0, function()
		page:keepScroll()
		C_Timer.After(0, function()
			if page.hold ~= hold then return end   -- a new resize holds it now
			page:keepScroll()
			page.hold = nil
		end)
	end)
end

-- Puts the held place back, within the range. At a range of 0 it waits for the next range change:
-- a page that fits has no place to keep, and the range may not be settled yet.
function Page:keepScroll()
	local hold, s = self.hold, self.scroll
	if not hold or hold.busy then return end
	local range = s:GetVerticalScrollRange()
	if range <= 0 then return end
	local want, row = hold.offset, hold.row
	if row and row.visible and row.y then want = row.y + hold.dy end
	want = math.max(0, math.min(want, range))
	if math.abs(s:GetVerticalScroll() - want) > 0.5 then
		hold.busy = true   -- not again from inside the scroll handlers setting it runs
		s:SetVerticalScroll(want)
		hold.busy = false
	end
end

-- shown: nil, or a function: the row is hidden while it returns false.
-- Set around a run of rows, like the gate: inset, a function returning the rows' left and right
-- margins inside the page (a second column); float, a function: while true, the rows after it start
-- level with it instead of below it, so it stands beside them (give them an inset to make room).
-- A page with panels = false (set before its first header) has no blocks: its rows use the whole
-- page, as the Groups & Layout page's group list does.
function Page:add(frame, height, shown, refresh)
	-- A page-wide gate (set around a run of rows) hides them all while it returns false.
	local gate = self.gate
	if gate then
		local inner = shown
		shown = function() return gate() and (not inner or inner()) and true or false end
	end
	local it = { frame = frame, height = height, shown = shown, refresh = refresh,
		inset = self.inset, float = self.float, block = self.block, sub = self.subRun }
	table.insert(self.items, it)
	if self.block then table.insert(self.block.items, it) end
	local run = self.subRun
	while run do table.insert(run.items, it); run = run.outer end
	return frame
end

-- Rows that apply only while parent (a row just added: a checkbox, a dropdown...) shows and
-- active() is true: build() adds them. They hide with their parent, sit a level in, and hang on a
-- thin gold rule from under the parent down to the last of them that shows. A sub inside a sub
-- goes one level deeper; two levels at most. Their own shown, if any, still applies.
function Page:sub(parent, active, build)
	local parentItem
	for i = #self.items, 1, -1 do
		if self.items[i].frame == parent then parentItem = self.items[i] break end
	end
	assert(parentItem, "Page:sub: the parent row is not on this page")
	local outer = self.subRun
	local run = { parent = parentItem, active = active, outer = outer, items = {},
		depth = (outer and outer.depth or 0) + 1 }
	assert(run.depth <= SUB_MAX, "Page:sub: two levels at most")
	table.insert(self.subs, run)
	self.subRun = run
	build()
	self.subRun = outer
end

-- The width of the row being refreshed (the page's, less its insets): what its controls fit into.
function Page:width() return self.rowW or self.content:GetWidth() end

-- A row that shows only while active() is true (and shown(), if given).
function Page.showWhen(active, shown)
	return function() return (not shown or shown()) and active() and true or false end
end

-- A block's panel, from top to bottom (down from the page's top): a faint fill and a thin border,
-- drawn on the page itself, under its rows.
local function placePanel(content, b, top, bottom)
	if not b.panel then
		local fill = content:CreateTexture(nil, "BACKGROUND")
		fill:SetColorTexture(1, 0.93, 0.78, 0.035)
		local edges = {}
		for i = 1, 4 do
			edges[i] = content:CreateTexture(nil, "BORDER")
			edges[i]:SetColorTexture(0.23, 0.17, 0.10, 1)
		end
		b.panel = { fill = fill, edges = edges }
	end
	local fill, e = b.panel.fill, b.panel.edges
	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
	fill:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", 0, -bottom)
	for i = 1, 4 do e[i]:ClearAllPoints() end
	e[1]:SetPoint("TOPLEFT", fill); e[1]:SetPoint("TOPRIGHT", fill); e[1]:SetHeight(1)
	e[2]:SetPoint("BOTTOMLEFT", fill); e[2]:SetPoint("BOTTOMRIGHT", fill); e[2]:SetHeight(1)
	e[3]:SetPoint("TOPLEFT", fill); e[3]:SetPoint("BOTTOMLEFT", fill); e[3]:SetWidth(1)
	e[4]:SetPoint("TOPRIGHT", fill); e[4]:SetPoint("BOTTOMRIGHT", fill); e[4]:SetWidth(1)
	fill:Show()
	for i = 1, 4 do e[i]:Show() end
end

local function hidePanel(b)
	if not b.panel then return end
	b.panel.fill:Hide()
	for i = 1, 4 do b.panel.edges[i]:Hide() end
end

function Page:refresh()
	if self.beforeRefresh then self.beforeRefresh() end
	if self.fixed then
		local ok, err = pcall(self.fixed.refresh, self.fixed)
		if not ok and not self.fixedReported then
			self.fixedReported = true
			ns.say("options: the %s page header failed to update: %s", self.key, tostring(err))
		end
	end
	local y, bottom = 0, 0   -- bottom: of any row standing beside others (float)
	local width = self.content:GetWidth()
	-- open: the block being laid out, while its header shows; gap: owed before the next row shown.
	local open, gap = nil, false
	local function close()
		if not open then return end
		y = math.max(y, open.low) + PANEL_PAD_B
		placePanel(self.content, open, open.top, y)
		open.drawn = true
		open, gap = nil, true
	end
	for _, b in ipairs(self.blockList) do b.drawn = false end
	local first, heads = nil, 0   -- the first block whose header shows, and how many show
	for _, it in ipairs(self.items) do
		local b = it.block
		if it.head then close() end   -- a header, shown or not, ends the block before it
		local show = not it.shown or it.shown()
		local sub = it.sub
		if show and sub then show = sub.parent.visible and sub.active() and true or false end
		-- A folded block keeps only its header; one whose header is hidden can't fold.
		if show and b and not it.head and b.head.visible and folded()[b.key] then show = false end
		it.visible = show
		it.frame:SetShown(show)
		if show then
			if gap or (it.head and y > 0) then y = y + BLOCK_GAP; gap = false end
			if it.head then open = b; b.top, b.low = y, y end
			local pad = open and b == open and PANEL_PAD or 0
			local left, right = 0, 0
			if it.inset then left, right = it.inset() end
			left, right = left + pad + (sub and sub.depth * SUB_INDENT or 0), right + pad
			self.rowW = width - left - right
			-- One failing row must not blank the rest of the page: report it once and carry on.
			if it.refresh then
				local ok, err = pcall(it.refresh)
				if not ok and not it.reported then
					it.reported = true
					ns.say("options: a row on the %s page failed to update: %s", self.key, tostring(err))
				end
			end
			if it.head then
				first, heads = first or b, heads + 1
				self:paintHeader(b, b == first)
			end
			it.frame:ClearAllPoints()
			it.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", left, -y)
			it.frame:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -right, -y)
			local h = type(it.height) == "function" and it.height() or it.height
			it.x, it.y, it.h = left, y, h
			if open and b == open then open.low = math.max(open.low, y + h) end
			if it.float and it.float() then bottom = math.max(bottom, y + h) else y = y + h end
		end
	end
	close()
	for _, b in ipairs(self.blockList) do if not b.drawn then hidePanel(b) end end
	self.heads = heads
	self:placeFoldBar(heads >= 2 and first or nil)
	for _, run in ipairs(self.subs) do self:placeRule(run) end
	self.rowW = nil
	self.content:SetHeight(math.max(y, bottom, 1))
	if self.hold then
		self.scroll:UpdateScrollChildRect()
		self:keepScroll()
	end
	if self.afterRefresh then self.afterRefresh() end
end

-- A sub's rule: from just under its parent's box down to near the foot of its last row shown.
function Page:placeRule(run)
	local parent, low = run.parent, nil
	if parent.visible then
		for _, it in ipairs(run.items) do
			if it.visible then low = math.max(low or 0, it.y + it.h) end
		end
	end
	local top, bottom = parent.y and parent.y + parent.h - 4, low and low - 6
	if not (low and bottom > top) then
		if run.rule then run.rule:Hide() end
		return
	end
	if not run.rule then
		run.rule = self.content:CreateTexture(nil, "ARTWORK")
		run.rule:SetColorTexture(0.85, 0.71, 0.42, 0.55)
		run.rule:SetWidth(1)
	end
	local x = parent.x + RULE_X
	run.rule:ClearAllPoints()
	run.rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -top)
	run.rule:SetPoint("BOTTOMLEFT", self.content, "TOPLEFT", x, -bottom)
	run.rule:Show()
end

-- Lays the page out again at once, its scroll range with it (after a fold).
function Page:relaid()
	self:refresh()
	local s = self.scroll
	s:UpdateScrollChildRect()
	local range = s:GetVerticalScrollRange()
	if s:GetVerticalScroll() > range then s:SetVerticalScroll(range) end
end

-- Folds or opens block b.
function Page:setFolded(b, fold)
	folded()[b.key] = fold or nil
	self:relaid()
end

-- Folds or opens every block whose header shows.
function Page:foldAll(fold)
	for _, b in ipairs(self.blockList) do
		if b.head.visible then folded()[b.key] = fold or nil end
	end
	self:relaid()
end

-- Opens the block holding frame (a row or a header), for a jump that lands on it.
function Page:reveal(frame)
	for _, it in ipairs(self.items) do
		if it.frame == frame then
			if it.block and folded()[it.block.key] then self:setFolded(it.block, false) end
			return
		end
	end
end

-- What a folded block has on: the names of its ticked boxes that show (not those in a sub), the
-- first three and a count.
local function onList(b)
	local on = {}
	for _, it in ipairs(b.items) do
		if it.says and not it.sub and (not it.shown or it.shown()) then
			local s = it.says()
			if s then table.insert(on, s) end
		end
	end
	if #on > 3 then return table.concat(on, ", ", 1, 3) .. " +" .. (#on - 3) end
	return table.concat(on, ", ")
end

-- The fold arrow before a header: the expand and collapse icons of Blizzard's trainer and
-- profession recipe headers, fitted to a 14 px box. A client without them gets the arrow from the
-- totem bar art, turned to point down while open and right while folded.
local ARROW_BOX = 14
local arrowAtlas = {}   -- atlas name -> its info, or false where the client lacks it
local function paintArrow(t, isFolded)
	local name = isFolded and "Professions-recipe-header-expand" or "Professions-recipe-header-collapse"
	local info = arrowAtlas[name]
	if info == nil then
		info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		if not (info and (info.width or 0) > 0 and (info.height or 0) > 0) then info = false end
		arrowAtlas[name] = info
	end
	if info then
		t:SetAtlas(name, false)
		local k = ARROW_BOX / math.max(info.width, info.height)
		t:SetSize(info.width * k, info.height * k)
	else
		t:SetTexture("Interface\\Buttons\\UI-TotemBar")
		t:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
		t:SetBlendMode("ADD")
		t:SetSize(12, 7)
		t:SetRotation(isFolded and -math.pi / 2 or math.pi)
	end
end

-- Fold all and Open all: two small arrow buttons at the right of the page's first header, on pages
-- with two blocks or more. Shift-click on any header does the same.
local FOLD_BAR_W, FOLD_BUTTON = 40, 18

-- The header's arrow and, folded, what's on. first: the page's first header, which leaves room for
-- the fold buttons.
function Page:paintHeader(b, first)
	local f = b.head.frame
	local isFolded = folded()[b.key] and true or false
	paintArrow(f.arrow, isFolded)
	f.says:SetShown(isFolded)
	if isFolded then
		local room = first and FOLD_BAR_W or 0
		f.says:SetPoint("BOTTOMRIGHT", -room, 9)
		f.says:SetText(onList(b))
		local used = f.textX + f.text:GetStringWidth() + (f.note and 10 + f.note:GetStringWidth() or 0)
		f.says:SetWidth(math.max(self.rowW - used - room - 24, 1))   -- cut short with "..." where it's long
	end
end

local function foldButton(bar, fold, x)
	local b = CreateFrame("Button", nil, bar)
	b:SetSize(FOLD_BUTTON, FOLD_BUTTON)
	b:SetPoint("RIGHT", x, 0)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetPoint("CENTER")
	paintArrow(b.tex, not fold)   -- the arrow that opens a folded block opens them all
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	local text = fold and "Fold all" or "Open all"
	Page.setTip(b, text, "Shift-click a header does the same.")
	return b
end

-- The fold buttons on head's block (nil: none), each dimmed while it would change nothing.
function Page:placeFoldBar(head)
	local bar = self.foldBar
	if not head then
		if bar then bar:Hide() end
		return
	end
	if not bar then
		bar = CreateFrame("Frame", nil, self.content)
		bar:SetSize(FOLD_BAR_W, FOLD_BUTTON)
		bar.open = foldButton(bar, false, -FOLD_BUTTON - 4)
		bar.fold = foldButton(bar, true, 0)
		bar.open:SetScript("OnClick", function() self:foldAll(false) end)
		bar.fold:SetScript("OnClick", function() self:foldAll(true) end)
		self.foldBar = bar
	end
	local frame = head.head.frame
	if bar:GetParent() ~= frame then
		bar:SetParent(frame)
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 7)
	end
	local anyFolded, anyOpen = false, false
	for _, b in ipairs(self.blockList) do
		if b.head.visible then
			if folded()[b.key] then anyFolded = true else anyOpen = true end
		end
	end
	for _, pair in ipairs({ { bar.open, anyFolded }, { bar.fold, anyOpen } }) do
		pair[1]:SetEnabled(pair[2])
		pair[1].tex:SetDesaturated(not pair[2])
		pair[1].tex:SetAlpha(pair[2] and 1 or 0.4)
	end
	bar:Show()
end

function Page:row(height)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetSize(ROW_W, height)
	return f
end

function Page:label(f, text, tip)
	f:EnableMouse(true)
	Page.setTip(f, text, tip, true)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

------------------------------------------------------------------------
-- What a block owns: the settings its rows write, as refs that the helpers binding rows to settings
-- add (Page:owns), so a block can tell whether it differs from the defaults, and reset them.
------------------------------------------------------------------------
-- A ref names one setting: { elem = key, name } (an element's own, db.elementOpts), { general =
-- name } (the profile's, db), { bar = "totembar" or "swing", name }, { group = g or a function
-- returning it, name }. Any ref may also carry:
--   after    the follow-up its row runs after a change; a reset runs each one once
--   default  a function returning the value to compare with, in place of its kind's
--   reset    a function of the ref that resets it, in place of its kind's: for a row that does
--            more than store the value (a group's Scale keeps its centre, Show goes through
--            ns.setShow). It returns false when it can't now (Show in combat), as by hand.
--   label    what a refused reset is called, in the line that says so
local REF = {}

-- A kind of ref. spec.id(ref): unique per setting, for one ref per setting in a block. A stored
-- value: holder(ref), the table it is saved in (nil while there is none: no group chosen);
-- slot(ref), its field there; default(ref); unset, true where nil means the default (a reset clears
-- it; otherwise a reset stores a copy of the default). A kind that is more than a stored value
-- gives changed(ref) and reset(ref) instead.
function Page.refKind(kind, spec) REF[kind] = spec end

local function copy(v) return type(v) == "table" and CopyTable(v) or v end

-- Whether two saved values are the same: tables field by field, numbers to a hair (a typed 0.33).
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" then return math.abs(a - b) < 1e-6 end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end
Page.same = same

local function defaultOf(r)
	if r.default then return r.default() end
	return REF[r.kind].default(r)
end
Page.refDefault = defaultOf

local function refChanged(r)
	local k = REF[r.kind]
	if k.changed then return k.changed(r) end
	local t = k.holder(r)
	if not t then return false end
	local v = t[k.slot(r)]
	if v == nil and k.unset then return false end
	return not same(v, defaultOf(r))
end

-- Resets every ref in list, then the follow-ups once each: the rows' own, the glows' restyle and a
-- relayout (which repaints the options). The same path as changing each setting by hand, so its
-- combat rules hold: layout waits for combat to end, aura buttons restyle out of combat, and what
-- can't change in combat is left, said once.
local function resetRefs(list)
	local afters, seen, refused = {}, {}, {}
	for _, r in ipairs(list) do
		local k = REF[r.kind]
		local done
		if r.reset then done = r.reset(r)
		elseif k.reset then done = k.reset(r)
		else
			local t = k.holder(r)
			if t then
				if k.unset then t[k.slot(r)] = nil else t[k.slot(r)] = copy(defaultOf(r)) end
			end
		end
		if done == false then table.insert(refused, r.label or r.name) end
		if r.after and not seen[r.after] then
			seen[r.after] = true
			table.insert(afters, r.after)
		end
	end
	if not seen[ns.Options.kit.relayout] then table.insert(afters, ns.Options.kit.relayout) end
	ns.Effects.applyStyle()
	for _, f in ipairs(afters) do f() end
	if #refused > 0 then
		ns.say("layout changes wait until combat ends; not reset: %s", table.concat(refused, ", "))
	end
end

local function anyChanged(list)
	for _, r in ipairs(list) do if refChanged(r) then return true end end
	return false
end

-- Asks before run(), a reset of what name names (the dialog: ShamanForever_Options.lua).
local function askReset(name, run) StaticPopup_Show("SHAMANFOREVER_RESET_SETTINGS", name, nil, run) end

-- An element's own setting; field: one field of a table setting (its Expiring's). Unset is its
-- default.
Page.refKind("elem", {
	id = function(r) return r.elem .. "." .. r.name .. (r.field and "." .. r.field or "") end,
	holder = function(r)
		local o = ns.elementOpts(r.elem)
		if not r.field then return o end
		return type(o[r.name]) == "table" and o[r.name] or nil
	end,
	slot = function(r) return r.field or r.name end,
	default = function(r) return ns.elementDefault(r.elem, r.name) end,
	unset = true,
})
Page.refKind("general", {
	id = function(r) return r.general end,
	holder = function() return ns.getDB() end,
	slot = function(r) return r.general end,
	default = function(r) return ns.DEFAULTS[r.general] end,
})
local BARS = { totembar = "TotemBar", swing = "Swing" }   -- their modules (cfg, DEFAULTS)
Page.refKind("bar", {
	id = function(r) return r.bar .. "." .. r.name end,
	holder = function(r) return ns[BARS[r.bar]].cfg() end,
	slot = function(r) return r.name end,
	default = function(r) return ns[BARS[r.bar]].DEFAULTS[r.name] end,
})
-- A group's default: the profile's shipped group with its id and name (ns.DEFAULTS.groups), where
-- that one sets it, else the new-group template's.
local function groupOf(r) if type(r.group) == "function" then return r.group() end return r.group end
Page.refKind("group", {
	id = function(r) return tostring(r.group) .. "." .. r.name end,
	holder = groupOf,
	slot = function(r) return r.name end,
	default = function(r)
		local g = groupOf(r)
		for _, shipped in ipairs(g and ns.DEFAULTS.groups or {}) do
			if shipped.id == g.id and shipped.name == g.name and shipped[r.name] ~= nil then
				return shipped[r.name]
			end
		end
		return ns.GROUP_DEFAULTS[r.name]
	end,
})

-- Adds ref to the block being built; a row outside any block (a page with panels = false) adds it
-- to the page's own list, which only a whole-page reset reads.
function Page:owns(ref)
	for kind in pairs(REF) do
		if ref[kind] ~= nil then ref.kind = kind end
	end
	assert(ref.kind, "Page:owns: a ref of no known kind")
	local into = self.block or self
	local id = ref.kind .. ":" .. REF[ref.kind].id(ref)
	if into.ownIds[id] then return end
	into.ownIds[id] = true
	table.insert(into == self and self.pageOwns or into.owns, ref)
end

-- A block: its header's text (name), fold key, rows (items) and refs (owns).
local Block = {}
Block.__index = Block
function Block:changed() return anyChanged(self.owns) end
function Block:reset() resetRefs(self.owns) end
function Block:askReset() askReset(self.name, function() self:reset() end) end

-- The whole page: every block's refs and its own.
function Page:refs()
	local out = {}
	for _, r in ipairs(self.pageOwns) do table.insert(out, r) end
	for _, b in ipairs(self.blockList) do
		for _, r in ipairs(b.owns) do table.insert(out, r) end
	end
	return out
end
function Page:changed() return anyChanged(self:refs()) end
function Page:reset() resetRefs(self:refs()) end
-- name: what the question calls the page ("Stormstrike").
function Page:askReset(name) askReset(name, function() self:reset() end) end

-- A header starts a block, which runs to the next one. icon: an optional texture before the text.
function Page:header(text, shown, note, icon)
	local f = self:row(36)
	local block, x = nil, 0
	if self.panels ~= false then
		-- Named by its text, so the saved fold state survives changes to the blocks before it; a
		-- second header with the same text on a page gets a number.
		self.blockKeys = self.blockKeys or {}
		local key = self.key .. ":" .. text
		if self.blockKeys[key] then key = key .. "#" .. #self.blockList end
		self.blockKeys[key] = true
		block = setmetatable({ index = #self.blockList + 1, key = key, name = text, items = {}, owns = {},
			ownIds = {} }, Block)
		table.insert(self.blockList, block)
		self.block = block
		-- The fold arrow (painted by paintHeader).
		f.arrow = f:CreateTexture(nil, "ARTWORK")
		f.arrow:SetPoint("CENTER", f, "BOTTOMLEFT", 6, 15)
		f.says = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.says:SetPoint("BOTTOMRIGHT", 0, 9)
		f.says:SetJustifyH("RIGHT")
		f.says:SetWordWrap(false)
		f.says:Hide()
		x = 16
	end
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.textX = x + (icon and 26 or 0)
	f.text:SetPoint("BOTTOMLEFT", f.textX, 7)
	if icon then
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetSize(20, 20)
		f.icon:SetPoint("BOTTOMLEFT", x, 5)
		f.icon:SetTexture(icon)
		ns.cropIcon(f.icon)
	end
	f.text:SetText(text)
	if note then
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 10, 1)
		f.note:SetText(note)
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 1)
	line:SetHeight(1)
	pcall(line.SetGradient, line, "HORIZONTAL", CreateColor(0.85, 0.71, 0.42, 0.45), CreateColor(0.85, 0.71, 0.42, 0))
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
	self:add(f, 36, shown)
	if block then
		block.head = self.items[#self.items]
		block.head.head = true
		-- The whole header folds and opens its block (with Shift, every block), and lights up under
		-- the mouse. Its tooltip, like the fold buttons, only on a page with two blocks or more.
		local r, g, bl = f.text:GetTextColor()
		f:EnableMouse(true)
		f:SetScript("OnEnter", function()
			f.text:SetTextColor(1, 0.93, 0.6)
			if (self.heads or 0) < 2 then return end
			GameTooltip:SetOwner(f, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", f.textX, -4)
			GameTooltip:SetText(text)
			GameTooltip:AddLine("Shift-click to fold or open every block.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function()
			f.text:SetTextColor(r, g, bl)
			GameTooltip:Hide()
		end)
		f:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			local fold = not folded()[block.key]
			if IsShiftKeyDown() then self:foldAll(fold) else self:setFolded(block, fold) end
		end)
	end
	return f
end

-- A page's own title, above its blocks: in the title style of the element pages' headers, with no
-- panel and no fold.
function Page:pageTitle(text)
	local f = self:row(40)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.text:SetPoint("BOTTOMLEFT", 4, 8)
	f.text:SetShadowOffset(1, -1)
	f.text:SetText(text)
	return self:add(f, 40)
end

-- A brief gold glow behind a row (a header), to show where a button has brought the reader. The
-- glow and its animation are made on first use and nothing runs between flashes.
function Page.flash(_, frame)
	local flash = frame.flashAnim
	if not flash then
		local glow = frame:CreateTexture(nil, "BACKGROUND")
		glow:SetPoint("TOPLEFT", -6, 2)
		glow:SetPoint("BOTTOMRIGHT", 6, -2)
		glow:SetColorTexture(0.88, 0.66, 0.29, 0.35)
		glow:SetAlpha(0)
		flash = glow:CreateAnimationGroup()
		local up = flash:CreateAnimation("Alpha")
		up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.35); up:SetOrder(1)
		local down = flash:CreateAnimation("Alpha")
		down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.9); down:SetOrder(2)
		flash:SetLooping("NONE")
		frame.flashAnim = flash
	end
	flash:Stop()
	flash:Play()
end

-- Names the last row added, for ns.Options.openGeneral and the like to scroll to.
function Page:anchor(name)
	self.anchors = self.anchors or {}
	self.anchors[name] = self.items[#self.items].frame
end

-- Wraps to the page width; the row grows to fit. str may be a function, re-read on every refresh.
-- Helper text, in grey so it reads apart from the controls.
local HELP_GREY = 0.72
function Page:text(str, shown)
	local f = self:row(20)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetTextColor(HELP_GREY, HELP_GREY, HELP_GREY)
	f.text:SetPoint("TOPLEFT", 4, -4)
	f.text:SetJustifyH("LEFT")
	f.text:SetSpacing(2)
	return self:add(f, function() return f.text:GetStringHeight() + 12 end, shown, function()
		f.text:SetWidth(math.min(self:width() - 8, TEXT_MAX_W))
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
	cb:SetScript("OnClick", function(button) set(button:GetChecked() and true or false) end)
	Page.setTip(cb, label, tip)
	f.check = cb
	self:add(f, 30, shown, function() cb:SetChecked(get() and true or false) end)
	self.items[#self.items].says = function() return get() and label or nil end   -- for a folded header
	return f
end

-- How a slider's value reads in the box beside it, where the player can also type one.
function Page.pct(v) return string.format("%.0f%%", v * 100) end
function Page.times(v) return string.format("%.2fx", v) end
function Page.int(v) return string.format("%d", v) end
function Page.px(v) return string.format("%d px", v) end
local NUMBER = "%-?%d*%.?%d+"   -- the first number in a text: "44", "-5", "1.25", "44 px", "100%"
local BOX_W, BOX_GAP = 52, 10

-- A value's units as its label shows them: how many label units one of the value's makes (100 for
-- a percent of a 0-1 value, else 1), and the decimals the label shows. Read from the label at the
-- top of the range, or the bottom where the top reads as a word ("Off").
local function unitsOf(fmt, minV, maxV)
	for _, v in ipairs({ maxV, minV }) do
		local text = fmt(v)
		local shown = tonumber(text:match(NUMBER) or "")
		if shown and v ~= 0 then
			local per = math.abs(shown - v * 100) < math.abs(shown - v) and 100 or 1
			local decimals = text:match("%d%.(%d+)")
			return per, decimals and #decimals or 0
		end
	end
	return 1, 0
end

-- fmt: Page.px, Page.int, Page.times, Page.pct or a function of the row's own (seconds, "Off").
-- The slider moves in steps; a number typed in the box takes effect on Enter as typed, in the
-- label's units and to the decimals it shows, held to the slider's range, with the slider at the
-- nearest step. Escape, or leaving the box any other way, keeps the value as it was.
function Page:slider(label, tip, minV, maxV, step, fmt, get, set, shown)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local s = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	s:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	local updating = false   -- while the page sets the value itself
	local per, decimals = unitsOf(fmt, minV, maxV)
	local function snap(v)
		v = math.floor(v / step + 0.5) * step
		if step < 1 then v = tonumber(string.format("%.2f", v)) end
		return v
	end
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5))
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		v = snap(v)
		set(v)
		box:ClearFocus()   -- moving the slider drops a number half typed
		box:SetText(fmt(v))
	end, s)
	box:SetSize(BOX_W, 20)
	box:SetPoint("LEFT", s, "RIGHT", BOX_GAP, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(8)
	box:SetFontObject("GameFontHighlight")
	box:SetJustifyH("CENTER")
	-- While typing, the bare number (in the label's units); otherwise the value as it reads.
	box:SetScript("OnEditFocusGained", function(b)
		local text = string.format("%." .. decimals .. "f", (get() or minV) * per)
		if decimals > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
		b:SetText(text)
		b:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(b)
		b:HighlightText(0, 0)
		b:SetText(fmt(get() or minV))
	end)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", function(b)
		local n = tonumber((b:GetText():gsub(",", ".")):match(NUMBER) or "")
		if n then
			local scale = 10 ^ decimals
			n = math.floor(n * scale + 0.5) / scale / per
			-- Rounded again past the label's decimals, so a percent's 0.33 isn't 0.33000000000000002.
			local v = tonumber(string.format("%." .. (decimals + (per == 100 and 2 or 0)) .. "f", n))
			v = math.min(math.max(v, minV), maxV)
			set(v)
			updating = true
			s:SetValue(get() or v)
			updating = false
		end
		b:ClearFocus()
	end)
	return self:add(f, 34, shown, function()
		-- The slider and its box share the row's width, up to their own; the slider takes what the
		-- box leaves, so a narrow window never pushes the box past its edge.
		local span = math.min(self:width() - LABEL_W - 8, SLIDER_SPAN_W)
		s:SetWidth(math.max(span - BOX_GAP - BOX_W, 80))
		-- Set only when it differs: setting it formats and lays out the slider again.
		local v = get() or minV
		if not (s.Slider and s.Slider:GetValue() == v) then
			updating = true
			s:SetValue(v)
			updating = false
		end
		if not box:HasFocus() then box:SetText(fmt(v)) end
	end)
end

-- choices: list of { value, text }, or a function returning one. A choice's init(button), if it has
-- one, dresses its line in the open list (Blizzard's menu initializer: button.fontString is the text).
function Page:dropdown(label, tip, choices, get, set, shown, width)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dd:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	dd:SetWidth(width or 200)
	dd:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(400)   -- a long list (fonts, textures) scrolls past 400 px
		for _, c in ipairs(type(choices) == "function" and choices() or choices) do
			local item = rootDescription:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
			if c.init then item:AddInitializer(c.init) end
		end
	end)
	f.dropdown = dd
	-- The menu is made again (its text with it) only when the value or the choices changed since the
	-- last refresh: making it is the costliest part of a page's refresh. A row with a menu of its own
	-- (SetupMenu after this) gives a get that changes whenever its text should.
	-- Never while the list is open: Blizzard rebuilds an open menu in place, and a scrolling one
	-- keeps its old rows in its scroll list (blank gaps). A change then waits for it to close.
	local was
	local function update()
		local now = tostring(get())
		if type(choices) == "function" then
			for _, c in ipairs(choices()) do now = now .. "\1" .. tostring(c[1]) .. "=" .. tostring(c[2]) end
		end
		if now ~= was and not dd:IsMenuOpen() then
			was = now
			dd:GenerateMenu()
		end
	end
	dd:RegisterCallback("OnMenuClose", function() C_Timer.After(0, update) end, f)
	return self:add(f, 34, shown, update)
end

-- A colour swatch; clicking opens Blizzard's colour picker, with opacity unless opaque (a colour
-- that can only be solid, like one inside text). get/set use { r, g, b, a }.
function Page:color(label, tip, get, set, shown, opaque)
	local f = self:row(30)
	self:label(f, label, tip)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(22, 22)
	b:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.5, 0.5, 0.5, 1)   -- shows through a translucent colour
	b:SetBackdropBorderColor(1, 1, 1, 0.6)
	b.swatch = b:CreateTexture(nil, "ARTWORK")
	b.swatch:SetPoint("TOPLEFT", 2, -2)
	b.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetScript("OnClick", function()
		local c = get()
		if not c then return end
		local function apply()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			set({ r, g, bl, opaque and 1 or ColorPickerFrame:GetColorAlpha() })
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = not opaque,
			swatchFunc = apply, opacityFunc = apply,
			cancelFunc = function(prev) set({ prev.r, prev.g, prev.b, prev.a or 1 }) end,
		})
	end)
	Page.setTip(b, label, tip)
	return self:add(f, 30, shown, function()
		local c = get() or { 0.5, 0.5, 0.5, 1 }
		b.swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	end)
end

-- A button whose text follows the settings, e.g. Unlock / Lock.
function Page:button(textFn, onClick, tip, width, shown)
	local f = self:row(32)
	local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btn:SetSize(width or 160, 22)
	btn:SetPoint("LEFT", 0, 0)
	btn:SetScript("OnClick", onClick)
	btn:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText(textFn())
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return self:add(f, 32, shown, function() btn:SetText(textFn()) end)
end

-- list: { { text, onClick, tip, width, enabled }, ... }; enabled is an optional function.
function Page:buttons(list, shown)
	local f = self:row(32)
	local x = 0
	local toggles = {}
	for _, b in ipairs(list) do
		local w = b[4] or 140
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(w, 22)
		btn:SetPoint("LEFT", x, 0)
		btn:SetText(b[1])
		btn:SetScript("OnClick", b[2])
		Page.setTip(btn, b[1], b[3])
		if b[5] then toggles[btn] = b[5] end
		x = x + w + 6
	end
	return self:add(f, 32, shown, function()
		for btn, enabled in pairs(toggles) do btn:SetEnabled(enabled() and true or false) end
	end)
end

-- A page header pinned above the page's scrolling area (so an element's preview stays in view while
-- settings change). The scrollbar starts below it, so the header spans the full page width, with
-- the same margin on the right (from the window's inner edge) as on the left (from the nav).
function Page:pin(h)
	local win = self.win
	h:SetParent(win)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	h:SetPoint("TOPRIGHT", win, "TOPRIGHT", -22, PAGE_TOP)
	h:Hide()
	self.fixed = h
	self.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP - (h.heroH or ns.Look.HERO_H))
	return h
end

-- An element page's header (ShamanForever_OptionsLook.lua): art, identity and a live preview.
function Page:hero(key)
	return self:pin(ns.Look.buildHero(self.win, key))
end

-- The options' panel look: a dark fill and a thin border (brown unless given).
function Page.panelBackdrop(f, r, g, b)
	f:SetBackdrop(ns.BACKDROP)
	f:SetBackdropColor(0.09, 0.075, 0.06, 1)
	f:SetBackdropBorderColor(r or 0.23, g or 0.17, b or 0.10, 1)
end

-- Pick one value from a row of icon cards. choices: { value, text, icon, experimental feature name },
-- and optionally tag = a word for a plain badge in the same place (RECOMMENDED).
local CARD_W, CARD_H = 84, 84
function Page:cards(label, tip, choices, get, set, shown)
	local f = self:row(CARD_H + 8)
	self:label(f, label, tip)
	f.cards = {}
	for i, c in ipairs(choices) do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		b:SetSize(CARD_W, CARD_H)
		b:SetPoint("LEFT", f, "LEFT", LABEL_W + (i - 1) * (CARD_W + 6), 0)
		Page.panelBackdrop(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(34, 34)
		b.icon:SetPoint("TOP", 0, -8)
		b.icon:SetTexture(c[3])
		ns.cropIcon(b.icon)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("TOP", b.icon, "BOTTOM", 0, -5)
		b.text:SetWidth(CARD_W - 6)
		b.text:SetText(c[2])
		local badge = c[4] and ns.Look.expBadge(b, c[4]) or c.tag and ns.Look.tagBadge(b, c.tag)
		if badge then
			badge:SetScale(0.8)
			badge:SetPoint("BOTTOM", 0, 5)
		end
		b.value = c[1]
		b:SetScript("OnClick", function() set(c[1]); ns.Options.refresh() end)
		f.cards[i] = b
	end
	return self:add(f, CARD_H + 8, shown, function()
		local v = get()
		for _, b in ipairs(f.cards) do
			local on = b.value == v
			b:SetBackdropBorderColor(on and 0.88 or 0.23, on and 0.66 or 0.17, on and 0.29 or 0.10, 1)
			b.icon:SetDesaturated(not on)
			b.icon:SetAlpha(on and 1 or 0.7)
			b.text:SetTextColor(on and 1 or 0.75, on and 0.84 or 0.72, on and 0.5 or 0.68)
		end
	end)
end

-- Big buttons side by side, for the most common actions. list: { icon, titleFn, subtitleFn, onClick }.
function Page:bigButtons(list)
	local H, GAP = 56, 10
	local f = self:row(H + 8)
	local buttons = {}
	for i, t in ipairs(list) do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		Page.panelBackdrop(b, 0.55, 0.42, 0.22)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(36, 36)
		b.icon:SetPoint("LEFT", 12, 0)
		b.icon:SetTexture(t[1])
		ns.cropIcon(b.icon)
		b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -1)
		b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 1)
		b.sub:SetTextColor(0.78, 0.74, 0.68)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(0.88, 0.66, 0.29, 0.10)
		b:SetScript("OnClick", t[4])
		b.titleFn, b.subFn = t[2], t[3]
		buttons[i] = b
	end
	return self:add(f, H + 8, nil, function()
		local w = (self:width() - (#buttons - 1) * GAP) / #buttons
		for i, b in ipairs(buttons) do
			b:SetSize(w, H)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", (i - 1) * (w + GAP), 0)
			b.title:SetText(b.titleFn())
			b.sub:SetText(b.subFn())
		end
	end)
end

-- A boxed notice, e.g. the beta warning: as wide as the page, up to the width text wraps at.
function Page:callout(text, shown)
	local f = self:row(40)
	local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
	box:SetPoint("TOPLEFT")
	Page.panelBackdrop(box, 0.95, 0.59, 0.24)
	box:SetBackdropColor(0.95, 0.59, 0.24, 0.08)
	f.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", 12, -10)
	f.text:SetJustifyH("LEFT")
	f.text:SetText(text)
	return self:add(f, function() return f.text:GetStringHeight() + 30 end, shown, function()
		local w = math.min(self:width(), TEXT_MAX_W + 24)
		f.text:SetWidth(w - 24)
		box:SetSize(w, f.text:GetStringHeight() + 20)
	end)
end

-- Read-only text the player can select and copy (links cannot be clicked in game).
-- icon, color: an optional small icon before the label (a white one tinted, e.g. a site's logo).
function Page:copyField(label, value, icon, color)
	local f = self:row(30)
	local fs = self:label(f, label)
	if icon then
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetSize(18, 18)
		t:SetPoint("LEFT", 4, 0)
		t:SetTexture(icon)
		if color then t:SetVertexColor(color[1], color[2], color[3]) end
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 30, 0)
		fs:SetWidth(LABEL_W - 34)
	end
	local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	e:SetSize(380, 20)
	e:SetPoint("LEFT", f, "LEFT", LABEL_W + 6, 0)
	e:SetAutoFocus(false)
	e:SetText(value)
	e:SetCursorPosition(0)
	e:SetScript("OnTextChanged", function(box, user) if user then box:SetText(value); box:HighlightText() end end)
	e:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return self:add(f, 30)
end

-- An experimental feature and where to find it (feedback is About's own section, above the list).
function Page:experimental(name, where)
	local f = self:row(28)
	self:label(f, name)
	local w = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	w:SetText(where)
	return self:add(f, 28)
end

------------------------------------------------------------------------
-- Drag and drop in a list (the Groups & Layout page's elements, the totem bar's order): a ghost of
-- the dragged item follows the cursor, and a white line marks where it will land.
------------------------------------------------------------------------
-- The ghost: an icon and a label on the cursor while shown. onMove runs as it follows.
function Page.dragGhost(onMove)
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(180, 24)
	ghost:SetAlpha(0.9)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	ns.cropIcon(ghost.icon)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local sc = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 8, y / sc)
		onMove()
	end)
	return ghost
end

function Page.dropLine(parent)
	local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	line:SetColorTexture(0.95, 0.95, 0.95, 1)
	line:SetHeight(2)
	line:Hide()
	return line
end

-- Where a drop lands among items (top to bottom; skip(item) leaves out the one being dragged): its
-- place among the others, by the cursor's height, and those others.
function Page.dropPosition(items, skip)
	local _, cy = GetCursorPosition()
	local at, others = 1, {}
	for _, it in ipairs(items) do
		if not skip(it) then
			table.insert(others, it)
			local _, y = it:GetCenter()
			if y and y * it:GetEffectiveScale() > cy then at = #others + 1 end
		end
	end
	return at, others
end

-- The drop line above others[at], or under the last one. False when there are no others to place it by.
function Page.placeDropLine(line, others, at)
	line:ClearAllPoints()
	if #others == 0 then return false end
	if at <= #others then
		line:SetPoint("BOTTOMLEFT", others[at], "TOPLEFT", 0, 0)
		line:SetPoint("BOTTOMRIGHT", others[at], "TOPRIGHT", 0, 0)
	else
		line:SetPoint("TOPLEFT", others[#others], "BOTTOMLEFT", 0, 0)
		line:SetPoint("TOPRIGHT", others[#others], "BOTTOMRIGHT", 0, 0)
	end
	return true
end
