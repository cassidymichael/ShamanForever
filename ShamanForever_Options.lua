-- Options window, opened with /sf. The entry under Escape > Options > AddOns only points here: the
-- Settings list is built once, so it cannot follow groups being added and removed.
local ADDON, ns = ...

-- A fixed width, the one the art is made for; the player may make it taller.
local WIDTH, HEIGHT, NAV_W = 864, 700, 190
local MIN_H, MAX_H = 560, 1300
local PAGE_TOP = -38   -- pages start below the title bar
local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
local ROW_W = WIDTH - NAV_W - 64                  -- initial row width; rows then follow the window
local LABEL_W = 150
local SLIDER_MAX_W, SLIDER_VALUE_W = 360, 56   -- the value text sits right of the slider

local win
local pages, pageOrder, currentPage = {}, {}, nil
local selectedGroup = 1

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end
local function relayout() ns.applyLayout() end
local function respell() ns.resolveSpells(); ns.refreshAll() end

local function setTip(frame, title, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Pages: a scrolling column of rows. Rows can hide themselves; refresh reflows the visible ones
-- and pulls every control's value from the saved settings.
------------------------------------------------------------------------
local Page = {}
Page.__index = Page

local function newPage(key, title, indent)
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
	end
	scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -40, 12)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ROW_W, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function(_, w)
		content:SetWidth(w)
		if ns.RefreshOptions then ns.RefreshOptions() end
	end)
	scroll:Hide()
	local p = setmetatable({ key = key, title = title, indent = indent, scroll = scroll, content = content, items = {} }, Page)
	pages[key] = p
	table.insert(pageOrder, p)
	return p
end

-- shown: nil, a function (the row is hidden while it returns false), or dimWhen(...) (the row stays
-- in place but greys out, and does nothing, while another setting makes it irrelevant).
function Page:add(frame, height, shown, refresh)
	local dim
	if type(shown) == "table" then dim, shown = shown, shown.shown end
	table.insert(self.items, { frame = frame, height = height, shown = shown, dim = dim, refresh = refresh, rowIndent = self.rowIndent })
	return frame
end

-- Grey a row out unless active() is true; reason shows in its tooltip.
local function dimWhen(active, reason, shown) return { active = active, reason = reason, shown = shown } end

-- A clear cover over a greyed-out row: swallows clicks and wheel, and says why.
local function applyDim(frame, dim)
	local on = dim.active()
	frame:SetAlpha(on and 1 or 0.4)
	if not frame.dimCover then
		local c = CreateFrame("Frame", nil, frame)
		c:SetAllPoints()
		c:SetFrameLevel(frame:GetFrameLevel() + 30)
		c:EnableMouse(true)
		c:EnableMouseWheel(true)
		c:SetScript("OnMouseWheel", function() end)
		c:SetScript("OnEnter", function(self)
			if not dim.reason then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(dim.reason, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		frame.dimCover = c
	end
	frame.dimCover:SetShown(not on)
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
			if it.dim then applyDim(it.frame, it.dim) end
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
	setTip(f, text, tip)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", 4, 0)
	fs:SetWidth(LABEL_W - 8)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

function Page:header(text, shown, note)
	local f = self:row(36)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.text:SetPoint("BOTTOMLEFT", 0, 7)
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

-- Wraps to the page width; the row grows to fit. str may be a function, re-read on every refresh.
function Page:text(str, shown)
	local f = self:row(20)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	setTip(cb, label, tip)
	return self:add(f, 30, shown, function() cb:SetChecked(get() and true or false) end)
end

function Page:slider(label, tip, minV, maxV, step, fmt, get, set, shown)
	local f = self:row(34)
	self:label(f, label, tip)
	local s = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
	s:SetPoint("LEFT", f, "LEFT", LABEL_W, 0)
	local updating = true
	s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5),
		{ [MinimalSliderWithSteppersMixin.Label.Right] = fmt })
	updating = false
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
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
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
	setTip(b, label, tip)
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
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
		setTip(btn, b[1], b[3])
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
	h:SetParent(win)
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP)
	h:SetPoint("TOPRIGHT", win, "TOPRIGHT", -22, PAGE_TOP)
	h:Hide()
	self.fixed = h
	self.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", NAV_W + 18, PAGE_TOP - ns.Look.HERO_H)
	return h
end

-- An element page's header (ShamanForever_OptionsLook.lua): art, identity and a live preview.
function Page:hero(key)
	return self:pin(ns.Look.buildHero(win, key))
end

local function panelBackdrop(f, r, g, b)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
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
		panelBackdrop(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(34, 34)
		b.icon:SetPoint("TOP", 0, -8)
		b.icon:SetTexture(c[3])
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
		b:SetScript("OnClick", function() set(c[1]); ns.RefreshOptions() end)
		f.cards[i] = b
	end
	setTip(f, label, tip)
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
		panelBackdrop(b, 0.55, 0.42, 0.22)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(36, 36)
		b.icon:SetPoint("LEFT", 12, 0)
		b.icon:SetTexture(t[1])
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
	panelBackdrop(f, 0.95, 0.59, 0.24)
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
function Page:copyField(label, value)
	local f = self:row(30)
	self:label(f, label)
	local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	e:SetSize(380, 20)
	e:SetPoint("LEFT", f, "LEFT", LABEL_W + 6, 0)
	e:SetAutoFocus(false)
	e:SetText(value)
	e:SetCursorPosition(0)
	e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(value); self:HighlightText() end end)
	e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
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

------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
local function pct(v) return string.format("%.0f%%", v * 100) end
local function times(v) return string.format("%.2fx", v) end
local function int(v) return string.format("%d", v) end

local function get(key) return function() return db()[key] end end
local function set(key, after) return function(v) db()[key] = v; (after or relayout)() end end

local function groupCount() return #db().groups end
local function hasGroups() return groupCount() > 0 end
local function selected()
	local n = groupCount()
	if selectedGroup > n then selectedGroup = n end
	if selectedGroup < 1 then selectedGroup = 1 end
	return db().groups[selectedGroup]
end
local function groupGet(key) return function() local g = selected(); return g and g[key] end end
local function groupSet(key) return function(v) local g = selected(); if g then g[key] = v; relayout() end end end

