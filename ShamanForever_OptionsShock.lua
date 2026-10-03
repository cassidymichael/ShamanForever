-- Shocks options page
local _, ns = ...
local E = ns.Elements

local Page, K = ns.Page, ns.Options.kit
local showWhen, pct = Page.showWhen, Page.pct
local elementDisplay, idleBlock, styleBlocks = K.elementDisplay, K.idleBlock, K.styleBlocks
local readyBlock, timerSettings, gcdBlock, eopt = K.readyBlock, K.timerSettings, K.gcdBlock, K.eopt
local eslider, respell = K.eslider, K.respell

-- A shock state's look uses overlay or tint
local function lookUses(state, part)
	return function()
		local v = E.setting("shock", state, "look")
		return v == part or v == "both"
	end
end

local function buildShock(p, def)
	local key = "shock"
	elementDisplay(p, key)
	idleBlock(p, def)
	p:header("Tracking")
	local SK = ns.Shock
	local cards = {}
	for _, shock in ipairs(SK.ORDER) do
		table.insert(cards, { shock, SK.SHOCKS[shock], SK.ICONS[shock] })
	end
	p:cards("Track", "Its cooldown and range.", cards, eopt(p, key, "track", nil, respell))
	local manaChoices = { { "tracked", "Tracked shock" } }
	for _, shock in ipairs(SK.ORDER) do table.insert(manaChoices, { shock, SK.SHOCKS[shock] }) end
	p:dropdown("Mana check", nil, manaChoices, eopt(p, key, "manaSpell", nil, respell))
	p:text("The spell whose cost turns the icon blue when you're short of mana.")

	local looks = { { "tint", "Tint" }, { "overlay", "Overlay" }, { "both", "Both" } }
	p:header("No mana")
	p:dropdown("Show as", "Out of range wins over this.", looks, eopt(p, key, "mana", "look"))
	eslider(p, key, "Overlay", nil, pct, showWhen(lookUses("mana", "overlay")), "mana", "overlay")
	eslider(p, key, "Tint", nil, pct, showWhen(lookUses("mana", "tint")), "mana", "tint")
	eslider(p, key, "Ring", "The blue ring, shown even when out of range.", pct, nil, "mana", "ring")

	p:header("Out of range")
	p:dropdown("Show as", nil, looks, eopt(p, key, "range", "look"))
	eslider(p, key, "Overlay", nil, pct, showWhen(lookUses("range", "overlay")), "range", "overlay")
	eslider(p, key, "Tint", nil, pct, showWhen(lookUses("range", "tint")), "range", "tint")
	timerSettings(p, "Cooldown", key, "cooldown")
	gcdBlock(p, key)
	readyBlock(p, key)
	styleBlocks(p, key)
end

ns.registerKind("shock", { page = buildShock })
