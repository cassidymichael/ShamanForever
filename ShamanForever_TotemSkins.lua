-- Totem bar: its theme (a "look" in the code, `skin` in its settings), the ways the whole bar can
-- be drawn. Default is the bar as its own settings draw it; another look draws the slots, their
-- time bars, the out-of-range mark, the pickers and what sits behind the bar its own way. Each
-- look is a data entry (the list below); the totem bar, its range strip and the options' preview
-- of the bar call the functions below, which leave everything as it was for Default and take down
-- what another look drew when the player goes back to it.
--
-- A look can own some of the bar's settings (its `owns`): while it is picked the bar uses the
-- look's value and the options hide that setting ("set by the theme"), and the player's own value
-- stays saved for Default or another look. The slots' border is a border style drawn through
-- ns.Looks like any other; the rest is the bar's own art.
--
-- The out-of-range mark keeps the strip's rule (ShamanForever_TotemRange.lua): no addon code knows
-- whether you are in range. Our mark sits under Blizzard's aura button, which covers it while you
-- have your totem's buff; a look changes only where the mark sits, what it draws, and what the
-- button draws over it. Nothing here reads a totem or an aura: it draws what the bar already knows.

local ADDON, ns = ...
local TB = ns.TotemBar

local SK = {}
TB.skin = SK

local S = ns.Style
local BLACK = { 0, 0, 0, 1 }
local GOLD = ns.Looks.GOLD                  -- the options window's gold, as ns.Looks' Gold hairline
local RED = { 0.9, 0.12, 0.08, 1 }          -- out of range
local TRAY = { 0.047, 0.035, 0.024 }         -- the Pixel look's dark fill


-- Our art for Stone and bronze (AI-made plinth and medallion), by path.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local PLINTH = MEDIA .. "Plinth"
-- Plinth.tga (512x256): three one-piece plinths for four slots, each drawn once (no tiling), for a
-- slot PL_SLOT texels wide: rect { x, y, w, h }, each opening's left edge and the openings' top
-- (from the rect's top left); and the plug that seals a socket. (The file also holds a strip of
-- plain stone that nothing draws now: the pickers are the plinths' own pieces.)
local PL_SLOT = 48
local PLINTHS = {
	slim = { rect = { 1, 174, 248, 60 }, slotX = { 13.6, 71.2, 128.8, 186.4 }, slotY = 7.2 },
	normal = { rect = { 1, 100, 284, 72 }, slotX = { 21.6, 86, 150.4, 214.8 }, slotY = 13.2 },
	grand = { rect = { 1, 1, 322, 97 }, slotX = { 27.6, 100.8, 173.6, 246.4 }, slotY = 25.2 },
}
local PLUG = { 391, 1, 48, 48 }
-- The options' order.
SK.PLINTHS = { { "slim", "Slim" }, { "normal", "Normal" }, { "grand", "Grand" } }
-- The plinth picked now; the gap between two slots and before the first, as shares of a slot.
local function plinthNow()
	return PLINTHS[ns.getDB() and TB.cfg().stonePlinth] or PLINTHS.normal
end
local function shares(pl)
	return (pl.slotX[2] - pl.slotX[1] - PL_SLOT) / PL_SLOT, pl.slotX[1] / PL_SLOT
end

-- A border style (ns.Style's "border" kind, every field) drawn in one of ns.Looks' border looks.
local function borderStyle(look, size)
	local k = S.KINDS.border
	return S.clean({ show = true, look = look, size = size }, k.defaults, k.ranges)
end

------------------------------------------------------------------------
-- The looks, in the order the options offer them. An entry has name, experimental, owns (see
-- SK.owned), and the parts it draws its own way:
--   border, extrasBorder  border styles for the slots (or a function returning one) and for Call
--                  and Recall
--   behind         what sits behind the slots: "tray", "plinth"
--   extrasScaleKey the bar setting that holds Call and Recall's size under this look (its own
--                  default); the options' size row edits it
--   fixedSlots     drawn round four slots: every element keeps its place, one not shown (not
--                  learned, or hidden) a sealed socket
--   timeBar        the slots' time bars: "tip" (a bright line at the fill's end)
--   mark           the out-of-range mark: "edge" (the strip, solid red)
--   picker         the pickers' look ("tray", "stone")
--   arrow          the arrow tab's look ("stone")
--   picker "stone" also draws the picker's measures (SK.popMetrics)
--   badgeGap(size) how far past the slot the look hangs something on the badge's side ("not your
--                  pick" sits beyond it)
--   rangeText      the Out of range section's line while the look owns its rows
--   mark and rangeText can be functions of the look's own settings
------------------------------------------------------------------------
SK.LIST, SK.byKey = {}, {}
local function add(key, entry)
	entry.key = key
	table.insert(SK.LIST, entry)
	SK.byKey[key] = entry
