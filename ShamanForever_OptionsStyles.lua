-- The options window's Styles page: a gallery of every border look, pulsing glow and pop, each
-- on one sample icon with everything else as shipped (never the player's own settings). Right-click
-- one to use it in General. The looks come from ns.Style's choices, so a new one shows up here
-- with no page code. Every icon is a look tile (ns.Look.tilePool), taken while its section shows
-- and given back when it hides: nothing here runs while the page is closed.
local _, ns = ...

local SP = {}
ns.StylesPage = SP

local Page, K, L, S = ns.Page, ns.Options.kit, ns.Look, ns.Style
local LABEL_W = Page.LABEL_W

local SIZES = { small = 40, large = 56 }
-- A cell's backdrop, and the text on it.
local BACKDROPS = {
	dark = { bg = { 0.04, 0.045, 0.06 }, text = { 0.8, 0.8, 0.83 } },
	snow = { bg = { 0.91, 0.93, 0.95 }, text = { 0.2, 0.22, 0.25 } },
}
local GAP = 6              -- between cells in a row section
local ROW_HEAD_W = 104     -- the pop grid's row names
local PLAY_STEP = 0.03     -- Play all: seconds from one cell's pop to the next

-- What every cell shows, chosen on the strip at the top: the element the looks take and its sample
-- icon, the backdrop, the icon size, the pop's colour, and the pop grid's flash. For this session.
local view = { school = "fire", backdrop = "dark", size = "small",
	colorBy = S.KINDS.pop.defaults.colorBy, flash = S.KINDS.pop.defaults.flash }

local function size() return SIZES[view.size] end
local function schoolOf(key)
	for _, sc in ipairs(L.SCHOOLS) do if sc.key == key then return sc end end
	return L.SCHOOLS[1]
end
local function schoolName(sc) return sc.name or sc.key:gsub("^%l", string.upper) end

-- A kind's shipped style: every field at its default.
local function neutral(kind)
	local spec = S.KINDS[kind]
	return S.clean(nil, spec.defaults, spec.ranges)
end

------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------
-- A cell's tile in its look, on shipped settings, in the strip's element.
local function dress(c)
	local t = c.tile
	local over = { border = neutral("border"), glow = neutral("glow"), pop = neutral("pop") }
	over.pop.colorBy = view.colorBy
	for k, v in pairs(c.fields()) do over[c.kind][k] = v end
	local sc = schoolOf(view.school)
	t:wear(nil, over)
	t:school(sc.key)
	t:icon(sc.icon)
	t:glow(c.kind == "glow")
end

-- The question before a cell's look goes into General's style.
local KIND_NAMES = { border = "border look", glow = "pulsing glow", pop = "pop" }
local AFTER = {
	border = K.relayout,
	-- As the glow and pop blocks' own changes: glows under Blizzard's aura buttons take a style
	-- through their module's hook.
	glow = function() ns.Effects.applyStyle(); ns.applyTimers(); ns.Options.refresh() end,
	pop = function() ns.applyTimers(); ns.Options.refresh() end,
}
K.confirm("SHAMANFOREVER_USE_STYLE", "Use %s for General's %s?", "Use", function(run) run() end)

-- Writes fields into General's style of kind, then what a change by hand runs.
local function use(kind, fields)
	for k, v in pairs(fields) do S.set(nil, kind, k, v) end
	AFTER[kind]()
end

-- The fields as the cell shows them when asked: the strip may change while the question is open.
local function askUse(c)
	local fields = c.fields()
	StaticPopup_Show("SHAMANFOREVER_USE_STYLE", c.name(), KIND_NAMES[c.kind], function() use(c.kind, fields) end)
end

local function menu(c)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(c.frame, function(_, root)
		root:CreateTitle(c.name())
		root:CreateButton("Use as General setting", function() askUse(c) end)
	end)
end

-- A cell: its frame (the backdrop and the mouse), the tile it holds while its section shows, and
-- what it shows: kind (border, glow or pop), fields() (the style fields it sets), name() (for the
-- menu and the question) and hover (it pops under the mouse).
local function newCell(parent, kind, fields, name, hover)
	local c = { kind = kind, fields = fields, name = name, hover = hover }
	local f = CreateFrame("Button", nil, parent)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f:SetScript("OnEnter", function() if c.hover and c.tile then c.tile:pop("ready") end end)
	f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then menu(c) end end)
	c.frame = f
	return c
end

local function paintCell(c)
	local b = BACKDROPS[view.backdrop]
	c.frame.bg:SetColorTexture(b.bg[1], b.bg[2], b.bg[3], 1)
	if c.text then c.text:SetTextColor(b.text[1], b.text[2], b.text[3]) end
end

------------------------------------------------------------------------
-- Sections: a row of the page holding cells, which takes its tiles while it shows
------------------------------------------------------------------------
local sections = {}

