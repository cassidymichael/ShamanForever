-- Totem bar: out of range
-- Nothing can measure the distance to a totem and buffs are secret in combat, so per slot an aura
-- slot (HELPFUL|PLAYER, that element's buffs) lets Blizzard's container show a green strip while
-- you have the buff. Under it, our red "out of range" mark shows only while one of your buff totems
-- is down in the slot and Blizzard's part is there to cover it; until auras are readable the strip
-- stays off (red alone would always read out of range).
-- Nothing addon-side may change the button in combat: the container hangs off the strip's holder,
-- anchored to the secure slot button.
-- The buff lingers after the totem goes and after leaving range, so "out of range" shows late.
-- Totems without a buff get no mark. Another shaman's same buff makes yours read out of range.

local _, ns = ...
local TB = ns.TotemBar
local R = {}
TB.range = R
local isSecret = ns.isSecret

-- Totems that buff the player: the totem spell and its buff, every rank. IDs are Classic's; a rank
-- not listed is learned by the client's buff name (learn)
local BUFF_TOTEMS = {
	earth = {
		{ totem = 8075, buffs = { 8076, 8162, 8163, 10441, 25362 } },   -- Strength of Earth
		{ totem = 8071, buffs = { 8072, 8156, 8157, 10403, 10404, 10405 } },   -- Stoneskin
	},
	fire = {
		{ totem = 8181, buffs = { 8182, 10476, 10477 } },   -- Frost Resistance
	},
	water = {
		{ totem = 5394, buffs = { 5672, 6371, 6372, 10460, 10461 } },   -- Healing Stream
		{ totem = 5675, buffs = { 5677, 10491, 10493, 10494 } },   -- Mana Spring
		{ totem = 8184, buffs = { 8185, 10534, 10535 } },   -- Fire Resistance
	},
	air = {
		{ totem = 8835, buffs = { 8836, 10626, 25360 } },   -- Grace of Air
		{ totem = 10595, buffs = { 10596, 10598, 10599 } },   -- Nature Resistance
		{ totem = 15107, buffs = { 15108, 15109, 15110 } },   -- Windwall
	},
}

local buffIDs = {}
local buffTotem = {}
for el, list in pairs(BUFF_TOTEMS) do
	buffIDs[el] = {}
	local all = {}
	for _, e in ipairs(list) do
		table.insert(all, e.totem)
		for _, id in ipairs(e.buffs) do buffIDs[el][id] = true; table.insert(all, id) end
	end
	ns.Spells.addCheck(el .. " totems and buffs", all)
end

local function enabled() return ns.getDB() ~= nil and TB.cfg().range end

local function isBuffTotem(el, id)
	if type(id) ~= "number" or isSecret(id) then return false end
	local v = buffTotem[id]
	if v == nil then
		v = false
		for _, e in ipairs(BUFF_TOTEMS[el] or {}) do
			if ns.Spells.same(id, e.totem) then v = true end
		end
		buffTotem[id] = v
	end
	return v
end

-- Frames: per slot, our red part under Blizzard's container (made while auras are readable)
local function makeMark(s)
	local b = s.button
	local hold = CreateFrame("Frame", nil, TB.frame)
	hold:SetAllPoints(b)
	hold:EnableMouse(false)
	s.rangeHold = hold
	local gate = CreateFrame("Frame", nil, hold)
	gate:SetFrameLevel(b:GetFrameLevel() + TB.RANGE_LEVEL)
	gate:EnableMouse(false)
	gate:SetAlpha(0)
	local m = CreateFrame("Frame", nil, gate)
	m:SetAllPoints()
	m:SetAlpha(0)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetAllPoints()
	ns.Looks.followMask(s.vis, m.bg)
	s.rangeGate, s.rangeMark = gate, m
end

local previewOn = false

local PARTS = {
	{ key = "own", filter = "HELPFUL|PLAYER", color = "rangeIn", level = 1 },
}

-- partLive keeps the mark dark until our mark and Blizzard's part are styled alike (a layout can't
-- reach the part while auras are secret)
local function styledFor(s)
	return TB.skin.current().key .. ":" .. tostring(s.rangeW) .. "x" .. tostring(s.rangeH)
end

