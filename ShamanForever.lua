-- ShamanForever: Lightning Shield charges + shock cooldown/range/mana HUD for the WoW: Forever beta.
--
-- Addon code cannot read player auras in combat on this client, so the shield is drawn by Blizzard's
-- secure CustomAuraContainer: we hand it widgets, its untainted code fills them. Everything else here
-- is plain UI. Rule for this client: never do Lua math or comparisons on a possibly-secret value.

local ADDON, ns = ...
local PREFIX = "|cff3399ffShamanForever|r: "
local function say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

local SHIELD_NAME = "Lightning Shield"
local VANILLA_SHIELD_IDS = { 324, 325, 905, 945, 8134, 10431, 10432 }
local SHOCKS = { earth = "Earth Shock", flame = "Flame Shock", frost = "Frost Shock" }
local SHOCK_ORDER = { "earth", "flame", "frost" }
local CD_FONT = "ShamanForeverCDFont"

local DEFAULTS = {
	point = "CENTER", x = 0, y = -160, alpha = 0.65, scale = 1, locked = true, size = 56,
	combatOnly = false,     -- hide the whole display out of combat (always shown while unlocked)
	-- layout
	iconSize = 40,
	spacing = 10,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	order = { "shield", "shock" },
	-- shield
	countPos = "center",    -- corner | center
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	showCount = true,       -- charge number (Blizzard prints it for two or more)
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	-- shock
	shock = "earth",        -- which shock the icon tracks
	manaSpell = "tracked",  -- tracked | earth | flame | frost
	cdText = true,
	cdTextSize = 22,
	manaRing = 0.6,         -- not enough mana: blue ring inside the icon edge, this opaque
	manaStyle = "both",     -- not enough mana (alone): overlay | tint | both on the icon body
	manaIntensity = 0.25,
	manaTint = 0.8,
	rangeStyle = "tint",    -- out of range: overlay | tint | both, painted on the icon body
	rangeIntensity = 0.45,
	rangeTint = 0.7,
}
local db

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end
local function safe(fn, ...) if not fn then return false end return pcall(fn, ...) end
local function describeArg(v) if isSecret(v) then return "<secret>" end return tostring(v) end

------------------------------------------------------------------------
-- Spellbook: highest known rank of each spell, by name
------------------------------------------------------------------------
local book = {}

local function rankOf(item)
	local sub = item.subName
	if (not sub or sub == "") and C_Spell.GetSpellSubtext then
		local ok, s = safe(C_Spell.GetSpellSubtext, item.spellID)
		if ok then sub = s end
	end
	return tonumber((sub or ""):match("(%d+)")) or 0
end

local function scanSpellbook()
	book = {}
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local ok, item = safe(C_SpellBook.GetSpellBookItemInfo, i, bank)
				if ok and item and item.spellID and item.name and not item.isPassive then
					local rank = rankOf(item)
					local cur = book[item.name]
					if not cur or rank > cur.rank then
						book[item.name] = { id = item.spellID, icon = item.iconID, rank = rank }
					end
				end
			end
		end
	end
end

local function knownSpell(name)
	local e = book[name]
	if e then return e.id, e.icon end
	local ok, info = safe(C_Spell.GetSpellInfo, name)
	if ok and type(info) == "table" and info.spellID then return info.spellID, info.iconID end
	return nil
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local cdFont = CreateFont(CD_FONT)

local root = CreateFrame("Frame", "ShamanForeverFrame", UIParent, "BackdropTemplate")
root:SetSize(130, 80)
root:SetMovable(true)
root:SetClampedToScreen(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
root:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, _, x, y = self:GetPoint()
	db.point, db.x, db.y = point, x, y
end)
root:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
root.label = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
root.label:SetPoint("BOTTOM", root, "TOP", 0, 2)
root.label:SetText("ShamanForever: drag me, then lock in /sf")