end

add("default", { name = "Default" })

-- Pixel lines in the options' gold: school-coloured edges on the slots, a dark tray behind them,
-- a red edge along the top out of range.
add("pixel", {
	name = "Pixel",
	owns = { border = true, range = true },
	border = function() return borderStyle("schooledge", TB.cfg().pixelEdge) end,
	extrasBorder = borderStyle("hairline"),
	behind = "tray", timeBar = "tip", mark = "edge",
	picker = "tray",
	rangeText = "Out of range, for totems that buff you: a red edge along the top of the slot.",
})

-- The Stone and bronze plinth's reach past a slot's box, above and below, for slots of this size.
local function plinthReach(size)
	local pl = plinthNow()
	local u = size / PL_SLOT
	return pl.slotY * u, (pl.rect[4] - pl.slotY - PL_SLOT) * u
end

-- The bar set in a carved granite plinth (fixed art: it sets the spacing, a row, pickers opening
-- up), Call and Recall in round bronze medallions. Out of range is Default's strip.
add("stone", {
	name = "Stone and bronze",
	-- It keeps the time bar in the icon. Its spacing is the plinth's, Call and Recall just past its
	-- ends.
	owns = function()
		local gap, cap = shares(plinthNow())
		-- Call and Recall one on each side, as on Blizzard's totem bar, at the theme's own size.
		return { border = true, spacing = gap, extrasGap = cap + 0.12, dir = "row", pop = "up",
			barPlace = true, extras = "ends", extrasScale = TB.cfg().stoneExtrasScale }
	end,
	border = borderStyle("line", 1), extrasBorder = borderStyle("medallion"),
	behind = "plinth", picker = "stone", arrow = "stone", fixedSlots = true,
	extrasScaleKey = "stoneExtrasScale",
	badgeGap = function(size) return select(2, plinthReach(size)) end,
})

-- The look picked now (an unknown key, from a newer version's profile: Default).
local DEFAULT = SK.byKey.default
function SK.current()
	if not ns.getDB() then return DEFAULT end
	return SK.byKey[TB.cfg().skin] or DEFAULT
end

-- The look's out-of-range mark now (nil: Default's strip), and its Out of range line.
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

-- The bar setting Call and Recall's size is kept in under the look picked now.
function SK.extrasScaleKey() return SK.current().extrasScaleKey or "extrasScale" end

-- A stone picker is a small plinth stood on end: the picked plinth's pieces turned a quarter, its
-- right end at the slot, an opening per button with a rune divider between, its left end at the
-- far end; the rails run up its sides. Its measures, for buttons psz wide as the openings: the
-- ends, the gap between buttons, the width across (TB.popLength); nil for a plain picker.
function SK.popMetrics(psz)
	if SK.current().picker ~= "stone" then return nil end
	local pl = plinthNow()
	local u = psz / PL_SLOT
	local r = pl.rect
	local gap = (pl.slotX[2] - pl.slotX[1] - PL_SLOT) * u
	return (r[3] - pl.slotX[4] - PL_SLOT) * u, pl.slotX[1] * u, gap, r[4] * u
end

-- Whether the look picked now is drawn round four fixed slots (the bar keeps a place for each).
function SK.fixedSlots() return SK.current().fixedSlots == true end

