-- Style art: each part's styles and the art they draw
-- Our own media by path, never file ID; Blizzard's art by atlas, checked before use.

local ADDON, ns = ...

local SA = {}
ns.StyleArt = SA

local S = ns.Style
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Looks\\"
local WHITE = ns.WHITE
local CLAMP = "CLAMPTOBLACKADDITIVE"   -- a mask's wrap mode, as Blizzard's own masks use
local STRETCHED = Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0

local atlasKnown = {}
function SA.hasAtlas(name)
	if atlasKnown[name] == nil then
		atlasKnown[name] = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) ~= nil
	end
	return atlasKnown[name]
end

local THEME = ns.THEME

local function schoolOf(f)
	if f.over then f = f.over end
	if f.school then return f.school end
	local e = type(f.owner) == "string" and ns.Elements.ALL[f.owner]
	return e and e.school or THEME.fallback
end

function SA.elementSchool(key, own)
	local e = ns.Elements.ALL[key]
	if not e then return THEME.fallback end
	if not own and ns.Profiles.getDB and ns.Profiles.getDB() then
		local pick = ns.Elements.setting(key, "popSchool")
		if THEME.color[pick] then return pick end
	end
	return e.ownSchool and e.ownSchool() or e.school or THEME.fallback
end
local function effectSchool(f)
	if f.over then f = f.over end
	if f.school then return f.school end
	return type(f.owner) == "string" and SA.elementSchool(f.owner) or THEME.fallback
end

-- Frames
local SIDES = { "top", "bottom", "left", "right" }
local CORNERS = { { "TOPLEFT", -1, 1 }, { "TOPRIGHT", 1, 1 }, { "BOTTOMLEFT", -1, -1 }, { "BOTTOMRIGHT", 1, -1 } }
local BLACK = { 0, 0, 0, 1 }

local schoolColors = {}
local function colorOf(c, b, f)
	if c == "school" then
		local school = f and schoolOf(f) or THEME.fallback
		local k = schoolColors[school]
		if not k then
			local sc = THEME.color[school] or THEME.color[THEME.fallback]
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

function SA.uses(look, field) return look.uses ~= nil and look.uses[field] == true end

-- Each ring is four textures; returns how far the rings reach.
local function drawRings(f, rings, b)
	f.border = f.border or {}
	local tex, n, d = f.border, 0, 0
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

local function setArt(t, art)
	if art.atlas then t:SetAtlas(art.atlas) else t:SetTexture(art.file) end
end

local function placeArt(t, art, over, w)
	local i = art.inset
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", over, "TOPLEFT", -i[1] * w, i[3] * w)
	t:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", i[2] * w, -i[4] * w)
end

-- On f itself: over the picture, under its swipe, timers and text.
local function drawOverlay(f, art)
	local t = f.frameOverlay
	if not art or art.margin or f.noOverlay or (art.atlas and not SA.hasAtlas(art.atlas)) then
		if t then t:Hide() end
		return
	end
	if not t then
		t = f:CreateTexture(nil, "OVERLAY", nil, 7)
		f.frameOverlay = t
	end
	local w = f:GetWidth()
	if ns.isSecret(w) then return end   -- secret under a secure button: next layout
	placeArt(t, art, f, w)
	setArt(t, art)
	t:Show()
end

