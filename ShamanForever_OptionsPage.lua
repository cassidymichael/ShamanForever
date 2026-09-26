-- The options window's page kit: a page is a scrolling column of rows (headers, text, checkboxes,
-- sliders, dropdowns, colours, cards, buttons...). Rows can hide themselves; refresh reflows the
-- visible ones and pulls every control's value from the saved settings. The pages themselves are
-- built in ShamanForever_Options.lua.

local _, ns = ...

local Page = {}
Page.__index = Page
ns.Page = Page

-- The window's geometry, shared with ShamanForever_Options.lua. A fixed width, the one the art is
-- made for; the player may make it taller.
Page.WIDTH, Page.NAV_W = 864, 190
Page.PAGE_TOP = -38   -- pages start below the title bar
Page.LABEL_W = 150
local WIDTH, NAV_W, PAGE_TOP, LABEL_W = Page.WIDTH, Page.NAV_W, Page.PAGE_TOP, Page.LABEL_W
local ROW_W = WIDTH - NAV_W - 64                  -- initial row width; rows then follow the window
local SLIDER_MAX_W, SLIDER_VALUE_W = 360, 56   -- the value text sits right of the slider

-- above: over the frame's top-left corner, for full-width rows, whose right edge is far from the
-- mouse on the label; otherwise to the right of the frame.
function Page.setTip(frame, title, text, above)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		if above then
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
		else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
-- A page of the options window (win), scrolling in the area right of the nav.
function Page.new(win, key, title, indent)
	-- Blizzard's modern scroll frame and slim bar; the old one if this client lacks it.
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", "ShamanForeverOptionsScroll_" .. key, win, "ScrollFrameTemplate")
	if not (ok and scroll and scroll.ScrollBar) then
		scroll = CreateFrame("ScrollFrame", "ShamanForeverOptionsScroll_" .. key .. "Old", win, "UIPanelScrollFrameTemplate")
	else
		if scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
		-- A clear gutter between the page and the slim bar.
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 14, 0)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 14, 0)
		-- A mouse wheel step: Blizzard's default is 30 px, about one row; two rows feels right.
		if scroll.SetPanExtent then scroll:SetPanExtent(64) end
	end
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, w)
		content:SetWidth(w)
		ns.Options.refresh()
	end)
	scroll:Hide()
	return setmetatable({ win = win, key = key, title = title, indent = indent, scroll = scroll, content = content,
		items = {} }, Page)
end

-- shown: nil, or a function: the row is hidden while it returns false.
function Page:add(frame, height, shown, refresh)
	-- A page-wide gate (set around a run of rows) hides them all while it returns false.
	local gate = self.gate
	if gate then
		local inner = shown
		shown = function() return gate() and (not inner or inner()) and true or false end
	end
	table.insert(self.items, { frame = frame, height = height, shown = shown, refresh = refresh, rowIndent = self.rowIndent })
	return frame
end

-- A row that shows only while active() is true (and shown(), if given).
function Page.showWhen(active, shown)
	return function() return (not shown or shown()) and active() and true or false end
end

function Page:refresh()
	if self.fixed then
		local ok, err = pcall(self.fixed.refresh, self.fixed)
		if not ok and not self.fixedReported then
			self.fixedReported = true
			ns.say("options: the %s page header failed to update: %s", self.key, tostring(err))
		end
	end
	local y = 0
	for _, it in ipairs(self.items) do
		local show = not it.shown or it.shown()
		it.frame:SetShown(show)
		if show then
			-- One failing row must not blank the rest of the page: report it once and carry on.
			if it.refresh then
				local ok, err = pcall(it.refresh)
				if not ok and not it.reported then
					it.reported = true
					ns.say("options: a row on the %s page failed to update: %s", self.key, tostring(err))
				end
			end
			it.frame:ClearAllPoints()
			local indent = it.rowIndent or 0   -- rows inside a panel (Layout's group settings)
			it.frame:SetPoint("TOPLEFT", self.content, "TOPLEFT", indent, -y)
			it.frame:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -indent, -y)
			y = y + (type(it.height) == "function" and it.height() or it.height)
		end
	end
	self.content:SetHeight(math.max(y, 1))
	if self.afterRefresh then self.afterRefresh() end
