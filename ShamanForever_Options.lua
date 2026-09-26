-- Options window, opened with /sf. The entry under Escape > Options > AddOns only points here: the
-- Settings list is built once, so it cannot follow groups being added and removed.
local ADDON, ns = ...

local OP = {}
ns.Options = OP

local Page = ns.Page   -- ShamanForever_OptionsPage.lua: the page kit
local showWhen, setTip, panelBackdrop = Page.showWhen, Page.setTip, Page.panelBackdrop

local WIDTH, NAV_W, LABEL_W = Page.WIDTH, Page.NAV_W, Page.LABEL_W
local HEIGHT, MIN_H, MAX_H = 700, 560, 1300   -- the player may make it taller
local LOGO_SIZE, LOGO_X, LOGO_Y = 112, -19, 24   -- the logo badge over the window's top-left corner
local ART = "Interface\\AddOns\\" .. ADDON .. "\\Art\\"

local win
local pages, pageOrder, currentPage = {}, {}, nil
local selectedGroup = 1

local function db() return ns.getDB() end
local function acct() return ns.getAccount() end
-- Settings are written at once; the HUD's layout and the page's repaint follow once per frame, so a
-- slider drag or a colour-picker move lays out once a frame, not once per step. The repaint also
-- covers combat, where the layout itself waits for combat to end.
local relayoutQueued = false
local function relayout()
	if relayoutQueued then return end
	relayoutQueued = true
	C_Timer.After(0, function()
		relayoutQueued = false
		ns.applyLayout()
		OP.refresh()
	end)
end
-- Timer rows: only the timers take the new look, not the whole layout.
local function retime()
	ns.applyTimers()
	OP.refresh()
end
local function respell() ns.resolveSpells(); ns.refreshAll(); OP.refresh() end

local function newPage(key, title, indent)
	local p = Page.new(win, key, title, indent)
	pages[key] = p
	table.insert(pageOrder, p)
	return p
end


------------------------------------------------------------------------
-- Settings helpers
------------------------------------------------------------------------
local function pct(v) return string.format("%.0f%%", v * 100) end
local function times(v) return string.format("%.2fx", v) end
local function int(v) return string.format("%d", v) end
local function px(v) return string.format("%d px", v) end

------------------------------------------------------------------------
-- Styles (ShamanForever_Style.lua): General sets each one; an element, a group or the totem bar can
-- have its own. owner: nil for General, an element key, "totembar", or a function returning the
-- selected group (nil while there is none).
------------------------------------------------------------------------
local function resolve(owner) if type(owner) == "function" then return owner() end return owner end

-- A switch to use General's settings, with a button to them (General's page, scrolled to anchor).
local function generalRow(p, label, tip, get, set, anchor, shown)
	local row = p:checkbox(label, tip, get, set, shown)
	local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	b:SetSize(100, 22)
	b:SetPoint("LEFT", row.check.Text, "RIGHT", 12, 0)
	b:SetText("Edit General")
	b:SetScript("OnClick", function() OP.openGeneral(anchor) end)
	setTip(b, "Edit General", "These settings on the General page.")
	return row
end

-- "Same as General" for a style: on, the rows under it hide; off the first time, the owner keeps
-- the look it has as its own, and later its own values come back.
local function followRow(p, owner, kind, after, label, shown)
	if type(owner) == "string" then ns.Style.addUser(kind, owner) end
	return generalRow(p, label or "Same as General", "Use the settings on the General page.",
		function() local o = resolve(owner); return o ~= nil and ns.Style.follows(o, kind) end,
		function(v)
			local o = resolve(owner)
			if o == nil then return end
			ns.Style.setFollow(o, kind, v)
			after()
		end, kind, shown)
end

