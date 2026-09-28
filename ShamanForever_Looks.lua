-- Looks: the ways the HUD's parts can be drawn, each a data entry in ns.Style (S.addLook) that a
-- style's `look` field picks, and the shared pieces that draw them:
--   frame      the edge around an icon, in its border's look (rings of lines, corner caps, art
--              over or around the icon, a mask on the icon's picture)
--   burster    textures that grow and fade over a pop's short life
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

-- The school whose colour a frame's "school" parts take: the frame's own (a totem bar slot's),
-- else its element's (element icons and their previews carry the element's key as owner).
local function schoolOf(f)
	if f.school then return f.school end
	local e = type(f.owner) == "string" and ns.ELEMENTS[f.owner]
	return e and e.school or "spirit"
end
Looks.schoolOf = schoolOf

------------------------------------------------------------------------
-- Frames: a border look's entry has any of these parts (the options also read name, S.addLook).
--   rings  lines round the icon's edge, listed outside in. Each is { px, color }, or has a colour
--          per side (top, bottom, left, right) in place of color. px: screen pixels (default 1) or
--          "size" for the Border size setting. A colour is { r, g, b, a }, "setting" for the
--          Border colour setting, or "school" for the element's school colour.
--   caps   { px, len, color }: an L on each corner, px thick, reaching 1 px beyond the rings, its
--          arms running len along the icon's edges past the corner (screen pixels).
--   art    Blizzard's or our art: { atlas or file, inset } drawn stretched over the icon, inset
--          { left, right, top, bottom } past each edge as a share of the icon's width; or { file,
--          margin, px } drawn as a 9-slice round the icon, whose margin (texels) lands on px whole
--          screen pixels.
--   mask   { atlas or file, scale } for the icon's picture and what covers it (its size over the
--          picture's, centred; default 1).
--   swipe  a file for the icon's cooldown swipe (f.cd), shaped like the mask.
--   experimental  not tested in game yet (the options badge it); ai  AI-made art (credited).
-- Lines and caps are screen pixels (ns.linePx): crisp, grown by Scale, not by icon Size. They sit
-- outside the icon's edge, so they never cover the rings inside it or Blizzard's aura button.
------------------------------------------------------------------------
local SIDES = { "top", "bottom", "left", "right" }
local CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
local BLACK = { 0, 0, 0, 1 }

local function colorOf(c, b, school)
	if c == "setting" then return b.color or BLACK end
	if c == "school" then return ns.SCHOOL_COLOR[school] or ns.SCHOOL_COLOR.spirit end
	return c
end

-- Whether a look uses a border setting ("size" or "color"): the options show only those it uses.
function Looks.uses(look, part)
	for _, r in ipairs(look.rings or {}) do
		if part == "size" and r.px == "size" then return true end
		if part == "color" and r.color == "setting" then return true end
	end
	return part == "color" and look.caps ~= nil and look.caps.color == "setting"
end

-- Each ring is four textures: top and bottom span the corners, left and right fill between them.
-- Drawn inside out; returns how far the rings reach outside the icon's edge.
local function drawRings(f, rings, b, school)
	f.border = f.border or {}
	local tex, n, d = f.border, 0, 0   -- d: how far out this ring starts
	for i = #(rings or {}), 1, -1 do
		local ring = rings[i]
		local w = ns.linePx(f, ring.px == "size" and b.size or ring.px or 1)
		local o = d + w
		for _, side in ipairs(SIDES) do
			n = n + 1
			local t = tex[n] or f:CreateTexture(nil, "BACKGROUND", nil, -8)
			tex[n] = t
			local c = colorOf(ring[side] or ring.color, b, school)
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
-- reach beyond them.
local function drawCaps(f, caps, out, b, school)
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
	local px, beyond = ns.linePx(f, caps.px or 2), ns.linePx(f, 1)
	local o = out + beyond
	local len = o + ns.linePx(f, caps.len or 6)
	local c = colorOf(caps.color, b, school)
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
	return beyond
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
	local w, i = f:GetWidth(), art.inset
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", f, "TOPLEFT", -i[1] * w, i[3] * w)
	t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", i[2] * w, -i[4] * w)
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
	h:SetScale(k)
	h:SetSize((f:GetWidth() + 2 * px) / k, (f:GetHeight() + 2 * px) / k)
	h:ClearAllPoints()
	h:SetPoint("CENTER", f, "CENTER", 0, 0)
	h:SetFrameLevel(f:GetFrameLevel())
	h.tex:SetTexture(art.file)
	h.tex:SetTextureSliceMargins(art.margin, art.margin, art.margin, art.margin)
	h.tex:SetTextureSliceMode(STRETCHED)
	h:Show()
	return px
end

-- A look's mask, if the client has its art.
local function maskOf(look)
	local m = look.mask
	if m and m.atlas and not Looks.hasAtlas(m.atlas) then return nil end
	return m