local function makeIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.manaOverlay = f:CreateTexture(nil, "ARTWORK", nil, 2)
	f.manaOverlay:SetAllPoints(f.tex)
	f.manaOverlay:SetColorTexture(0.2, 0.45, 1, 0.55)
	f.manaOverlay:Hide()
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints()
	f.cd:SetDrawEdge(false)
	-- Text sits on its own frame above the cooldown so the swipe never dims it.
	f.textFrame = CreateFrame("Frame", nil, f)
	f.textFrame:SetAllPoints()
	f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.count = f.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	f.count:SetFont(STANDARD_TEXT_FONT, math.floor(size * 0.45), "OUTLINE")
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	f.count:SetJustifyH("RIGHT")
	local okFS, cdText = pcall(f.cd.GetCountdownFontString, f.cd)
	if okFS and cdText then pcall(cdText.SetDrawLayer, cdText, "OVERLAY", 7) end
	-- Red ring just inside the icon edge, so an exact-size frame on top covers it completely.
	f.ring = {}
	local function edge(p1, p2, w, h)
		local t = f.textFrame:CreateTexture(nil, "OVERLAY", nil, 6)
		t:SetColorTexture(1, 0, 0, 0.9)
		t:SetPoint(p1, f.tex, p1, 0, 0)
		t:SetPoint(p2, f.tex, p2, 0, 0)
		if w then t:SetWidth(w) end
		if h then t:SetHeight(h) end
		t:Hide()
		table.insert(f.ring, t)
	end
	edge("TOPLEFT", "TOPRIGHT", nil, 3)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 3)
	edge("TOPLEFT", "BOTTOMLEFT", 3, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", 3, nil)
	f.SetRingShown = function(self, shown, r, g, b, a)
		for _, t in ipairs(self.ring) do
			if shown then t:SetColorTexture(r or 1, g or 0, b or 0, a or 0.9); t:Show() else t:Hide() end
		end
	end
	return f
end

local shield = makeIcon(root, DEFAULTS.size)
shield.count:Hide()

local shock = makeIcon(root, DEFAULTS.size)
shock.count:Hide()

-- Icon registry: every HUD icon lives here; db.order holds the keys in display order.
local ICONS = {
	shield = { frame = shield, label = "Lightning Shield" },
	shock  = { frame = shock,  label = "Shock" },
}
local ICON_KEYS = { "shield", "shock" }   -- registration order, used to fill gaps in db.order

-- Returns db.order cleaned up: unknown keys dropped, missing icons appended.
local function iconOrder()
	local seen, order = {}, {}
	for _, key in ipairs(db.order or {}) do
		if ICONS[key] and not seen[key] then table.insert(order, key); seen[key] = true end
	end
	for _, key in ipairs(ICON_KEYS) do
		if not seen[key] then table.insert(order, key) end
	end
	db.order = order
	return order
end

-- Sizes and anchors every icon in one pass; the root shrinks to fit so dragging feels right.
local function layoutIcons()
	local size, gap = db.iconSize, db.spacing
	local horizontal = db.orientation == "horizontal"
	local forward = db.growth ~= "backward"
	local order = iconOrder()
	local prev
	for _, key in ipairs(order) do
		local f = ICONS[key].frame
		f:SetSize(size, size)
		f:ClearAllPoints()
		if not prev then
			-- First icon sits in the corner the row grows away from.
			local corner = horizontal and (forward and "TOPLEFT" or "TOPRIGHT") or (forward and "TOPLEFT" or "BOTTOMLEFT")
			f:SetPoint(corner, root, corner, 0, 0)
		elseif horizontal then
			if forward then f:SetPoint("LEFT", prev, "RIGHT", gap, 0) else f:SetPoint("RIGHT", prev, "LEFT", -gap, 0) end
		else
			if forward then f:SetPoint("TOP", prev, "BOTTOM", 0, -gap) else f:SetPoint("BOTTOM", prev, "TOP", 0, gap) end
		end
		prev = f
	end
	local n = #order
	local extent = n * size + math.max(n - 1, 0) * gap
	if horizontal then root:SetSize(extent, size) else root:SetSize(size, extent) end
end

------------------------------------------------------------------------
-- Lightning Shield: underlay (our "no shield" look) + Blizzard's secure aura button on top
------------------------------------------------------------------------
local shieldSpellID, shieldAuraSpellID
local believedUp = false      -- last known shield state (exact out of combat, from events in combat)
local native = { container = nil, button = nil, fs = nil, cd = nil, bar = nil, ticks = nil, overlay = nil,
	err = nil, ids = {} }

-- The underlay is only ever visible when Blizzard's button is hidden, i.e. when the shield is down,
-- so grey and tint apply unconditionally. The engine does not tell us about the hide in combat, so
-- the ring (which would bleed through a translucent icon) follows our belief instead.
local function applyEmptyLook()
	shield.tex:SetDesaturated(db.emptyGrey)
	if db.emptyTint then shield.tex:SetVertexColor(1, 0.35, 0.35) else shield.tex:SetVertexColor(1, 1, 1) end
	shield:SetRingShown(not believedUp and db.emptyRing)
end

local function setBelievedUp(up)
	believedUp = up
	applyEmptyLook()
end

local function shieldIDMap()
	local map = {}
	for _, id in ipairs(VANILLA_SHIELD_IDS) do map[id] = true end
	for id in pairs(native.ids) do map[id] = true end
	if shieldSpellID then map[shieldSpellID] = true end
	if shieldAuraSpellID then map[shieldAuraSpellID] = true end
	return map
end

local function learnShieldID(id)
	if not id or isSecret(id) or native.ids[id] then return end
	native.ids[id] = true
	if native.container and not native.err and not InCombatLockdown() then
		pcall(native.container.SetAuraSlotCandidateFilters, native.container, "shield", { includeSpellIDs = shieldIDMap() })
	end
end

-- Blizzard's button and its parts are off limits to addon code in combat; defer until it ends.
local nativeStylePending = false
local function styleNative()
	if not native.button then return end
	if InCombatLockdown() then nativeStylePending = true return end
	nativeStylePending = false
	pcall(function()
		local size = db.iconSize
		native.container:SetSize(size, size)
		native.button:SetSize(size, size)
		for i, t in ipairs(native.tickTextures or {}) do
			t:ClearAllPoints()
			t:SetPoint("TOP", native.ticks, "TOPLEFT", size * i / native.maxCharges, 0)
			t:SetPoint("BOTTOM", native.ticks, "BOTTOMLEFT", size * i / native.maxCharges, 0)
		end
		native.bar:SetAlpha(db.showBar and 1 or 0)
		native.ticks:SetAlpha(db.showBar and 1 or 0)
		native.fs:SetAlpha(db.showCount and 1 or 0)
		native.fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
		native.fs:ClearAllPoints()
		if db.countPos == "center" then
			native.fs:SetPoint("CENTER", native.button, "CENTER", 0, 0); native.fs:SetJustifyH("CENTER")
		else
			native.fs:SetPoint("BOTTOMRIGHT", native.button, "BOTTOMRIGHT", 2, -2); native.fs:SetJustifyH("RIGHT")
		end
		native.cd:SetCountdownFont(CD_FONT)
		native.cd:SetHideCountdownNumbers(true)
	end)
end

-- Called by Blizzard (untainted) once, right after it creates the slot button.
local function initNativeButton(button)
	local size = db.iconSize
	button:SetSize(size, size)
	-- Slot frames are positioned by the caller, not by the container's flow layout.
	button:SetPoint("TOPLEFT", button:GetParent(), "TOPLEFT", 0, 0)
	-- No tooltip and click-through: disable mouse input before Blizzard locks the button down.
	pcall(button.EnableMouse, button, false)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)

	local tex = button:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(tex)

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetCountdownFont(CD_FONT)
	cd:SetHideCountdownNumbers(true)
	button:SetDurationCooldown(cd)
	native.cd = cd

	-- Our parts live on an overlay frame above the cooldown so nothing Blizzard hides takes them along.
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
	native.overlay = overlay

	-- Blizzard writes the count immediately on registration, so the font must already be set.
	local fs = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
	fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
	if db.countPos == "center" then
		fs:SetPoint("CENTER", button, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
	else
		fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2); fs:SetJustifyH("RIGHT")
	end
	button:SetApplicationCount(fs)
	native.fs = fs

	-- Charge bar along the bottom edge: min 0 so one charge is one third, not empty.
	local bar = CreateFrame("StatusBar", nil, overlay)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(7)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetStatusBarColor(0.35, 0.75, 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	local maxCharges = 3
	button:SetApplicationBar(bar, { minApplications = 0, maxApplications = maxCharges })
	native.bar = bar
	local ticks = CreateFrame("Frame", nil, overlay)
	ticks:SetAllPoints(bar)
	ticks:SetFrameLevel(bar:GetFrameLevel() + 1)
	native.tickTextures, native.maxCharges = {}, maxCharges
	for i = 1, maxCharges - 1 do
		local t = ticks:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.9)
		t:SetWidth(1)
		t:SetPoint("TOP", ticks, "TOPLEFT", size * i / maxCharges, 0)
		t:SetPoint("BOTTOM", ticks, "BOTTOMLEFT", size * i / maxCharges, 0)
		table.insert(native.tickTextures, t)
	end
	native.ticks = ticks

	-- Note: script handlers on anything under Blizzard's button never run (tested: OnShow/OnHide on a
	-- child frame fired zero times), so there is no way to learn when the button hides.

	bar:SetAlpha(db.showBar and 1 or 0)
	ticks:SetAlpha(db.showBar and 1 or 0)
	fs:SetAlpha(db.showCount and 1 or 0)
	native.button = button
