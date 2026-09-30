-- Maelstrom Weapon (an Enhancement talent): its stacks, and a pop and a glow at five, when the
-- next Lightning Bolt is instant and free.
--
-- The stacks are secret in combat, as every aura is, so Blizzard's aura container draws them
-- (ns.makeAuraSlot, as for the shield's charges). Three jobs on four slots follow the same buff:
-- 1. The stacks: the buff's icon and time left, the stack number and a stack bar (one segment per
--    stack), all drawn by Blizzard's button.
-- 2. The pop at five, on two slots. Blizzard's button plays handed animations only when an aura is
--    newly assigned to it (AddAuraAssignedAnimation) or it first shows (AddAuraShownAnimation),
--    and a new stack is neither: it updates the same aura (Blizzard_CustomAuraButton.lua,
--    ApplyAuraAssignmentAnimations and ApplyVisibility). So the pop has a container of its own
--    that is visible only at five: it hangs from a bar a second button shows only from five
--    stacks (its minApplications), and a container does its work only while visible
--    (Blizzard_ManagedAuraContainer.lua: its dirty flags wait for an OnUpdate that runs when
--    visible). At the fifth stack it shows, takes the buff as a new aura, and its button plays
--    the pop (ns.Effects' rig on it, the aura route). Staying at five, a refresh or a stack more
--    is an update of the same aura there: nothing plays again. Below five it is hidden, so a buff
--    that goes and comes back is new to it again at its fifth stack. The same buff is assigned
--    to it again at login, /reload, a loading screen, a refilter and the container's first pass,
--    with no new stack: each starts a quiet spell (quietPop) in which the pop draws nothing.
-- 3. At five: a button of its own drives an invisible bar five steps long, and a clip from the
--    icon's reach on the left to that bar's fill edge covers the icon and its reach at exactly five
--    stacks and is empty below (Shields' one-charge clip, aimed at five of five; tested there in
--    combat 2026-10-01). In it, the Pulsing glow in the element's look: it hangs under the button,
--    where scripts never run, so the button plays its animations (handed with
--    AddAuraShownAnimation) while the buff is up, and the clip shows them only at five.
--    No sound marks the fifth stack: Blizzard's aura sounds come with every added stack
--    (C_UnitAuras.AddAuraSound).
--    Idle when "Below five stacks": the stacks' button sits at the Idle opacity (its gate, set out
--    of combat and held through a fight), and the clip also holds a copy of the element at five in
--    full: the aura's icon, its border, time left and number drawn by this button, the stack bar
--    full.
-- The five in its own colour: a numeric rule formatter hands Blizzard one format per count, so the
-- engine picks it. Blizzard prints only counts from 2 without one (below, "The stack number").
-- Nothing here reads the buff or compares its stacks. Under Blizzard's buttons nothing gets a script
-- handler (the client refuses SetScript on frames made in the button's initializeFrame, which ends
-- it) and nothing is read back (IsShown and the like come back secret; tested 2026-09-29).
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule).

local _, ns = ...
local say, isSecret, safe = ns.say, ns.isSecret, ns.safe
local Spells = ns.Spells

-- The buff's own seed ID, kept out of Spells.DEFS: it shares its client name with the talent
-- (maelstromWeapon), and two DEFS keys sharing a name would leave Spells' name lookup to file a new
-- same-named ID (the rune spell that grants the talent) under either key at random. Its own
-- self-check, labelled apart from the talent's, so a missing ID still shows in /sf debug.
local BUFF_IDS = { 408505 }
Spells.addCheck("Maelstrom Weapon (buff)", BUFF_IDS)
local function buffIcon()
	for _, id in ipairs(BUFF_IDS) do
		local ok, tex = safe(C_Spell.GetSpellTexture, id)
		if ok and tex and not isSecret(tex) then return tex end
	end
end

local M = { name = "maelstrom" }
ns.Maelstrom = M

local KEY = "maelstrom"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SI = Enum and Enum.StatusBarInterpolation
local IMMEDIATE = SI and SI.Immediate or 0

