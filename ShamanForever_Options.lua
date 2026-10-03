-- Options window
local ADDON, ns = ...

local OP = {}
ns.Options = OP

local Page = ns.Page
local setTip, panelBackdrop = Page.setTip, Page.panelBackdrop

local WIDTH, NAV_W = Page.WIDTH, Page.NAV_W
local HEIGHT, MIN_H, MAX_H = 700, 560, 1300
local MAX_W = 1600
local LOGO_SIZE, LOGO_X, LOGO_Y = 112, -19, 24
local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"
OP.ART = ART

local win
local pages, pageOrder, stubs, currentPage = {}, {}, {}, nil

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end
-- Settings write at once; what follows (layout or restyle, repaint) runs once a frame.
local function perFrame(fn)
	local queued = false
	return function()
		if queued then return end
		queued = true
		C_Timer.After(0, function()
			queued = false
			fn()
		end)
	end
end
local relayout = perFrame(function() ns.applyLayout(); OP.refresh() end)
local retime = perFrame(function() ns.applyTimers(); OP.refresh() end)
-- ns.Effects.applyStyle restyles only the listed glows; one under the aura button goes through
-- -- its module's applyTimers.
local reglow = perFrame(function() ns.Effects.applyStyle(); ns.applyTimers(); OP.refresh() end)
local function respell() ns.resolveSpells(); ns.applyLayout(); ns.refreshAll(); OP.refresh() end

local K = {}
OP.kit = K
K.perFrame, K.relayout, K.retime, K.reglow, K.respell = perFrame, relayout, retime, reglow, respell

-- Pages register at load: title, icon, build, order (the order they build in, and their place in
-- the top nav), bottom (height above the window's foot: a lower nav page, placed by it, not order).
local registered, registeredKeys = {}, {}
function OP.registerPage(key, spec)
	assert(not registeredKeys[key], "page registered twice: " .. tostring(key))
	assert(spec.title and spec.build, "page needs a title and build: " .. tostring(key))
	local page = CopyTable(spec)
	page.key, page.order = key, spec.order or 100
	registeredKeys[key] = true
	table.insert(registered, page)
end

local function newPage(key, title, indent, build)
	local stub = { key = key, title = title, indent = indent, build = build }
	stubs[key] = stub
	table.insert(pageOrder, stub)
end

-- Kept before its builder runs: a builder that fails raises once, not on every try.
local function pageOf(key)
	local p = pages[key]
	if p or not stubs[key] then return p end
	local stub = stubs[key]
	p = Page.new(win, key, stub.title, stub.indent)
	pages[key] = p
	stub.build(p)
	return p
end

-- Settings helpers
local int = Page.int

local function confirm(which, text, button, action)
	StaticPopupDialogs[which] = {
		text = text, button1 = button, button2 = CANCEL,
		OnAccept = function(_, data) action(data) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end

local function get(key) return function() return db()[key] end end
local function set(key, after) return function(v) db()[key] = v; (after or relayout)() end end
local function gopt(p, key, after)
	p:owns({ general = key, after = after or relayout })
	return get(key), set(key, after)
end

-- Pages
local function lockText() return acct().locked and "Unlock positioning" or "Lock positioning" end
local function toggleLock() ns.setLocked(not acct().locked); OP.refresh() end
local function lockSub()
	return acct().locked and "Move the HUD on screen" or "Done moving? Lock them"
end

local aboutExp, aboutFeedback

local function addonVersion()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and getMeta(ADDON, "Version") or "?"
end

local function buildHome(p)
	p:pin(ns.Look.buildIntro(win, addonVersion()))
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText, lockSub, toggleLock },
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", function() return "Groups & Layout" end,
			function() return "Set up groups of elements" end, function() OP.open("layout") end },
	})
	p:add(p:row(24), 24)
	local lead = p:text("Ideas, requests, bugs? Please let me know!")
	lead.text:SetFontObject("GameFontHighlightMedium")
	lead.text:SetTextColor(1, 0.92, 0.75)
	p:add(p:row(4), 4)
	p:bigButtons({
		{ "Interface\\Icons\\INV_Letter_15", function() return "Give feedback" end,
			function() return "Discord, CurseForge or GitHub" end, function() OP.showFeedback() end },
	})
end

