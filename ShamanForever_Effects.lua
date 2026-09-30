-- Effects: the pulsing glow, the pop, the end-of-totem flash, and the effect host that gives an
-- element icon its glow and pop. Looks come from ns.Style and ns.Looks; nothing here reads
-- settings of its own.

local _, ns = ...

local E = {}
ns.Effects = E

------------------------------------------------------------------------
-- The pulsing glow
------------------------------------------------------------------------
-- A pulsing glow inside an icon: soft light over the icon's art and inside its border, breathing.
-- `over` is the icon it covers (default: the parent). Its style is its owner's (an element key or
-- "totembar"; nil for General's): its look (one of ns.Looks' glow looks), colour, pulse length,
-- pulse depth (low is the dimmest it gets) and thickness (how far in it reaches, as a share of the
-- icon). fit(size) lays it out for an icon of that size. opts:
--   underButton  a glow under Blizzard's aura button, left out of E.applyStyle: its owner restyles
--                it only when that's allowed (out of combat, auras not secret). The button plays its
--                animations (script handlers under it never run, so its OnShow can't): g:bindButton
--                hands them over as the button is made, and a new look's as the look changes, out
--                of combat; a look whose animations the button won't take stays the old one (until
--                a /reload; E.auraGlowStale).
-- g.onLayout(g, parts, look), if set: called as a look's parts are made and after each fit (their
-- sizes and scales may have changed), for the owner's own touches.
local glows = {}
local auraGlows = {}
function E.glow(parent, over, owner, opts)
	local underButton = opts and opts.underButton or false
	local g = CreateFrame("Frame", nil, parent)
	g.owner, g.underButton = owner, underButton
	-- The icon whose frame and school its looks follow; never Blizzard's aura button (it and its
	-- parts are off limits in combat): a glow under it takes its owner's school and no frame.
	g.over = not underButton and (over or parent) or nil
	if not underButton then table.insert(glows, g) end
	g:SetAllPoints(over or parent)
	g:EnableMouse(false)
	g.inner = CreateFrame("Frame", nil, g)   -- the breathing; g's own alpha stays free for a gate
	g.inner:SetAllPoints()
	g.anim = g.inner:CreateAnimationGroup()
	g.anim:SetLooping("BOUNCE")
	g.fade = g.anim:CreateAnimation("Alpha")
	g.fade:SetFromAlpha(1); g.fade:SetSmoothing("IN_OUT")
	g.parts = {}   -- look key -> the regions and animations it made (ns.Looks), or false
	-- A look's parts, made on first use; nil for one the client refused.
	local function parts(look)
		local p = g.parts[look.key]
		if p == nil then
			local ok, made = ns.try("glow look " .. look.key, look.build, g)
			p = ok and made or false
			if p then ns.Looks.levelParts(p) end
			for _, r in ipairs(p and p.roots or {}) do r:Hide() end
			g.parts[look.key] = p
			if p and g.onLayout then ns.try("glow layout", g.onLayout, g, p, look) end
		end
		return p or nil
	end
	-- The look drawn for a style's: itself, or the default look where the client refused its parts.
	local function drawn(look)
		if parts(look) then return look end
		return ns.Style.look("glow", ns.Style.KINDS.glow.defaults.look)
	end
	if underButton then table.insert(auraGlows, g) end
	local function play(self, on)
		local p = self.look and self.parts[self.look.key]
		if on then
			if p then ns.Looks.levelParts(p) end
			self.anim:Play()
			for _, a in ipairs(p and p.anims or {}) do a:Play() end
		else
			self.anim:Stop()
			for _, a in ipairs(p and p.anims or {}) do a:Stop() end
			for _, a in ipairs(p and p.stop or {}) do a:Stop() end
		end
	end
	-- Not under Blizzard's aura button: the client refuses script handlers there (blocked by secret
	-- aspects, seen 2026-09-29), and the button plays allAnims() itself.
	if not underButton then
		g:SetScript("OnShow", function(self) play(self, true) end)
		g:SetScript("OnHide", function(self) play(self, false) end)
	end
	-- A glow under the button: its animations handed over now (the button plays them while its
	-- aura shows); a new look's are handed in restyle. Each only once (the button refuses a repeat).
	function g:bindButton(button)
		self.button, self.handed = button, {}
		for _, a in ipairs(self:allAnims()) do self:hand(a) end
	end
	function g:hand(a)
		if self.handed[a] then return true end
		local b = self.button
		local ok = b.AddAuraShownAnimation ~= nil and ns.try("glow hand-off", b.AddAuraShownAnimation, b, a)
		if ok then self.handed[a] = true end
		return ok
	end
	-- Every animation group Blizzard's aura button must play for this glow (under the button).
	function g:allAnims()
		local out = { self.anim }
		local p = parts(self.look)
		for _, a in ipairs(p and p.aura or {}) do table.insert(out, a) end
		return out
	end
	-- The owner's style; a fixed colour (killed early's red) wins over its colour.
	function g:restyle()
		local st = ns.Style.get(self.owner, "glow")
		local look = drawn(ns.Style.look("glow", st.look))
		-- Under the button, a new look only once the button has taken its animations: out of combat,
		-- auras readable (it refuses calls otherwise); else the old look stays for now.
		if underButton and self.look and look ~= self.look then
			local ok = self.button ~= nil and not InCombatLockdown() and not ns.aurasSecret()
			local p = ok and parts(look)
			for _, a in ipairs(p and p.aura or {}) do ok = ok and self:hand(a) end
			if not ok then look = self.look end
		end
		if look ~= self.look then
			local running = not underButton and self.look ~= nil and self:IsShown()
			if running then play(self, false) end
			local old = self.look and self.parts[self.look.key]
			for _, r in ipairs(old and old.roots or {}) do r:Hide() end
			self.look, self.fitWidth = look, nil   -- lay the new look out at the next fit
			local p = parts(look)
			for _, r in ipairs(p and p.roots or {}) do r:Show() end
			if running then play(self, true) end
			-- Under the button: the new look's animations start now; the button restarts them as its
			-- aura shows (a look's old ones keep playing on its hidden parts).
			if underButton and self.button then
				for _, a in ipairs(p and p.aura or {}) do pcall(a.Play, a) end
			end
		end
		self.width = st.width   -- kept for fit, which the ready glows call ten times a second
		-- A running pulse restarts only when its timing changed, so other changes don't make it jump.
		local retime = st.speed ~= self.speed or st.low ~= self.low
		self.speed, self.low = st.speed, st.low
		self.fade:SetDuration(st.speed)
		self.fade:SetToAlpha(look.steady and 1 or st.low)
		local k = self.fixed or st.color
		local p = parts(look)
		if p then look.style(self, p, st, k) end
		if self.iconSize then self:fit(self.iconSize) end
		-- Under the aura button IsShown is secret; the button restarts that glow itself.
		if retime and not underButton and self:IsShown() then self.anim:Stop(); self.anim:Play() end
	end
	-- out: how far the icon's frame reaches past its edge (looks drawn outside it start there).
	function g:fit(size)
		local out = ns.Looks.outerEdge(self.over)
		if size == self.iconSize and self.width == self.fitWidth and out == self.fitOut then return end
		self.iconSize, self.fitWidth, self.fitOut = size, self.width, out
		local p = parts(self.look)
		if p then
			self.look.fit(self, p, size, out)
			if self.onLayout then ns.try("glow layout", self.onLayout, self, p, self.look) end
		end
	end
	function g:color(r, gg, b) self.fixed = { r, gg, b, 1 }; self:restyle() end
	g:restyle()
	g:Hide()
	return g
end
-- Every glow restyled from its style now (not those under an aura button: their owners do it).
function E.applyStyle() for _, g in ipairs(glows) do g:restyle() end end

-- The owners of glows under Blizzard's aura button whose look differs from their style's now,
-- among those whose style is owner's (nil: General's): they change after a /reload (the options
-- say so). Returns their keys.
function E.auraGlowStale(owner)
	local out = {}
	for _, g in ipairs(auraGlows) do
		local reaches = owner == g.owner or (owner == nil and ns.Style.follows(g.owner, "glow"))
		local want = ns.Style.look("glow", ns.Style.get(g.owner, "glow").look)
		if reaches and g.look ~= want then
			table.insert(out, g.owner)
		end
	end
	return out
