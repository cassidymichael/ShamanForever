-- Maelstrom Weapon options page
local _, ns = ...

local Page, K = ns.Page, ns.Options.kit
local showWhen, int, px = Page.showWhen, Page.int, Page.px
local elementDisplay, idleBlock, lookBlocks = K.elementDisplay, K.idleBlock, K.lookBlocks
local activeBlock, timerSettings, eopt, eread = K.activeBlock, K.timerSettings, K.eopt, K.eread
local eslider = K.eslider

local function buildMaelstrom(p, def)
	local key = def.key
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Stacks")
	p:checkbox("Stack bar", "One segment per stack.", eopt(p, key, "count", "bar"))
	local barOn = showWhen(eread(key, "count", "bar"))
	eslider(p, key, "Bar height", nil, px, barOn, "count", "barHeight")
	local barColorGet, barColorSet = eopt(p, key, "count", "barColor")
	p:color("Bar colour", nil, barColorGet, barColorSet, barOn)
	p:checkbox("Stack number", nil, eopt(p, key, "count", "number"))
	local numberOn = showWhen(eread(key, "count", "number"))
	local posGet, posSet = eopt(p, key, "count", "pos")
	p:dropdown("Number position", nil, { { "BOTTOMRIGHT", "Corner" }, { "CENTER", "Centre" } }, posGet, posSet, numberOn)
	eslider(p, key, "Number size", nil, int, numberOn, "count", "size")
	local markGet, markSet = eopt(p, key, "count", "mark")
	p:checkbox("Colour at five", "The number takes its own colour at five stacks.", markGet, markSet, numberOn)
	local markColorGet, markColorSet = eopt(p, key, "count", "markColor")
	p:color("Five colour", nil, markColorGet, markColorSet, showWhen(function()
		return ns.elementSetting(key, "count", "number") and ns.elementSetting(key, "count", "mark")
	end))
	timerSettings(p, "Time left", key, "uptime")
	activeBlock(p, key, { title = "Five stacks", tips = { pop = "The moment it reaches five.", glow = "While at five." } })
	lookBlocks(p, key)
end

ns.registerKind("maelstrom", { page = buildMaelstrom })
