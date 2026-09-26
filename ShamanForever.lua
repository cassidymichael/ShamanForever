-- ShamanForever: shaman HUD (Lightning or Water Shield, shock, weapon imbue, totem cooldowns) for the WoW: Forever beta.
--
-- Rule for this client: never do Lua math or comparisons on a possibly-secret value. In combat, show
-- state through Blizzard's own widgets instead: the aura container for the shield, duration objects
-- for cooldowns and totem timers, curves and SetAlpha for anything that must appear or disappear.
-- The only inference anywhere is the shield's in-combat "up" state; ShamanForever_Shield.lua explains it.

local ADDON, ns = ...
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells = ns.Spells

-- Shock choice -> spell key; SHOCKS holds the display names (the client's, set by resolveSpells).
local SHOCK_SPELL = { earth = "earthShock", flame = "flameShock", frost = "frostShock" }
local SHOCKS = {}
for key, spell in pairs(SHOCK_SPELL) do SHOCKS[key] = Spells.name(spell) end
local SHOCK_ORDER = { "earth", "flame", "frost" }

-- Every element belongs to exactly one group, which owns its position, scale, opacity and flow;
-- whether the element is drawn (always, in combat, never) is its own setting in db.elementOpts.
-- Positions are offsets in the group's own (scaled) units.
local GROUP_DEFAULTS = {
	point = "CENTER", x = 0, y = -160, scale = 1, alpha = 0.75,
	-- Icon size: General's, or the group's own (Size keeps lines crisp; Scale grows everything).
	sizeFollow = true, size = 44,
	orientation = "horizontal",  -- horizontal | vertical
	growth = "forward",          -- forward (right / down) | backward (left / up)
	spacing = 6,
	combatOnly = false,          -- hide the group out of combat (always shown while unlocked)
}

-- A profile: the layout and how every element looks.
local DEFAULTS = {
	iconSize = 44,          -- base element size; a group can have its own, and its scale multiplies it
	-- General's styles (ShamanForever_Style.lua): the border around every element, the pulsing glow
	-- and the pop. Groups and the totem bar can have their own border; elements and the totem bar
	-- their own glow and pop.
	border = CopyTable(ns.Style.KINDS.border.defaults),
	glowStyle = CopyTable(ns.Style.KINDS.glow.defaults),
	popStyle = CopyTable(ns.Style.KINDS.pop.defaults),
	gcdStyle = CopyTable(ns.Style.KINDS.gcd.defaults),
	-- Default layout: just below the centre of the screen, side by side 16 px apart, ready to be
	-- dragged where the player wants them (the totem bar sits below, see TotemBar.lua). Offsets are
	-- in each group's scaled units, so the third group's are divided by its 0.9 scale.
	groups = {
		{ point = "CENTER", x = 0, y = -40, scale = 1, alpha = 0.75, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "shield", "shock", "firenova" } },
		{ point = "CENTER", x = -110, y = -40, scale = 1, alpha = 0.75, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "imbue" } },
		{ point = "CENTER", x = 120, y = -44, scale = 0.9, alpha = 0.6, orientation = "horizontal",
			growth = "forward", spacing = 6, members = { "earthbind", "stoneclaw" } },
	},
	known = {},             -- element keys placed at least once; new ones join the first group
	elementOpts = {         -- per-element settings by key, e.g. { shock = { show = "combat" } }
		stoneclaw = { show = "never" },   -- rarely used: starts hidden, beside Earthbind
	},
	-- shield
	shieldTrack = "lightning", -- lightning | water | either: which shield counts as "up" (water and either are experimental)
	countPos = "center",    -- corner | center
	countSize = 20,
	showBar = true,         -- charge bar along the bottom of the icon
	chargeBarHeight = 8,
	chargeBarColor = { 0.35, 0.75, 1, 1 },
	showCount = false,      -- charge number (Blizzard prints it for two or more); the charge bar shows it anyway
	emptyRing = true,       -- no-shield look
	emptyGrey = true,
	emptyTint = false,
	emptyPulse = true,
	underlayUp = 0.25,      -- underlay strength while the shield is believed up (0 = none)
	shieldIconAlpha = 1,    -- manual multiplier on the compensated shield icon alpha
	-- shock
	shock = "earth",        -- which shock the icon tracks
	manaSpell = "tracked",  -- tracked | earth | flame | frost
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
	imbueGlow = true,         -- a pulsing glow while no imbue is on
	imbuePop = true,          -- the icon bursts bigger the moment the imbue drops
	imbueWarnMins = 5,        -- show time left below this many minutes (0 = never)
	imbueHideActive = true,   -- while an imbue is on, only show once its time left shows
	totemBar = {},            -- the totem bar's settings (ShamanForever_TotemBar.lua fills its defaults)
	-- General's timer styles, one per kind (ShamanForever_Timers.lua); elements and the totem bar
	-- follow them unless they have their own.
	timers = { cooldown = CopyTable(ns.Timer.DEFAULTS.cooldown), uptime = CopyTable(ns.Timer.DEFAULTS.uptime) },
}
-- Settings a profile no longer has: dropped when it loads.
local RETIRED_KEYS = { "glowColor", "glowSpeed", "glowLow", "glowWidth", "popMotion", "popSize", "popSpeed",
	"popFlash", "popRing", "popStar", "popTint" }
local acct       -- ShamanForeverDB: account settings, and every profile
local db         -- the active profile
local profileName

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------

-- root spans the screen and takes no input: the parent of every group (each anchored to UIParent),
-- hidden as a whole for other classes. Not named ShamanForeverFrame: older versions dragged a frame
-- of that name, and the client's layout cache would re-anchor it.
local root = CreateFrame("Frame", "ShamanForeverRoot", UIParent)
root:SetAllPoints(UIParent)

local makeIcon = ns.makeIcon   -- ShamanForever_Widgets.lua

local shield = makeIcon(root, DEFAULTS.iconSize, "shield")
shield.count:Hide()

local shock = makeIcon(root, DEFAULTS.iconSize, "shock")
shock.count:Hide()
shock.cdTimer = ns.Timer.new(shock, "shock", "cooldown", { cd = shock.cd, school = "spirit" })

local imbue = makeIcon(root, DEFAULTS.iconSize, "imbue")
imbue.count:Hide()

