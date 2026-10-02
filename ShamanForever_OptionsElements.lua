-- Element pages
local _, ns = ...

local EP = {}
ns.ElementPages = EP

local Page, K = ns.Page, ns.Options.kit
local showWhen, setTip, panelBackdrop = Page.showWhen, Page.setTip, Page.panelBackdrop
local respell, get, gopt = K.respell, K.get, K.gopt
local pct, int, px = Page.pct, Page.int, Page.px
local SHOW_CHOICES = K.SHOW_CHOICES
local timerSettings, gcdBlock = K.timerSettings, K.gcdBlock
local eopt, eread, COUNT_POINTS = K.eopt, K.eread, K.COUNT_POINTS
local elementDisplay, idleBlock, readyBlock, lookBlocks = K.elementDisplay, K.idleBlock, K.readyBlock, K.lookBlocks
local warningBlock, primedBlock, reagentBlocks = K.warningBlock, K.primedBlock, K.reagentBlocks
local groundedBlock, expiringBlock, procBlock = K.groundedBlock, K.expiringBlock, K.procBlock
local killedBlock = K.killedBlock

local function db() return ns.getDB() end

-- Learned first, then not learned, then other races' racials; each by name.
local function byName()
	local keys, band, lower = {}, {}, {}
	for i, key in ipairs(ns.ELEMENT_KEYS) do
		keys[i] = key
		band[key] = ns.isLearned(key) and 0 or ns.Spells.otherRace(ns.ELEMENTS[key].race) and 2 or 1
		lower[key] = ns.Look.elementName(key):lower()
	end
	table.sort(keys, function(a, b)
		if band[a] ~= band[b] then return band[a] < band[b] end
		if lower[a] ~= lower[b] then return lower[a] < lower[b] end
		return a < b
	end)
	return keys
end
EP.ordered = byName


local SHOW_TIP = "When the element is drawn. Hidden keeps its place in its group, so choosing Always or In combat again puts it back where it was. Groups have their own Show on the Groups & Layout page; an element shows only when both it and its group allow it."

-- Elements overview
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
	p:pageTitle("Elements")
	p:text("Most of ShamanForever's HUD indicators are \"elements\", usually icon-shaped things which"
		.. " always fit inside one \"group\", and \"groups\" get moved around the screen in the unlocked"
		.. " mode.")
	local COLS = {
		{ key = "name", label = "Element", min = 150, grow = 0.25, x0 = 32 },
		{ key = "group", label = "Group", min = 100, grow = 0.25, max = 200 },
		{ key = "link", label = "Group settings", min = 100, grow = 0 },
		{ key = "show", label = "Show", min = 80, grow = 0.1, max = 130 },
		{ key = "styles", label = "Own styles", min = 120, grow = 0.4 },
	}
	local GAP = 6
	local placed, placedW
	local function place(width)
		if width == placedW then return placed end
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
		local last = COLS[#COLS].key
		out[last].w = math.max(out[last].w, width - out[last].x)
		placed, placedW = out, width
		return out
	end
	local heads = {}
	do
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
	local STYLE_NAMES = { { "cooldown", "Cooldown timer" }, { "uptime", "Time left timer" },
		{ "glow", "Pulsing glow" }, { "pop", "Pop" }, { "border", "Border" }, { "frame", "Frame" } }
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
		local unknown = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		unknown:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
		unknown:SetText(ns.notLearnedText(key))
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
		local function openPage() if EP.pageOf(key) then ns.Options.open(EP.pageOf(key)) end end
		local open = CreateFrame("Button", nil, f)
		open:SetPoint("TOPLEFT", 0, 0)
		open:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", 4, -8)
		open:SetScript("OnClick", openPage)
		open:SetScript("OnEnter", function() name:SetTextColor(1, 0.82, 0) end)
		open:SetScript("OnLeave", function() name:SetTextColor(1, 1, 1) end)
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
				GameTooltip:AddLine("Follows Global styles for its timers, glow, pop, border and frame.", 1, 1, 1, true)
			else
				GameTooltip:AddLine(table.concat(own, ", "), 1, 1, 1, true)
				GameTooltip:AddLine("The rest follow Global styles.", 0.7, 0.7, 0.7, true)
			end
			GameTooltip:Show()
		end)
		styles:SetScript("OnLeave", function() GameTooltip:Hide() end)
		local SHORT = { ["Cooldown timer"] = "cooldown", ["Time left timer"] = "time left",
			["Pulsing glow"] = "glow", ["Pop"] = "pop", ["Border"] = "border", ["Frame"] = "frame" }
		local cells = { { group, "group" }, { show, "show" }, { groupOpen, "link" }, { styles, "styles" } }
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
			for _, cell in ipairs(cells) do
				cell[1]:ClearAllPoints()
				cell[1]:SetPoint("LEFT", pos[cell[2]].x, 0)
				cell[1]:SetWidth(pos[cell[2]].w)
			end
			local own, short = ownStyles(key), {}
			for i, n in ipairs(own) do short[i] = SHORT[n] end
			if #own == 0 then
				styles.text:SetText("Global")
				styles.text:SetTextColor(0.6, 0.6, 0.6)
			else
				styles.text:SetText("Own: " .. table.concat(short, ", "))
				styles.text:SetTextColor(1, 1, 1)
			end
			open:SetEnabled(EP.pageOf(key) ~= nil)
			groupOpen:SetShown(g ~= nil)
		end)
	end
	local rows, first = {}, #p.items - #rowKeys
	for i, key in ipairs(rowKeys) do rows[key] = p.items[first + i] end
	function p.beforeRefresh()
		for i, key in ipairs(byName()) do p.items[first + i] = rows[key] end
	end
