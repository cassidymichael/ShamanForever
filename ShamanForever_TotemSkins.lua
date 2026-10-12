-- Totem bar themes (a "look" in the code, `skin` in its settings), and the Totem band group art frame
-- Each look is a data entry; the bar and the options' preview call the functions below, which leave
-- everything as it was for Default and take down what another look drew.
-- A look can own some of the bar's settings (`owns`): the options hide them, the player's own value
-- stays saved.
-- Nothing here reads a totem or an aura.

local ADDON, ns = ...
local W = ns.Widgets
local P = ns.Profiles
local TB = ns.TotemBar

local TH = {}
TB.skin = TH

local S, FR = ns.Style, ns.Frames
local BLACK = { 0, 0, 0, 1 }
local GOLD = ns.StyleArt.GOLD
local TRAY = { 0.047, 0.035, 0.024 }
local THEME = ns.THEME

-- Our art, by path
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local TOTEMS = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Totems\\"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- Blizzard's Totem Action Bar art (128x256), in texels
local BLIZZ = "Interface\\Buttons\\UI-TotemBar"
local BZ = {
	empty = { earth = { 66, 96, 3, 33 }, fire = { 67, 97, 100, 130 }, water = { 39, 69, 209, 239 },
		air = { 66, 96, 36, 66 } },
	ring = { earth = { 1, 35, 172, 206 }, fire = { 36, 70, 172, 206 }, water = { 1, 35, 207, 240 },
		air = { 36, 70, 137, 171 }, spell = { 1, 35, 137, 171 } },
	top = { earth = { 0, 32, 46, 68 }, fire = { 33, 65, 46, 68 }, water = { 0, 32, 1, 23 },
		air = { 0, 32, 91, 113 }, spell = { 33, 65, 1, 23 } },
	mid = { earth = { 0, 32, 68, 88 }, fire = { 33, 65, 68, 88 }, water = { 0, 32, 23, 43 },
		air = { 0, 32, 113, 133 }, spell = { 33, 65, 23, 43 } },
	up = { earth = { 99, 127, 160, 178 }, fire = { 99, 127, 122, 140 }, water = { 99, 127, 199, 217 },
		air = { 99, 127, 237, 255 }, spell = { 99, 127, 84, 102 } },
	down = { earth = { 99, 127, 141, 159 }, fire = { 99, 127, 103, 121 }, water = { 99, 127, 180, 198 },
		air = { 99, 127, 218, 236 }, spell = { 99, 127, 65, 83 } },
}
local function blizzPiece(t, r, flip)
	t:SetTexture(BLIZZ)
	local top, bottom = r[3] / 256, r[4] / 256
	if flip then top, bottom = bottom, top end
	t:SetTexCoord(r[1] / 128, r[2] / 128, top, bottom)
end

-- One-piece plinths for four slots of PL_SLOT texels: rect, openings' left edges and top, per size
local PL_SLOT = 48
local PLINTH_ART = {
	stone = { file = MEDIA .. "Plinth", w = 512, h = 256, plug = { 391, 1, 48, 48 }, sizes = {
		slim = { rect = { 1, 174, 248, 60 }, slotX = { 13.6, 71.2, 128.8, 186.4 }, slotY = 7.2 },
		normal = { rect = { 1, 100, 284, 72 }, slotX = { 21.6, 86, 150.4, 214.8 }, slotY = 13.2 },
		grand = { rect = { 1, 1, 322, 97 }, slotX = { 27.6, 100.8, 173.6, 246.4 }, slotY = 25.2 },
	} },
	bosses = { file = TOTEMS .. "Bosses", w = 512, h = 128, plug = { 339, 1, 48, 48 }, capCut = 12,
		arrowCols = { 93.6, 111.6 }, sizes = {
		normal = { rect = { 1, 1, 336, 67 }, slotX = { 45.6, 111.6, 177.2, 242.8 }, slotY = 11.6 },
	} },
	wood = { file = TOTEMS .. "Wood", w = 512, h = 128, plug = { 336, 1, 48, 48 }, sizes = {
		normal = { rect = { 1, 1, 333, 93 }, slotX = { 37.6, 107.6, 177.6, 247.6 }, slotY = 23.6 },
	} },
	iron = { file = TOTEMS .. "Iron", w = 512, h = 128, plug = { 285, 1, 48, 48 }, sizes = {
		normal = { rect = { 1, 1, 282, 87 }, slotX = { 19.2, 84.4, 149.6, 214.8 }, slotY = 20.8 },
	} },
}
TH.PLINTHS = { { "slim", "Slim" }, { "normal", "Normal" }, { "grand", "Grand" } }

