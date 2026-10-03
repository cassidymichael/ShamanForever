-- Page kit: scrolling pages of rows grouped into foldable blocks

local _, ns = ...

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
-- Fold state is saved per page and header text; an untouched block starts folded unless it is
-- -- the page's first, under an open section, or its page or header says open.
local function folded() return ns.getAccount().foldedBlocks end
local function isFolded(b)
	local v = folded()[b.key]
	if v == nil then return b.startFolded end
	return v
end
local allPages = {}
local SUB_INDENT, SUB_MAX, RULE_X = 24, 2, 12

Page.setTip = ns.setTip

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
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	local page = setmetatable({ win = win, key = key, title = title, indent = indent, scroll = scroll,
		content = content, items = {}, blockList = {}, subs = {}, pageOwns = {}, ownIds = {} }, Page)
	scroll:SetScript("OnSizeChanged", function(self, w)
		if not Page.resizing then content:SetWidth(w) end
		self:UpdateScrollChildRect()
		page:keepScroll()
		if not Page.resizing then ns.Options.refresh() end
	end)
	content:SetScript("OnSizeChanged", function() scroll:UpdateScrollChildRect() end)
	-- Blizzard's handler re-sets the position from its scroll bar's fraction: the held place is put
	-- -- back after it.
	scroll:HookScript("OnScrollRangeChanged", function() if page.hold then page:keepScroll() end end)
	scroll:Hide()
	table.insert(allPages, page)
	return page
end

-- Resizing feeds back on itself (the range follows the frame, the position the range) and can send
-- -- the page to the top: from the grip's press until two frames after its release the page holds
-- -- its place, and it is laid out once at the end.
local resized

function Page.startResize(page)
	if not page then return end
	Page.resizing, resized = true, page
	local offset = page.scroll:GetVerticalScroll()
	local hold = { offset = offset }
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
	for _, p in ipairs(allPages) do
		local w = p.scroll:GetWidth()
		if math.abs(p.content:GetWidth() - w) > 0.5 then
			p.content:SetWidth(w)
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

-- At a range of 0 it waits for the next range change.
function Page:keepScroll()
	local hold, s = self.hold, self.scroll
	if not hold or hold.busy then return end
	local range = s:GetVerticalScrollRange()
	if range <= 0 then return end
	local want, row = hold.offset, hold.row
	if row and row.visible and row.y then want = row.y + hold.dy end
	want = math.max(0, math.min(want, range))
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

function Page.showWhen(active, shown)
	return function() return (not shown or shown()) and active() and true or false end
end

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

local function report(err) geterrorhandler()(err) end
function Page:refresh()
	ns.Style.beginReads()
	xpcall(function() self:paint() end, report)
	ns.Style.endReads()
end

function Page:paint()
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
	self.heads = heads
	local y, bottom = self:placeFoldRow(heads >= 2), 0
	local width = self.content:GetWidth()
	local open, gap = nil, false
	local function close()
		if not open then return end
		y = math.max(y, open.low) + PANEL_PAD_B
		placePanel(self.content, open, open.top, y)
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
		if show and sub then show = sub.parent.visible and sub.active() and true or false end
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
	self.content:SetHeight(math.max(y, bottom, 1))
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
		run.rule:SetWidth(1)
	end
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
	folded()[b.key] = fold and true or false
	self:relaid()
end

function Page:foldAll(fold)
	for _, b in ipairs(self.blockList) do
		if b.head.visible then folded()[b.key] = fold and true or false end
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

-- A client without the trainer's atlases gets the totem bar's arrow.
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

