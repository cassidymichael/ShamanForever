-- Weapon imbue (main hand): warns while no shaman imbue is on, shows which one is and, near the end,
-- its time left. Imbues are item data, not auras: C_Item.GetWeaponEnchantInfo lists them with
-- enchantType Imbue (C_PaperDollInfo.GetTemporaryEnchantmentInfo only covers stones and oils, tested
-- 2026-09-23). The API is not documented as secret and stays readable in combat, so it is read
-- directly every time. If a read fails the icon shows "?" rather than guessing, and /sf debug says
-- what came back.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule).

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local IM = { name = "imbue" }
ns.Imbue = IM

local imbue = ns.newElementIcon("imbue")
ns.registerElement("imbue", { frame = imbue, label = "Weapon Imbue", paint = function(t) t:SetTexture(IM.icon()) end })

-- The key is also the spell's key in ns.Spells; name is its display name (the client's). ids are
-- enchant IDs (item data), not spell IDs.
local IMBUES = {
	rockbiter   = { icon = 136086, ids = { 29, 6, 1, 503, 1663, 683, 1664 } },
	flametongue = { icon = 135814, ids = { 5, 4, 3, 523, 1665, 1666 } },
	frostbrand  = { icon = 135847, ids = { 2, 12, 524, 1667, 1668 } },
	windfury    = { icon = 136018, ids = { 283, 284, 525, 1669 } },
}
for key, m in pairs(IMBUES) do m.name = Spells.name(key) end
local IMBUE_ORDER = { "rockbiter", "flametongue", "frostbrand", "windfury" }
IM.IMBUES, IM.ORDER = IMBUES, IMBUE_ORDER
local MAIN_HAND = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
local IMBUE_TYPE = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue or 3

-- Recognised by enchant ID (seeded from the vanilla ranks), else by icon, else learned from our own cast.
local imbueByID = {}
for key, m in pairs(IMBUES) do
	for _, id in ipairs(m.ids) do imbueByID[id] = key end
end

-- key: the imbue on (nil = none); unreadable: the last read failed; read: what it said, for /sf debug.
-- total: the longest time left seen for this imbue, its full length as far as we know (swipe and bar).
-- castKey, castAt: our last imbue cast and when. changedAt: when the weapon's imbue last changed (a
-- new enchant, or its time going up: a recast); lastID, lastLeft: the read before.
local imbueState = { key = nil, expiresAt = nil, total = nil, unreadable = false, read = "not checked", castKey = nil, castAt = 0,
	changedAt = 0 }

-- Time left: a timer fed the imbue's readable time. imbue.timer only shows "?" when unreadable.
imbue.upTimer = ns.Timer.new(imbue, "imbue", "uptime", { cd = imbue.cd, school = "spirit" })
imbue.timer = imbue.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
imbue.timer:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
imbue.timer:SetPoint("CENTER")

local function imbueIconFor(key)
	if not IMBUES[key] then key = "rockbiter" end
	local _, icon = Spells.known(key)
	return icon or IMBUES[key].icon
end

-- The main hand's imbue entry (enchantID, timeLeft in ms, enchantIconID), false when none is on,
-- nil when it cannot be read.
local function readMainHand()
	if not (C_Item and C_Item.GetWeaponEnchantInfo) then return nil end
	local ok, list = pcall(C_Item.GetWeaponEnchantInfo, MAIN_HAND)
	if not ok or isSecret(list) or type(list) ~= "table" then return nil end
	for _, w in ipairs(list) do
		if isSecret(w.hasEnchant) or isSecret(w.enchantType) then return nil end
		if w.hasEnchant and w.enchantType == IMBUE_TYPE then
			if isSecret(w.enchantID) or isSecret(w.timeLeft) or isSecret(w.enchantIconID) then return nil end
			return w
		end
	end
	return false
end

local function imbueKeyFor(w)
	local key = ns.getAccount().imbueIDs[w.enchantID] or imbueByID[w.enchantID]
	if key then return key end
	for k, m in pairs(IMBUES) do
		if w.enchantIconID == m.icon or w.enchantIconID == imbueIconFor(k) then return k end
	end
end

local imbueIcon = imbueIconFor("rockbiter")
-- The icon while no imbue is on: the player's pick, or the last one used.
local function preferredImbueIcon()
	local db, acct = ns.getDB(), ns.getAccount()
	return imbueIconFor(db.imbuePreferred == "last" and (acct.imbueLast or "rockbiter") or db.imbuePreferred)
end
IM.preferredIcon = preferredImbueIcon
function IM.icon() return imbueIcon end

