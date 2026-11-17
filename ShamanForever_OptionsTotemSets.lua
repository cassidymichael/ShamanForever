-- Totem sets grid
local _, ns = ...
local W = ns.Widgets
local OA = ns.OptionsArt

local TSG = {}
ns.TotemSetsPage = TSG

local TS = ns.TotemSets
local CALLS = TS.CALLS

TSG.WORDS = {
	use = "Use on the bar", useTip = "Put the bar's totem buttons, pickers and keys on this Call's totems.",
	onBar = "On the bar", onBarTip = "The bar's totem buttons, pickers and keys use this Call's totems.",
	fighting = "A Call's totems can only be changed out of combat.",
	useFighting = "This button works out of combat only. In combat, the \"Next totem set\" key still switches sets,"
		.. " as does right-clicking Call when it is on the bar.",
	noTotem = "No totem", notLearned = "No totem of this kind learned yet.",
	refused = "Currently blocked from changing Call's totems from this menu.",
}
local function callName(set) return ns.Spells.name(TS.CALL_KEYS[set]) end
local function totemName(id) return ns.Spells.nameOf(id) or ("Spell " .. tostring(id)) end
local function texture(id)
	local ok, tex = ns.try("totem sets: icon", C_Spell.GetSpellTexture, id)
	return ok and not ns.isSecret(tex) and tex or nil
end
local function learned(set) return ns.Spells.known(TS.CALL_KEYS[set]) ~= nil end

function TSG.notYet(set)
	return string.format("%s isn't learned yet. It can be learned at level %d.", callName(set), TS.LEVELS[set])
end

local cells = setmetatable({}, { __mode = "k" })
local function openMenu(c)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local set, slot, el = c.forSet, c.slot, c.el
	MenuUtil.CreateContextMenu(c, function(_, root)
		root:CreateTitle(string.format("%s totem for %s", ns.TotemBar.NAME[el], callName(set)))
		local function item(label, id)
			root:CreateRadio(label, function() return (ns.TotemBar.pickOf(slot, set) or 0) == id end,
				function() TSG.pick(set, slot, id) end)
		end
		item(TSG.WORDS.noTotem, 0)
		for _, id in ipairs(ns.Totems.knownTotems(slot)) do
			local tex = texture(id)
			item((tex and string.format("|T%s:16:16:0:0:64:64:5:59:5:59|t ", tostring(tex)) or "") .. totemName(id), id)
		end
	end)
end

