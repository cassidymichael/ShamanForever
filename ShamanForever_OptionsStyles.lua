-- The options window's Styles explorer page: a gallery of every border look, pulsing glow and
-- pop, each on one sample icon with everything else as shipped (never the player's own settings).
-- Right-click one to use it in General. The looks come from ns.Style's choices, so a new one shows
-- up here with no page code. The border and glow icons are look tiles (ns.Look.tilePool), taken
-- while their section shows and given back when it hides; the pop grid's cells hold a still
-- picture and take a tile only while they play. Nothing here runs while the page is closed.
local _, ns = ...

local SP = {}
ns.StylesPage = SP

local Page, K, L, S = ns.Page, ns.Options.kit, ns.Look, ns.Style
local pool = L.tilePool

local SIZES = { small = 40, large = 64 }
-- A cell's backdrop, and the text on it.
local BACKDROPS = {
	dark = { bg = { 0.04, 0.045, 0.06 }, text = { 0.8, 0.8, 0.83 } },
	snow = { bg = { 0.91, 0.93, 0.95 }, text = { 0.2, 0.22, 0.25 } },
}
local GAP = 6              -- between cells in a row section
local ROW_HEAD_W = 120     -- the pop grid's row names and their Play
local MAKE_PER_FRAME = 3   -- tiles made in one frame at most: the first open spreads over a few
local PLAYERS = 6          -- pop grid cells playing at once (a row's worth)
local HOLD = 1.2           -- seconds a playing cell keeps its tile: past the longest pop

-- What every cell shows, chosen on the strip at the top: the element the looks take and its sample
-- icon (or All: a look that differs by element once for each), the backdrop, the icon size, the scale of every section (to see a border up close), the
-- pop's colour, and the pop grid's flash. For this session.
local view = { school = "fire", backdrop = "dark", size = "small", scale = 1,
	colorBy = S.KINDS.pop.defaults.colorBy, flash = S.KINDS.pop.defaults.flash }
local stamp = 0   -- counts strip changes: a tile dressed before the last one dresses again

local function size() return SIZES[view.size] end
local function schoolOf(key)
	for _, sc in ipairs(L.SCHOOLS) do if sc.key == key then return sc end end
	return L.SCHOOLS[1]
end

-- An owner whose border, glow and pop are as shipped, for the tiles to wear: every field set, so
-- ns.Style reads nothing from General.
local NEUTRAL = {}
for _, kind in ipairs({ "border", "glow", "pop" }) do
	local spec = S.KINDS[kind]
	local t = S.clean(nil, spec.defaults, spec.ranges)
	t.follow = false
	NEUTRAL[spec.path[1]] = t
end

------------------------------------------------------------------------
-- Using a look in General
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- Cells and their tiles
------------------------------------------------------------------------
-- With All, a cell whose look is the same in every element takes spirit's.
local ALL, REST = "all", "spirit"
local function cellSchool(c) return schoolOf(c.school or (view.school == ALL and REST or view.school)) end
-- Whether a cell shows for the strip's element: one per element with All, else the one cell.
local function cellShown(c)
	if c.perSchool == nil then return true end
	return c.perSchool == (view.school == ALL)
end

-- A cell's tile in its look, on shipped settings, in its element, at the strip's size.
local function dress(c)
	local sc = cellSchool(c)
	c.tile:dress(NEUTRAL, { [c.kind] = c.fields() }, sc.key, sc.icon, size())
	c.tile:glow(c.kind == "glow")
	c.dressed = stamp
end

local function placeTile(c)
	c.tile:point("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
end

-- Making a tile takes a while (an icon with its effects); taking a free one back doesn't. At most
-- MAKE_PER_FRAME are made a frame, and the page refreshes the next frame for the rest.
local budget, budgetAt, again = 0, nil, false
local function mayMake()
	local _, free = pool.counts()
	if free > 0 then return true end
	local now = GetTime()
	if now ~= budgetAt then budget, budgetAt = MAKE_PER_FRAME, now end
	if budget > 0 then
		budget = budget - 1
		return true
	end
	if not again then
		again = true
		C_Timer.After(0, function() again = false; ns.Options.refresh() end)
	end
	return false
end

local players = {}   -- tiles that have played in the pop grid: their pops' parts are made

-- A cell takes back the tile it had last time where it can: that one has its look made already.
-- A border or glow cell new to the page leaves the pop grid's players free for it. A pop plays
-- at once, made or not.
local function takeTile(c, want)
	if not c.pop and not mayMake() then return false end
	want = want or c.last
	if not (want and want.released) and not c.pop then
		want = function(t) return not tContains(players, t) end
	end
	c.tile = pool.acquire(c.frame, size(), want)
	dress(c)
	placeTile(c)
	return true
end

local function giveTile(c)
	if not c.tile then return end
	c.last = c.tile
	pool.release(c.tile)
	c.tile = nil
end

-- A pop grid cell at rest: the sample icon in the shipped border, which is one line (ns.Style's
-- border defaults), as a picture over a square of the line's colour; the tile that plays draws the
-- real thing over it.
local function paintStill(c)
	local st, s, b = c.still, size(), NEUTRAL.border
	st.edge:ClearAllPoints()
	st.edge:SetPoint("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
	st.edge:SetSize(s, s)
	local o = b.show and ns.linePx(c.frame, b.size) or 0
	st.edge:SetColorTexture(b.color[1], b.color[2], b.color[3], b.color[4] or 1)
	st.edge:SetShown(b.show and not c.tile)
	st.pic:ClearAllPoints()
	st.pic:SetPoint("TOPLEFT", st.edge, "TOPLEFT", o, -o)
	st.pic:SetPoint("BOTTOMRIGHT", st.edge, "BOTTOMRIGHT", -o, o)
	st.pic:SetTexture(cellSchool(c).icon)
	st.pic:SetShown(not c.tile)
end

------------------------------------------------------------------------
-- Playing the pop grid: a few tiles move from cell to cell, each held while its pop plays
------------------------------------------------------------------------
local playing = {}   -- cell -> when its pop started
local warming = {}   -- tiles held while their pops' parts are made, before any play

local function stopPlay(c)
	if not playing[c] then return end
	playing[c] = nil
	giveTile(c)
	paintStill(c)
end

local function freePlayer()
	for _, t in ipairs(players) do if t.released then return t end end
end

local function play(c)
	if not c.frame:IsVisible() then return end
	if not c.tile then
		local n, oldest = 0, nil
		for o, at in pairs(playing) do
			n = n + 1
			if not oldest or at < playing[oldest] then oldest = o end
		end
		if n >= PLAYERS then stopPlay(oldest) end
		if not takeTile(c, freePlayer()) then return end
		if #players < PLAYERS and not tContains(players, c.tile) then table.insert(players, c.tile) end
		paintStill(c)
	end
	playing[c] = GetTime()
	c.tile:pop("ready")
	c.token = (c.token or 0) + 1
	local token = c.token
	C_Timer.After(HOLD, function() if c.token == token then stopPlay(c) end end)
end

local function stopAll()
	for c in pairs(playing) do stopPlay(c) end
end

-- Before any play, the grid's player tiles are made and popped once with nothing to show (which
-- makes their pops' parts), one a frame, over the first cells, which look the same at rest.
local function warm(sec)
	if #players + #warming >= PLAYERS or not sec.frame:IsVisible() then
		sec.warming = false
		for i = #warming, 1, -1 do
			local t = table.remove(warming, i)
			if not tContains(players, t) then table.insert(players, t) end
			pool.release(t)
		end
		return
	end
	if mayMake() then
		local c, n = nil, 0
		for _, o in ipairs(sec.cells) do
			if o.frame:IsShown() then n = n + 1 end
			if n == #warming + 1 then c = o break end
		end
		local t = pool.acquire(c.frame, size())
		local sc = cellSchool(c)
		t:dress(NEUTRAL, { pop = { burst = "none", motion = "none", flash = "none" } }, sc.key, sc.icon, size())
		t:point("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
		t:pop("ready")
		table.insert(warming, t)
	end
	C_Timer.After(0, function() warm(sec) end)
end

------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------
-- A cell: its frame (the backdrop and the mouse), the tile it holds, and what it shows: kind
-- (border, glow or pop), fields() (the style fields it sets), name() (for the menu and the
-- question), school (its own element, or the strip's) and pop (a pop grid cell: hovering or a
-- click plays it).
local function newCell(parent, kind, fields, name, pop)
	local c = { kind = kind, fields = fields, name = name, pop = pop }
	local f = CreateFrame("Button", nil, parent)
	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	if pop then
		c.still = { edge = f:CreateTexture(nil, "ARTWORK"), pic = f:CreateTexture(nil, "ARTWORK", nil, 1) }
		ns.cropIcon(c.still.pic)
	end
	f:SetScript("OnEnter", function() if c.pop then play(c) end end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then menu(c) elseif c.pop then play(c) end
	end)
	c.frame = f
	return c
end

local function paintCell(c)
	local b = BACKDROPS[view.backdrop]
	c.frame.bg:SetColorTexture(b.bg[1], b.bg[2], b.bg[3], 1)
	if c.text then c.text:SetTextColor(b.text[1], b.text[2], b.text[3]) end
end

------------------------------------------------------------------------
-- Sections: a row of the page holding cells
------------------------------------------------------------------------
local sections = {}

local function give(sec)
	for _, c in ipairs(sec.cells) do
		if playing[c] then stopPlay(c) else giveTile(c) end
	end
end

-- place(sec, width) lays the cells out and returns the height they take. A section of tiles
-- (border and glow) takes one for each cell while it shows; the pop grid's cells take theirs as
-- they play.
-- The cells sit on sec.box, at the strip's scale.
local function newSection(p, place, grid)
	local f = p:row(1)
	local sec = { frame = f, box = CreateFrame("Frame", nil, f), cells = {}, height = 1, grid = grid }
	sec.box:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f:SetScript("OnHide", function() give(sec) end)
	p:add(f, function() return sec.height end, nil, function()
		local k = view.scale
		local w = p:width() / k
		sec.box:SetScale(k)
		local h = place(sec, w)
		sec.box:SetSize(w, h)
		sec.height = h * k
		local visible = f:IsVisible()
		-- Cells hidden now give back first, so a cell shown again finds its own tile free.
		for _, c in ipairs(sec.cells) do
			if c.tile and not c.frame:IsShown() then
				if playing[c] then stopPlay(c) else giveTile(c) end
			end
		end
		for _, c in ipairs(sec.cells) do
			paintCell(c)
			local on = c.frame:IsShown()
			if c.tile and c.dressed ~= stamp then dress(c) end
			if not grid and visible and on and not c.tile then takeTile(c) end
			if c.tile then placeTile(c) end
			if c.still then paintStill(c) end
		end
		if grid and visible and #players < PLAYERS and not sec.warming then
			sec.warming = true
			warm(sec)
		end
	end)
	table.insert(sections, sec)
	return sec
end

local function restyleAll()
	stamp = stamp + 1
	stopAll()
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
				g.title:SetPoint("TOPLEFT", sec.box, "TOPLEFT", 2, -y)
				y = y + 16
			end
			local ch = stageH + 30 + (g.badged and 18 or 0)
			local x = 0
			for _, c in ipairs(g.cells) do
				local on = cellShown(c)
				c.frame:SetShown(on)
				if on then
					if x > 0 and x + cw > w then x, y = 0, y + ch + GAP end
					c.stageH = stageH
					c.frame:ClearAllPoints()
					c.frame:SetPoint("TOPLEFT", sec.box, "TOPLEFT", x, -y)
					c.frame:SetSize(cw, ch)
					c.text:SetWidth(cw - 6)
					c.text:ClearAllPoints()
					c.text:SetPoint("TOP", c.frame, "TOP", 0, -(stageH + 2))
					x = x + cw + GAP
				end
			end
			y = y + ch + GAP * 2
		end
		return math.max(y - GAP * 2, 1)
	end)
	for _, part in ipairs(parts) do
		local g = { cells = {} }
		if part.name and #parts > 1 then
			g.title = sec.box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			g.title:SetText(part.name)
		end
		for _, e in ipairs(part.list) do
			-- A border cell also turns General's border on: it shows one.
			local fields = kind == "border" and function() return { look = e.key, show = true } end
				or function() return { [field] = e.key } end
			-- A look that differs by element: one cell, and one per element for All.
			local schools = { false }
			if e.bySchool then for _, sc in ipairs(L.SCHOOLS) do table.insert(schools, sc) end end
			for _, sc in ipairs(schools) do
				local c = newCell(sec.box, kind, fields, function() return e.name end)
				if e.bySchool then c.perSchool, c.school = sc and true or false, sc and sc.key or nil end
				c.text = c.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				c.text:SetMaxLines(2)
				c.text:SetText(sc and (e.name .. ": " .. sc.name) or e.name)
				if e.experimental then
					c.badge = L.expBadge(c.frame, list.name)
					c.badge:SetPoint("TOP", c.text, "BOTTOM", 0, -2)
					g.badged = true
				end
				table.insert(g.cells, c)
				table.insert(sec.cells, c)
			end
		end
		table.insert(groups, g)
	end
	return sec
end

------------------------------------------------------------------------
-- The pop grid: bursts (rows, by group) against motions (columns), each cell with the flash above
------------------------------------------------------------------------
-- A small text link.
local function link(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT")
	b.text:SetText(text)
	b:SetSize(b.text:GetStringWidth() + 4, 16)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function() b.text:SetTextColor(1, 0.93, 0.6) end)
	b:SetScript("OnLeave", function() b.text:SetTextColor(1, 0.82, 0) end)
	return b
end

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
			col.text:SetPoint("BOTTOM", sec.box, "TOPLEFT", ROW_HEAD_W + (j - 0.5) * pitch, -(headH - 4))
			if col.badge then
				col.badge:ClearAllPoints()
				col.badge:SetPoint("BOTTOM", col.text, "TOP", 0, 2)
			end
		end
		local i = 0
		for _, row in ipairs(rows) do
			local on = row.shown()
			row.text:SetShown(on)
			row.play:SetShown(on)
			if row.badge then row.badge:SetShown(on) end
			for _, c in ipairs(row.cells) do c.frame:SetShown(on) end
			if on then i = i + 1 end
			local y = headH + (i - 1) * pitch
			row.text:ClearAllPoints()
			row.text:SetPoint("TOPLEFT", sec.box, "TOPLEFT", 2, -(y + pitch / 2 - 14))
			row.play:ClearAllPoints()
			row.play:SetPoint("TOPRIGHT", sec.box, "TOPLEFT", ROW_HEAD_W - 8, -(y + pitch / 2 - 14))
			for j, c in ipairs(row.cells) do
				c.stageH = pitch - 1
				c.frame:ClearAllPoints()
				c.frame:SetPoint("TOPLEFT", sec.box, "TOPLEFT", ROW_HEAD_W + (j - 1) * pitch, -y)
				c.frame:SetSize(pitch - 1, pitch - 1)
			end
		end
		return headH + i * pitch
	end, true)
	for _, m in ipairs(motions) do
		local col = { text = sec.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
		col.text:SetMaxLines(2)
		col.text:SetText(m.name)
		if m.experimental then col.badge = L.expBadge(sec.box, motionList.name) end
		table.insert(cols, col)
	end
	local function flashName() return S.choice("pop", "flash", view.flash).name end
	local function colorName() return S.choice("pop", "colorBy", view.colorBy).name:lower() end
	-- A burst that differs by element: one row, and one per element for All, named for it.
	local function addRow(b, sc)
		local row = { cells = {} }
		row.text = sec.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetWidth(ROW_HEAD_W - 44)
		row.text:SetJustifyH("LEFT")
		local sub = sc and sc.name or groupName[b.group]
		row.text:SetText(b.name .. (sub and ("\n|cff9a9aa0" .. sub .. "|r") or ""))
		if b.experimental then
			row.badge = L.expBadge(sec.box, burstList.name)
			row.badge:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		end
		for _, m in ipairs(motions) do
			local c = newCell(sec.box, "pop",
				function() return { burst = b.key, motion = m.key, flash = view.flash, colorBy = view.colorBy } end,
				function() return b.name .. ", " .. m.name .. ", " .. flashName() .. " and colour " .. colorName() end,
				true)
			if b.bySchool then c.perSchool, c.school = sc and true or false, sc and sc.key or nil end
			table.insert(row.cells, c)
			table.insert(sec.cells, c)
		end
		function row.shown() return cellShown(row.cells[1]) end
		-- Play: the row's cells at once.
		row.play = link(sec.box, "Play", function() for _, c in ipairs(row.cells) do play(c) end end)
		table.insert(rows, row)
	end
	for _, b in ipairs(bursts) do
		addRow(b)
		if b.bySchool then for _, sc in ipairs(L.SCHOOLS) do addRow(b, sc) end end
	end
	return sec
end

------------------------------------------------------------------------
-- The strip: rows of flat buttons, the chosen one outlined in gold, in a header that stays put
-- while the page scrolls under it
------------------------------------------------------------------------
local HEAD_H, HEAD_LABEL_W, HEAD_COL2 = 162, 84, 300

-- A label and its buttons at x, y in parent, choosing view[key]; returns refresh(), which marks
-- the one chosen.
local function chips(parent, label, items, key, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", parent, "TOPLEFT", x, y)
	fs:SetText(label)
	local buttons, bx = {}, x + HEAD_LABEL_W
	for _, it in ipairs(items) do
		local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
		b:SetBackdrop(ns.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(it[2])
		local w = math.ceil(b.text:GetStringWidth()) + 20
		b:SetSize(w, 20)
		b:SetPoint("LEFT", parent, "TOPLEFT", bx, y)
		bx = bx + w + 2
		b:SetScript("OnClick", function()
			if view[key] == it[1] then return end
			view[key] = it[1]
			restyleAll()
		end)
		b.value = it[1]
		table.insert(buttons, b)
	end
	return function()
		for _, b in ipairs(buttons) do L.paintChoice(b, view[key] == b.value) end
	end
end

-- Scale, 100% to 200%, at x, y in parent; returns refresh().
local function scaleSlider(parent, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", parent, "TOPLEFT", x, y)
	fs:SetText("Scale")
	local s = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	s:SetSize(150, 20)
	s:SetPoint("LEFT", parent, "TOPLEFT", x + HEAD_LABEL_W - 6, y)
	local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("LEFT", s, "RIGHT", 8, 0)
	local updating = false
	s:Init(view.scale, 1, 2, 10)
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		v = math.floor(v * 10 + 0.5) / 10
		if v == view.scale then return end
		view.scale = v
		restyleAll()
	end, s)
	return function()
		value:SetText(Page.pct(view.scale))
		if not (s.Slider and s.Slider:GetValue() == view.scale) then
			updating = true
			s:SetValue(view.scale)
			updating = false
		end
	end
end

local function choiceItems(kind, field)
	local out = {}
	for _, e in ipairs(S.offered(kind, field)) do table.insert(out, { e.key, e.name }) end
	return out
end

local function header(p)
	local h = CreateFrame("Frame", nil, p.win, "BackdropTemplate")
	h:SetHeight(HEAD_H - 14)
	h.heroH = HEAD_H
	Page.panelBackdrop(h)
	local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetShadowOffset(1, -1)
	title:SetText("Styles explorer")
	local intro = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	intro:SetTextColor(0.72, 0.72, 0.72)
	intro:SetText("Right-click a look to use it in General. Hover or click a pop to play it.")
	local schools = {}
	for _, sc in ipairs(L.SCHOOLS) do table.insert(schools, { sc.key, sc.name }) end
	table.insert(schools, { ALL, "All" })
	local paints = {
		chips(h, "Element", schools, "school", 14, -74),
		chips(h, "Background", { { "dark", "Dark" }, { "snow", "Snow" } }, "backdrop", 14, -100),
		chips(h, "Size", { { "small", "Small" }, { "large", "Large" } }, "size", HEAD_COL2, -100),
		chips(h, "Colour", choiceItems("pop", "colorBy"), "colorBy", 14, -126),
	}
	table.insert(paints, scaleSlider(h, HEAD_COL2, -126))
	function h.refresh() for _, paint in ipairs(paints) do paint() end end
	p:pin(h)
end

------------------------------------------------------------------------
-- The page
------------------------------------------------------------------------
function SP.build(p)
	header(p)
	p:header("Border look")
	flowSection(p, "border", "look")
	p:header("Pulsing glow")
	flowSection(p, "glow", "look")
	p:header("Pop")
	-- The flash every pop in the grid takes.
	local f = p:row(26)
	local paint = chips(f, S.field("pop", "flash").name, choiceItems("pop", "flash"), "flash", 4, -13)
	p:add(f, 26, nil, paint)
	popGrid(p)
end
