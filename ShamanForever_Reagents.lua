-- Reagents (Reincarnation's Ankh, the water buffs' reagents): whether the spell still takes one,
-- how many the player carries, and the count on the icon, in its low colour at or below the Low
-- mark, with the missing look when there are none. While low the element isn't idle, so it shows
-- even at Idle opacity 0. Used by the cooldown elements, the buff elements and the options' previews.
--
-- An element here is any table with key, frame, spellID and reagent (an item ID); the reagent's
-- state is kept on it: takesReagent, reagentReadAt and reagentRead (for /sf debug).

local _, ns = ...
local isSecret, safe = ns.isSecret, ns.safe

local R = {}
ns.Reagents = R

local setting = ns.elementSetting

-- A reagent element's option defaults (ns.elementSetting): the count (always | low | never), its Low
-- mark, whether running low holds it out of idle, the count's text (its colour while plenty and
-- while low or none, its size and place), and the none-left looks.
R.DEFAULTS = {
	reagentCount = "always", reagentLow = 2, reagentShow = true,
	reagentColor = { 1, 1, 1, 1 }, reagentLowColor = { 1, 0.82, 0, 1 },
	reagentSize = 14, reagentPos = "BOTTOMRIGHT", reagentX = 0, reagentY = 0,
	reagentRing = true, reagentPulse = true,
}

-- How many the player carries, or nil when that can't be read.
function R.count(def)
	local ok, n = safe(C_Item and C_Item.GetItemCount, def.reagent)
	if ok and type(n) == "number" and not isSecret(n) then return n end
end

-- Whether the spell still takes its reagent. It may not: an account perk, Reagent Economy, removes
-- the vendor reagents of class abilities, and a count or warning would then be false. So while the
-- perk is known nothing shows and nothing is kept. Else the spell's tooltip decides, and only a yes
-- (it names the item) shows the count and its looks; a no, or nil while it can't be told yet, shows
-- neither. The tooltip is read while auras are readable, and again once its answer is 30 s old (a
-- tooltip can be incomplete while the client loads it); a nil at the next refresh.
local RECHECK = 30
local PERK, PERK_AURA = 1225503, 1262643   -- Reagent Economy, and its aura ("no reagent use")
-- The perk: its spell, else (while auras are readable) its aura. Read at each spellbook scan
-- (R.readPerk, from the resolves) and at most every RECHECK s while auras are readable, which finds
-- a perk bought mid-session; in between, and while auras are secret, the last answer.
local perk, perkReadAt = false, -math.huge
function R.readPerk()
	local ok, v = safe(IsPlayerSpell, PERK)
	if ok and not isSecret(v) and v == true then perk, perkReadAt = true, GetTime() return end
	if InCombatLockdown() or ns.aurasSecret() or not C_UnitAuras then return end
	local aok, a = safe(C_UnitAuras.GetPlayerAuraBySpellID, PERK_AURA)
	perk, perkReadAt = aok and type(a) == "table", GetTime()
end
local function perkKnown()
	if GetTime() - perkReadAt >= RECHECK and not InCombatLockdown() and not ns.aurasSecret() then R.readPerk() end
	return perk
end
R.perkKnown = perkKnown   -- for /sf debug
function R.takes(def)
	if perkKnown() then def.takesReagent = nil return false end
	if def.takesReagent ~= nil and GetTime() - (def.reagentReadAt or 0) < RECHECK then return def.takesReagent end
	-- While auras are secret (combat, a PvP match) the perk's aura can't be seen, so the tooltip isn't
	-- read either: only an answer from a readable moment stands, and nil shows nothing.
	if InCombatLockdown() or ns.aurasSecret() then return def.takesReagent end
	def.reagentReadAt = GetTime()
	if not (def.spellID and C_TooltipInfo and C_TooltipInfo.GetSpellByID and C_Item and C_Item.GetItemNameByID) then return nil end
	local ok, item = safe(C_Item.GetItemNameByID, def.reagent)
	if not ok or type(item) ~= "string" or isSecret(item) then
		safe(C_Item.RequestLoadItemDataByID, def.reagent)   -- asked again on the next refresh
		return nil
	end
	local tok, data = safe(C_TooltipInfo.GetSpellByID, def.spellID)
	if not tok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	def.takesReagent = false
	for _, line in ipairs(data.lines) do
		for _, t in ipairs({ line.leftText or false, line.rightText or false }) do
			if type(t) == "string" and not isSecret(t) and t:find(item, 1, true) then def.takesReagent = true end
		end
	end
	return def.takesReagent
end

-- A number setting, or its default when the saved one isn't a number (shared text can hold anything).
local function num(key, name)
	local v = setting(key, name)
	if type(v) ~= "number" or v ~= v then v = ns.elementDefault(key, name) end
	return v
end

-- The count for n reagents on an icon (the HUD's and the options' previews), as the element's
-- Reagent settings say: when it shows, its colours (plenty; low or none), size and place. Returns
-- whether n is low, and the none-left looks wanted (ring, pulse), which the caller sets together
-- with any other look on that icon, so a running pulse isn't restarted.
local COUNT_JUSTIFY = { TOPLEFT = "LEFT", BOTTOMLEFT = "LEFT", TOPRIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT", CENTER = "CENTER" }
function R.draw(f, key, n)
	local low = n <= num(key, "reagentLow")
	local show = setting(key, "reagentCount")   -- always | low | never
	local fs = f.count
	if show == "always" or (show == "low" and low) then
		local pos = setting(key, "reagentPos")
		if not COUNT_JUSTIFY[pos] then pos = "BOTTOMRIGHT" end
		ns.placeScaledText(fs, f, num(key, "reagentSize"), pos, num(key, "reagentX"), num(key, "reagentY"))
		fs:SetJustifyH(COUNT_JUSTIFY[pos])
		local name = low and "reagentLowColor" or "reagentColor"
		local c = setting(key, name)
		if not ns.isColor(c) then c = ns.elementDefault(key, name) end
		local shown = string.format("%d%.3f%.3f%.3f%.3f", n, c[1], c[2], c[3], c[4] or 1)
		if fs.shown ~= shown then   -- the text and colour only when they change
			fs.shown = shown
			fs:SetText(n)
			fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		end
		fs:Show()
	else fs:Hide() end
	local out = n == 0
	return low, out and setting(key, "reagentRing") or false, out and setting(key, "reagentPulse") or false
end

-- Reads the count and draws it, once the tooltip says the spell takes the reagent (R.takes).
-- Returns whether it's low enough to hold the element out of idle (Idle when counts reagents), and
-- the none-left looks wanted (see R.draw).
function R.refresh(def)
	local n = def.reagent and R.takes(def) == true and R.count(def)
	def.reagentRead = n
	if not n then
		def.frame.count:Hide()
		return false, false, false
	end
	local low, ring, pulse = R.draw(def.frame, def.key, n)
	return low and setting(def.key, "reagentShow") and true or false, ring, pulse
end