end







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
	local soundGet, soundSet = eopt(p, "shield", "removedSound")
	ns.Sounds.row(p, "Sound", "When the shield goes: charges spent, cancelled or run out.", soundGet,
		function(v) soundSet(v); ns.Shield.applyRemovedSound() end, nil, ns.Sounds.fileChoices)

	timerSettings(p, "Time left", "shield", "uptime")
	gcdBlock(p, "shield")
	lookBlocks(p, "shield")
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
	lookBlocks(p, "shock")
end

local function buildImbue(p, def)
	local function opt(name) return gopt(p, name) end
	elementDisplay(p, "imbue")
	idleBlock(p, def)
	warningBlock(p, "No imbue", opt, { "imbueMissingGrey", "imbueMissingRing", "imbuePulse" }, function()
		local cards = { { "last", "Last used", 136086 } }
		-- " Weapon" is trimmed from the client's names (English).
		for _, key in ipairs(ns.Imbue.ORDER) do table.insert(cards, { key, (ns.Imbue.IMBUES[key].name:gsub(" Weapon$", "")), ns.Imbue.IMBUES[key].icon }) end
		p:cards("Icon", nil, cards, opt("imbuePreferred"))
		p:text("The icon shown while no imbue is on.")
	end)
	p:checkbox("Pulsing glow", "A glow inside the icon that pulses.", opt("imbueGlow"))
	p:checkbox("Pop", "The moment your imbue runs out or is lost.", opt("imbuePop"))
	ns.Sounds.row(p, "Sound", "The moment your imbue runs out or is lost.", eopt(p, "imbue", "lostSound"))

	timerSettings(p, "Time left", "imbue", "uptime", nil, nil, function()
		p:slider("Show under", nil, 0, 30, 1,
			function(v) return v == 0 and "Never" or string.format("%d min", v) end, opt("imbueWarnMins"))
		p:text("Time left shows once it's below this. 0 never shows it.")
	end)
	lookBlocks(p, "imbue")
end





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
	lookBlocks(p, key)
end

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
	if def.proc and not def.noGlow then procBlock(p, def, opt)
	elseif not def.proc then expiringBlock(p, key, 120, 5) end
	lookBlocks(p, key)
end

-- Tremor watchlist: a ScrollBox recycles its rows, so hundreds of mobs take a dozen frames.
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

	local shown = 0
	local listW
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
	box:SetScript("OnEnterPressed", function(self)
		if shown == 0 then addTyped() end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	add:SetScript("OnClick", addTyped)
	addTarget:SetScript("OnClick", function() T.addTarget() end)
	return p:add(f, H, nil, function() listW = p:width(); fill() end)
end

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
	lookBlocks(p, key)
end

local PAGE = { shield = buildShield, shock = buildShock, imbue = buildImbue, cooldown = buildCooldown, buff = buildBuff,
	tremor = buildTremor }

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
	lookBlocks(p, key)
end
PAGE.maelstrom = buildMaelstrom

local pageObjects = {}
function EP.register(newPage)
	for _, key in ipairs(byName()) do
		local e = ns.ELEMENTS[key]
		local build = e.kind and PAGE[e.kind]
		if build then
			newPage(key, e.label, true, function(p)
				pageObjects[key] = p
				build(p, e.def)
			end)
		end
	end
end

function EP.pageOf(key)
	local e = ns.ELEMENTS[key]
	return e and e.kind and PAGE[e.kind] and key or nil
end

function EP.askReset(key)
	local p = pageObjects[key]
	if p then p:askReset("every " .. ns.Look.elementName(key) .. " setting") end
end
