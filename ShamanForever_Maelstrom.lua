-- Maelstrom Weapon (an Enhancement talent): its stacks, and a highlight at five, when the next
-- Lightning Bolt is instant and free.
--
-- The stacks are secret in combat, as every aura is, so Blizzard's aura container draws them
-- (ns.makeAuraSlot, as for the shield's charges). Two slots follow the same buff:
-- 1. The stacks: the buff's icon and time left, the stack number and a stack bar (one segment per
--    stack), all drawn by Blizzard's button.
-- 2. The five-stack look: a second button whose only visible part is a bar. Blizzard shows that bar
--    only from four stacks (its minApplications) and fills it from four to five, with no
--    background: nothing shows at four, the whole bar at five (the gate tested 2026-09-28 on
--    Lightning Shield's charges). The bar is the highlight, over the icon, drawn by the engine.
--    - Its pop: Blizzard eases the bar to each new count of the same buff (ExponentialEaseOut) and
--      the bar fills from its centre, so the fifth stack makes the highlight burst out from the
--      middle. A new buff, or one read after a /reload, is drawn at once.
--    - Its pulsing glow: an animation handed to that button, which plays it while the buff is up;
--      it is seen only while the highlight is.
--    Nothing else can mark the fifth stack: the button plays handed animations only when a buff is
--    new to its slot or first shows, and Blizzard's aura sounds come with every added stack
--    (Blizzard_CustomAuraButton.lua, C_UnitAuras.AddAuraSound).
-- The five in its own colour: a numeric rule formatter hands Blizzard one format per count, so the
-- engine picks it. Blizzard prints only counts from 2 without one (below, "The stack number").
-- Nothing here reads the buff or compares its stacks. Under Blizzard's buttons nothing gets a script
-- handler (the client refuses SetScript on frames made in the button's initializeFrame, which ends
-- it) and nothing is read back (IsShown and the like come back secret; tested 2026-09-29).
--
-- ShamanForever.lua calls in through the module hooks (ns.registerModule).

local ADDON, ns = ...
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
local EDGE_GLOW = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Edge-Glow"
local SI = Enum and Enum.StatusBarInterpolation
local EASE, IMMEDIATE = SI and SI.ExponentialEaseOut or 1, SI and SI.Immediate or 0
local CENTER_FILL = Enum and Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Center or "CENTER"

-- Its option defaults (ns.elementSetting), and the ranges its numbers are kept in.
M.DEFAULTS = {
	idleAlpha = 0,
	stackBar = true, stackBarHeight = 6, stackBarColor = { 0.52, 0.69, 1, 1 },
	stackCount = true, countPos = "center", countSize = 18,
	fullCount = true, fullCountColor = { 1, 0.82, 0.25, 1 },   -- the number at five, in its colour
	highlight = "glow", highlightColor = { 1, 0.82, 0.25, 1 },  -- glow | wash | none
	fullPop = true,     -- the highlight bursts out as the fifth stack lands
	fullGlow = false,   -- the highlight pulses while at five
}
M.RANGES = { stackBarHeight = { 1, 20 }, countSize = { 8, 40 } }
local CHOICES = { highlight = { glow = true, wash = true, none = true }, countPos = { corner = true, center = true } }

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
	kind = "maelstrom", def = M, spell = "maelstromWeapon", icon = M.icon, school = "air",
	blurb = "Its stacks, with a highlight at five.", experimental = "Maelstrom Weapon" })
-- For the options' Idle block: it's a buff (its Idle is "not up").
M.key, M.buff = KEY, true

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
local function styleStacks(slot, size)
	local on = setting("stackBar")
	local base = baseLevel()
	slot.overlay:SetFrameLevel(base + 4)
	slot.bar:SetFrameLevel(base + 5)
	slot.tickFrame:SetFrameLevel(base + 6)
	slot.numFrame:SetFrameLevel(base + 7)   -- above the bar and its ticks: the count is never clipped
	local c = color("stackBarColor")
	slot.bar:SetHeight(number("stackBarHeight"))
	slot.bar:SetStatusBarTexture(ns.Media.barTexture())   -- before the colour
	slot.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	-- Again with the bar's range, which a new source changes (the options, out of combat).
	ns.try("maelstrom stack bar", slot.button.SetApplicationBar, slot.button, slot.bar,
		{ minApplications = 0, maxApplications = src.max })
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

-- Made by Blizzard's initializeFrame: each step on its own, so one refused leaves the rest.
local function buildStacks(slot, button)
	slot.button = button
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	slot.overlay = overlay
	-- The count's own frame, above the bar and its ticks (styleStacks sets its level), so the bar
	-- never draws over the digits.
	local numFrame = CreateFrame("Frame", nil, button)
	numFrame:SetAllPoints()
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

local stacks = ns.makeAuraSlot(f, {
	key = KEY, slot = "stacks", ids = function() return src.ids() end, parent = f.effects,
	sites = { container = "maelstrom container", style = "maelstrom style", filter = "maelstrom filter" },
	onButton = function(slot, button) buildStacks(slot, button) end,
	onStyle = function(slot, size) styleStacks(slot, size) end,
	onError = function(err) ns.noteError("maelstrom container", err) end,
})