-- A style's rows: style() now, get(field) and set(field) for controls, and own(), whether the rows
-- apply (General's, or an owner with its own).
local function styleRows(owner, kind, after)
	local St = ns.Style
	local r = {}
	function r.style()
		local o = resolve(owner)
		if o == nil then return St.general(kind) end
		return St.get(o, kind)
	end
	function r.own() local o = resolve(owner); return o == nil or not St.follows(o, kind) end
	function r.get(field) return function() return r.style()[field] end end
	function r.set(field) return function(v)
		local o = resolve(owner)
		if o == nil and owner ~= nil then return end   -- no group selected
		St.set(o, kind, field, v)
		after()
	end end
	return r
end

-- General's lookup of what currently has its own, under a style's rows.
local function ownLine(p, kind)
	p:text(function() return "Currently using their own: " .. table.concat(ns.Style.ownStyles(kind), ", ") end,
		function() return #ns.Style.ownStyles(kind) > 0 end)
end


-- Standard rows: the border around icons, General's or an owner's (a group, the totem bar).
local function borderRows(p, owner, after, label, shown)
	after = after or relayout
	local r = styleRows(owner, "border", after)
	if owner ~= nil then followRow(p, owner, "border", after, label, shown) end
	local bordered = function() return r.own() and r.style().show end
	p:checkbox("Border", "A border around each icon.", r.get("show"), r.set("show"), showWhen(r.own, shown))
	p:slider("Border size", "Thickness in screen pixels.", 1, 8, 1, px, r.get("size"), r.set("size"), showWhen(bordered, shown))
	p:color("Border colour", "Colour and opacity.", r.get("color"), r.set("color"), showWhen(bordered, shown))
end

-- The border a preview icon wears: its owner's.
local function previewBorder(owner)
	if owner == nil then return ns.Style.general("border") end
	if owner == "totembar" then local _, b = ns.TotemBar.look(); return b end
	return ns.borderFor(owner)
end

-- Standard block: the pulsing glow's style, with an icon glowing all the time that follows every
-- change at once.
local function glowBlock(p, owner, icon)
	local function after() ns.applyGlowStyle(); OP.refresh() end
	local r = styleRows(owner, "glow", after)
	p:header("Glow style")
	if owner == nil then
		p:anchor("glow")
		p:text("Every pulsing glow. Elements and the totem bar can have their own.")
	else followRow(p, owner, "glow", after) end
	local own = showWhen(r.own)
	local f = p:row(64)
	p:label(f, "Preview")
	local ic = ns.makeIcon(f, 40, owner)
	ic:SetPoint("LEFT", f, "LEFT", LABEL_W + 24, 0)
	ic.tex:SetTexture(icon)
	p:add(f, 64, own, function() ns.applyBorder(ic, previewBorder(owner)); ic:SetGlowShown(true) end)
	p:color("Colour", "Colour and opacity. Killed early keeps its red.", r.get("color"), r.set("color"), own)
	p:slider("Pulse length", "One pulse, in seconds.", 0.2, 2, 0.1, function(v) return string.format("%.1f s", v) end,
		r.get("speed"), r.set("speed"), own)
	local setLow = r.set("low")
	p:slider("Pulse depth", "How much it fades between pulses. 0% is steady.", 0, 1, 0.05, pct,
		function() return 1 - r.style().low end, function(v) setLow(1 - v) end, own)
	p:slider("Thickness", "How far in from the edges it reaches.", 0.1, 0.5, 0.05, pct, r.get("width"), r.set("width"), own)
	if owner == nil then ownLine(p, "glow") end
end

-- Standard block: the pop's style, with an icon that pops on every change and on Play. kind: the
-- light's colour the icon shows (ready, imbue, expired, killed).
local POP_MOTIONS = { { "pop", "Grow" }, { "bounce", "Bounce" }, { "hop", "Hop" }, { "shake", "Shake side to side" }, { "shakeV", "Shake up and down" } }
local function popBlock(p, owner, icon, kind)
	local ic
	local function after() OP.refresh(); if ic and ic:IsVisible() then ic:Pop(kind) end end
	local r = styleRows(owner, "pop", after)
	p:header("Pop style")
	if owner == nil then
		p:anchor("pop")
		p:text("The burst when something happens: a cooldown ready, an imbue dropping, a totem ending. Elements and the totem bar can have their own.")
	else followRow(p, owner, "pop", after) end
	local own = showWhen(r.own)
	local f = p:row(56)
	p:label(f, "Try it")
	ic = ns.makeIcon(f, 40, owner)
	ic:SetPoint("LEFT", f, "LEFT", LABEL_W + 16, 0)
	ic.tex:SetTexture(icon)
	local play = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	play:SetSize(80, 22)
	play:SetPoint("LEFT", ic, "RIGHT", 24, 0)
	play:SetText("Play")
	play:SetScript("OnClick", function() ic:Pop(kind) end)
	p:add(f, 56, own, function() ns.applyBorder(ic, previewBorder(owner)) end)
	p:dropdown("Motion", nil, POP_MOTIONS, r.get("motion"), r.set("motion"), own, 190)
	p:slider("Motion distance", "How far it grows, hops or shakes.", 1.1, 1.8, 0.05, pct, r.get("size"), r.set("size"), own)
	p:slider("Motion speed", nil, 0.5, 2, 0.1, pct, r.get("speed"), r.set("speed"), own)
	p:checkbox("Flash", "A quick flash of light over the icon.", r.get("flash"), r.set("flash"), own)
	p:checkbox("Ring burst", "A ring that spreads out from the icon.", r.get("ring"), r.set("ring"), own)
	p:checkbox("Star burst", "A star of light behind the icon.", r.get("star"), r.set("star"), own)
	p:checkbox("Colour by event", "Gold when ready, blue for the imbue, white when a totem runs out, red when killed. Off: white.",
		r.get("tint"), r.set("tint"), own)
	if owner == nil then ownLine(p, "pop") end
end

-- Standard block rows: the looks of the Expiring warning. get(field) and set(field) make a row's
-- getter and setter for "grey", "ring", "pulse" or "glow"; noun is where the glow sits.
local function expiringLooks(p, get, set, noun, shown)
	p:checkbox("Grey icon", "Desaturate the icon.", get("grey"), set("grey"), shown)
	p:checkbox("Red ring", "A red ring inside the icon edge.", get("ring"), set("ring"), shown)
	p:checkbox("Fade in and out", nil, get("pulse"), set("pulse"), shown)
	p:checkbox("Pulsing glow", "A glow inside the " .. noun .. " that pulses.", get("glow"), set("glow"), shown)
end

-- Standard block: Killed early. get(name) and set(name) make a row's getter and setter; noun is what
-- flashes (the element's icon, or a slot of the totem bar).
local function killedBlock(p, get, set, noun, label)
	p:header("Killed early")
	p:checkbox(label, "The dead totem flashes red over its " .. noun .. ". Not when you dismiss it or it runs out.",
		get("killed"), set("killed"))
	local on = showWhen(get("killed"))
	p:checkbox("Pop", "The " .. noun .. " bursts for a moment.", get("killedPop"), set("killedPop"), on)
	p:checkbox("Pulsing glow", "In red.", get("killedGlow"), set("killedGlow"), on)
	p:checkbox("Cross until recast", "A red cross stays over the " .. noun .. " until you recast it, up to 5 s.",
		get("killedMark"), set("killedMark"), on)
end

-- Standard block: a timer's look (ShamanForever_Timers.lua). key nil: General's for the kind, with
-- note under its header; otherwise an element's own ("totembar" for the totem bar), with Same as General.
local TEXT_POS = { { "auto", "Auto" }, { "center", "Centre" }, { "topleft", "Top left" }, { "bottom", "Bottom" } }
local function timerSettings(p, title, key, kind, after, note)
	after = after or retime
	local cant = ns.Timer.cant(key, kind)
	local r = styleRows(key, kind, after)
	local style, tg, ts, own = r.style, r.get, r.set, r.own
	-- A row hides while following General, while its part is off, or when the game can't do it.
	local function dim(part, needs)
		return showWhen(function()
			if cant[part] or not own() then return false end
			if needs and not style()[needs] then return false end
			return true
		end)
	end
	local function secs(v) return string.format("%d", v) end
	p:header(title)
	if key then followRow(p, key, kind, after)
	else
		p:anchor(kind)
		if note then p:text(note) end
	end
	-- What the game can't do here, said once instead of showing rows that could never apply.
	for _, why in pairs(cant) do p:text(why, own) end
	p:checkbox("Countdown text", "Numbers counting down.", tg("text"), ts("text"), dim("text"))
	p:slider("Text size", nil, 6, 48, 1, secs, tg("textSize"), ts("textSize"), dim("text", "text"))
	p:color("Text colour", nil, tg("textColor"), ts("textColor"), dim("text", "text"))
	p:dropdown("Text position", "Auto: centred, or top-left on an icon that also shows a cooldown.", TEXT_POS,
		tg("textPos"), ts("textPos"), dim("text", "text"), 140)
	p:dropdown("Time format", "How minutes show. Minutes round up; the last minute always counts seconds.", {
		{ 0, "2m, then seconds" }, { 120, "1:31 in the last 2 minutes" },
		{ 300, "1:31 in the last 5 minutes" }, { 600, "1:31 in the last 10 minutes" },
	}, tg("abbrev"), ts("abbrev"), dim("text", "text"), 220)
	p:checkbox("Swipe", "A shade that sweeps round the icon.", tg("swipe"), ts("swipe"), dim("swipe"))
	p:slider("Swipe darkness", nil, 0.1, 1, 0.05, pct, tg("swipeAlpha"), ts("swipeAlpha"), dim("swipe", "swipe"))
	p:checkbox("Swipe darkens as time runs out", "Off: it lightens, like most cooldowns.", tg("swipeReverse"), ts("swipeReverse"), dim("swipe", "swipe"))
	p:checkbox("Time bar", "A bar along an edge that drains.", tg("bar"), ts("bar"), dim("bar"))
	p:slider("Bar height", nil, 1, 20, 1, px, tg("barHeight"), ts("barHeight"), dim("bar", "bar"))
	p:dropdown("Bar edge", nil, { { "bottom", "Bottom" }, { "top", "Top" } }, tg("barEdge"), ts("barEdge"), dim("bar", "bar"), 140)
	p:dropdown("Bar colour", nil, { { true, "Element colour" }, { false, "Custom" } }, tg("barElement"), ts("barElement"), dim("bar", "bar"), 160)
	p:color("Custom bar colour", nil, tg("barColor"), ts("barColor"), showWhen(function()
		return not cant.bar and own() and style().bar and not style().barElement
	end))
	if not key then ownLine(p, kind) end
end

-- Standard block: the global cooldown's sweep, on or off (the gcd style). key nil: General's;
-- otherwise an element's or the totem bar's, with Same as General.
local function gcdBlock(p, key)
	local function after() ns.refreshAll(); ns.TotemBar.drawGCD(); OP.refresh() end
	local r = styleRows(key, "gcd", after)
	p:header("Global cooldown")
	if key then followRow(p, key, "gcd", after)
	else
		p:anchor("gcd")
		p:text("Elements and the totem bar can have their own.")
	end
	p:checkbox("Show global cooldown", "The sweep after every cast, as on action bars.", r.get("show"), r.set("show"), showWhen(r.own))
	if not key then ownLine(p, "gcd") end
end

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
local function toggleLock() ns.setLocked(not acct().locked); OP.refresh() end
local function lockSub() return acct().locked and "Move groups and the totem bar on screen" or "Done moving? Lock them" end

local aboutExp, aboutFeedback   -- About's flashing headings (OP.showExperimental, OP.showFeedback)
local groupPanel -- Layout's selected-group panel, for OP.openGroup

local function addonVersion()
	local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Home, the page the window opens on: name, version, warnings and where to send feedback.
local function buildHome(p)
	p:pin(ns.Look.buildIntro(win, addonVersion()))
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText, lockSub, toggleLock },
		{ "Interface\\Icons\\Spell_Nature_Invisibilty", function() return "Layout" end,
			function() return "Set up groups of elements" end, function() OP.open("layout") end },
	})
	p:add(p:row(24), 24)   -- room between the big buttons and Feedback
	-- Feedback, in large type: it matters most on this page.
	local lead = p:text("Ideas, requests, bugs? Please let me know!")
	lead.text:SetFontObject("GameFontHighlightMedium")
	lead.text:SetTextColor(1, 0.92, 0.75)
	p:add(p:row(4), 4)
	p:bigButtons({
		{ "Interface\\Icons\\INV_Letter_15", function() return "Give feedback" end,
			function() return "Discord, CurseForge or GitHub" end, function() OP.showFeedback() end },
	})
end

