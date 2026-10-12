-- Page kit: scrolling pages of rows grouped into foldable blocks

local _, ns = ...
local W = ns.Widgets
local E, G, Bars, P, MOD = ns.Elements, ns.Groups, ns.Bars, ns.Profiles, ns.Modules

local Page = {}
Page.__index = Page
ns.Page = Page

Page.WIDTH, Page.NAV_W = 864, 200
Page.PAGE_TOP = -38
Page.LABEL_W = 150
local WIDTH, NAV_W, PAGE_TOP, LABEL_W = Page.WIDTH, Page.NAV_W, Page.PAGE_TOP, Page.LABEL_W
local ROW_W = WIDTH - NAV_W - 64
local SLIDER_SPAN_W = 400
local TEXT_MAX_W = 600
local PANEL_PAD, PANEL_PAD_B, BLOCK_GAP = 10, 6, 10
-- Blocks start open; a folded one is saved by its page and header text.
local function folded() return P.getAccount().foldedBlocks end
local function isFolded(b) return folded()[b.key] == true end
local allPages = {}
-- Room kept under every page, above the window's foot (the off banner's), and each page's bottom point
local bottomInset = 0
function Page.bottomY() return 12 + bottomInset end
function Page.setBottomInset(h)
	bottomInset = h
	for _, p in ipairs(allPages) do p.scroll:SetPoint(p.bottom[1], p.win, p.bottom[1], p.bottom[2], Page.bottomY()) end
end
local SUB_INDENT, SUB_MAX, RULE_X = 24, 2, 12

Page.setTip = W.setTip

-- Page size: one scale on a page's blocks (the window, nav and header keep theirs), saved per account
Page.SCALES = { { 1, "100%" }, { 0.9, "90%" }, { 0.8, "80%" } }
local function scaleOK(v)
	for _, c in ipairs(Page.SCALES) do if c[1] == v then return true end end
	return false
end
MOD.register({ name = "page size", sanitize = function(_, acct)
	if not scaleOK(acct.pageScale) then acct.pageScale = 1 end
end })
local function savedScale()
	local a = P.getAccount()
	return a and scaleOK(a.pageScale) and a.pageScale or 1
end

-- Pages
function Page.new(win, key, title, indent)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", ns.NAME .. "OptionsScroll_" .. key, win, "ScrollFrameTemplate")
	if not (ok and scroll and scroll.ScrollBar) then
		scroll = CreateFrame("ScrollFrame", ns.NAME .. "OptionsScroll_" .. key .. "Old", win, "UIPanelScrollFrameTemplate")
	else
		if scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 14, 0)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 14, 0)
		if scroll.SetPanExtent then scroll:SetPanExtent(64) end
	end
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, Page.bottomY())
	-- The rows sit in content, which takes the page size; the scroll frame scrolls an unscaled holder
	-- of content's size on screen, so its range and offsets stay in its own units.
	local holder = CreateFrame("Frame", nil, scroll)
	holder:SetSize(ROW_W, 1)
	local content = CreateFrame("Frame", nil, holder)
	content:SetPoint("TOPLEFT")
	content:SetSize(ROW_W, 1)
	holder.content = content
	scroll:SetScrollChild(holder)
	local page = setmetatable({ win = win, key = key, title = title, indent = indent, scroll = scroll,
		bottom = { "BOTTOMRIGHT", -40 },
		holder = holder, content = content, scaled = 1, lines = {}, items = {}, blockList = {}, subs = {}, pageOwns = {},
		ownIds = {} }, Page)
	scroll:SetScript("OnSizeChanged", function(self, w)
		if not Page.resizing then page:fitWidth(w) end
		self:UpdateScrollChildRect()
		page:keepScroll()
		if not Page.resizing then ns.Options.refresh() end
	end)
	holder:SetScript("OnSizeChanged", function() scroll:UpdateScrollChildRect() end)
	-- Blizzard's handler re-sets the position from its scroll bar's fraction: the held place is put
	-- back after it.
	scroll:HookScript("OnScrollRangeChanged", function() if page.hold then page:keepScroll() end end)
	scroll:Hide()
	table.insert(allPages, page)
	return page
end

-- Resizing feeds back on itself (the range follows the frame, the position the range) and can send
-- the page to the top: from the grip's press until two frames after its release the page holds
-- its place, and it is laid out once at the end.
local resized

function Page.startResize(page)
	if not page then return end
	Page.resizing, resized = true, page
	page.hold = page:holdHere()
end

function Page.endResize()
	local page = resized
	Page.resizing, resized = nil, nil
	if not page then return end
	for _, p in ipairs(allPages) do
		if math.abs(p.holder:GetWidth() - p.scroll:GetWidth()) > 0.5 then
			p:fitWidth(p.scroll:GetWidth())
			p.scroll:UpdateScrollChildRect()
		end
	end
	if page.scroll:IsVisible() then page:refresh() end
	page:keepScroll()
	local hold = page.hold
	C_Timer.After(0, function()
		page:keepScroll()
		C_Timer.After(0, function()
			if page.hold ~= hold then return end
			page:keepScroll()
			page.hold = nil
		end)
	end)
end

-- What the view shows: the first row reaching below the view's top, shift lower (content's units)
function Page:holdHere(shift)
	local offset = (self.scroll:GetVerticalScroll() + (shift or 0)) / self.scaled
	local hold = { offset = offset }
	for _, it in ipairs(self.items) do
		if it.visible and it.y and it.y + it.h > offset then
			hold.row, hold.dy = it, offset - it.y
			break
		end
	end
	return hold
