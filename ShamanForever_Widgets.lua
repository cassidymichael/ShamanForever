-- Widgets shared by the HUD, the totem bar and the options previews: the pulsing glow, the pop, the
-- end-of-totem flash and the element icon that carries them. Looks come from ns.Style; nothing here
-- reads settings of its own.

local _, ns = ...

-- The five element schools' colours (spirit covers anything mixed): time bars in "element colour",
-- the totem bar's slots, the options' art.
ns.SCHOOL_COLOR = {
	earth  = { 0.75, 0.54, 0.24 },
	fire   = { 0.89, 0.38, 0.18 },
	water  = { 0.25, 0.69, 0.77 },
	air    = { 0.56, 0.76, 0.92 },
	spirit = { 0.73, 0.64, 0.90 },
}

-- A flat backdrop: a solid fill and a 1 px edge, coloured by the caller.
ns.BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

-- A spell icon without Blizzard's built-in border.
function ns.cropIcon(tex) tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

-- The icon size text sizes are given at (the default): text on an icon scales with it from here.
ns.BASE_ICON_SIZE = 44
-- A font string on an icon: size at the base icon size (it grows and shrinks with the icon), placed
-- at a point of the icon (a corner, CENTER, or TOP / BOTTOM for text above or below it) with an
-- offset. Restated only when something changed; returns the font size used.
function ns.placeScaledText(fs, icon, size, point, x, y, relPoint)
	local px = math.max(math.floor(size * icon:GetWidth() / ns.BASE_ICON_SIZE + 0.5), 6)
	local sig = string.format("%d%s%s%s,%s", px, point, relPoint or point, x, y)
	if fs.placed == sig then return px end
	fs.placed = sig
	fs:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
	fs:ClearAllPoints()
	fs:SetPoint(point, icon, relPoint or point, x, y)
	return px
end

-- An element icon easing to a new opacity: slowly into idle, quickly back (each rate covers 0 to 1).
-- A frame above Blizzard's protected aura button (frame.aboveProtected) takes no alpha change in
-- combat, so its fade is dropped then and restated after combat by its owner's refresh.
local FADE_OUT, FADE_IN = 0.8, 0.15
local fading = {}   -- frame -> target alpha
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
	local combat = InCombatLockdown()
	for f, target in pairs(fading) do
		if combat and f.aboveProtected then fading[f] = nil
		else
			local a = f:GetAlpha()
			if target < a then a = math.max(target, a - elapsed / FADE_OUT)
			else a = math.min(target, a + elapsed / FADE_IN) end
			f:SetAlpha(a)
			if a == target then fading[f] = nil end
		end
	end
	if next(fading) == nil then self:Hide() end
end)
function ns.fadeTo(f, alpha)
	if f.aboveProtected and InCombatLockdown() then return end
	if math.abs(f:GetAlpha() - alpha) < 0.005 then
		fading[f] = nil
		f:SetAlpha(alpha)
		return
	end
	fading[f] = alpha
	fader:Show()
end

------------------------------------------------------------------------
-- Lines (borders, warning rings, the range strip) are measured in screen pixels, so they stay crisp:
-- n pixels at scale 1. A Scale between the screen and the frame (a group's, the totem bar's, a
-- preview's) grows them with everything else, rounded to whole pixels. Icon Size doesn't.
------------------------------------------------------------------------
-- The length, in the frame's own units, of n screen pixels grown by the frame's Scale.
function ns.linePx(frame, n)
	local eff = frame:GetEffectiveScale()
	local count = math.floor(n * eff / UIParent:GetEffectiveScale() + 0.5)
	if n > 0 and count < 1 then count = 1 end
	local _, physicalHeight = GetPhysicalScreenSize()
	return count * (768 / (physicalHeight or 768)) / eff
end

------------------------------------------------------------------------
-- Warning looks shared by the HUD, the totem bar and the options previews
------------------------------------------------------------------------
-- A ring just inside an icon's edge: four textures, the side ones between the top and bottom ones
-- (no doubled corners). Its thickness is a line's (ns.linePx): crisp, the same at any icon size.
local RING_PX = 3
local RING_COLOR = { 1, 0, 0, 0.9 }
local Ring = {}
Ring.__index = Ring
local rings = setmetatable({}, { __mode = "k" })
function ns.makeRing(parent, anchor)
	local r = setmetatable({ anchor = anchor, edges = {} }, Ring)
	rings[r] = true
	for i = 1, 4 do
		local t = parent:CreateTexture(nil, "OVERLAY", nil, 6)
		t:Hide()
		r.edges[i] = t
	end
	r:color()
	return r
end
-- A colour other than the warning red (the shock's blue "no mana" ring); no arguments: the red.
function Ring:color(red, g, b, a)
	local k = RING_COLOR
	for _, t in ipairs(self.edges) do t:SetColorTexture(red or k[1], g or k[2], b or k[3], a or k[4]) end
end
-- Sizes the edges for the anchor's current scale; re-anchors only when that changed.
function Ring:fit()
	local w = ns.linePx(self.anchor, RING_PX)
	if w == self.width then return end
	self.width = w
	local a, top, bottom, left, right = self.anchor, self.edges[1], self.edges[2], self.edges[3], self.edges[4]
	for _, t in ipairs(self.edges) do t:ClearAllPoints() end
	top:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0); top:SetHeight(w)
	bottom:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0); bottom:SetHeight(w)
	left:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -w); left:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, w); left:SetWidth(w)
	right:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, -w); right:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, w); right:SetWidth(w)
