-- /sf debug auras: what the game lets us read about the player's buffs, for the totem range
-- indicator (is a totem's buff on me?) and the shield (is Lightning Shield still secret in combat?).
--   Out of combat: lists every helpful aura (spell ID, secrecy level, time), the weapon enchants, and
--   remembers the aura IDs for the next run.
--   In combat: asks C_UnitAuras.GetPlayerAuraBySpellID about each remembered ID and each shield rank,
--   and says what came back (an answer, nothing, secret, or an error). A failed aura call can log a
--   "Lua Taint" line; that's expected for a probe.
-- /sf debug auras watch: toggles a watcher that says when a remembered buff comes or goes (in combat
-- too, as far as it's readable), to see how long a totem's buff lingers after leaving its range.

local _, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg

local seen = {}      -- spell ID -> name: auras found out of combat this session
local order = {}

local levelName = {}
if Enum and type(Enum.SecrecyLevel) == "table" then
	for name, v in pairs(Enum.SecrecyLevel) do levelName[v] = name end
end
local function secrecy(id)
	if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then return "no API" end
	local ok, v = pcall(C_Secrets.GetSpellAuraSecrecy, id)
	if not ok then return "error" end
	if isSecret(v) then return "<secret>" end
	return levelName[v] or tostring(v)
end

local function remember(id, name)
	if type(id) ~= "number" or isSecret(id) or seen[id] then return end
	seen[id] = name or "?"
	table.insert(order, id)
end

-- The shield ranks are always asked about.
local function shieldIDs()
	local out = {}
	for _, key in ipairs({ "lightningShield", "waterShield" }) do
		for id in pairs(ns.Spells.ids(key)) do out[id] = ns.Spells.name(key) end
	end
	return out
end

local function listOutOfCombat()
	local ok, restricted = safe(C_Secrets and C_Secrets.ShouldAurasBeSecret)
	say("auras secret now: %s", ok and describeArg(restricted) or "unknown")
	local n = 0
	for i = 1, 40 do
		local aok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not aok then say("aura %d: error %s", i, tostring(a)) break end
		if not a then break end
		n = n + 1
		local id = a.spellId
		local left = (not isSecret(a.expirationTime) and type(a.expirationTime) == "number" and a.expirationTime > 0)
			and string.format("%.0fs left", a.expirationTime - GetTime()) or "no end"
		say("  %s: spell %s, secrecy %s, %s, from %s", describeArg(a.name), describeArg(id),
			isSecret(id) and "?" or secrecy(id), left, describeArg(a.sourceUnit))
		if not isSecret(a.name) then remember(id, a.name) end
	end
	say("%d helpful auras; remembered for the in-combat run: %d IDs", n, #order)
	for id, name in pairs(shieldIDs()) do
		say("  shield %s (%d): secrecy %s", name, id, secrecy(id))
	end
	-- Weapon enchants (Classic-style Windfury / Flametongue totems enchant the weapon).
	if C_Item and C_Item.GetWeaponEnchantInfo then
		for _, slot in ipairs({ { "main hand", Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0 },
				{ "off hand", Enum and Enum.WeaponSlot and Enum.WeaponSlot.OffHand or 1 } }) do
			local wok, list = pcall(C_Item.GetWeaponEnchantInfo, slot[2])
			if wok and type(list) == "table" then
				for _, w in ipairs(list) do
					say("  %s enchant: id %s, type %s, icon %s, %s ms left", slot[1], describeArg(w.enchantID),
						describeArg(w.enchantType), describeArg(w.enchantIconID), describeArg(w.timeLeft))
				end
			else say("  %s enchants: unreadable", slot[1]) end
		end
	end
end

-- One ID through GetPlayerAuraBySpellID: "up (...)", "nothing", or what went wrong.
local function ask(id)
	local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
	if not ok then return "error: " .. tostring(a) end
	if a == nil then return "nothing" end
	if isSecret(a) then return "secret table" end
	local left = a.expirationTime
	if isSecret(left) then left = "secret time"
	elseif type(left) == "number" and left > 0 then left = string.format("%.0fs left", left - GetTime())
	else left = "no end" end
	return string.format("up (id %s, %s)", describeArg(a.spellId), left)
end

local function askInCombat()
	local ok, restricted = safe(C_Secrets and C_Secrets.ShouldAurasBeSecret)
	say("in combat; auras secret now: %s", ok and describeArg(restricted) or "unknown")
	for id, name in pairs(shieldIDs()) do say("  shield %s (%d): %s", name, id, ask(id)) end
	if #order == 0 then say("  no totem buffs remembered: run /sf debug auras out of combat first") end
	for _, id in ipairs(order) do say("  %s (%d): %s", seen[id], id, ask(id)) end
end

-- Watcher: a remembered buff (or a shield) coming or going, with the time.
local watcher = CreateFrame("Frame")
local state = {}
local function poll()
	local ids = shieldIDs()
	for _, id in ipairs(order) do ids[id] = seen[id] end
	for id, name in pairs(ids) do
		local r = ask(id)
		local up = r:sub(1, 2) == "up" and "up" or r
		if state[id] ~= nil and state[id] ~= up then
			say("%.1f %s (%d): %s%s", GetTime(), name, id, up, InCombatLockdown() and " [combat]" or "")
		end
		state[id] = up
	end
end
watcher:SetScript("OnEvent", poll)
watcher:SetScript("OnUpdate", function(self, elapsed)
	self.t = (self.t or 0) + elapsed
	if self.t >= 0.5 then self.t = 0; poll() end
end)
watcher:Hide()

function ns.probeAuras(arg)
	if arg == "watch" then
		if watcher:IsShown() then
			watcher:Hide(); watcher:UnregisterAllEvents()
			say("aura watch off")
		else
			wipe(state); poll()
			watcher:Show(); pcall(watcher.RegisterUnitEvent, watcher, "UNIT_AURA", "player")
			say("aura watch on: says when a remembered buff or a shield comes or goes (/sf debug auras watch to stop)")
		end
		return
	end
	if InCombatLockdown() then askInCombat() else listOutOfCombat() end
end
