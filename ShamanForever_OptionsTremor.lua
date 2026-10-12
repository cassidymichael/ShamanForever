-- Tremor options page
local _, ns = ...
local E = ns.Elements

local Page, K = ns.Page, ns.Options.kit
local setTip, panelBackdrop = Page.setTip, Page.panelBackdrop
local elementDisplay, styleBlocks, activeBlock = K.elementDisplay, K.styleBlocks, K.activeBlock
local timerSettings, eopt, eread = K.timerSettings, K.eopt, K.eread

-- Tremor watchlist: a ScrollBox recycles its rows, so hundreds of mobs take a dozen frames.
local MOB_ROW_H, MOB_ROWS, MOB_LIST_W = 22, 9, 640
local function mobList(p)
	local TR = ns.Tremor
	local listH = MOB_ROW_H * MOB_ROWS + 8
	local H = 32 + listH + 32
	local f = p:row(H)
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(240, 20)
	box:SetPoint("TOPLEFT", 8, -5)
	box:SetAutoFocus(false)
	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	box.hint:SetPoint("LEFT", 2, 0)
	box.hint:SetText("Search, or type a name to add")
	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	add:SetSize(70, 22)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	add:SetText("Add")
	setTip(add, "Add", "Puts the name in the box on the list.")
	local addTarget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	addTarget:SetSize(110, 22)
	addTarget:SetPoint("LEFT", add, "RIGHT", 6, 0)
	addTarget:SetText("Add target")
	setTip(addTarget, "Add target", "Puts the mob you have targeted on the list.")
	local ownOnly = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	ownOnly:SetSize(24, 24)
	ownOnly.Text:SetFontObject("GameFontHighlight")
	ownOnly.Text:SetText("Only mobs you added")
	setTip(ownOnly, "Only mobs you added", "Hides the default list's mobs.")

	local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
	panelBackdrop(panel)
	panel:SetPoint("TOPLEFT", 0, -32)
	panel:SetSize(MOB_LIST_W, listH)
	ownOnly:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(ownOnly.Text:GetStringWidth() + 4), 29)
	local sb = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	sb:SetPoint("TOPLEFT", 4, -4)
	sb:SetPoint("BOTTOMRIGHT", -22, 4)
	local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", sb, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 6, 0)
	local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("No matches. Add puts the name on the list.")

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(MOB_ROW_H)
	view:SetElementInitializer("Button", function(row, r)
		if not row.name then
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 1, 1, 0.05)
			row.x = CreateFrame("Button", nil, row)
			row.x:SetSize(20, 20)
			row.x:SetPoint("RIGHT", -2, 0)
			row.x:SetNormalFontObject("GameFontNormal")
			row.x:SetHighlightFontObject("GameFontHighlight")
			row.x:SetText("X")
			row.x:SetScript("OnClick", function(self) TR.remove(self.lower) end)
			setTip(row.x, "Remove", "Takes this mob off the list.")
			row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.name:SetPoint("LEFT", 6, 0)
			row.name:SetPoint("RIGHT", row, "CENTER", 0, 0)
			row.name:SetJustifyH("LEFT")
			row.name:SetWordWrap(false)
			row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			row.info:SetPoint("LEFT", row, "CENTER", 8, 0)
			row.info:SetPoint("RIGHT", row.x, "LEFT", -6, 0)
			row.info:SetJustifyH("LEFT")
			row.info:SetWordWrap(false)
		end
		row.name:SetText(r.name)
		local info = {}
		if r.zone then table.insert(info, r.zone) end
		if r.effects ~= "" then table.insert(info, r.effects) end
		if r.own then table.insert(info, "added") end
		row.info:SetText(table.concat(info, "  ·  "))
		row.x.lower = r.lower
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(sb, bar, view)

	local count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 4, -10)
	local restore = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	restore:SetSize(180, 22)
	restore:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -5)
	restore:SetText("Restore removed defaults")
	setTip(restore, "Restore removed defaults",
		"Puts back the mobs you removed from the default list. Mobs you added stay as they are.")
	restore:SetScript("OnClick", function() TR.restore() end)

	local shown = 0
	local listW
	local function fill()
		panel:SetWidth(math.min(listW or p:width(), MOB_LIST_W))
		local text = box:GetText()
		box.hint:SetShown(text == "" and not box:HasFocus())
		local list = TR.rows(text, ownOnly:GetChecked())
		shown = #list
		sb:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants.RetainScrollPosition)
		empty:SetShown(shown == 0)
		local c = TR.counts()
		local parts = { string.format("%d mobs", c.mobs) }
		if c.added > 0 then table.insert(parts, string.format("%d added", c.added)) end
		if c.removed > 0 then
			table.insert(parts, string.format("%d removed from the defaults", c.removed))
		end
		count:SetText(table.concat(parts, ", "))
		restore:SetEnabled(c.removed > 0)
	end
	local function addTyped()
		TR.add(box:GetText())
		box:SetText("")
	end
	ownOnly:SetScript("OnClick", fill)
	box:SetScript("OnTextChanged", fill)
	box:SetScript("OnEditFocusGained", fill)
	box:SetScript("OnEditFocusLost", fill)
	box:SetScript("OnEnterPressed", function(self)
		if shown == 0 then addTyped() end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	add:SetScript("OnClick", addTyped)
	addTarget:SetScript("OnClick", function() TR.addTarget() end)
	return p:add(f, H, nil, function() listW = p:width(); fill() end)
end

local function linkLine(p, text, tip, onClick)
	local f = p:row(22)
	Page.goLink(f, text, onClick, tip):SetPoint("LEFT", 4, 0)
	return p:add(f, 22)
end

local function buildTremor(p)
	local key = "tremor"
	local function opt(name) return eopt(p, key, name) end
	elementDisplay(p, key)
	K.idleBlock(p, E.ALL[key].def)
	p:header("Warn when")
	p:checkbox("Your target is on the list", nil, opt("tremorTarget"))
	local plates = p:checkbox("A mob on the list is near", "Its nameplate is on screen.", opt("tremorPlates"))
	p:sub(plates, eread(key, "tremorPlates"), function() p:text("Needs enemy nameplates on.") end)
	p:checkbox("You're feared, charmed or asleep", "And for 10 s after, in case it comes again.",
		opt("tremorFeared"))
	p:text("Only your own fear, charm or sleep, not your party's.")
	p:text("None of these while your Tremor Totem is down, or while you're dead, on a flight path or "
		.. "in a vehicle.")
	p:header("Watchlist")
	p:callout("The watchlist doesn't work in dungeons and raids. Only \"You're feared, charmed or asleep\" "
		.. "does, when it's on.")
	p:text("Mobs that cast fear, charm or sleep.")
	mobList(p)
	linkLine(p, "Suggest a mob for the default list", "Opens Feedback, on the About page.",
		function() ns.Options.showFeedback() end)
	activeBlock(p, key, { title = "Warning", tips = { pop = "The moment it starts warning.",
		glow = "While it warns.", sound = "The moment it starts warning." }, extra = function(s)
		local textGet, textSet = s.opt("active", "text")
		local text = p:checkbox("Text", "Shows \"" .. ns.Tremor.WORD .. "\" by the icon.", textGet, textSet)
		p:sub(text, textGet, function()
			K.wordRows(p, key)
		end)
	end })
	K.castBlocks(p, key)
	styleBlocks(p, key, function()
		timerSettings(p, "Time left", key, "uptime", nil,
			"Its time left while it's down. With the default Idle (\"No warning\", 0%) it isn't seen.")
	end)
end

ns.registerKind("tremor", { page = buildTremor })