end

-- Held over the next frames as the range settles; a jump waiting to land wins over it
function Page:keepHeld(hold)
	if self.jump then return end
	self.hold = hold
	C_Timer.After(0, function()
		self:keepScroll()
		C_Timer.After(0, function()
			if self.hold ~= hold then return end
			self:keepScroll()
			self.hold = nil
		end)
	end)
end

-- At a range of 0 it waits for the next range change. A hold is in content's units.
function Page:keepScroll()
	local hold, s = self.hold, self.scroll
	if not hold or hold.busy then return end
	local range = s:GetVerticalScrollRange()
	if range <= 0 then return end
	local want, row = hold.offset, hold.row
	if row and row.visible and row.y then want = row.y + hold.dy end
	want = math.max(0, math.min(want * self.scaled, range))
	if math.abs(s:GetVerticalScroll() - want) > 0.5 then
		hold.busy = true
		s:SetVerticalScroll(want)
		hold.busy = false
	end
end

function Page:add(frame, height, shown, refresh)
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

-- The rows build() adds, indented under the row parent (added before them) on a rule, shown while it shows
-- and active() is true; active nil: each row says when it shows (a menu's rows for some of its choices)
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

function Page:width() return self.rowW or self.content:GetWidth() end

-- One-unit lines on a page: as shipped at 100%, whole screen pixels at a smaller size
function Page:pixels(n) return self.scaled == 1 and n or W.linePx(self.content, n) end
function Page:pxLine(t, wide)
	if wide then t:SetWidth(self:pixels(1)) else t:SetHeight(self:pixels(1)) end
end
function Page:line(t, wide)
	table.insert(self.lines, { t, wide })
	self:pxLine(t, wide)
end
-- The client's backdrop pieces, for a one-unit backdrop edge in the same way. The fill hangs from
-- the corners by the edge's size, so it moves with them to stay inside the frame.
local CORNERS = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }
local function pixelEdges(page, f)
	if f.backdropInfo == W.BACKDROP then
		local px = page:pixels(1)
		for _, k in ipairs(CORNERS) do if f[k] then f[k]:SetSize(px, px) end end
		if f.TopEdge then f.TopEdge:SetHeight(px) end
		if f.BottomEdge then f.BottomEdge:SetHeight(px) end
		if f.LeftEdge then f.LeftEdge:SetWidth(px) end
		if f.RightEdge then f.RightEdge:SetWidth(px) end
		local c, tl, br = f.Center, f.TopLeftCorner, f.BottomRightCorner
		if c and tl and br then
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", -px, px)
			c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT", px, -px)
		end
	end
	for _, kid in ipairs({ f:GetChildren() }) do pixelEdges(page, kid) end
end

local function repixel(page)
	for _, l in ipairs(page.lines) do page:pxLine(l[1], l[2]) end
	pixelEdges(page, page.content)
end
-- A UI scale or resolution change moves the screen pixel: lines and edges below 100% follow, once
-- the client has set its new scale
do
	local watch = CreateFrame("Frame")
	watch:SetScript("OnEvent", function()
		C_Timer.After(0, function()
			for _, page in ipairs(allPages) do
				if page.scaled ~= 1 then
					repixel(page)
					if page.scroll:IsVisible() then page:refresh() end
				end
			end
		end)
	end)
	ns.registerEvent(watch, "UI_SCALE_CHANGED")
	ns.registerEvent(watch, "DISPLAY_SIZE_CHANGED")
end

-- Whether this page takes the page size: pages of blocks, unless the page keeps its real size
function Page:scales() return not self.fullSize and self.panels ~= false and #self.blockList > 0 end
function Page:fitWidth(w)
	self.holder:SetWidth(w)
	self.content:SetWidth(w / self.scaled)
end
-- Takes a new page size, keeping the row at the top of the view where it is
function Page:applyScale()
	local want = self:scales() and savedScale() or 1
	if want == self.scaled then return end
	local hold = self:holdHere()
	self.scaled = want
	self.content:SetScale(want)
	self:fitWidth(self.scroll:GetWidth())
	repixel(self)
	self:keepHeld(hold)
end

function Page.showWhen(active, shown)
	return function() return (not shown or shown()) and active() and true or false end
end

local function placePanel(page, b, top, bottom)
	local content = page.content
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
	local px = page:pixels(1)
	e[1]:SetPoint("TOPLEFT", fill); e[1]:SetPoint("TOPRIGHT", fill); e[1]:SetHeight(px)
	e[2]:SetPoint("BOTTOMLEFT", fill); e[2]:SetPoint("BOTTOMRIGHT", fill); e[2]:SetHeight(px)
	e[3]:SetPoint("TOPLEFT", fill); e[3]:SetPoint("BOTTOMLEFT", fill); e[3]:SetWidth(px)
	e[4]:SetPoint("TOPRIGHT", fill); e[4]:SetPoint("BOTTOMRIGHT", fill); e[4]:SetWidth(px)
	fill:Show()
	for i = 1, 4 do e[i]:Show() end
end

local function hidePanel(b)
	if not b.panel then return end
	b.panel.fill:Hide()
	for i = 1, 4 do b.panel.edges[i]:Hide() end
end

local function report(err) geterrorhandler()(err) end
function Page:refresh()
	ns.Style.beginReads()
	xpcall(function() self:paint() end, report)
	ns.Style.endReads()
end