-- Cooldown elements: a spell's cooldown, plus for a totem the active time of ours in its slot, or for
-- Fire Nova whether the fire totem it needs is out. Totem slots: 1 fire, 2 earth, 3 water, 4 air.
-- Adding one starts with a line here (its look and page go in the Options files); spellKey is its
-- spell in ns.Spells, icon the fallback until the spellbook has it, duration the totem's lifetime in
-- seconds (for the options previews).
-- spell is the display name (the client's).
local COOLDOWNS = {
	{ key = "earthbind", spellKey = "earthbind", icon = 136102, totemSlot = 2, duration = 45, school = "earth" },
	{ key = "stoneclaw", spellKey = "stoneclaw", icon = 136097, totemSlot = 2, duration = 15, school = "earth" },
	{ key = "firenova",  spellKey = "fireNova",  icon = 135824, needsTotem = 1, school = "fire" },
}
for _, def in ipairs(COOLDOWNS) do def.spell = Spells.name(def.spellKey) end

for _, def in ipairs(COOLDOWNS) do
	local f = makeIcon(root, DEFAULTS.iconSize, def.key)
	f.count:Hide()
	f.tex:SetTexture(def.icon)
	-- Effects (the glows, the pops' light, the end flashes) on a layer that ignores the icon's alpha,
	-- so an idle icon (applyIdle) doesn't fade them. It takes its group's opacity instead (layoutGroup).
	f.effects = CreateFrame("Frame", nil, f)
	f.effects:SetAllPoints()
	f.effects:SetIgnoreParentAlpha(true)
	f.glowF:SetParent(f.effects)
	if def.totemSlot or def.needsTotem then
		-- A totem's time left (its own, or for Fire Nova whichever fire totem is out): a timer of the
		-- "uptime" kind beside the spell's cooldown. Its parts sit in a holder so one alpha can hide
		-- them all (Earthbind and Stoneclaw show it only while the earth totem out is theirs).
		f.activeHolder = CreateFrame("Frame", nil, f.textFrame)
		f.activeHolder:SetAllPoints()
		f.upTimer = ns.Timer.new(f.activeHolder, def.key, "uptime", { anchor = f, dual = true, school = def.school })
	end
	f.cdTimer = ns.Timer.new(f, def.key, "cooldown", { cd = f.cd, school = def.school })
	if def.needsTotem then
		-- Ready glow (updateReadyGlow): the gate's alpha is "a fire totem is down", the glow's is "off
		-- cooldown"; nested, the two multiply.
		f.readyGate = CreateFrame("Frame", nil, f.effects)
		f.readyGate:SetAllPoints()
		f.readyGlow = ns.makeGlow(f.readyGate, f, def.key)
		-- "No totem" warning layer: a grey copy of the icon and a red ring, above the icon and below the
		-- cooldown swipe. Its alpha is set from a possibly-secret boolean (see refreshCooldown), so it
		-- always pulses and is simply invisible while a totem is out.
		f.warn = CreateFrame("Frame", nil, f)
		f.warn:SetAllPoints()
		f.warn.grey = f.warn:CreateTexture(nil, "ARTWORK")
		f.warn.grey:SetAllPoints(f.tex)
		f.warn.grey:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.warn.grey:SetDesaturated(true)
		f.warn.ring = ns.makeRing(f.warn, f.tex)
		f.warn.pulse = ns.makePulse(f.warn.grey, "fade")
		f.warn:SetAlpha(0)
		-- Hiding a frame (a combat-only group out of combat) stops its animations.
		f.warn:SetScript("OnShow", function(w) if w.pulseOn and not w.pulse:IsPlaying() then w.pulse:Play() end end)
	end
	-- Layers, bottom up: icon, Fire Nova's warning layer and the expiring warning, the swipe, the timer
	-- bar, text. Restated after regrouping (layoutGroup), since reparenting moves frame levels.
	function f.stack()
		local base = f:GetFrameLevel()
		f.effects:SetFrameLevel(base)
		f.glowF:SetFrameLevel(base + 1)
		if f.warn then f.warn:SetFrameLevel(base + 1) end
		f.cd:SetFrameLevel(base + 2)
		if f.cdTimer.bar then f.cdTimer.bar:SetFrameLevel(base + 3) end
		f.textFrame:SetFrameLevel(base + 4)
		if f.upTimer and f.upTimer.restack then f.upTimer:restack() end
	end
	f.stack()
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
-- getSize(size): the element's width and height for its group's icon size.
local function iconSize(size) return size, size end
local ELEMENTS = {
	shield = { frame = shield, label = "Shields",          getSize = iconSize, paint = function(t) t:SetTexture(ns.shieldIcon()) end },
	shock  = { frame = shock,  label = "Shocks",           getSize = iconSize, paint = function(t) t:SetTexture(shockIcon) end },
	imbue  = { frame = imbue,  label = "Weapon Imbue",     getSize = iconSize, paint = function(t) t:SetTexture(ns.imbueIcon()) end },
}
local ELEMENT_KEYS = { "shield", "shock", "imbue" }   -- registration order
for _, def in ipairs(COOLDOWNS) do
	ELEMENTS[def.key] = { frame = def.frame, label = def.spell, getSize = iconSize, cooldown = def, stack = def.frame.stack,
		paint = function(t) t:SetTexture(def.iconID or def.icon) end }
	table.insert(ELEMENT_KEYS, def.key)
end
for _, p in ipairs(PLACEHOLDERS) do
	local c = p.color
	ELEMENTS[p.key] = { frame = makePlaceholder(p), label = "Test " .. p.letter, placeholder = true,
		getSize = function(size) return size * p.w, size * p.h end,
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

-- A group's icon size: its own, or General's.
local function groupSize(g) return (g and not g.sizeFollow and g.size) or db.iconSize end
-- An element's: its group's.
local function sizeOf(key)
	local gi = findElement(key)
	return groupSize(gi and db.groups[gi])
end
ns.sizeOf = sizeOf

local function isEnabled(key) return findElement(key) ~= nil and showMode(key) ~= "never" end

local function removeElement(key)
	local gi, i = findElement(key)
	if gi then table.remove(db.groups[gi].members, i) end
end

local function newGroup(template)
	local g = {}
	for k, v in pairs(GROUP_DEFAULTS) do
		if template and template[k] ~= nil then g[k] = template[k] else g[k] = v end   -- a template's false counts
	end
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
-- update, or test ones) show; ones seen before but in no group (older saves
-- hid an element that way) come back into the first group, set to never show.
local function sanitize()
	ns.Shield.sanitize(db, acct)
	if type(db.groups) ~= "table" then db.groups = {} end
	if type(db.known) ~= "table" then db.known = {} end
	local seen = {}
	for _, g in ipairs(db.groups) do
		for k, v in pairs(GROUP_DEFAULTS) do if g[k] == nil then g[k] = v end end
		-- A border saved before styles (0.6.1 and earlier) was the group's own.
		if type(g.border) == "table" and g.border.follow == nil then g.border.follow = false end
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
local selectedGroup       -- unlocked: the group the arrow keys move (see the nudge section)

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
-- back). The driver's manager shows and hides from untainted code instead.
-- Groups and elements are driven separately, so an element shows only when both allow it. The
-- manager re-applies its state every 0.2s and does not show a frame it lets go of, so a driven frame
-- is never shown or hidden by hand. Only called out of combat.
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
-- Blizzard's shield button. size is a line's (ns.linePx): screen pixels, grown by Scale, not by Size.
local function applyBorder(f, b)
	if not (b and b.show and b.size and b.size > 0) then
		if f.border then for _, t in ipairs(f.border) do t:Hide() end end
		return
	end
	if not f.border then
		f.border = {}
		for i = 1, 4 do f.border[i] = f:CreateTexture(nil, "BACKGROUND", nil, -8) end
	end
	local s = ns.linePx(f, b.size)
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
-- shrinks to fit so dragging feels right. Every member anchors to the group frame, never to another
-- member: a frame a protected frame anchors to may turn protected too, and the shield is protected
-- (Blizzard's aura button), so a chain could stop the members before it changing in combat.
local function layoutGroup(gi)
	local g, gf = db.groups[gi], groupFrame(gi)
	local gap = g.spacing
	local horizontal = g.orientation == "horizontal"
	local forward = g.growth ~= "backward"
	local n, along, across = 0, 0, 0
	for _, key in ipairs(g.members) do
		local e = ELEMENTS[key]
		local f = e.frame
		if f:GetParent() ~= gf then f:SetParent(gf) end
		if e.stack then e.stack() end
		if showMode(key) == "never" then
			hideFrame(f)
		else
			local w, h = e.getSize(groupSize(g))
			f:SetSize(w, h)
			f:ClearAllPoints()
			local offset = along + n * gap   -- from the group's leading edge
			if horizontal then
				if forward then f:SetPoint("LEFT", gf, "LEFT", offset, 0)
				else f:SetPoint("RIGHT", gf, "RIGHT", -offset, 0) end
				along, across = along + w, math.max(across, h)
			else
				if forward then f:SetPoint("TOP", gf, "TOP", 0, -offset)
				else f:SetPoint("BOTTOM", gf, "BOTTOM", 0, offset) end
				along, across = along + h, math.max(across, w)
			end
			showFrame(f, acct.locked and showMode(key) == "combat")
			n = n + 1
		end
	end
	along = math.max(along + math.max(n - 1, 0) * gap, 1)
	across = math.max(across, 1)
	if horizontal then gf:SetSize(along, across) else gf:SetSize(across, along) end
	gf:SetScale(g.scale)
	gf:SetAlpha(g.alpha)
	for _, key in ipairs(g.members) do   -- effects layers ignore their icon's alpha, so they take the group's
		local fx = ELEMENTS[key].frame.effects
		if fx then fx:SetAlpha(g.alpha) end
	end
	-- After the scale, so borders are sized in real pixels.
	local border = ns.Style.get(g, "border")
	for _, key in ipairs(g.members) do applyBorder(ELEMENTS[key].frame, border) end
	gf:ClearAllPoints()
	gf:SetPoint(g.point, UIParent, g.point, g.x, g.y)
	local unlocked = not acct.locked
	gf:EnableMouse(unlocked)
	gf:EnableMouseWheel(unlocked)
	gf:SetBackdropColor(0, 0, 0, unlocked and 0.4 or 0)
	if unlocked and selectedGroup == gi then gf:SetBackdropBorderColor(1, 0.82, 0, 1)
	else gf:SetBackdropBorderColor(0.2, 0.6, 1, unlocked and 0.9 or 0) end
	gf.label:SetText(unlocked and selectedGroup == gi and ("Group " .. gi .. " (arrow keys move it)") or ("Group " .. gi))
	gf.label:SetShown(unlocked)
	if n > 0 then showFrame(gf, acct.locked and g.combatOnly or false) else hideFrame(gf) end
end

-- Deferred in combat: the shield's group is an ancestor of Blizzard's protected aura button, so
-- showing, hiding, moving or reparenting it in combat is silently dropped.
local updateTray   -- defined further down
local function layoutElements()
	if ns.deferInCombat("layout", layoutElements) then return end
	for key, e in pairs(ELEMENTS) do
		if not isEnabled(key) then hideFrame(e.frame) end
	end
	for gi in ipairs(db.groups) do layoutGroup(gi) end
	for gi = #db.groups + 1, #groupFrames do hideFrame(groupFrames[gi]) end
	ns.Shield.style()   -- the shield's alpha compensation follows its group's opacity
	ns.refitRings()
	updateTray()
	ns.TotemBar.layout()
	ns.RefreshOptions()
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
		ns.selectGroup(self.index)
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
	-- Wheel: icon size (lines stay crisp); Ctrl: scale (everything grows, lines too); Shift: opacity.
	f:SetScript("OnMouseWheel", function(self, delta)
		if acct.locked or InCombatLockdown() then return end
		local g = db.groups[self.index]
		local sx, sy = screenCenter(self)
		if IsShiftKeyDown() then g.alpha = clamp(round2(g.alpha + delta * 0.05), 0.1, 1)
		elseif IsControlKeyDown() then g.scale = clamp(round2(g.scale + delta * 0.05), 0.5, 3)
		else
			if g.sizeFollow then g.sizeFollow, g.size = false, db.iconSize end   -- its own from here on
			g.size = clamp(g.size + delta * 2, 24, 96)
		end
		if sx then setGroupCenter(g, sx, sy) end   -- grow about the centre, not the anchor
		layoutElements()
		self.label:SetText(string.format("Group %d: size %d, scale %.2f, opacity %.0f%%", self.index, groupSize(g), g.scale, g.alpha * 100))
	end)
	-- Right-click: the group's settings. Shift-right-click: the settings of the element under the cursor.
	f:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and not acct.locked and not InCombatLockdown() then ns.selectGroup(self.index) return end
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

-- Nudging: while unlocked, the arrow keys move the selected group by 1 (Shift: 10), repeating while
-- held; Escape deselects. Out of combat only, like dragging. Keyboard capture is restricted in combat
-- (EnableKeyboard is protected, SetPropagateKeyboardInput restricted), and a frame left swallowing
-- keys when combat starts would block every key for the fight. So: only the arrows (and Escape) are
-- kept, and only for the key press itself (propagation goes back on the next frame); the frame is
-- shown only while a group is selected out of combat; and it hides itself when combat starts, which
-- is always allowed for our own frame and stops all capture.
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local nudger = CreateFrame("Frame", "ShamanForeverNudge", UIParent)
nudger:Hide()

local function nudge(key)
	local g, d = selectedGroup and db.groups[selectedGroup], NUDGE_KEYS[key]
	local f = selectedGroup and groupFrames[selectedGroup]
	if not (g and d and f) then return end
	local step = IsShiftKeyDown() and 10 or 1
	g.x = g.x + d[1] * step / g.scale   -- offsets are in the group's scaled units
	g.y = g.y + d[2] * step / g.scale
	f:ClearAllPoints()
	f:SetPoint(g.point, UIParent, g.point, g.x, g.y)
end

local function syncNudger()
	local on = selectedGroup ~= nil and not acct.locked and not InCombatLockdown()
	if on and not nudger.keys then
		-- Out of combat only (both are restricted in combat), so not at file load: a /reload in
		-- combat would lose them for the session.
		nudger:EnableKeyboard(true)
		nudger:SetPropagateKeyboardInput(true)
		nudger.keys = true
	end
	if on then nudger:Show() else nudger:Hide() end
end

function ns.selectGroup(gi)
	if selectedGroup == gi then return end
	selectedGroup = gi
	syncNudger()
	layoutElements()
end

nudger:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then self:Hide() return end
	if NUDGE_KEYS[key] or key == "ESCAPE" then
		self:SetPropagateKeyboardInput(false)
		C_Timer.After(0, function() if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end end)
		if key == "ESCAPE" then ns.selectGroup(nil) return end
		nudge(key)
		self.held, self.wait = key, 0.4
	end
end)
nudger:SetScript("OnKeyUp", function(self, key)
	if key == self.held then self.held = nil end
end)
nudger:SetScript("OnUpdate", function(self, elapsed)
	if not self.held then return end
	self.wait = self.wait - elapsed
	if self.wait <= 0 then
		nudge(self.held)
		self.wait = 0.04
	end
end)
nudger:SetScript("OnHide", function(self) self.held = nil end)
-- Hidden frames still get events: hide at the start of combat, come back after it.
nudger:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_REGEN_DISABLED" then
		self:Hide()
		if isShaman and not acct.locked and ns.lockInCombat then ns.lockInCombat(); say("positioning locked for combat") end
	else syncNudger() end
end)
nudger:RegisterEvent("PLAYER_REGEN_DISABLED")
nudger:RegisterEvent("PLAYER_REGEN_ENABLED")

