-- Shields (Lightning or Water)
-- Blizzard's aura button shows the shield; the No shield look is a clip look the engine draws only
-- while no tracked shield is up, in combat too, with nothing read. One aura slot matches every
-- tracked shield (they exclude each other).
-- Until the button can be made (a login in combat or a PvP match) the plain icon shows: a miss,
-- never a false warning.

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

local SH = { name = "shield" }
ns.Shield = SH

-- Only one shield can be on at a time; Water Shield is a talent here (408510: its cast and buff)
local SHIELDS = {
	lightning = { spell = "lightningShield", icon = 136051, school = "air" },
	water     = { spell = "waterShield",     icon = 132315, school = "water" },
}
local SHIELD_ORDER = { "lightning", "water" }

local shield = ns.newElementIcon("shield")
-- Blizzard's container hangs from this: its alpha changes only out of combat (an ancestor of the button)
local gate = CreateFrame("Frame", nil, shield)
gate:SetAllPoints(shield)
-- The element's border while Blizzard's button isn't made
local edge = CreateFrame("Frame", nil, gate)
edge:SetAllPoints(shield)
edge.owner = "shield"
local IDLE_CHOICES = {
	{ "never", "Never", "It always shows in full" },
	{ "up", "Shield up", "Idle while your shield is up", "Shown in full only as No shield." },
	{ "charges", "2 or more charges",
		"Idle while your shield has 2 or more charges. "
			.. "It shows in full at 1 charge and as No shield at 0",
		"Shown in full at 1 charge and as No shield." },
}
ns.registerElement("shield", { frame = shield, label = "Shields", paint = function(t) t:SetTexture(SH.icon()) end,
	learned = function() return SH.learned() end,
	defaults = { idleWhen = "never", idleAlpha = 0.3, removedSound = "none" },
	def = { key = "shield", idleChoices = IDLE_CHOICES },
	effects = { glow = { "missing" }, pop = {} },
	borderHost = edge,
	standInBorder = true,
	kind = "shield", icon = 136051, school = "spirit", blurb = "Charges and time left. Warns when it's gone.",
	ownSchool = function() return SH.school() end })

for _, s in pairs(SHIELDS) do
	s.name = Spells.name(s.spell)
	s.castIDs = {}
	for _, id in ipairs(Spells.DEFS[s.spell].ids) do s.castIDs[id] = true end
end
-- Kept as which shield, not "a tracked one is up", so a new Track is judged at once
local upShield
local native
local copy   -- one-charge copy's aura slot

local function tracksShield(key)
	local track = ns.getDB().shieldTrack
	return track == "either" or track == key
end
local function believedUp()
	if upShield == nil then return nil end
	return upShield ~= "none" and tracksShield(upShield)
end

local COUNT_NUDGE = { CENTER = { 0, 0 }, TOPLEFT = { -2, 2 }, TOPRIGHT = { 2, 2 }, BOTTOMLEFT = { -2, -2 },
	BOTTOMRIGHT = { 2, -2 } }
local COUNT_POS_SAVED = { center = "CENTER", corner = "BOTTOMRIGHT" }

function SH.placeCount(fs, icon)
	local pos = ns.getDB().countPos
	local nudge = COUNT_NUDGE[pos]
	fs:ClearAllPoints()
	fs:SetPoint(pos, icon, pos, nudge[1], nudge[2])
	fs:SetJustifyH(ns.COUNT_JUSTIFY[pos])
end

function SH.sanitize(db, acct)
	if db.shieldTrack ~= "either" and not SHIELDS[db.shieldTrack] then db.shieldTrack = "lightning" end
	db.countPos = COUNT_POS_SAVED[db.countPos] or db.countPos
	if not ns.COUNT_JUSTIFY[db.countPos] then db.countPos = "CENTER" end
	if not SHIELDS[acct.lastShield] then acct.lastShield = "lightning" end
	if not ns.isColor(db.countLastColor) then db.countLastColor = CopyTable(ns.DEFAULTS.countLastColor) end
end

