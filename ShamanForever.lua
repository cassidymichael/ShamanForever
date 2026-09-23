-- ShamanForever: shaman HUD (Lightning or Water Shield, shock, weapon imbue, totem cooldowns) for the WoW: Forever beta.
--
-- Rule for this client: never do Lua math or comparisons on a possibly-secret value. In combat, show
-- state through Blizzard's own widgets instead: the aura container for the shield, duration objects
-- for cooldowns and totem timers, curves and SetAlpha for anything that must appear or disappear.
-- The only inference anywhere is the shield's in-combat "up" state; its section explains it.

local ADDON, ns = ...
local PREFIX = "|cff3399ffShamanForever|r: "
local function say(fmt, ...) print(PREFIX .. string.format(fmt, ...)) end

-- Elemental shields. Only one can be on the shaman at a time (Water Shield's tooltip says so), so one
-- element shows whichever is up. Water Shield is a Restoration talent on Forever; 408510 is both its
-- cast and its buff (wowhead.com/forever). Spellbook and live aura IDs are added at runtime.
local SHIELDS = {
	lightning = { name = "Lightning Shield", ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, icon = 136051 },
	water     = { name = "Water Shield",     ids = { 408510 },                                 icon = 132315 },
}
local SHIELD_ORDER = { "lightning", "water" }
local SHOCKS = { earth = "Earth Shock", flame = "Flame Shock", frost = "Frost Shock" }
local SHOCK_ORDER = { "earth", "flame", "frost" }
local CD_FONT = "ShamanForeverCDFont"

-- Every element belongs to exactly one group, which owns its position, scale, opacity and flow;
-- whether the element is drawn (always, in combat, never) is its own setting in db.elementOpts.
-- Positions are offsets in the group's own (scaled) units.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.65,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	spacing = 10,
	combatOnly = false,          -- hide the group out of combat (always shown while unlocked)
}

-- Settings for the whole account, outside profiles: how the player works with the addon, and what
-- it has learned about the game.
local ACCOUNT_DEFAULTS = {
	locked = true,
	testMode = false,       -- register placeholder elements for trying out layouts
	snap = false,           -- unlocked drags snap to other groups, the screen centre and the grid
	grid = false,           -- grid over the screen while unlocked
	gridSize = 32,
	hideIssueReporter = false,  -- beta: hide Blizzard's Issue Reporter button (its position is kept either way)
	minimalArt = false,     -- options window without banners and ornaments; kept ready, no control for now
	lastShield = "lightning",  -- the shield last cast or seen; its icon is the no-shield look in "either" mode
	imbueIDs = {},            -- learned enchant ID -> imbue key
	totemLifetimes = {},      -- learned totem lifetime in seconds, by cooldown element key
	profiles = {},            -- name -> settings (DEFAULTS below)
	chars = {},               -- "Name-Realm" -> { profile = name }
}
local DEFAULT_PROFILE = "Default"

-- A profile: the layout and how every element looks.
local DEFAULTS = {
	iconSize = 40,          -- base element size; each group scales it
	border = { show = true, size = 1, color = { 0, 0, 0, 1 } },   -- around every element; a group can override (g.border)
	-- Default layout (the author's, 2026-09-23): shield, shock and Fire Nova under the character,
	-- the imbue below-left, the earth totems further left.
	groups = {
		{ point = "CENTER", x = 0, y = -216, scale = 0.98, alpha = 0.65, orientation = "horizontal",
			growth = "forward", spacing = 10, members = { "shield", "shock", "firenova" } },
		{ point = "CENTER", x = -176, y = -265, scale = 1, alpha = 0.65, orientation = "horizontal",
			growth = "forward", spacing = 10, members = { "imbue" } },
		{ point = "CENTER", x = -310, y = -174, scale = 0.93, alpha = 0.65, orientation = "horizontal",
			growth = "forward", spacing = 10, members = { "earthbind", "stoneclaw" } },
	},
	known = {},             -- element keys placed at least once; new ones join the first group
	elementOpts = {},       -- per-element settings by key, e.g. { shock = { show = "combat" } }
	-- shield
	shieldTrack = "lightning", -- lightning | water | either: which shield counts as "up" (water and either are experimental)
	countPos = "center",    -- corner | center
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	showCount = false,      -- charge number (Blizzard prints it for two or more); the charge bar shows it anyway
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	emptyPulse = true,
	underlayUp = 0.25,      -- underlay strength while the shield is believed up (0 = none)
	shieldSwipe = 0.5,      -- darkness of the duration swipe over the shield icon (0 = no swipe)
	shieldIconAlpha = 1,    -- manual multiplier on the compensated shield icon alpha
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
	-- weapon imbue
	imbuePreferred = "last",  -- icon while none is on: last | rockbiter | flametongue | frostbrand | windfury
	imbueMissingRing = true,
	imbueMissingGrey = true,
	imbuePulse = true,
	imbueWarnMins = 5,        -- show time left below this many minutes (0 = never)
	imbueTextSize = 16,
	imbueHideActive = true,   -- while an imbue is on, only show once its time left shows
}
-- Pre-groups layout keys, folded into a single group on first load.
local LEGACY_KEYS = { "point", "x", "y", "alpha", "scale", "size", "spacing", "orientation", "growth", "order", "enabled" }
-- Saved settings format. Bump it and add a step on ADDON_LOADED when a stored value must change.
local SETTINGS_VERSION = 4
local acct       -- ShamanForeverDB: account settings, and every profile
local db         -- the active profile
local profileName

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

-- root spans the screen and takes no input: the parent of every group (each anchored to UIParent),
-- hidden as a whole for other classes. Not the old
-- ShamanForeverFrame name: that frame was dragged, so the client's layout cache would re-anchor it.
local root = CreateFrame("Frame", "ShamanForeverRoot", UIParent)
root:SetAllPoints(UIParent)

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
	-- Pulse: the icon fades in and out, used for "missing" warnings.
	f.pulse = f.tex:CreateAnimationGroup()
	f.pulse:SetLooping("BOUNCE")
	local fade = f.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.8)
	fade:SetSmoothing("IN_OUT")
	f.SetPulsing = function(self, on)
		if not on then self.pulse:Stop()
		elseif not self.pulse:IsPlaying() then self.pulse:Play() end
	end
	f.SetRingShown = function(self, shown, r, g, b, a)
		for _, t in ipairs(self.ring) do
			if shown then t:SetColorTexture(r or 1, g or 0, b or 0, a or 0.9); t:Show() else t:Hide() end
		end
	end
	return f
end

local shield = makeIcon(root, DEFAULTS.iconSize)
shield.count:Hide()

local shock = makeIcon(root, DEFAULTS.iconSize)
shock.count:Hide()

local imbue = makeIcon(root, DEFAULTS.iconSize)
imbue.count:Hide()

-- Cooldown elements: a spell's cooldown, plus for a totem the active time of ours in its slot, or for
-- Fire Nova whether the fire totem it needs is out. Totem slots: 1 fire, 2 earth, 3 water, 4 air.
-- Adding one is a line here; icon is the fallback until the spellbook has the spell, duration the
-- totem's lifetime in seconds until one is learned out of combat (see refreshCooldown).
local COOLDOWNS = {
	{ key = "earthbind", spell = "Earthbind Totem", icon = 136102, totemSlot = 2, duration = 45 },
	{ key = "stoneclaw", spell = "Stoneclaw Totem", icon = 136097, totemSlot = 2, duration = 15 },
	{ key = "firenova",  spell = "Fire Nova",       icon = 135824, needsTotem = 1 },
}
local ACTIVE_FONT = "ShamanForeverActiveFont"
local activeFont = CreateFont(ACTIVE_FONT)

for _, def in ipairs(COOLDOWNS) do
	local f = makeIcon(root, DEFAULTS.iconSize)
	f.count:Hide()
	f.tex:SetTexture(def.icon)
	if def.totemSlot or def.needsTotem then
		-- A totem's active time (its own, or for Fire Nova whichever fire totem is out), as a draining
		-- bar along the bottom and small numbers in the top-left corner. Both take the totem's duration
		-- object, so the time itself is never read. They share a holder so one alpha can hide both.
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.active = CreateFrame("StatusBar", nil, f.activeHolder)
		f.active:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
		f.active:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
		f.active:SetHeight(5)
		f.active:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		f.active:SetStatusBarColor(0.4, 0.9, 0.3)
		f.active.bg = f.active:CreateTexture(nil, "BACKGROUND")
		f.active.bg:SetAllPoints()
		f.active.bg:SetColorTexture(0, 0, 0, 0.6)
		f.active:Hide()
		f.activeCD = CreateFrame("Cooldown", nil, f.activeHolder, "CooldownFrameTemplate")
		f.activeCD:SetAllPoints()
		f.activeCD:SetDrawSwipe(false)
		f.activeCD:SetDrawEdge(false)
		f.activeCD:SetDrawBling(false)
		f.activeCD:SetCountdownFont(ACTIVE_FONT)
		local ok, fs = pcall(f.activeCD.GetCountdownFontString, f.activeCD)
		if ok and fs then
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
		end
	end
	if def.needsTotem then
		-- "No totem" warning layer: a grey copy of the icon and a red ring, above the icon and below the
		-- cooldown swipe. Its alpha is set from a possibly-secret boolean (see refreshCooldown), so it
		-- always pulses and is simply invisible while a totem is out.
		f.warn = CreateFrame("Frame", nil, f)
		f.warn:SetAllPoints()
		f.warn:SetFrameLevel(f:GetFrameLevel() + 1)
		f.cd:SetFrameLevel(f.warn:GetFrameLevel() + 1)
		f.warn.grey = f.warn:CreateTexture(nil, "ARTWORK")
		f.warn.grey:SetAllPoints(f.tex)
		f.warn.grey:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.warn.grey:SetDesaturated(true)
		f.warn.ring = {}
		for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 3 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 3 },
				{ "TOPLEFT", "BOTTOMLEFT", 3, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 3, nil } }) do
			local t = f.warn:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(1, 0, 0, 0.9)
			t:SetPoint(e[1], f.tex, e[1], 0, 0)
			t:SetPoint(e[2], f.tex, e[2], 0, 0)
			if e[3] then t:SetWidth(e[3]) end
			if e[4] then t:SetHeight(e[4]) end
			table.insert(f.warn.ring, t)
		end
		f.warn.pulse = f.warn.grey:CreateAnimationGroup()
		f.warn.pulse:SetLooping("BOUNCE")
		local fade = f.warn.pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.35)
		fade:SetDuration(0.8)
		fade:SetSmoothing("IN_OUT")
		f.warn:SetAlpha(0)
	end
	def.frame = f