-- Its option defaults (ns.elementSetting), and the ranges its numbers are kept in.
M.DEFAULTS = {
	idleWhen = "notup", idleAlpha = 0,
	stackBar = true, stackBarHeight = 6, stackBarColor = { 0.52, 0.69, 1, 1 },
	stackCount = true, countPos = "center", countSize = 18,
	fullCount = true, fullCountColor = { 1, 0.82, 0.25, 1 },   -- the number at five, in its colour
	fullPop = true,     -- the Pop as the fifth stack lands
	fullGlow = true,    -- the Pulsing glow while at five
}
M.RANGES = { stackBarHeight = { 1, 20 }, countSize = { 8, 40 } }
local CHOICES = { countPos = { corner = true, center = true },
	idleWhen = { never = true, notup = true, five = true } }

local function setting(name) return ns.elementSetting(KEY, name) end
local function color(name)
	local c = setting(name)
	return ns.isColor(c) and c or M.DEFAULTS[name]
end
local function number(name)
	local v, r = setting(name), M.RANGES[name]
	if type(v) ~= "number" or v ~= v then v = M.DEFAULTS[name] end
	return math.min(math.max(v, r[1]), r[2])
end

-- What the element follows: the buff's spell IDs, its most stacks, and whether the character has
-- it. Maelstrom Weapon's own by default; M.follow can point the same parts at another aura that
-- stacks (a way to try the looks on a character without the talent).
local BUFF = {
	ids = function()
		local t = {}
		-- The buff's own seed only: the talent's passive must never match it.
		for _, id in ipairs(BUFF_IDS) do t[id] = true end
		return t
	end,
	max = 5,
	learned = function() return M.spellID ~= nil end,
}
local src = BUFF

M.icon = buffIcon() or 237584
local f = ns.newElementIcon(KEY, { effects = true })
f.tex:SetTexture(M.icon)
f.aboveProtected = true   -- Blizzard's buttons sit on it: its alpha only changes out of combat
f.stack()

ns.registerElement(KEY, { frame = f, label = Spells.name("maelstromWeapon"), defaults = M.DEFAULTS,
	learned = function() return src.learned() end, paint = function(t) t:SetTexture(M.icon) end,
	effects = { glow = { "full" }, pop = { "full" } },
	-- Preview mode: its border is on Blizzard's button, not its frame (ShamanForever_Preview.lua).
	standInBorder = true,
	kind = "maelstrom", def = M, spell = "maelstromWeapon", icon = M.icon, school = "air",
	blurb = "Its stacks, with a pop and a glow at five.", experimental = "Maelstrom Weapon" })
-- For the options' Idle block: its "Idle when" choices (idleWhen).
M.key = KEY
M.idleChoices = {
	{ "never", "Never", "It always shows in full" },
	{ "notup", "Not up", "Idle while it isn't up" },
	{ "five", "Below five stacks", "Idle while it's below five stacks or not up",
		"Below five stacks: shown in full only at five." },
}
local function idleWhen()
	local w = setting("idleWhen")
	return CHOICES.idleWhen[w] and w or "notup"
end

-- Its time left is Blizzard's button's own swipe: no text, no bar (its defaults and CANT note are
-- with every other element's in ShamanForever_Timers.lua).

-- The containers sit at their element icon's text level + 5 (ns.makeAuraSlot); our parts are set
-- from that, never read back from Blizzard's buttons.
local function baseLevel() return f.textFrame:GetFrameLevel() + 5 end

------------------------------------------------------------------------
-- The stack number
------------------------------------------------------------------------
-- Given a formatter, Blizzard prints every count through it (without one, only counts from 2):
-- one rule for every count, one for the most stacks in its colour. Made on first use and tried on
-- every count first: Blizzard formats inside the button's aura update, where an error would stop
-- the rest of it, so one that doesn't give a string for each is never handed over.
local formatters, made = {}, 0
local function byte(v) return math.floor(math.min(math.max(v, 0), 1) * 255 + 0.5) end
local function countOptions()
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local code = ""
	if setting("fullCount") then
		local c = color("fullCountColor")
		code = string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
	end
	local id = code .. ":" .. src.max
	local fm = formatters[id]
	if fm == nil then
		if made >= 8 then wipe(formatters); made = 0 end   -- a colour dragged through many
		made = made + 1
		local ok, new = ns.try("maelstrom count formatter", function()
			local x = C_StringUtil.CreateNumericRuleFormatter()
			local rules = { { threshold = 0, format = "%d" } }
			if code ~= "" then table.insert(rules, { threshold = src.max, format = code .. "%d|r" }) end
			x:SetBreakpoints(rules)
			for n = 0, src.max do
				local text = x:FormatNumber(n)
				local coloured = code ~= "" and n == src.max
				if type(text) ~= "string" or isSecret(text) or (coloured and not text:lower():find(code, 1, true)) then
					error(string.format("formatted %d as %s", n, tostring(text)))
				end
			end
			return x
		end)
		fm = ok and new or false
		formatters[id] = fm
	end
	return fm and { formatter = fm } or nil
end
-- Hands the count its formatter again when that changed.
local function applyCountFormat(slot)
	local opts = countOptions()
	local fm = opts and opts.formatter or false
	if fm == slot.countFormatter then return end
	if ns.try("maelstrom count", slot.button.SetApplicationCount, slot.button, slot.fs, opts) then
		slot.countFormatter = fm
	end
end

local function placeCount(fs, button)
	ns.Media.setFont(fs, nil, number("countSize"))
	fs:ClearAllPoints()
	if setting("countPos") == "corner" then
		-- Clear of the stack bar along the bottom edge, when it's on.
		local y = -2 + (setting("stackBar") and (number("stackBarHeight") + 1) or 0)
		fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, y); fs:SetJustifyH("RIGHT")
	else
		fs:SetPoint("CENTER", button, "CENTER", 0, 0); fs:SetJustifyH("CENTER")
	end
