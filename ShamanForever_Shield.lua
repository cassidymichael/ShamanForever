-- Shields (Lightning or Water): Blizzard's aura button shows the shield; under it, our No shield look
--
-- The two shields exclude each other, so one aura slot matches every shield the player tracks
-- (db.shieldTrack) and Blizzard shows whichever is up, switching exactly when the player swaps
-- mid-fight. Both have 3 charges, so one charge bar fits both.
--
-- 1. Blizzard's CustomAuraContainer draws the shield: icon, charge count, charge bar, and its time
--    as a swipe, countdown or bar. Its untainted code reads the aura, so all of this is exact in
--    combat, and its button hides the moment the shield goes, in combat too.
-- 2. Under the button sits the underlay, the No shield look: grey, the red tint, fade in and out,
--    the red ring and a pulsing glow. Nothing tells addon code in combat when the button hides
--    (reads by index or instance throw, reads by spell come back empty, UNIT_AURA brings nothing
--    readable, script handlers under the button never run; tested 2026-09-23). So in combat the
--    button itself is the switch: its opaque icon covers the underlay while the shield is up, and
--    the underlay shows the moment it goes, drawn by the engine with nothing read or inferred. So:
--    - the cover must be opaque: the container hangs from a gate that ignores the group's opacity
--      (the shield draws at full), and the underlay takes the group's opacity itself;
--    - only looks inside the icon: grey, tint, fade, the ring, and a glow in a look drawn inside it
--      (Soft inner or School material), a screen pixel in from the icon's edges and in a rounded or
--      cut-corner look's shape, so the button's icon covers every pixel of them;
--    - checked every frame (plain reads, and writes to our own frames only, allowed in combat), it
--      hides while it can't be trusted: the button not made, a new spell ID or look the button
--      can't take until combat ends, preview mode, and a moment after our own cast of a shield it
--      tracks (a recast must never flash it) or a loading screen. While you can't act (dead, a
--      ghost, a flight path, a vehicle) it shows the grey alone, without the warning, or nothing
--      without Grey icon;
--    - Blizzard's container catches up with the aura on its next frame after it shows, so the
--      underlay waits two frames each time it shows.
--    Out of combat, auras readable, the underlay follows a read of the aura instead (refreshAura):
--    shown only while no shield it tracks is up. So nothing lies under a live shield between fights,
--    when its group fades out after combat, or across a loading screen. In a PvP match auras stay
--    secret out of combat too (Blizzard's API documentation; not yet seen in a battleground): the
--    button is the switch until it ends.
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

local shield = ns.newElementIcon("shield")   -- its icon: the plain one, while nothing covers it
-- What Blizzard's container hangs from: at full opacity whatever its group's, so the button's icon
-- covers the underlay completely (the underlay takes the group's opacity itself, below).
local gate = CreateFrame("Frame", nil, shield)
gate:SetAllPoints(shield)
gate:SetIgnoreParentAlpha(true)
ns.registerElement("shield", { frame = shield, label = "Shields", paint = function(t) t:SetTexture(SH.icon()) end,
	learned = function() return SH.learned() end,
	fadeFrames = { gate },   -- it ignores the group's alpha
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
local native   -- Blizzard's aura container over the underlay, and our parts on its button (below)

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
local function underlayShield()
	local track, last = ns.getDB().shieldTrack, ns.getAccount().lastShield
	if SHIELDS[track] then return track end
	if SHIELDS[last] and SHIELDS[last].known then return last end
	for _, key in ipairs(SHIELD_ORDER) do if SHIELDS[key].known then return key end end
	return "lightning"
end
function SH.icon()
	local s = SHIELDS[underlayShield()]
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

local standIn, standInState   -- preview mode's icon over the shield and its state (SH.preview, below)

------------------------------------------------------------------------
-- The underlay (see the top of this file)
------------------------------------------------------------------------
-- Over the element's own icon, under Blizzard's container (styleNative sets both levels).
local under = CreateFrame("Frame", nil, gate)
under:SetAllPoints(shield)
under:SetAlpha(0)
under.inner = CreateFrame("Frame", nil, under)   -- the wait's alpha (appear), apart from under's own
under.inner:SetAllPoints()
under.tex = under.inner:CreateTexture(nil, "ARTWORK")
ns.cropIconExact(under.tex)
under.tex:SetPoint("TOPLEFT", shield, "TOPLEFT", 0, 0)   -- placed with the button (placeUnder)
under.tex:SetSize(1, 1)
under.ring = ns.makeRing(under.inner, under.tex)   -- inside the inset picture
-- Every texture under frame in the icon's shape, over the inset picture. Masks are textures too,
-- but take no mask themselves (a look's own masks live there).
local function shapeTextures(frame)
	for _, r in ipairs({ frame:GetRegions() }) do
		if r:IsObjectType("Texture") and not r:IsObjectType("MaskTexture") then
			ns.Looks.maskOver(shield, r, under.tex)
		end
	end
	for _, c in ipairs({ frame:GetChildren() }) do shapeTextures(c) end
end
-- Its pulsing glow: its own look (No shield's Glow look), one drawn inside the icon only, over the
-- inset picture, in the Pulsing glow style's colour and speed. Its look before the profile loads
-- (the glow is made at load): the default.
under.tex.owner = "shield"   -- its looks take their school from what they cover: the element's
under.glow = ns.makeInsideGlow(under.inner, under.tex, "shield", function()
	local db = ns.getDB()
	return db and db.emptyGlowLook or nil
end)
-- Its textures take the shape as they're made and each time they're fitted, in combat too (a look
-- changed with the options open): never a square corner past the button.
under.glow.onLayout = function(_, parts)
	for _, r in ipairs(parts.roots or {}) do shapeTextures(r) end
end
for _, parts in pairs(under.glow.parts) do if parts then under.glow.onLayout(under.glow, parts) end end
under.pulse = ns.makePulse(under.tex, "fade")

-- After our own cast of a shield it tracks, the underlay stays hidden this long (seconds). Blizzard
-- handles a recast in one aura update (the old aura's removal and the new one's arrival refresh the
-- slot once), so the button shouldn't hide for a frame; this keeps a recast from ever flashing the
-- warning if a removal and an arrival come apart. A shield just cast can't be gone this soon.
-- LOAD_HOLD: after a loading screen, while the client lists the player's auras again.
local CAST_HOLD, LOAD_HOLD = 0.3, 1
local holdUntil = 0
local fighting = false   -- from PLAYER_REGEN_DISABLED (before lockdown) to PLAYER_REGEN_ENABLED

-- In combat, or auras secret out of combat: the button is the switch. Else the read is.
local function covering() return fighting or InCombatLockdown() or ns.aurasSecret() end

-- The player can't act on a warning: dead, a ghost, a flight path, a vehicle.
local function blocked()
	return ns.cantAct() or ns.plainYes(UnitInVehicle, "player")
end

-- Whether the button's icon covers the underlay's shape: square (it covers any), or in the same
-- rounded or cut-corner shape as the icon's look now, which the underlay follows at once (a new
-- look waits for combat's end on the button).
local function shapeCovers()
	local shape = ns.Looks.auraShape(native.icon)
	return shape == nil or shape == ns.Looks.maskSpec(shield)
end

-- While the button is the switch: whether it can be trusted to cover the underlay exactly. Its
-- slot matches every spell ID the shields it tracks have now (a new rank or Track waits for
-- combat's end there), it has the size the underlay was placed for (a new size waits too) and a
-- shape that covers it, its gate is at full opacity and not fading out with its group after combat
-- (where auras stay secret out of combat, the button would be see-through meanwhile), and our own
-- shield cast or a loading screen isn't a moment ago.
local function coverTrusted()
	return native.idsOK and under.size == native.size and shapeCovers() and gate:GetAlpha() > 0.99
		and not ns.AfterCombat.fading(gate) and GetTime() >= holdUntil
end

-- What the underlay shows now: "warn" (the No shield look), "grey" (the grey alone: you can't act),
-- or nil (hidden).
local function underState()
	if not under.on or standIn then return nil end
	if covering() then
		if not coverTrusted() then return nil end
	elseif believedUp() ~= false then return nil end
	if blocked() then return ns.getDB().emptyGrey and "grey" or nil end
	return "warn"
end

local watch   -- below

-- The wait: hidden now, and back on its second OnUpdate from here. Blizzard's container updates in
-- its own next OnUpdate after a change (or after it shows), in this frame's pass or the next one's;
-- ours comes back a pass after that, so before the frame drawn after the container's update, never
-- the one before. Our own frame: allowed in combat.
local function appear()
	under.inner:SetAlpha(0)
	under.hold = 2
	watch()
end

-- The underlay's looks for its state: the full No shield look, or the grey alone. Our own frames
-- and textures (not under Blizzard's button): allowed in combat.
local function lookUnder()
	local db, warn = ns.getDB(), under.state == "warn"
	under.tex:SetDesaturated(db.emptyGrey and true or false)
	if warn and db.emptyTint then under.tex:SetVertexColor(1, 0.35, 0.35) else under.tex:SetVertexColor(1, 1, 1) end
	under.ring:show(warn and db.emptyRing)
	under.pulseOn = warn and db.emptyPulse and true or false
	if not under.pulseOn then under.pulse:Stop()
	elseif not under.pulse:IsPlaying() then under.pulse:Play() end
	under.glow:SetShown(warn and db.emptyGlow and true or false)
end

-- Shows the underlay in state st (underState), at its group's opacity, or hides it (alpha 0).
local function setUnder(st)
	if st ~= nil and under.state == nil then appear() end
	under.state = st
	local g = ns.groupOf("shield")
	under:SetAlpha(st and (g and g.alpha or 1) or 0)
	lookUnder()
end

-- Every frame while the button is the switch, a wait runs or a hold hasn't ended: its state now.
-- The state changes the frame a read goes the other way (dead, a flight path, our cast), so it
-- never waits for an event. Out of combat, with auras readable, the events that change the read or
-- the settings decide (SH.applyEmptyLook), and it stops.
local function guard(self)
	if self.hold then
		self.hold = self.hold - 1
		if self.hold <= 0 then self.hold = nil; self.inner:SetAlpha(1) end
	end
	local st = underState()
	if st ~= self.state then setUnder(st) end
	if not (self.hold or covering() or GetTime() < holdUntil) then
		self:SetScript("OnUpdate", nil)
		self.watching = false
	end
end
-- Starts the guard, if it isn't running (it stops itself once nothing needs it).
function watch()
	if under.watching then return end
	under.watching = true
	under:SetScript("OnUpdate", guard)
end
under:SetScript("OnShow", function(self)
	appear()   -- its group or the element was hidden: the container may be a frame behind
	setUnder(underState())
	if self.pulseOn then self.pulse:Play() end   -- a hidden frame's animations stop
end)

-- The underlay's picture and ring in the icon's shape, and its glow in its look now, fitted to the
-- inset picture (placeUnder, SH.applyTimers); the glow's textures shape themselves (onLayout).
local function shapeUnder()
	local f, u = shield, under
	ns.Looks.maskOver(f, u.tex)
	for _, e in ipairs(u.ring.edges) do ns.Looks.maskOver(f, e, u.tex) end
	local g = u.glow
	g:restyle()
	if u.size then g:fit(math.max(u.size - 2 * ns.pixel(u), 1)) end
end

-- With the button's restyle (styleNative), so the two always change together: the underlay's
-- picture a screen pixel in from the button's edges (rounding at any scale leaves no edge past it),
-- at the button's size from the same corner.
local function placeUnder(size)
	local u = under
	u:SetFrameLevel(shield.textFrame:GetFrameLevel() + 1)   -- over the icon, under the container (+5)
	local px = ns.pixel(u)
	local inner = math.max(size - 2 * px, 1)
	u.tex:ClearAllPoints()
	u.tex:SetPoint("TOPLEFT", shield, "TOPLEFT", px, -px)
	u.tex:SetSize(inner, inner)
	u.size = size
	shapeUnder()
end

-- The shield's looks, from its settings and state: the element's own icon (only seen while nothing
-- covers it), the underlay and, in preview mode, the stand-in.
function SH.applyEmptyLook()
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
	under.tex:SetTexture(icon)
	under.on = (known and covered and under.size ~= nil and ns.isEnabled("shield")) and true or false
	if standIn then
		-- Preview mode (SH.preview, below). The stand-in draws the state shown over everything, the
		-- underlay hidden: shield up, at full opacity whatever its group's, as Blizzard's button draws
		-- the shield; down, at its group's, unless the real shield may be up under it, whose opaque
		-- button would show through.
		local up = standInState ~= "down"
		local realUp = covered and believedUp() ~= false
		standIn:SetIgnoreParentAlpha(up or realUp)
	end
	setUnder(underState())
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

-- Whether the slot matches every spell ID of every tracked shield (coverTrusted): a slot missing
-- one would leave the button hidden over that shield. Matching more (a Track just narrowed) only
-- keeps the button up over a shield that no longer counts: a miss, not a false warning.
local function checkIDs()
	local have = native.filtered
	local ok = have ~= nil
	if ok then
		for id in pairs(shieldIDMap()) do
			if not have[id] then ok = false break end
		end
	end
	native.idsOK = ok
end

-- The slot's filter can only change while auras are readable; a change meanwhile waits for that
-- (ns.makeAuraSlot).
local function applyShieldFilter()
	native:refilter()
	checkIDs()
end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if type(id) ~= "number" or isSecret(id) then return end
	s.castIDs[id] = true
	Spells.learn(s.spell, id)
	if tracksShield(key) and not (native.filtered and native.filtered[id]) then applyShieldFilter() end
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
-- comes with the button's restyle, which waits for combat to end. The underlay's glow takes a new
-- look or style at once (its own frames; the options call this after a glow style change).
function SH.applyTimers()
	SH.style()
	shapeUnder()
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
	placeUnder(size)   -- the underlay follows the button's size and shape
	SH.applyEmptyLook()   -- the button may be new: the underlay now has it on top
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

-- Our own successful cast (UNIT_SPELLCAST_SUCCEEDED, spellID not secret): the shield the underlay
-- shows in Either, the cast hold (CAST_HOLD), and a rank the slot doesn't match yet, which the slot
-- takes once combat ends (the underlay waits meanwhile: coverTrusted).
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
	local id = ns.isEnabled("shield") and ns.Style.value("shield", "gcd", "show") and Spells.known(SHIELDS[underlayShield()].spell)
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
	-- The IDs the slot was made with: given again, so the slot records them (checkIDs).
	if native.container and not native.filtered then applyShieldFilter() end
	SH.style()
	SH.applyEmptyLook()
end
-- The button's restyle for a new size or look, and the underlay's opacity follows its group's.
function SH.afterGroups()
	SH.style()
	SH.applyEmptyLook()
end
function SH.refresh()
	-- applyShieldFilter checks the IDs itself.
	if native.container and not native.filtered then applyShieldFilter() else checkIDs() end
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
	say("no-shield look: %s, %s, state %s; button %s, spell IDs %s, shape %s, gate %s, cast hold %s",
		under.on and "on" or "off", covering() and "button decides" or "read decides", tostring(under.state),
		native.button and "made" or "not made", native.idsOK and "matched" or "behind",
		shapeCovers() and "covers" or "behind",
		gate:GetAlpha() > 0.99 and "full" or "not full", GetTime() < holdUntil and "on" or "off")
	for _, key in ipairs(SHIELD_ORDER) do
		local s = SHIELDS[key]
		local e = Spells.bookEntry(s.spell)
		say("%s: %s, spell %s rank %s", s.name, s.known and "known" or "not known", tostring(s.spellID), e and e.rank or "?")
	end
	say("aura container %s%s", native.container and "created" or "not created",
		native.err and (", error: " .. native.err) or "")
	local t = {} for id in pairs(shieldIDMap()) do table.insert(t, tostring(id)) end table.sort(t)
	say("tracked spell IDs: %s", table.concat(t, ","))
end

------------------------------------------------------------------------
-- Preview mode (ShamanForever_Preview.lua) shows the shield up or down. Blizzard's button can't be
-- shown, hidden or faked by addon code, so the preview draws a stand-in over it, and the underlay
-- hides meanwhile (SH.applyEmptyLook sets the stand-in's opacity). Only our own frames change;
-- the element's frame itself is never hidden (ns.fadeTo).
------------------------------------------------------------------------
shield.aboveProtected = true   -- Blizzard's button hangs from it
-- icon: the preview's stand-in, just drawn in state (an options preview state: up3, up1, down);
-- nil when the preview ends.
function SH.preview(icon, state)
	standIn, standInState = icon, state
	SH.applyEmptyLook()
end

ns.registerModule(SH)
