-- Maelstrom Weapon options page
local _, ns = ...

local Page, K = ns.Page, ns.Options.kit
local int, px = Page.int, Page.px
local elementDisplay, idleBlock, styleBlocks = K.elementDisplay, K.idleBlock, K.styleBlocks
local activeBlock, timerSettings, eopt, eread = K.activeBlock, K.timerSettings, K.eopt, K.eread
local eslider = K.eslider

local function buildMaelstrom(p, def)
	local key = def.key
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Stacks")
	local bar = p:checkbox("Stack bar", "One segment per stack.", eopt(p, key, "count", "bar"))
	p:sub(bar, eread(key, "count", "bar"), function()
		eslider(p, key, "Bar height", nil, px, nil, "count", "barHeight")
		p:color("Bar colour", nil, eopt(p, key, "count", "barColor"))
	end)
	local number = p:checkbox("Stack number", nil, eopt(p, key, "count", "number"))
	p:sub(number, eread(key, "count", "number"), function()
		local POS = { { "BOTTOMRIGHT", "Corner" }, { "CENTER", "Centre" } }
		p:dropdown("Number position", nil, POS, eopt(p, key, "count", "pos"))
		eslider(p, key, "Number size", nil, int, nil, "count", "size")
		local mark = p:checkbox("Colour at five", "The number takes its own colour at five stacks.",
			eopt(p, key, "count", "mark"))
		p:sub(mark, eread(key, "count", "mark"), function()
			p:color("Five colour", nil, eopt(p, key, "count", "markColor"))
		end)
	end)
	activeBlock(p, key, { title = "5 stacks",
		tips = { pop = "The moment it reaches five.", glow = "While at five." } })
	styleBlocks(p, key, function() timerSettings(p, "Time left", key, "uptime") end)
end

ns.registerKind("maelstrom", { page = buildMaelstrom })
