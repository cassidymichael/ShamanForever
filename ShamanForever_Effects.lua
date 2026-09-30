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
--   lookFor()    the look's key, in place of its style's (colour, speed and the rest still come
--                from the style): a warning's own Glow look (Shields' No shield, Flame Shock's Not
--                on target: their clip looks, and the options' previews)
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
	g.owner, g.lookFor, g.underButton = owner, opts and opts.lookFor, underButton
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
		local look = drawn(ns.Style.look("glow", self.lookFor and self.lookFor() or st.look))
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
-- part: a motion (none, grow, bounce, hop, shake) with a size and speed; a flash over the icon
-- (plain, or Blizzard's edge flash); a burst (a ring spreading out, a star behind it, or one of
-- ns.Looks' drawn bursts); and their colour, by what happened or by school. Every part is built
-- on the frame the first time it pops.
local POP_TINT = { ready = { 1, 0.82, 0.25 }, imbue = { 0.35, 0.65, 1 }, expired = { 0.95, 0.95, 0.95 }, killed = { 1, 0.15, 0.1 },
	grounded = { 0.56, 0.76, 0.92 }, blocked = { 0.6, 0.6, 0.6 } }
E.POP_TINT = POP_TINT
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
-- blocked: ready but it can't be cast (Fire Nova with no fire totem): grey and a dimmer flash,
-- whatever the Colour, so it never reads as the full ready pop.
-- Nothing on a frame that isn't visible (a combat-only group out of combat): it would wait there and
-- play when the frame next shows, for something long over.
function E.pop(f, kind, owner)
	if not f:IsVisible() then return end
	kind = kind or "ready"
	local st = ns.Style.get(owner, "pop")
	local x = popFx(f)
	local motion, S = st.motion, st.size
	local k = 1 / math.max(st.speed, 0.1)   -- duration multiplier
	-- popSize: the icon's size, set by whoever knows it where a read could be secret (an end flash
	-- over the totem bar's slot, under its secure button).
	local h = math.max(f.popSize or f:GetHeight(), 8)
	for _, m in ipairs({ "grow", "bounce", "hop", "shake", "shakeV" }) do x[m]:Stop() end
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
	elseif motion == "bounce" then   -- overshoot, dip, settle
		local a, u, o = x.bounce.a, 1 - (S - 1) * 0.25, 1 + (S - 1) * 0.15
		a[1]:SetScaleFrom(1, 1); a[1]:SetScaleTo(S, S); a[1]:SetDuration(0.12 * k)
		a[2]:SetScaleFrom(S, S); a[2]:SetScaleTo(u, u); a[2]:SetDuration(0.12 * k)
		a[3]:SetScaleFrom(u, u); a[3]:SetScaleTo(o, o); a[3]:SetDuration(0.1 * k)
		a[4]:SetScaleFrom(o, o); a[4]:SetScaleTo(1, 1); a[4]:SetDuration(0.08 * k)
		x.bounce:Play()
	end
	-- The colour: the event's, or the school's for Ready and Ran out when the style says so. A
	-- warning (killed early, grounded, the imbue dropping, blocked) always keeps its own.
	local muted = kind == "blocked"
	local c = POP_TINT[kind] or POP_TINT.ready
	if st.colorBy == "school" and ns.Looks.POP_EVENTS[kind] then
		c = ns.SCHOOL_COLOR[ns.Looks.schoolOf(f)] or ns.SCHOOL_COLOR.spirit
	end
	x.flashAnim:Stop()
	local flash = st.flash
	if flash == "edge" and not ns.Looks.popFlash(x, c, k, h) then flash = "plain" end
	if flash == "plain" then
		x.flash:SetVertexColor(c[1], c[2], c[3])
		local a, peak = x.flashAnim.a, muted and 0.4 or 0.8
		a[1]:SetFromAlpha(0); a[1]:SetToAlpha(peak); a[1]:SetDuration(0.06 * k)
		a[2]:SetFromAlpha(peak); a[2]:SetToAlpha(0); a[2]:SetDuration(0.3 * k)
		x.flashAnim:Play()
	end
	-- The ring spreads from just inside the icon to 2.2 icon widths; the star from 1.2 to 3.5.
	x.bursts.stop(x.ring); x.bursts.stop(x.star)
	local burst = st.burst
	if burst == "ring" or burst == "both" then
		x.ring:SetDesaturated(true)
		x.ring:SetVertexColor(c[1], c[2], c[3])
		x.ring:SetSize(h * 0.9, h * 0.9)
		x.bursts.play(x.ring, { dur = 0.45 * k, from = h * 0.9, to = h * 2.2 })
	end
	if burst == "star" or burst == "both" then
		x.star:SetDesaturated(true)
		x.star:SetVertexColor(c[1], c[2], c[3])
		x.star:SetSize(h, h)
		x.bursts.play(x.star, { dur = 0.45 * k, from = h * 1.2, to = h * 3.5, spin = -0.5 })
	end
	ns.Looks.popBurst(x, f, burst, c, k, h)   -- a drawn burst (shapes, painted, rune, by school)
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

-- A grow-and-settle pop as an animation group on region (a texture or frame), sized and timed by
-- owner's pop style: the one kind of pop Blizzard's aura button can play for us (Elemental Focus),
-- and its previews. restyle() takes the current style; on = false makes it a no-op (scale 1).
function E.growPop(region, owner)
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