end

------------------------------------------------------------------------
-- 1. The stacks: number and bar, on an overlay above the time left's swipe
------------------------------------------------------------------------
-- slot.copy: the copy at five (below), its parts slot.levelUp levels higher, its bar always full.
local function styleStacks(slot, size)
	local on = setting("stackBar")
	local base = baseLevel() + (slot.levelUp or 0)
	slot.overlay:SetFrameLevel(base + 4)
	slot.bar:SetFrameLevel(base + 5)
	slot.tickFrame:SetFrameLevel(base + 6)
	slot.numFrame:SetFrameLevel(base + 7)   -- above the bar and its ticks: the count is never clipped
	slot.edge:SetFrameLevel(base + 8)
	ns.try("maelstrom border", ns.applyBorder, slot.edge, ns.borderFor(KEY))
	if slot.copy and slot.edge.frameOverlay then slot.edge.frameOverlay:Hide() end   -- the host's (auraMask)
	local c = color("stackBarColor")
	slot.bar:SetHeight(number("stackBarHeight"))
	slot.bar:SetStatusBarTexture(ns.Media.barTexture())   -- before the colour
	slot.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	if slot.copy then
		slot.bar:SetMinMaxValues(0, src.max)
		slot.bar:SetValue(src.max)
	else
		-- Again with the bar's range, which a new source changes (the options, out of combat).
		ns.try("maelstrom stack bar", slot.button.SetApplicationBar, slot.button, slot.bar,
			{ minApplications = 0, maxApplications = src.max })
	end
	for i = 1, src.max - 1 do
		local t = slot.ticks[i]
		if not t then
			t = slot.tickFrame:CreateTexture(nil, "OVERLAY")
			t:SetColorTexture(0, 0, 0, 0.9)
			t:SetWidth(1)
			slot.ticks[i] = t
		end
		t:ClearAllPoints()
		t:SetPoint("TOP", slot.tickFrame, "TOPLEFT", size * i / src.max, 0)
		t:SetPoint("BOTTOM", slot.tickFrame, "BOTTOMLEFT", size * i / src.max, 0)
		t:Show()
	end
	for i = src.max, #slot.ticks do slot.ticks[i]:Hide() end
	slot.bar:SetAlpha(on and 1 or 0)
	slot.tickFrame:SetAlpha(on and 1 or 0)
	slot.fs:SetAlpha(setting("stackCount") and 1 or 0)
	placeCount(slot.fs, slot.button)
	applyCountFormat(slot)
end