end

-- Placeholder elements for trying out layouts, available only in test mode. Sizes are multiples of
-- the icon size, with one wide and one tall shape to exercise non-square layout.
local PLACEHOLDERS = {
	{ key = "testA", letter = "A", color = { 0.85, 0.25, 0.25 }, w = 1, h = 1 },
	{ key = "testB", letter = "B", color = { 0.25, 0.7, 0.3 }, w = 1, h = 1 },
	{ key = "testC", letter = "C", color = { 0.3, 0.45, 0.9 }, w = 1, h = 1 },
	{ key = "testD", letter = "D", color = { 0.85, 0.7, 0.2 }, w = 2.5, h = 0.5 },
	{ key = "testE", letter = "E", color = { 0.65, 0.3, 0.8 }, w = 0.5, h = 1.5 },
}

local function makePlaceholder(p)
	local f = CreateFrame("Frame", nil, root)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetColorTexture(p.color[1], p.color[2], p.color[3], 0.9)
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	f.text:SetPoint("CENTER")
	f.text:SetText(p.letter)
	f:Hide()
	return f
end

local shockIcon = 136026

-- Element registry. db.groups decides where each one shows. Each entry owns its size, so elements
-- need not be square, and paints a texture that stands in for it in the unlock tray and while dragging.
local function iconSize() return db.iconSize, db.iconSize end
local ELEMENTS = {
	shield = { frame = shield, label = "Shields",          getSize = iconSize, paint = function(t) t:SetTexture(ns.shieldIcon()) end },
	shock  = { frame = shock,  label = "Shocks",           getSize = iconSize, paint = function(t) t:SetTexture(shockIcon) end },
	imbue  = { frame = imbue,  label = "Weapon Imbue",     getSize = iconSize, paint = function(t) t:SetTexture(ns.imbueIcon()) end },
}
local ELEMENT_KEYS = { "shield", "shock", "imbue" }   -- registration order
for _, def in ipairs(COOLDOWNS) do
	ELEMENTS[def.key] = { frame = def.frame, label = def.spell, getSize = iconSize, cooldown = def,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end }
	table.insert(ELEMENT_KEYS, def.key)
end
for _, p in ipairs(PLACEHOLDERS) do
	local c = p.color
	ELEMENTS[p.key] = { frame = makePlaceholder(p), label = "Test " .. p.letter, placeholder = true,
		getSize = function() return db.iconSize * p.w, db.iconSize * p.h end,
		paint = function(t) t:SetColorTexture(c[1], c[2], c[3], 0.9) end }
	table.insert(ELEMENT_KEYS, p.key)
end

------------------------------------------------------------------------
-- Groups
------------------------------------------------------------------------
local function available(key)
	local e = ELEMENTS[key]
	return e ~= nil and (not e.placeholder or acct.testMode)
end

-- Group index and position of an element. Every available element sits in a group; whether it is
-- drawn is its own "show" setting, so hiding one keeps its place.
local function findElement(key)
	for gi, g in ipairs(db.groups) do
		for i, k in ipairs(g.members) do if k == key then return gi, i end end
	end
end

local function elementOpts(key)
	local o = db.elementOpts[key]
	if not o then o = {}; db.elementOpts[key] = o end
	return o
end

-- always | combat | never
local function showMode(key) return elementOpts(key).show or "always" end

local function isEnabled(key) return findElement(key) ~= nil and showMode(key) ~= "never" end

local function removeElement(key)
	local gi, i = findElement(key)
	if gi then table.remove(db.groups[gi].members, i) end
end

local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do g[k] = template and template[k] or v end
	if template and template.border then g.border = CopyTable(template.border) end
	g.members = {}
	table.insert(db.groups, g)
	return g
end

local function pruneGroups()
	for gi = #db.groups, 1, -1 do
		if #db.groups[gi].members == 0 then table.remove(db.groups, gi) end
	end
end

-- Makes db.groups consistent: fills missing group fields, drops unknown, unavailable and duplicate
-- members, and places every element that is in no group. Elements never seen before (new in an
-- update, or test ones) show; ones seen before were hidden under the old rule, so they come back
-- into the first group set to never show.
local function sanitize()
	if db.shieldTrack ~= "either" and not SHIELDS[db.shieldTrack] then db.shieldTrack = "lightning" end
	if not SHIELDS[acct.lastShield] then acct.lastShield = "lightning" end
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		local kept = {}
		for _, key in ipairs(type(g.members) == "table" and g.members or {}) do
			if available(key) and not seen[key] then
				table.insert(kept, key)
				seen[key], db.known[key] = true, true
			end
		end
		g.members = kept
	end
	pruneGroups()
	local fresh, freshTest = {}, {}
	for _, key in ipairs(ELEMENT_KEYS) do
		if available(key) and not seen[key] then
			if not db.known[key] then
				table.insert(ELEMENTS[key].placeholder and freshTest or fresh, key)
				db.known[key] = true
			else
				elementOpts(key).show = "never"
				table.insert(fresh, key)
			end
		end
	end
	if #fresh > 0 then
		local g = db.groups[1] or newGroup()
		for _, key in ipairs(fresh) do table.insert(g.members, key) end
	end
	if #freshTest > 0 then
		local g = newGroup(db.groups[1])
		g.point, g.x, g.y = "CENTER", 0, -40
		g.members = freshTest
	end
end

-- Test elements are forgotten when switched off, so switching back on puts them in a fresh group.
local function setTestMode(on)
	acct.testMode = on
	if not on then
		for _, prof in pairs(acct.profiles) do
			for _, p in ipairs(PLACEHOLDERS) do if type(prof.known) == "table" then prof.known[p.key] = nil end end
		end
	end
	sanitize()
end

-- Places a group so its centre sits at screen coordinates (the units GetCursorPosition returns).
local function setGroupCenter(g, sx, sy)
	local ui = UIParent:GetEffectiveScale()
	local w, h = UIParent:GetSize()
	g.point = "CENTER"
	g.x = (sx / ui - w / 2) / g.scale
	g.y = (sy / ui - h / 2) / g.scale
end

local function screenCenter(f)
	local x, y = f:GetCenter()
	if not x then return nil end
	local s = f:GetEffectiveScale()
	return x * s, y * s
end

local groupFrames = {}
local groupFrameScripts   -- unlock-mode handlers, assigned below

local function groupFrame(gi)
	local f = groupFrames[gi]
	if f then return f end
	f = CreateFrame("Frame", nil, root, "BackdropTemplate")
	f:SetSize(1, 1)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	f.label:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.index = gi
	groupFrameScripts(f)
	groupFrames[gi] = f
	return f
end

-- Combat-only visibility uses Blizzard's secure state driver, the standard technique for this. The
-- shield's group and element frames are ancestors of Blizzard's protected aura button, so an addon
-- Show/Hide/SetAlpha on them is silently dropped in combat (tested: alpha 0 out of combat never came
-- back). The driver's manager shows and hides from untainted code instead; its visibility path
-- needs only SecureCmdOptionParse, not a compiled snippet, so it survives this build's missing
-- loadstring_untainted. Groups and elements are driven separately, so an element shows only when
-- both allow it. The manager re-applies its state every 0.2s and does not show a frame it lets go
-- of, so a driven frame is never shown or hidden by hand. Only called out of combat.
local driven = {}
local function setDriven(frame, want)
	if want == (driven[frame] or false) then return end
	if want then
		local ok, err = pcall(RegisterStateDriver, frame, "visibility", "[combat] show; hide")
		if not ok then say("state driver failed: %s", tostring(err)); return end
		driven[frame] = true
	else
		pcall(UnregisterStateDriver, frame, "visibility")
		driven[frame] = nil
	end
end

-- Shows a frame, or hands it to the driver when it should only show in combat.
local function showFrame(frame, combatOnly)
	setDriven(frame, combatOnly)
	if not combatOnly then frame:Show() end
end

local function hideFrame(frame)
	setDriven(frame, false)
	frame:Hide()
end

-- Border drawn just outside an element's edge, so it never covers the rings inside the icon or
-- Blizzard's shield button. size is in physical pixels, so 1 stays one crisp pixel at any scale.
local function applyBorder(f, b)
	if not (b and b.show and b.size and b.size > 0) then
		if f.border then for _, t in ipairs(f.border) do t:Hide() end end
		return
	end
	if not f.border then
		f.border = {}
		for i = 1, 4 do f.border[i] = f:CreateTexture(nil, "BACKGROUND", nil, -8) end
	end
	local _, physicalHeight = GetPhysicalScreenSize()
	local px = (768 / (physicalHeight or 768)) / f:GetEffectiveScale()
	local s = b.size * px
	local c = b.color or { 0, 0, 0, 1 }
	local top, bottom, left, right = f.border[1], f.border[2], f.border[3], f.border[4]
	for _, t in ipairs(f.border) do
		t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
		t:ClearAllPoints()
		t:Show()
	end
	-- Top and bottom span the corners; left and right fill between them.
	top:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -s, 0)
	top:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", s, 0)
	top:SetHeight(s)
	bottom:SetPoint("TOPLEFT", f, "BOTTOMLEFT", -s, 0)
	bottom:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", s, 0)
	bottom:SetHeight(s)
	left:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", 0, 0)
	left:SetWidth(s)
	right:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(s)
