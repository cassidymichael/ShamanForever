-- Styles explorer: border looks, frames, glows and pops on sample icons, never the player's settings
local _, ns = ...

local SP = {}
ns.StylesPage = SP

local Page, K, L, S, FR = ns.Page, ns.Options.kit, ns.Look, ns.Style, ns.Frames
local pool = L.tilePool

local SIZES = { small = 40, large = 64 }
local BACKDROPS = {
	dark = { bg = { 0.04, 0.045, 0.06 }, text = { 0.8, 0.8, 0.83 } },
	snow = { file = 189053, tint = { 1, 1, 1 }, text = { 0.2, 0.22, 0.25 }, light = true },
	grass = { file = 187126, tint = { 0.75, 0.75, 0.75 }, text = { 1, 1, 0.92 } },
}
local TILE = 256
local GAP = 6
local ROW_HEAD_W = 120
local MAKE_PER_FRAME = 3
local PLAYERS = 6
local HOLD = 1.2

local view = { school = "all", backdrop = "dark", size = "small", scale = 1.2, colorBy = "school",
	flash = S.KINDS.pop.defaults.flash, frameBorder = true, groupDir = "row" }
local stamp = 0
local preview = { border = {}, glow = {}, pop = {}, frame = {} }

local function size() return SIZES[view.size] end
local function schoolOf(key)
	for _, sc in ipairs(L.SCHOOLS) do if sc.key == key then return sc end end
	return L.SCHOOLS[1]
end

local NEUTRAL = {}
local NEUTRAL_GROUP = S.clean(nil, S.KINDS.groupframe.defaults)
for _, kind in ipairs({ "border", "glow", "pop", "frame" }) do
	local spec = S.KINDS[kind]
	local t = S.clean(nil, spec.defaults, spec.ranges)
	t.follow = false
	NEUTRAL[spec.path[1]] = t
end

-- Using a look as a global style
local KIND_NAMES = { border = "border look", glow = "pulsing glow", pop = "pop", frame = "frame",
	groupframe = "group frame" }
local USE = { frame = "Use as Global frame", groupframe = "Use as Global group frame" }
local AFTER = {
	border = K.relayout, frame = K.relayout, groupframe = K.relayout,
	glow = function() ns.Effects.applyStyle(); ns.applyTimers(); ns.Options.refresh() end,
	pop = function() ns.applyTimers(); ns.Options.refresh() end,
}
K.confirm(ns.POPUP .. "USE_STYLE", "Use %s for the global %s?", "Use", function(run) run() end)

local function use(kind, fields)
	for k, v in pairs(fields) do S.set(nil, kind, k, v) end
	AFTER[kind]()
end

local function askUse(c)
	local fields = c.fields()
	StaticPopup_Show(ns.POPUP .. "USE_STYLE", c.name(), KIND_NAMES[c.kind],
		function() use(c.kind, fields) end)
end

local function menu(c)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(c.frame, function(_, root)
		root:CreateTitle(c.name())
		root:CreateButton(USE[c.kind] or "Use as Global style", function() askUse(c) end)
	end)
end

-- Cells and their tiles
local ALL, REST = "all", ns.THEME.fallback
local function cellSchool(c)
	return schoolOf(c.school or (view.school == ALL and REST or view.school))
end
local function cellShown(c)
	if c.perSchool == nil then return true end
	return c.perSchool == (view.school == ALL)
end

local function worn()
	local b = S.global("border")
	b.follow = false
	local o = {}
	for k, v in pairs(NEUTRAL) do o[k] = v end
	o[S.KINDS.border.path[1]] = b
	return o
end

local function sigOf(v)
	if type(v) ~= "table" then return tostring(v) end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. sigOf(x) end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

local borderSig
local function syncBorder()
	local sig = sigOf(S.read(nil, "border"))
	if sig == borderSig then return end
	if borderSig then stamp = stamp + 1 end
	borderSig = sig
end

local function dress(c)
	local sc = cellSchool(c)
	local own = {}
	for k, v in pairs(preview[c.kind]) do own[k] = v end
	for k, v in pairs(c.fields()) do own[k] = v end
	local over = { [c.kind] = own }
	if c.kind == "frame" and not view.frameBorder then over.border = { show = false } end
	c.tile:dress(c.kind == "border" and NEUTRAL or worn(), over, sc.key, sc.icon, size())
	c.tile:glow(c.kind == "glow")
	c.dressed = stamp
