-- Buff elements
-- Each is shown by Blizzard's aura container while its aura is up (proc): only the container can show
-- an aura in combat, on the player or another unit. Nothing here times a buff from a cast.

local _, ns = ...
local P = ns.Profiles
local W = ns.Widgets
local E, MOD = ns.Elements, ns.Modules
local say, isSecret, safe, describeArg = ns.say, ns.isSecret, ns.safe, ns.describeArg
local Spells, KD, CS = ns.Spells, ns.Kinds, ns.CastStates

local B = { name = "buffs" }
ns.Buffs = B

local setting = E.setting

-- Elements: the class's rows (ns.CLASS.buffs), all built here; BUFFS are those this file runs. Rows
-- from other files join the list before this file loads.
local ROWS = ns.CLASS.buffs or {}
local BUFFS = {}

-- The kind and its parts (ns.registerPart); a row's flags name its parts. Other files' rows and
-- parts join it: the reagent's (_Reagents), a class's own.
local function procName(def) return def.buffKey and Spells.name(def.buffKey) end
ns.registerPart("buff", {
	idle = { text = function(def)
		local name = def.proc and procName(def)
		return name and ("Idle while " .. name .. " isn't up") or "Idle while it isn't up"
	end },
	page = {
		uptime = function(def) return not def.noTimer and "Time left" or nil end,
		expire = {},
		active = function(def)
			local tips = { pop = def.popTip or "The moment it procs.",
				glow = def.glowTip or "While it's up." }
			return { title = def.procHeader or procName(def), tips = tips }
		end,
	},
	preview = {
		uptime = true,
		labels = { low = "Not up, few left", out = "Not up, none left" },
		states = function(def)
			local states = { { "up", def.upLabel or procName(def) or "Up", 10 } }
			table.insert(states, { "idle", def.idleLabel or "Not up", 40 })
			return states
		end,
		render = function(ic, st, def, kit)
			local key = def.key
			kit.reset(ic, def.icon)
			if st == "up" then
				-- A buff on you at its own length; on another unit, one of 15 s
				if not def.noTimer then kit.frozen(ic.upT, 0.3, not def.unit and def.duration or 15) end
				ic:SetGlowShown(setting(key, "active", "glow"))
			elseif st == "idle" then
				if setting(key, "idleWhen") ~= "never" then kit.idle(ic, key) end
			end
		end,
		rest = function(ic, def, kit, keep) if not keep then kit.idle(ic, def.key) end end,
	},
})
-- breath: warns under water without it (the breath bar runs only while no water breathing is up)
ns.registerPart("breath", {
	defaults = { warn = { on = true, ring = true, fade = true, glow = false }, breath = { sound = "none" } },
	glow = true,
	page = { warn = { title = "Under water without it",
		on = { "Warn", "While your breath bar drains, which it never does while it's up." } },
		own = { "sound", name = "breath", title = "Low breath", tip = "When your breath bar has 10 seconds left.",
			badge = "Low breath sound" } },
	experiment = "Low breath sound",
	preview = {
		warning = "underwater",
		states = { { "underwater", "Under water without it", 80 } },
		render = function(ic, st, def, kit)
			if st ~= "underwater" then return end
			if setting(def.key, "warn", "on") then ic:SetWarnParts(W.warnParts(def.key, "warn"))
			else kit.idle(ic, def.key) end
		end,
	},
})
-- procSound (with proc): a sound as its aura comes, played by the engine; experimental
ns.registerPart("procSound", {
	kind = "buff", after = "proc",
	defaults = { active = { sound = "none" } },
	experiment = function(def) return procName(def) .. " sound" end,
	page = { active = function(def)
		return { soundBadge = procName(def) .. " sound", tips = { sound = "The moment it procs." } }
	end },
})
-- proc: shown by Blizzard's aura container while the aura is up (noPop, noGlow: without its own)
ns.registerPart("proc", {
	has = function(def) return def.proc and not (def.noPop and def.noGlow) end,
	defaults = { active = { pop = true, glow = true } },
	glow = function(def) return not def.noGlow end,
	pop = function(def) return not def.noPop end,
	preview = {
		pop = function(ic, st, def)
			if st == "up" and setting(def.key, "active", "pop") then ic:Pop("ready") end
		end,
	},
})
-- charges: the most its aura can have, shown on Blizzard's button as a number and a bar (W.Count)
local Count = W.Count
local COUNT_POS = {}
for pos in pairs(W.COUNT_JUSTIFY) do table.insert(COUNT_POS, pos) end
local function charge(def, field)
	local v = setting(def.key, "count", field)
	if v == nil then v = def.defaults.count[field] end
	return v
end
local function chargesLift(def) return charge(def, "bar") and charge(def, "barHeight") or 0 end
local function placeCharges(def, fs, anchor)
	ns.Media.setFont(fs, nil, charge(def, "size"))
	local lift = charge(def, "bar") and chargesLift(def) + 1 or 0
	Count.place(fs, anchor, charge(def, "pos"), lift, ns.StyleArt.pictureInset(anchor))