function Page:paint()
	self:applyScale()
	if self.beforeRefresh then self.beforeRefresh() end
	if self.fixed then
		local ok, err = pcall(self.fixed.refresh, self.fixed)
		if not ok and not self.fixedReported then
			self.fixedReported = true
			ns.say("options: the %s page header failed to update: %s", self.key, tostring(err))
		end
	end
	local heads = 0
	for _, b in ipairs(self.blockList) do
		if not b.head.shown or b.head.shown() then heads = heads + 1 end
	end
	local y, bottom = self:placeFoldRow(heads >= 2, self:scales()), 0
	local width = self.content:GetWidth()
	local open, gap = nil, false
	local function close()
		if not open then return end
		y = math.max(y, open.low) + PANEL_PAD_B
		placePanel(self, open, open.top, y)
		open.drawn = true
		open, gap = nil, true
	end
	for _, b in ipairs(self.blockList) do b.drawn, b.painted = false, nil end
	for _, it in ipairs(self.items) do
		local b = it.block
		if it.head or it.ends then close() end
		local show = not (b and not it.head and b.head.visible and isFolded(b))
		show = show and (not it.shown or it.shown())
		local sub = it.sub
		if show and sub then show = sub.parent.visible and (not sub.active or sub.active()) and true or false end
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
			-- One failing row must not blank the rest of the page.
			if it.refresh then
				local ok, err = pcall(it.refresh)
				if not ok and not it.reported then
					it.reported = true
					ns.say("options: a row on the %s page failed to update: %s", self.key, tostring(err))
				end
			end
			if it.head then self:paintHeader(b) end
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
	self:paintFoldRow()
	for _, b in ipairs(self.blockList) do b.painted = nil end
	for _, run in ipairs(self.subs) do self:placeRule(run) end
	self.rowW = nil
	local h = math.max(y, bottom, 1)
	self.content:SetHeight(h)
	self.holder:SetHeight(h * self.scaled)
	if self.hold then
		self.scroll:UpdateScrollChildRect()
		self:keepScroll()
	end
	if self.afterRefresh then self.afterRefresh() end
end

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
	end
	self:pxLine(run.rule, true)
	local x = parent.x + RULE_X
	run.rule:ClearAllPoints()
	run.rule:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -top)
	run.rule:SetPoint("BOTTOMLEFT", self.content, "TOPLEFT", x, -bottom)
	run.rule:Show()
end

function Page:relaid()
	self:refresh()
	local s = self.scroll
	s:UpdateScrollChildRect()
	local range = s:GetVerticalScrollRange()
	if s:GetVerticalScroll() > range then s:SetVerticalScroll(range) end
end

function Page:setFolded(b, fold)
	folded()[b.key] = fold and true or nil
	self:relaid()
end

function Page:foldAll(fold)
	for _, b in ipairs(self.blockList) do
		if b.head.visible then folded()[b.key] = fold and true or nil end
	end
	self:relaid()
end

function Page:reveal(frame)
	for _, it in ipairs(self.items) do
		if it.frame == frame then
			if it.block and isFolded(it.block) then self:setFolded(it.block, false) end
			return
		end
	end
end

-- A box in a run under another box is that box's detail; under a menu or slider it counts while it shows
local function listed(it)
	if not it.says or (it.shown and not it.shown()) then return false end
	local run = it.sub
	while run do
		local parent = run.parent
		if parent.says or (parent.shown and not parent.shown()) or (run.active and not run.active()) then return false end
		run = run.outer
	end
	return true
end

local function onList(b)
	local on = {}
	for _, it in ipairs(b.items) do
		if listed(it) then
			local s = it.says()
			if s then table.insert(on, s) end
		end
	end
	if #on > 3 then return table.concat(on, ", ", 1, 3) .. " +" .. (#on - 3) end
	return table.concat(on, ", ")
end

-- A client without the trainer's atlases gets Blizzard's older arrow.
local ARROW_BOX = 14
local arrowAtlas = {}
local function paintArrow(t, shut)
	local name = shut and "Professions-recipe-header-expand" or "Professions-recipe-header-collapse"
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
		t:SetRotation(shut and -math.pi / 2 or math.pi)
	end
end

local LINK_H, LINK_GAP = 18, 14
local LINK_GREY = 0.62
-- A larger hit area, so a click doesn't land on the header and fold the block.
local RESET_PAD_X, RESET_PAD_Y = 8, 6
local function textLink(parent, text, onClick, pad)
	local b = CreateFrame("Button", nil, parent)
	if pad then b:SetHitRectInsets(-RESET_PAD_X, -RESET_PAD_X, -RESET_PAD_Y, -RESET_PAD_Y) end
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("LEFT")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function() b.text:SetTextColor(1, 0.82, 0) end)
	b:SetScript("OnLeave", function() b.text:SetTextColor(LINK_GREY, LINK_GREY, LINK_GREY) end)
	b.text:SetTextColor(LINK_GREY, LINK_GREY, LINK_GREY)
	function b.say(t)
		b.text:SetText(t)
		b:SetSize(b.text:GetStringWidth() + 2, LINK_H)
	end
	b.say(text)
	return b
end
Page.textLink = textLink

-- A yellow link that goes somewhere else in the options; tip: a tooltip line
function Page.goLink(parent, text, onClick, tip)
	local b = CreateFrame("Button", nil, parent)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT")
	b.text:SetText(text)
	b:SetSize(b.text:GetStringWidth() + 4, 16)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function()
		b.text:SetTextColor(1, 0.93, 0.6)
		if not tip then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetText(text)
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		b.text:SetTextColor(1, 0.82, 0)
		if tip then GameTooltip:Hide() end
	end)
	return b