-- Tiles for every cell, dressed; none while the row is hidden.
local function take(sec)
	if sec.held then return end
	sec.held = true
	local s = size()
	for _, c in ipairs(sec.cells) do
		c.tile = L.tilePool.acquire(c.frame, s)
		dress(c)
	end
end

local function give(sec)
	if sec.stop then sec.stop() end
	if not sec.held then return end
	sec.held = false
	for _, c in ipairs(sec.cells) do
		L.tilePool.release(c.tile)
		c.tile = nil
	end
end

local function newSection(p, place)
	local f = p:row(1)
	local sec = { frame = f, cells = {}, height = 1 }
	f:SetScript("OnHide", function() give(sec) end)
	p:add(f, function() return sec.height end, nil, function()
		-- A strip change dresses the tiles again: given back, taken anew (the pool reuses them).
		if sec.stale then give(sec); sec.stale = false end
		sec.height = place(sec, p:width())
		if f:IsVisible() then take(sec) end
		-- Each tile centred in its cell's stage, which follows the page's width in the pop grid.
		for _, c in ipairs(sec.cells) do
			paintCell(c)
			if c.tile then c.tile:point("CENTER", c.frame, "TOP", 0, -c.stageH / 2) end
		end
	end)
	table.insert(sections, sec)
	return sec
end

local function restyleAll()
	for _, sec in ipairs(sections) do sec.stale = true end
	ns.Options.refresh()
end

-- Cells in rows that wrap at the page's width, under each group's title (the border looks'
-- groups), each with its name under it.
local function flowSection(p, kind, field)
	local list = S.field(kind, field)
	local parts = S.sections(kind, field)
	local groups = {}
	local sec = newSection(p, function(sec, w)
		local s = size()
		local cw, stageH = s + 44, math.floor(s * 1.5 + 0.5)
		local y = 0
		for _, g in ipairs(groups) do
			if g.title then
				g.title:ClearAllPoints()
				g.title:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 2, -y)
				y = y + 16
			end
			local ch = stageH + 30 + (g.badged and 18 or 0)
			local x = 0
			for _, c in ipairs(g.cells) do
				if x > 0 and x + cw > w then x, y = 0, y + ch + GAP end
				c.stageH = stageH
				c.frame:ClearAllPoints()
				c.frame:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", x, -y)
				c.frame:SetSize(cw, ch)
				c.text:SetWidth(cw - 6)
				c.text:ClearAllPoints()
				c.text:SetPoint("TOP", c.frame, "TOP", 0, -(stageH + 2))
				x = x + cw + GAP
			end
			y = y + ch + GAP * 2
		end
		return math.max(y - GAP * 2, 1)
	end)
	for _, part in ipairs(parts) do
		local g = { cells = {} }
		if part.name and #parts > 1 then
			g.title = sec.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			g.title:SetText(part.name)
		end
		for _, e in ipairs(part.list) do
			-- A border cell also turns General's border on: it shows one.
			local fields = kind == "border" and function() return { look = e.key, show = true } end
				or function() return { [field] = e.key } end
			local c = newCell(sec.frame, kind, fields, function() return e.name end)
			c.text = c.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			c.text:SetMaxLines(2)
			c.text:SetText(e.name)
			if e.experimental then
				c.badge = L.expBadge(c.frame, list.name)
				c.badge:SetPoint("TOP", c.text, "BOTTOM", 0, -2)
				g.badged = true
			end
			table.insert(g.cells, c)
			table.insert(sec.cells, c)
		end
		table.insert(groups, g)
	end
	return sec
end