end
local function styleCharges(def, slot, size, button)
	local site = "proc charges " .. def.key
	Count.styleBar(slot, size, def.charges, charge(def, "barHeight"), charge(def, "barColor"), charge(def, "bar"))
	slot.fs:SetAlpha(charge(def, "number") and 1 or 0)
	placeCharges(def, slot.fs, button or slot.button)
	-- Every count from 1 (Blizzard's own prints only from 2), none at 0, once the slot has its button
	if slot.button then
		Count.setFormat(slot, Count.formatter(nil, def.charges, def.charges, site .. " formatter", 1), site)
	end
end
ns.registerPart("charges", {
	kind = "buff", after = "proc",
	defaults = { count = { number = true, pos = "CENTER", size = 18, bar = false, barHeight = 5,
		barColor = { 1, 1, 1, 1 } } },
	ranges = { count = { size = { 8, 40, 1 }, barHeight = { 1, 20, 1 } } },
	-- Its rows sit in the proc's block, under its glow
	page = { active = { extra = function(s, p)
		local K, Page = ns.Options.kit, ns.Page
		local numberGet, numberSet = s.opt("count", "number")
		local number = p:checkbox("Charge number", nil, numberGet, numberSet)
		p:sub(number, numberGet, function()
			local posGet, posSet = s.opt("count", "pos")
			p:dropdown("Number position", nil, K.COUNT_POINTS, posGet, posSet, nil, 150)
			local sizeGet, sizeSet = s.opt("count", "size")
			K.rangeSlider(p, s.range("count", "size"), "Number size", nil, Page.int, sizeGet, sizeSet)
		end)
		local barGet, barSet = s.opt("count", "bar")
		local bar = p:checkbox("Charge bar", "One segment per charge.", barGet, barSet)
		p:sub(bar, barGet, function()
			local heightGet, heightSet = s.opt("count", "barHeight")
			K.rangeSlider(p, s.range("count", "barHeight"), "Bar height", nil, Page.px, heightGet, heightSet)
			local colorGet, colorSet = s.opt("count", "barColor")
			p:color("Bar colour", nil, colorGet, colorSet)
		end)
	end } },
	preview = {
		render = function(ic, st, def, kit)
			if st ~= "up" then return end
			local n = def.charges
			if charge(def, "bar") then
				local c = charge(def, "barColor")
				ic.bar:SetHeight(charge(def, "barHeight"))
				kit.setBar(ic, n, n, c[1], c[2], c[3], c[4])
			end
			if charge(def, "number") then
				placeCharges(def, ic.count, ic)
				ic.count:SetText(n)
				ic.count:SetTextColor(1, 1, 1, 1)
				ic.count:Show()
			end
		end,
	},
	runtime = {
		button = function(def, slot, button)
			local site = "proc charges " .. def.key
			local overlay = CreateFrame("Frame", nil, button)
			overlay:SetAllPoints()
			overlay:SetFrameLevel(slot.cd:GetFrameLevel() + 2)
			Count.text(slot, button, overlay, function(fs) placeCharges(def, fs, button) end, site)
			-- min 0: one charge is a third, not empty
			local bar = Count.bar(slot, overlay, button)
			ns.try(site .. " bar", button.SetApplicationBar, button, bar,
				{ minApplications = 0, maxApplications = def.charges })
			ns.try(site, styleCharges, def, slot, slot.size, button)
		end,
		style = function(def, size, slot) if slot.fs then styleCharges(def, slot, size) end end,
	},
})

-- Expiring drawn by the engine on an aura button, set out of combat: an invisible driver bar's fill end
-- splits the time bar's place at the threshold, the time bar held in a clip before it and a bar in the
-- Expiring colour in a clip after it, so each spot is drawn once; and a red countdown. x holds its frames
-- and lengthOff; def its settings
local EXPIRE_FAST = 240   -- the driver's fill end crosses the time bar in a 240th of the aura's length
local EXPIRE_RED = { 1, 0.2, 0.2, 1 }
local REMAINING = Enum and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration or 0
local function expireSite(def, what) return (def.unit == "target" and "target " or "") .. what .. " " .. def.key end

-- A bar of ours on parent that the button drives with its aura's time left
local function boundBar(button, parent, def, what)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(ns.WHITE)
	return bar, ns.try(expireSite(def, what), button.SetDurationBar, button, bar, ns.Timer.AURA_BAR)
end
-- The Expiring colour: its bar in a clip hung from the driver's fill end
local function makeExpireBar(button, def)
	local x = {}
	x.clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
	x.clip:SetClipsChildren(true)
	x.clip:Hide()
	x.bar, x.ok = boundBar(button, x.clip, def, "expiring bar")
	return x
end
-- The driver: never drawn, only its fill end is used
local function makeDriver(button, def)
	local x = {}
	x.bar, x.ok = boundBar(button, button, def, "expiring driver")
	x.bar:SetStatusBarColor(0, 0, 0, 0)
	x.fill = x.bar:GetStatusBarTexture()
	return x
end

-- Step colour curve: red under secs, colour c from there
local expireCurves = ns.cache(32, function(secs, c)
	local curve = C_CurveUtil.CreateColorCurve()
	if Enum and Enum.LuaCurveType then pcall(curve.SetType, curve, Enum.LuaCurveType.Step) end
	curve:AddPoint(0, CreateColor(EXPIRE_RED[1], EXPIRE_RED[2], EXPIRE_RED[3], EXPIRE_RED[4]))
	curve:AddPoint(secs, CreateColor(c[1], c[2], c[3], c[4] or 1))
	return curve
end)
local function expireTextCurve(secs, c)
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
	return expireCurves(string.format("%d:%.3f:%.3f:%.3f:%.3f", secs, c[1], c[2], c[3], c[4] or 1), secs, c)
end

local function styleExpireText(x, def, slot, st, secs)
	local key, t = def.key, slot.timer
	local fs, b = x.durText, slot.button
	local textOn = secs > 0 and setting(key, "expire", "text") and st.text and fs ~= nil
		and expireTextCurve(secs, st.textColor)
	if textOn then
		x.textHolder:SetFrameLevel(def.frame.textFrame:GetFrameLevel() + 15)
		ns.Media.setFont(fs, key, st.textSize)
		ns.Timer.placeText(fs, b, st, t and t.barIn, t and t.dual, ns.StyleArt.pictureInset(slot.host))
		if ns.try(expireSite(def, "countdown"), b.SetDurationText, b, fs,
			{ textColor = { curve = textOn, property = REMAINING } }) then
			x.textHanded = true
			fs:Show()
			if t then t.cd:SetHideCountdownNumbers(true) end
			return
		end
	end
	if fs then
		ns.try(expireSite(def, "countdown"), b.ClearDurationText, b)
		fs:Hide()
	end
	x.textHanded = false
end

-- slot: its aura slot (W.makeAuraSlot); length: the aura's full length
local function styleExpire(x, def, length, slot)
	local key, t = def.key, slot.timer
	local st = ns.Style.get(key, "uptime")
	local secs, r = setting(key, "expire", "secs"), def.ranges.expire.secs
	if type(secs) ~= "number" or secs ~= secs then secs = def.defaults.expire.secs end
	secs = math.min(math.max(math.floor(secs + 0.5), r[1]), r[2])
	local red, driver, keep = x.redBar, x.driver, t and t.holder
	local barOn = secs > 0 and setting(key, "expire", "bar") and t and t.barOn and red and driver and keep
		and red.ok and driver.ok and driver.fill ~= nil and not x.lengthOff and type(length) == "number"
		and length > 0
	-- Placed hidden, then shown; off or not placed, the time bar whole
	if red then red.clip:Hide() end
	if not barOn then
		if t then t:clipBar(false) end
		return styleExpireText(x, def, slot, st, secs)
	end
	local c = setting(key, "expire", "barColor")
	if not ns.isColor(c) then c = def.defaults.expire.barColor end
	local part = math.min(secs, length) / length
	local placed = ns.try(expireSite(def, "expiring place"), function()
		-- Along the time bar wherever it sits, from the end it drains to: its left, an upright one's bottom
		local upright = t.side == "left" or t.side == "right"
		local len = t:barLength(t.side)
		-- Out of the icon the bars' edges lie outside them: both clips reach past the bar by it
		local e = t:edge()
		-- Levels: glow and countdown above the Expiring colour
		local base = def.frame.textFrame:GetFrameLevel()
		red.clip:SetFrameLevel(base + 10); red.bar:SetFrameLevel(base + 11)
		driver.bar:SetFrameLevel(base + 12)
		local d, fill = driver.bar, driver.fill
		if upright ~= (x.upright or false) then
			d:SetOrientation(upright and "VERTICAL" or "HORIZONTAL")
			x.upright = upright
		end
		-- The driver, far longer than the time bar: its fill end reaches the bar's far end a 240th of the
		-- aura's length before the threshold and its draining end at the threshold
		local long = len * EXPIRE_FAST
		local off = -long * part
		d:ClearAllPoints()
		red.clip:ClearAllPoints()
		keep:ClearAllPoints()
		-- The time bar's clip from its draining end to the fill end, the Expiring colour's from there on
		if upright then
			d:SetPoint("BOTTOMLEFT", t.bar, "BOTTOMLEFT", 0, off)
			d:SetPoint("BOTTOMRIGHT", t.bar, "BOTTOMRIGHT", 0, off)
			d:SetSize(st.barHeight, long)
			keep:SetPoint("BOTTOMLEFT", t.bar, "BOTTOMLEFT", -e, -e)
			keep:SetPoint("TOPRIGHT", fill, "TOPRIGHT", e, 0)
			red.clip:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", -e, 0)
			red.clip:SetPoint("TOPRIGHT", t.bar, "TOPRIGHT", e, e)
		else
			d:SetPoint("TOPLEFT", t.bar, "TOPLEFT", off, 0)
			d:SetPoint("BOTTOMLEFT", t.bar, "BOTTOMLEFT", off, 0)
			d:SetSize(long, st.barHeight)
			keep:SetPoint("TOPLEFT", t.bar, "TOPLEFT", -e, e)
			keep:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, -e)
			red.clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, e)
			red.clip:SetPoint("BOTTOMRIGHT", t.bar, "BOTTOMRIGHT", e, -e)
		end
		-- The Expiring colour's bar: the time bar's twin on the same aura
		red.bar:ClearAllPoints()
		red.bar:SetAllPoints(t.bar)
		t:dress(red.bar)
		red.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
	end)
	t:clipBar(placed)
	red.clip:SetShown(placed)
	styleExpireText(x, def, slot, st, secs)