end

-- Sizes and anchors a group's members in one pass, centred on the cross axis; the group frame
-- shrinks to fit so dragging feels right.
local function layoutGroup(gi)
	local g, gf = db.groups[gi], groupFrame(gi)
	local gap = g.spacing
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local prev, n, along, across = nil, 0, 0, 0
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		if showMode(key) == "never" then
			hideFrame(f)
		else
			local w, h = e.getSize()
			f:SetSize(w, h)
			f:ClearAllPoints()
			if horizontal then
				if not prev then
					local edge = forward and "LEFT" or "RIGHT"
					f:SetPoint(edge, gf, edge, 0, 0)
				elseif forward then f:SetPoint("LEFT", prev, "RIGHT", gap, 0)
				else f:SetPoint("RIGHT", prev, "LEFT", -gap, 0) end
				along, across = along + w, math.max(across, h)
			else
				if not prev then
					local edge = forward and "TOP" or "BOTTOM"
					f:SetPoint(edge, gf, edge, 0, 0)
				elseif forward then f:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
				else f:SetPoint("BOTTOM", prev, "TOP", 0, gap) end
				along, across = along + h, math.max(across, w)
			end
			showFrame(f, acct.locked and showMode(key) == "combat")
			prev, n = f, n + 1
		end
	end
	along = math.max(along + math.max(n - 1, 0) * gap, 1)
	across = math.max(across, 1)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetScale(g.scale)
	gf:SetAlpha(g.alpha)
	-- After the scale, so borders are sized in real pixels.
	for _, key in ipairs(g.members) do applyBorder(ELEMENTS[key].frame, g.border or db.border) end
	gf:ClearAllPoints()
	gf:SetPoint(g.point, UIParent, g.point, g.x, g.y)
	local unlocked = not acct.locked
	gf:EnableMouse(unlocked)
	gf:EnableMouseWheel(unlocked)
	gf:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	gf:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0)
	gf.label:SetText("Group " .. gi)
	gf.label:SetShown(unlocked)
	if n > 0 then showFrame(gf, acct.locked and g.combatOnly or false) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected aura button, so
-- showing, hiding, moving or reparenting it in combat is silently dropped.
local styleNative, updateTray   -- defined further down
local layoutPending = false
local function layoutElements()
	if InCombatLockdown() then layoutPending = true return end
	layoutPending = false
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	for gi in ipairs(db.groups) do layoutGroup(gi) end
	for gi = #db.groups + 1, #groupFrames do hideFrame(groupFrames[gi]) end
	styleNative()   -- the shield's alpha compensation follows its group's opacity
	updateTray()
	if ns.RefreshOptions then ns.RefreshOptions() end
end

------------------------------------------------------------------------
-- Unlock mode: drag a group to move it (snapping to the grid and to other groups), wheel for scale
-- and opacity, right-click for its settings. Group membership is edited in the options window.
------------------------------------------------------------------------
local isShaman = false
local SNAP = 8   -- UI units: how close an edge must come to another group's edge or centre to snap
local function round2(v) return math.floor(v * 100 + 0.5) / 100 end
local function clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
local function uiScale() return UIParent:GetEffectiveScale() end

-- Grid over the whole screen while unlocked, measured from the screen centre in UIParent units.
local grid = CreateFrame("Frame", nil, UIParent)
grid:SetAllPoints(UIParent)
grid:SetFrameStrata("BACKGROUND")
grid:Hide()
grid.lines = {}

local function drawGrid()
	local w, h = UIParent:GetSize()
	local gs = acct.gridSize
	local n = 0
	local function line(vertical, offset)
		n = n + 1
		local t = grid.lines[n]
		if not t then t = grid:CreateTexture(nil, "BACKGROUND"); grid.lines[n] = t end
		t:ClearAllPoints()
		if offset == 0 then t:SetColorTexture(0.2, 0.6, 1, 0.5) else t:SetColorTexture(1, 1, 1, 0.1) end
		if vertical then
			t:SetPoint("TOP", grid, "TOP", offset, 0)
			t:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
			t:SetWidth(1)
		else
			t:SetPoint("LEFT", grid, "LEFT", 0, offset)
			t:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
			t:SetHeight(1)
		end
		t:Show()
	end
	for k = 0, math.floor(w / 2 / gs) do
		line(true, k * gs)
		if k > 0 then line(true, -k * gs) end
	end
	for k = 0, math.floor(h / 2 / gs) do
		line(false, k * gs)
		if k > 0 then line(false, -k * gs) end
	end
	for i = n + 1, #grid.lines do grid.lines[i]:Hide() end
end

-- Gold lines showing what a dragged group has snapped to.
local guides = CreateFrame("Frame", nil, UIParent)
guides:SetAllPoints(UIParent)
guides:SetFrameStrata("BACKGROUND")
guides:SetFrameLevel(grid:GetFrameLevel() + 5)
guides.x = guides:CreateTexture(nil, "ARTWORK")
guides.x:SetColorTexture(1, 0.82, 0, 0.8)
guides.x:SetWidth(1)
guides.y = guides:CreateTexture(nil, "ARTWORK")
guides.y:SetColorTexture(1, 0.82, 0, 0.8)
guides.y:SetHeight(1)

local function showGuides(gx, gy)
	guides.x:SetShown(gx ~= nil)
	guides.y:SetShown(gy ~= nil)
	if gx then
		guides.x:ClearAllPoints()
		guides.x:SetPoint("TOP", guides, "TOPLEFT", gx, 0)
		guides.x:SetPoint("BOTTOM", guides, "BOTTOMLEFT", gx, 0)
	end
	if gy then
		guides.y:ClearAllPoints()
		guides.y:SetPoint("LEFT", guides, "BOTTOMLEFT", 0, gy)
		guides.y:SetPoint("RIGHT", guides, "BOTTOMRIGHT", 0, gy)
	end
end

-- Snaps one axis. pos is the group's centre, half its half-extent, targets the edges and centres of
-- other groups (and the screen centre). A group target within SNAP wins and returns a guide line;
-- otherwise, with a grid, the nearest of the group's two edges and centre lands on a grid line.
local function snapAxis(pos, half, targets, origin, gs)
	local bestAbs, shift, guide = SNAP, nil, nil
	for _, t in ipairs(targets) do
		for _, e in ipairs({ -half, 0, half }) do
			local d = t - (pos + e)
			if math.abs(d) <= bestAbs then bestAbs, shift, guide = math.abs(d), d, t end
		end
	end
	if shift then return pos + shift, guide end
	if gs then
		for _, e in ipairs({ -half, 0, half }) do
			local p = pos + e
			local d = origin + math.floor((p - origin) / gs + 0.5) * gs - p
			if not shift or math.abs(d) < math.abs(shift) then shift = d end
		end
		return pos + shift
	end
	return pos
end

-- Groups are dragged by hand rather than with StartMoving so they can snap while moving.
local function dragUpdate(self)
	if InCombatLockdown() then self:SetScript("OnUpdate", nil); showGuides(); return end
	local ui = uiScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx / ui + self.dragDX, cy / ui + self.dragDY
	local gx, gy
	if acct.snap then
		local w, h = UIParent:GetSize()
		local s = self:GetEffectiveScale() / ui
		local tx, ty = { w / 2 }, { h / 2 }
		for gi = 1, #db.groups do
			local f = groupFrames[gi]
			if gi ~= self.index and f and f:IsShown() and f:GetLeft() then
				local fs = f:GetEffectiveScale() / ui
				local l, r, b, t = f:GetLeft() * fs, f:GetRight() * fs, f:GetBottom() * fs, f:GetTop() * fs
				table.insert(tx, l); table.insert(tx, (l + r) / 2); table.insert(tx, r)
				table.insert(ty, b); table.insert(ty, (b + t) / 2); table.insert(ty, t)
			end
		end
		local gs = acct.grid and acct.gridSize or nil
		x, gx = snapAxis(x, self:GetWidth() * s / 2, tx, w / 2, gs)
		y, gy = snapAxis(y, self:GetHeight() * s / 2, ty, h / 2, gs)
	end
	showGuides(gx, gy)
	local g = db.groups[self.index]
	setGroupCenter(g, x * ui, y * ui)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", g.x, g.y)
end

groupFrameScripts = function(f)
	f:SetScript("OnDragStart", function(self)
		if acct.locked or InCombatLockdown() then return end
		local ui = uiScale()
		local s = self:GetEffectiveScale() / ui
		local fx, fy = self:GetCenter()
		local cx, cy = GetCursorPosition()
		self.dragDX, self.dragDY = fx * s - cx / ui, fy * s - cy / ui
		self:SetScript("OnUpdate", dragUpdate)
	end)
	f:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		showGuides()
		if not InCombatLockdown() then layoutElements() end
	end)
	f:SetScript("OnMouseWheel", function(self, delta)
		if acct.locked or InCombatLockdown() then return end
		local g = db.groups[self.index]
		local sx, sy = screenCenter(self)
		if IsShiftKeyDown() then g.alpha = clamp(round2(g.alpha + delta * 0.05), 0.1, 1)
		else g.scale = clamp(round2(g.scale + delta * 0.05), 0.5, 3) end
		if sx then setGroupCenter(g, sx, sy) end   -- scale about the centre, not the anchor
		layoutElements()
		self.label:SetText(string.format("Group %d: scale %.2f, opacity %.0f%%", self.index, g.scale, g.alpha * 100))
	end)
	-- Right-click: the group's settings. Shift-right-click: the settings of the element under the cursor.
	f:SetScript("OnMouseUp", function(self, button)
		if button ~= "RightButton" or acct.locked or not ns.OpenOptions then return end
		if IsShiftKeyDown() then
			for _, key in ipairs(db.groups[self.index].members) do
				local e = ELEMENTS[key].frame
				if e:IsShown() and e:IsMouseOver() then ns.OpenElementOptions(key) return end
			end
		end
		ns.OpenOptions("layout", self.index)
	end)
