-- Totem bar themes (a "look" in the code, `skin` in its settings)
-- Each look is a data entry; the bar, its range strip and the options' preview call the functions
-- below, which leave everything as it was for Default and take down what another look drew.
-- A look can own some of the bar's settings (`owns`): the options hide them, the player's own value
-- stays saved.
-- Nothing here reads a totem or an aura. The out-of-range mark keeps the strip's rule: it sits under
-- Blizzard's aura button.

local ADDON, ns = ...
local TB = ns.TotemBar

local SK = {}
TB.skin = SK

local S = ns.Style
local BLACK = { 0, 0, 0, 1 }
local GOLD = ns.StyleArt.GOLD
local RED = { 0.9, 0.12, 0.08, 1 }
local TRAY = { 0.047, 0.035, 0.024 }

-- Our art for Stone and bronze, by path
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local PLINTH = MEDIA .. "Plinth"
-- Plinth.tga (512x256): three one-piece plinths for four slots, drawn once, for a slot PL_SLOT
-- texels wide: rect { x, y, w, h }, each opening's left edge and the openings' top; and the plug
-- that seals a socket
local PL_SLOT = 48
local PLINTHS = {
	slim = { rect = { 1, 174, 248, 60 }, slotX = { 13.6, 71.2, 128.8, 186.4 }, slotY = 7.2 },
	normal = { rect = { 1, 100, 284, 72 }, slotX = { 21.6, 86, 150.4, 214.8 }, slotY = 13.2 },
	grand = { rect = { 1, 1, 322, 97 }, slotX = { 27.6, 100.8, 173.6, 246.4 }, slotY = 25.2 },
}
local PLUG = { 391, 1, 48, 48 }
SK.PLINTHS = { { "slim", "Slim" }, { "normal", "Normal" }, { "grand", "Grand" } }
local function plinthNow()
	return PLINTHS[ns.getDB() and TB.cfg().stonePlinth] or PLINTHS.normal
end
local function shares(pl)
	return (pl.slotX[2] - pl.slotX[1] - PL_SLOT) / PL_SLOT, pl.slotX[1] / PL_SLOT
end

local function borderStyle(look, size)
	local k = S.PARTS.border
	return S.clean({ show = true, look = look, size = size }, k.defaults, k.ranges)
end

-- The looks, in the order the options offer them. Entry fields: name, experimental, owns, border,
-- extrasBorder, behind, extrasScaleKey, fixedSlots (every element keeps a place; unshown ones are
-- sealed sockets), timeBar, mark, picker, arrow, badgeGap(size), rangeText
SK.LIST, SK.byKey = {}, {}
local function add(key, entry)
	entry.key = key
	table.insert(SK.LIST, entry)
	SK.byKey[key] = entry
end

add("default", { name = "Default" })

add("pixel", {
	name = "Pixel",
	owns = { border = true, range = true },
	border = function() return borderStyle("schooledge", TB.cfg().pixelEdge) end,
	extrasBorder = borderStyle("hairline"),
	behind = "tray", timeBar = "tip", mark = "edge",
	picker = "tray",
	rangeText = "Out of range, for totems that buff you: a red edge along the top of the slot.",
})

local function plinthReach(size)
	local pl = plinthNow()
	local u = size / PL_SLOT
	return pl.slotY * u, (pl.rect[4] - pl.slotY - PL_SLOT) * u
end

-- Stone and bronze: a carved plinth (fixed art sets the spacing, a row, pickers up), Call and Recall
-- in bronze medallions
add("stone", {
	name = "Stone and bronze",
	owns = function()
		local gap, cap = shares(plinthNow())
		return { border = true, spacing = gap, extrasGap = cap + 0.12, dir = "row", pop = "up",
			barPlace = true, extras = "ends", extrasScale = TB.cfg().stoneExtrasScale }
	end,
	border = borderStyle("line", 1), extrasBorder = borderStyle("medallion"),
	behind = "plinth", picker = "stone", arrow = "stone", fixedSlots = true,
	extrasScaleKey = "stoneExtrasScale",
	badgeGap = function(size) return select(2, plinthReach(size)) end,
})