end

-- Its extra slots (the Expiring colour, then the driver: a refilter stopped part way leaves no colour), its
-- countdown's holder (font set first: Blizzard writes at once), style
B.expiring = {
	extras = function(x, def)
		return {
			{ key = "expire", init = function(_, b) x.redBar = makeExpireBar(b, def) end },
			{ key = "driver", init = function(_, b) x.driver = makeDriver(b, def) end },
		}
	end,
	button = function(x, button)
		x.textHolder = CreateFrame("Frame", nil, button)
		x.textHolder:SetAllPoints(button)
		x.durText = x.textHolder:CreateFontString(nil, "OVERLAY")
		x.durText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
		x.durText:Hide()
	end,
	style = function(x, def, length, slot)
		ns.try(expireSite(def, "expiring"), styleExpire, x, def, length, slot)
	end,
	-- Its settings: off until Warn in the last is set, then a red bar part and a red countdown
	defaults = { expire = { secs = 0, bar = true, barColor = EXPIRE_RED, text = true } },
	range = { 0, 30, 1 },
}
-- Its time bar made clippable; Time left's page says what its countdown keeps once the engine draws it
-- (T.CANT, a copy: rows share theirs)
function B.expiring.note(key)
	ns.Timer.holdBar(key)
	local cant = ns.Timer.CANT[key] or {}
	local up = {}
	for k, v in pairs(type(cant.uptime) == "table" and cant.uptime or {}) do up[k] = v end
	up.format = "While Expiring warns with Red countdown, the countdown keeps only its font, size, colour and position."
	local out = {}
	for k, v in pairs(cant) do out[k] = v end
	out.uptime = up
	ns.Timer.CANT[key] = out
end

-- The length guard: an aura read at another length than its row's turns Expiring's bar part off until a
-- read gives the row's again (never placed on a guess). dur: a plain read's; true when x.lengthOff changed
local function plainLength(dur) return type(dur) == "number" and not isSecret(dur) and dur > 0 end
function B.expiring.checkLength(x, dur, length)
	if not plainLength(dur) or type(length) ~= "number" then return false end
	local off = math.abs(dur - length) > 0.05
	if off == (x.lengthOff or false) then return false end
	x.lengthOff = off
	return true