function TSG.pick(set, slot, spell)
	if ns.inCombat() then
		ns.say(TSG.WORDS.fighting)
		return false
	end
	return TS.setPick(set, slot, spell)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, action)
	if event == "ACTIONBAR_SLOT_CHANGED" and not ns.isSecret(action) and type(action) == "number" and action ~= 0
		and (action < ns.TotemBar.actionFor(1, 1) or action > ns.TotemBar.actionFor(4, #CALLS)) then
		return
	end
	ns.Options.refresh()
end)
ns.registerEvent(events, "ACTIONBAR_SLOT_CHANGED")
ns.registerEvent(events, "UPDATE_MULTI_CAST_ACTIONBAR")
local function closeMenu()
	local open = Menu and Menu.GetManager and Menu.GetManager():GetOpenMenu()
	if open and cells[open:GetOwnerRegion()] then open:Close() end
end
ns.onCombatStart(function()
	ns.try("totem sets: menu", closeMenu)
	ns.Options.refresh()
end)
ns.onCombatEnd(ns.Options.refresh)

local LEVEL_WORDS = {}
for set, level in ipairs(TS.LEVELS) do LEVEL_WORDS[set] = string.format("Level %d", level) end

local HEAD_H, LINE_H, ICON, CELL, CELL_GAP, NAME_X, USE_W = 18, 34, 22, 28, 8, 30, 120

local function cellTip(c)
	GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
	local el = ns.TotemBar.NAME[c.el]
	if not c.live then
		GameTooltip:SetText(el, 1, 1, 1)
		GameTooltip:AddLine(TSG.notYet(c.forSet), nil, nil, nil, true)
	elseif not c.learned then
		GameTooltip:SetText(el, 1, 1, 1)
		GameTooltip:AddLine(TSG.WORDS.notLearned, nil, nil, nil, true)
	else
		GameTooltip:SetText(string.format("%s: %s", el, c.spell and totemName(c.spell) or TSG.WORDS.noTotem), 1, 1, 1)
		if TS.picksRefused() then
			GameTooltip:AddLine(TSG.WORDS.refused, nil, nil, nil, true)
		elseif ns.inCombat() then
			GameTooltip:AddLine(TSG.WORDS.fighting, nil, nil, nil, true)
		else
			GameTooltip:AddLine(string.format("Click to choose the %s totem %s drops.", el:lower(), callName(c.forSet)),
				nil, nil, nil, true)
		end
	end
	GameTooltip:Show()
end

local function cell(parent)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(CELL, CELL)
	c:RegisterForClicks("LeftButtonUp")
	c:SetMotionScriptsWhileDisabled(true)
	c.ground = c:CreateTexture(nil, "BACKGROUND")
	c.ground:SetAllPoints()
	c.ground:SetColorTexture(1, 1, 1, 0.06)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetPoint("TOPLEFT", 1, -1)
	c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	W.cropIcon(c.icon)
	c.none = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	c.none:SetPoint("CENTER")
	c.none:SetText("X")
	c.lit = c:CreateTexture(nil, "HIGHLIGHT")
	c.lit:SetAllPoints()
	c.lit:SetColorTexture(1, 1, 1, 0.12)
	c:SetScript("OnEnter", cellTip)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	c:SetScript("OnClick", function(self)
		if ns.inCombat() or TS.picksRefused() or not self.live then return end
		openMenu(self)
	end)
	cells[c] = true
	return c
end

local function tag(parent, text)
	local t = OA.tagBadge(parent, text)
	function t.say(words)
		t.text:SetText(words)
		t:SetWidth(t.text:GetStringWidth() + 12)
	end
	return t
end

local function line(f)
	local l = CreateFrame("Frame", nil, f)
	l:SetHeight(LINE_H)
	l.icon = l:CreateTexture(nil, "ARTWORK")
	l.icon:SetSize(ICON, ICON)
	l.icon:SetPoint("LEFT", 0, 0)
	W.cropIcon(l.icon)
	l.name = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l.name:SetPoint("LEFT", NAME_X, 0)
	l.name:SetJustifyH("LEFT")
	l.name:SetWordWrap(false)
	l.cells = {}
	for i = 1, 4 do l.cells[i] = cell(l) end
	l.use = CreateFrame("Button", nil, l, "UIPanelButtonTemplate")
	l.use:SetSize(USE_W, 22)
	l.use:SetText(TSG.WORDS.use)
	l.use:SetMotionScriptsWhileDisabled(true)
	l.use:SetScript("OnClick", function() if l.forSet then TS.switch(l.forSet) end end)
	l.use:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(TSG.WORDS.use, 1, 1, 1)
		GameTooltip:AddLine(ns.inCombat() and TSG.WORDS.useFighting or TSG.WORDS.useTip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	l.use:SetScript("OnLeave", function() GameTooltip:Hide() end)
	l.onBar = tag(l, TSG.WORDS.onBar)
	l.onBar:EnableMouse(true)
	W.setTip(l.onBar, TSG.WORDS.onBar, TSG.WORDS.onBarTip)
	l.later = tag(l, "")
	l.later:EnableMouse(true)
	l.later:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(TSG.notYet(l.forSet), 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	l.later:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return l
end

local function paintCell(c, set, el, live, learnedSlot)
	local slot = ns.TotemBar.SLOT[el]
	c.forSet, c.slot, c.el, c.live = set, slot, el, live
	c.learned = learnedSlot
	local pick, unknown = ns.TotemBar.pickOf(slot, set)
	c.spell = pick
	local off = ns.inCombat() or TS.picksRefused() or not live
	if pick then
		c.icon:SetTexture(texture(pick))
	elseif unknown then
		c.icon:SetTexture(ns.TotemBar.pickTexture(el, set))
	else
		c.icon:SetTexture(nil)
	end
	c.none:SetShown(not pick and not unknown)
	c.icon:SetDesaturated(off or not c.learned)
	c.icon:SetAlpha((off or not c.learned) and 0.5 or 1)
	c:SetEnabled(c.learned and not off)
end

function TSG.build(p)
	local TB = ns.TotemBar
	local f = p:row(HEAD_H + #CALLS * LINE_H)
	f.heads = {}
	for i = 1, 4 do
		f.heads[i] = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		f.heads[i]:SetJustifyH("CENTER")
	end
	f.lines = {}
	for n = 1, #CALLS do
		local l = line(f)
		l:SetPoint("TOPLEFT", 0, -(HEAD_H + (n - 1) * LINE_H))
		f.lines[n] = l
	end
	p:add(f, HEAD_H + #CALLS * LINE_H, nil, function()
		local width = p:width()
		local cols = TB.cfg().order
		local any = {}
		for _, el in ipairs(cols) do any[el] = #ns.Totems.knownTotems(TB.SLOT[el]) > 0 end
		local cellsW = 4 * CELL + 3 * CELL_GAP
		local cellX = math.max(NAME_X + 110, math.min(NAME_X + 200, width - cellsW - USE_W - 16))
		for i, el in ipairs(cols) do
			local h = f.heads[i]
			h:ClearAllPoints()
			h:SetPoint("BOTTOM", f, "TOPLEFT", cellX + (i - 1) * (CELL + CELL_GAP) + CELL / 2, -HEAD_H + 3)
			h:SetText(TB.NAME[el])
		end
		for set, l in ipairs(f.lines) do
			l.forSet = set
			local live, known = TS.known(set), learned(set)
			l:SetWidth(width)
			l.icon:SetTexture(texture(CALLS[set]))
			l.icon:SetDesaturated(not known)
			l.icon:SetAlpha(known and 1 or 0.5)
			l.name:SetText(callName(set))
			l.name:SetWidth(cellX - NAME_X - 8)
			if known then l.name:SetTextColor(1, 1, 1) else l.name:SetTextColor(0.5, 0.5, 0.5) end
			for i, el in ipairs(cols) do
				local c = l.cells[i]
				c:ClearAllPoints()
				c:SetPoint("LEFT", l, "LEFT", cellX + (i - 1) * (CELL + CELL_GAP), 0)
				paintCell(c, set, el, live, any[el])
			end
			local x = cellX + cellsW + 16
			local active = set == TS.active()
			l.use:ClearAllPoints()
			l.use:SetPoint("LEFT", l, "LEFT", x, 0)
			l.use:SetShown(live and not active)
			l.use:SetEnabled(not ns.inCombat())
			l.onBar:ClearAllPoints()
			l.onBar:SetPoint("LEFT", l, "LEFT", x, 0)
			l.onBar:SetShown(active)
			l.later.say(LEVEL_WORDS[set])
			l.later:ClearAllPoints()
			l.later:SetPoint("LEFT", l, "LEFT", x, 0)
			l.later:SetShown(not live)
		end
	end)
	p:text(TSG.WORDS.refused, TS.picksRefused)
end