local function shownShield()
	local track, last = ns.getDB().shieldTrack, ns.getAccount().lastShield
	if SHIELDS[track] then return track end
	if SHIELDS[last] and SHIELDS[last].known then return last end
	for _, key in ipairs(SHIELD_ORDER) do if SHIELDS[key].known then return key end end
	return "lightning"
end
function SH.icon()
	local s = SHIELDS[shownShield()]
	return s.bookIcon or s.icon
end
function SH.school()
	local s = SHIELDS[shownShield()]
	return s.known and s.school or nil
end

-- Match by spell ID, never by name alone: spells sharing a shield's name (the bolts Lightning Shield
-- fires) aren't casts of it. An unknown ID counts only when the client says plainly the player knows it.
local notCast = {}
local function castOf(id)
	if type(id) ~= "number" or isSecret(id) or notCast[id] then return nil end
	for _, key in ipairs(SHIELD_ORDER) do
		if SHIELDS[key].castIDs[id] then return key end
	end
	local n = Spells.nameOf(id)
	if not n then return nil end
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if n == s.name then
			local ok, mine = safe(C_SpellBook.IsSpellKnown, id)
			if not ok or isSecret(mine) then return nil end
			if mine == true then
				s.castIDs[id] = true
				return key
			end
			notCast[id] = true
			return nil
		end
	end
	notCast[id] = true
end

local function anyTrackedShieldKnown()
	for key, s in pairs(SHIELDS) do if tracksShield(key) and s.known then return true end end
	return false
end
SH.learned = anyTrackedShieldKnown
function SH.knows(key) return SHIELDS[key] ~= nil and SHIELDS[key].known == true end

local standIn
local glowSchool

-- The No shield look
-- Dead: a state driver hides it, in combat too; it shows nothing, never a false warning
local holder = CreateFrame("Frame", nil, shield)
holder:SetAllPoints(shield)
local driven = false
local function driveHolder()
	if driven or InCombatLockdown() then return end
	driven = true
	local ok, err = pcall(RegisterStateDriver, holder, "visibility", "[@player,dead] hide; show")
	if not ok then ns.noteError("shield warning holder", err) end
end
local look
local lookOn, lookState, watching = false, nil, false

-- After our own cast of a tracked shield the look stays off this long: a recast must never flash it
-- LOAD_HOLD: after a loading screen, until the client lists the auras again
local CAST_HOLD, LOAD_HOLD = 0.3, 1
local holdUntil = 0
local fighting = false

local function aurasUnread() return fighting or InCombatLockdown() or ns.aurasSecret() end

local function blocked()
	return ns.cantAct() or ns.plainYes(UnitInVehicle, "player")
end

local function stateNow()
	if not lookOn or standIn then return nil end
	if aurasUnread() then
		if GetTime() < holdUntil then return nil end
	elseif believedUp() ~= false then return nil end
	if blocked() then return ns.getDB().emptyGrey and "grey" or nil end
	return "warn"
end

-- Waits two frames each time it comes on: the sensor may be a frame behind
local function setLook(st)
	if st ~= nil and lookState == nil then look:wait() end
	lookState = st
	local db, warn = ns.getDB(), st == "warn"
	look:setParts(db.emptyGrey, warn and db.emptyTint, warn and db.emptyRing,
		warn and db.emptyPulse, warn and db.emptyGlow)
	look:want(st ~= nil)
end

local watch

-- Every frame while auras can't be read or a hold hasn't ended; otherwise events decide
local function guard(self)
	local st = stateNow()
	if st ~= lookState then setLook(st) end
	if not (aurasUnread() or GetTime() < holdUntil) then
		self:SetScript("OnUpdate", nil)
		watching = false
	end
end
function watch()
	if watching then return end
	watching = true
	holder:SetScript("OnUpdate", guard)
end
holder:SetScript("OnShow", function() setLook(stateNow()) end)

local lookEdge
local function placeLook()
	look:setLevel(shield.textFrame:GetFrameLevel() + 1)   -- over the icon, under the container
	look:reshape()
	look:style()
	lookEdge:SetFrameLevel(shield.textFrame:GetFrameLevel() + 1)
	ns.applyBorder(lookEdge, ns.borderFor("shield"))
	if lookEdge.frameOverlay then lookEdge.frameOverlay:Hide() end
