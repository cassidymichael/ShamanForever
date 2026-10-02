-- Reagents

local _, ns = ...
local isSecret, safe = ns.isSecret, ns.safe

local R = {}
ns.Reagents = R

local setting = ns.elementSetting

R.DEFAULTS = {
	reagentCount = "always", reagentLow = 2, reagentShow = true,
	reagentColor = { 1, 1, 1, 1 }, reagentLowColor = { 1, 0.82, 0, 1 },
	reagentSize = 14, reagentPos = "BOTTOMRIGHT", reagentX = 0, reagentY = 0,
	reagentRing = true, reagentPulse = true,
}
ns.Profiles.addRanges(nil, { reagentLow = { 0, 10 }, reagentSize = { 8, 40 }, reagentX = { -50, 50 },
	reagentY = { -50, 50 } })

R.IDLE_EXTRA = { key = "reagentShow", label = "Running low",
	tip = "Running low or out counts as something going on, even at 0%.",
	choices = { { true, "Shows it" }, { false, "Stays idle" } } }

function R.count(def)
	local ok, n = safe(C_Item and C_Item.GetItemCount, def.reagent)
	if ok and type(n) == "number" and not isSecret(n) then return n end
end

-- The Reagent Economy perk removes the reagent: then nothing shows
local RECHECK = 30
local PERK, PERK_AURA = 1225503, 1262643
ns.Spells.addCheck("Reagent Economy", { PERK, PERK_AURA })
-- Once known, stays known for the session
local perk, perkReadAt = false, -math.huge
function R.readPerk()
	if perk then return end
	local ok, v = safe(C_SpellBook.IsSpellKnown, PERK)
	if ok and not isSecret(v) and v == true then perk, perkReadAt = true, GetTime() return end
	if not ns.aurasReadable() or not C_UnitAuras then return end
	local aok, a = safe(C_UnitAuras.GetPlayerAuraBySpellID, PERK_AURA)
	perk, perkReadAt = aok and type(a) == "table", GetTime()
end
local function perkKnown()
	if not perk and GetTime() - perkReadAt >= RECHECK and ns.aurasReadable() then
		R.readPerk()
	end
	return perk
end
R.perkKnown = perkKnown
function R.auraChanged()
	if perk then return false end
	perkReadAt = -math.huge
	return true
end
function R.takes(def)
	if perkKnown() then def.takesReagent = nil return false end
	if def.takesReagent ~= nil and GetTime() - (def.reagentReadAt or 0) < RECHECK then return def.takesReagent end
	-- Auras secret: only an answer from a readable moment stands
	if not ns.aurasReadable() then return def.takesReagent end
	def.reagentReadAt = GetTime()
	if not (def.spellID and C_TooltipInfo and C_TooltipInfo.GetSpellByID and C_Item and C_Item.GetItemNameByID) then return nil end
	local ok, item = safe(C_Item.GetItemNameByID, def.reagent)
	if not ok or type(item) ~= "string" or isSecret(item) then
		safe(C_Item.RequestLoadItemDataByID, def.reagent)
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

local function num(key, name)
	local v = setting(key, name)
	if type(v) ~= "number" or v ~= v then v = ns.elementDefault(key, name) end
	return v
end

local COUNT_JUSTIFY = ns.COUNT_JUSTIFY
function R.draw(f, key, n)
	local low = n <= num(key, "reagentLow")
	local show = setting(key, "reagentCount")
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
		if fs.shown ~= shown then
			fs.shown = shown
			fs:SetText(n)
			fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		end
		fs:Show()
	else fs:Hide() end
	local out = n == 0
	return low, out and setting(key, "reagentRing") or false, out and setting(key, "reagentPulse") or false
end

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