-- General: the styles everything follows unless it has its own, then housekeeping.
local function buildGeneral(p)
	p:header("Defaults")
	p:anchor("size")
	p:text("Elements, groups and the totem bar use these unless they have their own.")
	p:slider("Icon size", "Every group's and the totem bar's, unless it has its own.", 24, 96, 1, int,
		get("iconSize"), set("iconSize"))
	-- Who has an own icon size: groups by number, then the totem bar.
	local function ownSizes()
		local out = {}
		for gi, g in ipairs(db().groups) do if not g.sizeFollow then table.insert(out, "Group " .. gi) end end
		if ns.TotemBar.barOn() and not ns.TotemBar.cfg().sizeFollow then table.insert(out, "Totem bar") end
		return out
	end
	p:text(function() return "Currently using their own: " .. table.concat(ownSizes(), ", ") end,
		function() return #ownSizes() > 0 end)
	p:header("Border")
	p:anchor("border")
	borderRows(p, nil)
	ownLine(p, "border")
	timerSettings(p, "Cooldowns", nil, "cooldown", nil, "A spell you can't cast yet.")
	timerSettings(p, "Time left", nil, "uptime", nil, "A totem, shield or imbue running.")
	gcdBlock(p, nil)
	glowBlock(p, nil, 136026)
	popBlock(p, nil, 136026, "ready")

	p:header("Minimap")
	p:checkbox("Show the minimap button", "Click it to open these options. Also listed in the minimap's addon menu.",
		function() return not (acct().minimap and acct().minimap.hide) end,
		function(v)
			if type(acct().minimap) ~= "table" then acct().minimap = {} end
			acct().minimap.hide = not v
			ns.applyMinimapButton()
		end)

	local hasReporter = ns.IssueReporter.has
	p:header("Beta", hasReporter)
	p:checkbox("Hide the Issue Reporter button", "Blizzard's beta Issue Reporter button. ShamanForever also remembers where you drag it.",
		function() return acct().hideIssueReporter end, function(v) acct().hideIssueReporter = v; ns.IssueReporter.apply() end, hasReporter)
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
		{ "Delete", function() StaticPopup_Show("SHAMANFOREVER_DELETE_PROFILE", ns.profileName()) end,
			"Characters using it go back to Default. Default can't be deleted.", 90, notDefault },
		{ "Reset", function() StaticPopup_Show("SHAMANFOREVER_RESET", ns.profileName()) end,
			"Every setting in this profile back to defaults, including the layout.", 90 },
	})

	p:header("Share")
	p:buttons({
		{ "Export", function() OP.showShare("export") end, "This profile as text, to share.", 90 },
		{ "Import", function() OP.showShare("import") end, "Profile text from someone else. It becomes a new profile.", 90 },
	})
end

-- A heading with a gold glow that flashes when a button elsewhere brings the reader to it.
local function flashingHeader(p, text, icon)
	local header = p:header(text, nil, nil, icon)
	local glow = header:CreateTexture(nil, "BACKGROUND")
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
	return { page = p, header = header, flash = flash }
end

-- Link icons: white site logos (Simple Icons, CC0), tinted with each site's colour. PNG paths need
-- their extension (the client only adds .tga or .blp itself).
local LINKS = {
	discord = { ART .. "Link-Discord.png", { 0.35, 0.40, 0.95 } },
	curseforge = { ART .. "Link-CurseForge.png", { 0.95, 0.39, 0.21 } },
	github = { ART .. "Link-GitHub.png", { 0.92, 0.92, 0.92 } },
	kofi = { ART .. "Link-Kofi.png", { 1, 0.37, 0.36 } },
}
local function link(p, label, url, site) p:copyField(label, url, LINKS[site][1], LINKS[site][2]) end

-- About's title card: the logo, the name, the version and what it is.
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
	f.title:SetText("ShamanForever")
	f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.sub:SetTextColor(0.80, 0.74, 0.66)
	return p:add(f, 84, nil, function() f.sub:SetText("Version " .. addonVersion() .. ". A shaman HUD for WoW Forever.") end)
end

local function buildAbout(p)
	local function gap() p:add(p:row(12), 12) end   -- a little room above each heading
	p:add(p:row(6), 6)
	aboutCard(p)
	gap()
	aboutFeedback = flashingHeader(p, "Feedback", "Interface\\Icons\\INV_Letter_15")
	p:text("Ideas, requests or problems? Post in #feedback on Discord, comment on CurseForge, or open an issue on GitHub. Click a link, then Ctrl+C to copy.")
	link(p, "Discord", ns.Look.DISCORD, "discord")
	link(p, "CurseForge", ns.Look.CURSEFORGE .. "/comments", "curseforge")
	link(p, "GitHub", ns.Look.REPO .. "/issues", "github")
	gap()
	p:header("Support", nil, nil, "Interface\\Icons\\INV_Misc_Coin_01")
	p:text("If you'd like to support this addon, you can buy me a coffee. Thanks!")
	link(p, "Ko-fi", ns.Look.KOFI, "kofi")
	gap()
	aboutExp = flashingHeader(p, "Experimental", "Interface\\Icons\\INV_Gizmo_02")
	p:text("I can't test these in game yet. If you can, please try them and tell me whether they work and what could be improved.")
	p:experimental("Water Shield", "Shields > Track")
	p:experimental("Either shield", "Shields > Track")
	gap()
	p:header("Art", nil, nil, "Interface\\Icons\\INV_Scroll_03")
	p:text("Banners from public-domain paintings: Thomas Moran, The Chasm of the Colorado (earth); Joseph Wright of Derby, " ..
		"Vesuvius from Portici (fire); Frederic Edwin Church, Rainy Season in the Tropics (water) and Aurora Borealis (spirit); " ..
		"Francisque Millet, Mountain Landscape with Lightning (air). Corner and divider ornaments: public domain / CC0, Wikimedia Commons. " ..
		"Logo: Blizzard's shaman crest, redrawn, over the same paintings and Ivan Aivazovsky, Breaking Wave; wood texture CC0, ambientCG. Link icons: Simple Icons, CC0.")
end

------------------------------------------------------------------------
-- Group board (Layout page): one card per group, "New group" and "Hidden". Drag an element's chip
-- onto a card to move it there, at the position the line shows; click a chip for a menu.
-- Hidden is a place in the UI only: underneath, a hidden element is Show "never" and still belongs
-- to its group, so showing it again (other than by dropping it on a group) puts it back there.
------------------------------------------------------------------------
local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" }, { "never", "Hidden" } }
-- On an element's page, where "Hidden keeps its place" is shown as text under the control.
local SHOW_TIP_PAGE = "Choosing Always or In combat again puts it back where it was. Groups can also be set to show only in combat on the Layout page; an element shows only when both allow it. Everything visible shows while positioning is unlocked."
local SHOW_TIP = "When the element is drawn. Hidden keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups can also be set to show only in combat on the Layout page; an element shows only when both it and its group allow it. Everything visible shows while the layout is unlocked."

local CARD_GAP, CHIP_H, CARD_HEAD = 8, 26, 28

local function isHidden(key) return ns.showMode(key) == "never" end
-- Into a group (or a new one) and shown: dropping a hidden element on a group shows it there.
local function placeShown(key, target, index)
	local hidden = isHidden(key)
	ns.placeElement(key, target, index)
	if hidden then ns.setShow(key, "always") end
end
local board = { cards = {}, chips = {} }

local function cardUnderCursor()
	for _, c in ipairs(board.cards) do
		if c:IsShown() and c:IsMouseOver() then return c end
	end
end

------------------------------------------------------------------------
-- Drag and drop in a list (the Layout board's chips, the totem bar's order): a ghost of the dragged
-- item follows the cursor, and a white line marks where it will land.
------------------------------------------------------------------------
-- The ghost: an icon and a label on the cursor while shown. onMove runs as it follows.
local function makeDragGhost(onMove)
	local ghost = CreateFrame("Frame", nil, UIParent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(180, 24)
	ghost:SetAlpha(0.9)
	ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
	ghost.icon:SetSize(20, 20)
	ghost.icon:SetPoint("LEFT", 2, 0)
	ns.cropIcon(ghost.icon)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ghost.text:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local sc = self:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 8, y / sc)
		onMove()
	end)
	return ghost
end

local function makeDropLine(parent)
	local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	line:SetColorTexture(0.95, 0.95, 0.95, 1)
	line:SetHeight(2)
	line:Hide()
	return line
end

-- Where a drop lands among items (top to bottom; skip(item) leaves out the one being dragged): its
-- place among the others, by the cursor's height, and those others.
local function dropPosition(items, skip)
	local _, cy = GetCursorPosition()
	local at, others = 1, {}
	for _, it in ipairs(items) do
		if not skip(it) then
			table.insert(others, it)
			local _, y = it:GetCenter()
			if y and y * it:GetEffectiveScale() > cy then at = #others + 1 end
		end
	end
	return at, others
end

