-- Shield (Lightning or Water): underlay (our "no shield" look) + Blizzard's secure aura button on top
--
-- The two shields exclude each other, so one aura slot matches every shield the player tracks
-- (db.shieldTrack) and Blizzard shows whichever is up, switching exactly when the player swaps
-- mid-fight. Both have 3 charges, so one charge bar fits both.
--
-- How it works, and the one inference it makes (docs/combat-techniques.md has more):
-- 1. Blizzard's CustomAuraContainer draws the shield: icon, charge count, charge bar and duration
--    swipe. Its untainted code reads the aura, so all of this is exact in combat. Sanctioned.
-- 2. Under Blizzard's button sits our underlay: the grey icon, red ring and pulse that say "no
--    shield". It should show only when Blizzard's button is hidden, but nothing tells addon code
--    when that happens in combat: every aura API throws for tainted code in combat, even
--    GetAuraDuration and GetUnitAuraInstanceIDs, UNIT_AURA stops reaching the addon, script
--    handlers under the button never run, and the button only animates its own descendants
--    (all tested 2026-09-23). So the underlay follows `believedUp`:
--    * out of combat: exact, read from the aura (SH.refresh). Except in a PvP match: auras stay
--      secret for the whole match (Blizzard's API documentation; not yet seen in a battleground),
--      so the in-combat rules below hold until it ends;
--    * in combat: set to up when UNIT_SPELLCAST_SUCCEEDED reports our own cast of a tracked shield.
--      Our own cast events are documented as never secret (SecretWhenUnitSpellCastRestricted
--      only hides other units' casts); the combat log is never read. The inference is only
--      "a successful shield cast means that shield is up". Casting an untracked shield sets it to
--      down, since that shield replaces the tracked one (the same inference, applied to exclusivity).
--    * Nothing else can set it to down in combat. A shield that drops mid-fight shows the underlay at
--      the "In-combat fallback" strength (No shield block; underlayUp) until the recast or combat
--      (or the match) ends.
--    * Why keep the inference: without it, entering combat with no shield and casting one mid-fight
--      leaves the full "no shield" look bleeding through the live shield until combat ends
--      (at group opacity below 100%).
--    * After a login or /reload in combat or in a PvP match the belief is unknown until a cast or a
--      read, and nothing warns. Blizzard's button is made only while auras are readable, so until
--      then nothing covers the underlay either: believed up or not known, it shows the plain icon.
-- 3. The underlay matters at all only because the group's opacity makes Blizzard's button
--    translucent, so the underlay bleeds through it; nativeIconAlpha compensates so the stack
--    matches the group's opacity. At 100% group opacity the button hides the underlay completely.
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

local shield = ns.newElementIcon("shield")   -- the underlay
ns.registerElement("shield", { frame = shield, label = "Shields", paint = function(t) t:SetTexture(SH.icon()) end,
	learned = function() return SH.learned() end,
	kind = "shield", icon = 136051, school = "spirit", blurb = "Charges and time left. Warns when it's gone." })

-- Per shield at runtime: name (the client's), spellID and bookIcon (highest known rank), known. The IDs
-- that count as it are ns.Spells' (seeds, spellbook, and the live aura's, learned here).
for _, s in pairs(SHIELDS) do s.name = Spells.name(s.spell) end
local believedUp   -- see above: read when auras are readable, else set by our cast; nil until known
local native   -- Blizzard's aura container over the underlay, and our parts on its button (below)

local function tracksShield(key)
	local track = ns.getDB().shieldTrack
	return track == "either" or track == key
end

-- A profile's shield settings, and the account's last shield, made valid (when a profile loads).
function SH.sanitize(db, acct)
	if db.shieldTrack ~= "either" and not SHIELDS[db.shieldTrack] then db.shieldTrack = "lightning" end
	if not SHIELDS[acct.lastShield] then acct.lastShield = "lightning" end
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

-- The shield an own cast belongs to, if any (any rank: ns.Spells matches by ID, then by the client's name).
local function shieldForSpell(id)
	local spell = Spells.keyOf(id)
	for _, key in ipairs(SHIELD_ORDER) do
		if SHIELDS[key].spell == spell then return key end
	end
end

local function anyTrackedShieldKnown()
	for key, s in pairs(SHIELDS) do if tracksShield(key) and s.known then return true end end
	return false
end
-- The element's learned() (ns.registerElement): a shield it tracks (its Track setting) is known.
SH.learned = anyTrackedShieldKnown

-- The underlay is meant to show only when Blizzard's button is hidden, i.e. when the shield is down,
-- so grey and tint apply unconditionally. Frame alpha is applied per texture, so while the shield is
-- up the translucent button stacks on the underlay and reads darker than the shock icon. The engine
-- does not tell us about the hide in combat, so the ring and the underlay strength follow our belief:
-- faded while believed up, full when believed down. Blizzard's icon alpha then compensates for the
-- remaining bleed-through (see nativeIconAlpha) so the stack sums to the display opacity exactly.
function SH.applyEmptyLook()
	local db = ns.getDB()
	shield.tex:SetTexture(SH.icon())
	if not anyTrackedShieldKnown() then
		-- Not learned yet (or Water Shield without its talent): a plain grey icon, as for cooldowns.
		shield.tex:SetDesaturated(true)
		shield.tex:SetVertexColor(1, 1, 1)
		shield.tex:SetAlpha(1)
		shield:SetRingShown(false)
		shield:SetPulsing(false)
		return
	end
	local down = believedUp == false   -- not known yet: no warning
	if not down and not (native.button and not native.err) then
		-- Nothing of Blizzard's over it yet: the underlay is all that shows, so the plain icon.
		shield.tex:SetDesaturated(false)
		shield.tex:SetVertexColor(1, 1, 1)
		shield.tex:SetAlpha(1)
		shield:SetRingShown(false)
		shield:SetPulsing(false)
		return
	end
	shield.tex:SetDesaturated(db.emptyGrey)
	if db.emptyTint then shield.tex:SetVertexColor(1, 0.35, 0.35) else shield.tex:SetVertexColor(1, 1, 1) end
	shield.tex:SetAlpha(down and 1 or db.underlayUp)
	shield:SetRingShown(down and db.emptyRing)
	-- Only while known down: a drop in combat (or a match) is not seen until the recast or its end.
	shield:SetPulsing(down and db.emptyPulse)
end

-- With display opacity a and underlay strength u, an icon alpha b gives a stacked result of
-- a*b + (1 - a*b)*a*u; solving that for a yields b = (1 - u) / (1 - a*u). The display opacity is
-- that of the shield's group.
local function nativeIconAlpha()
	local db = ns.getDB()
	local gi = ns.findElement("shield")
	local a, u = gi and db.groups[gi].alpha or 1, db.underlayUp
	local d = 1 - a * u   -- 0 at full opacity and full underlay: then any b stacks the same, and 1 is natural
	local b = (u > 0 and d > 0) and (1 - u) / d or 1
	return math.min(math.max(b * db.shieldIconAlpha, 0.05), 1)
end

local function setBelievedUp(up)
	believedUp = up
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

-- The slot's filter can only change while auras are readable; a change meanwhile waits for that
-- (ns.makeAuraSlot).
local function applyShieldFilter() native:refilter() end

local function learnShieldID(key, id)
	local s = SHIELDS[key]
	if type(id) ~= "number" or isSecret(id) then return end
	Spells.learn(s.spell, id)
	if tracksShield(key) and not (native.filtered and native.filtered[id]) then applyShieldFilter() end
end

-- After a spellbook scan (ns.resolveSpells): each shield's name, highest known rank and icon, and the
-- slot's filter to match. Returns a signature of what it found.
function SH.resolve()
	local sig = {}
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
	return table.concat(sig, ",")
end

-- Blizzard's button and its parts are off limits to addon code in combat, and while auras are
-- secret: the aura slot's restyle waits until that ends (ns.makeAuraSlot).
function SH.style() native:style() end

-- The shield's timer takes its current style (ns.applyTimers). It sits on Blizzard's button, so it
-- comes with the button's restyle, which waits for combat to end.
SH.applyTimers = SH.style

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
	fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
	if db.countPos == "center" then
		fs:SetPoint("CENTER", button, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
	else
		fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2); fs:SetJustifyH("RIGHT")
	end
	button:SetApplicationCount(fs)
	slot.fs = fs

	-- Charge bar along the bottom edge: min 0 so one charge is one third, not empty.
	local bar = CreateFrame("StatusBar", nil, overlay)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	bar:SetHeight(db.chargeBarHeight)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
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

-- Our parts again, for the current size and settings (after the aura slot's own restyle).
local function styleNative(slot, size)
	local db = ns.getDB()
	for i, t in ipairs(slot.tickTextures or {}) do
		t:ClearAllPoints()
		t:SetPoint("TOP", slot.ticks, "TOPLEFT", size * i / slot.maxCharges, 0)
		t:SetPoint("BOTTOM", slot.ticks, "BOTTOMLEFT", size * i / slot.maxCharges, 0)
	end
	slot.icon:SetAlpha(nativeIconAlpha())
	slot.bar:SetHeight(db.chargeBarHeight)
	slot.bar:SetStatusBarColor(db.chargeBarColor[1], db.chargeBarColor[2], db.chargeBarColor[3], db.chargeBarColor[4] or 1)
	slot.bar:SetAlpha(db.showBar and 1 or 0)
	slot.ticks:SetAlpha(db.showBar and 1 or 0)
	slot.fs:SetAlpha(db.showCount and 1 or 0)
	slot.fs:SetFont(STANDARD_TEXT_FONT, db.countSize, "OUTLINE")
	slot.fs:ClearAllPoints()
	if db.countPos == "center" then
		slot.fs:SetPoint("CENTER", slot.button, "CENTER", 0, 0); slot.fs:SetJustifyH("CENTER")
	else
		slot.fs:SetPoint("BOTTOMRIGHT", slot.button, "BOTTOMRIGHT", 2, -2); slot.fs:SetJustifyH("RIGHT")
	end
	SH.applyEmptyLook()   -- the button may be new: the underlay now has it on top
end

-- Made only while auras are readable (after a /reload in combat or a PvP match, when that ends);
-- once made, it stays.
native = ns.makeAuraSlot(shield, {
	key = "shield", slot = "shield", ids = shieldIDMap, name = "ShamanForeverAuraContainer",
	sites = { container = "shield container", style = "shield style", filter = "shield filter" },
	iconAlpha = nativeIconAlpha,
	onButton = buildNative, onStyle = styleNative,
	onError = function(err)
		say("Blizzard aura container failed on this client; the shield icon will not update: %s", err)
	end,
})

-- Auras can be secret out of combat too (PvP matches, encounters): then keep the belief.
local function aurasReadable() return not InCombatLockdown() and not ns.aurasSecret() end

-- While auras are readable: sync our belief and learn the live spell IDs. Looked up by the client's
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
	setBelievedUp(upKey ~= nil and tracksShield(upKey))
end

-- Our own successful cast (UNIT_SPELLCAST_SUCCEEDED, spellID not secret). The one inference: our
-- cast means that shield is up and the other is gone (see the top of this file).
function SH.onCast(spellID)
	local cast = shieldForSpell(spellID)
	if not cast then return end
	ns.getAccount().lastShield = cast
	setBelievedUp(tracksShield(cast))
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
	SH.style()
	SH.applyEmptyLook()
end
SH.afterGroups = SH.style   -- the alpha compensation follows the group's opacity
function SH.refresh()
	refreshAura()
	refreshGCD(false)
end
SH.onCooldowns = refreshGCD
-- A shaman logged in: the aura, read again whenever it changes (while auras are readable).
function SH.start()
	local ev = CreateFrame("Frame")
	ns.registerEvent(ev, "UNIT_AURA", "player")
	ev:SetScript("OnEvent", refreshAura)
end

-- /sf debug
function SH.debug()
	say("shield tracking %s (last %s), believed up %s", ns.getDB().shieldTrack, ns.getAccount().lastShield,
		believedUp == nil and "unknown" or tostring(believedUp))
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

ns.registerModule(SH)