local DEFAULT = SK.byKey.default
function SK.current()
	if not ns.getDB() then return DEFAULT end
	return SK.byKey[TB.cfg().skin] or DEFAULT
end

function SK.mark()
	local m = SK.current().mark
	if type(m) == "function" then return m() end
	return m
end
function SK.rangeText()
	local t = SK.current().rangeText
	if type(t) == "function" then return t() end
	return t
end

function SK.extrasScaleKey() return SK.current().extrasScaleKey or "extrasScale" end

-- A stone picker is a small plinth stood on end: the picked plinth's pieces turned a quarter, an
-- opening per button. Returns the measures (TB.popLength); nil for a plain picker
function SK.popMetrics(psz)
	if SK.current().picker ~= "stone" then return nil end
	local pl = plinthNow()
	local u = psz / PL_SLOT
	local r = pl.rect
	local gap = (pl.slotX[2] - pl.slotX[1] - PL_SLOT) * u
	return (r[3] - pl.slotX[4] - PL_SLOT) * u, pl.slotX[1] * u, gap, r[4] * u
end

function SK.fixedSlots() return SK.current().fixedSlots == true end

-- Settings a look owns: border, spacing, extrasGap, dir, pop, range, rangeHeight, barPlace,
-- extras, extrasScale (the layout reads them through TB.eff())
local function ownsNow()
	local o = SK.current().owns
	if type(o) == "function" then return o() end
	return o
end

function SK.owns(field)
	local o = ownsNow()
	return o ~= nil and o[field] ~= nil
end

local POPS = { row = { up = true, down = true }, column = { right = true, left = true } }
-- A look that sets the direction keeps the player's picker side when it fits
function SK.owned(field)
	local o = ownsNow()
	if not o then return nil end
	if field == "dir" or field == "extras" or field == "extrasScale" then return o[field] end
	if field == "pop" and o.pop then return o.pop end
	if field == "pop" and o.dir then
		local pop = TB.cfg().pop
		if POPS[o.dir][pop] then return nil end
		return o.dir == "row" and "up" or "right"
	end
	return nil
end

local borders = {}
function SK.border()
	local b = SK.current().border
	if type(b) ~= "function" then return b end
	local made = b()
	local key = made.look .. made.size
	borders[key] = borders[key] or made
	return borders[key]
end
function SK.extrasBorder() return SK.current().extrasBorder end

function SK.spacing(size)
	local o = ownsNow()
	local share = o and o.spacing
	if not share then return nil end
	return size * share, size * (o.extrasGap or share)
end

function SK.barPlace()
	if SK.owns("barPlace") or not ns.getDB() then return "in" end
	return TB.cfg().barPlace
end

local function outGap(size) return math.max(math.floor(size * 3 / ns.BASE_ICON_SIZE + 0.5), 2) end
local function outReach(size)
	if SK.barPlace() ~= "out" or not ns.Style.value("totembar", "uptime", "bar") then return 0 end
	return outGap(size) + ns.Style.value("totembar", "uptime", "barHeight")
end

function SK.badgeGap(size)
	local f = SK.current().badgeGap
	return (f and f(size) or 0) + outReach(size)
end

-- Drawing: each call draws the look picked now, or takes down what another look drew
local function insetRings(f, list, rings)
	local n, d = 0, 0
	for _, r in ipairs(rings) do
		local w, c = ns.linePx(f, r[1]), r[2]
		for side = 1, 4 do
			n = n + 1
			local t = list[n] or f:CreateTexture(nil, "BORDER")
			list[n] = t
			t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
			t:ClearAllPoints()
			if side == 1 then t:SetPoint("TOPLEFT", d, -d); t:SetPoint("TOPRIGHT", -d, -d); t:SetHeight(w)
			elseif side == 2 then t:SetPoint("BOTTOMLEFT", d, d); t:SetPoint("BOTTOMRIGHT", -d, d); t:SetHeight(w)
			elseif side == 3 then t:SetPoint("TOPLEFT", d, -d - w); t:SetPoint("BOTTOMLEFT", d, d + w); t:SetWidth(w)
			else t:SetPoint("TOPRIGHT", -d, -d - w); t:SetPoint("BOTTOMRIGHT", -d, d + w); t:SetWidth(w) end
			t:Show()
		end
		d = d + w
	end
	for i = n + 1, #list do list[i]:Hide() end
	return d
