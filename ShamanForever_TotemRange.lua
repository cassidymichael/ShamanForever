-- Totem bar: out of range. Whether you are getting your own totem's buff, per slot.
--
-- Nothing can measure the distance to a totem, and in combat every aura is secret to addon code
-- (every buff reads ContextuallySecret, and GetPlayerAuraBySpellID returns nothing in combat; tested
-- 2026-09-26). So, as for the shield, Blizzard's CustomAuraContainer does the reading: per totem slot
-- an aura slot filtered to "HELPFUL|PLAYER" (only buffs you cast) and to the buffs of that element's
-- totems. Blizzard shows its button (green) while you have the buff, in combat too. Under it sits our
-- "out of range" mark (red), shown only while one of your buff totems is down in the slot (the slot's
-- duration through a curve, and which totem it is from our own cast) and Blizzard's part is there to
-- cover it. Blizzard's part isn't made or shown while auras are secret (a login or /reload in combat
-- or in a PvP match): until then the strip stays off, as the red alone would always read "out of range".
-- * Nothing addon-side may change the button in combat. The container hangs off the strip's own
--   holder (R.refresh says when that shows) and is anchored to the secure slot button, never placed
--   inside the slot's look, whose alpha changes in combat.
-- * A totem's buff also lingers a moment after the totem goes (dismissed, killed, run out), and
--   Blizzard's part shows it that long: so the holder hides the strip while no buff totem of yours
--   is down in the slot.
-- * A buff lingers a few seconds after you leave a totem's range, so "out of range" shows late.
-- * Totems that give you no buff (Searing, Earthbind, Tremor, ...) get no mark.
-- * The same buff from two shamans doesn't stack: when another shaman's is the one on you, yours
--   reads out of range. Showing theirs too (a third colour) doesn't work:
--   Blizzard's parts can't be hidden in combat, so it also showed on slots holding other totems.

local _, ns = ...
local TB = ns.TotemBar
local R = {}
TB.range = R
local isSecret = ns.isSecret

-- The totems that buff the player, per element: the totem spell (any rank) and its buff on the player,
-- every rank. IDs are Classic's; Forever has shown 8076 (Strength of Earth) and 5672 (Healing
-- Stream). A rank not listed is learned by the client's name for the buff while auras are readable
-- (learn).
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
		-- Tranquil Air (25908) isn't on Forever's client (spell ID self-check, 2026-09-26).
	},
}