end

local function placeResets(header, foldRow)
	if header then header.reset:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 5) end
	if foldRow then foldRow.resetAll:SetPoint("LEFT", foldRow, "LEFT", 4, 0) end
end

function Page:paintHeader(b)
	local f = b.head.frame
	local shut = isFolded(b) and true or false
	paintArrow(f.arrow, shut)
	local changed = b:changed()
	b.painted = changed
	f.reset:SetShown(changed)
	local resetW = changed and f.reset:GetWidth() + LINK_GAP or 0
	f.says:SetShown(shut)
	if shut then
		f.says:SetPoint("BOTTOMRIGHT", -resetW, 9)
		f.says:SetText(onList(b))
		local used = f.textX + f.text:GetStringWidth() + (f.note and 10 + f.note:GetStringWidth() or 0)
		f.says:SetWidth(math.max(self.rowW - used - resetW - 24, 1))
	end
end

-- Page size: the current one white, the others links
local SIZE_GAP = 8
local function tintSizes(row)
	local now = savedScale()
	for _, b in ipairs(row.sizes) do
		local v = b.value == now and 1 or LINK_GREY
		b.text:SetTextColor(v, v, v)
	end
end
-- Disabling the button under the mouse fires its OnLeave at once, so OnLeave only recolours
local function paintSizes(row)
	local now = savedScale()
	for _, b in ipairs(row.sizes) do
		local live = b.value ~= now
		if b:IsEnabled() ~= live then b:SetEnabled(live) end
	end
	tintSizes(row)
end
function Page:setSize(v)
	if not scaleOK(v) then return end
	P.getAccount().pageScale = v
	ns.Options.refresh()
end
local function makeSizes(page, row)
	row.sizes = {}
	for i, c in ipairs(Page.SCALES) do
		local b = textLink(row, c[2], function() page:setSize(c[1]) end)
		b:SetScript("OnEnter", function() if b:IsEnabled() then b.text:SetTextColor(1, 0.82, 0) end end)
		b:SetScript("OnLeave", function() tintSizes(row) end)
		b.value = c[1]
		row.sizes[i] = b
	end
	row.sizeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sizeLabel:SetText("Page size")
end
-- The sizes sit left of the fold links, or at the right without them
local function placeSizes(row, folds)
	local n = #row.sizes
	row.sizes[n]:ClearAllPoints()
	if folds then
		row.sizes[n]:SetPoint("RIGHT", row.expand, "LEFT", -2 * LINK_GAP, 0)
	else
		row.sizes[n]:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	end
	for i = n - 1, 1, -1 do row.sizes[i]:SetPoint("RIGHT", row.sizes[i + 1], "LEFT", -SIZE_GAP, 0) end
	row.sizeLabel:SetPoint("RIGHT", row.sizes[1], "LEFT", -SIZE_GAP, 0)
end

-- folds: Collapse all and Expand all; sizes: the page size. The row keeps its size above the blocks
-- (in the holder, not content): its height in content's units comes back.
function Page:placeFoldRow(folds, sizes)
	local row = self.foldRow
	if not (folds or sizes) then
		if row then row:Hide() end
		return 0
	end
	if not row then
		row = CreateFrame("Frame", nil, self.holder)
		row:SetFrameLevel(self.content:GetFrameLevel() + 10)
		row:SetHeight(LINK_H)
		row.collapse = textLink(row, "Collapse all", function() self:foldAll(true) end)
		row.collapse:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.expand = textLink(row, "Expand all", function() self:foldAll(false) end)
		row.expand:SetPoint("RIGHT", row.collapse, "LEFT", -LINK_GAP, 0)
		makeSizes(self, row)
		if self.resetAll then
			row.resetAll = textLink(row, "", self.resetAll.ask, true)
			placeResets(nil, row)
		end
		self.foldRow = row
	end
	row.collapse:SetShown(folds)
	row.expand:SetShown(folds)
	for _, b in ipairs(row.sizes) do b:SetShown(sizes) end
	row.sizeLabel:SetShown(sizes)
	if sizes then placeSizes(row, folds) end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, 0)
	row:SetPoint("TOPRIGHT", self.holder, "TOPRIGHT", 0, 0)
	row:Show()
	return LINK_H / self.scaled
end

function Page:paintFoldRow()
	local row = self.foldRow
	if not (row and row:IsShown()) then return end
	local anyFolded, anyOpen = false, false
	for _, b in ipairs(self.blockList) do
		if b.head.visible then
			if isFolded(b) then anyFolded = true else anyOpen = true end
		end
	end
	for _, pair in ipairs({ { row.expand, anyFolded }, { row.collapse, anyOpen } }) do
		pair[1]:SetEnabled(pair[2])
		pair[1]:SetAlpha(pair[2] and 1 or 0.45)
	end
	paintSizes(row)
	if row.resetAll then
		row.resetAll.say(self.resetAll.text())
		row.resetAll:SetShown(self:changed())
	end
end

function Page:row(height)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetSize(ROW_W, height)
	return f
end

function Page:label(f, text, tip)
	f:EnableMouse(true)
	Page.setTip(f, text, tip, "above")
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- What a block owns: refs to its settings, to tell whether it differs and to reset it.
-- Ref kinds: elem, general, bar, group, style; optional field (elem and bar: one field of a state
-- or event table), after, default, changed, reset, label.
local REF = {}