local function borderStyle(look, size)
	local k = S.PARTS.border
	return S.clean({ show = true, look = look, size = size }, k.defaults, k.ranges)
end

-- Border styles only themes use
local IRON, EMBER = { 0.16, 0.15, 0.15, 1 }, { 0.95, 0.42, 0.1, 1 }
S.addLook("border", "totembare", { name = "None", group = "lines", hidden = true })
S.addLook("border", "roundicon", { name = "Round", group = "lines", hidden = true,
	mask = { file = ROUND }, swipe = ROUND })
S.addLook("border", "woodedge", { name = "Slim wood", group = "painted", hidden = true, credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Wood", margin = 22, px = 4 } })
S.addLook("border", "ironedge", { name = "Iron edge", group = "lines", hidden = true,
	rings = { { color = BLACK }, { px = 2, color = IRON }, { color = EMBER } } })

-- A group art frame, offered for any group
local BAND = "TotemBand"
FR.addGroupStyle("totemband", { name = "Totem band", group = "painted", credit = "ai",
	cells = {
		first = { path = BAND, coords = { 0, 144 / 512, 0, 127 / 128 }, size = { 144, 127 } },
		unit = { path = BAND, coords = { 144 / 512, 226 / 512, 0, 127 / 128 }, size = { 82, 127 } },
		last = { path = BAND, coords = { 226 / 512, 370 / 512, 0, 127 / 128 }, size = { 144, 127 } },
		hole = { 75, 28, 56, 56 },
	} })

-- The looks, in the order the options offer them. Entry fields: name, experimental, owns, border,
-- extrasBorder, behind, plinth (PLINTH_ART key) and plinthSize(), extrasScaleKey, fixedSlots (every
-- element keeps a place; unshown ones are sealed sockets), dress (per-button art: "blizzard",
-- "plates", "boss"), dressInset (the share of the picture its dress covers from the edge), timeBar,
-- picker, arrow, badgeGap(size)
TH.LIST, TH.byKey = {}, {}
local function add(key, entry)
	entry.key = key
	table.insert(TH.LIST, entry)
	TH.byKey[key] = entry
end

-- The Totem theme setting is labelled experimental while any theme is
function TH.experimental()
	for _, e in ipairs(TH.LIST) do if e.experimental then return true end end
	return false
end

local DEFAULT
function TH.current()
	if not P.getDB() then return DEFAULT end
	return TH.byKey[TB.cfg().skin] or DEFAULT
end

local function plinthNow()
	local look = TH.current()
	local art = PLINTH_ART[look.plinth] or PLINTH_ART.stone
	local size = look.plinthSize and P.getDB() and look.plinthSize()
	return art.sizes[size] or art.sizes.normal, art
end
local function shares(pl)
	return (pl.slotX[2] - pl.slotX[1] - PL_SLOT) / PL_SLOT, pl.slotX[1] / PL_SLOT
end
local function plinthReach(size)
	local pl = plinthNow()
	local u = size / PL_SLOT
	return pl.slotY * u, (pl.rect[4] - pl.slotY - PL_SLOT) * u
end
local function belowPlinth(size) return select(2, plinthReach(size)) end

local function plinthOwns(extra, beyond)
	return function()
		local gap, cap = shares(plinthNow())
		local o = { border = true, spacing = gap, extrasGapShare = cap + (beyond or 0.1), dir = "row", pop = "up",
			barPlace = true, extras = "ends" }
		for k, v in pairs(extra and extra() or {}) do o[k] = v end
		return o
	end
end

add("default", { name = "Default" })
DEFAULT = TH.byKey.default

add("pixel", {
	name = "Pixel", experimental = true,
	owns = { border = true },
	border = function() return borderStyle("schooledge", TB.cfg().pixelEdge) end,
	extrasBorder = borderStyle("hairline"),
	behind = "tray", timeBar = "tip",
	picker = "tray",
})

-- Stone and bronze: a carved plinth (fixed art sets the spacing, a row, pickers up), Call and Recall
-- in bronze medallions
add("stone", {
	name = "Stone and bronze", experimental = true,
	plinth = "stone", plinthSize = function() return TB.cfg().stonePlinth end,
	owns = plinthOwns(function()
		local _, cap = shares(plinthNow())
		return { extrasGapShare = cap + 0.12, extrasScale = TB.cfg().stoneExtrasScale }
	end),
	border = borderStyle("line", 1), extrasBorder = borderStyle("medallion"),
	behind = "plinth", picker = "plinth", arrow = "plinth", fixedSlots = true,
	extrasScaleKey = "stoneExtrasScale", badgeGap = belowPlinth,
})

add("bosses", {
	name = "Stone bosses", experimental = true,
	plinth = "bosses",
	owns = plinthOwns(function() return { extrasGapShare = TB.cfg().extrasScale / 2 + 0.06 } end),
	border = borderStyle("line", 1), extrasBorder = borderStyle("roundicon"), dress = "boss",
	behind = "plinth", picker = "plinth", arrow = "plinth", fixedSlots = true,
	badgeGap = belowPlinth,
})

add("wood", {
	name = "Wood and bone", experimental = true,
	plinth = "wood", owns = plinthOwns(nil, -0.3),
	border = borderStyle("line", 1), extrasBorder = borderStyle("woodedge"),
	behind = "plinth", picker = "plinth", arrow = "plinth", fixedSlots = true, badgeGap = belowPlinth,
})

add("iron", {
	name = "Iron and ember", experimental = true,
	plinth = "iron", owns = plinthOwns(nil, 0.06),
	border = borderStyle("line", 1), extrasBorder = borderStyle("ironedge"),
	behind = "plinth", picker = "plinth", arrow = "plinth", fixedSlots = true, badgeGap = belowPlinth,
})

add("elements", {
	name = "Elements", experimental = true,
	owns = { border = true, spacing = 0.42, extrasGapShare = 0.42, barPlace = true },
	border = borderStyle("line", 1), extrasBorder = borderStyle("line", 1),
	dress = "plates", timeBar = "tip", picker = "element", arrow = "element",
	badgeGap = function(size) return math.floor(size * 0.16 + 0.5) end,
})

add("blizzard", {
	name = "Blizzard's totem bar", experimental = true,
	owns = { border = true, spacing = 8 / 30, extrasGapShare = 8 / 30, dir = "row", extras = "ends" },
	border = borderStyle("totembare"), extrasBorder = borderStyle("totembare"),
	dress = "blizzard", dressInset = 3 / 30, picker = "blizzard", arrow = "blizzard",
	badgeGap = function(size) return math.floor(size * 2 / 30 + 0.5) end,
})

function TH.extrasScaleKey() return TH.current().extrasScaleKey or "extrasScale" end

-- Blizzard's flyout: edge and gap as shares of its 24-texel button, which is 32 texels wide
local BZ_EDGE, BZ_GAP = 6 / 24, 2 / 24

-- A plinth picker is a small plinth stood on end: the plinth's pieces turned a quarter, an
-- opening per button. Returns the measures (TB.popLength); nil for a plain picker
function TH.popMetrics(psz)
	local kind = TH.current().picker
	if kind == "blizzard" then return psz * BZ_EDGE, psz * BZ_EDGE, psz * BZ_GAP, psz * 32 / 24 end
	if kind ~= "plinth" then return nil end
	local pl, art = plinthNow()
	local u = psz / PL_SLOT
	local r = pl.rect
	local gap = (pl.slotX[2] - pl.slotX[1] - PL_SLOT) * u
	if art.capCut then return art.capCut * u, art.capCut * u, gap, r[4] * u end
	return (r[3] - pl.slotX[4] - PL_SLOT) * u, pl.slotX[1] * u, gap, r[4] * u
end

function TH.fixedSlots() return TH.current().fixedSlots == true end

-- Settings a look owns: border, spacing, extrasGapShare, dir, pop, barPlace, extras,
-- extrasScale. Dir, pop, extras and extrasScale reach the layout through TB.eff(); spacing and
-- extrasGapShare are shares of the icon size, read through TH.spacing
local function ownsNow()
	local o = TH.current().owns
	if type(o) == "function" then return o() end
	return o
end

function TH.owns(field)
	local o = ownsNow()
	return o ~= nil and o[field] ~= nil
end

local POPS = { row = { up = true, down = true }, column = { right = true, left = true } }
-- A look that sets the direction keeps the player's picker side when it fits
function TH.owned(field)
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
function TH.border()
	local b = TH.current().border
	if type(b) ~= "function" then return b end
	local made = b()
	local key = made.look .. made.size
	borders[key] = borders[key] or made
	return borders[key]
end
function TH.extrasBorder() return TH.current().extrasBorder end

-- The picture's size inside a button whose border art frames it smaller (a medallion), for text
function TH.faceSize(b, sz, frame)
	local look = b and b.show and S.look("border", b.look)
	if not (look and look.art and look.art.inset) then return sz end
	return sz - 2 * ns.StyleArt.inset(frame, b, sz)
end

-- How far in from the edge of v's picture (w wide) its dress covers it, in whole pixels
function TH.dressInset(v, w)
	local share = TH.current().dressInset
	if not share then return 0 end
	local px = W.pixel(v)
	return math.ceil(w * share / px - 0.01) * px
end

function TH.spacing(size)
	local o = ownsNow()
	local share = o and o.spacing
	if not share then return nil end
	return size * share, size * (o.extrasGapShare or share)
end

function TH.barPlace()
	if TH.owns("barPlace") or not P.getDB() then return "in" end
	return TB.cfg().barPlace
end

local function outGap(size) return math.max(math.floor(size * 3 / W.BASE_ICON_SIZE + 0.5), 2) end
local function outReach(size)
	if TH.barPlace() ~= "out" or not ns.Style.value("totembar", "uptime", "bar") then return 0 end
	return outGap(size) + ns.Style.value("totembar", "uptime", "barHeight")
end

function TH.badgeGap(size)
	local f = TH.current().badgeGap
	return (f and f(size) or 0) + outReach(size)
end

-- Drawing: each call draws the look picked now, or takes down what another look drew
local function insetRings(f, list, rings)
	local n, d = 0, 0
	for _, r in ipairs(rings) do
		local w, c = W.linePx(f, r[1]), r[2]
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
	local pad = W.roundPx(size * 0.12, W.pixel(host))
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

local function plinthPiece(t, r, art)
	t:SetTexture(art.file)
	t:SetTexCoord(r[1] / art.w, (r[1] + r[3]) / art.w, r[2] / art.h, (r[2] + r[4]) / art.h)
end
-- The plinth: one piece stretched from the first box to the last, so its openings meet them
-- whatever the rounding. A row only
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
	local pl, art = plinthNow()
	local u = size / PL_SLOT
	local r = pl.rect
	plinthPiece(f.art, r, art)
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
				f.plugs[i] = plug
			end
			plinthPiece(plug, art.plug, art)
			plug:ClearAllPoints()
			plug:SetAllPoints(box)
			plug:Show()
		elseif plug then plug:Hide() end
	end
	f:Show()
end

function TH.layoutBar(host, boxes, size, row, sealed)
	local look = TH.current()
	tray(host, boxes, size, look.behind == "tray" and TB.cfg().pixelTray and #boxes > 0)
	plinth(host, boxes, size, look.behind == "plinth" and row and #boxes == 4, sealed)
end

-- el: nil for Call and Recall; w: v's width, passed as it can read secret under a secure button
local function dressParts(v)
	local d = v.skinDress
	if not d then
		d = {}
		v.skinDress = d
	end
	return d
end

local function blizzardDress(v, el, w)
	local d = dressParts(v)
	-- On the slot's art frame, over the out of range mark
	local ring = d.ring or (v.art or v):CreateTexture(nil, "OVERLAY", nil, 5)
	d.ring = ring
	blizzPiece(ring, BZ.ring[el or "spell"])
	local o = w * 2 / 30
	ring:ClearAllPoints()
	ring:SetPoint("TOPLEFT", v, "TOPLEFT", -o, o)
	ring:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", o, -o)
	ring:Show()
	-- Only bare: under a dimmed pick it muddies the pick
	if el and TB.cfg().empty == "blank" then
		local empty = d.empty or v:CreateTexture(nil, "BACKGROUND", nil, -8)
		d.empty = empty
		blizzPiece(empty, BZ.empty[el])
		empty:SetAllPoints(v)
		empty:Show()
	end
end

local function plateFill(t, col)
	t:SetColorTexture(1, 1, 1, 1)
	t:SetGradient("VERTICAL", CreateColor(col[1] * 0.5, col[2] * 0.5, col[3] * 0.5, 0.95),
		CreateColor(col[1] * 0.12, col[2] * 0.12, col[3] * 0.12, 0.92))
end
local function plateDress(v, el, w)
	local d = dressParts(v)
	local school = el or THEME.fallback
	local col = THEME.color[school]
	local f = d.plate
	if not f then
		f = CreateFrame("Frame", nil, v)
		f:EnableMouse(false)
		f.fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		f.fill:SetAllPoints()
		f.mat = f:CreateTexture(nil, "BACKGROUND", nil, -7)
		f.mat:SetAllPoints()
		f.mat:SetBlendMode("ADD")
		f.foot = f:CreateTexture(nil, "BORDER", nil, 1)
		f.lines = {}
		d.plate = f
	end
	f:SetFrameLevel(math.max(v:GetFrameLevel() - (TB.LAYER.look - TB.LAYER.plate), 0))
	local pad = W.roundPx(w * 0.16, W.pixel(v))
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", v, "TOPLEFT", -pad, pad)
	f:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", pad, -pad)
	plateFill(f.fill, col)
	local mat = THEME.material[school]
	f.mat:SetTexture(MEDIA .. (mat and mat.file or "Mat-Earth"))
	f.mat:SetTexCoord(0.2, 0.8, 0.2, 0.8)
	f.mat:SetVertexColor(col[1], col[2], col[3], 0.5)
	insetRings(f, f.lines, { { 1, BLACK }, { 1, { col[1], col[2], col[3], 0.85 } } })
	local px = W.linePx(f, 1)
	f.foot:ClearAllPoints()
	f.foot:SetPoint("BOTTOMLEFT", px, px)
	f.foot:SetPoint("BOTTOMRIGHT", -px, px)
	f.foot:SetHeight(W.linePx(f, 2))
	f.foot:SetColorTexture(col[1], col[2], col[3], 1)
	f:Show()
end

-- Art only: Call and Recall keep their own clickable size
local function bossDress(v, w)
	local d = dressParts(v)
	local t = d.boss or v:CreateTexture(nil, "OVERLAY", nil, 5)
	d.boss = t
	t:SetTexture(TOTEMS .. "Boss")
	local o = w / 2
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", v, "TOPLEFT", -o, o)
	t:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT", o, -o)
	t:Show()
end

function TH.dressSlot(v, el, w)
	local kind = TH.current().dress
	local d = v.skinDress
	if d then
		for _, t in pairs(d) do t:Hide() end
	end
	if kind == "blizzard" then blizzardDress(v, el, w)
	elseif kind == "plates" then plateDress(v, el, w)
	elseif kind == "boss" and not el then bossDress(v, w) end
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
	x:SetWidth(W.linePx(bar, 1))
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

function TH.styleTimer(t, anchor, size)
	if not (t and t.bar) then return end
	local out = TH.barPlace() == "out"
	outsideBar(t, anchor, size, out)
	tip(t, not out and TH.current().timeBar == "tip")
end

-- Plain plinth from its tall strip without stretching; a size that reads secret or empty
-- (anchored to a secure button) takes a short piece
local function turnedPiece(t, c0, c1)
	local pl, art = plinthNow()
	local r = pl.rect
	local x0, x1 = (r[1] + c0) / art.w, (r[1] + c1) / art.w
	local y0, y1 = r[2] / art.h, (r[2] + r[4]) / art.h
	t:SetTexture(art.file)
	t:SetTexCoord(x0, y1, x1, y1, x0, y0, x1, y0)
end

-- A picker or arrow's element: the preview names it, the bar's own are found by their frames
local function schoolOf(f, key)
	for el, s in pairs(TB.slots) do
		if s[key] == f then return el end
	end
	return nil
end

local ARROW_BRONZE = { 0.9, 0.72, 0.42 }
local function arrowBg(t)
	local bg = t.skinBg
	if not bg then
		bg = t:CreateTexture(nil, "BACKGROUND", nil, 1)
		t.skinBg = bg
	end
	bg:ClearAllPoints()
	bg:SetAllPoints()
	bg:Show()
	return bg
end

function TH.styleArrow(t, el)
	local kind = TH.current().arrow
	if t.skinned then
		TB.plainArrow(t)
		t.glyph:Show()
		if t.skinBg then t.skinBg:Hide() end
		t.skinned = nil
	end
	if not kind then return end
	t.skinned = true
	el = el or schoolOf(t, "arrowVis")
	if kind == "element" then
		local col = THEME.color[el or THEME.fallback]
		t:SetBackdropColor(col[1] * 0.2, col[2] * 0.2, col[3] * 0.2, 0.92)
		t:SetBackdropBorderColor(col[1], col[2], col[3], 0.9)
		t.glyph:SetVertexColor(col[1], col[2], col[3], 1)
		return
	end
	t:SetBackdropColor(0, 0, 0, 0)
	t:SetBackdropBorderColor(0, 0, 0, 0)
	local bg = arrowBg(t)
	if kind == "blizzard" then
		-- Blizzard's tab carries its own arrow
		local pop = TB.eff().pop
		blizzPiece(bg, (pop == "down" and BZ.down or BZ.up)[el or "spell"])
		local size = TB.look()
		if not el then size = math.floor(size * TB.eff().extrasScale + 0.5) end
		local h = TB.eff().arrowSize
		local w = math.min(size - 2, h * 28 / 18)
		bg:ClearAllPoints()
		bg:SetSize(w, h)
		bg:SetPoint(pop == "down" and "TOP" or "BOTTOM")
		t.glyph:Hide()
		return
	end
	local pl, art = plinthNow()
	local cols = art.arrowCols or { pl.slotX[4] + PL_SLOT, pl.rect[3] }
	turnedPiece(bg, cols[1], cols[2])
	-- The glyph is Blizzard's added highlight art (a black ground): tinted, still added
	t.glyph:SetVertexColor(ARROW_BRONZE[1], ARROW_BRONZE[2], ARROW_BRONZE[3], 1)
end

local function place(t, pop, y, h, dx)
	t:ClearAllPoints()
	t:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", dx or 0, y)
	t:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", dx or 0, y)
	t:SetHeight(h)
	t:Show()
end

local function plinthPicker(pop, p, n, psz)
	local pl, art = plinthNow()
	local first, last, gap = TH.popMetrics(psz)
	local f = p.stone
	if not f then
		f = { head = pop:CreateTexture(nil, "BACKGROUND", nil, 1),
			foot = pop:CreateTexture(nil, "BACKGROUND", nil, 1), tiles = {}, divs = {} }
		p.stone = f
	end
	local x1, x2, x4 = pl.slotX[1], pl.slotX[2], pl.slotX[4]
	local w = pl.rect[3]
	local cut = art.capCut
	-- The openings sit off the plinth's middle
	local dx = (pl.slotY + PL_SLOT / 2 - pl.rect[4] / 2) * psz / PL_SLOT
	turnedPiece(f.foot, cut and w - cut or x4 + PL_SLOT, w)
	place(f.foot, pop, 0, first, dx)
	local y = first
	for i = 1, n do
		local t = f.tiles[i] or pop:CreateTexture(nil, "BACKGROUND", nil, 1)
		f.tiles[i] = t
		turnedPiece(t, x1, x1 + PL_SLOT)
		place(t, pop, y, psz, dx)
		y = y + psz
		if i < n then
			local d = f.divs[i] or pop:CreateTexture(nil, "BACKGROUND", nil, 1)
			f.divs[i] = d
			turnedPiece(d, x1 + PL_SLOT, x2)
			place(d, pop, y, gap, dx)
			y = y + gap
		end
	end
	for i = n + 1, #f.tiles do f.tiles[i]:Hide() end
	for i = math.max(n, 1), #f.divs do f.divs[i]:Hide() end
	turnedPiece(f.head, 0, cut or x1)
	place(f.head, pop, y, last, dx)
end

local function blizzardPicker(pop, p, n, psz, el)
	local f = p.blizz
	if not f then
		f = { mid = pop:CreateTexture(nil, "BACKGROUND", nil, 1), head = pop:CreateTexture(nil, "BACKGROUND", nil, 2),
			foot = pop:CreateTexture(nil, "BACKGROUND", nil, 2) }
		p.blizz = f
	end
	local key = el or "spell"
	local len = TB.popLength(n, psz)
	local edge = psz * BZ_EDGE
	local top = BZ.top[key]
	local rim = { top[1], top[2], top[3], top[3] + 6 }
	local down = TB.eff().pop == "down"
	blizzPiece(f.mid, BZ.mid[key])
	place(f.mid, pop, edge, len - 2 * edge)
	blizzPiece(f.head, rim, down)
	place(f.head, pop, down and 0 or len - edge, edge)
	blizzPiece(f.foot, rim, not down)
	place(f.foot, pop, down and len - edge or 0, edge)
end

function TH.stylePopout(pop, n, psz, el)
	local kind = TH.current().picker
	local p = pop.skin
	if p then
		for _, t in ipairs(p.lines) do t:Hide() end
		if p.stone then
			p.stone.head:Hide()
			p.stone.foot:Hide()
			for _, t in ipairs(p.stone.tiles) do t:Hide() end
			for _, t in ipairs(p.stone.divs) do t:Hide() end
		end
		if p.blizz then
			for _, t in pairs(p.blizz) do t:Hide() end
		end
	end
	if not kind then
		local fill = TB.POP_FILL
		if p then pop.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
		return
	end
	p = p or { lines = {} }
	pop.skin = p
	el = el or schoolOf(pop, "popout")
	if kind == "plinth" then
		pop.bg:SetColorTexture(0, 0, 0, 0)
		plinthPicker(pop, p, n, psz)
	elseif kind == "blizzard" then
		pop.bg:SetColorTexture(0, 0, 0, 0)
		blizzardPicker(pop, p, n, psz, el)
	elseif kind == "element" then
		local col = THEME.color[el or THEME.fallback]
		pop.bg:SetColorTexture(col[1] * 0.16, col[2] * 0.16, col[3] * 0.16, 0.92)
		insetRings(pop, p.lines, { { 1, BLACK }, { 1, { col[1], col[2], col[3], 0.75 } } })
	else
		pop.bg:SetColorTexture(TRAY[1], TRAY[2], TRAY[3], 0.9)
		insetRings(pop, p.lines, { { 1, BLACK }, { 1, GOLD } })
	end
end