end

-- Idle
-- Idle puts the gate, and with it Blizzard's button, at the Idle opacity: set out of combat, held
-- through a fight. The No shield look doesn't hang from the gate and shows in full.
local function idleWhen()
	local w = ns.elementSetting("shield", "idleWhen")
	return (w == "up" or w == "charges") and w or "never"
end
local copyReady, full
local gateNow = 1

local function applyIdle()
	if InCombatLockdown() then return end
	local when = idleWhen()
	local on = when ~= "never" and lookOn and ns.getAccount().locked
		and (when ~= "charges" or copyReady())
	gateNow = on and ns.idleAlpha("shield") or 1
	gate:SetAlpha(gateNow)
	full:SetAlpha((on and when == "charges") and 1 or 0)
end

function SH.applyEmptyLook()
	driveHolder()
	local icon = SH.icon()
	local known = anyTrackedShieldKnown()
	local covered = native.button ~= nil and not native.err
	shield.tex:SetTexture(icon)
	shield.tex:SetDesaturated(not known)
	shield.tex:SetVertexColor(1, 1, 1)
	shield.tex:SetAlpha((known and covered) and 0 or 1)
	shield:SetRingShown(false)
	shield:SetPulsing(false)
	shield:SetGlowShown(false)
	-- One border at any time: the button's while the shield is up, the look's while it's gone, the
	-- element's own until the button is made
	edge:SetShown(not (known and covered))
	look.tex:SetTexture(icon)
	local school = SH.school()
	if school ~= glowSchool then
		glowSchool = school
		look.glow:restyle()
	end
	lookOn = (known and covered and ns.isEnabled("shield")) and true or false
	if standIn then
		-- The stand-in draws the state shown over everything, at full opacity while the real shield may be
		-- up under it
		standIn:SetIgnoreParentAlpha(covered and believedUp() ~= false)
	end
	setLook(stateNow())
	watch()
	applyIdle()
end

local function setUpShield(key)
	upShield = key
	SH.applyEmptyLook()
end

local function shieldIDMap()
	local map = {}
	for key, s in pairs(SHIELDS) do
		if tracksShield(key) then
			for id in pairs(Spells.ids(s.spell)) do map[id] = true end
		end
	end
	return map
end

-- The sensor hangs from the element's frame, not the gate (which is 0 at Idle 0%)
look = ns.makeClipLook(shield, {
	key = "shield", parent = holder, sensorParent = shield, ids = shieldIDMap, owner = "shield",
	sites = {
		container = "shield warning sensor", style = "shield warning style",
		filter = "shield warning filter",
	},
})
lookEdge = CreateFrame("Frame", nil, look.art)
lookEdge:SetAllPoints(shield)
lookEdge.owner = "shield"

-- A sensor missing a tracked ID would stay empty over that shield, so the look waits
local function checkIDs() look:checkIDs() end

-- Filters only change while auras are readable
local function applyShieldFilter()
	native:refilter()
	look:refilter()
	copy:refilter()
	checkIDs()
end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if type(id) ~= "number" or isSecret(id) then return end
	s.castIDs[id] = true
	Spells.learn(s.spell, id)
	if not tracksShield(key) then return end
	-- A container not made, or failed, has nothing to refilter: it counts as matching
	local function matches(c)
		return c.container == nil or c.err ~= nil or (c.filtered and c.filtered[id])
	end
	if matches(native) and matches(look) and matches(copy) then look:checkIDs()
	else applyShieldFilter() end
end

-- Charges spent, cancelled or run out; a recast over a live shield stays silent
local WATER_COPY = 408511
function SH.applyRemovedSound()
	local ids = {}
	if ns.isEnabled("shield") then
		for id in pairs(shieldIDMap()) do ids[id] = true end
		if tracksShield("water") then ids[WATER_COPY] = true end
	end
	ns.Sounds.setAuraSound("shield", ns.elementSetting("shield", "removedSound"), ids)
end

