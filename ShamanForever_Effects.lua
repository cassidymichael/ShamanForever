-- Effects

local _, ns = ...

local E = {}
ns.Effects = E

-- The pulsing glow
-- Under Blizzard's aura button (underButton) the button plays the animations: g:bindButton hands
-- -- them over.
local glows = {}
local auraGlows = {}
function E.glow(parent, over, owner, opts)
	local underButton = opts and opts.underButton or false
	local g = CreateFrame("Frame", nil, parent)
	g.owner, g.underButton = owner, underButton
	-- Never Blizzard's aura button: a glow under it takes its owner's school and no frame.
	g.over = not underButton and (over or parent) or nil
	if not underButton then table.insert(glows, g) end
	g:SetAllPoints(over or parent)
	g:EnableMouse(false)
	g.inner = CreateFrame("Frame", nil, g)
	g.inner:SetAllPoints()
	g.anim = g.inner:CreateAnimationGroup()
	g.anim:SetLooping("BOUNCE")
	g.fade = g.anim:CreateAnimation("Alpha")
	g.fade:SetFromAlpha(1); g.fade:SetSmoothing("IN_OUT")
	g.parts = {}
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
	-- Not under the aura button: script handlers there are refused, and it plays allAnims() itself.
	if not underButton then
		g:SetScript("OnShow", function(self) play(self, true) end)
		g:SetScript("OnHide", function(self) play(self, false) end)
	end
	-- Under the button: animations handed over once (it refuses a repeat).
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
	function g:allAnims()
		local out = { self.anim }
		local p = parts(self.look)
		for _, a in ipairs(p and p.aura or {}) do table.insert(out, a) end
		return out
	end
	function g:restyle()
		local st = ns.Style.get(self.owner, "glow")
		local look = drawn(ns.Style.look("glow", st.look))
		-- Under the button: a new look only out of combat with auras readable.
		if underButton and self.look and look ~= self.look then
			local ok = self.button ~= nil and ns.aurasReadable()
			local p = ok and parts(look)
			for _, a in ipairs(p and p.aura or {}) do ok = ok and self:hand(a) end
			if not ok then look = self.look end
		end
		if look ~= self.look then
			local running = not underButton and self.look ~= nil and self:IsShown()
			if running then play(self, false) end
			local old = self.look and self.parts[self.look.key]
			for _, r in ipairs(old and old.roots or {}) do r:Hide() end
			self.look, self.fitWidth = look, nil   -- next fit
			local p = parts(look)
			for _, r in ipairs(p and p.roots or {}) do r:Show() end
			if self.held then for _, r in ipairs(p and p.moving or {}) do r:Hide() end end
			if running then play(self, true) end
			if underButton and self.button then
				for _, a in ipairs(p and p.aura or {}) do ns.try("glow: aura parts", a.Play, a) end
			end
		end
		self.width = st.width   -- fit runs ten times a second for ready glows
		-- A running pulse restarts only when its timing changed.
		local retime = st.speed ~= self.speed or st.low ~= self.low
		self.speed, self.low = st.speed, st.low
		self.fade:SetDuration(st.speed)
		self.fade:SetToAlpha(look.steady and 1 or st.low)
		local k = self.fixed or st.color
		local p = parts(look)
		if p then look.style(self, p, st, k) end
		if self.iconSize then self:fit(self.iconSize) end
		-- IsShown is secret under the aura button
		if retime and not underButton and self:IsShown() then
			self.anim:Stop(); self.anim:Play()
			if p and p.paced then
				for _, a in ipairs(p.anims or {}) do a:Stop(); a:Play() end
			end
		end
	end
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
	function g:hold(secs)
		local p = self.look and self.parts[self.look.key]
		if p and p.moving then
			for _, a in ipairs(p.anims or {}) do a:Stop() end
			for _, r in ipairs(p.moving) do r:Hide() end
		end
		self.held, self.holdToken = true, (self.holdToken or 0) + 1
		local token = self.holdToken
		C_Timer.After(secs, function()
			if self.holdToken ~= token then return end
			self.held = false
			local q = self.look and self.parts[self.look.key]
			if not (q and q.moving) then return end
			for _, r in ipairs(q.moving) do r:Show() end
			if self:IsShown() then
				if q.paced then self.anim:Stop(); self.anim:Play() end
				for _, a in ipairs(q.anims or {}) do a:Play() end
			end
		end)
	end
	function g:color(r, gg, b) self.fixed = { r, gg, b, 1 }; self:restyle() end
	g:restyle()
	g:Hide()
	return g
