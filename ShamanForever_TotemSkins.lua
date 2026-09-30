-- Totem bar: its theme (a "look" in the code, `skin` in its settings), the ways the whole bar can
-- be drawn. Default is the bar as its own settings draw it; another look draws the slots, their time bars, the
-- out-of-range mark, the pickers and what sits behind the bar its own way. Each look is a data
-- entry (the list below); the totem bar, its range strip and the options' preview of the bar
-- call the functions below, which leave everything as it was for Default and take down what
-- another look drew when the player goes back to it.
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


-- Our art for Stone and bronze (AI-made plinth and medallion, a drawn gem), by path.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local PLINTH, GEM = MEDIA .. "Plinth", MEDIA .. "Gem"
-- Plinth.tga (512x256): three one-piece plinths for four slots, each drawn once (no tiling), for a
-- slot PL_SLOT texels wide: rect { x, y, w, h }, each opening's left edge and the openings' top
-- (from the rect's top left), and the bottom rail's middle, where the gems sit. Then plain stone
-- for the pickers (a tall strip) and the plug that seals a socket.
local PL_SLOT = 48
local PLINTHS = {
	slim = { rect = { 1, 174, 248, 60 }, slotX = { 13.6, 71.2, 128.8, 186.4 }, slotY = 7.2, railMid = 58.2 },
	normal = { rect = { 1, 100, 284, 72 }, slotX = { 21.6, 86, 150.4, 214.8 }, slotY = 13.2, railMid = 69.6 },
	grand = { rect = { 1, 1, 322, 97 }, slotX = { 27.6, 100.8, 173.6, 246.4 }, slotY = 25.2, railMid = 92 },
}
local STONE, PLUG = { 325, 1, 64, 254 }, { 391, 1, 48, 48 }
SK.PLINTHS = { { "slim", "Slim" }, { "normal", "Normal" }, { "grand", "Grand" } }   -- the options' order
-- The plinth picked now; the gap between two slots and before the first, as shares of a slot.
local function plinthNow()
	return PLINTHS[ns.getDB() and TB.cfg().stonePlinth] or PLINTHS.normal
end
local function shares(pl)
	return (pl.slotX[2] - pl.slotX[1] - PL_SLOT) / PL_SLOT, pl.slotX[1] / PL_SLOT
end
-- Gem.tga's cells (texture coordinates): lit (a glow round it), unlit, and the bronze setting.
local GEM_LIT, GEM_UNLIT, GEM_SET = { 0, 0.5, 0, 0.5 }, { 0.5, 1, 0, 0.5 }, { 0, 0.5, 0.5, 1 }
local GEM_DARK = { 0.33, 0.31, 0.28 }
local BRONZE = { 0.64, 0.48, 0.24, 1 }
local BRONZE_DARK = { 0.10, 0.07, 0.03, 1 }

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
--   behind         what sits behind the slots: "tray", "plinth" (with a gem under each slot)
--   fixedSlots     drawn round four slots: every element keeps its place, one not shown (not
--                  learned, or hidden) a sealed socket
--   timeBar        the slots' time bars: "tip" (a bright line at the fill's end)
--   mark           the out-of-range mark: "edge" (the strip, solid red), "gem" (the gem under the
--                  slot turns red)
--   picker         the pickers' look ("tray", "stone")
--   arrow          the arrow tab's look ("bronze")
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
	name = "Pixel", experimental = true,
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
-- up), a gem on the bottom rail under each slot lit in its element's colour while the totem is
-- down and red out of range, Call and Recall in round bronze medallions.
add("stone", {
	name = "Stone and bronze", experimental = true,
	-- It keeps the time bar in the icon: the plinth's gems sit under the slot. Its spacing is the
	-- plinth's, Call and Recall just past its ends.
	owns = function()
		local gap, cap = shares(plinthNow())
		-- Without its gems, out of range is the red edge, at the player's Height.
		return { border = true, range = true, rangeHeight = TB.cfg().stoneGems or nil, spacing = gap,
			extrasGap = cap + 0.12, dir = "row", pop = "up", barPlace = true }
	end,
	border = borderStyle("line", 1), extrasBorder = borderStyle("medallion"),
	behind = "plinth", picker = "stone", arrow = "bronze", fixedSlots = true,
	mark = function() return TB.cfg().stoneGems and "gem" or "edge" end,
	badgeGap = function(size) return select(2, plinthReach(size)) end,
	rangeText = function()
		if TB.cfg().stoneGems then return "Out of range, for totems that buff you: the gem under the slot turns red." end
		return "Out of range, for totems that buff you: a red edge along the top of the slot."
	end,
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
-- range = true (the range colours), rangeHeight = true, barPlace = true (the time bar's place) }.
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
	if field == "dir" then return o.dir end
	if field == "pop" and o.pop then return o.pop end
	if field == "pop" and o.dir then
		local pop = TB.cfg().pop
		if POPS[o.dir][pop] then return nil end
		return o.dir == "row" and "up" or "right"
	end
	return nil
end

-- The slots' border style, and Call and Recall's (nil: the bar's own, General's or its own). A
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
-- The gem under a slot: its size, and how far its middle sits below the slot's box (on the
-- plinth's bottom rail).
local function gemPlace(size, px)
	local pl = plinthNow()
	local u = size / PL_SLOT
	return ns.roundPx(size * 0.6, px), ns.roundPx((pl.railMid - pl.slotY - PL_SLOT) * u, px)
end
-- The Stone and bronze plinth: the picked one, one piece round the four slots' boxes, stretched
-- from the first box to the last so its openings meet them whatever the rounding; and under each
-- slot a gem in its bronze setting on the bottom rail. A sealed box's socket is plugged with stone
-- and its gem stays dark. A row only (the look sets it).
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
		f.gems, f.plugs = {}, {}
		plinths[host] = f
	end
	f:SetFrameLevel(host:GetFrameLevel())
	f:SetAllPoints(host)
	local pl = plinthNow()
	local px = ns.pixel(host)
	local u = size / PL_SLOT
	local r = pl.rect
	plinthPiece(f.art, r)
	f.art:ClearAllPoints()
	f.art:SetPoint("TOPLEFT", boxes[1], "TOPLEFT", -pl.slotX[1] * u, pl.slotY * u)
	f.art:SetPoint("BOTTOMRIGHT", boxes[#boxes], "BOTTOMRIGHT", (r[3] - pl.slotX[4] - PL_SLOT) * u,
		-(r[4] - pl.slotY - PL_SLOT) * u)
	local g, drop = gemPlace(size, px)
	local gems = TB.cfg().stoneGems
	local used = {}
	f.sealed = sealed or {}
	for i, box in ipairs(boxes) do
		local plug = f.plugs[i]
		if f.sealed[box] then
			if not plug then
				plug = f:CreateTexture(nil, "ARTWORK")
				plinthPiece(plug, PLUG)
				f.plugs[i] = plug
			end
			plug:ClearAllPoints()
			plug:SetAllPoints(box)
			plug:Show()
		elseif plug then plug:Hide() end
		local gem = f.gems[box]
		if not gem then
			gem = { set = f:CreateTexture(nil, "ARTWORK", nil, 1),
				gem = f:CreateTexture(nil, "ARTWORK", nil, 2) }
			gem.set:SetTexture(GEM)
			gem.set:SetTexCoord(GEM_SET[1], GEM_SET[2], GEM_SET[3], GEM_SET[4])
			gem.gem:SetTexture(GEM)
			f.gems[box] = gem
		end
		for _, x in pairs(gem) do
			x:ClearAllPoints()
			x:SetPoint("CENTER", box, "BOTTOM", 0, -drop)
			x:SetSize(g, g)
			x:SetShown(gems)
		end
		used[box] = true
	end
	for box, gem in pairs(f.gems) do
		if not used[box] then gem.set:Hide(); gem.gem:Hide() end
	end
	for box in pairs(f.sealed) do SK.light(host, box, nil, false, true) end
	f:Show()
end

-- sealed: boxes (in boxes) whose slot doesn't show: a fixed-slot theme's sealed sockets.
function SK.layoutBar(host, boxes, size, row, sealed)
	local look = SK.current()
	tray(host, boxes, size, look.behind == "tray" and TB.cfg().pixelTray and #boxes > 0)
	plinth(host, boxes, size, look.behind == "plinth" and row and #boxes == 4, sealed)
end

-- A slot's own mark under it (lit while its totem is down), on host beside box: the plinth's gem,
-- in the element's colour or dark; always dark on a sealed socket (force: the plinth's own call).
-- Plain textures, so any time.
function SK.light(host, box, el, lit, force)
	local f = plinths[host]
	local gem = f and f.gems[box]
	if not gem or (f.sealed[box] and not force) then return end
	if f.sealed[box] then lit = false end
	local t, c = gem.gem, lit and ns.SCHOOL_COLOR[el] or GEM_DARK
	local cell = lit and GEM_LIT or GEM_UNLIT
	t:SetTexCoord(cell[1], cell[2], cell[3], cell[4])
	t:SetVertexColor(c[1], c[2], c[3], 1)
end

-- A slot's totem state changed (the bar's refresh and its preview mode; any time, combat included).
function SK.slotState(s, down)
	SK.light(TB.frame, s.button, s.el, down)
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

-- The arrow tab's look (TB.makeArrowLook; TB.placeArrow has placed it). "bronze": the plain tab
-- edged in the plinth's bronze.
function SK.styleArrow(t)
	local kind = SK.current().arrow
	if t.skinned then
		TB.plainArrow(t)
		t.skinned = nil
	end
	if not kind then return end
	t.skinned = true
	t:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], BRONZE[4])
end

-- A picker's look (pop: the popout, with its bg). Default: a plain dark fill. "tray": the Pixel
-- tray's fill and edge. "stone": plain stone from the plinth.
function SK.stylePopout(pop)
	local kind = SK.current().picker
	local p = pop.skin
	if p then
		for _, t in ipairs(p.lines) do t:Hide() end
		pop.bg:SetVertexColor(1, 1, 1, 1)
		pop.bg:SetTexCoord(0, 1, 0, 1)
	end
	if kind == "stone" then
		-- Plain stone from the plinth, darkened, edged dark then bronze.
		p = p or { lines = {} }
		pop.skin = p
		plinthPiece(pop.bg, STONE)
		pop.bg:SetVertexColor(0.8, 0.8, 0.8, 1)
		insetRings(pop, p.lines, { { 1, BRONZE_DARK }, { 2, BRONZE } })
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
	if kind == "gem" then
		-- The plinth's gem under the slot (SK.layoutBar).
		local g, drop = gemPlace(size, ns.pixel(frame))
		return (size - g) / 2, -(size + drop - g / 2), g, g
	end
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
	p.shade:SetVertexColor(1, 1, 1, 1)
	p.shade:SetTexCoord(0, 1, 0, 1)
	if kind == "gem" then
		-- The gem, lit red.
		p.shade:SetTexture(GEM)
		p.shade:SetTexCoord(GEM_LIT[1], GEM_LIT[2], GEM_LIT[3], GEM_LIT[4])
		p.shade:SetVertexColor(RED[1], RED[2], RED[3], 1)
	else
		-- "edge": the strip, solid red.
		p.shade:SetColorTexture(RED[1], RED[2], RED[3], RED[4])
	end
	p.shade:Show()
	return true
end

-- Blizzard's part over the mark (TotemRange's styleButton, out of combat): p { button, icon, over };
-- the icon is already cropped to the mark's share of the picture. Returns true when the look styled
-- it: in range it shows the strip of the buff's icon, uncoloured, or the gem lit in the element's
-- colour.
function SK.styleRangeButton(p, s)
	local kind = SK.mark()
	if p.gem then p.gem:Hide() end
	-- The buff's icon: hidden by its colour's alpha where the look draws its own art (preview mode
	-- hides it by its alpha).
	if p.iconHidden then
		p.icon:SetVertexColor(1, 1, 1, 1)
		p.iconHidden = nil
	end
	if not kind then return false end
	p.over.bg:SetColorTexture(0, 0, 0, 0)
	if kind == "gem" then
		-- In range, the gem lit in the element's colour over the red one. The holder hides the whole
		-- part while no buff totem of yours is down in the slot (TotemRange's showStrip); in combat
		-- that is its alpha on a frame holding Blizzard's button, not yet tested. If a lingering buff
		-- turns out to keep this lit over an emptied slot in combat, the lit gem goes out-of-combat
		-- only.
		p.icon:SetVertexColor(1, 1, 1, 0)
		p.iconHidden = true
		local c = ns.SCHOOL_COLOR[s.el]
		p.gem = p.gem or p.over:CreateTexture(nil, "ARTWORK", nil, 1)
		p.gem:SetTexture(GEM)
		p.gem:SetTexCoord(GEM_LIT[1], GEM_LIT[2], GEM_LIT[3], GEM_LIT[4])
		p.gem:SetVertexColor(c[1], c[2], c[3], 1)
		p.gem:SetAllPoints(p.button)
		p.gem:Show()
	end
	return true
end