------------------------------------------------------------------------
-- Page contents
------------------------------------------------------------------------
local function lockText() return acct().locked and "Unlock positioning" or "Lock positioning" end
local function toggleLock() acct().locked = not acct().locked; relayout() end
local LOCK_TIP = "Unlocked, drag groups on screen, mouse wheel to scale, shift + wheel for opacity. /sf lock does the same."

local aboutExp   -- About's Experimental heading, for ns.ShowExperimental
local groupPanel -- Layout's selected-group panel, for ns.OpenGroupSettings

local function addonVersion()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Home, the page the window opens on: name, version, warnings and where to send feedback.
local function buildHome(p)
	p:pin(ns.Look.buildIntro(win, addonVersion()))
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText,
			function() return acct().locked and "Move groups on screen" or "Done moving? Lock them" end, toggleLock },
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", function() return "Layout" end,
			function() return "Set up groups of elements" end, function() ns.OpenOptions("layout") end },
	})
	-- TEMPORARY: remove once Blizzard fixes the beta's SavedVariables loading.
	p:callout("|cffff9933Beta:|r saved settings don't load on startup yet. ForeverSVFix works around it.")
	p:header("Feedback")
	p:text("Ideas, requests or problems? Open an issue on GitHub:")
	p:copyField("Issues", ns.Look.REPO .. "/issues")
end

-- General: the defaults every element inherits, then housekeeping.
local function buildGeneral(p)
	p:header("Defaults for all elements")
	p:text("Elements and groups can override some of these on their own pages.")
	p:slider("Icon size", "Base size of every element. Each group's scale multiplies it.", 24, 96, 1, int,
		get("iconSize"), set("iconSize"))
	local function bget(k) return function() return db().border[k] end end
	local function bset(k) return function(v) db().border[k] = v; relayout() end end
	local function bordered() return db().border.show end
	p:checkbox("Border", "A border around every element. Groups can have their own on the Layout page.",
		bget("show"), bset("show"))
	p:slider("Border size", "Thickness in screen pixels.", 1, 8, 1,
		function(v) return string.format("%d px", v) end, bget("size"), bset("size"), dimWhen(bordered, "Turn on Border to use this."))
	p:color("Border colour", "Colour and opacity.", bget("color"), bset("color"), dimWhen(bordered, "Turn on Border to use this."))
	p:checkbox("Countdown text", "Numbers on every cooldown.", get("cdText"), set("cdText"))
	p:slider("Countdown size", "Elements can set their own on their page.", 8, 48, 1, int,
		get("cdTextSize"), set("cdTextSize"), dimWhen(function() return db().cdText end, "Turn on Countdown text to use this."))

	local function hasReporter() return ns.hasIssueReporter and ns.hasIssueReporter() end
	p:header("Beta", hasReporter)
	p:checkbox("Hide the Issue Reporter button", "Blizzard's beta Issue Reporter button. /ptr still works while it is hidden. Shaman Forever also remembers where you drag it.",
		function() return acct().hideIssueReporter end, function(v) acct().hideIssueReporter = v; ns.applyIssueReporter() end, hasReporter)
end

-- Asks for a profile name, then passes it to action, which returns an error message or nil.
local nameAction
local function askName(prompt, initial, action)
	nameAction = { prompt = prompt, initial = initial or "", run = action }
	StaticPopup_Show("SHAMANFOREVER_PROFILE_NAME", prompt)
end

local function buildProfiles(p)
	local function notDefault() return ns.profileName() ~= ns.DEFAULT_PROFILE end
	p:header("Profile")
	p:dropdown("This character", "Each character uses one profile. New characters use Default.", function()
		local t = {}
		for _, name in ipairs(ns.profileNames()) do table.insert(t, { name, name }) end
		return t
	end, ns.profileName, ns.useProfile)
	p:buttons({
		{ "New", function() askName("Name for the new profile:", nil, function(n) return ns.newProfile(n) end) end,
			"A new profile with default settings.", 90 },
		{ "Copy", function() askName("Name for the copy:", ns.profileName() .. " copy", function(n) return ns.newProfile(n, true) end) end,
			"A new profile with this one's settings.", 90 },
		{ "Rename", function() askName("New name:", ns.profileName(), ns.renameProfile) end,
			"Default can't be renamed.", 90, notDefault },
		{ "Delete", function() StaticPopup_Show("SHAMANFOREVER_DELETE_PROFILE", ns.profileName()) end,
			"Characters using it go back to Default. Default can't be deleted.", 90, notDefault },
		{ "Reset", function() StaticPopup_Show("SHAMANFOREVER_RESET", ns.profileName()) end,
			"Every setting in this profile back to defaults, including the layout.", 90 },
	})
end

local function buildAbout(p)
	p:header("Shaman Forever")
	p:text(function() return "Version " .. addonVersion() .. ". A shaman HUD for WoW Forever." end)
	p:copyField("Source and issues", ns.Look.REPO)
	p:copyField("CurseForge", "https://www.curseforge.com/wow/addons/shamanforever")
	local expHeader = p:header("Experimental")
	-- A gold glow ns.ShowExperimental flashes over the heading.
	local glow = expHeader:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -6, 2)
	glow:SetPoint("BOTTOMRIGHT", 6, -2)
	glow:SetColorTexture(0.88, 0.66, 0.29, 0.35)
	glow:SetAlpha(0)
	local flash = glow:CreateAnimationGroup()
	local up = flash:CreateAnimation("Alpha")
	up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.35); up:SetOrder(1)
	local down = flash:CreateAnimation("Alpha")
	down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.9); down:SetOrder(2)
	flash:SetLooping("NONE")
	aboutExp = { page = p, header = expHeader, flash = flash }
	p:text("I can't test these in game yet. If you can, please try them and tell me whether they work and what could be improved.")
	p:experimental("Water Shield", "Shields > Track")
	p:experimental("Either shield", "Shields > Track")
	p:header("Art")
	p:text("Banners from public-domain paintings: Thomas Moran, The Chasm of the Colorado (earth); Joseph Wright of Derby, " ..
		"Vesuvius from Portici (fire); Frederic Edwin Church, Rainy Season in the Tropics (water) and Aurora Borealis (spirit); " ..
		"Francisque Millet, Mountain Landscape with Lightning (air). Corner and divider ornaments: public domain / CC0, Wikimedia Commons.")
end