-- Made by Blizzard's initializeFrame: each step on its own, so one refused leaves the rest. into:
-- the frame the parts hang from (default the button; the copy's host at five).
local function buildStacks(slot, button, into)
	slot.button = button
	into = into or button
	-- The group's border drawn on the button too, so it shows exactly with the buff (the element's
	-- own frame, and its border, sit at its Idle opacity). Styled out of combat only (styleStacks).
	slot.edge = CreateFrame("Frame", nil, into)
	slot.edge:SetAllPoints(button)
	slot.edge.owner = KEY   -- its school colour (ns.Looks)
	local overlay = CreateFrame("Frame", nil, into)
	overlay:SetAllPoints(button)
	slot.overlay = overlay
	-- The count's own frame, above the bar and its ticks (styleStacks sets its level), so the bar
	-- never draws over the digits.
	local numFrame = CreateFrame("Frame", nil, into)
	numFrame:SetAllPoints(button)
	slot.numFrame = numFrame
	-- The font must be set first: Blizzard writes the count at once.
	local fs = numFrame:CreateFontString(nil, "OVERLAY", nil, 7)
	placeCount(fs, button)
	slot.fs = fs
	ns.try("maelstrom count", button.SetApplicationCount, button, fs)
	slot.countFormatter = false
	local bar = CreateFrame("StatusBar", nil, overlay)
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	bar:SetStatusBarTexture(ns.Media.barTexture())
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	slot.bar = bar
	slot.tickFrame = CreateFrame("Frame", nil, overlay)
	slot.tickFrame:SetAllPoints(bar)
	slot.ticks = {}
	ns.try("maelstrom stacks build", styleStacks, slot, ns.sizeOf(KEY))
end

-- The stacks' button hangs from this gate: its Idle opacity with "Below five stacks" (applyIdle).
-- An ancestor of the button: its alpha changes only out of combat.
local gate = CreateFrame("Frame", nil, f.effects)
gate:SetAllPoints(f)

local stacks = ns.makeAuraSlot(f, {
	key = KEY, slot = "stacks", ids = function() return src.ids() end, parent = gate,
	sites = { container = "maelstrom container", style = "maelstrom style", filter = "maelstrom filter" },
	onButton = function(slot, button) buildStacks(slot, button) end,
	onStyle = function(slot, size) styleStacks(slot, size) end,
	onError = function(err) ns.noteError("maelstrom container", err) end,
})

------------------------------------------------------------------------
-- 2. The pop at five: the gate, and the pop's own container on it (see the top of this file)
------------------------------------------------------------------------
-- Levels over the containers' (baseLevel): the stacks' parts at 4 to 8, the copy at five (below)
-- from 9 to 18, the pop's button (its moving icon and border) from 19, the glow at five at 22, and
-- the pop's light over everything.
local POP_LEVEL, GLOW_LEVEL, LIGHT_LEVEL = 19, 22, 24
local SHORTEST = 0.01   -- an animation's shortest length (none takes no time)

-- The pop: ns.Effects' rig on the pop's button (the aura route), in the element's Pop style while
-- Pop is on. Its light over the element's text by baseLevel's 5, then LIGHT_LEVEL.
local fx = ns.Effects.host(f, KEY, { aura = { popOnly = true, popLevel = 5 + LIGHT_LEVEL,
	popOn = function() return setting("fullPop") end } })

-- The rig's values again, and the holds' length: the copy of the icon and its border show only
-- while the motion plays (no motion: never). While quiet (below) they never show.
local quiet = false
local function stylePop(slot, size)
	ns.try("maelstrom pop border", ns.applyBorder, slot.edge, ns.borderFor(KEY))
	if slot.edge.frameOverlay then slot.edge.frameOverlay:Hide() end   -- the copy's (auraMask)
	fx:setQuiet(quiet)
	fx:stylePop(size)
	local len = fx:motionLength()
	local a = (len > 0 and not quiet) and 1 or 0
	for _, g in ipairs(slot.holds) do
		g.hold:SetFromAlpha(a)
		g.hold:SetToAlpha(a)
		g.hold:SetDuration(math.max(len, SHORTEST))
	end
end

-- As Blizzard makes the pop's button: the rig (its motion moves the button's icon, a copy of the
-- element's, and a border of the element's on the rig's body), every group handed to the button.
-- The copy (on the slot's host, with the border look's art) and its border sit at alpha 0, so the
-- stacks' own icon, number and bar show; an Alpha holding each at 1 for the motion's length,
-- handed over too, shows them only while they move.
local function buildPop(slot, button)
	slot.button = button
	fx:bind(button, slot.icon)
	slot.edge = fx:makeEdge(button)
	slot.edge:SetAlpha(0)
	slot.holds = {}
	for _, r in ipairs({ slot.host, slot.edge }) do
		local g = r:CreateAnimationGroup()
		g.hold = g:CreateAnimation("Alpha")
		g.hold:SetFromAlpha(0)
		g.hold:SetToAlpha(0)
		g.hold:SetDuration(SHORTEST)
		table.insert(slot.holds, g)
		ns.try("maelstrom pop hand-off", button.AddAuraAssignedAnimation, button, g)
	end
	ns.try("maelstrom pop build", stylePop, slot, ns.sizeOf(KEY))