-- Under the colour, the slice of the buff's icon the strip covers (opaque): what's below is always
-- hidden, so colours can be see-through
local function styleButton(s, part)
	local c, p = TB.cfg(), s.rangeParts[part.key]
	local ok = ns.try("totem range: style", function()
		p.button:SetSize(s.rangeW, s.rangeH)
		local share = math.min(s.rangeH / math.max(s.rangeSize, 1), 1)
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.08 + 0.84 * share)
		if TB.skin.styleRangeButton(p, s) then return end
		local k = c[part.color]
		p.over.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
	end)
	s.rangeStyled = ok and styledFor(s) or nil
end

local function initButton(s, part, button)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	button:SetFrameLevel(s.rangeContainer:GetFrameLevel() + part.level)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button:SetIcon(icon)
	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:SetFrameLevel(button:GetFrameLevel() + 1)
	over.bg = over:CreateTexture(nil, "ARTWORK")
	over.bg:SetAllPoints()
	s.rangeParts[part.key] = { button = button, icon = icon, over = over }
	if s.rangeW then styleButton(s, part) end
	if previewOn then icon:SetAlpha(0); over:SetAlpha(0) end
end

local function styleButtons(s)
	for _, part in ipairs(PARTS) do
		if s.rangeParts[part.key] then styleButton(s, part) end
	end
end

-- Preview: hide our parts on Blizzard's button (never the container), back at once when it ends
function R.preview(on)
	previewOn = on
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		for _, part in ipairs(PARTS) do
			local p = s.rangeParts and s.rangeParts[part.key]
			if p then
				-- p.icon and p.over sit on Blizzard's aura button, which can be forbidden while auras are secret:
				-- guarded so a refusal can't break the preview's start
				ns.try("totem range: preview", function()
					p.icon:SetAlpha(on and 0 or 1)
					p.over:SetAlpha(on and 0 or 1)
				end)
			end
		end
	end
end

local function makeContainer(s)
	s.rangeParts, s.rangeSlots = {}, {}
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", "ShamanForeverRange" .. TB.NAME[s.el], s.rangeHold, "CustomAuraContainerTemplate")
		c:SetFrameLevel(s.button:GetFrameLevel() + TB.RANGE_LEVEL + 1)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)
		s.rangeContainer = c
		-- Each part on its own, so one the client refuses can't stop the rest
		for _, part in ipairs(PARTS) do
			s.rangeSlots[part.key] = ns.try("totem range: " .. part.key .. " slot", c.AddAuraSlot, c, part.key, part.filter, {
				candidateFilters = { includeSpellIDs = CopyTable(buffIDs[s.el]) },
				initializeFrame = function(button) initButton(s, part, button) end,
			})
		end
	end)
	if not ok then
		s.rangeError = tostring(err)
		ns.noteError("totem range: container", err)
		if s.rangeContainer then s.rangeContainer:Hide() end
	end
end

local function partLive(s)
	return s.rangeShown and not s.rangeError and s.rangeParts.own ~= nil and s.rangeSlots.own == true
		and s.rangeStyled == styledFor(s)
end

local function place(s, size, ownOnly)
	local c, b, gate, o = TB.cfg(), s.button, s.rangeGate, s.inset or 0
	gate:ClearAllPoints()
	local x, y, w, h = TB.skin.markRect(gate, size, o)
	if not x then x, y, w, h = o, -o, size - 2 * o, ns.linePx(gate, c.rangeHeight) end
	gate:SetPoint("TOPLEFT", b, "TOPLEFT", x, y)
	gate:SetSize(w, h)
	if not TB.skin.paintMark(s.rangeMark, w, h, s.vis) then
		local k = c.rangeOut
		s.rangeMark.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
	end
	s.rangeW, s.rangeH, s.rangeSize = w, h, size - 2 * o
	local ct = s.rangeContainer
	if not ct or ownOnly then return end
	ct:ClearAllPoints()
	ct:SetPoint("TOPLEFT", gate, "TOPLEFT", 0, 0)
	ct:SetSize(w, h)
	ct:SetAlpha(1)
	ct:Show()
	s.rangeShown = true
	styleButtons(s)
end

local function applyFilter(s)
	local c = s.rangeContainer
	if not c or InCombatLockdown() or ns.aurasSecret() then return end
	for _, part in ipairs(PARTS) do
		if s.rangeSlots[part.key] then
			ns.try("totem range: filter", c.SetAuraSlotCandidateFilters, c, part.key, { includeSpellIDs = CopyTable(buffIDs[s.el]) })
		end
	end