end
function Ring:show(on)
	if on then self:fit() end
	for _, t in ipairs(self.edges) do t:SetShown(on and true or false) end
end
-- After a layout (a group's or the bar's Scale may have changed): every ring on screen re-measures.
function ns.refitRings()
	for r in pairs(rings) do
		if r.edges[1]:IsShown() then r:fit() end
	end
end

-- A looping pulse on a region. "fade": the region itself breathes, 100% to 35% over 0.8 s (missing
-- looks). "dim": a dark layer from 0 to 55% over 0.6 s (expiring; it dims the icon, never the text
-- above it). Returns the animation group.
function ns.makePulse(region, kind)
	local g = region:CreateAnimationGroup()
	g:SetLooping("BOUNCE")
	local a = g:CreateAnimation("Alpha")
	if kind == "dim" then a:SetFromAlpha(0); a:SetToAlpha(0.55); a:SetDuration(0.6)
	else a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.8) end
	a:SetSmoothing("IN_OUT")
	return g
end

-- The global cooldown's sweep, as on action bars: its own Cooldown over an icon, a dark swipe with no
-- edge, bling or numbers. The caller sets its frame level.
function ns.makeGCDSweep(parent)
	local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetDrawBling(false)
	cd:SetHideCountdownNumbers(true)
	cd:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
	cd:SetSwipeColor(0, 0, 0, 0.6)
	ns.Looks.followSwipe(parent, cd)   -- a rounded or cut-corner icon's shape
	return cd
end


-- A pulsing glow inside an icon: soft light running in from its four edges, over the icon's art and
-- inside its border, breathing. `over` is the icon it covers (default: the parent). Its style is its
-- owner's (an element key or "totembar"; nil for General's): its look (the four edges, or one of
-- ns.Looks' glow looks), colour, pulse length, pulse depth (low is the dimmest it gets) and
-- thickness (how far in it reaches, as a share of the icon). fit(size) lays it out for an icon of
-- that size.
local glows = {}
-- unlisted: left out of ns.applyGlowStyle, for a glow under Blizzard's aura button, which its owner
-- restyles only when that's allowed (out of combat, auras not secret). It keeps the look it had as
-- the button was made (until a /reload; ns.auraGlowStale), and allAnims() lists what the button
-- must play for it (script handlers under the button never run, so its OnShow can't).
local auraGlows = {}
local function makeGlow(parent, over, owner, unlisted)
	local g = CreateFrame("Frame", nil, parent)
	g.owner = owner
	-- The icon whose frame and school its looks follow; never Blizzard's aura button (it and its
	-- parts are off limits in combat): an unlisted glow takes its owner's school and no frame.
	g.over = not unlisted and (over or parent) or nil
	if not unlisted then table.insert(glows, g) end
	g:SetAllPoints(over or parent)
	g:EnableMouse(false)
	g.inner = CreateFrame("Frame", nil, g)   -- the breathing; g's own alpha stays free for a gate
	g.inner:SetAllPoints()
	g.edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = g.inner:CreateTexture(nil, "OVERLAY")
		t:SetTexture("Interface\\Buttons\\WHITE8x8")
		t:SetBlendMode("ADD")
		g.edges[side] = t
	end
	g.anim = g.inner:CreateAnimationGroup()
	g.anim:SetLooping("BOUNCE")
	g.fade = g.anim:CreateAnimation("Alpha")
	g.fade:SetFromAlpha(1); g.fade:SetSmoothing("IN_OUT")
	g.parts = {}   -- look key -> the regions and animations it made (ns.Looks), or false
	-- A look's parts, made on first use; one the client refuses falls back to the four edges.
	local function parts(look)
		if not look.build then return nil end
		local p = g.parts[look.key]
		if p == nil then
			local ok, made = ns.try("glow look " .. look.key, look.build, g)
			p = ok and made or false
			for _, r in ipairs(p and p.roots or {}) do r:Hide() end
			g.parts[look.key] = p
		end
		return p or nil
	end
	if unlisted then table.insert(auraGlows, g) end
	local function play(self, on)
		local p = self.look and self.parts[self.look.key]
		if on then
			self.anim:Play()
			for _, a in ipairs(p and p.anims or {}) do a:Play() end
		else
			self.anim:Stop()
			for _, a in ipairs(p and p.anims or {}) do a:Stop() end
			for _, a in ipairs(p and p.stop or {}) do a:Stop() end
		end
	end
	g:SetScript("OnShow", function(self) play(self, true) end)
	g:SetScript("OnHide", function(self) play(self, false) end)
	-- Every animation group Blizzard's aura button must play for this glow (unlisted glows).
	function g:allAnims()
		local out = { self.anim }
		local p = parts(self.look)
		for _, a in ipairs(p and p.aura or {}) do table.insert(out, a) end
		return out
	end
	-- The owner's style; a fixed colour (killed early's red) wins over its colour.
	function g:restyle()
		local st = ns.Style.get(self.owner, "glow")
		local look = unlisted and self.look or ns.Style.look("glow", st.look)
		if look ~= self.look then
			local running = self.look ~= nil and self:IsShown()
			if running then play(self, false) end
			local old = self.look and self.parts[self.look.key]
			for _, r in ipairs(old and old.roots or {}) do r:Hide() end
			self.look, self.fitWidth = look, nil   -- lay the new look out at the next fit
			local p = parts(look)
			for _, r in ipairs(p and p.roots or {}) do r:Show() end
			for _, t in pairs(self.edges) do t:SetShown(p == nil) end
			if running then play(self, true) end
		end
		self.width = st.width   -- kept for fit, which the ready glows call ten times a second
		-- A running pulse restarts only when its timing changed, so other changes don't make it jump.
		local retime = st.speed ~= self.speed or st.low ~= self.low
		self.speed, self.low = st.speed, st.low
		self.fade:SetDuration(st.speed)
		self.fade:SetToAlpha(look.steady and 1 or st.low)
		local k = self.fixed or st.color
		local p = parts(look)
		if p then look.style(self, p, st, k)
		else
			local on, off = CreateColor(k[1], k[2], k[3], k[4] or 1), CreateColor(k[1], k[2], k[3], 0)
			local e = self.edges
			-- Bright at the edge, clear inward (vertical gradients run bottom to top, horizontal left to right).
			e.TOP:SetGradient("VERTICAL", off, on)
			e.BOTTOM:SetGradient("VERTICAL", on, off)
			e.LEFT:SetGradient("HORIZONTAL", on, off)
			e.RIGHT:SetGradient("HORIZONTAL", off, on)
		end
		if self.iconSize then self:fit(self.iconSize) end
		if retime and self:IsShown() then self.anim:Stop(); self.anim:Play() end
	end
	-- out: how far the icon's frame reaches past its edge (looks drawn outside it start there).
	function g:fit(size)
		local out = ns.Looks.outerEdge(self.over)
		if size == self.iconSize and self.width == self.fitWidth and out == self.fitOut then return end
		self.iconSize, self.fitWidth, self.fitOut = size, self.width, out
		local p = parts(self.look)
		if p then self.look.fit(self, p, size, out) return end
		local th = math.max(size * (self.width or 0.2), 1)
		local e = self.edges
		for _, t in pairs(e) do t:ClearAllPoints() end
		e.TOP:SetPoint("TOPLEFT"); e.TOP:SetPoint("TOPRIGHT"); e.TOP:SetHeight(th)
		e.BOTTOM:SetPoint("BOTTOMLEFT"); e.BOTTOM:SetPoint("BOTTOMRIGHT"); e.BOTTOM:SetHeight(th)
		e.LEFT:SetPoint("TOPLEFT"); e.LEFT:SetPoint("BOTTOMLEFT"); e.LEFT:SetWidth(th)
		e.RIGHT:SetPoint("TOPRIGHT"); e.RIGHT:SetPoint("BOTTOMRIGHT"); e.RIGHT:SetWidth(th)
	end
	function g:color(r, gg, b) self.fixed = { r, gg, b, 1 }; self:restyle() end
	g:restyle()
	g:Hide()
	return g