end

-- A frame over a button for its icon, its border look's art and its swipe, at alpha 0 (the aura
-- slot's host): the gate draws nothing, the pop's copy shows only while it moves.
local function unseenHost(_, button)
	local h = CreateFrame("Frame", nil, button)
	h:SetAllPoints(button)
	h:SetAlpha(0)
	return h
end

-- Until setupPop gives it the gate's bar, the pop's container would hang from a frame that never
-- shows: a container made anywhere else would take the buff at its first stack and pop there.
local nowhere = CreateFrame("Frame")
nowhere:Hide()
local pop = ns.makeAuraSlot(f, {
	key = KEY, slot = "pop", ids = function() return src.ids() end, parent = nowhere, level = POP_LEVEL,
	noTimer = true, ownIcon = function() return M.icon end, host = unseenHost,
	sites = { container = "maelstrom pop container", style = "maelstrom pop style",
		filter = "maelstrom pop filter" },
	onButton = function(slot, button) buildPop(slot, button) end,
	onStyle = function(slot, size) stylePop(slot, size) end,
	onError = function(err) ns.noteError("maelstrom pop container", err) end,
})

-- The gate: a button whose bar Blizzard shows only from the most stacks (its min and max), drawing
-- nothing. Made hidden, so only Blizzard's own count shows it; a bar the button refused
-- (or held at an old count) is taken back and hidden, never left showing the pop's container.
local function styleGate(slot)
	local ok = ns.try("maelstrom pop gate", slot.button.SetApplicationBar, slot.button, slot.gateBar,
		{ minApplications = src.max, maxApplications = src.max, interpolation = IMMEDIATE })
	if not ok then
		pcall(slot.button.ClearApplicationBar, slot.button)
		slot.gateBar:Hide()
	end
	slot.gated = ok
end

local function buildGate(slot, button)
	slot.button = button
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetAllPoints(button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:Hide()
	slot.gateBar = bar
	ns.try("maelstrom pop gate build", styleGate, slot)
end

local gateSlot   -- below

-- Blizzard hands the pop's button its animations whenever it assigns the buff to it, and that also
-- happens with no new fifth stack: at login, /reload and loading screens (a full aura update), a
-- refilter, the container's first pass, turning Pop on. So for QUIET seconds from each of those
-- the pop's visible parts stay off (the copy and border holds at 0, the rig's frames at alpha 0),
-- set out of combat only (they are Blizzard's animations and our frames beside its button); then
-- restored. Accepted limits: a group shown in combat, a refilter mid-fight or a loading screen in
-- combat can't be quieted, and a quiet that ends in combat is restored after it.
local QUIET = 2
local quietToken
local function restylePop()
	if pop.button and not InCombatLockdown() and not ns.aurasSecret() then
		ns.try("maelstrom pop quiet", stylePop, pop, ns.sizeOf(KEY))
	end
	pop:style()
end
local function quietPop()
	if InCombatLockdown() then return end
	quiet = true
	local token = {}
	quietToken = token
	restylePop()
	C_Timer.After(QUIET, function()
		if quietToken ~= token then return end
		quiet = false
		restylePop()
	end)
end

-- The pop's container on the gate's bar, once the bar took its count, while Pop is on. Made from
-- the layout or the gate's restyle, never as Blizzard makes a button (frames made there can't run
-- scripts); out of combat with auras readable (the aura slot waits for that).
local function setupPop()
	if pop.container or pop.err or not (gateSlot.gated and setting("fullPop")) then return end
	pop.opts.parent = gateSlot.gateBar
	quietPop()   -- before the container exists: its first assignment plays nothing
	pop:setup()
end