end

------------------------------------------------------------------------
-- The pop
------------------------------------------------------------------------
-- The burst when something happens (a cooldown ready, an imbue dropping, a totem ending).
-- Its style is its owner's (General's, or an element's or the totem bar's own), one setting per
-- part, each changing only its own: a motion (none, grow, bounce, hop, shake) with a size and
-- speed; a flash over the icon (plain, or Blizzard's edge flash); a burst (a ring spreading out, a
-- star behind it, or one of ns.Looks' drawn bursts); and their colour, by what happened or by
-- school.
-- It plays on a rig: a fixed set of parts on the frame that pops, each a texture (or the frame
-- itself, for the motion) with one animation group whose values the style sets. Nothing is driven
-- by script. Made the first time the frame pops.
-- Nothing with a Scale, Rotation or Translation of its own sits under the frame the motion moves:
-- burst textures with scale animations under an icon playing the motion drew across the whole
-- screen (seen 2026-09-25 and 2026-10-01), while textures with scale animations under a still
-- frame draw as asked (the glow looks'). So the bursts sit on frames beside the icon, anchored to
-- it; the flashes, whose animations only fade or flip, stay on the icon and move with it. No
-- animation takes no time, and every Scale and Rotation turns about the centre.
local POP_TINT = { ready = { 1, 0.82, 0.25 }, imbue = { 0.35, 0.65, 1 }, expired = { 0.95, 0.95, 0.95 }, killed = { 1, 0.15, 0.1 },
	grounded = { 0.56, 0.76, 0.92 }, blocked = { 0.6, 0.6, 0.6 } }
local BLACK = { 0, 0, 0 }
-- The ring spreads from just inside the icon to 2.2 icon heights; the star turns as it spreads
-- from 1.2 to 3.5, behind the ring. Parts as ns.Looks' drawn bursts' (Looks.popParts), plus an
-- atlas (with a file for a client without it), desaturated to take the pop's colour.
local RING = { name = "ring", atlas = "ArtifactsFX-YellowRing", file = "Interface\\Buttons\\UI-ActionButton-Border",
	layer = "OVERLAY", add = true, desat = true, from = 0.9, to = 2.2, dur = 0.45, a = 1 }
local STAR = { name = "star", atlas = "AftLevelup-WhiteStarBurst", file = "Interface\\Cooldown\\star4",
	layer = "BACKGROUND", add = true, desat = true, from = 1.2, to = 3.5, dur = 0.45, a = 1, spin = -0.5 }
local MOTION_STEPS = 4
local SHORTEST = 0.01   -- a burst part's shortest wait, and a motion step no motion uses (s)

local function anim(g, kind, order)
	local a = g:CreateAnimation(kind)
	a:SetOrder(order)
	if kind == "Scale" or kind == "Rotation" then a:SetOrigin("CENTER", 0, 0) end
	return a
end

-- One burst part: a texture on parent that waits unseen, then grows, fades, turns and moves all
-- at once, as one group, in the shape Blizzard's own bursts take: a texture at alpha 0 and a group
-- that sets its final alpha (the fade's 0), so its end leaves the texture at 0 whatever the group's
-- other animations left behind. The wait is an Alpha holding 0 from the start (Blizzard's idiom)
-- for the delay, at least SHORTEST; the rest start after it, all in one order. Hidden while no
-- style uses it (Rig:style).
local function newPart(parent, spec)
	local t = parent:CreateTexture(nil, "OVERLAY")
	if spec and spec.atlas then
		if ns.Looks.hasAtlas(spec.atlas) then t:SetAtlas(spec.atlas) else t:SetTexture(spec.file) end
	end
	t:SetAlpha(0)
	t:Hide()
	local g = t:CreateAnimationGroup()
	g:SetToFinalAlpha(true)
	g.wait = anim(g, "Alpha", 1)
	g.wait:SetFromAlpha(0); g.wait:SetToAlpha(0)
	g.grow = anim(g, "Scale", 1)
	g.grow:SetSmoothing("OUT")
	g.fade = anim(g, "Alpha", 1)
	g.fade:SetToAlpha(0)
	g.turn = anim(g, "Rotation", 1)
	g.turn:SetSmoothing("OUT")
	g.move = anim(g, "Translation", 1)
	g.move:SetSmoothing("OUT")
	return { tex = t, group = g }
end

-- A part's values from its spec: h the icon height its sizes are in (the sheen's: the frame's
-- own), c the pop's colour, k the duration multiplier. After delay, the size eases out and the
-- alpha fades evenly (late for slow) over dur. Its alpha is set to 0 again once its texture is.
local function stylePart(p, spec, parent, h, c, k)
	local t, g = p.tex, p.group
	if not spec.atlas then t:SetTexture(spec.file) end
	t:SetAlpha(0)
	t:SetBlendMode(spec.add and "ADD" or "BLEND")
	t:SetDrawLayer(spec.layer, spec.sub or 0)
	t:SetDesaturated(spec.desat and true or false)
	local col = spec.dark and BLACK or spec.color or c
	t:SetVertexColor(col[1], col[2], col[3])
	t:ClearAllPoints()
	local shift = spec.shift
	if shift then
		-- The sheen: the frame-sized picture slides across the frame, clipped to it.
		local s = shift[1]
		t:SetPoint("TOPLEFT", parent, "TOPLEFT", -s * h, s * h)
		t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -s * h, s * h)
		g.grow:SetScaleTo(1, 1)
		local d = shift[2] - shift[1]
		g.move:SetOffset(-d * h, d * h)
	else
		t:SetSize(h * spec.from, h * spec.from * (spec.sy or 1))
		t:SetPoint("CENTER", parent, "CENTER", 0, 0)
		local grow = spec.to / spec.from
		g.grow:SetScaleTo(grow, grow)
		g.move:SetOffset(0, h * (spec.rise or 0))
	end
	g.grow:SetScaleFrom(1, 1)
	g.fade:SetFromAlpha(spec.a or 1)
	g.fade:SetSmoothing(spec.slow and "IN" or "NONE")
	g.turn:SetDegrees(math.deg(spec.spin or 0))
	local delay, dur = math.max((spec.delay or 0) * k, SHORTEST), spec.dur * k
	g.wait:SetDuration(delay)
	for _, a in ipairs({ g.grow, g.fade, g.turn, g.move }) do a:SetStartDelay(delay); a:SetDuration(dur) end
end

local Rig = {}
Rig.__index = Rig

-- The rig on f. The flashes sit on a frame above the icon's text (fx, on f.effects where the icon
-- has one, so an idle icon's fade leaves them at full) and move with the icon; the bursts on two
-- frames beside it (front, level with fx, and back, behind the icon), anchored to it and kept under
-- its parent (Rig:home).
-- icon, level: on Blizzard's aura button (the aura route), the aura's icon texture, which moves with
-- f, and the light's frame level (levels there may read back as secret, so none is read).
local function newRig(f, icon, level)
	local r = setmetatable({ f = f, parts = {}, playing = {}, level = level }, Rig)
	-- The motion: two groups on f, one of Scales and one of Translations, a step each per order
	-- (Rig:styleMotion). Only the ones a motion uses play.
	r.motionScale, r.motionMove = f:CreateAnimationGroup(), f:CreateAnimationGroup()
	r.scale, r.move = {}, {}
	for i = 1, MOTION_STEPS do
		r.scale[i] = anim(r.motionScale, "Scale", i)
		r.move[i] = anim(r.motionMove, "Translation", i)
	end
	if icon then
		r.iconMotion = icon:CreateAnimationGroup()
		r.iconScale, r.iconMove = {}, {}
		for i = 1, MOTION_STEPS do
			r.iconScale[i] = anim(r.iconMotion, "Scale", i)
			r.iconMove[i] = anim(r.iconMotion, "Translation", i)
		end
	end
	local fx = CreateFrame("Frame", nil, f.effects or f)
	fx:SetAllPoints()
	fx:EnableMouse(false)
	r.fx = fx
	r.flash = fx:CreateTexture(nil, "OVERLAY")
	r.flash:SetAllPoints()
	r.flash:SetTexture("Interface\\Buttons\\WHITE8x8")
	r.flash:SetBlendMode("ADD")
	r.flash:SetAlpha(0)
	r.flashAnim = r.flash:CreateAnimationGroup()
	r.flashAnim:SetToFinalAlpha(true)   -- ends at flashOut's 0, as the burst parts do
	r.flashIn, r.flashOut = anim(r.flashAnim, "Alpha", 1), anim(r.flashAnim, "Alpha", 2)
	r.flashIn:SetFromAlpha(0)
	r.flashOut:SetToAlpha(0)
	r.flashOut:SetSmoothing("OUT")
	r.edge = ns.Looks.popEdge(fx)
	for _, name in ipairs({ "front", "back" }) do
		local b = CreateFrame("Frame", nil, f:GetParent())
		b:SetAllPoints(f)
		b:EnableMouse(false)
		if f.effects then b:SetIgnoreParentAlpha(true) end   -- at full on an idle icon, as fx is
		r[name] = b
	end
	r.clip = CreateFrame("Frame", nil, r.front)
	r.clip:SetAllPoints()
	r.clip:SetClipsChildren(true)
	r.clip:EnableMouse(false)
	r.parts.ring, r.parts.star = newPart(r.front, RING), newPart(r.front, STAR)
	local where = { back = r.back, front = r.front, clip = r.clip }
	for name, at in pairs(ns.Looks.POP_PARTS) do r.parts[name] = newPart(where[at]) end
	r.all = { r.motionScale, r.motionMove, r.flashAnim }
	if r.iconMotion then table.insert(r.all, r.iconMotion) end
	for _, e in ipairs(r.edge or {}) do table.insert(r.all, e.group) end
	for _, p in pairs(r.parts) do table.insert(r.all, p.group) end
	-- A hidden frame holds its animations, so a pop cut short by a hide (its group hiding as combat
	-- ends) would finish when the icon next shows. A hide ends it instead: fx hides with the icon,
	-- and the stop takes the bursts beside it down too.
	-- Not under an aura button: scripts there never run, and the button stops what it plays when
	-- the aura goes.
	if not icon then fx:SetScript("OnHide", function() r:stop() end) end
	return r
end

-- Every animation group of the rig (the caller doesn't change the list): none has a script, so
-- the same groups can be handed to an aura button, which plays them on each new aura.
function Rig:groups() return self.all end

-- Stops every group, and puts the flash and burst textures back at alpha 0, whatever a group
-- stopped before its end leaves them at.
function Rig:stop()
	for _, g in ipairs(self.all) do g:Stop() end
	self.flash:SetAlpha(0)
	for _, p in pairs(self.parts) do p.tex:SetAlpha(0) end
end

-- The bursts' frames under the icon's parent now (a layout or the preview can move the icon to
-- another), at the light's level. Not in combat: a parent there may be a protected group's frame;
-- the icon's next pop out of combat catches up.
function Rig:home()
	local f, front, back = self.f, self.front, self.back
	local parent = f:GetParent()
	if parent ~= front:GetParent() and not InCombatLockdown() then
		front:SetParent(parent)
		back:SetParent(parent)
	end
	local level = self.level or f:GetFrameLevel() + 12
	self.fx:SetFrameLevel(level)
	front:SetFrameLevel(level)
end

-- The motion's steps: step i scales from a to b, or moves by x, y, over dur with smoothing (the
-- aura's icon's too, on the aura route).
function Rig:scaleStep(i, a, b, dur, smoothing)
	for _, s in ipairs({ self.scale[i], self.iconScale and self.iconScale[i] }) do
		s:SetScaleFrom(a, a); s:SetScaleTo(b, b); s:SetDuration(dur); s:SetSmoothing(smoothing)
	end
end
function Rig:moveStep(i, x, y, dur, smoothing)
	for _, m in ipairs({ self.move[i], self.iconMove and self.iconMove[i] }) do
		m:SetOffset(x, y); m:SetDuration(dur); m:SetSmoothing(smoothing)
	end
end

-- The motion for the style: S its size, k the duration multiplier, h the icon's height. Returns
-- its groups in use (a table of group -> true), or nil for none. The steps a motion doesn't use
-- come after its own, scale by 1 or move by 0 and take SHORTEST each: a group that plays them (the
-- aura route plays every group) changes nothing.
function Rig:styleMotion(motion, S, k, h)
	local scales, moves = 0, 0
	if motion == "pop" then
		self:scaleStep(1, 1, S, 0.12 * k, "OUT")
		self:scaleStep(2, S, 1, 0.25 * k, "IN_OUT")
		scales = 2
	elseif motion == "hop" then
		local up = h * (S - 1) * 0.8
		self:moveStep(1, 0, up, 0.12 * k, "OUT")
		self:moveStep(2, 0, -up, 0.2 * k, "IN")
		moves = 2
	elseif motion == "shake" or motion == "shakeV" then   -- side to side, or up and down
		local d = h * (S - 1) * 0.3
		local sx, sy = motion == "shake" and d or 0, motion == "shakeV" and d or 0
		self:moveStep(1, sx, sy, 0.04 * k, "NONE")
		self:moveStep(2, -2 * sx, -2 * sy, 0.07 * k, "NONE")
		self:moveStep(3, 2 * sx, 2 * sy, 0.07 * k, "NONE")
		self:moveStep(4, -sx, -sy, 0.05 * k, "NONE")
		moves = 4
	elseif motion == "bounce" then   -- overshoot, dip, settle
		local u, o = 1 - (S - 1) * 0.25, 1 + (S - 1) * 0.15
		self:scaleStep(1, 1, S, 0.12 * k, "OUT")
		self:scaleStep(2, S, u, 0.12 * k, "IN_OUT")
		self:scaleStep(3, u, o, 0.1 * k, "IN_OUT")
		self:scaleStep(4, o, 1, 0.08 * k, "IN")
		scales = 4
	end
	for i = scales + 1, MOTION_STEPS do self:scaleStep(i, 1, 1, SHORTEST, "NONE") end
	for i = moves + 1, MOTION_STEPS do self:moveStep(i, 0, 0, SHORTEST, "NONE") end
	if scales + moves == 0 then return nil end
	return { [self.motionScale] = scales > 0 or nil, [self.motionMove] = moves > 0 or nil }
end

-- The rig's values for pop style st: size the icon's height (never read under a secure button),
-- c the colour, school the icon's, muted a dimmer flash (a pop that can't be acted on). Marks
-- the groups play() plays.
function Rig:style(st, size, c, school, muted)
	local k = 1 / math.max(st.speed, 0.1)   -- duration multiplier
	local on = self.playing
	wipe(on)
	self:home()
	for g in pairs(self:styleMotion(st.motion, st.size, k, size) or {}) do on[g] = true end
	local flash = st.flash
	if flash == "edge" and not self.edge then flash = "plain" end
	if flash == "edge" then
		for _, e in ipairs(self.edge) do
			local s = size * e.grow
			e.tex:SetSize(s, s)
			e.tex:SetVertexColor(c[1] * 0.6 + 0.4, c[2] * 0.6 + 0.4, c[3] * 0.6 + 0.4)
			e.group.flip:SetDuration(0.75 * k)
			e.group.show:SetDuration(0.75 * k)
			on[e.group] = true
		end
	elseif flash == "plain" then
		self.flash:SetVertexColor(c[1], c[2], c[3])
		local peak = muted and 0.4 or 0.8
		self.flashIn:SetToAlpha(peak); self.flashIn:SetDuration(0.06 * k)
		self.flashOut:SetFromAlpha(peak); self.flashOut:SetDuration(0.3 * k)
		on[self.flashAnim] = true
	end
	local burst = st.burst
	-- On the aura route (self.guard) each burst part is styled on its own, so one refused call
	-- leaves the others, and the final show and hide, done.
	local function part(name, fn)
		if self.guard then ns.try("aura pop " .. name, fn) else fn() end
	end
	if burst == "ring" or burst == "both" then
		part("ring", function()
			stylePart(self.parts.ring, RING, self.front, size, c, k)
			on[self.parts.ring.group] = true
		end)
	end
	if burst == "star" or burst == "both" then
		part("star", function()
			stylePart(self.parts.star, STAR, self.front, size, c, k)
			on[self.parts.star.group] = true
		end)
	end
	-- A drawn burst: sized by the icon with its frame; its back parts under the icon as it stands
	-- now (for an end flash's pop, the icon it covers: a totem bar slot, so the shapes and their
	-- dark disc stay behind that slot's neighbours too).
	local drawn = ns.Looks.popParts(burst, school)
	if drawn then
		local over = self.f.over or self.f
		self.back:SetFrameLevel(math.max(over:GetFrameLevel() - 1, 0))
		local h = size + 2 * ns.Looks.outerEdge(over)
		for _, spec in ipairs(drawn) do
			part(spec.name, function()
				local p = self.parts[spec.name]
				if spec.shift then stylePart(p, spec, self.clip, size, c, k)
				else stylePart(p, spec, p.tex:GetParent(), h, c, k) end
				on[p.group] = true
			end)
		end
	end
	-- Only the parts this style uses are shown (each sized and anchored above).
	self:showParts()
end

function Rig:showParts()
	local on = self.playing
	for _, p in pairs(self.parts) do p.tex:SetShown(on[p.group] or false) end
end

-- Every part hidden and nothing marked to play: a restyle that must not draw starts here.
function Rig:hideAll()
	wipe(self.playing)
	self.flash:Hide()
	for _, e in ipairs(self.edge or {}) do e.tex:Hide() end
	for _, p in pairs(self.parts) do p.tex:Hide() end
end

-- Shows the flashes style() marked and hides the rest, as style() does the burst parts. An aura
-- button plays every group handed to it, so on the aura route a part the style doesn't use must
-- draw nothing whatever its group does.
function Rig:showPlaying()
	local on = self.playing
	self.flash:SetShown(on[self.flashAnim] == true)
	for _, e in ipairs(self.edge or {}) do e.tex:SetShown(on[e.group] == true) end
end

-- Stops every group, then plays those style() marked.
function Rig:play()
	self:stop()
	for _, g in ipairs(self.all) do
		if self.playing[g] then g:Play() end
	end
end

-- kind: ready | imbue | expired | killed | grounded (the tint); owner: whose style (nil: General's).
-- blocked: ready but it can't be cast (Fire Nova with no fire totem): grey and a dimmer flash,
-- whatever the Colour, so it never reads as the full ready pop.
-- Nothing on a frame that isn't visible (a combat-only group out of combat): it would wait there and
-- play when the frame next shows, for something long over.
-- The pop's colour for kind: the event's, or the school's for Ready and Ran out when style st says
-- so. A warning (killed early, grounded, the imbue dropping, blocked) always keeps its own.
local function popColor(st, kind, school)
	if st.colorBy == "school" and ns.Looks.POP_EVENTS[kind] then
		return ns.SCHOOL_COLOR[school] or ns.SCHOOL_COLOR.spirit
	end
	return POP_TINT[kind] or POP_TINT.ready
end

function E.pop(f, kind, owner)
	if not f:IsVisible() then return end
	kind = kind or "ready"
	local st = ns.Style.get(owner, "pop")
	local school = ns.Looks.schoolOf(f)
	local c = popColor(st, kind, school)
	f.popRig = f.popRig or newRig(f)
	f.popRig:stop()   -- nothing plays while its values change
	-- popSize: the icon's size, set by whoever knows it where a read could be secret (an end flash
	-- over the totem bar's slot, under its secure button).
	f.popRig:style(st, math.max(f.popSize or f:GetHeight(), 8), c, school, kind == "blocked")
	f.popRig:play()
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
function E.endFlash(parent, anchor, owner, over)
	over = over or anchor
	local kf = CreateFrame("Frame", nil, parent)
	kf:SetAllPoints(anchor)
	kf:SetFrameLevel(anchor:GetFrameLevel() + 8)
	kf:EnableMouse(false)
	kf.pop = CreateFrame("Frame", nil, kf)
	kf.pop:SetAllPoints()
	kf.pop.over = over   -- the icon whose school and frame its pop's looks take
	kf.body = CreateFrame("Frame", nil, kf.pop)
	kf.body:SetAllPoints()
	kf.body:SetAlpha(0)
	kf.glow = E.glow(kf.body, over, owner)
	kf.glow:color(1, 0.12, 0.08)
	kf.icon = kf.body:CreateTexture(nil, "ARTWORK")
	kf.icon:SetAllPoints()
	ns.cropIconExact(kf.icon)
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
	ns.cropIconExact(kf.mark.icon)
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
		-- fitSize: the picture's size, set by whoever lays it out where the flash sits in from anchor
		-- (the totem bar's slots, inside their border), so no size is read under a secure button.
		local size = self.fitSize or anchor:GetWidth()
		self.pop.popSize = size
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
		if opts.pop then E.pop(self.pop, opts.expired and "expired" or opts.grounded and "grounded" or "killed", owner) end
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

------------------------------------------------------------------------
-- The effect host: an element's one glow and one pop, in its one glow look and pop style. Other
-- glows an element has (a ready glow on its gate, its timer's expiring glow, an end flash's red
-- glow) are E.glow with the element as owner: one look and style, several places it shows. Two
-- routes behind the same calls:
-- * Frame route: our own icon draws the element, so the host shows the glow and plays the pop
--   directly.
-- * Aura route: Blizzard's aura button draws it (Elemental Focus, Purge). Its glow is a clip look
--   lit while the aura is up (ns.makeClipLook, inverted), drawn by the engine outside the button's
--   tree, in every look. Its pop is a rig made under the button as Blizzard makes it (h:bind),
--   every group of it handed over once with AddAuraAssignedAnimation: the button plays them on
--   each new aura, in combat too (tested 2026-10-01; a recast over a live aura is an update and
--   plays none). The motion moves the aura's icon and our body frame over it (the border and the
--   pop's light) together. Restyled only out of combat with auras readable (the aura slot's
--   restyle); nothing under the button runs a script or is read.
------------------------------------------------------------------------
local Host = {}
Host.__index = Host

-- A pop that draws and moves nothing: the aura route's rig while the element's Pop is off.
local NO_POP = { colorBy = "event", flash = "none", burst = "none", motion = "none", size = 1, speed = 1 }

-- f: the element's icon; key: its style owner (an element key, "totembar", or nil for General's).
-- Frame route: h.glowF is its glow (E.glow over f). Aura route, opts.aura:
--   slot                     the aura slot showing the aura (ns.makeAuraSlot): the glow waits
--                            until its sensor took the same filters
--   parent, sensorParent     what the glow's chain and its sensor hang from
--   unit, needUnit, filter   as ns.makeClipLook's; ids() or candidates(), the slot's own
--   popKind, popOn()         its pop's kind (the colour; default "ready"), and whether it pops
--   sites                    names for the sensor's waiting work and caught errors
function E.host(f, key, opts)
	local h = setmetatable({ f = f, key = key }, Host)
	local a = opts and opts.aura
	if not a then
		h.glowF = E.glow(f, f, key)
		return h
	end
	h.aura = a
	h.up = ns.makeClipLook(f, {
		key = key, owner = key, invert = true, glowOnly = true,
		parent = a.parent, sensorParent = a.sensorParent or a.parent,
		unit = a.unit, needUnit = a.needUnit, filter = a.filter, ids = a.ids, candidates = a.candidates,
		agrees = function() return a.slot.applied ~= nil and a.slot.applied == h.up.applied end,
		sites = a.sites,
	})
	return h
end

-- The glow on or off; r, g, b: a colour of its own (killed early's red) in place of the style's.
-- Frame route: shown now, fitted to the icon. Aura route: wanted, and drawn exactly while the aura
-- is up.
function Host:glow(on, r, g, b)
	if self.up then
		self.up:setParts(false, false, false, false, on)
		self.up:want(on)
		return
	end
	local gl = self.glowF
	if on then
		gl:fit(self.f:GetWidth())
		if r then gl:color(r, g, b)
		elseif gl.fixed then gl.fixed = nil; gl:restyle() end
	end
	gl:SetShown(on and true or false)
end

-- The pop for kind (default ready), now: nothing while the icon isn't visible. On the aura route
-- the button plays it; this does nothing.
function Host:pop(kind)
	if self.aura then return end
	E.pop(self.f, kind or "ready", self.key)
end

-- The glow restyled from its style, and fitted to an icon of size (the aura route's glow fits as
-- its sensor takes a size).
function Host:restyle()
	if self.up then self.up:reshape() else self.glowF:restyle() end
end
function Host:fit(size)
	if self.glowF then self.glowF:fit(size) end
end

-- Levels over the element's icon (its container's is the text's + 5, ns.makeAuraSlot): the glow
-- over the button, the pop's light over that. Set from our own levels, never read from Blizzard's.
local GLOW_LEVEL, POP_LEVEL = 11, 13

-- Aura route: the glow's levels now, from the element's own frame (out of combat).
function Host:levelGlow()
	if self.up then self.up:setLevel(self.f.textFrame:GetFrameLevel() + GLOW_LEVEL) end
end

-- Aura route: the element's border frame on the button, covering it, under the rig's body when
-- there is one (so the two move together), in the element's school colour (ns.Looks).
function Host:makeEdge(button)
	local edge = CreateFrame("Frame", nil, self.body or button)
	edge:SetAllPoints(button)
	edge.owner = self.key
	return edge
end

-- Aura route: the rig on Blizzard's button, from the aura slot's onButton (as Blizzard makes the
-- button): a body frame over the button that moves with its icon (the caller hangs the element's
-- border there), the rig on it with its light above the element's text, styled, and every group
-- handed to the button. Returns the body.
function Host:bind(button, icon)
	if self.body then return self.body end
	local level = self.f.textFrame:GetFrameLevel() + POP_LEVEL
	local body = CreateFrame("Frame", nil, button)
	body:SetAllPoints(button)
	body.over = self.f   -- the element's own icon: its school, its frame's reach, the level behind it
	self.body, self.handed = body, 0
	local ok = ns.try("aura pop " .. self.key, function()
		self.rig = newRig(body, icon, level)
		self.rig.guard = true
		self:stylePop(ns.sizeOf(self.key))   -- styled before its groups are handed over
	end)
	if not ok or not button.AddAuraAssignedAnimation then return body end
	for _, g in ipairs(self.rig:groups()) do
		if ns.try("aura pop hand-off " .. self.key, button.AddAuraAssignedAnimation, button, g) then
			self.handed = self.handed + 1
		end
	end
	return body
end

-- Aura route, out of combat with auras readable (the aura slot's restyle): the rig for an icon of
-- size, in the element's pop style while it pops (popOn), else drawing and moving nothing.
function Host:stylePop(size)
	local rig = self.rig
	if not rig then return end
	local pops = self.aura.popOn()
	if not pops then rig:hideAll() end   -- Pop off wins even if a setter below is refused
	ns.try("aura pop style " .. self.key, function()
		local st = pops and ns.Style.get(self.key, "pop") or NO_POP
		local school = ns.Looks.schoolOf(self.f)
		rig:style(st, size, popColor(st, self.aura.popKind or "ready", school), school)
	end)
	-- Whatever styling did or didn't finish, the parts shown are exactly those marked to play.
	rig:showParts()
	rig:showPlaying()
end

-- Aura route: the glow's sensor made (out of combat, auras readable), refiltered with the slot,
-- pointed at a unit, its levels and look now (after a layout, a size or a look change).
function Host:setup() if self.up then self.up:setup() end end
function Host:refilter() if self.up then self.up:refilter() end end
function Host:follow(unit) return not self.up or self.up:follow(unit) end
function Host:setLevel(lv) if self.up then self.up:setLevel(lv) end end
function Host:style()
	if not self.up then return end
	self.up:reshape()
	self.up:style()
end
function Host:checkIDs() if self.up then self.up:checkIDs() end end

-- For /sf debug: one line of the aura route's state.
function Host:describe()
	if not self.up then return "frame route" end
	return string.format("glow %s; pop %s, %d of %d groups handed", self.up:describe(),
		self.rig and "made" or "not made", self.handed or 0, self.rig and #self.rig:groups() or 0)
end