end
ns.makeGlow = makeGlow
function ns.applyGlowStyle() for _, g in ipairs(glows) do g:restyle() end end
-- The owners of glows under Blizzard's aura button whose look differs from their style's now,
-- among those whose style is owner's (nil: General's): they change after a /reload (the options
-- say so). Returns their keys.
function ns.auraGlowStale(owner)
	local out = {}
	for _, g in ipairs(auraGlows) do
		local reaches = owner == g.owner or (owner == nil and ns.Style.follows(g.owner, "glow"))
		if reaches and g.look ~= ns.Style.look("glow", ns.Style.get(g.owner, "glow").look) then
			table.insert(out, g.owner)
		end
	end
	return out
end

-- Pop: the burst when something happens (a cooldown ready, an imbue dropping, a totem ending).
-- Its style is its owner's (General's, or an element's or the totem bar's own): a motion (grow,
-- bounce, hop, shake) with a size and speed, and optional light (a flash over the icon, a ring
-- spreading out, a star behind it), tinted by what happened. For Ready, a pop look in place of that
-- (ns.Looks.popStyle). Every part is built on the frame the first time it pops.
local POP_TINT = { ready = { 1, 0.82, 0.25 }, imbue = { 0.35, 0.65, 1 }, expired = { 0.95, 0.95, 0.95 }, killed = { 1, 0.15, 0.1 },
	grounded = { 0.56, 0.76, 0.92 } }
ns.POP_TINT = POP_TINT
-- An atlas if the client has it, else a plain texture.
local function atlasOr(t, atlas, file)
	local ok = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
	if ok then t:SetAtlas(atlas) else t:SetTexture(file) end
end
local function anim(g, kind, order, smoothing)
	local a = g:CreateAnimation(kind)
	a:SetOrder(order)
	if smoothing then a:SetSmoothing(smoothing) end
	return a