local buffIDs = {}      -- element -> { [buff spell ID] = true }: what its aura slot matches
local buffTotem = {}    -- totem spell ID -> whether it buffs the player (cached; ranks by the client's name)
for el, list in pairs(BUFF_TOTEMS) do
	buffIDs[el] = {}
	local all = {}   -- for the spell ID self-check
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

------------------------------------------------------------------------
-- Frames: per slot, a strip along the top edge. Our red part (plain) under Blizzard's aura container,
-- whose button draws the green part (made while auras are readable, on first use).
------------------------------------------------------------------------
-- The red part: two nested frames, one gated by "a buff totem of yours is down" (plain), one by the
-- slot's time left (a curve, possibly secret). Both are ours and hold nothing of Blizzard's.
local function makeMark(s)
	local b = s.button
	-- The holder of the whole strip: the gate and Blizzard's container (R.refresh shows and hides it).
	local hold = CreateFrame("Frame", nil, TB.frame)
	hold:SetAllPoints(b)
	hold:EnableMouse(false)
	s.rangeHold = hold
	local gate = CreateFrame("Frame", nil, hold)
	gate:SetFrameLevel(b:GetFrameLevel() + TB.RANGE_LEVEL)   -- under the GCD sweep and the timer
	gate:EnableMouse(false)
	gate:SetAlpha(0)
	local m = CreateFrame("Frame", nil, gate)
	m:SetAllPoints()
	m:SetAlpha(0)
	m.bg = m:CreateTexture(nil, "ARTWORK")
	m.bg:SetAllPoints()
	ns.Looks.followMask(s.vis, m.bg)   -- a rounded or cut-corner icon's shape
	s.rangeGate, s.rangeMark = gate, m
end

-- Preview mode (ShamanForever_Preview.lua, called from TB.preview through R.preview): whether our
-- own parts on Blizzard's button should stay hidden, including one made while it's on.
local previewOn = false

-- Blizzard's part over our red: an aura slot in the element's container (a list, so another part
-- would be a line here).
local PARTS = {
	{ key = "own", filter = "HELPFUL|PLAYER", color = "rangeIn", level = 1 },
}

-- A part's look (while auras are readable, or from Blizzard's init). Under the colour, opaque, the
-- slice of the buff's icon that the strip covers (a totem's buff has the totem's icon): whatever is
-- below is always hidden, so the colours can be see-through, down to not shown at all. The bar's
-- Look can draw it its own way (TB.skin.styleRangeButton).
local function styleButton(s, part)
	local c, p = TB.cfg(), s.rangeParts[part.key]
	ns.try("totem range: style", function()
		p.button:SetSize(s.rangeW, s.rangeH)
		local share = math.min(s.rangeH / math.max(s.rangeSize, 1), 1)
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.08 + 0.84 * share)   -- the slot's icon crop, top part
		if TB.skin.styleRangeButton(p, s) then return end
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
	-- A mask for it, made now (the button takes one only as it is made): plain, hiding nothing,
	-- until a Look that rounds the slots' icons gives it their shape (TB.skin.styleRangeButton).
	local mask = button:CreateMaskTexture()
	mask:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	if not pcall(icon.AddMaskTexture, icon, mask) then mask = nil end
	button:SetIcon(icon)
	-- Our colour on the button: it shows exactly when Blizzard shows the button.
	local over = CreateFrame("Frame", nil, button)
	over:SetAllPoints()
	over:SetFrameLevel(button:GetFrameLevel() + 1)
	over.bg = over:CreateTexture(nil, "ARTWORK")
	over.bg:SetAllPoints()
	s.rangeParts[part.key] = { button = button, icon = icon, over = over, mask = mask }
	if s.rangeW then styleButton(s, part) end
	if previewOn then icon:SetAlpha(0); over:SetAlpha(0) end
end

local function styleButtons(s)
	for _, part in ipairs(PARTS) do
		if s.rangeParts[part.key] then styleButton(s, part) end
	end
end