gateSlot = ns.makeAuraSlot(f, {
	key = KEY, slot = "gate", ids = function() return src.ids() end, parent = f.effects,
	noTimer = true, host = unseenHost,
	sites = { container = "maelstrom pop gate container", style = "maelstrom pop gate style",
		filter = "maelstrom pop gate filter" },
	onButton = function(slot, button) buildGate(slot, button) end,
	onStyle = function(slot)
		styleGate(slot)
		setupPop()
	end,
	onError = function(err) ns.noteError("maelstrom pop gate container", err) end,
})

------------------------------------------------------------------------
-- 3. At five: the clip, and the Pulsing glow in it (see the top of this file)
------------------------------------------------------------------------
-- The glow's reach past the icon's edge, as a clip look's (ns.makeClipLook: the widest look, Proc
-- glow's opening burst, reaches 1.7 widths of the icon with its frame from its centre).
local REACH = 1.7
-- Its container, levels above the stacks' (ns.makeAuraSlot's level); the copy's icon and swipe; its
-- parts as the stacks' (styleStacks) that many levels higher.
local FIVE_LEVEL, HOST_LEVEL, COPY_UP = 9, 12, 10

-- The sensor bar and the clip over it, for an icon of size: the bar src.max steps long (a step:
-- the icon with its reach both ways, and 2 px), its fill edge on the reach's right edge at the most
-- stacks and a step left of its left edge at one fewer.
local function placeFive(slot, button, size)
	local reach = math.ceil(REACH * (size + 2 * ns.Looks.outerEdge(f)) - size / 2)
	local step = size + 2 * reach + 2
	local bar, clip = slot.sensor, slot.clip
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", size + reach - src.max * step, -reach)
	bar:SetSize(src.max * step, 2)
	clip:ClearAllPoints()
	clip:SetPoint("TOPLEFT", button, "TOPLEFT", -reach, reach)
	clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
	return bar
end

-- As Blizzard makes the button: the sensor, the clip and the frame in it where the aura slot puts
-- the icon and the timer (ns.makeAuraSlot's host), unseen for now.
local function fiveHost(slot, button)
	local bar = CreateFrame("StatusBar", nil, button)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetMinMaxValues(0, src.max)
	bar:SetValue(0)   -- until Blizzard sets it: the clip empty
	slot.sensor = bar
	local clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(baseLevel() + HOST_LEVEL)
	slot.clip = clip
	placeFive(slot, button, ns.sizeOf(KEY))
	slot.sensed = ns.try("maelstrom five sensor", button.SetApplicationBar, button, bar,
		{ minApplications = 0, maxApplications = src.max, interpolation = IMMEDIATE })
	local host = CreateFrame("Frame", nil, clip)
	host:SetAllPoints(button)
	host:SetFrameLevel(baseLevel() + HOST_LEVEL)
	host:SetAlpha(0)   -- the copy: shown by applyIdle
	return host
end

local function styleFive(slot, size)
	local base = baseLevel()
	placeFive(slot, slot.button, size)
	ns.try("maelstrom five sensor", slot.button.SetApplicationBar, slot.button, slot.sensor,
		{ minApplications = 0, maxApplications = src.max, interpolation = IMMEDIATE })
	slot.cd:SetFrameLevel(base + HOST_LEVEL + 1)
	styleStacks(slot, size)   -- the copy's parts
	local g = slot.glow
	g:SetFrameLevel(base + GLOW_LEVEL)
	g.inner:SetFrameLevel(base + GLOW_LEVEL)
	g:restyle()
	g:fit(size)
	-- Shown only when its sensor works: a bar the button refused would leave the clip empty.
	g:SetShown((setting("fullGlow") and slot.sensed) and true or false)
end

local applyIdle   -- below

-- Once Blizzard has made the button: the glow in the clip, its animations handed to the button,
-- and the copy's parts on the host (the stacks' parts, drawn full).
local function buildFive(slot, button)
	slot.button = button
	local g = ns.Effects.glow(slot.clip, button, KEY, { underButton = true })
	g:bindButton(button)
	slot.glow = g
	slot.copy, slot.levelUp = true, COPY_UP
	buildStacks(slot, button, slot.host)
	-- A copy that can't be styled never counts: the stacks stay in full.
	slot.built = ns.try("maelstrom five build", styleFive, slot, ns.sizeOf(KEY))
	-- Blizzard is still inside initializeFrame, and the copy counts only once it is made: Idle
	-- decides again the next frame.
	C_Timer.After(0, function() applyIdle() end)