end

local function placeTile(c)
	c.tile:point("CENTER", c.frame, "TOP", 0, -c.stageH / 2)
end

-- Making a tile takes a while: at most MAKE_PER_FRAME a frame.
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

local players = {}

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

local function paintStill(c)
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

-- Playing the pop grid
local playing = {}
local warming = {}

local function stopPlay(c)
	if not playing[c] then return end
	playing[c] = nil
	giveTile(c)
	syncBorder()
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
		syncBorder()
		paintStill(c)
	end
	playing[c] = GetTime()
	c.tile:pop("ready")
	c.token = (c.token or 0) + 1
	local token = c.token
	local hold = HOLD / math.min(preview.pop.speed or 1, 1)
	C_Timer.After(hold, function() if c.token == token then stopPlay(c) end end)
end

local function stopAll()
	for c in pairs(playing) do stopPlay(c) end
end

-- Before any play the player tiles are popped once, so their pops' parts are made.
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

-- Cells
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

-- Sections
local sections = {}

local function give(sec)
	for _, c in ipairs(sec.cells) do
		if playing[c] then stopPlay(c) else giveTile(c) end
	end
end

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
		for _, c in ipairs(sec.cells) do
			if c.tile and not c.frame:IsShown() then
				if playing[c] then stopPlay(c) else giveTile(c) end
			end
		end
		for _, c in ipairs(sec.cells) do
			paintCell(c)
			local on = c.frame:IsShown()
			if c.tile and c.dressed ~= stamp then dress(c) end
			if not (grid or sec.stills) and visible and on and not c.tile then takeTile(c) end
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

local changes = 0
local function restyleSoon()
	changes = changes + 1
	local this = changes
	ns.Options.refresh()
	C_Timer.After(0.3, function() if changes == this then restyleAll() end end)
end

