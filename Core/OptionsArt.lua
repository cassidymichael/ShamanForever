-- Options art: school art, element headers with live previews, the experimental badge
local ADDON, ns = ...
local W = ns.Widgets
local E, G, Bars = ns.Elements, ns.Groups, ns.Bars
local OA = {}
ns.OptionsArt = OA

local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
OA.GOLD = { 0.85, 0.71, 0.42 }

-- The schools, from the class theme: in order (OA.SCHOOLS) and by key (OA.SCHOOL), one entry each; an
-- entry's [1] to [3] are its colour
OA.SCHOOLS, OA.SCHOOL = {}, {}
for i, key in ipairs(ns.THEME.order) do
	local c = ns.THEME.color[key]
	local sc = { c[1], c[2], c[3], key = key, name = ns.THEME.name[key], icon = ns.THEME.icon[key],
		color = c, banner = ns.THEME.banner[key] }
	OA.SCHOOLS[i], OA.SCHOOL[key] = sc, sc
end
-- Banners are 1400x260 art in the top-left of a 2048x512 file: cropped to the header, never stretched.
local ART_W, ART_H, FILE_W, FILE_H = 1400, 260, 2048, 512
local function coverCoords(w, h)
	if w <= 0 or h <= 0 then return 0, ART_W / FILE_W, 0, ART_H / FILE_H end
	local aspect = w / h
	if aspect < ART_W / ART_H then
		local sw = ART_H * aspect
		return (ART_W - sw) / FILE_W, ART_W / FILE_W, 0, ART_H / FILE_H
	end
	local sh = ART_W / aspect
	local top = (ART_H - sh) / 2
	return 0, ART_W / FILE_W, top / FILE_H, (top + sh) / FILE_H
end
OA.PANEL = { 29 / 255, 24 / 255, 19 / 255 }

-- An element's, or a bar's (Bars.register)
local function identity(key) return E.ALL[key] or Bars.get(key) end

function OA.elementName(key)
	local e = identity(key)
	if not e then return key end
	return e.spell and ns.Spells.name(e.spell) or e.label or key
end

-- Words in a sentence: "a", "a and b", "a, b and c" (or another last joining word)
function OA.wordList(words, last)
	if #words <= 1 then return words[1] or "" end
	return table.concat(words, ", ", 1, #words - 1) .. " " .. (last or "and") .. " " .. words[#words]
end
-- What positioning moves: lead ("groups"), then the bars that move
function OA.movingWords(lead, last)
	return OA.wordList(Bars.nouns(function(bar) return bar.movable ~= nil end, lead), last)
end

-- Ornaments
function OA.addCorners(frame, size, inset)
	size, inset = size or 26, inset or 4
	local list = {}
	for _, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 },
		{ "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetTexture(ART .. "Corner.tga")
		t:SetSize(size, size)
		t:SetPoint(c[1], (c[1]:find("LEFT") and 1 or -1) * inset, (c[1]:find("TOP") and -1 or 1) * inset)
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		t:SetVertexColor(OA.GOLD[1], OA.GOLD[2], OA.GOLD[3], 0.55)
		table.insert(list, t)
	end
	return list
end

function OA.divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t.refresh = function()
		t:SetTexture(ART .. "Divider.tga")
		t:SetVertexColor(OA.GOLD[1], OA.GOLD[2], OA.GOLD[3], 0.45)
		t:SetHeight(10)
	end
	t.refresh()
	return t
end

-- Badges: a word in a faintly filled frame of its colour
local TAG, TAG_TEXT, EXP = { 0.55, 0.82, 0.5 }, { 0.62, 0.86, 0.56 }, { 0.95, 0.77, 0.42 }
local function makeBadge(frameType, parent, text, edge, color)
	local b = CreateFrame(frameType, nil, parent, "BackdropTemplate")
	b:SetBackdrop(W.BACKDROP)
	b:SetBackdropColor(edge[1], edge[2], edge[3], 0.08)
	b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 0.5)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(text)
	b.text:SetTextColor(color[1], color[2], color[3])
	b:SetSize(b.text:GetStringWidth() + 12, 16)
	return b
end
function OA.tagBadge(parent, text) return makeBadge("Frame", parent, text, TAG, TAG_TEXT) end