end

local five = ns.makeAuraSlot(f, {
	key = KEY, slot = "five", ids = function() return src.ids() end, parent = f.effects, level = FIVE_LEVEL,
	host = fiveHost,
	sites = { container = "maelstrom five container", style = "maelstrom five style",
		filter = "maelstrom five filter" },
	onButton = function(slot, button) buildFive(slot, button) end,
	onStyle = function(slot, size)
		styleFive(slot, size)
		applyIdle()   -- it may count now
	end,
	onError = function(err) ns.noteError("maelstrom five container", err) end,
})

-- Whether the copy at five is made, sized and filtered as the stacks' slot is: until then the
-- stacks stay in full (a missed idle, never a faint icon at five). While a restyle for a new Size
-- is queued the answer stays what it was, so a dragged Size slider doesn't flicker it.
local readyLast = false
local function copyReady()
	local ok = five.built and five.sensed and five.applied ~= nil and five.applied == stacks.applied
	local ready = ok and five.size == ns.sizeOf(KEY)
	if ok and not ready and five.styleSoon then ready = readyLast end
	readyLast = ready and true or false
	return readyLast
end

-- Idle "Below five stacks": the stacks' gate at the Idle opacity and the copy shown, set out of
-- combat and held through a fight (a change in combat waits for its end). Only while positioning
-- is locked, the element is on and learned, and the copy counts.
function applyIdle()
	-- Blizzard's button refuses our calls in combat and while auras are secret: run again when
	-- they are readable.
	if ns.deferWhileAurasSecret("maelstrom idle", applyIdle) then return end
	local on = idleWhen() == "five" and src.learned() and ns.isEnabled(KEY) and ns.getAccount().locked
		and copyReady()
	gate:SetAlpha(on and ns.idleAlpha(KEY) or 1)
	if five.host then five.host:SetAlpha(on and 1 or 0) end
end

local SLOTS = { stacks, gateSlot, pop, five }

------------------------------------------------------------------------
-- The icon under Blizzard's buttons: the look while the buff isn't up
------------------------------------------------------------------------
local function refresh()
	applyIdle()
	if not ns.isEnabled(KEY) then return end
	f.tex:SetTexture(M.icon)
	if not src.learned() then
		-- Not learned yet (seen only in test mode): a plain grey icon.
		f.tex:SetDesaturated(true)
		ns.fadeTo(f, 1)
		return
	end
	f.tex:SetDesaturated(false)
	-- The buttons say when it's up, on the effects layer, which ignores this icon's alpha.
	ns.fadeTo(f, (ns.getAccount().locked and idleWhen() ~= "never") and ns.idleAlpha(KEY) or 1)
end

local function styleAll() for _, s in ipairs(SLOTS) do s:style() end end

-- Points the element at another stacking aura: { ids() -> spell ID map, max, learned() }, or nil for
-- Maelstrom Weapon again. Out of combat; the slots follow as soon as auras are readable.
function M.follow(s)
	src = s or BUFF
	wipe(formatters); made = 0
	quietPop()
	for _, slot in ipairs(SLOTS) do slot:refilter() end
	ns.applyLayout()
	ns.refreshAll()
end
function M.maxStacks() return src.max end

------------------------------------------------------------------------
-- The options' preview (ShamanForever_OptionsLook.lua): the same parts, drawn by us for n stacks
------------------------------------------------------------------------
local function previewParts(ic)
	if ic.mw then return ic.mw end
	local p = CreateFrame("Frame", nil, ic.textFrame)
	p:SetAllPoints(ic)
	p:SetFrameLevel(ic.textFrame:GetFrameLevel() + 1)
	p.bg = p:CreateTexture(nil, "BACKGROUND")
	p.segs = {}
	ic.mw = p
	return p
end

