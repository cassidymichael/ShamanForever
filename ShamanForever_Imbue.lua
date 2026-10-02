-- Weapon imbue

local _, ns = ...
local say, isSecret = ns.say, ns.isSecret
local Spells = ns.Spells

local IM = { name = "imbue" }
ns.Imbue = IM

ns.Profiles.addRanges({ imbueWarnMins = { 0, 30 } })
local imbue = ns.newElementIcon("imbue")
local anyKnown = false
local IDLE_CHOICES = {
	{ "never", "Never", "It always shows in full" },
	{ "notlow", "On, not running low",
		"Idle while an imbue is on and its time left isn't low" },
	{ "on", "On", "Idle while an imbue is on", "Idle whatever its time left is." },
}
ns.registerElement("imbue", { frame = imbue, label = "Weapon Imbue", paint = function(t) t:SetTexture(IM.icon()) end,
	learned = function() return anyKnown end,
	defaults = { idleWhen = "notlow", idleAlpha = 0 },
	styles = { uptime = { text = true, textSize = 16, textColor = { 1, 1, 1, 1 }, textPos = "center", swipe = false,
		bar = false } },
	def = { key = "imbue", idleChoices = IDLE_CHOICES },
	effects = { glow = { "missing" }, pop = { "lost" }, popKind = "imbue" },
	kind = "imbue", icon = 136086, school = "spirit", blurb = "Warns when your main hand has no imbue." })

-- ids are enchant IDs (item data), not spell IDs
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
local MAIN_HAND_SLOT = 16
local IMBUE_TYPE = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue or 3

-- Recognised by enchant ID, else icon, else learned from a cast
local imbueByID = {}
for key, m in pairs(IMBUES) do
	for _, id in ipairs(m.ids) do imbueByID[id] = key end
end

local imbueState = { on = nil, key = nil, expiresAt = nil, total = nil, unreadable = false, read = "not checked",
	castKey = nil, castAt = 0, changedAt = 0 }

imbue.upTimer = ns.Timer.new(imbue, "imbue", "uptime", { cd = imbue.cd, school = "spirit" })
imbue.timer = imbue.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
ns.Media.setFont(imbue.timer, nil, 16)
imbue.timer:SetPoint("CENTER")

local function imbueIconFor(key)
	if not IMBUES[key] then key = "rockbiter" end
	local _, icon = Spells.known(key)
	return icon or IMBUES[key].icon
end

-- false when none is on, nil when it can't be read
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

local function hasWeapon()
	local ok, id = ns.safe(GetInventoryItemID, "player", MAIN_HAND_SLOT)
	if not ok or isSecret(id) then return true end
	return id ~= nil
end

local function imbueKeyFor(w)
	local key = ns.getAccount().imbueIDs[w.enchantID] or imbueByID[w.enchantID]
	if key then return key end
	for k, m in pairs(IMBUES) do
		if w.enchantIconID == m.icon or w.enchantIconID == imbueIconFor(k) then return k end
	end
end

function IM.mainHand()
	local r = readMainHand()
	return r and imbueKeyFor(r) or nil
end

local imbueIcon = imbueIconFor("rockbiter")
local function preferredImbueIcon()
	local db, acct = ns.getDB(), ns.getAccount()
	return imbueIconFor(db.imbuePreferred == "last" and (acct.imbueLast or "rockbiter") or db.imbuePreferred)
end
IM.preferredIcon = preferredImbueIcon
function IM.icon() return imbueIcon end

