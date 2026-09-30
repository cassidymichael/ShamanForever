-- Maelstrom Weapon (an Enhancement talent): its stacks, and a highlight at five, when the next
-- Lightning Bolt is instant and free.
--
-- The stacks are secret in combat, as every aura is, so Blizzard's aura container draws them
-- (ns.makeAuraSlot, as for the shield's charges). Three slots follow the same buff:
-- 1. The stacks: the buff's icon and time left, the stack number and a stack bar (one segment per
--    stack), all drawn by Blizzard's button.
-- 2. The highlight (Colour): a second button whose only visible part is a bar. Blizzard shows that
--    bar only from four stacks (its minApplications) and fills it from four to five, with no
--    background: nothing shows at four, the whole bar at five (the gate tested 2026-09-28 on
--    Lightning Shield's charges). The bar is the highlight, over the icon, drawn by the engine.
--    Its pop: Blizzard eases the bar to each new count of the same buff (ExponentialEaseOut) and
--    the bar fills from its centre, so the fifth stack makes the highlight burst out from the
--    middle. A new buff, or one read after a /reload, is drawn at once.
-- 3. At five: a third button drives an invisible bar five steps long, and a clip from the icon's
--    reach on the left to that bar's fill edge covers the icon and its reach at exactly five
--    stacks and is empty below (Shields' one-charge clip, aimed at five of five; tested there in
--    combat 2026-10-01). In it, the Pulsing glow in the element's look: it hangs under the button,
--    where scripts never run, so the button plays its animations (handed with
--    AddAuraShownAnimation) while the buff is up, and the clip shows them only at five.
--    Nothing else can mark the fifth stack: the button plays handed animations only when a buff is
--    new to its slot or first shows, and Blizzard's aura sounds come with every added stack
--    (Blizzard_CustomAuraButton.lua, C_UnitAuras.AddAuraSound).
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
local EASE, IMMEDIATE = SI and SI.ExponentialEaseOut or 1, SI and SI.Immediate or 0
local CENTER_FILL = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Center or "CENTER"

-- Its option defaults (ns.elementSetting), and the ranges its numbers are kept in.
M.DEFAULTS = {
	idleWhen = "notup", idleAlpha = 0,
	stackBar = true, stackBarHeight = 6, stackBarColor = { 0.52, 0.69, 1, 1 },
	stackCount = true, countPos = "center", countSize = 18,
	fullCount = true, fullCountColor = { 1, 0.82, 0.25, 1 },   -- the number at five, in its colour
	highlight = "none", highlightColor = { 1, 0.82, 0.25, 1 },  -- wash | none: a colour over the icon
	fullPop = true,     -- the highlight bursts out as the fifth stack lands
	fullGlow = true,    -- the Pulsing glow while at five
}
M.RANGES = { stackBarHeight = { 1, 20 }, countSize = { 8, 40 } }
local CHOICES = { highlight = { wash = true, none = true }, countPos = { corner = true, center = true },
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
	-- Its pop is the highlight's own burst (Pop, under Five stacks), not the Pop style's.
	effects = { glow = { "full" }, pop = {} },
	-- Preview mode: its border is on Blizzard's button, not its frame (ShamanForever_Preview.lua).
	standInBorder = true,
	kind = "maelstrom", def = M, spell = "maelstromWeapon", icon = M.icon, school = "air",
	blurb = "Its stacks, with a highlight at five.", experimental = "Maelstrom Weapon" })
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
-- 2. The highlight: the gated bar and its burst
------------------------------------------------------------------------
-- Levels over the containers' (baseLevel): the stacks' parts at 4 to 8, the copy at five (below)
-- from 9 to 18, then the highlight and the glow at five over everything.
local HL_LEVEL, GLOW_LEVEL = 20, 22