end

-- A small bar while unlocked: what the mouse does, snapping and grid toggles, Lock and Options.
local tray = CreateFrame("Frame", "ShamanForeverTray", UIParent, "BackdropTemplate")
tray:SetSize(560, 120)
tray:SetFrameStrata("DIALOG")
tray:SetPoint("TOP", UIParent, "TOP", 0, -120)
tray:SetMovable(true)
tray:SetClampedToScreen(true)
tray:EnableMouse(true)
tray:RegisterForDrag("LeftButton")
tray:SetScript("OnDragStart", tray.StartMoving)
tray:SetScript("OnDragStop", tray.StopMovingOrSizing)
tray:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
tray:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
tray:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
tray:Hide()
do
	local title = tray:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText("ShamanForever: positioning unlocked")
	tray.hint = tray:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tray.hint:SetPoint("TOPLEFT", 10, -30)
	tray.hint:SetWidth(540)
	tray.hint:SetJustifyH("LEFT")
	tray.hint:SetSpacing(2)
	tray.hint:SetText("Drag a group to move it.\n" ..
		"Mouse wheel over a group: scale. Shift + wheel: opacity.\n" ..
		"Right-click a group: its settings.\n" ..
		"Shift-right-click an element: its own settings.\n" ..
		"Options: choose which elements each group holds.")
	-- Controls sit on a row under the hint, so a longer hint pushes them down instead of overlapping.
	local row = CreateFrame("Frame", nil, tray)
	row:SetPoint("TOPLEFT", tray.hint, "BOTTOMLEFT", 0, -10)
	row:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row:SetHeight(26)
	tray.row = row
	local function check(label, key, tip)
		local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb.Text:SetFontObject("GameFontHighlightSmall")
		cb.Text:SetText(label)
		cb:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; layoutElements() end)
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return cb
	end
	tray.snap = check("Snapping", "snap", "While dragging, groups snap to other groups' edges and centres, the screen centre, and the grid when it is shown.")
	tray.snap:SetPoint("LEFT", -4, 0)
	tray.grid = check("Show grid", "grid", "A grid over the whole screen while unlocked. With snapping on, groups snap to it.")
	tray.grid:SetPoint("LEFT", tray.snap.Text, "RIGHT", 16, 0)
	-- Grid size: - value +, in steps of 4.
	local function stepper(text, delta)
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetSize(22, 20)
		b:SetText(text)
		b:SetScript("OnClick", function()
			acct.gridSize = math.min(math.max(acct.gridSize + delta, 8), 128)
			layoutElements()
		end)
		return b
	end
	tray.gridLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tray.gridLabel:SetPoint("LEFT", tray.grid.Text, "RIGHT", 16, 0)
	tray.gridLabel:SetText("Grid size")
	tray.gridDown = stepper("-", -4)
	tray.gridDown:SetPoint("LEFT", tray.gridLabel, "RIGHT", 6, 0)
	tray.gridValue = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tray.gridValue:SetPoint("LEFT", tray.gridDown, "RIGHT", 4, 0)
	tray.gridValue:SetWidth(26)
	tray.gridUp = stepper("+", 4)
	tray.gridUp:SetPoint("LEFT", tray.gridValue, "RIGHT", 4, 0)
	local lock = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	lock:SetSize(90, 22)
	lock:SetPoint("RIGHT", 0, 0)
	lock:SetText("Lock")
	lock:SetScript("OnClick", function() acct.locked = true; ns.applyLayout() end)
	local options = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	options:SetSize(90, 22)
	options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	options:SetText("Options")
	options:SetScript("OnClick", function() if ns.OpenOptions then ns.OpenOptions("layout") end end)
end

function updateTray()
	local unlocked = isShaman and not acct.locked
	tray:SetShown(unlocked)
	tray:SetHeight(30 + tray.hint:GetStringHeight() + 10 + 26 + 10)
	tray.snap:SetChecked(acct.snap)
	tray.grid:SetChecked(acct.grid)
	tray.gridValue:SetText(acct.gridSize)
	grid:SetShown(unlocked and acct.grid)
	if unlocked and acct.grid then drawGrid() end
	if not unlocked then showGuides() end
end