end
local function popFx(f)
	if f.popFx then return f.popFx end
	local x = {}
	-- Motions: one group each, values set on every play (size and speed can change).
	x.grow = f:CreateAnimationGroup()
	x.grow.a = { anim(x.grow, "Scale", 1, "OUT"), anim(x.grow, "Scale", 2, "IN_OUT") }
	x.bounce = f:CreateAnimationGroup()
	x.bounce.a = { anim(x.bounce, "Scale", 1, "OUT"), anim(x.bounce, "Scale", 2, "IN_OUT"), anim(x.bounce, "Scale", 3, "IN_OUT"), anim(x.bounce, "Scale", 4, "IN") }
	x.hop = f:CreateAnimationGroup()
	x.hop.a = { anim(x.hop, "Translation", 1, "OUT"), anim(x.hop, "Translation", 2, "IN") }
	x.shake = f:CreateAnimationGroup()
	x.shake.a = { anim(x.shake, "Translation", 1), anim(x.shake, "Translation", 2), anim(x.shake, "Translation", 3), anim(x.shake, "Translation", 4) }
	x.shakeV = f:CreateAnimationGroup()
	x.shakeV.a = { anim(x.shakeV, "Translation", 1), anim(x.shakeV, "Translation", 2), anim(x.shakeV, "Translation", 3), anim(x.shakeV, "Translation", 4) }
	-- Light, on a frame above the icon's text.
	local fx = CreateFrame("Frame", nil, f.effects or f)
	fx:SetAllPoints()
	fx:SetFrameLevel(f:GetFrameLevel() + 12)
	fx:EnableMouse(false)
	x.fx = fx
	x.flash = fx:CreateTexture(nil, "OVERLAY")
	x.flash:SetAllPoints()
	x.flash:SetTexture("Interface\\Buttons\\WHITE8x8")
	x.flash:SetBlendMode("ADD")
	x.flash:SetAlpha(0)
	x.flashAnim = x.flash:CreateAnimationGroup()
	x.flashAnim.a = { anim(x.flashAnim, "Alpha", 1), anim(x.flashAnim, "Alpha", 2, "OUT") }
	x.flashAnim:SetScript("OnFinished", function() x.flash:SetAlpha(0) end)
	-- Ring and star: sized frame by frame (not scale animations), so they never reach further than
	-- the sizes given here, a couple of icon widths.
	x.ring = fx:CreateTexture(nil, "OVERLAY")
	x.ring:SetPoint("CENTER")
	atlasOr(x.ring, "ArtifactsFX-YellowRing", "Interface\\Buttons\\UI-ActionButton-Border")
	x.ring:SetBlendMode("ADD")
	x.ring:Hide()
	x.star = fx:CreateTexture(nil, "BACKGROUND")
	x.star:SetPoint("CENTER")
	atlasOr(x.star, "AftLevelup-WhiteStarBurst", "Interface\\Cooldown\\star4")
	x.star:SetBlendMode("ADD")
	x.star:Hide()
	x.bursts = ns.Looks.burster(fx)
	-- A hidden frame runs no OnUpdate and holds its animations, so a pop cut short by a hide (its
	-- group hiding as combat ends) would finish when the icon next shows. A hide ends it instead.
	fx:SetScript("OnHide", function()
		x.bursts.clear()
		for _, m in ipairs({ "grow", "bounce", "hop", "shake", "shakeV" }) do x[m]:Stop() end
		x.flashAnim:Stop()
		x.flash:SetAlpha(0)
		for _, g in ipairs(x.gcd or {}) do g.group:Stop() end
	end)
	f.popFx = x
	return x
