-- The options window's element pages: the Elements overview, and one page per element (its header
-- with a live preview, Display, Idle, its own settings, then the standard blocks), including the
-- Tremor warning's watchlist. The window, its other pages and the standard blocks are
-- ShamanForever_Options.lua's (ns.Options.kit).
local _, ns = ...

local EP = {}
ns.ElementPages = EP

local Page, K = ns.Page, ns.Options.kit
local showWhen, setTip, panelBackdrop = Page.showWhen, Page.setTip, Page.panelBackdrop
local relayout, respell, get, gopt = K.relayout, K.respell, K.get, K.gopt
local pct, int, px = Page.pct, Page.int, Page.px
local SHOW_CHOICES = K.SHOW_CHOICES
local timerSettings, gcdBlock, glowBlock, popBlock = K.timerSettings, K.gcdBlock, K.glowBlock, K.popBlock
local expiringLooks, killedBlock = K.expiringLooks, K.killedBlock

local function db() return ns.getDB() end

-- An element's own option (db.elementOpts): a row's getter (with its default, ns.elementSetting)
-- and setter; the block being built owns it.
function K.eopt(p, key, name)
	p:owns({ elem = key, name = name, after = relayout })
	return function() return ns.elementSetting(key, name) end,
		function(v) ns.elementOpts(key)[name] = v; relayout() end
end
local eopt = K.eopt
-- Its value, for what only reads it (a row shown while it's on).
local function eread(key, name) return function() return ns.elementSetting(key, name) end end

-- The elements in the options' order (the nav and the Elements list): the ones the character has
-- learned, then the ones it hasn't, then other races' racials; each band by name, A to Z, in the
-- client's language. Read when asked, so a spell learned since moves up.
local function byName()
	local keys, name = {}, ns.Look.elementName
	local band = {}
	for i, key in ipairs(ns.ELEMENT_KEYS) do
		keys[i] = key
		band[key] = ns.isLearned(key) and 0 or ns.Spells.otherRace(ns.ELEMENTS[key].race) and 2 or 1
	end
	table.sort(keys, function(a, b)
		if band[a] ~= band[b] then return band[a] < band[b] end
		local na, nb = name(a):lower(), name(b):lower()
		if na ~= nb then return na < nb end
		return a < b
	end)
	return keys
end
EP.ordered = byName

-- The Group choices: every group by name, then New group; an ungrouped element's reads Ungrouped.
-- Choosing one moves the element there (to its end) and leaves its Show as it is.
local function groupMenu(dd, key)
	pcall(dd.SetDefaultText, dd, "Ungrouped")
	dd:SetupMenu(function(_, root)
		for _, g in ipairs(db().groups) do
			root:CreateRadio(g.name, function() return ns.groupOf(key) == g end, function()
				if ns.groupOf(key) ~= g then ns.placeElement(key, g.id) end
			end)
		end
		root:CreateButton("New group", function() ns.placeElement(key, "new") end)
	end)
end

-- On an element's page, where "Hidden keeps its place" is shown as text under the control.
local SHOW_TIP_PAGE = "Choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both allow it. Everything visible shows while positioning is unlocked."
local SHOW_TIP = "When the element is drawn. Hidden keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both it and its group allow it."

------------------------------------------------------------------------
-- Elements: an overview of every element, and one page per real element under it in the nav.
------------------------------------------------------------------------
local ELEMENT_PAGES = {}   -- key -> page key, filled as element pages are built

-- The overview's controls, light enough for a table: a flat cell with a thin border and small text
-- that lights up under the mouse. A menu cell shows its value and a small arrow, and opens its menu
-- (gen, a menu generator) at the cursor.
local function tableCell(parent, width, font)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, 20)
	b:SetBackdrop(ns.BACKDROP)
	b:SetBackdropColor(1, 1, 1, 0.03)
	b:SetBackdropBorderColor(0.36, 0.29, 0.19, 0.7)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", -1, 1)
	hl:SetColorTexture(1, 0.9, 0.7, 0.08)
	b.text = b:CreateFontString(nil, "OVERLAY", font)
	b.text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.72, 0.58, 0.34, 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.36, 0.29, 0.19, 0.7) end)
	return b
end
local function menuCell(parent, width, gen)
	local b = tableCell(parent, width, "GameFontHighlightSmall")
	b.arrow = b:CreateTexture(nil, "ARTWORK")
	b.arrow:SetTexture("Interface\\Buttons\\UI-TotemBar")
	b.arrow:SetTexCoord(0.5625, 0.71875, 0.34375, 0.3828125)
	b.arrow:SetSize(10, 6)
	b.arrow:SetRotation(math.pi)   -- the art points up
	b.arrow:SetPoint("RIGHT", -6, 0)
	b.text:SetPoint("LEFT", 6, 0)
	b.text:SetPoint("RIGHT", b.arrow, "LEFT", -4, 0)
	b.text:SetJustifyH("LEFT")
	b:SetScript("OnClick", function(self)
		if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, gen) end
	end)
	return b
end

