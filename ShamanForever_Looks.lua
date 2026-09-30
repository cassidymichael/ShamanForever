-- Looks: the ways the HUD's parts can be drawn, each a data entry in ns.Style (S.addLook) that a
-- style's `look` field picks, and the shared pieces that draw them:
--   frame      the edge around an icon, in its border's look (rings of lines, corner caps, art
--              over or around the icon, a mask on the icon's picture)
--   glow       the pulsing glow's looks (ns.Effects.glow calls in)
--   pop        the pop's choices (colour, flash, burst, motion), its edge flash and its drawn
--              bursts as data (ns.Effects' pop rig reads them by part)
-- Our own media are named by path, never by file ID: the client gives our loose files IDs that
-- change between client starts (tested 2026-09-28). Blizzard's art is named by atlas and checked
-- before use (C_Texture.GetAtlasInfo): a missing atlas draws nothing, so each look has a fallback.

local ADDON, ns = ...

local Looks = {}
ns.Looks = Looks

local S = ns.Style
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CLAMP = "CLAMPTOBLACKADDITIVE"   -- a mask's wrap mode, as Blizzard's own masks use
local STRETCHED = Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0

-- Whether the client has an atlas by this name.
local atlasKnown = {}
function Looks.hasAtlas(name)
	if atlasKnown[name] == nil then
		atlasKnown[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) ~= nil
	end
	return atlasKnown[name]
end

-- The school a frame's looks take (a glow's material, a pop's colour and shapes): the frame's own
-- (a totem bar slot's), else its element's (element icons and their previews carry the element's
-- key as owner). A frame laid over an icon (an end flash's pop) names that icon as f.over.
local function schoolOf(f)
	if f.over then f = f.over end
	if f.school then return f.school end
	local e = type(f.owner) == "string" and ns.ELEMENTS[f.owner]
	return e and e.school or "spirit"
end

-- The school an element's pop and School material glow take: the one picked for them (its
-- popSchool setting) unless own, else its own now (ownSchool(), for an element whose school follows
-- its state), else the element's.
function Looks.elementSchool(key, own)
	local e = ns.ELEMENTS[key]
	if not e then return "spirit" end
	if not own and ns.getDB and ns.getDB() then
		local pick = ns.elementSetting(key, "popSchool")
		if ns.SCHOOL_COLOR[pick] then return pick end
	end
	return e.ownSchool and e.ownSchool() or e.school or "spirit"
end
-- As schoolOf, with an element's pick for its pop and School material glow.
local function effectSchool(f)
	if f.over then f = f.over end
	if f.school then return f.school end
	return type(f.owner) == "string" and Looks.elementSchool(f.owner) or "spirit"
end

------------------------------------------------------------------------
-- Frames: a border look's entry (a choice, S.addLook: name, group, uses and the rest) has any of
-- these parts.
--   rings  lines round the icon's edge, listed outside in. Each is { px, color }, or has a colour
--          per side (top, bottom, left, right) in place of color. px: screen pixels (default 1) or
--          the name of a border setting that holds them ("size", the Border size). A colour is
--          { r, g, b, a }, the name of a border setting that holds one ("color"), or "school": the
--          school colour of the icon it is drawn round (a totem bar slot's element).
--   caps   { px, len, color }: an L on each corner, px thick (px and color as for rings), its outer
--          edge on the rings' or further out when it is thicker than they are, its arms running len
--          along the icon's edges past the corner (screen pixels).
--   art    Blizzard's or our art: { atlas or file, inset } drawn stretched over the icon, inset
--          { left, right, top, bottom } past each edge as a share of the icon's width; or { file,
--          margin, px } drawn as a 9-slice round the icon, whose margin (texels) lands on px whole
--          screen pixels.
--   mask   { atlas or file, scale } for the icon's picture and what covers it (its size over the
--          picture's, centred; default 1).
--   swipe  a file for the icon's cooldown swipes (f.cd, and those Looks.followSwipe registers),
--          shaped like the mask; swipeInset: or the swipes inset this share of the icon's width
--          each side, inside the mask's shape, as Blizzard insets its action buttons' cooldowns.
--   hidden   not offered in the options' Border look lists: drawn only for a totem bar Look
--            (ShamanForever_TotemSkins.lua).
-- uses names the border settings its rings and caps read ("size", "color", "capSize", "capColor").
-- A look whose Blizzard art is missing from the client draws a plain 1 px black line instead.
-- A look drawn with AI-made art is credited in the README and About's Art text.
-- Lines and caps are screen pixels (ns.linePx): crisp, grown by Scale, not by icon Size. They sit
-- round the icon's picture, so they never cover the rings inside it or Blizzard's aura button, and
-- inside the element's box: an icon's Size is its outer edge, and whoever lays it out sets the
-- picture in by Looks.inset (Looks.fit), so Spacing is the gap between what shows.
------------------------------------------------------------------------
local SIDES = { "top", "bottom", "left", "right" }
local CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
local BLACK = { 0, 0, 0, 1 }

-- A part's colour or thickness (screen pixels): its own, or the border setting it names, or the
-- school colour of f, the icon it is drawn round.
local schoolColors = {}   -- school -> { r, g, b, 1 }
local function colorOf(c, b, f)
	if c == "school" then
		local school = f and schoolOf(f) or "spirit"
		local k = schoolColors[school]
		if not k then
			local sc = ns.SCHOOL_COLOR[school] or ns.SCHOOL_COLOR.spirit
			k = { sc[1], sc[2], sc[3], 1 }
			schoolColors[school] = k
		end
		return k
	end
	if type(c) == "string" then return b[c] or BLACK end
	return c
end
local function pxOf(px, b)
	if type(px) == "string" then return b[px] or 1 end
	return px or 1
end

-- Whether a look (a choice's entry) uses a style setting: the options show only those it uses.
function Looks.uses(look, field) return look.uses ~= nil and look.uses[field] == true end

-- Each ring is four textures: top and bottom span the corners, left and right fill between them.
-- Drawn inside out; returns how far the rings reach outside the icon's edge.
local function drawRings(f, rings, b)
	f.border = f.border or {}
	local tex, n, d = f.border, 0, 0   -- d: how far out this ring starts
	for i = #(rings or {}), 1, -1 do
		local ring = rings[i]
		local w = ns.linePx(f, pxOf(ring.px, b))
		local o = d + w
		for _, side in ipairs(SIDES) do
			n = n + 1
			local t = tex[n] or f:CreateTexture(nil, "BACKGROUND", nil, -8)
			tex[n] = t
			local c = colorOf(ring[side] or ring.color, b, f)
			t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
			t:ClearAllPoints()
			t:Show()
			if side == "top" then
				t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -o, d)
				t:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", o, d)
				t:SetHeight(w)
			elseif side == "bottom" then
				t:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -o, -d)
				t:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", o, -d)
				t:SetHeight(w)
			elseif side == "left" then
				t:SetPoint("TOPRIGHT", f, "TOPLEFT", -d, d)
				t:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -d, -d)
				t:SetWidth(w)
			else
				t:SetPoint("TOPLEFT", f, "TOPRIGHT", d, d)
				t:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", d, -d)
				t:SetWidth(w)
			end
		end
		d = o
	end
	for i = n + 1, #tex do tex[i]:Hide() end
	return d