end
-- kind: ready | imbue | expired | killed | grounded (the tint); owner: whose style (nil: General's).
-- Nothing on a frame that isn't visible (a combat-only group out of combat): it would wait there and
-- play when the frame next shows, for something long over.
function ns.playPop(f, kind, owner)
	if not f:IsVisible() then return end
	local st = ns.Looks.popStyle(ns.Style.get(owner, "pop"), kind or "ready", f)
	local x = popFx(f)
	local S = st.size
	local k = 1 / math.max(st.speed, 0.1)   -- duration multiplier
	local h = math.max(f:GetHeight(), 8)
	for _, m in ipairs({ "grow", "bounce", "hop", "shake", "shakeV" }) do x[m]:Stop() end
	local motion = st.motion
	if motion == "pop" then
		local a = x.grow.a
		a[1]:SetScaleFrom(1, 1); a[1]:SetScaleTo(S, S); a[1]:SetDuration(0.12 * k)
		a[2]:SetScaleFrom(S, S); a[2]:SetScaleTo(1, 1); a[2]:SetDuration(0.25 * k)
		x.grow:Play()
	elseif motion == "hop" then
		local a, up = x.hop.a, h * (S - 1) * 0.8
		a[1]:SetOffset(0, up); a[1]:SetDuration(0.12 * k)
		a[2]:SetOffset(0, -up); a[2]:SetDuration(0.2 * k)
		x.hop:Play()
	elseif motion == "shake" or motion == "shakeV" then   -- side to side, or up and down
		local g, d = x[motion], h * (S - 1) * 0.3
		local sx, sy = motion == "shake" and 1 or 0, motion == "shakeV" and 1 or 0
		local a = g.a
		a[1]:SetOffset(d * sx, d * sy); a[1]:SetDuration(0.04 * k)
		a[2]:SetOffset(-2 * d * sx, -2 * d * sy); a[2]:SetDuration(0.07 * k)
		a[3]:SetOffset(2 * d * sx, 2 * d * sy); a[3]:SetDuration(0.07 * k)
		a[4]:SetOffset(-d * sx, -d * sy); a[4]:SetDuration(0.05 * k)
		g:Play()
	else   -- bounce: overshoot, dip, settle
		local a, u, o = x.bounce.a, 1 - (S - 1) * 0.25, 1 + (S - 1) * 0.15
		a[1]:SetScaleFrom(1, 1); a[1]:SetScaleTo(S, S); a[1]:SetDuration(0.12 * k)
		a[2]:SetScaleFrom(S, S); a[2]:SetScaleTo(u, u); a[2]:SetDuration(0.12 * k)
		a[3]:SetScaleFrom(u, u); a[3]:SetScaleTo(o, o); a[3]:SetDuration(0.1 * k)
		a[4]:SetScaleFrom(o, o); a[4]:SetScaleTo(1, 1); a[4]:SetDuration(0.08 * k)
		x.bounce:Play()
	end
	local c = st.tint and POP_TINT[kind or "ready"] or { 1, 1, 1 }
	x.flashAnim:Stop()
	if st.flash then
		x.flash:SetVertexColor(c[1], c[2], c[3])
		local a = x.flashAnim.a
		a[1]:SetFromAlpha(0); a[1]:SetToAlpha(0.8); a[1]:SetDuration(0.06 * k)
		a[2]:SetFromAlpha(0.8); a[2]:SetToAlpha(0); a[2]:SetDuration(0.3 * k)
		x.flashAnim:Play()
	end
	-- The ring spreads from just inside the icon to 2.2 icon widths; the star from 1.2 to 3.5.
	x.bursts.stop(x.ring); x.bursts.stop(x.star)
	if st.ring then
		x.ring:SetDesaturated(true)
		x.ring:SetVertexColor(c[1], c[2], c[3])
		x.ring:SetSize(h * 0.9, h * 0.9)
		x.bursts.play(x.ring, { dur = 0.45 * k, from = h * 0.9, to = h * 2.2 })
	end
	if st.star then
		x.star:SetDesaturated(true)
		x.star:SetVertexColor(c[1], c[2], c[3])
		x.star:SetSize(h, h)
		x.bursts.play(x.star, { dur = 0.45 * k, from = h * 1.2, to = h * 3.5, spin = -0.5 })
	end
	if st.play then st.play(x, k) end   -- a pop look's own light (ns.Looks.popStyle)
end

-- The end of a totem, over `anchor`. Nothing here reads a secret: play() hands the gone totem's
-- last duration object to a curve and the result to the frame's SetAlpha.
-- * Killed early (it died with time left; curve 1 from 1.25 s left, 0 up to 1.2 s): the dead totem
--   greyed under red flashing, with an optional pop, red glow and a red cross that stays up to 5 s.
--   Used by the totem bar's slots and the totem elements.
-- * Ran out (opts.expired; the opposite curve, 1 up to 1.2 s left): the totem's icon pops and fades.
-- A totem that ran out never shows the first, one that was killed never the second.
-- * Grounded (opts.grounded): Grounding Totem's early end is a spell it took for us, so the same
--   flash in air blue instead of red, with a tick (Blizzard's ready-check one) instead of the cross.
-- * Ran out, softly (opts.expired with opts.ranOut = { r, g, b }): for totems whose end matters (Mana
--   Tide, Grounding), the grey icon under a wash of the totem's colour and an hourglass, shorter
--   than Killed early and without the pop's burst.
local killedCurve = ns.curve({ 0, 0, 1.2, 0, 1.25, 1, 36000, 1 })
local expiredCurve = ns.curve({ 0, 1, 1.2, 1, 1.25, 0, 36000, 0 })
-- over: the icon frame whose picture it covers (default anchor): its copies of the icon and its wash
-- take that icon's mask, and its glow the icon's school and frame.
function ns.makeEndFlash(parent, anchor, owner, over)
	over = over or anchor
	local kf = CreateFrame("Frame", nil, parent)
	kf:SetAllPoints(anchor)
	kf:SetFrameLevel(anchor:GetFrameLevel() + 8)
	kf:EnableMouse(false)
	kf.pop = CreateFrame("Frame", nil, kf)
	kf.pop:SetAllPoints()
	kf.body = CreateFrame("Frame", nil, kf.pop)
	kf.body:SetAllPoints()
	kf.body:SetAlpha(0)
	kf.glow = makeGlow(kf.body, over, owner)
	kf.glow:color(1, 0.12, 0.08)
	kf.icon = kf.body:CreateTexture(nil, "ARTWORK")
	kf.icon:SetAllPoints()
	ns.cropIcon(kf.icon)
	kf.icon:SetDesaturated(true)
	kf.red = kf.body:CreateTexture(nil, "OVERLAY")
	kf.red:SetAllPoints()
	kf.red:SetColorTexture(0.95, 0.12, 0.08, 0.7)
	kf.flash = kf.body:CreateAnimationGroup()
	local inA = kf.flash:CreateAnimation("Alpha")
	inA:SetFromAlpha(0); inA:SetToAlpha(1); inA:SetDuration(0.12); inA:SetOrder(1)
	local outA = kf.flash:CreateAnimation("Alpha")
	outA:SetFromAlpha(1); outA:SetToAlpha(0); outA:SetDuration(1.4); outA:SetStartDelay(0.5); outA:SetOrder(2)
	kf.flash:SetScript("OnFinished", function() kf.body:SetAlpha(0); kf.glow:Hide() end)
	-- Ran out: quicker, in colour.
	kf.quick = kf.body:CreateAnimationGroup()
	local qIn = kf.quick:CreateAnimation("Alpha")
	qIn:SetFromAlpha(0); qIn:SetToAlpha(1); qIn:SetDuration(0.05); qIn:SetOrder(1)
	local qOut = kf.quick:CreateAnimation("Alpha")
	qOut:SetFromAlpha(1); qOut:SetToAlpha(0); qOut:SetDuration(0.5); qOut:SetStartDelay(0.2); qOut:SetOrder(2)
	kf.quick:SetScript("OnFinished", function() kf.body:SetAlpha(0); kf.glow:Hide() end)
	-- Ran out, softly: in quickly, a short hold, out over most of a second.
	kf.soft = kf.body:CreateAnimationGroup()
	local sIn = kf.soft:CreateAnimation("Alpha")
	sIn:SetFromAlpha(0); sIn:SetToAlpha(1); sIn:SetDuration(0.1); sIn:SetOrder(1)
	local sOut = kf.soft:CreateAnimation("Alpha")
	sOut:SetFromAlpha(1); sOut:SetToAlpha(0); sOut:SetDuration(0.9); sOut:SetStartDelay(0.3); sOut:SetOrder(2)
	kf.soft:SetScript("OnFinished", function() kf.body:SetAlpha(0); kf.glow:Hide() end)
	-- A small white hourglass from the client's common art (tinted by its alpha only).
	kf.hourglass = kf.body:CreateTexture(nil, "OVERLAY", nil, 2)
	kf.hourglass:SetTexture("Interface\\Common\\mini-hourglass")
	kf.hourglass:SetPoint("CENTER")
	kf.hourglass:Hide()
	kf.tick = kf.body:CreateTexture(nil, "OVERLAY", nil, 2)
	kf.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	kf.tick:SetPoint("CENTER")
	kf.tick:Hide()
	kf.mark = CreateFrame("Frame", nil, kf)
	kf.mark:SetAllPoints()
	kf.mark:Hide()
	kf.mark.icon = kf.mark:CreateTexture(nil, "ARTWORK")
	kf.mark.icon:SetAllPoints()
	ns.cropIcon(kf.mark.icon)
	kf.mark.icon:SetDesaturated(true)
	kf.mark.icon:SetAlpha(0.6)
	kf.mark.x = kf.mark:CreateTexture(nil, "OVERLAY")
	kf.mark.x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
	kf.mark.x:SetPoint("CENTER")
	ns.Looks.followMask(over, kf.icon, kf.red, kf.mark.icon)   -- a rounded or cut-corner icon's shape
	-- The dead totem's icon (secret in combat is fine: SetTexture takes it).
	function kf:setIcon(icon)
		pcall(self.icon.SetTexture, self.icon, icon)
		pcall(self.mark.icon.SetTexture, self.mark.icon, icon)
	end
	-- dur: the gone totem's last duration object, or nil to play regardless (the options' previews).
	-- opts: expired (ran out, else killed early), and for killed early pop, glow, mark (booleans);
	-- grounded; ranOut (a colour) for the soft ran-out.
	-- Not while the icon it covers isn't visible: the flash would wait and play when it next shows.
	function kf:play(dur, opts)
		if not anchor:IsVisible() then return end
		local a = 1
		if dur then
			local curve = opts.expired and expiredCurve or killedCurve
			if not curve then return end
			local ok
			ok, a = ns.try("end flash", dur.EvaluateRemainingDuration, dur, curve)
			if not ok then return end
		end
		self:SetAlpha(a)
		local size = anchor:GetWidth()
		local soft = opts.expired and opts.ranOut
		if soft then
			local c = opts.ranOut
			self.glow:color(c[1], c[2], c[3]); self.red:SetColorTexture(c[1], c[2], c[3], 0.45)
		elseif opts.grounded then
			local c = POP_TINT.grounded
			self.glow:color(c[1], c[2], c[3]); self.red:SetColorTexture(c[1], c[2], c[3], 0.7)
		else
			self.glow:color(1, 0.12, 0.08); self.red:SetColorTexture(0.95, 0.12, 0.08, 0.7)
		end
		self.glow:fit(size)
		self.glow:SetShown(opts.glow and true or false)
		self.red:SetShown(not opts.expired or soft and true or false)
		self.icon:SetDesaturated(not opts.expired or soft and true or false)
		self.hourglass:SetShown(soft and true or false)
		self.hourglass:SetSize(size * 0.5, size * 0.5)
		self.tick:SetShown(opts.grounded and not opts.expired and true or false)
		self.tick:SetSize(size * 0.6, size * 0.6)
		self.mark.x:SetSize(size * 0.7, size * 0.7)
		self.flash:Stop(); self.quick:Stop(); self.soft:Stop()
		if soft then self.soft:Play() elseif opts.expired then self.quick:Play() else self.flash:Play() end
		if opts.pop then ns.playPop(self.pop, opts.expired and "expired" or opts.grounded and "grounded" or "killed", owner) end
		if opts.mark then
			self.mark:Show()
			local token = {}
			self.markToken = token
			C_Timer.After(5, function() if self.markToken == token then self.mark:Hide() end end)
		else self.mark:Hide() end
	end
	-- Stops a flash still playing and takes down its cross (the options' previews, on a new state).
	function kf:stop()
		self.flash:Stop(); self.quick:Stop(); self.soft:Stop()
		self.body:SetAlpha(0); self.glow:Hide(); self.mark:Hide()
		self.markToken = nil
	end
	-- A flash cut short by a hide ends there, for the same reason.
	kf:SetScript("OnHide", function(self) self:stop() end)
	return kf
end

-- A grow-and-settle pop as an animation group on region (a texture or frame), sized and timed by
-- owner's pop style: the one kind of pop Blizzard's aura button can play for us (Elemental Focus),
-- and its previews. restyle() takes the current style; on = false makes it a no-op (scale 1).
function ns.makeGrowPop(region, owner)
	local g = region:CreateAnimationGroup()
	local up = g:CreateAnimation("Scale")
	up:SetOrder(1); up:SetOrigin("CENTER", 0, 0)
	local down = g:CreateAnimation("Scale")
	down:SetOrder(2); down:SetOrigin("CENTER", 0, 0)
	function g:restyle(on)
		local st = ns.Style.get(owner, "pop")
		local s = on == false and 1 or st.size
		local k = 1 / math.max(st.speed, 0.1)
		up:SetScaleFrom(1, 1); up:SetScaleTo(s, s); up:SetDuration(0.12 * k)
		down:SetScaleFrom(s, s); down:SetScaleTo(1, 1); down:SetDuration(0.25 * k)
	end
	g:restyle()
	return g
end

------------------------------------------------------------------------
-- An aura slot: Blizzard's aura container on an element icon, with one aura slot whose button
-- Blizzard (untainted) shows while an aura it matches is up and draws that aura's icon, time left
-- and charges, exact in combat too. It is the one way to show an aura in combat: every aura API
-- throws for addon code then (docs/combat-techniques.md). Used by the shield and Elemental Focus.
-- What it takes:
-- * The container and its button refuse addon calls in combat and while auras are secret, which
--   can also happen out of combat (PvP matches, encounters). So the container is made, and it and
--   the button restyled, only outside both; anything asked for meanwhile waits for them to end
--   (ns.deferWhileAurasSecret), and a refused call is noted for /sf debug and tried again then.
-- * An intrinsic frame doesn't inherit placement: the container takes the icon's strata (HIGH
--   would float over other addons' dialogs) and a frame level above the icon's text, so it sits
--   over the icon and its rings. Regrouping reparents the icon, which can drop the container back
--   under them, so each restyle restates both.
-- * The slot's button is placed by us (at the container's corner), not by the container's flow.
-- * Mouse input goes off before Blizzard locks the button down: no tooltip, clicks pass through.
-- * Script handlers on anything under the button never run (OnShow and OnHide on a child fired
--   zero times, tested 2026-09-23), so nothing tells addon code when it shows or hides; the button
--   only plays animations handed to it (Blizzard_CustomAuraButton.lua).
------------------------------------------------------------------------
local AuraSlot = {}
AuraSlot.__index = AuraSlot

-- frame: the element icon it covers. opts:
--   key          the element: its icon size (ns.sizeOf) and its timer's style
--   slot, ids()  the aura slot's name, and the spell ID map it matches (read when it is made)
--   parent       what the container hangs from (default frame); name: a global name, or nil
--   sites        { container = , style = , filter = }: names for its waiting work and caught errors
--   iconAlpha()  the aura icon's alpha as the button is made (optional)
--   onButton(slot, button, cd)  the caller's own parts, once Blizzard has made the button
--   onStyle(slot, size)         the caller's own restyle, after the shared one
--   onError(err)                the container couldn't be made on this client
-- Nothing is made until slot:setup(). The slot then holds container, button, icon (the aura's
-- texture), cd and timer (swipe and countdown only), or err; and after slot:refilter(), filtered
-- (the spell IDs it last gave the slot).
function ns.makeAuraSlot(frame, opts)
	return setmetatable({ frame = frame, opts = opts }, AuraSlot)
end

-- Called by Blizzard (untainted) once, right after it makes the slot's button.
local function initAuraButton(slot, button)
	local o = slot.opts
	local size = ns.sizeOf(o.key)
	button:SetSize(size, size)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	local tex = button:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	ns.cropIcon(tex)
	if o.iconAlpha then tex:SetAlpha(o.iconAlpha()) end
	button:SetIcon(tex)
	slot.icon = tex
	-- A frame look's mask and art: only now, on the button (ns.Looks.auraMask).
	ns.try(o.sites.style, ns.Looks.auraMask, button, tex, o.key)
	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	-- Its timer: swipe and countdown text only (no bar: nothing of ours can follow Blizzard's time).
	slot.timer = ns.Timer.new(button, o.key, "uptime", { cd = cd, anchor = button, noBar = true })
	slot.timer:apply()
	button:SetDurationCooldown(cd)
	slot.cd = cd
	if o.onButton then o.onButton(slot, button, cd) end
	slot.button = button
end

-- Makes the container and its slot, once (out of combat, auras readable; else when that ends).
-- Once made it stays; a client that refuses it gets err and onError.
function AuraSlot:setup()
	if self.container or self.err then return end
	local o, f = self.opts, self.frame
	if ns.deferWhileAurasSecret(o.sites.container, function() self:setup() end) then return end
	local ok, err = pcall(function()
		local size = ns.sizeOf(o.key)
		local c = CreateFrame("AuraContainer", o.name, o.parent or f, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		c:SetSize(size, size)
		c:SetFrameStrata(f:GetFrameStrata())
		c:SetFrameLevel(f.textFrame:GetFrameLevel() + 5)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)   -- unlocked drags start on the group frame underneath
		self.container = c
		c:AddAuraSlot(o.slot, "HELPFUL", {
			candidateFilters = { includeSpellIDs = o.ids() },
			initializeFrame = function(button) initAuraButton(self, button) end,
		})
	end)
	if not ok then
		self.err = tostring(err)
		if self.container then self.container:Hide() end
		o.onError(self.err)
	else
		self:style()   -- a layout queued before it (a /reload in combat) found no button to style
	end
end

-- The container's size and placement, the button's size and its timer's style, then the caller's
-- own parts (onStyle). Out of combat only, and not while auras are secret: waits for that, and
-- one refused call (the whole restyle is one pcall) is noted and tried again when combat ends.
function AuraSlot:style()
	if not self.button then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.style, function() self:style() end) then return end
	local ok = ns.try(o.sites.style, function()
		local size, f, c = ns.sizeOf(o.key), self.frame, self.container
		c:SetSize(size, size)
		c:SetFrameStrata(f:GetFrameStrata())
		c:SetFrameLevel(f.textFrame:GetFrameLevel() + 5)
		self.button:SetSize(size, size)
		ns.Looks.auraStyle(self, size)
		self.timer:apply()
		if o.onStyle then o.onStyle(self, size) end
	end)
	if not ok then ns.retryAfterCombat(o.sites.style, function() self:style() end) end
end

-- The slot's filter again, from opts.ids() (the IDs that count can grow), once the container is
-- made. Out of combat only, and not while auras are secret: waits for that, and a refused call is
-- noted and tried again when combat ends.
function AuraSlot:refilter()
	if not self.container or self.err then return end
	local o = self.opts
	if ns.deferWhileAurasSecret(o.sites.filter, function() self:refilter() end) then return end
	local ids = o.ids()
	local ok = ns.try(o.sites.filter, self.container.SetAuraSlotCandidateFilters, self.container, o.slot,
		{ includeSpellIDs = ids })
	if ok then self.filtered = ids else ns.retryAfterCombat(o.sites.filter, function() self:refilter() end) end
end

-- owner: whose glow and pop style it uses (an element key, "totembar", or nil for General's).
function ns.makeIcon(parent, size, owner)
	local f = CreateFrame("Frame", nil, parent)
	f.owner = owner
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	ns.cropIcon(f.tex)
	f.manaOverlay = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.manaOverlay:SetAllPoints(f.tex)
	f.manaOverlay:SetColorTexture(0.2, 0.45, 1, 0.55)
	f.manaOverlay:Hide()
	-- The shock's body colour (out of range, no mana): an overlay over the art, a tint of the art, or
	-- both. style: overlay | tint | both; the caller clears it first.
	f.SetBodyPaint = function(self, style, r, g, b, overlayAlpha, tintStrength)
		if style == "overlay" or style == "both" then
			self.manaOverlay:SetColorTexture(r, g, b, overlayAlpha)
			self.manaOverlay:Show()
		end
		if style == "tint" or style == "both" then
			local k = 1 - tintStrength
			self.tex:SetVertexColor(r == 1 and 1 or k, g == 1 and 1 or k, b == 1 and 1 or k)
		end
	end
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	-- Text sits on its own frame above the cooldown so the swipe never dims it.
	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints()
	f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.count = f.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	f.count:SetFont(STANDARD_TEXT_FONT, math.floor(size * 0.45), "OUTLINE")
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	f.count:SetJustifyH("RIGHT")
	local okFS, cdText = pcall(f.cd.GetCountdownFontString, f.cd)
	if okFS and cdText then pcall(cdText.SetDrawLayer, cdText, "OVERLAY", 7) end
	-- Red ring just inside the icon edge (ns.makeRing), so an exact-size frame on top covers it completely.
	f.ring = ns.makeRing(f.textFrame, f.tex)
	-- Pulse: the icon fades in and out, used for "missing" warnings.
	f.pulse = ns.makePulse(f.tex, "fade")
	f.SetPulsing = function(self, on)
		if not on then self.pulse:Stop()
		elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	end
	-- r, g, b, a: a colour other than the warning red (the shock's blue "no mana" ring).
	f.SetRingShown = function(self, shown, r, g, b, a)
		if shown then self.ring:color(r, g, b, a) end
		self.ring:show(shown)
	end
	-- Glow (gold by default) and pop, for warnings and moments worth catching the eye.
	f.glowF = makeGlow(f, f, owner)
	f.SetGlowShown = function(self, shown, r, g, b)
		if shown then
			self.glowF:fit(self:GetWidth())
			if r then self.glowF:color(r, g, b) elseif self.glowF.fixed then self.glowF.fixed = nil; self.glowF:restyle() end
		end
		self.glowF:SetShown(shown and true or false)
	end
	f.Pop = function(self, kind) ns.playPop(self, kind or "ready", self.owner) end
	return f
end