end

-- Ranks not listed: a buff whose name is the client's name for a listed buff is another rank of it
local names = {}
local function learn()
	if InCombatLockdown() or not ns.isClass() or not enabled() then return end
	if ns.aurasSecret() then return end
	if next(names) == nil then
		for el, list in pairs(BUFF_TOTEMS) do
			for _, e in ipairs(list) do
				for _, id in ipairs(e.buffs) do
					local n = ns.Spells.nameOf(id)
					if n then names[n] = el end
				end
			end
		end
	end
	for i = 1, 40 do
		local aok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL|PLAYER")
		if not aok or not a then break end
		local el = not isSecret(a.name) and names[a.name]
		local id = a.spellId
		if el and not isSecret(id) and type(id) == "number" and not buffIDs[el][id] then
			buffIDs[el][id] = true
			applyFilter(TB.slots[el])
		end
	end
end

function R.layout(size)
	-- Blizzard's containers refuse addon calls while auras are secret: their part waits, the layout
	-- reruns after
	local blocked = ns.deferWhileAurasSecret("totem range layout", function() R.layout(size) end)
	local want = enabled() and ns.isClass()
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		local on = want and s.button:IsShown()
		if on and not s.rangeGate then makeMark(s) end
		if not blocked and on and not s.rangeContainer and not s.rangeError then makeContainer(s) end
		if s.rangeGate then s.rangeGate:SetShown(on) end
		if not blocked and s.rangeContainer and not on then s.rangeContainer:Hide(); s.rangeShown = false end
		if on then
			place(s, size, blocked)
			if not blocked then applyFilter(s) end
		end
		R.refresh(s)
	end
	if not blocked then learn() end
end

-- The holder: shown while one of your buff totems is down in the slot, so a buff lingering after its
-- totem goes can't keep Blizzard's part lit. Out of combat its alpha stays 1 and a state driver
-- hides it, showing it as combat starts (an addon Show on a frame holding Blizzard's button is
-- dropped in combat); in combat its alpha hides it. The red is held by the same frame.
local EMPTY = "[combat] show; hide"
local function showStrip(s, on)
	local h = s.rangeHold
	if InCombatLockdown() then
		ns.try("totem range: holder alpha", h.SetAlpha, h, on and 1 or 0)
		return
	end
	h:SetAlpha(1)
	if on then
		if s.rangeDriven then
			UnregisterStateDriver(h, "visibility")
			s.rangeDriven = false
		end
		h:Show()
	elseif not s.rangeDriven then
		local ok, err = pcall(RegisterStateDriver, h, "visibility", EMPTY)
		if ok then s.rangeDriven = true else ns.noteError("totem range: holder", err) end
	end
end

local function buffTotemDown(s)
	return s.down and isBuffTotem(s.el, ns.Totems.downSpell(s.slot))
end

-- The mark's gate: only over Blizzard's part (red alone would always say out of range)
function R.refresh(s)
	if not s.rangeGate then return end
	local on = enabled() and partLive(s) and buffTotemDown(s)
	s.rangeGate:SetAlpha(on and 1 or 0)
	showStrip(s, on)
	R.drawTimeLeft(s)
end

function R.drawTimeLeft(s)
	local m = s.rangeMark
	if not m then return end
	local d = s.dur
	if d and ns.CURVE_LIVE then
		local ok, a = ns.try("totem range: time", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		m:SetAlpha(ok and a or 0)
	else m:SetAlpha(0) end
end

-- Called by the totem bar's start
function R.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ev:SetScript("OnEvent", learn)
	ns.onCombatEnd(function()
		for _, el in ipairs(TB.ELEMENTS) do R.refresh(TB.slots[el]) end
	end)
	-- Before the lockdown: drop any holder whose slot has no buff totem of ours down (a lingering buff
	-- from a totem that went out of combat would show at the pull)
	ns.onCombatStart(function()
		for _, el in ipairs(TB.ELEMENTS) do
			local s = TB.slots[el]
			local h = s.rangeHold
			if h and not buffTotemDown(s) then
				ns.try("totem range: holder alpha", h.SetAlpha, h, 0)
			end
		end
	end)
end