end

-- Two textures a corner, above the rings; out: where the rings end. Returns how far the caps
-- reach beyond them (when they are thicker).
local function drawCaps(f, caps, out, b)
	local t = f.frameCaps
	if not caps then
		if t then for _, x in ipairs(t) do x:Hide() end end
		return 0
	end
	if not t then
		t = {}
		for i = 1, 8 do t[i] = f:CreateTexture(nil, "BACKGROUND", nil, -7) end
		f.frameCaps = t
	end
	local px = ns.linePx(f, pxOf(caps.px, b))
	local o = math.max(out, px)
	local len = o + ns.linePx(f, caps.len or 6)
	local c = colorOf(caps.color, b, f)
	for i, corner in ipairs(CORNERS) do
		local point, x, y = corner[1], corner[2] * o, corner[3] * o
		-- along: the arm along the top or bottom; down: the one down the side.
		local along, down = t[2 * i - 1], t[2 * i]
		along:SetSize(len, px)
		down:SetSize(px, len)
		for _, a in ipairs({ along, down }) do
			a:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
			a:ClearAllPoints()
			a:SetPoint(point, f, point, x, y)
			a:Show()
		end
	end
	return o - out
end

-- Stretched art's place over `over`, an icon w wide.
local function placeArt(t, art, over, w)
	local i = art.inset
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", over, "TOPLEFT", -i[1] * w, i[3] * w)
	t:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", i[2] * w, -i[4] * w)
end

-- Stretched art: a texture on f itself, so it draws over the icon's picture and under f's children
-- (its swipe, timers and text), as Blizzard draws its own buttons' frames.
local function drawOverlay(f, art)
	local t = f.frameOverlay
	if not art or art.margin or (art.atlas and not Looks.hasAtlas(art.atlas)) then
		if t then t:Hide() end
		return
	end
	if not t then
		t = f:CreateTexture(nil, "OVERLAY", nil, 7)
		f.frameOverlay = t
	end
	local w = f:GetWidth()
	if ns.isSecret(w) then return end   -- under a secure button: placed at the next layout
	placeArt(t, art, f, w)
	if art.atlas then t:SetAtlas(art.atlas) else t:SetTexture(art.file) end
	t:Show()
end

-- Sliced art: a 9-slice round the icon, in a holder frame at f's level. It lies outside the icon's
-- edge, where only the rings under it and the glows and pops above it draw. A margin texel is
-- drawn as one of its frame's units (tested 2026-09-28), so the holder is scaled px over margin,
-- px being whole screen pixels; its margins stay under half its size (else the client draws a
-- plain stretch), as the icon is always wider than the frame. Returns how far it reaches outside.
local function drawSlice(f, art)
	local h = f.frameArt
	if not (art and art.margin) then
		if h then h:Hide() end
		return 0
	end
	if not h then
		h = CreateFrame("Frame", nil, f)
		h:EnableMouse(false)
		h.tex = h:CreateTexture(nil, "ARTWORK")
		h.tex:SetAllPoints()
		f.frameArt = h
	end
	local px = ns.linePx(f, art.px)
	local k = px / art.margin
	if k <= 0 then h:Hide(); return 0 end   -- SetScale refuses 0 (a frame not laid out yet)
	h:SetScale(k)
	local w, hh = f:GetWidth(), f:GetHeight()
	if ns.isSecret(w) or ns.isSecret(hh) then return px end   -- under a secure button: sized at the next layout
	h:SetSize((w + 2 * px) / k, (hh + 2 * px) / k)
	h:ClearAllPoints()
	h:SetPoint("CENTER", f, "CENTER", 0, 0)
	h:SetFrameLevel(f:GetFrameLevel())
	h.tex:SetTexture(art.file)
	h.tex:SetTextureSliceMargins(art.margin, art.margin, art.margin, art.margin)
	h.tex:SetTextureSliceMode(STRETCHED)
	h:Show()
	return px
end

-- A frame look whose Blizzard art the client lacks, and what draws in its place.
local NO_ART = { rings = { { color = BLACK } } }
local function artMissing(look)
	local a, m = look.art and look.art.atlas, look.mask and look.mask.atlas
	return (a and not Looks.hasAtlas(a)) or (m and not Looks.hasAtlas(m)) or false
end

-- A look's mask, if the client has its art.
local function maskOf(look)
	local m = look.mask
	if m and m.atlas and not Looks.hasAtlas(m.atlas) then return nil end
	return m
end
-- The look a border style b draws in (nil: the border is off).
local function lookFor(b)
	local look = b and b.show and S.look("border", b.look)
	if look and artMissing(look) then return NO_ART end
	return look or nil
end
-- The mask for a border style b (nil: none, or the border is off).
local function maskFor(b)
	local look = lookFor(b)
	return look and maskOf(look) or nil
end
-- The stretched art for a border style b (nil: none, or the border is off).
local function artFor(b)
	local look = lookFor(b)
	return look and look.art and not look.art.margin and look.art or nil
end

-- A mask texture's art and place: spec over the rect of `over` (the icon's picture), w and h its
-- size (default square; a mask larger than the picture is centred on it).
local function placeMask(m, spec, over, w, h)
	if spec.atlas then m:SetAtlas(spec.atlas, false, nil, nil, CLAMP, CLAMP)
	else m:SetTexture(spec.file, spec.wrap or CLAMP, spec.wrap or CLAMP) end
	m:ClearAllPoints()
	-- A size that reads as secret (the totem bar's picture, under its secure button) can't be
	-- scaled: the mask then covers the picture exactly, a little tighter than the look's own.
	if (spec.scale or 1) == 1 or ns.isSecret(w) or ns.isSecret(h) then m:SetAllPoints(over)
	else
		m:SetPoint("CENTER", over, "CENTER", 0, 0)
		m:SetSize(w * spec.scale, (h or w) * spec.scale)
	end
end

-- Textures other code lays over an icon's picture (the expiring warning's grey copy and dimming),
-- registered with Looks.followMask: they take the icon's mask too.
local followers = setmetatable({}, { __mode = "k" })   -- icon frame -> { texture, ... }
local ownShape = setmetatable({}, { __mode = "k" })    -- icon frame -> { texture -> over } (Looks.maskOver)
local maskSpecs = setmetatable({}, { __mode = "k" })   -- icon frame -> its mask spec now