------------------------------------------------------------------------
-- Shield (Lightning or Water): underlay (our "no shield" look) + Blizzard's secure aura button on top
--
-- The two shields exclude each other, so one aura slot matches every shield the player tracks
-- (db.shieldTrack) and Blizzard shows whichever is up, switching exactly when the player swaps
-- mid-fight. Both have 3 charges, so one charge bar fits both.
--
-- How it works, and the one inference it makes (reviewed 2026-09-23):
-- 1. Blizzard's CustomAuraContainer draws the shield: icon, charge count, charge bar and duration
--    swipe. Its untainted code reads the aura, so all of this is exact in combat. Sanctioned.
-- 2. Under Blizzard's button sits our underlay: the grey icon, red ring and pulse that say "no
--    shield". It should show only when Blizzard's button is hidden, but nothing tells addon code
--    when that happens in combat: every aura API throws for tainted code in combat, even
--    GetAuraDuration and GetUnitAuraInstanceIDs, UNIT_AURA stops reaching the addon, script
--    handlers under the button never run, and the button only animates its own descendants
--    (all tested 2026-09-23). So the underlay follows `believedUp`:
--    * out of combat: exact, read from the aura (refreshShield);
--    * in combat: set to up when UNIT_SPELLCAST_SUCCEEDED reports our own cast of a tracked shield.
--      Our own cast events are documented as never secret (SecretWhenUnitSpellCastRestricted
--      only hides other units' casts); the combat log is never read. The inference is only
--      "a successful shield cast means that shield is up". Casting an untracked shield sets it to
--      down, since that shield replaces the tracked one (the same inference, applied to exclusivity).
--    * Nothing else can set it to down in combat. A shield that drops mid-fight shows the underlay at
--      the "No shield: combat fallback" strength (underlayUp) until the recast or combat ends.
--    * Why keep the inference: without it, entering combat with no shield and casting one mid-fight
--      leaves the full "no shield" look bleeding through the live shield until combat ends
--      (at group opacity below 100%). Tried and kept, 2026-09-23.
-- 3. The underlay matters at all only because the group's opacity makes Blizzard's button
--    translucent, so the underlay bleeds through it; nativeIconAlpha compensates so the stack
--    matches the group's opacity. At 100% group opacity the button hides the underlay completely.
------------------------------------------------------------------------
-- Per shield at runtime: spellID (spellbook), known (in the spellbook), auraIDs (every ID seen
-- for it, learned from the spellbook and the live aura).
for _, s in pairs(SHIELDS) do s.auraIDs = {} end
local believedUp = false      -- see above: exact out of combat, set up by our own cast in combat
local native = { container = nil, button = nil, icon = nil, fs = nil, cd = nil, bar = nil, ticks = nil, overlay = nil,
	err = nil }

local function tracksShield(key) return db.shieldTrack == "either" or db.shieldTrack == key end

-- Which shield the no-shield look shows: the tracked one, or in "either" mode the one last cast or
-- seen, falling back to one the player actually knows.
local function underlayShield()
	if SHIELDS[db.shieldTrack] then return db.shieldTrack end
	if SHIELDS[acct.lastShield] and SHIELDS[acct.lastShield].known then return acct.lastShield end
	for _, key in ipairs(SHIELD_ORDER) do if SHIELDS[key].known then return key end end
	return "lightning"
end
function ns.shieldIcon()
	local s = SHIELDS[underlayShield()]
	return s.bookIcon or s.icon
end

-- The shield an own cast belongs to, if any.
local function shieldForSpell(id)
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if id == s.spellID or s.auraIDs[id] then return key end
		for _, v in ipairs(s.ids) do if id == v then return key end end
	end
end

-- The underlay is meant to show only when Blizzard's button is hidden, i.e. when the shield is down,
-- so grey and tint apply unconditionally. Frame alpha is applied per texture, so while the shield is
-- up the translucent button stacks on the underlay and reads darker than the shock icon. The engine
-- does not tell us about the hide in combat, so the ring and the underlay strength follow our belief:
-- faded while believed up, full when believed down. Blizzard's icon alpha then compensates for the
-- remaining bleed-through (see nativeIconAlpha) so the stack sums to the display opacity exactly.
local function applyEmptyLook()
	shield.tex:SetTexture(ns.shieldIcon())
	shield.tex:SetDesaturated(db.emptyGrey)
	if db.emptyTint then shield.tex:SetVertexColor(1, 0.35, 0.35) else shield.tex:SetVertexColor(1, 1, 1) end
	shield.tex:SetAlpha(believedUp and db.underlayUp or 1)
	shield:SetRingShown(not believedUp and db.emptyRing)
	-- Only while known down: in combat a drop is not seen until the recast or combat ends.
	shield:SetPulsing(not believedUp and db.emptyPulse)
end

-- With display opacity a and underlay strength u, an icon alpha b gives a stacked result of
-- a*b + (1 - a*b)*a*u; solving that for a yields b = (1 - u) / (1 - a*u). The display opacity is
-- that of the shield's group.
local function nativeIconAlpha()
	local gi = findElement("shield")
	local a, u = gi and db.groups[gi].alpha or 1, db.underlayUp
	local b = u > 0 and (1 - u) / (1 - a * u) or 1
	return math.min(math.max(b * db.shieldIconAlpha, 0.05), 1)
end

local function styleSwipe(cd)
	cd:SetDrawSwipe(db.shieldSwipe > 0)
	cd:SetSwipeColor(0, 0, 0, db.shieldSwipe)
end

local function setBelievedUp(up)
	believedUp = up
	applyEmptyLook()
end

-- Every spell ID of every tracked shield: what Blizzard's aura slot matches.
local function shieldIDMap()
	local map = {}
	for key, s in pairs(SHIELDS) do
		if tracksShield(key) then
			for _, id in ipairs(s.ids) do map[id] = true end
			for id in pairs(s.auraIDs) do map[id] = true end
		end
	end
	return map
end

-- The slot's filter can only change out of combat; a change in combat waits for it to end.
local filterPending = false
local function applyShieldFilter()
	if not native.container or native.err then return end
	if InCombatLockdown() then filterPending = true return end
	filterPending = false
	pcall(native.container.SetAuraSlotCandidateFilters, native.container, "shield", { includeSpellIDs = shieldIDMap() })
end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if not id or isSecret(id) or s.auraIDs[id] then return end
	s.auraIDs[id] = true
	if tracksShield(key) then applyShieldFilter() end
end

-- Blizzard's button and its parts are off limits to addon code in combat; defer until it ends.
local nativeStylePending = false
function styleNative()
	if not native.button then return end
	if InCombatLockdown() then nativeStylePending = true return end
	nativeStylePending = false
	pcall(function()
		local size = db.iconSize
		native.container:SetSize(size, size)
		-- Moving the shield to another group reparents it, which can drop the container back under
		-- the underlay and its ring; restate the placement from setupNative.
		native.container:SetFrameStrata(shield:GetFrameStrata())
		native.container:SetFrameLevel(shield.textFrame:GetFrameLevel() + 5)
		native.button:SetSize(size, size)
		for i, t in ipairs(native.tickTextures or {}) do
			t:ClearAllPoints()
			t:SetPoint("TOP", native.ticks, "TOPLEFT", size * i / native.maxCharges, 0)
			t:SetPoint("BOTTOM", native.ticks, "BOTTOMLEFT", size * i / native.maxCharges, 0)
		end
		native.icon:SetAlpha(nativeIconAlpha())
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
		styleSwipe(native.cd)
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
	tex:SetAlpha(nativeIconAlpha())
	button:SetIcon(tex)
	native.icon = tex

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawEdge(false)
	cd:SetCountdownFont(CD_FONT)
	cd:SetHideCountdownNumbers(true)
	styleSwipe(cd)
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
		-- Intrinsic frames do not inherit placement; match the HUD's strata (HIGH would float over other
		-- addons' dialogs) and use frame level alone to sit above the underlay and its ring.
		c:SetFrameStrata(shield:GetFrameStrata())
		c:SetFrameLevel(shield.textFrame:GetFrameLevel() + 5)
		c:SetUnit("player")
		pcall(c.EnableMouse, c, false)   -- unlocked drags start on the group frame underneath
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

-- Out of combat the auras are readable: sync our belief and learn the live spell IDs.
local function refreshShield()
	if InCombatLockdown() then return end
	local upKey
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if s.known then
			local ok, aura = safe(C_UnitAuras.GetAuraDataBySpellName, "player", s.name, "HELPFUL")
			if not ok then return end
			if aura then
				upKey = key
				if not isSecret(aura.spellId) then learnShieldID(key, aura.spellId) end
			end
		end
	end
	if upKey then acct.lastShield = upKey end
	setBelievedUp(upKey ~= nil and tracksShield(upKey))
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
	if not shockSpellID or not isEnabled("shock") then return end
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, shockSpellID)
	if ok and dur then pcall(shock.cd.SetCooldownFromDurationObject, shock.cd, dur) end
end

local function refreshShockRange()
	if not shockSpellID or not isEnabled("shock") then return end
	local ok, r = safe(C_Spell.IsSpellInRange, shockSpellID, "target")
	shockState.outOfRange = ok and not isSecret(r) and r == false
	updateShockTint()
end

local function refreshShockMana()
	if not isEnabled("shock") then return end
	local ok, _, noPower = safe(C_Spell.IsSpellUsable, manaSpellID)
	shockState.noMana = ok and not isSecret(noPower) and noPower == true
	updateShockTint()
end

------------------------------------------------------------------------
-- Weapon imbue (main hand): warns while no shaman imbue is on, shows which one is and, near the end,
-- its time left. Imbues are item data, not auras: C_Item.GetWeaponEnchantInfo lists them with
-- enchantType Imbue (C_PaperDollInfo.GetTemporaryEnchantmentInfo only covers stones and oils, tested
-- 2026-09-23). The API is not documented as secret, so it is read directly every time. If a read fails (for example in combat) the icon shows
-- "?" rather than guessing, and /sf debug says what came back; fallbacks wait until the limits are known.
------------------------------------------------------------------------
local IMBUES = {
	rockbiter   = { name = "Rockbiter Weapon",   icon = 136086, ids = { 29, 6, 1, 503, 1663, 683, 1664 } },
	flametongue = { name = "Flametongue Weapon", icon = 135814, ids = { 5, 4, 3, 523, 1665, 1666 } },
	frostbrand  = { name = "Frostbrand Weapon",  icon = 135847, ids = { 2, 12, 524, 1667, 1668 } },
	windfury    = { name = "Windfury Weapon",    icon = 136018, ids = { 283, 284, 525, 1669 } },
}
local IMBUE_ORDER = { "rockbiter", "flametongue", "frostbrand", "windfury" }
local MAIN_HAND = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
local IMBUE_TYPE = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue or 3

-- Recognised by enchant ID (seeded from the vanilla ranks), else by icon, else learned from our own cast.
local imbueByName, imbueByID = {}, {}
for key, m in pairs(IMBUES) do
	imbueByName[m.name] = key
	for _, id in ipairs(m.ids) do imbueByID[id] = key end
end

-- key: the imbue on (nil = none); unreadable: the last read failed; read: what it said, for /sf debug.
local imbueState = { key = nil, expiresAt = nil, unreadable = false, read = "not checked", castKey = nil, castAt = 0 }

imbue.timer = imbue.textFrame:CreateFontString(nil, "OVERLAY", nil, 7)
imbue.timer:SetPoint("CENTER")

local function imbueIconFor(key)
	local m = IMBUES[key] or IMBUES.rockbiter
	local _, icon = knownSpell(m.name)
	return icon or m.icon
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
	local key = acct.imbueIDs[w.enchantID] or imbueByID[w.enchantID]
	if key then return key end
	for k, m in pairs(IMBUES) do
		if w.enchantIconID == m.icon or w.enchantIconID == imbueIconFor(k) then return k end
	end
end

local function formatLeft(s)
	if s >= 60 then return string.format("%dm", math.ceil(s / 60)) end
	return string.format("%d", math.max(math.ceil(s), 0))
end

local imbueIcon = imbueIconFor("rockbiter")

local function paintImbue(now)
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
	else
		imbueIcon = imbueIconFor(db.imbuePreferred == "last" and (acct.imbueLast or "rockbiter") or db.imbuePreferred)
		imbue.tex:SetDesaturated(db.imbueMissingGrey)
		imbue:SetRingShown(db.imbueMissingRing)
		imbue:SetPulsing(db.imbuePulse)
	end
	imbue.tex:SetTexture(imbueIcon)
	if unreadable then
		imbue:SetRingShown(false)
		imbue:SetPulsing(false)
		imbue.timer:SetText("?")
		imbue.timer:SetTextColor(1, 0.82, 0)
	elseif showTime then
		imbue.timer:SetText(formatLeft(left))
		if left < 60 then imbue.timer:SetTextColor(1, 0.3, 0.3) else imbue.timer:SetTextColor(1, 1, 1) end
	end
	imbue.timer:SetShown(unreadable or showTime)
	-- Hidden by alpha, not Hide, so it keeps its place in the group and shows again at once.
	imbue:SetAlpha((acct.locked and key and db.imbueHideActive and not showTime and not unreadable) and 0 or 1)
end

local function refreshImbue()
	if not isEnabled("imbue") then return end
	local now = GetTime()
	local r = readMainHand()
	imbueState.unreadable = r == nil
	imbueState.key, imbueState.expiresAt = nil, nil
	if r == nil then
		imbueState.read = "unreadable" .. (InCombatLockdown() and " (in combat)" or "")
	elseif r == false then
		imbueState.read = "no imbue"
	else
		local key = imbueKeyFor(r)
		if not key and now - imbueState.castAt < 3 then key = imbueState.castKey; acct.imbueIDs[r.enchantID] = key end
		imbueState.read = string.format("enchant %d, icon %d, %s", r.enchantID, r.enchantIconID, key or "not recognised")
		imbueState.key = key
		imbueState.expiresAt = r.timeLeft > 0 and now + r.timeLeft / 1000 or nil
		if key then acct.imbueLast = key end
	end
	paintImbue(now)
end

-- Remembers our own imbue cast, so an imbue not recognised by ID or icon is learned on the next read.
local function imbueCast(spellID)
	local ok, name = safe(C_Spell.GetSpellName, spellID)
	local key = ok and not isSecret(name) and imbueByName[name]
	if not key then return end
	imbueState.castKey, imbueState.castAt = key, GetTime()
	refreshImbue()
end

------------------------------------------------------------------------
-- Cooldown elements (see COOLDOWNS). Nothing here reads a secret value:
-- * The spell cooldown and a totem's time are duration objects that Blizzard widgets draw (cooldown
--   swipe, countdown numbers, timer bar), as with the shock.
-- * Fire Nova's "no fire totem" warning: the fire slot's duration object evaluates its remaining time
--   through a curve (0s -> 1, anything more -> 0) and the result, secret or not, goes straight to
--   SetAlpha, which accepts secrets. An empty slot returns no duration object at all (seen
--   2026-09-23), which is plainly "no totem"; an expired one evaluates to 0s remaining.
--   (IsZero was tried first and did not work: an expired totem's duration is not a zero time span.)
--   The addon never branches on it.
-- * Earthbind / Stoneclaw must tell their totem from any other earth totem, and in combat everything
--   GetTotemInfo returns is secret, even for totems flagged never-secret out of combat (tested
--   2026-09-23). The earth slot's duration object still exists, so the timer is identified by its
--   TOTAL duration instead: the bar and numbers always take the slot's duration object, and their
--   holder's alpha is the total duration evaluated through a curve that is 1 only within half a
--   second of this totem's lifetime and 0 otherwise. Both calls accept secrets.
--   ASSUMPTION: no two earth totems share a lifetime (vanilla: Earthbind 45s, Stoneclaw 15s, the
--   rest 120s). Lifetimes are learned out of combat, where the slot's name and duration are
--   readable, so a changed duration corrects itself the first time the totem is dropped out of
--   combat. If Forever ever gives two earth totems the same lifetime, both would show the timer.
------------------------------------------------------------------------
local TIMER_REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local TIMER_IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0

-- Remaining seconds -> alpha: fully shown at 0s, hidden from 0.05s up.
local noTimeLeftCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
	noTimeLeftCurve = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then noTimeLeftCurve:SetType(Enum.LuaCurveType.Linear) end
	noTimeLeftCurve:AddPoint(0, 1)
	noTimeLeftCurve:AddPoint(0.05, 0)
end
-- The reverse, for the timer bar's background: hidden at 0s, shown from 0.05s up.
local timeLeftCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
	timeLeftCurve = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then timeLeftCurve:SetType(Enum.LuaCurveType.Linear) end
	timeLeftCurve:AddPoint(0, 0)
	timeLeftCurve:AddPoint(0.05, 1)
end

-- Per-element option with its default.
local function cdOpt(key, name, default)
	local v = elementOpts(key)[name]
	if v == nil then return default end
	return v
end

-- Whether a totem is out in a slot, its name and total duration; nil when the slot cannot be read. haveTotem alone
-- is not enough: on Forever an empty slot reports haveTotem true with a blank name, and a slot can
-- also return nothing at all (both seen 2026-09-23). So a totem is out only when it has a name.
local function readTotem(slot)
	if not GetTotemInfo then return nil end
	local ok, have, name, _, duration = pcall(GetTotemInfo, slot)
	if not ok or isSecret(have) or isSecret(name) or isSecret(duration) then return nil end
	if not have or type(name) ~= "string" or name == "" then return false end
	return true, name, duration
end

-- Total duration -> alpha: 1 within half a second of seconds, 0 elsewhere.
local function lifetimeCurve(seconds)
	if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
	local c = C_CurveUtil.CreateCurve()
	if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Linear) end
	c:AddPoint(0, 0)
	c:AddPoint(math.max(seconds - 0.5, 0.01), 0)
	c:AddPoint(seconds - 0.4, 1)
	c:AddPoint(seconds + 0.4, 1)
	c:AddPoint(seconds + 0.5, 0)
	return c