end
-- Not those under an aura button; a parked glow restyles when taken again.
function E.applyStyle() for _, g in ipairs(glows) do if not g.parked then g:restyle() end end end

-- Owners whose glow under the button differs from their style (changes after a /reload).
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

-- The pop
-- No Scale, Rotation or Translation under the frame the motion moves: bursts sit on frames beside
-- -- the icon, flashes (fade and flip only) stay on it.
local POP_TINT = { ready = { 1, 0.82, 0.25 }, imbue = { 0.35, 0.65, 1 }, expired = { 0.95, 0.95, 0.95 }, killed = { 1, 0.15, 0.1 },
	grounded = { 0.56, 0.76, 0.92 }, blocked = { 0.6, 0.6, 0.6 } }
local BLACK = { 0, 0, 0 }
local RING = { name = "ring", atlas = "ArtifactsFX-YellowRing", file = "Interface\\Buttons\\UI-ActionButton-Border",
	layer = "OVERLAY", add = true, desat = true, from = 0.9, to = 2.2, dur = 0.45, a = 1 }
local STAR = { name = "star", atlas = "AftLevelup-WhiteStarBurst", file = "Interface\\Cooldown\\star4",
	layer = "BACKGROUND", add = true, desat = true, from = 1.2, to = 3.5, dur = 0.45, a = 1, spin = -0.5 }
local RIG_PARTS = { ring = RING, star = STAR }
local MOTION_STEPS = 4
local SHORTEST = 0.01   -- a burst part's shortest wait, and a motion step no motion uses (s)
local HOLD_MARGIN = 0.05   -- a glow's moving parts stay hidden this long past the motion (s)

local function anim(g, kind, order)
	local a = g:CreateAnimation(kind)
	a:SetOrder(order)
	if kind == "Scale" or kind == "Rotation" then a:SetOrigin("CENTER", 0, 0) end
	return a
end

-- One burst part: waits unseen (an Alpha holding 0), then grows, fades, turns and moves as one group.
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

local function stylePart(p, spec, parent, h, c, k, reach)
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
		local s = shift[1]
		t:SetPoint("TOPLEFT", parent, "TOPLEFT", -s * h, s * h)
		t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -s * h, s * h)
		g.grow:SetScaleTo(1, 1)
		local d = shift[2] - shift[1]
		g.move:SetOffset(-d * h, d * h)
	else
		local from = h * spec.from * (reach or 1)
		t:SetSize(from, from * (spec.sy or 1))
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

-- The rig on f: flashes above the icon's text, bursts on frames beside it.
local function newRig(f, icon, level)
	local r = setmetatable({ f = f, parts = {}, playing = {}, level = level }, Rig)
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
	r.flashAnim:SetToFinalAlpha(true)
	r.flashIn, r.flashOut = anim(r.flashAnim, "Alpha", 1), anim(r.flashAnim, "Alpha", 2)
	r.flashIn:SetFromAlpha(0)
	r.flashOut:SetToAlpha(0)
	r.flashOut:SetSmoothing("OUT")
	r.edge = ns.Looks.popEdge(fx)
	for _, name in ipairs({ "front", "back" }) do
		local b = CreateFrame("Frame", nil, f:GetParent())
		b:SetAllPoints(f)
		b:EnableMouse(false)
		if f.effects then b:SetIgnoreParentAlpha(true) end
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
	-- A hide ends a pop cut short (a hidden frame would finish it on its next show). Not under an aura
	-- -- button: no scripts run there.
	if not icon then fx:SetScript("OnHide", function() r:stop() end) end
	return r
end

function Rig:groups() return self.all end

function Rig:stop()
	for _, g in ipairs(self.all) do g:Stop() end
	self.flash:SetAlpha(0)
	for _, p in pairs(self.parts) do p.tex:SetAlpha(0) end
end

-- Not in combat: a parent there may be a protected frame.
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

function Rig:scaleStep(i, a, b, dur, smoothing)
	for _, s in ipairs({ self.scale[i], self.iconScale and self.iconScale[i] }) do
		s:SetScaleFrom(1, 1); s:SetScaleTo(b / a, b / a); s:SetDuration(dur); s:SetSmoothing(smoothing)
	end