-- opts: keep(e) (offer only these), stage(e, s) (a cell's width and stage height)
local function flowSection(p, kind, field, opts)
	opts = opts or {}
	local list = S.field(kind, field)
	local parts = {}
	for _, part in ipairs(S.sections(kind, field)) do
		local kept = {}
		for _, e in ipairs(part.list) do if not opts.keep or opts.keep(e) then table.insert(kept, e) end end
		if #kept > 0 then table.insert(parts, { name = part.name, list = kept }) end
	end
	local groups = {}
	local sec = newSection(p, function(sec, w)
		local s = size()
		local y = 0
		for _, g in ipairs(groups) do
			if g.title then
				g.title:ClearAllPoints()
				g.title:SetPoint("TOPLEFT", sec.box, "TOPLEFT", 2, -y)
				y = y + 16
			end
			local x, rowH = 0, 0
			for _, c in ipairs(g.cells) do
				local on = cellShown(c)
				c.frame:SetShown(on)
				if on then
					local cw, stageH = s + 44, math.floor(s * 1.5 + 0.5)
					if opts.stage then cw, stageH = opts.stage(c.entry, s) end
					local ch = stageH + 30 + (g.badged and 18 or 0)
					if x > 0 and x + cw > w then x, y, rowH = 0, y + rowH + GAP, 0 end
					rowH = math.max(rowH, ch)
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
			y = y + rowH + GAP * 2
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
			local fields = kind == "border" and function() return { look = e.key, show = true } end
				or function() return { [field] = e.key } end
			local schools = { false }
			if e.bySchool then for _, sc in ipairs(L.SCHOOLS) do table.insert(schools, sc) end end
			for _, sc in ipairs(schools) do
				local c = newCell(sec.box, kind, fields, function() return e.name end)
				c.entry = e
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

-- Element frames: a cell as wide and tall as the look reaches
local function frameStage(e, s)
	local r = e.reach
	local across, up = math.max(r.left, r.right), math.max(r.top, r.bottom)
	return math.max(s + 44, math.ceil(s * (1 + 2 * across)) + 8), math.max(math.floor(s * 1.5 + 0.5), math.ceil(s * (1 + 2 * up)) + 8)
end
local function usableFrame(e) return not e.none and FR.usable(e) end

-- Group frames: each look round four still icons, drawn as a group's
local GROUP_N, GROUP_PAD, GROUP_GAP = 4, 10, 4
local function groupSection(p)
	local s0 = size()
	local sec
	sec = newSection(p, function(_, w)
		local s = size()
		local vertical = view.groupDir == "column"
		local x, y, rowH = 0, 0, 0
		for _, c in ipairs(sec.cells) do
			local look = c.entry
			local key = table.concat({ s, tostring(vertical), tostring(borderSig), c.frame:GetEffectiveScale() }, "|")
			if c.drawnAt ~= key then
				local lay = { size = s, n = GROUP_N, gap = FR.fitSpacing(look, s) or GROUP_GAP, vertical = vertical }
				local o = FR.groupLayout(look, lay, ns.pixel(c.frame)).outer
				local artW = o[3] - o[1] + 2 * GROUP_PAD
				c.cw, c.stageH = math.max(artW, 120), o[4] - o[2] + 2 * GROUP_PAD
				lay.x, lay.y = GROUP_PAD - o[1] + (c.cw - artW) / 2, GROUP_PAD - o[2]
				c.lay = lay
			end
			local cw, stageH, lay = c.cw, c.stageH, c.lay
			local ch = stageH + 30
			if x > 0 and x + cw > w then x, y, rowH = 0, y + rowH + GAP, 0 end
			rowH = math.max(rowH, ch)
			c.frame:ClearAllPoints()
			c.frame:SetPoint("TOPLEFT", sec.box, "TOPLEFT", x, -y)
			c.frame:SetSize(cw, ch)
			c.text:SetWidth(cw - 6)
			c.text:ClearAllPoints()
			c.text:SetPoint("TOP", c.frame, "TOP", 0, -(stageH + 2))
			x = x + cw + GAP
			if c.drawnAt ~= key then
				c.drawnAt = key
				local border = worn()[S.KINDS.border.path[1]]
				FR.drawGroup(c.host, look, lay, NEUTRAL_GROUP)
				for i, st in ipairs(c.stills) do
					local at = (i - 1) * (s + lay.gap)
					st:ClearAllPoints()
					st:SetPoint("TOPLEFT", c.host, "TOPLEFT", lay.x + (vertical and 0 or at), -(lay.y + (vertical and at or 0)))
					st:SetSize(s, s)
					st.ic.tex:SetTexture(L.SCHOOLS[i].icon)
					ns.Looks.fit(st.ic, border, s)
					st.ic:ClearAllPoints()
					st.ic:SetPoint("CENTER", st, "CENTER", 0, 0)
				end
			end
		end
		return math.max(y + rowH, 1)
	end)
	sec.stills = true
	for _, look in ipairs(FR.available("groupframe", nil, true)) do
		if not look.none then
			local c = newCell(sec.box, "groupframe", function() return { look = look.key } end, function() return look.name end)
			c.entry = look
			c.host = CreateFrame("Frame", nil, c.frame)
			c.host:SetAllPoints()
			c.stills = {}
			for i = 1, GROUP_N do
				local box = CreateFrame("Frame", nil, c.host)
				box:SetSize(s0, s0)
				box:SetFrameLevel(c.host:GetFrameLevel() + 3)
				box.ic = CreateFrame("Frame", nil, box)
				box.ic.tex = box.ic:CreateTexture(nil, "ARTWORK")
				box.ic.tex:SetAllPoints()
				ns.cropIconExact(box.ic.tex)
				c.stills[i] = box
			end
			c.text = c.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			c.text:SetMaxLines(2)
			c.text:SetText(look.name)
			table.insert(sec.cells, c)
		end
	end
	return sec
end

-- The pop grid
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
		row.play = link(sec.box, "Play", function() for _, c in ipairs(row.cells) do play(c) end end)
		table.insert(rows, row)
	end
	for _, b in ipairs(bursts) do
		addRow(b)
		if b.bySchool then for _, sc in ipairs(L.SCHOOLS) do addRow(b, sc) end end
	end
	return sec
end

-- The strip
local HEAD_H, HEAD_LABEL_W, HEAD_COL2 = 162, 84, 300

local function chips(parent, label, items, key, x, y)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", parent, "TOPLEFT", x, y)
	fs:SetText(label)
	local row = L.choiceRow(parent, items, function() return view[key] end, function(v)
		view[key] = v
		restyleAll()
	end)
	row:SetPoint("LEFT", parent, "TOPLEFT", x + HEAD_LABEL_W, y)
	return row.refresh
end

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
		chips(h, ns.THEME.axis.name, schools, "school", 14, -74),
		chips(h, "Background", { { "dark", "Dark" }, { "snow", "Snow" }, { "grass", "Grass" } }, "backdrop",
			14, -100),
		chips(h, "Size", { { "small", "Small" }, { "large", "Large" } }, "size", HEAD_COL2, -100),
		chips(h, "Colour", choiceItems("pop", "colorBy"), "colorBy", 14, -126),
	}
	table.insert(paints, scaleSlider(h, HEAD_COL2, -126))
	function h.refresh() for _, paint in ipairs(paints) do paint() end end
	p:pin(h)
end

-- The page
-- K 24 25 26 27 28 36
local GLOBAL = "Global settings"
local BLOCKS = { border = { "border", "Border style" }, glow = { "glow", "Pulsing glow style" },
	pop = { "pop", "Pop style" }, frame = { "frame", "Frame style" }, groupframe = { "groupframe", "Group frame style" } }

-- A row of chips and the Global settings link for a block without preview sliders
local function chipRow(p, label, items, key, kind)
	local f = p:row(26)
	local paint = chips(f, label, items, key, 4, -13)
	local block = BLOCKS[kind]
	local go = link(f, GLOBAL .. " > " .. block[2], function() ns.Options.openGlobal(block[1]) end)
	go:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	p:add(f, 26, nil, paint)
end

-- rows: { label, field, format, flip (shows 1 - the value) }
local function previewRows(p, kind, rows)
	local shipped = NEUTRAL[S.KINDS[kind].path[1]]
	for _, r in ipairs(rows) do
		local field, flip = r[2], r[4]
		local function get()
			local v = preview[kind][field] or shipped[field]
			return flip and 1 - v or v
		end
		local function set(v)
			preview[kind][field] = flip and 1 - v or v
			restyleSoon()
		end
		K.styleSlider(p, kind, field, r[1], nil, r[3], get, set)
	end
	local f = p:row(22)
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", f, "LEFT", 4, 0)
	text:SetTextColor(0.72, 0.72, 0.72)
	text:SetText("Preview only. Not all settings affect all styles. All settings:")
	local block = BLOCKS[kind]
	local go = link(f, GLOBAL .. " > " .. block[2], function() ns.Options.openGlobal(block[1]) end)
	go:SetPoint("LEFT", text, "RIGHT", 6, 0)
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
	p.allOpen = true
	p:header("Border look")
	previewRows(p, "border", { { "Border size", "size", px } })
	flowSection(p, "border", "look")
	p:header("Element frame")
	chipRow(p, "Border", { { true, "On" }, { false, "Off" } }, "frameBorder", "frame")
	flowSection(p, "frame", "look", { keep = usableFrame, stage = frameStage })
	p:header("Group frame")
	chipRow(p, "Direction", { { "row", "Row" }, { "column", "Column" } }, "groupDir", "groupframe")
	groupSection(p)
	p:header("Pulsing glow")
	previewRows(p, "glow", {
		{ "Pulse length", "speed", secs },
		{ "Pulse depth", "low", pct, true },
		{ "Thickness", "width", pct },
		{ "Intensity", "strength", pct },
	})
	flowSection(p, "glow", "look")
	p:header("Pop")
	local f = p:row(26)
	local paint = chips(f, S.field("pop", "flash").name, choiceItems("pop", "flash"), "flash", 4, -13)
	p:add(f, 26, nil, paint)
	previewRows(p, "pop", {
		{ "Motion distance", "size", pct },
		{ "Speed", "speed", pct },
		{ "Reach", "reach", pct },
	})
	popGrid(p)
end

ns.Options.registerPage("styles", { title = "Styles explorer", icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
	order = 30, build = SP.build })