end

local function refreshCooldown(def)
	if not isEnabled(def.key) then return end
	local f = def.frame
	f.tex:SetTexture(def.iconID or def.icon)
	if not def.spellID then
		-- Not learned yet: a plain grey icon.
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.cd:Clear()
		if f.active then f.active:Hide(); f.activeCD:Clear() end
		if f.warn then f.warn:SetAlpha(0) end
		return
	end
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, def.spellID)
	if ok and dur then pcall(f.cd.SetCooldownFromDurationObject, f.cd, dur) end
	f.tex:SetDesaturated(false)
	if def.needsTotem then
		-- Fire Nova: the slot's duration object drives everything, secret or not. An empty slot's
		-- duration is zero, so the timer widgets draw nothing and the warning layer shows.
		local slot = def.needsTotem
		local tok, tdur = safe(GetTotemDuration, slot)
		local aok, alpha = false, nil
		if tok and tdur and noTimeLeftCurve then aok, alpha = pcall(tdur.EvaluateRemainingDuration, tdur, noTimeLeftCurve) end
		f.activeHolder:SetAlpha(1)   -- any fire totem counts, so its timer always shows
		local w = f.warn
		-- Icon, then warning layer, then swipe, then text; restated as regrouping reparents the icon.
		w:SetFrameLevel(f:GetFrameLevel() + 1)
		f.cd:SetFrameLevel(f:GetFrameLevel() + 2)
		f.textFrame:SetFrameLevel(f:GetFrameLevel() + 4)
		w.grey:SetTexture(def.iconID or def.icon)
		w.grey:SetShown(cdOpt(def.key, "blockedGrey", true))
		for _, t in ipairs(w.ring) do t:SetShown(cdOpt(def.key, "blockedRing", true)) end
		if cdOpt(def.key, "blockedPulse", false) then
			if not w.pulse:IsPlaying() then w.pulse:Play() end
		else w.pulse:Stop() end
		if tok and tdur == nil then
			-- Nothing in the slot: no duration object to evaluate.
			w:SetAlpha(1)
			f.active.bg:SetAlpha(0)
			def.read = "no fire totem (no duration)"
		elseif aok and alpha ~= nil then
			w:SetAlpha(alpha)
			local bok, bgAlpha = pcall(tdur.EvaluateRemainingDuration, tdur, timeLeftCurve)
			f.active.bg:SetAlpha(bok and bgAlpha or 1)
			def.read = "warning alpha " .. describeArg(alpha)
		else
			w:SetAlpha(0)
			def.read = string.format("fire slot duration %s, curve %s: %s", tok and "ok" or "error",
				noTimeLeftCurve and "ok" or "missing", describeArg(alpha))
		end
		if tok and tdur and cdOpt(def.key, "activeBar", true) then
			pcall(f.active.SetTimerDuration, f.active, tdur, TIMER_IMMEDIATE, TIMER_REMAINING)
			f.active:Show()
		else f.active:Hide() end
		if tok and tdur and cdOpt(def.key, "activeText", true) then
			pcall(f.activeCD.SetCooldownFromDurationObject, f.activeCD, tdur, true)
		else f.activeCD:Clear() end
	elseif def.totemSlot then
		-- Earthbind / Stoneclaw: the slot's timer, shown only when its total matches this totem's
		-- lifetime (see the section comment). Out of combat the lifetime is learned from the slot.
		local slot = def.totemSlot
		local have, name, duration = readTotem(slot)
		if have and name:find(def.spell, 1, true) == 1 and type(duration) == "number" and duration > 0 then
			acct.totemLifetimes[def.key] = duration
		end
		local lifetime = acct.totemLifetimes[def.key] or def.duration
		if def.curveFor ~= lifetime then def.curve, def.curveFor = lifetimeCurve(lifetime), lifetime end
		local tok, tdur = safe(GetTotemDuration, slot)
		if tok and tdur and def.curve then
			local aok, alpha = pcall(tdur.EvaluateTotalDuration, tdur, def.curve)
			f.activeHolder:SetAlpha(aok and alpha or 0)
			local bok, bgAlpha = pcall(tdur.EvaluateRemainingDuration, tdur, timeLeftCurve)
			f.active.bg:SetAlpha(bok and bgAlpha or 1)
			if cdOpt(def.key, "activeBar", true) then
				pcall(f.active.SetTimerDuration, f.active, tdur, TIMER_IMMEDIATE, TIMER_REMAINING)
				f.active:Show()
			else f.active:Hide() end
			if cdOpt(def.key, "activeText", true) then
				pcall(f.activeCD.SetCooldownFromDurationObject, f.activeCD, tdur, true)
			else f.activeCD:Clear() end
			def.read = string.format("earth slot timer, lifetime %ss, match alpha %s", tostring(lifetime), aok and describeArg(alpha) or "error")
		else
			f.activeHolder:SetAlpha(0)
			f.active:Hide()
			f.activeCD:Clear()
			def.read = string.format("no earth totem (lifetime %ss)", tostring(lifetime))
		end
	end
end

local function refreshCooldowns()
	for _, def in ipairs(COOLDOWNS) do refreshCooldown(def) end
end

------------------------------------------------------------------------
-- Spell resolution and layout
------------------------------------------------------------------------
local function resolveSpells()
	scanSpellbook()
	for key, s in pairs(SHIELDS) do
		s.known = book[s.name] ~= nil
		s.spellID, s.bookIcon = nil, nil
		if s.known then s.spellID, s.bookIcon = book[s.name].id, book[s.name].icon end
		if s.spellID then learnShieldID(key, s.spellID) end
	end
	applyShieldFilter()   -- the tracked shields may have changed
	shockIDs = {}
	for key, name in pairs(SHOCKS) do
		local id = knownSpell(name)
		if id then shockIDs[key] = id end
	end
	local id, ic = knownSpell(SHOCKS[db.shock] or SHOCKS.earth)
	shockSpellID = id
	shockIcon = ic or 136026
	shock.tex:SetTexture(shockIcon)
	manaSpellID = (db.manaSpell ~= "tracked" and shockIDs[db.manaSpell]) or shockSpellID
	if shockSpellID and C_Spell.EnableSpellRangeCheck then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
	for _, def in ipairs(COOLDOWNS) do
		local cid, cicon = knownSpell(def.spell)
		def.spellID, def.iconID = cid, cicon
	end
