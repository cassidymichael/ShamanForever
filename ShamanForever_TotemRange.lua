-- Totem bar: out of range. Whether you are getting your own totem's buff, per slot.
--
-- Nothing can measure the distance to a totem, and in combat every aura is secret to addon code
-- (every buff reads ContextuallySecret, and GetPlayerAuraBySpellID returns nothing in combat; tested
-- 2026-09-26). So, as for the shield, Blizzard's CustomAuraContainer does the reading: per totem slot
-- an aura slot filtered to "HELPFUL|PLAYER" (only buffs you cast) and to the buffs of that element's
-- totems. Blizzard shows its button (green) while you have the buff, in combat too. Under it sits our
-- "out of range" mark (red), shown only while one of your buff totems is down in the slot (the slot's
-- duration through a curve, and which totem it is from our own cast).
-- * Nothing addon-side may change the button, or the alpha of anything above it, in combat: the
--   container hangs off the bar (changed out of combat only) and is anchored to the secure slot
--   button, never placed inside the slot's look, whose alpha changes in combat.
-- * A buff lingers a few seconds after you leave a totem's range, so "out of range" shows late.
-- * Totems that give you no buff (Searing, Earthbind, Tremor, ...) get no mark.
-- * The same buff from two shamans doesn't stack: when another shaman's is the one on you, yours
--   reads out of range. Showing theirs too (a third colour) was tried and dropped (2026-09-26):
--   Blizzard's parts can't be hidden in combat, so it also showed on slots holding other totems.

local _, ns = ...
local TB = ns.TotemBar
local R = {}
TB.range = R
local isSecret = ns.isSecret

-- The totems that buff the player, per element: the totem spell (any rank) and its buff on the player,
-- every rank. IDs are Classic's; Forever has shown 8076 (Strength of Earth) and 5672 (Healing
-- Stream). A rank not listed is learned out of combat by the client's name for the buff (learn).
local BUFF_TOTEMS = {
	earth = {
		{ totem = 8075, buffs = { 8076, 8162, 8163, 10441, 25362 } },          -- Strength of Earth
		{ totem = 8071, buffs = { 8072, 8156, 8157, 10403, 10404, 10405 } },   -- Stoneskin
	},
	fire = {
		{ totem = 8181, buffs = { 8182, 10476, 10477 } },                      -- Frost Resistance
	},
	water = {
		{ totem = 5394, buffs = { 5672, 6371, 6372, 10460, 10461 } },          -- Healing Stream
		{ totem = 5675, buffs = { 5677, 10491, 10493, 10494 } },               -- Mana Spring
		{ totem = 8184, buffs = { 8185, 10534, 10535 } },                      -- Fire Resistance
	},
	air = {
		{ totem = 8835, buffs = { 8836, 10626, 25360 } },                      -- Grace of Air
		{ totem = 10595, buffs = { 10596, 10598, 10599 } },                    -- Nature Resistance
		{ totem = 15107, buffs = { 15108, 15109, 15110 } },                    -- Windwall
		{ totem = 25908, buffs = { 25909 } },                                  -- Tranquil Air
	},
}

local buffIDs = {}      -- element -> { [buff spell ID] = true }: what its aura slot matches
local buffTotem = {}    -- totem spell ID -> whether it buffs the player (cached; ranks by the client's name)
for el, list in pairs(BUFF_TOTEMS) do
	buffIDs[el] = {}
	for _, e in ipairs(list) do
		for _, id in ipairs(e.buffs) do buffIDs[el][id] = true end
	end
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

------------------------------------------------------------------------
-- Frames: per slot, a strip along the top edge. Our red part (plain) under Blizzard's aura container,
-- whose button draws the green part (made out of combat, on first use).
------------------------------------------------------------------------
-- The red part: two nested frames, one gated by "a buff totem of yours is down" (plain), one by the
-- slot's time left (a curve, possibly secret). Both are ours and hold nothing of Blizzard's.
local function makeMark(s)
	local b = s.button
	local gate = CreateFrame("Frame", nil, TB.frame)
	gate:SetFrameLevel(b:GetFrameLevel() + 9)
	gate:EnableMouse(false)
	gate:SetAlpha(0)
	local m = CreateFrame("Frame", nil, gate)
	m:SetAllPoints()
	m:SetAlpha(0)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetAllPoints()
	s.rangeGate, s.rangeMark = gate, m
end

-- Blizzard's part over our red: an aura slot in the element's container (a list, so another part
-- would be a line here).
local PARTS = {
	{ key = "own", filter = "HELPFUL|PLAYER", color = "rangeIn", level = 1 },
}

-- A part's look (out of combat, or from Blizzard's init). Under the colour, opaque, the slice of the
-- buff's icon that the strip covers (a totem's buff has the totem's icon): whatever is below is
-- always hidden, so the colours can be see-through, down to not shown at all.
local function styleButton(s, part)
	local c, p = TB.cfg(), s.rangeParts[part.key]
	ns.try("totem range: style", function()
		p.button:SetSize(s.rangeW, s.rangeH)
		local share = math.min(s.rangeH / math.max(s.rangeSize, 1), 1)
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.08 + 0.84 * share)   -- the slot's icon crop, top part
		local k = c[part.color]
		p.over.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
	end)
