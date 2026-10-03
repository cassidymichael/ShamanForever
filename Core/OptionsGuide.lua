-- Guide page: slides on how the HUD fits together, stepped with Next and Previous
local ADDON, ns = ...
local W = ns.Widgets
local P, MOD = ns.Profiles, ns.Modules

local GD = {}
ns.Guide = GD

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
local BOARD_W, BOARD_H = 600, 650
local HOLD = 7      -- seconds a slide without steps holds while playing
local FADE = 0.35

-- Colours: Global, Group, Element, Bars
GD.GOLD = { 0.75, 0.54, 0.24 }
GD.TEAL = { 0.25, 0.69, 0.77 }
GD.ORANGE = { 0.89, 0.38, 0.18 }
GD.LAVENDER = { 0.73, 0.64, 0.90 }
GD.GREY = { 0.73, 0.69, 0.64 }

-- Slides
-- spec: title, blurb, order, build(f) (once, f the slide's frame, BOARD_W wide), steps ({ seconds, ... }:
-- each step's hold, looping), step(f, x), tick(f, now) (while it shows)
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
function GD.text(parent, font, str, x, y, width, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if width then fs:SetWidth(width) end
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	fs:SetText(str)
	return fs
end

-- A box with a one-pixel edge in color (a faint fill of it, or the panel's)
function GD.box(parent, x, y, w, h, color, fill)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	b:SetSize(w, h)
	b:SetBackdrop(W.BACKDROP)
	if fill then b:SetBackdropColor(color[1], color[2], color[3], fill)
	else b:SetBackdropColor(0.10, 0.08, 0.07, 1) end
	b:SetBackdropBorderColor(color[1], color[2], color[3], 0.75)
	return b
end

function GD.rect(parent, x, y, w, h, r, g, b, a)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	t:SetSize(w, h)
	t:SetColorTexture(r, g, b, a or 1)
	return t
end

-- The dark stage examples sit on
function GD.stage(parent, x, y, w, h)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	f:SetSize(w, h)
	f:SetBackdrop(W.BACKDROP)
	f:SetBackdropColor(0.05, 0.04, 0.035, 1)
	f:SetBackdropBorderColor(0.17, 0.13, 0.10, 1)
	return f
end

function GD.button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 24)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Texts over everything a slide draws
function GD.over(f)
	if not f.over then
		f.over = CreateFrame("Frame", nil, f)
		f.over:SetAllPoints()
		f.over:SetFrameLevel(f:GetFrameLevel() + 30)
	end
	return f.over
end

-- The shape slides share: Global settings round a group (its stage and its element) and bars beside
-- the group. o: global, group, element and bars texts (no bars: a wider group). Positions are f's.
function GD.shape(f, o)
	local s = {}
	local w = o.bars and 380 or 552
	s.global = GD.box(f, 0, 90, 600, 422, GD.GOLD)
	GD.text(s.global, "GameFontNormalLarge", "Global settings", 12, 7, nil, GD.GOLD)
	s.globalText = GD.text(s.global, "GameFontHighlight", o.global, 12, 28, 576)
	s.group = GD.box(s.global, 12, 70, w + 24, 340, GD.TEAL, 0.035)
	GD.text(s.group, "GameFontHighlightMedium", "Group", 12, 7, nil, GD.TEAL)
	s.groupText = GD.text(s.group, "GameFontHighlight", o.group, 12, 27, w)
	s.stage = GD.stage(s.group, 12, 66, w, 140)
	s.element = GD.box(s.group, 12, 220, w, 108, GD.ORANGE, 0.045)
	GD.text(s.element, "GameFontHighlightMedium", "Element", 12, 7, nil, GD.ORANGE)
	s.elementText = GD.text(s.element, "GameFontHighlight", o.element, 12, 27, w - 22)
	if o.bars then
		s.bars = GD.box(s.global, 428, 70, 160, 340, GD.LAVENDER, 0.035)
		GD.text(s.bars, "GameFontHighlightMedium", "Bars", 12, 7, nil, GD.LAVENDER)
		GD.text(s.bars, "GameFontHighlightSmall", o.bars, 12, 28, 140)
	end
	s.stageW = w
	return s
end

-- A line from x, y on the stage down to the Element box
function GD.lead(s, x, y)
	local f = CreateFrame("Frame", nil, s.group)
	f:SetFrameLevel(s.stage:GetFrameLevel() + 5)
	f:SetPoint("TOPLEFT", s.stage, "TOPLEFT", x - 1, -y)
	f:SetSize(2, 154 - y)
	local t = f:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetColorTexture(GD.ORANGE[1], GD.ORANGE[2], GD.ORANGE[3], 1)
	return f
end

-- The page
local board, holder
local frames, dots = {}, {}
local cur, stepX, stepAt, playing = 1, 0, 0, false
local title, blurb, prevB, nextB, playB

local function stepTo(x)
	stepX, stepAt = x, GetTime()
	local sp = slides[cur]
	if sp.step then ns.try("guide step", sp.step, frames[cur], x) end
end

local function makeSlide(i)
	local f = CreateFrame("Frame", nil, board)
	f:SetPoint("TOPLEFT")
	f:SetSize(BOARD_W, BOARD_H - 30)
	local fade = f:CreateAnimationGroup()
	local a = fade:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(FADE)
	f.fadeIn = fade
	frames[i] = f
	ns.try("guide slide " .. slides[i].title, slides[i].build, f)
	return f
end

local function paintPlay()
	playB.icon:SetTexture(playing and "Interface\\TimeManager\\PauseButton" or "Interface\\OptionsFrame\\VoiceChat-Play")
end

local function show(n)
	n = (n - 1) % #slides + 1
	if frames[cur] and cur ~= n then frames[cur]:Hide() end
	cur = n
	local sp = slides[n]
	local f = frames[n] or makeSlide(n)
	title:SetText(sp.title)
	blurb:SetText(sp.blurb or "")
	prevB:SetShown(n > 1)
	nextB:SetText(n == #slides and "Start over" or "Next")
	for i, d in ipairs(dots) do
		if i == n then d.tex:SetColorTexture(1, 0.82, 0) else d.tex:SetColorTexture(0.29, 0.23, 0.14) end
	end
	f:Show()
	f.fadeIn:Stop()
	f.fadeIn:Play()
	stepTo(0)
end
GD.show, GD.stepTo = show, stepTo
function GD.current() return cur, stepX end

-- Steps run only while the page shows
local ticker = ns.ticker(0.1, function()
	local sp, f = slides[cur], frames[cur]
	local now = GetTime()
	if sp.tick then ns.try("guide tick", sp.tick, f, now) end
	local steps = sp.steps
	local hold = steps and steps[stepX + 1] or HOLD
	if now - stepAt < hold then return end
	if steps and stepX + 1 < #steps then stepTo(stepX + 1)
	elseif playing and not board:IsMouseOver() then show(cur + 1)
	elseif steps and #steps > 1 then stepTo(0)
	else stepAt = now end
end)

-- Small square buttons under the slides
local function smallButton(parent, texture, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(18, 18)
	b:SetBackdrop(W.BACKDROP)
	b:SetBackdropColor(0.10, 0.08, 0.07, 1)
	b:SetBackdropBorderColor(0.35, 0.27, 0.19, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexture(texture)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.1)
	b:SetScript("OnClick", onClick)
	return b
end

local function build(p)
	holder = CreateFrame("Frame", nil, p.content)
	board = CreateFrame("Frame", nil, holder)
	board:SetSize(BOARD_W, BOARD_H)
	board:SetPoint("TOP", holder, "TOP", 0, 0)
	local word = GD.text(board, "GameFontNormalHuge", "Guide", 2, 2)
	local sep = board:CreateTexture(nil, "ARTWORK")
	sep:SetColorTexture(0.54, 0.42, 0.23, 1)
	sep:SetSize(1, 20)
	sep:SetPoint("LEFT", word, "RIGHT", 9, -1)
	title = board:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("LEFT", sep, "RIGHT", 9, 1)
	blurb = GD.text(board, "GameFontHighlight", "", 2, 36, 596)
	blurb:SetSpacing(2)
	nextB = GD.button(board, "Next", 112, function() show(cur + 1) end)
	nextB:SetPoint("TOPRIGHT", board, "TOPRIGHT", 0, 0)
	prevB = GD.button(board, "Previous", 108, function() show(cur - 1) end)
	prevB:SetPoint("RIGHT", nextB, "LEFT", -8, 0)
	local ctl = CreateFrame("Frame", nil, board)
	ctl:SetSize(BOARD_W, 18)
	ctl:SetPoint("BOTTOM", board, "BOTTOM", 0, 6)
	local n = #slides
	local span = 18 * 3 + n * 13 + 30
	local x = (BOARD_W - span) / 2
	smallButton(ctl, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", function() show(cur - 1) end)
		:SetPoint("LEFT", ctl, "LEFT", x, 0)
	x = x + 28
	for i = 1, n do
		local d = CreateFrame("Button", nil, ctl)
		d:SetSize(13, 13)
		d:SetPoint("LEFT", ctl, "LEFT", x + (i - 1) * 13, 0)
		d.tex = d:CreateTexture(nil, "ARTWORK")
		d.tex:SetSize(6, 6)
		d.tex:SetPoint("CENTER")
		d:SetScript("OnClick", function() show(i) end)
		W.setTip(d, slides[i].title)
		dots[i] = d
	end
	x = x + n * 13 + 2
	playB = smallButton(ctl, nil, function()
		playing = not playing
		stepAt = GetTime()
		paintPlay()
	end)
	playB:SetPoint("LEFT", ctl, "LEFT", x, 0)
	W.setTip(playB, "Play", "Steps through the slides on its own.")
	paintPlay()
	smallButton(ctl, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", function() show(cur + 1) end)
		:SetPoint("LEFT", playB, "RIGHT", 10, 0)
	board:SetScript("OnShow", function()
		ticker:Show()
		stepAt = GetTime()
	end)
	board:SetScript("OnHide", function() ticker:Hide() end)
	show(cur)
	p:add(holder, BOARD_H)
end

-- Redrawn after a layout or a restyle: a time bar out of an icon goes back in after either
local function redraw()
	if not (board and board:IsVisible()) then return end
	C_Timer.After(0, function() if board:IsVisible() then stepTo(stepX) end end)
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
	bottom = 130, build = build, nav = nav })

MOD.register({ name = "guide",
	sanitize = function(_, acct) if type(acct.guideSeen) ~= "boolean" then acct.guideSeen = false end end,
	afterGroups = redraw, applyTimers = redraw })

-- Early days
local LINKS = {
	{ "Discord", "discord", "Link-Discord.png", { 0.35, 0.40, 0.95 } },
	{ "CurseForge", "curseforge", "Link-CurseForge.png", { 0.95, 0.39, 0.21 }, "/comments" },
}

local function copyField(parent, value, x, y, w)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(w, 20)
	e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	e:SetAutoFocus(false)
	e:SetText(value)
	e:SetCursorPosition(0)
	e:SetScript("OnTextChanged", function(box, user) if user then box:SetText(value); box:HighlightText() end end)
	e:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

GD.add({ title = "Early days", order = 1000,
	blurb = ns.NAME .. " is brand new, made for WoW Forever, and it's still early days. Feedback is very appreciated!",
	build = function(f)
		local card = GD.box(f, 0, 96, 600, 96, { 0.56, 0.43, 0.22 })
		local logo = card:CreateTexture(nil, "ARTWORK")
		logo:SetSize(76, 76)
		logo:SetPoint("LEFT", 14, 0)
		logo:SetTexture(ART .. "Logo-Icon")
		GD.text(card, "GameFontNormalHuge", ns.NAME, 104, 20)
		GD.text(card, "GameFontHighlight", ns.CLASS.blurb, 104, 50, nil, GD.GREY)
		GD.text(f, "GameFontHighlight", "Ideas, requests or problems? Post in #feedback on Discord or comment on "
			.. "CurseForge. Click a link, then Ctrl+C to copy.", 2, 214, 596)
		for i, l in ipairs(LINKS) do
			local y = 262 + (i - 1) * 38
			local t = f:CreateTexture(nil, "ARTWORK")
			t:SetSize(20, 20)
			t:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -y)
			t:SetTexture(ART .. l[3])
			t:SetVertexColor(l[4][1], l[4][2], l[4][3])
			GD.text(f, "GameFontHighlightMedium", l[1], 34, y + 2)
			copyField(f, ns.CLASS.links[l[2]] .. (l[5] or ""), 156, y, 434)
		end
	end })