end
function Rig:moveStep(i, x, y, dur, smoothing)
	for _, m in ipairs({ self.move[i], self.iconMove and self.iconMove[i] }) do
		m:SetOffset(x, y); m:SetDuration(dur); m:SetSmoothing(smoothing)
	end
end

function Rig:styleMotion(motion, S, k, h)
	local scales, moves, length = 0, 0, 0
	if motion == "pop" then
		self:scaleStep(1, 1, S, 0.12 * k, "OUT")
		self:scaleStep(2, S, 1, 0.25 * k, "IN_OUT")
		scales, length = 2, 0.37 * k
	elseif motion == "hop" then
		local up = h * (S - 1) * 0.8
		self:moveStep(1, 0, up, 0.12 * k, "OUT")
		self:moveStep(2, 0, -up, 0.2 * k, "IN")
		moves, length = 2, 0.32 * k
	elseif motion == "shake" or motion == "shakeV" then
		local d = h * (S - 1) * 0.3
		local sx, sy = motion == "shake" and d or 0, motion == "shakeV" and d or 0
		self:moveStep(1, sx, sy, 0.04 * k, "NONE")
		self:moveStep(2, -2 * sx, -2 * sy, 0.07 * k, "NONE")
		self:moveStep(3, 2 * sx, 2 * sy, 0.07 * k, "NONE")
		self:moveStep(4, -sx, -sy, 0.05 * k, "NONE")
		moves, length = 4, 0.23 * k
	elseif motion == "bounce" then
		local u, o = 1 - (S - 1) * 0.25, 1 + (S - 1) * 0.15
		self:scaleStep(1, 1, S, 0.12 * k, "OUT")
		self:scaleStep(2, S, u, 0.12 * k, "IN_OUT")
		self:scaleStep(3, u, o, 0.1 * k, "IN_OUT")
		self:scaleStep(4, o, 1, 0.08 * k, "IN")
		scales, length = 4, 0.42 * k
	end
	self.motionLength = length
	for i = scales + 1, MOTION_STEPS do self:scaleStep(i, 1, 1, SHORTEST, "NONE") end
	for i = moves + 1, MOTION_STEPS do self:moveStep(i, 0, 0, SHORTEST, "NONE") end
	if scales + moves == 0 then return nil end
	return { [self.motionScale] = scales > 0 or nil, [self.motionMove] = moves > 0 or nil }
end

function Rig:style(st, size, c, school, muted)
	local k = 1 / math.max(st.speed, 0.1)
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
	local burst = ns.Style.field("pop", "burst").byKey[st.burst] or ns.Style.choice("pop", "burst", "none")
	-- On the aura route each part is styled on its own, so a refused call leaves the others.
	local function part(name, fn)
		if self.guard then ns.try("aura pop " .. name, fn) else fn() end
	end
	for _, name in ipairs(burst.rigParts or {}) do
		part(name, function()
			stylePart(self.parts[name], RIG_PARTS[name], self.front, size, c, k, st.reach)
			on[self.parts[name].group] = true
		end)
	end
	local drawn = ns.Looks.popParts(burst.key, school)
	if drawn then
		local over = self.f.over or self.f
		self.back:SetFrameLevel(math.max(over:GetFrameLevel() - 1, 0))
		local h = size + 2 * ns.Looks.outerEdge(over)
		for _, spec in ipairs(drawn) do
			part(spec.name, function()
				local p = self.parts[spec.name]
				if spec.shift then stylePart(p, spec, self.clip, size, c, k)
				else stylePart(p, spec, p.tex:GetParent(), h, c, k, st.reach) end
				on[p.group] = true
			end)
		end
	end
	self:showParts()
	for _, e in ipairs(self.edge or {}) do e.tex:SetShown(on[e.group] == true) end
end

function Rig:showParts()
	local on = self.playing
	for _, p in pairs(self.parts) do p.tex:SetShown(on[p.group] or false) end
end

function Rig:hideAll()
	wipe(self.playing)
	self.flash:Hide()
	for _, e in ipairs(self.edge or {}) do e.tex:Hide() end
	for _, p in pairs(self.parts) do p.tex:Hide() end
end