end

local trays = setmetatable({}, { __mode = "k" })
local function tray(host, boxes, size, on)
	local t = trays[host]
	if not on then
		if t then t:Hide() end
		return
	end
	if not t then
		t = CreateFrame("Frame", nil, host)
		t:EnableMouse(false)
		t.fill = t:CreateTexture(nil, "BACKGROUND")
		t.lines = {}
		trays[host] = t
	end
	t:SetFrameLevel(host:GetFrameLevel())
	local pad = ns.roundPx(size * 0.12, ns.pixel(host))
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", boxes[1], "TOPLEFT", -pad, pad)
	t:SetPoint("BOTTOMRIGHT", boxes[#boxes], "BOTTOMRIGHT", pad, -pad)
	local d = insetRings(t, t.lines, { { 1, BLACK }, { 1, GOLD }, { 1, BLACK } })
	t.fill:ClearAllPoints()
	t.fill:SetPoint("TOPLEFT", d, -d)
	t.fill:SetPoint("BOTTOMRIGHT", -d, d)
	t.fill:SetColorTexture(TRAY[1], TRAY[2], TRAY[3], 0.82)
	t:Show()
end

local function plinthPiece(t, r)
	t:SetTexture(PLINTH)
	t:SetTexCoord(r[1] / 512, (r[1] + r[3]) / 512, r[2] / 256, (r[2] + r[4]) / 256)
end
-- The Stone and bronze plinth: one piece stretched from the first box to the last, so its openings
-- meet them whatever the rounding. A row only
local plinths = setmetatable({}, { __mode = "k" })
local function plinth(host, boxes, size, on, sealed)
	local f = plinths[host]
	if not on then
		if f then f:Hide() end
		return
	end
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:EnableMouse(false)
		f.art = f:CreateTexture(nil, "BACKGROUND")
		f.plugs = {}
		plinths[host] = f
	end
	f:SetFrameLevel(host:GetFrameLevel())
	f:SetAllPoints(host)
	local pl = plinthNow()
	local u = size / PL_SLOT
	local r = pl.rect
	plinthPiece(f.art, r)
	f.art:ClearAllPoints()
	f.art:SetPoint("TOPLEFT", boxes[1], "TOPLEFT", -pl.slotX[1] * u, pl.slotY * u)
	f.art:SetPoint("BOTTOMRIGHT", boxes[#boxes], "BOTTOMRIGHT", (r[3] - pl.slotX[4] - PL_SLOT) * u,
		-(r[4] - pl.slotY - PL_SLOT) * u)
	sealed = sealed or {}
	for i, box in ipairs(boxes) do
		local plug = f.plugs[i]
		if sealed[box] then
			if not plug then
				plug = f:CreateTexture(nil, "ARTWORK")
				plinthPiece(plug, PLUG)
				f.plugs[i] = plug
			end
			plug:ClearAllPoints()
			plug:SetAllPoints(box)
			plug:Show()
		elseif plug then plug:Hide() end
	end
	f:Show()
end

function SK.layoutBar(host, boxes, size, row, sealed)
	local look = SK.current()
	tray(host, boxes, size, look.behind == "tray" and TB.cfg().pixelTray and #boxes > 0)
	plinth(host, boxes, size, look.behind == "plinth" and row and #boxes == 4, sealed)
end

-- "tip": a bright line where the fill ends, on the fill's own texture so it moves with the time
-- left at no cost
local function tip(t, on)
	local bar = t.bar
	local x = bar.skinTip
	if not on then
		if x then x:Hide() end
		return
	end
	if not x then
		x = bar:CreateTexture(nil, "OVERLAY", nil, 7)
		x:SetColorTexture(1, 1, 1, 0.9)
		x:SetBlendMode("ADD")
		bar.skinTip = x
	end
	local fill = bar:GetStatusBarTexture()
	x:ClearAllPoints()
	x:SetPoint("TOP", fill, "TOPRIGHT", 0, 0)
	x:SetPoint("BOTTOM", fill, "BOTTOMRIGHT", 0, 0)
	x:SetWidth(ns.linePx(bar, 1))
	x:Show()
end

local AWAY = { up = "below", down = "above", right = "left", left = "right" }
local function outsideBar(t, anchor, size, on)
	local bar = t.bar
	if not on then
		if bar.sfOutside then
			bar:SetOrientation("HORIZONTAL")
			bar:SetRotatesTexture(false)
			bar.sfOutside = nil
		end
		return
	end
	bar.sfOutside = true
	local _, border = TB.look()
	local d = ns.StyleArt.inset(anchor, border, size) + outGap(size)
	local thick = ns.Style.value("totembar", "uptime", "barHeight")
	local side = AWAY[TB.eff().pop]
	bar:ClearAllPoints()
	if side == "below" or side == "above" then
		local y = side == "below" and -d or d
		local edge, from = side == "below" and "TOP" or "BOTTOM", side == "below" and "BOTTOM" or "TOP"
		bar:SetPoint(edge .. "LEFT", anchor, from .. "LEFT", 0, y)
		bar:SetPoint(edge .. "RIGHT", anchor, from .. "RIGHT", 0, y)
		bar:SetHeight(thick)
		bar:SetOrientation("HORIZONTAL")
		bar:SetRotatesTexture(false)
	else
		local x = side == "left" and -d or d
		local edge, from = side == "left" and "RIGHT" or "LEFT", side == "left" and "LEFT" or "RIGHT"
		bar:SetPoint("TOP" .. edge, anchor, "TOP" .. from, x, 0)
		bar:SetPoint("BOTTOM" .. edge, anchor, "BOTTOM" .. from, x, 0)
		bar:SetWidth(thick)
		bar:SetOrientation("VERTICAL")
		bar:SetRotatesTexture(true)
	end
end

function SK.styleTimer(t, anchor, size)
	if not (t and t.bar) then return end
	local out = SK.barPlace() == "out"
	outsideBar(t, anchor, size, out)
	tip(t, not out and SK.current().timeBar == "tip")
end

-- Plain stone from the plinth's tall strip without stretching; a size that reads secret or empty
-- (anchored to a secure button) takes a short piece
local function turnedPiece(t, c0, c1)
	local r = plinthNow().rect
	local x0, x1 = (r[1] + c0) / 512, (r[1] + c1) / 512
	local y0, y1 = r[2] / 256, (r[2] + r[4]) / 256
	t:SetTexture(PLINTH)
	t:SetTexCoord(x0, y1, x1, y1, x0, y0, x1, y0)
end

local ARROW_BRONZE = { 0.9, 0.72, 0.42 }
function SK.styleArrow(t)
	local kind = SK.current().arrow
	if t.skinned then
		TB.plainArrow(t)
		if t.skinBg then t.skinBg:Hide() end
		t.skinned = nil
	end
	if not kind then return end
	t.skinned = true
	t:SetBackdropColor(0, 0, 0, 0)
	t:SetBackdropBorderColor(0, 0, 0, 0)
	local bg = t.skinBg
	if not bg then
		bg = t:CreateTexture(nil, "BACKGROUND", nil, 1)
		bg:SetAllPoints()
		t.skinBg = bg
	end
	local pl = plinthNow()
	turnedPiece(bg, pl.slotX[4] + PL_SLOT, pl.rect[3])
	bg:Show()
	-- The glyph is Blizzard's added highlight art (a black ground): tinted, still added
	t.glyph:SetVertexColor(ARROW_BRONZE[1], ARROW_BRONZE[2], ARROW_BRONZE[3], 1)
end

local function stonePicker(pop, p, n, psz)
	local pl = plinthNow()
	local first, last, gap = SK.popMetrics(psz)
	local f = p.stone
	if not f then
		f = { head = pop:CreateTexture(nil, "BACKGROUND", nil, 1),
			foot = pop:CreateTexture(nil, "BACKGROUND", nil, 1), tiles = {}, divs = {} }
		p.stone = f
	end
	local x1, x2, x4 = pl.slotX[1], pl.slotX[2], pl.slotX[4]
	local function place(t, y, h)
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 0, y)
		t:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", 0, y)
		t:SetHeight(h)
		t:Show()
	end
	turnedPiece(f.foot, x4 + PL_SLOT, pl.rect[3])
	place(f.foot, 0, first)
	local y = first
	for i = 1, n do
		local t = f.tiles[i] or pop:CreateTexture(nil, "BACKGROUND", nil, 1)
		f.tiles[i] = t
		turnedPiece(t, x1, x1 + PL_SLOT)
		place(t, y, psz)
		y = y + psz
		if i < n then
			local d = f.divs[i] or pop:CreateTexture(nil, "BACKGROUND", nil, 1)
			f.divs[i] = d
			turnedPiece(d, x1 + PL_SLOT, x2)
			place(d, y, gap)
			y = y + gap
		end
	end
	for i = n + 1, #f.tiles do f.tiles[i]:Hide() end
	for i = math.max(n, 1), #f.divs do f.divs[i]:Hide() end
	turnedPiece(f.head, 0, x1)
	place(f.head, y, last)
end

function SK.stylePopout(pop, n, psz)
	local kind = SK.current().picker
	local p = pop.skin
	if p then
		for _, t in ipairs(p.lines) do t:Hide() end
		if p.stone then
			p.stone.head:Hide()
			p.stone.foot:Hide()
			for _, t in ipairs(p.stone.tiles) do t:Hide() end
			for _, t in ipairs(p.stone.divs) do t:Hide() end
		end
	end
	if kind == "stone" then
		p = p or { lines = {} }
		pop.skin = p
		pop.bg:SetColorTexture(0, 0, 0, 0)
		stonePicker(pop, p, n, psz)
		return
	end
	if not kind then
		local fill = TB.POP_FILL
		if p then pop.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
		return
	end
	p = p or { lines = {} }
	pop.skin = p
	pop.bg:SetColorTexture(TRAY[1], TRAY[2], TRAY[3], 0.9)
	insetRings(pop, p.lines, { { 1, BLACK }, { 1, GOLD } })
end

-- Out of range: where the look's mark sits, or nil: the strip along the top. A mark over the
-- picture is the strip, as Default sizes it: Blizzard's part covers the mark in range with the
-- buff's icon, which can be another totem's. No whole-picture mark: in combat our texture under
-- Blizzard's part refuses SetTexture and SetAlpha, and a MOD tint under a parent at alpha 0 still
-- tints.
function SK.markRect(frame, size, inset)
	local kind = SK.mark()
	if not kind then return nil end
	return inset, -inset, size - 2 * inset, ns.linePx(frame, TB.cfg().rangeHeight)
end

local function markParts(m, icon)
	local p = m.skinParts
	if p then return p end
	p = { shade = m:CreateTexture(nil, "ARTWORK", nil, 1) }
	p.shade:SetAllPoints()
	if icon then ns.StyleArt.followMask(icon, p.shade) end
	m.skinParts = p
	return p
end

function SK.paintMark(m, w, h, icon)
	local kind = w and SK.mark()
	local p = m.skinParts
	if not kind then
		if p then
			p.shade:Hide()
			m.bg:Show()
		end
		return false
	end
	p = markParts(m, icon)
	m.bg:Hide()
	p.shade:SetColorTexture(RED[1], RED[2], RED[3], RED[4])
	p.shade:Show()
	return true
end

function SK.styleRangeButton(p, s)
	if not SK.mark() then return false end
	p.over.bg:SetColorTexture(0, 0, 0, 0)
	return true
end