function SH.resolve()
	local sig = {}
	wipe(notCast)
	for key, s in pairs(SHIELDS) do
		s.name = Spells.name(s.spell)
		-- A talent's spell (Water Shield) can be missing from the spellbook view
		s.spellID, s.bookIcon = Spells.known(s.spell)
		s.known = s.spellID ~= nil
		if s.spellID then learnShieldID(key, s.spellID) end
		table.insert(sig, tostring(s.spellID))
	end
	applyShieldFilter()
	SH.applyEmptyLook()
	SH.applyRemovedSound()
	return table.concat(sig, ",")
end

function SH.style()
	native:style()
	copy:style()
end

function SH.applyTimers()
	SH.style()
	look:reshape()
end

local function buildNative(slot, button, cd)
	local db = ns.getDB()
	local size = ns.sizeOf("shield")
	slot.edge = CreateFrame("Frame", nil, button)
	slot.edge:SetAllPoints(button)
	slot.edge.owner = "shield"
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
	slot.overlay = overlay

	-- Blizzard writes the count on registration: font first
	local fs = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
	ns.Media.setFont(fs, nil, db.countSize)
	SH.placeCount(fs, button)
	button:SetApplicationCount(fs)
	slot.fs = fs

	-- min 0: one charge is one third, not empty
	local bar = CreateFrame("StatusBar", nil, overlay)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(db.chargeBarHeight)
	bar:SetStatusBarTexture(ns.Media.barTexture())
	bar:SetStatusBarColor(db.chargeBarColor[1], db.chargeBarColor[2], db.chargeBarColor[3], db.chargeBarColor[4] or 1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	local maxCharges = 3
	button:SetApplicationBar(bar, { minApplications = 0, maxApplications = maxCharges })
	slot.bar = bar
	local ticks = CreateFrame("Frame", nil, overlay)
	ticks:SetAllPoints(bar)
	ticks:SetFrameLevel(bar:GetFrameLevel() + 1)
	slot.tickTextures, slot.maxCharges = {}, maxCharges
	for i = 1, maxCharges - 1 do
		local t = ticks:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.9)
		t:SetWidth(1)
		t:SetPoint("TOP", ticks, "TOPLEFT", size * i / maxCharges, 0)
		t:SetPoint("BOTTOM", ticks, "BOTTOMLEFT", size * i / maxCharges, 0)
		table.insert(slot.tickTextures, t)
	end
	slot.ticks = ticks

	bar:SetAlpha(db.showBar and 1 or 0)
	ticks:SetAlpha(db.showBar and 1 or 0)
	fs:SetAlpha(db.showCount and 1 or 0)
end