function Rig:showPlaying()
	local on = self.playing
	self.flash:SetShown(on[self.flashAnim] == true)
	for _, e in ipairs(self.edge or {}) do e.tex:SetShown(on[e.group] == true) end
end

function Rig:play()
	self:stop()
	for _, g in ipairs(self.all) do
		if self.playing[g] then g:Play() end
	end
end

-- blocked: ready but can't be cast; grey and a dimmer flash.
-- Nothing on a hidden frame: it would play on its next show.
local function popColor(st, kind, school)
	if st.colorBy == "school" and ns.Looks.POP_EVENTS[kind] then
		local theme = ns.THEME
		return theme.color[school] or theme.color[theme.fallback]
	end
	return POP_TINT[kind] or POP_TINT.ready
end

function E.pop(f, kind, owner)
	if not f:IsVisible() then return end
	kind = kind or "ready"
	local st = ns.Style.get(owner, "pop")
	local school = ns.Looks.effectSchool(f)
	local c = popColor(st, kind, school)
	f.popRig = f.popRig or newRig(f)
	f.popRig:stop()
	-- popSize: set by whoever knows it, where a read could be secret.
	f.popRig:style(st, math.max(f.popSize or f:GetHeight(), 8), c, school, kind == "blocked")
	f.popRig:play()
	local length = f.popRig.motionLength
	if length > 0 then
		for _, g in ipairs(glows) do
			local up = g:GetParent()
			while up and up ~= f do up = up:GetParent() end
			if up then g:hold(length + HOLD_MARGIN) end
		end
	end
end

-- The end of a totem: Killed early, Ran out, Grounded, Ran out softly. Nothing here reads a secret:
-- -- the gone totem's last duration object goes to a curve, then SetAlpha.
local killedCurve = ns.curve({ 0, 0, 1.2, 0, 1.25, 1, 36000, 1 })
local expiredCurve = ns.curve({ 0, 1, 1.2, 1, 1.25, 0, 36000, 0 })
function E.endFlash(parent, anchor, owner, over)
	over = over or anchor
	local kf = CreateFrame("Frame", nil, parent)
	kf:SetAllPoints(anchor)
	kf:SetFrameLevel(anchor:GetFrameLevel() + 8)
	kf:EnableMouse(false)
	kf.pop = CreateFrame("Frame", nil, kf)
	kf.pop:SetAllPoints()
	kf.pop.over = over
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
	kf.quick = kf.body:CreateAnimationGroup()
	local qIn = kf.quick:CreateAnimation("Alpha")
	qIn:SetFromAlpha(0); qIn:SetToAlpha(1); qIn:SetDuration(0.05); qIn:SetOrder(1)
	local qOut = kf.quick:CreateAnimation("Alpha")
	qOut:SetFromAlpha(1); qOut:SetToAlpha(0); qOut:SetDuration(0.5); qOut:SetStartDelay(0.2); qOut:SetOrder(2)
	kf.quick:SetScript("OnFinished", function() kf.body:SetAlpha(0); kf.glow:Hide() end)
	kf.soft = kf.body:CreateAnimationGroup()
	local sIn = kf.soft:CreateAnimation("Alpha")
	sIn:SetFromAlpha(0); sIn:SetToAlpha(1); sIn:SetDuration(0.1); sIn:SetOrder(1)
	local sOut = kf.soft:CreateAnimation("Alpha")
	sOut:SetFromAlpha(1); sOut:SetToAlpha(0); sOut:SetDuration(0.9); sOut:SetStartDelay(0.3); sOut:SetOrder(2)
	kf.soft:SetScript("OnFinished", function() kf.body:SetAlpha(0); kf.glow:Hide() end)
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
	ns.Looks.followMask(over, kf.icon, kf.red, kf.mark.icon)
	-- SetTexture takes a secret
	function kf:setIcon(icon)
		ns.try("killed flash: icon", self.icon.SetTexture, self.icon, icon)
		ns.try("killed flash: icon", self.mark.icon.SetTexture, self.mark.icon, icon)
	end
	-- dur nil: play regardless (previews).
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
		-- fitSize: set by the layout, so no size is read under a secure button.
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
	function kf:stop()
		self.flash:Stop(); self.quick:Stop(); self.soft:Stop()
		self.body:SetAlpha(0); self.glow:Hide(); self.mark:Hide()
		self.markToken = nil
	end
	kf:SetScript("OnHide", function(self) self:stop() end)
	return kf