-- A small bar while unlocked: what the mouse does, snapping and grid toggles, Lock and Options.
local wasUnlocked, optionsSteppedAside = false, false   -- see stepOptionsAside
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
	tray.hint:SetText("Drag a group to move it, or click it and use the arrow keys (Shift: 10x).\n" ..
		"Mouse wheel over a group: icon size (borders stay crisp).\n" ..
		"Ctrl + wheel: scale (everything grows, borders too). Shift + wheel: opacity.\n" ..
		"Right-click a group: its settings.\n" ..
		"Shift-right-click an element: its own settings.\n" ..
		"Options: choose which elements each group holds.")
	-- Controls sit on a row under the hint, so a longer hint pushes them down instead of overlapping.
	local row = CreateFrame("Frame", nil, tray)
	row:SetPoint("TOPLEFT", tray.hint, "BOTTOMLEFT", 0, -10)
	row:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row:SetHeight(26)
	tray.row = row
	local function check(label, key, tip, parent, after)
		local cb = CreateFrame("CheckButton", nil, parent or row, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb.Text:SetFontObject("GameFontHighlightSmall")
		cb.Text:SetText(label)
		cb:SetScript("OnClick", function(self)
			acct[key] = self:GetChecked() and true or false
			if after then after(acct[key]) end
			layoutElements()
		end)
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
	lock:SetScript("OnClick", function() ns.setLocked(true) end)
	local options = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	options:SetSize(90, 22)
	options:SetPoint("RIGHT", lock, "LEFT", -6, 0)
	options:SetText("Options")
	options:SetScript("OnClick", function() ns.OpenOptions("layout") end)
	local row2 = CreateFrame("Frame", nil, tray)
	row2:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -2)
	row2:SetPoint("RIGHT", tray, "RIGHT", -10, 0)
	row2:SetHeight(24)
	-- Takes effect at once: ticking brings the window back, unticking puts it away until locking.
	tray.keepOptions = check("Keep options open", "keepOptionsOpen",
		"Unticked, the options window closes while you move groups and comes back when you lock.", row2,
		function(keep)
			if keep then
				optionsSteppedAside = false
				ns.OpenOptions()
			elseif ns.HideOptions() then
				optionsSteppedAside = true
			end
		end)
	tray.keepOptions:SetPoint("LEFT", -4, 0)