end

function Page:row(height)
	local f = CreateFrame("Frame", nil, self.content)
	f:SetSize(ROW_W, height)
	return f
end

function Page:label(f, text, tip)
	f:EnableMouse(true)
	Page.setTip(f, text, tip, true)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- icon: an optional texture before the text.
function Page:header(text, shown, note, icon)
	local f = self:row(36)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.text:SetPoint("BOTTOMLEFT", icon and 26 or 0, 7)
	if icon then
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetSize(20, 20)
		f.icon:SetPoint("BOTTOMLEFT", 0, 5)
		f.icon:SetTexture(icon)
		ns.cropIcon(f.icon)
	end
	f.text:SetText(text)
	if note then
		f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		f.note:SetPoint("BOTTOMLEFT", f.text, "BOTTOMRIGHT", 10, 1)
		f.note:SetText(note)
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 1)
	line:SetHeight(1)
	pcall(line.SetGradient, line, "HORIZONTAL", CreateColor(0.85, 0.71, 0.42, 0.45), CreateColor(0.85, 0.71, 0.42, 0))
	line:SetPoint("BOTTOMLEFT", 0, 3)
	line:SetPoint("BOTTOMRIGHT", 0, 3)
	return self:add(f, 36, shown)
end

-- Names the last row added, for ns.Options.openGeneral and the like to scroll to.
function Page:anchor(name)
	self.anchors = self.anchors or {}
	self.anchors[name] = self.items[#self.items].frame
end

-- Wraps to the page width; the row grows to fit. str may be a function, re-read on every refresh.
-- Helper text, in grey so it reads apart from the controls.
local HELP_GREY = 0.72
function Page:text(str, shown)
	local f = self:row(20)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.text:SetTextColor(HELP_GREY, HELP_GREY, HELP_GREY)
	f.text:SetPoint("TOPLEFT", 4, -4)
	f.text:SetJustifyH("LEFT")
	f.text:SetSpacing(2)
	return self:add(f, function() return f.text:GetStringHeight() + 12 end, shown, function()
		f.text:SetWidth(self.content:GetWidth() - 8)
		f.text:SetText(type(str) == "function" and str() or str)
	end)
end

function Page:checkbox(label, tip, get, set, shown)
	local f = self:row(30)
	local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("LEFT", 0, 0)
	cb.Text:SetFontObject("GameFontHighlight")
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(button) set(button:GetChecked() and true or false) end)
	Page.setTip(cb, label, tip)
	f.check = cb
	return self:add(f, 30, shown, function() cb:SetChecked(get() and true or false) end)
end

function Page:slider(label, tip, minV, maxV, step, fmt, get, set, shown)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local s = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	s:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	local updating = false   -- while the page sets the value itself
	s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5),
		{ [MinimalSliderWithSteppersMixin.Label.Right] = fmt })
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		if updating then return end
		v = math.floor(v / step + 0.5) * step
		if step < 1 then v = tonumber(string.format("%.2f", v)) end
		set(v)
	end, s)
	return self:add(f, 34, shown, function()
		-- Fit the page width so the value text never runs past the edge of a narrow window.
		s:SetWidth(math.max(math.min(self.content:GetWidth() - LABEL_W - SLIDER_VALUE_W, SLIDER_MAX_W), 80))
		updating = true
		s:SetValue(get() or minV)
		updating = false
	end)
end

-- choices: list of { value, text }, or a function returning one
function Page:dropdown(label, tip, choices, get, set, shown, width)
	local f = self:row(34)
	f.label = self:label(f, label, tip)
	local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
	dd:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	dd:SetWidth(width or 200)
	dd:SetupMenu(function(_, rootDescription)
		for _, c in ipairs(type(choices) == "function" and choices() or choices) do
			rootDescription:CreateRadio(c[2], function() return get() == c[1] end, function() set(c[1]) end)
		end
	end)
	f.dropdown = dd
	return self:add(f, 34, shown, function() dd:GenerateMenu() end)
end

