-- Totem bar: its Look (the options' word for it), the ways the whole bar can be drawn. Default is
-- the bar as its own settings draw it; another look draws the slots, their time bars, the
-- out-of-range mark, the pickers and what sits behind the bar its own way. Each look is a data
-- entry (the list below); the totem bar, its range strip and the options' preview of the bar call the
-- functions below, which leave everything as it was for Default and take down what another look
-- drew when the player goes back to it.
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

local _, ns = ...
local TB = ns.TotemBar

local SK = {}
TB.skin = SK

local S = ns.Style
local BLACK = { 0, 0, 0, 1 }
local GOLD = { 0.71, 0.55, 0.29, 1 }        -- the options window's gold, as ns.Looks' Gold hairline
local RED = { 0.9, 0.12, 0.08, 1 }          -- out of range
local TRAY = { 0.047, 0.035, 0.024 }         -- the Pixel look's dark fill

-- A border style (ns.Style's "border" kind, every field) drawn in one of ns.Looks' border looks.
local function borderStyle(look)
	local k = S.KINDS.border
	return S.clean({ show = true, look = look }, k.defaults, k.ranges)
end

------------------------------------------------------------------------
-- The looks, in the order the options offer them. An entry has name, experimental, owns (see
-- SK.owned), and the parts it draws its own way:
--   border, extrasBorder  border styles for the slots and for Call and Recall
--   behind         what sits behind the slots: "tray"
--   timeBar        the slots' time bars: "tip" (a bright line at the fill's end)
--   mark           the out-of-range mark: "edge" (a red top edge over the top third, darkened)
--   raiseWarning   the expiring warning draws over the mark, which covers part of the picture
--   picker, popHead      the pickers' look ("tray") and the length of its heading at the far end
--   badgeGap       how far past the slot the look hangs something ("not your pick" sits beyond)
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
-- a red top edge out of range.
add("pixel", {
	name = "Pixel", experimental = true,
	owns = { border = true, range = true },
	border = borderStyle("schooledge"), extrasBorder = borderStyle("hairline"),
	behind = "tray", timeBar = "tip", mark = "edge", raiseWarning = true,
	picker = "tray", popHead = function(psz) return math.floor(psz * 0.5 + 0.5) end,
	rangeText = "Out of range, for totems that buff you: a red edge along the top of the slot, its top third darkened.",
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
-- Settings a look owns: owns = { border = true, spacing = share, dir = "row", range = true,
-- timeBar = true }. The options hide what it owns; the layout reads it through TB.eff().
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

-- Extra length at a picker's far end (the look's heading there), for buttons psz wide: only on a
-- picker that opens up or down, as the heading is a line of text across it.
function SK.popHead(psz)
	local f = SK.current().popHead
	local dir = f and TB.eff().pop
	if dir ~= "up" and dir ~= "down" then return 0 end
	return f(psz)
end

-- How far past the slot's edge the look hangs something on the side away from the picker (a time
-- bar under the slot, the plinth's stone): the "not your pick" badge sits beyond it.
function SK.badgeGap(size)
	local f = SK.current().badgeGap
	return f and f(size) or 0
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

function SK.layoutBar(host, boxes, size, row)
	local look = SK.current()
	tray(host, boxes, size, look.behind == "tray" and #boxes > 0)
end

-- A slot's own mark under it (lit while its totem is down), on host beside box.
function SK.light(host, box, el, lit) end

-- The expiring warning (Timer:setExpire) above the range mark, for a look whose mark covers more
-- than a strip of the picture (in range, Blizzard's part covers that much with the buff's icon);
-- else where the timer puts it, just over the icon.
local function placeWarning(s)
	local x = s.timer.exp
	if not x then return end
	local raise = SK.current().raiseWarning
	if not raise and not x.skinRaised then return end
	local lv = raise and (s.button:GetFrameLevel() + TB.RANGE_LEVEL + 4) or (s.vis:GetFrameLevel() + 1)
	x:SetFrameLevel(lv)
	x.glow:SetFrameLevel(lv + 1)
	x.skinRaised = raise or nil
end

-- A slot's totem state changed (the bar's refresh and its preview mode; any time, combat included).
function SK.slotState(s, down)
	placeWarning(s)
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

function SK.styleTimer(t, anchor, size)
	if not (t and t.bar) then return end
	tip(t, SK.current().timeBar == "tip")
end

-- The arrow tab's look (TB.makeArrowLook).
function SK.styleArrow(look) end

-- A picker's look (pop: the popout, with its bg), for element el, buttons psz wide. Default: a
-- plain dark fill. "tray": the Pixel tray's fill and edge, the element's name at the far end.
local PLAIN_POP = { 0, 0, 0, 0.72 }
function SK.stylePopout(pop, el, psz)
	local kind = SK.current().picker
	local p = pop.skin
	if not kind then
		if p then
			for _, t in ipairs(p.lines) do t:Hide() end
			p.name:Hide()
			pop.bg:SetColorTexture(PLAIN_POP[1], PLAIN_POP[2], PLAIN_POP[3], PLAIN_POP[4])
		end
		return
	end
	if not p then
		p = { lines = {} }
		p.name = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		pop.skin = p
	end
	pop.bg:SetColorTexture(TRAY[1], TRAY[2], TRAY[3], 0.9)
	local d = insetRings(pop, p.lines, { { 1, BLACK }, { 1, GOLD } })
	-- The name, along a picker that opens up or down (one opening sideways has no room for it).
	local dir, head = TB.eff().pop, SK.popHead(psz)
	local name = p.name
	name:ClearAllPoints()
	if head > 0 and (dir == "up" or dir == "down") then
		ns.Media.setFont(name, "totembar", math.max(math.floor(psz * 0.26 + 0.5), 7))
		name:SetTextColor(0.85, 0.75, 0.54)
		name:SetText(string.upper(TB.NAME[el] or ""))
		local y = d + (head - d) / 2
		if dir == "up" then name:SetPoint("CENTER", pop, "TOP", 0, -y) else name:SetPoint("CENTER", pop, "BOTTOM", 0, y) end
		name:Show()
	else name:Hide() end
end

-- Out of range: where the look's mark sits (x, y from the slot's box's top left, w, h, in the
-- frame's units), or nil: the strip along the top. inset: how far the picture sits in from the box.
function SK.markRect(frame, size, inset)
	local kind = SK.current().mark
	if not kind then return nil end
	local w = size - 2 * inset
	-- "edge": the top third of the picture.
	return inset, -inset, w, ns.roundPx(w / 3, ns.pixel(frame))
end

-- The mark's parts on m, made the first time a look draws there; icon: the slot's picture, whose
-- mask (a rounded look's) they take.
local function markParts(m, icon)
	local p = m.skinParts
	if p then return p end
	p = { shade = m:CreateTexture(nil, "ARTWORK", nil, 1), edge = m:CreateTexture(nil, "ARTWORK", nil, 2) }
	p.shade:SetAllPoints()
	if icon then ns.Looks.followMask(icon, p.shade, p.edge) end
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
			p.shade:Hide(); p.edge:Hide()
			m.bg:Show()
		end
		return false
	end
	p = markParts(m, icon)
	m.bg:Hide()
	-- "edge": darker toward the top, and a red line along it.
	p.shade:SetBlendMode("BLEND")
	p.shade:SetColorTexture(1, 1, 1, 1)
	p.shade:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
	p.shade:Show()
	p.edge:ClearAllPoints()
	p.edge:SetPoint("TOPLEFT")
	p.edge:SetPoint("TOPRIGHT")
	p.edge:SetHeight(ns.linePx(m, 2))
	p.edge:SetColorTexture(RED[1], RED[2], RED[3], RED[4])
	p.edge:Show()
	return true
end

-- Blizzard's part over the mark (TotemRange's styleButton, out of combat): p { button, icon, over,
-- mask }; the icon is already cropped to the mark's share of the picture. Returns true when the
-- look styled it: in range it shows the buff's icon (the totem's) over the mark, uncoloured.
function SK.styleRangeButton(p, s)
	if not SK.current().mark then return false end
	p.over.bg:SetColorTexture(0, 0, 0, 0)
	return true
end

-- Whether Blizzard's part shows the buff's icon (a look can draw its own art there instead).
function SK.rangeIcon() return true end