end

-- Countdown text per element: its own size (elementOpts(key).cdTextSize) or the general one. A
-- totem's active time uses a smaller size of the same. Returns the font object names.
local elementFonts = {}
local function cdFontFor(key)
	local f = elementFonts[key]
	if not f then
		f = { cd = CD_FONT .. "_" .. key, active = ACTIVE_FONT .. "_" .. key }
		CreateFont(f.cd)
		CreateFont(f.active)
		elementFonts[key] = f
	end
	local size = elementOpts(key).cdTextSize or db.cdTextSize
	_G[f.cd]:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
	_G[f.active]:SetFont(STANDARD_TEXT_FONT, math.max(math.floor(size * 0.55), 8), "OUTLINE")
	_G[f.active]:SetTextColor(0.5, 1, 0.4)
	return f.cd, f.active
end
ns.cdFontFor = cdFontFor

local function applyLayout()
	layoutElements()
	cdFont:SetFont(STANDARD_TEXT_FONT, db.cdTextSize, "OUTLINE")
	shock.cd:SetCountdownFont((cdFontFor("shock")))
	shock.cd:SetHideCountdownNumbers(not db.cdText)
	activeFont:SetFont(STANDARD_TEXT_FONT, math.max(math.floor(db.cdTextSize * 0.55), 8), "OUTLINE")
	activeFont:SetTextColor(0.5, 1, 0.4)
	for _, def in ipairs(COOLDOWNS) do
		local cdName, activeName = cdFontFor(def.key)
		def.frame.cd:SetCountdownFont(cdName)
		def.frame.cd:SetHideCountdownNumbers(not db.cdText)
		if def.frame.activeCD then def.frame.activeCD:SetCountdownFont(activeName) end
	end
	refreshShockMana()
	imbue.timer:SetFont(STANDARD_TEXT_FONT, db.imbueTextSize, "OUTLINE")
	refreshImbue()
	refreshCooldowns()
	if not native.container then setupNative() end
	styleNative()
	applyEmptyLook()
end

local function refreshAll()
	refreshShield()
	refreshShockCooldown()
	refreshShockRange()
	refreshShockMana()
	refreshImbue()
	refreshCooldowns()
end

-- Layout edits used by the options window. Each leaves db.groups consistent and relays out.
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return end
		fn(...)
		pruneGroups()
		layoutElements()
	end
end