local function styleFull(slot)
	slot.cd:SetAlpha(0)   -- the stacks' button shows the time left
	local base = baseLevel()
	slot.holder:SetFrameLevel(base + HL_LEVEL)
	slot.hl:SetFrameLevel(base + HL_LEVEL + 1)
	local look, c = setting("highlight"), color("highlightColor")
	local bar = slot.hl
	bar:SetStatusBarTexture(WHITE)
	ns.try("maelstrom highlight look", function() bar:SetFillStyle(CENTER_FILL) end)
	-- The colour over the whole icon, so fainter.
	bar:SetStatusBarColor(c[1], c[2], c[3], (c[4] or 1) * 0.4)
	bar:SetAlpha(look == "none" and 0 or 1)
	if slot.container then slot.container:SetShown(look ~= "none") end
	ns.try("maelstrom highlight", slot.button.SetApplicationBar, slot.button, bar, {
		minApplications = src.max - 1, maxApplications = src.max,
		interpolation = setting("fullPop") and EASE or IMMEDIATE,
	})
end

local function buildFull(slot, button)
	slot.button = button
	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints()
	slot.holder = holder
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetAllPoints(button)
	bar:SetStatusBarTexture(WHITE)
	slot.hl = bar
	ns.try("maelstrom highlight build", styleFull, slot)
end

local full = ns.makeAuraSlot(f, {
	key = KEY, slot = "full", ids = function() return src.ids() end, parent = f.effects,
	iconAlpha = function() return 0 end,   -- the stacks' button has the icon
	sites = { container = "maelstrom highlight container", style = "maelstrom highlight style",
		filter = "maelstrom highlight filter" },
	onButton = function(slot, button) buildFull(slot, button) end,
	onStyle = function(slot) styleFull(slot) end,
	onError = function(err) ns.noteError("maelstrom highlight container", err) end,
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
	if InCombatLockdown() then return end
	local on = idleWhen() == "five" and src.learned() and ns.isEnabled(KEY) and ns.getAccount().locked
		and copyReady()
	gate:SetAlpha(on and ns.idleAlpha(KEY) or 1)
	if five.host then five.host:SetAlpha(on and 1 or 0) end
end

local SLOTS = { stacks, full, five }

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
	p.hl = p:CreateTexture(nil, "OVERLAY")
	p.hl:SetAllPoints(ic)
	p.burst = p.hl:CreateAnimationGroup()
	local grow = p.burst:CreateAnimation("Scale")
	grow:SetOrigin("CENTER", 0, 0); grow:SetScaleFrom(0.01, 1); grow:SetScaleTo(1, 1)
	grow:SetDuration(0.35); grow:SetSmoothing("OUT")
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
	local hc = color("highlightColor")
	p.hl:SetTexture(WHITE)
	p.hl:SetVertexColor(hc[1], hc[2], hc[3], (hc[4] or 1) * 0.4)
	p.hl:SetShown(n >= max and setting("highlight") ~= "none")
	-- The glow at five: the preview icon's own, in the element's Pulsing glow style.
	ic:SetGlowShown(n >= max and setting("fullGlow"))
end

-- The moment of the fifth stack in the preview: the highlight's burst, when Pop is on.
function M.previewPop(ic)
	if not setting("fullPop") or setting("highlight") == "none" then return end
	local p = previewParts(ic)
	p.burst:Stop()
	p.burst:Play()
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
	for _, name in ipairs({ "stackBarColor", "fullCountColor", "highlightColor" }) do
		if o[name] ~= nil and not ns.isColor(o[name]) then o[name] = nil end
	end
	for name, ok in pairs(CHOICES) do
		if o[name] ~= nil and not ok[o[name]] then o[name] = nil end
	end
end

M.applyTimers = styleAll
-- After a layout: the containers made once (only for a character with the buff), then their looks.
-- The highlight's container only when Highlight isn't None, the one at five only for its glow:
-- with one made but unused, Blizzard would still register it for every player UNIT_AURA for a
-- look the player turned off.
function M.applyLayout()
	if src.learned() and ns.isEnabled(KEY) then
		stacks:setup()
		if setting("highlight") ~= "none" then full:setup() end
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
		return (slot.container and "made" or "not made") .. (slot.err and (" (error: " .. slot.err .. ")") or "")
	end
	say("maelstrom: spell %s, following %s (%d stacks), stacks container %s, highlight container %s, "
		.. "container at five %s (sensor %s, glow %s); idle %s, copy counts %s",
		tostring(M.spellID), table.concat(ids, ","), src.max, state(stacks), state(full), state(five),
		tostring(five.sensed), five.glow and five.glow.look and five.glow.look.key or "none",
		idleWhen(), tostring(copyReady()))
end

ns.registerModule(M)
