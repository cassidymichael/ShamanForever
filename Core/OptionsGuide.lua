-- Guide page: slides on how the HUD fits together, stepped with Next and Previous
local ADDON, ns = ...
local W = ns.Widgets
local E, P, MOD = ns.Elements, ns.Profiles, ns.Modules
local OA, S, FR = ns.OptionsArt, ns.Style, ns.Frames

local GD = {}
ns.Guide = GD

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
local BOARD_W = 600
-- One spacing scale: a box's padding, the gap between blocks, a title's gap to its text
local PAD, GAP, UNDER = 12, 12, 6
local BLURB_Y, UNDER_BLURB = 50, 30   -- the blurb's top, and the room under it before the slide
GD.W, GD.PAD, GD.GAP = BOARD_W, PAD, GAP

-- Colours: Global, Group, Element, Bars
GD.GOLD = { 0.85, 0.66, 0.30 }
GD.TEAL = { 0.30, 0.72, 0.80 }
GD.ORANGE = { 0.92, 0.45, 0.22 }
GD.LAVENDER = { 0.73, 0.64, 0.90 }
GD.EMPH = "|cffffd100"

-- Slides
-- spec: title, blurb, order, build(f) (once, f the slide's frame, BOARD_W wide; it sets f.height, the
-- height it fills), steps ({ seconds, ... }: each step's hold, looping), step(f, x), tick(f, now)
-- (while it shows), refresh(f) (as the page repaints)
local slides = {}
function GD.add(spec)
	assert(spec.title and spec.build, "a guide slide needs a title and build")
	spec.seq = #slides
	table.insert(slides, spec)
	table.sort(slides, function(a, b)
		local x, y = a.order or 100, b.order or 100
		if x ~= y then return x < y end
		return a.seq < b.seq
	end)
end

-- Drawing helpers
-- Body text is white at one size; titles take a colour and the next size up
function GD.text(parent, str, x, y, width, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(3)
	if width then fs:SetWidth(width) end
	fs:SetText(str)
	return fs
end
function GD.title(parent, str, x, y, color)
	local fs = GD.text(parent, str, x, y, nil, "GameFontHighlightMedium")
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end
-- Its height as drawn (a line's when it has no width yet)
function GD.height(fs) return math.max(math.ceil(fs:GetStringHeight()), 14) end

-- A box filled faintly in color with one thin line of it; active: the slide's subject, brighter
function GD.box(parent, x, y, w, h, color, active)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetBackdrop(W.BACKDROP)
	b:SetBackdropColor(color[1], color[2], color[3], active and 0.10 or 0.045)
	b:SetBackdropBorderColor(color[1], color[2], color[3], active and 0.9 or 0.4)
	return b
end

-- A plain dark panel (a tile, a card)
function GD.panel(parent, x, y, w, h)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetBackdrop(W.BACKDROP)
	b:SetBackdropColor(0.07, 0.06, 0.05, 1)
	b:SetBackdropBorderColor(0.30, 0.23, 0.15, 1)
	return b
end

function GD.rect(parent, x, y, w, h, r, g, b, a)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

-- The dark band examples sit on
function GD.stage(parent, x, y, w, h)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	f:SetSize(w, h)
	f:SetBackdrop(W.BACKDROP)
	f:SetBackdropColor(0, 0, 0, 0.35)
	f:SetBackdropBorderColor(0, 0, 0, 0)
	return f
end

function GD.button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- The arrows Friz Quadrata has, for the bigger buttons that move on: Next, Previous, Styles explorer
GD.BACK, GD.ON = "\226\128\185  ", " \226\128\186"
function GD.bigButton(parent, text, width, onClick)
	local b = GD.button(parent, text, width, onClick)
	b:SetHeight(28)
	b:SetNormalFontObject("GameFontNormalMed3")
	b:SetHighlightFontObject("GameFontHighlightMedium")
	b:SetDisabledFontObject("GameFontDisableMed3")
	return b
end

-- A row of small squares, one lit: n of them; click(i) makes them buttons
local DOT = 18
function GD.dots(parent, n, click)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(n * DOT, DOT)
	row.dots = {}
	for i = 1, n do
		local d = CreateFrame(click and "Button" or "Frame", nil, row)
		d:SetSize(DOT, DOT)
		d:SetPoint("LEFT", row, "LEFT", (i - 1) * DOT, 0)
		d.tex = d:CreateTexture(nil, "ARTWORK")
		d.tex:SetSize(click and 9 or 6, click and 9 or 6)
		d.tex:SetPoint("CENTER")
		if click then
			d:SetScript("OnClick", function() click(i) end)
			local hl = d:CreateTexture(nil, "HIGHLIGHT")
			hl:SetSize(11, 11)
			hl:SetPoint("CENTER")
			hl:SetColorTexture(1, 0.82, 0, 0.35)
		end
		row.dots[i] = d
	end
	function row.light(on)
		for i, d in ipairs(row.dots) do
			if i == on then d.tex:SetColorTexture(1, 0.82, 0) else d.tex:SetColorTexture(0.58, 0.47, 0.29) end
		end
	end
	return row
end

-- The shape slides share: Global settings round a group (its stage, then its element) and bars beside
-- the group, each a titled box sized to its text. o: global, group, element and bars texts (global and
-- group may be nil), stageH, active (the subject: "global", "group", "element" or "bars"). Positions are
-- f's; s.height is the whole.
local BARS_W = 168
function GD.shape(f, o)
	local s = {}
	local w = BOARD_W - 2 * PAD - (o.bars and BARS_W + GAP or 0)
	s.global = GD.box(f, 0, 0, BOARD_W, 1, GD.GOLD, o.active == "global")
	GD.title(s.global, "Global settings", PAD, PAD, GD.GOLD)
	local y = PAD + 16 + UNDER
	if o.global then
		s.globalText = GD.text(s.global, o.global, PAD, y, BOARD_W - 2 * PAD)
		y = y + GD.height(s.globalText) + GAP
	else y = y + GAP - UNDER end
	local top = y
	s.group = GD.box(s.global, PAD, top, w, 1, GD.TEAL, o.active == "group")
	GD.title(s.group, "Group", PAD, PAD, GD.TEAL)
	local gy = PAD + 16 + UNDER
	if o.group then
		local t = GD.text(s.group, o.group, PAD, gy, w - 2 * PAD)
		gy = gy + GD.height(t) + GAP
	end
	s.stageY, s.stageW, s.stageH = gy, w - 2 * PAD, o.stageH
	s.stage = GD.stage(s.group, PAD, gy, s.stageW, o.stageH)
	gy = gy + o.stageH + GAP
	s.elementY = gy
	s.element = GD.box(s.group, PAD, gy, w - 2 * PAD, 1, GD.ORANGE, o.active == "element")
	GD.title(s.element, "Element", PAD, PAD, GD.ORANGE)
	s.elementText = GD.text(s.element, o.element, PAD, PAD + 16 + UNDER, w - 4 * PAD)
	local eh = PAD + 16 + UNDER + GD.height(s.elementText) + PAD
	s.element:SetHeight(eh)
	local gh = gy + eh + PAD
	s.group:SetHeight(gh)
	if o.bars then
		s.bars = GD.box(s.global, PAD + w + GAP, top, BARS_W, gh, GD.LAVENDER, o.active == "bars")
		GD.title(s.bars, "Bars", PAD, PAD, GD.LAVENDER)
		s.barsText = GD.text(s.bars, o.bars, PAD, PAD + 16 + UNDER, BARS_W - 2 * PAD)
	end
	s.height = top + gh + PAD
	s.global:SetHeight(s.height)
	return s
end

-- A line from x, y on the stage down to the Element box; f.from(y, x) starts it elsewhere
function GD.lead(s, x, y)
	local f = CreateFrame("Frame", nil, s.group)
	f:SetFrameLevel(s.stage:GetFrameLevel() + 5)
	f:SetWidth(2)
	function f.from(top, left)
		x = left or x
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", s.stage, "TOPLEFT", x - 1, -top)
		f:SetHeight(math.max(s.elementY - s.stageY - top, 1))
	end
	f.from(y)
	local t = f:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetColorTexture(GD.ORANGE[1], GD.ORANGE[2], GD.ORANGE[3], 0.9)
	return f
end

-- Example icons: the HUD's own icon, timers and parts on a sandbox owner, never the player's settings.
-- A style an example names replaces the player's Global one (or the element's shipped one, el).
local OWN_PARTS = { "border", "glow", "pop", "frame", "cooldown", "uptime" }

local function setOwn(owner, part, st)
	local spec = S.PARTS[part]
	local t = S.clean(st, spec.defaults, spec.ranges)
	t.follow = false
	local h, path = owner, spec.path
	for i = 1, #path - 1 do
		h[path[i]] = h[path[i]] or {}
		h = h[path[i]]
	end
	h[path[#path]] = t
end

local function baseOf(el, part)
	if el then return select(2, S.shipped(el, part)) end
	return S.get(nil, part)
end

local Ex = {}
Ex.__index = Ex

function GD.icon(parent, size)
	local owner = {}
	for _, part in ipairs(OWN_PARTS) do setOwn(owner, part) end
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(size, size)
	local ic = OA.makePreviewIcon(box, owner, { cooldown = true, uptime = true }, size)
	if ic.tex.SetSnapToPixelGrid then ic.tex:SetSnapToPixelGrid(true) end
	return setmetatable({ box = box, ic = ic, owner = owner, size = size }, Ex)
end

function Ex:point(...)
	self.box:ClearAllPoints()
	self.box:SetPoint(...)
	return self
end

-- Puts the box's centre at x, y from parent's top-left
function Ex:at(parent, x, y)
	return self:point("CENTER", parent, "TOPLEFT", x, -y)
end

-- Its size (box, border included); the next wear fits it
function Ex:resize(size)
	self.size = size
	self.box:SetSize(size, size)
	return self
end

-- spec: el (whose shipped styles it starts from), school, and per part (border, glow, pop, frame,
-- cooldown, uptime) the fields that replace the start's; no art frame unless spec.frame names one
function Ex:wear(spec)
	spec = spec or {}
	self.spec = spec
	for _, part in ipairs(OWN_PARTS) do
		local st = baseOf(spec.el, part)
		-- An art frame only where a slide names one: they're experimental, badged where shown
		if part == "frame" then st.look = "none" end
		for k, v in pairs(spec[part] or {}) do st[k] = type(v) == "table" and CopyTable(v) or v end
		setOwn(self.owner, part, st)
	end
	local ic = self.ic
	ic.school = spec.school
	for _, t in ipairs({ ic.cdT, ic.upT }) do t.school = spec.school end
	ic.glowF:restyle()
	ns.StyleArt.fit(ic, self.owner.border, self.size)
	ic:ClearAllPoints()
	ic:SetPoint("CENTER", self.box, "CENTER", 0, 0)
	FR.mount(ic, self.owner, self.size)
	return self
end

local function setFont(ex, font)
	local path = ns.Media.fontPath(font.name or "")
	local outline = font.outline or "OUTLINE"
	local ic = ex.ic
	local _, size = ic.count:GetFont()
	ic.count:SetFont(path, size or 14, outline)
	ic.count.placed = nil
	for _, t in ipairs({ ic.cdT, ic.upT }) do
		local _, ts = t.font:GetFont()
		t.font:SetFont(path, ts or 12, outline)
		t.cd:SetCountdownFont(t.fontName)
	end
end

-- A reagent count drawn by the reagent part on its shipped settings: n, and color in place of its own
local function reagentCount(ic, r)
	ns.Reagents.draw(ic, r.el, r.n, function(field) return E.default(r.el, "reagent", field) end)
	if r.color then ic.count:SetTextColor(r.color[1], r.color[2], r.color[3], 1) end
end

-- look: icon, cd and up ({ share gone, length }: frozen timers), cast ({ out, low }: out of range and
-- the cost unpaid, as the cast states draw them), warn ({ grey, tint, ring, fade, glow }), glow, alpha
-- (the icon's, as the preview kit's idle sets it), bar ({ n, filled, color, height }), count ({ text,
-- color, size, pos }), reagent ({ el, n, color }), font ({ name, outline })
local function draw(ex, look)
	local ic, kit = ex.ic, OA.kit
	kit.reset(ic, look.icon)
	if look.cd then kit.frozen(ic.cdT, look.cd[1], look.cd[2]) end
	if look.up then kit.frozen(ic.upT, look.up[1], look.up[2]) end
	local cast = look.cast
	if cast or ic.paintRing then ns.CastStates.paint(ic, ex.owner, cast and cast.out, cast and cast.low) end
	local wn = look.warn
	if wn then ic:SetWarnParts(wn.grey, wn.tint, wn.ring, wn.fade, wn.glow) end
	if look.glow then ic:SetGlowShown(true) end
	local b = look.bar
	if b then
		ic.bar:SetHeight(b.height or 6)
		local c = b.color
		kit.setBar(ic, b.n, b.filled, c[1], c[2], c[3], c[4])
	end
	local c = look.count
	if c then
		W.placeScaledText(ic.count, ic, c.size or 18, c.pos or "CENTER", 0, 0)
		ic.count:SetText(c.text)
		local col = c.color or { 1, 1, 1 }
		ic.count:SetTextColor(col[1], col[2], col[3], 1)
		ic.count:Show()
	end
	if look.reagent then reagentCount(ic, look.reagent) end
	if look.font then setFont(ex, look.font) end
	ic:SetAlpha(look.alpha or 1)
end

-- Draws look as in a row (or a column: self.column), whatever the player's own groups
function Ex:show(look)
	self.look = look
	self.ic.column = self.column or false
	ns.try("guide example", draw, self, look)
	return self
end

-- Draws an element's own preview state (its page's drawing) on this sandbox, as in a row or a column
function Ex:showAs(key, state)
	self.look = nil
	self.ic.column = self.column or false
	ns.try("guide example " .. key, OA.PREVIEW[key].render, self.ic, state, OA.kit)
	return self
end

function Ex:pop(kind) self.ic:Pop(kind or "ready") end

-- The page
local board, holder, page
local frames = {}
local cur, stepX, stepAt = 1, 0, 0
local title, blurb, prevB, nextB, dots

local function stepTo(x)
	stepX, stepAt = x, GetTime()
	local sp = slides[cur]
	if sp.step then ns.try("guide step", sp.step, frames[cur], x) end
end

-- No alpha animation on a slide: one on an ancestor of the examples overrides their own alpha (the
-- Idle example showed in full)
local function makeSlide(i)
	local f = CreateFrame("Frame", nil, board)
	f:SetSize(BOARD_W, 1)
	frames[i] = f
	ns.try("guide slide " .. slides[i].title, slides[i].build, f)
	f:SetHeight(f.height or 400)
	return f
end

-- Where the slide starts: the same room under every blurb; the board's height: the slide, then its dots
local function slideTop() return BLURB_Y + GD.height(blurb) + UNDER_BLURB end
local function boardHeight() return slideTop() + (frames[cur] and frames[cur].height or 400) + GAP + DOT end

local function show(n)
	n = (n - 1) % #slides + 1
	if frames[cur] and cur ~= n then frames[cur]:Hide() end
	cur = n
	local sp = slides[n]
	local f = frames[n] or makeSlide(n)
	title:SetText(sp.title)
	blurb:SetText(sp.blurb or "")
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", board, "TOPLEFT", 0, -slideTop())
	prevB:SetShown(n > 1)
	nextB:SetText(n == #slides and "Start over" or ("Next" .. GD.ON))
	dots.light(n)
	dots:ClearAllPoints()
	dots:SetPoint("TOP", f, "BOTTOM", 0, -GAP)
	board:SetHeight(boardHeight())
	f:Show()
	stepTo(0)
	if page then ns.Options.refresh() end
end
GD.show, GD.stepTo = show, stepTo
function GD.current() return cur, stepX end

-- Steps run only while the page shows
local ticker = ns.ticker(0.1, function()
	local sp, f = slides[cur], frames[cur]
	local now = GetTime()
	if sp.tick then ns.try("guide tick", sp.tick, f, now) end
	local steps = sp.steps
	if not steps or now - stepAt < steps[stepX + 1] then return end
	stepTo((stepX + 1) % #steps)
end)

local function build(p)
	holder = CreateFrame("Frame", nil, p.content)
	board = CreateFrame("Frame", nil, holder)
	board:SetWidth(BOARD_W)
	board:SetPoint("TOP", holder, "TOP", 0, 0)
	local word = GD.text(board, "Guide", 2, 2, nil, "GameFontNormalHuge")
	local sep = board:CreateTexture(nil, "ARTWORK")
	sep:SetColorTexture(0.54, 0.42, 0.23, 1)
	sep:SetSize(1, 20)
	sep:SetPoint("LEFT", word, "RIGHT", 9, -1)
	title = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("LEFT", sep, "RIGHT", 9, 1)
	blurb = GD.text(board, "", 2, BLURB_Y, BOARD_W - 4)
	nextB = GD.bigButton(board, "Next" .. GD.ON, 112, function() show(cur + 1) end)
	nextB:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, 0)
	prevB = GD.bigButton(board, GD.BACK .. "Previous", 128, function() show(cur - 1) end)
	prevB:SetPoint("RIGHT", nextB, "LEFT", -8, 0)
	dots = GD.dots(board, #slides, function(i) show(i) end)
	board:SetScript("OnShow", function()
		ticker:Show()
		stepAt = GetTime()
	end)
	board:SetScript("OnHide", function() ticker:Hide() end)
	show(cur)
	page = p
	p:add(holder, function()
		local h = boardHeight()
		holder:SetHeight(h)
		return h
	end, nil, function()
		local sp, f = slides[cur], frames[cur]
		if f and sp.refresh then ns.try("guide refresh", sp.refresh, f) end
	end)
end

-- The one-time highlight on the nav entry: the first time the window opens, until it closes
local function nav(b, current)
	local a = P.getAccount()
	if not a then return end
	if current then a.guideSeen = true end
	local on = not a.guideSeen
	if on and not b.guideGlow then
		local g = b:CreateTexture(nil, "BACKGROUND", nil, 1)
		g:SetPoint("TOPLEFT", -4, 2)
		g:SetPoint("BOTTOMRIGHT", 4, -2)
		g:SetColorTexture(1, 0.82, 0, 0.35)
		local pulse = g:CreateAnimationGroup()
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.25)
		fade:SetDuration(0.8)
		fade:SetSmoothing("IN_OUT")
		b.guideGlow, b.guidePulse = g, pulse
		b:GetParent():HookScript("OnHide", function() a.guideSeen = true end)
	end
	if not b.guideGlow then return end
	b.guideGlow:SetShown(on)
	if on then b.guidePulse:Play() else b.guidePulse:Stop() end
end

ns.Options.registerPage("guide", { title = "Guide", icon = "Interface\\Icons\\INV_Misc_Map_01", order = 75,
	bottom = 160, build = build, nav = nav })

MOD.register({ name = "guide",
	sanitize = function(_, acct) if type(acct.guideSeen) ~= "boolean" then acct.guideSeen = false end end })

-- Early days
local LINKS = { { "Discord", "discord" }, { "CurseForge", "curseforge", "/comments" } }

GD.add({ title = "Early days", order = 1000,
	blurb = ns.NAME .. " is brand new, made for WoW Forever, and it's still early days. Feedback is "
		.. GD.EMPH .. "very|r appreciated!",
	build = function(f)
		local card = GD.box(f, 0, 0, BOARD_W, 100, GD.GOLD, true)
		local logo = card:CreateTexture(nil, "ARTWORK")
		logo:SetSize(76, 76)
		logo:SetPoint("LEFT", PAD, 0)
		logo:SetTexture(ART .. "Logo-Icon")
		GD.text(card, ns.NAME, 76 + 2 * PAD, 26, nil, "GameFontNormalHuge")
		GD.text(card, ns.CLASS.blurb, 76 + 2 * PAD, 56)
		local y = 100 + 2 * GAP
		local ask = GD.text(f, "Ideas, requests or problems? Post in #feedback on Discord or comment on CurseForge.",
			0, y, BOARD_W)
		y = y + GD.height(ask) + 2 * GAP
		for _, l in ipairs(LINKS) do
			local t = f:CreateTexture(nil, "ARTWORK")
			t:SetSize(20, 20)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
			local art = ns.Options.LINKS[l[2]]
			t:SetTexture(art[1])
			t:SetVertexColor(art[2][1], art[2][2], art[2][3])
			GD.title(f, l[1], 30, y + 2)
			ns.Page.copyBox(f, ns.CLASS.links[l[2]] .. (l[3] or ""), 440):SetPoint("TOPLEFT", f, "TOPLEFT", 156, -y)
			y = y + 20 + 2 * GAP
		end
		f.height = y - GAP
	end })