-- Puts key into target (a group index or "new"). index is its position among the target's other
-- members; nil appends.
local placeElement = edit(function(key, target, index)
	local gi = findElement(key)
	local src = gi and db.groups[gi]
	if target == "new" then
		if src and #src.members == 1 then return end
		removeElement(key)
		local g = newGroup(src or db.groups[1])
		g.members = { key }
		-- Screen centre, stepping down past any group already parked there.
		g.point, g.x, g.y = "CENTER", 0, 0
		local taken = true
		while taken do
			taken = false
			for _, o in ipairs(db.groups) do
				if o ~= g and o.point == "CENTER" and o.x == g.x and o.y == g.y then taken = true end
			end
			if taken then g.y = g.y - 60 end
		end
	elseif db.groups[target] then
		local g = db.groups[target]
		local list = {}
		for _, k in ipairs(g.members) do if k ~= key then table.insert(list, k) end end
		index = math.min(math.max(index or #list + 1, 1), #list + 1)
		table.insert(list, index, key)
		removeElement(key)
		g.members = list
	end
end)

-- Splits a group into single-element groups, each left exactly where it is on screen.
local splitGroup = edit(function(gi)
	local g = db.groups[gi]
	if not g or #g.members < 2 then return end
	for i = #g.members, 2, -1 do
		local key = g.members[i]
		local sx, sy = screenCenter(ELEMENTS[key].frame)
		table.remove(g.members, i)
		local ng = newGroup(g)
		ng.members = { key }
		if sx then setGroupCenter(ng, sx, sy) end
	end
	local sx, sy = screenCenter(ELEMENTS[g.members[1]].frame)
	if sx then setGroupCenter(g, sx, sy) end
end)

local setShow = edit(function(key, mode) elementOpts(key).show = mode ~= "always" and mode or nil end)

-- Hides every element in the group; the group keeps them, so showing one brings it back in place.
local hideGroup = edit(function(gi)
	for _, key in ipairs(db.groups[gi] and db.groups[gi].members or {}) do elementOpts(key).show = "never" end
end)
local centerGroup = edit(function(gi)
	local g = db.groups[gi]
	if g then g.point, g.x, g.y = "CENTER", 0, 0 end
end)

------------------------------------------------------------------------
-- Profiles: named sets of settings in acct.profiles. Each character picks one (acct.chars); new
-- characters start on Default.
------------------------------------------------------------------------
local function charKey()
	local name, realm = UnitName("player"), GetNormalizedRealmName and GetNormalizedRealmName()
	if not realm or realm == "" then realm = GetRealmName() end
	if name and realm then return name .. "-" .. realm end
end

local function fillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then t[k] = type(v) == "table" and CopyTable(v) or v end
	end
end

-- Makes name the active profile (created from defaults if new) and remembers it for this character.
local function selectProfile(name)
	if type(acct.profiles[name]) ~= "table" then acct.profiles[name] = {} end
	profileName, db = name, acct.profiles[name]
	fillDefaults(db, DEFAULTS)
	sanitize()
	local key = charKey()
	if key then
		acct.chars[key] = acct.chars[key] or {}
		acct.chars[key].profile = name
	end
end

local function redraw()
	resolveSpells(); applyLayout(); refreshAll()
	if ns.RefreshOptions then ns.RefreshOptions() end
end

local function useProfile(name)
	selectProfile(name)
	redraw()
end

local function profileNames()
	local t = {}
	for name in pairs(acct.profiles) do table.insert(t, name) end
	table.sort(t, function(a, b) return a:lower() < b:lower() end)
	return t
end

-- Returns an error message, or nil once done.
local function checkNewName(name)
	if name == "" then return "a profile needs a name" end
	if acct.profiles[name] then return "there is already a profile called " .. name end
end

local function newProfile(name, copy)
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	acct.profiles[name] = copy and CopyTable(db) or {}
	useProfile(name)
end

-- Default keeps its name: it is the profile new characters start on.
local function renameProfile(name)
	if profileName == DEFAULT_PROFILE then return end
	name = strtrim(name or "")
	local err = checkNewName(name)
	if err then return err end
	local old = profileName
	acct.profiles[name], acct.profiles[old] = acct.profiles[old], nil
	for _, c in pairs(acct.chars) do if c.profile == old then c.profile = name end end
	profileName = name
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Deletes the active profile; characters that used it go back to Default, which cannot be deleted.
local function deleteProfile()
	local name = profileName
	if name == DEFAULT_PROFILE then return end
	acct.profiles[name] = nil
	for _, c in pairs(acct.chars) do if c.profile == name then c.profile = nil end end
	useProfile(DEFAULT_PROFILE)
end

-- The active profile back to defaults, keeping its name.
local function resetProfile()
	wipe(db)
	selectProfile(profileName)
	redraw()
end

-- Shared with ShamanForever_Options.lua
ns.DEFAULTS, ns.GROUP_DEFAULTS, ns.SHOCKS, ns.SHOCK_ORDER = DEFAULTS, GROUP_DEFAULTS, SHOCKS, SHOCK_ORDER
ns.SHIELDS, ns.SHIELD_ORDER = SHIELDS, SHIELD_ORDER
ns.ELEMENTS, ns.ELEMENT_KEYS, ns.available, ns.findElement = ELEMENTS, ELEMENT_KEYS, available, findElement
ns.getDB = function() return db end
ns.getAccount = function() return acct end
ns.profileName = function() return profileName end
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
ns.profileNames, ns.useProfile, ns.newProfile = profileNames, useProfile, newProfile
ns.renameProfile, ns.deleteProfile, ns.resetProfile = renameProfile, deleteProfile, resetProfile
ns.applyLayout, ns.resolveSpells, ns.refreshAll, ns.elementOpts = applyLayout, resolveSpells, refreshAll, elementOpts
ns.placeElement, ns.splitGroup, ns.hideGroup, ns.centerGroup = placeElement, splitGroup, hideGroup, centerGroup
ns.setShow, ns.showMode = setShow, showMode
ns.COOLDOWNS = COOLDOWNS
ns.makeIcon = makeIcon   -- the options previews draw with the HUD's own icon
ns.IMBUES, ns.IMBUE_ORDER, ns.imbueIcon = IMBUES, IMBUE_ORDER, function() return imbueIcon end
ns.setTestMode = function(on) edit(setTestMode)(on) end
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
		ShamanForeverDB = ShamanForeverDB or {}
		acct = ShamanForeverDB
		-- Steps 1 to 3 are for saves from before profiles, where every setting sat in ShamanForeverDB.
		local legacy = acct
		-- Pre-groups saves: one row or column, with hidden elements in db.enabled.
		if legacy.groups == nil and (legacy.order or legacy.point) then
			local g = {}
			for k, v in pairs(GROUP_DEFAULTS) do if legacy[k] ~= nil then g[k] = legacy[k] else g[k] = v end end
			g.members, legacy.known = {}, {}
			for _, key in ipairs(legacy.order or { "shield", "shock" }) do
				legacy.known[key] = true
				if not (legacy.enabled and legacy.enabled[key] == false) then table.insert(g.members, key) end
			end
			legacy.groups = { g }
		end
		if (acct.settingsVersion or 0) < 4 then
			for _, k in ipairs(LEGACY_KEYS) do legacy[k] = nil end
		end
		-- 1: snapping and the grid briefly defaulted to on during 0.2.0 development; start them off
		-- once, after which the saved choice is kept.
		if (acct.settingsVersion or 0) < 1 then acct.snap, acct.grid = false, false end
		-- 2: "only show in combat" moved from the whole display to each group (and element).
		if (acct.settingsVersion or 0) < 2 then
			if legacy.combatOnly and type(legacy.groups) == "table" then
				for _, g in ipairs(legacy.groups) do g.combatOnly = true end
			end
			legacy.combatOnly = nil
		end
		-- 3: per-element "only in combat" became the element's show mode (always | combat | never).
		-- Elements hidden by being in no group are placed by sanitize below, set to never.
		if (acct.settingsVersion or 0) < 3 and type(legacy.elementOpts) == "table" then
			for _, o in pairs(legacy.elementOpts) do
				if o.combatOnly then o.show = "combat" end
				o.combatOnly = nil
			end
		end
		-- 4: profiles. The settings so far become the Default profile, which every character uses.
		if (acct.settingsVersion or 0) < 4 then
			local p = {}
			for k in pairs(DEFAULTS) do p[k], acct[k] = acct[k], nil end
			acct.profiles = { [DEFAULT_PROFILE] = p }
		end
		acct.settingsVersion = SETTINGS_VERSION
		fillDefaults(acct, ACCOUNT_DEFAULTS)
		local c = charKey() and acct.chars[charKey()]
		local name = c and c.profile
		selectProfile(name and acct.profiles[name] and name or DEFAULT_PROFILE)
		if ns.BuildOptions then ns.BuildOptions() end
	elseif event == "PLAYER_LOGIN" then
		if ns.applyIssueReporter then ns.applyIssueReporter() end   -- any class
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then root:Hide(); return end
		isShaman = true
		reg("UNIT_AURA", "player")
		reg("UNIT_SPELLCAST_SUCCEEDED", "player")
		reg("SPELL_UPDATE_COOLDOWN")
		reg("SPELL_UPDATE_USABLE")
		reg("UNIT_POWER_UPDATE", "player")
		reg("PLAYER_TARGET_CHANGED")
		reg("SPELLS_CHANGED")
		reg("PLAYER_REGEN_ENABLED")
		reg("SPELL_RANGE_CHECK_UPDATE")
		reg("UNIT_INVENTORY_CHANGED", "player")
		reg("PLAYER_EQUIPMENT_CHANGED")
		reg("PLAYER_TOTEM_UPDATE")
		resolveSpells()
		applyLayout()
		refreshAll()
		C_Timer.NewTicker(0.25, refreshShockRange)
		C_Timer.NewTicker(1, function() refreshImbue(); refreshCooldowns() end)
		root:Show()
	elseif event == "UNIT_AURA" then
		refreshShield()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3   -- args: unit, castGUID, spellID
		local cast = not isSecret(spellID) and shieldForSpell(spellID)
		if cast then
			-- The one inference: our cast means that shield is up and the other is gone (see the Shield section).
			acct.lastShield = cast
			setBelievedUp(tracksShield(cast))
		end
		if not isSecret(spellID) then imbueCast(spellID) end   -- only to learn an unknown imbue enchant ID
		refreshShockCooldown()
		refreshCooldowns()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		refreshShockCooldown()
		refreshCooldowns()
	elseif event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then
		refreshShockMana()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "SPELL_RANGE_CHECK_UPDATE" then
		refreshShockRange()
	elseif event == "PLAYER_TOTEM_UPDATE" then
		refreshCooldowns()
	elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		refreshImbue()
	elseif event == "SPELLS_CHANGED" then
		resolveSpells()
		applyLayout()
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if layoutPending then layoutElements() end
		if nativeStylePending then styleNative() end
		if filterPending then applyShieldFilter() end
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
	if cmd == "" or cmd == "options" or cmd == "config" then
		if ns.ToggleOptions then ns.ToggleOptions() else say("options window unavailable") end
	elseif cmd == "lock" then   -- toggles; /sf unlock still works but is no longer advertised
		acct.locked = not acct.locked; applyLayout()
		say(acct.locked and "positioning locked" or "positioning unlocked: drag groups to move them, /sf lock when done")
	elseif cmd == "unlock" then acct.locked = false; applyLayout(); say("positioning unlocked: drag groups to move them, /sf lock when done")
	elseif cmd == "test" then
		ns.setTestMode(not acct.testMode)
		say("test elements %s", acct.testMode and "on" or "off")
	elseif cmd == "debug" then
		say("shield tracking %s (last %s), believed up %s; shock spell %s (%s), mana spell %s, in combat %s",
			db.shieldTrack, acct.lastShield, tostring(believedUp), tostring(shockSpellID), db.shock,
			tostring(manaSpellID), tostring(InCombatLockdown()))
		for _, key in ipairs(SHIELD_ORDER) do
			local s, e = SHIELDS[key], book[SHIELDS[key].name]
			local ids = {} for id in pairs(s.auraIDs) do table.insert(ids, tostring(id)) end table.sort(ids)
			say("%s: %s, spell %s rank %s, seen IDs %s", s.name, s.known and "known" or "not known",
				tostring(s.spellID), e and e.rank or "?", #ids > 0 and table.concat(ids, ",") or "none")
		end
		say("aura container %s%s", native.container and "created" or "not created",
			native.err and (", error: " .. native.err) or "")
		local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
		say("tracked spell IDs: %s", table.concat(t, ","))
		local r = readMainHand()
		say("main hand imbue now: %s; last ticker read: %s", r == nil and "unreadable" .. (InCombatLockdown() and " (in combat)" or "")
			or r == false and "none" or string.format("enchant %d, icon %d, %.0fs left", r.enchantID, r.enchantIconID, r.timeLeft / 1000),
			imbueState.read)
		for slot = 1, 4 do
			local ok, have, name, start, duration, icon, modRate, spellID = pcall(GetTotemInfo, slot)
			say("totem slot %d: %s", slot, ok and string.format("have=%s name=%s start=%s duration=%s icon=%s spellID=%s",
				describeArg(have), describeArg(name), describeArg(start), describeArg(duration), describeArg(icon), describeArg(spellID))
				or ("error " .. tostring(have)))
			local dok, d = pcall(GetTotemDuration, slot)
			if dok and d then
				local rok, r = pcall(d.GetRemainingDuration, d)
				local tok2, t = pcall(d.GetTotalDuration, d)
				say("  duration object: remaining=%s total=%s", rok and describeArg(r) or "error", tok2 and describeArg(t) or "error")
			end
		end
		for _, def in ipairs(COOLDOWNS) do
			local secret = "?"
			if def.spellID and C_Secrets and C_Secrets.ShouldTotemSpellBeSecret then
				local ok, v = pcall(C_Secrets.ShouldTotemSpellBeSecret, def.spellID)
				secret = ok and describeArg(v) or "error"
			end
			say("%s: spell %s, totem spell secret=%s, %s", def.spell, tostring(def.spellID), secret, def.read or "not checked")
		end
		if C_Secrets and C_Secrets.ShouldTotemSlotBeSecret then
			local t = {}
			for slot = 1, 4 do
				local ok, v = pcall(C_Secrets.ShouldTotemSlotBeSecret, slot)
				t[slot] = ok and describeArg(v) or "error"
			end
			say("totem slots secret now: %s", table.concat(t, ", "))
		end
		for key, id in pairs(shockIDs) do
			local ok, usable, noPower = safe(C_Spell.IsSpellUsable, id)
			local _, r = safe(C_Spell.IsSpellInRange, id, "target")
			say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
				book[SHOCKS[key]] and book[SHOCKS[key]].rank or "?", describeArg(usable), describeArg(noPower), describeArg(r))
		end
		-- Probe: does Forever have specs or dual spec? Decides whether profiles can follow the spec.
		local function probe(label, fn, ...)
			if not fn then return label .. "=missing" end
			local n = select("#", pcall(fn, ...))
			local res = { pcall(fn, ...) }
			if not res[1] then return label .. "=error" end
			local out = {}
			for i = 2, n do out[#out + 1] = describeArg(res[i]) end
			return label .. "=" .. (#out > 0 and table.concat(out, "/") or "nothing")
		end
		local spec = C_SpecializationInfo or {}
		say("profile %s; specs: %s, %s, %s, %s, %s, %s", tostring(profileName),
			probe("GetSpecialization", _G.GetSpecialization), probe("GetNumSpecializations", _G.GetNumSpecializations),
			probe("GetActiveSpecGroup", _G.GetActiveSpecGroup), probe("GetNumSpecGroups", GetNumSpecGroups),
			probe("C_SpecializationInfo.GetSpecialization", spec.GetSpecialization),
			probe("C_SpecializationInfo.GetActiveSpecGroup", spec.GetActiveSpecGroup))
		local cur = _G.GetSpecialization and select(2, pcall(_G.GetSpecialization))
		if type(cur) == "number" and _G.GetSpecializationInfo then
			say("  current spec: %s", probe("GetSpecializationInfo", _G.GetSpecializationInfo, cur))
		end
		for gi, g in ipairs(db.groups) do
			local names = {}
			for _, key in ipairs(g.members) do
				local mode = showMode(key)
				table.insert(names, mode == "always" and key or (key .. " (" .. mode .. ")"))
			end
			say("group %d: %s, %s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", gi, table.concat(names, ","),
				g.orientation, g.scale, g.alpha, g.point, g.x, g.y, g.combatOnly and ", combat only" or "")
		end
	else
		say("/sf opens the options. Also: /sf lock (lock or unlock positioning), /sf test (placeholder elements), /sf debug")
	end
end