end

-- Called by Blizzard (untainted) once, right after it creates the part's button.
local function initButton(s, part, button)
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	button:SetFrameLevel(s.rangeContainer:GetFrameLevel() + part.level)
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
	-- The buff's icon (Blizzard sets it), cropped to the strip by styleButton.
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	button:SetIcon(icon)
	-- Our colour on the button: it shows exactly when Blizzard shows the button.
	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:SetFrameLevel(button:GetFrameLevel() + 1)
	over.bg = over:CreateTexture(nil, "ARTWORK")
	over.bg:SetAllPoints()
	s.rangeParts[part.key] = { button = button, icon = icon, over = over }
	if s.rangeW then styleButton(s, part) end
end

local function styleButtons(s)
	for _, part in ipairs(PARTS) do
		if s.rangeParts[part.key] then styleButton(s, part) end
	end
end

local function makeContainer(s)
	s.rangeParts, s.rangeSlots = {}, {}
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", "ShamanForeverRange" .. TB.NAME[s.el], TB.frame, "CustomAuraContainerTemplate")
		c:SetFrameLevel(s.button:GetFrameLevel() + 10)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)
		s.rangeContainer = c
		-- Each part on its own: one the client refuses (a filter it doesn't take) leaves the other.
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

-- Size, place and colour both parts (out of combat). The height is in physical pixels, so it stays
-- crisp at any scale (as borders are).
local function place(s, size)
	local c, b, gate = TB.cfg(), s.button, s.rangeGate
	gate:ClearAllPoints()
	gate:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
	local _, physicalHeight = GetPhysicalScreenSize()
	local px = (768 / (physicalHeight or 768)) / gate:GetEffectiveScale()
	local w, h = size, c.rangeHeight * px
	gate:SetSize(w, h)
	local k = c.rangeOut
	s.rangeMark.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
	s.rangeW, s.rangeH, s.rangeSize = w, h, size
	local ct = s.rangeContainer
	if not ct then return end
	ct:ClearAllPoints()
	ct:SetPoint("TOPLEFT", gate, "TOPLEFT", 0, 0)
	ct:SetSize(w, h)
	ct:Show()
	styleButtons(s)
end

local function applyFilter(s)
	local c = s.rangeContainer
	if not c or InCombatLockdown() then return end
	for _, part in ipairs(PARTS) do
		if s.rangeSlots[part.key] then
			ns.try("totem range: filter", c.SetAuraSlotCandidateFilters, c, part.key, { includeSpellIDs = CopyTable(buffIDs[s.el]) })
		end
	end
end

-- Buff ranks not in the list: out of combat your own buffs are readable, and one whose name is the
-- client's name for a listed buff is another rank of it (locale-free: both names are the client's).
local names = {}   -- the client's buff name -> element
local function learn()
	if InCombatLockdown() or not TB.isShaman() or not enabled() then return end
	local ok, secret = ns.safe(C_Secrets and C_Secrets.ShouldAurasBeSecret)
	if ok and (isSecret(secret) or secret) then return end
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

------------------------------------------------------------------------
-- Called by the totem bar
------------------------------------------------------------------------
-- layout (out of combat): make, place or hide everything.
function R.layout(size)
	local want = enabled() and TB.isShaman()
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		local on = want and s.button:IsShown()
		if on and not s.rangeGate then makeMark(s) end
		if on and not s.rangeContainer and not s.rangeError then makeContainer(s) end
		if s.rangeGate then s.rangeGate:SetShown(on) end
		if s.rangeContainer and not on then s.rangeContainer:Hide() end
		if on then place(s, size); applyFilter(s) end
	end
	learn()
end

-- draw (any time): the mark's gate, from which totem of yours is down.
function R.draw(s)
	if not s.rangeGate then return end
	local on = s.down and enabled() and isBuffTotem(s.el, TB.downSpell(s.slot))
	s.rangeGate:SetAlpha(on and 1 or 0)
	R.alphas(s)
end

-- alphas (ten times a second while totems are down): the mark only while the totem has time left.
function R.alphas(s)
	local m = s.rangeMark
	if not m then return end
	local d = s.dur
	if d and ns.CURVE_LIVE then
		local ok, a = ns.try("totem range: time", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		m:SetAlpha(ok and a or 0)
	else m:SetAlpha(0) end
end

local ev = CreateFrame("Frame")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", learn)