-- A colour swatch; clicking opens Blizzard's colour picker (with opacity). get/set use { r, g, b, a }.
function Page:color(label, tip, get, set, shown)
	local f = self:row(30)
	self:label(f, label, tip)
	local b = CreateFrame("Button", nil, f, "BackdropTemplate")
	b:SetSize(22, 22)
	b:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(0.5, 0.5, 0.5, 1)   -- shows through a translucent colour
	b:SetBackdropBorderColor(1, 1, 1, 0.6)
	b.swatch = b:CreateTexture(nil, "ARTWORK")
	b.swatch:SetPoint("TOPLEFT", 2, -2)
	b.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
	b:SetScript("OnClick", function()
		local c = get()
		if not c then return end
		local function apply()
			local r, g, bl = ColorPickerFrame:GetColorRGB()
			set({ r, g, bl, ColorPickerFrame:GetColorAlpha() })
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = true,
			swatchFunc = apply, opacityFunc = apply,
			cancelFunc = function(prev) set({ prev.r, prev.g, prev.b, prev.a or 1 }) end,
		})
	end)
	Page.setTip(b, label, tip)
	return self:add(f, 30, shown, function()
		local c = get() or { 0.5, 0.5, 0.5, 1 }
		b.swatch:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	end)
end

-- A button whose text follows the settings, e.g. Unlock / Lock.
function Page:button(textFn, onClick, tip, width, shown)
	local f = self:row(32)
	local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	btn:SetSize(width or 160, 22)
	btn:SetPoint("LEFT", 0, 0)
	btn:SetScript("OnClick", onClick)
	btn:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText(textFn())
		GameTooltip:AddLine(tip, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return self:add(f, 32, shown, function() btn:SetText(textFn()) end)
end

-- list: { { text, onClick, tip, width, enabled }, ... }; enabled is an optional function.
function Page:buttons(list, shown)
	local f = self:row(32)
	local x = 0
	local toggles = {}
	for _, b in ipairs(list) do
		local w = b[4] or 140
		local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		btn:SetSize(w, 22)
		btn:SetPoint("LEFT", x, 0)
		btn:SetText(b[1])
		btn:SetScript("OnClick", b[2])
		Page.setTip(btn, b[1], b[3])
		if b[5] then toggles[btn] = b[5] end
		x = x + w + 6
	end
	return self:add(f, 32, shown, function()
		for btn, enabled in pairs(toggles) do btn:SetEnabled(enabled() and true or false) end
	end)
end

-- A page header pinned above the page's scrolling area (so an element's preview stays in view while
-- settings change). The scrollbar starts below it, so the header spans the full page width, with
-- the same margin on the right (from the window's inner edge) as on the left (from the nav).
function Page:pin(h)
	local win = self.win
	h:SetParent(win)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	h:SetPoint("TOPRIGHT", win, "TOPRIGHT", -22, PAGE_TOP)
	h:Hide()
	self.fixed = h
	self.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP - (h.heroH or ns.Look.HERO_H))
	return h
end

-- An element page's header (ShamanForever_OptionsLook.lua): art, identity and a live preview.
function Page:hero(key)
	return self:pin(ns.Look.buildHero(self.win, key))
end

-- The options' panel look: a dark fill and a thin border (brown unless given).
function Page.panelBackdrop(f, r, g, b)
	f:SetBackdrop(ns.BACKDROP)
	f:SetBackdropColor(0.09, 0.075, 0.06, 1)
	f:SetBackdropBorderColor(r or 0.23, g or 0.17, b or 0.10, 1)
end