-- Without a formatter Blizzard prints a count only from 2: a numeric rule formatter is used, tried
-- on counts 0 to 3 first (an error would stop Blizzard's aura update); nil falls back to its count
local lastFormatters, made = {}, 0
local function byte(v) return math.floor(math.min(math.max(v, 0), 1) * 255 + 0.5) end
local function countOptions()
	local db = ns.getDB()
	if not (db.showCount and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local code = ""
	if db.countOne then
		local c = db.countLastColor
		code = string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
	end
	local fm = lastFormatters[code]
	if fm == nil then
		if made >= 8 then wipe(lastFormatters); made = 0 end
		made = made + 1
		local ok, f = ns.try("shield count formatter", function()
			local new = C_StringUtil.CreateNumericRuleFormatter()
			local lastFormat = code ~= "" and (code .. "%d|r") or "%d"
			new:SetBreakpoints({ { threshold = 0, format = "%d" }, { threshold = 1, format = lastFormat },
				{ threshold = 2, format = "%d" } })
			for n = 0, 3 do
				local text = new:FormatNumber(n)
				if type(text) ~= "string" or isSecret(text)
					or (n == 1 and code ~= "" and not text:lower():find(code, 1, true)) then
					error(string.format("formatted %d as %s", n, tostring(text)))
				end
			end
			return new
		end)
		fm = ok and f or false
		lastFormatters[code] = fm
	end
	return fm and { formatter = fm } or nil
end
local function applyCountFormat(slot)
	local opts = countOptions()
	local fm = opts and opts.formatter or nil
	if fm == slot.countFormatter then return end
	if ns.try("shield count", slot.button.SetApplicationCount, slot.button, slot.fs, opts) then slot.countFormatter = fm end
end

local function styleNative(slot, size)
	local db = ns.getDB()
	ns.try("shield border", ns.applyBorder, slot.edge, ns.borderFor("shield"))
	if slot.edge.frameOverlay then slot.edge.frameOverlay:Hide() end
	applyCountFormat(slot)
	for i, t in ipairs(slot.tickTextures or {}) do
		t:ClearAllPoints()
		t:SetPoint("TOP", slot.ticks, "TOPLEFT", size * i / slot.maxCharges, 0)
		t:SetPoint("BOTTOM", slot.ticks, "BOTTOMLEFT", size * i / slot.maxCharges, 0)
	end
	slot.bar:SetHeight(db.chargeBarHeight)
	slot.bar:SetStatusBarTexture(ns.Media.barTexture())
	slot.bar:SetStatusBarColor(db.chargeBarColor[1], db.chargeBarColor[2], db.chargeBarColor[3], db.chargeBarColor[4] or 1)
	slot.bar:SetAlpha(db.showBar and 1 or 0)
	slot.ticks:SetAlpha(db.showBar and 1 or 0)
	slot.fs:SetAlpha(db.showCount and 1 or 0)
	ns.Media.setFont(slot.fs, nil, db.countSize)
	SH.placeCount(slot.fs, slot.button)
	SH.applyEmptyLook()
end

-- The time bar sits on the charge bar, which is drawn over it
function SH.timeBarInset()
	local db = ns.getDB()
	return db.showBar and db.chargeBarHeight or 0
end

native = ns.makeAuraSlot(shield, {
	key = "shield", slot = "shield", ids = shieldIDMap, name = "ShamanForeverAuraContainer", parent = gate,
	sites = { container = "shield container", style = "shield style", filter = "shield filter" },
	barInset = SH.timeBarInset,
	onButton = buildNative, onStyle = styleNative,
	onError = function(err)
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", err)
	end,
})

-- "2 or more charges": the one-charge copy
-- A second aura slot whose bar and clip make the engine draw the copy at exactly one charge, in
-- combat, with nothing read. It hangs from `full`, in the group's alpha chain.
-- Frames under Blizzard's button take no scripts and may read back secret: all plain frames, placed
-- from our own values.
-- It counts (copyReady) only once made, sized and matching every tracked shield; until then the gate
-- stays full.
local IDLE_LEVEL = 8   -- levels above the shield's button and its parts
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SI = Enum and Enum.StatusBarInterpolation
local IMMEDIATE = SI and SI.Immediate or 0

full = CreateFrame("Frame", nil, shield)
full:SetAllPoints(shield)
full:SetAlpha(0)

local function placeClip(slot, button, size)
	local reach = math.ceil(ns.Looks.outerEdge(shield)) + 2
	local step = size + 2 * reach + 2
	local bar, clip = slot.sensor, slot.clip
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
	bar:SetSize(3 * step, 2)
	clip:ClearAllPoints()
	clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", -step, 0)
	clip:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", reach, -reach)
end

local function copyHost(slot, button)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, 3)
	bar:SetValue(0)
	slot.sensor = bar
	local clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	slot.clip = clip
	placeClip(slot, button, ns.sizeOf("shield"))
	slot.sensed = ns.try("shield copy sensor", button.SetApplicationBar, button, bar,
		{ minApplications = 0, maxApplications = 3, interpolation = IMMEDIATE })
	local host = CreateFrame("Frame", nil, clip)
	host:SetAllPoints(button)
	return host
end

local function styleCopy(slot, size)
	local db = ns.getDB()
	placeClip(slot, slot.button, size)
	ns.try("shield copy border", ns.applyBorder, slot.edge, ns.borderFor("shield"))
	if slot.edge.frameOverlay then slot.edge.frameOverlay:Hide() end
	local bar = slot.bar
	bar:SetHeight(db.chargeBarHeight)
	bar:SetStatusBarTexture(ns.Media.barTexture())
	local c = db.chargeBarColor
	bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	bar:SetAlpha(db.showBar and 1 or 0)
	for i, t in ipairs(slot.tickTextures) do
		t:ClearAllPoints()
		t:SetPoint("TOP", bar, "TOPLEFT", size * i / 3, 0)
		t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", size * i / 3, 0)
		t:SetAlpha(db.showBar and 1 or 0)
	end
	applyCountFormat(slot)
	ns.Media.setFont(slot.fs, nil, db.countSize)
	SH.placeCount(slot.fs, slot.host)
	slot.fs:SetAlpha(db.showCount and 1 or 0)
end

local function buildCopy(slot, button)
	slot.button = button
	local host = slot.host
	slot.edge = CreateFrame("Frame", nil, host)
	slot.edge:SetAllPoints(host)
	slot.edge.owner = "shield"
	local parts = CreateFrame("Frame", nil, host)
	parts:SetAllPoints(host)
	-- Levels under the button may read secret: a failed read leaves the default
	ns.try("shield copy level", function() parts:SetFrameLevel(slot.cd:GetFrameLevel() + 2) end)
	slot.parts = parts
	local db = ns.getDB()
	-- Font first: Blizzard writes the count as it takes the font string
	local fs = parts:CreateFontString(nil, "OVERLAY", nil, 7)
	ns.Media.setFont(fs, nil, db.countSize)
	SH.placeCount(fs, host)
	button:SetApplicationCount(fs)
	slot.fs = fs
	local bar = CreateFrame("StatusBar", nil, parts)
	bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
	bar:SetMinMaxValues(0, 3)
	bar:SetValue(1)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	slot.bar = bar
	slot.tickTextures = {}
	for i = 1, 2 do
		local t = parts:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.9)
		t:SetWidth(1)
		slot.tickTextures[i] = t
	end
	slot.built = ns.try("shield copy style", styleCopy, slot, ns.sizeOf("shield"))
	C_Timer.After(0, SH.applyEmptyLook)