-- Experimental badge
function OA.expBadge(parent, feature)
	local b = makeBadge("Button", parent, "EXPERIMENTAL", EXP, EXP)
	b:SetScript("OnClick", function() ns.Options.showExperimental() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Not fully tested yet")
		GameTooltip:AddLine("Click to see all experimental features.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Preview icons
local PREVIEW_SIZE = 56
-- box: the icon's own size, border included (else it stands in for the element at its size); key
-- may be a sandbox owner (a table); ic.column, when set, lays it out as in a column (true) or a row
local function makePreviewIcon(parent, key, preview, box)
	local ic = W.makeIcon(parent, PREVIEW_SIZE, key)
	local e = identity(key)
	local school = e and e.school
	local function column() return ic.column end
	local out = type(key) == "table" or nil
	if preview.cooldown then
		ic.cdT = ns.Timer.new(ic, key, "cooldown", { cd = ic.cd, school = school, box = box, column = column,
			placeOut = out })
	end
	-- Pops play in full over a resting icon, as on the HUD
	local hud = type(key) == "string" and E.ALL[key] and E.ALL[key].frame
	if hud and hud.popLayer then
		local layer = W.popLayer(ic, ic, function() return parent:GetAlpha() end,
			function() return W.fadeTarget(ic) * parent:GetAlpha() end)
		ns.ignoreParentAlpha(layer, true)
	end
	-- What the player may keep in full over an idle icon is drawn on a frame over it (the HUD's keep holders)
	if preview.keeps then
		ic.keepOver = CreateFrame("Frame", nil, parent)
		ic.keepOver:SetAllPoints(ic)
		ic.glowF:SetParent(ic.keepOver)
	end
	if preview.uptime then
		local holder = ic.keepOver or ic.textFrame
		ic.upT = ns.Timer.new(holder, key, "uptime", { anchor = ic, dual = preview.cooldown,
			cd = not preview.cooldown and ic.cd or nil, school = school, barInset = preview.barInset, box = box,
			column = column, placeOut = out })
	end
	ic.bar = CreateFrame("Frame", nil, ic.textFrame)
	ic.bar:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 0, 0)
	ic.bar:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 0, 0)
	ic.bar:SetHeight(7)
	ic.bar.bg = ic.bar:CreateTexture(nil, "BACKGROUND")
	ic.bar.bg:SetAllPoints()
	ic.bar.bg:SetColorTexture(0, 0, 0, 0.6)
	ic.bar.segs = {}
	for i = 1, 3 do
		local t = ic.bar:CreateTexture(nil, "ARTWORK")
		t:SetPoint("TOP")
		t:SetPoint("BOTTOM")
		ic.bar.segs[i] = t
	end
	W.stackIcon(ic)
	return ic
end
OA.makePreviewIcon = makePreviewIcon

local function setBar(ic, n, filled, r, g, b, a)
	local d = ns.StyleArt.pictureInset(ic)
	ic.bar:ClearAllPoints()
	ic.bar:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", d, d)
	ic.bar:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", d > 0 and -d or 0, d)
	local w = ic:GetWidth() - 2 * d
	local path, atlas = ns.Media.barOf(ns.Style.value(nil, "bar", "texture"))
	for i = #ic.bar.segs + 1, n do ic.bar.segs[i] = ic.bar:CreateTexture(nil, "ARTWORK") end
	for i, t in ipairs(ic.bar.segs) do
		if i > n then t:Hide() else
			local segW = (n == 1) and w * filled or (w - (n - 1)) / n
			t:ClearAllPoints()
			t:SetPoint("TOP")
			t:SetPoint("BOTTOM")
			t:SetPoint("LEFT", ic.bar, "LEFT", (i - 1) * ((w - (n - 1)) / n + 1), 0)
			t:SetWidth(math.max(segW, 0.01))
			if atlas then t:SetAtlas(path) else t:SetTexture(path) end
			t:SetVertexColor(r, g, b, a or 1)
			t:SetShown(n == 1 or i <= filled)
		end
	end
	ic.bar:Show()
end

local function reset(ic, icon)
	ic.tex:SetTexture(icon)
	ic.tex:SetDesaturated(false)
	ic.tex:SetVertexColor(1, 1, 1)
	ic.warnTint = nil
	ic.tex:SetAlpha(1)
	W.fadeTo(ic, 1)
	OA.holdersAlpha(ic, 1)
	ic.bodyOverlay:Hide()
	if ic.paintRing then ic.paintRing:show(false) end
	ic:SetRingShown(false)
	ic:SetPulsing(false)
	ic:SetGlowShown(false)
	pcall(ic.cd.Clear, ic.cd)
	if ic.cdT then ic.cdT:clear() end
	if ic.upT then ic.upT:clear() end
	ic.count:Hide()
	ic.bar:Hide()
end

-- A frozen timer; under OA.paint it runs from the state's moment.
local stage
local function frozen(t, frac, length)
	if not t then return end
	t:apply()
	if not stage then t:static(frac, length) return end
	length = length or 30
	stage.ends = math.max(stage.ends or 0, stage.start + (1 - frac) * length)
	pcall(t.cd.Resume, t.cd)
	t:setTime(stage.start - frac * length, length)
end

local function opt(key, name, field) return E.setting(key, name, field) end
local function expiringLook(ic, key, length)
	local secs = opt(key, "expire", "secs") or 0
	frozen(ic.upT, 1 - math.min(secs > 0 and secs or 5, length) / length, length)
	if secs <= 0 then return end
	ic:SetWarnParts(W.warnParts(key, "expire"))
end

local function engineExpireLook(ic, key, length)
	length = length or 12
	local secs = opt(key, "expire", "secs") or 0
	local left = secs > 0 and math.min(2, secs) or 2
	frozen(ic.upT, 1 - left / length, length)
	if secs <= 0 or not ic.upT then return end
	if opt(key, "expire", "bar") and ic.upT.bar then
		local c = opt(key, "expire", "barColor")
		ic.upT.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	end
	if opt(key, "expire", "text") then ic.upT.font:SetTextColor(1, 0.2, 0.2, 1) end
end

local previewState = {}

local FAINT = 0.12
function OA.idleAlpha(key) return math.max(E.idleAlpha(key), FAINT) end
-- The frames over a preview icon (ic.keepOver, ic.keepFrames[field]) at a, each as the HUD's holder is;
-- ease: over the Idle fade
function OA.holdersAlpha(ic, a, key, st, ease)
	local secs = ease and E.idleFade() or nil
	local function put(f, v) W.fadeTo(f, v, secs) end
	local pv = a < 1 and OA.PREVIEW[key]
	local function kept(field)
		return a < 1 and field ~= nil and E.setting(key, "idleKeep", field) == true
	end
	if ic.keepOver then put(ic.keepOver, kept(pv and pv.keeps and pv.keeps[st]) and 1 or a) end
	if ic.popLayer and not ic.awakeUntil then put(ic.popLayer, a * ic:GetParent():GetAlpha()) end
	for field, frames in pairs(ic.keepFrames or {}) do
		for _, f in ipairs(frames) do put(f, kept(field) and 1 or a) end
	end
end
-- A preview icon at alpha a in state st: the icon, and what the player keeps in full over it
function OA.fadeIcon(ic, key, st, a, ease)
	W.fadeTo(ic, a, ease and E.idleFade() or nil)
	OA.holdersAlpha(ic, a, key, st, ease)
end
local function idleLook(ic, key, st) OA.fadeIcon(ic, key, st, OA.idleAlpha(key)) end
-- Whether a state goes idle once its moment has played (the preview's own rule)
function OA.idles(key, st)
	local when = E.ALL[key] and E.setting(key, "idleWhen")
	if not when or when == "never" then return false end
	local pv = OA.PREVIEW[key]
	return pv and pv.idles and pv.idles(st, when) and true or false
end

-- The preview icon rests at once; its pop plays on over it
local function idleSoon(ic, key, st)
	OA.fadeIcon(ic, key, st, OA.idleAlpha(key), true)
end

OA.PREVIEW = {}

-- An element's preview, from its kind, made when first asked for; or a bar's (Bars.register)
setmetatable(OA.PREVIEW, { __index = function(t, key)
	local bar = Bars.get(key)
	local pv = bar and bar.preview or ns.Kinds.previewOf(key)
	if pv then rawset(t, key, pv) end
	return pv
end })

-- What a preview draws with: render(ic, st, kit), pop(ic, st, kit)
OA.kit = { reset = reset, frozen = frozen, expiring = expiringLook, engineExpire = engineExpireLook,
	idle = idleLook, setBar = setBar, current = function(key) return previewState[key] end }

function OA.paint(ic, key, st, at)
	stage = { start = at }
	local ok, err = pcall(OA.PREVIEW[key].render, ic, st, OA.kit)
	local ends = stage.ends
	stage = nil
	if not ok then ns.noteError("preview " .. key, err) end
	return ends
end

-- Element page header
OA.HERO_H = 160
local WING_MAX = 48
local heroes = {}

function OA.paintChoice(b, chosen)
	b:SetBackdropColor(chosen and 0.88 or 0.09, chosen and 0.66 or 0.075, chosen and 0.29 or 0.06, chosen and 0.16 or 1)
	b:SetBackdropBorderColor(chosen and 0.88 or 0.23, chosen and 0.66 or 0.17, chosen and 0.29 or 0.10, 1)
	b.text:SetTextColor(chosen and 1 or 0.78, chosen and 0.84 or 0.74, chosen and 0.5 or 0.68)
end

-- A row of chips, items { value, label, tip }: set(value) when another is clicked; row.refresh paints get()'s
function OA.choiceRow(parent, items, get, set, tipAnchor)
	local row = CreateFrame("Frame", nil, parent)
	row.buttons = {}
	local x = 0
	for _, it in ipairs(items) do
		local b = CreateFrame("Button", nil, row, "BackdropTemplate")
		b:SetBackdrop(W.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(it[2])
		local w = math.ceil(b.text:GetStringWidth()) + 20
		b:SetSize(w, 20)
		b:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + w + 2
		b.value = it[1]
		b:SetScript("OnClick", function(self)
			if get() ~= self.value then set(self.value) end
		end)
		W.setTip(b, it[2], it[3], tipAnchor)
		table.insert(row.buttons, b)
	end
	row:SetSize(x - 2, 20)
	function row.refresh()
		for _, b in ipairs(row.buttons) do OA.paintChoice(b, get() == b.value) end
	end
	return row
end

-- How far a time bar out of the icon reaches out on its left, right, top and bottom
local REACH_AT = { left = 1, right = 2, above = 3, below = 4 }
local function barReach(ic)
	local out = { 0, 0, 0, 0 }
	for _, t in ipairs({ ic.cdT or false, ic.upT or false }) do
		local s = t and ns.Style.get(t.key, t.part)
		local at = s and s.bar and not ns.Timer.cant(t.key, t.part).bar and REACH_AT[t:barSide(s)]
		if at then out[at] = math.max(out[at], math.ceil(t:reach())) end
	end
	return out
end
-- The preview panel's height for what sits above and below its icon: the icon stays where it is on
-- every page (centred, 6 down), clear of the caption (CAP_ROOM) and the panel's foot (FOOT_ROOM)
local CAP_ROOM, FOOT_ROOM = 22, 6
local function panelFor(base, top, bottom)
	local half = PREVIEW_SIZE / 2
	return math.max(base, 2 * (top + half - 6 + CAP_ROOM), 2 * (bottom + half + 6 + FOOT_ROOM))
end

-- h.afterRefresh(), when set, runs after each of its refreshes
function OA.buildHero(parent, key)
	local e = identity(key)
	local school = OA.SCHOOL[e.school]
	local def = OA.PREVIEW[key]
	local BTN_H, BTN_W = 17, 108
	do
		local probe = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		for _, st in ipairs(def.states) do
			probe:SetText(st[2])
			BTN_W = math.max(BTN_W, math.ceil(probe:GetStringWidth()) + 16)
		end
		probe:Hide()
	end
	local listH = #def.states * (BTN_H + 3) - 3
	local baseH = def.heroH or math.max(OA.HERO_H, listH + 14 + 24 + 4)
	local heroH = baseH
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(heroH - 14)
	h.heroH = heroH
	h:SetBackdrop(W.BACKDROP)
	h:SetBackdropColor(OA.PANEL[1], OA.PANEL[2], OA.PANEL[3], 1)
	h:SetBackdropBorderColor(0.36, 0.28, 0.17, 1)

	h.banner = h:CreateTexture(nil, "BACKGROUND", nil, 1)
	h.banner:SetTexture(ART .. school.banner)
	h.banner:SetPoint("TOPLEFT", 1, -1)
	h.banner:SetPoint("BOTTOMRIGHT", -1, 1)
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	OA.addCorners(h)

	h.icon = h:CreateTexture(nil, "ARTWORK")
	h.icon:SetSize(60, 60)
	if def.stage then h.icon:SetPoint("TOPLEFT", 40, -24) else h.icon:SetPoint("LEFT", 40, 0) end
	h.icon:SetTexture(e.icon)
	W.cropIcon(h.icon)
	h.iconEdge = h:CreateTexture(nil, "BORDER")
	h.iconEdge:SetPoint("TOPLEFT", h.icon, -2, 2)
	h.iconEdge:SetPoint("BOTTOMRIGHT", h.icon, 2, -2)
	h.iconEdge:SetColorTexture(school[1] * 0.7, school[2] * 0.7, school[3] * 0.7, 1)

	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("TOPLEFT", h.icon, "TOPRIGHT", 14, -4)
	h.title:SetText(OA.elementName(key))
	h.title:SetShadowOffset(1, -1)
	h.blurb = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.blurb:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -5)
	h.blurb:SetTextColor(0.80, 0.74, 0.66)
	h.blurb:SetShadowOffset(1, -1)
	h.blurb:SetJustifyH("LEFT")
	h.blurb:Hide()
	h.tags = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	h.tags:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -7)
	if def.stage then
		h.icon:Hide(); h.iconEdge:Hide(); h.blurb:Hide()
		h.title:ClearAllPoints()
		h.title:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -18)
		h.tags:ClearAllPoints()
		h.tags:SetPoint("BOTTOMLEFT", h.title, "BOTTOMRIGHT", 16, 2)
		h.rule = h:CreateTexture(nil, "ARTWORK")
		h.rule:SetColorTexture(1, 1, 1, 1)
		h.rule:SetHeight(1)
		h.rule:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -50)
		h.rule:SetPoint("TOPRIGHT", h, "TOPRIGHT", -40, -50)
		pcall(h.rule.SetGradient, h.rule, "HORIZONTAL", CreateColor(0.85, 0.71, 0.42, 0.45), CreateColor(0.85, 0.71, 0.42, 0))
	end
	if e.experimental then
		h.exp = OA.expBadge(h, e.experimental)
		if def.stage then h.exp:SetPoint("LEFT", h.tags, "RIGHT", 12, 0)
		else h.exp:SetPoint("BOTTOMLEFT", h.icon, "TOPLEFT", -2, 6) end
		h.exp:SetFrameLevel(h:GetFrameLevel() + 6)
	end

	local PANEL_W, PANEL_H = def.stage and 0 or 88 + BTN_W, heroH - 14 - 24
	local p = CreateFrame("Frame", nil, h, "BackdropTemplate")
	p:SetSize(PANEL_W, PANEL_H)
	p:SetPoint("RIGHT", -40, 0)
	p:SetBackdrop(W.BACKDROP)
	p:SetBackdropColor(0, 0, 0, 0.5)
	p:SetBackdropBorderColor(0.23, 0.17, 0.10, 1)
	local cap = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	cap:SetPoint("TOPLEFT", 10, -8)
	cap:SetText("PREVIEW")
	if def.stage then
		p:Hide()
		def.build(h)
	else
		h.previewIcon = makePreviewIcon(p, key, def, PREVIEW_SIZE)
		h.previewIcon:SetPoint("LEFT", 16, -6)
		-- The element's frame, clipped to the panel left of the state buttons; it fades with the icon
		local clip = CreateFrame("Frame", nil, p)
		clip:SetPoint("TOPLEFT", 1, -1)
		clip:SetPoint("BOTTOMRIGHT", -(BTN_W + 10), 1)
		clip:SetClipsChildren(true)
		h.frameHost = CreateFrame("Frame", nil, clip)
		h.frameHost:SetAllPoints(h.previewIcon)
		hooksecurefunc(h.previewIcon, "SetAlpha", function(_, a) h.frameHost:SetAlpha(a) end)
	end
	h.stateButtons = {}
	previewState[key] = previewState[key] or def.states[1][1]
	local firstShown, revealed = 1, nil
	for _, st in ipairs(def.states) do
		local b = CreateFrame("Button", nil, def.stage and h or p, "BackdropTemplate")
		if def.stage then
			b:SetSize(BTN_W, BTN_H)
			b:SetFrameLevel(h:GetFrameLevel() + 6)
		else
			b:SetSize(BTN_W, BTN_H)
		end
		b:SetBackdrop(W.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("LEFT", 7, 0)
		b.text:SetText(st[2])
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		b.state = st[1]
		b:SetScript("OnClick", function(self)
			previewState[key] = self.state
			revealed = nil
			h:refresh()
			if def.pop then def.pop(def.stage and h or h.previewIcon, self.state, OA.kit) end
			if not def.stage and OA.idles(key, self.state) then idleSoon(h.previewIcon, key, self.state) end
		end)
		table.insert(h.stateButtons, b)
	end
	h.preview = p
	heroes[key] = h

	-- State buttons
	local STEP, SHADE_H = BTN_H + 3, 12
	local function listed(st) return not def.stateShown or def.stateShown(st) end
	local placeStates
	local function onWheel(_, delta)
		firstShown = firstShown - delta
		placeStates(h)
	end
	function placeStates(self)
		-- Centred in its room; one that scrolls keeps clear of the banner's foot (an element page's panel edges)
		local host, right, y0, room, inner = p, -8, 0, PANEL_H, PANEL_H - 4
		if def.stage then
			host, right, y0, room = self, -40, 58, heroH - 14 - 58 - 12
			inner = room
		end
		local sel = previewState[key]
		local list, now = {}, tostring(sel)
		for _, b in ipairs(self.stateButtons) do
			if listed(b.state) then
				table.insert(list, b)
				now = now .. "/" .. b.state
			else
				b:Hide()
			end
		end
		local n = #list
		local fits = n * STEP - 3 <= inner
		local vis = fits and n or math.max(math.floor((inner + 3) / STEP), 1)
		firstShown = fits and 1 or math.min(math.max(firstShown, 1), n - vis + 1)
		-- A state picked, or a new set of them, brings the chosen one into view; the wheel's place holds
		if now ~= revealed then
			revealed = now
			for i, b in ipairs(list) do
				if b.state == sel then firstShown = math.max(math.min(firstShown, i), i - vis + 1) end
			end
		end
		local top = y0 + math.max((room - (vis * STEP - 3)) / 2, 0)
		for i, b in ipairs(list) do
			local slot = i - firstShown
			if slot >= 0 and slot < vis then
				b:ClearAllPoints()
				b:SetPoint("TOPRIGHT", host, "TOPRIGHT", right, -(top + slot * STEP))
				b:Show()
			else
				b:Hide()
			end
		end
		local line = self.stateLine
		if fits then
			if line then line:Hide(); line.wheel:Hide(); line.shades:Hide() end
			return
		end
		if not line then
			line = W.scrollLine(host)
			line:SetFrameLevel(list[1]:GetFrameLevel())
			line.wheel = CreateFrame("Frame", nil, host)
			line.wheel:SetFrameLevel(math.max(list[1]:GetFrameLevel() - 1, host:GetFrameLevel()))
			line.wheel:EnableMouseWheel(true)
			line.wheel:SetScript("OnMouseWheel", onWheel)
			for _, b in ipairs(self.stateButtons) do
				b:EnableMouseWheel(true)
				b:SetScript("OnMouseWheel", onWheel)
			end
			line.shades = CreateFrame("Frame", nil, host)
			line.shades:SetFrameLevel(list[1]:GetFrameLevel() + 2)
			line.above, line.below = W.moreShades(line.shades, SHADE_H, 0)
			self.stateLine = line
		end
		local colH = vis * STEP - 3
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", host, "TOPRIGHT", right + 3, -top)
		line:update(colH, (firstShown - 1) / n, vis / n)
		line:Show()
		line.wheel:ClearAllPoints()
		line.wheel:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top)
		line.wheel:SetSize(BTN_W - right, colH)
		line.wheel:Show()
		line.shades:ClearAllPoints()
		line.shades:SetPoint("TOPRIGHT", host, "TOPRIGHT", right, -top)
		line.shades:SetSize(BTN_W, colH)
		line.above:SetShown(firstShown > 1)
		line.below:SetShown(firstShown + vis - 1 < n)
		line.shades:Show()
	end

	-- Taller for what sits above or below the preview's icon; the page moves its content with it
	local function setHeight(self, want)
		if def.stage or want == self.heroH then return end
		-- Not while a slider is dragged: the header settles once the button is let go
		if self.heroH and IsMouseButtonDown("LeftButton") then
			self.settle = self.settle or ns.ticker(0.1, function(t)
				if IsMouseButtonDown("LeftButton") then return end
				t:Hide()
				self:refresh()
			end)
			self.settle:Show()
			return
		end
		heroH, PANEL_H = want, want - 14 - 24
		self.heroH = want
		self:SetHeight(want - 14)
		p:SetHeight(PANEL_H)
		placeStates(self)
		if self.onHeight then self.onHeight() end
	end
	if not def.stage then
		h.heroH = nil
		setHeight(h, heroH)
	end

	function h:refresh()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, heroH - 16))
		local el = E.ALL[key]
		-- The panel widens for a frame's wings, up to a point
		local padL, padR = 0, 0
		local framed = not def.stage and el
		if framed then
			local r = ns.Frames.reach(key)
			local out = barReach(self.previewIcon)
			if def.reach then
				local more = { def.reach(self.previewIcon) }
				for i = 1, 4 do out[i] = math.max(out[i], more[i] or 0) end
			end
			padL = math.max(math.min(math.ceil(r.left * PREVIEW_SIZE), WING_MAX), out[1])
			padR = math.max(math.min(math.ceil(r.right * PREVIEW_SIZE), WING_MAX), out[2])
			p:SetWidth(PANEL_W + padL + padR)
			setHeight(self, panelFor(baseH - 14 - 24, out[3], out[4]) + 14 + 24)
		end
		self.blurb:SetWidth(def.stage and 300 or math.max(w - 40 - 60 - 14 - 40 - PANEL_W - padL - padR - 12, 120))
		if e.tags then self.tags:SetText(e.tags()) else
			local g = G.of(key)
			local shows = { always = "Always", combat = "In combat" }
			self.tags:SetText(string.format("%s  ·  %s%s", g and g.name or "Ungrouped",
				E.isOn(key) and shows[E.showMode(key)] or "Off",
				E.isLearned(key) and "" or "  ·  " .. E.notLearnedText(key)))
		end
		if def.stage then
			self.stateW = BTN_W + 16
			if self.area then self.area:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -40 - self.stateW, 12) end
		end
		local first, cur = nil, false
		for _, b in ipairs(self.stateButtons) do
			if listed(b.state) then
				first = first or b.state
				if b.state == previewState[key] then cur = true end
			end
		end
		if not cur and first then
			previewState[key] = (def.fallback and listed(def.fallback)) and def.fallback or first
		end
		placeStates(self)
		for _, b in ipairs(self.stateButtons) do OA.paintChoice(b, b.state == previewState[key]) end
		if not def.stage then
			local ic = self.previewIcon
			local x = 16 + padL
				+ ns.StyleArt.fit(ic, E.borderFor(key), PREVIEW_SIZE, PREVIEW_SIZE, { shape = el and el.shape })
			ic:ClearAllPoints()
			ic:SetPoint("LEFT", p, "LEFT", x, -6)
			local l, t = ic:GetLeft(), ic:GetTop()
			if l and t then
				local px = W.pixel(ic)
				ic:SetPoint("LEFT", p, "LEFT", x + W.roundPx(l, px) - l, -6 + W.roundPx(t, px) - t)
			end
			self.frameHost:SetFrameLevel(ic:GetFrameLevel())
			if framed then ns.Frames.mount(self.frameHost, key, PREVIEW_SIZE)
			else ns.Frames.draw(self.frameHost) end
		end
		local st = previewState[key]
		if def.stage then def.render(self, st, OA.kit) else
			def.render(self.previewIcon, st, OA.kit)
			if self.shownState == nil or self.shownState == st then
				if OA.idles(key, st) then idleLook(self.previewIcon, key, st) end
			end
			self.shownState = st
		end
		if self.afterRefresh then self.afterRefresh() end
	end
	return h
