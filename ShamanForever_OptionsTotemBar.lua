-- Totem bar options page
local _, ns = ...
local W = ns.Widgets
local Bars = ns.Bars

local K, Page, OA = ns.Options.kit, ns.Page, ns.OptionsArt
local showWhen, setTip = Page.showWhen, Page.setTip
local LABEL_W = Page.LABEL_W
local pct, times, int, px = Page.pct, Page.times, Page.int, Page.px

local MAX_WARN_ROWS = 32

-- Header: the bar is its stage, drawn at real size, shrunk only to fit
local POP_ITEMS = 3
local PREVIEW
PREVIEW = {
	stage = true, heroH = 210, uptime = true,
	states = { { "idle", "Nothing down" }, { "down", "Totems down" }, { "expiring", "Expiring" },
		{ "killed", "Killed early" }, { "range", "Out of range" }, { "offpick", "Different totem down" },
		{ "picking", "Picking" } },
	stateShown = function(st)
		local c = ns.TotemBar.cfg()
		local mode = c.mode
		if mode == "blizzard" then return false end
		if st == "range" then return c.range end
		return mode == "everything" or (st ~= "offpick" and st ~= "picking")
	end,
	fallback = "down",
	pop = function(h, st)
		local o = st == "killed" and h.endIcon and ns.Totems.endOptions(ns.TotemBar.cfg().killed, "killed")
		if o then h.endIcon.killed:play(nil, o) end
	end,
	build = function(h)
		h.area = CreateFrame("Frame", nil, h)
		h.area:SetPoint("TOPLEFT", h, "TOPLEFT", 40, -58)
		h.area:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -40, 12)
		local bar = CreateFrame("Frame", nil, h)
		bar:SetSize(1, 1)
		bar:SetFrameLevel(h:GetFrameLevel() + 5)
		h.barFrame = bar
		h.slots = {}
		for i = 1, 4 do
			local ic = OA.makePreviewIcon(bar, "totembar", PREVIEW)
			ic.upT:restack(2)
			ic.box = CreateFrame("Frame", nil, bar)
			ic.badge = CreateFrame("Frame", nil, bar)
			ic.badge:SetFrameLevel(ic:GetFrameLevel() + 6)
			ic.badge.icon = ic.badge:CreateTexture(nil, "ARTWORK")
			ic.badge.icon:SetAllPoints()
			W.cropIcon(ic.badge.icon)
			ic.rangeF = CreateFrame("Frame", nil, bar)
			ic.rangeF:SetFrameLevel(ic:GetFrameLevel() + 7)
			ic.rangeF.bg = ic.rangeF:CreateTexture(nil, "ARTWORK")
			ic.rangeF.bg:SetAllPoints()
			ns.StyleArt.followMask(ic, ic.rangeF.bg)
			-- As the bar's slot look: TB.paintDown and TB.paintEmpty draw both
			ic.icon = ic.tex
			ic.bg = ic:CreateTexture(nil, "BACKGROUND")
			ic.bg:SetAllPoints()
			ic.killed = ns.Effects.endFlash(bar, ic, "totembar", ic)
			h.slots[i] = ic
		end
		h.extras = {}
		for _, key in ipairs({ "Call", "Recall" }) do
			h.extras[key] = W.makeIcon(bar, 56)
		end
		h.extras.Call.num = W.makeKeyText(h.extras.Call)
		h.extras.Call.num:SetTextColor(1, 1, 1)
		h.tab = ns.TotemBar.makeArrowLook(bar)
		h.pop = CreateFrame("Frame", nil, bar)
		h.pop.bg = h.pop:CreateTexture(nil, "BACKGROUND")
		h.pop.bg:SetAllPoints()
		local fill = ns.TotemBar.POP_FILL
		h.pop.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4])
		h.pop.items = {}
		for i = 1, POP_ITEMS do
			local it = CreateFrame("Frame", nil, h.pop)
			it.tex = it:CreateTexture(nil, "ARTWORK")
			it.tex:SetAllPoints()
			W.cropIcon(it.tex)
			it.x = it:CreateFontString(nil, "OVERLAY", "GameFontDisable")
			it.x:SetPoint("CENTER")
			it.x:SetText("X")
			h.pop.items[i] = it
		end
		h.fitNote = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.fitNote:SetPoint("TOPRIGHT", h.area, "TOPRIGHT", 0, 0)
	end,
	render = function(h, st, kit)
		local TB = ns.TotemBar
		local c = TB.cfg()
		local size, border, extrasBorder = TB.look()
		h.barFrame:SetShown(c.mode ~= "blizzard")
		if c.mode == "blizzard" then h.fitNote:SetText("") return end
		local full = c.mode == "everything"
		local els = {}
		local canList = GetMultiCastTotemSpells ~= nil and TB.hasTotems()
		for _, el in ipairs(c.order) do
			if not c.hidden[el] and (not canList or #ns.Totems.knownTotems(TB.SLOT[el]) > 0) then table.insert(els, el) end
		end
		local places = els
		if TB.skin.fixedSlots() and #els > 0 then places = c.order end
		local placeIdx, liveIdx = {}, {}
		for i, el in ipairs(places) do placeIdx[el] = i end
		for i, el in ipairs(els) do liveIdx[el] = i end
		local row = TB.eff().dir == "row"
		local picking = st == "picking" and #els > 0
		local psz = TB.popButtonSize(size)
		local known = picking and TB.known(els[1]) or {}
		local items = math.min(POP_ITEMS, 1 + #known)
		local popLen = TB.popLength(items, psz)
		local seq, along, line = TB.along(math.max(#places, 1), size)
		local badge = st == "offpick" and c.offPick
			and TB.badgeSize(size) + TB.skin.badgeGap(size) or 0
		local across = line + (picking and (c.arrowSize + 4 + popLen) or 0) + badge
		local w = h:GetWidth()
		if not w or w <= 0 then w = 600 end
		local availW, availH = w - 80 - (h.stateW or 0), h.heroH - 14 - 58 - 12
		local needW, needH = row and along or across, row and across or along
		local real = c.scale
		local fit = math.min(1, availW / (needW * real), availH / (needH * real))
		local scale = real * fit
		local bar = h.barFrame
		bar:SetScale(scale)
		h.fitNote:SetText(fit < 0.999 and string.format("Shown at %d%% to fit", math.floor(fit * 100 + 0.5)) or "")
		local bw, bh = (row and along or across), (row and across or along)
		bar:SetSize(bw, bh)
		bar:ClearAllPoints()
		local dir = TB.eff().pop
		bar:SetPoint("CENTER", h.area, "CENTER", 0, 0)
		local function place(ic, off, cross)
			local x = badge + (cross or 0)
			if row then
				if dir == "down" then ic:SetPoint("TOPLEFT", bar, "TOPLEFT", off, -x)
				else ic:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", off, x) end
			else
				if dir == "left" then ic:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -x, -off)
				else ic:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -off) end
			end
		end
		for _, ic in pairs(h.extras) do ic:Hide() end
		local slotAt = {}
		for _, it in ipairs(seq) do
			if it.extra then
				local ic = h.extras[it.key]
				local o = ns.StyleArt.fit(ic, extrasBorder, it.size)
				ic:ClearAllPoints()
				place(ic, it.offset + o, (line - it.size) / 2 + o)
				local learned = TB.extraLearned(it.key)
				ic.tex:SetTexture(TB.extraTexture(it.key))
				ic.tex:SetDesaturated(not learned)
				ic.tex:SetAlpha(learned and 1 or 0.6)
				if ic.num then
					local set, count = ns.TotemSets.active(), ns.TotemSets.count()
					ns.Media.setFont(ic.num, "totembar", W.keyTextSize(it.size, c.keySize))
					ic.num:ClearAllPoints()
					ic.num:SetPoint("BOTTOMRIGHT", -1, 2)
					ic.num:SetText(set)
					ic.num:SetShown(c.setNumber and count > 1)
				end
				ic:Show()
			else slotAt[it.key] = it.offset end
		end
		local expEl = tContains(els, "fire") and "fire" or els[1]
		h.endIcon = nil
		for i, ic in ipairs(h.slots) do
			local el = els[i]
			ic:SetShown(el ~= nil)
			ic.rangeF:Hide()
			if el then
				ic.box:SetSize(size, size)
				ic.box:ClearAllPoints()
				place(ic.box, slotAt[placeIdx[el]], (line - size) / 2)
				ic.school = el
				local o = ns.StyleArt.fit(ic, border, size)
				ic:ClearAllPoints()
				place(ic, slotAt[placeIdx[el]] + o, (line - size) / 2 + o)
				local pick = TB.pickTexture(el)
				if ns.isSecret(pick) then pick = nil end
				kit.reset(ic, pick or TB.TOTEM_ICON[el])
				TB.paintDown(ic)
				ic.killed:setIcon(pick or TB.TOTEM_ICON[el])
				if st ~= "killed" or el ~= expEl then ic.killed:stop() end
				ic.badge:Hide()
				if st == "range" then
					local f = ic.rangeF
					f:ClearAllPoints()
					local x, y, mw, mh = TB.skin.markRect(f, size, o)
					if x then
						f:SetPoint("TOPLEFT", ic.box, "TOPLEFT", x, y)
						f:SetSize(mw, mh)
						f:SetShown(i == 1 and TB.skin.paintMark(f, mw, mh, ic))
					else
						local k = i == 1 and c.rangeOut or c.rangeIn
						f:SetPoint("TOPLEFT", ic, "TOPLEFT", 0, 0)
						f:SetSize(size - 2 * o, W.linePx(ic, c.rangeHeight))
						TB.skin.paintMark(f)
						f.bg:SetColorTexture(k[1], k[2], k[3], k[4] or 1)
						f:Show()
					end
				end
				if st == "offpick" and i == 1 then
					local other
					for _, id in ipairs(TB.known(el)) do
						local tex = C_Spell.GetSpellTexture(id)
						if tex and not ns.isSecret(tex) and tex ~= pick then other = tex break end
					end
					ic.tex:SetTexture(other or TB.TOTEM_ICON[el])
					if c.offPick and pick then
						ic.badge.icon:SetTexture(pick)
						TB.layoutBadge(ic.badge, ic.box, size, border)
						ic.badge:Show()
					end
				end
				ic.upT.school = el
				local expiring = st == "expiring" and el == expEl and TB.expireOpts(c, TB.pickSpell(el))
				if st == "idle" and not full then
					ic:Hide()
				elseif st == "killed" and el == expEl then
					-- Its totem is gone: the end flash plays over the empty slot as the state is chosen
					h.endIcon = ic
					TB.paintEmpty(ic, c, el, pick)
					if not full then ic:SetAlpha(0) end
				elseif st == "idle" or (picking and i == 1) then
					TB.paintEmpty(ic, c, el, pick)
				else
					local left, life = TB.PREVIEW_LEFT[el][1], TB.PREVIEW_LEFT[el][2]
					if expiring then left = expiring.secs > 0 and math.min(5, expiring.secs) or 5 end
					kit.frozen(ic.upT, 1 - left / life, life)
				end
				ic.upT:setExpire(expiring or nil, pick or TB.TOTEM_ICON[el])
			end
		end
		local boxes, sealed, spare = {}, {}, #els
		for pi, el in ipairs(places) do
			local i = liveIdx[el]
			if i then boxes[pi] = h.slots[i].box
			else
				spare = spare + 1
				local b = h.slots[spare].box
				b:SetSize(size, size)
				b:ClearAllPoints()
				place(b, slotAt[pi], (line - size) / 2)
				boxes[pi], sealed[b] = b, true
			end
		end
		TB.skin.layoutBar(bar, boxes, size, row, sealed)
		for i, ic in ipairs(h.slots) do
			if els[i] then TB.skin.styleTimer(ic.upT, ic, size) end
		end
		h.tab:SetShown(picking and TB.feat("arrows"))
		h.pop:SetShown(picking)
		if picking then
			local first = h.slots[1]
			TB.placeArrow(h.tab, first.box, h.tab.glyph)
			TB.skin.styleArrow(h.tab)
			local p = h.pop
			TB.placePopout(p, first.box, items, psz)
			TB.skin.stylePopout(p, items, psz)
			for i, it in ipairs(p.items) do
				it:SetShown(i <= items)
				TB.placePopButton(it, p, i, psz)
				if i == 1 then it.tex:SetColorTexture(0.1, 0.1, 0.1, 1); it.x:Show()
				elseif known[i - 1] then
					it.tex:SetTexture(C_Spell.GetSpellTexture(known[i - 1]))
					it.x:Hide()
				end
			end
		end
	end,
}

local function build(p)
	local TB = ns.TotemBar
	local function c() return TB.cfg() end
	local changed = K.perFrame(function() TB.applySettings(); ns.Options.refresh() end)
	local function tget(key) return function() return c()[key] end end
	local function own(key, ref)
		ref = ref or {}
		ref.bar, ref.name, ref.after = "totembar", key, changed
		p:owns(ref)
	end
	local function tset(key)
		own(key)
		return function(v) c()[key] = v; changed() end
	end
	-- A slider over the setting's range (TB.RANGES)
	local function tslider(label, tip, fmt, key, shown)
		return K.rangeSlider(p, TB.RANGES[key], label, tip, fmt, tget(key), tset(key), shown)
	end

	p:hero("totembar")
	p:callout("Not learned yet. It shows on screen once your character knows a totem.",
		function() return TB.barOn() and not TB.hasTotems() end)
	local full = function() return c().mode == "everything" end
	p:section("Totem settings")
	p:header("Totem mode", nil, nil, nil, { open = true })
	own("mode", { reset = function() TB.setMode(TB.DEFAULTS.mode) end })
	p:cards("Use", nil, {
		{ "blizzard", "Blizzard's", "Interface\\Icons\\INV_Misc_Gear_01" },
		{ "active", "Active totems", "Interface\\Icons\\Spell_Nature_TimeStop" },
		{ "everything", "Everything", "Interface\\Icons\\Spell_Shaman_DropAll_01", tag = "RECOMMENDED" },
	}, tget("mode"), function(v) TB.setMode(v); changed() end)
	local KEYS = "Keys: Options > Keybindings > " .. ns.NAME .. "."
	local BAR_KEYS = "Keys: Options > Keybindings > " .. ns.NAME .. ", or hover the bar in Quick Keybind Mode."
	p:text(ns.NAME .. "'s totem bar is off. Blizzard's totem bar and active totems display are on.\n"
		.. "The totem key bindings still work. " .. KEYS, function() return c().mode == "blizzard" end)
	p:text("Keeps Blizzard's totem bar, but replaces Blizzard's active totems display usually shown under the player "
		.. "frame.\n"
		.. "Right-click a totem to dismiss it. " .. BAR_KEYS, function() return c().mode == "active" end)
	p:text("Both of Blizzard's totem frames are replaced by " .. ns.NAME .. ".\n"
		.. "Right-click a totem to dismiss it. Alt+click a slot to pick its totem. " .. BAR_KEYS, full)

	p.gate = TB.barOn
	p:header("Display", nil, nil, nil, { open = true })
	local function free(field) return function() return not TB.skin.owns(field) end end
	local function owned(field) return function() return TB.skin.owns(field) end end
	local show = p:dropdown("Show", "When the bar is on screen. It always shows while positioning is unlocked.",
		{ { "always", "Always" }, { "active", "In combat or a totem down" }, { "combat", "In combat" },
			{ "target", "In combat or with an enemy target" } },
		tget("show"), tset("show"), nil, 250)
	p:sub(show, function() return c().show ~= "always" end, function()
		tslider("Stay after combat", K.STAY_TIP, K.staySecs, "fadeAfter")
	end)
	p:dropdown("Tooltips", nil, { { "always", "Always" }, { "ooc", "Out of combat" }, { "never", "Never" } },
		tget("tips"), tset("tips"), nil, 160)
	local keys = p:checkbox("Show keybinding text", "Each button's key, in its corner.", tget("keys"), tset("keys"))
	p:sub(keys, tget("keys"), function()
		tslider("Text size", "At the default icon size. It grows with the icon.", int, "keySize")
		tslider("X offset", "From the top-right corner.", px, "keyX")
		tslider("Y offset", "From the top-right corner.", px, "keyY")
		p:color("Text colour", nil, tget("keyColor"), tset("keyColor"))
	end)

	p:header("Layout")
	local ORDER_H, ORDER_W = 28, 260
	own("order")
	own("hidden")
	p:text("Drag to reorder.")
	local list = p:row(4 * ORDER_H)
	local rows, dragFrom = {}, nil
	local line = Page.dropLine(list)
	local function dropAt()
		return Page.dropPosition(rows, function(r) return r == rows[dragFrom] end)
	end
	local ghost = Page.dragGhost(function()
		local at, others = dropAt()
		line:SetShown(Page.placeDropLine(line, others, at))
	end)
	local function endDrag(drop)
		local from = dragFrom
		local at = from and drop and dropAt()
		dragFrom = nil
		ghost:Hide()
		line:Hide()
		if not from then return end
		if at then
			local o = c().order
			local el = table.remove(o, from)
			table.insert(o, at, el)
			changed()
		end
		ns.Options.refresh()
	end
	-- Leaving the page or closing the window mid-drag drops nothing.
	list:SetScript("OnHide", function() endDrag(false) end)
	for i = 1, 4 do
		local r = CreateFrame("Button", nil, list)
		r:SetSize(ORDER_W, ORDER_H - 2)
		r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ORDER_H)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.06)
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.12)
		local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		cb:SetSize(26, 26)
		cb:SetPoint("LEFT", 0, 0)
		cb:SetScript("OnClick", function(self)
			c().hidden[r.el] = not self:GetChecked() or nil
			changed()
		end)
		setTip(cb, "Slot", "Show this element's slot.")
		r.cb = cb
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(20, 20)
		r.icon:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		W.cropIcon(r.icon)
		r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
		r:RegisterForDrag("LeftButton")
		r:SetScript("OnDragStart", function(self)
			dragFrom = i
			self:SetAlpha(0.35)
			ghost.icon:SetTexture(self.icon:GetTexture())
			ghost.text:SetText(self.text:GetText())
			ghost:Show()
		end)
		r:SetScript("OnDragStop", function() endDrag(true) end)
		setTip(r, "Order", "Drag to change where the element sits on the bar.")
		rows[i] = r
	end
	p:add(list, 4 * ORDER_H, nil, function()
		for i, r in ipairs(rows) do
			local el = c().order[i]
			r.el = el
			r.icon:SetTexture(TB.TOTEM_ICON[el])
			r.text:SetText(TB.NAME[el])
			r.cb:SetChecked(not c().hidden[el])
			r:SetAlpha(1)
		end
	end)
	local function setDir(v)
		c().dir = v
		c().pop = v == "row" and "up" or "right"
	end
	own("dir", { reset = function() setDir(TB.DEFAULTS.dir) end })
	p:dropdown("Direction", nil, { { "row", "Row" }, { "column", "Column" } }, tget("dir"),
		function(v) setDir(v); changed() end, free("dir"), 140)
	p:dropdown("Pickers open", "Which way the totem picker opens from a slot.", function()
		if TB.eff().dir == "row" then return { { "up", "Up" }, { "down", "Down" } } end
		return { { "right", "Right" }, { "left", "Left" } }
	end, function() return TB.eff().pop end, tset("pop"),
		function() return full() and not TB.skin.owns("pop") end, 140)
	tslider("Spacing", "Gap between the slots. Below 0 they overlap.", px, "spacing", free("spacing"))
	p:text(function()
		local names = {}
		for _, it in ipairs({ { "dir", "Direction" }, { "pop", "Pickers open" }, { "spacing", "Spacing" },
				{ "extras", "Call and Recall" } }) do
			if TB.skin.owns(it[1]) then table.insert(names, it[2]) end
		end
		return table.concat(names, ", ") .. ": set by the theme."
	end, function()
		return TB.skin.owns("dir") or TB.skin.owns("pop") or TB.skin.owns("spacing") or TB.skin.owns("extras")
	end)
	own("sizeFollow", { reset = function() TB.setSizeFollow(TB.DEFAULTS.sizeFollow) end })
	local sizeFollow = K.globalRow(p, "Icon size same as Global", "Use the global icon size.",
		tget("sizeFollow"), function(v) TB.setSizeFollow(v); changed() end, "size")
	own("size", { default = tget("size"), reset = function() c().size = nil end })
	p:sub(sizeFollow, function() return not c().sizeFollow end, function()
		K.rangeSlider(p, TB.RANGES.size, "Icon size", nil, px, tget("size"), function(v) c().size = v; changed() end)
	end)
	p:dropdown("Call and Recall", "Where they sit on the bar.",
		{ { "ends", "Both ends" }, { "before", "Before the slots" }, { "after", "After the slots" } },
		tget("extras"), tset("extras"),
		showWhen(function() return (c().call or c().recall) and not TB.skin.owns("extras") end, full), 180)
	own("extrasScale")
	own("stoneExtrasScale")
	K.rangeSlider(p, TB.RANGES.extrasScale, "Call and Recall size", "As a share of the slots' size.",
		pct, function() return TB.eff().extrasScale end,
		function(v) c()[TB.skin.extrasScaleKey()] = v; changed() end,
		showWhen(function() return c().call or c().recall end, full))
	tslider("Call and Recall gap", "From the slots. Below 0 they overlap.", px, "extrasGap",
		showWhen(function() return (c().call or c().recall) and not TB.skin.owns("spacing") end, full))
	tslider("Gap between them", "Between Call and Recall when both sit on one side.", px, "extrasSpacing",
		showWhen(function()
			local before, after = TB.extraSides()
			return (#before > 1 or #after > 1) and not TB.skin.owns("spacing")
		end, full))
	tslider("Scale", "Grows everything on the bar, borders too.", times, "scale")
	tslider("Opacity", nil, pct, "alpha")

	p.gate = full
	p:header("Buttons")
	p:checkbox("Left-click casts your pick", "Left-click a slot to drop that element's picked totem.", tget("cast"),
		tset("cast"))
	local arrows = p:checkbox("Arrow opens a totem picker", "A tab on each slot opens its totems. Works in combat.",
		tget("arrows"), tset("arrows"))
	p:sub(arrows, tget("arrows"), function()
		tslider("Arrow size", "How deep the tab is.", px, "arrowSize")
	end)
	p:checkbox("Open pickers on hover", "Hovering a slot opens its totems. Works in combat.",
		tget("pickHover"), tset("pickHover"))
	p:checkbox(ns.Spells.name("call"), nil, tget("call"), tset("call"))
	p:checkbox(ns.Spells.name("recall"), nil, tget("recall"), tset("recall"))
	p:text(function()
		return string.format("%s shows once you know it. Right-click %s to dismiss all totems, even before you learn it.",
			ns.Spells.name("call"), ns.Spells.name("recall"))
	end)

	p:header("Totem not down")
	local look = p:dropdown("Show as", "How a slot shows while its totem isn't down.",
		{ { "pick", "Your pick" }, { "frame", "Element colour" }, { "blank", "Blank" } }, tget("empty"), tset("empty"), nil,
		180)
	p:sub(look, function() return c().empty == "pick" end, function()
		p:checkbox("Greyed", "Off: the pick in colour.", tget("idleGrey"), tset("idleGrey"))
		tslider("Opacity", nil, pct, "idleAlpha")
		p:text("With No totem picked, the slot shows its element colour.")
	end)

	p:header("Different totem down")
	p:text("When a totem other than that slot's default is down.")
	local offPick = p:checkbox("Show your pick", "On the side away from the picker.",
		tget("offPick"), tset("offPick"))
	p:sub(offPick, tget("offPick"), function()
		tslider("Size", nil, pct, "badgeSize")
		tslider("Opacity", nil, pct, "badgeAlpha")
		tslider("Colour", "0% is grey, 100% full colour.", pct, "badgeSat")
		tslider("X offset", "From its place beside the slot.", px, "badgeX")
		tslider("Y offset", "From its place beside the slot.", px, "badgeY")
	end)

	p.gate = TB.barOn
	p:header("Out of range")
	p:text("A strip along the top of a slot shows whether you're getting your own totem's buff, for totems that buff "
		.. "you. In range shows nothing at 0% opacity, the default.",
		free("range"))
	p:text(function() return TB.skin.rangeText() or "" end, owned("range"))
	local range = p:checkbox("Show", nil, tget("range"), tset("range"))
	p:sub(range, tget("range"), function()
		tslider("Height", "In pixels.", px, "rangeHeight", free("rangeHeight"))
		p:color("In range", "Colour and opacity.", tget("rangeIn"), tset("rangeIn"), free("range"))
		p:color("Out of range", "Colour and opacity.", tget("rangeOut"), tset("rangeOut"), free("range"))
		p:text("A buff lingers a few seconds after you leave its range. Another shaman's totem of the same type can "
			.. "replace your buff, so yours shows as out of range.")
	end)

	-- Defaults use spell names that may not have loaded yet: TB.overChanged accepts either.
	local function over() return c().expire.over end
	local function overRows()
		p:owns({ bar = "totembar", name = "expire", field = "over", after = changed,
			changed = function() return TB.overChanged(over()) end,
			reset = function() c().expire.over = TB.overDefaults() end })
		p:text("Totems with their own warning time, instead of the default:", function() return next(over()) ~= nil end)
		-- Totems are kept by the client's name for them (any rank).
		local function overName(i)
			local names = {}
			for name in pairs(over()) do table.insert(names, name) end
			table.sort(names)
			return names[i]
		end
		local secs = function(v) return v == 0 and "Off" or string.format("%d s", v) end
		local r = TB.RANGES.expire.secs
		for i = 1, MAX_WARN_ROWS do
			local row = K.rangeSlider(p, r, "", nil, secs,
				function() local name = overName(i); return name and over()[name] or c().expire.secs end,
				function(v) local name = overName(i); if name then over()[name] = v; changed() end end,
				function() return overName(i) ~= nil end)
			local item = p.items[#p.items]
			local refresh = item.refresh
			item.refresh = function()
				row.label:SetText(((overName(i) or ""):gsub(" Totem$", "")))
				refresh()
			end
			local x = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			x:SetSize(24, 22)
			x:SetPoint("RIGHT", row, "RIGHT", -2, 0)
			x:SetText("X")
			x:SetScript("OnClick", function()
				local name = overName(i)
				if name then over()[name] = nil; changed() end
			end)
			setTip(x, "Remove", "Use the time above for this totem.")
		end
		local add = p:dropdown("Add a totem", "Give a totem its own warning time.", {}, function() return nil end,
			function() end, nil, 220, function(_, root)
			local names, seen = {}, {}
			for slot = 1, 4 do
				for _, id in ipairs(ns.Totems.knownTotems(slot)) do
					local name = ns.Spells.nameOf(id)
					if name and not seen[name] and over()[name] == nil then
						seen[name] = true
						table.insert(names, name)
					end
				end
			end
			table.sort(names)
			for _, name in ipairs(names) do
				root:CreateButton(name, function() over()[name] = c().expire.secs; changed() end)
			end
			if #names == 0 then root:CreateTitle("Every totem you know has its own time") end
		end)
		pcall(add.dropdown.SetDefaultText, add.dropdown, "Choose a totem")
	end
	-- A totem with its own time can warn while the default is off
	local function warns()
		if c().expire.secs > 0 then return true end
		for _, v in pairs(over()) do if v > 0 then return true end end
		return false
	end
	K.expiringBlock(p, "totembar", { after = changed, noun = "slot", afterSecs = overRows, warns = warns,
		tips = { endPop = "The totem pops and fades the moment it runs out.",
			endSound = "When a totem runs out or is killed. Not when you dismiss it." } })
	K.killedBlock(p, "totembar", { after = changed, noun = "slot", flash = { "Flash when a totem dies early",
		"The dead totem flashes red over its slot. Not when you dismiss it or it runs out." } })

	-- Only once a second Call is known
	p.gate = function() return full() and ns.TotemSets.count() > 1 end
	p:header("Totem sets")
	local setsRow = p:row(22)
	ns.OptionsArt.expBadge(setsRow, "Totem sets"):SetPoint("LEFT", setsRow, "LEFT", LABEL_W, 0)
	p:add(setsRow, 22)
	p:text("Each Call drops its own set of four totems. The bar uses one set at a time: its slots, "
		.. "picks, Call button and keys.")
	p:dropdown("Switch sets", "How the Call button changes the set.",
		{ { "popout", "Picker on the Call button" }, { "cycle", "Right-click the Call button" } },
		tget("setSwitch"), tset("setSwitch"), nil, 240)
	p:checkbox("Show set number", "On the Call button.", tget("setNumber"), tset("setNumber"))
	p:text(ns.TotemSets.switchInCombat() and "Key: Next totem set."
		or "Sets switch out of combat only. Key: Next totem set.")

	p.gate = TB.barOn
	p:section("Styles")
	p:header("Totem theme")
	local skins = {}
	for _, e in ipairs(TB.skin.LIST) do table.insert(skins, { e.key, e.name }) end
	p:dropdown("Theme", "How the whole bar is drawn.", skins, function() return TB.skin.current().key end,
		tset("skin"), nil, 190)
	local expRow = p:row(22)
	ns.OptionsArt.expBadge(expRow, "Totem themes"):SetPoint("LEFT", expRow, "LEFT", LABEL_W, 0)
	p:add(expRow, 22, function() return TB.skin.current().experimental or false end)
	local function theme(key) return function() return TB.skin.current().key == key end end
	p:checkbox("Tray", "A dark tray edged in gold behind the slots.", tget("pixelTray"), tset("pixelTray"),
		theme("pixel"))
	tslider("Edge thickness", "The element-coloured edge round each slot, in pixels.", px, "pixelEdge", theme("pixel"))
	p:dropdown("Plinth", nil, TB.skin.PLINTHS, tget("stonePlinth"), tset("stonePlinth"), theme("stone"), 140)

	local function beside() return TB.skin.barPlace() == "out" end
	K.timerSettings(p, "Time left", "totembar", "uptime", changed, nil, nil, beside)
	p:dropdown("Time bar position", "Beside the icon: on the side away from the pickers.",
		{ { "in", "In the icon" }, { "out", "Beside the icon" } }, tget("barPlace"), tset("barPlace"),
		function() return ns.Style.value("totembar", "uptime", "bar") and not TB.skin.owns("barPlace") end, 190)
	K.barRows(p, "totembar", changed)
	K.textBlock(p, "totembar", changed)

	p.gate = full
	K.gcdBlock(p, "totembar")
	p.gate = TB.barOn
	K.glowBlock(p, "totembar")
	K.popBlock(p, "totembar", "expired")
	p:header("Border style")
	p:text("Set by the theme.", owned("border"))
	K.borderRows(p, "totembar", changed, nil, free("border"))
	if K.barFramed("totembar") then
		p:header("Art frame style")
		K.frameRows(p, "totembar", "groupframe", changed, { spacing = {
			get = tget("spacing"), set = function(v) c().spacing = v; changed() end,
			min = TB.RANGES.spacing[1], max = TB.RANGES.spacing[2],
			size = function() return (TB.look()) end, enabled = free("spacing") } })
	end
	p.gate = nil
end

Bars.register("totembar", { icon = "Interface\\Icons\\Spell_Shaman_DropAll_01",
	school = ns.THEME.fallback,
	blurb = "Your totems, their timers, and a pick for each element.",
	tags = function()
		local TB = ns.TotemBar
		local c = TB.cfg()
		local shows = { always = "Always", active = "In combat or a totem down", combat = "In combat" }
		if c.mode == "blizzard" then return TB.modeName() end
		return string.format("%s  ·  %s%s", TB.modeName(), shows[c.show] or "",
			TB.hasTotems() and "" or "  ·  Not learned")
	end,
	preview = PREVIEW, page = { order = 50, build = build },
	ownSize = function() return not ns.TotemBar.cfg().sizeFollow end,
	experiments = { { "Totem sets", "Totem sets, once you know a second Call" } },
	tiles = { icon = ns.TotemBar.TOTEM_ICON.earth, schools = ns.TotemBar.ELEMENTS,
		border = function() return select(2, ns.TotemBar.look()) end } })