end

local function setupNative()
	if native.container or native.err or InCombatLockdown() then return end
	local ok, err = pcall(function()
		local c = CreateFrame("AuraContainer", "ShamanForeverAuraContainer", shield, "CustomAuraContainerTemplate")
		c:SetPoint("TOPLEFT", shield, "TOPLEFT", 0, 0)
		c:SetSize(db.iconSize, db.iconSize)
		c:SetFrameStrata("HIGH")   -- intrinsic frames do not sit where you expect; force it above the underlay
		c:SetFrameLevel(20)
		c:SetUnit("player")
		native.container = c
		c:AddAuraSlot("shield", "HELPFUL", {
			candidateFilters = { includeSpellIDs = shieldIDMap() },
			initializeFrame = initNativeButton,
		})
	end)
	if not ok then
		native.err = tostring(err)
		if native.container then native.container:Hide() end
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", native.err)
	end
end

-- Out of combat the aura is readable: sync our belief and learn the live spell ID.
local function refreshShield()
	if not shieldSpellID or InCombatLockdown() then return end
	local ok, aura = safe(C_UnitAuras.GetAuraDataBySpellName, "player", SHIELD_NAME, "HELPFUL")
	if not ok then return end
	setBelievedUp(aura ~= nil)
	if aura then
		if not isSecret(aura.spellId) then shieldAuraSpellID = aura.spellId; learnShieldID(aura.spellId) end
	end
