-- Weapon Imbue options page
local _, ns = ...

local K = ns.Options.kit
local elementDisplay, idleBlock, styleBlocks = K.elementDisplay, K.idleBlock, K.styleBlocks
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
	p:header("Running low")
	local function mins(v) return v == 0 and "Never" or string.format("%d min", v) end
	eslider(p, key, "Show under", nil, mins, nil, "showUnderMins")
	p:text("Its time left shows once it's below this, and Idle counts it as running low. 0 never shows it.")
	K.lookRows(p, key, "expire", { tips = { glow = "While it's running low." } },
		ns.Page.showWhen(function() return ns.Elements.setting(key, "showUnderMins") > 0 end))
	local lost = "The moment your imbue runs out or is lost."
	warnBlock(p, key, { title = "No imbue", tips = { pop = lost, sound = lost } })
	K.castBlocks(p, key)
	styleBlocks(p, key, function() timerSettings(p, "Time left", key, "uptime") end)
end

ns.registerKind("imbue", { page = buildImbue })