local function buildGlobal(p)
	p:pageTitle("Global settings")

	p:section("General", true)
	p:header("Minimap")
	p:checkbox("Show the minimap button", "Click it to open these options. Also listed in the minimap's addon menu.",
		function() return not (acct().minimap and acct().minimap.hide) end,
		function(v)
			if type(acct().minimap) ~= "table" then acct().minimap = {} end
			acct().minimap.hide = not v
			ns.applyMinimapButton()
		end)
	K.soundsBlock(p)
	local hasReporter = ns.IssueReporter.has
	p:header("Beta", hasReporter)
	p:checkbox("Hide the Issue Reporter button", "Blizzard's beta Issue Reporter button. " .. ns.NAME .. " also remembers where you drag it.",
		function() return acct().hideIssueReporter end, function(v) acct().hideIssueReporter = v; ns.IssueReporter.apply() end, hasReporter)

	p:section("Global styles")
	p:text("These apply to all components within the addon, which can be overridden within each component's settings.")
	p:header("Icon size")
	p:anchor("size")
	local sized = ns.Bars.nouns(function(bar) return bar.ownSize ~= nil end, "group")
	for i, noun in ipairs(sized) do sized[i] = noun .. "'s" end
	local tip = "Every " .. ns.Look.wordList(sized) .. ", unless it has its own."
	K.rangeSlider(p, ns.Profiles.RANGES.iconSize, "Icon size", tip, int, gopt(p, "iconSize"))
	local function ownSizes()
		local out = {}
		for _, g in ipairs(db().groups) do
			if #g.members > 0 and not g.sizeFollow then table.insert(out, g.name) end
		end
		for _, key in ipairs(ns.Bars.list()) do
			local bar = ns.Bars.get(key)
			if bar.ownSize and bar.on() and bar.ownSize() then table.insert(out, bar.label) end
		end
		return out
	end
	p:text(function() return "Currently using their own: " .. table.concat(ownSizes(), ", ") end,
		function() return #ownSizes() > 0 end)
	K.timerSettings(p, "Cooldowns", nil, "cooldown", nil, "A spell you can't cast yet.")
	K.gcdBlock(p, nil)
	K.timerSettings(p, "Time left", nil, "uptime", nil, ns.CLASS.help.uptime)
	K.textBlock(p, nil)
	K.barBlock(p)
	p:header("Border style")
	p:anchor("border")
	p:text("Every border. " .. K.ownersText("Elements", "border"))
	K.borderRows(p, nil)
	K.ownLine(p, "border")
	p:header("Frame style")
	p:anchor("frame")
	p:text("Art round each icon. " .. K.ownersText("Elements", "frame"))
	K.frameRows(p, nil, "frame")
	K.ownLine(p, "frame")
	p:header("Group frame style")
	p:anchor("groupframe")
	p:text("Art round a whole group. " .. K.ownersText("Groups", "groupframe"))
	K.frameRows(p, nil, "groupframe")
	K.ownLine(p, "groupframe")
	K.glowBlock(p, nil)
	K.popBlock(p, nil, "ready")
end

local nameAction
local function askName(prompt, initial, action)
	nameAction = { prompt = prompt, initial = initial or "", run = action }
	StaticPopup_Show(ns.POPUP .. "PROFILE_NAME", prompt)
end

local function buildProfiles(p)
	local function notDefault() return ns.profileName() ~= ns.DEFAULT_PROFILE end
	p:header("Profile")
	p:text("Each character uses one profile. New characters start on Default.")
	p:dropdown("This character", nil, function()
		local t = {}
		for _, name in ipairs(ns.Profiles.names()) do table.insert(t, { name, name }) end
		return t
	end, ns.profileName, ns.useProfile)
	p:buttons({
		{ "New", function() askName("Name for the new profile:", nil, function(n) return ns.Profiles.new(n) end) end,
			"A new profile with default settings.", 90 },
		{ "Copy", function() askName("Name for the copy:", ns.profileName() .. " copy", function(n) return ns.Profiles.new(n, ns.getDB()) end) end,
			"A new profile with this one's settings.", 90 },
		{ "Rename", function() askName("New name:", ns.profileName(), ns.Profiles.rename) end,
			"Default can't be renamed.", 90, notDefault },
		{ "Delete", function() StaticPopup_Show(ns.POPUP .. "DELETE_PROFILE", ns.profileName()) end,
			"Characters using it go back to Default. Default can't be deleted.", 90, notDefault },
		{ "Reset", function() StaticPopup_Show(ns.POPUP .. "RESET", ns.profileName()) end,
			"Every setting in this profile back to defaults, including the layout.", 90 },
	})

	p:header("Share", nil, nil, nil, { open = true })
	p:buttons({
		{ "Export", function() OP.showShare("export") end, "This profile as text, to share.", 90 },
		{ "Import", function() OP.showShare("import") end, "Profile text from someone else. It becomes a new profile.", 90 },
	})

end

local function flashingHeader(p, text, icon)
	return { page = p, header = p:header(text, nil, nil, icon) }
end

-- PNG paths need their extension (the client only adds .tga or .blp itself).
local LINKS = {
	discord = { ART .. "Link-Discord.png", { 0.35, 0.40, 0.95 } },
	curseforge = { ART .. "Link-CurseForge.png", { 0.95, 0.39, 0.21 } },
	github = { ART .. "Link-GitHub.png", { 0.92, 0.92, 0.92 } },
	kofi = { ART .. "Link-Kofi.png", { 1, 0.37, 0.36 } },
}
local function link(p, label, url, site) p:copyField(label, url, LINKS[site][1], LINKS[site][2]) end

local function aboutCard(p)
	local f = CreateFrame("Frame", nil, p.content, "BackdropTemplate")
	f:SetHeight(78)
	panelBackdrop(f, 0.55, 0.42, 0.22)
	f.logo = f:CreateTexture(nil, "ARTWORK")
	f.logo:SetSize(64, 64)
	f.logo:SetPoint("LEFT", 10, 0)
	f.logo:SetTexture(ART .. "Logo-Icon")
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.title:SetPoint("TOPLEFT", f.logo, "TOPRIGHT", 14, -8)
	f.title:SetText(ns.NAME)
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.sub:SetTextColor(0.80, 0.74, 0.66)
	return p:add(f, 84, nil, function() f.sub:SetText("Version " .. addonVersion() .. ". " .. ns.CLASS.blurb) end)
end

local function buildAbout(p)
	p:add(p:row(6), 6)
	aboutCard(p)
	aboutFeedback = flashingHeader(p, "Feedback", "Interface\\Icons\\INV_Letter_15")
	p:text("Ideas, requests or problems? Post in #feedback on Discord, comment on CurseForge, or open an issue on GitHub. Click a link, then Ctrl+C to copy.")
	local links = ns.CLASS.links
	link(p, "Discord", links.discord, "discord")
	link(p, "CurseForge", links.curseforge .. "/comments", "curseforge")
	link(p, "GitHub", links.repo .. "/issues", "github")
	p:header("Support", nil, nil, "Interface\\Icons\\INV_Misc_Coin_01", { open = true })
	p:text("If you'd like to support this addon, please feel free to buy me a coffee. I have spent many hours "
		.. "working on this project (and many millions of AI tokens). Thank you!")
	link(p, "Ko-fi", links.kofi, "kofi")
	aboutExp = flashingHeader(p, "Experimental", "Interface\\Icons\\INV_Gizmo_02")
	p:text("These features aren't fully tested and may not work properly. Please use the feedback options above"
		.. " to help me out and improve the addon.")
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local e = ns.ELEMENTS[key]
		if e.experimental then p:experimental(e.experimental, "Elements > " .. e.label) end
	end
	p:experimental("Art frames", "Frame and Group frame styles")
	for _, key in ipairs(ns.Bars.list()) do
		local bar = ns.Bars.get(key)
		for _, x in ipairs(bar.experiments or {}) do
			p:experimental(x[1], bar.label .. " > " .. x[2])
		end
	end
	for _, l in ipairs(ns.Style.fields()) do
		for _, e in ipairs(l.order) do
			if e.experimental and not e.hidden then p:experimental(e.name, l.where .. " > " .. l.name) end
		end
	end
	p:header("Art", nil, nil, "Interface\\Icons\\INV_Scroll_03")
	p:text(ns.CLASS.credits .. " Corner and divider ornaments: public domain / CC0, Wikimedia Commons. "
		.. "Link icons: Simple Icons, CC0. The Carved stone, Aged bronze and Carved wood borders: made with an AI image "
		.. "model (Google Gemini).")
	local ai = {}
	for _, kind in ipairs({ "frame", "groupframe" }) do
		for _, e in ipairs(ns.Style.choices(kind, "look")) do
			if e.credit == "ai" and not e.hidden then table.insert(ai, e.name) end
		end
	end
	if #ai > 0 then p:text("Frames made with the same model: " .. table.concat(ai, ", ") .. ".") end
end

-- Key stays "general": it is saved as the last page and in folded blocks' keys.
OP.registerPage("home", { title = "Home", icon = ns.CLASS.icon, order = 10, build = buildHome })
OP.registerPage("general", { title = "Global settings", icon = "Interface\\Icons\\INV_Misc_Gear_01", order = 20,
	build = buildGlobal })
OP.registerPage("profiles", { title = "Profiles", icon = "Interface\\Icons\\INV_Misc_Note_01", order = 80,
	bottom = 100, build = buildProfiles })
OP.registerPage("about", { title = "About", icon = "Interface\\Icons\\INV_Misc_Book_09", order = 90, bottom = 70,
	build = buildAbout })

-- Show choices
local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" }, { "never", "Hidden" } }
local COMBAT_SHOW = { { "always", "Always" }, { "combat", "In combat" }, { "target", "In combat or with an enemy target" } }
local STAY_TIP = "Seconds it stays once combat ends, then it fades out."
local function staySecs(v) return v == 0 and "None" or string.format("%d s", v) end

K.confirm = confirm
K.SHOW_CHOICES, K.COMBAT_SHOW, K.STAY_TIP, K.staySecs = SHOW_CHOICES, COMBAT_SHOW, STAY_TIP, staySecs

-- Window
local navButtons, navDivider, navLock, navList = {}, nil, nil, nil
local navPreview

local function refreshNav()
	if navList then navList.order() end
	for _, b in ipairs(navButtons) do
		local on = b.page == currentPage
		b.sel:SetShown(on)
		b.accent:SetShown(on)
		if on or not b.sub or ns.isLearned(b.page) then
			b.label:SetTextColor(on and 1 or (b.sub and 0.9 or 1), on and 0.84 or (b.sub and 0.88 or 0.82), on and 0.5 or (b.sub and 0.84 or 0))
		else b.label:SetTextColor(0.55, 0.53, 0.5) end
		b.icon:SetDesaturated(b.sub and not ns.isLearned(b.page) or false)
	end
	if navDivider then navDivider.refresh() end
	if navLock then navLock.refresh() end
	if navPreview then navPreview.refresh() end
end

local function showPage(key)
	if not stubs[key] then key = "home" end
	local page = pageOf(key)
	currentPage = key
	acct().optionsPage = key
	for _, p in pairs(pages) do
		p.scroll:SetShown(p == page)
		if p.fixed then p.fixed:SetShown(p == page) end
	end
	refreshNav()
	for _, b in ipairs(navButtons) do
		if b.page == key and b.sub and navList then navList.reveal(b) end
	end
	page:refresh()
end

local NAV_SUB_H, NAV_SUB_STEP = 24, 26
local function buildNav()
	local function add(pageKey, text, icon, sub, parent)
		local b = CreateFrame("Button", nil, parent or win)
		local indent = sub and 16 or 0
		b:SetSize(NAV_W - 20 - indent, sub and NAV_SUB_H or 28)
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
		ns.cropIcon(b.icon)
		b.label = b:CreateFontString(nil, "OVERLAY", sub and "GameFontHighlight" or "GameFontNormal")
		b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.label:SetPoint("RIGHT", -4, 0)
		b.label:SetJustifyH("LEFT")
		b.label:SetWordWrap(false)
		b.label:SetText(text)
		b.page, b.sub = pageKey, sub
		b:SetScript("OnClick", function() showPage(pageKey) end)
		table.insert(navButtons, b)
		return b
	end
	local y = LOGO_Y - LOGO_SIZE - 1
	local function top(...)
		local b = add(...)
		b:SetPoint("TOPLEFT", win, "TOPLEFT", 12, y)
		y = y - 30
	end
	for _, spec in ipairs(registered) do
		if not spec.bottom then top(spec.key, spec.title, spec.icon) end
	end
	navPreview = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	navPreview:SetSize(NAV_W - 32, 22)
	navPreview:SetPoint("BOTTOMLEFT", 16, 38)
	navPreview:SetScript("OnClick", function() ns.Preview.toggle() end)
	setTip(navPreview, "Preview", "The whole HUD in a typical moment, to arrange it out of combat. " .. ns.CLASS.slash[1]
		.. " preview does the same.")
	function navPreview.refresh() navPreview:SetText(ns.Preview.isOn() and "Stop preview" or "Preview") end
	navPreview.refresh()
	navLock = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	navLock:SetSize(NAV_W - 32, 22)
	navLock:SetPoint("BOTTOMLEFT", 16, 12)
	navLock:SetScript("OnClick", function() ns.setLocked(not acct().locked) end)
	setTip(navLock, "Positioning", "Unlocked, drag " .. ns.Look.movingWords("groups")
		.. " on screen. " .. ns.CLASS.slash[1] .. " lock does the same.")
	function navLock.refresh() navLock:SetText(acct().locked and "Unlock positioning" or "Lock positioning") end
	navLock.refresh()
	for _, spec in ipairs(registered) do
		if spec.bottom then
			add(spec.key, spec.title, spec.icon):SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, spec.bottom)
		end
	end
	navDivider = ns.Look.divider(win)
	navDivider:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 20, 136)
	navDivider:SetWidth(NAV_W - 36)
	local list = CreateFrame("ScrollFrame", nil, win)
	list:SetPoint("TOPLEFT", win, "TOPLEFT", 4, y)
	list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 4, 148)
	list:SetWidth(NAV_W - 8)
	local child = CreateFrame("Frame", nil, list)
	child:SetWidth(NAV_W - 8)
	list:SetScrollChild(child)
	local byKey, n = {}, 0
	for _, p in ipairs(pageOrder) do
		local e = ns.ELEMENTS[p.key]
		if e and e.kind then
			local b = add(p.key, ns.Look.elementName(p.key), e.icon, true, child)
			b:SetWidth(NAV_W - 42)
			byKey[p.key] = b
			n = n + 1
		end
	end
	local placed
	function list.order()
		local seq = {}
		for _, key in ipairs(ns.ElementPages.ordered()) do
			if byKey[key] then table.insert(seq, key) end
		end
		local sig = table.concat(seq, ",")
		if sig == placed then return end
		placed = sig
		for i, key in ipairs(seq) do
			local b = byKey[key]
			b.listTop = (i - 1) * NAV_SUB_STEP
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", child, "TOPLEFT", 8 + 16, -b.listTop)
		end
	end
	list.order()
	local over = CreateFrame("Frame", nil, list)
	over:SetAllPoints()
	over:SetFrameLevel(child:GetFrameLevel() + 5)
	local function shade(point, from, to)
		local t = over:CreateTexture(nil, "OVERLAY")
		t:SetPoint(point .. "LEFT"); t:SetPoint(point .. "RIGHT", -8, 0)
		t:SetHeight(18)
		t:SetColorTexture(1, 1, 1, 1)
		t:SetGradient("VERTICAL", CreateColor(0.09, 0.075, 0.06, from), CreateColor(0.09, 0.075, 0.06, to))
		return t
	end
	list.moreAbove, list.moreBelow = shade("TOP", 0, 0.95), shade("BOTTOM", 0.95, 0)
	local track = CreateFrame("Button", nil, over)
	track:SetPoint("TOPRIGHT", -1, 0)
	track:SetPoint("BOTTOMRIGHT", -1, 0)
	track:SetWidth(5)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints()
	track.bg:SetColorTexture(1, 1, 1, 0.06)
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(5)
	thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
	thumb.tex:SetAllPoints()
	thumb.tex:SetColorTexture(0.88, 0.66, 0.29, 0.55)
	thumb:SetScript("OnEnter", function(t) t.tex:SetAlpha(1) end)
	thumb:SetScript("OnLeave", function(t) if not t.drag then t.tex:SetAlpha(0.55) end end)

	function list.maxScroll()
		return math.max(math.ceil((n * NAV_SUB_STEP - list:GetHeight()) / NAV_SUB_STEP), 0) * NAV_SUB_STEP
	end
	local function place()
		local h, max = list:GetHeight(), list.maxScroll()
		child:SetHeight(math.max(h + max, 1))
		local scrolls = max > 0
		track:SetShown(scrolls)
		if not scrolls then return end
		local th = math.max(h * h / (h + max), 16)
		thumb:SetHeight(th)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -(h - th) * list:GetVerticalScroll() / max)
	end
	function list.scrollTo(v)
		v = math.floor(v / NAV_SUB_STEP + 0.5) * NAV_SUB_STEP
		v = math.min(math.max(v, 0), list.maxScroll())
		list:SetVerticalScroll(v)
		list.moreAbove:SetShown(v > 0.5)
		list.moreBelow:SetShown(v < list.maxScroll() - 0.5)
		place()
	end
	function list.reveal(b)
		local v, h = list:GetVerticalScroll(), list:GetHeight()
		if b.listTop < v then list.scrollTo(b.listTop)
		elseif b.listTop + NAV_SUB_H > v + h then
			list.scrollTo(math.ceil((b.listTop + NAV_SUB_H - h) / NAV_SUB_STEP) * NAV_SUB_STEP)
		end
	end
	local function scrollToCursor(grab)
		local _, cy = GetCursorPosition()
		cy = cy / track:GetEffectiveScale()
		local h, th = track:GetHeight(), thumb:GetHeight()
		local frac = (track:GetTop() - cy - grab) / math.max(h - th, 1)
		list.scrollTo(frac * list.maxScroll())
	end
	thumb:SetScript("OnMouseDown", function(t)
		local _, cy = GetCursorPosition()
		t.drag = t:GetTop() - cy / t:GetEffectiveScale()
		t:SetScript("OnUpdate", function() scrollToCursor(t.drag) end)
	end)
	thumb:SetScript("OnMouseUp", function(t)
		t.drag = nil
		t:SetScript("OnUpdate", nil)
		if not t:IsMouseOver() then t.tex:SetAlpha(0.55) end
	end)
	track:SetScript("OnClick", function() scrollToCursor(thumb:GetHeight() / 2) end)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta) list.scrollTo(list:GetVerticalScroll() - delta * NAV_SUB_STEP) end)
	list:SetScript("OnSizeChanged", function() list.scrollTo(list:GetVerticalScroll()) end)
	navList = list