end

------------------------------------------------------------------------
-- Shock
------------------------------------------------------------------------
local shockSpellID, manaSpellID
local shockIDs = {}
local shockState = { outOfRange = false, noMana = false }

-- Shock looks, fixed rule: out of range paints the body red; not enough mana paints the body blue
-- and adds a blue ring; when both apply the body is red (range) and the ring blue (mana).
local function paintBody(style, r, g, b, overlayAlpha, tintStrength)
	if style == "overlay" or style == "both" then
		shock.manaOverlay:SetColorTexture(r, g, b, overlayAlpha)
		shock.manaOverlay:Show()
	end
	if style == "tint" or style == "both" then
		local k = 1 - tintStrength
		shock.tex:SetVertexColor(r == 1 and 1 or k, g == 1 and 1 or k, b == 1 and 1 or k)
	end
end

local function updateShockTint()
	shock.manaOverlay:Hide()
	shock.tex:SetVertexColor(1, 1, 1)
	if shockState.outOfRange then
		paintBody(db.rangeStyle, 1, 0.25, 0.25, db.rangeIntensity, db.rangeTint)
	elseif shockState.noMana then
		paintBody(db.manaStyle, 0.2, 0.45, 1, db.manaIntensity, db.manaTint)
	end
	shock:SetRingShown(shockState.noMana, 0.2, 0.45, 1, db.manaRing)
end

local function refreshShockCooldown()
	if not shockSpellID then return end
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, shockSpellID)
	if ok and dur then pcall(shock.cd.SetCooldownFromDurationObject, shock.cd, dur) end
end

local function refreshShockRange()
	if not shockSpellID then return end
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	updateShockTint()
end

local function refreshShockMana()
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ok and not isSecret(noPower) and noPower == true
	updateShockTint()
end