end

copy = ns.makeAuraSlot(shield, {
	key = "shield", slot = "shieldcopy", ids = shieldIDMap, parent = full, level = IDLE_LEVEL,
	host = copyHost, barInset = SH.timeBarInset,
	sites = { container = "shield copy container", style = "shield copy style",
		filter = "shield copy filter" },
	onButton = function(slot, button) buildCopy(slot, button) end,
	onStyle = function(slot, size)
		styleCopy(slot, size)
		SH.applyEmptyLook()
	end,
	onError = function(err) ns.noteError("shield copy container", err) end,
})

-- While a restyle for a new Size is queued the answer stays: a dragged Size slider mustn't flicker the gate
local readyLast = false
copyReady = function()
	local ready = copy.built and copy.sensed and copy.size == ns.sizeOf("shield") and copy.filtered ~= nil
	if not ready and copy.built and copy.sensed and copy.size and copy.filtered and copy.styleSoon then
		ready = readyLast
	end
	if ready then
		for id in pairs(shieldIDMap()) do
			if not copy.filtered[id] then ready = false break end
		end
	end
	readyLast = ready and true or false
	return readyLast
end

local baseRefilter = copy.refilter
function copy:refilter()
	baseRefilter(self)
	if self.filtered then C_Timer.After(0, SH.applyEmptyLook) end
end

-- Auras can be secret out of combat too: keep the last read
local function aurasReadable() return not InCombatLockdown() and not ns.aurasSecret() end

local function refreshAura()
	if not aurasReadable() then return end
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
	if upKey then ns.getAccount().lastShield = upKey end
	setUpShield(upKey or "none")
end

function SH.onCast(spellID)
	local cast = castOf(spellID)
	if not cast then return end
	ns.getAccount().lastShield = cast
	if tracksShield(cast) then
		holdUntil = GetTime() + CAST_HOLD
		watch()
	end
	learnShieldID(cast, spellID)
	SH.applyEmptyLook()
end