end

-- Unlocking closes the options window (unless the player keeps it open) and locking brings it back.
local function stepOptionsAside(unlocked)
	if unlocked == wasUnlocked then return end
	wasUnlocked = unlocked
	if unlocked then
		optionsSteppedAside = not acct.keepOptionsOpen and ns.HideOptions() or false
	elseif optionsSteppedAside then
		optionsSteppedAside = false
		ns.OpenOptions()
	end
end

function updateTray()
	local unlocked = isShaman and not acct.locked
	if not unlocked then selectedGroup = nil end
	if selectedGroup and not db.groups[selectedGroup] then selectedGroup = nil end
	syncNudger()
	tray:SetShown(unlocked)
	tray:SetHeight(30 + tray.hint:GetStringHeight() + 10 + 26 + 2 + 24 + 8)
	tray.snap:SetChecked(acct.snap)
	tray.keepOptions:SetChecked(acct.keepOptionsOpen)
	stepOptionsAside(unlocked)
	tray.grid:SetChecked(acct.grid)
	tray.gridValue:SetText(acct.gridSize)
	grid:SetShown(unlocked and acct.grid)
	if unlocked and acct.grid then drawGrid() end
	if not unlocked then showGuides() end
end

-- Combat locks positioning, and it cannot be unlocked until combat ends (setLocked). Showing, moving
-- and mouse changes on group frames are dropped in combat (the shield's group holds Blizzard's
-- protected aura button), so only the looks change now: tray, grid, guides, outlines, labels and
-- the selection. The full layout runs when combat ends. Called from PLAYER_REGEN_DISABLED, which comes
-- before lockdown: then the groups also stop taking the mouse, or they would eat clicks, camera drags
-- and wheel zoom for the whole fight.
function ns.lockInCombat()
	acct.locked = true
	optionsSteppedAside = false   -- no options window popping up mid-fight
	selectedGroup = nil
	local free = not InCombatLockdown()
	for _, gf in ipairs(groupFrames) do
		if free then gf:EnableMouse(false); gf:EnableMouseWheel(false) end
		gf:SetScript("OnUpdate", nil)
		gf:SetBackdropColor(0, 0, 0, 0)
		gf:SetBackdropBorderColor(0, 0, 0, 0)
		gf.label:Hide()
	end
	showGuides()
	updateTray()
	ns.retryAfterCombat("layout", layoutElements)
	ns.TotemBar.lockInCombat()
	ns.RefreshOptions()
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

local shockPainted   -- what updateShockTint last drew; repainted only on a change
local function updateShockTint()
	local now = (shockState.outOfRange and "r" or "") .. (shockState.noMana and "m" or "")
	if now == shockPainted then return end
	shockPainted = now
	shock.manaOverlay:Hide()
	shock.tex:SetVertexColor(1, 1, 1)
	if shockState.outOfRange then
		paintBody(db.rangeStyle, 1, 0.25, 0.25, db.rangeIntensity, db.rangeTint)
	elseif shockState.noMana then
		paintBody(db.manaStyle, 0.2, 0.45, 1, db.manaIntensity, db.manaTint)
	end
	shock:SetRingShown(shockState.noMana, 0.2, 0.45, 1, db.manaRing)
end

-- The global cooldown: while it runs, every spell reads as on cooldown, so the swipe, the ready pop
-- and the ready glows would react to each cast. isOnGCD says so, when it's readable (if it's secret
-- in combat, this falls back to treating it as a real cooldown). Blizzard only vouches for it inside
-- SPELL_UPDATE_COOLDOWN; the timers keep the GCD sweep, so they still read it (tested 2026-09-25).
local inCooldownEvent = false   -- set while SPELL_UPDATE_COOLDOWN refreshes (the event handler)
local function onGCD(spellID)
	local ok, info = safe(C_Spell.GetSpellCooldown, spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isOnGCD) then return false end
	return info.isOnGCD == true
end
ns.onGCD = onGCD
-- The spell's own cooldown without the GCD (ignoreGCD, on Forever since 12.0.5): true when none is
-- running, false when one is, nil when that can't be told (secret, or an older client).
local function ownCooldownOver(spellID)
	local ok, d = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if not ok then return nil end
	if not d then return true end
	local zok, z = pcall(d.IsZero, d)
	if zok and not isSecret(z) and type(z) == "boolean" then return z end
end
-- Before a cooldown timer takes a new duration: a global-cooldown sweep gets no bling, and the
-- ready pop that fires when it ends is skipped (f.gcdUntil), unless the spell's own cooldown is
-- running under the GCD: then its end is a real "ready".
local function noteGCD(f, spellID)
	local g = onGCD(spellID)
	if g and ownCooldownOver(spellID) ~= false then f.gcdUntil = GetTime() + 1.6 end
	f.cd:SetDrawBling(not g)
end
-- A cooldown timer's duration, by the element's Global cooldown style: on, with the GCD (every cast
-- sweeps it, as on action bars); off, its own cooldown only (ignoreGCD), which its own cast starts,
-- so other spells don't sweep it. nil when none can be read.
local function cooldownFor(f, key, spellID)
	if ns.Style.value(key, "gcd", "show") then
		local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID)
		if not (ok and dur) then return nil end
		noteGCD(f, spellID)
		return dur
	end
	f.gcdUntil = nil
	f.cd:SetDrawBling(true)
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	-- None running: clear what an earlier read (a GCD sweep from before the style changed) left.
	if ok and not dur then f.cdTimer:clear() end
	return ok and dur or nil
end

local function refreshShockCooldown()
	if not shockSpellID or not isEnabled("shock") then return end
	local dur = cooldownFor(shock, "shock", shockSpellID)
	if dur then shock.cdTimer:set(dur) end
end

local function refreshShockRange()
	if not shockSpellID or not isEnabled("shock") then return end
	-- The event also fires for other spells' checks; the 4 Hz ticker covers ours either way.
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
-- Cooldown elements (see COOLDOWNS). Nothing here reads a secret value:
-- * The spell cooldown and a totem's time are duration objects that Blizzard widgets draw (cooldown
--   swipe, countdown numbers, timer bar), as with the shock.
-- * Fire Nova's "no fire totem" warning: the fire slot's duration object evaluates its remaining time
--   through a curve (0s -> 1, anything more -> 0) and the result, secret or not, goes straight to
--   SetAlpha, which accepts secrets. An empty slot returns no duration object at all (seen
--   2026-09-23), which is plainly "no totem"; an expired one evaluates to 0s remaining.
--   (IsZero doesn't work: an expired totem's duration is not a zero time span.)
--   The addon never branches on it.
-- * Earthbind / Stoneclaw must tell their totem from any other earth totem, and in combat everything
--   GetTotemInfo returns is secret (tested 2026-09-23). Our own UNIT_SPELLCAST_SUCCEEDED is not: it
--   gives the spell, in combat too, in the same frame as the PLAYER_TOTEM_UPDATE that fills the
--   slot (tested 2026-09-24). So the totem in each slot is the last totem we cast into it
--   (totemOwner), and the timer's holder is shown only when that is this element's totem. The
--   slot's duration object still drives the timer, and an empty slot has none.
--   Call of the Elements fires one cast per totem it drops, after its own (tested 2026-09-25), so
--   its totems are bound like any other. When the owner is unknown (a /reload with a totem already
--   out), out of combat the slot says which totem it is (its spell ID, else its icon), and that is
--   kept as the owner. In combat the slot is secret, so the timer stays hidden until combat ends or
--   the totem is recast: a /reload in combat isn't worth guessing for.
------------------------------------------------------------------------
-- Remaining seconds -> alpha: fully shown at 0s, hidden from 0.05s up.
local noTimeLeftCurve = ns.CURVE_OVER