end
-- A plain read on you at rest: the first of ids up decides; a failed or secret read, nothing
function B.expiring.readOnPlayer(x, ids, length)
	if not (ns.aurasReadable() and C_UnitAuras) then return false end
	for id in pairs(ids) do
		local ok, a = safe(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if not ok or isSecret(a) then return false end
		local dur = type(a) == "table" and a.duration
		if plainLength(dur) then return B.expiring.checkLength(x, dur, length) end
	end
	return false
end

-- engineExpire (with proc and duration, the aura's full length): Expiring drawn by the engine. Its length
-- is checked by a plain read: on you here, on another unit only with missing's read (and its aura's key)
local function lengthChecked(def)
	return not def.unit or (def.missing and (def.auraKey or def.buffKey) ~= nil) or false
end
local function engineExpires(def)
	return def.engineExpire and def.proc and type(def.duration) == "number" and lengthChecked(def) or false
end
ns.registerPart("engineExpire", {
	kind = "buff", after = "missing",
	has = engineExpires,
	defaults = B.expiring.defaults,
	ranges = function(def) return { expire = { secs = def.expireRange or B.expiring.range } } end,
	preview = {
		states = { { "expiring", "Expiring", 20 } },
		render = function(ic, st, def, kit)
			if st == "expiring" then kit.engineExpire(ic, def.key, def.duration) end
		end,
	},
	runtime = {
		make = function(def) return { extras = B.expiring.extras(def, def) } end,
		button = function(def, _, button) B.expiring.button(def, button) end,
		style = function(def, _, slot) B.expiring.style(def, def, def.duration, slot) end,
	},
})

-- Rows with proc are shown by Blizzard's aura container. The builder reads their fields: filter
-- (else "HELPFUL"), candidates(def) (candidate filters, else the aura's IDs), auraKey or buffKey
-- (the aura's spell, any rank), ownIcon (the row's icon, not the aura's), noTimer (no time left),
-- noGlow and noPop (without its own glow or pop; with neither, no effect host), charges (above),
-- swingMark (below), ownSpell (above), reagent (its count over the button: countOver), castUnder (its cast states also
-- on the icon under the button, for when the aura is down).
-- Page texts, each optional: idleText (the Idle block), procHeader, popTip and glowTip (its active state's
-- block), upLabel and idleLabel (its preview states), castNote and castTips (its cast states').
-- A part's runtime hooks for them (each optional; parts from other files bring their own):
--   make(def)                  at load, after the icon, before the aura slot: frames of its own;
--                              returns { looks, extras }: aura looks set up, refiltered and checked
--                              with the slot, and more slots on its container (makeAuraSlot); it
--                              may set def.borderHost (registerElement's: the frame its border is on)
--   aura(def)                  where the aura is read, else on the player: { unit, slot, parent,
--                              site, glow = { unit, needUnit, parent } }
--   button(def, slot, button)  Blizzard's button was made, after its pop and border
--   style(def, size, slot)     the button restyles, before its border and pop
--   engine                     true: its own module runs the element; this file builds it
-- make, button and style run for every part, in parts order; the others come from the first part
-- that gives one.
local EXPIRE_RANGE = { 0, 120, 5 }
ns.registerKind("buff", {
	parts = { "buff", "breath", "proc" },
	slots = { "own", "warn", "cast", "active", "expire", "uptime" },
	prepare = function(def) def.expireRange = EXPIRE_RANGE end,
})

local NONE = {}

local function makeBuffIcon(def)
	local f = E.newIcon(def.key, { effects = true })
	f.tex:SetTexture(def.icon)
	f.stack()
	return f
end

-- The aura's IDs: any rank of its spell; ownSpell: only those you know (an item's spell of the same name,
-- once cast, is matched by name too)
local function knownID(id) return ns.plain(safe(C_SpellBook.IsSpellKnown, id)) == true end
local function auraIDs(def)
	if not def.ids then
		def.ids = {}
		local key = def.auraKey or def.buffKey
		if key then
			for id in pairs(Spells.ids(key)) do
				if not def.ownSpell or id == def.spellID or knownID(id) then def.ids[id] = true end
			end
		end
	end
	return def.ids
end
B.auraIDs = auraIDs

-- countOver (reagent, with proc): the reagent count over Blizzard's button while the aura is up, on a look
-- its own sensor shows on the effects layer, so an idle icon doesn't fade it and the button's parts don't cover it
local function mirrorCount(def)
	local fs, o = def.frame.count, def.countOver
	if not o then return end
	local shown = fs:IsShown()
	o:SetShown(shown)
	if not shown then return end
	-- R.draw and W.placeScaledText keep what the count shows and where
	local copied = tostring(fs.shown) .. "|" .. tostring(fs.placed)
	if def.countCopied == copied then return end
	local font, size, flags = fs:GetFont()
	if font then o:SetFont(font, size, flags) end
	o:SetText(fs:GetText())
	o:SetTextColor(fs:GetTextColor())
	def.countCopied = font and copied or nil
end
-- Over the button's parts: its Expiring parts and countdown reach 15 levels over the icon's text layer
local COUNT_OVER = 16
ns.registerPart("countOver", {
	kind = "buff", after = "proc",
	has = function(def) return def.reagent and def.proc and not def.unit and true or false end,
	runtime = {
		make = function(def)
			local f, key = def.frame, def.key
			local site = "reagent over " .. key
			local look = W.makeClipLook(f, { key = key, owner = key, invert = true, glowOnly = true, noGlow = true,
				parent = f.effects, sensorParent = f.effects, filter = def.filter,
				ids = function() return auraIDs(def) end,
				sites = { container = site, style = site .. " style", filter = site .. " filter" } })
			def.countLook = look
			def.countOver = look.look:CreateFontString(nil, "OVERLAY", nil, 7)
			def.countOver:SetShadowOffset(1, -1)
			def.countOver:SetShadowColor(0, 0, 0, 1)
			-- Placed on the count itself: the same font and text fill the same box
			def.countOver:SetPoint("CENTER", f.count, "CENTER", 0, 0)
			def.countOver:Hide()
			return { looks = { look } }
		end,
		style = function(def)
			local look = def.countLook
			look:setLevel(def.frame.textFrame:GetFrameLevel() + COUNT_OVER)
			look:style()
		end,
	},
})

-- An aura element's button: its pop, its border (the button draws the border's art), then parts'
local function buildButton(def, slot, button, site)
	if def.fx then def.fx:bind(button, slot.icon) end
	def.edge = def.fx and def.fx:makeEdge(button)
		or ns.Frames.edge(button, button, def.key, { overlay = false })
	-- Dressed now too: its styling may wait for the fight to end
	ns.try(site .. " border " .. def.key, ns.Frames.dress, def.edge, def.key)
	KD.eachHook("buff", def, "button", slot, button)
end

local function styleButton(def, size, slot, site)
	KD.eachHook("buff", def, "style", size, slot)
	if def.edge then ns.try(site .. " border " .. def.key, ns.Frames.dress, def.edge, def.key) end
	if def.fx then ns.try(site .. " pop " .. def.key, def.fx.stylePop, def.fx, size) end
end

-- Its slot and, unless it has neither glow nor pop, its effect host (glow and pop on the button)
local function buildAura(def)
	local key, f = def.key, def.frame
	def.looks, def.extras = {}, {}
	for _, p in ipairs(KD.partsOf("buff", def)) do
		local made = p.runtime and p.runtime.make and p.runtime.make(def) or NONE
		for _, look in ipairs(made.looks or NONE) do table.insert(def.looks, look) end
		for _, x in ipairs(made.extras or NONE) do table.insert(def.extras, x) end
	end
	local where = KD.hook("buff", def, "aura")
	where = where and where(def) or { slot = "proc", parent = f.effects, site = "proc",
		glow = { parent = f.effects } }
	local site = where.site
	local ids = function() return auraIDs(def) end
	local candidates = def.candidates and function() return def.candidates(def) end
	def.aura = W.makeAuraSlot(f, {
		key = key, slot = where.slot, unit = where.unit, filter = def.filter, parent = where.parent,
		ids = ids, candidates = candidates,
		ownIcon = def.ownIcon and function() return def.icon end, noTimer = def.noTimer,
		-- The time bar sits on the charge bar
		barInset = def.charges and function() return chargesLift(def) end,
		extras = #def.extras > 0 and def.extras or nil,
		sites = { container = site .. " container " .. key, style = site .. " style " .. key,
			filter = site .. " filter " .. key },
		onButton = function(slot, button) buildButton(def, slot, button, site) end,
		onStyle = function(slot, size) styleButton(def, size, slot, site) end,
		onError = function(err) ns.noteError(site .. " container " .. key, err) end,
	})
	if def.noGlow and def.noPop then return end
	local g = where.glow
	def.fx = ns.Effects.host(f, key, { aura = {
		slot = def.aura, parent = g.parent, unit = g.unit, needUnit = g.needUnit, filter = def.filter,
		ids = ids, candidates = candidates,
		popOn = function() return not def.noPop and setting(key, "active", "pop") end,
		sites = { container = site .. " glow sensor " .. key, style = site .. " glow style " .. key,
			filter = site .. " glow filter " .. key },
	} })
end

-- A cast state's paint over the button, while the aura is up: sensed as its glow is, faded with the
-- button
local function auraCover(def)
	local where = KD.hook("buff", def, "aura")
	local g = where and where(def).glow or { parent = def.frame.effects }
	return { parent = def.idle or g.parent, sensorParent = g.parent, unit = g.unit, needUnit = g.needUnit,
		filter = def.filter, ids = function() return auraIDs(def) end,
		candidates = def.candidates and function() return def.candidates(def) end, slot = def.aura,
		note = def.castNote, tips = def.castTips, icon = def.castUnder,
		-- Refiltered and pointed with the row's own looks while attached
		attach = function(look) table.insert(def.looks, look) end,
		detach = function(look)
			for i = #def.looks, 1, -1 do if def.looks[i] == look then table.remove(def.looks, i) end end
		end }
end

-- swingMark (with charges): its charges offered to the swing timer as pips
local function swingMarkOf(def)
	if not (def.swingMark and def.charges) then return nil end
	return { max = def.charges, ids = function() return auraIDs(def) end,
		color = function() return ns.THEME.barColor[def.school] or ns.THEME.barColor[ns.THEME.fallback] end }
end

for _, def in ipairs(ROWS) do
	def.spell = Spells.name(def.spellKey)
	def.icon = Spells.icon(def.buffKey or def.spellKey) or def.icon
	def.frame = makeBuffIcon(def)
	def.frame.holdsAuraButton = def.proc
	if def.proc then buildAura(def) end
	E.register(def.key, { frame = def.frame, label = def.spell,
		defaults = def.defaults or {}, learned = function() return def.spellID ~= nil end,
		paint = function(t) t:SetTexture(def.icon) end,
		standInBorder = def.proc, borderHost = def.borderHost,
		ranges = def.ranges, choices = def.charges and { count = { pos = COUNT_POS } } or nil,
		kind = "buff", def = def, spell = def.spellKey, icon = def.icon, school = def.school, blurb = def.blurb,
		experimental = def.experimental, styles = def.styles, swingMark = swingMarkOf(def) })
	if engineExpires(def) then B.expiring.note(def.key) end
	if not KD.hook("buff", def, "engine") then table.insert(BUFFS, def) end
	if def.power or def.range then CS.watchRow(def, def.proc and auraCover(def) or nil) end
end

-- Cooldown rows with auraState = { key, filter, length, active }: the buff its cast puts on you, drawn
-- by Blizzard's aura button over the icon, in combat too; nothing read. key: the aura's spell (default
-- the row's), any rank, by ID; filter: default HELPFUL|PLAYER (yours only); length: its full length in
-- seconds, for its time left and Expiring (nil: until spent, no time left); active = { title, text,
-- tips = { pop, glow } }: a state with its switch (active.on), pop and glow from the same aura. The
-- button draws the buff's picture, border and art frame over the icon on its effects layer, as a proc's
-- does: in full while the buff is up, so the element is awake exactly then. An aura slot
-- (W.makeAuraSlot): made and styled out of combat with auras readable.
local STATES, STATE_LIST = {}, {}
for _, def in ipairs(ns.CLASS.cooldowns or {}) do
	if def.auraState then
		local x = { def = def, spec = def.auraState }
		STATES[def.key] = x
		table.insert(STATE_LIST, x)
	end
end
local statesPreviewing = false
local function stateIDs(x) return Spells.ids(x.spec.key or x.def.spellKey) end
local function stateFilter(x) return x.spec.filter or "HELPFUL|PLAYER" end
local function stateActiveOn(def) return setting(def.key, "active", "on") ~= false end
local function stateOn(x)
	local def = x.def
	return E.inUse(def.key) and (not x.spec.active or stateActiveOn(def))
end
local function stateAlpha(x) x.slot:fade("aura state alpha " .. x.def.key, x.alpha) end
local function stateGlow(x)
	if not x.fx then return end
	local def = x.def
	x.fx:glow(stateOn(x) and setting(def.key, "active", "glow") and not statesPreviewing)
end
-- The engine pops at each assignment, also of an aura already up (login, a loading screen, a new
-- container): its parts stay off for QUIET seconds after one, started out of combat only
local QUIET = 2
-- A flag its style applies, not B.quietAura's direct call: the rig comes with a button, often after the quiet starts
local function quietState(x)
	if not x.fx or not ns.aurasReadable() then return end
	local token = {}
	x.quiet, x.quietToken = true, token
	x.slot:styleNow()
	-- Its end in a fight restyles once combat ends (the restyle waits): a missed pop, never one stuck off
	C_Timer.After(QUIET, function()
		if x.quietToken ~= token then return end
		x.quiet = false
		x.slot:styleNow()
	end)
end
-- Its handed pop quiet for QUIET seconds as its container shows again (its end waits for readable auras)
function B.quietAura(def)
	if not (def.fx and ns.aurasReadable()) then return end
	local token = {}
	def.quietToken = token
	def.fx:setQuiet(true)
	local function done()
		if def.quietToken ~= token then return end
		if ns.deferWhileAurasSecret("aura quiet " .. def.key, done) then return end
		def.fx:setQuiet(false)
	end
	C_Timer.After(QUIET, done)
end
-- Not in use: its holder hidden, so its container stops following auras (out of combat)
local function holderShown(slot, site, on)
	if not slot.holder or ns.deferInCombat(site, function() holderShown(slot, site, on) end) then return end
	slot.holder:SetShown(on())
end
-- Made once, while it's on, out of combat with auras readable
local function makeState(x)
	local slot = x.slot
	if slot.container or slot.err or not stateOn(x) then return end
	if ns.deferWhileAurasSecret(slot.opts.sites.container, function() makeState(x) end) then return end
	-- Its first assignment plays no pop
	quietState(x)
	slot:setup()
	if not slot.container or slot.err then return end
	slot:styleNow()
	stateAlpha(x)
end
-- Its length guard (B.expiring)
local function readStateLength(x)
	local length = x.spec.length
	if length and stateOn(x) and B.expiring.readOnPlayer(x, stateIDs(x), length) then x.slot:styleNow() end
end
for _, x in ipairs(STATE_LIST) do
	local def, key, s = x.def, x.def.key, x.spec
	local f = def.frame
	if s.length then B.expiring.note(key) end
	x.alpha = function() return (stateOn(x) and not statesPreviewing) and 1 or 0 end
	-- dual: its time left placed as beside the cooldown's, as the preview draws it
	x.slot = W.makeAuraSlot(f, {
		key = key, slot = key .. "-state", filter = stateFilter(x), layer = f.effects, dual = true,
		noTimer = not s.length, ids = function() return stateIDs(x) end,
		extras = s.length and B.expiring.extras(x, def) or nil,
		sites = { container = "aura state " .. key, style = "aura state style " .. key,
			filter = "aura state filter " .. key, bar = "aura state bar " .. key },
		onButton = function(slot, button)
			if x.fx then x.fx:bind(button, slot.icon) end
			-- The button draws the border's art; this edge its lines and art frame
			x.edge = x.fx and x.fx:makeEdge(button) or ns.Frames.edge(button, button, key, { overlay = false })
			ns.try("aura state border " .. key, ns.Frames.dress, x.edge, key)
			if s.length then B.expiring.button(x, button) end
		end,
		onStyle = function(slot, size)
			if x.edge then ns.try("aura state border " .. key, ns.Frames.dress, x.edge, key) end
			if x.fx then
				x.fx:setQuiet(x.quiet)
				x.fx:stylePop(size)
			end
			if slot.timer then B.expiring.style(x, def, s.length, slot) end
		end,
		onError = function(err) ns.noteError("aura state " .. key, err) end,
	})
	if s.active then
		x.fx = ns.Effects.host(f, key, { aura = {
			slot = x.slot, parent = f.effects, unit = "player", filter = stateFilter(x),
			ids = function() return stateIDs(x) end,
			popOn = function() return stateOn(x) and setting(key, "active", "pop") end,
			sites = { container = "aura state glow sensor " .. key, style = "aura state glow style " .. key,
				filter = "aura state glow filter " .. key },
		} })
	end
end
ns.registerPart("auraState", {
	kind = "cooldown",
	defaults = function(def)
		local s, d = def.auraState, {}
		if s.length then d.expire = B.expiring.defaults.expire end
		if s.active then d.active = { on = true, pop = true, glow = true } end
		return d
	end,
	ranges = function(def)
		if def.auraState.length then return { expire = { secs = B.expiring.range } } end
	end,
	glow = function(def) return def.auraState.active ~= nil end,
	pop = function(def) return def.auraState.active ~= nil end,
	page = {
		uptime = function(def) return def.auraState.length and "Time left" or nil end,
		active = function(def)
			local a = def.auraState.active
			if not a then return nil end
			return { title = a.title, text = a.text, on = { "Show it", "Off, it's just a cooldown." },
				tips = a.tips or { pop = "The moment it's up.", glow = "While it's up." } }
		end,
	},
	preview = {
		uptime = function(def) return def.auraState.length ~= nil end,
		states = function(def)
			local s = def.auraState
			local list = { { "active", s.active and s.active.title or "Active", 61 } }
			if s.length then table.insert(list, { "expiring", "Expiring", 62 }) end
			return list
		end,
		-- Its switch off, nothing of it: the plain cooldown
		render = function(ic, st, def, kit)
			local s = def.auraState
			if (st ~= "active" and st ~= "expiring") or (s.active and not stateActiveOn(def)) then return end
			if s.active then ic:SetGlowShown(setting(def.key, "active", "glow")) end
			if st == "expiring" then kit.engineExpire(ic, def.key, s.length)
			elseif s.length then kit.frozen(ic.upT, 0.3, s.length) end
		end,
		pop = function(ic, st, def)
			if st == "active" and def.auraState.active and stateActiveOn(def) and setting(def.key, "active", "pop") then
				ic:Pop("ready")
			end
		end,
		-- As the HUD: the buff's button is in full whatever Idle says; its switch off, the cast started its
		-- cooldown
		idles = function(st, def, when)
			if st ~= "active" and st ~= "expiring" then return nil end
			if def.auraState.active and not stateActiveOn(def) then return KD.idleMode(def, when) == "oncd" end
			return false
		end,
	},
	runtime = {
		uptime = function(def) return STATES[def.key].slot.timer end,
		refresh = function(def, _, held)
			stateGlow(STATES[def.key])
			return held
		end,
		debug = function(def)
			local x = STATES[def.key]
			if not stateOn(x) then return "buff off" end
			local words = "buff " .. x.slot:describe()
			words = words .. (x.slot.button and ", button made" or ", no button yet")
			if x.lengthOff then words = words .. ", another length (no Expiring bar)" end
			if x.fx then words = words .. "; " .. x.fx:describe() end
			return words
		end,
	},
})
local function statesLayout()
	for _, x in ipairs(STATE_LIST) do
		local on = stateOn(x)
		-- Back in use: a container shown again plays its pop for an aura already up
		if on and x.wasOn == false and x.slot.container then quietState(x) end
		x.wasOn = on
		makeState(x)
		if on and x.refilterDue then
			x.refilterDue = false
			x.slot:refilter()
			if x.fx then x.fx:refilter(); x.fx:checkIDs() end
		end
		if on then x.slot:styleNow() end
		stateAlpha(x)
		holderShown(x.slot, "aura state shown " .. x.def.key, function() return stateOn(x) end)
		if x.fx then
			if on then
				x.fx:setup()
				B.styleGlow(x)
			end
			if x.fx.up then x.fx.up:setShown(on) end
			stateGlow(x)
		end
	end
end
-- Only those in use: the rest wait until they're back (statesLayout)
local function statesStyle()
	for _, x in ipairs(STATE_LIST) do
		if stateOn(x) then
			x.slot:styleNow()
			if x.fx then B.styleGlow(x) end
		end
	end
end

-- Cooldown rows with buffBar = { buffKey, talentKey, school }: a bar on the icon while that buff of
-- yours is up, drawn by Blizzard's aura button (a proc can't be timed from a cast). It takes Time
-- left's style and the icon's other edge from Time left's bar. Its switch, buffBar, starts off.
-- B.buffBarLearned(def) says whether its talent is learned.
local BUFF_BARS = {}
for _, def in ipairs(ns.CLASS.cooldowns or {}) do
	if def.buffBar then table.insert(BUFF_BARS, { def = def, spec = def.buffBar }) end
end
local barsPreviewing = false
local function buffBarShown(def) return setting(def.key, "buffBar") == true end
local function buffBarOn(x)
	local def = x.def
	return x.learned and E.inUse(def.key) and buffBarShown(def)
end
-- Where it sits on anchor, in Time left's style: the edge its bar doesn't use, inside the picture of
-- icon (the element's icon, the same box: Blizzard's button has no border of its own)
local function placeBuffBar(bar, anchor, key, school, icon)
	local s = ns.Style.get(key, "uptime")
	local pic = ns.StyleArt.pictureInset(icon or anchor)
	local edge = s.barEdge == "top" and "BOTTOM" or "TOP"
	local y = edge == "TOP" and -pic or pic
	bar:ClearAllPoints()
	bar:SetPoint(edge .. "LEFT", anchor, edge .. "LEFT", pic, y)
	bar:SetPoint(edge .. "RIGHT", anchor, edge .. "RIGHT", -pic, y)
	bar:SetHeight(s.barHeight)
	bar:SetStatusBarTexture(ns.Media.barTexture(key))
	local c = ns.THEME.barColor[school] or ns.THEME.barColor[ns.THEME.fallback]
	bar:SetStatusBarColor(c[1], c[2], c[3], 1)
end
local function newBuffBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	return bar
end
local function buffBarAlpha(x) x.slot:fade("buff bar alpha " .. x.def.key, x.alpha) end
-- Made once, while it's on, out of combat with auras readable
local function makeBuffBar(x)
	local slot = x.slot
	if slot.container or slot.err or not buffBarOn(x) then return end
	if ns.deferWhileAurasSecret(slot.opts.sites.container, function() makeBuffBar(x) end) then return end
	slot:setup()
	if not slot.container or slot.err then return end
	slot:styleNow()
	buffBarAlpha(x)
end
for _, x in ipairs(BUFF_BARS) do
	local def, key = x.def, x.def.key
	local f = def.frame
	x.alpha = function() return (buffBarOn(x) and not barsPreviewing) and 1 or 0 end
	-- No picture of its own, only the bar it drives
	x.slot = W.makeAuraSlot(f, {
		key = key, slot = key .. "-buff", layer = f.keepHolder("buffBar"), noIcon = true, noTimer = true,
		ids = function() return Spells.ids(x.spec.buffKey) end,
		sites = { container = "buff bar " .. key, style = "buff bar style " .. key, filter = "buff bar filter " .. key },
		onButton = function(_, button)
			local bar = newBuffBar(button)
			if ns.try("buff bar " .. key, button.SetDurationBar, button, bar, ns.Timer.AURA_BAR) then x.bar = bar
			else bar:Hide() end
		end,
		onStyle = function(slot) if x.bar then placeBuffBar(x.bar, slot.button, key, x.spec.school, f) end end,
		onError = function(err) ns.noteError("buff bar " .. key, err) end,
	})
end
local function buffBarOf(def)
	for _, x in ipairs(BUFF_BARS) do if x.def == def then return x end end
end
function B.buffBarLearned(def)
	local x = buffBarOf(def)
	return x ~= nil and x.learned == true
end
ns.registerPart("buffBar", {
	kind = "cooldown",
	defaults = { buffBar = false, idleKeep = { buffBar = false } },
	idle = { keep = function(def)
		return { "buffBar", Spells.name(def.buffBar.buffKey), "Its bar and glow, while either is on.",
			function() return not B.buffBarLearned(def) end }
	end },
	page = { own = function(def)
		local timeLeft = KD.words("cooldown", def, "uptime") or "Time left"
		return { "toggle", name = "buffBar", title = Spells.name(def.buffBar.buffKey), label = "Time left bar",
			tip = "While it's up, on the icon's other edge from the " .. timeLeft .. " bar.",
			unlearned = function() return not B.buffBarLearned(def) end }
	end },
	preview = {
		states = function(def) return { { "buffBar", Spells.name(def.buffBar.buffKey), 63 } } end,
		keeps = { buffBar = "buffBar" },
		-- Drawn cooling down: it idles where the cooldown does
		idles = function(st, def, when) if st == "buffBar" then return KD.idleMode(def, when) == "oncd" end end,
		-- Drawn on the preview icon by hand: the cooldown under way, a frozen bar while its switch is on
		render = function(ic, st, def, kit)
			local bar = ic.buffBar
			if st == "buffBar" then kit.frozen(ic.cdT, 0.4, def.cd or 60) end
			if st ~= "buffBar" or not buffBarShown(def) then
				if bar then bar:Hide() end
				return
			end
			if not bar then
				bar = newBuffBar(ic.keepOver or ic.textFrame)
				ic.buffBar = bar
			end
			placeBuffBar(bar, ic, def.key, def.buffBar.school)
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0.7)
			bar:Show()
		end,
	},
	runtime = {
		debug = function(def)
			local x = buffBarOf(def)
			local name = Spells.name(def.buffBar.buffKey)
			if not buffBarShown(def) then return name .. " bar off" end
			if not x.learned then return name .. " bar: talent not learned" end
			return name .. " bar: " .. x.slot:describe()
		end,
	},
})

-- An aura element's steps, for whichever module runs it
-- Its slot, looks and host made (out of combat, auras readable: they wait otherwise)
function B.setupAura(def)
	def.aura:setup()
	for _, look in ipairs(def.looks) do look:setup() end
	if def.fx then def.fx:setup() end
end
-- After a spellbook scan: a new rank's ID refilters each look
function B.resolveAura(def)
	local before = def.ids
	def.ids = nil
	if before and def.aura.container then
		for id in pairs(auraIDs(def)) do
			if not before[id] then
				def.aura:refilter()
				for _, look in ipairs(def.looks) do look:refilter() end
				if def.fx then def.fx:refilter() end
				break
			end
		end
	end
	for _, look in ipairs(def.looks) do look:checkIDs() end
	if def.fx then def.fx:checkIDs() end
end
-- Back in use after a scan while off: every filter read again (each skips when unchanged)
function B.refilterAura(def)
	def.ids = nil
	def.aura:refilter()
	for _, look in ipairs(def.looks) do look:refilter(); look:checkIDs() end
	if def.fx then def.fx:refilter(); def.fx:checkIDs() end
end
-- Its glow's level and look (out of combat: the host restyles its sensor)
function B.styleGlow(def)
	if not def.fx or InCombatLockdown() then return end
	def.fx:levelGlow()
	def.fx:style()
end
local styleGlow = B.styleGlow

-- Under water: the breath bar drains (never while water breathing is up)
local breathing = false
local function underWaterWarns(def)
	return def.breath and breathing and setting(def.key, "warn", "on") and not ns.cantAct()
end

-- Its length guard (B.expiring)
local function readAura(def)
	if E.inUse(def.key) and B.expiring.readOnPlayer(def, auraIDs(def), def.duration) then def.aura:style() end
end

local previewing = false

local function refreshBuff(def)
	local f, key = def.frame, def.key
	if def.proc then f.tex:SetAlpha(previewing and 0 or 1) end
	if not E.isEnabled(key) then
		if def.fx then def.fx:glow(false) end
		return
	end
	f.tex:SetTexture(def.icon)
	if not def.spellID then
		f.tex:SetDesaturated(true)
		f:SetRingShown(false)
		f:SetPulsing(false)
		if def.glowing then f:SetGlowShown(false); def.glowing = false end
		f.count:Hide()
		if def.countOver then def.countOver:Hide() end
		E.fade(key, 1)
		return
	end
	f.tex:SetDesaturated(false)
	if def.fx then def.fx:glow(setting(key, "active", "glow") and not previewing) end
	if not (def.reagent or def.breath) then
		E.fade(key, P.getAccount().locked and E.idleAlpha(key) or 1)
		return
	end
	-- Set each look once: re-setting a pulse restarts it
	local held, ring, pulse, glow = false, false, false, false
	if def.reagent then held, ring, pulse = ns.Reagents.refresh(def) end
	if def.countLook then
		mirrorCount(def)
		def.countLook:want(not previewing)
	end
	if underWaterWarns(def) then
		ring, pulse, held = setting(key, "warn", "ring"), setting(key, "warn", "fade"), true
		glow = setting(key, "warn", "glow")
	end
	f:SetRingShown(ring)
	f:SetPulsing(pulse)
	if def.breath and glow ~= (def.glowing or false) then
		def.glowing = glow and true or false
		f:SetGlowShown(def.glowing)
	end
	-- Its button shows it while up, on the effects layer (the wake: no idle fade)
	local busy = not P.getAccount().locked or held
	E.fade(key, busy and 1 or E.idleAlpha(key))
end

local function refreshAll()
	for _, def in ipairs(BUFFS) do refreshBuff(def) end
end

-- Its sound as its aura comes (any rank's ID), while it's learned
local function applyProcSound(def)
	if def.procSound then ns.Sounds.elementAura(def.key, "active", def.spellID and auraIDs(def) or nil, "Added") end
end

function B.resolve()
	ns.Reagents.readPerk()
	local sig = {}
	for _, x in ipairs(STATE_LIST) do
		x.refilterDue = not stateOn(x)
		if not x.refilterDue then
			x.slot:refilter()
			if x.fx then x.fx:refilter(); x.fx:checkIDs() end
		end
	end
	for _, def in ipairs(BUFFS) do
		def.spell = Spells.name(def.spellKey)
		E.ALL[def.key].label = def.spell
		local known = Spells.known(def.spellKey)
		if known ~= def.spellID then def.takesReagent = nil end
		def.spellID = known
		-- A row not in use refilters as it's back (B.applyLayout)
		if def.proc and E.inUse(def.key) then B.resolveAura(def)
		elseif def.proc then def.ids, def.refilterDue = nil, true end
		applyProcSound(def)
		table.insert(sig, tostring(known))
	end
	for _, x in ipairs(BUFF_BARS) do
		x.learned = Spells.known(x.spec.talentKey) ~= nil
		x.refilterDue = not buffBarOn(x)
		if not x.refilterDue then x.slot:refilter() end
		table.insert(sig, tostring(x.learned))
	end
	return table.concat(sig, ",")
end

-- Restyles reach only what's in use: the rest wait until they're back (B.applyLayout)
local function styleInUse()
	statesStyle()
	for _, def in ipairs(BUFFS) do
		if def.proc and E.inUse(def.key) then
			def.aura:style()
			styleGlow(def)
		end
	end
	for _, x in ipairs(BUFF_BARS) do
		if buffBarOn(x) then x.slot:styleNow() end
	end
end
B.applyTimers = styleInUse
B.afterGroups = styleInUse

local syncEvents
function B.applyLayout()
	statesLayout()
	for _, def in ipairs(BUFFS) do
		applyProcSound(def)
		local on = E.inUse(def.key)
		if on and def.wasOn == false and def.aura and def.aura.container then B.quietAura(def) end
		def.wasOn = on
		if def.proc and on then
			B.setupAura(def)
			if def.refilterDue then
				def.refilterDue = false
				B.refilterAura(def)
			end
			def.aura:style()
			styleGlow(def)
		end
	end
	refreshAll()
	for _, x in ipairs(BUFF_BARS) do
		makeBuffBar(x)
		if buffBarOn(x) then
			if x.refilterDue then
				x.refilterDue = false
				x.slot:refilter()
			end
			x.slot:styleNow()
		end
		buffBarAlpha(x)
		holderShown(x.slot, "buff bar shown " .. x.def.key, function() return buffBarOn(x) end)
	end
	syncEvents()
end

local function breathOn()
	for _, def in ipairs(BUFFS) do
		if def.breath and E.inUse(def.key) then return true end
	end
	return false
end
local function readBreath()
	breathing = false
	if not breathOn() then return end
	for i = 1, 3 do
		local ok, name, _, _, scale = safe(GetMirrorTimerInfo, i)
		if ok and not isSecret(name) and name == "BREATH" and type(scale) == "number" and not isSecret(scale)
			and scale < 0 then
			breathing = true
		end
	end
end

-- Low breath: its sound once as the breath bar passes LOW_BREATH seconds left, again after it refills
local LOW_BREATH = 10   -- seconds
local breathLow = false
local breathWatch = ns.ticker(0.25, function()
	local ok, ms = safe(GetMirrorTimerProgress, "BREATH")
	if not ok or isSecret(ms) or type(ms) ~= "number" then return end
	if ms > (LOW_BREATH + 1) * 1000 then breathLow = false end
	if breathLow or ms > LOW_BREATH * 1000 then return end
	breathLow = true
	for _, def in ipairs(BUFFS) do
		if def.breath and def.spellID then ns.Sounds.element(def.key, "breath") end
	end
end)
local function watchBreath() breathWatch:SetShown(breathing and breathOn()) end

function B.refresh()
	for _, x in ipairs(STATE_LIST) do readStateLength(x) end
	readBreath()
	watchBreath()
	for _, def in ipairs(BUFFS) do
		if def.engineExpire then readAura(def) end
	end
	refreshAll()
end

B.tick = refreshAll

-- Each event only while something in use needs it
local auraEvents, breathEvents, zoneEvents   -- set(on), from start
function syncEvents()
	if not auraEvents then return end
	local aura, zone = false, false
	for _, def in ipairs(BUFFS) do
		if E.inUse(def.key) then aura = true end
	end
	for _, x in ipairs(STATE_LIST) do
		if stateOn(x) then
			zone = true
			if x.spec.length then aura = true end
		end
	end
	auraEvents(aura)
	breathEvents(breathOn())
	zoneEvents(zone)
end

function B.start()
	-- A loading screen (login and /reload too) assigns every aura again: no pop for one already up
	local zone = CreateFrame("Frame")
	zoneEvents = ns.eventsWhile(zone, { "PLAYER_ENTERING_WORLD" })
	zone:SetScript("OnEvent", function()
		for _, x in ipairs(STATE_LIST) do if x.slot.container then quietState(x) end end
	end)
	ns.onCanActChange(refreshAll)
	local ev = CreateFrame("Frame")
	auraEvents = ns.eventsWhile(ev, { { "UNIT_AURA", "player" } })
	breathEvents = ns.eventsWhile(ev, { "MIRROR_TIMER_START", "MIRROR_TIMER_STOP" })
	ev:SetScript("OnEvent", function(_, event, timer, _, _, scale)
		if event == "UNIT_AURA" then
			if not ns.aurasReadable() then return end
			-- The Reagent Economy perk may have just come as its aura
			for _, def in ipairs(BUFFS) do
				if def.reagent and E.inUse(def.key) then ns.Reagents.auraChanged() break end
			end
			B.refresh()
			return
		end
		if isSecret(timer) or timer ~= "BREATH" then return end
		breathing = event == "MIRROR_TIMER_START" and type(scale) == "number" and not isSecret(scale) and scale < 0
		watchBreath()
		refreshAll()
	end)
end

function B.onPreview(shown)
	statesPreviewing = shown
	for _, x in ipairs(STATE_LIST) do
		stateAlpha(x)
		stateGlow(x)
	end
	previewing = shown
	refreshAll()
	barsPreviewing = shown
	for _, x in ipairs(BUFF_BARS) do buffBarAlpha(x) end
end

-- /sf debug
function B.debug()
	for _, def in ipairs(BUFFS) do
		local a = def.aura
		local state = a and (a:describe() .. "; " .. (def.fx and def.fx:describe() or "no glow or pop")) or "no container"
		if def.reagent then state = string.format("%s, reagent %s (takes it: %s, Reagent Economy %s)", state,
			describeArg(def.reagentRead), tostring(def.takesReagent), tostring(ns.Reagents.perkKnown())) end
		if def.breath then state = state .. ", breath bar " .. tostring(breathing) end
		if def.lengthOff then state = state .. ", another length (no Expiring bar)" end
		say("%s: spell %s, %s", def.spell, tostring(def.spellID), state)
		if def.countLook then
			say("%s count over the button: %s; %s", def.spell, def.countOver:IsShown()
				and ("shown " .. describeArg(def.countOver:GetText())) or "hidden", def.countLook:describe())
		end
	end
end

MOD.register(B)