------------------------------------------------------------------------
-- Group board (Layout page): one card per group plus "New group". Drag an element's chip onto a card
-- to move it there, at the position the blue line shows; click a chip for a menu. Hidden elements
-- stay in their group, dimmed.
------------------------------------------------------------------------
local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" }, { "never", "Never" } }
local SHOW_TIP = "When the element is drawn. Never keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups can also be set to show only in combat on the Layout page; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked."

local CARD_GAP, CHIP_H, CARD_HEAD = 8, 26, 28
local board = { cards = {}, chips = {} }

local function cardUnderCursor()
	for _, c in ipairs(board.cards) do
		if c:IsShown() and c:IsMouseOver() then return c end
	end
end

-- Position among the card's other chips that the cursor points at (chips run top to bottom).
local function dropIndex(c, key)
	local _, cy = GetCursorPosition()
	local at, n, others = 1, 0, {}
	for _, chip in ipairs(c.chips) do
		if chip.key ~= key then
			n = n + 1
			others[n] = chip
			local _, y = chip:GetCenter()
			if y and y * chip:GetEffectiveScale() > cy then at = n + 1 end
		end
	end
	return at, others
end

-- Gold marks the selected group, as it marks the current page in the nav; white is drop feedback.
local function cardBorder(c)
	if board.dragKey and c == board.hover then c:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
	elseif type(c.target) == "number" and c.target == selectedGroup then c:SetBackdropBorderColor(0.88, 0.66, 0.29, 1)
	else c:SetBackdropBorderColor(0.23, 0.17, 0.10, 1) end
end

