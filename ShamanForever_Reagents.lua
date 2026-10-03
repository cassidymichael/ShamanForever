-- Reagents

local _, ns = ...
local E = ns.Elements
local isSecret, safe = ns.isSecret, ns.safe

local R = {}
ns.Reagents = R

local setting = E.setting

-- when: the count shows always | low | never; lowKeepsShown: running low isn't idle; ring and fade:
-- the None left look
local DEFAULTS = { reagent = {
	when = "always", low = 2, lowKeepsShown = true,
	color = { 1, 1, 1, 1 }, lowColor = { 1, 0.82, 0, 1 },
	size = 14, pos = "BOTTOMRIGHT", x = 0, y = 0,
	ring = true, fade = true,
} }
local RANGES = { reagent = { low = { 0, 10, 1 }, size = { 8, 40, 1 }, x = { -50, 50, 1 },
	y = { -50, 50, 1 } } }

local IDLE_EXTRA = { name = "reagent", field = "lowKeepsShown", label = "Running low",
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
	if ns.plain(safe(C_SpellBook.IsSpellKnown, PERK)) == true then perk, perkReadAt = true, GetTime() return end
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

local function num(key, field)
	local v = setting(key, "reagent", field)
	if type(v) ~= "number" or v ~= v then v = E.default(key, "reagent", field) end
	return v
end

local COUNT_JUSTIFY = ns.COUNT_JUSTIFY
function R.draw(f, key, n)
	local low = n <= num(key, "low")
	local show = setting(key, "reagent", "when")
	local fs = f.count
	if show == "always" or (show == "low" and low) then
		local pos = setting(key, "reagent", "pos")
		if not COUNT_JUSTIFY[pos] then pos = "BOTTOMRIGHT" end
		ns.placeScaledText(fs, f, num(key, "size"), pos, num(key, "x"), num(key, "y"))
		fs:SetJustifyH(COUNT_JUSTIFY[pos])
		local field = low and "lowColor" or "color"
		local c = setting(key, "reagent", field)
		if not ns.isColor(c) then c = E.default(key, "reagent", field) end
		local shown = string.format("%d%.3f%.3f%.3f%.3f", n, c[1], c[2], c[3], c[4] or 1)
		if fs.shown ~= shown then
			fs.shown = shown
			fs:SetText(n)
			fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
		end
		fs:Show()
	else fs:Hide() end
	local out = n == 0
	return low, out and setting(key, "reagent", "ring") or false, out and setting(key, "reagent", "fade") or false
end

function R.refresh(def)
	local n = def.reagent and R.takes(def) == true and R.count(def)
	def.reagentRead = n
	if not n then
		def.frame.count:Hide()
		return false, false, false
	end
	local low, ring, pulse = R.draw(def.frame, def.key, n)
	return low and setting(def.key, "reagent", "lowKeepsShown") and true or false, ring, pulse
end

-- The reagent part (ns.registerPart): its count and None left look, for any kind
local PLENTY = 15
local function fewLeft(key)
	local v = setting(key, "reagent", "low")
	return math.max(type(v) == "number" and v == v and v or 2, 1)
end
local function look(ic, key, n)
	local _, ring, pulse = R.draw(ic, key, n)
	ic:SetRingShown(ring)
	ic:SetPulsing(pulse)
end
ns.registerPart("reagent", {
	kinds = { cooldown = { after = "primed" }, buff = { after = "skipLong" } },
	defaults = DEFAULTS,
	ranges = RANGES,
	idle = { extra = IDLE_EXTRA },
	page = { own = "reagent" },
	preview = {
		warning = "out",
		states = { { "low", "Few left", 70 }, { "out", "None left", 71 } },
		render = function(ic, st, def, P, pv)
			local key = def.key
			if st == "low" or st == "out" then
				pv.rest(ic, P, setting(key, "reagent", "lowKeepsShown"))
			end
			look(ic, key, st == "out" and 0 or st == "low" and fewLeft(key) or PLENTY)
		end,
		idles = function(st, def, when)
			if st ~= "low" and st ~= "out" then return nil end
			return ns.Kinds.idleMode(def, when) == "oncd"
				and setting(def.key, "reagent", "lowKeepsShown") == false
		end,
	},
})
