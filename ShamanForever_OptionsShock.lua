-- Shocks options page
local _, ns = ...
local W = ns.Widgets

local Page, K = ns.Page, ns.Options.kit
local showWhen, pct = Page.showWhen, Page.pct
local elementDisplay, idleBlock, styleBlocks = K.elementDisplay, K.idleBlock, K.styleBlocks
local readyBlock, timerSettings, gcdBlock, eopt = K.readyBlock, K.timerSettings, K.gcdBlock, K.eopt
local eslider, respell = K.eslider, K.respell

-- The marks' sides as the Shocks' group lays them out
local SIDE_LABEL = { above = "Above", below = "Below", right = "Right", left = "Left" }
local function sideChoices()
	return { { "above", SIDE_LABEL[W.attachSide("shock", "above")] },
		{ "below", SIDE_LABEL[W.attachSide("shock", "below")] } }
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

	p:header("On target")
	p:text("A small icon while your shock is on your hostile target, with its time left.")
	local anyOn = {}
	for _, m in ipairs(SK.MARKS) do
		local get, set = eopt(p, key, "marks", m.key)
		p:checkbox(SK.SHOCKS[m.key], nil, get, set)
		p:text(SK.SHOCKS[m.key] .. ": not learned yet.", function() return get() and not SK.knows(m.key) end)
		table.insert(anyOn, get)
	end
	local marksShown = showWhen(function()
		for _, get in ipairs(anyOn) do if get() then return true end end
		return false
	end)
	local sideGet, sideSet = eopt(p, key, "marks", "side")
	p:dropdown("Side", nil, sideChoices, sideGet, sideSet, marksShown, 140)
	eslider(p, key, "Size", "Of the icon's size.", pct, marksShown, "marks", "size")
	eslider(p, key, "Gap", "From the icon, at the default icon size; it grows with the icon.", Page.px, marksShown,
		"marks", "gap")

	K.castBlocks(p, key, { power = function(on)
		local manaChoices = { { "tracked", "Tracked shock" } }
		for _, shock in ipairs(SK.ORDER) do table.insert(manaChoices, { shock, SK.SHOCKS[shock] }) end
		local get, set = eopt(p, key, "manaSpell", nil, respell)
		p:dropdown("Mana check", nil, manaChoices, get, set, showWhen(on), 180)
		p:text("The spell whose cost turns the icon blue when you're short of mana.", showWhen(on))
	end })
	readyBlock(p, key)
	styleBlocks(p, key, function()
		timerSettings(p, "Cooldown", key, "cooldown")
		gcdBlock(p, key)
	end)
end

ns.registerKind("shock", { page = buildShock })
