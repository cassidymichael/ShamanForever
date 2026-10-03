-- Preview mode (/sf preview): the HUD in a made-up moment, drawn on stand-ins; nothing is saved and
-- it ends when combat starts. Elements holding Blizzard's protected button stay under their
-- stand-in rather than parked (no change to it in combat).

local _, ns = ...
local say = ns.say
local L = ns.Look
local FR = ns.Frames

local PV = { name = "preview" }
ns.Preview = PV

local on = false
local opts = { mode = "preview", unlearned = true }

-- What each element shows: a loop of steps
-- Preview and Warnings give each element one step; Busy gives every state in turn, BUSY_HOLD
-- seconds each, the n-th element starting on its n-th state so they change out of step
local BUSY_HOLD = 2.5
local IDLE_DELAY = ns.IDLE_DELAY

local function stepsFor(key)
	local def = L.PREVIEW[key]
	local steps, valid = {}, {}
	for _, st in ipairs(def.states) do
		table.insert(steps, { st[1] })
		valid[st[1]] = true
	end
	if opts.mode == "busy" then return steps end
	local typical = valid[def.typical] and def.typical or def.states[1][1]
	return { { opts.mode == "warnings" and valid[def.warning] and def.warning or typical } }
end

-- Bars draw their own (ns.registerBar's hud)
local function eachHud(fn)
	for _, key in ipairs(ns.Bars.list()) do
		local hud = ns.Bars.get(key).hud
		if hud then fn(hud, key) end
	end
end

local idles = L.idles

-- Stand-ins, and parking the real elements
local parked = {}
local veils = {}
local holders = {}
local standIns = {}

local function park(f, gf)
	local v = veils[gf]
	if not v then
		v = CreateFrame("Frame", nil, gf)
		v:Hide()
		veils[gf] = v
	end
	parked[f] = gf
	if f:GetParent() ~= v then f:SetParent(v) end
end
local function unparkAll()
	for f, gf in pairs(parked) do
		if f:GetParent() == veils[gf] then
			f:SetParent(gf)
			if f.stack then f.stack() end
		end
	end
	wipe(parked)
end

local function makeStandIn(key, gf)
	local h = CreateFrame("Frame", nil, gf:GetParent())
	h:SetFrameLevel(gf:GetFrameLevel() + 30)   -- over everything in a group, Blizzard's buttons too
	h:SetAllPoints(ns.ELEMENTS[key].frame)
	local pv = L.PREVIEW[key]
	local ic = L.makePreviewIcon(h, key, pv)
	ic:SetAllPoints(h)
	if ic.upT then ic.upT:restack(2) end
	if pv.standIn then pv.standIn(ic) end
	holders[key], standIns[key] = h, ic
	return ic, h
end

-- Painting
local runs = {}
local barRuns = {}   -- a bar's slots, each looping through its steps like an element

local function setAlpha(f, a)
	f:SetAlpha(a)
	ns.fadeTo(f, a)
end

local function paintElement(key, r, moment)
	local ic, st = standIns[key], r.steps[r.i][1]
	ic.momentToken, ic.idleToken = nil, nil
	local ends = L.paint(ic, key, st, r.at)
	local pv = L.PREVIEW[key]
	if pv.hold then pv.hold(ic) end
	if idles(key, st) and not (r.idleAt and GetTime() < r.idleAt) then setAlpha(ic, L.idleAlpha(key))
	else setAlpha(ic, ic:GetAlpha()) end
	local pop = pv.pop
	if moment and pop then ns.try("preview pop " .. key, pop, ic, st, L.kit) end
	return ends
end

local function nextAt(r, ends)
	if #r.steps == 1 then return ends or math.huge end
	local hold = r.first or BUSY_HOLD
	r.first = nil
	return r.at + hold
end

local function startStep(key, r, moment)
	r.at = GetTime()
	r.idleAt = moment and idles(key, r.steps[r.i][1]) and r.at + IDLE_DELAY or nil
	r.nextAt = nextAt(r, paintElement(key, r, moment))
end

local function startBarStep(r, moment)
	r.at = GetTime()
	local step = r.steps[r.i]
	r.nextAt = nextAt(r, r.hud.step(r.slot, step[1], r.at, step.range, moment))
end

local function place(key, r)
	local f = ns.ELEMENTS[key].frame
	local h = holders[key]
	if not ns.isEnabled(key) then
		r.live = false
		if h then h:Hide() end
		return
	end
	local gf = f:GetParent()
	if parked[f] and gf == veils[parked[f]] then gf = parked[f] end
	if not h then h = select(2, makeStandIn(key, gf)) end
	if not f.aboveProtected then park(f, gf) end
	h:SetScale(gf:GetScale())
	h:SetAlpha(gf:GetAlpha())
	h:Show()
	r.live = true
	-- An element above Blizzard's button keeps its own border under its stand-in unless that border is
	-- on parts that show only with a hostile target or their aura (standInBorder): the stand-in draws theirs
	local own = f.aboveProtected and f:IsVisible() and not ns.ELEMENTS[key].standInBorder
	local ic, st = standIns[key], ns.Style.read(key, "frame")
	ns.Looks.applyBorder(ic, not own and ns.borderFor(key) or nil)
	FR.draw(ic, not own and ns.Style.look("frame", st.look) or nil, ns.boxOf(key), st)
	if f.aboveProtected then FR.veil(key, not own) end
	if r.nextAt then paintElement(key, r, false) else startStep(key, r, false) end
end

-- A group hidden out of combat: its art frame on a frame of its own
local groupHolders = {}
local function placeGroup(g)
	local gf = ns.groupFrames[g.id]
	local h = gf and groupHolders[gf]
	if not (gf and gf.laidOut and gf.frameLayout and not gf:IsVisible())
		or ns.Style.read(g, "groupframe").look == "none" then
		if h then h:Hide() end
		return
	end
	if not h then
		h = CreateFrame("Frame", nil, gf:GetParent())
		groupHolders[gf] = h
	end
	h:SetFrameLevel(gf:GetFrameLevel())
	h:SetAllPoints(gf)
	h:SetScale(gf:GetScale())
	h:SetAlpha(gf:GetAlpha())
	h:Show()
	FR.mountGroup(h, g, gf.frameLayout)
end

local function repaint()
	for _, g in ipairs(ns.getDB().groups) do ns.try("preview group frame", placeGroup, g) end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local r = runs[key]
		if r then ns.try("preview " .. key, place, key, r) end
	end
	for _, r in ipairs(barRuns) do
		if not r.nextAt then ns.try("preview " .. r.key, startBarStep, r, false) end
	end
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local function advance(key, r)
	r.i = r.i % #r.steps + 1
	startStep(key, r, #r.steps > 1)
end
local function advanceBar(r)
	r.i = r.i % #r.steps + 1
	startBarStep(r, #r.steps > 1)
end
ticker:SetScript("OnUpdate", ns.throttled(0.1, function()
	local now = GetTime()
	for key, r in pairs(runs) do
		if r.live and r.nextAt then
			if now >= r.nextAt then ns.try("preview step", advance, key, r)
			elseif r.idleAt and now >= r.idleAt then
				r.idleAt = nil
				ns.fadeTo(standIns[key], L.idleAlpha(key))
			end
		end
	end
	for _, r in ipairs(barRuns) do
		if r.nextAt and now >= r.nextAt then ns.try("preview " .. r.key, advanceBar, r) end
	end
end))

local function restart()
	wipe(runs)
	wipe(barRuns)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if L.PREVIEW[key] then runs[key] = { steps = stepsFor(key), i = 1 } end
	end
	eachHud(function(hud, key)
		for _, slot in ipairs(hud.slots or {}) do
			table.insert(barRuns, { hud = hud, key = key, slot = slot, steps = hud.steps(slot, opts.mode),
				i = 1 })
		end
	end)
	local n = 0
	local function stagger(r)
		n = n + 1
		if #r.steps > 1 then r.i, r.first = (n - 1) % #r.steps + 1, (n * 0.7) % BUSY_HOLD + 0.2 end
	end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if runs[key] then stagger(runs[key]) end
	end
	for _, r in ipairs(barRuns) do stagger(r) end
	ticker:SetShown(on)
	eachHud(function(hud) hud.show(on and opts or nil) end)
end

-- The panel
-- Not named, so the client keeps no position for it: it starts at the top each time
local panel = ns.floatingPanel(nil, 560, 66, { 0.85, 0.71, 0.42, 0.9 })
panel:SetPoint("TOP", UIParent, "TOP", 0, -12)

local function changed()
	restart()
	ns.layoutElements()
	panel.refresh()
end

local function choice(parent, key, items)
	local row = CreateFrame("Frame", nil, parent)
	row.buttons = {}
	local x = 0
	for _, it in ipairs(items) do
		local b = CreateFrame("Button", nil, row, "BackdropTemplate")
		b:SetBackdrop(ns.BACKDROP)
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(it[2])
		local w = math.ceil(b.text:GetStringWidth()) + 20
		b:SetSize(w, 20)
		b:SetPoint("LEFT", row, "LEFT", x, 0)
		x = x + w + 2
		b.value = it[1]
		b:SetScript("OnClick", function(self)
			if opts[key] == self.value then return end
			opts[key] = self.value
			changed()
		end)
		ns.setTip(b, it[2], it[3], "ANCHOR_BOTTOM")
		table.insert(row.buttons, b)
	end
	row:SetSize(x - 2, 20)
	function row.refresh()
		for _, b in ipairs(row.buttons) do L.paintChoice(b, opts[key] == b.value) end
	end
	return row
end

local function check(parent, key, label, tip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.Text:SetFontObject("GameFontHighlightSmall")
	cb.Text:SetText(label)
	cb:SetScript("OnClick", function(self)
		opts[key] = self:GetChecked() and true or false
		changed()
	end)
	ns.setTip(cb, label, tip, "ANCHOR_BOTTOM")
	return cb
end

local function button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local optionsButton

do
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -13)
	title:SetText(ns.NAME .. ": preview")
	local mode = choice(panel, "mode", {
		{ "preview", "Preview", "An ordinary moment in a fight." },
		{ "warnings", "Warnings", "Warnings focused." },
		{ "busy", "Busy", "Everything everywhere all at once." },
	})
	mode:SetPoint("TOPLEFT", 10, -38)
	local unlearned = check(panel, "unlearned", "Show not learned",
		"Also the elements you haven't learned yet, so you can place them now.")
	unlearned:SetPoint("LEFT", mode, "RIGHT", 10, 0)
	local stop = button(panel, "Stop preview", 110, function() PV.close() end)
	stop:SetPoint("TOPRIGHT", -10, -8)
	optionsButton = button(panel, "Show options", 110, function() ns.Options.toggleAside() end)
	optionsButton:SetPoint("RIGHT", stop, "LEFT", -6, 0)
	ns.setTip(optionsButton, "Options", "The options stay shown or hidden the next time.", "ANCHOR_BOTTOM")
	local lock = button(panel, "Unlock positioning", 140, function()
		ns.setLocked(not ns.getAccount().locked)
		panel.refresh()
	end)
	lock:SetPoint("RIGHT", optionsButton, "LEFT", -6, 0)
	ns.setTip(lock, "Positioning", function()
		return "Drag " .. L.movingWords("groups") .. " while the preview shows."
	end, "ANCHOR_BOTTOM")
	function panel.refresh()
		mode.refresh()
		unlearned:SetChecked(opts.unlearned)
		lock:SetText(ns.getAccount().locked and "Unlock positioning" or "Lock positioning")
		PV.optionsShown(ns.Options.isShown())
	end
end

-- On and off
function PV.isOn() return on end
function PV.optionsShown(shown)
	optionsButton:SetText(shown and "Hide options" or "Show options")
end
function PV.showsUnlearned() return on and opts.unlearned end

function PV.open()
	if on then return end
	if not ns.isActive() then say("the preview is for %s only", ns.CLASS.plural) return end
	if InCombatLockdown() then say("the preview can't start in combat") return end
	on = true
	ns.Options.stepAside("preview")
	restart()
	ns.eachModule("onPreview", true)
	ns.applyLayout()
	panel:Show()
	panel.refresh()
	ns.changed()
end

function PV.close(forCombat)
	if not on then return end
	on = false
	ticker:Hide()
	panel:Hide()
	for key, h in pairs(holders) do
		h:Hide()
		standIns[key]:SetPulsing(false)
		FR.veil(key, false)
	end
	for _, h in pairs(groupHolders) do h:Hide() end
	wipe(runs)
	wipe(barRuns)
	unparkAll()
	eachHud(function(hud) hud.show(nil) end)
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		local pv = L.PREVIEW[key]
		if pv and pv.hold then pv.hold(nil) end
	end
	ns.eachModule("onPreview", false)
	ns.applyLayout()
	ns.refreshAll()
	ns.Options.comeBack("preview", forCombat)
	ns.changed()
end

function PV.toggle()
	if on then PV.close() else PV.open() end
end

function PV.afterGroups()
	if not on then return end
	repaint()
	panel.refresh()
end

-- Ends when combat starts, so the layout that restores the real HUD runs at once
function PV.start()
	ns.onCombatStart(function()
		if not on then return end
		PV.close(true)
		say("preview off for combat")
	end)
end

ns.registerModule(PV)