function Page:placeFoldRow(on)
	local row = self.foldRow
	if not on then
		if row then row:Hide() end
		return 0
	end
	if not row then
		row = CreateFrame("Frame", nil, self.content)
		row:SetHeight(LINK_H)
		row.collapse = textLink(row, "Collapse all", function() self:foldAll(true) end)
		row.collapse:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.expand = textLink(row, "Expand all", function() self:foldAll(false) end)
		row.expand:SetPoint("RIGHT", row.collapse, "LEFT", -LINK_GAP, 0)
		if self.resetAll then
			row.resetAll = textLink(row, "", self.resetAll.ask, true)
			placeResets(nil, row)
		end
		self.foldRow = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
	row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, 0)
	row:Show()
	return LINK_H
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
Page.same = same

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
-- -- after combat, and what can't change in combat is left, said once.
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
		local o = ns.elementOpts(r.elem)
		if not r.field then return o end
		return type(o[r.name]) == "table" and o[r.name] or nil
	end,
	slot = function(r) return r.field or r.name end,
	default = function(r) return ns.elementDefault(r.elem, r.name, r.field) end,
	unset = true,
})
Page.refKind("general", {
	id = function(r) return r.general end,
	holder = function() return ns.getDB() end,
	slot = function(r) return r.general end,
	default = function(r) return ns.DEFAULTS[r.general] end,
})
Page.refKind("bar", {
	id = function(r) return r.bar .. "." .. r.name .. (r.field and "." .. r.field or "") end,
	holder = function(r)
		local c = ns.Bars.get(r.bar).cfg()
		if not r.field then return c end
		return type(c[r.name]) == "table" and c[r.name] or nil
	end,
	slot = function(r) return r.field or r.name end,
	default = function(r)
		local d = ns.Bars.get(r.bar).defaults[r.name]
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
		return ns.GROUP_DEFAULTS[r.name]
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
		local St = ns.Style
		local o, chosen = styleOwner(r)
		if not chosen then return false end
		local follows, shipped = St.readShipped(o, r.style)
		if o ~= nil then
			local now = St.follows(o, r.style)
			if now ~= follows then return true end
			if now then return false end
		end
		return not same(St.read(o, r.style), shipped)
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

function Page:header(text, shown, note, icon, opts)
	local f = self:row(36)
	local block, x = nil, 0
	if self.panels ~= false then
		-- Named by its text, so fold state survives changes before it.
		self.blockKeys = self.blockKeys or {}
		local key = self.key .. ":" .. text
		if self.blockKeys[key] then key = key .. "#" .. #self.blockList end
		self.blockKeys[key] = true
		local first = #self.blockList == 0 and not self.firstFolded
		block = setmetatable({ index = #self.blockList + 1, key = key, name = text, items = {}, owns = {},
			ownIds = {}, startFolded = not (first or self.allOpen or self.openRun or (opts and opts.open)) }, Block)
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
		local r, g, bl = f.text:GetTextColor()
		f:EnableMouse(true)
		f:SetScript("OnEnter", function()
			f.text:SetTextColor(1, 0.93, 0.6)
			if (self.heads or 0) < 2 then return end
			GameTooltip:SetOwner(f, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", f, "TOPLEFT", f.textX, -4)
			GameTooltip:SetText(text)
			GameTooltip:AddLine("Shift-click to expand or collapse every block.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		f:SetScript("OnLeave", function()
			f.text:SetTextColor(r, g, bl)
			GameTooltip:Hide()
		end)
		f:SetScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" then return end
			local link = f.reset
			if link:IsShown() and link:IsMouseOver(RESET_PAD_Y, -RESET_PAD_Y, -RESET_PAD_X, RESET_PAD_X) then return end
			local fold = not isFolded(block)
			if IsShiftKeyDown() then self:foldAll(fold) else self:setFolded(block, fold) end
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
function Page:section(text, open)
	self.block = nil
	self.openRun = open or nil
	local f = self:row(SECTION_H)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	local file, _, flags = GameFontNormalLarge:GetFont()
	if file then f.text:SetFont(file, SECTION_SIZE, flags) end
	f.text:SetPoint("BOTTOMLEFT", 4, 9)
	f.text:SetShadowOffset(1, -1)
	f.text:SetText(text)
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(0.85, 0.71, 0.42, 0.6)
	line:SetHeight(1)
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
	-- Never while the list is open: Blizzard rebuilds it in place and a scrolling one keeps old rows
	-- -- (blank gaps); a change waits for it to close.
	local was
	local function update()
		local now = tostring(get())
		if type(choices) == "function" then
			for _, c in ipairs(choices()) do now = now .. "\1" .. tostring(c[1]) .. "=" .. tostring(c[2]) end
		end
		if was == nil then
			was = now
			dd:SetupMenu(menu)
		elseif now ~= was and not dd:IsMenuOpen() then
			was = now
			dd:GenerateMenu()
		end
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
	b:SetBackdrop(ns.BACKDROP)
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

function Page:button(textFn, onClick, tip, width, shown)
	local f = self:row(32)
	local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btn:SetSize(width or 160, 22)
	btn:SetPoint("LEFT", 0, 0)
	btn:SetScript("OnClick", onClick)
	Page.setTip(btn, textFn, tip)
	return self:add(f, 32, shown, function() btn:SetText(textFn()) end)
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
	self.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP - (h.heroH or ns.Look.HERO_H))
	return h
end

function Page:hero(key)
	return self:pin(ns.Look.buildHero(self.win, key))
end

function Page.panelBackdrop(f, r, g, b)
	f:SetBackdrop(ns.BACKDROP)
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

function Page:experimental(name, where)
	local f = self:row(28)
	self:label(f, name)
	local w = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	w:SetText(where)
	return self:add(f, 28)
end

-- Drag and drop in a list
-- K 952 1058
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
