-- Shields (Lightning or Water): Blizzard's aura button shows the shield; our No shield look shows
-- exactly while it's gone
--
-- The two shields exclude each other, so one aura slot matches every shield the player tracks
-- (db.shieldTrack) and Blizzard shows whichever is up, switching exactly when the player swaps
-- mid-fight. Both have 3 charges, so one charge bar fits both.
--
-- 1. Blizzard's CustomAuraContainer draws the shield: icon, charge count, charge bar, and its time
--    as a swipe, countdown or bar. Its untainted code reads the aura, so all of this is exact in
--    combat, and its button hides the moment the shield goes, in combat too. It takes its group's
--    opacity like any icon.
-- 2. The No shield look (grey, the red tint, fade in and out, the red ring and the pulsing glow) is
--    a clip look (ns.makeClipLook): drawn by the engine only while no shield it tracks is up, in
--    combat too, with nothing read. Nothing tells addon code in combat when the shield goes (reads
--    by index or instance throw, reads by spell come back empty, UNIT_AURA brings nothing readable,
--    script handlers under the button never run; tested 2026-09-23), so:
--    - checked every frame while auras can't be read (plain reads, and writes to our own frames
--      only, allowed in combat), the look is off while it can't be trusted: the button not made,
--      preview mode, and a moment after our own cast of a shield it tracks (a recast must never
--      flash it) or a loading screen; its sensor adds its own waits (a new spell ID, size or look
--      it can't take until combat ends, and two frames each time it shows). While you can't act
--      (a flight path, a vehicle) it shows the grey alone, without the warning, or nothing without
--      Grey icon; while you're dead a state driver on its holder hides it, in combat too;
--    - out of combat, auras readable, it also follows a read of the aura (refreshAura): shown only
--      while no shield it tracks is up. In a PvP match auras stay secret out of combat too
--      (Blizzard's API documentation; not yet seen in a battleground): the sensor alone decides
--      until it ends.
-- 3. After a login or /reload in combat or in a PvP match the button is made only once auras are
--    readable; until then Shields shows its plain icon: a miss, never a false warning.
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule).

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

local SH = { name = "shield" }
ns.Shield = SH

-- Elemental shields. Only one can be on the shaman at a time (Water Shield's tooltip says so), so one
-- element shows whichever is up. Water Shield is a Restoration talent on Forever; 408510 is both its
-- cast and its buff (wowhead.com/forever). Spells by key in ns.Spells (ShamanForever_Core.lua); the
-- IDs the aura slot matches grow with the spellbook's and the live aura's.
local SHIELDS = {
	lightning = { spell = "lightningShield", icon = 136051 },
	water     = { spell = "waterShield",     icon = 132315 },
}
local SHIELD_ORDER = { "lightning", "water" }

local shield = ns.newElementIcon("shield")   -- its icon: the plain one, while the button isn't made
-- What Blizzard's container hangs from: the button's own opacity, under its group's. Its alpha
-- changes only out of combat (an ancestor of the button takes no alpha change in combat); the No
-- shield look doesn't hang from it.
local gate = CreateFrame("Frame", nil, shield)
gate:SetAllPoints(shield)
ns.registerElement("shield", { frame = shield, label = "Shields", paint = function(t) t:SetTexture(SH.icon()) end,
	learned = function() return SH.learned() end,
	kind = "shield", icon = 136051, school = "spirit", blurb = "Charges and time left. Warns when it's gone." })

-- Per shield at runtime: name (the client's), spellID and bookIcon (highest known rank), known. The
-- IDs that count as it are ns.Spells' (seeds, spellbook, and the live aura's, learned here); castIDs
-- the ones that count as a cast of it (castOf, below).
for _, s in pairs(SHIELDS) do
	s.name = Spells.name(s.spell)
	s.castIDs = {}
	for _, id in ipairs(Spells.DEFS[s.spell].ids) do s.castIDs[id] = true end
end
-- The shield up (lightning | water), "none", or nil until known: the last read, while auras were
-- readable. Kept as which shield, not as "a tracked one is up", so a new Track is judged at once.
local upShield
local native   -- Blizzard's aura container, and our parts on its button (below)

local function tracksShield(key)
	local track = ns.getDB().shieldTrack
	return track == "either" or track == key
end
-- Whether a shield the player tracks was up at the last read: nil while not known.
local function believedUp()
	if upShield == nil then return nil end
	return upShield ~= "none" and tracksShield(upShield)
end

-- The charge number's offset from its point (ns.COUNT_JUSTIFY has the points): in a corner it is
-- nudged 2 px outward.
local COUNT_NUDGE = { CENTER = { 0, 0 }, TOPLEFT = { -2, 2 }, TOPRIGHT = { 2, 2 }, BOTTOMLEFT = { -2, -2 },
	BOTTOMRIGHT = { 2, -2 } }
-- 0.8.0 and earlier saved "center" or "corner" (the bottom right).
local COUNT_POS_SAVED = { center = "CENTER", corner = "BOTTOMRIGHT" }

-- Places the charge number fs on icon, as the settings say (the HUD's and the options' preview).
function SH.placeCount(fs, icon)
	local pos = ns.getDB().countPos
	local nudge = COUNT_NUDGE[pos]
	fs:ClearAllPoints()
	fs:SetPoint(pos, icon, pos, nudge[1], nudge[2])
	fs:SetJustifyH(ns.COUNT_JUSTIFY[pos])
end

-- A profile's shield settings, and the account's last shield, made valid (when a profile loads).
function SH.sanitize(db, acct)
	if db.shieldTrack ~= "either" and not SHIELDS[db.shieldTrack] then db.shieldTrack = "lightning" end
	db.countPos = COUNT_POS_SAVED[db.countPos] or db.countPos
	if not ns.COUNT_JUSTIFY[db.countPos] then db.countPos = "CENTER" end
	if not SHIELDS[acct.lastShield] then acct.lastShield = "lightning" end
	if not ns.isColor(db.countLastColor) then db.countLastColor = CopyTable(ns.DEFAULTS.countLastColor) end
end

-- Which shield the no-shield look shows: the tracked one, or in "either" mode the one last cast or
-- seen, falling back to one the player actually knows.
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

-- The shield an own cast is a cast of, if any: by its own spell IDs (its seeds, the ranks the
-- player knows, the live aura's), never by name alone. Spells that share a shield's name without
-- being its cast, such as the bolts Lightning Shield fires as it loses a charge (build 70009 has
-- more than twenty spells of that name), must not count as a new shield. An ID not on record counts
-- only when it has the shield's name and the client says plainly that the player knows it (a rank
-- not seen yet), which a triggered effect is not. A no is kept until the next spellbook scan.
local notCast = {}
local function castOf(id)
	if type(id) ~= "number" or isSecret(id) or notCast[id] then return nil end
	for _, key in ipairs(SHIELD_ORDER) do
		if SHIELDS[key].castIDs[id] then return key end
	end
	local n = Spells.nameOf(id)
	if not n then return nil end   -- a name can come late on a cold start: asked again next time
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		if n == s.name then
			local ok, mine = safe(C_SpellBook.IsSpellKnown, id)
			if not ok or isSecret(mine) then return nil end   -- no answer: asked again next time
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
-- The element's learned() (ns.registerElement): a shield it tracks (its Track setting) is known.
SH.learned = anyTrackedShieldKnown
-- Whether the character knows a shield (lightning | water), tracked or not (the options).
function SH.knows(key) return SHIELDS[key] ~= nil and SHIELDS[key].known == true end

local standIn   -- preview mode's icon over the shield (SH.preview, below)

------------------------------------------------------------------------
-- The No shield look (see the top of this file)
------------------------------------------------------------------------
-- Its holder, over the element's own icon; its guard runs here. A state driver hides it while
-- you're dead, so the engine backs the guard up in combat (the guard only checks once a frame). It
-- wins over the grey-only look: dead shows nothing, a miss, never a false warning.
local holder = CreateFrame("Frame", nil, shield)
holder:SetAllPoints(shield)
local driven = false
local function driveHolder()
	if driven or InCombatLockdown() then return end
	driven = true
	local ok, err = pcall(RegisterStateDriver, holder, "visibility", "[@player,dead] hide; show")
	if not ok then ns.noteError("shield warning holder", err) end
end
local look   -- the clip look (below)
local lookOn, lookState, watching = false, nil, false

-- After our own cast of a shield it tracks, the look stays off this long (seconds). Blizzard
-- handles a recast in one aura update (the old aura's removal and the new one's arrival refresh the
-- slot once), so the sensor shouldn't empty for a frame; this keeps a recast from ever flashing the
-- warning if a removal and an arrival come apart. A shield just cast can't be gone this soon.
-- LOAD_HOLD: after a loading screen, while the client lists the player's auras again.
local CAST_HOLD, LOAD_HOLD = 0.3, 1
local holdUntil = 0
local fighting = false   -- from PLAYER_REGEN_DISABLED (before lockdown) to PLAYER_REGEN_ENABLED

-- In combat, or auras secret out of combat: the sensor alone decides. Else the read does too.
local function aurasUnread() return fighting or InCombatLockdown() or ns.aurasSecret() end

-- The player can't act on a warning: dead, a ghost, a flight path, a vehicle.
local function blocked()
	return ns.cantAct() or ns.plainYes(UnitInVehicle, "player")
end

-- What the look shows now: "warn" (the No shield look), "grey" (the grey alone: you can't act), or
-- nil (nothing).
local function stateNow()
	if not lookOn or standIn then return nil end
	if aurasUnread() then
		if GetTime() < holdUntil then return nil end
	elseif believedUp() ~= false then return nil end
	if blocked() then return ns.getDB().emptyGrey and "grey" or nil end
	return "warn"
end

-- Shows the look in state st (stateNow), or not. It waits two frames each time it comes on, as it
-- does each time it shows (ns.makeClipLook): the sensor may be a frame behind.
local function setLook(st)
	if st ~= nil and lookState == nil then look:wait() end
	lookState = st
	local db, warn = ns.getDB(), st == "warn"
	look:setParts(db.emptyGrey, warn and db.emptyTint, warn and db.emptyRing,
		warn and db.emptyPulse, warn and db.emptyGlow)
	look:want(st ~= nil)
end

local watch   -- below

-- Every frame while auras can't be read or a hold hasn't ended: the state now. It changes the frame
-- a read goes the other way (dead, a flight path, our cast), so it never waits for an event. Out of
-- combat, with auras readable, the events that change the read or the settings decide
-- (SH.applyEmptyLook), and it stops.
local function guard(self)
	local st = stateNow()
	if st ~= lookState then setLook(st) end
	if not (aurasUnread() or GetTime() < holdUntil) then
		self:SetScript("OnUpdate", nil)
		watching = false
	end
end
-- Starts the guard, if it isn't running (it stops itself once nothing needs it).
function watch()
	if watching then return end
	watching = true
	holder:SetScript("OnUpdate", guard)
end
-- Its group or the element was hidden: the state may have changed meanwhile.
holder:SetScript("OnShow", function() setLook(stateNow()) end)

-- The look's levels, shape and size, after a layout (a size, scale or look change).
local function placeLook()
	look:setLevel(shield.textFrame:GetFrameLevel() + 1)   -- over the icon, under the container (+5)
	look:reshape()
	look:style()
end

-- The shield's looks, from its settings and state: the element's own icon (only seen while the
-- button isn't made), the No shield look and, in preview mode, the stand-in.
function SH.applyEmptyLook()
	driveHolder()
	local icon = SH.icon()
	local known = anyTrackedShieldKnown()
	local covered = native.button ~= nil and not native.err
	-- The icon: grey while not learned (as for cooldowns); the plain icon while Blizzard's button
	-- isn't made (a /reload in combat, until auras are readable); under the button, nothing.
	shield.tex:SetTexture(icon)
	shield.tex:SetDesaturated(not known)
	shield.tex:SetVertexColor(1, 1, 1)
	shield.tex:SetAlpha((known and covered) and 0 or 1)
	shield:SetRingShown(false)
	shield:SetPulsing(false)
	shield:SetGlowShown(false)
	-- One border at any time. The element's frame draws the border's lines and sliced art round the
	-- icon, once, always. The border look's inner art (over the icon) is drawn by the aura button
	-- while the shield is up and by the No shield look while it's gone (ns.makeClipLook), each
	-- exactly with what it belongs to, so the frame's own copy stays down while those are made: the
	-- button is see-through at partial opacity, and a copy under it would show as a second one.
	if shield.frameOverlay then shield.frameOverlay:SetShown(not (known and covered)) end
	look.tex:SetTexture(icon)
	lookOn = (known and covered and ns.isEnabled("shield")) and true or false
	if standIn then
		-- Preview mode (SH.preview, below). The stand-in draws the state shown over everything, the
		-- look off: at its group's opacity, as Blizzard's button draws the shield, but at full
		-- while the real shield may be up under it, which would show through.
		standIn:SetIgnoreParentAlpha(covered and believedUp() ~= false)
	end
	setLook(stateNow())
	watch()
end

local function setUpShield(key)
	upShield = key
	SH.applyEmptyLook()
end

-- Every spell ID of every tracked shield: what Blizzard's aura slot matches.
local function shieldIDMap()
	local map = {}
	for key, s in pairs(SHIELDS) do
		if tracksShield(key) then
			for id in pairs(Spells.ids(s.spell)) do map[id] = true end
		end
	end
	return map
end

-- The No shield look, its glow in its Glow look and the shield's Pulsing glow style, past the
-- icon's edge if the look reaches there. Its sensor hangs beside Blizzard's container. The glow's
-- look before the profile loads (it is made at load): the default.
look = ns.makeClipLook(shield, {
	key = "shield", parent = holder, sensorParent = gate, ids = shieldIDMap, owner = "shield",
	lookFor = function()
		local db = ns.getDB()
		return db and db.emptyGlowLook or nil
	end,
	sites = {
		container = "shield warning sensor", style = "shield warning style",
		filter = "shield warning filter",
	},
})

-- Whether the sensor matches every spell ID of every tracked shield: a sensor missing one would
-- stay empty over that shield, so the look waits (ns.makeClipLook). Matching more (a Track just
-- narrowed) only keeps it empty over a shield that no longer counts: a miss, not a false warning.
local function checkIDs() look:checkIDs() end

-- The filters can only change while auras are readable; a change meanwhile waits for that
-- (ns.makeAuraSlot, ns.makeClipLook).
local function applyShieldFilter()
	native:refilter()
	look:refilter()
	checkIDs()   -- a refilter that waits leaves the look waiting too
end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if type(id) ~= "number" or isSecret(id) then return end
	s.castIDs[id] = true
	Spells.learn(s.spell, id)
	if not tracksShield(key) then return end
	-- A container that isn't made, or failed, has nothing to refilter: it counts as matching, so an
	-- aura read doesn't ask again for ever.
	local function matches(c)
		return c.container == nil or c.err ~= nil or (c.filtered and c.filtered[id])
	end
	if matches(native) and matches(look) then look:checkIDs() else applyShieldFilter() end
end

-- After a spellbook scan (ns.resolveSpells): each shield's name, highest known rank and icon, and the
-- slot's filter to match. Returns a signature of what it found.
function SH.resolve()
	local sig = {}
	wipe(notCast)   -- names and known spells may have changed
	for key, s in pairs(SHIELDS) do
		s.name = Spells.name(s.spell)
		-- The highest rank known, read as every element reads it: the spellbook's, else the client's
		-- answer (a talent's spell, such as Water Shield, can be missing from the spellbook view).
		s.spellID, s.bookIcon = Spells.known(s.spell)
		s.known = s.spellID ~= nil
		if s.spellID then learnShieldID(key, s.spellID) end
		table.insert(sig, tostring(s.spellID))
	end
	applyShieldFilter()   -- the tracked shields may have changed
	SH.applyEmptyLook()   -- and with them whether the shield up counts
	return table.concat(sig, ",")
end

-- Blizzard's button and its parts are off limits to addon code in combat, and while auras are
-- secret: the aura slot's restyle waits until that ends (ns.makeAuraSlot).
function SH.style() native:style() end

-- The shield's timer takes its current style (ns.applyTimers). It sits on Blizzard's button, so it
-- comes with the button's restyle, which waits for combat to end. The No shield look's glow (its
-- new look or style) follows at once: our own frames (the options call this after a timer or glow
-- style change).
function SH.applyTimers()
	SH.style()
	look:reshape()
end

-- Our parts on Blizzard's button, once it is made: the charge number and the charge bar with its
-- ticks, on an overlay above the cooldown so nothing Blizzard hides takes them along.
local function buildNative(slot, button, cd)
	local db = ns.getDB()
	local size = ns.sizeOf("shield")
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
	slot.overlay = overlay

	-- Blizzard writes the count immediately on registration, so the font must already be set.
	local fs = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
	ns.Media.setFont(fs, nil, db.countSize)
	SH.placeCount(fs, button)
	button:SetApplicationCount(fs)
	slot.fs = fs

	-- Charge bar along the bottom edge: min 0 so one charge is one third, not empty.
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

-- The charge number's last charge. Without a formatter Blizzard prints a count only from 2, so a
-- numeric rule formatter is always used once Charge number is on: one rule per count, the last one
-- wrapped in a colour code only when Different colour last charge is on (Blizzard_CustomAuraButton.lua;
-- ShamanPower does the same on Forever). Blizzard formats inside the button's aura update, where an
-- error would stop the rest of it, so it is tried on the counts 0 to 3 first (out of combat, in the
-- slot's restyle) and only handed over once it gives a string for each; nil falls back to Blizzard's
-- own count (hides the 1). One formatter per colour (plus the plain one), made on first use. The few
-- kept are dropped while a colour is being dragged through many (the button keeps the one it was given).
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
-- Hands the count its formatter again when that changed. Blizzard's own count (the tested path) is
-- never registered again until a formatter has been given.
local function applyCountFormat(slot)
	local opts = countOptions()
	local fm = opts and opts.formatter or nil
	if fm == slot.countFormatter then return end
	if ns.try("shield count", slot.button.SetApplicationCount, slot.button, slot.fs, opts) then slot.countFormatter = fm end
end

-- Our parts again, for the current size and settings (after the aura slot's own restyle).
local function styleNative(slot, size)
	local db = ns.getDB()
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
	SH.applyEmptyLook()   -- the button may be new
end

-- The time bar on the bottom edge sits on the charge bar, which is drawn over it (the options'
-- preview too).
function SH.timeBarInset()
	local db = ns.getDB()
	return db.showBar and db.chargeBarHeight or 0
end

-- Made only while auras are readable (after a /reload in combat or a PvP match, when that ends);
-- once made, it stays.
native = ns.makeAuraSlot(shield, {
	key = "shield", slot = "shield", ids = shieldIDMap, name = "ShamanForeverAuraContainer", parent = gate,
	sites = { container = "shield container", style = "shield style", filter = "shield filter" },
	barInset = SH.timeBarInset,
	onButton = buildNative, onStyle = styleNative,
	onError = function(err)
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", err)
	end,
})

-- Auras can be secret out of combat too (PvP matches, encounters): then keep the last read.
local function aurasReadable() return not InCombatLockdown() and not ns.aurasSecret() end

-- While auras are readable: which shield is up, and the live spell IDs. Looked up by the client's
-- name for the shield, which every rank shares.
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

-- Our own successful cast (UNIT_SPELLCAST_SUCCEEDED, spellID not secret): the shield the look shows
-- in Either, the cast hold (CAST_HOLD), and a rank the filters don't match yet, which they take
-- once combat ends (the look waits meanwhile: checkIDs).
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

-- The global cooldown on the shield, when its Global cooldown style is on. The shield's time left
-- is Blizzard's aura button's own cooldown, so the GCD gets its own sweep, above that button (it
-- darkens the charges too, for the GCD's length). Timed by the shown shield's spell, while that is on
-- the GCD (read in SPELL_UPDATE_COOLDOWN, as the timers are).
local shieldGCD = ns.makeGCDSweep(shield)
-- inCooldownEvent: called from SPELL_UPDATE_COOLDOWN, the only place isOnGCD is vouched for.
local function refreshGCD(inCooldownEvent)
	local id = ns.isEnabled("shield") and ns.Style.value("shield", "gcd", "show")
		and Spells.known(SHIELDS[shownShield()].spell)
	local d
	if id and ns.Cooldowns.onGCD(id) then
		local ok, dur = safe(C_Spell.GetSpellCooldownDuration, id)
		d = ok and dur or nil
	end
	if not d then
		-- Elsewhere a running sweep stays (it ends on its own), unless the sweep is off.
		if inCooldownEvent or not id then shieldGCD:Clear() end
		return
	end
	-- Above Blizzard's button, wherever regrouping left the container.
	shieldGCD:SetFrameLevel((native.container or shield.textFrame):GetFrameLevel() + 10)
	shieldGCD:SetCooldownFromDurationObject(d)
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
-- After a layout (settings may have changed): Blizzard's container made once, then its looks.
function SH.applyLayout()
	native:setup()
	look:setup()
	-- The IDs the slot was made with: given again, so the slot records them.
	if native.container and not native.filtered then native:refilter() end
	SH.style()
	SH.applyEmptyLook()
end
-- The button's restyle and the look's place for a new size, scale or look.
function SH.afterGroups()
	SH.style()
	placeLook()
	SH.applyEmptyLook()
end
function SH.refresh()
	if native.container and not native.filtered then native:refilter() end
	checkIDs()
	refreshAura()
	refreshGCD(false)
end
SH.onCooldowns = refreshGCD
-- A shaman logged in: the aura, read again whenever it changes (while auras are readable).
function SH.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ns.registerEvent(ev, "PLAYER_REGEN_DISABLED")
	ns.registerEvent(ev, "PLAYER_REGEN_ENABLED")
	ns.registerEvent(ev, "PLAYER_ENTERING_WORLD")
	-- A vehicle turns the look to the grey alone, or back (blocked).
	ns.registerEvent(ev, "UNIT_ENTERED_VEHICLE", "player")
	ns.registerEvent(ev, "UNIT_EXITED_VEHICLE", "player")
	-- Auras may turn secret out of combat (a PvP match, an encounter): the button becomes the switch.
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
			watch()   -- the look re-evaluated below
		else
			refreshAura()
			return
		end
		SH.applyEmptyLook()
	end)
	ns.onCanActChange(SH.applyEmptyLook)   -- death, resurrection, a flight path
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
	local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
	say("tracked spell IDs: %s", table.concat(t, ","))
end

------------------------------------------------------------------------
-- Preview mode (ShamanForever_Preview.lua) shows the shield up or down. Blizzard's button can't be
-- shown, hidden or faked by addon code, so the preview draws a stand-in over it, and the No shield
-- look is off meanwhile (SH.applyEmptyLook sets the stand-in's opacity). Only our own frames
-- change; the element's frame itself is never hidden (ns.fadeTo).
------------------------------------------------------------------------
shield.aboveProtected = true   -- Blizzard's button hangs from it
-- icon: the preview's stand-in, just drawn in a state; nil when the preview ends.
function SH.preview(icon)
	standIn = icon
	SH.applyEmptyLook()
end

ns.registerModule(SH)
