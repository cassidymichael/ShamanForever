-- Options panel under Escape > Options > AddOns > Shaman Forever.
local ADDON, ns = ...

local category
local settings = {}

local function header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function checkbox(variable, label, key, tooltip, after)
	local db = ns.getDB()
	local s = Settings.RegisterProxySetting(category, "ShamanForever_" .. variable, Settings.VarType.Boolean,
		label, ns.DEFAULTS[key],
		function() return db[key] end,
		function(value) db[key] = value; after() end)
	Settings.CreateCheckbox(category, s, tooltip)
	table.insert(settings, s)
	return s
end

local function slider(variable, label, key, minV, maxV, step, fmt, tooltip, after)
	local db = ns.getDB()
	local s = Settings.RegisterProxySetting(category, "ShamanForever_" .. variable, Settings.VarType.Number,
		label, ns.DEFAULTS[key],
		function() return db[key] end,
		function(value) db[key] = value; after() end)
	local options = Settings.CreateSliderOptions(minV, maxV, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
	Settings.CreateSlider(category, s, options, tooltip)
	table.insert(settings, s)
	return s
end

local function dropdown(variable, label, key, choices, tooltip, after)
	local db = ns.getDB()
	local s = Settings.RegisterProxySetting(category, "ShamanForever_" .. variable, Settings.VarType.String,
		label, ns.DEFAULTS[key],
		function() return db[key] end,
		function(value) db[key] = value; after() end)
	local function getOptions()
		local container = Settings.CreateControlTextContainer()
		for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
		return container:GetData()
	end
	Settings.CreateDropdown(category, s, getOptions, tooltip)
	table.insert(settings, s)
	return s
end

function ns.BuildOptions()
	if category or not Settings or not Settings.RegisterVerticalLayoutCategory then return end
	local db = ns.getDB()
	category = Settings.RegisterVerticalLayoutCategory("Shaman Forever")
	local layout = SettingsPanel:GetLayout(category)

	local relayout = ns.applyLayout
	local respell = function() ns.resolveSpells(); ns.refreshAll() end

	local function pct(v) return string.format("%.0f%%", v * 100) end
	local function times(v) return string.format("%.2fx", v) end
	local function int(v) return string.format("%d", v) end

	header(layout, "Display")
	checkbox("Locked", "Lock frame", "locked",
		"Unlock to drag the icons around the screen. Lock when done so clicks pass through.", relayout)
	checkbox("CombatOnly", "Only show in combat", "combatOnly",
		"Hide the display out of combat. It always shows while the frame is unlocked so you can move it.", ns.applyVisibility)
	slider("Alpha", "Opacity", "alpha", 0.1, 1, 0.01, pct, "Transparency of the whole display.", relayout)
	slider("Scale", "Scale", "scale", 0.5, 3, 0.02, times, "Size of the whole display. Text sizes below are multiplied by this.", relayout)

	header(layout, "Layout")
	slider("IconSize", "Icon size", "iconSize", 24, 96, 1, int, "Size of each icon. Text sizes are separate.", relayout)
	slider("Spacing", "Spacing", "spacing", 0, 40, 1, int, "Gap between icons.", relayout)
	dropdown("Orientation", "Orientation", "orientation", { { "horizontal", "Row" }, { "vertical", "Column" } },
		"Lay the icons out in a row or a column.", relayout)
	dropdown("Growth", "Growth direction", "growth", { { "forward", "Right / down" }, { "backward", "Left / up" } },
		"Which way the row or column extends from the first icon.", relayout)
	-- One dropdown per slot; picking an icon swaps it with whatever was in that slot.
	local slotSettings = {}
	local function refreshSlots() for _, s in ipairs(slotSettings) do s:NotifyUpdate() end end
	local iconChoices = {}
	for _, key in ipairs(ns.ICON_KEYS) do table.insert(iconChoices, { key, ns.ICONS[key].label }) end
	for slot = 1, #ns.ICON_KEYS do
		local s = Settings.RegisterProxySetting(category, "ShamanForever_Slot" .. slot, Settings.VarType.String,
			"Position " .. slot, ns.ICON_KEYS[slot],
			function() return ns.iconOrder()[slot] end,
			function(value)
				local order = ns.iconOrder()
				local from
				for i, key in ipairs(order) do if key == value then from = i end end
				if from and from ~= slot then order[from], order[slot] = order[slot], order[from] end
				ns.applyLayout()
				refreshSlots()
			end)
		local function getOptions()
			local container = Settings.CreateControlTextContainer()
			for _, c in ipairs(iconChoices) do container:Add(c[1], c[2]) end
			return container:GetData()
		end
		Settings.CreateDropdown(category, s, getOptions, "Which icon sits in this position. Choosing one swaps it with the icon currently there.")
		table.insert(settings, s)
		table.insert(slotSettings, s)
	end

	header(layout, "Lightning Shield")
	dropdown("CountPos", "Charge number position", "countPos",
		{ { "corner", "Bottom right corner" }, { "center", "Centered" } },
		"Where the charge count sits on the shield icon.", relayout)
	slider("CountSize", "Charge number size", "countSize", 8, 64, 1, int, "Font size of the charge count.", relayout)

	checkbox("ShowBar", "Show charge bar", "showBar",
		"Blizzard aura container mode: a bar along the bottom of the icon, one segment per charge.", relayout)
	checkbox("ShowCount", "Show charge number", "showCount",
		"Blizzard aura container mode: the charge count text (Blizzard only prints it for two or more).", relayout)
	checkbox("EmptyRing", "No shield: red ring", "emptyRing", "Red ring inside the icon edge when the shield is down.", relayout)
	checkbox("EmptyGrey", "No shield: grey icon", "emptyGrey", "Desaturate the icon when the shield is down.", relayout)
	checkbox("EmptyTint", "No shield: red tint", "emptyTint", "Red tint on the icon when the shield is down.", relayout)

	header(layout, "Shock")
	local shockChoices = {}
	for _, key in ipairs(ns.SHOCK_ORDER) do table.insert(shockChoices, { key, ns.SHOCKS[key] }) end
	dropdown("Shock", "Tracked shock", "shock", shockChoices,
		"Which shock the icon shows, with its cooldown and range.", respell)
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, c in ipairs(shockChoices) do table.insert(manaChoices, c) end
	dropdown("ManaSpell", "Mana check uses", "manaSpell", manaChoices,
		"Which spell's cost decides when the icon turns blue. Always the highest rank you know.", respell)
	local lookChoices = { { "tint", "Tint" }, { "overlay", "Coloured overlay" }, { "both", "Overlay and tint" } }
	dropdown("ManaStyle", "Not enough mana look", "manaStyle", lookChoices,
		"Blue on the icon itself when you cannot afford the mana-check spell. If you are also out of range, the icon goes red instead and only the blue ring remains.", relayout)
	slider("ManaIntensity", "Mana overlay strength", "manaIntensity", 0.1, 1, 0.05, pct, "Opacity of the blue overlay.", relayout)
	slider("ManaTint", "Mana tint strength", "manaTint", 0.1, 1, 0.05, pct, "How strongly the blue tint removes the other colours.", relayout)
	slider("ManaRing", "Not enough mana ring", "manaRing", 0.1, 1, 0.05, pct,
		"A blue ring inside the icon edge whenever you cannot afford the mana-check spell. This is its opacity.", relayout)
	dropdown("RangeStyle", "Out of range look", "rangeStyle", lookChoices,
		"Red on the icon itself when your target is out of range. Takes the icon body over the mana look.", relayout)
	slider("RangeIntensity", "Range overlay strength", "rangeIntensity", 0.1, 1, 0.05, pct, "Opacity of the red overlay.", relayout)
	slider("RangeTint", "Range tint strength", "rangeTint", 0.1, 1, 0.05, pct, "How strongly the red tint removes the other colours.", relayout)
	checkbox("CDText", "Show cooldown countdown", "cdText", "Countdown numbers on the shock cooldown.", relayout)
	slider("CDTextSize", "Countdown text size", "cdTextSize", 8, 48, 1, int, "Font size of countdown numbers.", relayout)

	header(layout, "Reset")
	layout:AddInitializer(CreateSettingsButtonInitializer("Reset", "Reset to defaults", function()
		for k, v in pairs(ns.DEFAULTS) do db[k] = type(v) == "table" and CopyTable(v) or v end
		ns.resolveSpells(); ns.applyLayout(); ns.refreshAll()
		for _, s in ipairs(settings) do s:NotifyUpdate() end
		ns.say("reset to defaults")
	end, "Restores position and every option above.", true))

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if category then Settings.OpenToCategory(category:GetID()) end
end
