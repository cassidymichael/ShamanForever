-- Totem bar: its Look (the options' word for it), the ways the whole bar can be drawn. Default is
-- the bar as its own settings draw it; another look draws the slots, their time bars, the
-- out-of-range mark, the pickers and what sits behind the bar its own way. Each look is a data
-- entry (SK.add); the totem bar, its range strip and the options' preview of the bar call the
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

------------------------------------------------------------------------
-- The looks, in the order the options offer them. An entry has name, experimental, and the parts
-- it draws its own way (each described where it is drawn, below).
------------------------------------------------------------------------
SK.LIST, SK.byKey = {}, {}
local function add(key, entry)
	entry.key = key
	table.insert(SK.LIST, entry)
	SK.byKey[key] = entry
end

add("default", { name = "Default" })

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

-- Extra length at a picker's far end (the look's heading there), for buttons psz wide.
function SK.popHead(psz)
	local f = SK.current().popHead
	return f and f(psz) or 0
end

-- How far past the slot's edge the look hangs something on the side away from the picker (a time
-- bar under the slot, the plinth's stone): the "not your pick" badge sits beyond it.
function SK.badgeGap(size)
	local f = SK.current().badgeGap
	return f and f(size) or 0
end

------------------------------------------------------------------------
-- Drawing. Each call draws the look picked now, or takes down what another look drew.
------------------------------------------------------------------------
-- Behind the bar: boxes are the slots' boxes (buttons on the bar), in bar order; host, the frame
-- to draw on (the bar, or the options' preview of it).
function SK.layoutBar(host, boxes, size, row) end

-- A slot's own mark under it (lit while its totem is down), on host beside box.
function SK.light(host, box, el, lit) end

-- A slot's totem state changed (the bar's refresh and its preview mode; any time, combat included).
function SK.slotState(s, down) end

-- After a slot timer's apply(): the look's time bar. anchor: the slot's picture.
function SK.styleTimer(t, anchor, size) end

-- The arrow tab's look (TB.makeArrowLook).
function SK.styleArrow(look) end

-- A picker's look (pop: the popout, with its bg), for element el, buttons psz wide.
function SK.stylePopout(pop, el, psz) end

-- Out of range: where the look's mark sits (x, y from the slot's box's top left, w, h, in the
-- frame's units), or nil: the strip along the top. inset: how far the picture sits in from the box.
function SK.markRect(frame, size, inset) return nil end

-- Draws the look's mark on m (a frame with .bg, w by h), or takes it down (w nil, or Default).
-- Returns true when the look drew it; false: the caller colours m.bg as the strip.
function SK.paintMark(m, w, h) return false end

-- Blizzard's part over the mark (TotemRange's styleButton, out of combat): p { button, icon, over,
-- mask }. Returns true when the look styled it.
function SK.styleRangeButton(p, s) return false end

-- Whether Blizzard's part shows the buff's icon (a look can draw its own art there instead).
function SK.rangeIcon() return true end