------------------------------------------------------------------------
-- Spell resolution and layout
------------------------------------------------------------------------
local function resolveSpells()
	scanSpellbook()
	local icon
	shieldSpellID, icon = knownSpell(SHIELD_NAME)
	shield.tex:SetTexture(icon or 136051)
	shockIDs = {}
	for key, name in pairs(SHOCKS) do
		local id = knownSpell(name)
		if id then shockIDs[key] = id end
	end
	local id, ic = knownSpell(SHOCKS[db.shock] or SHOCKS.earth)
	shockSpellID = id
	shock.tex:SetTexture(ic or 136026)
	manaSpellID = (db.manaSpell ~= "tracked" and shockIDs[db.manaSpell]) or shockSpellID
	if shockSpellID and C_Spell.EnableSpellRangeCheck then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
	if shieldSpellID then learnShieldID(shieldSpellID) end
end

-- Combat-only visibility uses Blizzard's secure state driver, the standard technique for this.
-- root is an ancestor of Blizzard's protected aura button, so an addon Show/Hide/SetAlpha on it is
-- silently dropped in combat (tested: alpha 0 out of combat never came back). The driver's manager
-- shows and hides the frame from untainted code instead. It only needs SecureCmdOptionParse, not a
-- compiled snippet, so it survives this build's missing loadstring_untainted. Registering with the
-- manager is itself done out of combat. An unlocked frame is never driven, so it can be dragged.
local visibilityPending = false
local driverActive = false
local function applyVisibility()
	if InCombatLockdown() then visibilityPending = true return end
	visibilityPending = false
	local want = db.combatOnly and db.locked
	if want == driverActive then return end
	if want then
		if not RegisterStateDriver then say("state driver unavailable on this client; cannot hide out of combat") return end
		local ok, err = pcall(RegisterStateDriver, root, "visibility", "[combat] show; hide")
		if not ok then say("state driver failed: %s", tostring(err)); return end
	else
		pcall(UnregisterStateDriver, root, "visibility")
		root:Show()
	end
	driverActive = want
end

local function applyLayout()
	root:ClearAllPoints()
	root:SetPoint(db.point, UIParent, db.point, db.x, db.y)
	root:SetAlpha(db.alpha)
	root:SetScale(db.scale)
	if db.locked then
		root:EnableMouse(false)
		root:SetBackdropColor(0, 0, 0, 0)
		root:SetBackdropBorderColor(0, 0, 0, 0)
		root.label:Hide()
	else
		root:EnableMouse(true)
		root:SetBackdropColor(0, 0, 0, 0.4)
		root:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
		root.label:Show()
	end
	layoutIcons()
	applyVisibility()
	cdFont:SetFont(STANDARD_TEXT_FONT, db.cdTextSize, "OUTLINE")
	shock.cd:SetCountdownFont(CD_FONT)
	shock.cd:SetHideCountdownNumbers(not db.cdText)
	refreshShockMana()
	if not native.container then setupNative() end
	styleNative()
	applyEmptyLook()
end

local function refreshAll()
	refreshShield()
	refreshShockCooldown()
	refreshShockRange()
	refreshShockMana()
end

-- Shared with ShamanForever_Options.lua
ns.DEFAULTS, ns.SHOCKS, ns.SHOCK_ORDER = DEFAULTS, SHOCKS, SHOCK_ORDER
ns.ICONS, ns.ICON_KEYS, ns.iconOrder = ICONS, ICON_KEYS, iconOrder
ns.getDB = function() return db end
ns.applyLayout, ns.resolveSpells, ns.refreshAll = applyLayout, resolveSpells, refreshAll
ns.applyVisibility = applyVisibility
ns.say = say

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(event, unit)
	local ok = pcall(function()
		if unit then ev:RegisterUnitEvent(event, unit) else ev:RegisterEvent(event) end
	end)
	if not ok then say("event %s not available on this client", event) end