-- Preview mode (ShamanForever_Preview.lua, called from TB.preview): hide our own parts on
-- Blizzard's button (never the container itself, R.layout may stay blocked while auras are secret
-- and never reach it) so a real green strip can't sit on the preview's picture, and bring them
-- back the moment the preview ends -- with no layout needed in between.
function R.preview(on)
	previewOn = on
	for _, el in ipairs(TB.ELEMENTS) do
		local s = TB.slots[el]
		for _, part in ipairs(PARTS) do
			local p = s.rangeParts and s.rangeParts[part.key]   -- made with the slot's first strip
			if p then
				-- p.icon and p.over sit on Blizzard's aura button, which can be forbidden while
				-- auras are secret out of combat too (a PvP match): guarded so a refusal there
				-- can't break the preview's start. Once small-items merges, the holder's own alpha
				-- is the better way to hide this (the preview draws its own strip); this stays as
				-- a guard on Blizzard's part.
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
		-- Each part on its own, so one the client refuses (a filter it doesn't take) can't stop the rest.
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

-- Whether Blizzard's part is made and shown over our mark (rangeShown: place showed its container).
local function partLive(s)
	return s.rangeShown and not s.rangeError and s.rangeParts.own ~= nil and s.rangeSlots.own == true
end

-- Size, place and colour our strip and Blizzard's part (out of combat). The height is a line's (ns.linePx), as borders are.
-- Along the top of the slot's picture, which sits in from the button by its border (s.inset).
-- ownOnly: our strip only, not Blizzard's container (auras are secret).
local function place(s, size, ownOnly)
	local c, b, gate, o = TB.cfg(), s.button, s.rangeGate, s.inset or 0
	gate:ClearAllPoints()
	-- Where the bar's Look puts its mark, and what it draws there; else the strip.
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
	ct:SetAlpha(1)   -- preview mode hides our own parts on it instead (R.preview), never the container
	ct:Show()
	s.rangeShown = true
	styleButtons(s)
end

local function applyFilter(s)
	local c = s.rangeContainer
	if not c or InCombatLockdown() or ns.aurasSecret() then return end   -- R.layout runs again then
	for _, part in ipairs(PARTS) do
		if s.rangeSlots[part.key] then
			ns.try("totem range: filter", c.SetAuraSlotCandidateFilters, c, part.key, { includeSpellIDs = CopyTable(buffIDs[s.el]) })
		end
	end
end

-- Buff ranks not in the list: while auras are readable your own buffs can be read, and one whose
-- name is the client's name for a listed buff is another rank of it (locale-free: both names are
-- the client's).
local names = {}   -- the client's buff name -> element
local function learn()
	if InCombatLockdown() or not TB.isShaman() or not enabled() then return end
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

------------------------------------------------------------------------
-- Called by the totem bar
------------------------------------------------------------------------
-- layout (out of combat): make, place or hide everything.
function R.layout(size)
	-- Blizzard's containers refuse addon calls while auras are secret: their part waits and the whole
	-- layout runs again once that ends. Our own strip (the mark) is laid out now.
	local blocked = ns.deferWhileAurasSecret("totem range layout", function() R.layout(size) end)
	local want = enabled() and TB.isShaman()
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
		R.refresh(s)   -- Blizzard's part may be there now (a layout that waited)
	end
	if not blocked then learn() end
end

-- The strip's holder: shown while one of your buff totems is down in the slot, else hidden, so a
-- buff that lingers after its totem goes can't keep Blizzard's part lit over the emptied slot.
-- Out of combat its alpha stays 1 and it hides through a state driver that shows it again as
-- combat starts (an addon Show on a frame holding Blizzard's button is dropped in combat), so a
-- totem dropped in combat always gets its strip. In combat its alpha hides it: SetAlpha isn't a
-- protected call, but whether it takes on a frame holding Blizzard's button in combat is not yet
-- tested; if it doesn't, the part stays lit until the buff goes. The red is held by the
-- same frame, so it can never show without Blizzard's part over it.
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
		h:Show()   -- the driver leaves it as it last set it
	elseif not s.rangeDriven then
		local ok, err = pcall(RegisterStateDriver, h, "visibility", EMPTY)
		if ok then s.rangeDriven = true else ns.noteError("totem range: holder", err) end
	end
end

-- Whether one of your buff totems is down in the slot (the gate for the holder's alpha, in and out
-- of combat).
local function buffTotemDown(s)
	return s.down and isBuffTotem(s.el, ns.Totems.downSpell(s.slot))
end

-- refresh (any time): the mark's gate, from which totem of yours is down. Only over Blizzard's part:
-- without it the red would say "out of range" all the time. Then the holder (showStrip).
function R.refresh(s)
	if not s.rangeGate then return end
	local on = enabled() and partLive(s) and buffTotemDown(s)
	s.rangeGate:SetAlpha(on and 1 or 0)
	showStrip(s, on)
	R.drawTimeLeft(s)
end

-- drawTimeLeft (ten times a second while totems are down): the mark only while the totem has time
-- left.
function R.drawTimeLeft(s)
	local m = s.rangeMark
	if not m then return end
	local d = s.dur
	if d and ns.CURVE_LIVE then
		local ok, a = ns.try("totem range: time", d.EvaluateRemainingDuration, d, ns.CURVE_LIVE)
		m:SetAlpha(ok and a or 0)
	else m:SetAlpha(0) end
end

local ev = CreateFrame("Frame")
ns.registerEvent(ev, "UNIT_AURA", "player")
ns.registerEvent(ev, "PLAYER_REGEN_ENABLED")
ns.registerEvent(ev, "PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		-- Combat's alpha off the holders, and each one's driver as it should be out of combat.
		for _, el in ipairs(TB.ELEMENTS) do R.refresh(TB.slots[el]) end
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- Fires before the lockdown takes hold: drop any holder whose slot has no buff totem of
		-- ours down now, so a buff lingering from a totem that went out of combat (still bright,
		-- since out of combat the holder's alpha stays 1) doesn't show at the pull.
		for _, el in ipairs(TB.ELEMENTS) do
			local s = TB.slots[el]
			local h = s.rangeHold
			if h and not buffTotemDown(s) then
				ns.try("totem range: holder alpha", h.SetAlpha, h, 0)
			end
		end
		return
	end
	learn()
end)