function Page.refKind(kind, spec) REF[kind] = spec end

local function copy(v) return type(v) == "table" and CopyTable(v) or v end

-- Numbers compare to a hair (a typed 0.33).
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" then return math.abs(a - b) < 1e-6 end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function defaultOf(r)
	if r.default then return r.default() end
	return REF[r.kind].default(r)
end
Page.refDefault = defaultOf

local function refChanged(r)
	if r.changed then return r.changed(r) end
	local k = REF[r.kind]
	if k.changed then return k.changed(r) end
	local t = k.holder(r)
	if not t then return false end
	local v = t[k.slot(r)]
	if v == nil and k.unset then return false end
	return not same(v, defaultOf(r))
end

-- The same path as a change by hand, so combat rules hold: layout waits, aura buttons restyle
-- after combat, and what can't change in combat is left, said once.
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

local function askReset(name, run) StaticPopup_Show(ns.POPUP .. "RESET_SETTINGS", name, nil, run) end

Page.refKind("elem", {
	id = function(r) return r.elem .. "." .. r.name .. (r.field and "." .. r.field or "") end,
	holder = function(r)
		local o = E.opts(r.elem)
		if not r.field then return o end
		return type(o[r.name]) == "table" and o[r.name] or nil
	end,
	slot = function(r) return r.field or r.name end,
	default = function(r) return E.default(r.elem, r.name, r.field) end,
	unset = true,
})
Page.refKind("general", {
	id = function(r) return r.general end,
	holder = function() return P.getDB() end,
	slot = function(r) return r.general end,
	default = function(r) return P.DEFAULTS[r.general] end,
})
Page.refKind("bar", {
	id = function(r) return r.bar .. "." .. r.name .. (r.field and "." .. r.field or "") end,
	holder = function(r)
		local c = Bars.get(r.bar).cfg()
		if not r.field then return c end
		return type(c[r.name]) == "table" and c[r.name] or nil
	end,
	slot = function(r) return r.field or r.name end,
	default = function(r)
		local d = Bars.get(r.bar).defaults[r.name]
		if not r.field then return d end
		if type(d) ~= "table" then return nil end
		return d[r.field]
	end,
})
local function groupOf(r) if type(r.group) == "function" then return r.group() end return r.group end
Page.refKind("group", {
	id = function(r) return tostring(r.group) .. "." .. r.name end,
	holder = groupOf,
	slot = function(r) return r.name end,
	default = function(r)
		local g = groupOf(r)
		for _, shipped in ipairs(g and ns.CLASS.layout or {}) do
			if shipped.id == g.id and shipped.name == g.name and shipped[r.name] ~= nil then
				return shipped[r.name]
			end
		end
		return G.DEFAULTS[r.name]
	end,
})

local function styleOwner(r)
	if type(r.owner) == "function" then
		local o = r.owner()
		return o, o ~= nil
	end
	return r.owner, true
end
Page.refKind("style", {
	id = function(r) return r.style .. "." .. tostring(r.owner) end,
	changed = function(r)
		local S = ns.Style
		local o, chosen = styleOwner(r)
		if not chosen then return false end
		local follows, shipped = S.readShipped(o, r.style)
		if o ~= nil then
			local now = S.follows(o, r.style)
			if now ~= follows then return true end
			if now then return false end
		end
		return not same(S.read(o, r.style), shipped)
	end,
	reset = function(r)
		local o, chosen = styleOwner(r)
		if chosen then ns.Style.reset(o, r.style) end
	end,
})

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

local Block = {}
Block.__index = Block
function Block:changed() return anyChanged(self.owns) end
function Block:reset() resetRefs(self.owns) end
function Block:askReset() askReset(self.name, function() self:reset() end) end

function Page:refs()
	local out = {}
	for _, r in ipairs(self.pageOwns) do table.insert(out, r) end
	for _, b in ipairs(self.blockList) do
		for _, r in ipairs(b.owns) do table.insert(out, r) end
	end
	return out
end
function Page:changed()
	if anyChanged(self.pageOwns) then return true end
	for _, b in ipairs(self.blockList) do
		local c = b.painted
		if c == nil then c = b:changed() end
		if c then return true end
	end
	return false
end
function Page:reset() resetRefs(self:refs()) end
function Page:askReset(name) askReset(name, function() self:reset() end) end

function Page:header(text, shown, note, icon)
	local f = self:row(36)
	local block, x = nil, 0
	if self.panels ~= false then
		-- Named by its text, so fold state survives changes before it.
		self.blockKeys = self.blockKeys or {}
		local key = self.key .. ":" .. text
		if self.blockKeys[key] then key = key .. "#" .. #self.blockList end
		self.blockKeys[key] = true
		block = setmetatable({ index = #self.blockList + 1, key = key, name = text, items = {}, owns = {},
			ownIds = {} }, Block)
		table.insert(self.blockList, block)
		self.block = block
		f.arrow = f:CreateTexture(nil, "ARTWORK")
		f.arrow:SetPoint("CENTER", f, "BOTTOMLEFT", 6, 15)
		f.says = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.says:SetJustifyH("RIGHT")
		f.says:SetWordWrap(false)
		f.says:Hide()
		f.reset = textLink(f, "Reset", function() block:askReset() end, true)
		f.reset:Hide()
		placeResets(f)
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
		W.cropIcon(f.icon)
	end
	f.text:SetText(text)
	if note then
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 10, 1)
		f.note:SetText(note)
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 1)
	self:line(line)
	pcall(line.SetGradient, line, "HORIZONTAL", CreateColor(0.85, 0.71, 0.42, 0.45), CreateColor(0.85, 0.71, 0.42, 0))
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
	self:add(f, 36, shown)
	if block then
		block.head = self.items[#self.items]
		block.head.head = true
		local r, g, bl = f.text:GetTextColor()
		f:EnableMouse(true)
		f:SetScript("OnEnter", function()
			f.text:SetTextColor(1, 0.93, 0.6)
		end)
		f:SetScript("OnLeave", function()
			f.text:SetTextColor(r, g, bl)
		end)
		f:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			local link = f.reset
			if link:IsShown() and link:IsMouseOver(RESET_PAD_Y, -RESET_PAD_Y, -RESET_PAD_X, RESET_PAD_X) then return end
			self:setFolded(block, not isFolded(block))
		end)
	end
	return f
