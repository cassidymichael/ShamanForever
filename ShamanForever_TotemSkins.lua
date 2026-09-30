-- Totem bar: its Look (the options' word for it), the ways the whole bar can be drawn. Default is
-- the bar as its own settings draw it; another look draws the slots, their time bars, the
-- out-of-range mark, the pickers and what sits behind the bar its own way. Each look is a data
-- entry (the list below); the totem bar, its range strip and the options' preview of the bar
-- call the functions below, which leave everything as it was for Default and take down what
-- another look drew when the player goes back to it.
--
-- A look can own some of the bar's settings (its `owns`): while it is picked the bar uses the
-- look's value and the options hide that setting ("Set by the look"), and the player's own value
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
local hasAtlas = ns.Looks.hasAtlas

-- The Cooldown Manager's time bar art, by its plain names, which draw Forever's bronze art (tested
-- 2026-09-28: the bar, its background and pip). A missing atlas draws the plain part instead.
local CDM_BAR, CDM_BAR_BG, CDM_PIP = "UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG",
	"UI-HUD-CoolDownManager-Bar-Pip"

-- Our art for Stone and bronze (AI-made plinth and medallion, a drawn gem), by path.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local PLINTH, GEM = MEDIA .. "Plinth", MEDIA .. "Gem"
-- Plinth.tga's pieces, { x, y, w, h } in texels of its 256 square: the left end, one opening (a
-- slot's tile, the plinth's full height), the rune divider between slots, the right end, and a
-- swatch of plain stone. boxTop: from the tile's top to where a slot's box starts (the opening,
-- a little taller than wide, centred on the box).
local PL = { capL = { 1, 0, 53, 204 }, tile = { 56, 0, 92, 204 }, divider = { 150, 0, 48, 204 },
	capR = { 200, 0, 53, 204 }, stone = { 2, 208, 96, 46 }, boxTop = 55.4, gemDrop = 47.6 }
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
--   border, extrasBorder  border styles for the slots and for Call and Recall
--   behind         what sits behind the slots: "tray", "plinth" (with a gem under each slot)
--   timeBar        the slots' time bars: "tip" (a bright line at the fill's end)
--   mark           the out-of-range mark: "edge" (the strip, solid red), "gem" (the gem under the
--                  slot turns red)
--   picker         the pickers' look ("tray", "stone")
--   arrow          the arrow tab's look ("bronze")
--   extrasGap      the gap between the slots and Call and Recall, as a share of the slots' size,
--                  when the look owns the spacing
--   badgeGap(size) how far past the slot the look hangs something on the badge's side ("not your
--                  pick" sits beyond it)
--   gapAdd(size)   what the look hangs in the gaps between slots, added to the Spacing
--   rangeText      the Out of range section's line while the look owns its rows
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
	border = borderStyle("schooledge"), extrasBorder = borderStyle("hairline"),
	behind = "tray", timeBar = "tip", mark = "edge",
	picker = "tray",
	rangeText = "Out of range, for totems that buff you: a red edge along the top of the slot.",
})

-- The Stone and bronze plinth's reach past a slot's box, above and below, for slots of this size.
local function plinthReach(size)
	local u = size / PL.tile[3]
	return PL.boxTop * u, (PL.tile[4] - PL.boxTop - PL.tile[3]) * u
end

-- The bar set in a carved granite plinth (fixed art: it sets the spacing, a row, pickers opening
-- up), a gem under each slot lit in its element's colour while the totem is down and red out of
-- range, Call and Recall in round bronze medallions.
add("stone", {
	name = "Stone and bronze", experimental = true,
	-- It keeps the time bar inside the slot: the plinth's gems sit under it.
	owns = { border = true, range = true, rangeHeight = true, spacing = PL.divider[3] / PL.tile[3], dir = "row",
		pop = "up", barStyle = true },
	extrasGap = 0.2,
	border = borderStyle("line", 1), extrasBorder = borderStyle("medallion"),
	behind = "plinth", mark = "gem", picker = "stone", arrow = "bronze",
	badgeGap = function(size) return select(2, plinthReach(size)) end,
	rangeText = "Out of range, for totems that buff you: the gem under the slot turns red.",
})