-- An element's option (db.elementOpts[key]) with its default: an element's own default, else
-- everyone's. Every element starts with its pops on and its "use me" glows off.
local ELEMENT_OPT_DEFAULTS = {
	readyPop = true, readyGlow = false,                          -- Ready (cooldowns)
	blockedGrey = true, blockedRing = false, blockedPulse = false,  -- No fire totem (Fire Nova)
	expiredPop = true,                                           -- a totem ran out
	killed = true, killedPop = true, killedGlow = true, killedMark = true,   -- a totem killed early
	idleAlpha = 0.35, idleWhen = "never",                        -- Idle (idleWhen: Fire Nova's rule)
}
local function elementSetting(key, name)
	local v = elementOpts(key)[name]
	if v == nil then return ELEMENT_OPT_DEFAULTS[name] end
	return v
end
ns.elementSetting = elementSetting

-- Whether a totem is out in a slot, its spell ID and icon (each nil if not given); nil when the slot
-- cannot be read. haveTotem alone is not enough: on Forever an empty slot reports haveTotem true with a
-- blank name, and a slot can also return nothing at all (both seen 2026-09-23). So a totem is out
-- only when it has a name. The name itself is never used to tell totems apart (it is in the
-- client's language and carries the rank, "Stoneclaw Totem II").
local function readTotem(slot)
	if not GetTotemInfo then return nil end
	local ok, have, name, _, _, icon, _, spellID = pcall(GetTotemInfo, slot)
	if not ok or isSecret(have) or isSecret(name) then return nil end
	if not have or type(name) ~= "string" or name == "" then return false end
	if isSecret(spellID) or type(spellID) ~= "number" then spellID = nil end
	if isSecret(icon) or type(icon) ~= "number" then icon = nil end
	return true, spellID, icon
end

-- The totem in each slot, from our own casts: slot -> cooldown element key, or "other" for any other
-- totem of that slot; nil while unknown. Which slot a totem spell fills comes from the multi-cast
-- bar's lists, by ID, and for a rank not listed there by the client's name (ranks share it).
local totemOwner = {}
local totemSpells = {}   -- slot -> spell ID of the totem we last cast into it
local totemSlotByID, totemSlotByName = {}, {}

local function scanTotemSlots()
	if not GetMultiCastTotemSpells then return end
	local byID, byName = {}, {}
	for slot = 1, 4 do
		local ok, ids = pcall(function() return { GetMultiCastTotemSpells(slot) } end)
		if not ok then return end   -- keep the last good map
		for _, id in ipairs(ids) do
			if type(id) == "number" and not isSecret(id) then
				byID[id] = slot
				local name = Spells.nameOf(id)
				if name then byName[name] = slot end
			end
		end
	end
	totemSlotByID, totemSlotByName = byID, byName
end

-- Our own cast: if it put a totem in a slot, remember which.
local function totemCast(spellID)
	local slot = totemSlotByID[spellID]
	if not slot then
		local name = Spells.nameOf(spellID)
		slot = name and totemSlotByName[name]
		if not slot then return end
		totemSlotByID[spellID] = slot
	end
	local key = Spells.keyOf(spellID)
	local owner = "other"
	for _, def in ipairs(COOLDOWNS) do
		if def.totemSlot == slot and key == def.spellKey then owner = def.key end
	end
	totemOwner[slot] = owner
	totemSpells[slot] = spellID
	-- Recast: that element's killed-early cross goes.
	for _, def in ipairs(COOLDOWNS) do
		if def.key == owner and def.frame.killed then def.frame.killed.mark:Hide() end
	end
end
function ns.totemSpellInSlot(slot) return totemSpells[slot] end

-- The end of an Earthbind / Stoneclaw totem: the totem bar reports a slot that emptied without our
-- dismissing or replacing it (ShamanForever_TotemBar.lua); the element whose totem it was (our last
-- cast into the slot) plays its ends, each gated on the time the totem had left (ns.makeEndFlash):
-- killed early, or ran out.
function ns.onTotemGone(slot, dur)
	local owner = totemOwner[slot]
	for _, def in ipairs(COOLDOWNS) do
		if def.totemSlot == slot and owner == def.key and isEnabled(def.key) then
			local f, key = def.frame, def.key
			if elementSetting(key, "expiredPop") then
				if not f.expired then f.expired = ns.makeEndFlash(f.effects or f, f, key) end
				f.expired:setIcon(def.iconID or def.icon)
				f.expired:play(dur, { expired = true, pop = true })
			end
			if elementSetting(key, "killed") then
				if not f.killed then f.killed = ns.makeEndFlash(f.effects or f, f, key) end
				f.killed:setIcon(def.iconID or def.icon)
				f.killed:play(dur, { pop = elementSetting(key, "killedPop"), glow = elementSetting(key, "killedGlow"), mark = elementSetting(key, "killedMark") })
			end
		end
	end
end

-- Looks that change only with the spellbook and settings (applyLayout): the icon, and Fire Nova's
-- warning layer.
local function styleCooldown(def)
	local f = def.frame
	f.tex:SetTexture(def.iconID or def.icon)
	local w = f.warn
	if not w then return end
	w.grey:SetTexture(def.iconID or def.icon)
	w.grey:SetShown(elementSetting(def.key, "blockedGrey"))
	w.ring:show(elementSetting(def.key, "blockedRing"))
	w.pulseOn = elementSetting(def.key, "blockedPulse")   -- OnShow restarts it after the group was hidden
	if w.pulseOn then
		if not w.pulse:IsPlaying() then w.pulse:Play() end
	else w.pulse:Stop() end
end

-- Idle (Earthbind, Stoneclaw, Fire Nova): off cooldown, with nothing of its own going on. Both halves
-- are plain values in combat (probed 2026-09-26): the spell's own cooldown from GetSpellCooldown's
-- isActive and isOnGCD (a global cooldown shows as active and on the GCD; the duration object is
-- secret), and a totem from its slot having a duration at all (nil the moment it's gone) plus our
-- own casts. An idle icon takes its "Opacity when idle" and keeps its place in the group; it is
-- always full while positioning is unlocked. The end of a cooldown fires no event: OnCooldownDone
-- (below) and the 1 s ticker catch it. isOnGCD is only vouched for inside SPELL_UPDATE_COOLDOWN, so
-- its answer is kept (def.cdRunning) and only re-read there; isActive false needs no such care.
-- Going idle waits IDLE_DELAY at full opacity first, so a ready or run-out pop plays at full.
local IDLE_DELAY = 1.5
local refreshCooldown           -- below
local function ownCooldownRunning(def)
	local ok, info = safe(C_Spell.GetSpellCooldown, def.spellID)
	if not ok or type(info) ~= "table" or isSecret(info.isActive) then return true end   -- can't tell: not idle
	if info.isActive == false then def.cdRunning = false return false end
	if inCooldownEvent or def.cdRunning == nil then
		if isSecret(info.isOnGCD) then return true end
		def.cdRunning = info.isOnGCD ~= true
	end
	return def.cdRunning
end
local function idleAlpha(key)
	local v = elementSetting(key, "idleAlpha")
	if type(v) ~= "number" or v ~= v then return 1 end
	return math.min(math.max(v, 0), 1)
end
-- The icon eases to its new opacity: slowly into idle, quickly back (each rate covers 0 to 1).
local FADE_OUT, FADE_IN = 0.8, 0.15
local fading = {}   -- def -> target alpha
local fader = CreateFrame("Frame")
fader:Hide()
fader:SetScript("OnUpdate", function(self, elapsed)
	for def, target in pairs(fading) do
		local a = def.frame:GetAlpha()
		if target < a then a = math.max(target, a - elapsed / FADE_OUT)
		else a = math.min(target, a + elapsed / FADE_IN) end
		def.frame:SetAlpha(a)
		if a == target then fading[def] = nil end
	end
	if next(fading) == nil then self:Hide() end
end)
local function fadeTo(def, alpha)
	if math.abs(def.frame:GetAlpha() - alpha) < 0.005 then
		fading[def] = nil
		def.frame:SetAlpha(alpha)
		return
	end
	fading[def] = alpha
	fader:Show()
end

-- totemBusy: our totem is down (Earthbind, Stoneclaw), or any fire totem is (Fire Nova).
local function applyIdle(def, totemBusy)
	local when = def.needsTotem and elementSetting(def.key, "idleWhen")   -- Fire Nova: never | nototem | offcd
	local cdRunning = ownCooldownRunning(def)   -- always, so its kept answer stays current
	local busy = not acct.locked or when == "never" or cdRunning
	if not busy and totemBusy then busy = when ~= "offcd" end
	if busy then def.idleAt = nil
	elseif def.idle == false then
		-- Just went idle: full for a moment, then refresh to fade.
		def.idleAt = GetTime() + IDLE_DELAY
		C_Timer.After(IDLE_DELAY + 0.05, function() refreshCooldown(def) end)
	end
	local waiting = def.idleAt and GetTime() < def.idleAt
	fadeTo(def, (busy or waiting) and 1 or idleAlpha(def.key))
	def.idle = not busy
end

-- def.read (for /sf debug) is kept as parts and only formatted there.
function refreshCooldown(def)
	if not isEnabled(def.key) then def.cdRunning = nil return end   -- read afresh when it's back
	local f = def.frame
	if f.killed and not (elementSetting(def.key, "killed") and elementSetting(def.key, "killedMark")) then f.killed.mark:Hide() end
	if not def.spellID then
		-- Not learned yet: a plain grey icon.
		fadeTo(def, 1)
		def.idle = nil
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		f.cdTimer:clear()
		if f.upTimer then f.upTimer:clear() end
		if f.warn then f.warn:SetAlpha(0) end
		return
	end
	local dur = cooldownFor(f, def.key, def.spellID)
	if dur then f.cdTimer:set(dur) end
	f.tex:SetDesaturated(false)
	if def.needsTotem then
		-- Fire Nova: the slot's duration object drives everything, secret or not. An empty slot has
		-- none and an expired one evaluates to 0 s, so the timer widgets draw nothing and the warning
		-- layer shows.
		local tok, tdur = safe(GetTotemDuration, def.needsTotem)
		applyIdle(def, tok and tdur ~= nil)
		f.activeHolder:SetAlpha(1)   -- any fire totem counts, so its timer always shows
		if tok and tdur == nil then
			-- Nothing in the slot: no duration object to evaluate.
			f.warn:SetAlpha(1)
			def.read = "no fire totem (no duration)"
		else
			local aok, alpha = false, nil
			if tok and tdur and noTimeLeftCurve then
				aok, alpha = ns.try("fire nova warning", tdur.EvaluateRemainingDuration, tdur, noTimeLeftCurve)
			end
			if aok and alpha ~= nil then
				f.warn:SetAlpha(alpha)
				def.read = alpha   -- possibly secret; described by /sf debug
			else
				f.warn:SetAlpha(0)
				def.read = tok and "fire slot duration unreadable" or "fire slot duration error"
			end
		end
		f.upTimer:set(tok and tdur or nil)
	elseif def.totemSlot then
		-- Earthbind / Stoneclaw: the slot's timer, shown only while this totem is the one in the slot
		-- (see the section comment).
		local slot = def.totemSlot
		local tok, tdur = safe(GetTotemDuration, slot)
		if tok and tdur then
			local owner = totemOwner[slot]
			local match, how
			if owner then
				match, how = owner == def.key and 1 or 0, "cast"
			else
				-- Not known from our casts (a /reload with the totem already down): out of combat the
				-- slot's spell, else its icon (every rank shares it); kept as the owner, so it holds
				-- into combat. In combat: unknown, hidden.
				local have, spellID, icon = readTotem(slot)
				local mine
				if have and spellID then mine, how = Spells.keyOf(spellID) == def.spellKey, "slot spell"
				elseif have and icon then mine, how = icon == def.iconID or icon == def.icon, "slot icon" end
				if mine ~= nil then
					match = mine and 1 or 0
					if mine then
						totemOwner[slot] = def.key
						if spellID then totemSpells[slot] = spellID end
					end
				else
					match, how = 0, "unknown"
				end
			end
			f.activeHolder:SetAlpha(match)
			f.upTimer:set(tdur)
			def.read, def.readHow = match, how
			applyIdle(def, match == 1)
		else
			f.activeHolder:SetAlpha(0)
			f.upTimer:clear()
			def.read, def.readHow = "no earth totem", nil
			applyIdle(def, false)
		end
	end
end

local function refreshCooldowns()
	for _, def in ipairs(COOLDOWNS) do refreshCooldown(def) end
end

-- Pop when ready: Blizzard's cooldown widget says when its swipe finishes (OnCooldownDone), a
-- moment with no secret in it, so the icon can pop right then, in combat too.
local function popWhenReady(f, key)
	f.cd:HookScript("OnCooldownDone", function()
		if f.gcdUntil and GetTime() <= f.gcdUntil then return end   -- a global cooldown ended
		if isEnabled(key) and elementSetting(key, "readyPop") then f:Pop() end
	end)
end
popWhenReady(shock, "shock")
for _, def in ipairs(COOLDOWNS) do
	popWhenReady(def.frame, def.key)
	-- A cooldown ending can make it idle (see applyIdle); read on the next frame.
	def.frame.cd:HookScript("OnCooldownDone", function() C_Timer.After(0, function() refreshCooldown(def) end) end)
end

-- Ready glows ("use me"), both off by default. Fire Nova: while it is off cooldown and a fire totem
-- is down, the moment it can be cast; both are secret in combat, so each goes through a curve into
-- one of two nested frames' alphas. Shocks: while the shock is off cooldown. Re-read ten times a
-- second while any is on, so they follow a cooldown ending or a totem running out without waiting for
-- an event.
local hasTimeLeftCurve = ns.CURVE_LIVE
-- 1 while the spell is off cooldown (possibly secret: only ever handed to SetAlpha). Its own
-- cooldown, without the GCD (ignoreGCD), so the glow doesn't blink with every cast.
local function readyAlpha(spellID)
	local ok, dur = safe(C_Spell.GetSpellCooldownDuration, spellID, true)
	if not (ok and dur) then return 1 end   -- no cooldown running
	local rok, r = ns.try("ready glow", dur.EvaluateRemainingDuration, dur, ns.CURVE_OVER)
	if rok then return r end
	return 0
end
local function updateShockGlow()
	local on = shockSpellID and isEnabled("shock") and elementSetting("shock", "readyGlow") and noTimeLeftCurve
	shock.glowF:SetShown(on and true or false)
	if not on then return end
	shock.glowF:fit(shock:GetWidth())
	shock.glowF:SetAlpha(readyAlpha(shockSpellID))
end
local function updateReadyGlow(def)
	local f = def.frame
	local on = def.spellID and isEnabled(def.key) and elementSetting(def.key, "readyGlow") and hasTimeLeftCurve and noTimeLeftCurve
	f.readyGlow:SetShown(on and true or false)
	if not on then return end
	f.readyGlow:fit(f:GetWidth())
	local tok, tdur = safe(GetTotemDuration, def.needsTotem)
	if not (tok and tdur) then f.readyGate:SetAlpha(0) return end   -- no fire totem
	local gok, g = ns.try("ready gate", tdur.EvaluateRemainingDuration, tdur, hasTimeLeftCurve)
	if gok then f.readyGate:SetAlpha(g) else f.readyGate:SetAlpha(0) end
	f.readyGlow:SetAlpha(readyAlpha(def.spellID))
end
local readyTicker = CreateFrame("Frame")
readyTicker:Hide()
readyTicker.t = 0
readyTicker:SetScript("OnUpdate", function(self, elapsed)
	self.t = self.t + elapsed
	if self.t < 0.1 then return end
	self.t = 0
	for _, def in ipairs(COOLDOWNS) do
		if def.needsTotem then updateReadyGlow(def) end
	end
	updateShockGlow()
end)
-- Runs only while a ready glow is turned on (checked on every layout, i.e. every settings change).
local function syncReadyTicker()
	local want = false
	if isShaman then
		want = isEnabled("shock") and elementSetting("shock", "readyGlow")
		for _, def in ipairs(COOLDOWNS) do
			if def.needsTotem and isEnabled(def.key) and elementSetting(def.key, "readyGlow") then want = true end
		end
	end
	readyTicker:SetShown(want and true or false)
	if not want then
		-- One last pass turns the glows off.
		updateShockGlow()
		for _, def in ipairs(COOLDOWNS) do if def.needsTotem then updateReadyGlow(def) end end
	end
end

------------------------------------------------------------------------
-- Spell resolution and layout
------------------------------------------------------------------------
-- Looks up every tracked spell: display names in the client's language, the highest rank known, the
-- shock's range check. Returns a signature of what it found, so callers can skip a relayout when
-- nothing changed (SPELLS_CHANGED fires often).
local rangeCheckID   -- the spell whose range check is on
local function resolveSpells()
	Spells.scan()
	local sig = { ns.Shield.resolve() }
	shockIDs = {}
	for key, spell in pairs(SHOCK_SPELL) do
		SHOCKS[key] = Spells.name(spell)
		local id = Spells.known(spell)
		if id then shockIDs[key] = id end
	end
	local id, ic = Spells.known(SHOCK_SPELL[db.shock] or SHOCK_SPELL.earth)
	shockSpellID = id
	shockIcon = ic or 136026
	shock.tex:SetTexture(shockIcon)
	manaSpellID = (db.manaSpell ~= "tracked" and shockIDs[db.manaSpell]) or shockSpellID
	if rangeCheckID ~= shockSpellID and C_Spell.EnableSpellRangeCheck then
		if rangeCheckID then safe(C_Spell.EnableSpellRangeCheck, rangeCheckID, false) end
		if shockSpellID then safe(C_Spell.EnableSpellRangeCheck, shockSpellID, true) end
		rangeCheckID = shockSpellID
	end
	table.insert(sig, tostring(shockSpellID)); table.insert(sig, tostring(manaSpellID))
	for _, def in ipairs(COOLDOWNS) do
		def.spell = Spells.name(def.spellKey)
		ELEMENTS[def.key].label = def.spell
		def.spellID, def.iconID = Spells.known(def.spellKey)
		table.insert(sig, tostring(def.spellID)); table.insert(sig, tostring(def.iconID))
	end
	ns.Imbue.resolve()
	scanTotemSlots()
	return table.concat(sig, ",")
end

-- Every timer takes its current style (General's or its own).
local function applyTimers()
	shock.cdTimer:apply()
	for _, def in ipairs(COOLDOWNS) do
		def.frame.cdTimer:apply()
		if def.frame.upTimer then
			def.frame.upTimer:apply()
			def.frame.upTimer:setExpire(ns.expireOpts(def.key), def.iconID or def.icon)
		end
	end
	ns.Imbue.applyTimer()
	ns.TotemBar.applyTimers()
	ns.Shield.applyTimer()
end
ns.applyTimers = applyTimers

local function applyLayout()
	layoutElements()
	applyTimers()
	for _, def in ipairs(COOLDOWNS) do styleCooldown(def) end
	shockPainted = nil   -- the looks may have changed
	updateShockTint()
	refreshShockMana()
	ns.Imbue.refresh()
	refreshCooldowns()
	ns.Shield.setup()
	ns.Shield.style()
	ns.Shield.applyEmptyLook()
	syncReadyTicker()
end

-- Every lock and unlock goes through here: in combat, locking takes the combat path and unlocking
-- is refused. Returns whether the state changed as asked. Only shamans have anything to position.
function ns.setLocked(locked)
	if not isShaman then say("positioning is for shamans only") return false end
	if InCombatLockdown() then
		if not locked then say("positioning can't be unlocked in combat") return false end
		if not acct.locked then ns.lockInCombat() end
		return true
	end
	acct.locked = locked
	applyLayout()
	return true
end

local function refreshAll()
	ns.Shield.refresh()
	ns.Shield.refreshGCD(inCooldownEvent)
	refreshShockCooldown()
	refreshShockRange()
	refreshShockMana()
	ns.Imbue.refresh()
	refreshCooldowns()
end

-- A cast, a cooldown update and a totem update come in the same frame (three or more events per
-- cast). SPELL_UPDATE_COOLDOWN refreshes at once (isOnGCD is only vouched for inside it); the others
-- wait for the next frame, by then with the cast's totem owner, and are skipped if that event came.
local cooldownsDirty = false
local function flushCooldowns()
	cooldownsDirty = false
	ns.Shield.refreshGCD(inCooldownEvent)
	refreshShockCooldown()
	refreshCooldowns()
end
local function flushIfDirty() if cooldownsDirty then flushCooldowns() end end
local function refreshCooldownsSoon()
	if cooldownsDirty then return end
	cooldownsDirty = true
	C_Timer.After(0, flushIfDirty)
end

-- Layout edits used by the options window. Each leaves db.groups consistent and relays out.
local function edit(fn)
	return function(...)
		if InCombatLockdown() then say("layout changes wait until combat ends"); return false end
		local groups = #db.groups
		fn(...)
		pruneGroups()
		-- Groups renumbered: the selection (an index) would jump to another group.
		if #db.groups ~= groups then selectedGroup = nil; syncNudger() end
		layoutElements()
		return true
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
-- The active profile (the rest of profiles: ShamanForever_Profiles.lua)
------------------------------------------------------------------------
local function fillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then t[k] = type(v) == "table" and CopyTable(v) or v end
	end
end

-- Makes name the active profile (created from defaults if new) and remembers it for this character.
local function selectProfile(name)
	if type(acct.profiles[name]) ~= "table" then acct.profiles[name] = {} end
	profileName, db = name, acct.profiles[name]
	for _, k in ipairs(RETIRED_KEYS) do db[k] = nil end
	fillDefaults(db, DEFAULTS)
	sanitize()
	ns.Profiles.remember(name)
end

-- Everything drawn again from the active profile.
local function redraw()
	resolveSpells(); ns.applyGlowStyle(); applyLayout(); refreshAll()
	ns.RefreshOptions()
end

local function useProfile(name)
	selectProfile(name)
	redraw()
end

-- Shared with the other files
ns.DEFAULTS, ns.GROUP_DEFAULTS, ns.SHOCKS, ns.SHOCK_ORDER = DEFAULTS, GROUP_DEFAULTS, SHOCKS, SHOCK_ORDER
ns.ELEMENTS, ns.ELEMENT_KEYS, ns.available, ns.findElement = ELEMENTS, ELEMENT_KEYS, available, findElement
ns.isEnabled = isEnabled
ns.getDB = function() return db end
ns.getAccount = function() return acct end
ns.profileName = function() return profileName end
ns.useProfile, ns.selectProfile, ns.fillDefaults = useProfile, selectProfile, fillDefaults
ns.applyLayout, ns.resolveSpells, ns.refreshAll, ns.elementOpts = applyLayout, resolveSpells, refreshAll, elementOpts
ns.placeElement, ns.splitGroup, ns.hideGroup, ns.centerGroup = placeElement, splitGroup, hideGroup, centerGroup
ns.setShow, ns.showMode = setShow, showMode
ns.COOLDOWNS = COOLDOWNS
ns.applyBorder = applyBorder
-- An element's expiring warning (its time left's last seconds): its own settings over the defaults.
function ns.expireOpts(key)
	local o = elementOpts(key).expire
	local own = ns.Timer.EXPIRE_ELEMENT[key] or {}
	local out = {}
	for k, v in pairs(ns.Timer.EXPIRE_DEFAULTS) do
		if own[k] ~= nil then v = own[k] end
		if type(o) == "table" and type(o[k]) == type(v) then out[k] = o[k] else out[k] = v end   -- a saved false counts
	end
	return out
end
-- The border an element wears: its group's.
function ns.borderFor(key)
	local gi = findElement(key)
	return ns.Style.get(gi and db.groups[gi] or nil, "border")
end
ns.setTestMode = function(on) return edit(setTestMode)(on) end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local lastSpells   -- resolveSpells' last signature
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
		acct = ns.Profiles.load()
		selectProfile(ns.Profiles.saved())   -- a guess on a cold start (no name yet): checked at PLAYER_LOGIN
		ns.BuildOptions()
	elseif event == "PLAYER_LOGIN" then
		-- The name is known now: switch to this character's own profile if loading couldn't tell.
		local want = ns.Profiles.saved()
		if want ~= profileName then selectProfile(want) end
		ns.applyIssueReporter()   -- any class
		local _, class = UnitClass("player")
		if class ~= "SHAMAN" then root:Hide(); return end
		isShaman = true
		ns.try("spell self-check", Spells.selfCheck)   -- unknown seed IDs go to the error log (/sf debug)
		ns.applyMinimapButton()
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
		-- Tickers first, each refresher on its own: one that errors can't stop the others, and an
		-- error at login can't leave the HUD without its tickers.
		C_Timer.NewTicker(0.25, function() ns.try("range refresh", refreshShockRange) end)
		C_Timer.NewTicker(1, function()
			ns.try("imbue refresh", ns.Imbue.refresh)
			ns.try("cooldown refresh", refreshCooldowns)
			ns.try("shock refresh", refreshShockCooldown)
		end)
		lastSpells = resolveSpells()
		ns.applyGlowStyle()
		applyLayout()
		refreshAll()
		root:Show()
	elseif event == "UNIT_AURA" then
		ns.Shield.refresh()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		local spellID = arg3   -- args: unit, castGUID, spellID
		if not isSecret(spellID) then
			ns.Shield.onCast(spellID)   -- the one inference (ShamanForever_Shield.lua)
			ns.Imbue.onCast(spellID)   -- only to learn an unknown imbue enchant ID
			totemCast(spellID)
		end
		refreshCooldownsSoon()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		inCooldownEvent = true
		ns.try("cooldown refresh", flushCooldowns)
		inCooldownEvent = false
	elseif event == "SPELL_UPDATE_USABLE" or event == "UNIT_POWER_UPDATE" then
		refreshShockMana()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "SPELL_RANGE_CHECK_UPDATE" then
		refreshShockRange()
	elseif event == "PLAYER_TOTEM_UPDATE" then
		refreshCooldownsSoon()
	elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
		ns.Imbue.refresh()
	elseif event == "SPELLS_CHANGED" then
		-- Fires often (shapeshifts, zoning, ...): a relayout only when a tracked spell changed.
		local found = resolveSpells()
		if found ~= lastSpells then lastSpells = found; applyLayout() end
		refreshAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Anything held back in combat has run already (ns.deferInCombat).
		refreshAll()
	end
end)

------------------------------------------------------------------------
-- /sf debug (ShamanForever_Slash.lua): what the addon sees right now
------------------------------------------------------------------------
function ns.debugReport()
	say("in combat %s", tostring(InCombatLockdown()))
	ns.Shield.debug()
	say("shock spell %s (%s), mana spell %s", tostring(shockSpellID), db.shock, tostring(manaSpellID))
	-- Every tracked spell: the client's name and the rank known (by spell ID, not name).
	local known = {}
	for key in pairs(Spells.DEFS) do
		local id = Spells.known(key)
		table.insert(known, string.format("%s=%s", Spells.name(key), id and tostring(id) or "-"))
	end
	table.sort(known)
	say("spells: %s", table.concat(known, ", "))
	ns.Imbue.debug()
	for slot = 1, 4 do
		local ok, have, name, start, duration, icon, _, spellID = pcall(GetTotemInfo, slot)
		say("totem slot %d: %s", slot, ok and string.format("have=%s name=%s start=%s duration=%s icon=%s spellID=%s",
			describeArg(have), describeArg(name), describeArg(start), describeArg(duration), describeArg(icon), describeArg(spellID))
			or ("error " .. tostring(have)))
		local dok, d = pcall(GetTotemDuration, slot)
		if dok and d then
			local rok, rem = pcall(d.GetRemainingDuration, d)
			local tok, total = pcall(d.GetTotalDuration, d)
			say("  duration object: remaining=%s total=%s", rok and describeArg(rem) or "error", tok and describeArg(total) or "error")
		end
	end
	for _, def in ipairs(COOLDOWNS) do
		local secret = "?"
		if def.spellID and C_Secrets and C_Secrets.ShouldTotemSpellBeSecret then
			local ok, v = pcall(C_Secrets.ShouldTotemSpellBeSecret, def.spellID)
			secret = ok and describeArg(v) or "error"
		end
		local read = def.read == nil and "not checked" or describeArg(def.read)
		if def.readHow then read = string.format("earth slot timer, by %s, match %s", def.readHow, read)
		elseif def.needsTotem and type(def.read) ~= "string" and def.read ~= nil then read = "warning alpha " .. read end
		say("%s: spell %s, totem spell secret=%s, %s, idle %s", def.spell, tostring(def.spellID), secret, read, tostring(def.idle))
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
		local _, usable, noPower = safe(C_Spell.IsSpellUsable, id)
		local _, inRange = safe(C_Spell.IsSpellInRange, id, "target")
		local e = Spells.bookEntry(SHOCK_SPELL[key])
		say("%s id %s rank %s usable=%s noPower=%s inRange=%s", SHOCKS[key], tostring(id),
			e and e.rank or "?", describeArg(usable), describeArg(noPower), describeArg(inRange))
	end
	say("profile %s", tostring(profileName))
	say("%s", ns.TotemBar.debug())
	for gi, g in ipairs(db.groups) do
		local names = {}
		for _, key in ipairs(g.members) do
			local mode = showMode(key)
			table.insert(names, mode == "always" and key or (key .. " (" .. mode .. ")"))
		end
		say("group %d: %s, %s, size %d%s, scale %.2f, opacity %.2f, at %s %.0f,%.0f%s", gi, table.concat(names, ","),
			g.orientation, groupSize(g), g.sizeFollow and " (General)" or "", g.scale, g.alpha, g.point, g.x, g.y,
			g.combatOnly and ", combat only" or "")
	end
	local errs = ns.errorLines()
	if #errs == 0 then say("no caught errors")
	else for _, line in ipairs(errs) do say("caught error: %s", line) end end
end