end
-- The mask for a border style b (nil: none, or the border is off).
local function maskFor(b)
	return b and b.show and maskOf(S.look("border", b.look)) or nil
end

-- A mask texture's art and place: spec over the rect of `over` (the icon's picture), size its
-- width (a mask larger than the picture is centred on it).
local function placeMask(m, spec, over, size)
	if spec.atlas then m:SetAtlas(spec.atlas, false, nil, nil, CLAMP, CLAMP)
	else m:SetTexture(spec.file, CLAMP, CLAMP) end
	m:ClearAllPoints()
	if (spec.scale or 1) == 1 then m:SetAllPoints(over)
	else
		m:SetPoint("CENTER", over, "CENTER", 0, 0)
		m:SetSize(size * spec.scale, size * spec.scale)
	end
end

-- Textures other code lays over an icon's picture (the expiring warning's grey copy and dimming),
-- registered with Looks.followMask: they take the icon's mask too.
local followers = setmetatable({}, { __mode = "k" })   -- icon frame -> { texture, ... }
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
		placeMask(m, spec, over, over:GetWidth())
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

-- The icon's cooldown swipe in the look's shape; only touched once a look has asked for one.
local function drawSwipe(f, file)
	local cd = f.cd
	if not cd or (file == nil and f.frameSwipe == nil) then return end
	file = file or WHITE
	if f.frameSwipe ~= file then cd:SetSwipeTexture(file) end
	f.frameSwipe = file
end

-- Draws b (a border style) round f in its look, or takes it down (b off, or a size of 0 for a
-- look drawn at the Border size). Drawn just outside f's edge, so it never covers the rings inside
-- the icon or Blizzard's aura button; art and masks draw as each look says. Its lines are screen
-- pixels (ns.linePx), grown by Scale, not by icon Size. Sets f.frameOuter, how far it reaches
-- outside f's edge (f's units), for Looks.outerEdge.
function ns.applyBorder(f, b)
	local look = S.look("border", b and b.look)
	local on = b and b.show and (not Looks.uses(look, "size") or (b.size and b.size > 0))
	if not on then
		drawRings(f, nil, b, nil)
		drawCaps(f, nil)
		drawOverlay(f, nil)
		drawSlice(f, nil)
		drawMask(f, nil)
		drawSwipe(f, nil)
		f.frameOuter = 0
		return
	end
	local school = schoolOf(f)
	local out = drawRings(f, look.rings, b, school)
	out = out + drawCaps(f, look.caps, out, b, school)
	drawOverlay(f, look.art)
	out = math.max(out, drawSlice(f, look.art))
	local mask = maskOf(look)
	drawMask(f, mask)
	drawSwipe(f, mask and look.swipe)
	f.frameOuter = out
end

-- How far f's frame reaches outside its edge (f's units): where a glow or a pop that wraps the
-- frame starts, so a heavier frame doesn't cover it.
function Looks.outerEdge(f) return f and f.frameOuter or 0 end

