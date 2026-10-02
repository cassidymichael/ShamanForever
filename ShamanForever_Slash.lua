-- Slash command, minimap button, addon drawer

local ADDON, ns = ...
local say = ns.say

local SLASH = ns.NAME:upper()
_G["SLASH_" .. SLASH .. "1"] = "/sf"
_G["SLASH_" .. SLASH .. "2"] = "/shf"
local function toggleLock()
	local acct = ns.getAccount()
	if ns.setLocked(not acct.locked) then
		say(acct.locked and "positioning locked" or "positioning unlocked: drag groups to move them, /sf lock when done")
	end
end
local function onLauncherClick(button)
	if button == "RightButton" then toggleLock()
	else ns.Options.toggle() end
end
local function launcherTip(tt)
	tt:AddLine("Click: options", 1, 0.82, 0)
	tt:AddLine(ns.getAccount().locked and "Right-click: unlock positioning" or "Right-click: lock positioning", 1, 0.82, 0)
end

local minimapIcon
function ns.applyMinimapButton()
	local acct = ns.getAccount()
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

_G.ShamanForever_OnAddonCompartmentClick = function(_, button) onLauncherClick(button) end
_G.ShamanForever_OnAddonCompartmentEnter = function(_, button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.NAME)
	launcherTip(GameTooltip)
	GameTooltip:Show()
end
_G.ShamanForever_OnAddonCompartmentLeave = function() GameTooltip:Hide() end

SlashCmdList[SLASH] = function(msg)
	local cmd = (msg:match("^(%S*)") or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		ns.Options.toggle()
	elseif cmd == "lock" then
		toggleLock()
	elseif cmd == "unlock" then
		if ns.setLocked(false) then say("positioning unlocked: drag groups to move them, /sf lock when done") end
	elseif cmd == "preview" then
		ns.Preview.toggle()
	elseif cmd == "debug" then
		ns.debugReport()
	else
		say("/sf opens the options. Also: /sf lock (lock or unlock positioning), /sf preview (the whole HUD in a typical moment), /sf debug")
	end
end