end

function Page:pageTitle(text)
	local f = self:row(40)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.text:SetPoint("BOTTOMLEFT", 4, 8)
	f.text:SetShadowOffset(1, -1)
	f.text:SetText(text)
	return self:add(f, 40)
end

local SECTION_H, SECTION_SIZE = 46, 18
function Page:section(text)
	self.block = nil
	local f = self:row(SECTION_H)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	local file, _, flags = GameFontNormalLarge:GetFont()
	if file then f.text:SetFont(file, SECTION_SIZE, flags) end
	f.text:SetPoint("BOTTOMLEFT", 4, 9)
	f.text:SetShadowOffset(1, -1)
	f.text:SetText(text)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.85, 0.71, 0.42, 0.6)
	self:line(line)
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
	self:add(f, SECTION_H)
	self.items[#self.items].ends = true
	return f
end

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

function Page:anchor(name)
	self.anchors = self.anchors or {}
	self.anchors[name] = self.items[#self.items].frame
end

-- Unfolds frame's block and scrolls it to the top once laid out, then after()
function Page:scrollTo(frame, after)
	local jump = {}
	self.jump, self.hold = jump, nil
	self:reveal(frame)
	C_Timer.After(0, function()
		if self.jump == jump then self.jump = nil end
		self.hold = nil
		if not frame:IsVisible() then return end
		local top, y = self.content:GetTop(), frame:GetTop()
		if top and y then
			local at = (top - y - 8) * self.scaled
			self.scroll:SetVerticalScroll(math.max(0, math.min(at, self.scroll:GetVerticalScrollRange())))
		end
		if after then after() end
	end)
end

-- To an anchor on this page, flashing it
function Page:goTo(name)
	local f = self.anchors and self.anchors[name]
	if f then self:scrollTo(f, function() self:flash(f) end) end
end

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
	self.items[#self.items].says = function() return get() and label or nil end
	return f
end

-- Switches (Page.pillSwitch, Page.boxSwitch): show(on), nudge(), and flip(), the click; a refused one
-- shakes and stays as get() says
local SLIDE, SHAKE = 0.12, 0.24
local GOLD_TEXT, GREY_TEXT = { 1, 0.82, 0 }, { 0.5, 0.5, 0.5 }
local Switch = {}

local function mix(a, b, f) return a + (b - a) * f end

-- One ticker moves every switch in motion, made at the first
local moving, mover = {}, nil
local function slideStep(t)
	local now, any = GetTime(), false
	for sw in pairs(moving) do
		local f = math.min((now - sw.t0) / sw.dur, 1)
		if sw.dur == SHAKE then sw.shake = math.sin(f * math.pi * 2) * (1 - f)
		else sw.at = mix(sw.from, sw.goal, f) end
		if f >= 1 then
			sw.shake, moving[sw] = nil, nil
			sw.at = sw.goal
		else any = true end
		sw:paint()
	end
	if not any then t:Hide() end
end
local function move(sw, dur)
	sw.from, sw.t0, sw.dur, sw.shake = sw.at, GetTime(), dur, nil
	moving[sw] = true
	mover = mover or ns.ticker(0, slideStep)
	mover:Show()
end

function Switch:show(on)
	local goal = on and 1 or 0
	if self.text then
		local c = on and GOLD_TEXT or GREY_TEXT
		self.text:SetText(on and "On" or "Off")
		self.text:SetTextColor(c[1], c[2], c[3])
	end
	if goal == self.goal and self.at ~= nil then
		if not moving[self] then self:paint() end
		return
	end
	self.goal = goal
	if self.at == nil or self.instant or not self:IsVisible() then
		self.at, moving[self], self.shake = goal, nil, nil
		self:paint()
	else move(self, SLIDE) end
end
function Switch:nudge()
	if self:IsVisible() and not moving[self] then move(self, SHAKE) end
end

local function makeSwitch(parent, get, set, title, tip, word)
	local sw = CreateFrame("Button", nil, parent)
	for k, fn in pairs(Switch) do sw[k] = fn end
	function sw.flip()
		local was = get() and true or false
		set(not was)
		local now = get() and true or false
		sw:show(now)
		if now == was then sw:nudge() end
	end
	sw:SetScript("OnClick", sw.flip)
	Page.setTip(sw, title, tip)
	sw:HookScript("OnEnter", function(self) self.hover = true; if self.at then self:paint() end end)
	sw:HookScript("OnLeave", function(self) self.hover = nil; if self.at then self:paint() end end)
	if word then
		-- The word is part of the click
		sw.text = sw:CreateFontString(nil, "OVERLAY", word)
		sw.text:SetPoint("LEFT", sw, "RIGHT", 6, 0)
		sw:SetHitRectInsets(0, -44, 0, 0)
	end
	return sw
end

-- Pill: Blizzard's widget status bar; 70 wide, the narrowest without cutting its art
local BAR, PILL_W, PILL_H, FILL_IN, FILL_H, KNOB = "UI-Frame-Bar-", 70, 31, 8, 15, 21
local KNOB_RIM, KNOB_HI = { 0.25, 0.16, 0.05 }, { 1, 1, 1, 0.45 }
local KNOB_ON, KNOB_OFF = { { 0.72, 0.47, 0.12 }, { 1, 0.9, 0.55 } }, { { 0.36, 0.36, 0.36 }, { 0.8, 0.8, 0.8 } }
local function slices(sw, part, layer, sub, inset, blend)
	local l, c, r = sw:CreateTexture(nil, layer, nil, sub), sw:CreateTexture(nil, layer, nil, sub),
		sw:CreateTexture(nil, layer, nil, sub)
	l:SetAtlas(BAR .. part .. "Left", true)
	r:SetAtlas(BAR .. part .. "Right", true)
	c:SetAtlas(BAR .. part .. "Center", false)
	l:SetPoint("LEFT", inset, 0)
	r:SetPoint("RIGHT", -inset, 0)
	c:SetPoint("TOPLEFT", l, "TOPRIGHT")
	c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
	if blend then for _, t in ipairs({ l, c, r }) do t:SetBlendMode(blend) end end
	return { l, c, r }
end
local function paintPill(self)
	local at = self.at
	local travel = PILL_W - 2 * FILL_IN - FILL_H
	local x = FILL_IN + FILL_H / 2 + travel * at + (self.shake or 0) * 4
	self.knob:ClearAllPoints()
	self.knob:SetPoint("CENTER", self, "LEFT", x, 0)
	self.fill:SetWidth(math.max(x - FILL_IN, 0.01))
	self.fill:SetShown(at > 0)
	local lo, hi, offLo, offHi = KNOB_ON[1], KNOB_ON[2], KNOB_OFF[1], KNOB_OFF[2]
	self.knobFace:SetGradient("VERTICAL",
		CreateColor(mix(offLo[1], lo[1], at), mix(offLo[2], lo[2], at), mix(offLo[3], lo[3], at), 1),
		CreateColor(mix(offHi[1], hi[1], at), mix(offHi[2], hi[2], at), mix(offHi[3], hi[3], at), 1))
	for _, t in ipairs(self.glow) do t:SetAlpha(self.hover and 0.5 or 0) end
end
function Page.pillSwitch(parent, get, set, title, tip, word)
	local sw = makeSwitch(parent, get, set, title, tip, word)
	sw:SetSize(PILL_W, PILL_H)
	sw.paint = paintPill
	slices(sw, "BG", "BACKGROUND", 0, 6)
	sw.glow = slices(sw, "Glow", "BACKGROUND", -1, 0, "ADD")
	slices(sw, "Border", "ARTWORK", 2, 0)
	sw.fill = sw:CreateTexture(nil, "ARTWORK", nil, 0)
	sw.fill:SetAtlas(BAR .. "Fill-Yellow", false)
	sw.fill:SetPoint("LEFT", FILL_IN, 0)
	sw.fill:SetHeight(FILL_H)
	sw.knob = W.disc(sw, "OVERLAY", 0)
	sw.knob:SetSize(KNOB, KNOB)
	sw.knob:SetColorTexture(KNOB_RIM[1], KNOB_RIM[2], KNOB_RIM[3], 1)
	sw.knobFace = W.disc(sw, "OVERLAY", 1)
	sw.knobFace:SetSize(KNOB - 2, KNOB - 2)
	sw.knobFace:SetPoint("CENTER", sw.knob)
	sw.knobFace:SetColorTexture(1, 1, 1, 1)
	local hi = W.disc(sw, "OVERLAY", 2)
	hi:SetSize(KNOB / 2, KNOB / 3)
	hi:SetPoint("TOP", sw.knob, "TOP", 0, -2)
	hi:SetColorTexture(KNOB_HI[1], KNOB_HI[2], KNOB_HI[3], KNOB_HI[4])
	return sw
end

-- Box: Blizzard's checkbox; it changes at once
local BOX = "Interface\\Buttons\\UI-CheckBox-"
local function paintBox(self)
	local dx = (self.shake or 0) * 3
	for _, t in ipairs(self.parts) do
		t:ClearAllPoints()
		t:SetPoint("CENTER", dx, 0)
	end
	self.tick:SetShown(self.at >= 0.5)
end
function Page.boxSwitch(parent, size, get, set, title, tip)
	local sw = makeSwitch(parent, get, set, title, tip)
	sw:SetSize(size, size)
	sw.paint, sw.instant = paintBox, true
	sw.box = sw:CreateTexture(nil, "ARTWORK")
	sw.box:SetTexture(BOX .. "Up")
	sw.tick = sw:CreateTexture(nil, "OVERLAY")
	sw.tick:SetTexture(BOX .. "Check")
	sw.parts = { sw.box, sw.tick }
	for _, t in ipairs(sw.parts) do t:SetSize(size, size) end
	local lit = sw:CreateTexture(nil, "HIGHLIGHT")
	lit:SetTexture(BOX .. "Highlight")
	lit:SetAllPoints()
	lit:SetBlendMode("ADD")
	return sw
end

function Page.pct(v) return string.format("%.0f%%", v * 100) end
function Page.times(v) return string.format("%.2fx", v) end
function Page.int(v) return string.format("%d", v) end
function Page.px(v) return string.format("%d px", v) end
local NUMBER = "%-?%d*%.?%d+"
local BOX_W, BOX_GAP = 52, 10

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

function Page:slider(label, tip, minV, maxV, step, fmt, get, set, shown)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local s = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	s:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	local updating = false
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
		box:ClearFocus()
		box:SetText(fmt(v))
	end, s)
	box:SetSize(BOX_W, 20)
	box:SetPoint("LEFT", s, "RIGHT", BOX_GAP, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(8)
	box:SetFontObject("GameFontHighlight")
	box:SetJustifyH("CENTER")
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
			-- Rounded again past the label's decimals (0.33, not 0.33000000000000002).
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
		-- A narrow window never pushes the box past its edge.
		local span = math.min(self:width() - LABEL_W - 8, SLIDER_SPAN_W)
		s:SetWidth(math.max(span - BOX_GAP - BOX_W, 80))
		-- Set only when it differs: setting reformats the slider.
		local v = get() or minV
		if not (s.Slider and s.Slider:GetValue() == v) then
			updating = true
			s:SetValue(v)
			updating = false
		end
		if not box:HasFocus() then box:SetText(fmt(v)) end
	end)
end

function Page:dropdown(label, tip, choices, get, set, shown, width, menu)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dd:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	dd:SetWidth(width or 200)
	dd:SetScript("OnShow", nil)
	menu = menu or function(_, rootDescription)
		rootDescription:SetScrollMode(400)
		for _, c in ipairs(type(choices) == "function" and choices() or choices) do
			local item = rootDescription:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
			if c.init then item:AddInitializer(c.init) end
		end
	end
	f.dropdown = dd
	-- What the menu was made from: the value, then each choice's value and label in turn. Compared
	-- in place, as a repaint runs this every frame while a slider drags.
	local was, wasN, now = nil, 0, {}
	local function update()
		local n = 1
		now[1] = get()
		if type(choices) == "function" then
			for _, c in ipairs(choices()) do
				now[n + 1], now[n + 2] = c[1], c[2]
				n = n + 2
			end
		end
		local unchanged = was ~= nil and wasN == n
		if unchanged then
			for i = 1, n do
				if was[i] ~= now[i] then unchanged = false break end
			end
		end
		if unchanged then return end
		if was == nil then
			dd:SetupMenu(menu)
		elseif dd:IsMenuOpen() then
			-- Never while the list is open: Blizzard rebuilds it in place and a scrolling one keeps
			-- old rows (blank gaps); a change waits for it to close.
			return
		else
			dd:GenerateMenu()
		end
		was, wasN, now = now, n, was or {}
	end
	dd:RegisterCallback("OnMenuClose", function() C_Timer.After(0, update) end, f)
	return self:add(f, 34, shown, update)
end

function Page:color(label, tip, get, set, shown, opaque)
	local f = self:row(30)
	self:label(f, label, tip)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(22, 22)
	b:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	b:SetBackdrop(W.BACKDROP)
	b:SetBackdropColor(0.5, 0.5, 0.5, 1)
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

function Page:pin(h)
	local win = self.win
	h:SetParent(win)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	h:SetPoint("TOPRIGHT", win, "TOPRIGHT", -22, PAGE_TOP)
	h:Hide()
	self.fixed = h
	local top
	local function place()
		local was = top
		top = PAGE_TOP - (h.heroH or ns.OptionsArt.HERO_H)
		if was and was ~= top then self:holdScroll(was - top) end
		self.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, top)
	end
	h.onHeight = place
	place()
	return h
end

-- The view's top moves down by shift (a taller header): what the player is looking at stays where it
-- is on screen, held over the next frames as the range settles
function Page:holdScroll(shift)
	self:keepHeld(self:holdHere(shift))
end

function Page:hero(key)
	return self:pin(ns.OptionsArt.buildHero(self.win, key))
end

function Page.panelBackdrop(f, r, g, b)
	f:SetBackdrop(W.BACKDROP)
	f:SetBackdropColor(0.09, 0.075, 0.06, 1)
	f:SetBackdropBorderColor(r or 0.23, g or 0.17, b or 0.10, 1)
end

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
		W.cropIcon(b.icon)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("TOP", b.icon, "BOTTOM", 0, -5)
		b.text:SetWidth(CARD_W - 6)
		b.text:SetText(c[2])
		local badge = c[4] and ns.OptionsArt.expBadge(b, c[4]) or c.tag and ns.OptionsArt.tagBadge(b, c.tag)
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
		W.cropIcon(b.icon)
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
	Page.copyBox(f, value, 380):SetPoint("LEFT", f, "LEFT", LABEL_W + 6, 0)
	return self:add(f, 30)
end

-- A box holding value to copy: a click selects it all, typing changes nothing
function Page.copyBox(parent, value, width)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetText(value)
	e:SetCursorPosition(0)
	e:SetScript("OnTextChanged", function(box, user) if user then box:SetText(value); box:HighlightText() end end)
	e:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

function Page:experimental(name, where)
	local f = self:row(28)
	self:label(f, name)
	local w = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	w:SetText(where)
	return self:add(f, 28)
end

-- Drag and drop in a list
function Page.dragGhost(onMove)
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(180, 24)
	ghost:SetAlpha(0.9)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	W.cropIcon(ghost.icon)
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
