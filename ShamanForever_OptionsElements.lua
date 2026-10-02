-- Element pages
local _, ns = ...

local EP = {}
ns.ElementPages = EP

local K = ns.Options.kit
local SHOW_CHOICES = K.SHOW_CHOICES
local timerSettings, gcdBlock = K.timerSettings, K.gcdBlock
local elementDisplay, idleBlock, lookBlocks, reagentBlocks = K.elementDisplay, K.idleBlock, K.lookBlocks, K.reagentBlocks
local warnBlock, readyBlock, activeBlock = K.warnBlock, K.readyBlock, K.activeBlock
local expiringBlock, killedBlock = K.expiringBlock, K.killedBlock

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

-- A kind made of parts: Display and Idle, its slots' standard blocks with its parts' words, then the
-- look blocks
local OWN = {
	reagent = function(p, def) reagentBlocks(p, def) end,
	toggle = function(p, def, b) K.toggleBlock(p, def.key, b) end,
}
local SLOT = {
	own = function(p, def, list)
		for _, b in ipairs(list) do
			local name = type(b) == "table" and b[1] or b
			OWN[name](p, def, b)
		end
	end,
	warn = function(p, def, o) warnBlock(p, def.key, o) end,
	cooldown = function(p, def, title) timerSettings(p, title, def.key, "cooldown") end,
	gcd = function(p, def) gcdBlock(p, def.key) end,
	uptime = function(p, def, title) timerSettings(p, title, def.key, "uptime") end,
	ready = function(p, def, o) readyBlock(p, def.key, o) end,
	active = function(p, def, o) activeBlock(p, def.key, o) end,
	expire = function(p, def, o) expiringBlock(p, def.key, o) end,
	killed = function(p, def, o) killedBlock(p, def.key, o) end,
}
local function partsPage(p, def)
	local key = def.key
	local kind = ns.ELEMENTS[key].kind
	elementDisplay(p, key)
	idleBlock(p, def)
	for _, slot in ipairs(ns.Kinds.get(kind).slots) do
		local words = ns.Kinds.slot(kind, def, slot)
		if words ~= nil then SLOT[slot](p, def, words) end
	end
	lookBlocks(p, key)
end

-- An element's page builder: its kind's own, else the parts page for a kind made of parts
local function builder(key)
	local e = ns.ELEMENTS[key]
	local k = e and e.kind and ns.Kinds.get(e.kind)
	return k and (k.page or (k.parts and partsPage)) or nil
end

local pageObjects = {}
function EP.register(newPage)
	for _, key in ipairs(byName()) do
		local e, build = ns.ELEMENTS[key], builder(key)
		if build then
			newPage(key, e.label, true, function(p)
				pageObjects[key] = p
				build(p, e.def)
			end)
		end
	end
end

function EP.pageOf(key) return builder(key) and key or nil end

function EP.askReset(key)
	local p = pageObjects[key]
	if p then p:askReset("every " .. ns.Look.elementName(key) .. " setting") end
end

ns.Options.registerPage("elements", { title = "Elements", icon = ns.Options.ART .. "Elements.tga", order = 70,
	build = EP.buildOverview })
