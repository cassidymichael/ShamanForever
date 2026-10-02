-- Totem bar options page
local _, ns = ...


local K, Page = ns.Options.kit, ns.Page
local showWhen, setTip = Page.showWhen, Page.setTip
local LABEL_W = Page.LABEL_W
local pct, times, int, px = Page.pct, Page.times, Page.int, Page.px

local MAX_WARN_ROWS = 32

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
		local r = TB.RANGES[key]
		return p:slider(label, tip, r[1], r[2], r[3], fmt, tget(key), tset(key), shown)
	end

	p:hero("totembar")
	p:callout("Not learned yet. It shows on screen once your character knows a totem.",
		function() return TB.barOn() and not TB.hasTotems() end)
	local full = function() return c().mode == "everything" end
	p:header("Totems", nil, nil, nil, { open = true })
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
	p:text("Keeps Blizzard's totem bar, but replaces Blizzard's active totems display usually shown under the player frame.\n"
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

	p:header("Totem theme")
	local skins = {}
	for _, e in ipairs(TB.skin.LIST) do table.insert(skins, { e.key, e.name }) end
	p:dropdown("Theme", "How the whole bar is drawn.", skins, function() return TB.skin.current().key end,
		tset("skin"), nil, 190)
	local expRow = p:row(22)
	ns.Look.expBadge(expRow, "Totem themes"):SetPoint("LEFT", expRow, "LEFT", LABEL_W, 0)
	p:add(expRow, 22, function() return TB.skin.current().experimental or false end)
	local function theme(key) return function() return TB.skin.current().key == key end end
	p:checkbox("Tray", "A dark tray edged in gold behind the slots.", tget("pixelTray"), tset("pixelTray"),
		theme("pixel"))
	tslider("Edge thickness", "The element-coloured edge round each slot, in pixels.", px, "pixelEdge", theme("pixel"))
	p:dropdown("Plinth", nil, TB.skin.PLINTHS, tget("stonePlinth"), tset("stonePlinth"), theme("stone"), 140)

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
		ns.cropIcon(r.icon)
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
			r.icon:SetTexture(ns.Look.TOTEM_ICON[el])
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
		local r = TB.RANGES.size
		p:slider("Icon size", nil, r[1], r[2], r[3], px, tget("size"), function(v) c().size = v; changed() end)
	end)
	p:dropdown("Call and Recall", "Where they sit on the bar.", { { "ends", "Both ends" }, { "before", "Before the slots" }, { "after", "After the slots" } },
		tget("extras"), tset("extras"),
		showWhen(function() return (c().call or c().recall) and not TB.skin.owns("extras") end, full), 180)
	own("extrasScale")
	own("stoneExtrasScale")
	local extras = TB.RANGES.extrasScale
	p:slider("Call and Recall size", "As a share of the slots' size.", extras[1], extras[2], extras[3],
		pct, function() return TB.eff().extrasScale end,
		function(v) c()[TB.skin.extrasScaleKey()] = v; changed() end,
		showWhen(function() return c().call or c().recall end, full))
	tslider("Scale", "Grows everything on the bar, borders too.", times, "scale")
	tslider("Opacity", nil, pct, "alpha")

	p.gate = full
	p:header("Buttons")
	p:checkbox("Left-click casts your pick", "Left-click a slot to drop that element's picked totem.", tget("cast"), tset("cast"))
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

	-- Only once a second Call is known
	p.gate = function() return full() and ns.TotemSets.count() > 1 end
	p:header("Totem sets")
	local setsRow = p:row(22)
	ns.Look.expBadge(setsRow, "Totem sets"):SetPoint("LEFT", setsRow, "LEFT", LABEL_W, 0)
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
	local function beside() return TB.skin.barPlace() == "out" end
	K.timerSettings(p, "Time left", "totembar", "uptime", changed, nil, nil, beside)
	p:dropdown("Time bar position", "Beside the icon: on the side away from the pickers.",
		{ { "in", "In the icon" }, { "out", "Beside the icon" } }, tget("barPlace"), tset("barPlace"),
		function() return ns.Style.value("totembar", "uptime", "bar") and not TB.skin.owns("barPlace") end, 190)
	K.barRows(p, "totembar", changed)
	K.textBlock(p, "totembar", changed)

	p.gate = full
	K.gcdBlock(p, "totembar")
	p:header("Totem not down")
	local look = p:dropdown("Look", "How a slot looks while its totem isn't down.",
		{ { "pick", "Your pick" }, { "frame", "Element colour" }, { "blank", "Blank" } }, tget("empty"), tset("empty"), nil, 180)
	p:sub(look, function() return c().empty == "pick" end, function()
		p:checkbox("Greyed", "Off: the pick in colour.", tget("idleGrey"), tset("idleGrey"))
		tslider("Opacity", nil, pct, "idleAlpha")
		p:text("With No totem picked, the slot shows its element colour.")
	end)

	p:header("Not your pick")
	p:text("When a different totem is down, your pick shows small beside the slot.")
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
	p:text("A strip along the top of a slot shows whether you're getting your own totem's buff, for totems that buff you. In range shows nothing at 0% opacity, the default.",
		free("range"))
	p:text(function() return TB.skin.rangeText() or "" end, owned("range"))
	local range = p:checkbox("Show", nil, tget("range"), tset("range"))
	p:sub(range, tget("range"), function()
		tslider("Height", "In pixels.", px, "rangeHeight", free("rangeHeight"))
		p:color("In range", "Colour and opacity.", tget("rangeIn"), tset("rangeIn"), free("range"))
		p:color("Out of range", "Colour and opacity.", tget("rangeOut"), tset("rangeOut"), free("range"))
		p:text("A buff lingers a few seconds after you leave its range. Another shaman's totem of the same type can replace your buff, so yours shows as out of range.")
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
			local row = p:slider("", nil, r[1], r[2], r[3], secs,
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
		local add = p:dropdown("Add a totem", "Give a totem its own warning time.", {}, function() return nil end, function() end, nil, 220, function(_, root)
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

	K.glowBlock(p, "totembar", 136098)
	K.popBlock(p, "totembar", 136098, "expired")
	p:header("Border style")
	p:text("Set by the theme.", owned("border"))
	K.borderRows(p, "totembar", changed, nil, free("border"))
	if K.barFramed("totembar") then
		p:header("Frame style")
		K.frameRows(p, "totembar", "groupframe", changed, { spacing = {
			get = tget("spacing"), set = function(v) c().spacing = v; changed() end,
			min = TB.RANGES.spacing[1], max = TB.RANGES.spacing[2],
			size = function() return (TB.look()) end, enabled = free("spacing") } })
	end
	p.gate = nil
end

ns.Options.registerPage("totembar", { title = "Totem bar", icon = "Interface\\Icons\\Spell_Shaman_DropAll_01",
	order = 50, build = build })