local function updateDragFeedback()
	board.hover = cardUnderCursor()
	for _, c in ipairs(board.cards) do cardBorder(c) end
	local ind, c = board.indicator, board.hover
	ind:Hide()
	if not (c and type(c.target) == "number") then return end
	local at, others = dropIndex(c, board.dragKey)
	ind:ClearAllPoints()
	if #others == 0 then
		ind:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -CARD_HEAD + 1)
		ind:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -CARD_HEAD + 1)
	elseif at <= #others then
		ind:SetPoint("BOTTOMLEFT", others[at], "TOPLEFT", 0, 0)
		ind:SetPoint("BOTTOMRIGHT", others[at], "TOPRIGHT", 0, 0)
	else
		ind:SetPoint("TOPLEFT", others[#others], "BOTTOMLEFT", 0, 0)
		ind:SetPoint("TOPRIGHT", others[#others], "BOTTOMRIGHT", 0, 0)
	end
	ind:Show()
end

local function startDrag(chip)
	if InCombatLockdown() then ns.say("layout changes wait until combat ends"); return end
	board.dragKey = chip.key
	chip:SetAlpha(0.35)
	local e = ns.ELEMENTS[chip.key]
	e.paint(board.ghost.icon)
	board.ghost.text:SetText(e.label)
	board.ghost:Show()
end

local function finishDrag()
	local key = board.dragKey
	board.dragKey = nil
	board.dragEnded = GetTime()
	board.ghost:Hide()
	board.indicator:Hide()
	if not key then return end
	local c = cardUnderCursor()
	if c then
		if type(c.target) == "number" then ns.placeElement(key, c.target, (dropIndex(c, key)))
		else ns.placeElement(key, c.target) end
	end
	ns.RefreshOptions()   -- also restores the dimmed chip when nothing moved
end

local function chipMenu(chip)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	if board.dragEnded and GetTime() - board.dragEnded < 0.3 then return end   -- the release that ended a drag
	local key = chip.key
	MenuUtil.CreateContextMenu(chip, function(_, root)
		root:CreateTitle(ns.ELEMENTS[key].label)
		root:CreateButton("Open settings", function() ns.OpenElementOptions(key) end)
		root:CreateDivider()
		local gi, i = ns.findElement(key)
		if gi and i > 1 then root:CreateButton("Move earlier", function() ns.placeElement(key, gi, i - 1) end) end
		if gi and i < #db().groups[gi].members then root:CreateButton("Move later", function() ns.placeElement(key, gi, i + 1) end) end
		for g = 1, groupCount() do
			if g ~= gi then root:CreateButton("Move to group " .. g, function() ns.placeElement(key, g) end) end
		end
		if not (gi and #db().groups[gi].members == 1) then
			root:CreateButton("Move to a new group", function() ns.placeElement(key, "new") end)
		end
		root:CreateDivider()
		root:CreateTitle("Show")
		for _, c in ipairs(SHOW_CHOICES) do
			root:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
		end
	end)
end

local function getCard(i)
	local c = board.cards[i]
	if c then return c end
	c = CreateFrame("Button", nil, board.frame, "BackdropTemplate")
	c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	c:SetBackdropColor(0.09, 0.075, 0.06, 1)
	c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.title:SetPoint("TOPLEFT", 8, -8)
	c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.sub:SetPoint("TOPRIGHT", -8, -9)
	c.empty = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	c.empty:SetPoint("TOPLEFT", 10, -CARD_HEAD - 4)
	c.empty:SetPoint("RIGHT", -10, 0)
	c.empty:SetJustifyH("LEFT")
	c:SetScript("OnClick", function(self)
		if type(self.target) == "number" then
			if self.target ~= selectedGroup then board.flashPanel = true end
			selectedGroup = self.target
			ns.RefreshOptions()
		end
	end)
	c.chips = {}
	board.cards[i] = c
	return c
end

local function getChip(i)
	local chip = board.chips[i]
	if chip then return chip end
	chip = CreateFrame("Button", nil, board.frame)
	chip:SetHeight(CHIP_H - 2)
	chip:SetFrameLevel(board.frame:GetFrameLevel() + 10)
	local bg = chip:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.06)
	local hl = chip:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	chip.icon = chip:CreateTexture(nil, "ARTWORK")
	chip.icon:SetSize(20, 20)
	chip.icon:SetPoint("LEFT", 2, 0)
	chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:RegisterForDrag("LeftButton")
	chip:SetScript("OnClick", chipMenu)
	chip:SetScript("OnDragStart", startDrag)
	chip:SetScript("OnDragStop", finishDrag)
	setTip(chip, "Move element", "Drag onto another group or New group. Drop between elements to set the order. Click for a menu, including when it shows.")
	board.chips[i] = chip
	return chip
end

local function layoutBoard()
	local groups = db().groups
	local colW = (board.page.content:GetWidth() - CARD_GAP) / 2
	local nCard, nChip = 0, 0
	local function fill(target, keys, title, sub, emptyText)
		nCard = nCard + 1
		local c = getCard(nCard)
		c.target = target
		c.title:SetText(title)
		c.sub:SetText(sub or "")
		c.empty:SetText(emptyText or "")
		c.empty:SetShown(#keys == 0)
		wipe(c.chips)
		for i, key in ipairs(keys) do
			nChip = nChip + 1
			local chip = getChip(nChip)
			chip.key = key
			ns.ELEMENTS[key].paint(chip.icon)
			local mode = ns.showMode(key)
			chip.text:SetText(ns.ELEMENTS[key].label .. (mode == "never" and "  |cff888888(hidden)|r"
				or mode == "combat" and "  |cff888888(in combat)|r" or ""))
			chip:SetAlpha(mode == "never" and 0.5 or 1)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -CARD_HEAD - (i - 1) * CHIP_H)
			chip:SetPoint("RIGHT", c, "RIGHT", -6, 0)
			chip:Show()
			c.chips[i] = chip
		end
		local h = CARD_HEAD + math.max(#keys, 1) * CHIP_H + 8
		if #keys == 0 and emptyText then h = h + 12 end
		c:SetSize(colW, h)
		cardBorder(c)
		c:Show()
		return c, h
	end
	local function place(c, x, y)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", board.frame, "TOPLEFT", x, -y)
	end
	-- Groups fill two columns, each card going into the shorter one.
	local colY = { 0, 0 }
	for gi, g in ipairs(groups) do
		local c, h = fill(gi, g.members, "Group " .. gi, g.orientation == "vertical" and "Column" or "Row")
		local col = colY[1] <= colY[2] and 1 or 2
		place(c, (col - 1) * (colW + CARD_GAP), colY[col])
		colY[col] = colY[col] + h + CARD_GAP
	end
	local y = math.max(colY[1], colY[2])
	local newCard, h = fill("new", {}, "New group", nil, "Drop an element here to give it a group of its own.")
	place(newCard, 0, y)
	for i = nCard + 1, #board.cards do board.cards[i]:Hide() end
	for i = nChip + 1, #board.chips do board.chips[i]:Hide() end
	board.height = y + h
	board.frame:SetHeight(board.height)
end

local function buildBoard(p)
	board.page = p
	board.frame = p:row(10)
	board.indicator = board.frame:CreateTexture(nil, "OVERLAY")
	board.indicator:SetColorTexture(0.95, 0.95, 0.95, 1)
	board.indicator:SetHeight(2)
	board.indicator:SetDrawLayer("OVERLAY", 7)
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(180, 24)
	ghost:SetAlpha(0.9)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local s = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / s + 8, y / s)
		updateDragFeedback()
	end)
	board.ghost = ghost
	p:add(board.frame, function() return board.height or 10 end, nil, layoutBoard)
end

local function buildLayout(p)
	p:button(lockText, toggleLock, LOCK_TIP)
	p:checkbox("Test elements", "Adds placeholder elements in their own group, for trying out layouts.",
		function() return acct().testMode end, function(v) ns.setTestMode(v) end)
	p:header("Groups", nil, "Drag elements between groups. Click one for a menu.")
	p:add(p:row(6), 6)   -- a little room between the heading's line and the group cards
	buildBoard(p)

	-- The selected group's settings sit in a panel edged in the same gold as its card, titled with the
	-- group's number, direction and element icons, and flash when another group is picked.
	local panel = CreateFrame("Frame", nil, p.content, "BackdropTemplate")
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0.11, 0.09, 0.07, 0.9)
	panel:SetBackdropBorderColor(0.88, 0.66, 0.29, 0.9)
	panel:SetFrameLevel(p.content:GetFrameLevel())
	local glow = panel:CreateTexture(nil, "BORDER")
	glow:SetAllPoints()
	glow:SetColorTexture(0.88, 0.66, 0.29, 0.22)
	glow:SetAlpha(0)
	local flash = glow:CreateAnimationGroup()
	local up = flash:CreateAnimation("Alpha")
	up:SetFromAlpha(0); up:SetToAlpha(1); up:SetDuration(0.15); up:SetOrder(1)
	local down = flash:CreateAnimation("Alpha")
	down:SetFromAlpha(1); down:SetToAlpha(0); down:SetDuration(0.6); down:SetOrder(2)

	p:add(p:row(22), 22, hasGroups)   -- clear space between the board and the group panel
	p.rowIndent = 12
	local settingsHeader = p:header("Group", hasGroups)
	settingsHeader.icons = {}
	p.items[#p.items].refresh = function()
		local g = selected()
		if not g then return end
		settingsHeader.text:SetText(string.format("Group %d  |cffa89880·  %s|r", selectedGroup, g.orientation == "vertical" and "Column" or "Row"))
		for i, key in ipairs(g.members) do
			local t = settingsHeader.icons[i]
			if not t then
				t = settingsHeader:CreateTexture(nil, "ARTWORK")
				t:SetSize(18, 18)
				t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				settingsHeader.icons[i] = t
			end
			t:ClearAllPoints()
			t:SetPoint("LEFT", settingsHeader.text, "RIGHT", 10 + (i - 1) * 21, 0)
			ns.ELEMENTS[key].paint(t)
			t:Show()
		end
		for i = #g.members + 1, #settingsHeader.icons do settingsHeader.icons[i]:Hide() end
	end
	p:dropdown("Direction", "Lay the group out as a row or a column.",
		{ { "horizontal", "Row" }, { "vertical", "Column" } }, groupGet("orientation"), groupSet("orientation"), hasGroups)
	p:dropdown("Growth", "Which way the row or column extends from its first element.",
		{ { "forward", "Right / down" }, { "backward", "Left / up" } }, groupGet("growth"), groupSet("growth"), hasGroups)
	p:slider("Spacing", "Gap between the group's elements.", 0, 40, 1, int, groupGet("spacing"), groupSet("spacing"), hasGroups)
	p:slider("Scale", "Size of the whole group. Mouse wheel over the group while unlocked does the same.", 0.5, 3, 0.05, times,
		groupGet("scale"), function(v)
			local g = selected()
			if not g then return end
			-- Offsets are in the group's own units: rescale them so the centre stays put.
			if g.point == "CENTER" then g.x, g.y = g.x * g.scale / v, g.y * g.scale / v end
			g.scale = v
			relayout()
		end, hasGroups)
	p:slider("Opacity", "Transparency of the group. Shift + mouse wheel over the group while unlocked does the same.", 0.1, 1, 0.05, pct,
		groupGet("alpha"), groupSet("alpha"), hasGroups)
	local function hasGroupBorder() local g = selected(); return g and g.border ~= nil end
	-- Without a custom border the (greyed) rows show the general border the group actually uses.
	local function gbget(k) return function()
		local g = selected()
		if g and g.border then return g.border[k] end
		return db().border[k]
	end end
	local function gbset(k) return function(v) local g = selected(); if g and g.border then g.border[k] = v; relayout() end end end
	p:checkbox("Custom border", "Give this group its own border instead of the global one (General page). Turning this off goes back to the global border.",
		hasGroupBorder, function(v)
			local g = selected()
			if not g then return end
			g.border = v and CopyTable(db().border) or nil
			relayout()
		end, hasGroups)
	local function groupBorderShown() return hasGroupBorder() and selected().border.show end
	p:checkbox("Show border", "Show this group's border.", gbget("show"), gbset("show"),
		dimWhen(hasGroupBorder, "Turn on Custom border to use this.", hasGroups))
	p:slider("Border size", "Thickness in screen pixels.", 1, 8, 1, function(v) return string.format("%d px", v) end,
		gbget("size"), gbset("size"), dimWhen(groupBorderShown, "Turn on Custom border and Show border to use this.", hasGroups))
	p:color("Border colour", "Colour and opacity of this group's border.", gbget("color"), gbset("color"),
		dimWhen(groupBorderShown, "Turn on Custom border and Show border to use this.", hasGroups))
	p:checkbox("Only show in combat", "Hide this group out of combat. Each element also has its own Show setting (Always, In combat, Never) under Elements; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked.",
		groupGet("combatOnly"), groupSet("combatOnly"), hasGroups)
	local lastRow = p:buttons({
		-- Hard to undo, so each asks first.
		{ "Centre on screen", function() StaticPopup_Show("SHAMANFOREVER_CENTER", selectedGroup, nil, selectedGroup) end, "Moves the group to the middle of the screen.", 130 },
		{ "Split up", function() StaticPopup_Show("SHAMANFOREVER_SPLIT", selectedGroup, nil, selectedGroup) end, "Gives every element in the group a group of its own, left where it is.", 100 },
		{ "Hide all", function() StaticPopup_Show("SHAMANFOREVER_HIDEALL", selectedGroup, nil, selectedGroup) end, "Sets every element in the group to never show. They keep their places; set one back to Always to bring it back.", 100 },
	}, hasGroups)
	p:add(p:row(10), 10, hasGroups)
	p.rowIndent = nil

	groupPanel = { page = p, frame = panel }
	p.afterRefresh = function()
		panel:SetShown(hasGroups())
		if not hasGroups() then return end
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", settingsHeader, "TOPLEFT", -12, 2)
		panel:SetPoint("TOPRIGHT", settingsHeader, "TOPRIGHT", 12, 2)
		panel:SetPoint("BOTTOM", lastRow, "BOTTOM", 0, -8)
		if board.flashPanel then
			board.flashPanel = false
			flash:Stop()
			flash:Play()
		end
	end
end

------------------------------------------------------------------------
-- Elements: an overview of every element, and one page per real element under it in the nav.
------------------------------------------------------------------------
local ELEMENT_PAGES = {}   -- key -> page key, filled as element pages are built

local function groupText(key)
	local gi = ns.findElement(key)
	return gi and ("Group " .. gi) or "No group"
end

local function buildElements(p)
	p:header("Elements")
	local GROUP_X, SHOW_X = 150, 260   -- sized to fit beside the Settings button at the minimum width
	do
		local f = p:row(20)
		local function col(text, x)
			local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			fs:SetPoint("LEFT", x, 0)
			fs:SetText(text)
		end
		col("Element", 32)
		col("Group", GROUP_X + 4)
		col("Show", SHOW_X + 4)
		p:add(f, 20)
	end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		local f = p:row(34)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", 4, 0)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", 32, 0)
		name:SetText(e.label)
		local group = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		group:SetPoint("LEFT", GROUP_X, 0)
		group:SetWidth(100)
		group:SetupMenu(function(_, rootDescription)
			for gi = 1, groupCount() do
				rootDescription:CreateRadio("Group " .. gi, function() return ns.findElement(key) == gi end,
					function() ns.placeElement(key, gi) end)
			end
			rootDescription:CreateRadio("New group", function() return false end, function() ns.placeElement(key, "new") end)
		end)
		local show = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		show:SetPoint("LEFT", SHOW_X, 0)
		show:SetWidth(110)
		show:SetupMenu(function(_, rootDescription)
			for _, c in ipairs(SHOW_CHOICES) do
				rootDescription:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function() ns.setShow(key, c[1]) end)
			end
		end)
		show:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Show")
			GameTooltip:AddLine(SHOW_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		open:SetSize(90, 22)
		open:SetPoint("RIGHT", -4, 0)
		open:SetText("Settings")
		open:SetScript("OnClick", function() if ELEMENT_PAGES[key] then ns.OpenOptions(ELEMENT_PAGES[key]) end end)
		p:add(f, 34, function() return ns.available(key) end, function()
			e.paint(icon)
			group:GenerateMenu()
			show:GenerateMenu()
			open:SetShown(ELEMENT_PAGES[key] ~= nil)
		end)
	end
end

-- Every element page, in one order: its header, Display (Show, Group), its own settings, then the
-- standard blocks: Warning (Grey icon, Red ring, Pulse), Timer (Time bar, Time left), Countdown.
local function elementDisplay(p, key)
	ELEMENT_PAGES[key] = p.key
	p:hero(key)
	p:header("Display")
	p:dropdown("Show", SHOW_TIP, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
	p:dropdown("Group", "Which group it sits in. Groups are arranged on the Layout page.", function()
		local list = {}
		for gi = 1, groupCount() do table.insert(list, { gi, "Group " .. gi }) end
		table.insert(list, { "new", "New group" })
		return list
	end, function() return ns.findElement(key) end, function(v) ns.placeElement(key, v) end, nil, 140)
	local groupRow = p.items[#p.items].frame
	local edit = CreateFrame("Button", nil, groupRow, "UIPanelButtonTemplate")
	edit:SetSize(96, 22)
	edit:SetPoint("LEFT", groupRow.dropdown, "RIGHT", 8, 0)
	edit:SetText("Edit group")
	edit:SetScript("OnClick", function() local gi = ns.findElement(key); if gi then ns.OpenGroupSettings(gi) end end)
	setTip(edit, "Edit group", "This group's settings on the Layout page.")
end

-- Standard block: the look while something is missing. first: an optional row before the three.
local function warningBlock(p, title, greyGet, greySet, ringGet, ringSet, pulseGet, pulseSet, first)
	p:header(title)
	if first then first() end
	p:checkbox("Grey icon", "Desaturate the icon.", greyGet, greySet)
	p:checkbox("Red ring", "A red ring inside the icon edge.", ringGet, ringSet)
	p:checkbox("Pulse", "Fade the icon in and out.", pulseGet, pulseSet)
end

-- Standard block: a running timer.
local function timerBlock(p, title, optGet, optSet)
	p:header(title)
	p:checkbox("Time bar", "A bar along the bottom that drains.", optGet("activeBar", true), optSet("activeBar"))
	p:checkbox("Time left", "Small numbers in the top-left corner.", optGet("activeText", true), optSet("activeText"))
end

-- Standard block: countdown text, with an optional size of the element's own.
local function countdownBlock(p, key)
	local function own() return ns.elementOpts(key).cdTextSize ~= nil end
	p:header("Countdown")
	p:checkbox("Own text size", "Off: the size on the General page.", own, function(v)
		ns.elementOpts(key).cdTextSize = v and db().cdTextSize or nil
		relayout()
	end)
	p:slider("Text size", nil, 8, 48, 1, int, function() return ns.elementOpts(key).cdTextSize or db().cdTextSize end,
		function(v) ns.elementOpts(key).cdTextSize = v; relayout() end, dimWhen(own, "Turn on Own text size to use this."))
end

-- A look choice (tint, overlay, both) greys out the strength it does not use.
local function lookUses(key, part) return function() local v = db()[key]; return v == part or v == "both" end end

local function buildShield(p)
	elementDisplay(p, "shield")
	p:header("Tracking")
	-- Lightning Shield is the tested default; the Water Shield modes are experimental until tested in game.
	p:cards("Track", "Only one shield can be active at a time. With one chosen, the other counts as no shield.", {
		{ "lightning", "Lightning Shield", 136051 },
		{ "water", "Water Shield", 132315, "Water Shield" },
		{ "either", "Either", 136051, "Either shield" },
	}, get("shieldTrack"), set("shieldTrack", respell))
	p:header("Charges")
	p:checkbox("Charge bar", "One segment per charge.", get("showBar"), set("showBar"))
	p:checkbox("Charge number", "Shown for 2 or more charges.", get("showCount"), set("showCount"))
	local numberOn = dimWhen(get("showCount"), "Turn on Charge number to use this.")
	p:dropdown("Number position", nil, { { "corner", "Corner" }, { "center", "Centre" } }, get("countPos"), set("countPos"), numberOn)
	p:slider("Number size", nil, 8, 64, 1, int, get("countSize"), set("countSize"), numberOn)

	warningBlock(p, "No shield", get("emptyGrey"), set("emptyGrey"), get("emptyRing"), set("emptyRing"), get("emptyPulse"), set("emptyPulse"))
	p:checkbox("Red tint", "Tint the icon red.", get("emptyTint"), set("emptyTint"))
	p:slider("In-combat fallback", "A drop in combat is only known when you recast or combat ends. Until then the no-shield look shows this strongly.",
		0, 1, 0.05, pct, get("underlayUp"), set("underlayUp"))

	p:header("Shield up")
	p:slider("Duration swipe", "Darkness of the time-left swipe. Zero turns it off.", 0, 1, 0.05, pct, get("shieldSwipe"), set("shieldSwipe"))
	p:slider("Icon opacity", "Fine-tunes brightness at low group opacity. Most can leave it at 100%.", 0.5, 1, 0.05, pct, get("shieldIconAlpha"), set("shieldIconAlpha"))
end

local function buildShock(p)
	elementDisplay(p, "shock")
	p:header("Tracking")
	local icons = { earth = 136026, flame = 135813, frost = 135849 }
	local cards = {}
	for _, key in ipairs(ns.SHOCK_ORDER) do table.insert(cards, { key, ns.SHOCKS[key], icons[key] }) end
	p:cards("Track", "Its cooldown and range.", cards, get("shock"), set("shock", respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, key in ipairs(ns.SHOCK_ORDER) do table.insert(manaChoices, { key, ns.SHOCKS[key] }) end
	p:dropdown("Mana check", "Which spell's cost turns the icon blue.", manaChoices, get("manaSpell"), set("manaSpell", respell))

	local looks = { { "tint", "Tint" }, { "overlay", "Overlay" }, { "both", "Both" } }
	p:header("No mana")
	p:dropdown("Look", "Out of range wins over this look.", looks, get("manaStyle"), set("manaStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("manaIntensity"), set("manaIntensity"),
		dimWhen(lookUses("manaStyle", "overlay"), "Choose Overlay or Both as the look to use this."))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("manaTint"), set("manaTint"),
		dimWhen(lookUses("manaStyle", "tint"), "Choose Tint or Both as the look to use this."))
	p:slider("Ring", "The blue ring, shown even when out of range.", 0.1, 1, 0.05, pct, get("manaRing"), set("manaRing"))

	p:header("Out of range")
	p:dropdown("Look", nil, looks, get("rangeStyle"), set("rangeStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("rangeIntensity"), set("rangeIntensity"),
		dimWhen(lookUses("rangeStyle", "overlay"), "Choose Overlay or Both as the look to use this."))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("rangeTint"), set("rangeTint"),
		dimWhen(lookUses("rangeStyle", "tint"), "Choose Tint or Both as the look to use this."))
	countdownBlock(p, "shock")
end

local function buildImbue(p)
	elementDisplay(p, "imbue")
	warningBlock(p, "No imbue", get("imbueMissingGrey"), set("imbueMissingGrey"), get("imbueMissingRing"), set("imbueMissingRing"),
		get("imbuePulse"), set("imbuePulse"), function()
			local cards = { { "last", "Last used", 136086 } }
			for _, key in ipairs(ns.IMBUE_ORDER) do table.insert(cards, { key, (ns.IMBUES[key].name:gsub(" Weapon", "")), ns.IMBUES[key].icon }) end
			p:cards("Icon", "Which imbue's icon shows while none is on.", cards, get("imbuePreferred"), set("imbuePreferred"))
		end)

	p:header("Time left")
	p:slider("Show under", "Show the time left once under this. Zero never shows it.", 0, 30, 1,
		function(v) return v == 0 and "Never" or string.format("%d min", v) end, get("imbueWarnMins"), set("imbueWarnMins"))
	p:slider("Text size", nil, 8, 48, 1, int, get("imbueTextSize"), set("imbueTextSize"),
		dimWhen(function() return db().imbueWarnMins > 0 end, "Set Show under above zero to use this."))
	p:checkbox("Hide until low", "While an imbue is on, stay hidden until the time left shows. Keeps its place in the group.",
		get("imbueHideActive"), set("imbueHideActive"))
end

-- One page per cooldown element; the blocks depend on what the element tracks.
local function buildCooldown(p, def)
	local key = def.key
	elementDisplay(p, key)
	local function optGet(name, default) return function()
		local v = ns.elementOpts(key)[name]
		if v == nil then return default end
		return v
	end end
	local function optSet(name) return function(v) ns.elementOpts(key)[name] = v; relayout() end end
	if def.needsTotem then
		warningBlock(p, "No fire totem", optGet("blockedGrey", true), optSet("blockedGrey"), optGet("blockedRing", true), optSet("blockedRing"),
			optGet("blockedPulse", false), optSet("blockedPulse"))
		timerBlock(p, "Fire totem out", optGet, optSet)
	end
	if def.totemSlot then timerBlock(p, "Totem down", optGet, optSet) end
	countdownBlock(p, key)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local navButtons, navDivider = {}, nil

local function showPage(key)
	currentPage = key
	for _, p in ipairs(pageOrder) do
		p.scroll:SetShown(p.key == key)
		if p.fixed then p.fixed:SetShown(p.key == key) end
	end
	for _, b in ipairs(navButtons) do
		local on = b.page == key
		b.sel:SetShown(on)
		b.accent:SetShown(on)
		b.label:SetTextColor(on and 1 or (b.sub and 0.9 or 1), on and 0.84 or (b.sub and 0.88 or 0.82), on and 0.5 or (b.sub and 0.84 or 0))
	end
	if navDivider then navDivider.refresh() end
	pages[key]:refresh()
end

-- The nav: main pages, then every element's page (indented), then Profiles and About.
local function buildNav()
	local y = -66   -- below the portrait
	local function add(pageKey, text, icon, sub, extra)
		local b = CreateFrame("Button", nil, win)
		local indent = sub and 16 or 0
		b:SetSize(NAV_W - 20 - indent, sub and 24 or 28)
		b:SetPoint("TOPLEFT", 12 + indent, y)
		y = y - (sub and 26 or 30)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints()
		b.sel:SetColorTexture(0.88, 0.66, 0.29, 0.16)
		b.accent = b:CreateTexture(nil, "ARTWORK")
		b.accent:SetPoint("TOPLEFT", -8 - indent, -4)
		b.accent:SetPoint("BOTTOMLEFT", -8 - indent, 4)
		b.accent:SetWidth(3)
		b.accent:SetColorTexture(0.88, 0.66, 0.29, 1)
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.05)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(sub and 18 or 20, sub and 18 or 20)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(icon)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.label = b:CreateFontString(nil, "OVERLAY", sub and "GameFontHighlight" or "GameFontNormal")
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.label:SetText(text)
		if extra then
			local t = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			t:SetPoint("RIGHT", -6, 0)
			t:SetText(extra)
		end
		b.page, b.sub = pageKey, sub
		b:SetScript("OnClick", function() showPage(pageKey) end)
		table.insert(navButtons, b)
	end
	add("home", "Home", "Interface\\Icons\\ClassIcon_Shaman")
	add("general", "General", "Interface\\Icons\\INV_Misc_Gear_01")
	add("layout", "Layout", "Interface\\Icons\\Spell_Nature_Invisibilty")
	add("elements", "Elements", ART .. "Elements.tga")
	for _, p in ipairs(pageOrder) do
		local e = ns.Look.ELEMENT[p.key]
		if e then add(p.key, e.name, e.icon, true) end
	end
	y = y - 4
	navDivider = ns.Look.divider(win)
	navDivider:SetPoint("TOPLEFT", 20, y)
	navDivider:SetWidth(NAV_W - 36)
	y = y - 14
	add("profiles", "Profiles", "Interface\\Icons\\INV_Misc_Note_01")
	add("about", "About", "Interface\\Icons\\INV_Misc_Book_09")
	local foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	foot:SetPoint("BOTTOMLEFT", 16, 14)
	foot:SetText("/sf  ·  /sf lock")
end

local function buildWindow()
	-- Blizzard's portrait window: gold frame, round portrait, title and close button.
	win = CreateFrame("Frame", "ShamanForeverOptionsFrame", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
	if win.Inset then win.Inset:Hide() end
	if win.SetTitle then win:SetTitle("Shaman Forever") end
	if win.SetPortraitToAsset then pcall(win.SetPortraitToAsset, win, "Interface\\Icons\\ClassIcon_Shaman") end
	-- Our warm charcoal inside the frame.
	local bg = win:CreateTexture(nil, "BACKGROUND", nil, 2)
	bg:SetPoint("TOPLEFT", 2, -22)
	bg:SetPoint("BOTTOMRIGHT", -2, 2)
	bg:SetColorTexture(23 / 255, 19 / 255, 15 / 255, 0.97)
	local navBg = win:CreateTexture(nil, "BACKGROUND", nil, 3)
	navBg:SetPoint("TOPLEFT", bg, "TOPLEFT")
	navBg:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT")
	navBg:SetWidth(NAV_W)
	navBg:SetColorTexture(0, 0, 0, 0.25)
	local navEdge = win:CreateTexture(nil, "BACKGROUND", nil, 4)
	navEdge:SetPoint("TOPLEFT", navBg, "TOPRIGHT")
	navEdge:SetPoint("BOTTOMLEFT", navBg, "BOTTOMRIGHT")
	navEdge:SetWidth(1)
	navEdge:SetColorTexture(0.23, 0.17, 0.10, 1)

	acct().optionsSize = nil   -- from the old resizable window
	win:SetSize(WIDTH, math.min(math.max(acct().optionsHeight or HEIGHT, MIN_H), MAX_H))
	win:SetPoint("CENTER")
	-- Taller only: the grip changes height, never width, and pins the top edge.
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(win:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local function sizeToCursor()
		local _, y = GetCursorPosition()
		win:SetHeight(math.min(math.max(grip.startH + (grip.startY - y) / win:GetEffectiveScale(), MIN_H), MAX_H))
	end
	grip:SetScript("OnMouseDown", function(self)
		local left, top = win:GetLeft(), win:GetTop()
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		self.startY = select(2, GetCursorPosition())
		self.startH = win:GetHeight()
		self:SetScript("OnUpdate", sizeToCursor)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		acct().optionsHeight = math.floor(win:GetHeight())
	end)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	table.insert(UISpecialFrames, win:GetName())   -- Escape closes it

	buildHome(newPage("home", "Home"))
	buildGeneral(newPage("general", "General"))
	buildLayout(newPage("layout", "Layout"))
	buildElements(newPage("elements", "Elements"))
	buildShield(newPage("shield", "Shields", true))
	buildShock(newPage("shock", "Shocks", true))
	buildImbue(newPage("imbue", "Weapon Imbue", true))
	for _, def in ipairs(ns.COOLDOWNS) do buildCooldown(newPage(def.key, def.spell, true), def) end
	buildProfiles(newPage("profiles", "Profiles"))
	buildAbout(newPage("about", "About"))
	buildNav()
	win:Hide()
end

-- Confirmations for the Layout page's group actions; data is the group number.
local function confirm(which, text, button, action)
	StaticPopupDialogs[which] = {
		text = text, button1 = button, button2 = CANCEL,
		OnAccept = function(_, gi) action(gi) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end
confirm("SHAMANFOREVER_CENTER", "Move Group %s to the middle of the screen?\nIts current position is lost.", "Centre",
	function(gi) ns.centerGroup(gi) end)
confirm("SHAMANFOREVER_SPLIT", "Split Group %s into one group per element?\nPutting them back together is done by hand.", "Split up",
	function(gi) ns.splitGroup(gi) end)
confirm("SHAMANFOREVER_HIDEALL", "Hide every element in Group %s?\nEach one's Show setting becomes Never.", "Hide all",
	function(gi) ns.hideGroup(gi) end)

StaticPopupDialogs["SHAMANFOREVER_RESET"] = {
	text = "Reset profile %s to defaults?\nIts layout and every setting are lost.",
	button1 = YES, button2 = NO,
	OnAccept = function() ns.resetProfile(); ns.say("profile reset to defaults") end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["SHAMANFOREVER_DELETE_PROFILE"] = {
	text = "Delete profile %s?\nCharacters using it go back to Default.",
	button1 = "Delete", button2 = CANCEL,
	OnAccept = function() ns.deleteProfile() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- The edit box moved from dialog.editBox to dialog.EditBox / GetEditBox() over the Retail versions.
local function popupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end
local function submitName(text)
	local action = nameAction
	nameAction = nil
	if not action then return end
	local err = action.run(text)
	if err then ns.say(err) end
end
StaticPopupDialogs["SHAMANFOREVER_PROFILE_NAME"] = {
	text = "%s", button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = true, maxLetters = 32,
	OnShow = function(self)
		local e = popupEditBox(self)
		if e then e:SetText(nameAction and nameAction.initial or ""); e:HighlightText(); e:SetFocus() end
	end,
	OnAccept = function(self) local e = popupEditBox(self); submitName(e and e:GetText() or "") end,
	EditBoxOnEnterPressed = function(self)
		submitName(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Several changes in one frame (a slider drag, a drop) refresh the visible page once.
local refreshQueued = false
function ns.RefreshOptions()
	if not (win and win:IsShown()) or refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if win:IsShown() and currentPage then pages[currentPage]:refresh() end
		if navDivider then navDivider.refresh() end
	end)
end

function ns.OpenOptions(page, groupIndex)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
	if groupIndex then selectedGroup = groupIndex end
	win:Show()
	showPage(page or currentPage or "home")
end

-- An element's own page, or the Elements overview for one without a page (test elements).
function ns.OpenElementOptions(key)
	if not win then buildWindow() end
	ns.OpenOptions(ELEMENT_PAGES[key] or "elements")
end

-- From an EXPERIMENTAL badge: About, scrolled to its Experimental section, which glows briefly.
function ns.ShowExperimental()
	ns.OpenOptions("about")
	C_Timer.After(0, function()
		if not aboutExp then return end
		local p, h = aboutExp.page, aboutExp.header
		local top, y = p.content:GetTop(), h:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
		aboutExp.flash:Stop()
		aboutExp.flash:Play()
	end)
end

-- From an element's page: Layout with that group selected, scrolled to its settings, which flash.
function ns.OpenGroupSettings(gi)
	board.flashPanel = true
	ns.OpenOptions("layout", gi)
	C_Timer.After(0, function()
		if not (groupPanel and groupPanel.frame:IsShown()) then return end
		local p = groupPanel.page
		local top, y = p.content:GetTop(), groupPanel.frame:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
	end)
end

function ns.ToggleOptions()
	if win and win:IsShown() then win:Hide() else ns.OpenOptions() end
end

-- Escape > Options > AddOns > Shaman Forever: a pointer to the window above.
local category
function ns.BuildOptions()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Shaman Forever")
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText("Shaman Forever has its own options window. You can also open it by typing /sf.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	button:SetText("Open options")
	button:SetScript("OnClick", function() ns.OpenOptions() end)
	category = Settings.RegisterCanvasLayoutCategory(panel, "Shaman Forever")
	Settings.RegisterAddOnCategory(category)
end