-- The GCD gets its own sweep above the button (Blizzard's button owns the shield's time left)
local shieldGCD = ns.makeGCDSweep(shield)
shieldGCD:SetParent(gate)
-- inCooldownEvent: from SPELL_UPDATE_COOLDOWN
local function refreshGCD(inCooldownEvent)
	local id = ns.isEnabled("shield") and ns.Style.value("shield", "gcd", "show")
		and Spells.known(SHIELDS[shownShield()].spell)
	local d
	if id and ns.Cooldowns.onGCD(id) then
		local ok, dur = safe(C_Spell.GetSpellCooldownDuration, id)
		d = ok and dur or nil
	end
	if not d then
		if inCooldownEvent or not id then shieldGCD:Clear() end
		return
	end
	shieldGCD:SetFrameLevel((native.container or shield.textFrame):GetFrameLevel() + 20)
	shieldGCD:SetCooldownFromDurationObject(d)
end

function SH.applyLayout()
	native:setup()
	look:setup()
	if idleWhen() == "charges" and ns.isEnabled("shield") then copy:setup() end
	if native.container and not native.filtered then native:refilter() end
	if copy.container and not copy.filtered then copy:refilter() end
	SH.style()
	SH.applyEmptyLook()
end
function SH.afterGroups()
	SH.style()
	placeLook()
	SH.applyEmptyLook()
end
function SH.refresh()
	if native.container and not native.filtered then native:refilter() end
	if copy.container and not copy.filtered then copy:refilter() end
	checkIDs()
	refreshAura()
	refreshGCD(false)
	SH.applyRemovedSound()
end
SH.onCooldowns = refreshGCD
function SH.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "PLAYER_REGEN_DISABLED")
	ns.registerEvent(ev, "PLAYER_REGEN_ENABLED")
	ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
	ns.registerEvent(ev, "UNIT_ENTERED_VEHICLE", "player")
	ns.registerEvent(ev, "UNIT_EXITED_VEHICLE", "player")
	-- Auras may turn secret out of combat: the button becomes the switch
	ns.registerEvent(ev, "ADDON_RESTRICTION_STATE_CHANGED")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			holdUntil = math.max(holdUntil, GetTime() + LOAD_HOLD)
			watch()
			return
		elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
			watch()
			return
		elseif event == "PLAYER_REGEN_DISABLED" then
			fighting = true
			checkIDs()
		elseif event == "PLAYER_REGEN_ENABLED" then
			fighting = false
			refreshAura()
		elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
			watch()
		else
			refreshAura()
			return
		end
		SH.applyEmptyLook()
	end)
	ns.onCanActChange(SH.applyEmptyLook)
end

-- /sf debug
function SH.debug()
	local up = believedUp()
	say("shield tracking %s (last %s), up at the last read %s (shield up %s)", ns.getDB().shieldTrack,
		ns.getAccount().lastShield, up == nil and "unknown" or tostring(up), tostring(upShield))
	say("no-shield look: %s, %s, state %s; button %s, cast hold %s", lookOn and "on" or "off",
		aurasUnread() and "sensor decides" or "read decides too", tostring(lookState),
		native.button and "made" or "not made", GetTime() < holdUntil and "on" or "off")
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		local e = Spells.bookEntry(s.spell)
		say("%s: %s, spell %s rank %s", s.name, s.known and "known" or "not known", tostring(s.spellID), e and e.rank or "?")
	end
	say("aura container %s%s", native.container and "created" or "not created",
		native.err and (", error: " .. native.err) or "")
	say("no-shield sensor: %s", look:describe())
	say("idle %s at %.2f, gate %.2f; one-charge copy %s%s, button %s, sensor %s, counts %s",
		idleWhen(), ns.idleAlpha("shield"), gateNow, copy.container and "made" or "not made",
		copy.err and (" (error: " .. copy.err .. ")") or "", copy.built and "built" or "not made",
		tostring(copy.sensed), tostring(copyReady()))
	local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
	say("tracked spell IDs: %s", table.concat(t, ","))
end

-- Preview: Blizzard's button can't be shown or hidden by addon code, so a stand-in draws over it
shield.aboveProtected = true
function SH.preview(icon)
	standIn = icon
	SH.applyEmptyLook()
end

ns.registerModule(SH)
