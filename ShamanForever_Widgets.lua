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

-- Border drawn just outside an element's edge, so it never covers the rings inside the icon or
-- Blizzard's shield button. size is a line's (ns.linePx): screen pixels, grown by Scale, not by Size.
function ns.applyBorder(f, b)
	if not (b and b.show and b.size and b.size > 0) then
		if f.border then for _, t in ipairs(f.border) do t:Hide() end end
		return
	end
	if not f.border then
		f.border = {}
		for i = 1, 4 do f.border[i] = f:CreateTexture(nil, "BACKGROUND", nil, -8) end
	end
	local s = ns.linePx(f, b.size)
	local c = b.color or { 0, 0, 0, 1 }
	local top, bottom, left, right = f.border[1], f.border[2], f.border[3], f.border[4]
	for _, t in ipairs(f.border) do
		t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		t:ClearAllPoints()
		t:Show()
	end
	-- Top and bottom span the corners; left and right fill between them.
	top:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -s, 0)
	top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", s, 0)
	top:SetHeight(s)
	bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -s, 0)
	bottom:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", s, 0)
	bottom:SetHeight(s)
	left:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
	left:SetWidth(s)
	right:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(s)
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
	return cd
end


-- A pulsing glow inside an icon: soft light running in from its four edges, over the icon's art and
-- inside its border, breathing. `over` is the icon it covers (default: the parent). Its style is its
-- owner's (an element key or "totembar"; nil for General's): colour, pulse length, pulse depth (low
-- is the dimmest it gets) and thickness (how far in it reaches, as a share of the icon).
-- fit(size) lays it out for an icon of that size.
local glows = {}
local function makeGlow(parent, over, owner)
	local g = CreateFrame("Frame", nil, parent)
	g.owner = owner
	table.insert(glows, g)
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
	g:SetScript("OnShow", function(self) self.anim:Play() end)
	g:SetScript("OnHide", function(self) self.anim:Stop() end)
	-- The owner's style; a fixed colour (killed early's red) wins over its colour.
	function g:restyle()
		local st = ns.Style.get(self.owner, "glow")
		self.width = st.width   -- kept for fit, which the ready glows call ten times a second
		-- A running pulse restarts only when its timing changed, so other changes don't make it jump.
		local retime = st.speed ~= self.speed or st.low ~= self.low
		self.speed, self.low = st.speed, st.low
		self.fade:SetDuration(st.speed)
		self.fade:SetToAlpha(st.low)
		local k = self.fixed or st.color
		local on, off = CreateColor(k[1], k[2], k[3], k[4] or 1), CreateColor(k[1], k[2], k[3], 0)
		local e = self.edges
		-- Bright at the edge, clear inward (vertical gradients run bottom to top, horizontal left to right).
		e.TOP:SetGradient("VERTICAL", off, on)
		e.BOTTOM:SetGradient("VERTICAL", on, off)
		e.LEFT:SetGradient("HORIZONTAL", on, off)
		e.RIGHT:SetGradient("HORIZONTAL", off, on)
		if self.iconSize then self:fit(self.iconSize) end
		if retime and self:IsShown() then self.anim:Stop(); self.anim:Play() end
	end
	function g:fit(size)
		if size == self.iconSize and self.width == self.fitWidth then return end
		self.iconSize, self.fitWidth = size, self.width
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

-- Pop: the burst when something happens (a cooldown ready, an imbue dropping, a totem ending).
-- Its style is its owner's (General's, or an element's or the totem bar's own): a motion (grow,
-- bounce, hop, shake) with a size and speed, and optional light (a flash over the icon, a ring
-- spreading out, a star behind it), tinted by what happened. Every part is built on the frame the
-- first time it pops.
local POP_TINT = { ready = { 1, 0.82, 0.25 }, imbue = { 0.35, 0.65, 1 }, expired = { 0.95, 0.95, 0.95 }, killed = { 1, 0.15, 0.1 } }
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
	x.bursts = {}   -- texture -> { t (elapsed), dur, from, to (sizes), spin (radians) }
	-- Runs only while a burst does (set by playPop).
	x.step = function(self, elapsed)
		for tex, b in pairs(x.bursts) do
			b.t = b.t + elapsed
			local p = math.min(b.t / b.dur, 1)
			local e = 1 - (1 - p) * (1 - p)   -- ease out
			local size = b.from + (b.to - b.from) * e
			tex:SetSize(size, size)
			tex:SetAlpha(1 - p)
			if b.spin then tex:SetRotation(b.spin * e) end
			if p >= 1 then tex:Hide(); x.bursts[tex] = nil end
		end
		if next(x.bursts) == nil then self:SetScript("OnUpdate", nil) end
	end
	f.popFx = x
	return x
