-- Art frames: looks drawn round one element's icon (kind "frame") or round a whole group or bar
-- (kind "groupframe"). Looks are data (_FrameLooks); this file checks them, lays them out and draws
-- them on frames the caller owns. It reads no game state.

local ADDON, ns = ...

local FR = {}
ns.Frames = FR

local S = ns.Style
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Frames\\"
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- Frame levels, from the carrier's (element) or the group frame's own; members sit at member
FR.LEVEL = { under = -2, over = 1, top = 13, group = 0, groupTop = 16, member = 3 }

local SECTIONS = { { "blizzard", "Blizzard's" }, { "painted", "Painted" }, { "minimal", "Minimal" } }
S.addField("frame", "look", { name = "Frame look", where = "Global settings > Frame style",
	preview = { play = "still" }, groups = SECTIONS })
S.addField("groupframe", "look", { name = "Group frame look", where = "Global settings > Group frame style",
	preview = { play = "still" }, groups = SECTIONS })

------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------
local ROTATE = { [0] = true, [90] = true, [180] = true, [270] = true }
local BLEND = { BLEND = true, ADD = true }
local WEIGHT = { solid = true, wispy = true }
local LAYER = { over = true, under = true }
local EDGES = { tile = true, stretch = true }
local PIECES = { "tl", "tr", "bl", "br", "t", "b", "l", "r", "center" }

local function num(v) return type(v) == "number" and v == v and abs(v) < math.huge end
local function positive(v) return num(v) and v > 0 end

local function artError(a, what)
	if type(a) ~= "table" then return what .. ": no art" end
	local n = (a.file ~= nil and 1 or 0) + (a.atlas ~= nil and 1 or 0) + (a.path ~= nil and 1 or 0)
	if n ~= 1 then return what .. ": needs one of file, atlas or path" end
	if a.file ~= nil and not (positive(a.file) and a.file == floor(a.file)) then return what .. ": file is not a file ID" end
	if a.atlas ~= nil and (type(a.atlas) ~= "string" or a.atlas == "") then return what .. ": bad atlas" end
	if a.path ~= nil and (type(a.path) ~= "string" or a.path == "" or a.path:find("%.%.")) then return what .. ": bad path" end
	local s = a.size
	if type(s) ~= "table" or not positive(s[1]) or not positive(s[2]) then return what .. ": size needs { w, h }" end
	local c = a.coords
	if c ~= nil then
		if type(c) ~= "table" then return what .. ": bad coords" end
		for i = 1, 4 do
			if not num(c[i]) or c[i] < 0 or c[i] > 1 then return what .. ": coords outside 0..1" end
		end
		if c[1] >= c[2] or c[3] >= c[4] then return what .. ": coords out of order" end
	end
	if a.rotate ~= nil and not ROTATE[a.rotate] then return what .. ": rotate is 0, 90, 180 or 270" end
	if a.blend ~= nil and not BLEND[a.blend] then return what .. ": blend is BLEND or ADD" end
end

local function holeError(hole, w, h, what)
	if type(hole) ~= "table" then return what .. ": no hole" end
	local x, y, hw, hh = hole[1], hole[2], hole[3], hole[4]
	if not (num(x) and num(y) and positive(hw) and positive(hh)) then return what .. ": hole needs { x, y, w, h }" end
	if x < 0 or y < 0 or x + hw > w or y + hh > h then return what .. ": hole outside the art" end
end

local function listError(v, what)
	if v == nil or type(v) == "string" then return end
	if type(v) ~= "table" then return what .. " is a name or a list of names" end
	for _, s in ipairs(v) do if type(s) ~= "string" then return what .. " is a list of names" end end
end

local function commonError(e)
	if type(e.name) ~= "string" or e.name == "" then return "no name" end
	if e.weight ~= nil and not WEIGHT[e.weight] then return "weight is solid or wispy" end
	if e.variants ~= nil and type(e.variants) ~= "table" then return "variants is a table" end
	if e.tiling ~= nil and type(e.tiling) ~= "table" then return "tiling is a table" end
	return listError(e.madeFor, "madeFor") or listError(e.classes, "classes")
