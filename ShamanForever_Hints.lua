-- One-time hints in the options window: a short line by the thing it's about, the first time it
-- matters, closed with its X and never shown again on the account (Profiles' "Show tips again"
-- brings them back). One at a time. None while the game's own tips are turned off (hideHelptips).
-- Our own small frame, not Blizzard's HelpTip, which is shared with Blizzard's frames.

local _, ns = ...

local H = {}
ns.Hints = H

local W = 230   -- the hint's width

-- id -> true once shown (ShamanForeverDB, the account's).
local function seen()
	local a = ns.getAccount()
	if type(a.hints) ~= "table" then a.hints = {} end
	return a.hints
end

local function tipsOff()
	local ok, v = pcall(C_CVar.GetCVarBool, "hideHelptips")
	return ok and v == true
end

local frame
local hooked = {}   -- anchors whose hiding hides the hint
local function build()
	frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetWidth(W)
	ns.Page.panelBackdrop(frame, 0.88, 0.66, 0.29)
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.text:SetPoint("TOPLEFT", 10, -10)
	frame.text:SetWidth(W - 36)
	frame.text:SetJustifyH("LEFT")
	frame.text:SetSpacing(2)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() frame:Hide() end)
	frame:Hide()
end

-- Shows hint id by anchor (to its right), unless it was seen, another hint is up, the anchor isn't
-- on screen or tips are off. It counts as seen once shown.
function H.show(id, anchor, text)
	if seen()[id] or tipsOff() or not (anchor and anchor:IsVisible()) then return false end
	if frame and frame:IsShown() then return false end
	if not frame then build() end
	seen()[id] = true
	frame.text:SetText(text)
	frame:SetHeight(frame.text:GetStringHeight() + 20)
	frame:ClearAllPoints()
	frame:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	if not hooked[anchor] then
		hooked[anchor] = true
		anchor:HookScript("OnHide", function() if frame.anchor == anchor then frame:Hide() end end)
	end
	frame.anchor = anchor
	frame:Show()
	return true
end

-- Every hint can show again.
function H.reset()
	wipe(seen())
	if frame then frame:Hide() end
	ns.say("tips will show again")
end

-- A nav button that is on screen: shown, and not scrolled out of the element list.
local function onScreen(b)
	if not (b and b:IsVisible()) then return false end
	local list = b:GetParent() and b:GetParent():GetParent()
	if list and list.IsObjectType and list:IsObjectType("ScrollFrame") then
		local top, bottom = list:GetTop(), list:GetBottom()
		if not (top and bottom and b:GetTop() and b:GetBottom()) then return false end
		return b:GetTop() <= top + 1 and b:GetBottom() >= bottom - 1
	end
	return true
end

-- The options window showed a page: the hints that apply now.
function H.check()
	local OP = ns.Options
	-- The first time: where each element's settings are.
	if H.show("elements", OP.navButton("elements"), "Each element has its own page, in the list below.") then return end
	-- The first time an element shows greyed in that list.
	if seen().notlearned then return end
	for _, key in ipairs(ns.ELEMENT_KEYS) do
		if not ns.isLearned(key) then
			local b = OP.navButton(key)
			if onScreen(b) then
				H.show("notlearned", b, "Greyed: not learned yet. It shows on screen once you learn the spell.")
				return
			end
		end
	end
end