local function paintImbue(now)
	local db, acct = ns.getDB(), ns.getAccount()
	local key = imbueState.key
	local unreadable = imbueState.unreadable
	local left = key and imbueState.expiresAt and imbueState.expiresAt - now
	local warnAt = db.imbueWarnMins * 60
	local showTime = left ~= nil and warnAt > 0 and left <= warnAt
	if key then
		imbueIcon = imbueIconFor(key)
		imbue.tex:SetDesaturated(false)
		imbue:SetRingShown(false)
		imbue:SetPulsing(false)
		imbue:SetGlowShown(false)
	else
		imbueIcon = preferredImbueIcon()
		imbue.tex:SetDesaturated(db.imbueMissingGrey)
		imbue:SetRingShown(db.imbueMissingRing)
		imbue:SetPulsing(db.imbuePulse)
		imbue:SetGlowShown(db.imbueGlow and not unreadable)
	end
	imbue.tex:SetTexture(imbueIcon)
	if unreadable then
		imbue:SetRingShown(false)
		imbue:SetPulsing(false)
		imbue.timer:SetText("?")
		imbue.timer:SetTextColor(1, 0.82, 0)
	end
	imbue.timer:SetShown(unreadable)
	if showTime and not unreadable then
		local total = math.max(imbueState.total or left, left)
		imbue.upTimer:setTime(imbueState.expiresAt - total, total)
		if left < 60 then imbue.upTimer:setTint(1, 0.3, 0.3) else imbue.upTimer:setTint(nil) end
	else
		imbue.upTimer:clear()
	end
	-- Hidden by alpha, not Hide, so it keeps its place in the group and shows again at once.
	imbue:SetAlpha((acct.locked and key and db.imbueHideActive and not showTime and not unreadable) and 0 or 1)
end

function IM.refresh()
	if not ns.isEnabled("imbue") then return end
	local db, acct = ns.getDB(), ns.getAccount()
	local now = GetTime()
	local r = readMainHand()
	local had = imbueState.key
	imbueState.unreadable = r == nil
	imbueState.key, imbueState.expiresAt = nil, nil
	if r == nil then
		imbueState.read = "unreadable" .. (InCombatLockdown() and " (in combat)" or "")
	elseif r == false then
		imbueState.read = "no imbue"
		imbueState.lastID, imbueState.lastLeft = nil, nil
	else
		local key = imbueKeyFor(r)
		local left = r.timeLeft / 1000
		if r.enchantID ~= imbueState.lastID or left > (imbueState.lastLeft or 0) + 1 then imbueState.changedAt = now end
		imbueState.lastID, imbueState.lastLeft = r.enchantID, left
		-- Unknown enchant that changed within 3 s of our cast: it is that imbue. (One that didn't change
		-- is still the old imbue, which must not be learned under the new name.)
		if not key and math.abs(now - imbueState.castAt) < 3 and math.abs(imbueState.changedAt - imbueState.castAt) < 3 then
			key = imbueState.castKey; acct.imbueIDs[r.enchantID] = key
		end
		imbueState.read = string.format("enchant %d, icon %d, %s", r.enchantID, r.enchantIconID, key or "not recognised")
		if key ~= imbueState.lastKey or left > (imbueState.total or 0) then imbueState.total = left end
		imbueState.lastKey = key
		imbueState.key = key
		imbueState.expiresAt = r.timeLeft > 0 and now + left or nil
		if key then acct.imbueLast = key end
	end
	paintImbue(now)
	-- The moment it drops (imbues stay readable in combat): pop.
	if had and r == false and db.imbuePop then imbue:Pop("imbue") end
end

-- Our own successful cast: remembered, so an imbue not recognised by ID or icon is learned on the next read.
function IM.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not IMBUES[key] then return end
	imbueState.castKey, imbueState.castAt = key, GetTime()
	IM.refresh()
end

-- After a spellbook scan (ns.resolveSpells): the client's names.
function IM.resolve()
	for key, m in pairs(IMBUES) do m.name = Spells.name(key) end
end

-- The timer takes its current style (ns.applyTimers).
function IM.applyTimers() imbue.upTimer:apply() end
IM.applyLayout = IM.refresh
IM.tick = IM.refresh   -- once a second: the time left
-- A shaman logged in: the weapon's own events.
function IM.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_INVENTORY_CHANGED", "player")
	ns.registerEvent(ev, "PLAYER_EQUIPMENT_CHANGED")
	ev:SetScript("OnEvent", function() IM.refresh() end)
end

-- /sf debug
function IM.debug()
	local r = readMainHand()
	say("main hand imbue now: %s; last ticker read: %s", r == nil and "unreadable" .. (InCombatLockdown() and " (in combat)" or "")
		or r == false and "none" or string.format("enchant %d, icon %d, %.0fs left", r.enchantID, r.enchantIconID, r.timeLeft / 1000),
		imbueState.read)
end

ns.registerModule(IM)