end

local function elementError(e)
	local a = e.art
	local err = artError(a, "art")
	if err then return err end
	if a.rotate == 90 or a.rotate == 270 then return "art: an element frame turns only 0 or 180" end
	if e.layer ~= nil and not LAYER[e.layer] then return "layer is over or under" end
	return holeError(e.hole, a.size[1], a.size[2], "art")
end

local function groupError(e)
	local bodies = (e.slice and 1 or 0) + (e.pieces and 1 or 0) + (e.cells and 1 or 0)
	if bodies ~= 1 then return "needs one of slice, pieces or cells" end
	if e.slice or e.pieces then
		if not positive(e.scale) then return "scale needs a number above 0" end
		if not num(e.rim) or e.rim < 0 then return "rim needs a number" end
		if e.gap ~= nil and not num(e.gap) then return "gap is a number" end
	end
	if e.slice then
		local err = artError(e.slice, "slice")
		if err then return err end
		local m = e.slice.margin
		if not positive(m) or 2 * m >= min(e.slice.size[1], e.slice.size[2]) then return "slice: bad margin" end
	elseif e.pieces then
		if type(e.pieces) ~= "table" then return "pieces is a table" end
		local any
		for k, a in pairs(e.pieces) do
			if not tContains(PIECES, k) then return "pieces: unknown piece " .. tostring(k) end
			local err = artError(a, "pieces." .. k)
			if err then return err end
			any = true
		end
		if not any then return "pieces: none given" end
		if e.edges ~= nil and not EDGES[e.edges] then return "edges is tile or stretch" end
	else
		local c = e.cells
		if type(c) ~= "table" then return "cells is a table" end
		for _, k in ipairs({ "first", "unit", "last" }) do
			local err = artError(c[k], "cells." .. k)
			if err then return err end
			if c[k].rotate or c[k].flipX or c[k].flipY then return "cells." .. k .. ": cells don't turn" end
		end
		local err = holeError(c.hole, c.first.size[1], c.first.size[2], "cells.first")
		if err then return err end
		if c.hole[3] >= c.unit.size[1] then return "cells.unit: narrower than the hole" end
	end
	if e.between ~= nil then
		if type(e.between) ~= "table" then return "between is a table" end
		if e.between.along ~= nil and e.between.along ~= "gap" then return "between.along is gap" end
		return artError(e.between.art, "between.art")
	end
end

-- An error message for a look's data, or nil
function FR.validate(e, kind)
	if type(e) ~= "table" then return "not a table" end
	if e.none then return commonError(e) end
	return commonError(e) or (kind == "groupframe" and groupError or elementError)(e)
end

------------------------------------------------------------------------
-- Geometry: units from the box's top-left, y down, rounded to whole pixels
------------------------------------------------------------------------
local function round(v, px) return floor(v / px + 0.5) * px end
local function atLeast(v, px) return max(px, round(v, px)) end

local function drawnSize(a)
	local w, h = a.size[1], a.size[2]
	if a.rotate == 90 or a.rotate == 270 then return h, w end
	return w, h
end