end
-- kind: ready | imbue | expired | killed (the tint); owner: whose style (nil: General's).
function ns.playPop(f, kind, owner)
	local st = ns.Style.get(owner, "pop")
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
	x.bursts[x.ring], x.bursts[x.star] = nil, nil
	x.ring:Hide(); x.star:Hide()
	if st.ring then
		x.ring:SetDesaturated(true)
		x.ring:SetVertexColor(c[1], c[2], c[3])
		x.ring:SetSize(h * 0.9, h * 0.9)
		x.ring:Show()
		x.bursts[x.ring] = { t = 0, dur = 0.45 * k, from = h * 0.9, to = h * 2.2 }
	end
	if st.star then
		x.star:SetDesaturated(true)
		x.star:SetVertexColor(c[1], c[2], c[3])
		x.star:SetSize(h, h)
		x.star:Show()
		x.bursts[x.star] = { t = 0, dur = 0.45 * k, from = h * 1.2, to = h * 3.5, spin = -0.5 }
	end
	if next(x.bursts) ~= nil then x.fx:SetScript("OnUpdate", x.step) end
end

-- The end of a totem, over `anchor`. Nothing here reads a secret: play() hands the gone totem's
-- last duration object to a curve and the result to the frame's SetAlpha.
-- * Killed early (it died with time left; curve 1 from 1.25 s left, 0 up to 1.2 s): the dead totem
--   greyed under red flashing, with an optional pop, red glow and a red cross that stays up to 5 s.
--   Used by the totem bar's slots and the Earthbind / Stoneclaw elements.
-- * Ran out (opts.expired; the opposite curve, 1 up to 1.2 s left): the totem's icon pops and fades.
-- A totem that ran out never shows the first, one that was killed never the second.
local killedCurve = ns.curve({ 0, 0, 1.2, 0, 1.25, 1, 36000, 1 })
local expiredCurve = ns.curve({ 0, 1, 1.2, 1, 1.25, 0, 36000, 0 })
function ns.makeEndFlash(parent, anchor, owner)
	local kf = CreateFrame("Frame", nil, parent)
	kf:SetAllPoints(anchor)
	kf:SetFrameLevel(anchor:GetFrameLevel() + 8)
	kf:EnableMouse(false)
	kf.pop = CreateFrame("Frame", nil, kf)
	kf.pop:SetAllPoints()
	kf.body = CreateFrame("Frame", nil, kf.pop)
	kf.body:SetAllPoints()
	kf.body:SetAlpha(0)
	kf.glow = makeGlow(kf.body, kf.body, owner)
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
	-- The dead totem's icon (secret in combat is fine: SetTexture takes it).
	function kf:setIcon(icon)
		pcall(self.icon.SetTexture, self.icon, icon)
		pcall(self.mark.icon.SetTexture, self.mark.icon, icon)
	end
	-- dur: the gone totem's last duration object. opts: expired (ran out, else killed early), and
	-- for killed early pop, glow, mark (booleans).
	function kf:play(dur, opts)
		local curve = opts.expired and expiredCurve or killedCurve
		if not curve then return end
		local ok, a = ns.try("end flash", dur.EvaluateRemainingDuration, dur, curve)
		if not ok then return end
		self:SetAlpha(a)
		local size = anchor:GetWidth()
		self.glow:fit(size)
		self.glow:SetShown(opts.glow and true or false)
		self.red:SetShown(not opts.expired)
		self.icon:SetDesaturated(not opts.expired)
		self.mark.x:SetSize(size * 0.7, size * 0.7)
		self.flash:Stop(); self.quick:Stop()
		if opts.expired then self.quick:Play() else self.flash:Play() end
		if opts.pop then ns.playPop(self.pop, opts.expired and "expired" or "killed", owner) end
		if opts.mark then
			self.mark:Show()
			local token = {}
			self.markToken = token
			C_Timer.After(5, function() if self.markToken == token then self.mark:Hide() end end)
		else self.mark:Hide() end
	end
	return kf
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