-- The drop line above others[at], or under the last one. False when there are no others to place it by.
local function placeDropLine(line, others, at)
	line:ClearAllPoints()
	if #others == 0 then return false end
	if at <= #others then
		line:SetPoint("BOTTOMLEFT", others[at], "TOPLEFT", 0, 0)
		line:SetPoint("BOTTOMRIGHT", others[at], "TOPRIGHT", 0, 0)
	else
		line:SetPoint("TOPLEFT", others[#others], "BOTTOMLEFT", 0, 0)
		line:SetPoint("TOPRIGHT", others[#others], "BOTTOMRIGHT", 0, 0)
	end
	return true
end

-- Position among the card's other chips that the cursor points at.
local function dropIndex(c, key)
	return dropPosition(c.chips, function(chip) return chip.key == key end)
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
	if not placeDropLine(ind, others, at) then   -- an empty card: under its header
		ind:SetPoint("TOPLEFT", c, "TOPLEFT", 6, -CARD_HEAD + 1)
		ind:SetPoint("TOPRIGHT", c, "TOPRIGHT", -6, -CARD_HEAD + 1)
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
		if c.target == "hidden" then ns.setShow(key, "never")
		elseif type(c.target) == "number" then
			-- The drop position counts only the visible chips; hidden members keep their places.
			local at, others = dropIndex(c, key)
			local rest = {}
			for _, k in ipairs(db().groups[c.target].members) do if k ~= key then table.insert(rest, k) end end
			local index = #rest + 1
			local anchor = others[at] or others[#others]
			for i, k in ipairs(rest) do
				if anchor and k == anchor.key then index = others[at] and i or i + 1 end
			end
			placeShown(key, c.target, index)
		else placeShown(key, c.target) end
	end
	OP.refresh()   -- also restores the dimmed chip when nothing moved
end

local function chipMenu(chip)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	if board.dragEnded and GetTime() - board.dragEnded < 0.3 then return end   -- the release that ended a drag
	local key = chip.key
	MenuUtil.CreateContextMenu(chip, function(_, root)
		root:CreateTitle(ns.ELEMENTS[key].label)
		root:CreateButton("Open settings", function() OP.openElement(key) end)
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
	c:SetBackdrop(ns.BACKDROP)
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
			OP.refresh()
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
	ns.cropIcon(chip.icon)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:RegisterForDrag("LeftButton")
	chip:SetScript("OnClick", chipMenu)
	chip:SetScript("OnDragStart", startDrag)
	chip:SetScript("OnDragStop", finishDrag)
	setTip(chip, "Move element", "Drag onto another group, New group or Hidden. Drop between elements to set the order. Click for a menu.")
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
			chip.text:SetText(ns.ELEMENTS[key].label .. (mode == "combat" and "  |cff888888(in combat)|r" or ""))
			chip:SetAlpha(target == "hidden" and 0.6 or 1)
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
	-- Groups fill two columns, each card going into the shorter one. A group lists its visible
	-- elements; one with nothing visible stays out of the way until something in it shows again.
	local colY = { 0, 0 }
	local hidden = {}
	for gi, g in ipairs(groups) do
		local shown = {}
		for _, key in ipairs(g.members) do
			if isHidden(key) then table.insert(hidden, key) else table.insert(shown, key) end
		end
		if #shown > 0 then
			local c, h = fill(gi, shown, "Group " .. gi, g.orientation == "vertical" and "Column" or "Row")
			local col = colY[1] <= colY[2] and 1 or 2
			place(c, (col - 1) * (colW + CARD_GAP), colY[col])
			colY[col] = colY[col] + h + CARD_GAP
		end
	end
	local y = math.max(colY[1], colY[2])
	local newCard, h = fill("new", {}, "New group", nil, "Drop an element here to give it a group of its own.")
	place(newCard, 0, y)
	local hiddenCard, hh = fill("hidden", hidden, "Hidden", nil, "Drop an element here to hide it.")
	place(hiddenCard, colW + CARD_GAP, y)
	h = math.max(h, hh)
	for i = nCard + 1, #board.cards do board.cards[i]:Hide() end
	for i = nChip + 1, #board.chips do board.chips[i]:Hide() end
	board.height = y + h
	board.frame:SetHeight(board.height)
end

local function buildBoard(p)
	board.page = p
	board.frame = p:row(10)
	board.indicator = makeDropLine(board.frame)
	board.ghost = makeDragGhost(updateDragFeedback)
	p:add(board.frame, function() return board.height or 10 end, nil, layoutBoard)
end

local function buildLayout(p)
	-- Positioning covers the groups and the totem bar; the totem bar's own layout is on its page.
	p:bigButtons({
		{ "Interface\\Icons\\INV_Misc_Key_03", lockText, lockSub, toggleLock },
		{ "Interface\\Icons\\Spell_Shaman_DropAll_01", function() return "Totem bar" end,
			function() return "Its layout is on its own page" end, function() OP.open("totembar") end },
	})
	p:header("Elements layout")
	p:text("ShamanForever calls each indicator an element, and every element sits in one group. Drag elements between groups; click one for a menu. Drop one between two others to change the order.")
	p:checkbox("Test elements", nil,
		function() return acct().testMode end, function(v) ns.setTestMode(v); OP.refresh() end)
	p:text("Adds placeholder elements in their own group, for trying out layouts.")
	p:add(p:row(6), 6)   -- a little room between the heading's line and the group cards
	buildBoard(p)

	-- The selected group's settings sit in a panel edged in the same gold as its card, titled with the
	-- group's number, direction and element icons, and flash when another group is picked.
	local panel = CreateFrame("Frame", nil, p.content, "BackdropTemplate")
	panel:SetBackdrop(ns.BACKDROP)
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
				ns.cropIcon(t)
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
	generalRow(p, "Icon size same as General", "Use the icon size on the General page.",
		function() local g = selected(); return g and g.sizeFollow end,
		function(v)
			local g = selected()
			if not g then return end
			if not v then g.size = db().iconSize end   -- its own starts from General's, so nothing jumps
			g.sizeFollow = v
			relayout()
		end, "size", hasGroups)
	p:slider("Icon size", "Mouse wheel over the group while unlocked does the same.", 24, 96, 1, int,
		groupGet("size"), groupSet("size"), showWhen(function() local g = selected(); return g and not g.sizeFollow end, hasGroups))
	p:text("Icon size keeps borders and rings crisp. Scale grows everything, borders and rings included.", hasGroups)
	p:slider("Scale", "Grows everything in the group, borders and rings too. Ctrl + mouse wheel over the group while unlocked does the same.", 0.5, 3, 0.05, times,
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
	borderRows(p, selected, relayout, "Border same as General", hasGroups)
	p:checkbox("Only show in combat", "Everything visible shows while positioning is unlocked.",
		groupGet("combatOnly"), groupSet("combatOnly"), hasGroups)
	p:text("Elements have their own Show setting too. An element shows only when both allow it.", hasGroups)
	local lastRow = p:buttons({
		-- Hard to undo, so each asks first.
		{ "Centre on screen", function() StaticPopup_Show("SHAMANFOREVER_CENTER", selectedGroup, nil, selectedGroup) end, "Moves the group to the middle of the screen.", 130 },
		{ "Split up", function() StaticPopup_Show("SHAMANFOREVER_SPLIT", selectedGroup, nil, selectedGroup) end, "Gives every element in the group a group of its own, left where it is.", 100 },
		{ "Hide all", function() StaticPopup_Show("SHAMANFOREVER_HIDEALL", selectedGroup, nil, selectedGroup) end, "Sets every element in the group to Hidden. They keep their places; set one back to Always to bring it back.", 100 },
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
-- Totem bar (ShamanForever_TotemBar.lua)
------------------------------------------------------------------------
-- Rows for the per-totem warning times: one per totem given its own time, at most this many.
local MAX_WARN_ROWS = 32

local function buildTotemBar(p)
	local TB = ns.TotemBar
	local function c() return TB.cfg() end
	local function changed() TB.apply(); OP.refresh() end
	local function tget(key) return function() return c()[key] end end
	local function tset(key) return function(v) c()[key] = v; changed() end end

	p:hero("totembar")
	-- The Totems cards decide which of ours and Blizzard's totem frames show; the sections below
	-- show only where they apply (Buttons in Everything, the rest while our bar is on).
	local full = function() return c().mode == "everything" end
	p:header("Totems")
	p:cards("Use", nil, {
		{ "blizzard", "Blizzard's", "Interface\\Icons\\INV_Misc_Gear_01" },
		{ "active", "Active totems", "Interface\\Icons\\Spell_Nature_TimeStop" },
		{ "everything", "Everything", "Interface\\Icons\\Spell_Shaman_DropAll_01" },
	}, tget("mode"), function(v) TB.setMode(v); changed() end)
	-- What the mode does, then how the bar is used in it.
	local KEYS = "Keys: Options > Keybindings > ShamanForever."
	local BAR_KEYS = "Keys: Options > Keybindings > ShamanForever, or hover the bar in Quick Keybind Mode."
	p:text("ShamanForever's totem bar is off. Blizzard's totem bar and active totems display are on.\n"
		.. "The totem key bindings still work. " .. KEYS, function() return c().mode == "blizzard" end)
	p:text("Keeps Blizzard's totem bar, but replaces Blizzard's active totems display usually shown under the player frame.\n"
		.. "Right-click a totem to dismiss it. " .. BAR_KEYS, function() return c().mode == "active" end)
	p:text("Both of Blizzard's totem frames are replaced by ShamanForever.\n"
		.. "Right-click a totem to dismiss it. Alt+click a slot to pick its totem. " .. BAR_KEYS, full)

	p.gate = TB.barOn
	p:header("Display")
	p:dropdown("Show", "When the bar is on screen. It always shows while positioning is unlocked.",
		{ { "always", "Always" }, { "active", "In combat or a totem down" }, { "combat", "In combat" } },
		tget("show"), tset("show"), nil, 200)
	p:dropdown("Tooltips", nil, { { "always", "Always" }, { "ooc", "Out of combat" }, { "never", "Never" } },
		tget("tips"), tset("tips"), nil, 160)
	p:checkbox("Show keybinding text", "Each button's key, in its corner.", tget("keys"), tset("keys"))

	p:header("Layout")
	-- The elements in bar order (first: the left end of a row, the top of a column). Drag one to move
	-- it; the box shows or hides its slot. The drag follows the group board's: a ghost on the cursor
	-- and a white line where it will land.
	local ORDER_H, ORDER_W = 28, 260
	p:text("Drag to reorder.")
	local list = p:row(4 * ORDER_H)
	local rows, dragFrom = {}, nil
	local line = makeDropLine(list)
	-- Where the dragged element would land: its place among the other three.
	local function dropAt()
		return dropPosition(rows, function(r) return r == rows[dragFrom] end)
	end
	local ghost = makeDragGhost(function()
		local at, others = dropAt()
		line:SetShown(placeDropLine(line, others, at))
	end)
	local function endDrag(drop)
		local from = dragFrom
		-- Where it lands, read while the dragged row is still left out of the others.
		local at = from and drop and dropAt()
		dragFrom = nil
		ghost:Hide()
		line:Hide()
		if not from then return end
		if at then
			local o = c().order
			local el = table.remove(o, from)
			table.insert(o, at, el)
			changed()
		end
		OP.refresh()   -- also restores the dimmed row
	end
	-- Leaving the page or closing the window mid-drag drops nothing.
	list:SetScript("OnHide", function() endDrag(false) end)
	for i = 1, 4 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(ORDER_W, ORDER_H - 2)
		r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ORDER_H)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.06)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		cb:SetSize(26, 26)
		cb:SetPoint("LEFT", 0, 0)
		cb:SetScript("OnClick", function(self)
			c().hidden[r.el] = not self:GetChecked() or nil
			changed()
		end)
		setTip(cb, "Slot", "Show this element's slot.")
		r.cb = cb
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		ns.cropIcon(r.icon)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r:RegisterForDrag("LeftButton")
		r:SetScript("OnDragStart", function(self)
			dragFrom = i
			self:SetAlpha(0.35)
			ghost.icon:SetTexture(self.icon:GetTexture())
			ghost.text:SetText(self.text:GetText())
			ghost:Show()
		end)
		r:SetScript("OnDragStop", function() endDrag(true) end)
		setTip(r, "Order", "Drag to change where the element sits on the bar.")
		rows[i] = r
	end
	p:add(list, 4 * ORDER_H, nil, function()
		for i, r in ipairs(rows) do
			local el = c().order[i]
			r.el = el
			r.icon:SetTexture(ns.Look.TOTEM_ICON[el])
			r.text:SetText(TB.NAME[el])
			r.cb:SetChecked(not c().hidden[el])
			r:SetAlpha(1)
		end
	end)
	p:dropdown("Direction", nil, { { "row", "Row" }, { "column", "Column" } }, tget("dir"), function(v)
		c().dir = v
		c().pop = v == "row" and "up" or "right"
		changed()
	end, nil, 140)
	p:dropdown("Pickers open", "Which way the totem picker opens from a slot.", function()
		if c().dir == "row" then return { { "up", "Up" }, { "down", "Down" } } end
		return { { "right", "Right" }, { "left", "Left" } }
	end, tget("pop"), tset("pop"), full, 140)
	p:slider("Spacing", nil, 0, 20, 1, px, tget("spacing"), tset("spacing"))
	-- Its own size is not its scale: scale grows everything, text, arrows, spacing and lines included.
	generalRow(p, "Icon size same as General", "Use the icon size on the General page.",
		tget("sizeFollow"), function(v) TB.setSizeFollow(v); changed() end, "size")
	p:slider("Icon size", "Mouse wheel over the bar while positioning is unlocked does the same.", 24, 96, 1, px, tget("size"), tset("size"),
		showWhen(function() return not c().sizeFollow end))
	p:dropdown("Call and Recall", "Where they sit on the bar.", { { "ends", "Both ends" }, { "before", "Before the slots" }, { "after", "After the slots" } },
		tget("extras"), tset("extras"), showWhen(function() return c().call or c().recall end, full), 180)
	p:slider("Call and Recall size", "As a share of the slots' size.", 0.5, 1.5, 0.05,
		pct, tget("extrasScale"), tset("extrasScale"),
		showWhen(function() return c().call or c().recall end, full))
	p:slider("Scale", "Grows everything on the bar, borders too. Ctrl + mouse wheel over the bar while positioning is unlocked does the same.", 0.5, 3, 0.05,
		times, tget("scale"), tset("scale"))
	p:slider("Opacity", "Shift + mouse wheel over the bar while positioning is unlocked does the same.", 0.1, 1, 0.05,
		pct, tget("alpha"), tset("alpha"))

	p.gate = full
	p:header("Buttons")
	p:checkbox("Left-click casts your pick", "Left-click a slot to drop that element's picked totem.", tget("cast"), tset("cast"))
	p:checkbox("Arrow opens a totem picker", "A tab on each slot opens its totems. Works in combat.", tget("arrows"), tset("arrows"))
	p:slider("Arrow size", "How deep the tab is.", 8, 32, 1, px,
		tget("arrowSize"), tset("arrowSize"), showWhen(function() return c().arrows end))
	p:checkbox(ns.Spells.name("call"), nil, tget("call"), tset("call"))
	p:checkbox(ns.Spells.name("recall"), nil, tget("recall"), tset("recall"))
	p:text(function()
		return string.format("%s shows once you know it. Right-click %s to dismiss all totems, even before you learn it.",
			ns.Spells.name("call"), ns.Spells.name("recall"))
	end)

	p.gate = TB.barOn
	p:header("Border")
	borderRows(p, "totembar", changed)
	timerSettings(p, "Time left", "totembar", "uptime", changed)

	p.gate = full
	gcdBlock(p, "totembar")
	p:header("Totem not down")
	p:dropdown("Look", "How a slot looks while its totem isn't down.",
		{ { "pick", "Your pick" }, { "frame", "Element colour" }, { "blank", "Blank" } }, tget("empty"), tset("empty"), nil, 180)
	local pickLook = showWhen(function() return c().empty == "pick" end)
	p:checkbox("Greyed", "Off: the pick in colour.", tget("idleGrey"), tset("idleGrey"), pickLook)
	p:slider("Opacity", nil, 0.1, 1, 0.05, pct,
		tget("idleAlpha"), tset("idleAlpha"), pickLook)
	p:text("With No totem picked, the slot shows its element colour.", pickLook)

	p:header("Not your pick")
	p:text("When a different totem is down, your pick shows small beside the slot.")
	p:checkbox("Show your pick", "On the side away from the picker.",
		tget("offPick"), tset("offPick"))
	p:slider("Size", nil, 0.25, 0.8, 0.05, pct,
		tget("badgeSize"), tset("badgeSize"), showWhen(tget("offPick")))
	p:slider("Opacity", nil, 0.1, 1, 0.05, pct,
		tget("badgeAlpha"), tset("badgeAlpha"), showWhen(tget("offPick")))
	p:slider("Colour", "0% is grey, 100% full colour.", 0, 1, 0.05, pct,
		tget("badgeSat"), tset("badgeSat"), showWhen(tget("offPick")))

	p.gate = TB.barOn
	p:header("Out of range")
	local rangeOn = tget("range")
	p:text("A strip along the top of a slot shows whether you're getting your own totem's buff, for totems that buff you. In range shows nothing at 0% opacity, the default.")
	p:checkbox("Show", nil, rangeOn, tset("range"))
	p:slider("Height", "In pixels.", 1, 12, 1, px,
		tget("rangeHeight"), tset("rangeHeight"), showWhen(rangeOn))
	p:color("In range", "Colour and opacity.", tget("rangeIn"), tset("rangeIn"), showWhen(rangeOn))
	p:color("Out of range", "Colour and opacity.", tget("rangeOut"), tset("rangeOut"), showWhen(rangeOn))
	p:text("A buff lingers a few seconds after you leave its range. Another shaman's totem of the same type can replace your buff, so yours shows as out of range.", rangeOn)

	p:header("Expiring")
	local WARN = { grey = "warnGrey", ring = "warnRing", pulse = "warnPulse", glow = "warnGlow" }
	expiringLooks(p, function(k) return tget(WARN[k]) end, function(k) return tset(WARN[k]) end, "slot")
	p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", tget("expiredPop"), tset("expiredPop"))
	local secs = function(v) return v == 0 and "Off" or string.format("%d s", v) end
	p:slider("Warn in the last", nil, 0, 30, 1, secs, tget("warn"), tset("warn"))
	p:text("Totems with their own warning time, instead of the default:", function() return next(c().warnOver) ~= nil end)
	-- Each totem's own time, with a small X at the end of its row to drop it. Totems are kept by the
	-- client's name for them (any rank), so row i shows the i-th name in order.
	local function overName(i)
		local names = {}
		for name in pairs(c().warnOver) do table.insert(names, name) end
		table.sort(names)
		return names[i]
	end
	for i = 1, MAX_WARN_ROWS do
		local row = p:slider("", nil, 0, 30, 1, secs,
			function() local name = overName(i); return name and c().warnOver[name] or c().warn end,
			function(v) local name = overName(i); if name then c().warnOver[name] = v; changed() end end,
			function() return overName(i) ~= nil end)
		local item = p.items[#p.items]
		local refresh = item.refresh
		item.refresh = function()
			row.label:SetText(((overName(i) or ""):gsub(" Totem$", "")))
			refresh()
		end
		local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		x:SetSize(24, 22)
		x:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		x:SetText("X")
		x:SetScript("OnClick", function()
			local name = overName(i)
			if name then c().warnOver[name] = nil; changed() end
		end)
		setTip(x, "Remove", "Use the time above for this totem.")
	end
	-- Adding is an action, not a choice kept: plain entries under a prompt, not radio buttons.
	local add = p:dropdown("Add a totem", "Give a totem its own warning time.", {}, function() return nil end, function() end, nil, 220)
	local dd = add.dropdown
	pcall(dd.SetDefaultText, dd, "Choose a totem")
	dd:SetupMenu(function(_, root)
		local names, seen = {}, {}
		for slot = 1, 4 do
			for _, id in ipairs(TB.knownTotems(slot)) do
				local name = ns.Spells.nameOf(id)
				if name and not seen[name] and c().warnOver[name] == nil then
					seen[name] = true
					table.insert(names, name)
				end
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			root:CreateButton(name, function() c().warnOver[name] = c().warn; changed() end)
		end
		if #names == 0 then root:CreateTitle("Every totem you know has its own time") end
	end)

	killedBlock(p, tget, tset, "slot", "Flash when a totem dies early")

	glowBlock(p, "totembar", 136098)
	popBlock(p, "totembar", 136098, "expired")
	p.gate = nil
end

------------------------------------------------------------------------
-- Elements: an overview of every element, and one page per real element under it in the nav.
------------------------------------------------------------------------
local ELEMENT_PAGES = {}   -- key -> page key, filled as element pages are built

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
		ns.cropIcon(icon)
		local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", 32, 0)
		name:SetText(e.label)
		local group = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		group:SetPoint("LEFT", GROUP_X, 0)
		group:SetWidth(100)
		group:SetupMenu(function(_, rootDescription)
			for gi = 1, groupCount() do
				rootDescription:CreateRadio("Group " .. gi, function() return not isHidden(key) and ns.findElement(key) == gi end,
					function() placeShown(key, gi) end)
			end
			rootDescription:CreateRadio("New group", function() return false end, function() placeShown(key, "new") end)
			rootDescription:CreateRadio("Hidden", function() return isHidden(key) end, function() ns.setShow(key, "never") end)
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
		open:SetScript("OnClick", function() if ELEMENT_PAGES[key] then OP.open(ELEMENT_PAGES[key]) end end)
		p:add(f, 34, function() return ns.available(key) end, function()
			e.paint(icon)
			group:GenerateMenu()
			show:GenerateMenu()
			open:SetShown(ELEMENT_PAGES[key] ~= nil)
		end)
	end
end

-- Every element page, in one order: its header, Display (Show, Group), its own settings, then the
-- standard blocks: the missing-look Warning, Idle, the timers (Cooldown, Time left), the event
-- blocks (Ready, Expiring, Killed early), then Glow style and Pop style.
local function elementDisplay(p, key)
	ELEMENT_PAGES[key] = p.key
	p:hero(key)
	p:header("Display")
	p:dropdown("Show", SHOW_TIP_PAGE, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
	p:text("Hidden keeps its place in its group.")
	p:dropdown("Group", "Which group it sits in. Groups are arranged on the Layout page.", function()
		local list = {}
		for gi = 1, groupCount() do table.insert(list, { gi, "Group " .. gi }) end
		table.insert(list, { "new", "New group" })
		table.insert(list, { "hidden", "Hidden" })
		return list
	end, function() return isHidden(key) and "hidden" or ns.findElement(key) end, function(v)
		if v == "hidden" then ns.setShow(key, "never") else placeShown(key, v) end
	end, nil, 140)
	local groupRow = p.items[#p.items].frame
	local edit = CreateFrame("Button", nil, groupRow, "UIPanelButtonTemplate")
	edit:SetSize(96, 22)
	edit:SetPoint("LEFT", groupRow.dropdown, "RIGHT", 8, 0)
	edit:SetText("Edit group")
	edit:SetScript("OnClick", function() local gi = ns.findElement(key); if gi then OP.openGroup(gi) end end)
	setTip(edit, "Edit group", "This group's settings on the Layout page.")
end

-- An element's own option (db.elementOpts), with its default (ns.elementSetting).
local function eget(key, name) return function() return ns.elementSetting(key, name) end end
local function eset(key, name) return function(v) ns.elementOpts(key)[name] = v; relayout() end end

-- Standard block: the moment a cooldown ends. A pop, and with glowTip a "use me" glow (Shocks, Fire
-- Nova; off by default).
local function readyBlock(p, key, glowTip)
	p:header("Ready")
	p:checkbox("Pop", "The moment the cooldown ends.", eget(key, "readyPop"), eset(key, "readyPop"))
	if glowTip then p:checkbox("Pulsing glow", glowTip, eget(key, "readyGlow"), eset(key, "readyGlow")) end
end

-- Standard block: the look while the element has nothing going on (Earthbind, Stoneclaw, Fire Nova).
local IDLE_WHEN = { { "never", "Never" }, { "nototem", "Off cooldown, no fire totem" }, { "offcd", "Off cooldown" } }
local function idleBlock(p, key, fireNova)
	p:header("Idle")
	if fireNova then
		p:text("Idle is when there's nothing to track. At 0% it's hidden and keeps its place in the group.")
		p:dropdown("Idle when", "Off cooldown, no fire totem: it can't be cast. Off cooldown: whether a fire totem is down or not.",
			IDLE_WHEN, eget(key, "idleWhen"), eset(key, "idleWhen"), nil, 210)
	else
		p:text("Idle is when it's off cooldown and its totem isn't down. At 0% it's hidden and keeps its place in the group.")
	end
	p:slider("Idle opacity", "The icon's opacity while idle.",
		0, 1, 0.05, pct, eget(key, "idleAlpha"), eset(key, "idleAlpha"),
		fireNova and showWhen(function() return ns.elementSetting(key, "idleWhen") ~= "never" end) or nil)
end

-- Standard block: a totem killed early (Earthbind, Stoneclaw), as on the totem bar.
-- Standard blocks at the end of a page with glows or pops: their styles, General's or its own.
local function effectBlocks(p, key, popKind)
	local icon = ns.Look.ELEMENT[key].icon
	glowBlock(p, key, icon)
	popBlock(p, key, icon, popKind or "ready")
end

-- Standard block: the look while something is missing. first: an optional row before the three.
local function warningBlock(p, title, greyGet, greySet, ringGet, ringSet, pulseGet, pulseSet, first)
	p:header(title)
	if first then first() end
	p:checkbox("Grey icon", "Desaturate the icon.", greyGet, greySet)
	p:checkbox("Red ring", "A red ring inside the icon edge.", ringGet, ringSet)
	p:checkbox("Fade in and out", nil, pulseGet, pulseSet)
end

-- A look choice (tint, overlay, both) greys out the strength it does not use.
local function lookUses(key, part) return function() local v = db()[key]; return v == part or v == "both" end end

local function buildShield(p)
	elementDisplay(p, "shield")
	p:header("Tracking")
	-- Lightning Shield is the tested default; the Water Shield modes are experimental until tested in game.
	p:cards("Track", nil, {
		{ "lightning", ns.Spells.name("lightningShield"), 136051 },
		{ "water", ns.Spells.name("waterShield"), 132315, "Water Shield" },
		{ "either", "Either", 136051, "Either shield" },
	}, get("shieldTrack"), set("shieldTrack", respell))
	p:text("Only one shield can be up at a time. With one chosen, the other counts as no shield.")
	p:header("Charges")
	p:checkbox("Charge bar", "One segment per charge.", get("showBar"), set("showBar"))
	p:slider("Bar height", nil, 1, 20, 1, px, get("chargeBarHeight"), set("chargeBarHeight"),
		showWhen(get("showBar")))
	p:color("Bar colour", nil, get("chargeBarColor"), set("chargeBarColor"), showWhen(get("showBar")))
	p:checkbox("Charge number", "Shown for 2 or more charges.", get("showCount"), set("showCount"))
	local numberOn = showWhen(get("showCount"))
	p:dropdown("Number position", nil, { { "corner", "Corner" }, { "center", "Centre" } }, get("countPos"), set("countPos"), numberOn)
	p:slider("Number size", nil, 8, 64, 1, int, get("countSize"), set("countSize"), numberOn)

	warningBlock(p, "No shield", get("emptyGrey"), set("emptyGrey"), get("emptyRing"), set("emptyRing"), get("emptyPulse"), set("emptyPulse"))
	p:checkbox("Red tint", "Tint the icon red.", get("emptyTint"), set("emptyTint"))
	p:slider("In-combat fallback", nil, 0, 1, 0.05, pct, get("underlayUp"), set("underlayUp"))
	p:text("A shield that drops in combat is only noticed when you recast it or combat ends. Until then, the no-shield look shows at this strength.")

	p:header("Shield up")
	p:slider("Icon opacity", nil, 0.5, 1, 0.05, pct, get("shieldIconAlpha"), set("shieldIconAlpha"))
	p:text("Only matters at low group opacity. Most can leave it at 100%.")
	timerSettings(p, "Time left", "shield", "uptime")
	gcdBlock(p, "shield")
end

local function buildShock(p)
	elementDisplay(p, "shock")
	p:header("Tracking")
	local icons = { earth = 136026, flame = 135813, frost = 135849 }
	local cards = {}
	for _, key in ipairs(ns.Cooldowns.SHOCK_ORDER) do table.insert(cards, { key, ns.Cooldowns.SHOCKS[key], icons[key] }) end
	p:cards("Track", "Its cooldown and range.", cards, get("shock"), set("shock", respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, key in ipairs(ns.Cooldowns.SHOCK_ORDER) do table.insert(manaChoices, { key, ns.Cooldowns.SHOCKS[key] }) end
	p:dropdown("Mana check", nil, manaChoices, get("manaSpell"), set("manaSpell", respell))
	p:text("The spell whose cost turns the icon blue when you're short of mana.")

	local looks = { { "tint", "Tint" }, { "overlay", "Overlay" }, { "both", "Both" } }
	p:header("No mana")
	p:dropdown("Look", "Out of range wins over this look.", looks, get("manaStyle"), set("manaStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("manaIntensity"), set("manaIntensity"),
		showWhen(lookUses("manaStyle", "overlay")))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("manaTint"), set("manaTint"),
		showWhen(lookUses("manaStyle", "tint")))
	p:slider("Ring", "The blue ring, shown even when out of range.", 0.1, 1, 0.05, pct, get("manaRing"), set("manaRing"))

	p:header("Out of range")
	p:dropdown("Look", nil, looks, get("rangeStyle"), set("rangeStyle"))
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, get("rangeIntensity"), set("rangeIntensity"),
		showWhen(lookUses("rangeStyle", "overlay")))
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, get("rangeTint"), set("rangeTint"),
		showWhen(lookUses("rangeStyle", "tint")))
	timerSettings(p, "Cooldown", "shock", "cooldown")
	gcdBlock(p, "shock")
	readyBlock(p, "shock", "While it's off cooldown.")
	effectBlocks(p, "shock")
end

local function buildImbue(p)
	elementDisplay(p, "imbue")
	warningBlock(p, "No imbue", get("imbueMissingGrey"), set("imbueMissingGrey"), get("imbueMissingRing"), set("imbueMissingRing"),
		get("imbuePulse"), set("imbuePulse"), function()
			local cards = { { "last", "Last used", 136086 } }
			-- The client's names; " Weapon" is trimmed where it has one (English).
		for _, key in ipairs(ns.Imbue.ORDER) do table.insert(cards, { key, (ns.Imbue.IMBUES[key].name:gsub(" Weapon$", "")), ns.Imbue.IMBUES[key].icon }) end
			p:cards("Icon", nil, cards, get("imbuePreferred"), set("imbuePreferred"))
			p:text("The icon shown while no imbue is on.")
		end)
	p:checkbox("Pulsing glow", "A glow inside the icon that pulses.", get("imbueGlow"), set("imbueGlow"))
	p:checkbox("Pop", "The moment your imbue runs out or is lost.", get("imbuePop"), set("imbuePop"))

	p:header("Time left")
	p:slider("Show under", nil, 0, 30, 1,
		function(v) return v == 0 and "Never" or string.format("%d min", v) end, get("imbueWarnMins"), set("imbueWarnMins"))
	p:text("Time left shows once it's below this. 0 never shows it.")
	p:checkbox("Hide until low", nil, get("imbueHideActive"), set("imbueHideActive"))
	p:text("While an imbue is on, the icon stays hidden until the time left shows. It keeps its place in the group.")
	timerSettings(p, "Timer", "imbue", "uptime")
	effectBlocks(p, "imbue", "imbue")
end

-- One page per cooldown element; the blocks depend on what the element tracks.
local function buildCooldown(p, def)
	local key = def.key
	elementDisplay(p, key)
	if def.needsTotem then
		warningBlock(p, "No fire totem", eget(key, "blockedGrey"), eset(key, "blockedGrey"), eget(key, "blockedRing"), eset(key, "blockedRing"),
			eget(key, "blockedPulse"), eset(key, "blockedPulse"))
	end
	idleBlock(p, key, def.needsTotem)
	timerSettings(p, "Cooldown", key, "cooldown")
	gcdBlock(p, key)
	readyBlock(p, key, def.needsTotem and "While it's off cooldown and a fire totem is down.")
	if def.needsTotem then timerSettings(p, "Fire totem's time left", key, "uptime")
	elseif def.totemSlot then timerSettings(p, "Time left", key, "uptime") end
	if def.needsTotem or def.totemSlot then
		-- Expiring: a warning in the totem's last seconds.
		local function xget(k) return function() return ns.Timer.expireOpts(key)[k] end end
		local function xset(k) return function(v)
			local o = ns.elementOpts(key)
			if type(o.expire) ~= "table" then o.expire = {} end
			o.expire[k] = v
			relayout()
		end end
		local on = showWhen(function() return ns.Timer.expireOpts(key).secs > 0 end)
		p:header("Expiring")
		p:slider("Warn in the last", "Seconds before the totem runs out. Zero turns the warning off.", 0, 30, 1,
			function(v) return v == 0 and "Off" or string.format("%d s", v) end, xget("secs"), xset("secs"))
		expiringLooks(p, xget, xset, "icon", on)
		if def.totemSlot then
			p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", eget(key, "expiredPop"), eset(key, "expiredPop"))
		end
	end
	if def.totemSlot then
		killedBlock(p, function(n) return eget(key, n) end, function(n) return eset(key, n) end, "icon",
			"Flash when it dies early")
	end
	effectBlocks(p, key)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local navButtons, navDivider, navLock = {}, nil, nil

local function showPage(key)
	currentPage = key
	acct().optionsPage = key   -- reopened next time, across reloads (account-wide, like the window height)
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
	if navLock then navLock.refresh() end
	pages[key]:refresh()
end

-- The nav: main pages, then every element's page (indented), then Profiles and About.
local function buildNav()
	local y = LOGO_Y - LOGO_SIZE - 1   -- just below the logo
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
		ns.cropIcon(b.icon)
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
	add("totembar", "Totem bar", "Interface\\Icons\\Spell_Shaman_DropAll_01")
	add("elements", "Elements", ART .. "Elements.tga")
	for _, p in ipairs(pageOrder) do
		local e = ns.Look.ELEMENT[p.key]
		if e and not e.page then add(p.key, ns.Look.elementName(p.key), e.icon, true) end
	end
	y = y - 4
	navDivider = ns.Look.divider(win)
	navDivider:SetPoint("TOPLEFT", 20, y)
	navDivider:SetWidth(NAV_W - 36)
	y = y - 14
	add("profiles", "Profiles", "Interface\\Icons\\INV_Misc_Note_01")
	add("about", "About", "Interface\\Icons\\INV_Misc_Book_09")
	-- Footer: positioning's lock, one click either way (as /sf lock); its label says what it does.
	navLock = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
	navLock:SetSize(NAV_W - 32, 22)
	navLock:SetPoint("BOTTOMLEFT", 16, 12)
	navLock:SetScript("OnClick", function() ns.setLocked(not acct().locked) end)
	setTip(navLock, "Positioning", "Unlocked, drag groups and the totem bar on screen. /sf lock does the same.")
	function navLock.refresh() navLock:SetText(acct().locked and "Unlock positioning" or "Lock positioning") end
	navLock.refresh()
end

local function buildWindow()
	-- Blizzard's portrait window: gold frame, round portrait, title and close button.
	win = CreateFrame("Frame", "ShamanForeverOptionsFrame", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, win) end
	if win.Inset then win.Inset:Hide() end
	if win.SetTitle then win:SetTitle("ShamanForever") end
	-- The logo: the crest alone (Art/Logo-Icon, with alpha) as a badge over the top-left corner, on
	-- Blizzard's plain-cornered border. At the portrait's size (62 px, inside the ring) its detail was
	-- lost; the ring can't grow (it is part of the frame's corner art). A soft shadow lifts it off the frame.
	if ButtonFrameTemplate_HidePortrait then pcall(ButtonFrameTemplate_HidePortrait, win) end
	local logo = CreateFrame("Frame", nil, win)
	logo:SetSize(LOGO_SIZE, LOGO_SIZE)
	logo:SetPoint("TOPLEFT", win, "TOPLEFT", LOGO_X, LOGO_Y)
	logo:SetFrameLevel(600)   -- above the frame's border and title bar
	local LOGO = "Interface\\AddOns\\ShamanForever\\Art\\Logo-Icon"
	logo.shadow = logo:CreateTexture(nil, "BACKGROUND")
	logo.shadow:SetTexture(LOGO)
	logo.shadow:SetVertexColor(0, 0, 0, 0.7)
	logo.shadow:SetPoint("TOPLEFT", 3, -4)
	logo.shadow:SetPoint("BOTTOMRIGHT", 3, -4)
	logo.tex = logo:CreateTexture(nil, "ARTWORK")
	logo.tex:SetTexture(LOGO)
	logo.tex:SetAllPoints()
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
	local function endResize()
		grip:SetScript("OnUpdate", nil)
		acct().optionsHeight = math.floor(win:GetHeight())
	end
	grip:SetScript("OnMouseUp", endResize)
	-- Closed mid-drag (Escape, the key binding), the release may never come: end a chip drag and a
	-- resize here, or the ghost stays on the cursor and the height follows it on reopening.
	win:HookScript("OnHide", function()
		if board.dragKey then
			board.dragKey = nil
			board.ghost:Hide()
			board.indicator:Hide()
		end
		if grip:GetScript("OnUpdate") then endResize() end
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
	buildTotemBar(newPage("totembar", "Totem bar"))
	buildElements(newPage("elements", "Elements"))
	buildShield(newPage("shield", "Shields", true))
	buildShock(newPage("shock", "Shocks", true))
	buildImbue(newPage("imbue", "Weapon Imbue", true))
	for _, def in ipairs(ns.Cooldowns.COOLDOWNS) do buildCooldown(newPage(def.key, def.spell, true), def) end
	buildProfiles(newPage("profiles", "Profiles"))
	buildAbout(newPage("about", "About"))
	buildNav()
	win:Hide()
end

-- Confirmations. data is what the question is about (a group number); action gets it.
local function confirm(which, text, button, action)
	StaticPopupDialogs[which] = {
		text = text, button1 = button, button2 = CANCEL,
		OnAccept = function(_, data) action(data) end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
end
confirm("SHAMANFOREVER_CENTER", "Move Group %s to the middle of the screen?\nIts current position is lost.", "Centre",
	function(gi) ns.centerGroup(gi) end)
confirm("SHAMANFOREVER_SPLIT", "Split Group %s into one group per element?\nPutting them back together is done by hand.", "Split up",
	function(gi) ns.splitGroup(gi) end)
confirm("SHAMANFOREVER_HIDEALL", "Hide every element in Group %s?\nEach one's Show setting becomes Hidden.", "Hide all",
	function(gi) ns.hideGroup(gi) end)

confirm("SHAMANFOREVER_RESET", "Reset profile %s to defaults?\nIts layout and every setting are lost.", "Reset",
	function() ns.Profiles.reset(); ns.say("profile reset to defaults") end)
confirm("SHAMANFOREVER_DELETE_PROFILE", "Delete profile %s?\nCharacters using it go back to Default.", "Delete",
	function() ns.Profiles.delete() end)

-- The edit box moved from dialog.editBox to dialog.EditBox / GetEditBox() over the Retail versions.
local function popupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.EditBox or dialog.editBox
end
-- A name that fails (taken, empty) asks again with the reason, keeping what was typed.
local function submitName(text)
	local action = nameAction
	nameAction = nil
	if not action then return end
	local err = action.run(text)
	if err then
		local prompt = action.retryOf or action.prompt
		C_Timer.After(0, function()
			nameAction = { prompt = prompt, retryOf = prompt, initial = text, run = action.run }
			StaticPopup_Show("SHAMANFOREVER_PROFILE_NAME", "|cffff6060" .. err:gsub("^%l", string.upper) .. ".|r\n" .. prompt)
		end)
	end
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

-- Profile sharing: one small window, in export mode (the text, selected for copying) or import mode
-- (an empty box to paste into).
local share
local function buildShare()
	local f = CreateFrame("Frame", "ShamanForeverShareFrame", UIParent, "BackdropTemplate")
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
	table.insert(UISpecialFrames, f:GetName())   -- Escape closes it

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
	-- Clicking anywhere in the box starts typing, not just on the lines of text.
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

	-- Import mode: the Import button waits for some text, and a problem shows in the note.
	e:SetScript("OnTextChanged", function(self, user)
		if f.mode == "export" then
			-- Read-only: typing puts the text back.
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

-- Several changes in one frame (a slider drag, a drop) refresh the visible page once.
local refreshQueued = false
function OP.refresh()
	if not (win and win:IsShown()) or refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if win:IsShown() and currentPage then pages[currentPage]:refresh() end
		if navDivider then navDivider.refresh() end
		if navLock then navLock.refresh() end
	end)
end

function OP.open(page, groupIndex)
	if not ns.getDB() then return end
	if not win then buildWindow() end
	-- In combat HideUIPanel is blocked (and says so); Settings then stays open under the window.
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
	if groupIndex then selectedGroup = groupIndex end
	win:Show()
	local last = acct().optionsPage
	showPage(page or currentPage or (last and pages[last] and last) or "home")
end

-- An element's own page, or the Elements overview for one without a page (test elements).
function OP.openElement(key)
	if not win then buildWindow() end
	OP.open(ELEMENT_PAGES[key] or "elements")
end

-- Scrolls a page so frame (one of its rows) sits at the top, once the page has laid out.
local function scrollTo(p, frame, after)
	C_Timer.After(0, function()
		if not frame:IsVisible() then return end
		local top, y = p.content:GetTop(), frame:GetTop()
		if top and y then p.scroll:SetVerticalScroll(math.max(0, math.min(top - y - 8, p.scroll:GetVerticalScrollRange()))) end
		if after then after() end
	end)
end

-- From an Edit General button: General, scrolled to the settings named anchor (a style's kind).
function OP.openGeneral(anchor)
	OP.open("general")
	local p = pages.general
	local f = p and p.anchors and p.anchors[anchor]
	if f then scrollTo(p, f) end
end

-- About, scrolled to one of its flashing headings, which glows briefly.
local function showAboutSection(section)
	OP.open("about")
	if not section then return end
	scrollTo(section.page, section.header, function()
		section.flash:Stop()
		section.flash:Play()
	end)
end
-- From an EXPERIMENTAL badge: About's Experimental section.
function OP.showExperimental() showAboutSection(aboutExp) end
-- From Home's Give feedback button: About's Feedback section.
function OP.showFeedback() showAboutSection(aboutFeedback) end


-- From an element's page: Layout with that group selected, scrolled to its settings, which flash.
function OP.openGroup(gi)
	board.flashPanel = true
	OP.open("layout", gi)
	if groupPanel then scrollTo(groupPanel.page, groupPanel.frame) end
end

-- Closes the window; true if it was open.
function OP.hide()
	if not (win and win:IsShown()) then return false end
	win:Hide()
	return true
end

function OP.toggle()
	if win and win:IsShown() then win:Hide() else OP.open() end
end

-- Escape > Options > AddOns > ShamanForever: a pointer to the window above.
local category
function OP.build()
	if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("ShamanForever")
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText("ShamanForever has its own options window. You can also open it by typing /sf.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(180, 26)
	button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
	button:SetText("Open options")
	button:SetScript("OnClick", function() OP.open() end)
	category = Settings.RegisterCanvasLayoutCategory(panel, "ShamanForever")
	Settings.RegisterAddOnCategory(category)
end
