-- The options window's Styles explorer page: a gallery of every border look, pulsing glow and
-- pop, each on one sample icon with everything else as shipped (never the player's own settings).
-- Right-click one to use it as a global style. The looks come from ns.Style's choices, so a new one
-- shows up here with no page code. The border and glow icons are look tiles (ns.Look.tilePool),
-- taken while their section shows and given back when it hides; the pop grid's cells hold a still
-- picture and take a tile only while they play. Nothing here runs while the page is closed.
local _, ns = ...

local SP = {}
ns.StylesPage = SP

local Page, K, L, S = ns.Page, ns.Options.kit, ns.Look, ns.Style
local pool = L.tilePool

local SIZES = { small = 40, large = 64 }
-- A cell's backdrop: a colour, or the game's ground (Winterspring's snow, Elwynn's grass) tiled
-- every TILE units and tinted; and the text on it.
local BACKDROPS = {
	dark = { bg = { 0.04, 0.045, 0.06 }, text = { 0.8, 0.8, 0.83 } },
	snow = { file = 189053, tint = { 1, 1, 1 }, text = { 0.2, 0.22, 0.25 }, light = true },
	grass = { file = 187126, tint = { 0.75, 0.75, 0.75 }, text = { 1, 1, 0.92 } },
}
local TILE = 256
local GAP = 6              -- between cells in a row section
local ROW_HEAD_W = 120     -- the pop grid's row names and their Play
local MAKE_PER_FRAME = 3   -- tiles made in one frame at most: the first open spreads over a few
local PLAYERS = 6          -- pop grid cells playing at once (a row's worth)
local HOLD = 1.2           -- seconds a playing cell keeps its tile: past the longest pop

-- What every cell shows, chosen on the strip at the top: the element the looks take and its
-- sample icon (or All: a look that differs by element once for each), the backdrop, the icon size,
-- the scale of every section (to see a border up close), the pop's colour, and the pop grid's
-- flash. For this session. It opens on every element at once, with the pops coloured by element.
local view = { school = "all", backdrop = "dark", size = "small", scale = 1.2, colorBy = "school",
	flash = S.KINDS.pop.defaults.flash }
local stamp = 0   -- counts strip changes: a tile dressed before the last one dresses again
-- Each section's preview settings (its own sliders): style fields over the shipped ones, for the
-- gallery only, never saved.
local preview = { border = {}, glow = {}, pop = {} }

local function size() return SIZES[view.size] end
local function schoolOf(key)
	for _, sc in ipairs(L.SCHOOLS) do if sc.key == key then return sc end end
	return L.SCHOOLS[1]
end

-- An owner whose border, glow and pop are as shipped, for the tiles to wear: every field set, so
-- ns.Style reads nothing from the global styles.
local NEUTRAL = {}
for _, kind in ipairs({ "border", "glow", "pop" }) do
	local spec = S.KINDS[kind]
	local t = S.clean(nil, spec.defaults, spec.ranges)
	t.follow = false
	NEUTRAL[spec.path[1]] = t
end

------------------------------------------------------------------------
-- Using a look as a global style
------------------------------------------------------------------------
local KIND_NAMES = { border = "border look", glow = "pulsing glow", pop = "pop" }
local AFTER = {
	border = K.relayout,
	-- As the glow and pop blocks' own changes: glows under Blizzard's aura buttons take a style
	-- through their module's hook.
	glow = function() ns.Effects.applyStyle(); ns.applyTimers(); ns.Options.refresh() end,
	pop = function() ns.applyTimers(); ns.Options.refresh() end,
}
K.confirm("SHAMANFOREVER_USE_STYLE", "Use %s for the global %s?", "Use", function(run) run() end)

-- Writes fields into the global style of kind, then what a change by hand runs.
local function use(kind, fields)
	for k, v in pairs(fields) do S.set(nil, kind, k, v) end
	AFTER[kind]()
end

-- The fields as the cell shows them when asked: the strip may change while the question is open.
local function askUse(c)
	local fields = c.fields()
	StaticPopup_Show("SHAMANFOREVER_USE_STYLE", c.name(), KIND_NAMES[c.kind],
		function() use(c.kind, fields) end)
end

local function menu(c)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(c.frame, function(_, root)
		root:CreateTitle(c.name())
		root:CreateButton("Use as Global style", function() askUse(c) end)
	end)
end

------------------------------------------------------------------------
-- Cells and their tiles
------------------------------------------------------------------------
-- With All, a cell whose look is the same in every element takes spirit's.
local ALL, REST = "all", "spirit"
local function cellSchool(c)
	return schoolOf(c.school or (view.school == ALL and REST or view.school))
end
-- Whether a cell shows for the strip's element: one per element with All, else the one cell.
local function cellShown(c)
	if c.perSchool == nil then return true end
	return c.perSchool == (view.school == ALL)
end

-- The shipped settings, but with the Global border: what the glow and pop cells wear, so each looks
-- as it does on an element that follows Global. The border cells show each look on its own.
local function worn()
	local b = S.global("border")
	b.follow = false
	local o = {}
	for k, v in pairs(NEUTRAL) do o[k] = v end
	o[S.KINDS.border.path[1]] = b
	return o
end

-- A string that differs when a settings table's contents do.
local function sigOf(v)
	if type(v) ~= "table" then return tostring(v) end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. sigOf(x) end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Counts a change of the Global border like a strip change, so the cells wearing it dress again.
local borderSig
local function syncBorder()
	local sig = sigOf(S.global("border"))
	if sig == borderSig then return end
	if borderSig then stamp = stamp + 1 end
	borderSig = sig
end

-- A cell's tile in its look, on shipped settings, in its element, at the strip's size.
local function dress(c)
	local sc = cellSchool(c)
	local own = {}
	for k, v in pairs(preview[c.kind]) do own[k] = v end
	for k, v in pairs(c.fields()) do own[k] = v end
	c.tile:dress(c.kind == "border" and NEUTRAL or worn(), { [c.kind] = own }, sc.key, sc.icon, size())
	c.tile:glow(c.kind == "glow")
	c.dressed = stamp
end

local function placeTile(c)
	c.tile:point("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
end

-- Making a tile takes a while (an icon with its effects); taking a free one back doesn't. At most
-- MAKE_PER_FRAME are made a frame, and the page refreshes the next frame for the rest.
local budget, budgetAt, again = 0, nil, false
local function mayMake(spare)
	local _, free = pool.counts()
	if free - (spare or 0) > 0 then return true end
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
local function isPlayer(t) return tContains(players, t) end
local function notPlayer(t) return not isPlayer(t) end
local function takeTile(c, want)
	want = want or c.last
	local strict = false
	if not c.pop then
		if not (want and want.released) then want, strict = notPlayer, true end
		local spare = 0
		for _, t in ipairs(players) do if t.released then spare = spare + 1 end end
		if strict and not mayMake(spare) then return false end
	end
	c.tile = pool.acquire(c.frame, size(), want, strict)
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

-- A pop grid cell at rest: the sample icon in the Global border, drawn by the HUD's own border
-- code (Looks.fit) on a bare icon (a picture and nothing else), set as a tile's icon is, so the tile
-- that plays looks the same under it.
local function paintStill(c)
	syncBorder()
	local st, s = c.still, size()
	st.box:ClearAllPoints()
	st.box:SetPoint("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
	st.box:SetSize(s, s)
	local sc = cellSchool(c)
	local key = table.concat({ borderSig, s, sc.key, c.frame:GetEffectiveScale() }, "|")
	if st.drawn ~= key then
		st.drawn = key
		local b = worn()[S.KINDS.border.path[1]]
		st.ic.school = sc.key
		st.ic.tex:SetTexture(sc.icon)
		ns.Looks.fit(st.ic, b, s)
		st.ic:ClearAllPoints()
		st.ic:SetPoint("CENTER", st.box, "CENTER", 0, 0)
	end
	st.box:SetShown(not c.tile)
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
	-- A slower pop (its preview Speed) is held longer.
	local hold = HOLD / math.min(preview.pop.speed or 1, 1)
	C_Timer.After(hold, function() if c.token == token then stopPlay(c) end end)
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
			if #players < PLAYERS and not tContains(players, t) then table.insert(players, t) end
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
		local nothing = { pop = { burst = "none", motion = "none", flash = "none" } }
		t:dress(worn(), nothing, sc.key, sc.icon, size())
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
		local box = CreateFrame("Frame", nil, f)
		local ic = CreateFrame("Frame", nil, box)
		ic.tex = ic:CreateTexture(nil, "ARTWORK")
		ic.tex:SetAllPoints()
		ns.cropIconExact(ic.tex)
		-- Snapped as a tile's picture is, so the tile that plays lands on the same pixels.
		if ic.tex.SetSnapToPixelGrid then ic.tex:SetSnapToPixelGrid(true) end
		c.still = { box = box, ic = ic }
	end
	f:SetScript("OnEnter", function() if c.pop then play(c) end end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then menu(c) elseif c.pop then play(c) end
	end)
	c.frame = f
	return c
end

-- An element's name in its colour, darker on a light backdrop so it stays readable.
local function schoolText(sc, light)
	local c, k = sc.color, light and 0.6 or 1
	local function hex(x) return math.floor(x * k * 255) end
	return string.format("|cff%02x%02x%02x%s|r", hex(c[1]), hex(c[2]), hex(c[3]), sc.name)
end

local function paintCell(c)
	local b, bg = BACKDROPS[view.backdrop], c.frame.bg
	if b.file then
		bg:SetTexture(b.file, "REPEAT", "REPEAT")
		bg:SetVertexColor(b.tint[1], b.tint[2], b.tint[3], 1)
		bg:SetTexCoord(0, c.frame:GetWidth() / TILE, 0, c.frame:GetHeight() / TILE)
	else
		bg:SetColorTexture(b.bg[1], b.bg[2], b.bg[3], 1)
		bg:SetVertexColor(1, 1, 1, 1)
		bg:SetTexCoord(0, 1, 0, 1)
	end
	if c.text then c.text:SetTextColor(b.text[1], b.text[2], b.text[3]) end
	if c.label then c.text:SetText(c.label(b.light)) end
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
		syncBorder()
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

-- The same, once a run of changes (a slider's drag) has rested a moment.
local changes = 0
local function restyleSoon()
	changes = changes + 1
	local this = changes
	ns.Options.refresh()
	C_Timer.After(0.3, function() if changes == this then restyleAll() end end)
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
			-- A border cell also turns the global border on: it shows one.
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
				c.text:SetText(e.name)
				if sc then c.label = function(light) return e.name .. ": " .. schoolText(sc, light) end end
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
		local group = groupName[b.group]
		local sub = sc and schoolText(sc) or group and ("|cff9a9aa0" .. group .. "|r")
		row.text:SetText(b.name .. (sub and ("\n" .. sub) or ""))
		if b.experimental then
			row.badge = L.expBadge(sec.box, burstList.name)
			row.badge:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
		end
		for _, m in ipairs(motions) do
			local c = newCell(sec.box, "pop",
				function()
					return { burst = b.key, motion = m.key, flash = view.flash, colorBy = view.colorBy }
				end,
				function()
					return b.name .. ", " .. m.name .. ", " .. flashName() .. " and colour " .. colorName()
				end,
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
	-- The sections take the scale at once; the tiles dress again (their lines on whole pixels at it)
	-- once the slider has rested a moment, not at every step of a drag.
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		v = math.floor(v * 10 + 0.5) / 10
		if math.abs(v - view.scale) < 0.001 then return end
		view.scale = v
		restyleSoon()
	end, s)
	return function()
		value:SetText(Page.pct(view.scale))
		if not (s.Slider and math.abs(s.Slider:GetValue() - view.scale) < 0.001) then
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
	intro:SetText("Right-click a look to use it as a global style. Hover or click a pop to play it.")
	local schools = {}
	for _, sc in ipairs(L.SCHOOLS) do table.insert(schools, { sc.key, sc.name }) end
	table.insert(schools, { ALL, "All" })
	local paints = {
		chips(h, "Element", schools, "school", 14, -74),
		chips(h, "Background", { { "dark", "Dark" }, { "snow", "Snow" }, { "grass", "Grass" } }, "backdrop",
			14, -100),
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
-- The page the full settings are on, as the nav names it, and each kind's block there.
local GLOBAL = "Global settings"
local BLOCKS = { border = { "border", "Border style" }, glow = { "glow", "Pulsing glow style" },
	pop = { "pop", "Pop style" } }

-- A section's preview sliders, rows { label, field, min, max, step, format, flip } (flip: the slider
-- shows 1 - the value, as Pulse depth does), then a line saying they're a preview, with a link to
-- the block that has them all.
local function previewRows(p, kind, rows)
	local shipped = NEUTRAL[S.KINDS[kind].path[1]]
	for _, r in ipairs(rows) do
		local field, flip = r[2], r[7]
		local function get()
			local v = preview[kind][field] or shipped[field]
			return flip and 1 - v or v
		end
		local function set(v)
			preview[kind][field] = flip and 1 - v or v
			restyleSoon()
		end
		p:slider(r[1], nil, r[3], r[4], r[5], r[6], get, set)
	end
	local f = p:row(22)
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", f, "LEFT", 4, 0)
	text:SetTextColor(0.72, 0.72, 0.72)
	text:SetText("Preview only. Not all settings affect all styles. All settings:")
	local block = BLOCKS[kind]
	local go = link(f, GLOBAL .. " > " .. block[2], function() ns.Options.openGlobal(block[1]) end)
	go:SetPoint("LEFT", text, "RIGHT", 6, 0)
	-- Reset: the section's preview back to as shipped, at once (nothing saved is lost); shown while
	-- there is something to reset.
	local reset = Page.textLink(f, "Reset", function()
		wipe(preview[kind])
		restyleAll()
	end, true)
	reset:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	p:add(f, 22, nil, function() reset:SetShown(next(preview[kind]) ~= nil) end)
end

local pct, px = Page.pct, Page.px
local function secs(v) return string.format("%.1f s", v) end

function SP.build(p)
	header(p)
	p.allOpen = true   -- the gallery is the page: its sections start open
	p:header("Border look")
	previewRows(p, "border", { { "Border size", "size", 1, 8, 1, px } })
	flowSection(p, "border", "look")
	p:header("Pulsing glow")
	previewRows(p, "glow", {
		{ "Pulse length", "speed", 0.2, 2, 0.1, secs },
		{ "Pulse depth", "low", 0, 1, 0.05, pct, true },
		{ "Thickness", "width", 0.1, 0.5, 0.05, pct },
		{ "Intensity", "strength", 0.2, 2.5, 0.1, pct },
	})
	flowSection(p, "glow", "look")
	p:header("Pop")
	-- The flash every pop in the grid takes.
	local f = p:row(26)
	local paint = chips(f, S.field("pop", "flash").name, choiceItems("pop", "flash"), "flash", 4, -13)
	p:add(f, 26, nil, paint)
	local reach = S.KINDS.pop.ranges.reach
	previewRows(p, "pop", {
		{ "Motion distance", "size", 1.1, 1.8, 0.05, pct },
		{ "Speed", "speed", 0.5, 2, 0.1, pct },
		{ "Reach", "reach", reach[1], reach[2], 0.05, pct },
	})
	popGrid(p)
end