------------------------------------------------------------------------
-- 2. The five-stack look: the gated bar, its burst and its pulse
------------------------------------------------------------------------
local function styleFull(slot)
	slot.cd:SetAlpha(0)   -- the stacks' button shows the time left
	local base = baseLevel()
	slot.holder:SetFrameLevel(base + 8)
	slot.hl:SetFrameLevel(base + 9)
	local look, c = setting("highlight"), color("highlightColor")
	local bar = slot.hl
	bar:SetStatusBarTexture(look == "wash" and WHITE or EDGE_GLOW)
	ns.try("maelstrom highlight look", function()
		local t = bar:GetStatusBarTexture()
		t:SetBlendMode(look == "wash" and "BLEND" or "ADD")
		bar:SetFillStyle(CENTER_FILL)
	end)
	-- The wash is the colour over the whole icon, so fainter.
	bar:SetStatusBarColor(c[1], c[2], c[3], (c[4] or 1) * (look == "wash" and 0.4 or 1))
	bar:SetAlpha(look == "none" and 0 or 1)
	if slot.container then slot.container:SetShown(look ~= "none") end
	ns.try("maelstrom highlight", slot.button.SetApplicationBar, slot.button, bar, {
		minApplications = src.max - 1, maxApplications = src.max,
		interpolation = setting("fullPop") and EASE or IMMEDIATE,
	})
	-- The pulse plays only while Pulsing glow is on and the highlight is shown: SetLooping(NONE)
	-- makes Blizzard's handed animation play once per buff and stop, so it costs nothing per frame
	-- while the option is off (the default).
	local pulseOn = setting("fullGlow") and look ~= "none"
	local st = ns.Style.get(KEY, "glow")
	ns.try("maelstrom pulse style", function()
		slot.pulse:SetLooping(pulseOn and "BOUNCE" or "NONE")
		slot.fade:SetDuration(st.speed)
		slot.fade:SetToAlpha(pulseOn and st.low or 1)
	end)
end

local function buildFull(slot, button)
	slot.button = button
	local holder = CreateFrame("Frame", nil, button)
	holder:SetAllPoints()
	slot.holder = holder
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetAllPoints(button)
	bar:SetStatusBarTexture(EDGE_GLOW)
	slot.hl = bar
	-- The pulse, on the holder (so the bar's own alpha stays ours for the look): the button plays it.
	-- styleFull sets its looping (below, via buildFull's own call) to match Pulsing glow.
	local pulse = holder:CreateAnimationGroup()
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1); fade:SetToAlpha(1); fade:SetDuration(0.5); fade:SetSmoothing("IN_OUT")
	slot.pulse, slot.fade = pulse, fade
	if button.AddAuraShownAnimation then
		slot.pulseHanded = ns.try("maelstrom pulse", button.AddAuraShownAnimation, button, pulse)
	end
	ns.try("maelstrom highlight build", styleFull, slot)
end

local full = ns.makeAuraSlot(f, {
	key = KEY, slot = "full", ids = function() return src.ids() end, parent = f.effects,
	iconAlpha = function() return 0 end,   -- the stacks' button has the icon
	sites = { container = "maelstrom five container", style = "maelstrom five style",
		filter = "maelstrom five filter" },
	onButton = function(slot, button) buildFull(slot, button) end,
	onStyle = function(slot) styleFull(slot) end,
	onError = function(err) ns.noteError("maelstrom five container", err) end,
})

local SLOTS = { stacks, full }

------------------------------------------------------------------------
-- The icon under Blizzard's buttons: the look while the buff isn't up
------------------------------------------------------------------------
local function refresh()
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
	ns.fadeTo(f, ns.getAccount().locked and ns.idleAlpha(KEY) or 1)
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
	p.pulse = p.hl:CreateAnimationGroup()
	p.pulse:SetLooping("BOUNCE")
	p.fade = p.pulse:CreateAnimation("Alpha")
	p.fade:SetFromAlpha(1); p.fade:SetSmoothing("IN_OUT")
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
	local look = setting("highlight")
	local lit = n >= max and look ~= "none"
	local hc = color("highlightColor")
	p.hl:SetTexture(look == "wash" and WHITE or EDGE_GLOW)
	p.hl:SetBlendMode(look == "wash" and "BLEND" or "ADD")
	p.hl:SetVertexColor(hc[1], hc[2], hc[3], (hc[4] or 1) * (look == "wash" and 0.4 or 1))
	p.hl:SetShown(lit)
	local st = ns.Style.get(KEY, "glow")
	if lit and setting("fullGlow") then
		p.fade:SetDuration(st.speed); p.fade:SetToAlpha(st.low)
		if not p.pulse:IsPlaying() then p.pulse:Play() end
	else
		p.pulse:Stop()
	end
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
-- The five-stack container only when Highlight isn't None: with it made but hidden, Blizzard would
-- still register it for every player UNIT_AURA for a look the player turned off.
function M.applyLayout()
	if src.learned() and ns.isEnabled(KEY) then
		stacks:setup()
		if setting("highlight") ~= "none" then full:setup() end
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
	say("maelstrom: spell %s, following %s (%d stacks), stacks container %s%s, five-stack container %s%s, "
		.. "pulse handed %s",
		tostring(M.spellID), table.concat(ids, ","), src.max,
		stacks.container and "made" or "not made", stacks.err and (" (error: " .. stacks.err .. ")") or "",
		full.container and "made" or "not made", full.err and (" (error: " .. full.err .. ")") or "",
		tostring(full.pulseHanded))
end

ns.registerModule(M)