end

local function addStyleUsers()
	local St = ns.Style
	for _, owner in ipairs(ns.Bars.list()) do
		for _, kind in ipairs(ns.Bars.get(owner).kinds) do St.addUser(kind, owner) end
	end
	for _, key in ipairs(ns.ElementPages.ordered()) do
		if ns.ElementPages.pageOf(key) then
			for _, kind in ipairs(St.ORDER) do
				if St.KINDS[kind].elements then St.addUser(kind, key) end
			end
		end
	end
end

local function buildWindow()
	win = CreateFrame("Frame", ns.NAME .. "OptionsFrame", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
	if win.Inset then win.Inset:Hide() end
	if win.SetTitle then win:SetTitle(ns.NAME) end
	local title = win.TitleContainer and win.TitleContainer.TitleText or win.TitleText
	if title then
		local font, size, flags = title:GetFont()
		if font and size then title:SetFont(font, size + 2, flags) end
	end
	-- The crest is a badge over the corner: the portrait ring can't grow.
	if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
	local logo = CreateFrame("Frame", nil, win)
	logo:SetSize(LOGO_SIZE, LOGO_SIZE)
	logo:SetPoint("TOPLEFT", win, "TOPLEFT", LOGO_X, LOGO_Y)
	logo:SetFrameLevel(600)
	local LOGO = ART .. "Logo-Icon"
	logo.shadow = logo:CreateTexture(nil, "BACKGROUND")
	logo.shadow:SetTexture(LOGO)
	logo.shadow:SetVertexColor(0, 0, 0, 0.7)
	logo.shadow:SetPoint("TOPLEFT", 3, -4)
	logo.shadow:SetPoint("BOTTOMRIGHT", 3, -4)
	logo.tex = logo:CreateTexture(nil, "ARTWORK")
	logo.tex:SetTexture(LOGO)
	logo.tex:SetAllPoints()
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

	local function fit(v, least, most, screen) return math.max(math.min(v, most, screen), least) end
	local function fitW(w) return fit(w, WIDTH, MAX_W, UIParent:GetWidth()) end
	local function fitH(h) return fit(h, MIN_H, MAX_H, UIParent:GetHeight()) end
	win:SetSize(fitW(acct().optionsWidth or WIDTH), fitH(acct().optionsHeight or HEIGHT))
	-- In UIParent's units: the window's scale is its parent's.
	local a = acct()
	win:ClearAllPoints()
	if a.optionsLeft and a.optionsTop then
		local w, h = win:GetSize()
		local left = math.max(math.min(a.optionsLeft, UIParent:GetWidth() - w), 0)
		local top = math.min(math.max(a.optionsTop, h), UIParent:GetHeight())
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	else
		win:SetPoint("CENTER")
	end
	local function savePlace()
		local left, top = win:GetLeft(), win:GetTop()
		if left and top then acct().optionsLeft, acct().optionsTop = math.floor(left + 0.5), math.floor(top + 0.5) end
	end
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel(win:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local function sizeToCursor()
		local x, y = GetCursorPosition()
		local s = win:GetEffectiveScale()
		win:SetSize(fitW(grip.startW + (x - grip.startX) / s), fitH(grip.startH + (grip.startY - y) / s))
	end
	grip:SetScript("OnMouseDown", function(self)
		local left, top = win:GetLeft(), win:GetTop()
		win:ClearAllPoints()
		win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		self.startX, self.startY = GetCursorPosition()
		self.startW, self.startH = win:GetSize()
		Page.startResize(pages[currentPage])
		self:SetScript("OnUpdate", sizeToCursor)
	end)
	local function endResize()
		grip:SetScript("OnUpdate", nil)
		Page.endResize()
		acct().optionsWidth = math.floor(win:GetWidth())
		acct().optionsHeight = math.floor(win:GetHeight())
		savePlace()
	end
	grip:SetScript("OnMouseUp", endResize)
	-- Closed mid-drag, the release may never come: end a resize here.
	win:HookScript("OnHide", function()
		if grip:GetScript("OnUpdate") then endResize() end
	end)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		savePlace()
	end)
	table.insert(UISpecialFrames, win:GetName())
	local function shownNow(shown)
		ns.Positioning.optionsShown(shown)
		ns.Preview.optionsShown(shown)
	end
	win:HookScript("OnShow", function() shownNow(true) end)
	win:HookScript("OnHide", function() shownNow(false) end)

	table.sort(registered, function(x, y) return x.order < y.order end)
	for _, spec in ipairs(registered) do newPage(spec.key, spec.title, nil, spec.build) end
	ns.ElementPages.register(newPage)
	addStyleUsers()
	buildNav()
	win:Hide()
end

confirm(ns.POPUP .. "RESET", "Reset profile %s to defaults?\nIts layout and every setting are lost.", "Reset",
	function() ns.Profiles.reset(); ns.say("profile reset to defaults") end)
confirm(ns.POPUP .. "RESET_SETTINGS", "Reset %s to defaults?", "Reset", function(run) run() end)
confirm(ns.POPUP .. "DELETE_PROFILE", "Delete profile %s?\nCharacters using it go back to Default.", "Delete",
	function() ns.Profiles.delete() end)

-- editBox is dialog.EditBox on newer clients.
local function popupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end
local function submitName(text)
	local action = nameAction
	nameAction = nil
	if not action then return end
	local err = action.run(text)
	if err then
		local prompt = action.retryOf or action.prompt
		C_Timer.After(0, function()
			nameAction = { prompt = prompt, retryOf = prompt, initial = text, run = action.run }
			StaticPopup_Show(ns.POPUP .. "PROFILE_NAME", "|cffff6060" .. err:gsub("^%l", string.upper) .. ".|r\n" .. prompt)
		end)
	end
end
StaticPopupDialogs[ns.POPUP .. "PROFILE_NAME"] = {
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

local share
local function buildShare()
	local f = CreateFrame("Frame", ns.NAME .. "ShareFrame", UIParent, "BackdropTemplate")
	f:SetSize(460, 250)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	panelBackdrop(f, 0.55, 0.42, 0.22)
	table.insert(UISpecialFrames, f:GetName())

	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("TOPLEFT", 14, -12)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local boxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panelBackdrop(boxBg)
	boxBg:SetBackdropColor(0, 0, 0, 0.35)
	boxBg:SetPoint("TOPLEFT", 12, -40)
	boxBg:SetPoint("BOTTOMRIGHT", -12, 64)
	local scroll = CreateFrame("ScrollFrame", nil, boxBg, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 8, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local e = CreateFrame("EditBox", nil, scroll)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontSmall")
	e:SetMaxLetters(0)
	e:SetWidth(460 - 24 - 36)
	e:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(e)
	boxBg:EnableMouse(true)
	boxBg:SetScript("OnMouseDown", function() e:SetFocus() end)
	f.edit = e

	f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.note:SetPoint("TOPLEFT", boxBg, "BOTTOMLEFT", 2, -8)
	f.note:SetPoint("RIGHT", -12, 0)
	f.note:SetJustifyH("LEFT")

	f.primary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.primary:SetSize(100, 22)
	f.primary:SetPoint("BOTTOMRIGHT", -12, 12)
	f.secondary = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.secondary:SetSize(100, 22)
	f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -6, 0)
	f.secondary:SetText(CANCEL)
	f.secondary:SetScript("OnClick", function() f:Hide() end)

	e:SetScript("OnTextChanged", function(self, user)
		if f.mode == "export" then
			if user then self:SetText(f.exported); self:HighlightText() end
			return
		end
		f.primary:SetEnabled(strtrim(self:GetText()) ~= "")
		if user then f.note:SetText("Paste profile text above."); f.note:SetTextColor(0.78, 0.74, 0.68) end
	end)
	f.primary:SetScript("OnClick", function()
		if f.mode == "export" then f:Hide(); return end
		local settings, err = ns.Profiles.decode(e:GetText())
		if not settings then
			f.note:SetText(err:gsub("^%l", string.upper) .. ".")
			f.note:SetTextColor(1, 0.38, 0.38)
			return
		end
		f:Hide()
		askName("Name for the imported profile:", "Imported", function(n) return ns.Profiles.new(n, settings) end)
	end)
	f:Hide()
	return f
end

function OP.showShare(mode)
	share = share or buildShare()
	share.mode = mode
	local e = share.edit
	share.note:SetTextColor(0.78, 0.74, 0.68)
	if mode == "export" then
		local text, err = ns.Profiles.export()
		if not text then ns.say(err); return end
		share.exported = text
		share.title:SetText("Export " .. ns.profileName())
		share.note:SetText("Ctrl+C to copy.")
		share.primary:SetText(CLOSE)
		share.primary:SetEnabled(true)
		share.secondary:Hide()
		share:Show()
		e:SetText(text)
		e:SetCursorPosition(0)
		e:SetFocus()
		e:HighlightText()
	else
		share.title:SetText("Import a profile")
		share.note:SetText("Paste profile text above.")
		share.primary:SetText("Import")
		share.primary:SetEnabled(false)
		share.secondary:Show()
		share:Show()
		e:SetText("")
		e:SetFocus()
	end
end

local refreshQueued = false
function OP.refresh()
	if not (win and win:IsShown()) or refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if win:IsShown() and currentPage then pages[currentPage]:refresh() end
		refreshNav()
	end)
end

function OP.open(page, groupId)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	-- In combat HideUIPanel is blocked; Settings stays open under the window.
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
	if groupId then ns.LayoutPage.choose(groupId) end
	win:Show()
	local last = acct().optionsPage
	showPage(page or currentPage or (last and stubs[last] and last) or "home")
end

function OP.openElement(key)
	if not win then buildWindow() end
	OP.open(ns.ElementPages.pageOf(key) or "elements")
end

local function scrollTo(p, frame, after)
	p:reveal(frame)
	C_Timer.After(0, function()
		if not frame:IsVisible() then return end
		local top, y = p.content:GetTop(), frame:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
		if after then after() end
	end)
end

function OP.openGlobal(anchor)
	OP.open("general")
	local p = pages.general
	local f = p and p.anchors and p.anchors[anchor]
	if f then scrollTo(p, f, function() p:flash(f) end) end
end

local function showAboutSection(which)
	OP.open("about")
	local section = which()
	if not section then return end
	scrollTo(section.page, section.header, function() section.page:flash(section.header) end)
end
function OP.showExperimental() showAboutSection(function() return aboutExp end) end
function OP.showFeedback() showAboutSection(function() return aboutFeedback end) end

function OP.openGroup(id)
	OP.open("layout", id)
	local p = pages.layout
	local f = ns.LayoutPage.headerOf(id)
	if f then scrollTo(p, f, function() p:flash(f) end) end
end

function OP.isShown() return win ~= nil and win:IsShown() end

function OP.hide()
	if not (win and win:IsShown()) then return false end
	win:Hide()
	return true
end

function OP.toggle()
	if win and win:IsShown() then win:Hide() else OP.open() end
end

local category
function OP.build()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(ns.NAME)
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText(ns.NAME .. " has its own options window. You can also open it by typing " .. ns.CLASS.slash[1] .. ".")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	button:SetText("Open options")
	button:SetScript("OnClick", function() OP.open() end)
	category = Settings.RegisterCanvasLayoutCategory(panel, ns.NAME)
	Settings.RegisterAddOnCategory(category)
end
