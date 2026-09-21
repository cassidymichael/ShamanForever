# ShamanForever

A small HUD for shamans on World of Warcraft: Forever.

![ShamanForever HUD: Lightning Shield with charge bar next to the shock icon](screenshot.png)

> This quick addon was created by Claude, with minimal oversight by a human. Feedback and requests are welcome.

- **Lightning Shield**: icon, charge number and a segmented charge bar, exact in combat. The buff is drawn by Blizzard's secure aura container, so it is not subject to the addon aura restrictions. When the shield is down the icon greys out and, once combat ends, gets a red ring.
- **Shock**: the shock of your choice (Earth, Flame or Frost, highest rank known) with its cooldown and countdown, red when your target is out of range, blue with a blue ring when you cannot afford it.

Options: Escape > Options > AddOns > Shaman Forever, or `/sf` (alias `/shf`). Sections for display (lock, opacity, scale), layout (icon size, spacing, row or column, growth direction, icon order), Lightning Shield look and Shock looks. Slash forms: `/sf lock|unlock`, `/sf alpha 0.65`, `/sf scale 1.2`, `/sf shock earth|flame|frost`, `/sf reset`, `/sf debug`.

Requires interface 16001 (WoW: Forever). Settings live in `ShamanForeverDB`.

## Showing auras in combat: Blizzard's CustomAuraContainer

Addon code cannot read player auras in combat on this client (every read throws "Auras cannot be accessed when secret"). The sanctioned route is the `AuraContainer` intrinsic with `CustomAuraContainerTemplate` from `Blizzard_AuraContainer`. Its Lua runs untainted, so it reads the aura and drives widgets the addon supplies. Verified working on build 69913 in this addon:

```lua
local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
c:SetFrameStrata("HIGH")          -- intrinsic does not sit where you expect; set it explicitly
c:SetUnit("player")
c:AddAuraSlot("key", "HELPFUL", {
  candidateFilters = { includeSpellIDs = { [324] = true, [325] = true } },  -- map, not list
  initializeFrame = function(button)
    button:SetSize(56, 56)
    button:SetPoint("TOPLEFT")      -- slot frames are NOT laid out by the container; anchor them yourself
    local tex = button:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(); button:SetIcon(tex)
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate"); cd:SetAllPoints(); button:SetDurationCooldown(cd)
    local fs = button:CreateFontString(nil, "OVERLAY"); fs:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE"); fs:SetPoint("CENTER")
    button:SetApplicationCount(fs)  -- font MUST be set first: Blizzard writes text immediately
    local bar = CreateFrame("StatusBar", nil, button); bar:SetPoint("BOTTOMLEFT"); bar:SetPoint("BOTTOMRIGHT"); bar:SetHeight(7)
    button:SetApplicationBar(bar, { minApplications = 0, maxApplications = 3 })  -- min 0 or one charge shows empty
  end,
})
```

Gotchas: registered parts must be descendants of the button; script handlers (OnShow/OnHide etc.) on anything under the button never run, so you cannot learn when the aura disappears in combat (keep an always-visible underlay for the empty state); the count text only prints for two or more applications (no formatter constructor found); the button and its parts are off limits to addon code in combat (change alpha/fonts out of combat); everything readable about the button is secret, even out of combat.