-- Whether any look is experimental (About's list).
function SK.anyExperimental()
	for _, e in ipairs(SK.LIST) do if e.experimental then return true end end
	return false
end

------------------------------------------------------------------------
-- Settings a look owns: owns = { border = true, spacing = share, extrasGap = share (the gap to
-- Call and Recall), dir = "row", pop = "up",
-- range = true (the range colours), rangeHeight = true, barPlace = true (the time bar's place),
-- extras = "ends" (Call and Recall's place), extrasScale = n (their size) }.
-- The options hide what it owns; the layout reads it through TB.eff().
------------------------------------------------------------------------
-- The settings the look picked now owns (a look's owns can be a function of its own settings).
local function ownsNow()
	local o = SK.current().owns
	if type(o) == "function" then return o() end
	return o
end

-- Whether the look picked now owns a setting (the options).
function SK.owns(field)
	local o = ownsNow()
	return o ~= nil and o[field] ~= nil
end

local POPS = { row = { up = true, down = true }, column = { right = true, left = true } }
-- The value the look gives a bar setting (TB.eff), or nil: the player's own. A look that sets the
-- direction keeps the player's picker side when it fits that direction.
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

-- The slots' border style, and Call and Recall's (nil: the bar's own, the global one or its own). A
-- look's border can be a function of its own settings.
local borders = {}   -- a look's border function's result, kept while it is the same
function SK.border()
	local b = SK.current().border
	if type(b) ~= "function" then return b end
	local made = b()
	local key = made.look .. made.size
	borders[key] = borders[key] or made
	return borders[key]
end
function SK.extrasBorder() return SK.current().extrasBorder end

-- The gap between slots and between the slots and Call and Recall for slots of this size, when the
-- look sets them (nil: the player's Spacing).
function SK.spacing(size)
	local o = ownsNow()
	local share = o and o.spacing
	if not share then return nil end
	return size * share, size * (o.extrasGap or share)
end

-- Where the time bar sits (the totem bar's setting): "in" the icon, where the timer draws it, or
-- "out", beside the icon on the side away from the pickers; a theme that owns it keeps it in.
function SK.barPlace()
	if SK.owns("barPlace") or not ns.getDB() then return "in" end
	return TB.cfg().barPlace
end

-- The bar beside the icon: its gap from the slot's box, and how far it reaches past the box with
-- its thickness (the Bar height); 0 while the bar is off or in the icon.
local function outGap(size) return math.max(math.floor(size * 3 / 44 + 0.5), 2) end
local function outReach(size)
	if SK.barPlace() ~= "out" or not ns.Style.value("totembar", "uptime", "bar") then return 0 end
	return outGap(size) + ns.Style.value("totembar", "uptime", "barHeight")
end

-- How far past the slot's edge the look or the time bar hangs something on the side away from the
-- picker (the plinth's stone, a time bar beside the icon): the "not your pick" badge, which sits on
-- that side too, goes beyond it.
function SK.badgeGap(size)
	local f = SK.current().badgeGap
	return (f and f(size) or 0) + outReach(size)
end

------------------------------------------------------------------------
-- Drawing. Each call draws the look picked now, or takes down what another look drew; a part a
-- look never drew costs nothing.
------------------------------------------------------------------------
-- Lines inside f's edge, outside in: rings { { px, colour }, ... } (screen pixels, ns.linePx).
-- list keeps f's textures for the next call. Returns how far in they reach.
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

-- Behind the bar: boxes are the slots' boxes (buttons on the bar), in bar order; host, the frame
-- to draw on (the bar, or the options' preview of it), at whose level it draws, under the slots.
-- The Pixel tray: a dark fill edged black, gold, black, a little past the first and last slots.
local trays = setmetatable({}, { __mode = "k" })   -- host -> its tray
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

-- A texture showing a piece of Plinth.tga ({ x, y, w, h } in texels).
local function plinthPiece(t, r)
	t:SetTexture(PLINTH)
	t:SetTexCoord(r[1] / 512, (r[1] + r[3]) / 512, r[2] / 256, (r[2] + r[4]) / 256)
end
-- The Stone and bronze plinth: the picked one, one piece round the four slots' boxes, stretched
-- from the first box to the last so its openings meet them whatever the rounding. A sealed box's
-- socket is plugged with stone. A row only (the look sets it).
local plinths = setmetatable({}, { __mode = "k" })   -- host -> its plinth
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

-- sealed: boxes (in boxes) whose slot doesn't show: a fixed-slot theme's sealed sockets.
function SK.layoutBar(host, boxes, size, row, sealed)
	local look = SK.current()
	tray(host, boxes, size, look.behind == "tray" and TB.cfg().pixelTray and #boxes > 0)
	plinth(host, boxes, size, look.behind == "plinth" and row and #boxes == 4, sealed)
end

-- After a slot timer's apply(): the look's time bar. anchor: the slot's picture.
-- "tip": a bright line where the fill ends, as the Cooldown Manager's bars have (on the fill's own
-- texture, so it moves with the time left without any work of ours).
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

-- The time bar beside the icon, on the side away from the pickers (the badge's side): under or
-- over a row's slots, running across the picture; left or right of a column's, running up it. Its
-- texture and colours stay the timer's (the Bars style), its thickness its Bar height; the timer's
-- dark background under it marks the empty part.
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
	local d = ns.Looks.inset(anchor, border, size) + outGap(size)
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

-- Plain stone for a frame f, from the plinth's tall strip without stretching it: as much of the
-- strip as fits f's shape. A size that reads as secret or empty (a frame anchored to a secure
-- button) takes a short piece.
-- A texture showing columns [c0, c1) of the picked plinth (texels from its left), turned a
-- quarter clockwise: the plinth's left becomes the top, its top rail the right side.
local function turnedPiece(t, c0, c1)
	local r = plinthNow().rect
	local x0, x1 = (r[1] + c0) / 512, (r[1] + c1) / 512
	local y0, y1 = r[2] / 256, (r[2] + r[4]) / 256
	t:SetTexture(PLINTH)
	t:SetTexCoord(x0, y1, x1, y1, x0, y0, x1, y0)
end

-- The arrow tab's look (TB.makeArrowLook; TB.placeArrow has placed it). "stone": the stone
-- picker's foot (the plinth's right end, turned), the arrow in bronze.
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
	-- The glyph is Blizzard's added highlight art (a black ground): tinted, still added.
	t.glyph:SetVertexColor(ARROW_BRONZE[1], ARROW_BRONZE[2], ARROW_BRONZE[3], 1)
end

-- The stone picker's pieces on pop for n buttons (the measures of SK.popMetrics): from the slot's
-- end, the foot, then an opening per button with a divider between, then the head.
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

-- A picker's look (pop: the popout, with its bg), for n buttons psz wide. Default: a plain dark
-- fill. "tray": the Pixel tray's fill and edge. "stone": a small plinth stood on end.
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

-- Out of range: where the look's mark sits (x, y from the slot's box's top left, w, h, in the
-- frame's units), or nil: the strip along the top. inset: how far the picture sits in from the box.
-- Blizzard's part covers the mark in range with the buff's icon, which can be another totem's (the
-- buff lingers after a swap within an element), so a mark over the picture is the strip, exactly as
-- Default sizes it: the buff's icon never shows more than a strip. No whole-picture mark (tested
-- 2026-09-30): in combat our own texture under Blizzard's part refuses SetTexture and SetAlpha
-- ("forbidden object"), so it can't show the slot's own totem instead of the buff's, and a MOD
-- tint under a parent at alpha 0 still tints.
function SK.markRect(frame, size, inset)
	local kind = SK.mark()
	if not kind then return nil end
	return inset, -inset, size - 2 * inset, ns.linePx(frame, TB.cfg().rangeHeight)
end

-- The mark's part on m, made the first time a look draws there; icon: the slot's picture, whose
-- mask (a rounded border look's) it takes.
local function markParts(m, icon)
	local p = m.skinParts
	if p then return p end
	p = { shade = m:CreateTexture(nil, "ARTWORK", nil, 1) }
	p.shade:SetAllPoints()
	if icon then ns.Looks.followMask(icon, p.shade) end
	m.skinParts = p
	return p
end

-- Draws the look's mark on m (a frame with .bg, w by h), or takes it down (w nil, or Default).
-- Returns true when the look drew it; false: the caller colours m.bg as the strip.
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
	-- "edge": the strip, solid red.
	p.shade:SetColorTexture(RED[1], RED[2], RED[3], RED[4])
	p.shade:Show()
	return true
end

-- Blizzard's part over the mark (TotemRange's styleButton, out of combat): p { button, icon, over };
-- the icon is already cropped to the mark's share of the picture. Returns true when the look styled
-- it: in range it shows the strip of the buff's icon, uncoloured.
function SK.styleRangeButton(p, s)
	if not SK.mark() then return false end
	p.over.bg:SetColorTexture(0, 0, 0, 0)
	return true
end