end

-- The effect host
-- -- Frame route: our own icon. Aura route: Blizzard's aura button, whose pop plays on each new
-- -- aura and whose glow is a clip look lit while the aura is up.
local Host = {}
Host.__index = Host

local NO_POP = { colorBy = "event", flash = "none", burst = "none", motion = "none", size = 1, speed = 1 }

function E.host(f, key, opts)
	local h = setmetatable({ f = f, key = key }, Host)
	local a = opts and opts.aura
	if not a then
		h.glowF = E.glow(f, f, key)
		return h
	end
	h.aura = a
	if a.popOnly then return h end
	h.up = ns.makeClipLook(f, {
		key = key, owner = key, invert = true, glowOnly = true,
		parent = a.parent, sensorParent = a.sensorParent or a.parent,
		unit = a.unit, needUnit = a.needUnit, filter = a.filter, ids = a.ids, candidates = a.candidates,
		agrees = function() return a.slot.applied ~= nil and a.slot.applied == h.up.applied end,
		sites = a.sites,
	})
	return h
end

function Host:glow(on, r, g, b)
	if self.up then
		self.up:setParts(false, false, false, false, on)
		self.up:want(on)
		return
	end
	local gl = self.glowF
	if not gl then return end
	if on then
		gl:fit(self.f:GetWidth())
		if r then gl:color(r, g, b)
		elseif gl.fixed then gl.fixed = nil; gl:restyle() end
	end
	gl:SetShown(on and true or false)
end

function Host:pop(kind)
	if self.aura then return end
	E.pop(self.f, kind or "ready", self.key)
end

function Host:restyle()
	if self.up then self.up:reshape() elseif self.glowF then self.glowF:restyle() end
end
function Host:fit(size)
	if self.glowF then self.glowF:fit(size) end
end

-- Levels are ours, never read from Blizzard's.
local GLOW_LEVEL, POP_LEVEL = 11, 13

function Host:levelGlow()
	if self.up then self.up:setLevel(self.f.textFrame:GetFrameLevel() + GLOW_LEVEL) end
end

function Host:makeEdge(button)
	local edge = CreateFrame("Frame", nil, self.body or button)
	edge:SetAllPoints(button)
	edge.owner = self.key
	return edge
end

function Host:bind(button, icon)
	if self.body then return self.body end
	local level = self.f.textFrame:GetFrameLevel() + (self.aura.popLevel or POP_LEVEL)
	local body = CreateFrame("Frame", nil, button)
	body:SetAllPoints(button)
	body.over = self.f
	self.body, self.handed = body, 0
	local ok = ns.try("aura pop " .. self.key, function()
		self.rig = newRig(body, icon, level)
		self.rig.guard = true
		self:stylePop(ns.sizeOf(self.key))
	end)
	if not ok or not button.AddAuraAssignedAnimation then return body end
	for _, g in ipairs(self.rig:groups()) do
		if ns.try("aura pop hand-off " .. self.key, button.AddAuraAssignedAnimation, button, g) then
			self.handed = self.handed + 1
		end
	end
	return body
end

function Host:stylePop(size)
	local rig = self.rig
	if not rig then return end
	local pops = self.aura.popOn()
	if not pops then rig:hideAll() end   -- Pop off wins even if a setter below is refused
	ns.try("aura pop style " .. self.key, function()
		local st = pops and ns.Style.get(self.key, "pop") or NO_POP
		local school = ns.Looks.effectSchool(self.f)
		rig:style(st, size, popColor(st, self.aura.popKind or "ready", school), school)
	end)
	-- Whatever styling did or didn't finish, the parts shown are exactly those marked to play.
	rig:showParts()
	rig:showPlaying()
end

function Host:setQuiet(on)
	local rig = self.rig
	if not rig then return end
	local a = on and 0 or 1
	for _, fr in ipairs({ rig.fx, rig.front, rig.back }) do fr:SetAlpha(a) end
end

function Host:motionLength() return self.rig and self.rig.motionLength or 0 end

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

function Host:describe()
	if not self.aura then return "frame route" end
	return string.format("glow %s; pop %s, %d of %d groups handed", self.up and self.up:describe() or "none",
		self.rig and "made" or "not made", self.handed or 0, self.rig and #self.rig:groups() or 0)
end