-- Pick one value from a row of icon cards. choices: { value, text, icon, experimental feature name }.
local CARD_W, CARD_H = 84, 84
function Page:cards(label, tip, choices, get, set, shown)
	local f = self:row(CARD_H + 8)
	self:label(f, label, tip)
	f.cards = {}
	for i, c in ipairs(choices) do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		b:SetSize(CARD_W, CARD_H)
		b:SetPoint("LEFT", f, "LEFT", LABEL_W + (i - 1) * (CARD_W + 6), 0)
		Page.panelBackdrop(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(34, 34)
		b.icon:SetPoint("TOP", 0, -8)
		b.icon:SetTexture(c[3])
		ns.cropIcon(b.icon)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("TOP", b.icon, "BOTTOM", 0, -5)
		b.text:SetWidth(CARD_W - 6)
		b.text:SetText(c[2])
		if c[4] then
			local badge = ns.Look.expBadge(b, c[4])
			badge:SetScale(0.8)
			badge:SetPoint("BOTTOM", 0, 5)
		end
		b.value = c[1]
		b:SetScript("OnClick", function() set(c[1]); ns.Options.refresh() end)
		f.cards[i] = b
	end
	return self:add(f, CARD_H + 8, shown, function()
		local v = get()
		for _, b in ipairs(f.cards) do
			local on = b.value == v
			b:SetBackdropBorderColor(on and 0.88 or 0.23, on and 0.66 or 0.17, on and 0.29 or 0.10, 1)
			b.icon:SetDesaturated(not on)
			b.icon:SetAlpha(on and 1 or 0.7)
			b.text:SetTextColor(on and 1 or 0.75, on and 0.84 or 0.72, on and 0.5 or 0.68)
		end
	end)
end

-- Big buttons side by side, for the most common actions. list: { icon, titleFn, subtitleFn, onClick }.
function Page:bigButtons(list)
	local H, GAP = 56, 10
	local f = self:row(H + 8)
	local buttons = {}
	for i, t in ipairs(list) do
		local b = CreateFrame("Button", nil, f, "BackdropTemplate")
		Page.panelBackdrop(b, 0.55, 0.42, 0.22)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(36, 36)
		b.icon:SetPoint("LEFT", 12, 0)
		b.icon:SetTexture(t[1])
		ns.cropIcon(b.icon)
		b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -1)
		b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 1)
		b.sub:SetTextColor(0.78, 0.74, 0.68)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(0.88, 0.66, 0.29, 0.10)
		b:SetScript("OnClick", t[4])
		b.titleFn, b.subFn = t[2], t[3]
		buttons[i] = b
	end
	return self:add(f, H + 8, nil, function()
		local w = (self.content:GetWidth() - (#buttons - 1) * GAP) / #buttons
		for i, b in ipairs(buttons) do
			b:SetSize(w, H)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", (i - 1) * (w + GAP), 0)
			b.title:SetText(b.titleFn())
			b.sub:SetText(b.subFn())
		end
	end)
end

-- A boxed notice, e.g. the beta warning.
function Page:callout(text, shown)
	local f = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
	Page.panelBackdrop(f, 0.95, 0.59, 0.24)
	f:SetBackdropColor(0.95, 0.59, 0.24, 0.08)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", 12, -10)
	f.text:SetJustifyH("LEFT")
	f.text:SetText(text)
	return self:add(f, function() return f.text:GetStringHeight() + 30 end, shown, function()
		f.text:SetWidth(self.content:GetWidth() - 24)
		f:SetHeight(f.text:GetStringHeight() + 20)
	end)
end

-- Read-only text the player can select and copy (links cannot be clicked in game).
-- icon, color: an optional small icon before the label (a white one tinted, e.g. a site's logo).
function Page:copyField(label, value, icon, color)
	local f = self:row(30)
	local fs = self:label(f, label)
	if icon then
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetSize(18, 18)
		t:SetPoint("LEFT", 4, 0)
		t:SetTexture(icon)
		if color then t:SetVertexColor(color[1], color[2], color[3]) end
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 30, 0)
		fs:SetWidth(LABEL_W - 34)
	end
	local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	e:SetSize(380, 20)
	e:SetPoint("LEFT", f, "LEFT", LABEL_W + 6, 0)
	e:SetAutoFocus(false)
	e:SetText(value)
	e:SetCursorPosition(0)
	e:SetScript("OnTextChanged", function(box, user) if user then box:SetText(value); box:HighlightText() end end)
	e:SetScript("OnEditFocusGained", function(box) box:HighlightText() end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return self:add(f, 30)
end

-- An experimental feature, where to find it, and its feedback badge.
function Page:experimental(name, where)
	local f = self:row(28)
	self:label(f, name)
	local w = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	w:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	w:SetText(where)
	ns.Look.expBadge(f, name, "Give feedback"):SetPoint("LEFT", w, "RIGHT", 10, 0)
	return self:add(f, 28)
end
