-- Weapon Imbue options page
local _, ns = ...

local K = ns.Options.kit
local elementDisplay, idleBlock, lookBlocks = K.elementDisplay, K.idleBlock, K.lookBlocks
local warnBlock, timerSettings, eopt, eslider = K.warnBlock, K.timerSettings, K.eopt, K.eslider

local function buildImbue(p, def)
	local key = "imbue"
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Icon")
	local cards = { { "last", "Last used", 136086 } }
	-- " Weapon" is trimmed from the client's names (English).
	for _, imbue in ipairs(ns.Imbue.ORDER) do
		local m = ns.Imbue.IMBUES[imbue]
		table.insert(cards, { imbue, (m.name:gsub(" Weapon$", "")), m.icon })
	end
	p:cards("Icon", nil, cards, eopt(p, key, "icon"))
	p:text("The icon shown while no imbue is on.")
	local lost = "The moment your imbue runs out or is lost."
	warnBlock(p, key, { title = "No imbue", tips = { pop = lost, sound = lost } })

	timerSettings(p, "Time left", key, "uptime", nil, nil, function()
		local function mins(v) return v == 0 and "Never" or string.format("%d min", v) end
		eslider(p, key, "Show under", nil, mins, nil, "showUnderMins")
		p:text("Time left shows once it's below this. 0 never shows it.")
	end)
	lookBlocks(p, key)
end

ns.registerKind("imbue", { page = buildImbue })