-- A 9-slice frame round the icon, outside its edge; returns how far it reaches.
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
	if k <= 0 then h:Hide(); return 0 end   -- SetScale refuses 0
	h:SetScale(k)
	-- Anchored, not sized (f's size can be secret); offsets are in h's scale
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", f, "TOPLEFT", -art.margin, art.margin)
	h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", art.margin, -art.margin)
	h:SetFrameLevel(f:GetFrameLevel())
	h.tex:SetTexture(art.file)
	h.tex:SetTextureSliceMargins(art.margin, art.margin, art.margin, art.margin)
	h.tex:SetTextureSliceMode(STRETCHED)
	h:Show()
	return px
end

local NO_ART = { rings = { { color = BLACK } } }
local function artMissing(look)
	local a, m = look.art and look.art.atlas, look.mask and look.mask.atlas
	return (a and not SA.hasAtlas(a)) or (m and not SA.hasAtlas(m)) or false
end

local function maskOf(look)
	local m = look.mask
	if m and m.atlas and not SA.hasAtlas(m.atlas) then return nil end
	return m
end
local function lookFor(b)
	local look = b and b.show and S.look("border", b.look)
	if look and artMissing(look) then return NO_ART end
	return look or nil
end
local function maskFor(b)
	local look = lookFor(b)
	return look and maskOf(look) or nil
end
local function artFor(b)
	local look = lookFor(b)
	return look and look.art and not look.art.margin and look.art or nil
end

local function placeMask(m, spec, over, w, h)
	if spec.atlas then m:SetAtlas(spec.atlas, false, nil, nil, CLAMP, CLAMP)
	else m:SetTexture(spec.file, spec.wrap or CLAMP, spec.wrap or CLAMP) end
	m:ClearAllPoints()
	-- A secret size (a secure button's) can't be scaled: the mask fits the picture exactly.
	if (spec.scale or 1) == 1 or ns.isSecret(w) or ns.isSecret(h) then m:SetAllPoints(over)
	else
		m:SetPoint("CENTER", over, "CENTER", 0, 0)
		m:SetSize(w * spec.scale, (h or w) * spec.scale)
	end
end

local followers = setmetatable({}, { __mode = "k" })
local ownShape = setmetatable({}, { __mode = "k" })
local maskSpecs = setmetatable({}, { __mode = "k" })

local function maskOne(f, tex, spec, over)
	if not tex then return end
	f.frameMasks = f.frameMasks or {}
	local m = f.frameMasks[tex]
	if spec then
		if not m then
			m = tex:GetParent():CreateMaskTexture()
			f.frameMasks[tex] = m
		end
		-- over's size on screen, for a texture on a scaled frame
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

function SA.maskOver(f, tex, over)
	local map = ownShape[f] or {}
	ownShape[f] = map
	map[tex] = over or tex
	if maskSpecs[f] then maskOne(f, tex, maskSpecs[f], map[tex]) end
end

function SA.followMask(f, ...)
	local list = followers[f] or {}
	followers[f] = list
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		table.insert(list, t)
		if maskSpecs[f] then maskOne(f, t, maskSpecs[f], f.tex or f.icon) end
	end
end

local swipers = setmetatable({}, { __mode = "k" })
local swipeLooks = setmetatable({}, { __mode = "k" })

-- w: the width when known (secret on Blizzard's aura button), else read.
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

local function drawSwipe(f, look)
	if look == nil and swipeLooks[f] == nil then return end
	swipeLooks[f] = look
	swipeOne(f, f.cd, look)
	for _, cd in ipairs(swipers[f] or {}) do swipeOne(f, cd, look) end
end

function SA.followSwipe(f, cd)
	local list = swipers[f] or {}
	swipers[f] = list
	table.insert(list, cd)
	if swipeLooks[f] then swipeOne(f, cd, swipeLooks[f]) end
end

-- Parts that fit a bar; a style with neither draws a plain line there.
local barLooks = {}
local function barParts(look)
	local v = barLooks[look]
	if not v then
		local slice = look.art and look.art.margin and look.art or nil
		v = (look.rings or slice) and { rings = look.rings, art = slice } or NO_ART
		barLooks[look] = v
	end
	return v
end

local function drawnLook(b, shape)
	local look = S.look("border", b and b.look)
	if artMissing(look) then look = NO_ART end
	local on = b and b.show and (not SA.uses(look, "size") or (b.size and b.size > 0))
	if not on then return nil end
	return shape == "bar" and barParts(look) or look
end

function SA.inset(f, b, w, shape)
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
	return math.min(out, math.max((w - 4) / 2, 0))
end

function SA.fit(f, b, w, h, opts)
	local host, shape = opts and opts.borderHost or f, opts and opts.shape
	local o = SA.inset(host, b, math.min(w, h or w), shape)
	f:SetSize(w - 2 * o, (h or w) - 2 * o)
	SA.applyBorder(host, b, shape)
	if host ~= f then
		-- The mask and swipe belong to the picture, not to the border's part.
		local look = drawnLook(b, shape)
		local mask = look and maskOf(look)
		drawMask(f, mask)
		drawSwipe(f, mask and look)
		f.frameOuter = host.frameOuter
	end
	return o
end

function SA.overlay(f, b, shape)
	local look = drawnLook(b, shape)
	drawOverlay(f, look and look.art)
end

function SA.applyBorder(f, b, shape)
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

function SA.outerEdge(f) return f and f.frameOuter or 0 end

-- Blizzard's aura button takes a mask only when made as it is built, so each gets one there;
-- SA.auraStyle restyles it out of combat.
local PLAIN_MASK = { file = WHITE, wrap = "CLAMP" }
local auraMade = setmetatable({}, { __mode = "k" })
function SA.auraMask(host, tex, key)
	local b = ns.Elements.borderFor(key)
	local spec, art, size = maskFor(b), artFor(b), ns.Elements.sizeOf(key)
	local made = { key = key, spec = spec, look = spec and lookFor(b), art = art }
	auraMade[tex] = made
	if art then
		local t = host:CreateTexture(nil, "OVERLAY", nil, 7)
		setArt(t, art)
		placeArt(t, art, host, size)
		made.artTex = t
	end
	local m = host:CreateMaskTexture()
	placeMask(m, spec or PLAIN_MASK, tex, size)
	tex:AddMaskTexture(m)
	made.mask = m
end

function SA.auraStyle(slot, size)
	local made = slot.icon and auraMade[slot.icon]
	if not made then return end
	local host = slot.host
	local b = ns.Elements.borderFor(made.key)
	local art, spec = artFor(b), maskFor(b)
	if art ~= made.art then
		if art and not made.artTex then made.artTex = host:CreateTexture(nil, "OVERLAY", nil, 7) end
		local t = made.artTex
		if art then
			setArt(t, art)
			t:Show()
		elseif t then t:Hide() end
		made.art = art
	end
	if made.artTex and made.art then placeArt(made.artTex, made.art, host, size) end
	if made.mask then placeMask(made.mask, spec or PLAIN_MASK, slot.icon, size) end
	made.spec = made.mask and spec or nil
	made.look = made.spec and lookFor(b) or nil
	swipeOne(host, slot.cd, made.look, size)
end

-- Frame styles
local GOLD = { 0.71, 0.55, 0.29, 1 }
SA.GOLD = GOLD
local BRONZE_HI, BRONZE_LO, BRONZE_DARK = { 0.85, 0.68, 0.39, 1 }, { 0.43, 0.29, 0.13, 1 }, { 0.10, 0.07, 0.03, 1 }
local CDM_MASK, CDM_OVERLAY = "UI-HUD-CoolDownManager-Mask", "UI-HUD-CoolDownManager-IconOverlay"
local CDM_SWIPE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local AB_MASK, AB_FRAME = "UI-HUD-ActionBar-IconFrame-Mask", "UI-HUD-ActionBar-IconFrame"

S.addField("border", "look", { name = "Border style", where = "Global settings > Border style", preview = { play = "still" },
	groups = { { "lines", "Lines" }, { "blizzard", "Blizzard's" }, { "painted", "Painted" } } })
S.addLook("border", "line", { name = "Line", group = "lines", uses = { size = true, color = true },
	rings = { { px = "size", color = "color" } } })
S.addLook("border", "hairline", { name = "Gold hairline", group = "lines",
	rings = { { color = BLACK }, { color = GOLD }, { color = BLACK } } })
S.addLook("border", "bevel", { name = "Bronze bevel", group = "lines", uses = { size = true },
	rings = { { color = BLACK }, { px = "size", top = BRONZE_HI, left = BRONZE_HI, bottom = BRONZE_LO, right = BRONZE_LO },
		{ color = BRONZE_DARK } } })
S.addLook("border", "caps", { name = "Corner caps", group = "lines",
	uses = { size = true, color = true, capSize = true, capColor = true },
	rings = { { px = "size", color = "color" } }, caps = { px = "capSize", len = 6, color = "capColor" } })
S.addLook("border", "cdm", { name = "Cooldown Manager", group = "blizzard",
	mask = { atlas = CDM_MASK }, swipe = CDM_SWIPE, art = { atlas = CDM_OVERLAY, inset = { 0.18, 0.18, 0.16, 0.16 } } })
S.addLook("border", "button", { name = "Forever action button", group = "blizzard",
	mask = { atlas = AB_MASK, scale = 64 / 45 }, swipeInset = 3 / 45,
	art = { atlas = AB_FRAME, inset = { 0, 1 / 45, 0, 0 } } })
S.addLook("border", "stone", { name = "Carved stone", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Stone", margin = 27, px = 6 } })
S.addLook("border", "bronze", { name = "Aged bronze", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Bronze", margin = 14, px = 4 } })
S.addLook("border", "wood", { name = "Carved wood", group = "painted", credit = "ai",
	rings = { { color = BLACK } }, art = { file = MEDIA .. "Frame-Wood", margin = 22, px = 6 } })
S.addLook("border", "schooledge", { name = "School edge", group = "lines", hidden = true, bySchool = true,
	uses = { size = true }, rings = { { color = BLACK }, { px = "size", color = "school" } } })
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
S.addLook("border", "medallion", { name = "Medallion", group = "painted", hidden = true, credit = "ai",
	mask = { file = ROUND }, swipe = ROUND, art = { file = MEDIA .. "Medallion", inset = { 0.35, 0.35, 0.35, 0.35 } } })

-- Glow styles
local GOLD_GLOW = { 1, 0.8, 0.25 }
local ACTIVE_GLOW = "UI-CooldownManager-ActiveGlow"
local PROC_START, PROC_LOOP = "UI-HUD-ActionBar-Proc-Start-Flipbook", "UI-HUD-ActionBar-Proc-Loop-Flipbook"

local function root(parent)
	local r = CreateFrame("Frame", nil, parent)
	r:SetAllPoints()
	r:EnableMouse(false)
	return r
end
-- Re-levels the style on each show: levels move as an icon regroups.
function SA.levelParts(parts)
	for _, r in ipairs(parts.roots or {}) do
		local lv = r:GetParent():GetFrameLevel()
		r:SetFrameLevel(lv)
		for _, c in ipairs({ r:GetChildren() }) do c:SetFrameLevel(lv) end
	end
end
local function light(c) return c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5 end

local function anim(region, kind, looping)
	local g = region:CreateAnimationGroup()
	if looping then g:SetLooping(looping) end
	return g, g:CreateAnimation(kind)
end
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
	if not (size and size > 0) then return end   -- not laid out: SetScale refuses 0
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

-- A style made of Blizzard's atlases, drawn as the soft style on a client that lacks one
local function orSoft(look, ...)
	local atlases, build, style, fit = { ... }, look.build, look.style, look.fit
	function look.build(g)
		for _, a in ipairs(atlases) do
			if not SA.hasAtlas(a) then
				local parts = soft.build(g)
				parts.fallback = true
				return parts
			end
		end
		return build(g)
	end
	function look.style(g, parts, st, c)
		if parts.fallback then return soft.style(g, parts, st, c) end
		return style(g, parts, st, c)
	end
	function look.fit(g, parts, size, out)
		if parts.fallback then return soft.fit(g, parts, size) end
		return fit(g, parts, size, out)
	end
	return look
end

local halo = orSoft({
	uses = { color = true, speed = true, low = true },
	build = function(g)
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
		parts.halo:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		parts.scale:SetDuration(st.speed)
	end,
	fit = function(g, parts, size, out)
		local d = out + size * 0.24
		parts.halo:ClearAllPoints()
		parts.halo:SetPoint("TOPLEFT", g, "TOPLEFT", -d, d)
		parts.halo:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", d, -d)
	end,
}, ACTIVE_GLOW)

-- Blizzard's proc glow; under the aura button only its ring (the burst needs a script).
local proc = orSoft({
	uses = { color = true }, steady = true,
	build = function(g)
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
		local own = not g.fixed and c[1] == GOLD_GLOW[1] and c[2] == GOLD_GLOW[2] and c[3] == GOLD_GLOW[3]
		for _, t in ipairs(parts.texs) do
			t:SetDesaturated(not own)
			if own then t:SetVertexColor(1, 1, 1, c[4] or 1) else t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
		end
	end,
	fit = function(g, parts, size, out)
		local s = size + 2 * out
		if parts.start then
			parts.start:SetSize(s * 150 / 45, s * 150 / 45)
			parts.start:SetPoint("CENTER", g, "CENTER", 0, 0)
		end
		parts.loop:SetSize(s * 1.4, s * 1.4)
		parts.loop:SetPoint("CENTER", g, "CENTER", 0, 0)
	end,
}, PROC_START, PROC_LOOP)

local SPARK_PATH = { { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 1 } }
local spark = {
	uses = { color = true, lap = true, width = true }, steady = true,
	fields = { lap = { name = "Lap time", tip = "One lap round the icon.", format = "%.1f s" } },
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

-- The school's texture drifting inside the glow's mask.
local function materialOf(school) return THEME.material[school] or THEME.material[THEME.fallback] end
local function materialLayout(g, parts)
	local size = parts.size
	if not (size and parts.pattern) then return end
	local mv = materialOf(parts.school).move
	local tile = size * parts.pattern
	local side = size + 2 * tile
	local cover = side / tile
	for i, t in ipairs(parts.tex) do
		t:SetSize(side, side)
		t:ClearAllPoints()
		t:SetPoint("CENTER", g, "CENTER", 0, 0)
		t:SetTexCoord(0, cover, 0, cover)
		parts.moves[i]:SetOffset(mv[1] * tile, mv[2] * tile)
	end
end
local material = {
	uses = { color = true, strength = true, width = true }, bySchool = true, inside = true, steady = true,
	fields = {
		scale = { name = "Pattern size", tip = "How big the pattern is.", format = "%.1fx" },
		drift = { name = "Drift speed", tip = "How fast the pattern moves.", format = "%.2fx" },
		width = { name = "Rim", tip = "How far in the edge glow reaches.",
			format = function(v) return string.format("%d%%", v * 100 + 0.5) end },
	},
	build = function(g)
		local r = root(g.inner)
		local parts = { roots = { r }, soft = softPart(r, 0.6), tex = {}, moves = {}, anims = {}, aura = {}, moving = { r } }
		local m = r:CreateMaskTexture()
		m:SetTexture(MEDIA .. "Glow-Inner", CLAMP, CLAMP)
		m:SetAllPoints(g)
		for i = 1, 2 do
			local t = r:CreateTexture(nil, "OVERLAY", nil, i)
			t:SetBlendMode("ADD")
			t:AddMaskTexture(m)
			local drift, a = anim(t, "Translation", "REPEAT")
			parts.tex[i], parts.moves[i] = t, a
			table.insert(parts.anims, drift)
			table.insert(parts.aura, drift)
		end
		return parts
	end,
	style = function(g, parts, st, c)
		local k = st.strength or 1
		styleSoft(parts.soft, c)
		local school = effectSchool(g)
		parts.school = school
		parts.pattern = st.scale
		local mat = materialOf(school)
		local file = MEDIA .. mat.file
		local alpha = { math.min(k, 1), math.min(math.max(k - 1, 0), 1) }
		for i, t in ipairs(parts.tex) do
			t:SetTexture(file, "REPEAT", "REPEAT")
			t:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * alpha[i])
			t:SetShown(alpha[i] > 0)
			parts.moves[i]:SetDuration(mat.move[3] / math.max(st.drift or 1, 0.1))
		end
		materialLayout(g, parts)
	end,
	fit = function(g, parts, size)
		fitSoft(g, parts.soft, size, g.width)
		parts.size = size
		materialLayout(g, parts)
	end,
}

local BEAT_IN = 0.15   -- the share of a beat the ring takes to fade in
local heartbeat = {
	uses = { color = true, speed = true, low = true, width = true },
	build = function(g)
		local r, o = root(g.inner), root(g)
		local ring = o:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(MEDIA .. "Glow-Outer")
		ring:SetBlendMode("ADD")
		ring:SetAlpha(0)
		local beat = ring:CreateAnimationGroup()
		beat:SetLooping("REPEAT")
		local s = beat:CreateAnimation("Scale")
		s:SetScaleFrom(0.9, 0.9); s:SetScaleTo(1.65, 1.65); s:SetSmoothing("OUT")
		local up = beat:CreateAnimation("Alpha")
		up:SetFromAlpha(0); up:SetToAlpha(0.9); up:SetSmoothing("OUT")
		local down = beat:CreateAnimation("Alpha")
		down:SetFromAlpha(0.9); down:SetToAlpha(0); down:SetSmoothing("OUT")
		return { roots = { r, o }, soft = softPart(r, 0.6), ring = ring, beat = { s, up, down }, anims = { beat },
			aura = { beat }, moving = { o }, paced = true }
	end,
	style = function(g, parts, st, c)
		styleSoft(parts.soft, c)
		parts.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		local len = st.speed * 2
		local s, up, down = unpack(parts.beat)
		s:SetDuration(len)
		up:SetDuration(len * BEAT_IN)
		down:SetStartDelay(len * BEAT_IN); down:SetDuration(len * (1 - BEAT_IN))
	end,
	fit = function(g, parts, size, out)
		fitSoft(g, parts.soft, size, g.width)
		local s = (size + 2 * out) / 0.68   -- the texture's hollow is 68% of it
		parts.ring:SetSize(s, s)
		parts.ring:SetPoint("CENTER", g, "CENTER", 0, 0)
	end,
}

S.addField("glow", "look", { name = "Glow style", where = "Global settings > Pulsing glow style", preview = { play = "loop" } })
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

-- Pop styles
-- A drawn burst is a list of parts: from/to and rise in icon heights, dur/delay in seconds.
local GCD_FLASH = "UI-HUD-ActionBar-GCD-Flipbook"
local HALO_SCALE, HALO_ALPHA = 1.08, 0.6

SA.POP_PARTS = { disc = "back", shape1 = "back", shape1Dark = "back", shape2 = "back", ring1 = "back",
	ring2 = "back", spark = "front", sheen = "clip" }

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
local function disc(out, to, dur, delay)
	table.insert(out, { name = "disc", file = MEDIA .. "Disc-Dark", layer = "BACKGROUND", sub = -1, dark = true,
		from = to * 0.55, to = to * 0.95, dur = dur * 1.1, delay = delay, a = 0.75, slow = true })
end
local function shapeOf(school) return THEME.shape[school] or THEME.shape[THEME.fallback] end
local function sheen(out, school, dur, delay)
	table.insert(out, { name = "sheen", file = MEDIA .. "Sheen", layer = "OVERLAY", add = true, dur = dur,
		delay = delay, a = 0.9, shift = shapeOf(school).sheenDir })
end
local function shapeFile(school) return MEDIA .. shapeOf(school).file end

local function shapes(file, to)
	return function(out, school)
		disc(out, 3.0, 0.5)
		burst(out, "shape1", file(school), 1.0, to, { dur = 0.5, spin = shapeOf(school).spin }, false, true)
		sheen(out, school, 0.34)
	end
end

local function effect(out, school)
	local spec = THEME.burst[school] or THEME.burst[THEME.fallback]
	for _, part in ipairs(spec.parts) do
		local file = part.art == "shape" and shapeFile(school) or MEDIA .. part.art
		burst(out, part.name, file, part.from, part.to, part, part.front, part.dark)
	end
	if spec.sheen then sheen(out, school, spec.sheen.dur, spec.sheen.delay) end
end

local POP = "Global settings > Pop style"
S.addField("pop", "colorBy", { name = "Colour", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "colorBy", "event", { name = "By event" })
S.addChoice("pop", "colorBy", "school", { name = "By school", bySchool = true })

S.addField("pop", "flash", { name = "Flash", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "flash", "none", { name = "None" })
S.addChoice("pop", "flash", "plain", { name = "Plain flash", uses = { colorBy = true } })
S.addChoice("pop", "flash", "edge", { name = "Blizzard's edge flash", uses = { colorBy = true } })

S.addField("pop", "burst", { name = "Burst", where = POP, preview = { play = "hover" },
	groups = { { "plain", "Plain" }, { "element", THEME.axis.name }, { "other", "Other" } } })
local function addBurst(key, entry)
	if entry.rigParts or entry.draw then entry.uses = { colorBy = true, reach = true } end
	S.addChoice("pop", "burst", key, entry)
end
addBurst("none", { name = "None", group = "plain" })
addBurst("ring", { name = "Ring", group = "plain", rigParts = { "ring" } })
addBurst("star", { name = "Star", group = "plain", rigParts = { "star" } })
addBurst("both", { name = "Ring and star", group = "plain", rigParts = { "ring", "star" } })
addBurst("painted", { name = "Emblem", group = "element", bySchool = true, credit = "ai",
	tip = THEME.axis.one:gsub("^%l", string.upper) .. "'s symbol spreads out behind the icon.",
	draw = shapes(function(school) return MEDIA .. shapeOf(school).emblem end, 3.2) })
addBurst("school", { name = THEME.axis.name .. " effect", group = "element", bySchool = true,
	tip = THEME.burstTip,
	draw = function(out, school)
		disc(out, 3.0, 0.6)
		effect(out, school)
	end })
addBurst("rune", { name = "Rune circle", group = "other",
	draw = function(out)
		disc(out, 2.6, 0.6)
		burst(out, "shape1", MEDIA .. "Rune-Ring", 1.05, 2.6, { dur = 0.62, spin = 0.55 }, false, true)
		burst(out, "spark", MEDIA .. "Spark", 1.2, 2.2, { dur = 0.35, a = 0.8, color = { 1, 1, 1 } }, true)
	end })

S.addField("pop", "motion", { name = "Motion", where = POP, preview = { play = "hover" } })
S.addChoice("pop", "motion", "none", { name = "None" })
for _, m in ipairs({ { "pop", "Grow" }, { "bounce", "Bounce" }, { "hop", "Hop" }, { "shake", "Shake side to side" },
	{ "shakeV", "Shake up and down" } }) do
	S.addChoice("pop", "motion", m[1], { name = m[2], uses = { size = true } })
end

local popParts = {}
function SA.popParts(key, school)
	local draw = S.choice("pop", "burst", key).draw
	if not draw then return nil end
	local id = key .. ":" .. tostring(school)
	if not popParts[id] then
		popParts[id] = {}
		draw(popParts[id], school)
	end
	return popParts[id]
end

-- What a pop marks, and its colour; byStyle: the Pop style's Colour applies (not to warnings); tick:
-- an end flash of this kind (an early end of its own) shows a tick
SA.POP_KINDS = {
	ready = { color = { 1, 0.82, 0.25 }, byStyle = true },
	expired = { color = { 0.95, 0.95, 0.95 }, byStyle = true },
	lost = { color = { 0.35, 0.65, 1 } },
	killed = { color = { 1, 0.15, 0.1 } },
	blocked = { color = { 0.6, 0.6, 0.6 } },   -- ready but can't be cast
}
-- A class's own pop kind
function SA.addPopKind(key, spec) SA.POP_KINDS[key] = spec end

SA.effectSchool = effectSchool

-- Blizzard's cooldown-done flash, doubled to be seen; nil without the art.
function SA.popEdge(parent)
	if not SA.hasAtlas(GCD_FLASH) then return nil end
	local out = {}
	for i, grow in ipairs({ 1, 1.15 }) do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
		t:SetAtlas(GCD_FLASH)
		t:SetDesaturated(true)
		t:SetBlendMode("ADD")
		t:SetPoint("CENTER", parent, "CENTER", 0, 1)
		t:SetSize(1, 1)   -- unsized: the sheet's 2048 px
		t:Hide()
		out[i] = { tex = t, group = flipBook(t, 11, 2, 22, 0.75), grow = grow }
	end
	return out
end