-- The look picked now (an unknown key, from a newer version's profile: Default).
local DEFAULT = SK.byKey.default
function SK.current()
	if not ns.getDB() then return DEFAULT end
	return SK.byKey[TB.cfg().skin] or DEFAULT
end

-- Whether any look is experimental (About's list).
function SK.anyExperimental()
	for _, e in ipairs(SK.LIST) do if e.experimental then return true end end
	return false
end

------------------------------------------------------------------------
-- Settings a look owns: owns = { border = true, spacing = share, dir = "row", pop = "up",
-- range = true (the range colours), rangeHeight = true, barStyle = true (the time bar's Style) }.
-- The options hide what it owns; the layout reads it through TB.eff().
------------------------------------------------------------------------
-- Whether the look picked now owns a setting (the options).
function SK.owns(field)
	local o = SK.current().owns
	return o ~= nil and o[field] ~= nil
end

local POPS = { row = { up = true, down = true }, column = { right = true, left = true } }
-- The value the look gives a bar setting (TB.eff), or nil: the player's own. A look that sets the
-- direction keeps the player's picker side when it fits that direction.
function SK.owned(field)
	local o = SK.current().owns
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

-- The slots' border style, and Call and Recall's (nil: the bar's own, General's or its own).
function SK.border() return SK.current().border end
function SK.extrasBorder() return SK.current().extrasBorder end

-- The gap between slots and between the slots and Call and Recall for slots of this size, when the
-- look sets them (nil: the player's Spacing).
function SK.spacing(size)
	local share = SK.current().owns
	share = share and share.spacing
	if not share then return nil end
	return size * share, size * (SK.current().extrasGap or share)
end

-- The time bar's Style (the totem bar's setting): "cdm", the Cooldown Manager's bar under the slot,
-- or "default", the timer's own bar; a look that owns it keeps the timer's.
function SK.barStyle()
	if SK.owns("barStyle") or not ns.getDB() then return "default" end
	return TB.cfg().barStyle
end

-- The Cooldown Manager's time bar under a slot: its height and its gap from the slot, and how far
-- it reaches past the slot's edge with its rim.
local function cdmBar(size)
	local h, gap = math.max(math.floor(size * 6 / 44 + 0.5), 3), math.max(math.floor(size * 3 / 44 + 0.5), 2)
	return h, gap, gap + h + math.max(math.floor(h / 3 + 0.5), 1)
end
-- How far the Cooldown Manager's time bar reaches past the slot: under a row's slots (over them
-- when pickers open down), where the badge goes; in a column, in the gap below each slot. 0 while
-- the time bars are off or in their default style.
local function cdmReach(size, row)
	if SK.barStyle() ~= "cdm" or not ns.Style.value("totembar", "uptime", "bar") then return 0 end
	if (TB.eff().dir == "row") ~= row then return 0 end
	return select(3, cdmBar(size))
end

-- How far past the slot's edge the look or the time bar hangs something on the side away from the
-- picker (the plinth's stone, a Cooldown Manager bar): the "not your pick" badge sits beyond it.
function SK.badgeGap(size)
	local f = SK.current().badgeGap
	return (f and f(size) or 0) + cdmReach(size, true)
end

-- What hangs in the gaps between slots (a column's Cooldown Manager bars), added to them.
function SK.gapAdd(size) return cdmReach(size, false) end

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

-- A texture showing one of Plinth.tga's pieces.
local function plinthPiece(t, r)
	t:SetTexture(PLINTH)
	t:SetTexCoord(r[1] / 256, (r[1] + r[3]) / 256, r[2] / 256, (r[2] + r[4]) / 256)
end
-- The Stone and bronze plinth: a tile round each slot's box, the rune divider between two slots,
-- an end before the first and after the last, all the plinth's height; and under each slot a gem
-- in its bronze setting. Laid round the boxes, which the look's own spacing puts exactly a
-- divider apart. A row only (the look sets it).
local plinths = setmetatable({}, { __mode = "k" })   -- host -> its plinth
local function plinth(host, boxes, size, on)
	local f = plinths[host]
	if not on then
		if f then f:Hide() end
		return
	end
	if not f then
		f = CreateFrame("Frame", nil, host)
		f:EnableMouse(false)
		f.capL, f.capR = f:CreateTexture(nil, "BACKGROUND"), f:CreateTexture(nil, "BACKGROUND")
		plinthPiece(f.capL, PL.capL)
		plinthPiece(f.capR, PL.capR)
		f.tiles, f.dividers, f.gems = {}, {}, {}
		plinths[host] = f
	end
	f:SetFrameLevel(host:GetFrameLevel())
	f:SetAllPoints(host)
	local px = ns.pixel(host)
	local u = size / PL.tile[3]
	local up, down = plinthReach(size)
	up, down = ns.roundPx(up, px), ns.roundPx(down, px)
	local function piece(list, i, r)
		local t = list[i]
		if not t then
			t = f:CreateTexture(nil, "BACKGROUND")
			plinthPiece(t, r)
			list[i] = t
		end
		t:ClearAllPoints()
		t:Show()
		return t
	end
	local g, drop = ns.roundPx(size * 0.42, px), ns.roundPx(PL.gemDrop * u, px)
	local used = {}
	for i, box in ipairs(boxes) do
		local t = piece(f.tiles, i, PL.tile)
		t:SetPoint("TOPLEFT", box, "TOPLEFT", 0, up)
		t:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, -down)
		if i < #boxes then
			local d = piece(f.dividers, i, PL.divider)
			d:SetPoint("TOPLEFT", box, "TOPRIGHT", 0, up)
			d:SetPoint("BOTTOMRIGHT", boxes[i + 1], "BOTTOMLEFT", 0, -down)
		end
		local gem = f.gems[box]
		if not gem then
			gem = { set = f:CreateTexture(nil, "ARTWORK", nil, 1), gem = f:CreateTexture(nil, "ARTWORK", nil, 2) }
			gem.set:SetTexture(GEM)
			gem.set:SetTexCoord(GEM_SET[1], GEM_SET[2], GEM_SET[3], GEM_SET[4])
			gem.gem:SetTexture(GEM)
			f.gems[box] = gem
		end
		for _, x in pairs(gem) do
			x:ClearAllPoints()
			x:SetPoint("CENTER", box, "BOTTOM", 0, -drop)
			x:SetSize(g, g)
			x:Show()
		end
		used[box] = true
	end
	for i = #boxes + 1, #f.tiles do f.tiles[i]:Hide() end
	for i = math.max(#boxes, 1), #f.dividers do f.dividers[i]:Hide() end
	for box, gem in pairs(f.gems) do
		if not used[box] then gem.set:Hide(); gem.gem:Hide() end
	end
	local capW = ns.roundPx(PL.capL[3] * u, px)
	f.capL:ClearAllPoints()
	f.capL:SetPoint("TOPRIGHT", boxes[1], "TOPLEFT", 0, up)
	f.capL:SetPoint("BOTTOMRIGHT", boxes[1], "BOTTOMLEFT", 0, -down)
	f.capL:SetWidth(capW)
	f.capR:ClearAllPoints()
	f.capR:SetPoint("TOPLEFT", boxes[#boxes], "TOPRIGHT", 0, up)
	f.capR:SetPoint("BOTTOMLEFT", boxes[#boxes], "BOTTOMRIGHT", 0, -down)
	f.capR:SetWidth(capW)
	f:Show()
end

function SK.layoutBar(host, boxes, size, row)
	local look = SK.current()
	tray(host, boxes, size, look.behind == "tray" and #boxes > 0)
	plinth(host, boxes, size, look.behind == "plinth" and row and #boxes > 0)
end

-- A slot's own mark under it (lit while its totem is down), on host beside box: the plinth's gem,
-- in the element's colour or dark. Plain textures, so any time.
function SK.light(host, box, el, lit)
	local f = plinths[host]
	local gem = f and f.gems[box]
	if not gem then return end
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

-- The Cooldown Manager's style: its bar (its texture, its bronze-rimmed background and pip) across the
-- slot's picture, outside the slot on the badge's side: under a row whose pickers open up or a
-- column, over a row whose pickers open down.
local function cdmTimeBar(t, anchor, size, on)
	local bar = t.bar
	local x = bar.skinCDM
	if not on then
		if x then
			x.bg:Hide()
			x.pip:Hide()
			bar.bg:SetAlpha(1)
		end
		return
	end
	if not x then
		x = { bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1), pip = bar:CreateTexture(nil, "OVERLAY", nil, 6) }
		bar.skinCDM = x
	end
	local _, border = TB.look()
	local o = ns.Looks.inset(anchor, border, size)
	local h, gap = cdmBar(size)
	local e = TB.eff()
	bar:ClearAllPoints()
	if e.dir == "row" and e.pop == "down" then
		bar:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, o + gap)
		bar:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, o + gap)
	else
		bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -o - gap)
		bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -o - gap)
	end
	bar:SetHeight(h)
	if hasAtlas(CDM_BAR) then
		local r, g, b, a = bar:GetStatusBarColor()   -- the timer's colour, restated over the new texture
		bar:SetStatusBarTexture(CDM_BAR)
		bar:SetStatusBarColor(r, g, b, a)
	end
	local rim = math.max(math.floor(h / 3 + 0.5), 1)
	if hasAtlas(CDM_BAR_BG) then
		x.bg:SetAtlas(CDM_BAR_BG)
		x.bg:ClearAllPoints()
		x.bg:SetPoint("TOPLEFT", -rim, rim)
		x.bg:SetPoint("BOTTOMRIGHT", rim, -rim)
		x.bg:Show()
		bar.bg:SetAlpha(0)
	else
		x.bg:Hide()
		bar.bg:SetAlpha(1)
	end
	local info = hasAtlas(CDM_PIP) and C_Texture.GetAtlasInfo(CDM_PIP)
	if info and info.height and info.height > 0 then
		local ph = h * 2.2
		x.pip:SetAtlas(CDM_PIP)
		x.pip:SetSize(ph * info.width / info.height, ph)
		x.pip:ClearAllPoints()
		x.pip:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
		x.pip:Show()
	else x.pip:Hide() end
end

function SK.styleTimer(t, anchor, size)
	if not (t and t.bar) then return end
	local cdm = SK.barStyle() == "cdm"
	cdmTimeBar(t, anchor, size, cdm)
	tip(t, not cdm and SK.current().timeBar == "tip")
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
		plinthPiece(pop.bg, PL.stone)
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
	local kind = SK.current().mark
	if not kind then return nil end
	if kind == "gem" then
		-- The plinth's gem under the slot (SK.layoutBar).
		local px = ns.pixel(frame)
		local g = ns.roundPx(size * 0.42, px)
		local drop = ns.roundPx(PL.gemDrop * size / PL.tile[3], px)
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
	local kind = w and SK.current().mark
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
	local kind = SK.current().mark
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