-- Blizzard's aura button (the shield, Elemental Focus via ns.makeAuraSlot) takes a mask only when
-- it is made on the button while Blizzard makes the button (the slot's initializeFrame); one made
-- on our frames, or added later in combat, is refused (tested 2026-09-28). So a masked look's mask
-- is made there, from the element's border look at that moment. key: the element. Returns the
-- mask, or nil for a look without one. Adding a mask later out of combat, or changing its art, is
-- untested, so the button keeps the look it was made with until the next /reload.
local auraMade = setmetatable({}, { __mode = "k" })   -- aura icon -> { key, spec, mask, swipe }
function Looks.auraMask(button, tex, key)
	local b = ns.borderFor(key)
	local spec = maskFor(b)
	local made = { key = key, spec = spec, swipe = spec and S.look("border", b.look).swipe }
	auraMade[tex] = made
	if not spec then return end
	local m = button:CreateMaskTexture()
	placeMask(m, spec, tex, ns.sizeOf(key))
	tex:AddMaskTexture(m)
	made.mask = m
	return m
end

-- The aura slot's restyle (out of combat, auras readable; AuraSlot:style): the mask's size for a
-- mask larger than the picture, and the swipe in the mask's shape.
function Looks.auraStyle(slot, size)
	local made = slot.icon and auraMade[slot.icon]
	if not made or not made.spec then return end
	if made.mask and (made.spec.scale or 1) ~= 1 then placeMask(made.mask, made.spec, slot.icon, size) end
	if made.swipe and slot.cd then slot.cd:SetSwipeTexture(made.swipe) end
end

-- Whether an aura button's shape differs from its element's border look now: it changes after a
-- /reload (the options say so).
function Looks.auraStale()
	for _, made in pairs(auraMade) do
		if maskFor(ns.borderFor(made.key)) ~= made.spec then return true end
	end
	return false
end

------------------------------------------------------------------------
-- Frame looks. "line" is the default look.
------------------------------------------------------------------------
local GOLD = { 0.71, 0.55, 0.29, 1 }   -- the options window's gold
local BRONZE_HI, BRONZE_LO, BRONZE_DARK = { 0.85, 0.68, 0.39, 1 }, { 0.43, 0.29, 0.13, 1 }, { 0.10, 0.07, 0.03, 1 }
-- Blizzard's Cooldown Manager and action button art. The plain names draw Forever's bronze art
-- (tested 2026-09-28); the action button's mask is drawn 64 over a 45 icon, as Blizzard draws it.
local CDM_MASK, CDM_OVERLAY = "UI-HUD-CoolDownManager-Mask", "UI-HUD-CoolDownManager-IconOverlay"
local CDM_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local AB_MASK, AB_FRAME = "UI-HUD-ActionBar-IconFrame-Mask", "UI-HUD-ActionBar-IconFrame"

S.addLook("border", "line", { name = "Line", rings = { { px = "size", color = "setting" } } })
S.addLook("border", "hairline", { name = "Gold hairline",
	rings = { { color = BLACK }, { color = GOLD }, { color = BLACK } } })
S.addLook("border", "school", { name = "School edge",
	rings = { { color = BLACK }, { color = "school" } } })
-- Lit from the top left.
S.addLook("border", "bevel", { name = "Bronze bevel",
	rings = { { color = BLACK }, { top = BRONZE_HI, left = BRONZE_HI, bottom = BRONZE_LO, right = BRONZE_LO },
		{ color = BRONZE_DARK } } })
S.addLook("border", "caps", { name = "Corner caps",
	rings = { { px = "size", color = "setting" } }, caps = { px = 2, len = 6, color = BRONZE_HI } })
-- Rounded corners and a soft dark edge, as on the Cooldown Manager's icons.
S.addLook("border", "cdm", { name = "Cooldown Manager", experimental = true,
	mask = { atlas = CDM_MASK }, swipe = CDM_SWIPE, art = { atlas = CDM_OVERLAY, inset = { 0.18, 0.18, 0.16, 0.16 } } })
-- Cut corners in a dark bronze frame, as on Forever's action buttons.
S.addLook("border", "button", { name = "Forever action button", experimental = true,
	mask = { atlas = AB_MASK, scale = 64 / 45 }, art = { atlas = AB_FRAME, inset = { 0, 1 / 45, 0, 0 } } })
-- Painted frames (AI-made art), 9-sliced from 128 px: margins are the board's 21%, 11% and 17%.
S.addLook("border", "stone", { name = "Carved stone", experimental = true, ai = true,
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Stone", margin = 27, px = 6 } })
S.addLook("border", "bronze", { name = "Aged bronze", experimental = true, ai = true,
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Bronze", margin = 14, px = 4 } })
S.addLook("border", "wood", { name = "Carved wood", experimental = true, ai = true,
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Wood", margin = 22, px = 6 } })

-- Whether any of a kind's looks is experimental (About's list).
function Looks.anyExperimental(kind)
	for _, e in ipairs(S.LOOKS[kind].order) do if e.experimental then return true end end
	return false
end

------------------------------------------------------------------------
-- Burster: textures that grow, fade and turn frame by frame (the pop's ring and star), sized
-- directly, not by a Scale animation, so they never reach further than asked. driver: the frame
-- whose OnUpdate runs while any burst does. An added (ADD) burst vanishes on bright ground (tested
-- 2026-09-28: white bursts on snow); the glows and pops lane adds a halo for that, after its own
-- probe.
------------------------------------------------------------------------
function Looks.burster(driver)
	local B, run = {}, {}   -- run: texture -> { t (elapsed), dur, from, to (sizes), spin (radians) }
	local function step(self, elapsed)
		for tex, b in pairs(run) do
			b.t = b.t + elapsed
			local p = math.min(b.t / b.dur, 1)
			local e = 1 - (1 - p) * (1 - p)   -- ease out
			local size = b.from + (b.to - b.from) * e
			tex:SetSize(size, size)
			tex:SetAlpha(1 - p)
			if b.spin then tex:SetRotation(b.spin * e) end
			if p >= 1 then B.stop(tex) end
		end
		if next(run) == nil then self:SetScript("OnUpdate", nil) end
	end
	-- Starts a burst on tex (sized by the caller for its first frame).
	function B.play(tex, b)
		b.t = 0
		run[tex] = b
		tex:Show()
		driver:SetScript("OnUpdate", step)
	end
	function B.stop(tex)
		run[tex] = nil
		tex:Hide()
	end
	function B.clear()
		for tex in pairs(run) do B.stop(tex) end
		driver:SetScript("OnUpdate", nil)
	end
	return B
end