end

function OA.setPreview(key, state)
	local h = heroes[key]
	if not h then return false end
	for _, b in ipairs(h.stateButtons) do
		if b.state == state then b:GetScript("OnClick")(b, "LeftButton") return true end
	end
	return false
end

function OA.buildIntro(parent, version)
	local h = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	h:SetHeight(OA.HERO_H - 14)
	h:SetBackdrop(W.BACKDROP)
	h:SetBackdropColor(OA.PANEL[1], OA.PANEL[2], OA.PANEL[3], 1)
	h:SetBackdropBorderColor(0.36, 0.28, 0.17, 1)
	h.banner = h:CreateTexture(nil, "BACKGROUND", nil, 1)
	h.banner:SetTexture(ART .. OA.SCHOOL[ns.THEME.fallback].banner)
	h.banner:SetPoint("TOPLEFT", 1, -1)
	h.banner:SetPoint("BOTTOMRIGHT", -1, 1)
	h.shade = h:CreateTexture(nil, "BACKGROUND", nil, 2)
	h.shade:SetPoint("TOPLEFT", 1, -1)
	h.shade:SetPoint("BOTTOMLEFT", 1, 1)
	h.shade:SetWidth(420)
	h.shade:SetColorTexture(1, 1, 1, 1)
	pcall(h.shade.SetGradient, h.shade, "HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
	OA.addCorners(h)
	h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	h.title:SetPoint("LEFT", 40, 8)
	h.title:SetText(ns.NAME)
	h.title:SetShadowOffset(1, -1)
	h.version = h:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	h.version:SetPoint("TOPLEFT", h.title, "BOTTOMLEFT", 0, -6)
	h.version:SetTextColor(0.80, 0.74, 0.66)
	h.version:SetText("Version " .. (version or "?"))
	h.version:SetShadowOffset(1, -1)
	function h:refresh()
		local w = self:GetWidth()
		if not w or w <= 0 then w = parent:GetWidth() end
		self.banner:SetTexCoord(coverCoords(w - 2, OA.HERO_H - 16))
	end
	return h
end

-- Style tiles: an icon wearing a style that isn't saved anywhere, drawn by the HUD's own code.

do
	local PARTS = { "border", "glow", "pop", "resetpop", "frame" }
	local Tile = {}
	Tile.__index = Tile

	local function copy(v) return type(v) == "table" and CopyTable(v) or v end

	local function setStyle(owner, part, st)
		local spec = ns.Style.PARTS[part]
		local t = ns.Style.clean(st, spec.defaults, spec.ranges)
		t.follow = false
		owner[spec.path[1]] = t
	end

	function Tile:wear(base, over)
		for _, part in ipairs(PARTS) do
			local st = ns.Style.get(base, part)
			for k, v in pairs(over and over[part] or {}) do st[k] = copy(v) end
			setStyle(self.owner, part, st)
		end
		-- A repaint's reads of the old styles would draw them
		ns.Style.forget(self.owner)
		self.ic.glowF:restyle()
		self:fit()
	end

	function Tile:school(s)
		self.ic.school = s
		self.ic.glowF:restyle()
		self:fit()
	end

	function Tile:icon(tex) self.ic.tex:SetTexture(tex) end

	function Tile:dress(base, over, s, tex, size)
		if size then
			self.size = size
			self.box:SetSize(size, size)
		end
		self.ic.school = s
		self:icon(tex)
		self:wear(base, over)
	end

	function Tile:fit()
		local size = self.size
		ns.StyleArt.fit(self.ic, self.owner.border, size)
		self.ic:ClearAllPoints()
		self.ic:SetPoint("CENTER", self.box, "CENTER", 0, 0)
		ns.Frames.mount(self.ic, self.owner, size)
		if self.glowing then self.ic.fx:fit(self.ic:GetWidth()) end
	end

	function Tile:glow(on)
		self.glowing = on and true or false
		self.ic:SetGlowShown(self.glowing)
	end

	function Tile:pop(kind) self.ic:Pop(kind) end

	function Tile:label(text, badge)
		if not self.text then
			self.text = self.box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			self.text:SetPoint("TOP", self.box, "BOTTOM", 0, -3)
		end
		self.text:SetText(text or "")
		self.text:SetShown(text ~= nil)
		for _, b in ipairs({ "exp", "tag" }) do if self[b] then self[b]:Hide() end end
		if not (text and badge) then return end
		local b
		if badge == true then
			self.exp = self.exp or OA.expBadge(self.box)
			b = self.exp
		else
			self.tag = self.tag or OA.tagBadge(self.box, badge)
			self.tag.text:SetText(badge)
			self.tag:SetWidth(self.tag.text:GetStringWidth() + 12)
			b = self.tag
		end
		b:ClearAllPoints()
		b:SetPoint("TOP", self.text, "BOTTOM", 0, -2)
		b:Show()
	end

	function Tile:point(...) self.box:ClearAllPoints(); self.box:SetPoint(...) end

	local function make(parent, size)
		local t = setmetatable({ size = size, owner = {} }, Tile)
		for _, part in ipairs(PARTS) do setStyle(t.owner, part) end
		t.box = CreateFrame("Frame", nil, parent)
		t.box:SetSize(size, size)
		t.ic = W.makeIcon(t.box, size, t.owner)
		-- Sits on whole pixels so its picture snaps with the art, or a sliver shows past flush art.
		if t.ic.tex.SetSnapToPixelGrid then t.ic.tex:SetSnapToPixelGrid(true) end
		return t
	end

	-- Tiles are made once and reused: each icon's glow joins a restyle list that only grows.
	local free, made = {}, {}
	local Pool = {}
	OA.tilePool = Pool

	function Pool.acquire(parent, size, want, strict)
		local t
		if want then
			for i = #free, 1, -1 do
				local f = free[i]
				if f == want or (type(want) == "function" and want(f)) then t = table.remove(free, i) break end
			end
		end
		if not (t or strict) then t = table.remove(free) end
		if not t then
			t = make(parent, size)
			table.insert(made, t)
		end
		t.released = nil
		t.ic.glowF.parked = nil
		t.size = size
		t.box:SetParent(parent)
		t.box:SetSize(size, size)
		t.ic.school = nil
		t:icon(OA.SCHOOLS[1].icon)
		t:glow(false)
		t:label(nil)
		t:wear(nil)
		t.box:Show()
		return t
	end

	function Pool.release(t)
		if t.released then return end
		t.released = true
		t:glow(false)
		t.ic.glowF.parked = true
		t.box:Hide()
		if t.ic.popRig then t.ic.popRig:stop() end
		t.box:ClearAllPoints()
		table.insert(free, t)
	end

	function Pool.counts() return #made, #free end
end