function EP.buildOverview(p)
	-- A page title and a line, then the list on its own: no block, so nothing to fold.
	p:pageTitle("Elements")
	p:text("Most of ShamanForever's HUD indicators are \"elements\", usually icon-shaped things which"
		.. " always fit inside one \"group\", and \"groups\" get moved around the screen in the unlocked"
		.. " mode.")
	-- Columns: each has a least width (what fits the window at its narrowest) and a share of any
	-- width beyond the least. Positions are worked out from the page's width on every layout.
	local COLS = {
		{ key = "name", label = "Element", min = 150, grow = 0.25, x0 = 32 },
		{ key = "group", label = "Group", min = 100, grow = 0.25, max = 200 },
		{ key = "link", label = "Group settings", min = 100, grow = 0 },
		{ key = "show", label = "Show", min = 80, grow = 0.1, max = 130 },
		{ key = "styles", label = "Own styles", min = 120, grow = 0.4 },
	}
	local GAP = 6
	local function place(width)
		local least = GAP * (#COLS - 1)
		for _, c in ipairs(COLS) do least = least + c.min end
		local extra = math.max(width - least, 0)
		local x, out = 0, {}
		for _, c in ipairs(COLS) do
			local w = c.min + extra * c.grow
			if c.max then w = math.min(w, c.max) end
			out[c.key] = { x = x, w = w }
			x = x + w + GAP
		end
		-- Width left by the capped columns goes to the last.
		local last = COLS[#COLS].key
		out[last].w = math.max(out[last].w, width - out[last].x)
		return out
	end
	local heads = {}
	do
		-- Taller than its text, which sits at its foot: a gap between the explainer and the table.
		local f = p:row(36)
		for _, c in ipairs(COLS) do
			local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			heads[c.key] = fs
			fs:SetText(c.label)
		end
		p:add(f, 36, nil, function()
			local pos = place(p:width())
			for _, c in ipairs(COLS) do
				local fs = heads[c.key]
				local inset = (c.key == "name" and 32) or (c.key == "link" and 0) or 6
				fs:ClearAllPoints()
				fs:SetPoint("BOTTOMLEFT", pos[c.key].x + inset, 4)
				fs:SetWidth(pos[c.key].w - inset)
			end
		end)
	end
	-- The styles an element has its own of (General's otherwise), by name: the timers, glow and pop
	-- it offers, from ns.Style.
	local STYLE_NAMES = { { "cooldown", "Cooldown timer" }, { "uptime", "Time left timer" },
		{ "glow", "Pulsing glow" }, { "pop", "Pop" } }
	local function ownStyles(key)
		local S, out = ns.Style, {}
		for _, k in ipairs(STYLE_NAMES) do
			local spec = S.KINDS[k[1]]
			if spec and tContains(spec.users, key) and not S.follows(key, k[1]) then table.insert(out, k[2]) end
		end
		return out
	end
	local rowKeys = byName()
	for _, key in ipairs(rowKeys) do
		local e = ns.ELEMENTS[key]
		local f = p:row(34)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(22, 22)
		icon:SetPoint("LEFT", 4, 0)
		ns.cropIcon(icon)
		local name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", 32, 0)
		name:SetJustifyH("LEFT")
		name:SetWordWrap(false)
		-- Every element is listed; one the character doesn't know yet says so (the HUD leaves it out).
		local unknown = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		unknown:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
		unknown:SetText(ns.notLearnedText(key))
		-- The Group choices: every group by name, then New group. Choosing one moves the element
		-- there (to its end) and leaves its Show as it is.
		local group = menuCell(f, 120, function(_, root)
			for _, g in ipairs(db().groups) do
				root:CreateRadio(g.name, function() return ns.groupOf(key) == g end, function()
					if ns.groupOf(key) ~= g then ns.placeElement(key, g.id) end
					ns.Options.refresh()
				end)
			end
			root:CreateButton("New group", function() ns.placeElement(key, "new"); ns.Options.refresh() end)
		end)
		local show = menuCell(f, 86, function(_, root)
			for _, c in ipairs(SHOW_CHOICES) do
				root:CreateRadio(c[2], function() return ns.showMode(key) == c[1] end, function()
					ns.setShow(key, c[1])
					ns.Options.refresh()
				end)
			end
		end)
		show:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Show")
			GameTooltip:AddLine(SHOW_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		show:HookScript("OnLeave", function() GameTooltip:Hide() end)
		local function openPage() if ELEMENT_PAGES[key] then ns.Options.open(ELEMENT_PAGES[key]) end end
		-- Its own page: its icon and name are the link, lit gold under the mouse.
		local open = CreateFrame("Button", nil, f)
		open:SetPoint("TOPLEFT", 0, 0)
		open:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 4, -8)
		open:SetScript("OnClick", openPage)
		open:SetScript("OnEnter", function() name:SetTextColor(1, 0.82, 0) end)
		open:SetScript("OnLeave", function() name:SetTextColor(1, 1, 1) end)
		-- Its group on Groups & Layout (none while ungrouped): a dim link, lit under the mouse.
		local groupOpen = CreateFrame("Button", nil, f)
		groupOpen:SetHeight(20)
		groupOpen.text = groupOpen:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		groupOpen.text:SetPoint("LEFT", 0, 0)
		groupOpen.text:SetText("Open group >")
		groupOpen.text:SetTextColor(0.6, 0.6, 0.6)
		groupOpen:SetScript("OnClick", function()
			local g = ns.groupOf(key)
			if g then ns.Options.openGroup(g.id) end
		end)
		groupOpen:SetScript("OnEnter", function(self)
			self.text:SetTextColor(1, 0.82, 0)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Group settings")
			GameTooltip:AddLine("This group's settings on the Groups & Layout page.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		groupOpen:SetScript("OnLeave", function(self)
			self.text:SetTextColor(0.6, 0.6, 0.6)
			GameTooltip:Hide()
		end)
		-- Which styles it has of its own, small text; the full list on hover.
		local styles = CreateFrame("Frame", nil, f)
		styles:EnableMouse(true)
		styles:SetHeight(20)
		styles.text = styles:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		styles.text:SetPoint("LEFT", 6, 0)
		styles.text:SetPoint("RIGHT", -2, 0)
		styles.text:SetJustifyH("LEFT")
		styles.text:SetWordWrap(false)
		styles:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Own styles")
			local own = ownStyles(key)
			if #own == 0 then
				GameTooltip:AddLine("Follows General for its timers, glow and pop.", 1, 1, 1, true)
			else
				GameTooltip:AddLine(table.concat(own, ", "), 1, 1, 1, true)
				GameTooltip:AddLine("The rest follow General.", 0.7, 0.7, 0.7, true)
			end
			GameTooltip:Show()
		end)
		styles:SetScript("OnLeave", function() GameTooltip:Hide() end)
		local SHORT = { ["Cooldown timer"] = "cooldown", ["Time left timer"] = "time left",
			["Pulsing glow"] = "glow", ["Pop"] = "pop" }
		p:add(f, 34, nil, function()
			e.paint(icon)
			local learned = ns.isLearned(key)
			local pos = place(p:width())
			name:SetWidth(pos.name.w - 36)
			name:SetText(e.label)
			name:ClearAllPoints()
			name:SetPoint("LEFT", 32, learned and 0 or 6)
			unknown:SetShown(not learned)
			icon:SetDesaturated(not learned)
			local g = ns.groupOf(key)
			group.text:SetText(g and g.name or "Ungrouped")
			local mode = ns.showMode(key)
			for _, c in ipairs(SHOW_CHOICES) do if c[1] == mode then show.text:SetText(c[2]) end end
			for _, cell in ipairs({ { group, "group" }, { show, "show" }, { groupOpen, "link" },
				{ styles, "styles" } }) do
				cell[1]:ClearAllPoints()
				cell[1]:SetPoint("LEFT", pos[cell[2]].x, 0)
				cell[1]:SetWidth(pos[cell[2]].w)
			end
			local own, short = ownStyles(key), {}
			for i, n in ipairs(own) do short[i] = SHORT[n] end
			if #own == 0 then
				styles.text:SetText("General")
				styles.text:SetTextColor(0.6, 0.6, 0.6)
			else
				styles.text:SetText("Own: " .. table.concat(short, ", "))
				styles.text:SetTextColor(1, 1, 1)
			end
			open:SetEnabled(ELEMENT_PAGES[key] ~= nil)
			groupOpen:SetShown(g ~= nil)
		end)
	end
	-- The rows follow the order again at each layout: they are the last items added.
	local rows, first = {}, #p.items - #rowKeys
	for i, key in ipairs(rowKeys) do rows[key] = p.items[first + i] end
	function p.beforeRefresh()
		for i, key in ipairs(byName()) do p.items[first + i] = rows[key] end
	end
end

-- Every element page, in one order: its header, Display (Show, Group), Idle (where it has one), its
-- own settings, then the standard blocks: the missing-look Warning, the timers (Cooldown, Time
-- left), the event blocks (Ready, Expiring, Killed early), then Pulsing glow style and Pop style,
-- each only where the element has something it applies to.
local function elementDisplay(p, key)
	ELEMENT_PAGES[key] = p.key
	p.resetAll = {
		text = function() return "Reset " .. ns.Look.elementName(key) end,
		ask = function() EP.askReset(key) end,
	}
	p:hero(key)
	p:callout("Not learned yet. It shows on screen once your character knows the spell.",
		function() return not ns.isLearned(key) and not ns.Spells.otherRace(ns.ELEMENTS[key].race) end)
	p:callout("Not your race. It shows on screen only for the races that have this spell.",
		function() return not ns.isLearned(key) and ns.Spells.otherRace(ns.ELEMENTS[key].race) end)
	p:header("Display")
	p:dropdown("Show", SHOW_TIP_PAGE, SHOW_CHOICES, function() return ns.showMode(key) end,
		function(v) ns.setShow(key, v) end, nil, 140)
	local function showDefault() return ns.elementDefault(key, "show") or "always" end
	-- Refused in combat, as by hand; checked first so ns.setShow doesn't say so too.
	p:owns({ elem = key, name = "show", label = "Show", default = showDefault, reset = function()
		if InCombatLockdown() then return false end
		ns.setShow(key, showDefault())
	end })
	p:text("Hidden keeps its place in its group.")
	-- Its menu is groupMenu's; the get only tells the row when to show another name.
	local groupRow = p:dropdown("Group", "Which group it sits in. Groups are arranged on the Groups & Layout page; ungrouped elements aren't on screen.",
		{}, function() local g = ns.groupOf(key); return g and g.id .. ":" .. g.name or "" end, function() end, nil, 140)
	groupMenu(groupRow.dropdown, key)
	local edit = CreateFrame("Button", nil, groupRow, "UIPanelButtonTemplate")
	edit:SetSize(110, 22)
	edit:SetPoint("LEFT", groupRow.dropdown, "RIGHT", 8, 0)
	edit:SetText("Group settings")
	edit:SetScript("OnClick", function() local g = ns.groupOf(key); if g then ns.Options.openGroup(g.id) end end)
	setTip(edit, "Group settings", "This group's settings on the Groups & Layout page.")
	local item = p.items[#p.items]
	local refresh = item.refresh
	item.refresh = function()
		refresh()
		edit:SetShown(ns.groupOf(key) ~= nil)
	end
end

-- Standard block: the moment a cooldown ends. A pop, and with glowTip a "use me" glow (off by
-- default). afterPop: an optional row right after Pop, before the glow (like warningBlock's first).
local function readyBlock(p, key, glowTip, afterPop)
	p:header("Ready")
	p:checkbox("Pop", "The moment the cooldown ends.", eopt(p, key, "readyPop"))
	if afterPop then afterPop() end
	if glowTip then p:checkbox("Pulsing glow", glowTip, eopt(p, key, "readyGlow")) end
	ns.Sounds.row(p, "Sound", "The moment the cooldown ends.", eopt(p, key, "readySound"))
end

-- Standard block: the look while the element has nothing going on, right under Display. What the
-- element offers comes from its def:
--   idleChoices = { { value, label, text, tip }, ... }
--                       the "Idle when" choices (setting idleWhen);
--                       text is the line saying what idle is (%s: def.idleAlso, what else keeps it
--                       out of idle), tip the dropdown's help. A choice with value "never" hides
--                       the opacity slider.
--   idleText            the line when there is no choice
--   idleExtra           a second dropdown { key, label, tip, choices } (the reagents' Running low)
local function idleBlock(p, def)
	local key, choices = def.key, def.idleChoices
	local function when() return ns.elementSetting(key, "idleWhen") end
	local function never() return choices ~= nil and when() == "never" end
	p:header("Idle")
	if choices then
		local options, tips = {}, {}
		for _, c in ipairs(choices) do
			table.insert(options, { c[1], c[2] })
			if c[4] then table.insert(tips, c[4]) end
		end
		p:text(function()
			for _, c in ipairs(choices) do
				if c[1] == when() then
					return c[3]:format(def.idleAlso or "") .. (c[1] == "never" and "."
						or ". At 0% it's hidden and keeps its place in the group.")
				end
			end
			return ""
		end)
		local whenGet, whenSet = eopt(p, key, "idleWhen")
		p:dropdown("Idle when", table.concat(tips, " "), options, whenGet, whenSet, nil, 230)
	else
		p:text((def.idleText or "Idle while it isn't up")
			.. ". At 0% it's hidden and keeps its place in the group.")
	end
	local extra = def.idleExtra
	if extra then
		local extraGet, extraSet = eopt(p, key, extra.key)
		p:dropdown(extra.label, extra.tip, extra.choices, extraGet, extraSet,
			choices and showWhen(function() return not never() end) or nil, 230)
	end
	local alphaGet, alphaSet = eopt(p, key, "idleAlpha")
	p:slider("Idle opacity", "The icon's opacity while idle.", 0, 1, 0.05, pct, alphaGet, alphaSet,
		choices and showWhen(function() return not never() end) or nil)
end

-- Standard blocks at the end of a page: the pulsing glow's and the pop's styles, General's or its
-- own, where the element has something they apply to (its effects, ns.registerElement).
local function effectBlocks(p, key)
	local e = ns.ELEMENTS[key]
	if #e.effects.glow > 0 then glowBlock(p, key, e.icon) end
	if #e.effects.pop > 0 then popBlock(p, key, e.icon, e.effects.popKind or "ready") end
end

-- Standard block: the look while something is missing. opt(name) gives a row's getter and setter;
-- names: the settings of Grey icon, Red ring and Fade in and out. first: an optional row before
-- them.
local function warningBlock(p, title, opt, names, first)
	p:header(title)
	if first then first() end
	p:checkbox("Grey icon", "Desaturate the icon.", opt(names[1]))
	p:checkbox("Red ring", "A red ring inside the icon edge.", opt(names[2]))
	p:checkbox("Fade in and out", nil, opt(names[3]))
end

-- Where a number on the icon sits (the shield's charges, a reagent count).
local COUNT_POINTS = { { "BOTTOMRIGHT", "Bottom right" }, { "BOTTOMLEFT", "Bottom left" }, { "TOPRIGHT", "Top right" },
	{ "TOPLEFT", "Top left" }, { "CENTER", "Centre" } }

-- A look choice (tint, overlay, both) greys out the strength it does not use.
local function lookUses(key, part) return function() local v = db()[key]; return v == part or v == "both" end end

local function buildShield(p, def)
	local function opt(name, after) return gopt(p, name, after) end
	elementDisplay(p, "shield")
	idleBlock(p, def)
	p:header("Tracking")
	p:cards("Track", nil, {
		{ "lightning", ns.Spells.name("lightningShield"), 136051 },
		{ "water", ns.Spells.name("waterShield"), 132315 },
		{ "either", "Either", 136051 },
	}, opt("shieldTrack", respell))
	p:text("Only one shield can be up at a time. With one chosen, the other counts as no shield.")
	-- Lightning, the default, reads a Water Shield that is up as no shield.
	p:callout(("You know %s: choose Either to count it."):format(ns.Spells.name("waterShield")),
		function() return db().shieldTrack == "lightning" and ns.Shield.knows("water") end)
	p:header("Charges")
	local bar = p:checkbox("Charge bar", "One segment per charge.", opt("showBar"))
	p:sub(bar, get("showBar"), function()
		p:slider("Bar height", nil, 1, 20, 1, px, opt("chargeBarHeight"))
		p:color("Bar colour", nil, opt("chargeBarColor"))
	end)
	local number = p:checkbox("Charge number", "The charges as a number.", opt("showCount"))
	p:sub(number, get("showCount"), function()
		local posGet, posSet = opt("countPos")
		p:dropdown("Number position", nil, COUNT_POINTS, posGet, posSet, nil, 150)
		p:slider("Number size", nil, 8, 64, 1, int, opt("countSize"))
		local last = p:checkbox("Different colour last charge", "Colours the 1, instead of plain white.",
			opt("countOne"))
		p:sub(last, get("countOne"), function()
			p:color("Last charge colour", nil, opt("countLastColor"))
		end)
	end)

	warningBlock(p, "No shield", opt, { "emptyGrey", "emptyRing", "emptyPulse" })
	p:checkbox("Red tint", "Tint the icon red.", opt("emptyTint"))
	p:checkbox("Pulsing glow", "A glow that pulses, in the Pulsing glow style.", opt("emptyGlow"))

	timerSettings(p, "Time left", "shield", "uptime")
	gcdBlock(p, "shield")
	effectBlocks(p, "shield")
end

local function buildShock(p, def)
	local function opt(name, after) return gopt(p, name, after) end
	elementDisplay(p, "shock")
	idleBlock(p, def)
	p:header("Tracking")
	local icons = { earth = 136026, flame = 135813, frost = 135849 }
	local cards = {}
	for _, key in ipairs(ns.Shock.ORDER) do table.insert(cards, { key, ns.Shock.SHOCKS[key], icons[key] }) end
	p:cards("Track", "Its cooldown and range.", cards, opt("shock", respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, key in ipairs(ns.Shock.ORDER) do table.insert(manaChoices, { key, ns.Shock.SHOCKS[key] }) end
	p:dropdown("Mana check", nil, manaChoices, opt("manaSpell", respell))
	p:text("The spell whose cost turns the icon blue when you're short of mana.")

	local looks = { { "tint", "Tint" }, { "overlay", "Overlay" }, { "both", "Both" } }
	p:header("No mana")
	p:dropdown("Look", "Out of range wins over this look.", looks, opt("manaStyle"))
	local manaOverlayGet, manaOverlaySet = opt("manaIntensity")
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, manaOverlayGet, manaOverlaySet,
		showWhen(lookUses("manaStyle", "overlay")))
	local manaTintGet, manaTintSet = opt("manaTint")
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, manaTintGet, manaTintSet, showWhen(lookUses("manaStyle", "tint")))
	p:slider("Ring", "The blue ring, shown even when out of range.", 0.1, 1, 0.05, pct, opt("manaRing"))

	p:header("Out of range")
	p:dropdown("Look", nil, looks, opt("rangeStyle"))
	local rangeOverlayGet, rangeOverlaySet = opt("rangeIntensity")
	p:slider("Overlay", nil, 0.1, 1, 0.05, pct, rangeOverlayGet, rangeOverlaySet,
		showWhen(lookUses("rangeStyle", "overlay")))
	local rangeTintGet, rangeTintSet = opt("rangeTint")
	p:slider("Tint", nil, 0.1, 1, 0.05, pct, rangeTintGet, rangeTintSet, showWhen(lookUses("rangeStyle", "tint")))
	timerSettings(p, "Cooldown", "shock", "cooldown")
	gcdBlock(p, "shock")
	readyBlock(p, "shock", "While it's off cooldown.")
	effectBlocks(p, "shock")
end

local function buildImbue(p, def)
	local function opt(name) return gopt(p, name) end
	elementDisplay(p, "imbue")
	idleBlock(p, def)
	warningBlock(p, "No imbue", opt, { "imbueMissingGrey", "imbueMissingRing", "imbuePulse" }, function()
		local cards = { { "last", "Last used", 136086 } }
		-- The client's names; " Weapon" is trimmed where it has one (English).
		for _, key in ipairs(ns.Imbue.ORDER) do table.insert(cards, { key, (ns.Imbue.IMBUES[key].name:gsub(" Weapon$", "")), ns.Imbue.IMBUES[key].icon }) end
		p:cards("Icon", nil, cards, opt("imbuePreferred"))
		p:text("The icon shown while no imbue is on.")
	end)
	p:checkbox("Pulsing glow", "A glow inside the icon that pulses.", opt("imbueGlow"))
	p:checkbox("Pop", "The moment your imbue runs out or is lost.", opt("imbuePop"))
	ns.Sounds.row(p, "Sound", "The moment your imbue runs out or is lost.", eopt(p, "imbue", "lostSound"))

	-- One Time left block: when it shows first, then its look.
	timerSettings(p, "Time left", "imbue", "uptime", nil, nil, function()
		p:slider("Show under", nil, 0, 30, 1,
			function(v) return v == 0 and "Never" or string.format("%d min", v) end, opt("imbueWarnMins"))
		p:text("Time left shows once it's below this. 0 never shows it.")
	end)
	effectBlocks(p, "imbue")
end

-- Primed: when it starts (from your cast), what spends it, and how it looks meanwhile.
local function primedBlock(p, def)
	local key = def.key
	p:header("Primed")
	if def.primed.text then p:text(def.primed.text) end
	if def.primedLooks == false then return end
	p:checkbox("Pop", "The moment it's primed.", eopt(p, key, "primedPop"))
	p:checkbox("Pulsing glow", "While it's primed.", eopt(p, key, "primedGlow"))
end

-- Reagent: the count on the icon and when it's low, then the look when there are none.
local COUNT_WHEN = { { "always", "Always" }, { "low", "When low or none" }, { "never", "Never" } }
local function reagentBlocks(p, def)
	local key = def.key
	p:header("Reagent")
	p:text("Only counted if the spell still needs one.")
	local countGet, countSet = eopt(p, key, "reagentCount")
	p:dropdown("Show count", "How many you carry, on the icon.", COUNT_WHEN, countGet, countSet, nil, 170)
	local counted = showWhen(function() return ns.elementSetting(key, "reagentCount") ~= "never" end)
	p:slider("Low at", "At this many or fewer, the count takes the low colour, and Idle can count it as running low.", 0, 10, 1, int, eopt(p, key, "reagentLow"))
	local colorGet, colorSet = eopt(p, key, "reagentColor")
	p:color("Count colour", "While you have enough.", colorGet, colorSet, counted)
	local lowGet, lowSet = eopt(p, key, "reagentLowColor")
	p:color("Low colour", "At the Low mark or below, and at none.", lowGet, lowSet, counted)
	local sizeGet, sizeSet = eopt(p, key, "reagentSize")
	p:slider("Text size", "At the default icon size; it grows with the icon.", 8, 40, 1, int, sizeGet, sizeSet, counted)
	local posGet, posSet = eopt(p, key, "reagentPos")
	p:dropdown("Position", nil, COUNT_POINTS, posGet, posSet, counted, 150)
	local xGet, xSet = eopt(p, key, "reagentX")
	p:slider("Text X offset", nil, -50, 50, 1, px, xGet, xSet, counted)
	local yGet, ySet = eopt(p, key, "reagentY")
	p:slider("Text Y offset", nil, -50, 50, 1, px, yGet, ySet, counted)
	p:header("None left")
	p:checkbox("Red ring", "A red ring inside the icon edge.", eopt(p, key, "reagentRing"))
	p:checkbox("Fade in and out", nil, eopt(p, key, "reagentPulse"))
end

-- Grounded: Grounding's early end, which means it took a spell for you.
local function groundedBlock(p, key)
	p:header("Grounded")
	p:checkbox("Flash when it takes a spell", "The totem flashes blue over its icon when it ends early: it took a spell, or was destroyed.",
		eopt(p, key, "grounded"))
	local on = showWhen(eread(key, "grounded"))
	local popGet, popSet = eopt(p, key, "groundedPop")
	p:checkbox("Pop", "The icon bursts for a moment.", popGet, popSet, on)
	local glowGet, glowSet = eopt(p, key, "groundedGlow")
	p:checkbox("Pulsing glow", "In blue.", glowGet, glowSet, on)
end

-- Expiring: a warning in the last seconds of its time left. only: the looks offered (all if nil).
local function expiringBlock(p, key, maxSecs, step, only)
	local function xget(k) return function() return ns.Timer.expireOpts(key)[k] end end
	-- A field's default: the element's own over everyone's, as ns.Timer.expireOpts reads them.
	local function xdefault(k) return function()
		local v, own = ns.Timer.EXPIRE_DEFAULTS[k], ns.elementDefault(key, "expire")
		if type(own) == "table" and type(own[k]) == type(v) then v = own[k] end
		return v
	end end
	local function xset(k)
		p:owns({ elem = key, name = "expire", field = k, default = xdefault(k), after = relayout })
		return function(v)
			local o = ns.elementOpts(key)
			if type(o.expire) ~= "table" then o.expire = {} end
			o.expire[k] = v
			relayout()
		end
	end
	p:header("Expiring")
	p:slider("Warn in the last", "Seconds before it runs out. Zero turns the warning off.", 0, maxSecs, step,
		function(v) return v == 0 and "Off" or string.format("%d s", v) end, xget("secs"), xset("secs"))
	expiringLooks(p, xget, xset, "icon", showWhen(function() return ns.Timer.expireOpts(key).secs > 0 end), only)
end

-- One page per cooldown element; the blocks depend on what the element tracks.
local function buildCooldown(p, def)
	local key = def.key
	local function opt(name) return eopt(p, key, name) end
	elementDisplay(p, key)
	idleBlock(p, def)
	if def.reagent then reagentBlocks(p, def) end
	if def.needsTotem then
		warningBlock(p, "No fire totem", opt, { "blockedGrey", "blockedRing", "blockedPulse" })
	end
	timerSettings(p, "Cooldown", key, "cooldown")
	gcdBlock(p, key)
	local timed, expires = ns.cooldownTimes(def)
	if def.needsTotem then timerSettings(p, "Fire totem's time left", key, "uptime")
	elseif def.totemSlot or def.window then timerSettings(p, "Time left", key, "uptime")
	elseif timed then timerSettings(p, "Primed time left", key, "uptime") end
	if not def.noReady then
		readyBlock(p, key, def.needsTotem and "While it's off cooldown and a fire totem is down."
			or def.readyGlow and "While it's off cooldown.", def.needsTotem and function()
				local noTotemGet, noTotemSet = opt("readyNoTotem")
				p:dropdown("Without a fire totem", "The pop when the cooldown ends with no fire totem down.",
					{ { "grey", "Greyed pop" }, { "none", "Nothing" } }, noTotemGet, noTotemSet,
					showWhen(eread(key, "readyPop")), 150)
			end or nil)
	end
	if def.primed then primedBlock(p, def) end
	if expires then
		expiringBlock(p, key, 30, 1, def.expireLooks)
		if def.ranOut then
			p:checkbox("Flash when it runs out", "Its icon, greyed under its colour, with an hourglass.", opt("ranOutFlash"))
			local on = showWhen(eread(key, "ranOutFlash"))
			local popGet, popSet = opt("ranOutPop")
			p:checkbox("Pop", "The icon bursts for a moment.", popGet, popSet, on)
			local glowGet, glowSet = opt("ranOutGlow")
			p:checkbox("Pulsing glow", "In its colour.", glowGet, glowSet, on)
		elseif def.totemSlot then
			p:checkbox("Pop when it runs out", "The totem pops and fades the moment it runs out.", opt("expiredPop"))
		end
	end
	if def.totemSlot then
		ns.Sounds.row(p, "Sound when it ends", "When it runs out or is killed. Not when you dismiss it.",
			opt("goneSound"))
	end
	if def.grounded then groundedBlock(p, key)
	elseif def.totemSlot then
		killedBlock(p, function(n) return eread(key, n) end, function(n) local _, s = opt(n); return s end, "icon",
			"Flash when it dies early")
	end
	effectBlocks(p, key)
end

-- One page per buff element (ShamanForever_Buffs.lua).
local function buildBuff(p, def)
	local key = def.key
	local function opt(name) return eopt(p, key, name) end
	elementDisplay(p, key)
	idleBlock(p, def)
	if def.reagent then reagentBlocks(p, def) end
	if def.breath then
		p:header("Under water")
		p:checkbox("Warn without it", "While your breath bar drains and it isn't up.", opt("breathWarn"))
		local on = showWhen(eread(key, "breathWarn"))
		local ringGet, ringSet = opt("breathRing")
		p:checkbox("Red ring", "A red ring inside the icon edge.", ringGet, ringSet, on)
		local pulseGet, pulseSet = opt("breathPulse")
		p:checkbox("Fade in and out", nil, pulseGet, pulseSet, on)
	end
	if def.skipLong then
		local lo, hi, step = def.skipLong[1], def.skipLong[2], def.skipLong[3]
		p:header("Track")
		local skip = p:checkbox("Skip long buffs", "Leaves out buffs that last longer than Longest buff, and buffs with no end.",
			opt("skipLong"))
		p:sub(skip, eread(key, "skipLong"), function()
			p:slider("Longest buff", "Buffs up to this long count.", lo, hi, step,
				function(v) return string.format("%d min", v) end, opt("skipLongMins"))
		end)
	end
	if def.missing then
		warningBlock(p, "Not on target", opt, { "missGrey", "missRing", "missPulse" }, function()
			p:text("While your hostile target doesn't have it.")
		end)
		p:checkbox("Pulsing glow", "A glow that pulses, in the Pulsing glow style.", opt("missGlow"))
	end
	local function procBlock()
		-- Elemental Focus's texts, unless the def has its own (the target's auras, ShamanForever_Target.lua).
		p:header(def.procHeader or ns.Spells.name("clearcasting"))
		if not def.noPop then
			p:checkbox("Pop", def.popTip or "The moment it procs.", opt("primedPop"))
		end
		p:checkbox("Pulsing glow", def.glowTip or "While it's up.", opt("primedGlow"))
	end
	-- Flame Shock: after Not on target, its time left and Expiring.
	if not def.noTimer then timerSettings(p, "Time left", key, "uptime") end
	if def.engineExpire then
		-- Flame Shock's, drawn by the engine: only what it can change in a fight.
		p:header("Expiring")
		p:slider("Warn in the last", "Seconds before it runs out. Zero turns the warning off.", 0, 10, 1,
			function(v) return v == 0 and "Off" or string.format("%d s", v) end, opt("expireSecs"))
		local warns = function() return (ns.elementSetting(key, "expireSecs") or 0) > 0 end
		local barGet, barSet = opt("expireBar")
		p:checkbox("Bar colour", "The time bar takes this colour in the last seconds.", barGet, barSet, showWhen(warns))
		local colorGet, colorSet = opt("expireBarColor")
		p:color("Colour", nil, colorGet, colorSet,
			showWhen(function() return warns() and ns.elementSetting(key, "expireBar") end))
		local textGet, textSet = opt("expireText")
		p:checkbox("Red countdown", "The countdown turns red in the last seconds.", textGet, textSet, showWhen(warns))
	end
	if def.proc and not def.noGlow then procBlock()
	elseif not def.proc then expiringBlock(p, key, 120, 5) end
	effectBlocks(p, key)
end

-- Tremor Totem's watchlist: a box that searches the list and adds a name, Add target, the list (a
-- remove button on each mob) and a count. The list is a ScrollBox, which recycles its rows, so
-- hundreds of mobs take a dozen frames.
local MOB_ROW_H, MOB_ROWS, MOB_LIST_W = 22, 9, 640
local function mobList(p)
	local T = ns.Tremor
	local listH = MOB_ROW_H * MOB_ROWS + 8
	local H = 32 + listH + 32
	local f = p:row(H)
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(240, 20)
	box:SetPoint("TOPLEFT", 8, -5)
	box:SetAutoFocus(false)
	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	box.hint:SetPoint("LEFT", 2, 0)
	box.hint:SetText("Search, or type a name to add")
	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	add:SetSize(70, 22)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetText("Add")
	setTip(add, "Add", "Puts the name in the box on the list.")
	local addTarget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	addTarget:SetSize(110, 22)
	addTarget:SetPoint("LEFT", add, "RIGHT", 6, 0)
	addTarget:SetText("Add target")
	setTip(addTarget, "Add target", "Puts the mob you have targeted on the list.")
	local ownOnly = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	ownOnly:SetSize(24, 24)
	ownOnly.Text:SetFontObject("GameFontHighlight")
	ownOnly.Text:SetText("Only mobs you added")
	setTip(ownOnly, "Only mobs you added", "Hides the default list's mobs.")

	-- As wide as the page, up to MOB_LIST_W: in a wide window a longer line reads no better.
	local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panelBackdrop(panel)
	panel:SetPoint("TOPLEFT", 0, -32)
	panel:SetSize(MOB_LIST_W, listH)
	ownOnly:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(ownOnly.Text:GetStringWidth() + 4), 29)
	local sb = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	sb:SetPoint("TOPLEFT", 4, -4)
	sb:SetPoint("BOTTOMRIGHT", -22, 4)
	local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", sb, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 6, 0)
	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("No matches. Add puts the name on the list.")

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(MOB_ROW_H)
	view:SetElementInitializer("Button", function(row, r)
		if not row.name then
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.05)
			row.x = CreateFrame("Button", nil, row)
			row.x:SetSize(20, 20)
			row.x:SetPoint("RIGHT", -2, 0)
			row.x:SetNormalFontObject("GameFontNormal")
			row.x:SetHighlightFontObject("GameFontHighlight")
			row.x:SetText("X")
			row.x:SetScript("OnClick", function(self) T.remove(self.lower) end)
			setTip(row.x, "Remove", "Takes this mob off the list.")
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", 6, 0)
			row.name:SetPoint("RIGHT", row, "CENTER", 0, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			row.info:SetPoint("LEFT", row, "CENTER", 8, 0)
			row.info:SetPoint("RIGHT", row.x, "LEFT", -6, 0)
			row.info:SetJustifyH("LEFT")
			row.info:SetWordWrap(false)
		end
		row.name:SetText(r.name)
		local info = {}
		if r.zone then table.insert(info, r.zone) end
		if r.effects ~= "" then table.insert(info, r.effects) end
		if r.own then table.insert(info, "added") end
		row.info:SetText(table.concat(info, "  ·  "))
		row.x.lower = r.lower
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(sb, bar, view)

	local count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -10)
	local restore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	restore:SetSize(180, 22)
	restore:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -5)
	restore:SetText("Restore removed defaults")
	setTip(restore, "Restore removed defaults", "Puts back the mobs you removed from the default list. Mobs you added stay as they are.")
	restore:SetScript("OnClick", function() T.restore() end)

	local shown = 0   -- rows matching the search
	local listW       -- the row's width at the page's last layout (the panels' padding included)
	local function fill()
		panel:SetWidth(math.min(listW or p:width(), MOB_LIST_W))
		local text = box:GetText()
		box.hint:SetShown(text == "" and not box:HasFocus())
		local list = T.rows(text, ownOnly:GetChecked())
		shown = #list
		sb:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
		empty:SetShown(shown == 0)
		local c = T.counts()
		local parts = { string.format("%d mobs", c.mobs) }
		if c.added > 0 then table.insert(parts, string.format("%d added", c.added)) end
		if c.removed > 0 then table.insert(parts, string.format("%d removed from the defaults", c.removed)) end
		count:SetText(table.concat(parts, ", "))
		restore:SetEnabled(c.removed > 0)
	end
	local function addTyped()
		T.add(box:GetText())
		box:SetText("")
	end
	ownOnly:SetScript("OnClick", fill)
	box:SetScript("OnTextChanged", fill)
	box:SetScript("OnEditFocusGained", fill)
	box:SetScript("OnEditFocusLost", fill)
	-- Enter adds only a name the list doesn't have; while the search finds mobs it just closes.
	box:SetScript("OnEnterPressed", function(self)
		if shown == 0 then addTyped() end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	add:SetScript("OnClick", addTyped)
	addTarget:SetScript("OnClick", function() T.addTarget() end)
	return p:add(f, H, nil, function() listW = p:width(); fill() end)
end

-- A line that reads as a link and opens another part of the options.
local function linkLine(p, text, tip, onClick)
	local f = p:row(22)
	local b = CreateFrame("Button", nil, f)
	b:SetPoint("LEFT", 4, 0)
	b:SetNormalFontObject("GameFontNormalSmall")
	b:SetHighlightFontObject("GameFontHighlightSmall")
	b:SetText(text)
	b:SetSize(b:GetFontString():GetStringWidth() + 4, 18)
	b:SetScript("OnClick", onClick)
	setTip(b, text, tip)
	return p:add(f, 22)
end

-- Tremor Totem's page (ShamanForever_Tremor.lua).
local WORD_POS = { { "below", "Below the icon" }, { "above", "Above the icon" }, { "center", "On the icon" } }
local TREMOR_IDLE_WHEN = { { "nowarning", "No warning" }, { "notdown", "Totem not down and no warning" } }
local function buildTremor(p)
	local key = "tremor"
	local function opt(name) return eopt(p, key, name) end
	elementDisplay(p, key)
	p:header("Idle")
	p:text("Idle while nothing warns. At 0% it's hidden and keeps its place in the group.")
	local whenGet, whenSet = opt("idleWhen")
	p:dropdown("Idle when", "No warning: also while your Tremor Totem is down. Totem not down and no warning: its time left shows while it's down.",
		TREMOR_IDLE_WHEN, whenGet, whenSet, nil, 250)
	p:slider("Idle opacity", "The icon's opacity while idle.", 0, 1, 0.05, pct, opt("idleAlpha"))
	p:header("Warn when")
	p:checkbox("Your target is on the list", nil, opt("tremorTarget"))
	p:checkbox("A mob on the list is near", "Its nameplate is on screen.", opt("tremorPlates"))
	p:text("Needs enemy nameplates on.", showWhen(eread(key, "tremorPlates")))
	p:checkbox("You're feared, charmed or asleep", "And for 10 s after, in case it comes again.", opt("tremorFeared"))
	p:text("The game hides party members' crowd control, so this covers only you.")
	p:text("None of these while your Tremor Totem is down, or while you're dead, on a flight path or in a vehicle.")
	p:header("Tremor warning watchlist")
	p:callout("In dungeons and raids the game hides mob names from addons, so the watchlist can't work there. "
		.. "Only \"You're feared, charmed or asleep\" can, when it's on.")
	p:text("Mobs that cast fear, charm or sleep.")
	mobList(p)
	linkLine(p, "Suggest a mob for the default list", "Opens Feedback, on the About page.", function() ns.Options.showFeedback() end)
	timerSettings(p, "Time left", key, "uptime", nil,
		"Its time left while it's down. With the default Idle (\"No warning\", 0%) it isn't seen.")
	p:header("When it warns")
	p:checkbox("Pop", "The moment it starts warning.", opt("alertPop"))
	p:checkbox("Pulsing glow", "While it warns.", opt("alertGlow"))
	p:checkbox("Text", "Shows \"" .. ns.Tremor.WORD .. "\" by the icon.", opt("alertText"))
	local text = showWhen(eread(key, "alertText"))
	local sizeGet, sizeSet = opt("wordSize")
	p:slider("Text size", "At the default icon size; it grows with the icon.", 8, 40, 1, int, sizeGet, sizeSet, text)
	local colorGet, colorSet = opt("wordColor")
	p:color("Text colour", nil, colorGet, colorSet, text)
	local posGet, posSet = opt("wordPos")
	p:dropdown("Position", nil, WORD_POS, posGet, posSet, text, 160)
	local xGet, xSet = opt("wordX")
	p:slider("Text X offset", nil, -100, 100, 1, px, xGet, xSet, text)
	local yGet, ySet = opt("wordY")
	p:slider("Text Y offset", nil, -100, 100, 1, px, yGet, ySet, text)
	ns.Sounds.row(p, "Sound", "The moment it starts warning.", opt("alertSound"))
	effectBlocks(p, key)
end

-- Each kind of element's page (the registry's kind); it gets the element's def.
local PAGE = { shield = buildShield, shock = buildShock, imbue = buildImbue, cooldown = buildCooldown, buff = buildBuff,
	tremor = buildTremor }

-- Maelstrom Weapon's page (ShamanForever_Maelstrom.lua): its stacks, then the five-stack look.
local function buildMaelstrom(p, def)
	local key = def.key
	local function opt(name) return eopt(p, key, name) end
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Stacks")
	p:checkbox("Stack bar", "One segment per stack.", opt("stackBar"))
	local barOn = showWhen(eread(key, "stackBar"))
	local heightGet, heightSet = opt("stackBarHeight")
	p:slider("Bar height", nil, 1, 20, 1, px, heightGet, heightSet, barOn)
	local barColorGet, barColorSet = opt("stackBarColor")
	p:color("Bar colour", nil, barColorGet, barColorSet, barOn)
	p:checkbox("Stack number", nil, opt("stackCount"))
	local numberOn = showWhen(eread(key, "stackCount"))
	local posGet, posSet = opt("countPos")
	p:dropdown("Number position", nil, { { "corner", "Corner" }, { "center", "Centre" } }, posGet, posSet, numberOn)
	local sizeGet, sizeSet = opt("countSize")
	p:slider("Number size", nil, 8, 40, 1, int, sizeGet, sizeSet, numberOn)
	local fullGet, fullSet = opt("fullCount")
	p:checkbox("Colour at five", "The number takes its own colour at five stacks.", fullGet, fullSet, numberOn)
	local fullColorGet, fullColorSet = opt("fullCountColor")
	p:color("Five colour", nil, fullColorGet, fullColorSet,
		showWhen(function() return ns.elementSetting(key, "stackCount") and ns.elementSetting(key, "fullCount") end))
	timerSettings(p, "Time left", key, "uptime")
	p:header("Five stacks")
	p:checkbox("Pop", "The moment it reaches five.", opt("fullPop"))
	p:checkbox("Pulsing glow", "While at five.", opt("fullGlow"))
	effectBlocks(p, key)
end
PAGE.maelstrom = buildMaelstrom

-- Every element's page, in the order the options list them.
local pageObjects = {}   -- key -> its page
function EP.build(newPage)
	for _, key in ipairs(byName()) do
		local e = ns.ELEMENTS[key]
		local build = e.kind and PAGE[e.kind]
		if build then
			local p = newPage(key, e.label, true)
			pageObjects[key] = p
			build(p, e.def)
		end
	end
end

-- The page key of an element's own page, nil for one without.
function EP.pageOf(key) return ELEMENT_PAGES[key] end

-- Every setting on an element's page back to its default, after a confirm.
function EP.askReset(key)
	local p = pageObjects[key]
	if p then p:askReset("every " .. ns.Look.elementName(key) .. " setting") end
end