-- Masks tex (a texture over f's picture) with spec, or takes its mask off (spec nil). The mask is
-- made on the frame tex belongs to. Our icons take a mask, and let it go, at any time (tested
-- 2026-09-28, in combat too).
local function maskOne(f, tex, spec, over)
	if not tex then return end
	f.frameMasks = f.frameMasks or {}
	local m = f.frameMasks[tex]
	if spec then
		if not m then
			m = tex:GetParent():CreateMaskTexture()
			f.frameMasks[tex] = m
		end
		-- over's size in the mask's own units: a texture on a scaled frame (a soft glow's) is masked
		-- by the size over has on screen.
		local w, h = over:GetWidth(), over:GetHeight()
		local a, b = over:GetEffectiveScale(), tex:GetParent():GetEffectiveScale()
		if not (ns.isSecret(w) or ns.isSecret(h) or ns.isSecret(a) or ns.isSecret(b)) and b > 0 then
			w, h = w * a / b, h * a / b
		end
		placeMask(m, spec, over, w, h)
		if not m.on then tex:AddMaskTexture(m); m.on = true end
	elseif m and m.on then
		tex:RemoveMaskTexture(m)
		m.on = false
	end
end

-- The icon's picture (f.tex on element icons, f.icon on the totem bar's) and what covers it.
local function drawMask(f, spec)
	local over = f.tex or f.icon
	if not over or (spec == nil and maskSpecs[f] == nil) then return end
	maskSpecs[f] = spec
	maskOne(f, over, spec, over)
	maskOne(f, f.bg, spec, over)
	maskOne(f, f.manaOverlay, spec, over)
	maskOne(f, f.warn and f.warn.grey, spec, over)
	for _, t in ipairs(followers[f] or {}) do maskOne(f, t, spec, over) end
	for t, o in pairs(ownShape[f] or {}) do maskOne(f, t, spec, o) end
end

-- Masks tex with icon frame f's look, in the place and size of over (default tex itself: a texture
-- set in from the picture's edges takes the whole shape, set in by as much), now and on each change
-- of look. Call again after moving them.
function Looks.maskOver(f, tex, over)
	local map = ownShape[f] or {}
	ownShape[f] = map
	map[tex] = over or tex
	if maskSpecs[f] then maskOne(f, tex, maskSpecs[f], map[tex]) end
end

-- Registers textures laid over icon frame f's picture, to take its mask (now, and on each change).
function Looks.followMask(f, ...)
	local list = followers[f] or {}
	followers[f] = list
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		table.insert(list, t)
		if maskSpecs[f] then maskOne(f, t, maskSpecs[f], f.tex or f.icon) end
	end
end

-- Cooldowns other code lays over an icon (a global cooldown sweep), registered with
-- Looks.followSwipe: their swipes take the icon's look too.
local swipers = setmetatable({}, { __mode = "k" })   -- icon frame -> { cooldown, ... }
local swipeLooks = setmetatable({}, { __mode = "k" })   -- icon frame -> the masked look it has now

-- One cooldown over f in look's shape (look nil: the plain square). Only touched once a look has
-- asked for a shape; its swipe file and its points go back to the square one after. w: f's width
-- when the caller knows it (Blizzard's aura button, whose size reads secret); else it is read, and a
-- secret read leaves the swipe's place for the next restyle.
local function swipeOne(f, cd, look, w)
	local file, inset = look and look.swipe, look and look.swipeInset
	if not cd or (file == nil and inset == nil and cd.frameSwipe == nil) then return end
	file = file or WHITE
	if cd.frameSwipe ~= file then cd:SetSwipeTexture(file) end
	cd.frameSwipe = file
	if inset or cd.frameInset then
		w = w or f:GetWidth()
		if ns.isSecret(w) then return end
		local d = (inset or 0) * w
		cd:ClearAllPoints()
		cd:SetPoint("TOPLEFT", f, "TOPLEFT", d, -d)
		cd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -d, d)
		cd.frameInset = inset
	end
end

-- The icon's cooldown swipes in a masked look's shape (look nil: unmasked).
local function drawSwipe(f, look)
	if look == nil and swipeLooks[f] == nil then return end
	swipeLooks[f] = look
	swipeOne(f, f.cd, look)
	for _, cd in ipairs(swipers[f] or {}) do swipeOne(f, cd, look) end
end

-- Registers a cooldown laid over icon frame f (all its points on f), to take its look's swipe.
function Looks.followSwipe(f, cd)
	local list = swipers[f] or {}
	swipers[f] = list
	table.insert(list, cd)
	if swipeLooks[f] then swipeOne(f, cd, swipeLooks[f]) end
end

-- The parts of a look that fit a bar (an element of shape "bar"): its rings and its sliced art. A
-- look with neither (a mask and stretched art, shaped for an icon) draws a plain line there.
local barLooks = {}   -- look -> its bar parts
local function barParts(look)
	local v = barLooks[look]
	if not v then
		local slice = look.art and look.art.margin and look.art or nil
		v = (look.rings or slice) and { rings = look.rings, art = slice } or NO_ART
		barLooks[look] = v
	end
	return v
end

-- The look border style b draws in (NO_ART for one whose Blizzard art is missing; for shape "bar",
-- its parts that fit a bar), or nil: b is off, or a look drawn at the Border size has a size of 0.
local function drawnLook(b, shape)
	local look = S.look("border", b and b.look)
	if artMissing(look) then look = NO_ART end
	local on = b and b.show and (not Looks.uses(look, "size") or (b.size and b.size > 0))
	if not on then return nil end
	return shape == "bar" and barParts(look) or look
end

-- How far in from the edge of a box w wide (the element's Size, in f's units) the icon's picture
-- sits, so that border b drawn round it stays inside the box: the reach of its lines and sliced
-- art (whole screen pixels, as they are drawn, for f's scale), or of its stretched art, which
-- reaches a share of the picture's width past its edges; whichever is further. shape: as for
-- ns.applyBorder.
function Looks.inset(f, b, w, shape)
	local look = drawnLook(b, shape)
	if not look then return 0 end
	local out = 0
	for _, ring in ipairs(look.rings or {}) do out = out + ns.linePx(f, pxOf(ring.px, b)) end
	if look.caps then out = math.max(out, ns.linePx(f, pxOf(look.caps.px, b))) end
	local art = look.art
	if art and art.margin then out = math.max(out, ns.linePx(f, art.px))
	elseif art and art.inset then
		local share = math.max(art.inset[1], art.inset[2], art.inset[3], art.inset[4])
		if share > 0 then
			local one = ns.pixel(f)
			out = math.max(out, math.ceil(share * w / (1 + 2 * share) / one - 0.01) * one)
		end
	end
	-- The picture keeps a few units, however small the icon and heavy the look.
	return math.min(out, math.max((w - 4) / 2, 0))
end

-- Sizes icon f for a box w by h (its Size) with border b drawn round it inside that box, and draws
-- b. Returns the inset (Looks.inset): the caller places f that far in from the box's edges.
-- opts (optional; an element's registry entry serves): borderHost, the part the border is drawn on
-- (a child covering f, so the border hides with it; default f), and shape (ns.applyBorder).
function Looks.fit(f, b, w, h, opts)
	local host, shape = opts and opts.borderHost or f, opts and opts.shape
	local o = Looks.inset(host, b, math.min(w, h or w), shape)
	f:SetSize(w - 2 * o, (h or w) - 2 * o)
	ns.applyBorder(host, b, shape)
	if host ~= f then
		-- The mask and the swipe belong to the icon's picture, not to the part the border is on.
		local look = drawnLook(b, shape)
		local mask = look and maskOf(look)
		drawMask(f, mask)
		drawSwipe(f, mask and look)
		f.frameOuter = host.frameOuter
	end
	return o
end

-- Draws b's stretched art (the inner overlay of a look such as Cooldown Manager) on part f alone,
-- or takes it down: for a frame that shows it where no other part of the border does.
function Looks.overlay(f, b, shape)
	local look = drawnLook(b, shape)
	drawOverlay(f, look and look.art)
end

-- Draws b (a border style) round f in its look, or takes it down (b off, or a size of 0 for a
-- look drawn at the Border size). Drawn round f's edge, so it never covers the rings inside the
-- icon or Blizzard's aura button; art and masks draw as each look says. f is the icon's picture,
-- set in from its box by Looks.inset. Its lines are screen pixels (ns.linePx), grown by Scale, not
-- by icon Size. shape "bar": f is a bar, not an icon, and takes only the look's parts that fit one
-- (barParts). Sets f.frameOuter, how far it reaches outside f's edge (f's units), for
-- Looks.outerEdge.
function ns.applyBorder(f, b, shape)
	local look = drawnLook(b, shape)
	if not look then
		drawRings(f, nil, b)
		drawCaps(f, nil)
		drawOverlay(f, nil)
		drawSlice(f, nil)
		drawMask(f, nil)
		drawSwipe(f, nil)
		f.frameOuter = 0
		return
	end
	local out = drawRings(f, look.rings, b)
	out = out + drawCaps(f, look.caps, out, b)
	drawOverlay(f, look.art)
	out = math.max(out, drawSlice(f, look.art))
	local mask = maskOf(look)
	drawMask(f, mask)
	drawSwipe(f, mask and look)
	f.frameOuter = out
end

-- How far f's frame reaches outside its edge (f's units): where a glow or a pop that wraps the
-- frame starts, so a heavier frame doesn't cover it.
function Looks.outerEdge(f) return f and f.frameOuter or 0 end

-- Blizzard's aura button (the shield, Elemental Focus via ns.makeAuraSlot) takes a mask only when
-- it is made on the button while Blizzard makes the button (the slot's initializeFrame); one made
-- on our frames, or added later in combat, is refused. So every button gets its mask there: the
-- element's look's shape, or a plain one that hides nothing, and so does its stretched art: the
-- aura's icon on the button covers everything drawn on the element's own frame. Later, out of
-- combat (Looks.auraStyle), the button follows the look picked since: its art is changed or
-- hidden and its mask takes the new shape. The element's frame keeps its own art too, for while
-- the button is hidden (no aura). key: the element.
-- host: the frame the icon is on, the button or the aura slot's host under it (made with it).
-- The plain mask is a solid white texture clamped to its edge texels (wrap "CLAMP", not the
-- black-blending wrap the shaped masks use), so it leaves every pixel of the icon as it was.
local PLAIN_MASK = { file = WHITE, wrap = "CLAMP" }
local auraMade = setmetatable({}, { __mode = "k" })   -- aura icon -> { key, spec, mask, look, art }
function Looks.auraMask(host, tex, key)
	local b = ns.borderFor(key)
	local spec, art, size = maskFor(b), artFor(b), ns.sizeOf(key)
	local made = { key = key, spec = spec, look = spec and lookFor(b), art = art }
	auraMade[tex] = made
	if art then
		local t = host:CreateTexture(nil, "OVERLAY", nil, 7)
		if art.atlas then t:SetAtlas(art.atlas) else t:SetTexture(art.file) end
		placeArt(t, art, host, size)
		made.artTex = t
	end
	local m = host:CreateMaskTexture()
	placeMask(m, spec or PLAIN_MASK, tex, size)
	tex:AddMaskTexture(m)
	made.mask = m
end

-- The aura slot's restyle (out of combat, auras readable; AuraSlot:style): the button takes the
-- element's border look now (its art and its mask's shape), placed for the icon's size, and the
-- swipe in the mask's shape. All on the slot's host (the button, or the caller's frame covering
-- it: ns.makeAuraSlot).
function Looks.auraStyle(slot, size)
	local made = slot.icon and auraMade[slot.icon]
	if not made then return end
	local host = slot.host
	local b = ns.borderFor(made.key)
	local art, spec = artFor(b), maskFor(b)
	if art ~= made.art then
		if art and not made.artTex then made.artTex = host:CreateTexture(nil, "OVERLAY", nil, 7) end
		local t = made.artTex
		if art then
			if art.atlas then t:SetAtlas(art.atlas) else t:SetTexture(art.file) end
			t:Show()
		elseif t then t:Hide() end
		made.art = art
	end
	if made.artTex and made.art then placeArt(made.artTex, made.art, host, size) end
	placeMask(made.mask, spec or PLAIN_MASK, slot.icon, size)
	made.spec = spec
	made.look = spec and lookFor(b) or nil
	swipeOne(host, slot.cd, made.look, size)
end

-- The aura elements whose button's shape differs from their border look now: none, every button
-- has a mask it reshapes.
function Looks.auraStale() return {} end

------------------------------------------------------------------------
-- Frame looks. "line" is the default look.
------------------------------------------------------------------------
local GOLD = { 0.71, 0.55, 0.29, 1 }   -- the options window's gold
Looks.GOLD = GOLD
local BRONZE_HI, BRONZE_LO, BRONZE_DARK = { 0.85, 0.68, 0.39, 1 }, { 0.43, 0.29, 0.13, 1 }, { 0.10, 0.07, 0.03, 1 }
-- Blizzard's Cooldown Manager and action button art. The plain names draw Forever's bronze art
-- (tested 2026-09-28); the action button's mask is drawn 64 over a 45 icon, as Blizzard draws it.
local CDM_MASK, CDM_OVERLAY = "UI-HUD-CoolDownManager-Mask", "UI-HUD-CoolDownManager-IconOverlay"
local CDM_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local AB_MASK, AB_FRAME = "UI-HUD-ActionBar-IconFrame-Mask", "UI-HUD-ActionBar-IconFrame"

S.addField("border", "look", { name = "Border look", where = "General > Border", preview = { play = "still" },
	groups = { { "lines", "Lines" }, { "blizzard", "Blizzard's" }, { "painted", "Painted" } } })
S.addLook("border", "line", { name = "Line", group = "lines", uses = { size = true, color = true },
	rings = { { px = "size", color = "color" } } })
S.addLook("border", "hairline", { name = "Gold hairline", group = "lines",
	rings = { { color = BLACK }, { color = GOLD }, { color = BLACK } } })
-- Lit from the top left; the lit band is Border size thick.
S.addLook("border", "bevel", { name = "Bronze bevel", group = "lines", uses = { size = true },
	rings = { { color = BLACK }, { px = "size", top = BRONZE_HI, left = BRONZE_HI, bottom = BRONZE_LO, right = BRONZE_LO },
		{ color = BRONZE_DARK } } })
S.addLook("border", "caps", { name = "Corner caps", group = "lines",
	uses = { size = true, color = true, capSize = true, capColor = true },
	rings = { { px = "size", color = "color" } }, caps = { px = "capSize", len = 6, color = "capColor" } })
-- Rounded corners and a soft dark edge, as on the Cooldown Manager's icons.
S.addLook("border", "cdm", { name = "Cooldown Manager", group = "blizzard",
	mask = { atlas = CDM_MASK }, swipe = CDM_SWIPE, art = { atlas = CDM_OVERLAY, inset = { 0.18, 0.18, 0.16, 0.16 } } })
-- Cut corners in a dark bronze frame, as on Forever's action buttons.
S.addLook("border", "button", { name = "Forever action button", group = "blizzard",
	mask = { atlas = AB_MASK, scale = 64 / 45 }, swipeInset = 3 / 45,
	art = { atlas = AB_FRAME, inset = { 0, 1 / 45, 0, 0 } } })
-- Painted frames, 9-sliced from 128 px art; margin: the painted frame's width in texels.
S.addLook("border", "stone", { name = "Carved stone", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Stone", margin = 27, px = 6 } })
S.addLook("border", "bronze", { name = "Aged bronze", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Bronze", margin = 14, px = 4 } })
S.addLook("border", "wood", { name = "Carved wood", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Wood", margin = 22, px = 6 } })
-- For the totem bar's Looks only: the Border size of the slot's element colour inside 1 px of black.
S.addLook("border", "schooledge", { name = "School edge", group = "lines", hidden = true, bySchool = true,
	uses = { size = true }, rings = { { color = BLACK }, { px = "size", color = "school" } } })
-- For the totem bar's Looks only: a round picture in a bronze medallion, whose opening overlaps the
-- picture's edge a little.
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
S.addLook("border", "medallion", { name = "Medallion", group = "painted", hidden = true, credit = "ai",
	mask = { file = ROUND }, swipe = ROUND, art = { file = MEDIA .. "Medallion", inset = { 0.35, 0.35, 0.35, 0.35 } } })

------------------------------------------------------------------------
-- Glow looks. The default is "soft", the soft inner glow. Each look is a choice (S.addLook: name,
-- uses, bySchool and the rest; uses from color, speed, low, width, strength) with:
--   steady    it doesn't breathe (the glow's pulse is off; speed may time its own motion)
--   inside    drawn only within the icon: a warning's glow on the element takes the icon's shape
--             (over ns.makeClipLook's picture); the other looks reach past it and take none
--   build(g)  its regions and animation groups, under g.inner (breathing) or g (not); returns
--             parts: { roots = { frames }, anims = { groups played while it shows }, aura = { the
--             groups Blizzard's aura button plays in their place, when the glow is under it },
--             moving = { the roots whose regions scale or move: hidden while a pop moves the icon } }
--   style(g, parts, st, c)       colours and timing; c is the colour (st.color or a fixed one)
--   fit(g, parts, size, out)     sizes for an icon of size, whose frame reaches out past its edge
------------------------------------------------------------------------
local GOLD_GLOW = { 1, 0.8, 0.25 }   -- the glow's default colour (ns.Style "glow")
local ACTIVE_GLOW = "UI-CooldownManager-ActiveGlow"
local PROC_START, PROC_LOOP = "UI-HUD-ActionBar-Proc-Start-Flipbook", "UI-HUD-ActionBar-Proc-Loop-Flipbook"

local function root(parent)
	local r = CreateFrame("Frame", nil, parent)
	r:SetAllPoints()
	r:EnableMouse(false)
	return r
end
-- Puts a look's frames (its roots and their holders) at the level of the frame they hang from,
-- the glow's own: a level higher is the timer bar's or the text's. Levels move as an
-- icon regroups, so the glow calls this each time it shows.
function Looks.levelParts(parts)
	for _, r in ipairs(parts.roots or {}) do
		local lv = r:GetParent():GetFrameLevel()
		r:SetFrameLevel(lv)
		for _, c in ipairs({ r:GetChildren() }) do c:SetFrameLevel(lv) end
	end
end
local function light(c) return c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5 end

-- A group of one animation of kind on region, looping ("REPEAT", "BOUNCE") or not.
local function anim(region, kind, looping)
	local g = region:CreateAnimationGroup()
	if looping then g:SetLooping(looping) end
	return g, g:CreateAnimation(kind)
end
-- A FlipBook: a sheet of rows x cols frames played in order (on atlases and our files, in
-- combat, on schedule: tested 2026-09-28), shown only while it plays.
local function flipBook(tex, rows, cols, frames, dur, looping)
	local g, f = anim(tex, "FlipBook", looping)
	f:SetFlipBookRows(rows)
	f:SetFlipBookColumns(cols)
	f:SetFlipBookFrames(frames)
	f:SetFlipBookFrameWidth(0)
	f:SetFlipBookFrameHeight(0)
	f:SetDuration(dur)
	local show = g:CreateAnimation("Alpha")
	show:SetFromAlpha(1); show:SetToAlpha(1); show:SetDuration(dur)
	tex:SetAlpha(0)
	g.flip, g.show = f, show
	return g
end

-- The soft inner glow: one texture, sliced so Thickness sets how far in it reaches; its
-- corners fall off as evenly as its sides.
local SOFT_MARGIN = 16
local function softPart(parent, alpha)
	local h = CreateFrame("Frame", nil, parent)
	h:EnableMouse(false)
	h.tex = h:CreateTexture(nil, "OVERLAY")
	h.tex:SetAllPoints()
	h.tex:SetTexture(MEDIA .. "Glow-Inner")
	h.tex:SetTextureSliceMargins(SOFT_MARGIN, SOFT_MARGIN, SOFT_MARGIN, SOFT_MARGIN)
	h.tex:SetTextureSliceMode(STRETCHED)
	h.tex:SetBlendMode("ADD")
	h.alpha = alpha or 1
	return h
end
local function styleSoft(h, c) h.tex:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * h.alpha) end
local function fitSoft(g, h, size, width)
	if not (size and size > 0) then return end   -- not laid out yet (a preview slot): SetScale refuses 0
	local th = math.min(math.max(size * (width or 0.2), 1), size * 0.45)
	local k = th / SOFT_MARGIN
	h:SetScale(k)
	h:SetSize(size / k, size / k)
	h:ClearAllPoints()
	h:SetPoint("CENTER", g, "CENTER", 0, 0)
end

local soft = {
	uses = { color = true, speed = true, low = true, width = true }, inside = true,
	build = function(g)
		local r = root(g.inner)
		return { roots = { r }, soft = softPart(r) }
	end,
	style = function(g, parts, st, c) styleSoft(parts.soft, c) end,
	fit = function(g, parts, size) fitSoft(g, parts.soft, size, g.width) end,
}

-- A halo outside the frame, from the Cooldown Manager's active glow; the soft inner glow on a
-- client without it.
local halo = {
	uses = { color = true, speed = true, low = true },
	build = function(g)
		if not Looks.hasAtlas(ACTIVE_GLOW) then
			local parts = soft.build(g)
			parts.fallback = true
			return parts
		end
		local r = root(g.inner)
		local t = r:CreateTexture(nil, "OVERLAY")
		t:SetAtlas(ACTIVE_GLOW)
		t:SetDesaturated(true)
		t:SetBlendMode("ADD")
		local grow, s = anim(t, "Scale", "BOUNCE")
		s:SetScaleFrom(1, 1); s:SetScaleTo(1.07, 1.07); s:SetSmoothing("IN_OUT")
		return { roots = { r }, halo = t, grow = grow, scale = s, anims = { grow }, aura = { grow }, moving = { r } }
	end,
	style = function(g, parts, st, c)
		if parts.fallback then return soft.style(g, parts, st, c) end
		parts.halo:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		parts.scale:SetDuration(st.speed)
	end,
	fit = function(g, parts, size, out)
		if parts.fallback then return soft.fit(g, parts, size) end
		local d = out + size * 0.24
		parts.halo:ClearAllPoints()
		parts.halo:SetPoint("TOPLEFT", g, "TOPLEFT", -d, d)
		parts.halo:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", d, -d)
	end,
}

-- Blizzard's action bar proc glow: a burst that settles into a ring of moving light, in its
-- own gold unless the glow's colour is changed. Under Blizzard's aura button (g.underButton) only the
-- ring, which the button plays: the burst needs a script to hand over to the ring and none runs
-- there, and the burst's flipbook drew there as a whole sprite sheet (seen 2026-09-30).
local proc = {
	uses = { color = true }, steady = true,
	build = function(g)
		if not (Looks.hasAtlas(PROC_START) and Looks.hasAtlas(PROC_LOOP)) then
			local parts = soft.build(g)
			parts.fallback = true
			return parts
		end
		local r = root(g.inner)
		local loop = r:CreateTexture(nil, "OVERLAY")
		loop:SetAtlas(PROC_LOOP)
		local loopG = flipBook(loop, 6, 5, 30, 1, "REPEAT")
		if g.underButton then
			return { roots = { r }, loop = loop, texs = { loop }, anims = { loopG }, aura = { loopG }, stop = { loopG } }
		end
		local start = r:CreateTexture(nil, "OVERLAY")
		start:SetAtlas(PROC_START)
		local startG = flipBook(start, 6, 5, 30, 0.7)
		startG:SetScript("OnFinished", function() if r:IsVisible() then loopG:Play() end end)
		return { roots = { r }, start = start, loop = loop, texs = { start, loop }, anims = { startG }, aura = { loopG },
			stop = { loopG } }
	end,
	style = function(g, parts, st, c)
		if parts.fallback then return soft.style(g, parts, st, c) end
		local own = not g.fixed and c[1] == GOLD_GLOW[1] and c[2] == GOLD_GLOW[2] and c[3] == GOLD_GLOW[3]
		for _, t in ipairs(parts.texs) do
			t:SetDesaturated(not own)
			if own then t:SetVertexColor(1, 1, 1, c[4] or 1) else t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
		end
	end,
	fit = function(g, parts, size, out)
		if parts.fallback then return soft.fit(g, parts, size) end
		local s = size + 2 * out
		if parts.start then
			parts.start:SetSize(s * 150 / 45, s * 150 / 45)
			parts.start:SetPoint("CENTER", g, "CENTER", 0, 0)
		end
		parts.loop:SetSize(s * 1.4, s * 1.4)
		parts.loop:SetPoint("CENTER", g, "CENTER", 0, 0)
	end,
}

-- Two sparks running round the edge over a faint steady inner glow, in Translation steps
-- (one a side, a quarter of the lap each).
local SPARK_PATH = { { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 1 } }   -- from the top left, clockwise
local spark = {
	uses = { color = true, lap = true, width = true }, steady = true,
	fields = { lap = { name = "Lap time", tip = "One lap round the icon.", range = S.KINDS.glow.ranges.lap, step = 0.1,
		format = "%.1f s" } },
	build = function(g)
		local r = root(g.inner)
		local parts = { roots = { r }, soft = softPart(r, 0.45), sparks = {}, anims = {}, moving = { r } }
		for i, corner in ipairs({ "TOPLEFT", "BOTTOMRIGHT" }) do
			local t = r:CreateTexture(nil, "OVERLAY", nil, 1)
			t:SetTexture(MEDIA .. "Spark")
			t:SetBlendMode("ADD")
			local grp = t:CreateAnimationGroup()
			grp:SetLooping("REPEAT")
			t.steps = {}
			for n = 1, 4 do
				local a = grp:CreateAnimation("Translation")
				a:SetOrder(n)
				t.steps[n] = a
			end
			t.corner, t.dir = corner, i == 1 and 1 or -1
			parts.sparks[i] = t
			table.insert(parts.anims, grp)
		end
		parts.aura = parts.anims
		return parts
	end,
	style = function(g, parts, st, c)
		styleSoft(parts.soft, c)
		for _, t in ipairs(parts.sparks) do
			local red, gr, b = light(c)
			t:SetVertexColor(red, gr, b, c[4] or 1)
			for _, a in ipairs(t.steps) do a:SetDuration(st.lap / 4) end
		end
	end,
	fit = function(g, parts, size)
		fitSoft(g, parts.soft, size, g.width)
		for _, t in ipairs(parts.sparks) do
			t:SetSize(size * 0.5, size * 0.5)
			t:ClearAllPoints()
			t:SetPoint("CENTER", g, t.corner, 0, 0)
			for n, a in ipairs(t.steps) do
				local step = SPARK_PATH[n]
				a:SetOffset(step[1] * size * t.dir, step[2] * size * t.dir)
			end
		end
	end,
}

-- The inner glow carrying its school's texture, drifting. The texture is larger than the icon
-- and slides one tile under a mask of the glow's shape, which stays put. Whether a mask holds still
-- while its texture moves is untested: if it doesn't, the texture shows still.
local MATERIAL = {   -- school -> tile move (in tiles), seconds a tile
	earth = { 0, 0, 1 }, fire = { 0, 1, 2.2 }, water = { 1, -1, 5 }, air = { 1, 0, 1.2 }, spirit = { 1, -1, 5 },
}
-- The drift for the school and the size last fitted (none yet: fit sets it).
local function materialDrift(parts)
	local size = parts.size
	if not size then return end
	local mv = MATERIAL[parts.school or "spirit"] or MATERIAL.spirit
	parts.move:SetOffset(mv[1] * size, mv[2] * size)
end
-- Intensity: below 100% the material dims; above it the glow under it brightens too (the material
-- itself is already at full opacity, so more light has to come from the soft glow beneath).
local material = {
	uses = { color = true, speed = true, strength = true }, bySchool = true, inside = true,
	build = function(g)
		local r = root(g.inner)
		local parts = { roots = { r }, soft = softPart(r, 0.35) }
		local t = r:CreateTexture(nil, "OVERLAY", nil, 1)
		t:SetBlendMode("ADD")
		local m = r:CreateMaskTexture()
		m:SetTexture(MEDIA .. "Glow-Inner", CLAMP, CLAMP)
		m:SetAllPoints(g)
		t:AddMaskTexture(m)
		local drift, a = anim(t, "Translation", "REPEAT")
		parts.mat, parts.drift, parts.move, parts.anims, parts.aura = t, drift, a, { drift }, { drift }
		parts.moving = { r }
		return parts
	end,
	style = function(g, parts, st, c)
		local k = st.strength or 1
		parts.soft.alpha = math.min(0.35 * math.max(k, 1), 1)
		styleSoft(parts.soft, c)
		local school = effectSchool(g)
		parts.school = school
		parts.mat:SetTexture(MEDIA .. "Mat-" .. school:sub(1, 1):upper() .. school:sub(2), "REPEAT", "REPEAT")
		parts.mat:SetTexCoord(0, 3, 0, 3)
		parts.mat:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * math.min(k, 1))
		parts.move:SetDuration((MATERIAL[school] or MATERIAL.spirit)[3])
		materialDrift(parts)
	end,
	fit = function(g, parts, size)
		fitSoft(g, parts.soft, size)
		parts.mat:SetSize(size * 3, size * 3)
		parts.mat:ClearAllPoints()
		parts.mat:SetPoint("CENTER", g, "CENTER", 0, 0)
		parts.size = size
		materialDrift(parts)
	end,
}

-- A steady inner glow and a ring that swells out from the frame's edge, like a ping: the
-- glow breathes with the pulse settings, the ring every 1.8 pulse lengths.
local heartbeat = {
	uses = { color = true, speed = true, low = true, width = true },
	build = function(g)
		local r, o = root(g.inner), root(g)
		local ring = o:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(MEDIA .. "Glow-Outer")
		ring:SetBlendMode("ADD")
		local beat = ring:CreateAnimationGroup()
		beat:SetLooping("REPEAT")
		local s = beat:CreateAnimation("Scale")
		s:SetScaleFrom(0.9, 0.9); s:SetScaleTo(1.65, 1.65); s:SetSmoothing("OUT")
		local a = beat:CreateAnimation("Alpha")
		a:SetFromAlpha(0.9); a:SetToAlpha(0); a:SetSmoothing("OUT")
		return { roots = { r, o }, soft = softPart(r, 0.6), ring = ring, beat = { s, a }, anims = { beat }, aura = { beat },
			moving = { o } }
	end,
	style = function(g, parts, st, c)
		styleSoft(parts.soft, c)
		parts.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		for _, a in ipairs(parts.beat) do a:SetDuration(st.speed * 1.8) end
	end,
	fit = function(g, parts, size, out)
		fitSoft(g, parts.soft, size, g.width)
		local s = (size + 2 * out) / 0.68   -- the texture's hollow is 68% of it
		parts.ring:SetSize(s, s)
		parts.ring:SetPoint("CENTER", g, "CENTER", 0, 0)
	end,
}

S.addField("glow", "look", { name = "Glow look", where = "General > Pulsing glow style", preview = { play = "loop" } })
local function addGlow(key, name, entry)
	entry.name = name
	S.addLook("glow", key, entry)
end
addGlow("soft", "Soft inner", soft)
addGlow("halo", "Outer halo", halo)
addGlow("proc", "Proc glow", proc)
addGlow("spark", "Travelling spark", spark)
addGlow("material", "School material", material)
addGlow("heartbeat", "Heartbeat", heartbeat)

------------------------------------------------------------------------
-- The pop: its choices (S.addChoice: colour, flash, burst, motion), and its parts past
-- ns.Effects' own plain flash, ring and star: Blizzard's edge flash (Looks.popEdge) and the drawn
-- bursts (Looks.popParts), as data for the pop's rig. A burst entry names the rig's own parts it
-- plays (rigParts: "ring", "star") or draws its parts (draw(out, school)). A burst's
-- shapes follow the school of the icon it pops on. Shapes spread behind the icon over a dark halo,
-- so they read on bright ground (an added burst vanishes on bright ground without one, tested
-- 2026-09-28: white bursts on snow); the sheen crosses the icon.
-- A drawn burst is a list of parts, each a texture that grows (or shrinks), fades, turns and rises
-- over its short life, in the colour the pop gives it:
--   name         the rig's texture it takes (Looks.POP_PARTS)
--   file         its texture
--   layer, sub   its draw layer and sublevel
--   add          added light (else blended); dark: black (the halo and the disc under a burst);
--                color: a colour of its own
--   from, to     its size at the start and at the end, in icon heights (the icon with its frame;
--                square, or sy as tall as wide)
--   dur, delay   its life and the wait before it starts, in seconds at the style's speed 1
--   a, slow      its alpha at the start, fading to 0; slow: fading late
--   spin, rise   radians it turns over its life; icon heights its centre moves up (down if less
--                than 0)
--   shift        { from, to }: the sheen's picture slides across the icon from and to these
--                shares of it (up and left as they grow), in place of growing
------------------------------------------------------------------------
local GCD_FLASH = "UI-HUD-ActionBar-GCD-Flipbook"
local SCHOOLS = { earth = "Earth", fire = "Fire", water = "Water", air = "Air", spirit = "Spirit" }
local SPIN = { earth = -0.35, fire = 0.25, water = -0.35, air = -1.2, spirit = -0.35 }
local SHEEN = { earth = { -0.7, 0.7 }, fire = { -0.7, 0.7 }, water = { 0.7, -0.7 }, air = { -0.7, 0.7 }, spirit = { -0.7, 0.7 } }
local HALO_SCALE, HALO_ALPHA = 1.08, 0.6

-- The rig's textures for the drawn bursts, and where each sits: behind the icon, over it (on the
-- pop's light frame), or over it clipped to its edge.
Looks.POP_PARTS = { disc = "back", shape1 = "back", shape1Dark = "back", shape2 = "back", ring1 = "back",
	ring2 = "back", spark = "front", sheen = "clip" }

-- A burst of file into out, from and to in icon heights, t its timing and motion (dur, delay, a,
-- slow, spin, rise, sy, color). Behind the icon unless front. dark: with a dark copy under it, a
-- little larger (the halo that keeps it readable on bright ground).
local function burst(out, name, file, from, to, t, front, dark)
	local a = t.a or 1
	table.insert(out, { name = name, file = file, layer = front and "OVERLAY" or "ARTWORK", add = true,
		color = t.color, from = from, to = to, dur = t.dur, delay = t.delay, a = a, slow = t.slow,
		spin = t.spin, rise = t.rise, sy = t.sy })
	if dark then
		table.insert(out, { name = name .. "Dark", file = file, layer = "BACKGROUND", dark = true,
			from = from * HALO_SCALE, to = to * HALO_SCALE, dur = t.dur, delay = t.delay, a = a * HALO_ALPHA,
			slow = t.slow, spin = t.spin, rise = t.rise, sy = t.sy })
	end
end
-- The dark disc under a burst: widest a little inside to, fading late.
local function disc(out, to, dur, delay)
	table.insert(out, { name = "disc", file = MEDIA .. "Disc-Dark", layer = "BACKGROUND", sub = -1, dark = true,
		from = to * 0.55, to = to * 0.95, dur = dur * 1.1, delay = delay, a = 0.75, slow = true })
end
-- A soft band crossing the icon, in the school's direction.
local function sheen(out, school, dur, delay)
	table.insert(out, { name = "sheen", file = MEDIA .. "Sheen", layer = "OVERLAY", add = true, dur = dur,
		delay = delay, a = 0.9, shift = SHEEN[school] or SHEEN.spirit })
end
local function shapeFile(school) return MEDIA .. "Shape-" .. (SCHOOLS[school] or "Spirit") end

-- Shapes spreading behind the icon (drawn or painted); a sheen in the school's direction crosses
-- the icon.
local function shapes(file, to)
	return function(out, school)
		disc(out, 3.0, 0.5)
		burst(out, "shape1", file(school), 1.0, to, { dur = 0.5, spin = SPIN[school] }, false, true)
		sheen(out, school, 0.34)
	end
end

-- Each school its own effect: earth slams, fire flares up, water ripples twice, air spins,
-- spirit gathers in and bursts.
local EFFECTS = {
	earth = function(out)
		burst(out, "shape1", shapeFile("earth"), 0.8, 2.7, { dur = 0.5, spin = 0.25, delay = 0.06 }, false, true)
		burst(out, "ring1", MEDIA .. "Ring-Soft", 1.0, 2.6, { dur = 0.55, sy = 0.42, rise = -0.32, a = 0.9, delay = 0.06 })
		sheen(out, "earth", 0.34, 0.05)
	end,
	fire = function(out)
		burst(out, "shape1", shapeFile("fire"), 1.0, 3.1, { dur = 0.55, rise = 0.35, spin = 0.2 }, false, true)
		burst(out, "shape2", shapeFile("fire"), 0.8, 1.9, { dur = 0.35, rise = 0.5, spin = -0.3, a = 0.7,
			color = { 1, 0.8, 0.45 } })
		sheen(out, "fire", 0.34)
	end,
	water = function(out)
		burst(out, "ring1", MEDIA .. "Ring-Soft", 0.9, 2.4, { dur = 0.5, a = 0.9 })
		burst(out, "ring2", MEDIA .. "Ring-Soft", 0.9, 2.4, { dur = 0.5, a = 0.7, delay = 0.16 })
		burst(out, "shape1", shapeFile("water"), 1.1, 2.8, { dur = 0.6, delay = 0.05 }, false, true)
		sheen(out, "water", 0.34)
	end,
	air = function(out)
		burst(out, "shape1", shapeFile("air"), 1.0, 3.2, { dur = 0.6, spin = -2.1 }, false, true)
		burst(out, "shape2", shapeFile("air"), 0.8, 2.0, { dur = 0.45, spin = -1.6, a = 0.5, color = { 1, 1, 1 } })
		sheen(out, "air", 0.24)
	end,
	spirit = function(out)
		burst(out, "ring1", MEDIA .. "Ring-Soft", 2.8, 1.0, { dur = 0.26, a = 0.9, slow = true })
		burst(out, "shape1", shapeFile("spirit"), 0.9, 3.2, { dur = 0.5, spin = 0.6, delay = 0.22 }, false, true)
		burst(out, "spark", MEDIA .. "Spark", 0.4, 1.6, { dur = 0.4, a = 0.9, delay = 0.22 }, true)
	end,
}

local POP = "General > Pop style"
S.addField("pop", "colorBy", { name = "Colour", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "colorBy", "event", { name = "By event" })
S.addChoice("pop", "colorBy", "school", { name = "By school", bySchool = true })

S.addField("pop", "flash", { name = "Flash", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "flash", "none", { name = "None" })
S.addChoice("pop", "flash", "plain", { name = "Plain flash", uses = { colorBy = true } })
S.addChoice("pop", "flash", "edge", { name = "Blizzard's edge flash", uses = { colorBy = true } })

S.addField("pop", "burst", { name = "Burst", where = POP, preview = { play = "hover" },
	groups = { { "plain", "Plain" }, { "element", "Element" }, { "other", "Other" } } })
local function addBurst(key, entry)
	if entry.rigParts or entry.draw then entry.uses = { colorBy = true, reach = true } end
	S.addChoice("pop", "burst", key, entry)
end
addBurst("none", { name = "None", group = "plain" })
addBurst("ring", { name = "Ring", group = "plain", rigParts = { "ring" } })
addBurst("star", { name = "Star", group = "plain", rigParts = { "star" } })
addBurst("both", { name = "Ring and star", group = "plain", rigParts = { "ring", "star" } })
addBurst("painted", { name = "Emblem", group = "element", bySchool = true, credit = "ai",
	tip = "An element's symbol spreads out behind the icon.",
	draw = shapes(function(school) return MEDIA .. "Burst-" .. (SCHOOLS[school] or "Spirit") end, 3.2) })
addBurst("school", { name = "Element effect", group = "element", bySchool = true,
	tip = "Each element its own effect: earth slams, fire flares, water ripples, air spins, spirit gathers.",
	draw = function(out, school)
		disc(out, 3.0, 0.6)
		local effect = EFFECTS[school] or EFFECTS.spirit
		effect(out)
	end })
addBurst("rune", { name = "Rune circle", group = "other",
	draw = function(out)
		disc(out, 2.6, 0.6)
		burst(out, "shape1", MEDIA .. "Rune-Ring", 1.05, 2.6, { dur = 0.62, spin = 0.55 }, false, true)
		burst(out, "spark", MEDIA .. "Spark", 1.2, 2.2, { dur = 0.35, a = 0.8, color = { 1, 1, 1 } }, true)
	end })
-- Emblem in flat drawn art: kept for a saved value.
addBurst("shapes", { name = "Shapes", group = "element", hidden = true, bySchool = true, draw = shapes(shapeFile, 3.0) })

S.addField("pop", "motion", { name = "Motion", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "motion", "none", { name = "None" })
for _, m in ipairs({ { "pop", "Grow" }, { "bounce", "Bounce" }, { "hop", "Hop" }, { "shake", "Shake side to side" },
	{ "shakeV", "Shake up and down" } }) do
	S.addChoice("pop", "motion", m[1], { name = m[2], uses = { size = true } })
end

-- The parts of the drawn burst named key for an icon of school; nil for a burst that draws none
-- (ns.Effects' own ring and star, or none). Made once each: the same table every time, never
-- changed.
local popParts = {}
function Looks.popParts(key, school)
	local draw = S.choice("pop", "burst", key).draw
	if not draw then return nil end
	local id = key .. ":" .. tostring(school)
	if not popParts[id] then
		popParts[id] = {}
		draw(popParts[id], school)
	end
	return popParts[id]
end

-- The events whose pop takes the style's Colour (by event or by school): Ready, and a totem that
-- ran out (the totem bar's pops, and the totem elements'). Killed early, Grounded and the imbue
-- dropping are warnings: their pops keep their own colours.
Looks.POP_EVENTS = { ready = true, expired = true }

-- The school f's looks take (its border's school colour), and the one its pop's colour by school,
-- drawn bursts and School material glow take.
Looks.schoolOf, Looks.effectSchool = schoolOf, effectSchool

-- Blizzard's cooldown-done flash, a light running round the edge, made stronger than Blizzard draws
-- it (too faint at 44, tested 2026-09-28): added, and a second copy a little larger. Its two
-- textures on parent, each { tex, group, grow }: group.flip and group.show (its FlipBook, and the
-- Alpha that shows it while it plays) are timed by the caller, and grow is its size over the
-- icon's. nil on a client without the art: the pop's plain flash stands in.
function Looks.popEdge(parent)
	if not Looks.hasAtlas(GCD_FLASH) then return nil end
	local out = {}
	for i, grow in ipairs({ 1, 1.15 }) do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
		t:SetAtlas(GCD_FLASH)
		t:SetDesaturated(true)
		t:SetBlendMode("ADD")
		t:SetPoint("CENTER", parent, "CENTER", 0, 1)
		out[i] = { tex = t, group = flipBook(t, 11, 2, 22, 0.75), grow = grow }
	end
	return out
end