-- quiet: nothing can be cast now, so a missing imbue shows grey without the warning
local function drawImbue(now, quiet)
	local db, acct = ns.getDB(), ns.getAccount()
	local on, key = imbueState.on, imbueState.key
	local unreadable = imbueState.unreadable
	local left = imbueState.expiresAt and imbueState.expiresAt - now
	local warnAt = db.imbueWarnMins * 60
	local showTime = left ~= nil and warnAt > 0 and left <= warnAt
	-- Missing look only when the read says none: unrecognised shows in colour, unreadable as "?"
	local missing = on == false
	imbueIcon = key and imbueIconFor(key) or preferredImbueIcon()
	imbue.tex:SetDesaturated(missing and db.imbueMissingGrey or false)
	imbue:SetRingShown(missing and db.imbueMissingRing and not quiet)
	imbue:SetPulsing(missing and db.imbuePulse and not quiet)
	imbue:SetGlowShown(missing and db.imbueGlow and not quiet)
	imbue.tex:SetTexture(imbueIcon)
	if unreadable then
		imbue.timer:SetText("?")
		imbue.timer:SetTextColor(1, 0.82, 0)
	end
	imbue.timer:SetShown(unreadable)
	if showTime and not unreadable then
		local total = math.max(imbueState.total or left, left)
		imbue.upTimer:setTime(imbueState.expiresAt - total, total)
	else
		imbue.upTimer:clear()
	end
	-- Idle fades by alpha, not Hide (keeps its place)
	local when = ns.elementSetting("imbue", "idleWhen")
	local idle = acct.locked and on and (when == "on" or (when == "notlow" and not showTime))
	ns.fadeTo(imbue, idle and ns.idleAlpha("imbue") or 1)
end

local function drawNotLearned()
	imbueIcon = preferredImbueIcon()
	imbue.tex:SetTexture(imbueIcon)
	imbue.tex:SetDesaturated(true)
	imbue:SetRingShown(false)
	imbue:SetPulsing(false)
	imbue:SetGlowShown(false)
	imbue.timer:Hide()
	imbue.upTimer:clear()
	ns.fadeTo(imbue, 1)
end

function IM.refresh()
	if not ns.isEnabled("imbue") then
		imbueState.on, imbueState.key, imbueState.lastID, imbueState.lastLeft = nil, nil, nil, nil
		return
	end
	if not anyKnown then drawNotLearned() return end
	local db, acct = ns.getDB(), ns.getAccount()
	local now = GetTime()
	local r = readMainHand()
	local had = imbueState.on
	imbueState.unreadable = r == nil
	imbueState.on = r and true or r
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
		-- Unknown enchant changed within 3 s of our cast: that imbue (one that didn't change is the old one)
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
	-- No weapon still warns
	local quiet = ns.cantAct()
	drawImbue(now, quiet)
	if had and r == false and not quiet then
		if db.imbuePop then imbue:Pop("imbue") end
		if imbue:IsVisible() then ns.Sounds.element("imbue", "lostSound", true) end
	end
end

function IM.onCast(spellID)
	local key = Spells.keyOf(spellID)
	if not IMBUES[key] then return end
	imbueState.castKey, imbueState.castAt = key, GetTime()
	IM.refresh()
end

function IM.sanitize(_, acct)
	if type(acct.imbueIDs) ~= "table" then acct.imbueIDs = {} end
end

function IM.resolve()
	local sig = {}
	anyKnown = false
	for _, key in ipairs(IMBUE_ORDER) do
		IMBUES[key].name = Spells.name(key)
		local id = Spells.known(key)
		if id then anyKnown = true end
		table.insert(sig, tostring(id))
	end
	return table.concat(sig, ",")
end

function IM.applyTimers()
	imbue.upTimer:apply()
	ns.Media.setFont(imbue.timer, nil, 16)
end
IM.applyLayout = IM.refresh
IM.tick = IM.refresh
function IM.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_INVENTORY_CHANGED", "player")
	ns.registerEvent(ev, "PLAYER_EQUIPMENT_CHANGED")
	ev:SetScript("OnEvent", function() IM.refresh() end)
	ns.onCanActChange(function() IM.refresh() end)
end

-- /sf debug
function IM.debug()
	local r = readMainHand()
	say("main hand imbue now: %s; last ticker read: %s; weapon %s", r == nil and "unreadable" .. (InCombatLockdown() and " (in combat)" or "")
		or r == false and "none" or string.format("enchant %d, icon %d, %.0fs left", r.enchantID, r.enchantIconID, r.timeLeft / 1000),
		imbueState.read, tostring(hasWeapon()))
end

ns.registerModule(IM)
