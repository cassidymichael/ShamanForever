-- Looks: the ways the HUD's parts can be drawn, each a data entry in ns.Style (S.addLook) that a
-- style's `look` field picks, and the shared pieces that draw them:
--   frame      the edge around an icon, in its border's look (rings of lines, corner caps, art
--              over the icon in a holder frame, a mask on the icon's picture)
--   burster    textures that grow and fade over a pop's short life
-- Our own media are named by path, never by file ID: the client gives our loose files IDs that
-- change between client starts (tested 2026-09-28).

local _, ns = ...

local Looks = {}
ns.Looks = Looks

local S = ns.Style

------------------------------------------------------------------------
-- Frames: a border look's entry has any of these parts (the options also read name and
-- experimental, S.addLook).
--   rings  lines round the icon's edge, listed outside in. Each is { px, color }, or has a colour
--          per side (top, bottom, left, right) in place of color. px: screen pixels (default 1) or
--          "size" for the Border size setting. A colour is { r, g, b, a }, "setting" for the
--          Border colour setting, or "school" for the element's school colour.
--   caps   { px, len, color }: an L on each corner, px thick, reaching 1 px beyond the rings, its
--          arms running len along the icon's edges past the corner (screen pixels).
--   art    a texture over the icon in a holder frame of its own: { file or atlas, spread } drawn
--          stretched, spread (a share of the icon's width) past each edge; or { file, margin, px,
--          over } drawn as a 9-slice whose margin (texels) lands on px whole screen pixels, over
--          of them inside the icon's edge. level: its frame level above the icon's.
--   mask   a mask file for the icon's picture (f.tex).
-- Lines and caps are screen pixels (ns.linePx): crisp, grown by Scale, not by icon Size. They sit
-- outside the icon's edge, so they never cover the rings inside it or Blizzard's aura button.
------------------------------------------------------------------------
local SIDES = { "top", "bottom", "left", "right" }
local CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
local BLACK = { 0, 0, 0, 1 }
local STRETCHED = Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0

-- The school whose colour a frame's "school" parts take: the frame's own (a totem bar slot's),
-- else its element's (element icons and their previews carry the element's key as owner).
local function schoolOf(f)
	if f.school then return f.school end
	local e = type(f.owner) == "string" and ns.ELEMENTS[f.owner]
	return e and e.school or "spirit"
end

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
		local along, down = t[2 * i - 1], t[2 * i]   -- the arm along the top or bottom, the one down the side
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

-- Art over the icon, in a holder frame. A 9-slice's margin texel is drawn as one of its frame's
-- units (tested 2026-09-28), so the holder is scaled px over margin, px being whole screen pixels.
-- Its margins must stay under half its size, or the client draws the art as a plain stretch.
-- Returns how far the art reaches outside the icon's edge.
local function drawArt(f, art)
	local h = f.frameArt
	if not art then
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
	local w, ht = f:GetWidth(), f:GetHeight()
	local k, out = 1, (art.spread or 0) * w
	if art.margin then
		local px = ns.linePx(f, art.px)
		out = px - (art.over and ns.linePx(f, art.over) or 0)
		k = px / art.margin
	end
	h:SetScale(k)
	h:SetSize((w + 2 * out) / k, (ht + 2 * out) / k)
	h:ClearAllPoints()
	h:SetPoint("CENTER", f, "CENTER", 0, 0)
	h:SetFrameLevel(f:GetFrameLevel() + (art.level or 0))
	if art.atlas then h.tex:SetAtlas(art.atlas) else h.tex:SetTexture(art.file) end
	if art.margin or h.sliced then
		local m = art.margin or 0
		h.tex:SetTextureSliceMargins(m, m, m, m)
		h.tex:SetTextureSliceMode(STRETCHED)
		h.sliced = art.margin ~= nil
	end
	h:Show()
	return out
end

-- A mask on a texture, made on owner (the frame the texture belongs to).
function Looks.addMask(owner, tex, file)
	local m = owner:CreateMaskTexture()
	m:SetAllPoints(tex)
	m:SetTexture(file, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
	tex:AddMaskTexture(m)
	return m
end

-- Our icons take a mask, and let it go, at any time (tested 2026-09-28, in combat too).
local function drawMask(f, file)
	local tex = f.tex
	if not tex then return end
	if file then
		if not f.frameMask then f.frameMask = Looks.addMask(f, tex, file)
		else
			f.frameMask:SetTexture(file, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
			if not f.frameMaskOn then tex:AddMaskTexture(f.frameMask) end
		end
		f.frameMaskOn = true
	elseif f.frameMaskOn then
		tex:RemoveMaskTexture(f.frameMask)
		f.frameMaskOn = false
	end
end

-- Draws b (a border style) round f in its look, or takes it down (b off, or a size of 0 for a
-- look drawn at the Border size).
function Looks.frame(f, b)
	local look = S.look("border", b and b.look)
	local on = b and b.show and (not Looks.uses(look, "size") or (b.size and b.size > 0))
	if not on then
		drawRings(f, nil, b, nil)
		drawCaps(f, nil)
		drawArt(f, nil)
		drawMask(f, nil)
		return
	end
	local school = schoolOf(f)
	local out = drawRings(f, look.rings, b, school)
	drawCaps(f, look.caps, out, b, school)
	drawArt(f, look.art)
	drawMask(f, look.mask)
end

-- Blizzard's aura button (the shield, Elemental Focus via ns.makeAuraSlot) takes a mask only when
-- it is made on the button while Blizzard makes the button (the slot's initializeFrame); one made
-- on our frames, or added later in combat, is refused (tested 2026-09-28). So a masked look's mask
-- is made there, from the element's border look at that moment. key: the element. Returns the
-- mask, or nil for a look without one. Adding a mask later out of combat, or changing its art, is
-- untested, so the button keeps the look it was made with until the next /reload.
function Looks.auraMask(button, tex, key)
	local look = S.look("border", ns.borderFor(key).look)
	if look.mask then return Looks.addMask(button, tex, look.mask) end
end

------------------------------------------------------------------------
-- Frame looks. "line" is the default: the look every profile had before looks existed.
------------------------------------------------------------------------
local GOLD = { 0.71, 0.55, 0.29, 1 }   -- the options window's gold
local BRONZE_HI, BRONZE_LO, BRONZE_DARK = { 0.85, 0.68, 0.39, 1 }, { 0.43, 0.29, 0.13, 1 }, { 0.10, 0.07, 0.03, 1 }

S.addLook("border", "line", { name = "Line", rings = { { px = "size", color = "setting" } } })
S.addLook("border", "hairline", { name = "Gold hairline", experimental = true,
	rings = { { color = BLACK }, { color = GOLD }, { color = BLACK } } })
S.addLook("border", "school", { name = "School edge", experimental = true,
	rings = { { color = BLACK }, { color = "school" } } })
-- Lit from the top left.
S.addLook("border", "bevel", { name = "Bronze bevel", experimental = true,
	rings = { { color = BLACK }, { top = BRONZE_HI, left = BRONZE_HI, bottom = BRONZE_LO, right = BRONZE_LO },
		{ color = BRONZE_DARK } } })
S.addLook("border", "caps", { name = "Corner caps", experimental = true,
	rings = { { px = "size", color = "setting" } }, caps = { px = 2, len = 6, color = BRONZE_HI } })

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