-- The same art drawn a quarter turn further (a vertical group's cells and between pieces)
local function turned(a)
	local t = a.turnedCopy
	if not t then
		t = CopyTable(a)
		t.rotate = ((a.rotate or 0) + 90) % 360
		a.turnedCopy = t
	end
	return t
end

-- SetTexCoord's eight values for the drawn part (u0..u1, v0..v1) of piece a in a file region
function FR.texCoords(a, u0, u1, v0, v1, l, r, t, b)
	l, r, t, b = l or 0, r or 1, t or 0, b or 1
	local c = a.coords
	if c then
		local w, h = r - l, b - t
		l, r, t, b = l + c[1] * w, l + c[2] * w, t + c[3] * h, t + c[4] * h
	end
	local rot = a.rotate or 0
	local function at(u, v)
		if a.flipX then u = 1 - u end
		if a.flipY then v = 1 - v end
		local s, q = u, v
		if rot == 90 then s, q = v, 1 - u
		elseif rot == 180 then s, q = 1 - u, 1 - v
		elseif rot == 270 then s, q = 1 - v, u end
		return l + s * (r - l), t + q * (b - t)
	end
	local ulx, uly = at(u0, v0)
	local llx, lly = at(u0, v1)
	local urx, ury = at(u1, v0)
	local lrx, lry = at(u1, v1)
	return ulx, uly, llx, lly, urx, ury, lrx, lry
end

-- Where the hole sits in the drawn art (flips and a half turn move it)
local function holeOf(look)
	local a, h = look.art, look.hole
	local x, y = h[1], h[2]
	local W, H = a.size[1], a.size[2]
	local fx, fy = a.flipX, a.flipY
	if a.rotate == 180 then fx, fy = not fx, not fy end
	if fx then x = W - x - h[3] end
	if fy then y = H - y - h[4] end
	return x, y, h[3], h[4]
end

-- An element look round a box of size box: the art's size and its centre's offset from the box's
function FR.fit(look, box, px)
	local x, y, hw, hh = holeOf(look)
	local k = box / hw
	local W, H = look.art.size[1], look.art.size[2]
	local w, h = atLeast(W * k, px), atLeast(H * k, px)
	local left = round(box / 2 - (x + hw / 2) * k, px)
	local top = round(box / 2 - (y + hh / 2) * k, px)
	return { w = w, h = h, left = left, top = top, x = left + w / 2 - box / 2, y = box / 2 - top - h / 2 }
end

local function cellsOf(lay)
	if lay.cells then return lay.cells end
	local out = {}
	for i = 0, (lay.n or 1) - 1 do
		local at = i * (lay.size + (lay.gap or 0))
		out[i + 1] = lay.vertical and { x = 0, y = at } or { x = at, y = 0 }
	end
	return out
end

local function edgeParts(parts, a, x0, y0, len, thick, along, tile, k, px)
	if len <= 0 then return end
	local w, h = drawnSize(a)
	local unit = atLeast((along == "x" and w or h) * k, px)
	if not tile or unit >= len then
		parts[#parts + 1] = along == "x" and { art = a, x = x0, y = y0, w = len, h = thick }
			or { art = a, x = x0, y = y0, w = thick, h = len }
		return
	end
	local at, n = 0, 0
	while at < len - px / 2 and n < 64 do
		local l = min(unit, len - at)
		local f = l < unit and l / unit or nil
		parts[#parts + 1] = along == "x" and { art = a, x = x0 + at, y = y0, w = l, h = thick, u1 = f }
			or { art = a, x = x0, y = y0 + at, w = thick, h = l, v1 = f }
		at, n = at + l, n + 1
	end
end

local function frameParts(look, W, H, size, px, parts)
	local k = look.scale * size / 44
	local o = round(look.rim * k + (look.gap or 0) * size / 44, px)
	local X0, Y0, X1, Y1 = -o, -o, W + o, H + o
	local OW, OH = X1 - X0, Y1 - Y0
	if look.slice then
		parts[#parts + 1] = { art = look.slice, x = X0, y = Y0, w = OW, h = OH, slice = look.slice.margin, k = k }
		return k
	end
	local p = look.pieces
	local halfW, halfH = floor(OW / 2 / px) * px, floor(OH / 2 / px) * px
	local cw, ch = {}, {}
	for _, c in ipairs({ "tl", "tr", "bl", "br" }) do
		local a = p[c]
		cw[c], ch[c] = 0, 0
		if a then
			local dw, dh = drawnSize(a)
			local w, h = atLeast(dw * k, px), atLeast(dh * k, px)
			local fw, fh = min(w, halfW), min(h, halfH)
			cw[c], ch[c] = fw, fh
			local right, bottom = c == "tr" or c == "br", c == "bl" or c == "br"
			local fu, fv = fw / w, fh / h
			parts[#parts + 1] = { art = a, x = right and X1 - fw or X0, y = bottom and Y1 - fh or Y0, w = fw, h = fh,
				u0 = right and 1 - fu or 0, u1 = right and 1 or fu, v0 = bottom and 1 - fv or 0, v1 = bottom and 1 or fv }
		end
	end
	local tile = look.edges == "tile"
	local th = {}
	for _, e in ipairs({ "t", "b", "l", "r" }) do
		local a = p[e]
		if a then
			local dw, dh = drawnSize(a)
			th[e] = atLeast((e == "t" or e == "b") and dh * k or dw * k, px)
		else
			th[e] = 0
		end
	end
	if p.t then edgeParts(parts, p.t, X0 + cw.tl, Y0, OW - cw.tl - cw.tr, th.t, "x", tile, k, px) end
	if p.b then edgeParts(parts, p.b, X0 + cw.bl, Y1 - th.b, OW - cw.bl - cw.br, th.b, "x", tile, k, px) end
	if p.l then edgeParts(parts, p.l, X0, Y0 + ch.tl, OH - ch.tl - ch.bl, th.l, "y", tile, k, px) end
	if p.r then edgeParts(parts, p.r, X1 - th.r, Y0 + ch.tr, OH - ch.tr - ch.br, th.r, "y", tile, k, px) end
	if p.center and OW - th.l - th.r > 0 and OH - th.t - th.b > 0 then
		parts[#parts + 1] = { art = p.center, x = X0 + th.l, y = Y0 + th.t, w = OW - th.l - th.r, h = OH - th.t - th.b }
	end
	return k
end

local function cellParts(look, cells, size, px, vertical, parts)
	local c = look.cells
	local hole = c.hole
	local k = size / hole[3]
	local hxUnit = hole[1] + c.unit.size[1] - c.first.size[1]
	local function place(cell, a, hx, s0, s1)
		local len, thick = a.size[1], a.size[2]
		local from = round((hx - s0 * len) * k, px)
		local L = atLeast((s1 - s0) * len * k, px)
		local T = atLeast(thick * k, px)
		if vertical then
			local across = round((thick - hole[2] - hole[4]) * k, px)
			parts[#parts + 1] = { art = turned(a), x = cell.x - across, y = cell.y - from, w = T, h = L, v0 = s0, v1 = s1 }
		else
			parts[#parts + 1] = { art = a, x = cell.x - from, y = cell.y - round(hole[2] * k, px), w = L, h = T, u0 = s0, u1 = s1 }
		end
	end
	local n = #cells
	if n == 1 then
		local mid = (hole[1] + hole[3] / 2) / c.first.size[1]
		place(cells[1], c.first, hole[1], 0, mid)
		local s0 = (hxUnit + hole[3] / 2) / c.last.size[1]
		-- the last cell's right half, from the box's centre on
		local a = c.last
		local L = atLeast((1 - s0) * a.size[1] * k, px)
		local T = atLeast(a.size[2] * k, px)
		local seam = round(size / 2, px)
		if vertical then
			local across = round((a.size[2] - hole[2] - hole[4]) * k, px)
			parts[#parts + 1] = { art = turned(a), x = cells[1].x - across, y = cells[1].y + seam, w = T, h = L, v0 = s0, v1 = 1 }
		else
			parts[#parts + 1] = { art = a, x = cells[1].x + seam, y = cells[1].y - round(hole[2] * k, px), w = L, h = T, u0 = s0, u1 = 1 }
		end
		-- the first half ends at the same seam
		local first = parts[#parts - 1]
		if vertical then first.h = seam - (first.y - cells[1].y) else first.w = seam - (first.x - cells[1].x) end
		return k
	end
	for i, cell in ipairs(cells) do
		if i == 1 then place(cell, c.first, hole[1], 0, 1)
		elseif i == n then place(cell, c.last, hxUnit, 0, 1)
		else place(cell, c.unit, hxUnit, 0, 1) end
	end
	return k
end

local function betweenParts(look, cells, size, k, Y0, Y1, px, vertical, parts)
	local a = look.between.art
	local dw = drawnSize(a)
	local t = atLeast(dw * k, px)
	local art = vertical and turned(a) or a
	for i = 2, #cells do
		local p, q = cells[i - 1], cells[i]
		if vertical then
			local mid = (p.y + size + q.y) / 2
			parts[#parts + 1] = { art = art, x = Y0, y = round(mid - t / 2, px), w = Y1 - Y0, h = t, between = true }
		else
			local mid = (p.x + size + q.x) / 2
			parts[#parts + 1] = { art = art, x = round(mid - t / 2, px), y = Y0, w = t, h = Y1 - Y0, between = true }
		end
	end
end

-- A group look round members laid out by lay: { size, n, gap, vertical } or { size, cells = {{ x, y }, ...} }
-- (each member's box from the group box's top-left). Returns { w, h, parts, outer = { x0, y0, x1, y1 } }.
function FR.groupLayout(look, lay, px)
	local size = lay.size
	local cells = cellsOf(lay)
	local key = lay.vertical and "y" or "x"
	local sorted = {}
	for i, c in ipairs(cells) do sorted[i] = c end
	table.sort(sorted, function(a, b) return a[key] < b[key] end)
	local W, H = 0, 0
	for _, c in ipairs(sorted) do W, H = max(W, c.x + size), max(H, c.y + size) end
	local parts = {}
	local k
	if look.cells then
		k = cellParts(look, sorted, size, px, lay.vertical, parts)
	else
		k = frameParts(look, W, H, size, px, parts)
	end
	local x0, y0, x1, y1 = 0, 0, W, H
	for _, p in ipairs(parts) do
		x0, y0, x1, y1 = min(x0, p.x), min(y0, p.y), max(x1, p.x + p.w), max(y1, p.y + p.h)
	end
	if look.between and #sorted > 1 then
		if lay.vertical then
			betweenParts(look, sorted, size, k, x0, x1, px, true, parts)
		else
			betweenParts(look, sorted, size, k, y0, y1, px, false, parts)
		end
	end
	return { w = W, h = H, parts = parts, outer = { x0, y0, x1, y1 }, k = k }
end

-- How far a look reaches past the box on each side, in icon widths
local ZERO = { left = 0, right = 0, top = 0, bottom = 0 }
local function reachOf(look, kind)
	if look.none then return ZERO end
	if kind == "frame" then
		local x, y, hw, hh = holeOf(look)
		local W, H = look.art.size[1], look.art.size[2]
		local function side(v) return max(0, v / hw - 0.5) end
		return { left = side(x + hw / 2), right = side(W - x - hw / 2), top = side(y + hh / 2),
			bottom = side(H - y - hh / 2) }
	end
	if look.cells then
		local c = look.cells
		local h = c.hole
		local hxUnit = h[1] + c.unit.size[1] - c.first.size[1]
		return { left = h[1] / h[3], right = max(0, (c.last.size[1] - hxUnit - h[3]) / h[3]), top = h[2] / h[3],
			bottom = max(0, (c.first.size[2] - h[2] - h[4]) / h[3]) }
	end
	local o = max(0, (look.rim * look.scale + (look.gap or 0)) / 44)
	return { left = o, right = o, top = o, bottom = o }
end

-- The spacing a repeating look's art was drawn for, at icon size (nil: any spacing)
function FR.fitSpacing(look, size, px)
	px = px or 1
	if look.cells then
		local h = look.cells.hole
		return round((look.cells.unit.size[1] - h[3]) * size / h[3], px)
	end
	if look.between then
		return atLeast(drawnSize(look.between.art) * look.scale * size / 44, px)
	end
end

------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------
local function register(kind, key, entry)
	local err = FR.validate(entry, kind)
	if type(entry) ~= "table" then entry = {} end
	if err then
		entry.name = type(entry.name) == "string" and entry.name or key
		entry.hidden, entry.bad = true, err
		entry.reach = ZERO
		ns.noteError("frame look " .. key, err)
	else
		entry.reach = reachOf(entry, kind)
	end
	entry.uses = { color = entry.tint == true, alpha = not entry.none }
	S.addLook(kind, key, entry)
	return entry
end
function FR.addLook(key, entry) return register("frame", key, entry) end
function FR.addGroupLook(key, entry) return register("groupframe", key, entry) end

FR.addLook("none", { name = "None", none = true })
FR.addGroupLook("none", { name = "None", none = true })

function FR.look(kind, key) return S.look(kind, key) end

-- A backdrop edge file as pieces: square cells in a row (left, right, top, bottom, then the four
-- corners); top and bottom are stored upright. band = { from, to }: the edges' texels across a cell.
function FR.strip(art, band)
	local W, cell = art.size[1], art.size[2]
	local n = floor(W / cell + 0.5)
	local out = {}
	for i, name in ipairs({ "l", "r", "t", "b", "tl", "tr", "bl", "br" }) do
		local p = CopyTable(art)
		local l, r = (i - 1) / n, i / n
		local w = cell
		local edge = i <= 4
		if band and edge then
			l, r = ((i - 1) * cell + band[1]) / W, ((i - 1) * cell + band[2]) / W
			w = band[2] - band[1]
		end
		p.coords, p.size = { l, r, 0, 1 }, { w, cell }
		if name == "t" or name == "b" then p.rotate = 90 end
		out[name] = p
	end
	return out
end

-- One image cut as nine pieces round margin texels
function FR.cut(art, margin)
	local W, H = art.size[1], art.size[2]
	local mx, my = margin / W, margin / H
	local function piece(l, r, t, b)
		local p = CopyTable(art)
		p.coords = { l, r, t, b }
		p.size = { (r - l) * W, (b - t) * H }
		return p
	end
	return { tl = piece(0, mx, 0, my), t = piece(mx, 1 - mx, 0, my), tr = piece(1 - mx, 1, 0, my),
		l = piece(0, mx, my, 1 - my), r = piece(1 - mx, 1, my, 1 - my),
		bl = piece(0, mx, 1 - my, 1), b = piece(mx, 1 - mx, 1 - my, 1), br = piece(1 - mx, 1, 1 - my, 1) }
end

------------------------------------------------------------------------
-- Art on this client
------------------------------------------------------------------------
local function eachArt(look, fn)
	if look.art then fn(look.art) end
	if look.slice then fn(look.slice) end
	if look.pieces then for _, k in ipairs(PIECES) do if look.pieces[k] then fn(look.pieces[k]) end end end
	if look.cells then fn(look.cells.first); fn(look.cells.unit); fn(look.cells.last) end
	if look.between then fn(look.between.art) end
end

-- An atlas as its file and region, when the client says
local atlasFile = {}
local function atlasSource(name)
	local s = atlasFile[name]
	if s == nil then
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		local file = info and (info.file or info.filename)
		s = file and { file, info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0,
			info.bottomTexCoord or 1 } or false
		atlasFile[name] = s
	end
	return s
end

local tester
local function fileKnown(src)
	if not tester then
		tester = UIParent:CreateTexture(nil, "BACKGROUND")
		tester:Hide()
	end
	local ok, set = pcall(tester.SetTexture, tester, src)
	tester:SetTexture(nil)
	if ok and type(set) == "boolean" then return set end
	if C_UIFileAsset and C_UIFileAsset.IsKnownFile then
		local ok2, yes = pcall(C_UIFileAsset.IsKnownFile, src)
		if ok2 and type(yes) == "boolean" then return yes end
	end
	return ok
end

local function needsRegion(a) return a.coords or (a.rotate or 0) ~= 0 or a.flipX or a.flipY end

local function artKnown(a, cropped)
	if a.atlas then
		if not ns.Looks.hasAtlas(a.atlas) then return false end
		return not (cropped or needsRegion(a)) or atlasSource(a.atlas) ~= false
	end
	return fileKnown(a.file or MEDIA .. a.path)
end

local known, missing = {}, {}
-- Whether the client has all of a look's art (checked once per look)
function FR.hasArt(look)
	if not look or look.none then return true end
	local v = known[look]
	if v == nil then
		v = true
		local cropped = look.pieces ~= nil or look.cells ~= nil
		eachArt(look, function(a) if v and not artKnown(a, cropped) then v = false end end)
		known[look] = v
		if not v then
			table.insert(missing, look.key)
			ns.noteError("frame look " .. tostring(look.key), "art missing on this client")
		end
	end
	return v
end
-- Looks whose art this client lacks, as found so far
function FR.missingArt() return missing end

-- Registered well, for this class, its art on the client
function FR.usable(look)
	if not look or look.bad then return false end
	if look.none then return true end
	if look.classes and not tContains(look.classes, ns.CLASS.token) then return false end
	return FR.hasArt(look)
end

local function madeFor(look, key)
	local m = look.madeFor
	if m == nil then return nil end
	if type(m) == "string" then return m == key end
	return key ~= nil and tContains(m, key) or false
end

-- The looks a picker offers for owner key (nil: Global or a group): None, those made for it, the
-- rest; looks made for other owners only with showAll
function FR.available(kind, key, showAll)
	local lead, mine, rest, others = {}, {}, {}, {}
	for _, look in ipairs(S.choices(kind, "look")) do
		if look.none then table.insert(lead, look)
		elseif not look.hidden and FR.usable(look) then
			local m = madeFor(look, key)
			if m == true then table.insert(mine, look)
			elseif m == nil then table.insert(rest, look)
			elseif showAll then table.insert(others, look) end
		end
	end
	for _, l in ipairs({ mine, rest, others }) do for _, look in ipairs(l) do table.insert(lead, look) end end
	return lead
end

-- A look's reach past the box per side (icon widths); the owner's current look by default
function FR.reach(owner, kind)
	kind = kind or "frame"
	local look = S.look(kind, S.read(owner, kind).look)
	return look and FR.usable(look) and look.reach or ZERO
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
local function paint(tex, a, u0, u1, v0, v1)
	local plain = not needsRegion(a) and (u0 or 0) == 0 and (u1 or 1) == 1 and (v0 or 0) == 0 and (v1 or 1) == 1
	if a.atlas then
		local s = atlasSource(a.atlas)
		if plain or not s then
			tex:SetAtlas(a.atlas)
		else
			tex:SetTexture(s[1])
			tex:SetTexCoord(FR.texCoords(a, u0 or 0, u1 or 1, v0 or 0, v1 or 1, s[2], s[3], s[4], s[5]))
		end
	else
		tex:SetTexture(a.file or MEDIA .. a.path)
		tex:SetTexCoord(FR.texCoords(a, u0 or 0, u1 or 1, v0 or 0, v1 or 1))
	end
	tex:SetBlendMode(a.blend or "BLEND")
end

local function tint(tex, look, style)
	local c = look.tint and style and style.color
	if c then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) else tex:SetVertexColor(1, 1, 1, 1) end
end

local function levelOf(look, base)
	local d = look.onTop and FR.LEVEL.top or look.layer == "under" and FR.LEVEL.under or FR.LEVEL.over
	return max(0, base + d)
end

-- An element look round carrier, whose box is box units square; style: { color, alpha }; level: the
-- carrier's, when the caller knows it (a secret read leaves the holder's own). False (and nothing
-- shown) for None, a bad look or missing art.
function FR.draw(carrier, look, box, style, level)
	local m = carrier.frameMount
	if not (look and look.art and FR.usable(look) and type(box) == "number" and box > 0) then
		if m then m:Hide() end
		return false
	end
	if not m then
		m = CreateFrame("Frame", nil, carrier)
		m.tex = m:CreateTexture(nil, "ARTWORK")
		carrier.frameMount = m
	end
	local g = FR.fit(look, box, ns.pixel(carrier))
	m:ClearAllPoints()
	m:SetPoint("CENTER", carrier, "CENTER", 0, 0)
	m:SetSize(box, box)
	level = level or carrier:GetFrameLevel()
	if not ns.isSecret(level) then m:SetFrameLevel(levelOf(look, level)) end
	local t = m.tex
	paint(t, look.art)
	t:ClearAllPoints()
	t:SetPoint("CENTER", m, "CENTER", g.x, g.y)
	t:SetSize(g.w, g.h)
	tint(t, look, style)
	m:SetAlpha(style and style.alpha or 1)
	m:Show()
	return true
end

-- The owner's (element key, sandbox table, nil for Global) own or followed frame on carrier
function FR.mount(carrier, owner, box, level)
	local st = S.read(owner, "frame")
	return FR.draw(carrier, S.look("frame", st.look), box, st, level)
end

-- An element's frame on a frame of the element's own that draws its border
local mounted = setmetatable({}, { __mode = "k" })
local veiled = {}
function FR.mountOwn(carrier, key, box, level)
	mounted[carrier] = key
	local ok = FR.mount(carrier, key, box, level)
	if ok and veiled[key] then carrier.frameMount:SetAlpha(0) end
	return ok
end

-- Its border and frame together, on one of those frames (bare: the border only)
function FR.dress(edge, key, level, bare)
	ns.applyBorder(edge, ns.borderFor(key))
	return FR.mountOwn(edge, key, not bare and ns.boxOf(key) or nil, level)
end

-- Hides (or brings back) an element's frames on its own carriers, while a stand-in draws it.
-- Out of combat: some carriers sit under Blizzard's aura button.
function FR.veil(key, on)
	veiled[key] = on or nil
	local a = S.read(key, "frame").alpha
	for carrier, owner in pairs(mounted) do
		local m = carrier.frameMount
		if owner == key and m then pcall(m.SetAlpha, m, on and 0 or a) end
	end
end

local function slicePart(m, p, look, style)
	local f = m.slice
	if not f then
		f = CreateFrame("Frame", nil, m)
		f.tex = f:CreateTexture(nil, "ARTWORK")
		f.tex:SetAllPoints()
		m.slice = f
	end
	local k = p.k
	f:SetScale(k)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", m, "TOPLEFT", p.x / k, -p.y / k)
	f:SetSize(p.w / k, p.h / k)
	paint(f.tex, p.art)
	local mg = p.slice
	f.tex:SetTextureSliceMargins(mg, mg, mg, mg)
	if Enum.UITextureSliceMode then f.tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end
	tint(f.tex, look, style)
	f:Show()
end

-- A group look on host round the box lay describes (see FR.groupLayout; lay.x, lay.y: the box's
-- top-left from host's). False (and nothing shown) for None, a bad look or missing art.
function FR.drawGroup(host, look, lay, style)
	local m = host.groupFrameMount
	if not (look and not look.none and FR.usable(look) and lay and type(lay.size) == "number" and lay.size > 0
		and (lay.cells and #lay.cells > 0 or not lay.cells and (lay.n or 1) > 0)) then
		if m then m:Hide() end
		return false
	end
	if not m then
		m = CreateFrame("Frame", nil, host)
		m.texs = {}
		host.groupFrameMount = m
	end
	local geo = FR.groupLayout(look, lay, ns.pixel(host))
	m:ClearAllPoints()
	m:SetPoint("TOPLEFT", host, "TOPLEFT", lay.x or 0, -(lay.y or 0))
	m:SetSize(geo.w, geo.h)
	m:SetFrameLevel(max(0, host:GetFrameLevel() + (look.onTop and FR.LEVEL.groupTop or FR.LEVEL.group)))
	local n, sliced = 0, false
	for _, p in ipairs(geo.parts) do
		if p.slice then
			slicePart(m, p, look, style)
			sliced = true
		else
			n = n + 1
			local t = m.texs[n]
			if not t then
				t = m:CreateTexture(nil, "ARTWORK")
				m.texs[n] = t
			end
			paint(t, p.art, p.u0, p.u1, p.v0, p.v1)
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", m, "TOPLEFT", p.x, -p.y)
			t:SetSize(p.w, p.h)
			tint(t, look, style)
			t:Show()
		end
	end
	for i = n + 1, #m.texs do m.texs[i]:Hide() end
	if m.slice and not sliced then m.slice:Hide() end
	m:SetAlpha(style and style.alpha or 1)
	m:Show()
	return true
end

-- The owner's (group table, bar key, nil for Global) own or followed group frame on host
function FR.mountGroup(host, owner, lay)
	local st = S.read(owner, "groupframe")
	return FR.drawGroup(host, S.look("groupframe", st.look), lay, st)
end