end

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")

ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		-- One-time migration from the addon's earlier name.
		if ShamanForeverDB == nil and type(ForeverShamanDB) == "table" then ShamanForeverDB = ForeverShamanDB end
		ShamanForeverDB = ShamanForeverDB or {}
		db = ShamanForeverDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = type(v) == "table" and CopyTable(v) or v end
		end
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "PLAYER_LOGIN" then
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then root:Hide(); return end
		reg("UNIT_AURA", "player")
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("SPELL_UPDATE_USABLE")
		reg("UNIT_POWER_UPDATE", "player")
		reg("PLAYER_TARGET_CHANGED")
		reg("SPELLS_CHANGED")
		reg("PLAYER_REGEN_ENABLED")
		reg("SPELL_RANGE_CHECK_UPDATE")
		resolveSpells()
		applyLayout()
		refreshAll()
		C_Timer.NewTicker(0.25, refreshShockRange)
		root:Show()
	elseif event == "UNIT_AURA" then
		refreshShield()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3   -- args: unit, castGUID, spellID
		if not isSecret(spellID) and (spellID == shieldSpellID or spellID == shieldAuraSpellID) then
			setBelievedUp(true)  -- our own cast events stay readable in combat
		end
		refreshShockCooldown()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		refreshShockCooldown()
	elseif event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then
		refreshShockMana()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "SPELL_RANGE_CHECK_UPDATE" then
		refreshShockRange()
	elseif event == "SPELLS_CHANGED" then
		resolveSpells()
		applyLayout()
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if visibilityPending then applyVisibility() end
		if nativeStylePending then styleNative() end
		refreshAll()
	end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_SHAMANFOREVER1 = "/sf"
SLASH_SHAMANFOREVER2 = "/shf"
SlashCmdList.SHAMANFOREVER = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "lock" then db.locked = true; applyLayout(); say("locked")
	elseif cmd == "unlock" then db.locked = false; applyLayout(); say("unlocked: drag the frame")
	elseif cmd == "alpha" then
		local a = tonumber(arg)
		if a and a > 0 and a <= 1 then db.alpha = a; applyLayout(); say("alpha %.2f", a) else say("usage: /sf alpha 0.1-1") end
	elseif cmd == "scale" then
		local s = tonumber(arg)
		if s and s >= 0.5 and s <= 3 then db.scale = s; applyLayout(); say("scale %.2f", s) else say("usage: /sf scale 0.5-3") end
	elseif cmd == "combat" then
		arg = arg:lower()
		if arg == "on" then db.combatOnly = true
		elseif arg == "off" then db.combatOnly = false
		elseif arg == "" or arg == "toggle" then db.combatOnly = not db.combatOnly
		else say("usage: /sf combat on|off"); return end
		applyVisibility()
		say(db.combatOnly and "shown only in combat%s" or "shown all the time",
			(db.combatOnly and not db.locked) and " (once locked)" or "")
	elseif cmd == "shock" then
		arg = arg:lower()
		if SHOCKS[arg] then db.shock = arg; resolveSpells(); refreshAll(); say("shock icon now %s", SHOCKS[arg])
		else say("usage: /sf shock earth|flame|frost") end
	elseif cmd == "reset" then
		for k, v in pairs(DEFAULTS) do db[k] = type(v) == "table" and CopyTable(v) or v end
		resolveSpells(); applyLayout(); refreshAll(); say("reset")
	elseif cmd == "debug" then
		say("shield spell %s (aura spell %s), shock spell %s (%s), mana spell %s, believed up %s, in combat %s, combat only %s",
			tostring(shieldSpellID), tostring(shieldAuraSpellID), tostring(shockSpellID), db.shock,
			tostring(manaSpellID), tostring(believedUp), tostring(InCombatLockdown()), tostring(db.combatOnly))
		local e = book[SHIELD_NAME]
		say("spellbook: %s rank %s", SHIELD_NAME, e and e.rank or "?")
		say("aura container %s%s", native.container and "created" or "not created",
			native.err and (", error: " .. native.err) or "")
		local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
		say("tracked spell IDs: %s", table.concat(t, ","))
		for key, id in pairs(shockIDs) do
			local ok, usable, noPower = safe(C_Spell.IsSpellUsable, id)
			local _, r = safe(C_Spell.IsSpellInRange, id, "target")
			say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
				book[SHOCKS[key]] and book[SHOCKS[key]].rank or "?", describeArg(usable), describeArg(noPower), describeArg(r))
		end
	elseif cmd == "" or cmd == "options" or cmd == "config" then
		if ns.OpenOptions then ns.OpenOptions() else say("options panel unavailable") end
	else
		say("commands (/sf or /shf): options, lock, unlock, alpha <0.1-1>, scale <0.5-3>, combat <on|off>, shock <earth|flame|frost>, reset, debug")
	end
end