------------------------------------------------------------------------
-- The pop grid: bursts (rows, by group) against motions (columns), each cell with the flash above
------------------------------------------------------------------------
local function popGrid(p)
	local bursts, motions = S.offered("pop", "burst"), S.offered("pop", "motion")
	local burstList, motionList = S.field("pop", "burst"), S.field("pop", "motion")
	local groupName = {}
	for _, g in ipairs(burstList.groups or {}) do groupName[g[1]] = g[2] end
	local rows, cols = {}, {}
	local sec = newSection(p, function(sec, w)
		local s = size()
		local pitch = math.floor(math.min(math.max((w - ROW_HEAD_W) / #motions, s * 1.3), s * 1.8))
		local headH = 34
		for _, col in ipairs(cols) do if col.badge then headH = 52 end end
		for j, col in ipairs(cols) do
			col.text:SetWidth(pitch - 4)
			col.text:ClearAllPoints()
			col.text:SetPoint("BOTTOM", sec.frame, "TOPLEFT", ROW_HEAD_W + (j - 0.5) * pitch, -(headH - 4))
			if col.badge then
				col.badge:ClearAllPoints()
				col.badge:SetPoint("BOTTOM", col.text, "TOP", 0, 2)
			end
		end
		for i, row in ipairs(rows) do
			local y = headH + (i - 1) * pitch
			row.text:ClearAllPoints()
			row.text:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", 2, -(y + pitch / 2 - 14))
			for j, c in ipairs(row.cells) do
				c.stageH = pitch - 1
				c.frame:ClearAllPoints()
				c.frame:SetPoint("TOPLEFT", sec.frame, "TOPLEFT", ROW_HEAD_W + (j - 1) * pitch, -y)
				c.frame:SetSize(pitch - 1, pitch - 1)
			end
		end
		return headH + #rows * pitch
	end)
	for _, m in ipairs(motions) do
		local col = { text = sec.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
		col.text:SetMaxLines(2)
		col.text:SetText(m.name)
		if m.experimental then col.badge = L.expBadge(sec.frame, motionList.name) end
		table.insert(cols, col)
	end
	local function flashName() return S.choice("pop", "flash", view.flash).name end
	local function colorName() return S.choice("pop", "colorBy", view.colorBy).name:lower() end
	for _, b in ipairs(bursts) do
		local row = { cells = {} }
		row.text = sec.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetWidth(ROW_HEAD_W - 8)
		row.text:SetJustifyH("LEFT")
		local sub = groupName[b.group] and ("\n|cff9a9aa0" .. groupName[b.group] .. "|r") or ""
		row.text:SetText(b.name .. sub)
		if b.experimental then
			row.badge = L.expBadge(sec.frame, burstList.name)
			row.badge:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		end
		for _, m in ipairs(motions) do
			local c = newCell(sec.frame, "pop",
				function() return { burst = b.key, motion = m.key, flash = view.flash, colorBy = view.colorBy } end,
				function() return b.name .. ", " .. m.name .. ", " .. flashName() .. " and colour " .. colorName() end,
				true)
			table.insert(row.cells, c)
			table.insert(sec.cells, c)
		end
		table.insert(rows, row)
	end
	-- Play all: every cell's pop, one after the other a moment apart (all at once would read as one
	-- flash), from a frame that runs only while it plays and stops when the section hides.
	local driver = CreateFrame("Frame", nil, sec.frame)
	driver:Hide()
	local at, wait = 0, 0
	driver:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		while wait <= 0 do
			at = at + 1
			local c = sec.cells[at]
			if not c then self:Hide(); return end
			if c.tile then c.tile:pop("ready") end
			wait = wait + PLAY_STEP
		end
	end)
	sec.stop = function() driver:Hide() end
	function sec.playAll()
		if not sec.held then return end
		at, wait = 0, 0
		driver:Show()
	end
	return sec
end

------------------------------------------------------------------------
-- The strip: a row of flat buttons, the chosen one outlined in gold
------------------------------------------------------------------------
local function chips(p, label, items, get, set)
	local f = p:row(26)
	p:label(f, label)
	local buttons, x = {}, LABEL_W
	for _, it in ipairs(items) do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		b:SetBackdrop(ns.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(it[2])
		local w = math.ceil(b.text:GetStringWidth()) + 20
		b:SetSize(w, 20)
		b:SetPoint("LEFT", f, "LEFT", x, 0)
		x = x + w + 2
		b:SetScript("OnClick", function()
			if get() == it[1] then return end
			set(it[1])
			restyleAll()
		end)
		b.value = it[1]
		table.insert(buttons, b)
	end
	p:add(f, 26, nil, function()
		for _, b in ipairs(buttons) do L.paintChoice(b, get() == b.value) end
	end)
	return f
end

local function choiceItems(kind, field)
	local out = {}
	for _, e in ipairs(S.offered(kind, field)) do table.insert(out, { e.key, e.name }) end
	return out
end

local function field(key) return function() return view[key] end, function(v) view[key] = v end end

------------------------------------------------------------------------
-- The page
------------------------------------------------------------------------
function SP.build(p)
	p:pageTitle("Styles")
	p:text("Each look on its own, everything else as shipped. Hover a pop to play it; right-click any look to use it in General.")
	local schools = {}
	for _, sc in ipairs(L.SCHOOLS) do table.insert(schools, { sc.key, schoolName(sc) }) end
	chips(p, "Element", schools, field("school"))
	chips(p, "Background", { { "dark", "Dark" }, { "snow", "Snow" } }, field("backdrop"))
	chips(p, "Size", { { "small", "Small" }, { "large", "Large" } }, field("size"))
	chips(p, "Colour", choiceItems("pop", "colorBy"), field("colorBy"))

	p:header("Border look")
	flowSection(p, "border", "look")
	p:header("Pulsing glow")
	flowSection(p, "glow", "look")
	p:header("Pop")
	local flashRow = chips(p, S.field("pop", "flash").name, choiceItems("pop", "flash"), field("flash"))
	local grid
	local play = CreateFrame("Button", nil, flashRow, "UIPanelButtonTemplate")
	play:SetSize(80, 22)
	play:SetText("Play all")
	play:SetPoint("RIGHT", flashRow, "RIGHT", -4, 0)
	play:SetScript("OnClick", function() grid.playAll() end)
	grid = popGrid(p)
end
