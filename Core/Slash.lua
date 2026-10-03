-- Slash command, minimap button, addon drawer

local ADDON, ns = ...
local E, G, P = ns.Elements, ns.Groups, ns.Profiles
local say = ns.say

local SLASH = ns.NAME:upper()
local CMD = ns.CLASS.slash[1]
for i, word in ipairs(ns.CLASS.slash) do _G["SLASH_" .. SLASH .. i] = word end
local function toggleLock()
	local acct = P.getAccount()
	if G.setLocked(not acct.locked) then
		say(acct.locked and "positioning locked" or "positioning unlocked: drag groups to move them, %s lock when done", CMD)
	end
end
local function onLauncherClick(button)
	if button == "RightButton" then toggleLock()
	else ns.Options.toggle() end
end
local function launcherTip(tt)
	tt:AddLine("Click: options", 1, 0.82, 0)
	tt:AddLine(P.getAccount().locked and "Right-click: unlock positioning" or "Right-click: lock positioning", 1, 0.82, 0)
end

local minimapIcon
function ns.applyMinimapButton()
	local acct = P.getAccount()
	local LibStub = _G.LibStub
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	local icon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (ldb and icon and acct) then return end
	if type(acct.minimap) ~= "table" then acct.minimap = {} end
	if not minimapIcon then
		local obj = ldb:NewDataObject(ns.NAME, {
			type = "launcher", text = ns.NAME, icon = "Interface\\AddOns\\" .. ADDON .. "\\Art\\Logo-Icon",
			OnClick = function(_, button) onLauncherClick(button) end,
			OnTooltipShow = function(tt)
				tt:AddLine(ns.NAME)
				launcherTip(tt)
			end,
		})
		icon:Register(ns.NAME, obj, acct.minimap)
		minimapIcon = icon
	end
	if acct.minimap.hide then minimapIcon:Hide(ns.NAME) else minimapIcon:Show(ns.NAME) end
end

-- The TOC's AddonCompartmentFunc names
_G[ns.NAME .. "_OnAddonCompartmentClick"] = function(_, button) onLauncherClick(button) end
_G[ns.NAME .. "_OnAddonCompartmentEnter"] = function(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.NAME)
	launcherTip(GameTooltip)
	GameTooltip:Show()
end
_G[ns.NAME .. "_OnAddonCompartmentLeave"] = function() GameTooltip:Hide() end

SlashCmdList[SLASH] = function(msg)
	local cmd = (msg:match("^(%S*)") or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		ns.Options.toggle()
	elseif cmd == "lock" then
		toggleLock()
	elseif cmd == "unlock" then
		if G.setLocked(false) then say("positioning unlocked: drag groups to move them, %s lock when done", CMD) end
	elseif cmd == "preview" then
		ns.Preview.toggle()
	elseif cmd == "debug" then
		E.debugReport()
	else
		say("%s opens the options. Also: %s lock (lock or unlock positioning), %s preview (the whole HUD in a typical "
			.. "moment), %s debug",
			CMD, CMD, CMD, CMD)
	end
end