function M.drawPreview(ic, n)
	local p = previewParts(ic)
	local max = src.max
	local w, h = ic:GetWidth(), number("stackBarHeight")
	local barOn = n > 0 and setting("stackBar")
	p.bg:ClearAllPoints()
	p.bg:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", 0, 0)
	p.bg:SetSize(w, h)
	p.bg:SetColorTexture(0, 0, 0, 0.6)
	p.bg:SetShown(barOn)
	local c = color("stackBarColor")
	local path, atlas = ns.Media.barOf(ns.Style.value(nil, "bar", "texture"))   -- the HUD's bar texture
	local segW = (w - (max - 1)) / max
	for i = 1, math.max(max, #p.segs) do
		local t = p.segs[i]
		if not t then t = p:CreateTexture(nil, "ARTWORK"); p.segs[i] = t end
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", ic, "BOTTOMLEFT", (i - 1) * (segW + 1), 0)
		t:SetSize(segW, h)
		if atlas then t:SetAtlas(path) else t:SetTexture(path) end
		t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		t:SetShown(barOn and i <= n)
	end
	if n > 0 and setting("stackCount") then
		local fc = color("fullCountColor")
		placeCount(ic.count, ic)
		ic.count:SetText(n)
		if n == max and setting("fullCount") then ic.count:SetTextColor(fc[1], fc[2], fc[3], 1)
		else ic.count:SetTextColor(1, 1, 1, 1) end
		ic.count:Show()
	end
	-- The glow at five: the preview icon's own, in the element's Pulsing glow style.
	ic:SetGlowShown(n >= max and setting("fullGlow"))
end

------------------------------------------------------------------------
-- Hooks (ShamanForever.lua calls them; see ns.registerModule)
------------------------------------------------------------------------
function M.resolve()
	ns.ELEMENTS[KEY].label = Spells.name("maelstromWeapon")
	M.spellID = Spells.known("maelstromWeapon")
	return tostring(M.spellID)
end

-- A profile's settings for it, made valid (a damaged value falls back to its default).
function M.sanitize(db)
	local o = type(db.elementOpts) == "table" and db.elementOpts[KEY]
	if type(o) ~= "table" then return end
	for name, r in pairs(M.RANGES) do
		local v = o[name]
		if v ~= nil and (type(v) ~= "number" or v ~= v) then o[name] = nil
		elseif v ~= nil then o[name] = math.min(math.max(v, r[1]), r[2]) end
	end
	for _, name in ipairs({ "stackBarColor", "fullCountColor" }) do
		if o[name] ~= nil and not ns.isColor(o[name]) then o[name] = nil end
	end
	for name, ok in pairs(CHOICES) do
		if o[name] ~= nil and not ok[o[name]] then o[name] = nil end
	end
end

-- A loading screen sends a full aura update: the buff is assigned to the pop again.
local worldEv = CreateFrame("Frame")
ns.registerEvent(worldEv, "PLAYER_ENTERING_WORLD")
worldEv:SetScript("OnEvent", function()
	if pop.container then quietPop() end
end)

M.applyTimers = styleAll
-- After a layout: the containers made once (only for a character with the buff), then their looks.
-- The gate and the pop's container only while Pop is on, the one at five only for its glow or
-- Idle: with one made but unused, Blizzard would still register it for every player UNIT_AURA for
-- a look the player turned off.
local popWasOn = false
function M.applyLayout()
	local popOn = src.learned() and ns.isEnabled(KEY) and setting("fullPop") and true or false
	if popOn and not popWasOn and pop.container then quietPop() end   -- Pop or element on
	popWasOn = popOn
	if src.learned() and ns.isEnabled(KEY) then
		stacks:setup()
		if setting("fullPop") then
			gateSlot:setup()
			setupPop()
		end
		if setting("fullGlow") or idleWhen() == "five" then five:setup() end
	end
	styleAll()
	refresh()
end
M.afterGroups = styleAll
M.refresh = refresh

-- /sf debug
function M.debug()
	local ids = {}
	for id in pairs(src.ids()) do table.insert(ids, tostring(id)) end
	table.sort(ids)
	local function state(slot)
		local err = slot.err and (" (error: " .. slot.err .. ")") or ""
		return (slot.container and "made" or "not made") .. err
	end
	say("maelstrom: spell %s, following %s (%d stacks), stacks container %s, pop gate container %s "
		.. "(gated %s), pop container %s (%s), container at five %s (sensor %s, glow %s); idle %s, "
		.. "copy counts %s",
		tostring(M.spellID), table.concat(ids, ","), src.max, state(stacks), state(gateSlot),
		tostring(gateSlot.gated), state(pop), fx:describe(), state(five),
		tostring(five.sensed), five.glow and five.glow.look and five.glow.look.key or "none",
		idleWhen(), tostring(copyReady()))
end

ns.registerModule(M)
